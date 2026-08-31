#!/usr/bin/env bash
#
# triage-lint.sh — check (and optionally repair) the mechanical invariants of a
# triaged GitHub issue board. Judgment stays with the triager; this enforces
# only what can be computed.
#
#   E1  every open issue carries exactly one state label
#   E2  every open issue carries exactly one category label
#   E3  the "blocked" label is present iff the issue has >=1 OPEN blocker
#   E4  every blocker declared in body text ("Depends on #3") also exists as a
#       GitHub native dependency, so the UI and the API agree
#   E5  the dependency graph is acyclic
#
# Blockers are read from the same two places dispatch-issues.sh reads them:
# GitHub's native issue dependencies, and a body line such as
# "Depends on #3, #4" / "Blocked by: #3".
#
# Exits non-zero when violations remain, so it can gate CI. --fix repairs E3
# and E4 (both are mechanically determined); E1, E2 and E5 need a human or an
# agent to decide, and are only ever reported.

set -euo pipefail

SCRIPT_NAME=${0##*/}

# ---------------------------------------------------------------- defaults --

BLOCKED_LABEL="blocked"
STATE_LABELS="needs-triage,needs-info,ready-for-agent,ready-for-human"
CATEGORY_LABELS="bug,enhancement"
REPO_OPT=""
FIX=0
LIMIT=500
NATIVE_DEPS=1
DEP_WORDS="depends on|blocked by|requires|needs"

usage() {
  cat <<HELPTEXT
$SCRIPT_NAME — lint the mechanical invariants of a triaged issue board

USAGE
  $SCRIPT_NAME [options]

Checks by default and changes nothing. Exits 1 if any violation remains.

OPTIONS
  -r, --repo OWNER/NAME  which repository (default: inferred from the checkout)
  -f, --fix              repair what is mechanically repairable (E3, E4)
  -L, --blocked-label N  label meaning "has an open blocker" (default: $BLOCKED_LABEL)
      --state-labels A,B comma-separated state labels
                         (default: $STATE_LABELS)
      --category-labels A,B
                         comma-separated category labels (default: $CATEGORY_LABELS)
      --no-native-deps   ignore GitHub native dependencies, read bodies only
      --limit N          how many open issues to scan (default: $LIMIT)
  -h, --help             this text

EXIT
  0  no violations
  1  violations remain (after --fix, if given)
  2  usage or environment error
HELPTEXT
}

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)           REPO_OPT=$2; shift 2 ;;
    -f|--fix)            FIX=1; shift ;;
    -L|--blocked-label)  BLOCKED_LABEL=$2; shift 2 ;;
    --state-labels)      STATE_LABELS=$2; shift 2 ;;
    --category-labels)   CATEGORY_LABELS=$2; shift 2 ;;
    --no-native-deps)    NATIVE_DEPS=0; shift ;;
    --limit)             LIMIT=$2; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "$SCRIPT_NAME: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "$SCRIPT_NAME: gh is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "$SCRIPT_NAME: jq is required" >&2; exit 2; }

REPO=$REPO_OPT
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -n "$REPO" ] || { echo "$SCRIPT_NAME: could not determine the repository" >&2; exit 2; }

gh_repo() { gh api "repos/$REPO/$1" "${@:2}"; }

# ------------------------------------------------------------------- state --

declare -A OPEN          # number -> 1 when open
declare -A LABELS        # number -> ,label,label,
declare -A NATIVE_ALL    # number -> native blocker numbers, any state
declare -A NATIVE_OPEN   # number -> native blocker numbers, open only
declare -A TEXT_OPEN     # number -> body-declared blocker numbers, open only
declare -A DEPS          # number -> union of open blockers (for cycle check)
declare -A STATE_CACHE
NUMBERS=()
VIOLATIONS=()

issue_state() {
  local n=$1
  if [ -z "${STATE_CACHE[$n]+x}" ]; then
    STATE_CACHE[$n]=$(gh_repo "issues/$n" --jq .state 2>/dev/null || echo unknown)
  fi
  printf '%s' "${STATE_CACHE[$n]}"
}

has_label() { case "${LABELS[$1]}" in *",$2,"*) return 0 ;; *) return 1 ;; esac; }

# labels from $2 (comma list) present on issue $1, space separated
labels_present() {
  local n=$1 found="" l
  # `|| [ -n "$l" ]` so the final element survives: tr leaves no trailing newline
  while IFS= read -r l || [ -n "$l" ]; do
    [ -n "$l" ] || continue
    has_label "$n" "$l" && found+="$l "
  done < <(printf '%s' "$2" | tr ',' '\n')
  printf '%s' "${found% }"
}

# normalise a space-separated number list; empty in, empty out (grep matching
# nothing is the common case, not an error)
uniq_nums() {
  printf '%s' "$1" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -un | tr '\n' ' ' || true
}

gather() {
  OPEN=(); LABELS=(); NATIVE_ALL=(); NATIVE_OPEN=(); TEXT_OPEN=(); DEPS=()
  STATE_CACHE=(); NUMBERS=()

  local number labels body n line ref native text
  while IFS=$'\t' read -r number labels body; do
    [ -n "$number" ] || continue
    NUMBERS+=("$number")
    OPEN[$number]=1
    LABELS[$number]=",${labels},"
    STATE_CACHE[$number]=open

    body=${body//\\n/$'\n'}

    native=""
    if [ "$NATIVE_DEPS" -eq 1 ]; then
      native=$(gh_repo "issues/$number/dependencies/blocked_by" --jq '.[].number' 2>/dev/null \
                 | tr '\n' ' ' || true)
    fi
    NATIVE_ALL[$number]=$(uniq_nums "$native")

    text=""
    while IFS= read -r line; do
      while read -r ref; do
        [ -n "$ref" ] || continue
        text+="$ref "
      done < <(printf '%s' "$line" | grep -oE '#[0-9]+' | tr -d '#')
    done < <(printf '%s' "$body" | grep -iE "$DEP_WORDS" || true)
    TEXT_OPEN[$number]=$(uniq_nums "$text")
  done < <(gh issue list --repo "$REPO" --state open --limit "$LIMIT" \
             --json number,labels,body \
             --jq '.[] | [.number, ([.labels[].name] | join(",")), (.body // "" | gsub("\n"; "\\n"))] | @tsv')

  # second pass: keep only blockers that are still open
  for n in "${NUMBERS[@]}"; do
    local keep=""
    for ref in ${NATIVE_ALL[$n]}; do
      [ "$(issue_state "$ref")" = "open" ] && keep+="$ref "
    done
    NATIVE_OPEN[$n]=${keep% }

    keep=""
    for ref in ${TEXT_OPEN[$n]}; do
      [ "$ref" = "$n" ] && continue
      [ "$(issue_state "$ref")" = "open" ] && keep+="$ref "
    done
    TEXT_OPEN[$n]=${keep% }

    DEPS[$n]=$(uniq_nums "${NATIVE_OPEN[$n]} ${TEXT_OPEN[$n]}")
  done
}

violation() { VIOLATIONS+=("$1"); }

# ------------------------------------------------------------------ checks --

check_labels() {
  local n present count
  for n in "${NUMBERS[@]}"; do
    present=$(labels_present "$n" "$STATE_LABELS")
    count=$(printf '%s' "$present" | wc -w)
    if [ "$count" -eq 0 ]; then
      violation "E1  #$n  no state label (expected one of: ${STATE_LABELS//,/, })"
    elif [ "$count" -gt 1 ]; then
      violation "E1  #$n  conflicting state labels: ${present// /, }"
    fi

    present=$(labels_present "$n" "$CATEGORY_LABELS")
    count=$(printf '%s' "$present" | wc -w)
    if [ "$count" -eq 0 ]; then
      violation "E2  #$n  no category label (expected one of: ${CATEGORY_LABELS//,/, })"
    elif [ "$count" -gt 1 ]; then
      violation "E2  #$n  conflicting category labels: ${present// /, }"
    fi
  done
}

check_blocked_label() {
  local n want has list
  for n in "${NUMBERS[@]}"; do
    [ -n "${NATIVE_OPEN[$n]}${TEXT_OPEN[$n]}" ] && want=1 || want=0
    has_label "$n" "$BLOCKED_LABEL" && has=1 || has=0
    list=$(printf '%s' "${DEPS[$n]}" | sed 's/\([0-9]\+\)/#\1/g; s/ $//; s/ /, /g')
    if [ "$want" -eq 1 ] && [ "$has" -eq 0 ]; then
      violation "E3  #$n  missing '$BLOCKED_LABEL' (open blockers: $list)"
    elif [ "$want" -eq 0 ] && [ "$has" -eq 1 ]; then
      violation "E3  #$n  stale '$BLOCKED_LABEL' (no open blockers)"
    fi
  done
}

check_edge_parity() {
  local n ref
  for n in "${NUMBERS[@]}"; do
    for ref in ${TEXT_OPEN[$n]}; do
      case " ${NATIVE_ALL[$n]} " in
        *" $ref "*) ;;
        *) violation "E4  #$n  body says it depends on #$ref, but no native dependency exists" ;;
      esac
    done
  done
}

declare -A COLOR
STACK=()
dfs() {
  local n=$1 b i from
  COLOR[$n]=gray
  STACK+=("$n")
  for b in ${DEPS[$n]}; do
    [ -n "${OPEN[$b]:-}" ] || continue
    case "${COLOR[$b]:-white}" in
      gray)
        from=""
        for i in "${STACK[@]}"; do
          [ -n "$from" ] && from+=" -> "
          from+="#$i"
        done
        violation "E5  cycle in the dependency graph: $from -> #$b"
        return 1
        ;;
      white)
        dfs "$b" || return 1
        ;;
    esac
  done
  COLOR[$n]=black
  unset 'STACK[-1]'
  return 0
}

check_cycles() {
  local n
  COLOR=(); STACK=()
  for n in "${NUMBERS[@]}"; do
    [ "${COLOR[$n]:-white}" = white ] || continue
    dfs "$n" || return 0   # one cycle report is enough
  done
}

run_checks() {
  VIOLATIONS=()
  check_labels
  check_blocked_label
  check_edge_parity
  check_cycles
}

# ------------------------------------------------------------------- fixes --

fix_edges() {
  local n ref id
  for n in "${NUMBERS[@]}"; do
    for ref in ${TEXT_OPEN[$n]}; do
      case " ${NATIVE_ALL[$n]} " in
        *" $ref "*) continue ;;
      esac
      id=$(gh_repo "issues/$ref" --jq .id)
      if gh api --method POST "repos/$REPO/issues/$n/dependencies/blocked_by" \
           -F issue_id="$id" >/dev/null 2>&1; then
        echo "fixed  E4  #$n  native dependency added: blocked by #$ref"
      else
        echo "FAILED E4  #$n  could not add native dependency on #$ref" >&2
      fi
    done
  done
}

fix_blocked_label() {
  local n want has
  if ! gh label list --repo "$REPO" --limit 200 --json name --jq '.[].name' \
       | grep -qxF "$BLOCKED_LABEL"; then
    gh label create "$BLOCKED_LABEL" --repo "$REPO" \
      -c E4E669 -d "Has an open blocker; not startable yet" >/dev/null
    echo "fixed  E3  label created: $BLOCKED_LABEL"
  fi

  for n in "${NUMBERS[@]}"; do
    [ -n "${NATIVE_OPEN[$n]}${TEXT_OPEN[$n]}" ] && want=1 || want=0
    has_label "$n" "$BLOCKED_LABEL" && has=1 || has=0
    if [ "$want" -eq 1 ] && [ "$has" -eq 0 ]; then
      gh issue edit "$n" --repo "$REPO" --add-label "$BLOCKED_LABEL" >/dev/null
      echo "fixed  E3  #$n  '$BLOCKED_LABEL' added"
    elif [ "$want" -eq 0 ] && [ "$has" -eq 1 ]; then
      gh issue edit "$n" --repo "$REPO" --remove-label "$BLOCKED_LABEL" >/dev/null
      echo "fixed  E3  #$n  '$BLOCKED_LABEL' removed"
    fi
  done
}

# -------------------------------------------------------------------- main --

gather
if [ "$FIX" -eq 1 ]; then
  fix_edges
  gather              # edges may have changed what counts as blocked
  fix_blocked_label
  gather
fi
run_checks

if [ ${#VIOLATIONS[@]} -eq 0 ]; then
  echo "$SCRIPT_NAME: ${#NUMBERS[@]} open issues, no violations ($REPO)"
  exit 0
fi

printf '%s\n' "${VIOLATIONS[@]}" | sort
echo "$SCRIPT_NAME: ${#VIOLATIONS[@]} violation(s) across ${#NUMBERS[@]} open issues ($REPO)"
[ "$FIX" -eq 1 ] && echo "$SCRIPT_NAME: remaining violations need a triage decision, not a script"
exit 1
