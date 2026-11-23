#!/usr/bin/env bash
# room-watch.test.sh: `sa room watch`, the coloured live view of the decision-room logs (superagent#010).
# Every case runs on its own throwaway fixture (fixture.sh) and watches only that fixture's room, never a real
# workspace. The logs come from tests/room-watch/room/, written by hand: two projects (one nested), several agents,
# a decision, a landing, a blocked and a failed stage, a failed and a refused report, a legend line, a blank line,
# a line with no badge, a line with the unknown badge and a line holding an ESC, a CR and a TAB. What they must give
# is in tests/room-watch/expected-plain.txt and expected-color.txt (COLUMNS=60, --since 99999999), written from the
# ticket's rules. A watch runs in the background and is stopped by its case; a watch that is slow or gone fails the case.
set -u
unset SA_ROLE NO_COLOR COLUMNS
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
S=$SA_UNDER_TEST
FX="$here/room-watch"
ESC=$(printf '\033')
LAST='ticket 002 is stuck'    # the text of the last line of the fixture in time order: the history is complete once it shows

W=""; R=""; D=""; OUT=""; ERR=""; WPID=""
fail() { echo "$*"; exit 1; }
sa() { bash "$S" "$@"; }   # through bash: a copy from `git show` is not executable
drop_dir() { # only a fixture folder, made writable again first (a case may have locked it)
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
stop_watch() { # stop the newest watch (sa execs the viewer: one process, no child)
  [ -n "${WPID:-}" ] || return 0
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""
  return 0
}
stop_all() { local p; [ -f "$D/pids" ] && for p in $(cat "$D/pids"); do kill "$p" 2>/dev/null; done; wait 2>/dev/null; return 0; }
run_case() { # run_case <name> <function>; with ONLY=<text> in the environment, only the cases whose name holds the text
  local rc
  case "$1" in *"${ONLY:-}"*) ;; *) return ;; esac
  W=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$W"); R="$W/decision-room"; OUT="$D/out"; ERR="$D/err"
  mkdir -p "$R/demo" "$R/group/app"
  cat "$FX/room/demo/LOG.md" > "$R/demo/LOG.md"
  cat "$FX/room/group/app/LOG.md" > "$R/group/app/LOG.md"
  ( trap stop_all EXIT; "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}

start_watch() { # start_watch <args of room watch>: in the background; stdout in $OUT, stderr in $ERR, its id in $WPID
  : > "$OUT"; : > "$ERR"
  bash "$S" room watch "$@" > "$OUT" 2> "$ERR" &
  WPID=$!; echo "$WPID" >> "$D/pids"
}
alive() { kill -0 "$1" 2>/dev/null && [ "$(ps -p "$1" -o stat= 2>/dev/null | cut -c1)" != Z ]; }
waitfor() { # waitfor <seconds> <file> <text>: until the file holds the text (0.1 s steps); at once when the watch is gone
  local i=0 n=$(( $1 * 10 ))
  while [ "$i" -lt "$n" ]; do
    grep -qF -- "$3" "$2" 2>/dev/null && return 0
    [ -z "$WPID" ] || alive "$WPID" || { grep -qF -- "$3" "$2" 2>/dev/null; return; }
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
ready() { # the watch has taken its first look at the logs: it prints its legend after that
  waitfor 5 "$OUT" 'unknown' || fail "the watch never printed its legend: out '$(cat "$OUT")' err '$(cat "$ERR")'"
}
run_history() { # run_history <args>: the whole history of the fixture, then stop the watch; the output is in $OUT
  start_watch "$@"
  waitfor 6 "$OUT" "$LAST" || fail "the history never completed: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  stop_watch
}
tty_run() { # tty_run <seconds> <out-file> <command...>: the command's stdout and stderr go to a pseudo-terminal of 24 x 100
  command -v python3 >/dev/null 2>&1 || fail "no python3 to give a command a terminal"
  python3 - "$@" <<'PY'
import fcntl, os, pty, select, signal, struct, sys, termios, time
secs, out, cmd = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
pid = os.fork()
if pid == 0:
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    os.dup2(slave, 1); os.dup2(slave, 2)
    os.close(master); os.close(slave)
    os.execvp(cmd[0], cmd)
os.close(slave)
data, end = b"", time.time() + secs
while time.time() < end:
    r, _, _ = select.select([master], [], [], 0.1)
    if r:
        try:
            chunk = os.read(master, 65536)
        except OSError:
            break
        if not chunk:
            break
        data += chunk
os.kill(pid, signal.SIGTERM)
os.waitpid(pid, 0)
open(out, "wb").write(data)
PY
}
chars() { tr -d '\r\n' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }   # the characters on stdin, without the line ends
badge_rows() { sed -n "/^BADGE_TABLE='/,/^BADGE_OTHER/p" "$S" | sed "s/^BADGE_TABLE='//; /^BADGE_OTHER/d; s/'\$//"; }
color_rows() { sed -n "/^BADGE_COLORS='/,/'\$/p" "$S" | sed "s/^BADGE_COLORS='//; s/'\$//"; }
sgr_open() { # sgr_open <file> <text>: the code of the SGR that opens "<kind> | <text>" on the line holding <text>
  grep -aF -- "$2" "$1" | head -1 | sed -n "s/.*${ESC}\[0m | ${ESC}\[\([0-9;]*\)m.*/\1/p"
}
rest_of() { # rest_of <file> <text>: what follows the ref (and its reset) on the line holding <text>
  grep -aF -- "$2" "$1" | head -1 | sed -n "s/.*${ESC}\[1m[^${ESC}]*${ESC}\[0m | //p"
}
bounded() { # bounded <seconds> <command...>: its exit status, or 99 when it still runs after <seconds> (and is stopped)
  local n=$(( $1 * 10 )) i=0 pid rc
  shift
  "$@" > "$D/bounded.out" 2> "$D/bounded.err" < /dev/null &
  pid=$!; echo "$pid" >> "$D/pids"
  while [ "$i" -lt "$n" ]; do alive "$pid" || break; sleep 0.1; i=$((i + 1)); done
  if alive "$pid"; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 99; fi
  wait "$pid"; rc=$?
  return "$rc"
}

# --- E-1: every log is followed live, the nested one too, and the old lines are not printed ---------------------------

c_e1_live() {
  local n
  start_watch "$W" --color never
  ready
  waitfor 2 "$ERR" 'watching' || fail "no 'watching' line on stderr: $(cat "$ERR")"
  printf '%s\n' '🔨 2026-11-14 10:00 | demo#003 | note | worker: live in demo' >> "$R/demo/LOG.md"
  printf '%s\n' '🧪 2026-11-14 10:01 | group/app#002 | note | tester: live in the nested log' >> "$R/group/app/LOG.md"
  waitfor 3 "$OUT" 'tester: live in the nested log' && waitfor 3 "$OUT" 'worker: live in demo' || fail "a line appended to a log was not printed within 3 s: out '$(cat "$OUT")'"
  stop_watch
  n=$(wc -l < "$OUT" | tr -d ' ')
  [ "$n" = 5 ] || fail "want the legend and two entries with a separator each (5 lines), got $n: $(cat "$OUT")"
  case "$(sed -n 1p "$OUT")" in *'router'*'worker'*'unknown') ;; *) fail "the first line is not the legend: $(sed -n 1p "$OUT")" ;; esac
  sed -n 2p "$OUT" | grep -q '^──── demo ' && [ "$(sed -n 3p "$OUT")" = '🔨 2026-11-14 10:00 | demo#003 | note | worker: live in demo' ] || fail "demo's separator or line: $(sed -n 2,3p "$OUT")"
  sed -n 4p "$OUT" | grep -q '^──── group/app ' && [ "$(sed -n 5p "$OUT")" = '🧪 2026-11-14 10:01 | group/app#002 | note | tester: live in the nested log' ] || fail "the nested log's separator or line: $(sed -n 4,5p "$OUT")"
  grep -qF 'demo#001' "$OUT" && fail "a line that was in the log before the start was printed"
  return 0
}

# --- E-2: a log created after the start is followed from its first line --------------------------------------------------

c_e2_new_log() {
  start_watch "$W" --color never
  ready
  mkdir -p "$R/late"
  printf '%s\n' '# Badges: x' '🧪 2026-11-14 10:00 | late#001 | note | tester: first' > "$R/late/LOG.md"
  waitfor 7 "$OUT" 'tester: first' || fail "a log created after the start was not followed within 7 s: out '$(cat "$OUT")'"
  grep -q '^──── late ' "$OUT" || fail "no separator for the new log: $(cat "$OUT")"
  [ "$(tail -1 "$OUT")" = '🧪 2026-11-14 10:00 | late#001 | note | tester: first' ] || fail "the new log's first line is not the last line: $(tail -2 "$OUT")"
  grep -qF '# Badges' "$OUT" && fail "the legend line of the new log was printed"
  printf '%s\n' '🧪 2026-11-14 10:01 | late#001 | note | tester: second' >> "$R/late/LOG.md"
  waitfor 3 "$OUT" 'tester: second' || fail "the new log is not followed after its first line: $(cat "$OUT")"
  [ "$(grep -c 'tester: first' "$OUT")" = 1 ] || fail "the first line was printed twice: $(cat "$OUT")"
}

# --- E-3: the workspace is found from a project folder; sa help lists the command -----------------------------------------

c_e3_default_workspace() {
  local h
  : > "$OUT"; : > "$ERR"
  ( cd "$W/demo" && exec bash "$S" room watch --color never > "$OUT" 2> "$ERR" ) &
  WPID=$!; echo "$WPID" >> "$D/pids"
  ready
  printf '%s\n' '🔨 2026-11-14 10:00 | demo#003 | note | worker: from inside the project' >> "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'worker: from inside the project' || fail "no workspace argument from inside a project: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  stop_watch
  [ "$(cat "$ERR")" = "watching 2 logs in $R (Ctrl-C to stop)" ] || fail "stderr: $(cat "$ERR")"
  h=$(sa help | grep 'room watch')
  case "$h" in *'--since'*'--project'*'--color'*) ;; *) fail "sa help does not list room watch with its options: '$h'" ;; esac
}

# --- E-4: the plain output is the expected file; E-5: separator widths; E-6: the legend ---------------------------------------

c_e4_plain() {
  NO_COLOR=1 COLUMNS=60 run_history "$W" --since 99999999
  diff "$OUT" "$FX/expected-plain.txt" > "$D/diff.txt" || fail "the plain output differs from expected-plain.txt: $(head -20 "$D/diff.txt")"
  [ "$(grep -c "$ESC" "$OUT")" = 0 ] || fail "an ESC byte reached stdout with colour off (the fixture holds one in a log line)"
  [ "$(grep -c "$(printf '\r')" "$OUT")" = 0 ] || fail "a CR reached stdout"
  grep -qF '# Badges' "$OUT" && fail "a legend line of a log was printed"
  [ "$(grep -c '^$' "$OUT")" = 0 ] || fail "a blank line was printed"
  grep -qF 'watching' "$OUT" && fail "the 'watching' line is on stdout"
  return 0
}

c_e5_widths() {
  local l
  run_history "$W" --since 99999999 --color never                         # no COLUMNS, stdout is a file: 80
  grep '^────' "$OUT" | while IFS= read -r l; do printf '%s' "$l" | chars; done | sort -u > "$D/widths"
  [ "$(cat "$D/widths")" = 80 ] || fail "with no COLUMNS off a terminal, want separators of 80 characters, got: $(cat "$D/widths")"
  COLUMNS=12 run_history "$W" --since 99999999 --color never
  grep '^────' "$OUT" | sort -u > "$D/seps"
  [ "$(cat "$D/seps")" = "$(printf '%s\n' '──── demo ──' '──── group/app')" ] || fail "COLUMNS=12: want '──── demo ──' and '──── group/app' alone, got: $(cat "$D/seps")"
  COLUMNS=10 run_history "$W" --since 99999999 --color never
  grep -qx '──── demo' "$OUT" || fail "COLUMNS=10: no room for a closing rule, want '──── demo' alone: $(grep '^────' "$OUT" | sort -u)"
  COLUMNS=0 run_history "$W" --since 99999999 --color never                # not a positive integer: the default
  [ "$(grep '^────' "$OUT" | head -1 | chars)" = 80 ] || fail "COLUMNS=0 is used"
  COLUMNS=abc run_history "$W" --since 99999999 --color never
  [ "$(grep '^────' "$OUT" | head -1 | chars)" = 80 ] || fail "COLUMNS=abc is used"
  COLUMNS=33 run_history "$W" --since 99999999 --color never
  [ "$(grep '^────' "$OUT" | head -1 | chars)" = 33 ] || fail "COLUMNS=33: want 33 characters: $(grep '^────' "$OUT" | head -1)"
}

c_e6_legend() {
  local first row badge name
  run_history "$W" --since 99999999 --color never
  first=$(sed -n 1p "$OUT")
  while IFS= read -r row; do
    badge=${row%% *}; name=${row#* }; name=${name%%,*}
    case "$first" in *"$badge $name"*) ;; *) fail "the legend has no '$badge $name': $first" ;; esac
  done <<< "$(badge_rows)"
  case "$first" in *'❔ '*) ;; *) fail "the legend has no ❔: $first" ;; esac
  [ "$(cat "$ERR")" = "watching 2 logs in $R (Ctrl-C to stop)" ] || fail "stderr: '$(cat "$ERR")'"
}

# --- E-7: the coloured output is the expected file and every segment is closed ---------------------------------------------

c_e7_color() {
  local n bad
  COLUMNS=60 run_history "$W" --since 99999999 --color always
  diff "$OUT" "$FX/expected-color.txt" > "$D/diff.txt" || fail "the coloured output differs from expected-color.txt: $(cat -v "$D/diff.txt" | head -20)"
  n=$(grep -c "${ESC}\\[2m2026-" "$OUT"); [ "$n" = 20 ] || fail "want 20 entries with a dim date-time, got $n"
  n=$(grep -c "| ${ESC}\\[1m" "$OUT"); [ "$n" = 20 ] || fail "want 20 entries with a bold ref, got $n"
  # an entry is "<badge> ESC[2m<time>ESC[0m | ESC[1m<ref>ESC[0m | <rest>": the badge and the separators carry no SGR
  bad=$(grep -a "${ESC}\\[2m2026-" "$OUT" | grep -avE "^([^ ${ESC}]+ )?${ESC}\\[2m[0-9: -]{16}${ESC}\\[0m \\| ${ESC}\\[1m[^|${ESC}]*${ESC}\\[0m \\| ") || true
  [ -z "$bad" ] || fail "an entry is not the badge, the dim time, the bold ref and the rest: $(printf '%s\n' "$bad" | cat -v | head -3)"
  # every SGR that opens is closed on its line, and never nested
  bad=$(perl -ne 'my $o = () = /\e\[(?!0m)[0-9;]*m/g; my $c = () = /\e\[0m/g; print "$.:" if $o != $c;' "$OUT")
  [ -z "$bad" ] || fail "a segment is left open on line(s) $bad"
}

# --- E-8: one colour per agent, none reserved, two roles differ, nothing for the unknown ----------------------------------------

c_e8_agent_colors() {
  local rows badges seen row code w t
  rows=$(color_rows); [ -n "$rows" ] || fail "no BADGE_COLORS table in sa"
  badges=$(badge_rows | cut -d' ' -f1)
  [ "$(printf '%s\n' "$rows" | cut -d' ' -f1)" = "$badges" ] || fail "BADGE_COLORS has not one row per badge of BADGE_TABLE, in its order: $(printf '%s\n' "$rows" | cut -d' ' -f1 | tr '\n' ' ')"
  seen=""
  while IFS= read -r row; do
    code=${row#* }
    case "$code" in ''|*[!0-9\;]*) fail "not an SGR parameter list: '$row'" ;; esac
    case ";$seen;" in *";$code;"*) fail "two badges share the colour $code" ;; esac
    case "$code" in 31|1\;35|1\;32|0|1|2) fail "a badge has a reserved or plain code: '$row'" ;; esac
    seen="$seen;$code"
  done <<< "$rows"
  COLUMNS=60 run_history "$W" --since 99999999 --color always
  w=$(sgr_open "$OUT" 'worker: baseline is 217 ok'); t=$(sgr_open "$OUT" 'tester: round 1 starts')
  [ -n "$w" ] && [ -n "$t" ] && [ "$w" != "$t" ] || fail "the worker and the tester must have two colours: worker '$w', tester '$t'"
  [ "$w" = "$(printf '%s\n' "$rows" | grep '^🔨 ' | cut -d' ' -f2)" ] || fail "the worker's line does not use the worker's row of the table: '$w'"
  for t in 'stranger: a line with no known role' 'worker starts'; do   # the unknown badge, and a line with no badge
    row=$(rest_of "$OUT" "$t")
    [ -n "$row" ] && [ "$(printf '%s' "$row" | grep -ac "$ESC")" = 0 ] || fail "a line with no agent colour has an SGR around its kind and text: $(printf '%s' "$row" | cat -v)"
  done
}

# --- E-9: a decision, a landing and a failure override the agent's colour -----------------------------------------------------------

c_e9_emphasis() {
  local w
  COLUMNS=60 run_history "$W" --since 99999999 --color always
  [ "$(sgr_open "$OUT" 'waits for an answer')" = 31 ] || fail "a stage to blocked is not red: '$(sgr_open "$OUT" 'waits for an answer')'"
  [ "$(sgr_open "$OUT" 'the build broke')" = 31 ] || fail "a stage to failed is not red: '$(sgr_open "$OUT" 'the build broke')'"
  [ "$(sgr_open "$OUT" 'tester: failed: one check fails')" = 31 ] || fail "a failed report is not red: '$(sgr_open "$OUT" 'tester: failed')'"
  [ "$(sgr_open "$OUT" 'codex-reviewer: refused')" = 31 ] || fail "a refused report is not red: '$(sgr_open "$OUT" 'codex-reviewer: refused')'"
  [ "$(sgr_open "$OUT" 'D1 (Q1)')" = '1;35' ] || fail "a decision is not bold magenta: '$(sgr_open "$OUT" 'D1 (Q1)')'"
  [ "$(sgr_open "$OUT" '3f2a1bc on main')" = '1;32' ] || fail "a landing is not bold green: '$(sgr_open "$OUT" '3f2a1bc on main')'"
  w=$(sgr_open "$OUT" 'tests first')
  [ -n "$w" ] && [ "$w" != 31 ] && [ "$w" = "$(sgr_open "$OUT" 'baseline is 217 ok')" ] || fail "a stage to in-progress keeps the worker's colour, not red: '$w'"
  w=$(sgr_open "$OUT" 'Q1 from worker')
  [ -n "$w" ] && [ "$w" != 31 ] || fail "a question line is not a stage line: it keeps the agent's colour, got '$w'"
  w=$(sgr_open "$OUT" 'ticket 002 is stuck')
  [ -n "$w" ] && [ "$w" != 31 ] || fail "a report that waits is not red: '$w'"
  w=$(sgr_open "$OUT" 'Q1 answered by the user')
  [ -n "$w" ] && [ "$w" != 31 ] || fail "an answer is not red: '$w'"
}

# --- E-10: when colour is on ----------------------------------------------------------------------------------------------------------

c_e10_switches() {
  run_history "$W" --since 99999999                                       # stdout is a file, NO_COLOR unset: off
  [ "$(grep -c "$ESC" "$OUT")" = 0 ] || fail "colour is on when stdout is a file"
  run_history "$W" --since 99999999 --color auto
  [ "$(grep -c "$ESC" "$OUT")" = 0 ] || fail "--color auto: colour is on when stdout is a file"
  run_history "$W" --since 99999999 --color never
  [ "$(grep -c "$ESC" "$OUT")" = 0 ] || fail "--color never: colour is on"
  NO_COLOR=1 run_history "$W" --since 99999999 --color always
  [ "$(grep -c "$ESC" "$OUT")" -gt 0 ] || fail "--color always does not force colour when NO_COLOR is set"
  tty_run 2 "$D/tty-on.out" bash "$S" room watch "$W" --since 99999999
  [ "$(grep -ac "$ESC" "$D/tty-on.out")" -gt 0 ] || fail "colour is off on a terminal: $(head -c 300 "$D/tty-on.out" | cat -v)"
  tty_run 2 "$D/tty-no.out" env NO_COLOR=1 bash "$S" room watch "$W" --since 99999999
  grep -aq 'unknown' "$D/tty-no.out" || fail "the watch printed nothing on a terminal"
  [ "$(grep -ac "$ESC" "$D/tty-no.out")" = 0 ] || fail "NO_COLOR=1 is ignored on a terminal"
  tty_run 2 "$D/tty-empty.out" env NO_COLOR= bash "$S" room watch "$W" --since 99999999
  [ "$(grep -ac "$ESC" "$D/tty-empty.out")" -gt 0 ] || fail "an empty NO_COLOR must not turn colour off"
  tty_run 2 "$D/tty-never.out" bash "$S" room watch "$W" --since 99999999 --color never
  [ "$(grep -ac "$ESC" "$D/tty-never.out")" = 0 ] || fail "--color never on a terminal"
  # with no COLUMNS the width of the terminal is used (the pseudo-terminal has 100 columns); COLUMNS wins over it
  [ "$(grep -a '──── demo ' "$D/tty-never.out" | head -1 | tr -d '\r' | chars)" = 100 ] || fail "the terminal's width is not used: $(grep -a '──── demo ' "$D/tty-never.out" | head -1 | tr -d '\r' | chars) characters"
  tty_run 2 "$D/tty-cols.out" env COLUMNS=40 bash "$S" room watch "$W" --since 99999999 --color never
  [ "$(grep -a '──── demo ' "$D/tty-cols.out" | head -1 | tr -d '\r' | chars)" = 40 ] || fail "COLUMNS does not win over the terminal's width"
}

# --- E-11: the history is merged by time and cut at --since ---------------------------------------------------------------------------

c_e11_since() {
  local t3 t2 t1 th
  t3=$(date -v-3M '+%Y-%m-%d %H:%M'); t2=$(date -v-2M '+%Y-%m-%d %H:%M'); t1=$(date -v-1M '+%Y-%m-%d %H:%M'); th=$(date -v-2H '+%Y-%m-%d %H:%M')
  { head -1 "$FX/room/demo/LOG.md"; printf '🔨 %s | demo#009 | note | worker: three minutes ago\n' "$t3"; } > "$R/demo/LOG.md"
  { head -1 "$FX/room/group/app/LOG.md"; printf '🧪 %s | group/app#009 | note | tester: two hours ago\n' "$th"; printf '🧪 %s | group/app#009 | note | tester: two minutes ago\n' "$t2"; } > "$R/group/app/LOG.md"
  start_watch "$W" --since 10 --color never
  waitfor 5 "$OUT" 'two minutes ago' || fail "no history: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  stop_watch
  grep -qF 'two hours ago' "$OUT" && fail "an entry older than --since is printed"
  [ "$(wc -l < "$OUT" | tr -d ' ')" = 5 ] || fail "want the legend, a separator and a line for each project (5 lines): $(cat "$OUT")"
  sed -n 2p "$OUT" | grep -q '^──── demo ' && sed -n 3p "$OUT" | grep -q 'worker: three minutes ago' && sed -n 4p "$OUT" | grep -q '^──── group/app ' && sed -n 5p "$OUT" | grep -q 'tester: two minutes ago' || fail "wrong order or separators: $(cat "$OUT")"
  # merged by time, not grouped by file: demo, then group/app, then demo again
  { head -1 "$FX/room/demo/LOG.md"; printf '🔨 %s | demo#009 | note | worker: first in demo\n' "$t3"; printf '🔨 %s | demo#009 | note | worker: later in demo\n' "$t1"; } > "$R/demo/LOG.md"
  { head -1 "$FX/room/group/app/LOG.md"; printf '🧪 %s | group/app#009 | note | tester: between them\n' "$t2"; } > "$R/group/app/LOG.md"
  start_watch "$W" --since 10 --color never
  waitfor 5 "$OUT" 'later in demo' || fail "no history: $(cat "$OUT")"
  stop_watch
  [ "$(sed -n 's/^──── \([^ ]*\) .*/\1/p' "$OUT" | tr '\n' ' ')" = 'demo group/app demo ' ] || fail "want the separators demo, group/app, demo by time: $(cat "$OUT")"
  [ "$(grep -v '^────' "$OUT" | sed -n '2,$p' | sed 's/.*worker: //; s/.*tester: //' | tr '\n' '|')" = 'first in demo|between them|later in demo|' ] || fail "the entries are not in time order: $(cat "$OUT")"
}

# --- E-12: one project only, history and live --------------------------------------------------------------------------------------------

c_e12_project() {
  start_watch "$W" --project group/app --since 99999999 --color never
  waitfor 6 "$OUT" "$LAST" || fail "no history: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  printf '%s\n' '🔨 2026-11-14 10:00 | demo#003 | note | worker: not for this view' >> "$R/demo/LOG.md"
  printf '%s\n' '🧪 2026-11-14 10:01 | group/app#002 | note | tester: for this view' >> "$R/group/app/LOG.md"
  waitfor 3 "$OUT" 'tester: for this view' || fail "the project's live line is not printed: $(cat "$OUT")"
  sleep 1
  stop_watch
  grep -qE 'demo#|^──── demo' "$OUT" && fail "an entry or a separator of another project is printed: $(grep -E 'demo#|^──── demo' "$OUT")"
  [ "$(grep -c '^──── ' "$OUT")" = 1 ] || fail "want one separator for the one project: $(grep '^──── ' "$OUT")"
  [ "$(grep -c ' | group/app' "$OUT")" = 6 ] || fail "want the 5 history entries and the live one: $(cat "$OUT")"
  [ "$(cat "$ERR")" = "watching 1 logs in $R (Ctrl-C to stop)" ] || fail "stderr: $(cat "$ERR")"
}

# --- X-2: a bad option, value or folder is refused: exit 1, nothing on stdout, one line on stderr that says what is wrong -----------------

c_x2_bad_input() {
  local name args want rc
  mkdir -p "$D/emptyws" && printf '# Active projects\n' > "$D/emptyws/ACTIVE-PROJECTS.md"
  while IFS='|' read -r name want args; do
    # shellcheck disable=SC2086
    ( cd "$D/outside" && bounded 5 bash "$S" room watch $args ); rc=$?
    [ "$rc" = 1 ] || fail "$name: want exit 1, got $rc (99: still running)"
    [ ! -s "$D/bounded.out" ] || fail "$name: something on stdout: $(cat "$D/bounded.out")"
    [ "$(wc -l < "$D/bounded.err" | tr -d ' ')" = 1 ] || fail "$name: want one line on stderr, got: $(cat "$D/bounded.err")"
    grep -qF -- "$want" "$D/bounded.err" || fail "$name: the line does not say '$want': $(cat "$D/bounded.err")"
  done <<EOF
since abc|--since|$W --since abc
since zero|--since|$W --since 0
since zeros|--since|$W --since 00
since negative|--since|$W --since -5
since decimal|--since|$W --since 1.5
since no value|--since|$W --since
unknown option|--bogus|$W --bogus
color value|purple|$W --color purple
color no value|--color|$W --color
project no value|--project|$W --project
project nope|nope|$W --project nope
two workspaces|unexpected|$W $W
nonexistent workspace|/nonexistent/for/sure|/nonexistent/for/sure
no decision-room|decision-room|$D/emptyws
no workspace above|ACTIVE-PROJECTS.md|--color never
EOF
  ( cd "$D/outside" && bounded 5 bash "$S" room watch --project nope "$W" ) || true
  grep -q 'demo' "$D/bounded.err" && grep -q 'group/app' "$D/bounded.err" || fail "an unknown project does not name the projects that have a log: $(cat "$D/bounded.err")"
}

# --- X-3: the viewer only reads, and sa is not slowed by it ----------------------------------------------------------------------------

c_x3_read_only() {
  local out t0 t1
  find "$R" | sort > "$D/files-before"; find "$R" -type f | sort | xargs shasum > "$D/sums-before"
  run_history "$W" --since 99999999 --color never
  sleep 1.2
  find "$R" | sort > "$D/files-after"; find "$R" -type f | sort | xargs shasum > "$D/sums-after"
  diff "$D/files-before" "$D/files-after" > /dev/null || fail "the file list changed: $(diff "$D/files-before" "$D/files-after")"
  diff "$D/sums-before" "$D/sums-after" > /dev/null || fail "a log changed"
  [ -z "$(find "$R" -name '*.lock')" ] || fail "a lock file exists: $(find "$R" -name '*.lock')"
  start_watch "$W" --color never
  ready
  t0=$(date +%s); out=$(sa room note "$W/demo/tickets" worker "x while watching" 2>&1); t1=$(date +%s)
  [ "$out" = noted ] || fail "sa room note: $out"
  [ $((t1 - t0)) -le 2 ] || fail "sa waited on the viewer: $((t1 - t0)) s"
  waitfor 3 "$OUT" 'worker: x while watching' || fail "the note is not printed: $(cat "$OUT")"
  case "$(tail -1 "$OUT")" in '🔨 '*) ;; *) fail "the printed note has no worker badge: $(tail -1 "$OUT")" ;; esac
}

# --- X-4: a half line is never shown, and neither is a half line that is taken back ------------------------------------------------------

c_x4_half_lines() {
  local size
  start_watch "$W" --color never
  ready
  printf '%s' '🔨 2026-11-14 10:01 | demo#003 | note | worker: half' >> "$R/demo/LOG.md"
  sleep 1.8
  grep -qF 'half' "$OUT" && fail "a line with no newline was printed: $(cat "$OUT")"
  printf '%s\n' ' done' >> "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'worker: half done' || fail "the completed line is not printed: $(cat "$OUT")"
  [ "$(grep -c 'worker: half' "$OUT")" = 1 ] || fail "the line is printed twice: $(cat "$OUT")"
  size=$(wc -c < "$R/demo/LOG.md" | tr -d ' ')
  printf '%s' '🔨 2026-11-14 10:02 | demo#003 | note | worker: torn' >> "$R/demo/LOG.md"
  sleep 1.8
  perl -e 'truncate($ARGV[0], $ARGV[1]) or die "truncate: $!"' "$R/demo/LOG.md" "$size"   # what sa does to a write that was cut short
  printf '%s\n' '🔨 2026-11-14 10:03 | demo#003 | note | worker: after the cut' >> "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'worker: after the cut' || fail "the line after a cut-back is lost: $(cat "$OUT")"
  grep -qF 'torn' "$OUT" && fail "a half line that was cut back was printed: $(cat "$OUT")"
  [ "$(grep -c 'after the cut' "$OUT")" = 1 ] || fail "the line after the cut is printed twice: $(cat "$OUT")"
}

# --- X-5: nothing in a log can move the cursor or change the colours ---------------------------------------------------------------------

c_x5_controls() {
  local line
  # a line of the fixture's own hour that holds a C1 CSI (U+009B), a bell, a DEL and a form feed
  printf '🔨 2026-11-14 09:30 | demo#002 | note | worker: c1 \302\233\061m bell \007 del \177 form\014feed\n' >> "$R/demo/LOG.md"
  COLUMNS=60 run_history "$W" --since 99999999 --color always
  line=$(grep -aF 'redafter' "$OUT")
  case "$line" in *"worker: [31mredafter tab${ESC}[0m") ;; *) fail "the ESC, CR and TAB of the log line are not handled: $(printf '%s' "$line" | cat -v)" ;; esac
  grep -aq 'worker: c1 1m bell  del  formfeed' "$OUT" || fail "the other controls are not removed: $(grep -a 'worker: c1' "$OUT" | cat -v)"
  [ "$(sed "s/${ESC}\\[[0-9;]*m//g" "$OUT" | grep -ac "$ESC")" = 0 ] || fail "an ESC byte that is not the viewer's own SGR reached stdout"
  [ "$(sed "s/${ESC}\\[[0-9;]*m//g" "$OUT" | perl -ne 'print "x" if /[\x00-\x08\x0b-\x1f\x7f]/ || /\xc2[\x80-\x9f]/')" = "" ] || fail "a control character reached stdout"
}

# --- X-6: Ctrl-C and SIGTERM stop it within a second and leave no process ----------------------------------------------------------------------

c_x6_signals() {
  local sig i o c
  for sig in INT TERM; do
    start_watch "$W" --since 99999999 --color always
    ready
    pgrep -f "$R" > /dev/null || fail "the watch is not found by pgrep -f (the check below could not fail)"
    kill -"$sig" "$WPID"
    i=0; while alive "$WPID" && [ "$i" -lt 12 ]; do sleep 0.1; i=$((i + 1)); done
    alive "$WPID" && fail "SIG$sig: still running 1.2 s after the signal"
    wait "$WPID" 2>/dev/null; WPID=""
    [ -z "$(pgrep -f "$R")" ] || fail "SIG$sig: a process is left: $(pgrep -fl "$R")"
    o=$(perl -ne '$o += () = /\e\[(?!0m)[0-9;]*m/g; $c += () = /\e\[0m/g; END { print "$o $c" }' "$OUT")
    [ "${o%% *}" = "${o##* }" ] || fail "SIG$sig: an SGR is left open ($o opened and closed)"
    [ "$(tail -c 1 "$OUT" | od -An -tx1 | tr -d ' ')" = 0a ] || fail "SIG$sig: the last line is cut: $(tail -c 40 "$OUT" | cat -v)"
  done
}

# --- the room's own log, the = form of the options, another project's new log, a replaced log, an unreadable log, a long history ----------

c_root_log() { # the room's own LOG.md is project "."
  printf '%s\n' '# Badges: x' '🧭 2026-11-14 09:30 | superagent | note | router: a line of the root log' > "$R/LOG.md"
  start_watch "$W" --since 99999999 --color never --project .
  waitfor 6 "$OUT" 'a line of the root log' || fail "the root log is not followed: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  stop_watch
  grep -q '^──── \. ' "$OUT" || fail "the root log's project is not '.': $(cat "$OUT")"
  [ "$(grep -c 'demo#' "$OUT")" = 0 ] || fail "--project . printed another project"
  [ "$(cat "$ERR")" = "watching 1 logs in $R (Ctrl-C to stop)" ] || fail "stderr: $(cat "$ERR")"
  run_history "$W" --since 99999999 --color never
  [ "$(grep -c '^──── ' "$OUT")" = 8 ] || fail "the root log is not merged with the others by time and path: $(grep '^──── ' "$OUT" | cut -c1-14)"
}

c_options_equals() { # --since=, --project= and --color= are the same as the two-word forms
  start_watch --project=group/app --color=never --since=99999999 "$W"
  waitfor 6 "$OUT" "$LAST" || fail "no output: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  stop_watch
  [ "$(grep -c '^──── ' "$OUT")" = 1 ] && [ "$(grep -c "$ESC" "$OUT")" = 0 ] || fail "$(cat "$OUT")"
}

c_project_later() { # an unknown project is refused; of the known one only its own new lines are followed
  start_watch "$W" --project later --color never
  waitfor 3 "$ERR" 'refused' || fail "an unknown project is accepted: err '$(cat "$ERR")'"
  stop_watch
  start_watch "$W" --project demo --color never
  ready
  mkdir -p "$R/other"; printf '%s\n' '🧪 2026-11-14 10:00 | other#001 | note | tester: not asked' > "$R/other/LOG.md"
  printf '%s\n' '🔨 2026-11-14 10:00 | demo#003 | note | worker: asked' >> "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'worker: asked' || fail "the asked project's line is not printed: $(cat "$OUT")"
  sleep 3
  grep -qF 'not asked' "$OUT" && fail "a log of another project is printed: $(cat "$OUT")"
  return 0
}

c_replaced_log() { # a log that is replaced, or cut below what was shown, is shown from its first line
  start_watch "$W" --color never
  ready
  mv "$R/demo/LOG.md" "$R/demo/LOG.md.old" && printf '%s\n' '🔨 2026-11-14 11:00 | demo#004 | note | worker: in the new file, a line that is longer than the one that comes after the cut' > "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'worker: in the new file' || fail "a replaced log is not followed: $(cat "$OUT")"
  : > "$R/demo/LOG.md"; printf '%s\n' '🔨 2026-11-14 11:01 | demo#004 | note | worker: after a cut to zero' >> "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'worker: after a cut to zero' || fail "a log cut below what was shown is not followed: $(cat "$OUT")"
  [ "$(grep -c 'worker: in the new file' "$OUT")" = 1 ] || fail "a line is printed twice: $(cat "$OUT")"
}

c_unreadable_log() { # a log that cannot be read does not stop the others
  chmod 000 "$R/group/app/LOG.md"
  start_watch "$W" --color never
  ready
  printf '%s\n' '🔨 2026-11-14 10:00 | demo#003 | note | worker: the other log goes on' >> "$R/demo/LOG.md"
  waitfor 3 "$OUT" 'the other log goes on' || fail "an unreadable log stops the viewer: out '$(cat "$OUT")' err '$(cat "$ERR")'"
  alive "$WPID" || fail "the viewer is gone"
  chmod 644 "$R/group/app/LOG.md"
}

c_many_lines() { # a long history and a burst of live lines come out whole and in order
  local i
  { head -1 "$FX/room/demo/LOG.md"; i=0; while [ "$i" -lt 600 ]; do i=$((i + 1)); printf '🔨 2026-10-%02d %02d:00 | demo#%03d | note | worker: line %d\n' $(( (i - 1) / 24 + 1 )) $(( (i - 1) % 24 )) $((i / 60)) "$i"; done; } > "$R/demo/LOG.md"
  start_watch "$W" --since 99999999 --color never
  waitfor 8 "$OUT" "$LAST" || fail "the long history is not printed: $(tail -3 "$OUT")"
  [ "$(grep -c 'worker: line ' "$OUT")" = 600 ] || fail "want 600 lines, got $(grep -c 'worker: line ' "$OUT")"
  [ "$(grep 'worker: line ' "$OUT" | sed 's/.*line //' | tr '\n' ' ')" = "$(seq 1 600 | tr '\n' ' ')" ] || fail "the history is out of order"
  i=0; while [ "$i" -lt 50 ]; do i=$((i + 1)); printf '🔨 2026-11-14 13:00 | demo#099 | note | worker: burst %d\n' "$i" >> "$R/demo/LOG.md"; done
  waitfor 4 "$OUT" 'worker: burst 50' || fail "the burst is not printed: $(tail -3 "$OUT")"
  [ "$(grep 'worker: burst ' "$OUT" | sed 's/.*burst //' | tr '\n' ' ')" = "$(seq 1 50 | tr '\n' ' ')" ] || fail "the burst is missing a line or out of order: $(grep -c 'worker: burst ' "$OUT") lines"
}

run_case "E-1 every log is followed live, the nested one too, and old lines are not printed" c_e1_live
run_case "E-2 a log created after the start is followed from its first line" c_e2_new_log
run_case "E-3 the workspace is found from a project folder, and sa help lists the command" c_e3_default_workspace
run_case "E-4 the plain output is the expected file, with no escape byte, legend or blank line" c_e4_plain
run_case "E-5 a separator is COLUMNS wide, else the terminal's, else 80; a long name stands alone" c_e5_widths
run_case "E-6 the legend names every badge with its first role, on stdout; the watching line is on stderr" c_e6_legend
run_case "E-7 the coloured output is the expected file and every segment is closed" c_e7_color
run_case "E-8 one colour per agent, none reserved, and no colour for the unknown and the badge-less" c_e8_agent_colors
run_case "E-9 a decision, a landing and a failure override the agent's colour" c_e9_emphasis
run_case "E-10 colour is on for a terminal without NO_COLOR, for always, and off otherwise" c_e10_switches
run_case "E-11 the history is merged by time and cut at --since" c_e11_since
run_case "E-12 --project shows one project, history and live" c_e12_project
run_case "X-2 a bad option, value or folder exits 1 with one line on stderr and nothing on stdout" c_x2_bad_input
run_case "X-3 the viewer changes nothing and does not slow sa" c_x3_read_only
run_case "X-4 a half line, and a half line cut back, are never shown" c_x4_half_lines
run_case "X-5 control characters of a log never reach the terminal" c_x5_controls
run_case "X-6 Ctrl-C and SIGTERM stop it within a second and leave no process" c_x6_signals
run_case "the room's own log is project . and is merged with the others" c_root_log
run_case "the options take = as well as a space" c_options_equals
run_case "--project: an unknown name is refused and another project's new log is not followed" c_project_later
run_case "a replaced log, or one cut below what was shown, is shown from its first line" c_replaced_log
run_case "an unreadable log does not stop the others" c_unreadable_log
run_case "a long history and a burst of live lines come out whole and in order" c_many_lines
