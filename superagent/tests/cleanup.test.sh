#!/usr/bin/env bash
# cleanup.test.sh: `sa cleanup <ticket-dir> [--dry-run]` removes the worktrees and branches of a done ticket only
# when each one is merged into the base and clean; anything else is kept and reported. Every case runs on its own fixture.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
unset SA_ROLE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
sa() { bash "$SA_UNDER_TEST" "$@"; }

F=""; D=""; R=""; T=""; LOG=""; WT=""
fail() { echo "$*"; exit 1; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); R="$F/demo"; T="$R/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"
  printf 'Cleanup: auto\n' >> "$R/tickets/PROJECT.md"   # the owner's choice; one case below takes it away
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}
worktree() { # worktree <folder name> <branch> <merge 0|1>: a worktree of the demo repo with one commit
  local w="$D/wt/$1"
  git -C "$R" worktree add -q -b "$2" "$w" main || fail "worktree add"
  echo "$1" > "$w/work-$1.txt" && git -C "$w" add -A && git -C "$w" commit -q -m "work $1" || fail "commit in $w"
  [ "$3" = 1 ] && { git -C "$R" merge -q --no-edit "$2" || fail "merge $2"; }
  WT=$(git -C "$w" rev-parse --show-toplevel)
}
done_ticket() { sa stage "$T" done "finished" >/dev/null || fail "stage done"; }
has_branch() { git -C "$R" show-ref --verify -q "refs/heads/$1"; }

c_removes_merged_clean() {
  local o w2
  worktree 001-demo-ticket feature/001 1
  worktree 001-demo-ticket-ui feature/001-ui 1; w2=$WT
  worktree 002-other feature/002 1
  done_ticket
  o=$(sa cleanup "$T") || fail "cleanup failed: $o"
  printf '%s\n' "$o" | grep -qxF "removed $w2 and branch feature/001-ui" || fail "output: $o"
  [ "$(printf '%s\n' "$o" | grep -c '^removed ')" = 2 ] || fail "want two removals: $o"
  [ ! -d "$D/wt/001-demo-ticket" ] && [ ! -d "$D/wt/001-demo-ticket-ui" ] || fail "a worktree is still there"
  ! has_branch feature/001 && ! has_branch feature/001-ui || fail "a branch is still there"
  [ -d "$D/wt/002-other" ] && has_branch feature/002 || fail "another ticket's worktree was touched"
  [ -d "$R/.git" ] || fail "the main checkout went away"
  [ "$(grep -c 'branch feature/001' "$T/notes/delete-list.md")" = 2 ] || fail "delete-list: $(cat "$T/notes/delete-list.md" 2>/dev/null)"
  grep -qE "^- [0-9]{4}-[0-9]{2}-[0-9]{2}: $w2, branch feature/001-ui\$" "$T/notes/delete-list.md" || fail "delete-list line: $(cat "$T/notes/delete-list.md")"
  [ "$(grep -c ' | demo#001 | note | cleanup: removed ' "$LOG")" = 2 ] || fail "room notes: $(cat "$LOG")"
  o=$(sa cleanup "$T") || fail "second run: $o"
  [ "$o" = "nothing to clean" ] || fail "second run: $o"
}
c_keeps_dirty() {
  local o
  worktree 001-demo-ticket feature/001 1
  echo x >> "$WT/work-001-demo-ticket.txt"
  done_ticket
  o=$(sa cleanup "$T") || fail "cleanup: $o"
  printf '%s\n' "$o" | grep -qF "kept $WT: uncommitted changes" || fail "output: $o"
  [ -d "$WT" ] && has_branch feature/001 || fail "removed a dirty worktree"
  grep -q 'x' "$WT/work-001-demo-ticket.txt" || fail "the change was lost"
}
c_keeps_unmerged() {
  local o
  worktree 001-demo-ticket feature/001 0
  done_ticket
  o=$(sa cleanup "$T") || fail "cleanup: $o"
  printf '%s\n' "$o" | grep -qF "kept $WT: branch feature/001 is not merged into main" || fail "output: $o"
  [ -d "$WT" ] && has_branch feature/001 || fail "removed an unmerged worktree"
  [ ! -e "$T/notes/delete-list.md" ] || fail "a delete-list was written"
}
c_refuses_not_done() {
  local o rc
  worktree 001-demo-ticket feature/001 1
  o=$(sa cleanup "$T"); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1, got $rc: $o"
  case "$o" in refused:*) ;; *) fail "want refused: $o" ;; esac
  [ -d "$WT" ] && has_branch feature/001 || fail "removed for a ticket that is not done"
}
c_dry_run() {
  local o
  worktree 001-demo-ticket feature/001 1
  done_ticket
  o=$(sa cleanup "$T" --dry-run) || fail "dry run: $o"
  [ "$o" = "would remove $WT and branch feature/001" ] || fail "output: $o"
  [ -d "$WT" ] && has_branch feature/001 || fail "the dry run removed something"
  [ ! -e "$T/notes/delete-list.md" ] || fail "the dry run wrote a delete-list"
  ! grep -qF 'cleanup' "$LOG" || fail "the dry run wrote a room line"
}
c_nothing() {
  local o
  done_ticket
  o=$(sa cleanup "$T") || fail "cleanup: $o"
  [ "$o" = "nothing to clean" ] || fail "output: $o"
}

c_refuses_without_auto() {
  local o
  printf '# Project: demo\n\nBase branch: main\nCleanup: ask\n' > "$R/tickets/PROJECT.md"
  worktree 001-demo-ticket feature/001 1
  done_ticket
  o=$(sa cleanup "$T") && fail "cleanup ran in a Cleanup: ask project: $o"
  case "$o" in "refused: "*"Cleanup: auto"*) ;; *) fail "want a refusal naming the line: $o" ;; esac
  [ -d "$D/wt/001-demo-ticket" ] && has_branch feature/001 || fail "something was removed"
  [ ! -e "$T/notes/delete-list.md" ] || fail "a delete list was written"
}
run_case "a done ticket's merged, clean worktrees and branches are removed" c_removes_merged_clean
run_case "without Cleanup: auto in PROJECT.md nothing is removed" c_refuses_without_auto
run_case "a dirty worktree is kept" c_keeps_dirty
run_case "an unmerged branch is kept" c_keeps_unmerged
run_case "a ticket that is not done is refused and nothing changes" c_refuses_not_done
run_case "--dry-run changes nothing" c_dry_run
run_case "no candidate: nothing to clean" c_nothing
