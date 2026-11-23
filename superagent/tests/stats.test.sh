#!/usr/bin/env bash
# stats.test.sh: `sa stats`, the spend and flow report the owner asked for on 2026-11-15 so that cost and
# send-backs are measured by a command, not by hand. Every case builds its own throwaway workspace and
# transcript folder; nothing outside them is read.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { SA_CLAUDE_PROJECTS="$D/projects" bash "$SA_UNDER_TEST" "$@"; }

D=""; WS=""; RUNS=""
fail() { echo "$*"; exit 1; }
run_case() { # run_case <name> <function>
  local rc
  D=$(mktemp -d "${TMPDIR:-/tmp}/sa-stats.XXXXXX") || { echo "FAIL $1 (no temp folder)"; return; }
  D=$(cd "$D" && pwd -P); WS="$D/ws"; mkdir -p "$WS/decision-room/demo"
  RUNS="$D/projects/$(printf '%s' "$WS" | sed 's/[^A-Za-z0-9]/-/g')/session1/subagents"; mkdir -p "$RUNS"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  case "$D" in */sa-stats.*) rm -rf "$D" ;; esac
}
has() { printf '%s\n' "$1" | grep -qE -- "$2" || fail "want /$2/ in: $1"; }
ago() { python3 -I -c 'import datetime, sys; t = datetime.datetime.now() - datetime.timedelta(hours=float(sys.argv[1])); print(t.strftime(sys.argv[2]))' "$1" "$2"; }
turn() { # turn <file> <message id> <model> <utc stamp> <input> <cache write> <cache read> <output>
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$4" "$2" "$3" "$5" "$6" "$7" "$8" >> "$1"
}
line() { printf '%s %s | %s | %s | %s\n' "$1" "$2" "${REF:-demo#001}" "$3" "$4" >> "$WS/decision-room/demo/LOG.md"; }
brief() { # brief <file> <text>: the first user row, the ticket brief a builder starts from
  printf '{"type":"user","message":{"role":"user","content":"%s"}}\n' "$2" >> "$1"
}

c_spend() { # weights: cache write 1.25, cache read 0.1, output 5; a repeated message id counts once; old turns are left out
  local out now
  now=$(python3 -I -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
  printf '{"agentType":"worker","effort":"low"}\n' > "$RUNS/agent-a1.meta.json"
  turn "$RUNS/agent-a1.jsonl" m0 claude-sonnet-5-5 2020-01-01T00:00:00.000Z 900000 0 0 900000
  turn "$RUNS/agent-a1.jsonl" m1 claude-sonnet-5-5 "$now" 100 1000 10000 200
  turn "$RUNS/agent-a1.jsonl" m2 claude-sonnet-5-5 "$now" 0 0 20000 7
  turn "$RUNS/agent-a1.jsonl" m2 claude-sonnet-5-5 "$now" 0 0 20000 100
  printf '{"agentType":"decision-room"}\n' > "$RUNS/agent-b2.meta.json"
  turn "$RUNS/agent-b2.jsonl" m3 claude-fable-5-2 "$now" 0 4000 0 30
  out=$(sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" 'by model: sonnet 53%, fable 47%'
  has "$out" 'conversation re-read 27%'; has "$out" 'new content read in 58%'; has "$out" 'output 15%'
  has "$out" '^worker@unknown +sonnet +1 +2 +16k +11k +96% +0\.3k +53% +low 1$'
  has "$out" '^decision-room +fable +1 +1 +4k +4k +0% +0\.0k +47% +default 1$'
}

c_stage() { # builders split by the brief's Stage line (first word, lower case); first = context of the first turn; cache = read share
  local out now
  now=$(python3 -I -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
  printf '{"agentType":"worker"}\n' > "$RUNS/agent-p1.meta.json"; printf '{"agentType":"worker"}\n' > "$RUNS/agent-p2.meta.json"
  printf '{"agentType":"router"}\n' > "$RUNS/agent-p3.meta.json"
  brief "$RUNS/agent-p1.jsonl" 'demo#001 start\nStage: Plan extra words\nRun: model opus'
  turn "$RUNS/agent-p1.jsonl" p1 claude-sonnet-5-5 "$now" 10 3000 7000 0
  turn "$RUNS/agent-p1.jsonl" p2 claude-sonnet-5-5 "$now" 0 0 20000 50
  brief "$RUNS/agent-p2.jsonl" 'demo#002 start\nStage: build'
  turn "$RUNS/agent-p2.jsonl" b1 claude-sonnet-5-5 "$now" 0 40000 0 0
  brief "$RUNS/agent-p3.jsonl" 'Stage: plan'
  turn "$RUNS/agent-p3.jsonl" r1 claude-sonnet-5-5 "$now" 0 1000 0 0
  out=$(sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" '^worker@plan +sonnet +1 +2 +15k +10k +90% '
  has "$out" '^worker@build +sonnet +1 +1 +40k +40k +0% '
  has "$out" '^router +sonnet +1 +1 +1k +1k +0% '
}

c_plan_revisions() { # plan entries beyond a ticket's first, counted in the window; named under most: from 3
  local out
  REF=demo#001 line 📝 "$(ago 100 '%Y-%m-%d %H:%M')" stage "in-progress/research -> in-progress/plan: plan written"
  REF=demo#001 line 📝 "$(ago 5 '%Y-%m-%d %H:%M')" stage "in-progress/plan-review -> in-progress/plan: plan review: 2 must-fix"
  REF=demo#001 line 📝 "$(ago 4 '%Y-%m-%d %H:%M')" stage "in-progress/plan-review -> in-progress/plan: plan review: 1 must-fix"
  REF=demo#001 line 🔍 "$(ago 3 '%Y-%m-%d %H:%M')" stage "in-progress/plan -> in-progress/plan-review: plan review round 3"
  for h in 9 8 7 6; do REF=demo#002 line 📝 "$(ago $h '%Y-%m-%d %H:%M')" stage "in-progress/plan-review -> in-progress/plan: plan review: 1 must-fix"; done
  out=$(sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" '^  plan revisions 5$'
  has "$out" '^  most: demo#002 \(3\)$'
  printf '%s\n' "$out" | grep -qF 'demo#001 (' && fail "demo#001 has 2 revisions and must not be named: $out"
  out=$(sa stats "$WS" 4.5) || fail "stats failed: $out"
  has "$out" '^  plan revisions 1$'  # only demo#001's entry at 4 h is inside 4.5 h, and its first entry is the old one
}

c_cost() { # by cost: from a prices file, refused without a price for a family that appears, silent without a file
  local out now
  now=$(python3 -I -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
  printf '{"agentType":"decision-room"}\n' > "$RUNS/agent-c1.meta.json"; printf '{"agentType":"router"}\n' > "$RUNS/agent-c2.meta.json"
  turn "$RUNS/agent-c1.jsonl" c1 claude-sonnet-5-5 "$now" 1000000 0 0 100000
  turn "$RUNS/agent-c2.jsonl" c2 claude-fable-5-2 "$now" 0 0 1000000 0
  printf '{"source":"test","models":{"sonnet":{"input":1,"output":5,"cache_write":1,"cache_read":1},"fable":{"input":1,"output":1,"cache_write":1,"cache_read":1}}}\n' > "$D/prices.json"
  out=$(SA_PRICES="$D/prices.json" sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" '^  by cost: sonnet 60%, fable 40%, total \$2\.50$'
  printf '{"models":{"sonnet":{"input":1,"output":5,"cache_write":1,"cache_read":1}}}\n' > "$D/prices.json"
  out=$(SA_PRICES="$D/prices.json" sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" '^  by cost: no price for fable$'
  out=$(SA_PRICES="$D/none.json" sa stats "$WS" 24) || fail "stats failed: $out"
  printf '%s\n' "$out" | grep -q 'by cost' && fail "no file must print no cost line: $out"
  has "$out" '^  by model: '
}

c_seats() { # headless room seats: one usage file in the window = one room-seat run; bad and old files are skipped
  local out debate="$WS/decision-room/demo/debate"
  mkdir -p "$debate"
  printf '{"result":"x","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":3000,"output_tokens":400}}\n' > "$debate/20261116-room-fable-1-usage.json"
  printf '{not json\n' > "$debate/20261116-room-fable-2-usage.json"
  printf '{"usage":{"input_tokens":9000000}}\n' > "$debate/20200101-room-fable-3-usage.json"; touch -t 202001010000 "$debate/20200101-room-fable-3-usage.json"
  out=$(sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" '^room-seat +fable +1 +1 +6k +6k +50% +0\.4k +100% +default 1$'
}

c_flow() { # the room log's lines of the window, counted by what they mean
  local out
  line 🔨 "2020-01-01 10:00" landing "aaaa on main"
  line ✍️ "$(ago 2 '%Y-%m-%d %H:%M')" stage "draft/- -> ready/-: approved by the user"
  line 🧪 "$(ago 1.5 '%Y-%m-%d %H:%M')" stage "in-progress/build -> review/test: test round 1"
  line 🧪 "$(ago 1.4 '%Y-%m-%d %H:%M')" stage "review/test -> in-progress/build: test round 1 failed: branch is stale, main moved"
  line 🧪 "$(ago 1.3 '%Y-%m-%d %H:%M')" stage "review/test -> in-progress/build: test round 2 failed: 3 checks fail"
  line 🔍 "$(ago 1.2 '%Y-%m-%d %H:%M')" stage "review/test -> review/review: review round 1"
  line 🔍 "$(ago 1.1 '%Y-%m-%d %H:%M')" stage "review/review -> in-progress/build: review round 1: 2 defect(s) to fix"
  line 🔍 "$(ago 1.0 '%Y-%m-%d %H:%M')" stage "in-progress/plan-review -> in-progress/plan: plan review: 1 must-fix"
  line 🏛️ "$(ago 0.9 '%Y-%m-%d %H:%M')" decision "D1 (merge): Merge it? -> (a) yes; decided by fable and codex"
  line 🔨 "$(ago 0.8 '%Y-%m-%d %H:%M')" question "Q1 from worker: Which way? | options: (a) one; (b) two"
  line 🧭 "$(ago 0.7 '%Y-%m-%d %H:%M')" question "router: asked the user: Pay for it? | options: Yes; No"
  line 🔀 "$(ago 0 '%Y-%m-%d %H:%M')" landing "bbbb on main"
  out=$(sa stats "$WS" 24) || fail "stats failed: $out"
  has "$out" 'no agent runs found'
  has "$out" '^  landed +1$'; has "$out" '^  test rounds +1$'; has "$out" '^  review rounds +1$'
  has "$out" '^  sent back: base moved +1$'; has "$out" '^  sent back: test failed +1$'
  has "$out" '^  sent back: review +1$'; has "$out" '^  sent back: plan review +1$'
  has "$out" '^  room decisions +1$'; has "$out" '^  questions \(agents\) +1$'; has "$out" '^  questions to you +1$'
  has "$out" 'ready to landed: median 2\.0 h, longest 2\.0 h \(1 tickets\)'
  out=$(sa stats "$WS" 0.5) || fail "stats failed for half an hour: $out"
  has "$out" '^  landed +1$'; has "$out" '^  room decisions +0$'
}

c_reads_only() { # bad input is refused; the report changes no file
  local out rc before
  line 🔀 "$(ago 0 '%Y-%m-%d %H:%M')" landing "bbbb on main"
  before=$(cd "$D" && find . -type f ! -name case.out -print0 | xargs -0 cksum | sort)
  sa stats "$WS" >/dev/null || fail "stats failed with the default window"
  [ "$(cd "$D" && find . -type f ! -name case.out -print0 | xargs -0 cksum | sort)" = "$before" ] || fail "stats changed a file"
  out=$(sa stats 2>&1); rc=$?; [ "$rc" = 1 ] || fail "want exit 1 with no argument, got $rc"; has "$out" 'refused: usage'
  out=$(sa stats "$D/nope" 2>&1); rc=$?; [ "$rc" = 1 ] || fail "want exit 1 for a missing folder, got $rc"; has "$out" 'refused: no such folder'
  out=$(sa stats "$WS" soon 2>&1); rc=$?; [ "$rc" = 1 ] || fail "want exit 1 for bad hours, got $rc"; has "$out" 'refused: hours must be a number above 0'
}

run_case "stats: spend per role and model, weighted, each message once" c_spend
run_case "stats: builders split by stage; first context and cache share per role" c_stage
run_case "stats: plan revisions beyond the first entry" c_plan_revisions
run_case "stats: by cost from a prices file, never guessed" c_cost
run_case "stats: headless room seats count as room-seat runs" c_seats
run_case "stats: flow counts landings, send-backs, decisions and questions" c_flow
run_case "stats: reads only; bad input refused" c_reads_only
