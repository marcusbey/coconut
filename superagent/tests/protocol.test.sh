#!/usr/bin/env bash
# protocol.test.sh: `sa protocol <role>` prints the sections of PROTOCOL.md that role needs. Checks structure only
# (the "## N." headings and the "- **Decision room**" bullet), never prose, since PROTOCOL.md's wording changes.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
PROTO="$(cd "$(dirname "$SA_UNDER_TEST")" && pwd)/PROTOCOL.md"
unset SA_ROLE
sa() { bash "$SA_UNDER_TEST" "$@"; }
O=$(mktemp -d "${TMPDIR:-/tmp}/sa-protocol.XXXXXX") || exit 1
trap 'rm -rf "$O"' EXIT

fail() { echo "$*"; exit 1; }
run_case() { # run_case <name> <function>
  local rc
  ( "$2" ) > "$O/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$O/case.out"; fi
}
sections() { grep -oE '^## [0-9]+\.' "$1" | tr -d '#. ' | tr '\n' ' '; }   # "1 2 3 " of a printed part
has_room() { grep -q '^- \*\*Decision room\*\*' "$1"; }
out() { sa protocol "$1" > "$O/$1.out" || fail "sa protocol $1 failed: $(cat "$O/$1.out")"; echo "$O/$1.out"; }
first_line_ok() { # first_line_ok <file> <role>
  head -1 "$1" | grep -qF "# Superagent protocol for $2: " || fail "first line: $(head -1 "$1")"
  head -1 "$1" | grep -qF "The whole file: $PROTO" || fail "first line names no file: $(head -1 "$1")"
}

c_fixture_shape() { # the structure this command relies on is still there
  [ "$(sections "$PROTO")" = "1 2 3 4 5 6 7 8 9 " ] || fail "PROTOCOL.md sections changed: $(sections "$PROTO")"
  has_room "$PROTO" || fail "PROTOCOL.md has no '- **Decision room**' bullet"
}
c_tester() {
  local f; f=$(out tester); first_line_ok "$f" tester
  [ "$(sections "$f")" = "1 2 3 4 5 6 7 8 " ] || fail "sections: $(sections "$f")"
  ! has_room "$f" || fail "the room part of section 1 was printed"
  ! grep -qF 'Legend and seats' "$f" || fail "Legend and seats was printed"
  for r in codex-reviewer merger checker; do [ "$(sections "$(out $r)")" = "1 2 3 4 5 6 7 8 " ] || fail "$r: $(sections "$O/$r.out")"; done
}
c_builders() {
  local r f
  for r in worker teammate reproducer; do
    f=$(out $r); first_line_ok "$f" $r
    [ "$(sections "$f")" = "1 2 3 4 5 6 7 8 9 " ] || fail "$r: $(sections "$f")"
    ! has_room "$f" || fail "$r got the room part"
  done
}
c_decision_room() {
  local f; f=$(out decision-room); first_line_ok "$f" decision-room
  [ "$(sections "$f")" = "1 8 " ] || fail "sections: $(sections "$f")"
  has_room "$f" || fail "no room part"
  ! grep -q '^## 5\.' "$f" || fail "has ## 5."
}
c_watchers() {
  local r f
  for r in watchdog follow-up; do
    f=$(out $r)
    [ "$(sections "$f")" = "1 2 3 7 8 " ] || fail "$r: $(sections "$f")"
    ! has_room "$f" || fail "$r got the room part"
  done
}
c_whole_file() {
  local r f
  for r in ticket-writer clerk router somebody-new; do
    f=$(out $r)
    head -1 "$f" | grep -qF 'the whole file' || fail "$r: $(head -1 "$f")"
    tail -n +2 "$f" | cmp -s - "$PROTO" || fail "$r: not the whole file"
  done
  ! sa protocol >/dev/null || fail "no role passed"
}

run_case "PROTOCOL.md has the nine sections and the room bullet" c_fixture_shape
run_case "tester, codex-reviewer, merger, checker: 1 basics, 2 to 8" c_tester
run_case "worker, teammate, reproducer: 1 basics, 2 to 9" c_builders
run_case "decision-room: 1 basics, 1 room, 8" c_decision_room
run_case "watchdog, follow-up: 1 basics, 2, 3, 7, 8" c_watchers
run_case "ticket-writer, clerk, router, others: the whole file" c_whole_file
