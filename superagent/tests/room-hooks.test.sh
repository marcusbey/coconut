#!/usr/bin/env bash
# room-hooks.test.sh: the router session's hooks (superagent/router-settings.json, `sa room hook`) log every
# dispatch with its real model and effort, and every question the router asks the user with its answer
# (superagent#008). Payloads under hooks/ were captured from real sessions (notes/diagnosis.md of 008).
# Every case runs on its own throwaway fixture (fixture.sh) and its own hook state folder.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
SA_DIR=$(cd "$(dirname "$SA_UNDER_TEST")" && pwd)
AGENTS="$SA_DIR/../agents"
SETTINGS="$SA_DIR/router-settings.json"
[ -f "$SETTINGS" ] || SETTINGS="$here/../router-settings.json"
# this test may itself run inside a Claude session: those variables would make every call a router child
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION SA_ROLE
sa() { bash "$SA_UNDER_TEST" "$@"; }
B='(🧭|🏛️|✍️|🔨|🤝|🐞|🧪|🔍|🔀|🌐|🐶|👤|❔)'
LINE='^'"$B"' [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| (dispatch|question|answer|report) \| .+$'

F=""; D=""; T=""; LOG=""; STATE=""
fail() { echo "$*"; exit 1; }
lines() { if [ -f "$1" ]; then grep -vc '^# ' "$1" || true; else echo 0; fi; }   # entries, not the legend
text() { sed 's/^[^|]*|[^|]*|[^|]*| //' ; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"
  STATE="$D/hook-state"; mkdir -p "$STATE"
  # SA_TIER=off: these cases test the logging with any model; the tier rule has its own test (tier-hook.test.sh)
  ( export SA_HOOK_STATE="$STATE" SA_TIER=off; "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}

# The hook command exactly as router-settings.json declares it, run with the sa under test.
declared() { # declared <PreToolUse|PostToolUse> <tool>: the args after the sa path of the hook for that tool
  perl -MJSON::PP -e '
    local $/; open my $f, "<", $ARGV[0] or exit 3; my $s = decode_json(<$f>);
    for my $m (@{ $s->{hooks}{$ARGV[1]} || [] }) {
      next unless $ARGV[2] =~ /^(?:$m->{matcher})$/;
      my $c = $m->{hooks}[0]{command};
      $c =~ s{^(?:~|\$HOME)/\.claude/superagent/sa\s+}{} or exit 4;
      print $c; exit 0 }
    exit 5' "$SETTINGS" "$1" "$2"
}
hook() { # hook <PreToolUse|PostToolUse> <tool> <payload file>: stdout to $D/hook.out, stderr to $D/hook.err
  local args
  args=$(declared "$1" "$2") || fail "router-settings.json declares no $1 hook for $2"
  # shellcheck disable=SC2086
  bash "$SA_UNDER_TEST" $args < "$3" > "$D/hook.out" 2> "$D/hook.err"
}
mk() { # mk <template> <out> [<path>=<json value>]...: a payload from a captured template, @F@ replaced by $F
  local tpl="$here/hooks/$1" out="$2"; shift 2
  perl -MJSON::PP -e '
    my ($tpl, $f, @set) = @ARGV; local $/; open my $h, "<", $tpl or die; my $s = <$h>; $s =~ s/\@F\@/$f/g;
    my $d = decode_json($s);
    for (@set) { my ($p, $v) = split /=/, $_, 2; my @k = split /\./, $p; my $x = \$d;
      $x = \(${$x}->{$_}) for @k[0 .. $#k - 1];
      if ($v eq "DEL") { delete ${$x}->{$k[-1]} } else { ${$x}->{$k[-1]} = JSON::PP->new->allow_nonref->decode($v) } }
    print JSON::PP->new->canonical->encode($d)' "$tpl" "$F" "$@" > "$out"
}
js() { perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$1"; }   # a JSON string
agent() { # agent <out> <role> <prompt> [<path>=<json>]...: an Agent PreToolUse payload of the router session
  local out="$1" role="$2" prompt="$3"; shift 3
  mk agent-pre.json "$out" "tool_input.subagent_type=$(js "$role")" "tool_input.prompt=$(js "$prompt")" "$@"
}
quiet() { # the hook printed nothing on stdout and at most one line on stderr
  [ ! -s "$D/hook.out" ] || fail "hook wrote on stdout: $(cat "$D/hook.out")"
  [ "$(wc -l < "$D/hook.err" | tr -d ' ')" -le 1 ] || fail "hook wrote more than one stderr line: $(cat "$D/hook.err")"
}
badge() { # badge <role>: the badge sa gives that role (written once in a scratch room)
  local w; w=$(mktemp -d "$D/b.XXXXXX"); mkdir -p "$w/t/001-x"; printf '# Project: b\nRoom: %s/room\n' "$w" > "$w/t/PROJECT.md"; : > "$w/t/001-x/rd.md"
  sa room event "$w/t/001-x" dispatch "$1" x >/dev/null; grep -v '^# ' "$w/room/b/LOG.md" | head -1 | cut -d' ' -f1
}
model_of() { sed -n '2,/^---/p' "$AGENTS/$1.md" | sed -n "s/^$2:[[:space:]]*//p" | head -1; }
last_text() { grep -v '^# ' "$1" | tail -1 | text; }

# --- dispatch (FR-1, FR-7) ---------------------------------------------------------------------------
c_e1_dispatch_real_values() {
  agent "$D/p.json" tester $'You are the tester.\nTicket folder: '"$T"$'\nStage: test\nDo the round.' \
    'tool_input.model="sonnet"' 'tool_input.effort="medium"'
  hook PreToolUse Agent "$D/p.json" || fail "hook exit $?"; quiet
  [ "$(lines "$LOG")" = 1 ] || fail "want one line: $(cat "$LOG" 2>/dev/null)"
  grep -v '^# ' "$LOG" | grep -qE "$LINE" || fail "format: $(cat "$LOG")"
  grep -v '^# ' "$LOG" | grep -qF ' | demo#001 | dispatch | ' || fail "ref/kind: $(cat "$LOG")"
  # the Agent call's description (the agent's name and task; "probe" in the captured payload) ends the line
  [ "$(last_text "$LOG")" = 'tester: started by router: stage test, model sonnet, effort medium, as probe' ] || fail "text: $(last_text "$LOG")"
  [ "$(grep -v '^# ' "$LOG" | cut -d' ' -f1)" = "$(badge tester)" ] || fail "want the tester's badge: $(cat "$LOG")"
}
c_e2_agent_defaults() {
  local m e
  agent "$D/p.json" codex-reviewer "Ticket folder: $T"$'\nStage: review round 1'  'tool_input.model=DEL' 'tool_input.effort=DEL'
  hook PreToolUse Agent "$D/p.json"; quiet
  m=$(model_of codex-reviewer model); e=$(model_of codex-reviewer effort)
  [ -n "$m" ] && [ -n "$e" ] || fail "codex-reviewer.md lacks model or effort"
  [ "$(last_text "$LOG")" = "codex-reviewer: started by router: stage review round 1, model $m (agent default), effort $e (agent default), as probe" ] || fail "codex: $(last_text "$LOG")"
  agent "$D/p2.json" worker "Ticket folder: $T"$'\nStage: build' 'tool_use_id="toolu_w2"' 'tool_input.model=DEL' 'tool_input.effort=DEL'
  hook PreToolUse Agent "$D/p2.json"; quiet
  m=$(model_of worker model); e=$(model_of worker effort)
  [ -z "$e" ] || fail "worker.md now sets effort; update this case"
  [ "$(last_text "$LOG")" = "worker: started by router: stage build, model $m (agent default), effort session default, as probe" ] || fail "worker: $(last_text "$LOG")"
}
c_e3_tickets_folder_and_stage() {
  agent "$D/p.json" ticket-writer "Tickets folder: $F/demo/tickets"$'\nStage: answer mode' 'tool_input.model="opus"' 'tool_input.effort="low"'
  hook PreToolUse Agent "$D/p.json"; quiet
  grep -v '^# ' "$LOG" | tail -1 | grep -qF ' | demo | dispatch | ' || fail "want ref demo: $(cat "$LOG")"
  [ "$(last_text "$LOG")" = 'ticket-writer: started by router: stage answer mode, model opus, effort low, as probe' ] || fail "$(last_text "$LOG")"
  agent "$D/p2.json" tester "Ticket folder: $T" 'tool_input.model="sonnet"' 'tool_input.effort="medium"' 'tool_use_id="toolu_e3b"'
  hook PreToolUse Agent "$D/p2.json"; quiet
  [ "$(last_text "$LOG")" = 'tester: started by router: stage unknown, model sonnet, effort medium, as probe' ] || fail "$(last_text "$LOG")"
}
c_e1_nested_project() {
  local L="$F/decision-room/group/app/LOG.md"
  agent "$D/p.json" worker "Ticket folder: $F/group/app/tickets/001-demo-ticket"$'\nStage: build' 'tool_input.model="opus"'
  hook PreToolUse Agent "$D/p.json"; quiet
  grep -v '^# ' "$L" | grep -qF ' | group/app#001 | dispatch | worker: started by router: stage build, model opus, effort low' || fail "nested: $(cat "$L" 2>/dev/null)"
  # the started worker's own line is claimed, though its ref holds a "/"
  CLAUDE_CODE_SESSION_ID=e5ae8e19-c0b8-4a8f-b37a-13dc1fae8cef CLAUDE_CODE_CHILD_SESSION=1 \
    sa room event "$F/group/app/tickets/001-demo-ticket" dispatch worker "started by unknown: stage build, model unknown, effort unknown" > "$D/o" || fail "event failed"
  grep -qx logged "$D/o" || fail "output: $(cat "$D/o")"
  [ "$(lines "$L")" = 1 ] || fail "the claim did not hold: $(cat "$L")"
}

# --- one line per start (FR-2, E-2b, N-3, row 16) -------------------------------------------------------
SID=e5ae8e19-c0b8-4a8f-b37a-13dc1fae8cef
child() { CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CODE_CHILD_SESSION=1 sa room event "$T" dispatch tester "started by unknown: stage test, model unknown, effort unknown"; }
manual() { sa room event "$T" dispatch tester "started by unknown: stage test, model unknown, effort unknown"; }
markers() { find "$F/decision-room/demo/.hooks/dispatched" -type f ! -name '*.claimed.*' ! -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' '; }
dispatch_tester() { # dispatch_tester <tool_use_id>: a marker-free brief (no Launched by: line)
  agent "$D/p-$1.json" tester "Ticket folder: $T"$'\nStage: test' "tool_use_id=\"$1\""
  hook PreToolUse Agent "$D/p-$1.json"; quiet
}
c_e2b_claims() {
  local o
  dispatch_tester toolu_a; dispatch_tester toolu_b
  [ "$(lines "$LOG")" = 2 ] || fail "two hook lines: $(cat "$LOG")"
  [ "$(markers)" = 2 ] || fail "two markers expected, found $(markers)"
  o=$(child); [ "$o" = logged ] || fail "child 1: $o"
  o=$(child); [ "$o" = logged ] || fail "child 2: $o"
  [ "$(lines "$LOG")" = 2 ] || fail "the agents' own lines were added: $(cat "$LOG")"
  [ "$(markers)" = 0 ] || fail "markers left: $(markers)"
  dispatch_tester toolu_c; [ "$(markers)" = 1 ] || fail "fresh marker missing"
  o=$(manual); [ "$o" = logged ] || fail "manual: $o"
  [ "$(lines "$LOG")" = 4 ] || fail "a manual start must write: $(cat "$LOG")"
  [ "$(markers)" = 1 ] || fail "a manual start must not take the marker"
  dispatch_tester toolu_d; [ "$(markers)" = 2 ] || fail "step-5 marker missing"
  o=$(CLAUDE_CODE_SESSION_ID=other-session CLAUDE_CODE_CHILD_SESSION=1 sa room event "$T" dispatch tester "started by unknown: x") ; [ "$o" = logged ] || fail "other session: $o"
  [ "$(lines "$LOG")" = 6 ] || fail "another session's start must write: $(cat "$LOG")"
  [ "$(markers)" = 2 ] || fail "another session must not take a marker"
}
c_e2b_expired_marker() {
  local f o
  dispatch_tester toolu_old
  f=$(find "$F/decision-room/demo/.hooks/dispatched" -type f | head -1)
  [ -n "$f" ] && [ "$(markers)" = 1 ] || fail "no unclaimed marker"
  touch -t "$(date -v-10M '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '-10 min' '+%Y%m%d%H%M.%S')" "$f"
  o=$(child); [ "$o" = logged ] || fail "child: $o"
  [ "$(lines "$LOG")" = 2 ] || fail "an aged marker must not swallow the start: $(cat "$LOG")"
}
c_n3_manual_and_child() {
  local o
  o=$(manual); [ "$o" = logged ] || fail "(a) $o"; [ "$(lines "$LOG")" = 1 ] || fail "(a) one line"
  dispatch_tester toolu_n3
  o=$(child); [ "$o" = logged ] || fail "(b) $o"; [ "$(lines "$LOG")" = 2 ] || fail "(b) the child added a line: $(cat "$LOG")"
  dispatch_tester toolu_n3c
  o=$(manual); [ "$o" = logged ] || fail "(c) $o"; [ "$(lines "$LOG")" = 4 ] || fail "(c) no line"
  [ "$(markers)" = 1 ] || fail "(c) the marker must stay"
}
c_row16_concurrent_claims() {
  dispatch_tester toolu_x
  : > "$F/decision-room/demo/.hooks/dispatched/toolu_zz.claimed.1"   # a leftover is never taken
  child > "$D/c1" & child > "$D/c2" & wait
  grep -qx logged "$D/c1" && grep -qx logged "$D/c2" || fail "outputs: $(cat "$D/c1" "$D/c2")"
  [ "$(lines "$LOG")" = 2 ] || fail "one claim and one write expected: $(cat "$LOG")"
  [ -f "$F/decision-room/demo/.hooks/dispatched/toolu_zz.claimed.1" ] || fail "the leftover was touched"
}

# --- questions and answers (FR-3, FR-4, FR-5) ------------------------------------------------------------
L_APP() { echo "$F/decision-room/group/app/LOG.md"; }
c_e4_e5_questions_and_answers() {
  mk ask-pre-option.json "$D/q1.json"; hook PreToolUse AskUserQuestion "$D/q1.json"; quiet
  [ "$(lines "$LOG")" = 1 ] || fail "q1: $(cat "$LOG" 2>/dev/null)"
  grep -v '^# ' "$LOG" | grep -qF ' | demo#001 | question | ' || fail "q1 ref: $(cat "$LOG")"
  [ "$(last_text "$LOG")" = 'router: asked the user: demo#001 Demo ticket: approve the plan? | options: (a) Approve (Recommended) - go; (b) Change it - edit' ] || fail "q1: $(last_text "$LOG")"
  [ "$(grep -v '^# ' "$LOG" | cut -d' ' -f1)" = "$(badge router)" ] || fail "router badge"
  mk ask-pre-other.json "$D/q2.json"; hook PreToolUse AskUserQuestion "$D/q2.json"; quiet
  [ "$(lines "$(L_APP)")" = 1 ] || fail "q2 in group/app: $(cat "$(L_APP)" 2>/dev/null)"
  [ "$(lines "$LOG")" = 1 ] || fail "q2 leaked into demo"
  [ "$(last_text "$(L_APP)")" = 'router: asked the user: app#001 Demo ticket: merge it? | options: (a) Merge (Recommended) - land it; (b) Not yet - wait' ] || fail "q2: $(last_text "$(L_APP)")"
  mk ask-post-option.json "$D/a1.json"; hook PostToolUse AskUserQuestion "$D/a1.json"; quiet
  [ "$(last_text "$LOG")" = 'router: Plan answered by the user: Approve (Recommended) | question: demo#001 Demo ticket: approve the plan?' ] || fail "a1: $(last_text "$LOG")"
  mk ask-post-other.json "$D/a2.json"; hook PostToolUse AskUserQuestion "$D/a2.json"; quiet
  [ "$(lines "$(L_APP)")" = 2 ] || fail "a2 split or missing: $(cat "$(L_APP)")"
  [ "$(last_text "$(L_APP)")" = 'router: Merge answered by the user: merge it, but "only" after 007 | not before | question: app#001 Demo ticket: merge it?' ] || fail "a2: $(last_text "$(L_APP)")"
}
c_e5_multi_and_unanswered() {
  local G="$F/decision-room/LOG.md"
  mk ask-post-multi.json "$D/m.json"; hook PostToolUse AskUserQuestion "$D/m.json"; quiet
  [ "$(last_text "$G")" = 'router: Checks answered by the user: Unit, Lint | question: Which checks should run?' ] || fail "multi: $(cat "$G" 2>/dev/null)"
  # a result that does not hold the answer: the question keeps its question line and gets no answer line (D10)
  mk ask-post-option.json "$D/u.json" 'tool_response.answers={}' 'tool_use_id="toolu_u"'
  hook PostToolUse AskUserQuestion "$D/u.json"; quiet
  [ "$(lines "$LOG")" = 0 ] || fail "an outcome was invented: $(cat "$LOG")"
}
c_e6_no_project_goes_to_room_log() {
  local G="$F/decision-room/LOG.md" q
  q='{"questions":[{"question":"Stop all running tickets?","header":"Stop","options":[{"label":"Stop all","description":"s"},{"label":"Keep going","description":"k"}],"multiSelect":false}]}'
  mk ask-pre-option.json "$D/q.json" "tool_input=$q" 'tool_use_id="toolu_s"'
  hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  mk ask-post-option.json "$D/a.json" "tool_input=$q" "tool_response=$(perl -MJSON::PP -e 'my $d=decode_json($ARGV[0]); $d->{answers}={"Stop all running tickets?"=>"Keep going"}; print encode_json($d)' "$q")" 'tool_use_id="toolu_s"'
  hook PostToolUse AskUserQuestion "$D/a.json"; quiet
  [ "$(lines "$G")" = 2 ] || fail "room log: $(cat "$G" 2>/dev/null)"
  grep -v '^# ' "$G" | grep -qF ' | router | question | router: asked the user: Stop all running tickets?' || fail "q: $(cat "$G")"
  grep -v '^# ' "$G" | grep -qF ' | router | answer | router: Stop answered by the user: Keep going | question: Stop all running tickets?' || fail "a: $(cat "$G")"
  [ "$(lines "$LOG")" = 0 ] && [ "$(lines "$(L_APP)")" = 0 ] || fail "a project log changed"
}
ask_text() { # ask_text <out> <tool_use_id> <question>
  local q; q=$(perl -MJSON::PP -e 'print encode_json({questions=>[{question=>$ARGV[0],header=>"H",options=>[{label=>"Yes",description=>"y"},{label=>"No",description=>"n"}],multiSelect=>JSON::PP::false}]})' "$3")
  mk ask-pre-option.json "$1" "tool_input=$q" "tool_use_id=\"$2\""
}
c_e6_absolute_entry_external_room() {
  local X="$D/abs" L
  mkdir -p "$X/docs/tickets"; printf '# Project: absproj\nRoom: %s/decision-room\n' "$F" > "$X/docs/tickets/PROJECT.md"
  printf '# Board\n' > "$X/docs/tickets/BOARD.md"
  printf -- '- [x] %s  <!-- absolute -->\n' "$X" >> "$F/ACTIVE-PROJECTS.md"
  L="$F/decision-room/absproj/LOG.md"; [ ! -e "$L" ] || fail "log exists before"
  [ ! -e "$F/decision-room/.hooks" ] || fail "registry not empty"
  ask_text "$D/q.json" toolu_abs 'absproj#004 Ready to build?'; hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  grep -v '^# ' "$L" 2>/dev/null | grep -qF ' | absproj#004 | question | router: asked the user: absproj#004 Ready to build?' || fail "absolute entry: $(cat "$L" 2>/dev/null)"
  # a Room: project known only by a path in the question, before any dispatch or log
  local E="$D/ext" LE="$F/decision-room/extproj/LOG.md"
  mkdir -p "$E/tickets"; printf '# Project: extproj\nRoom: %s/decision-room\n' "$F" > "$E/tickets/PROJECT.md"
  ask_text "$D/q2.json" toolu_ext "extproj#002 merge it? ($E/tickets/002-x)"; hook PreToolUse AskUserQuestion "$D/q2.json"; quiet
  grep -v '^# ' "$LE" 2>/dev/null | grep -qF ' | extproj#002 | question | ' || fail "path-named project: $(cat "$LE" 2>/dev/null)"
  [ "$(lines "$F/decision-room/LOG.md")" = 0 ] || fail "went to the room log instead"
}
c_e6_standalone_router_room_log() {
  local P="$D/solo" G="$D/solo-room/LOG.md" q
  mkdir -p "$P/tickets"; printf '# Project: solo\nRoom: %s/solo-room\n' "$D" > "$P/tickets/PROJECT.md"; printf '# Board\n' > "$P/tickets/BOARD.md"
  q='{"questions":[{"question":"Stop all running tickets?","header":"Stop","options":[{"label":"Stop all","description":"s"}],"multiSelect":false}]}'
  mk ask-pre-option.json "$D/q.json" "tool_input=$q" 'tool_use_id="toolu_solo"' "cwd=$(js "$P")"
  hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  grep -v '^# ' "$G" 2>/dev/null | grep -qF ' | router | question | router: asked the user: Stop all running tickets?' || fail "standalone room log: $(cat "$G" 2>/dev/null)"
  [ "$(lines "$D/solo-room/solo/LOG.md")" = 0 ] || fail "went to the project log"
}
c_d11_outside_room_project_registered() {
  local X="$D/ext2" L="$F/decision-room/ext2/LOG.md" q a
  mkdir -p "$X/tickets/003-x"; printf '# Project: ext2\nRoom: %s/decision-room\n' "$F" > "$X/tickets/PROJECT.md"
  printf '# 003: x\n' > "$X/tickets/003-x/rd.md"
  grep -qF ext2 "$F/ACTIVE-PROJECTS.md" && fail "fixture: ext2 is ticked"
  agent "$D/p.json" worker "Ticket folder: $X/tickets/003-x"$'\nStage: build' 'tool_use_id="toolu_ext2"'
  hook PreToolUse Agent "$D/p.json"; quiet
  [ "$(lines "$L")" = 1 ] || fail "dispatch: $(cat "$L" 2>/dev/null)"
  q='{"questions":[{"question":"ext2#003 merge it?","header":"Merge","options":[{"label":"Merge","description":"m"},{"label":"Not yet","description":"n"}],"multiSelect":false}]}'
  a=$(perl -MJSON::PP -e 'my $d=decode_json($ARGV[0]); $d->{answers}={"ext2#003 merge it?"=>"Merge"}; print encode_json($d)' "$q")
  mk ask-pre-option.json "$D/q.json" "tool_input=$q" 'tool_use_id="toolu_q11"'; hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  mk ask-post-option.json "$D/a.json" "tool_input=$q" "tool_response=$a" 'tool_use_id="toolu_q11"'; hook PostToolUse AskUserQuestion "$D/a.json"; quiet
  [ "$(lines "$L")" = 3 ] || fail "question and answer did not reach ext2's log: $(cat "$L" 2>/dev/null)"
  grep -v '^# ' "$L" | grep -qF ' | ext2#003 | answer | router: Merge answered by the user: Merge | question: ext2#003 merge it?' || fail "answer: $(cat "$L")"
  [ "$(lines "$F/decision-room/LOG.md")" = 0 ] || fail "went to the room's own log: $(cat "$F/decision-room/LOG.md")"
}
c_row15_same_basename() {
  local O="$F/other/app" LO="$F/decision-room/other/app/LOG.md"
  mkdir -p "$O/tickets"; printf '# Project: app2\n' > "$O/tickets/PROJECT.md"; printf '# Board\n' > "$O/tickets/BOARD.md"
  printf -- '- [x] other/app\n' >> "$F/ACTIVE-PROJECTS.md"
  ask_text "$D/q.json" toolu_full 'group/app#001 merge it?'; hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  [ "$(lines "$(L_APP)")" = 1 ] || fail "full ref missed group/app"
  [ "$(lines "$LO")" = 0 ] || fail "full ref leaked to other/app: $(cat "$LO")"
  ask_text "$D/q2.json" toolu_amb 'app#001 merge it?'; hook PreToolUse AskUserQuestion "$D/q2.json"; quiet
  [ "$(lines "$(L_APP)")" = 1 ] && [ "$(lines "$LO")" = 0 ] || fail "an ambiguous alias reached a project"
  ask_text "$D/q3.json" toolu_alias 'app2#003 and other/app#003: ship?'; hook PreToolUse AskUserQuestion "$D/q3.json"; quiet
  [ "$(lines "$LO")" = 1 ] || fail "two names of one project must give one line: $(cat "$LO" 2>/dev/null)"
}

# --- never in the way, router only, once per delivery (FR-6, E-12, X-1, X-2) ---------------------------
c_e12_dedupe_and_gating() {
  agent "$D/p.json" tester "Ticket folder: $T"$'\nStage: test' 'tool_input.model="sonnet"' 'tool_input.effort="medium"'
  hook PreToolUse Agent "$D/p.json"; hook PreToolUse Agent "$D/p.json"
  [ "$(lines "$LOG")" = 1 ] || fail "replay wrote twice"
  agent "$D/c.json" tester "Ticket folder: $T"$'\nStage: test' 'tool_use_id="toolu_conc"'
  (hook PreToolUse Agent "$D/c.json") & (hook PreToolUse Agent "$D/c.json") & wait
  [ "$(lines "$LOG")" = 2 ] || fail "concurrent runs: $(cat "$LOG")"
  mk ask-pre-option.json "$D/q.json"; hook PreToolUse AskUserQuestion "$D/q.json"; hook PreToolUse AskUserQuestion "$D/q.json"
  mk ask-post-option.json "$D/a.json"; hook PostToolUse AskUserQuestion "$D/a.json"; hook PostToolUse AskUserQuestion "$D/a.json"
  [ "$(lines "$LOG")" = 4 ] || fail "question/answer replay: $(cat "$LOG")"
  agent "$D/n.json" tester "Ticket folder: $T" 'tool_use_id="toolu_nr"' 'agent_type="worker"'; hook PreToolUse Agent "$D/n.json"; quiet
  agent "$D/s.json" tester "Ticket folder: $T" 'tool_use_id="toolu_sub"' 'agent_id="a123"'; hook PreToolUse Agent "$D/s.json"; quiet
  mk ask-pre-option.json "$D/sq.json" 'tool_use_id="toolu_sq"' 'agent_id="a123"'; hook PreToolUse AskUserQuestion "$D/sq.json"; quiet
  [ "$(lines "$LOG")" = 4 ] || fail "a non-router call was logged: $(cat "$LOG")"
  [ "$(lines "$F/decision-room/LOG.md")" = 0 ] || fail "room log changed"
}
timed() { # timed <PreToolUse|PostToolUse> <tool> <payload>: run the hook, fail beyond 2 seconds or on a non-zero exit
  local s e rc; s=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  hook "$@"; rc=$?
  e=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  [ "$rc" = 0 ] || fail "exit $rc"
  perl -e 'exit(($ARGV[1] - $ARGV[0]) <= 2 ? 0 : 1)' "$s" "$e" || fail "took $s -> $e"
  quiet
}
c_x1_never_in_the_way() {
  printf 'not json' > "$D/bad.json"; timed PreToolUse Agent "$D/bad.json"; timed PostToolUse AskUserQuestion "$D/bad.json"
  agent "$D/o.json" tester "Ticket folder: $D/outside/tickets/001-demo-ticket"$'\nStage: test' 'tool_use_id="toolu_o"'; timed PreToolUse Agent "$D/o.json"
  agent "$D/n.json" tester $'no folder line\nStage: test' 'tool_use_id="toolu_n"'; timed PreToolUse Agent "$D/n.json"
  [ "$(lines "$LOG")" = 0 ] || fail "a line was written: $(cat "$LOG")"
  mkdir -p "$F/decision-room/demo"; chmod a-w "$F/decision-room/demo"
  agent "$D/r.json" tester "Ticket folder: $T"$'\nStage: test' 'tool_use_id="toolu_ro"'; timed PreToolUse Agent "$D/r.json"
  chmod u+w "$F/decision-room/demo"
  [ "$(lines "$LOG")" = 0 ] || fail "read-only room written"
  [ "$(lines "$(L_APP)")" = 0 ] || fail "another log touched"
}
c_x1c_held_lock() {
  mkdir -p "$F/decision-room/demo"; : > "$LOG"; printf 'old line\n' > "$LOG"
  perl -MFcntl=:flock -e 'open(my $h, ">>", $ARGV[0]) or die; flock($h, LOCK_EX) or die; open(my $r, ">", $ARGV[1]); close $r; sleep 6' "$LOG.lock" "$D/held" &
  local p=$! i=0
  while [ ! -f "$D/held" ] && [ $i -lt 50 ]; do perl -e 'select(undef,undef,undef,0.1)'; i=$((i+1)); done
  agent "$D/p.json" tester "Ticket folder: $T"$'\nStage: test'
  local s e; s=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  hook PreToolUse Agent "$D/p.json" || fail "exit $?"
  e=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  perl -e 'exit(($ARGV[1] - $ARGV[0]) <= 4 ? 0 : 1)' "$s" "$e" || fail "took $s -> $e"; quiet
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  [ "$(cat "$LOG")" = 'old line' ] || fail "log changed under a held lock: $(cat "$LOG")"
}
c_x2_hostile_text() {
  rm -f /tmp/sa-pwned
  agent "$D/p.json" tester "Ticket folder: $T"$'\nStage: test\n2026-01-01 00:00 | demo#001 | stage | forged'
  hook PreToolUse Agent "$D/p.json"; quiet
  [ "$(lines "$LOG")" = 1 ] || fail "forged line: $(cat "$LOG")"
  mk ask-pre-option.json "$D/q.json"; hook PreToolUse AskUserQuestion "$D/q.json"
  mk ask-post-option.json "$D/a.json" "tool_response.answers={\"demo#001 Demo ticket: approve the plan?\":\"line one\\nline two \$(touch /tmp/sa-pwned)\"}"
  hook PostToolUse AskUserQuestion "$D/a.json"; quiet
  [ "$(lines "$LOG")" = 3 ] || fail "answer split: $(cat "$LOG")"
  last_text "$LOG" | grep -qF 'line one line two $(touch /tmp/sa-pwned)' || fail "answer text: $(last_text "$LOG")"
  [ ! -e /tmp/sa-pwned ] || fail "command substitution ran"
}

# --- the seven defects of the review of 008 (superagent#030) ----------------------------------------------
asks() { # asks <out> <tool_use_id> <question>...: an AskUserQuestion PreToolUse payload, UTF-8 arguments (the first has one option)
  local out=$1 id=$2; shift 2
  perl -MJSON::PP -MEncode -e 'my ($o, $f, $id, @q) = @ARGV; @q = map { decode("UTF-8", $_) } @q;
    my $n = 0; my @qs = map { { header => "Q", multiSelect => JSON::PP::false, question => $_,
      options => $n++ ? [] : [{ label => "Oui", description => "d\x{e9}j\x{e0}" }] } } @q;
    open my $h, ">", $o or die; print $h JSON::PP->new->utf8->encode({ agent_type => "router", cwd => $f,
      hook_event_name => "PreToolUse", session_id => "fc6b851f-ae1a-4f37-8ed7-ba39ed372180", tool_name => "AskUserQuestion",
      tool_use_id => $id, tool_input => { questions => \@qs } })' "$out" "$F" "$id" "$@"
}
c_u1_accented_text() {
  asks "$D/q1.json" toolu_u1a 'demo#001 déployer §7 ?'; hook PreToolUse AskUserQuestion "$D/q1.json"; quiet
  asks "$D/q2.json" toolu_u1b 'déployer demo#001 ?'; hook PreToolUse AskUserQuestion "$D/q2.json"; quiet
  [ "$(lines "$LOG")" = 2 ] || fail "want two lines: $(cat "$LOG" 2>/dev/null)"
  grep -v '^# ' "$LOG" | grep -qF ' | demo#001 | question | ' || fail "ref: $(cat "$LOG")"
  [ "$(grep -v '^# ' "$LOG" | head -1 | text)" = 'router: asked the user: demo#001 déployer §7 ? | options: (a) Oui - déjà' ] || fail "text: $(cat "$LOG")"
  [ "$(grep -v '^# ' "$LOG" | grep -cF ' | demo#001 | question | ')" = 2 ] || fail "both lines need the ref demo#001: $(cat "$LOG")"
  [ "$(last_text "$LOG")" = 'router: asked the user: déployer demo#001 ? | options: (a) Oui - déjà' ] || fail "second: $(last_text "$LOG")"
  iconv -f utf-8 -t utf-8 < "$LOG" > /dev/null || fail "the log is not UTF-8"
  [ "$(lines "$F/decision-room/LOG.md")" = 0 ] || fail "the room's own log got a line"
}
c_x1d_lock_released() {
  mkdir -p "$F/decision-room/demo"; : > "$LOG"
  perl -MFcntl=:flock -e 'open(my $h, ">>", $ARGV[0]) or die; flock($h, LOCK_EX) or die; open(my $r, ">", $ARGV[1]); close $r; sleep 1' "$LOG.lock" "$D/held" &
  local p=$! i=0
  while [ ! -f "$D/held" ] && [ $i -lt 50 ]; do perl -e 'select(undef,undef,undef,0.1)'; i=$((i+1)); done
  agent "$D/p.json" tester "Ticket folder: $T"$'\nStage: test'
  local s e; s=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  hook PreToolUse Agent "$D/p.json" || fail "exit $?"
  e=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  perl -e 'exit(($ARGV[1] - $ARGV[0]) <= 4 ? 0 : 1)' "$s" "$e" || fail "took $s -> $e"; quiet
  wait "$p" 2>/dev/null
  [ "$(last_text "$LOG" | cut -c1-30)" = 'tester: started by router: sta' ] || fail "no dispatch line: $(cat "$LOG")"
}
c_x1d_busy_log() {
  local r i
  for r in 1 2 3 4 5 6 7 8 9 10; do
    for i in $(seq 20); do SA_ROLE=worker bash "$SA_UNDER_TEST" room event "$T" report worker "ready: x $r $i" > /dev/null 2>&1 & done
    agent "$D/p$r.json" tester "Ticket folder: $T"$'\nStage: test' "tool_use_id=\"toolu_busy$r\""
    hook PreToolUse Agent "$D/p$r.json" || fail "hook exit $?"
    wait
  done
  [ "$(grep -c 'started by router' "$LOG")" = 10 ] || fail "dispatch lines: $(grep -c 'started by router' "$LOG")"
  [ "$(grep -c 'ready: x' "$LOG")" = 200 ] || fail "reports: $(grep -c 'ready: x' "$LOG")"
}
c_x1e_two_failed_writes() {
  local G="$F/decision-room/group/app/LOG.md"
  mkdir -p "$F/decision-room/demo"; chmod a-w "$F/decision-room/demo"
  asks "$D/q.json" toolu_x1e 'demo#001 one?' 'demo#001 two?' 'group/app#001 three?'
  hook PreToolUse AskUserQuestion "$D/q.json"; local rc=$?
  chmod u+w "$F/decision-room/demo"
  [ "$rc" = 0 ] || fail "exit $rc"; quiet
  [ "$(lines "$G")" = 1 ] && grep -qF 'group/app#001 three?' "$G" || fail "the third question was lost: $(cat "$G" 2>/dev/null)"
  [ ! -e "$LOG" ] || fail "demo's log was written"
}
c_e3b_ticket_folder_wins() {
  agent "$D/p1.json" tester "Ticket folder: $T"$'\nTickets folder: '"$F/demo/tickets"$'\nStage: test' 'tool_use_id="toolu_w1"'
  agent "$D/p2.json" tester "Tickets folder: $F/demo/tickets"$'\nTicket folder: '"$T"$'\nStage: test' 'tool_use_id="toolu_w2"'
  hook PreToolUse Agent "$D/p1.json"; quiet; hook PreToolUse Agent "$D/p2.json"; quiet
  [ "$(grep -v '^# ' "$LOG" | grep -cF ' | demo#001 | dispatch | ')" = 2 ] || fail "want two lines with the ref demo#001: $(cat "$LOG" 2>/dev/null)"
}
c_x3_not_a_tickets_folder() {
  local before after
  before=$(find "$F/decision-room" 2>/dev/null | sort)
  mkdir -p "$F/demo/tickets/002-new" "$F/loose/003-x"; : > "$F/loose/003-x/rd.md"
  agent "$D/p1.json" tester "Ticket folder: $F/demo/tickets/002-new" 'tool_use_id="toolu_n1"'
  agent "$D/p2.json" tester "Tickets folder: $F/demo" 'tool_use_id="toolu_n2"'
  agent "$D/p3.json" tester "Ticket folder: $F/loose/003-x" 'tool_use_id="toolu_n3"'
  hook PreToolUse Agent "$D/p1.json" || fail "exit $?"; hook PreToolUse Agent "$D/p2.json" || fail "exit $?"; hook PreToolUse Agent "$D/p3.json" || fail "exit $?"
  after=$(find "$F/decision-room" 2>/dev/null | sort)
  [ "$before" = "$after" ] || fail "the room changed: $after"
  agent "$D/p4.json" tester "Tickets folder: $F/demo/tickets" 'tool_use_id="toolu_n4"'; hook PreToolUse Agent "$D/p4.json"; quiet
  grep -v '^# ' "$LOG" | grep -qF ' | demo | dispatch | ' || fail "a real tickets folder was not logged: $(cat "$LOG" 2>/dev/null)"
}
c_e6b_project_name_case() {
  asks "$D/q.json" toolu_e6b 'Demo#001 go?' 'APP#001 go?'
  hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  grep -v '^# ' "$LOG" | grep -qF ' | demo#001 | question | ' || fail "demo: $(cat "$LOG" 2>/dev/null)"
  grep -v '^# ' "$(L_APP)" | grep -qF ' | group/app#001 | question | ' || fail "app: $(cat "$(L_APP)" 2>/dev/null)"
  [ "$(lines "$F/decision-room/LOG.md")" = 0 ] || fail "the room's own log got a line"
}
c_e6c_exact_case_wins() {
  local C="$F/cap/x" LC="$F/decision-room/cap/x/LOG.md"
  mkdir -p "$C/tickets"; printf '# Project: App\n' > "$C/tickets/PROJECT.md"; printf '# Board\n' > "$C/tickets/BOARD.md"
  printf -- '- [x] cap/x\n' >> "$F/ACTIVE-PROJECTS.md"
  asks "$D/q.json" toolu_e6c 'App#001 go?' 'app#001 go?' 'app go?'
  hook PreToolUse AskUserQuestion "$D/q.json"; quiet
  [ "$(lines "$LC")" = 1 ] && grep -qF 'App#001 go?' "$LC" || fail "exact App went wrong: $(cat "$LC" 2>/dev/null)"
  [ "$(lines "$(L_APP)")" = 2 ] || fail "exact app / bare app: $(cat "$(L_APP)" 2>/dev/null)"
}

# --- documents (FR-2 role files, FR-7 router brief, FR-9 protocol) --------------------------------------
c_e7_role_files() {
  local r
  for r in checker codex-reviewer decision-room merger reproducer teammate tester ticket-writer worker; do
    grep -m1 'very first action' "$AGENTS/$r.md" | grep -qF 'Launched by: router' || fail "$r.md: first action does not name Launched by: router"
  done
  grep -qF 'Launched by: router' "$SA_DIR/PROTOCOL.md" || fail "PROTOCOL.md"
}
c_e9_router_brief() {
  local l; l=$(grep -F '**Every brief**' "$AGENTS/router.md")
  for w in 'Ticket folder: <absolute path>' 'Tickets folder: <absolute path>' 'Stage: <stage or mode>' 'Launched by: router' 'Run: model'; do
    printf '%s' "$l" | grep -qF "$w" || fail "router brief rule lacks: $w"
  done
  grep -qF -- '--settings ~/.claude/superagent/router-settings.json' "$AGENTS/router.md" || fail "launch command lacks --settings"
}
c_e10_protocol() {
  grep -qF 'started by router: stage <stage>, model <model>, effort <effort>' "$SA_DIR/PROTOCOL.md" || fail "dispatch shape"
  grep -qF 'router: asked the user: <question text> | options:' "$SA_DIR/PROTOCOL.md" || fail "question shape"
  grep -qF 'answered by the user: <the answer verbatim> | question:' "$SA_DIR/PROTOCOL.md" || fail "answer shape"
}

run_case e1-dispatch-real-values c_e1_dispatch_real_values
run_case e2-agent-defaults c_e2_agent_defaults
run_case e3-tickets-folder-and-stage c_e3_tickets_folder_and_stage
run_case e1-nested-project c_e1_nested_project
run_case e2b-claims c_e2b_claims
run_case e2b-expired-marker c_e2b_expired_marker
run_case n3-manual-and-child c_n3_manual_and_child
run_case row16-concurrent-claims c_row16_concurrent_claims
run_case e4-e5-questions-and-answers c_e4_e5_questions_and_answers
run_case e5-multi-and-unanswered c_e5_multi_and_unanswered
run_case e6-no-project-room-log c_e6_no_project_goes_to_room_log
run_case e6-absolute-entry-external-room c_e6_absolute_entry_external_room
run_case e6-standalone-router-room-log c_e6_standalone_router_room_log
run_case d11-outside-room-project-registered c_d11_outside_room_project_registered
run_case row15-same-basename c_row15_same_basename
run_case e12-dedupe-and-gating c_e12_dedupe_and_gating
run_case x1-never-in-the-way c_x1_never_in_the_way
run_case x1c-held-lock c_x1c_held_lock
run_case x1d-lock-released c_x1d_lock_released
run_case x1d-busy-log c_x1d_busy_log
run_case x1e-two-failed-writes c_x1e_two_failed_writes
run_case u1-accented-text c_u1_accented_text
run_case e3b-ticket-folder-wins c_e3b_ticket_folder_wins
run_case x3-not-a-tickets-folder c_x3_not_a_tickets_folder
run_case e6b-project-name-case c_e6b_project_name_case
run_case e6c-exact-case-wins c_e6c_exact_case_wins
run_case x2-hostile-text c_x2_hostile_text
run_case e7-role-files c_e7_role_files
run_case e9-router-brief c_e9_router_brief
run_case e10-protocol c_e10_protocol
