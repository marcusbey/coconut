#!/usr/bin/env bash
# gate-override.test.sh: an override block after the newest review round passes `sa gate` (superagent#004).
# Every case runs the real `sa gate` on its own throwaway fixture (fixture.sh), under both override headers.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }   # through bash: a copy from `git show` is not executable

F=""; D=""; R=""; T=""; W=""; A=""
drop_dir() { case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && rm -rf "$1" ;; esac; return 0; }

setup() { # a ticket branch with one commit A beyond main, tested and ready for a review file
  F=$(bash "$here/fixture.sh") || return 1
  D=$(dirname "$F"); trap 'drop_dir "$D"' EXIT
  R="$F/demo"; T="$R/tickets/001-demo-ticket"; W="$D/wt"
  git -C "$R" worktree add -q "$W" -b ticket/001-demo-ticket main || return 1
  echo change > "$W/change.txt"; git -C "$W" add change.txt; git -C "$W" commit -q -m "feat: change" || return 1
  A=$(git -C "$W" rev-parse HEAD); mkdir -p "$T/notes"; tested "$A"
}
tested() { printf -- '--- Round 1, d\nTested commit: %s\nResult: pass\n' "$1" > "$T/notes/test.md"; }
R3() { printf -- '--- Round 3, d, reviewer: codex (gpt-6-astra)\nReviewed commit: %s\nMax severity: major\nShip allowed: no\n' "$1"; }
OV() { # OV <header> <commit|-> <verdict line|->: the clerk's block; "-" leaves that line out
  printf -- '\n--- %s override, 2026-11-13\n' "$1"
  if [ "$1" = User ]; then echo 'The user chose to merge despite the remaining defects: "merge anyway"'
  else echo 'The decision room chose to merge despite the remaining defects (D1)'; fi
  [ "$2" = - ] || printf 'Reviewed commit: %s\n' "$2"
  echo 'Max severity: major'
  [ "$3" = - ] || printf '%s\n' "$3"
}
review() { cat > "$T/notes/review.md"; }

expect() { # expect pass|fail [reason]: run the gate and check its first line, its exit code and the reason
  local out rc
  out=$(sa gate "$T" "$W" main 2>&1); rc=$?
  case "$1:$rc:$(printf '%s\n' "$out" | head -1)" in
    "pass:0:GATE: pass"*) return 0 ;;
    "fail:1:GATE: fail"*) [ -z "${2:-}" ] && return 0; case "$out" in *"$2"*) return 0 ;; esac ;;
  esac
  echo "expected $1${2:+ ($2)}, rc=$rc:"; printf '%s\n' "$out"; return 1
}

run_case() { # run_case <name> <function> [args]: one fresh fixture per case
  local name=$1 out rc; shift
  out=$( ( setup && "$@" ) 2>&1 ); rc=$?
  if [ "$rc" = "0" ]; then echo "ok $name"; else echo "FAIL $name"; printf '%s\n' "$out" | sed 's/^/    /'; fi
}

c_codex_no() { { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; } | review; expect pass; }
c_both_no() { { R3 "$A"; printf 'Second review, reviewer: claude (claude-fable-5-2)\nReviewed commit: %s\nMax severity: major\nShip allowed: no\n' "$A"; OV "$1" "$A" 'Ship allowed: yes'; } | review; expect pass; }
c_base_update() { # a clean update from the base after the review keeps the override valid
  { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; } | review
  echo other > "$R/other.txt"; git -C "$R" add other.txt; git -C "$R" commit -q -m "chore: base moves" || return 1
  git -C "$W" merge -q --no-edit main || return 1
  tested "$(git -C "$W" rev-parse HEAD)"; expect pass
}
c_other_commit() { { R3 "$A"; OV "$1" "$(git -C "$R" rev-parse main)" 'Ship allowed: yes'; } | review; expect fail; }
c_later_round() { { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; printf -- '\n--- Round 4, d, reviewer: codex (gpt-6-astra)\nReviewed commit: %s\nMax severity: major\nShip allowed: no\n' "$A"; } | review; expect fail; }
c_alone() { OV "$1" "$A" 'Ship allowed: yes' | review; expect fail; }
c_says_no() { { R3 "$A"; OV "$1" "$A" 'Ship allowed: no'; } | review; expect fail; }
c_no_verdict() { { R3 "$A"; OV "$1" "$A" -; } | review; expect fail; }
c_short() { { R3 "$A"; OV "$1" "$(git -C "$W" rev-parse --short "$A")" 'Ship allowed: yes'; } | review; expect fail; }
c_head() { { R3 "$A"; OV "$1" HEAD 'Ship allowed: yes'; } | review; expect fail; }
c_cap_yes() { { R3 "$A"; OV "$1" "$A" "Ship allowed: $2"; } | review; expect fail; }
c_no_commit() { { R3 "$A"; OV "$1" - 'Ship allowed: yes'; } | review; expect fail; }
c_fenced_round() { { R3 "$A"; echo '```'; R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; echo '```'; } | review; expect fail "does not name both reviewers"; }
c_code_changed() {
  { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; } | review
  echo more > "$W/change.txt"; git -C "$W" commit -q -am "feat: more" || return 1
  tested "$(git -C "$W" rev-parse HEAD)"; expect fail "the code changed after the review"
}
c_off_branch() {
  { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; } | review
  git -C "$W" reset -q --hard main && echo other > "$W/redo.txt" && git -C "$W" add redo.txt && git -C "$W" commit -q -m "feat: redo" || return 1
  tested "$(git -C "$W" rev-parse HEAD)"; expect fail "the reviewed commit is no longer in this branch"
}
c_trailing_ids() { { R3 "$A"; OV "$1" "$A $(git -C "$R" rev-parse main)" 'Ship allowed: yes'; } | review; expect fail; }
c_bare_round() { { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; printf -- '\n--- Round 4, d, reviewer: codex (gpt-6-astra)\nSecond review, reviewer: claude (claude-fable-5-2)\n'; } | review; expect fail; }
c_yes_round() { { R3 "$A"; OV "$1" "$A" 'Ship allowed: yes'; printf -- '\n--- Round 4, d, reviewer: codex (gpt-6-astra)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\nSecond review, reviewer: claude (claude-fable-5-2)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$A" "$A"; } | review; expect pass; }
c_codex_alone_yes() { printf -- '--- Round 1, d, reviewer: codex (gpt-6-astra)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$A" | review; expect fail "does not name both reviewers"; }

for H in User "Decision room"; do
  run_case "$H: E-1/E-4 codex-only no round, then override" c_codex_no "$H"
  run_case "$H: E-2 both reviewers said no, then override" c_both_no "$H"
  run_case "$H: FR-4 clean update from the base after the override" c_base_update "$H"
  run_case "$H: X-1 override names another commit" c_other_commit "$H"
  run_case "$H: X-2 a later round makes the override stale" c_later_round "$H"
  run_case "$H: X-3 override with no round before it" c_alone "$H"
  run_case "$H: X-4 override says no" c_says_no "$H"
  run_case "$H: X-4 override without a verdict" c_no_verdict "$H"
  run_case "$H: X-5 override with a short id" c_short "$H"
  run_case "$H: X-5 override with HEAD" c_head "$H"
  run_case "$H: override verdict Yes" c_cap_yes "$H" Yes
  run_case "$H: override verdict YES" c_cap_yes "$H" YES
  run_case "$H: override without a Reviewed commit line" c_no_commit "$H"
  run_case "$H: fenced quote of a round plus override" c_fenced_round "$H"
  run_case "$H: X-6 code changed after the overridden commit" c_code_changed "$H"
  run_case "$H: FR-4 overridden commit no longer in the branch" c_off_branch "$H"
  run_case "$H: override commit field with a second id after it" c_trailing_ids "$H"
  run_case "$H: a later round without its own commit and verdict" c_bare_round "$H"
  run_case "$H: a later dual-yes round decides" c_yes_round "$H"
done
run_case "N-2 codex alone saying yes is still refused" c_codex_alone_yes
