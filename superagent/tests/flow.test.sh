#!/usr/bin/env bash
# flow.test.sh: `flow.py queue` and `flow.py sweep`, the read-only start list and follow-up findings.
# Every case builds its own throwaway workspace with fixture.sh; "now" is SA_NOW, worktrees live under SA_WORKTREES.
set -u
here=$(cd "$(dirname "$0")" && pwd)
FLOW="$here/../flow.py"
TIMER="$here/../sweep-timer.sh"
NOW="2026-11-20 12:00"

D=""; WS=""
fail() { echo "$*"; exit 1; }
export SA_DISK_FREE_GB=500   # the machine's own free space must not decide a test
flow() { SA_NOW="$NOW" SA_WORKTREES="$D/wt" python3 -I "$FLOW" "$@"; }
has() { printf '%s\n' "$1" | grep -qE -- "$2" || fail "want /$2/ in: $1"; }
hasnt() { printf '%s\n' "$1" | grep -qE -- "$2" && fail "did not want /$2/ in: $1"; return 0; }
line_of() { printf '%s\n' "$1" | grep -nE -- "$2" | head -1 | cut -d: -f1; }
before() { # before <text> <a> <b>: line of a comes before line of b
  local a b; a=$(line_of "$1" "$2"); b=$(line_of "$1" "$3")
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] || fail "want /$2/ before /$3/ in: $1"
}
section() { printf '%s\n' "$1" | awk -v h="## $2" '/^## /{on=($0==h)} on'; }

run_case() { # run_case <name> <function>
  local rc
  D=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  WS="$D"; D=$(dirname "$D"); mkdir -p "$D/wt"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  case "$D" in */sa-fixture.*) rm -rf "$D" ;; esac
}

# board_reset <project>: an empty board with the header
board_reset() { printf '# Board\n\n| ID | Ticket | Status | Mode | Runs | Stage |\n|----|--------|--------|------|------|-------|\n' > "$WS/$1/tickets/BOARD.md"; }
# ticket <project> <id> <slug> <status cell> <runs> <stage> [priority]
ticket() {
  local t="$WS/$1/tickets"
  printf '| %s | %s | %s | solo | %s | %s |\n' "$2" "$3" "$4" "$5" "$6" >> "$t/BOARD.md"
  mkdir -p "$t/$2-$3/notes"
  printf '# %s\n\nStatus: %s\nStage: %s\n%s\n\n## Goal\nx\n' "$2" "$4" "$6" "${7:+Priority: $7}" > "$t/$2-$3/rd.md"
}
# stage_line <project> <id> <time> [text]: a stage line in the room log
stage_line() {
  mkdir -p "$WS/decision-room/$1"
  printf '🔨 %s | %s#%s | stage | %s\n' "$3" "$1" "$2" "${4:-x -> y: z}" >> "$WS/decision-room/$1/LOG.md"
}
age_files() { find "$1" -type f -exec touch -t "$2" {} +; } # age_files <dir> <YYYYMMDDhhmm>

c_deps() { # the three Runs forms; unmet ids named; missing ticket named
  local out
  board_reset demo
  ticket demo 003 merged-one merged alongside -
  ticket demo 004 done-one done alongside done
  ticket demo 006 ready-one ready alongside -
  ticket demo 007 draft-one draft alongside -
  ticket demo 020 multi ready "after 004, 006, 007 and 003 (why: all of them)" -
  ticket demo 021 single ready "after 004 (why)" -
  ticket demo 022 free ready "alongside (nothing)" -
  ticket demo 023 ghost ready "after 099 (nope)" -
  out=$(flow queue "$WS") || fail "queue failed: $out"
  has "$(section "$out" 'Not startable')" 'demo#020 multi \| ready \| waits on #006, #007 \|'
  has "$(section "$out" 'Not startable')" 'demo#023 ghost \| ready \| waits on #099 \(no such ticket\) \|'
  has "$(section "$out" 'Start next')" 'demo#021 single'
  has "$(section "$out" 'Start next')" 'demo#022 free'
  has "$(section "$out" 'Start next')" 'demo#006 ready-one'
  hasnt "$(section "$out" 'Start next')" 'demo#020|demo#023'
}

c_priority() { # Priority: high first, even when newer and with fewer dependents
  local out
  board_reset demo
  ticket demo 031 plain ready alongside -
  ticket demo 032 urgent ready alongside - high
  ticket demo 033 after-plain draft "after 031 (needs it)" -
  stage_line demo 031 "2026-11-20 08:00"; stage_line demo 032 "2026-11-20 11:00"
  out=$(flow queue "$WS") || fail "queue failed: $out"
  before "$out" 'demo#032 urgent' 'demo#031 plain'
  has "$out" 'demo#032 urgent \| ready \| ready, high priority'
}

c_aged() { # a startable ticket older than --age-days outranks a newer one that unblocks more
  local out
  board_reset demo
  ticket demo 041 old ready alongside -
  ticket demo 042 busy ready alongside -
  ticket demo 043 dep-a draft "after 042 (x)" -
  ticket demo 044 dep-b draft "after 042 (x)" -
  stage_line demo 041 "2026-11-10 08:00"; stage_line demo 042 "2026-11-20 09:00"
  out=$(flow queue "$WS") || fail "queue failed: $out"
  before "$out" 'demo#041 old' 'demo#042 busy'
  has "$out" 'demo#041 old \| ready \| ready, waited over 3 days \| waiting 10d 4h'
  out=$(flow queue "$WS" --age-days 30) || fail "queue failed: $out"
  before "$out" 'demo#042 busy' 'demo#041 old'
}

c_dependents() { # the ticket that unblocks two others, one of them through a third, beats one that unblocks none
  local out
  board_reset demo
  ticket demo 051 loner ready alongside -
  ticket demo 052 hub ready alongside -
  ticket demo 053 child draft "after 052 (x)" -
  ticket demo 054 grandchild draft "after 053 (x)" -
  stage_line demo 051 "2026-11-20 06:00"; stage_line demo 052 "2026-11-20 10:00"
  out=$(flow queue "$WS") || fail "queue failed: $out"
  before "$out" 'demo#052 hub' 'demo#051 loner'
  has "$out" 'demo#052 hub \| ready \| ready, unblocks 2 \|'
}

c_paused() { # a paused project's ready ticket is "paused project", never a start
  local out
  out=$(flow queue "$WS") || fail "queue failed: $out"
  has "$(section "$out" 'Not startable')" 'off#001 demo-ticket \| ready \| paused project \|'
  hasnt "$(section "$out" 'Start next')" 'off#001'
}

c_unlisted() { # a project with a board that ACTIVE-PROJECTS.md does not name is seen, as not active, and only once
  local out
  mkdir -p "$WS/extra/tickets" "$WS/listed/docs/tickets"
  printf -- '- [ ] listed\n' >> "$WS/ACTIVE-PROJECTS.md"
  board_reset extra; ticket extra 001 lonely ready alongside -
  board_reset listed/docs; ticket listed/docs 002 nested ready alongside -
  out=$(flow queue "$WS") || fail "queue failed: $out"
  has "$(section "$out" 'Not startable')" 'extra#001 lonely \| ready \| paused project \|'
  hasnt "$(section "$out" 'Start next')" 'extra#001'
  [ "$(printf '%s\n' "$out" | grep -c '#002 nested')" = 1 ] || fail "the listed project's board was read twice: $out"
  has "$out" 'listed#002 nested'
  # a working copy of an unlisted project, lying in the workspace with the same board, is not a second project
  git -C "$WS/extra" init -q && git -C "$WS/extra" add -A && git -C "$WS/extra" -c user.name=t -c user.email=t@t commit -qm x
  git -C "$WS/extra" worktree add -q "$WS/extra-copy" -b copy
  out=$(flow queue "$WS") || fail "queue failed: $out"
  [ "$(printf '%s\n' "$out" | grep -c '#001 lonely')" = 1 ] || fail "a working copy became a second project: $out"
}

c_sections() { # landing first, then test/review, then ready; decisions and drafts get their sections
  local out
  board_reset demo
  ticket demo 061 ready-one ready alongside -
  ticket demo 062 testing review alongside test
  ticket demo 063 landing review alongside merge
  ticket demo 064 plan-wait in-progress alongside plan-review
  ticket demo 065 stuck "blocked (stopped by user 2026-11-09)" alongside build
  ticket demo 066 idea draft alongside -
  stage_line demo 064 "2026-11-20 10:30"
  out=$(flow queue "$WS") || fail "queue failed: $out"
  has "$out" '^# Queue, built 2026-11-20 12:00$'
  before "$out" 'demo#063 landing \| merge \| landing' 'demo#062 testing \| test \| test next'
  before "$out" 'demo#062 testing' 'demo#061 ready-one'
  has "$(section "$out" 'Waiting for a decision')" 'demo#064 plan-wait \| plan-review \| .* \| waiting 0d 1h'
  has "$(section "$out" 'Waiting for a decision')" 'demo#065 stuck \| build \| blocked'
  has "$(section "$out" 'Drafts')" 'demo \| 1 draft\(s\)'
}

c_queue_write() { # --write makes QUEUE.md, replacing a file without leaving a temp; plain run writes nothing
  local out
  out=$(flow queue "$WS") || fail "queue failed"
  [ ! -e "$WS/decision-room/QUEUE.md" ] || fail "a plain run wrote QUEUE.md"
  out=$(flow queue "$WS" --write) || fail "queue --write failed: $out"
  [ -f "$WS/decision-room/QUEUE.md" ] || fail "no QUEUE.md"
  [ "$(head -1 "$WS/decision-room/QUEUE.md")" = "# Queue, built 2026-11-20 12:00" ] || fail "first line wrong"
  [ "$(printf '%s\n' "$out")" = "$(cat "$WS/decision-room/QUEUE.md")" ] || fail "printed text differs from the file"
  flow queue "$WS" --write >/dev/null
  [ "$(ls "$WS/decision-room" | grep -c tmp)" = 0 ] || fail "temp file left behind"
}

c_sweep_kinds() { # stalled (digest ignored), parked, paused, drafts, blocked, startable, unchecked
  local out
  board_reset demo
  ticket demo 071 quiet in-progress alongside build
  ticket demo 072 busy in-progress alongside build
  ticket demo 073 waiting in-progress alongside approve-plan
  ticket demo 074 fresh-wait in-progress alongside approve-plan
  ticket demo 075 idea draft alongside -
  ticket demo 076 stuck blocked alongside build
  ticket demo 077 old-ready ready alongside -
  ticket demo 078 landed merged alongside check
  age_files "$WS/demo/tickets/071-quiet" 202611190000
  age_files "$WS/demo/tickets/072-busy" 202611190000
  touch -t 202611201155 "$WS/demo/tickets/072-busy/notes/progress.md"
  echo x > "$WS/demo/tickets/071-quiet/notes/digest.md"
  stage_line demo 071 "2026-11-19 08:00"; stage_line demo 072 "2026-11-19 08:00"
  stage_line demo 073 "2026-11-20 01:00"; stage_line demo 074 "2026-11-20 11:30"
  stage_line demo 075 "2026-11-01 08:00"; stage_line demo 076 "2026-11-18 08:00"
  stage_line demo 077 "2026-11-20 09:00"; stage_line demo 078 "2026-11-20 03:00"
  age_files "$WS/demo/tickets/078-landed" 202611200300
  out=$(flow sweep "$WS") || fail "sweep failed: $out"
  has "$out" '^NEW: stalled \| demo#071 \|'
  hasnt "$out" 'stalled \| demo#072'
  hasnt "$out" 'stalled \| demo#073'
  has "$out" '^NEW: parked \| demo#073 \| at approve-plan for 11\.0 h \| since '
  hasnt "$out" 'parked \| demo#074'
  has "$out" '^NEW: paused \| off \| paused project holds 1 ready ticket\(s\) \|'
  has "$out" '^NEW: drafts \| demo \| 1 draft\(s\) older than 7 days \|'
  has "$out" '^NEW: blocked \| demo#076 \| blocked for 2\.2 days'
  has "$out" '^NEW: startable \| demo#077 \|'
  has "$out" '^NEW: unchecked \| demo#078 \| merged 9\.0 h ago'
  hasnt "$out" '^OK'
}

c_cleanup() { # a done ticket's worktree: merged and clean, or why not
  local out
  board_reset demo
  ticket demo 081 clean done alongside done
  ticket demo 082 dirty done alongside done
  ticket demo 083 ahead done alongside done
  ticket demo 084 running in-progress alongside build
  git -C "$WS/demo" worktree add -q "$D/wt/demo/081-clean" -b ticket/081-clean || fail "worktree 081"
  git -C "$WS/demo" worktree add -q "$D/wt/demo/082-dirty" -b ticket/082-dirty || fail "worktree 082"
  git -C "$WS/demo" worktree add -q "$D/wt/demo/083-ahead" -b ticket/083-ahead || fail "worktree 083"
  git -C "$WS/demo" worktree add -q "$D/wt/demo/084-running" -b ticket/084-running || fail "worktree 084"
  echo stray > "$D/wt/demo/082-dirty/stray.txt"
  echo more > "$D/wt/demo/083-ahead/more.txt"
  git -C "$D/wt/demo/083-ahead" add more.txt && git -C "$D/wt/demo/083-ahead" commit -q -m ahead
  out=$(flow sweep "$WS") || fail "sweep failed: $out"
  has "$out" '^NEW: cleanup \| demo#081 \| .*081-clean: merged and clean \|'
  has "$out" '^NEW: cleanup \| demo#082 \| .*082-dirty: not removable: uncommitted changes \|'
  has "$out" '^NEW: cleanup \| demo#083 \| .*083-ahead: not removable: branch ticket/083-ahead not merged into main \|'
  hasnt "$out" 'cleanup \| demo#084'
  [ "$(git -C "$D/wt/demo/082-dirty" status --porcelain)" = "?? stray.txt" ] || fail "sweep changed a worktree"
}

c_known_and_gone() { # a second run says KNOWN and keeps the first-seen time; a fixed finding drops out
  local out
  out=$(flow sweep "$WS" --write) || fail "sweep failed"
  has "$out" '^NEW: paused \| off \| .* \| since 2026-11-20 12:00$'
  [ -f "$WS/decision-room/FOLLOWUP.md" ] || fail "no FOLLOWUP.md"
  [ -f "$WS/decision-room/.followup-state.json" ] || fail "no state file"
  has "$(cat "$WS/decision-room/FOLLOWUP.md")" '^## paused$'
  out=$(SA_NOW="2026-11-20 15:30" SA_WORKTREES="$D/wt" python3 -I "$FLOW" sweep "$WS" --write) || fail "second sweep failed"
  has "$out" '^KNOWN: paused \| off \| .* \| since 2026-11-20 12:00$'
  hasnt "$out" '^NEW: paused'
  has "$(cat "$WS/decision-room/.followup-state.json")" '"paused\|off": "2026-11-20 12:00"'
  sed -i.bak 's/^- \[ \] off/- [x] off/' "$WS/ACTIVE-PROJECTS.md"
  out=$(SA_NOW="2026-11-20 15:40" SA_WORKTREES="$D/wt" python3 -I "$FLOW" sweep "$WS" --write) || fail "third sweep failed"
  hasnt "$out" 'paused'
  hasnt "$(cat "$WS/decision-room/FOLLOWUP.md")" 'paused'
  hasnt "$(cat "$WS/decision-room/.followup-state.json")" 'paused'
}

c_ok() { # nothing to report: OK, and a plain run writes nothing
  local out
  sed -i.bak 's/^- \[ \] off/- [x] off/' "$WS/ACTIVE-PROJECTS.md"
  out=$(SA_WORKTREES="$D/wt" python3 -I "$FLOW" sweep "$WS") || fail "sweep failed: $out"
  [ "$out" = "OK" ] || fail "want OK, got: $out"
  [ ! -e "$WS/decision-room" ] || fail "a plain run created decision-room"
  out=$(SA_WORKTREES="$D/wt" python3 -I "$FLOW" sweep "$WS" --write) || fail "sweep --write failed"
  [ "$out" = "OK" ] || fail "want OK with --write, got: $out"
  has "$(cat "$WS/decision-room/FOLLOWUP.md")" 'Nothing open'
}

c_disk() { # free space under the limit is the first finding; above it there is none
  local out
  sed -i.bak 's/^- \[ \] off/- [x] off/' "$WS/ACTIVE-PROJECTS.md"
  out=$(SA_DISK_FREE_GB=12 flow sweep "$WS") || fail "sweep failed: $out"
  [ "$(printf '%s\n' "$out" | head -1)" = "NEW: disk | machine | 12 GB free, under the limit of 25 GB | since $NOW" ] || fail "want the disk finding first, got: $out"
  out=$(SA_DISK_FREE_GB=12 flow sweep "$WS" --disk-gb 10) || fail "sweep failed: $out"
  hasnt "$out" 'disk'
  out=$(flow sweep "$WS") || fail "sweep failed: $out"
  hasnt "$out" 'disk'
}

c_watchdog() { # the watchdog's problems appear as kind watchdog, and its live memory file is not used
  local out state="$D/state"
  sed -i.bak 's/^- \[ \] off/- [x] off/' "$WS/ACTIVE-PROJECTS.md"
  board_reset demo
  ticket demo 091 odd "weird words here" alongside -
  mkdir -p "$state"
  out=$(SA_STATE_DIR="$state" SA_WORKTREES="$D/wt" python3 -I "$FLOW" sweep "$WS") || fail "sweep failed: $out"
  has "$out" '^NEW: watchdog \| demo \| 091 has an unknown status'
  [ -z "$(ls "$state")" ] || fail "the live watchdog memory was written: $(ls "$state")"
}

c_timer() { # the launchd plist is valid and runs both reports
  local out
  out=$(bash "$TIMER" print "$WS" 7) || fail "print failed: $out"
  printf '%s\n' "$out" | plutil -lint - >/dev/null || fail "plutil -lint refused the plist"
  has "$out" '<key>Label</key><string>com.superagent.sweep</string>'
  has "$out" '<integer>420</integer>'
  has "$out" 'sweep "\$1" --write; "\$0" queue "\$1" --write'
  has "$out" "<string>$(cd "$here/.." && pwd)/sa</string>"
  has "$out" '/\.superagent/sweep\.log'
  out=$(bash "$TIMER" print "$WS" 0 2>&1) && fail "minutes 0 should be refused"
  out=$(bash "$TIMER" print "$D/nope" 2>&1) && fail "a missing workspace should be refused"
  return 0
}

run_case "queue: dependencies of all three Runs forms" c_deps
run_case "queue: Priority high goes first" c_priority
run_case "queue: an old startable ticket outranks a new one" c_aged
run_case "queue: more dependents (also indirect) ranks first" c_dependents
run_case "queue: a paused project's ticket is not startable" c_paused
run_case "queue: an unlisted project with a board is seen once, as not active" c_unlisted
run_case "queue: sections, landing before tests before ready" c_sections
run_case "queue: --write makes QUEUE.md; a plain run writes nothing" c_queue_write
run_case "sweep: stalled, parked, paused, drafts, blocked, startable, unchecked" c_sweep_kinds
run_case "sweep: cleanup says merged and clean, or why not" c_cleanup
run_case "sweep: KNOWN keeps first seen; a fixed finding disappears" c_known_and_gone
run_case "sweep: OK on a clean fixture" c_ok
run_case "sweep: low disk space is the first finding" c_disk
run_case "sweep: watchdog problems, its live memory untouched" c_watchdog
run_case "sweep-timer: print passes plutil -lint" c_timer
