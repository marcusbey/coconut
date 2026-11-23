#!/usr/bin/env bash
# room-badges.test.sh: every line sa writes to a room log or to tickets/LOG.md starts with the badge of the
# agent role behind it; the two seats of a decision and each new log, record and index carry theirs; old
# lines and old files are never touched, and every reader takes old and new lines (superagent#007).
# Every case runs on its own throwaway fixture (fixture.sh), never on a real workspace.
# The old format is written by hand here, never by `git show main:superagent/sa`, so a case holds after this
# ticket has landed and main's sa is the badged one; the cases that compare with main's sa compare output
# or the content apart from the badges.
set -u
unset SA_ROLE   # a case sets it for one call at a time
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }   # through bash: a copy from `git show` is not executable
AG="$here/../../agents"; PROTO="$here/../PROTOCOL.md"
B='(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔)'
BADGES='🧭 🏛️ ✍️ 🔨 🤝 🐞 🧪 🔍 🔀 🌐 🐶 👤 ❔'
STAMP='[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}'
WORDS='the room decides everything; only what needs a login, access or the like reaches me, and only after computer use was tried and blocked.'
URL='https://github.com/superagent-fixture/demo/pull/7'
Q='Use A or B?'

F=""; D=""; T=""; TK=""; R=""; LOG=""; DEC=""; TL=""; C=""; F2=""
fail() { echo "$*"; exit 1; }
count() { grep -c "$@" 2>/dev/null || true; }
lines() { if [ -f "$1" ]; then grep -vc '^# ' "$1" || true; else echo 0; fi; }   # entries: the legend line is not one
drop_dir() { # only a fixture folder, made writable again first (a case may have locked it)
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); TK="$F/demo/tickets"; T="$TK/001-demo-ticket"; TL="$TK/LOG.md"
  R="$F/decision-room/demo"; LOG="$R/LOG.md"; DEC="$R/DECISIONS.md"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}
sa_base() { # the sa of the base branch: before this ticket lands the old one, after it the badged one
  [ -s "$D/sa-base" ] || git -C "$here" show main:superagent/sa > "$D/sa-base" || fail "no main:superagent/sa"
  bash "$D/sa-base" "$@"
}
second_fixture() { # a second fixture for the base sa; its folder is dropped when the case ends
  F2=$(bash "$here/fixture.sh") || fail "second fixture"
  trap 'drop_dir "$(dirname "$F2")"' EXIT
}

# room_is <badge> <kind> [<text>]: the newest line of the room log is "<badge> <date> | <ref> | <kind> | <text>"
room_is() {
  local line rest sep=" | $2 | " txt
  line=$(tail -1 "$LOG")
  case "$line" in "$1 "*) rest=${line#"$1 "} ;; *) fail "want the badge $1 first: $line" ;; esac
  printf '%s\n' "$rest" | grep -qE "^$STAMP \\| [^|]+ \\| $2 \\| " || fail "after the badge, not '<date> | <ref> | $2 | ...': $line"
  [ $# -ge 3 ] || return 0
  txt=${rest#*"$sep"}
  [ "$txt" = "$3" ] || fail "text: want '$3', got '$txt'"
}
# tk_is <badge> <move> <note>: the newest line of tickets/LOG.md is "<badge> <date> | 001 | <move> | <note>"
tk_is() {
  local line rest sep=" | 001 | " txt
  line=$(tail -1 "$TL")
  case "$line" in "$1 "*) rest=${line#"$1 "} ;; *) fail "tickets/LOG.md: want the badge $1 first: $line" ;; esac
  printf '%s\n' "$rest" | grep -qE "^$STAMP \\| 001 \\| " || fail "tickets/LOG.md: after the badge, not '<date> | 001 | ...': $line"
  txt=${rest#*"$sep"}
  [ "$txt" = "$2 | $3" ] || fail "tickets/LOG.md: want '$2 | $3', got '$txt'"
}
legend_count() { # the lines of <file> that name every one of the 13 badges
  awk -v list="$BADGES" 'BEGIN { n = split(list, b, " ") } { k = 0; for (i = 1; i <= n; i++) if (index($0, b[i])) k++; if (k == n) c++ } END { print c + 0 }' "$1"
}
legend_line() { # the first line of <file> that names every one of the 13 badges
  awk -v list="$BADGES" 'BEGIN { n = split(list, b, " ") } { k = 0; for (i = 1; i <= n; i++) if (index($0, b[i])) k++; if (k == n) { print; exit } }' "$1"
}
block() { awk -v h="## D$1" '$0==h {f=1; next} /^## /{f=0} f' "$DEC"; }
decide() { sa room decide "$T" "$1" "$Q" --option "use A" --option "use B" --fable a "x" --codex a "y"; }

# --- E-1: each role argument gives its badge ------------------------------------------------------

c_e1_roles() {
  local pair who badge
  for pair in router:🧭 decision-room:🏛️ clerk:✍️ ticket-writer:✍️ worker:🔨 teammate:🤝 reproducer:🐞 tester:🧪 \
              codex-reviewer:🔍 reviewer:🔍 merger:🔀 checker:🌐 watchdog:🐶 follow-up:🐶 user:👤 owner:👤; do
    who=${pair%%:*}; badge=${pair#*:}
    sa room event "$T" dispatch "$who" "x" >/dev/null || fail "$who: room event failed"
    room_is "$badge" dispatch "$who: x"
  done
  # the case of the name does not matter, a decision room may name its decision, and "the user" is the user
  for pair in 'Worker:🔨' 'TESTER:🧪' 'Codex-Reviewer:🔍' 'Decision Room D3:🏛️' 'decision room (D7):🏛️' 'decision room:🏛️' \
              'decision-room D12:🏛️' 'the user:👤' 'The User:👤'; do
    who=${pair%%:*}; badge=${pair#*:}
    sa room event "$T" report "$who" "ready: x" >/dev/null || fail "$who: room event failed"
    room_is "$badge" report "$who: ready: x"
  done
}

# --- E-2: the other role sources ------------------------------------------------------------------

c_e2_sources() {
  sa ask "$T" tester "q?" "a" "b" >/dev/null || fail "ask"
  room_is 🧪 question 'ready/- -> blocked/-: Q1 from tester: q? | options: (a) a (recommended); (b) b'
  tk_is 🧪 'ready/- -> blocked/-' 'question Q1 from tester'
  sa answer "$T" Q1 "a" >/dev/null || fail "answer"
  room_is 👤 answer 'Q1 answered by the user: a | question: q?'
  sa ask "$T" worker "q2?" "a" "b" >/dev/null || fail "second ask"
  room_is 🔨 question 'blocked/- -> blocked/-: Q2 from worker: q2? | options: (a) a (recommended); (b) b'
  sa answer "$T" Q2 "b" --by "decision room D3" >/dev/null || fail "answer --by"
  room_is 🏛️ answer 'Q2 answered by decision room D3: b | question: q2?'
  sa suggest "$TK" "demo#001 reviewer" "idea" "evidence" >/dev/null || fail "suggest"
  room_is 🔍 suggestion 'S1 from demo#001 reviewer: idea'
  sa learn "$TK" "demo#001 merger" "trap" >/dev/null || fail "learn"
  room_is 🔀 lesson 'from demo#001 merger: trap'
  sa learn "$TK" worker "a role with no ticket in front" >/dev/null || fail "learn with a bare role"
  room_is 🔨 lesson 'from worker: a role with no ticket in front'
  SA_ROLE=worker sa stage "$T" build "x" >/dev/null || fail "stage"
  room_is 🔨 stage
  tk_is 🔨 'blocked/- -> in-progress/build' x
  SA_ROLE=checker sa room note "$T" nobody "x" >/dev/null || fail "note"
  room_is 🌐 note 'nobody: x'
  decide Q1 >/dev/null || fail "decide"
  room_is 🏛️ decision 'D1 (Q1): Use A or B? -> (a) use A; decided by both'
}

# --- FR-4: the order named role, SA_ROLE, the command's own role, unknown ----------------------------

c_order() {
  SA_ROLE=worker sa room note "$T" tester "x" >/dev/null || fail "note"
  room_is 🧪 note 'tester: x'                                   # the role the command names beats SA_ROLE
  SA_ROLE=worker sa room note "$T" stranger "x" >/dev/null || fail "note"
  room_is 🔨 note 'stranger: x'                                 # a named role that is not in the table falls through
  SA_ROLE=nobody sa room note "$T" stranger "x" >/dev/null || fail "note"
  room_is ❔ note 'stranger: x'                                  # unknown everywhere
  SA_ROLE=Worker sa room note "$T" stranger "x" >/dev/null || fail "note"
  room_is 🔨 note 'stranger: x'                                 # SA_ROLE is read without regard to case
  sa ask "$T" worker "q?" "a" "b" >/dev/null || fail "ask"
  SA_ROLE=clerk sa answer "$T" Q1 "a" >/dev/null || fail "answer"
  room_is 👤 answer 'Q1 answered by the user: a | question: q?'   # the default "the user" is a named role
  SA_ROLE=nobody decide Q1 >/dev/null || fail "decide"
  room_is 🏛️ decision                                           # the command's own role, after an unusable SA_ROLE
  SA_ROLE=worker decide Q1 >/dev/null || fail "decide"
  room_is 🔨 decision                                           # SA_ROLE comes before the command's own role
}

# --- E-3: every kind of line is badged ---------------------------------------------------------------

c_e3_kinds() {
  local k all badged h m
  sa stage "$T" research "go" >/dev/null || fail "stage"
  sa ask "$T" worker "$Q" "use A" "use B" >/dev/null || fail "ask"
  sa answer "$T" Q1 "use A" >/dev/null || fail "answer"
  sa suggest "$TK" "demo#001 worker" "Add a retry" "seen in x.sh:3" >/dev/null || fail "suggest"
  sa learn "$TK" "demo#001 worker" "the flaky test needs TZ=UTC" >/dev/null || fail "learn"
  sa suggest-close "$TK" S1 dismissed "not now" >/dev/null || fail "suggest-close"
  sa qa "$T" "open the app -> it starts" >/dev/null || fail "qa"
  sa qa-pass "$T" >/dev/null || fail "qa-pass"
  sa room note "$T" clerk "set Model: opus in rd.md" >/dev/null || fail "note"
  decide Q1 >/dev/null || fail "decide"
  sa room event "$T" dispatch worker "started by router: stage build, model opus, effort high" >/dev/null || fail "dispatch"
  sa room event "$T" report worker "ready: done" >/dev/null || fail "report"
  sa stage "$T" resume "answered" >/dev/null || fail "resume"
  git -C "$F/demo" worktree add -q "$D/wt" -b ticket/001-demo-ticket main || fail "worktree"
  echo x > "$D/wt/feature.txt"
  git -C "$D/wt" add feature.txt && git -C "$D/wt" commit -q -m "feat: x" || fail "commit"
  h=$(git -C "$D/wt" rev-parse HEAD)
  mkdir -p "$T/notes"
  printf -- '--- Round 1, 2026-01-01\nTested commit: %s\nBase: main @ x\nResult: pass\n' "$h" > "$T/notes/test.md"
  printf -- '--- Round 1, 2026-01-01, reviewer: codex (fixture)\nSecond review, reviewer: claude (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$h" > "$T/notes/review.md"
  sa land "$T" "$D/wt" main >/dev/null || fail "land"
  m=$(git -C "$F/demo" rev-parse main)
  room_is 🔀 landing "$m on main"                                 # sa land's own role
  for k in stage question answer suggestion lesson check landing note decision dispatch report; do
    [ "$(count " | $k | " "$LOG")" -ge 1 ] || fail "no $k line in the log: $(cat "$LOG")"
  done
  all=$(grep -vc '^# ' "$LOG" || true); badged=$(grep -cE "^$B $STAMP \\| " "$LOG" || true)
  [ "$all" = "$badged" ] && [ "$all" -ge 13 ] || fail "$all entry lines, $badged badged: $(grep -vE "^# |^$B $STAMP \\| " "$LOG")"
}

# --- E-4: tickets/LOG.md lines are badged -------------------------------------------------------------

c_e4_tickets_log() {
  SA_ROLE=tester sa stage "$T" test "x" >/dev/null || fail "stage"
  tail -1 "$TL" | grep -qE "^🧪 $STAMP \\| 001 \\| [^|]+ -> [^|]+ \\| x\$" || fail "tickets/LOG.md line: $(tail -1 "$TL")"
  tk_is 🧪 'ready/- -> review/test' x
  room_is 🧪 stage 'ready/- -> review/test: x'
  sa stage "$T" build "no role" >/dev/null || fail "stage"
  tk_is ❔ 'review/test -> in-progress/build' 'no role'
}

# --- E-5: the two seats of a decision ------------------------------------------------------------------

c_e5_seats() {
  local args=(Q1 "$Q" --option "use A" --option "use B" --fable a "r1" --codex b "r2" --safer a "A is easier to undo")
  second_fixture
  sa room decide "$T" "${args[@]}" >/dev/null || fail "decide"
  sa_base room decide "$F2/demo/tickets/001-demo-ticket" "${args[@]}" >/dev/null || fail "base decide"
  grep -qxF '## D1' "$DEC" && [ "$(count '^## ' "$DEC")" = 1 ] || fail "the header is not exactly '## D1': $(grep '^## ' "$DEC")"
  block 1 | grep -qxF '🟣 Fable 5.2: a: r1' || fail "no '🟣 Fable 5.2: a: r1': $(block 1)"
  block 1 | grep -qxF '🟢 Codex Astra: b: r2' || fail "no '🟢 Codex Astra: b: r2': $(block 1)"
  [ "$(block 1 | grep -c 'Fable 5.2:')" = 1 ] && [ "$(block 1 | grep -c 'Codex Astra:')" = 1 ] || fail "a seat line twice: $(block 1)"
  # every other line of the record is what the base sa writes for the same call, apart from the date
  norm() { sed -E -e 's/^Date: .*/Date: X/' -e 's/^(🟣|🟢) //'; }
  block 1 | norm > "$D/blk-new"
  awk -v h="## D1" '$0==h {f=1; next} /^## /{f=0} f' "$F2/decision-room/demo/DECISIONS.md" | norm > "$D/blk-base"
  [ -s "$D/blk-base" ] || fail "the base sa wrote no record"
  diff "$D/blk-base" "$D/blk-new" || fail "the record differs from the base sa's beyond the seat badges"
  grep -qxE "Date: $STAMP" <(block 1) || fail "no Date: line"
  # a seat that is out is badged too
  sa room decide "$T" Q2 "$Q" --option "use A" --option "use B" --fable a "why" --codex-unavailable "usage limit" >/dev/null || fail "second decide"
  block 2 | grep -qxF '🟣 Fable 5.2: a: why' && block 2 | grep -qxF '🟢 Codex Astra: unavailable: usage limit' || fail "second record: $(block 2)"
}

# --- E-6: legends ------------------------------------------------------------------------------------------

c_e6_legends() {
  local f leg p
  sa stage "$T" research a >/dev/null || fail "stage"
  decide Q1 >/dev/null || fail "decide"
  sa room index "$F" >/dev/null || fail "index"
  for f in "$LOG" "$DEC" "$TL" "$F/decision-room/INDEX.md"; do
    [ "$(legend_count "$f")" = 1 ] || fail "$f: want exactly one legend line, got $(legend_count "$f"): $(head -8 "$f")"
  done
  leg=$(legend_line "$LOG")
  for p in '🧭 router' '🏛️ decision-room' '✍️ clerk' '🔨 worker' '🤝 teammate' '🐞 reproducer' '🧪 tester' '🔍 reviewer' '🔀 merger' '🌐 checker' '🐶 watchdog' '👤 user'; do
    case "$leg" in *"$p"*) ;; *) fail "the legend does not name '$p': $leg" ;; esac
  done
  [ "$(sed -n 1p "$LOG")" = "$leg" ] && case "$leg" in '# '*) true ;; *) false ;; esac || fail "in LOG.md the legend is not the first line, starting '# ': $(head -2 "$LOG")"
  [ "$(count '^# ' "$LOG")" = 1 ] || fail "LOG.md: want one line starting '# '"
  [ "$(legend_line "$DEC")" = "${leg#\# }" ] && [ "$(legend_line "$TL")" = "${leg#\# }" ] && [ "$(legend_line "$F/decision-room/INDEX.md")" = "${leg#\# }" ] ||
    fail "the legends differ from one another"
  # writing on never repeats it, and a regenerated index still holds one
  sa stage "$T" plan b >/dev/null || fail "second stage"
  decide Q2 >/dev/null || fail "second decide"
  sa room index "$F" >/dev/null || fail "second index"
  for f in "$LOG" "$DEC" "$TL" "$F/decision-room/INDEX.md"; do
    [ "$(legend_count "$f")" = 1 ] || fail "$f: after more writes, want one legend line, got $(legend_count "$f")"
  done
  [ "$(lines "$LOG")" = 4 ] || fail "LOG.md: want 4 entries (stage, decision, stage, decision), got $(lines "$LOG")"
}

# --- X-1: no role at all -------------------------------------------------------------------------------------

c_x1_no_role() {
  local out rc want wrc
  second_fixture
  out=$(sa stage "$T" build "x" 2>&1); rc=$?
  want=$(sa_base stage "$F2/demo/tickets/001-demo-ticket" build "x" 2>&1); wrc=$?
  [ "$rc" = 0 ] && [ "$wrc" = 0 ] && [ "$out" = "$want" ] || fail "rc $rc/$wrc, output '$out' / '$want'"
  room_is ❔ stage 'ready/- -> in-progress/build: x'
  tk_is ❔ 'ready/- -> in-progress/build' x
}

# --- X-2: an unknown or hostile SA_ROLE ---------------------------------------------------------------------

c_x2_hostile() {
  local v out rc line n
  for v in "$(printf 'x | y\nz')" nobody "worker | evil" "$(printf 'worker\nrouter')" "decision roomer" "\$(touch $D/sa-hostile)" '*' 'worker,tester' ''; do
    n=$(lines "$LOG")
    out=$(SA_ROLE="$v" sa stage "$T" build "x" 2>&1); rc=$?
    [ "$rc" = 0 ] || fail "SA_ROLE '$v': exit $rc: $out"
    room_is ❔ stage
    [ "$(lines "$LOG")" = $((n + 1)) ] || fail "SA_ROLE '$v': want one new line, got $(lines "$LOG") from $n: $(cat "$LOG")"
    for line in "$(tail -1 "$LOG")" "$(tail -1 "$TL")"; do
      [ "$(printf '%s\n' "$line" | awk -F' [|] ' '{print NF}')" = 4 ] || fail "SA_ROLE '$v': not four fields: $line"
      case "$line" in *evil*|*nobody*|*roomer*|*touch*|*tester*) fail "SA_ROLE's text got into the line: $line" ;; esac
    done
    [ "$(grep -vcE "^# |^$B $STAMP \\| " "$LOG" || true)" = 0 ] || fail "SA_ROLE '$v': a line is neither the legend nor badged: $(cat "$LOG")"
  done
  [ ! -e "$D/sa-hostile" ] || fail "SA_ROLE was run as code"
}

# --- X-3: old files stay as they are ---------------------------------------------------------------------------

c_x3_old_files() {
  local n_log n_tk n_dec
  mkdir -p "$R"
  cat > "$LOG" <<'EOF'
2026-11-13 09:12 | demo#001 | stage | ready/- -> in-progress/build: worker starts
2026-11-13 09:40 | demo#001 | note | clerk: an old note
EOF
  cat > "$TL" <<'EOF'
# Log

One line per state change, newest last. Written by `sa`; do not edit.

2026-11-13 09:12 | 001 | ready/- -> in-progress/build | worker starts
EOF
  cat > "$DEC" <<'EOF'
# Decisions: demo

One block per decision of the decision room, newest last. Written by `sa room decide`; do not edit.

## D1
Date: 2026-11-13 10:00
Ticket: demo#001
Subject: Q1
Question: Use A or B?
Options:
(a) use A
(b) use B
Fable 5.2: a: old reasoning
Codex Astra: a: old reasoning
Decision: (a) use A
Decided by: both
EOF
  command cp "$LOG" "$D/old-log"; command cp "$TL" "$D/old-tl"; command cp "$DEC" "$D/old-dec"
  n_log=$(wc -l < "$D/old-log" | tr -d ' '); n_tk=$(wc -l < "$D/old-tl" | tr -d ' '); n_dec=$(wc -l < "$D/old-dec" | tr -d ' ')
  SA_ROLE=worker sa stage "$T" test "x" >/dev/null || fail "stage"
  out=$(SA_ROLE=decision-room decide Q2) || fail "decide: $out"
  [ "$out" = "D2: (a) use A; decided by both" ] || fail "the old record was not counted: $out"
  head -n "$n_log" "$LOG" | diff - "$D/old-log" || fail "old room log lines changed"
  head -n "$n_tk" "$TL" | diff - "$D/old-tl" || fail "old tickets/LOG.md lines changed"
  head -n "$n_dec" "$DEC" | diff - "$D/old-dec" || fail "old DECISIONS.md changed"
  for f in "$LOG" "$TL" "$DEC"; do [ "$(legend_count "$f")" = 0 ] || fail "a legend was added to the old $f"; done
  [ "$(count '^# ' "$LOG")" = 0 ] || fail "a '# ' line was added to the old room log"
  room_is 🏛️ decision 'D2 (Q2): Use A or B? -> (a) use A; decided by both'
  grep -E " \\| demo#001 \\| stage \\| " "$LOG" | tail -1 | grep -qE "^🔨 $STAMP " || fail "the new stage line is not badged: $(cat "$LOG")"
  tk_is 🔨 'ready/- -> review/test' x
  block 2 | grep -qxF '🟣 Fable 5.2: a: x' || fail "the new record has no seat badge: $(block 2)"
}

# --- N-2: the readers take old and new lines ---------------------------------------------------------------------

prok_setup() { # a ticket that passes sa room pr-ok once merge.md names a merge decision
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "room on"
  printf 'Delivery: direct-PR\n' >> "$TK/PROJECT.md"
  git -C "$F/demo" commit -q --allow-empty -m c || fail "commit"
  C=$(git -C "$F/demo" rev-parse HEAD)
  mkdir -p "$T/notes"; echo "$URL" > "$T/notes/pr.md"
  printf -- '--- Round 1, 2026-11-13\nTested commit: %s\nBase: main @ %s\nResult: pass\n' "$C" "$C" > "$T/notes/test.md"
  printf -- '--- Round 1, 2026-11-13, reviewer: codex (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n\nSecond review, reviewer: claude (fixture)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n' "$C" "$C" > "$T/notes/review.md"
  sa stage "$T" approve-merge "reviewed" >/dev/null || fail "stage"
}
c_n2_readers() {
  local out n
  mkdir -p "$R"
  cat > "$DEC" <<'EOF'
# Decisions: demo

One block per decision of the decision room, newest last. Written by `sa room decide`; do not edit.

## D1
Date: 2026-11-13 10:00
Ticket: demo#001
Subject: merge
Question: Merge it?
Options:
(a) Merge it
(b) Not yet
Fable 5.2: a: ok
Codex Astra: a: ok
Decision: (a) Merge it
Decided by: both
EOF
  prok_setup
  out=$(sa room decide "$T" merge "Merge it?" --option "Merge it" --option "Not yet" --fable a ok --codex a ok) || fail "decide: $out"
  [ "$out" = "D2: (a) Merge it; decided by both" ] || fail "after an old block, want D2: $out"
  out=$(decide Q1) || fail "decide: $out"
  [ "$out" = "D3: (a) use A; decided by both" ] || fail "after an old and a new block, want D3: $out"
  block 2 | grep -qxF '🟣 Fable 5.2: a: ok' || fail "D2 is not a new-format record: $(block 2)"
  for n in 1 2; do   # the old block, then the new one
    printf 'Merge approved: 2026-11-13 for %s (decision room D%s, on the user'"'"'s standing order of 2026-11-13)\n' "$C" "$n" > "$T/notes/merge.md"
    out=$(sa room pr-ok "$T" 2>&1); [ $? = 0 ] && [ "$out" = "PR-OK: $URL $C" ] || fail "pr-ok for D$n: $out"
  done
  printf 'Merge approved: 2026-11-13 for %s (decision room D3, on the user'"'"'s standing order of 2026-11-13)\n' "$C" > "$T/notes/merge.md"
  out=$(sa room pr-ok "$T" 2>&1) && fail "pr-ok accepted D3, which is not a merge decision: $out"
  printf '%s\n' "$out" | grep -qF 'D3 is not a merge decision with option (a) for demo#001' || fail "pr-ok refused D3 for another reason: $out"
}
c_n2_index() { # the index lists what the base sa lists, and holds one more line: the legend
  local I="$F/decision-room/INDEX.md" strip
  printf '| 002 | done-ticket | done | solo | alongside | done |\n' >> "$TK/BOARD.md"
  sa ask "$T" worker "$Q" "use A" "use B" >/dev/null || fail "ask"
  sa_base room index "$F" >/dev/null || fail "base index"
  command cp "$I" "$D/index-base"
  sa room index "$F" >/dev/null || fail "index"
  strip() { grep -v '^Generated:' "$1" | awk -v list="$BADGES" 'BEGIN { n = split(list, b, " ") } { k = 0; for (i = 1; i <= n; i++) if (index($0, b[i])) k++; if (k < n) print }'; }
  diff <(strip "$D/index-base") <(strip "$I") || fail "the index differs from the base sa's beyond the time and the legend"
  grep -qx 'Open questions: 1' "$I" && grep -qx -- '- 001 demo-ticket: blocked/-' "$I" || fail "open ticket or question missing: $(cat "$I")"
  grep -q 'done-ticket' "$I" && fail "a done ticket is listed"
  return 0
}

# --- the legend is written once -----------------------------------------------------------------------------------

c_legend_once() { # writers of one new log from two tickets folders: the one that creates it writes the legend, no one else
  local O="$D/outside" i
  printf 'Room: %s\n' "$F/decision-room" >> "$O/tickets/PROJECT.md"
  sed -i.bak 's/^# Project: outside$/# Project: demo/' "$O/tickets/PROJECT.md"
  for i in 1 2 3 4 5 6; do
    sa room event "$T" dispatch worker "a$i" >/dev/null &
    sa room event "$O/tickets" report watchdog "waiting: router: b$i" >/dev/null &
  done
  wait
  [ "$(lines "$LOG")" = 12 ] || fail "want 12 entries: $(cat "$LOG")"
  [ "$(legend_count "$LOG")" = 1 ] && [ "$(count '^# ' "$LOG")" = 1 ] || fail "want one legend line: $(grep -n '^# ' "$LOG")"
  case "$(sed -n 1p "$LOG")" in '# '*) ;; *) fail "the first line is not the legend: $(sed -n 1p "$LOG")" ;; esac
  [ "$(grep -vcE "^# |^$B $STAMP \\| " "$LOG" || true)" = 0 ] || fail "a line is neither the legend nor badged: $(grep -vE "^# |^$B $STAMP \\| " "$LOG")"
}
c_legend_retry() { # a first write that failed, or was cut back, leaves nothing half and the next write its legend
  local out rc big
  mkdir -p "$F/decision-room"; chmod 555 "$F/decision-room"   # demo's room folder cannot be made
  out=$(sa room event "$T" dispatch worker "x" 2>&1); rc=$?
  chmod 755 "$F/decision-room"
  [ "$rc" = 0 ] && [ "$out" = "note: could not write the decision-room log" ] || fail "rc $rc, printed: '$out'"
  [ ! -e "$LOG" ] || fail "a log was written: $(cat "$LOG")"
  sa room event "$T" dispatch worker "y" >/dev/null || fail "the next event failed"
  case "$(sed -n 1p "$LOG")" in '# '*) ;; *) fail "no legend on the first successful write: $(cat "$LOG")" ;; esac
  [ "$(lines "$LOG")" = 1 ] && [ "$(legend_count "$LOG")" = 1 ] || fail "want the legend and one entry: $(cat "$LOG")"
  rm -f "$LOG"
  big=$(head -c 3000 /dev/zero | tr '\0' 'y')
  out=$( trap '' XFSZ; ulimit -f 1; sa room event "$T" dispatch worker "$big" 2>&1 ); rc=$?   # stops the append part way
  [ "$rc" = 0 ] && [ "$out" = "note: could not write the decision-room log" ] || fail "cut write: rc $rc, printed: '$out'"
  [ ! -s "$LOG" ] || fail "a cut first write left bytes: $(head -c 200 "$LOG")"
  sa room event "$T" dispatch worker "z" >/dev/null || fail "the event after the cut failed"
  [ "$(legend_count "$LOG")" = 1 ] && [ "$(lines "$LOG")" = 1 ] && case "$(sed -n 1p "$LOG")" in '# '*) true ;; *) false ;; esac || fail "after a cut first write: $(cat "$LOG")"
  room_is 🔨 dispatch 'worker: z'
}

# --- N-4: the watchdog ----------------------------------------------------------------------------------------------

c_n4_watchdog() { # watchdog.sh reads no log line: with badged logs it finds what the base watchdog finds
  local a b
  SA_ROLE=worker sa stage "$T" build "go" >/dev/null || fail "stage"
  [ -s "$LOG" ] && [ -s "$TL" ] || fail "no logs to read"
  git -C "$here" show main:superagent/watchdog.sh > "$D/watchdog-base.sh" || fail "no main:superagent/watchdog.sh"
  a=$(SA_STATE_DIR="$D/state-a" bash "$D/watchdog-base.sh" "$F" 0 0 2>&1; echo "rc=$?")
  b=$(SA_STATE_DIR="$D/state-b" bash "$here/../watchdog.sh" "$F" 0 0 2>&1; echo "rc=$?")
  printf '%s\n' "$b" | grep -q '^PROBLEM: \[demo\] 001' || fail "the comparison is empty, no finding: $b"
  [ "$a" = "$b" ] || fail "different findings: base '$a', now '$b'"
  printf '%s\n' "$b" | tail -1 | grep -qx 'rc=0' || fail "exit status: $b"
}

# --- E-7: the role files and PROTOCOL.md ------------------------------------------------------------------------------

c_e7_role_files() {
  local r bd
  for r in router ticket-writer worker teammate reproducer tester codex-reviewer merger checker watchdog decision-room; do
    grep -qF "SA_ROLE=$r ~/.claude/superagent/sa" "$AG/$r.md" || fail "$r.md has no 'SA_ROLE=$r ~/.claude/superagent/sa'"
  done
  grep -qF 'SA_ROLE=clerk ~/.claude/superagent/sa' "$AG/ticket-writer.md" || fail "ticket-writer.md has no 'SA_ROLE=clerk ~/.claude/superagent/sa' for its clerk modes"
  [ "$(count 'SA_ROLE' "$PROTO")" -ge 1 ] || fail "PROTOCOL.md does not mention SA_ROLE"
  grep -qF '`<badge> <YYYY-MM-DD HH:MM> | <ref> | <kind> | <text>`' "$PROTO" || fail "PROTOCOL.md does not show the new line format"
  for bd in $BADGES; do grep -qF "$bd" "$PROTO" || fail "PROTOCOL.md does not show the badge $bd"; done
  for bd in 🟣 🟢; do grep -qF "$bd" "$PROTO" || fail "PROTOCOL.md does not show the seat badge $bd"; done
  grep -qiF 'legend' "$PROTO" || fail "PROTOCOL.md does not describe the legend"
}

run_case "E-1 each role argument gives its badge in the room log" c_e1_roles
run_case "E-2 ask, answer, suggest, learn, SA_ROLE and decide give theirs" c_e2_sources
run_case "FR-4 the named role comes before SA_ROLE, then the command's own role" c_order
run_case "E-3 every kind of room line is badged" c_e3_kinds
run_case "E-4 tickets/LOG.md lines are badged" c_e4_tickets_log
run_case "E-5 the decision seats carry their badges, the rest of the record is as before" c_e5_seats
run_case "E-6 each new log, record and index starts with one legend" c_e6_legends
run_case "X-1 no role at all: the same output, the unknown badge" c_x1_no_role
run_case "X-2 an unknown or hostile SA_ROLE gives the unknown badge and no extra field" c_x2_hostile
run_case "X-3 old files are not rewritten, get no legend, and the new lines are badged" c_x3_old_files
run_case "N-2 old and new records: numbering and the PR guard" c_n2_readers
run_case "N-2 the index lists what the base sa lists, plus the legend" c_n2_index
run_case "the legend is written once, whoever creates the log" c_legend_once
run_case "a failed or cut first write leaves the next one its legend" c_legend_retry
run_case "N-4 the watchdog finds the same with badged logs" c_n4_watchdog
run_case "E-7 role files and PROTOCOL.md name SA_ROLE, the format and the badges" c_e7_role_files
