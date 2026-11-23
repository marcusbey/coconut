#!/usr/bin/env bash
# run-options.test.sh: `sa run-options` picks a model and effort from the tier table (the owner's rule of 2026-11-22),
# unless the owner's Model:/Effort:/Plan model:/Review effort: lines say otherwise (the ticket's beat the project's).
# Every case runs on its own throwaway fixture (fixture.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
unset SA_ROLE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
sa() { bash "$SA_UNDER_TEST" "$@"; }

F=""; D=""; T=""; P=""
fail() { echo "$*"; exit 1; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); P="$F/demo/tickets"; T="$P/001-demo-ticket"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}
want() { # want <dir> <role> <stage> <expected line>
  local got
  got=$(sa run-options "$1" "$2" "$3") || fail "run-options $2 '$3' failed: $got"
  [ "$got" = "$4" ] || fail "$2 at '$3': want '$4', got '$got'"
}
header_line() { # header_line <rd.md> <line>: add a line to the header, after Status:
  awk -v l="$2" '{ print } /^Status:/ && !d { print l; d = 1 }' "$1" > "$1.t" && cat "$1.t" > "$1" && rm -f "$1.t"
}

c_every_row() {
  want "$T" worker plan 'model fable, effort medium (tier table)'
  want "$T" teammate 'plan' 'model fable, effort medium (tier table)'
  want "$T" reproducer 'planning the fix' 'model fable, effort medium (tier table)'
  want "$T" worker design 'model opus, effort high (tier table)'
  want "$T" reproducer design 'model opus, effort high (tier table)'
  want "$T" reproducer build 'model opus, effort medium (tier table)'
  want "$T" worker research 'model sonnet, effort medium (tier table)'
  want "$T" worker build 'model sonnet, effort low (tier table)'
  want "$T" teammate report 'model sonnet, effort low (tier table)'
  want "$T" ticket-writer write-tickets 'model fable, effort medium (tier table)'
  want "$T" ticket-writer 'answer mode' 'model haiku, effort low (tier table)'
  want "$T" tester test 'model haiku, effort low (tier table)'
  want "$T" codex-reviewer 'claude mode' 'model opus, effort medium (tier table)'
  want "$T" codex-reviewer 'review round 1' 'model sonnet, effort medium (tier table)'
  want "$T" decision-room referee 'model opus, effort high (tier table)'
  want "$T" decision-room Q1 'model sonnet, effort medium (tier table)'
  for r in merger checker watchdog follow-up; do want "$T" "$r" any "model sonnet, effort low (tier table)"; done
  want "$T" router anything 'model sonnet, effort medium (tier table)'
}
c_scout_and_risk() {
  want "$T" worker build 'model sonnet, effort low (tier table)'
  header_line "$T/rd.md" 'Risk: high'
  want "$T" worker build 'model opus, effort medium (tier table)'
  want "$T" worker plan 'model fable, effort medium (tier table)'   # the plan row comes first
  sed -i.b 's/^Risk: high$//; s/^Kind: ship$/Kind: scout/' "$T/rd.md" && rm -f "$T/rd.md.b"
  want "$T" teammate 'research' 'model opus, effort medium (tier table)'
  want "$P" worker build 'model sonnet, effort low (tier table)'   # no ticket: no rd.md to read
}
c_loose_stage_words() {
  want "$T" worker 'Plan' 'model fable, effort medium (tier table)'
  want "$T" worker 'plan review round 2' 'model sonnet, effort low (tier table)'
  want "$T" worker 'plan-review' 'model sonnet, effort low (tier table)'
  want "$T" worker '  DESIGN of the API' 'model opus, effort high (tier table)'
  want "$T" ticket-writer 'writing tickets' 'model fable, effort medium (tier table)'
  want "$T" ticket-writer 'PROJECT.md' 'model fable, effort medium (tier table)'
  want "$T" ticket-writer 'draft the PRD' 'model fable, effort medium (tier table)'
  want "$T" codex-reviewer 'review (second-review mode)' 'model opus, effort medium (tier table)'
  want "$T" decision-room 'Referee round' 'model opus, effort high (tier table)'
  want "$T" worker '' 'model sonnet, effort low (tier table)'
}
c_owner_lines() {
  printf 'Model: claude-opus-5-5 (opus while Fable is unavailable)\nEffort: high (max for design work)\n' >> "$P/PROJECT.md"
  want "$T" worker build 'model opus, effort high (project line)'
  want "$P" worker build 'model opus, effort high (project line)'
  want "$T" tester test 'model haiku, effort low (tier table)'   # the lines are for builders only
  header_line "$T/rd.md" 'Model: fable'
  want "$T" worker build 'model fable, effort high (ticket line)'
  want "$P" worker build 'model opus, effort high (project line)'
  want "$T" worker plan 'model fable, effort medium (tier table)'   # Model: does not apply at plan
  # a Model: line in the body of rd.md is not an owner line
  printf '\n## Notes\nModel: haiku\n' >> "$T/rd.md"
  want "$T" worker build 'model fable, effort high (ticket line)'
}
c_plan_model() {
  printf 'Plan model: opus\n' >> "$P/PROJECT.md"
  want "$T" worker plan 'model opus, effort medium (project line)'
  want "$T" worker build 'model sonnet, effort low (tier table)'
  header_line "$T/rd.md" 'Plan model: claude-sonnet-5-5'
  want "$T" reproducer plan 'model sonnet, effort medium (ticket line)'
}
c_review_effort() {
  printf 'Review effort: xhigh\n' >> "$P/PROJECT.md"
  want "$T" codex-reviewer 'review round 2' 'model sonnet, effort xhigh (project line)'
  want "$T" worker build 'model sonnet, effort low (tier table)'
}
c_table_form() {
  local t
  t=$(sa run-options --table) || fail "--table failed"
  [ "$(printf '%s\n' "$t" | head -1)" = '| Role | Stage contains | Model | Max model the hook allows | Effort |' ] || fail "header: $t"
  [ "$(printf '%s\n' "$t" | grep -c '^| ')" = 16 ] || fail "want a header and 15 rows: $t"
  printf '%s\n' "$t" | grep -qxF '| ticket-writer | anything else (clerk jobs) | haiku | sonnet | low |' || fail "clerk row: $t"
  printf '%s\n' "$t" | grep -qxF '| any other role | any | sonnet | fable | medium |' || fail "last row: $t"
}
c_refusals() {
  local o
  o=$(sa run-options "$D/nowhere" worker build) && fail "a missing folder passed: $o"
  case "$o" in refused:*) ;; *) fail "want refused: $o" ;; esac
  o=$(sa run-options "$T" worker) && fail "two arguments passed: $o"
  true
}

run_case "every row of the tier table" c_every_row
run_case "Kind: scout and Risk: high give the scout row" c_scout_and_risk
run_case "loose stage words match by keyword, any case" c_loose_stage_words
run_case "owner Model:/Effort: lines beat the table; the ticket's beat the project's" c_owner_lines
run_case "Plan model: applies at the plan stage only" c_plan_model
run_case "Review effort: sets codex-reviewer's effort" c_review_effort
run_case "--table prints the rows as markdown" c_table_form
run_case "bad arguments are refused" c_refusals
