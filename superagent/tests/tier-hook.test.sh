#!/usr/bin/env bash
# tier-hook.test.sh: `sa room hook pre` refuses an Agent start above the tier (the owner's rule of 2026-11-22) with
# exit 2 and one stderr line, before the agent starts, and logs no dispatch for it; everything else passes as before.
# Payloads come from the captured template hooks/agent-pre.json. Every case runs on its own fixture and hook state.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
SETTINGS="$here/../router-settings.json"
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION SA_ROLE SA_TIER
export SA_TIER_SESSION=new   # these cases judge a router started after router.md last changed; one case below is an older one
sa() { bash "$SA_UNDER_TEST" "$@"; }

F=""; D=""; T=""; LOG=""; RC=0
fail() { echo "$*"; exit 1; }
lines() { if [ -f "$1" ]; then grep -vc '^# ' "$1" || true; else echo 0; fi; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); T="$F/demo/tickets/001-demo-ticket"; LOG="$F/decision-room/demo/LOG.md"
  mkdir -p "$D/hook-state"
  ( export SA_HOOK_STATE="$D/hook-state"; "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}
js() { perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$1"; }
agent() { # agent <out> <role> <prompt> [<path>=<json>|DEL]...: an Agent PreToolUse payload of the router session
  local out="$1" role="$2" prompt="$3"; shift 3
  perl -MJSON::PP -e '
    my ($tpl, $f, @set) = @ARGV; local $/; open my $h, "<", $tpl or die; my $s = <$h>; $s =~ s/\@F\@/$f/g;
    my $d = decode_json($s);
    for (@set) { my ($p, $v) = split /=/, $_, 2; my @k = split /\./, $p; my $x = \$d;
      $x = \(${$x}->{$_}) for @k[0 .. $#k - 1];
      if ($v eq "DEL") { delete ${$x}->{$k[-1]} } else { ${$x}->{$k[-1]} = JSON::PP->new->allow_nonref->decode($v) } }
    print JSON::PP->new->canonical->encode($d)' "$here/hooks/agent-pre.json" "$F" \
    "tool_input.subagent_type=$(js "$role")" "tool_input.prompt=$(js "$prompt")" "$@" > "$out"
}
hook() { # hook <payload>: the PreToolUse hook as router-settings.json declares it; sets RC
  local args
  args=$(perl -MJSON::PP -e 'local $/; open my $f, "<", $ARGV[0] or exit 3; my $s = decode_json(<$f>);
    my $c = $s->{hooks}{PreToolUse}[0]{hooks}[0]{command}; $c =~ s{^(?:~|\$HOME)/\.claude/superagent/sa\s+}{} or exit 4; print $c' "$SETTINGS") ||
    fail "router-settings.json declares no PreToolUse hook"
  # shellcheck disable=SC2086
  bash "$SA_UNDER_TEST" $args < "$1" > "$D/hook.out" 2> "$D/hook.err"; RC=$?
}
passes() { # passes <payload>: exit 0, nothing on stdout, a dispatch line logged
  local n; n=$(lines "$LOG")
  hook "$1"
  [ "$RC" = 0 ] || fail "want exit 0, got $RC: $(cat "$D/hook.err")"
  [ ! -s "$D/hook.out" ] && [ ! -s "$D/hook.err" ] || fail "output: $(cat "$D/hook.out" "$D/hook.err")"
  [ "$(lines "$LOG")" = $((n + 1)) ] && grep -v '^# ' "$LOG" | tail -1 | grep -qF ' | dispatch | ' || fail "no dispatch line: $(cat "$LOG" 2>/dev/null)"
}
refused() { # refused <payload> <text the line must hold>: exit 2, one stderr line, no dispatch, one note
  local n; n=$(lines "$LOG")
  hook "$1"
  [ "$RC" = 2 ] || fail "want exit 2, got $RC: $(cat "$D/hook.err")"
  [ ! -s "$D/hook.out" ] || fail "stdout: $(cat "$D/hook.out")"
  [ "$(wc -l < "$D/hook.err" | tr -d ' ')" = 1 ] || fail "want one stderr line: $(cat "$D/hook.err")"
  grep -q '^refused: ' "$D/hook.err" && grep -qF -- "$2" "$D/hook.err" || fail "message: $(cat "$D/hook.err")"
  grep -qF 'Tier rule of 2026-11-22' "$D/hook.err" || fail "message names no rule: $(cat "$D/hook.err")"
  ! grep -qF ' | dispatch | ' "$LOG" 2>/dev/null || fail "a dispatch was logged: $(cat "$LOG")"
  [ "$(lines "$LOG")" = $((n + 1)) ] && grep -v '^# ' "$LOG" | tail -1 | grep -qF ' | note | router: tier rule: ' || fail "want one note line: $(cat "$LOG" 2>/dev/null)"
  [ -z "$(ls "$F/decision-room/demo/.hooks/dispatched" 2>/dev/null)" ] || fail "a dispatch marker was written"
}

c_fable_build_refused() {
  agent "$D/p.json" worker "Ticket folder: $T"$'\nStage: build' 'tool_input.model="fable"'
  refused "$D/p.json" 'worker at stage "build" runs on sonnet at most (asked: fable)'
  grep -qF 'Start it again with model: sonnet.' "$D/hook.err" || fail "no next step: $(cat "$D/hook.err")"
  # a repeated delivery is refused again, and noted once
  hook "$D/p.json"; [ "$RC" = 2 ] || fail "the repeat passed"
  [ "$(lines "$LOG")" = 1 ] || fail "the repeat was noted again: $(cat "$LOG")"
}
c_full_id_refused() {
  agent "$D/p.json" tester "Ticket folder: $T"$'\nStage: test' 'tool_input.model="claude-opus-5-5"'
  refused "$D/p.json" 'tester at stage "test" runs on haiku at most (asked: opus)'
}
c_role_default_judged() {
  # no model in the call: the role file's default is what starts. No real role file sits above its tier, so this
  # runs a copy of the setup whose tester.md says sonnet (the tier gives the tester haiku at most).
  local src f; src=$(cd "$(dirname "$SA_UNDER_TEST")/.." && pwd)
  mkdir -p "$D/x/superagent" "$D/x/agents"
  cat "$SA_UNDER_TEST" > "$D/x/superagent/sa"
  for f in "$src"/agents/*.md; do cat "$f" > "$D/x/agents/$(basename "$f")"; done
  sed 's/^model: .*/model: sonnet/' "$src/agents/tester.md" > "$D/x/agents/tester.md"
  agent "$D/p.json" tester "Ticket folder: $T"$'\nStage: test' 'tool_input.model=DEL'
  SA_UNDER_TEST="$D/x/superagent/sa"
  refused "$D/p.json" 'tester at stage "test" runs on haiku at most (asked: sonnet)'
}
c_no_stage_line() {
  agent "$D/p.json" worker "Ticket folder: $T"$'\nDo the work.' 'tool_input.model="fable"'
  refused "$D/p.json" 'Stage: <stage>'
}
c_allowed_starts() {
  agent "$D/a.json" decision-room "Ticket folder: $T"$'\nStage: Q1' 'tool_input.model="fable"' 'tool_use_id="t_a"'
  passes "$D/a.json"
  agent "$D/b.json" ticket-writer "Tickets folder: $F/demo/tickets"$'\nStage: write-tickets' 'tool_input.model="fable"' 'tool_use_id="t_b"'
  passes "$D/b.json"
  agent "$D/c.json" worker "Ticket folder: $T"$'\nStage: plan' 'tool_input.model="claude-fable-5-2"' 'tool_use_id="t_c"'
  passes "$D/c.json"
  agent "$D/d.json" worker "Ticket folder: $T"$'\nStage: build' 'tool_input.model="haiku"' 'tool_use_id="t_d"'
  passes "$D/d.json"
}
c_owner_line_passes() {
  awk '{ print } /^Status:/ && !d { print "Model: fable"; d = 1 }' "$T/rd.md" > "$D/rd" && cat "$D/rd" > "$T/rd.md"
  agent "$D/p.json" worker "Ticket folder: $T"$'\nStage: build' 'tool_input.model="fable"'
  passes "$D/p.json"
}
c_tier_off() {
  agent "$D/p.json" worker "Ticket folder: $T"$'\nStage: build' 'tool_input.model="fable"'
  SA_TIER=off passes "$D/p.json"
  grep -qF 'worker: started by router: stage build, model fable' "$LOG" || fail "logging changed: $(cat "$LOG")"
}
c_other_role_passes() {
  agent "$D/p.json" echoer "Ticket folder: $T"$'\nStage: build' 'tool_input.model="fable"'
  hook "$D/p.json"
  [ "$RC" = 0 ] && [ ! -s "$D/hook.err" ] || fail "a non-superagent role was judged: $RC $(cat "$D/hook.err")"
  [ "$(lines "$LOG")" = 0 ] || fail "logged: $(cat "$LOG")"
}
c_no_folder() {
  # no folder: judged on role and stage, and nothing is logged
  agent "$D/p.json" worker $'Stage: build\nDo it.' 'tool_input.model="opus"'
  hook "$D/p.json"
  [ "$RC" = 2 ] && grep -qF '(asked: opus)' "$D/hook.err" || fail "want a refusal: $RC $(cat "$D/hook.err")"
  [ "$(lines "$LOG")" = 0 ] || fail "logged without a folder: $(cat "$LOG")"
}

run_case "a Fable build start is refused with exit 2 and no dispatch" c_fable_build_refused
run_case "a full model id is judged by its model word" c_full_id_refused
run_case "with no model in the call, the role file's default is judged" c_role_default_judged
run_case "a Fable start with no Stage: line asks for the line" c_no_stage_line
run_case "Fable for the decision room, ticket writing and the plan stage passes" c_allowed_starts
run_case "an owner Model: fable line passes" c_owner_line_passes
run_case "SA_TIER=off passes and logs as before" c_tier_off
c_old_router_not_refused() {
  # a router process older than router.md follows the older prompt: its starts are logged as before, never refused
  agent "$D/p.json" worker "Ticket folder: $T"$'\nStage: research (then plan)' 'tool_input.model="opus"'
  SA_TIER_SESSION=old passes "$D/p.json"
  grep -qF 'worker: started by router: stage research (then plan), model opus' "$LOG" || fail "logging changed: $(cat "$LOG")"
}
c_review_on_opus_passes() {
  # a second review that a brief calls "review" must not be pushed down to sonnet: the reviewer's ceiling is opus
  agent "$D/p.json" codex-reviewer "Ticket folder: $T"$'\nStage: review' 'tool_input.model="opus"'
  passes "$D/p.json"
}
c_review_on_fable_refused() {
  agent "$D/q.json" codex-reviewer "Ticket folder: $T"$'\nStage: plan-review' 'tool_input.model="fable"'
  refused "$D/q.json" 'codex-reviewer at stage "plan-review" runs on opus at most (asked: fable)'
}
c_label_logged() {
  agent "$D/p.json" worker "Ticket folder: $T"$'\nStage: build' 'tool_input.model="sonnet"' 'tool_input.name="Andrea-demo-001"' 'tool_input.description="build: the demo task"'
  passes "$D/p.json"
  grep -v '^# ' "$LOG" | tail -1 | grep -qF 'effort low, as Andrea-demo-001: build: the demo task' || fail "no label: $(cat "$LOG")"
}
run_case "a role that is not a superagent role passes" c_other_role_passes
run_case "a router older than router.md is logged, never refused" c_old_router_not_refused
run_case "a review on opus passes, whatever its brief calls it" c_review_on_opus_passes
c_review_model_line() {
  # the owner's Review model: line covers the Claude review only; Model: never covers a review
  awk '{ print } /^Status:/ && !d { print "Model: fable"; d = 1 }' "$T/rd.md" > "$D/rd" && cat "$D/rd" > "$T/rd.md"
  agent "$D/p.json" codex-reviewer "Ticket folder: $T"$'\nStage: second-review' 'tool_input.model="fable"'
  refused "$D/p.json" 'codex-reviewer at stage "second-review" runs on opus at most (asked: fable)'
  awk '{ print } /^Status:/ && !d { print "Review model: fable"; d = 1 }' "$T/rd.md" > "$D/rd" && cat "$D/rd" > "$T/rd.md"
  agent "$D/q.json" codex-reviewer "Ticket folder: $T"$'\nStage: second-review' 'tool_input.model="fable"' 'tool_use_id="t_q"'
  hook "$D/q.json"; [ "$RC" = 0 ] || fail "Review model: fable must allow the second review: $RC $(cat "$D/hook.err")"
  agent "$D/r.json" codex-reviewer "Ticket folder: $T"$'\nStage: review' 'tool_input.model="fable"' 'tool_use_id="t_r"'
  hook "$D/r.json"; [ "$RC" = 2 ] || fail "the Codex wrapper must stay on the table: $RC"
}
run_case "a review on fable is refused" c_review_on_fable_refused
run_case "Review model: fable allows the Claude review, and only that" c_review_model_line
run_case "the agent's name and task are on its start line" c_label_logged
run_case "a brief with no folder is judged on role and stage" c_no_folder
