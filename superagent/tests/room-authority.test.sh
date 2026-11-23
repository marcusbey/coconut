#!/usr/bin/env bash
# room-authority.test.sh: the decision room's switch, the owner-only markers, the refusals of
# `sa room decide`, the gate with a room-approved plan, and the PR guard `sa room pr-ok` (superagent#003).
# Every case runs on its own throwaway fixture (fixture.sh), never on a real workspace.
# SA_KEEP_FIXTURES=1 keeps each fixture and prints its path (for eval E-6's grep).
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }   # through bash: a copy from `git show` is not executable
AG="$here/../../agents"; PROTO="$here/../PROTOCOL.md"
WORDS='the room decides everything; only what needs a login, access or the like reaches me, and only after computer use was tried and blocked.'
OLD='user approvals are never skipped'
NEW='what only the user can give (logins, access, their own stop orders) is never skipped'
URL='https://github.com/superagent-fixture/demo/pull/7'
B='(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔)'   # the badge of the agent role behind a line (superagent#007)

F=""; D=""; T=""; R=""; LOG=""; DEC=""; C=""
fail() { echo "$*"; exit 1; }
count() { grep -c "$@" 2>/dev/null || true; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; R="$F/decision-room/demo"; LOG="$R/LOG.md"; DEC="$R/DECISIONS.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  if [ -n "${SA_KEEP_FIXTURES:-}" ]; then echo "    fixture kept: $F"; else drop_dir "$D"; fi
}

# every file under the fixture, by checksum (the case's own output aside)
snap() { (cd "$D" && find . -type f ! -path ./case.out -print0 | xargs -0 cksum | sort); }
# refuses "<text>" <command...>: exit 1, prints "refused: <text>", and no file under the fixture changed
refuses() {
  local want="$1" before out rc; shift
  before=$(snap)
  out=$("$@" 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 for '$want', got $rc: $out"
  printf '%s\n' "$out" | grep -qF "refused: $want" || fail "want 'refused: $want', got: $out"
  [ "$(snap)" = "$before" ] || fail "a refusal ('$want') changed a file"
}
on() { sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "room on failed"; }
decide() { sa room decide "$T" "$1" "$2" --option "$3" --option "$4" --fable a "ok" --codex a "ok"; }
qblock() { awk -v h="## $1 " 'index($0,h)==1 {f=1; print; next} /^## /{f=0} f' "$T/notes/questions.md"; }

# --- the switch (FR-1) -------------------------------------------------------------------------

c_switch() { # E-1
  local out
  [ "$(sa room status "$F")" = off ] || fail "no file: want off"
  printf '# Router preferences\n\n- 2026-11-11: "x". Standing rule: limits: user approvals are never skipped.\n' > "$F/ROUTER-PREFS.md"
  [ "$(sa room status "$F")" = off ] || fail "no switch line: want off"
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "on failed"
  [ "$(sa room status "$F")" = on ] || fail "want on"
  grep -qxF -- "- 2026-11-13: \"$WORDS\". Standing rule: Decision room: on." "$F/ROUTER-PREFS.md" || fail "no on line: $(cat "$F/ROUTER-PREFS.md")"
  grep -qF "$OLD" "$F/ROUTER-PREFS.md" && fail "old phrase still there"
  [ "$(sed -n 3p "$F/ROUTER-PREFS.md")" = "- 2026-11-11: \"x\". Standing rule: limits: $NEW." ] || fail "line 3 wrong: $(sed -n 3p "$F/ROUTER-PREFS.md")"
  [ "$(sed -n '1,2p' "$F/ROUTER-PREFS.md")" = "$(printf '# Router preferences\n')" ] || fail "lines 1-2 changed"
  [ "$(wc -l < "$F/ROUTER-PREFS.md" | tr -d ' ')" = 4 ] || fail "want 4 lines"
  sa room off "$F" "trial over" >/dev/null || fail "off failed"
  [ "$(sa room status "$F")" = off ] || fail "want off after off"
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "on again failed"
  [ "$(sa room status "$F")" = on ] || fail "want on again"
  refuses "the date must be YYYY-MM-DD" sa room on "$F" 2026-13 "$WORDS"
  refuses "the user's words are empty" sa room on "$F" 2026-11-13 ""
  refuses "no such folder" sa room on "$F/nope" 2026-11-13 "$WORDS"
  refuses "room off needs the reason" sa room off "$F" ""
  refuses "no such folder" sa room status "$F/nope"
  out=$(sa room bogus 2>&1); [ $? = 1 ] || fail "unknown room subcommand accepted: $out"
}

c_switch_any_path() { # the switch reads the same from any folder under the workspace (2026-11-15: a clerk
  # ran `sa room status <project>`, got off, and refused to carry out a room decision)
  on
  [ "$(sa room status "$F/demo")" = on ] || fail "project folder: want on"
  [ "$(sa room status "$F/demo/tickets")" = on ] || fail "tickets folder: want on"
  [ "$(sa room status "$T")" = on ] || fail "ticket folder: want on"
  [ "$(sa room status "$F/group/app")" = on ] || fail "nested project: want on"
  sa room off "$F" "trial over" >/dev/null || fail "off failed"
  [ "$(sa room status "$F/demo")" = off ] || fail "project folder: want off after off"
}

prefs8() { # a byte copy of the live ROUTER-PREFS.md, taken at the start of the build (T0)
cat <<'EOF'
# Router preferences

- 2026-11-11: "add this to the super-agent setting too. and only when fable-5-2 is not avalaible that u can use opus-5-5". Standing rule: Design work (UI/UX design, design specs, visual and motion design, design review) in every project runs on a worker started with model `fable` (Fable 5.2, claude-fable-5-2). Each design worker states its model ID first. Only when Fable 5.2 is not available may design work use `opus` (Opus 5.5); say so to the user when that happens. No other model does design work. Building follows each ticket's Builder line.
- 2026-11-11: "if anything is taking too much time. make sure to add more workers on it". Standing rule: when a ticket or stage runs long, the router adds workers on every part that can run in parallel (independent tickets, plans, research, media, reviews) without asking, and says so in one line. Limits that still hold: one UI-test session at a time per Mac; no two agents editing the same worktree; user approvals are never skipped (superseded 2026-11-13 for room-decidable decisions, see below).
- 2026-11-11: "set in my setting all the reviewers to codex astra and claude-fable-5-2 only when fabl52 is not available u review with opus". Standing rule: Reviews (plan reviews and code reviews, every project): the reviewers are Codex on the Astra model, and Claude on Fable 5.2 (a reviewer started with model `fable`, claude-fable-5-2). Whenever a Claude review is needed (Codex unavailable, Codex built the code, or `Review: claude`), it runs on Fable 5.2. Only when Fable 5.2 is not available may the Claude review use `opus` (Opus 5.5); the router says so when that happens. Each Claude reviewer states its model ID in its verdict.
- 2026-11-11: "qui note. set additional rules in the superagent setting. alway use fable-5-2 to write the ticket and anything related to prd or plan. then design too and reviewes." Standing rule: Model for writing and planning work (every project): ticket writing (the ticket-writer in write-tickets and project modes), PRDs, specs, research write-ups and plans — including the plan stage of builders and plan revisions — run on Fable 5.2 (model `fable`, claude-fable-5-2). Design and reviews already run on Fable 5.2 (earlier lines). Only when Fable 5.2 is not available may these use `opus` (Opus 5.5), and the router says so. Building (code) follows each ticket's Builder/Model lines; small clerk jobs (mark ready, record an answer, stop/resume) may stay on haiku.
- 2026-11-11: "alown with codex for the review. codex can also review the plan writeen with fable5.2". Standing rule: Reviews pair Codex and Fable 5.2 (every project): whenever Codex (Astra) is available, every plan review and code review is done by Codex, including plans written by Fable 5.2; Fable 5.2 also reviews (a second, independent review) — both verdicts are recorded and both must allow shipping (or call the plan sound). When Codex is unavailable (e.g. its usage limit until Nov 15, 2026), Fable 5.2 reviews alone and the router says so; Opus 5.5 only if Fable 5.2 is unavailable too.
- 2026-11-13: "Active la salle de décision, vérifie si ça marche, continue sans me demander d'autoriser". Standing rule: Decisions the router would ask the owner go to the decision room instead: `sa room decide`, with the decision-room agent's Codex and Fable 5.2 seats; Opus stands in when Fable is unavailable, and the brief then says "Fable seat unavailable: <reason>". The router carries out the room's recorded decision and tells the owner in one line. This covers agents' questions, draft open questions, ticket, plan and merge approvals, opening and merging PRs, suggestions, failed-check choices and cleanup. These stay with the owner: stop and resume; payments; logins, credentials and access; OS permission prompts; his own uncommitted files; device, microphone and phone checks; facts only he knows; anything Claude Code's safety check refuses until he types his own words; any question when no seat is available; switching this rule off. Until superagent#003 lands, the router does this by hand by starting the decision-room agent. This rule replaces the earlier "user approvals are never skipped" limit in the 2026-11-11 line only for the decisions the room may take.
EOF
}

c_switch_real_prefs() {
  local P="$F/ROUTER-PREFS.md" i
  prefs8 > "$D/orig"; command cp "$D/orig" "$P"
  [ "$(wc -l < "$P" | tr -d ' ')" = 8 ] || fail "the copy is not eight lines"
  [ "$(sa room status "$F")" = off ] || fail "at landing: want off"
  cmp -s "$P" "$D/orig" || fail "status changed the file"
  printf -- "- 2026-11-14: from superagent#003's landing, the 2026-11-13 decision-room rule above is carried by the switch below: 'sa room on' starts it, 'sa room off' ends it.\n" >> "$P"
  command cp "$P" "$D/noted"
  [ "$(sa room status "$F")" = off ] || fail "the clerk note must not read as a switch"
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "on failed"
  [ "$(sa room status "$F")" = on ] || fail "want on"
  for i in 1 2 3 5 6 7 8 9; do
    [ "$(sed -n "${i}p" "$P")" = "$(sed -n "${i}p" "$D/noted")" ] || fail "line $i changed: $(sed -n "${i}p" "$P")"
  done
  [ "$(sed -n 4p "$P")" = "$(sed -n 4p "$D/orig" | LC_ALL=C sed "s/$OLD/what only the user can give (logins, access, their own stop orders) is never skipped/")" ] || fail "line 4 wrong: $(sed -n 4p "$P")"
  grep -c "\"$OLD\"" "$P" | grep -qx 1 || fail "the quoted phrase on line 8 must stay"
  [ "$(sed -n 10p "$P")" = "- 2026-11-13: \"$WORDS\". Standing rule: Decision room: on." ] || fail "line 10 wrong"
  sa room off "$F" "trial over" >/dev/null || fail "off failed"
  [ "$(sa room status "$F")" = off ] || fail "want off"
  head -8 "$P" | cmp -s - "$D/orig" || fail "off did not restore lines 1-8: $(head -8 "$P" | diff - "$D/orig")"
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "on again failed"
  [ "$(sa room status "$F")" = on ] || fail "want on again"
}

notes_in() { count ' | note | .*decision room switched' "$1"; }
c_switch_logs() {
  local A="$F/decision-room/group/app/LOG.md" O="$F/decision-room/off/LOG.md" pid out
  sa stage "$T" research "start" >/dev/null || fail "stage failed"
  [ ! -e "$A" ] || fail "group/app log exists already"
  out=$(sa room on "$F" 2026-11-13 "$WORDS" "$F/demo/tickets" "$F/group/app/tickets/") || fail "on failed: $out"
  for f in "$LOG" "$A" "$O"; do [ "$(notes_in "$f")" = 1 ] || fail "want one switch note in $f: $(cat "$f" 2>/dev/null)"; done
  [ "$(grep -vc '^# ' "$LOG")" = 2 ] || fail "demo log: want the stage line and one note (the legend line is no entry)"
  grep -qE '^'"$B"' [0-9-]{10} [0-9:]{5} \| demo \| note \| ' "$LOG" || fail "note line shape: $(cat "$LOG")"
  sa room off "$F" "trial over" >/dev/null || fail "off failed"
  for f in "$LOG" "$A" "$O"; do [ "$(notes_in "$f")" = 2 ] || fail "want two switch notes in $f"; done
  # a switch running alongside a stage change loses no line
  ( sa stage "$T" build "parallel" >/dev/null ) & pid=$!
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "on (parallel) failed"
  wait "$pid" || fail "parallel stage failed"
  [ "$(notes_in "$LOG")" = 3 ] || fail "parallel: switch note lost"
  [ "$(count ' | stage | .*parallel' "$LOG")" = 1 ] || fail "parallel: stage line lost"
}

c_switch_room_project() {
  local O="$D/outside" L="$D/outside-room/outside/LOG.md"
  printf 'Room: %s/outside-room\n' "$D" >> "$O/tickets/PROJECT.md"
  sa room on "$D" 2026-11-13 "$WORDS" "$O/tickets" >/dev/null || fail "on failed"
  [ "$(sa room status "$D")" = on ] || fail "want on"
  [ "$(notes_in "$L")" = 1 ] || fail "no note in the Room: project's log: $(cat "$L" 2>/dev/null)"
  sa room off "$D" "trial over" "$O/tickets" >/dev/null || fail "off failed"
  [ "$(notes_in "$L")" = 2 ] || fail "no off note in the Room: project's log"
}

c_switch_note_fails() {
  local A="$F/decision-room/group/app/LOG.md" O="$F/decision-room/off/LOG.md" out rc w
  mkdir -p "$(dirname "$A")"; : > "$A"; chmod a-w "$A"
  for w in on off; do
    if [ "$w" = on ]; then out=$(sa room on "$F" 2026-11-13 "$WORDS" 2>&1); rc=$?
    else out=$(sa room off "$F" "trial over" 2>&1); rc=$?; fi
    [ "$rc" = 1 ] || fail "$w: want exit 1, got $rc: $out"
    printf '%s\n' "$out" | grep -qF "switch: $w" || fail "$w: the real switch value is not printed: $out"
    printf '%s\n' "$out" | grep -qxF "note: no switch note for group/app" || fail "$w: missing note line: $out"
    [ "$(sa room status "$F")" = "$w" ] || fail "$w: the switch was rolled back"
    [ "$(notes_in "$LOG")" -ge 1 ] && [ "$(notes_in "$O")" -ge 1 ] || fail "$w: the other projects lack their note"
  done
  [ "$(notes_in "$LOG")" = 2 ] && [ "$(notes_in "$O")" = 2 ] || fail "want two notes each in demo and off"
}

c_switch_text() {
  local P="$F/ROUTER-PREFS.md" t0
  on; on
  [ "$(count 'Decision room: on' "$P")" = 2 ] || fail "on twice: want two lines"
  sa room off "$F" "a" >/dev/null && sa room off "$F" "b" >/dev/null || fail "off twice failed"
  [ "$(sa room status "$F")" = off ] || fail "off twice: want off"
  tail -1 "$P" | grep -qF 'every decision goes to the owner' || fail "off line lacks its text"
  sa room on "$F" 2026-11-13 "$(printf 'say "hi"\nthere')" >/dev/null || fail "on with quotes failed"
  [ "$(tail -1 "$P")" = '- 2026-11-13: "say "hi" there". Standing rule: Decision room: on.' ] || fail "words not on one line: $(tail -2 "$P")"
  refuses "the words must not contain 'Decision room:'" sa room on "$F" 2026-11-13 "x. Decision room: off"
  refuses "the reason must not contain 'Decision room:'" sa room off "$F" "Decision room: on"
  [ "$(sa room status "$F")" = on ] || fail "a refused call changed the switch"
  # the switch folder is also a tickets folder: the note does not wait for the switch's own lock
  t0=$SECONDS
  sa room on "$F/demo/tickets" 2026-11-13 "$WORDS" "$F/demo/tickets" >/dev/null || fail "on in a tickets folder failed"
  [ $((SECONDS - t0)) -lt 10 ] || fail "waited for its own lock"
  [ "$(sa room status "$F/demo/tickets")" = on ] || fail "tickets-folder switch: want on"
}

# --- owner-only questions and room decide's refusals (FR-7, FR-8) ----------------------------

c_owner_access_q() { # E-10, X-4
  local b
  on; sa stage "$T" build go >/dev/null
  sa ask "$T" worker --access "opened the dashboard in the signed-in browser; it asks for a 2FA code" "Sign in to the dashboard?" "I signed in; continue" "Skip this check" >/dev/null || fail "ask --access failed"
  b=$(qblock Q1)
  printf '%s\n' "$b" | grep -qxF 'Kind: access' || fail "no Kind line: $b"
  printf '%s\n' "$b" | grep -qxF 'Tried: opened the dashboard in the signed-in browser; it asks for a 2FA code' || fail "no Tried line: $b"
  refuses "an access question reaches the user" decide Q1 "Sign in to the dashboard?" "I signed in; continue" "Skip this check"
  refuses "an access question needs what was tried" sa ask "$T" worker --access "" "Sign in?" "yes" "no"
  [ "$(count '^## Q' "$T/notes/questions.md")" = 1 ] || fail "the empty --access added a question"
  [ "$(count '^## Q1 \[open\]' "$T/notes/questions.md")" = 1 ] || fail "Q1 not open"
}

c_owner_marked_later() {
  local out
  on; sa stage "$T" build go >/dev/null
  sa ask "$T" worker "Pay the invoice?" "pay it" "wait" >/dev/null
  sa ask "$T" worker "Use A or B?" "use A" "use B" >/dev/null
  out=$(sa room owner "$T" Q1 "a payment") || fail "room owner failed: $out"
  qblock Q1 | grep -qxF 'Kind: access' || fail "Q1 not marked"
  qblock Q1 | grep -qxF 'Tried: a payment' || fail "Q1 lacks its Tried line"
  qblock Q2 | grep -q '^Kind:' && fail "Q2 marked too"
  refuses "an access question reaches the user" decide Q1 "Pay the invoice?" "pay it" "wait"
  refuses "001 waits for the user's answer to Q1" decide Q2 "Use A or B?" "use A" "use B"
  refuses "Q1 is already marked" sa room owner "$T" Q1 "again"
  refuses "no open question Q9" sa room owner "$T" Q9 "x"
  sa answer "$T" Q2 "use A" >/dev/null
  refuses "no open question Q2" sa room owner "$T" Q2 "x"
  refuses "room owner needs the reason" sa room owner "$T" Q1 ""
}

c_owner_draft() {
  local tmp="$T/rd.md.t"
  sed 's/^- None\.$/- **Q1**: Grant the OS permission the build asks for? (access)/' "$T/rd.md" > "$tmp" && cat "$tmp" > "$T/rd.md" && rm -f "$tmp"
  grep -qF '(access)' "$T/rd.md" || fail "setup"
  refuses "an access question reaches the user" decide Q1 "Grant the OS permission?" "grant" "skip"
  refuses "001 waits for the user's answer to Q1" decide ready "Approve demo#001?" "Approve" "Not yet"
}

c_owner_fact() {
  sa stage "$T" build go >/dev/null
  sa ask "$T" reproducer --access "could not reproduce in three tries; only the owner saw it happen" "What was different when it broke?" "the owner tells us" "drop the ticket" >/dev/null || fail "ask failed"
  refuses "an access question reaches the user" decide Q1 "What was different when it broke?" "the owner tells us" "drop the ticket"
}

c_room_investigation() {
  local out
  sa stage "$T" build go >/dev/null
  sa ask "$T" reproducer "Investigate another way, or drop it?" "investigate the cache" "drop it" >/dev/null
  out=$(decide Q1 "Investigate another way, or drop it?" "investigate the cache" "drop it") || fail "refused: $out"
  [ "$out" = "D1: (a) investigate the cache; decided by both" ] || fail "printed: $out"
}

c_owner_blocks_all_subjects() {
  local s
  sa stage "$T" build go >/dev/null
  sa ask "$T" worker --access "the browser has no session for the console" "Sign in to the console?" "signed in" "skip" >/dev/null
  for s in Q2 plan merge ready other; do
    refuses "001 waits for the user's answer to Q1" decide "$s" "Go on?" "yes" "no"
  done
}

c_owner_suggestion() {
  local S="$F/demo/tickets" out
  sa suggest "$S" "demo#001 worker" "Buy a license for the linter" "x.sh:3" small >/dev/null
  sa suggest "$S" "demo#001 worker" "Add a retry" "y.sh:4" small >/dev/null
  sa room owner "$S" S1 "a payment" >/dev/null || fail "room owner S1 failed"
  awk '/^## S1 /{f=1} /^## S2 /{f=0} f' "$S/SUGGESTIONS.md" | grep -qxF 'Kind: access' || fail "S1 not marked"
  awk '/^## S2 /{f=1} f' "$S/SUGGESTIONS.md" | grep -q '^Kind:' && fail "S2 marked too"
  refuses "an access question reaches the user" sa room decide "$S" S1 "Ticket it?" --option "ticket it" --option "dismiss" --fable a ok --codex a ok
  out=$(sa room decide "$S" S2 "Ticket it?" --option "ticket it" --option "dismiss" --fable a ok --codex a ok) || fail "plain S2 refused: $out"
}

c_decide_stopped() { # X-2
  sa stage "$T" stopped "stopped by the user" >/dev/null
  refuses "001 is stopped by the user; the room never lifts a stop" decide other "Resume demo#001?" "Resume" "Leave it"
  grep '^| 001' "$F/demo/tickets/BOARD.md" | grep -q '| stopped |' || fail "row not stopped"
  [ ! -e "$DEC" ] || fail "a decision was recorded"
}

# held_decide <change> <subject> <question> <a> <b>: room decide waits on a held lock while <change> lands
# (the way another sa would write it, under the lock); the lock is then freed. Prints decide's output, then its exit code.
held_decide() {
  local L="$F/demo/tickets/.sa.lock" change=$1 pid rc; shift
  mkdir "$L" && echo $$ > "$L/pid" || fail "could not hold the lock"
  decide "$@" > "$D/held.out" 2>&1 & pid=$!
  sleep 1
  "$change"
  rm -f "$L/pid"; rmdir "$L"
  wait "$pid"; rc=$?
  cat "$D/held.out"; echo "exit $rc"
}
stop_by_hand() { sed 's/^Status: .*/Status: stopped/' "$T/rd.md" > "$T/rd.md.t" && cat "$T/rd.md.t" > "$T/rd.md" && rm -f "$T/rd.md.t"; }
mark_by_hand() { awk '{ print } /^Question: Pay the invoice\?$/ { print "Kind: access"; print "Tried: a payment" }' "$T/notes/questions.md" > "$T/q.t" && cat "$T/q.t" > "$T/notes/questions.md" && rm -f "$T/q.t"; }

c_decide_waits_stop() { # a stop that lands while room decide waits for the lock is still refused
  local out
  on; sa stage "$T" build go >/dev/null
  out=$(held_decide stop_by_hand other "Go on?" "yes" "no")
  printf '%s\n' "$out" | grep -qF 'refused: 001 is stopped by the user' || fail "want the stop refusal, got: $out"
  [ ! -e "$DEC" ] || fail "a decision was recorded: $(cat "$DEC")"
}

c_decide_waits_owner() { # an owner-only mark that lands while room decide waits is still refused
  local out
  on; sa stage "$T" build go >/dev/null
  sa ask "$T" worker "Pay the invoice?" "pay it" "wait" >/dev/null
  out=$(held_decide mark_by_hand Q1 "Pay the invoice?" "pay it" "wait")
  printf '%s\n' "$out" | grep -qF 'refused: an access question reaches the user' || fail "want the access refusal, got: $out"
  [ ! -e "$DEC" ] || fail "a decision was recorded: $(cat "$DEC")"
}

c_owner_draft_mark() { # room owner marks a draft's question in rd.md that starts unmarked
  local out tmp="$T/rd.md.t"
  sa stage "$T" draft "back to draft" >/dev/null
  sed 's/^- None\.$/- **Q1**: Grant the OS permission the build asks for? (a) grant (b) skip\
- **Q2**: Use A or B? (a) A (b) B/' "$T/rd.md" > "$tmp" && cat "$tmp" > "$T/rd.md" && rm -f "$tmp"
  grep -qF '(access)' "$T/rd.md" && fail "setup: already marked"
  out=$(sa room owner "$T" Q1 "an OS permission prompt only the owner can accept") || fail "room owner refused the draft question: $out"
  grep -qxF -- '- **Q1**: Grant the OS permission the build asks for? (a) grant (b) skip (access)' "$T/rd.md" || fail "Q1 not marked: $(grep 'Q1' "$T/rd.md")"
  grep -qxF -- '- **Q2**: Use A or B? (a) A (b) B' "$T/rd.md" || fail "Q2 changed: $(grep 'Q2' "$T/rd.md")"
  tail -1 "$LOG" | grep -qF 'Q1 marked as the user'"'"'s: an OS permission prompt only the owner can accept' || fail "no room note: $(tail -1 "$LOG")"
  refuses "an access question reaches the user" decide Q1 "Grant the OS permission?" "grant" "skip"
  refuses "Q1 is already marked" sa room owner "$T" Q1 "again"
  refuses "no open question Q3" sa room owner "$T" Q3 "x"
}

c_rules_carry_out() { # the clerk logs a non-approval; a room-chosen undo names D<n>
  grep -E '^ +- `plan`, `merge` or `ready` with another option:' "$AG/ticket-writer.md" | grep -qF 'carried out D<n>' ||
    fail "ticket-writer: a non-approval does not log carried out D<n>"
  grep -qF 'merge undone by the decision room D<n>' "$AG/merger.md" || fail "merger: no room-chosen undo note naming D<n>"
}

c_no_seat() { # X-5
  on; sa stage "$T" build go >/dev/null; sa ask "$T" worker "Use A or B?" "use A" "use B" >/dev/null
  refuses "no seat is available; this question reaches the user" sa room decide "$T" Q1 "Use A or B?" --option "use A" --option "use B" --fable-unavailable "overloaded" --codex-unavailable "usage limit"
  [ "$(count '^## Q1 \[open\]' "$T/notes/questions.md")" = 1 ] || fail "Q1 closed"
}

c_rules() { # the written rules name what stays the owner's
  local f p
  for f in "$AG/router.md" "$AG/decision-room.md" "$PROTO"; do
    for p in 'credential' 'OS permission' 'payment' 'uncommitted files' 'safety check' 'only the owner knows'; do
      grep -qi -- "$p" "$f" || fail "$(basename "$f") does not name '$p' as the owner's"
    done
  done
}

# --- the gate with a room-approved plan (E-3 b, N-3) -------------------------------------------

W=""; A=""
gate_setup() { # a ticket branch with one commit A, tested and reviewed by both, at approve-plan with a plan
  local P="$F/demo"
  W="$D/wt"
  git -C "$P" worktree add -q "$W" -b ticket/001-demo-ticket main || fail "worktree"
  echo change > "$W/change.txt"; git -C "$W" add change.txt; git -C "$W" commit -q -m "feat: change" || fail "commit"
  A=$(git -C "$W" rev-parse HEAD); mkdir -p "$T/notes"
  tst "$A" pass > "$T/notes/test.md"; rev yes yes "$A" > "$T/notes/review.md"
  sa stage "$T" approve-plan "plan reviewed" >/dev/null || fail "stage"
  printf '# plan\n\nSome tasks.\n' > "$T/notes/plan.md"
}
room_approves() {
  printf 'Approved: 2026-11-13 by decision room D1, on the user'"'"'s standing order of 2026-11-13 ("Approve")\n' >> "$T/notes/plan.md"
  sa stage "$T" build "plan approved by the decision room D1" >/dev/null || fail "stage build"
}
gate_expect() { # gate_expect pass|fail [reason]
  local out rc
  out=$(sa gate "$T" "$W" main 2>&1); rc=$?
  case "$1:$rc:$(printf '%s\n' "$out" | head -1)" in
    "pass:0:GATE: pass"*) return 0 ;;
    "fail:1:GATE: fail"*) [ -z "${2:-}" ] && return 0; case "$out" in *"$2"*) return 0 ;; esac ;;
  esac
  fail "expected $1${2:+ ($2)}, rc=$rc: $out"
}
c_plan_by_room() {
  gate_setup; room_approves
  tail -1 "$T/notes/plan.md" | grep -qE "^Approved: [0-9-]{10} by decision room D[0-9]+, on the user's standing order of 2026-11-13 \(\".*\"\)$" || fail "plan line: $(tail -1 "$T/notes/plan.md")"
  grep '^| 001' "$F/demo/tickets/BOARD.md" | grep -q '| build |' || fail "row not at build"
}
c_gate_room_plan() { gate_setup; room_approves; gate_expect pass; }
c_gate_no_plan() { gate_setup; sa stage "$T" build go >/dev/null; gate_expect fail "the plan was never approved (no dated 'Approved: YYYY-MM-DD by ...' line in notes/plan.md, from the user or the decision room). Next: the router has the plan approved"; }
c_gate_no_test() { gate_setup; room_approves; tst "$A" fail > "$T/notes/test.md"; gate_expect fail "not pass"; }
c_gate_review_no() { gate_setup; room_approves; rev yes no "$A" > "$T/notes/review.md"; gate_expect fail "Ship allowed: no"; }
c_gate_open_q() { gate_setup; room_approves; sa ask "$T" worker "Use A or B?" "use A" "use B" >/dev/null; gate_expect fail "open question"; }

# --- the PR guard (FR-12: E-11, X-6) -----------------------------------------------------------

tst() { printf -- '--- Round 1, 2026-11-13\nTested commit: %s\nBase: main @ %s\nResult: %s\n' "$1" "$1" "$2"; }
rev() { # rev <codex verdict> <claude verdict> <commit> [<claude's commit>]
  printf -- '--- Round 1, 2026-11-13, reviewer: codex (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: %s\n\nSecond review, reviewer: claude (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: %s\n' "$3" "$1" "${4:-$3}" "$2"
}
approve() { printf 'Merge approved: 2026-11-13 for %s (decision room D%s, on the user'"'"'s standing order of 2026-11-13)\n' "$1" "$2"; }
newc() { git -C "$F/demo" commit -q --allow-empty -m "$1" && git -C "$F/demo" rev-parse HEAD; }
prok_setup() { # E-11's passing state
  on
  printf 'Delivery: direct-PR\n' >> "$F/demo/tickets/PROJECT.md"
  C=$(newc c) || fail "commit"
  mkdir -p "$T/notes"; echo "$URL" > "$T/notes/pr.md"
  tst "$C" pass > "$T/notes/test.md"; rev yes yes "$C" > "$T/notes/review.md"
  sa stage "$T" approve-merge "reviewed" >/dev/null || fail "stage"
  decide merge "Merge it?" "Merge it" "Not yet" >/dev/null || fail "decide"
  approve "$C" 1 > "$T/notes/merge.md"
}
prok_passes() {
  local out before
  before=$(snap)
  out=$(sa room pr-ok "$T" 2>&1) || fail "pr-ok refused: $out"
  [ "$out" = "PR-OK: $URL $C" ] || fail "printed: $out"
  [ "$(snap)" = "$before" ] || fail "pr-ok changed a file"
}
prok_refuses() { refuses "$1" sa room pr-ok "$T"; }
set_delivery() { local P="$F/demo/tickets/PROJECT.md"; grep -v '^Delivery:' "$P" > "$P.t"; echo "Delivery: $1" >> "$P.t"; cat "$P.t" > "$P"; rm -f "$P.t"; }

c_prok_pass() { prok_setup; prok_passes; }
c_prok_x_off() { prok_setup; sa room off "$F" "x" >/dev/null; prok_refuses "the decision room is switched off"; }
c_prok_x_local() { prok_setup; set_delivery local-only; prok_refuses "the project does not deliver through pull requests"; }
c_prok_x_no_pr() { prok_setup; rm -f "$T/notes/pr.md"; prok_refuses "no notes/pr.md"; }
c_prok_x_bad_url() { prok_setup; echo 'https://gitlab.com/superagent-fixture/demo/-/merge_requests/7' > "$T/notes/pr.md"; prok_refuses "notes/pr.md does not hold exactly one GitHub pull request URL"; }
c_prok_x_old_approval() {
  local C2
  prok_setup; C2=$(newc c2)
  printf -- '\n--- Round 2, 2026-11-13, reviewer: codex (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n\nSecond review, reviewer: claude (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$C2" "$C2" >> "$T/notes/review.md"
  printf -- '\n--- Round 2, 2026-11-13\nTested commit: %s\nResult: pass\n' "$C2" >> "$T/notes/test.md"
  prok_refuses "the approval is for $C, not the last reviewed commit"
}
c_prok_x_unknown_d() { prok_setup; approve "$C" 9 > "$T/notes/merge.md"; prok_refuses "D9 is not a merge decision with option (a) for demo#001"; }
c_prok_x_option_b() {
  prok_setup
  sa room decide "$T" merge "Merge it?" --option "Merge it" --option "Not yet" --fable b ok --codex b ok >/dev/null || fail "decide b"
  approve "$C" 2 > "$T/notes/merge.md"
  prok_refuses "D2 is not a merge decision with option (a) for demo#001"
}
c_prok_x_test_fail() { prok_setup; tst "$C" fail > "$T/notes/test.md"; prok_refuses "the last test round's result is 'fail'"; }
c_prok_x_review_no() { prok_setup; rev no no "$C" > "$T/notes/review.md"; prok_refuses "a reviewer in the newest round did not allow shipping"; }
c_prok_x_tested_other() { local C2; prok_setup; C2=$(newc c2); tst "$C2" pass > "$T/notes/test.md"; prok_refuses "the tested commit is not the reviewed commit"; }
c_prok_x_stopped() { prok_setup; sa stage "$T" stopped "stopped by the user" >/dev/null; prok_refuses "the ticket is stopped"; }
c_prok_x_open_q() { prok_setup; sa ask "$T" worker "Use A or B?" "use A" "use B" >/dev/null; prok_refuses "the ticket has an open question"; }
c_prok_x_build() { prok_setup; sa stage "$T" build "back" >/dev/null; prok_refuses "the ticket is at stage 'build', not approve-merge or merge"; }

c_prok_unfinished_round() { # round 6, fix 1: every reviewer block of the newest round has its own verdict
  local H='--- Round 2, 2026-11-13, reviewer: codex (fixture)' S='Second review, reviewer: claude (fixture)'
  prok_setup; command cp "$T/notes/review.md" "$D/rev1"
  # the Codex part unfinished, the second review finished
  { cat "$D/rev1"; printf '\n%s\n\n%s\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$H" "$S" "$C"; } > "$T/notes/review.md"
  prok_refuses "the newest review round has no verdict yet"
  # the Codex part finished, the second review only a header
  { cat "$D/rev1"; printf '\n%s\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n\n%s\n' "$H" "$C" "$S"; } > "$T/notes/review.md"
  prok_refuses "the newest review round has no verdict yet"
  # a claude-only round with its header alone
  { cat "$D/rev1"; printf '\n--- Round 2, 2026-11-13, reviewer: claude (fixture; codex unavailable: usage limit)\n'; } > "$T/notes/review.md"
  prok_refuses "the newest review round has no verdict yet"
  # the same in test.md
  command cp "$D/rev1" "$T/notes/review.md"
  printf -- '\n--- Round 2, 2026-11-13\n' >> "$T/notes/test.md"
  prok_refuses "the newest test round has no result yet"
}
c_prok_bad_records() {
  prok_setup; command cp "$T/notes/review.md" "$D/rev1"
  rev yes yes "${C:0:12}" > "$T/notes/review.md"; approve "${C:0:12}" 1 > "$T/notes/merge.md"
  prok_refuses "the last 'Reviewed commit:' of notes/review.md ('${C:0:12}') is not a full commit id"
  command cp "$D/rev1" "$T/notes/review.md"; approve "$C" 1 > "$T/notes/merge.md"
  printf '%s\n%s\n' "$URL" 'https://github.com/superagent-fixture/demo/pull/8' > "$T/notes/pr.md"
  prok_refuses "notes/pr.md does not hold exactly one GitHub pull request URL"
}
c_prok_conflicting_verdicts() {
  prok_setup
  rev yes no "$C" > "$T/notes/review.md"; prok_refuses "a reviewer in the newest round did not allow shipping"
  rev no yes "$C" > "$T/notes/review.md"; prok_refuses "a reviewer in the newest round did not allow shipping"
}
c_prok_one_reviewer() {
  prok_setup
  printf -- '--- Round 1, 2026-11-13, reviewer: codex (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$C" > "$T/notes/review.md"
  prok_refuses "the newest review round does not name both reviewers"
}
override() { printf -- '\n--- Decision room override, 2026-11-13\nThe decision room chose to merge despite the remaining defects (D1)\nReviewed commit: %s\nMax severity: major\nShip allowed: yes\n' "$1"; }
c_prok_override() {
  prok_setup
  { printf -- '--- Round 3, 2026-11-13, reviewer: codex (fixture)\nReviewed commit: %s\nMax severity: major\nShip allowed: no\n' "$C"; override "$C"; } > "$T/notes/review.md"
  prok_passes
  { printf -- '--- Round 3, 2026-11-13, reviewer: codex (fixture)\nReviewed commit: %s\nMax severity: major\nShip allowed: no\n' "$C"; override "$(git -C "$F/demo" rev-parse HEAD~1)"; } > "$T/notes/review.md"
  refuses "" sa room pr-ok "$T"
}
c_prok_ids() {
  local i
  prok_setup   # D1 is the merge decision; now record D2..D10 for other subjects, then D11 merge (a)
  rm -f "$DEC"; sa room decide "$T" other "Clean up?" --option "yes" --option "no" --fable a ok --codex a ok >/dev/null
  for i in 2 3 4 5 6 7 8 9 10; do sa room decide "$T" other "Clean up?" --option "yes" --option "no" --fable a ok --codex a ok >/dev/null; done
  decide merge "Merge it?" "Merge it" "Not yet" | grep -q '^D11:' || fail "want D11"
  approve "$C" 1 > "$T/notes/merge.md"
  prok_refuses "D1 is not a merge decision with option (a) for demo#001"
  approve "$C" 11 > "$T/notes/merge.md"
  prok_passes
}

# --- with the switch off, sa answers as before (N-2) ---------------------------------------------

off_steps() { # off_steps <runner> <workspace>
  local r="$1" w="$2" t="$2/demo/tickets/001-demo-ticket"
  $r stage "$t" build "go"; echo "rc=$?"
  $r ask "$t" worker "Use A or B?" "use A" "use B"; echo "rc=$?"
  $r answer "$t" Q1 "use A"; echo "rc=$?"
  $r stage "$t" resume "answered by the user"; echo "rc=$?"
  $r room decide "$t" Q2 "Keep it?" --option "keep" --option "drop" --fable a ok --codex-unavailable "usage limit"; echo "rc=$?"
  $r gate "$t" "$w/demo" main; echo "rc=$?"
}
# what superagent#007 adds is not what this case compares: a leading badge, the legend line, the two seat badges
mask() { sed -E -e "s#$1#WS#g" -e 's/^(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔) //' -e '/^(# )?Badges: /d' -e 's/^(🟣|🟢) //' -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}/TIME/g' -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/DATE/g' "$2" 2>&1; }
c_off_same_as_base() {
  local F2 f
  git -C "$here" show main:superagent/sa > "$D/sa-base" || fail "no main:superagent/sa"
  F2=$(bash "$here/fixture.sh") || fail "second fixture"
  trap 'drop_dir "$(dirname "$F2")"' EXIT
  sa_base() { bash "$D/sa-base" "$@"; }
  off_steps sa_base "$F2" > "$D/out-base" 2>&1
  off_steps sa "$F" > "$D/out-new" 2>&1
  diff <(mask "$F2" "$D/out-base") <(mask "$F" "$D/out-new") || fail "output differs"
  for f in demo/tickets/001-demo-ticket/notes/questions.md demo/tickets/BOARD.md demo/tickets/001-demo-ticket/rd.md demo/tickets/LOG.md decision-room/demo/DECISIONS.md; do
    diff <(mask "$F2" "$F2/$f") <(mask "$F" "$F/$f") || fail "$f differs"
  done
  # the room log differs only by the text superagent#005 adds: the options, the question and who answered
  diff <(mask "$F2" "$F2/decision-room/demo/LOG.md" | sed \
      -e 's/: Q1 from worker: Use A or B?$/& | options: (a) use A (recommended); (b) use B/' \
      -e 's/| Q1 answered: use A$/| Q1 answered by the user: use A | question: Use A or B?/' \
      -e 's/| D1 (Q2): (a) keep;/| D1 (Q2): Keep it? -> (a) keep;/') \
    <(mask "$F" "$F/decision-room/demo/LOG.md") || fail "decision-room/demo/LOG.md differs beyond superagent#005's additions"
}

c_help() {
  local h c
  h=$(sa help)
  for c in 'ask .*--access' 'room on' 'room off' 'room status' 'room owner' 'room pr-ok'; do
    printf '%s\n' "$h" | grep -q -- "$c" || fail "help lacks '$c'"
  done
}

run_case "switch: status, on, off, on; bad input refused" c_switch
run_case "switch: status reads the same from any folder under the workspace" c_switch_any_path
run_case "switch on the live eight-line preferences" c_switch_real_prefs
run_case "switch notes reach every project once" c_switch_logs
run_case "switch notes reach a Room: project named on the line" c_switch_room_project
run_case "a switch note that cannot be written is reported" c_switch_note_fails
run_case "switch text: repeats, quotes, refusals, own lock" c_switch_text
run_case "an access question records what was tried and the room refuses it" c_owner_access_q
run_case "a question marked owner-only later is refused" c_owner_marked_later
run_case "a draft question marked (access) is refused" c_owner_draft
run_case "a fact only the owner knows is refused" c_owner_fact
run_case "a plain investigation question is decided" c_room_investigation
run_case "an open owner-only question blocks every subject" c_owner_blocks_all_subjects
run_case "an owner-only suggestion is refused" c_owner_suggestion
run_case "a stopped ticket is refused" c_decide_stopped
run_case "a stop landing while room decide waits is refused" c_decide_waits_stop
run_case "an owner-only mark landing while room decide waits is refused" c_decide_waits_owner
run_case "room owner marks an unmarked draft question" c_owner_draft_mark
run_case "no seat leaves the question open" c_no_seat
run_case "a non-approval is logged; a room undo names D<n>" c_rules_carry_out
run_case "the rules name what stays the owner's" c_rules
run_case "plan approved by the room" c_plan_by_room
run_case "gate passes with a room-approved plan" c_gate_room_plan
run_case "gate fails without a plan approval" c_gate_no_plan
run_case "gate fails without a passing test" c_gate_no_test
run_case "gate fails when the review says no" c_gate_review_no
run_case "gate fails with an open question" c_gate_open_q
run_case "pr-ok passes when everything holds" c_prok_pass
run_case "pr-ok refuses with the switch off" c_prok_x_off
run_case "pr-ok refuses Delivery: local-only" c_prok_x_local
run_case "pr-ok refuses without notes/pr.md" c_prok_x_no_pr
run_case "pr-ok refuses a pr.md that is not a GitHub pull request URL" c_prok_x_bad_url
run_case "pr-ok refuses an approval for an older commit" c_prok_x_old_approval
run_case "pr-ok refuses an approval naming an unrecorded decision" c_prok_x_unknown_d
run_case "pr-ok refuses a merge decision with option (b)" c_prok_x_option_b
run_case "pr-ok refuses a failed test" c_prok_x_test_fail
run_case "pr-ok refuses a review that says no" c_prok_x_review_no
run_case "pr-ok refuses a tested commit other than the reviewed one" c_prok_x_tested_other
run_case "pr-ok refuses a stopped ticket" c_prok_x_stopped
run_case "pr-ok refuses an open question" c_prok_x_open_q
run_case "pr-ok refuses a ticket at build" c_prok_x_build
run_case "pr-ok refuses an unfinished newest round" c_prok_unfinished_round
run_case "pr-ok refuses a short commit id and two URLs" c_prok_bad_records
run_case "pr-ok refuses conflicting verdicts" c_prok_conflicting_verdicts
run_case "pr-ok refuses one reviewer" c_prok_one_reviewer
run_case "pr-ok follows a valid override" c_prok_override
run_case "pr-ok matches the decision id exactly" c_prok_ids
run_case "switched off, sa answers as the base sa" c_off_same_as_base
run_case "help lists the new commands" c_help
