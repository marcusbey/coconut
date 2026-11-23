#!/usr/bin/env bash
# room-context.test.sh: `sa room context`, the digest both seats of the decision room read in place of
# the whole room LOG.md and DECISIONS.md, which hold every ticket of the project and grow every day
# (the owner's rule of 2026-11-15). Every case runs on its own throwaway fixture (fixture.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }   # through bash: a copy from `git show` is not executable
WORDS='the room decides'

F=""; D=""; T=""; T2=""; TK=""
fail() { echo "$*"; exit 1; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  F=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$F"); TK="$F/demo/tickets"; T="$TK/001-demo-ticket"; T2="$TK/002-other-ticket"
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  if [ -n "${SA_KEEP_FIXTURES:-}" ]; then echo "    fixture kept: $F"; else drop_dir "$D"; fi
}
snap() { (cd "$D" && find . -type f ! -path ./case.out -print0 | xargs -0 cksum | sort); }
has() { printf '%s\n' "$1" | grep -qF -- "$2" || fail "want '$2' in the digest, got: $1"; }
hasnt() { if printf '%s\n' "$1" | grep -qF -- "$2"; then fail "'$2' must not be in the digest, got: $1"; fi; }
second_ticket() { # a second ticket of the same project, with its board row
  mkdir -p "$T2" || fail "no second ticket"
  printf '# 002: Other ticket\n\nStatus: draft\nKind: ship\nTrack: quick\nStage: -\n\n## Goal\nAnother fixture ticket.\n\n## Open questions\n- **Q1**: Draft question here? Options: (a) one way (b) the other way\n' > "$T2/rd.md"
  printf '| 002 | other-ticket | draft | solo | alongside | - |\n' >> "$TK/BOARD.md"
}
event() { sa room event "$1" report worker "$2" >/dev/null || fail "event failed: $2"; }
decide() { # decide <ticket-dir> <question> <tag>
  sa room decide "$1" other "$2" --option "yes: go" --option "no: wait" --fable a "fable says $3" --codex a "codex says $3" >/dev/null || fail "decide failed: $2"
}

c_only_this_ticket() {
  local out
  second_ticket
  event "$T" "ready: alpha-one"
  event "$T2" "ready: beta-two"
  sa room note "$TK" clerk "project-wide gamma-three" >/dev/null || fail "note failed"
  out=$(sa room context "$T") || fail "context failed: $out"
  has "$out" "demo#001"; has "$out" "alpha-one"; hasnt "$out" "beta-two"
  has "$out" "gamma-three"   # the project's own lines come along
  out=$(sa room context "$T2") || fail "context failed for 002: $out"
  has "$out" "demo#002"; has "$out" "beta-two"; hasnt "$out" "alpha-one"
  out=$(sa room context "$TK") || fail "context failed for the tickets folder: $out"
  has "$out" "gamma-three"; hasnt "$out" "alpha-one"; hasnt "$out" "beta-two"
}

c_decisions() { # every earlier decision of this ticket is named; only the newest two are in full
  local out
  second_ticket
  sa room on "$F" 2026-11-13 "$WORDS" >/dev/null || fail "room on failed"
  decide "$T" "First question?" one
  decide "$T" "Second question?" two
  decide "$T" "Third question?" three
  decide "$T2" "Other ticket question?" four
  out=$(sa room context "$T") || fail "context failed: $out"
  has "$out" "Third question?"; has "$out" "fable says three"; has "$out" "codex says three"
  has "$out" "Second question?"; has "$out" "fable says two"
  has "$out" "First question?"; has "$out" "yes: go"; hasnt "$out" "fable says one"
  hasnt "$out" "Other ticket question?"
  out=$(sa room context "$T2") || fail "context failed for 002: $out"
  has "$out" "Other ticket question?"; has "$out" "fable says four"; hasnt "$out" "Third question?"
}

c_caps() { # a long line is cut and says so; a long history shows its last lines and says how many there are
  local out long i longest
  long=$(printf 'x%.0s' $(seq 1 900))
  for i in $(seq 1 45); do event "$T" "ready: n$i-end"; done
  event "$T" "ready: $long"
  out=$(sa room context "$T") || fail "context failed"
  longest=$(printf '%s\n' "$out" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
  [ "$longest" -le 420 ] || fail "a line of $longest characters got through"
  has "$out" "[cut]"
  has "$out" "ready: n45-end"; has "$out" "ready: n7-end"; hasnt "$out" "ready: n6-end"
  has "$out" "(46, the last 40 shown)"
}

c_questions_and_files() {
  local out
  second_ticket
  mkdir -p "$T/notes" || fail "no notes folder"
  printf '## Q1 [open]\nFrom: worker\nQuestion: Which colour?\n- (a) blue\n- (b) red\n\n## Q2 [answered]\nQuestion: Old one?\nAnswer: yes\n' > "$T/notes/questions.md"
  printf 'results\n' > "$T/notes/results.md"
  out=$(sa room context "$T") || fail "context failed: $out"
  has "$out" "Which colour?"; has "$out" "(b) red"; hasnt "$out" "Old one?"
  has "$out" "$T/rd.md"; has "$out" "$T/eval.md"; has "$out" "$T/notes/results.md"; has "$out" "$T/notes/questions.md"
  hasnt "$out" "notes/review.md"   # only the files that exist
  out=$(sa room context "$T2") || fail "context failed for 002: $out"
  has "$out" "Draft question here?"
}

c_reads_only() { # the digest changes no file; bad input is refused; a project with no room says so
  local out rc before
  event "$T" "ready: alpha-one"
  before=$(snap)
  sa room context "$T" >/dev/null || fail "context failed"
  sa room context "$TK" >/dev/null || fail "context failed for the tickets folder"
  [ "$(snap)" = "$before" ] || fail "the digest changed a file"
  out=$(sa room context "$F/nope" 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 for a missing folder, got $rc: $out"
  has "$out" "refused: no such ticket or tickets folder"
  out=$(sa room context 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 with no argument, got $rc: $out"
  out=$(sa room context "$D/outside/tickets/001-demo-ticket") || fail "a project with no room must not fail: $out"
  has "$out" "no decision room for this project"
}

# --- the reading set of one question: `sa room context <dir> <subject>` (superagent#033) -------------------------------
ROLE_DIR=${ROLE_DIR:-$here/../../agents}; PROTO_FILE=${PROTO_FILE:-$here/../PROTOCOL.md}
C1=1111111111111111111111111111111111111111; C2=2222222222222222222222222222222222222222
ctx() { sa room context "$@"; }
sect() { printf '%s\n' "$1" | awk -v h="$2" 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f'; }   # the lines under a heading
in_sect() { sect "$1" "$2" | grep -qF -- "$3" || fail "want '$3' under '$2', got: $(sect "$1" "$2")"; }
size() { wc -c < "$1" | tr -d ' '; }
notes() { mkdir -p "$T/notes" || fail "no notes folder"; }
logline() { printf '🔨 2026-11-19 10:00 | %s | %s | %s\n' "$1" "$2" "$3" >> "$F/decision-room/demo/LOG.md"; }   # logline <ref> <kind> <text>
FIND='| # | Class | Severity | Where | What is wrong | Violates | Fix |
|---|---|---|---|---|---|---|'
verdict() { printf 'Reviewed commit: %s\nMax severity: %s\nShip allowed: %s\n' "$1" "$2" "$3"; }
all_notes() { # the eight notes, the three append-only ones with two rounds
  notes
  local f
  for f in results plan questions review-response check; do printf '%s body\n' "$f" > "$T/notes/$f.md"; done
  printf '## Q1 [open]\nFrom: worker\nQuestion: Which colour?\n- (a) blue\n- (b) red\n' > "$T/notes/questions.md"
  for f in test review plan-review; do printf -- '--- Round 1, 2026-11-19\nold %s\n\n--- Round 2, 2026-11-19\nnew %s\n' "$f" "$f" > "$T/notes/$f.md"; done
}

c_set_one_command() { # E-1: one read-only command prints the set; every listed size is the file's size
  local out before f n
  second_ticket; all_notes
  sa room on "$F" 2026-11-19 "$WORDS" >/dev/null || fail "room on failed"
  event "$T" "ready: alpha-one"; decide "$T" "First question?" one
  before=$(snap)
  out=$(ctx "$T" merge) || fail "context failed: $out"
  [ "$(snap)" = "$before" ] || fail "the command changed a file"
  has "$out" "# Decision room reading set: demo#001, subject merge"
  has "$out" "$T/rd.md"; has "$out" "$T/eval.md"
  has "$out" "## Log lines of demo#001"; has "$out" "alpha-one"
  has "$out" "## Decisions on demo#001"; has "$out" "First question?"
  has "$out" "## Open questions on demo#001"; has "$out" "Which colour?"
  has "$out" "## notes/review.md: round 2 of 2"; has "$out" "new review"
  has "$out" "## Read whole"; has "$out" "## Left out for merge"
  for f in results review-response check; do in_sect "$out" "## Read whole" "- $T/notes/$f.md ($(size "$T/notes/$f.md") bytes)"; done
  for f in plan plan-review questions; do in_sect "$out" "## Left out for merge" "- $T/notes/$f.md ($(size "$T/notes/$f.md") bytes)"; done
  n=$(sect "$out" "## Read whole" | grep -c '^- /') || true
  [ "$n" = 4 ] || fail "want 4 files to read whole (three notes and PROJECT.md), got $n: $(sect "$out" "## Read whole")"
  sect "$out" "## Read whole" | grep -qF "/rd.md" && fail "rd.md is listed under Read whole (E-9 would count it twice)"
  return 0
}

e2_review() { # <file>: round 1 with a fixed finding, an open one and a met requirement; round 2 marks the first fixed
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex (gpt-6-astra, effort high)\n## Findings\n%s\n' "$FIND"
    printf '| 1 | defect | minor | a.sh:1 | F-OLD-FIXED lint errors | rules | fix |\n| 2 | hardening | minor | a.sh:2 | F-OLD-OPEN orphan row | none | later |\n'
    printf '## Requirements\n| FR | Met | Evidence |\n|---|---|---|\n| FR-1 | yes | ROUND1-FILLER |\n'
    verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex (gpt-6-astra, effort high)\nROUND2-BODY\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 1 (lint errors) | Fixed | a.sh:1 |\n'
    verdict "$C2" none yes; } > "$1"
}
c_e2_rounds() { # E-2: the newest round whole; an earlier round without what is closed
  local out
  notes
  e2_review "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "ROUND2-BODY"; has "$out" "F-OLD-OPEN"; hasnt "$out" "ROUND1-FILLER"; hasnt "$out" "F-OLD-FIXED"
  has "$out" "- #1 (defect, minor): closed by round 2, status rows"
  rm -f "$T/notes/review.md"
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n| # | Class | Where in the plan | Problem | Change |\n|---|---|---|---|---|\n'
    printf '| 1 | must-fix | T1 | F-OLD-FIXED wrong order | swap |\n| 2 | advice | T2 | F-OLD-OPEN simpler way | consider |\n'
    printf '\n## Requirements\n| FR | Met | Evidence |\n|---|---|---|\n| FR-1 | yes | ROUND1-FILLER |\nQuestions for the user: none\nPlan sound: no\n'
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\nROUND2-BODY\n| # | Round-1 row | Fixed / partly / not fixed | Evidence |\n|---|---|---|---|\n| 1 | order | Fixed | plan.md:T1 |\nQuestions for the user: none\nPlan sound: no\n'
  } > "$T/notes/plan-review.md"
  out=$(ctx "$T" plan) || fail "context failed for plan: $out"
  has "$out" "ROUND2-BODY"; has "$out" "F-OLD-OPEN"; hasnt "$out" "ROUND1-FILLER"; hasnt "$out" "F-OLD-FIXED"
  { printf -- '--- Round 1, 2026-11-19\nTested commit: %s\nResult: fail\n| Check | Result | Evidence | Note |\n|---|---|---|---|\n' "$C1"
    printf '| E-1 first | fail | F-OLD-FIXED | |\n| E-2 second | fail | F-OLD-OPEN | |\n| A-1 syntax | pass | ROUND1-FILLER | |\n'
    printf -- '\n--- Round 2, 2026-11-19\nTested commit: %s\nResult: fail\n| Check | Result | Evidence | Note |\n|---|---|---|---|\n' "$C2"
    printf '| E-1 first | pass | ROUND2-BODY | |\n| E-2 second | fail | still red | |\n| A-1 syntax | pass | again | |\n'
  } > "$T/notes/test.md"
  out=$(ctx "$T" merge) || fail "context failed for the test note: $out"
  has "$out" "ROUND2-BODY"; has "$out" "F-OLD-OPEN"; hasnt "$out" "ROUND1-FILLER"; hasnt "$out" "F-OLD-FIXED"
}

c_cut_prose_status() { # prose beside a table stays; a status row saying Not fixed stays, with its finding
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n## Findings\n%s\n| 1 | defect | minor | a.sh:1 | F-ROW vacuous harness | eval | fix |\n' "$FIND"
    printf 'PROSE-FINDING: the retry loop never ends, see a.sh:40.\n## Follow-ups (never blocking)\n- FOLLOW-UP-LINE narrow the suppression\n'
    verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 1 (harness) | Not fixed | S-NOTFIXED still vacuous |\n'
    verdict "$C2" minor yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" minor yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "PROSE-FINDING"; has "$out" "FOLLOW-UP-LINE"; has "$out" "F-ROW"; has "$out" "S-NOTFIXED"; has "$out" "NEWEST"
}

c_cut_identity() { # a status row closes a finding only when it names it without doubt, in the round its table names
  local out
  notes
  # a named round that has no such finding: no other round is searched
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 7 | defect | minor | a.sh:7 | F-SEVEN | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n## Findings\nNone.\n'; verdict "$C1" none yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\n## Round 2 defects\n| # | Status | Evidence |\n|---|---|---|\n| 7 | Fixed | x |\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-SEVEN"; hasnt "$out" "closed by round"
  # a table that may be a fresh row index: rows 1 and 2 about findings 2 and 5
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | hardening | minor | a:1 | F-HARD | none | later |\n| 2 | defect | minor | a:2 | F-TWO | eval | fix |\n| 5 | defect | minor | a:5 | F-FIVE | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 1 | Fixed | lint |\n| 2 | Not fixed | harness |\n'; verdict "$C2" minor yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-HARD"; has "$out" "F-TWO"; has "$out" "F-FIVE"; hasnt "$out" "closed by round"
  # two findings with the same number in the named round (two reviewers): neither is closed
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | minor | a:1 | F-CODEX | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf '\nSecond review, reviewer: claude (claude-fable-5-2)\n%s\n| 1 | defect | minor | a:9 | F-CLAUDE | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 1 | Fixed | x |\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-CODEX"; has "$out" "F-CLAUDE"
  # a status table that names no round closes nothing; a fix taken back in a later round reopens the finding
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 3 | defect | minor | a:3 | F-UNNAMED | eval | fix |\n| 4 | defect | minor | a:4 | F-REOPENED | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n| # | Status | Evidence |\n|---|---|---|\n| 3 | Fixed | x |\n\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 4 | Fixed | x |\n'; verdict "$C2" none yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 4 | Not fixed | back again |\n'; verdict "$C2" minor yes
    printf -- '\n--- Round 4, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" minor yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-UNNAMED"; has "$out" "F-REOPENED"
  # a shape seen on a real ticket: round 3 renumbers its rows and gives the original number; the reference runs through round 2
  { printf -- '--- Round 1, 2026-11-10, reviewer: codex\n| # | Class | Where in the plan | Problem | Change |\n|---|---|---|---|---|\n| 9 | must-fix | T9 | F-NINE | c |\n| 10 | must-fix | T10 rollback | F-TEN | c |\n| 11 | advice | T11 | F-ELEVEN | c |\nPlan sound: no\n'
    printf -- '\n--- Round 2, 2026-11-10, reviewer: codex\n| # | Round-1 row | Fixed / partly / not fixed | Evidence |\n|---|---|---|---|\n| 9 | nine | Fixed | ok |\n| 10 | Resource-specific rollback | Partly | P-TEN-PARTLY |\n\n| # | Class (must-fix\\|advice) | Where | Problem | Change |\n|---|---|---|---|---|\n| 20 | must-fix | P1 | F-TWENTY | c |\nPlan sound: no\n'
    printf -- '\n--- Round 3, 2026-11-10, reviewer: codex\n| # | Round-2 row | closed / partly / not closed | Evidence |\n|---|---|---|---|\n| 1 | **10 — Infrastructure rollback** | closed | ok |\n| 2 | **20 — Circular phases** | partly | P-TWENTY-PARTLY |\nPlan sound: no\n'
    printf -- '\n--- Round 4, 2026-11-10, reviewer: codex\nNEWEST\nPlan sound: no\n'; } > "$T/notes/plan-review.md"
  out=$(ctx "$T" plan) || fail "context failed for plan: $out"
  hasnt "$out" "F-NINE"; hasnt "$out" "F-TEN"; hasnt "$out" "P-TEN-PARTLY"
  has "$out" "- #10 (must-fix): closed by round 3, status rows"; has "$out" "- #9 (must-fix): closed by round 2, status rows"
  has "$out" "F-ELEVEN"; has "$out" "F-TWENTY"; has "$out" "P-TWENTY-PARTLY"
}

c_cut_fenced() { # review 1, finding 1: a status table or verdicts inside a fence close nothing, and are still printed
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | major | a.sh:1 | F-FENCED-OPEN still broken | eval | fix |\n' "$FIND"; verdict "$C1" major no
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\nThe issue remains open. A fixed row would look like this:\n```\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 1 (broken) | Fixed | FENCE-EXAMPLE |\n\nSecond review, reviewer: claude (x)\nReviewed commit: %s\nMax severity: none\nShip allowed: yes\n```\n' "$C2"
    verdict "$C2" none yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" major no; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-FENCED-OPEN"; has "$out" "FENCE-EXAMPLE"; hasnt "$out" "closed by round"
}

fence_case() { # fence_case <name> <round-2 example text>: an example in round 2 closes nothing, and is printed
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | major | a.sh:1 | F-FENCED-OPEN still broken | eval | fix |\n' "$FIND"; verdict "$C1" major no
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\nThe issue remains open. A fixed row would look like this:\n%s\n' "$2"
    verdict "$C2" none yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" major no; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "$1: context failed: $out"
  printf '%s\n' "$out" | grep -qF "F-FENCED-OPEN" || fail "$1: the open finding was closed by the example: $out"
  printf '%s\n' "$out" | grep -qF "FENCE-EXAMPLE" || fail "$1: the example is not printed: $out"
  if printf '%s\n' "$out" | grep -qF "closed by round"; then fail "$1: something was closed: $out"; fi
}
STATUS_EX='## Round 1 defects
| # | Status | Evidence |
|---|---|---|
| 1 (broken) | Fixed | FENCE-EXAMPLE |'
VERDICT_EX="Second review, reviewer: claude (x)
Reviewed commit: $C2
Max severity: none
Ship allowed: yes"
# review 2, finding 1: every CommonMark fence form, and indented code, closes nothing
c_fence_1() { fence_case "tilde fence" "~~~
$STATUS_EX

$VERDICT_EX
~~~"; }
c_fence_2() { fence_case "tilde fence, backtick lines inside do not close it" "~~~ markdown
\`\`\`
an inner example
\`\`\`
$STATUS_EX

$VERDICT_EX
~~~"; }
c_fence_3() { fence_case "fence indented by up to three spaces" "   \`\`\`
$STATUS_EX

$VERDICT_EX
  \`\`\`"; }
c_fence_4() { fence_case "four backticks around three" "\`\`\`\`markdown
an example that opens a fence of three:
\`\`\`
$STATUS_EX

$VERDICT_EX
\`\`\`\`"; }
c_fence_5() { fence_case "a closing line with text after it does not close" "\`\`\`
\`\`\` not a close
$STATUS_EX
\`\`\`"; }
c_fence_6() { fence_case "indented code" "
    ## Round 1 defects
    | # | Round-1 row | Status |
    |---|---|---|
    | 1 | 1 - broken | Fixed |
    FENCE-EXAMPLE
	| 1 | 1 - broken (tab) | Fixed |"; }
c_fence_7() { fence_case "an unclosed tilde fence runs to the end" "~~~
$STATUS_EX
$VERDICT_EX"; }

c_fence_closes_again() { # after a fence closes (each form), a real status table outside it still closes the finding
  local out open close
  notes
  for pair in '```|```' '~~~~|~~~~~' '  ````md|````' '~~~|   ~~~'; do
    open=${pair%%|*}; close=${pair#*|}
    { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | minor | a.sh:1 | F-REALLY-FIXED | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
      printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n%s\n```\nx\n```\n%s\n\n    indented code\n\n%s\n' "$open" "$close" "$STATUS_EX"
      verdict "$C2" none yes; } > "$T/notes/review.md"
    out=$(ctx "$T" merge) || fail "context failed: $out"
    printf '%s\n' "$out" | sed -n '/^## notes\/review.md/,/^--- Round 2/p' | grep -qF "F-REALLY-FIXED" && fail "fence $open ... $close never closed: the real fix after it was not read: $out"
    has "$out" "- #1 (defect, minor): closed by round 2, status rows"
  done
}

# review 3, finding 1: a fence marker inside a list item or a quote; the rest of that round closes nothing
LIST_EX='  | # | Round-1 row | Status |
  |---|---|---|
  | 1 | 1 - broken | Fixed |
  FENCE-EXAMPLE'
c_list_1() { fence_case "list item, tilde fence" "- an example:
- ~~~
$LIST_EX
  ~~~"; }
c_list_2() { fence_case "list item, backtick fence" "- an example:
- \`\`\`markdown
$LIST_EX
  \`\`\`"; }
c_list_3() { fence_case "numbered item, fence" "1. an example:
2. ~~~
$LIST_EX
   ~~~"; }
c_list_4() { fence_case "quoted fence" "> ~~~
> | # | Round-1 row | Status |
> |---|---|---|
> | 1 | 1 - broken | Fixed |
> FENCE-EXAMPLE
> ~~~"; }
c_list_5() { fence_case "nested list item, fence indented 4" "- outer
  - ~~~
$LIST_EX
    ~~~"; }
unsure_case() { # unsure_case <name> <expect: kept|closed by round <n>> <round-2 text before the fix> [round-3 text]
  # round 1 has one defect; round 2 holds the text given, then a status row that fits it exactly
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | minor | a.sh:1 | F-LIST-ONE lint | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n%s\n\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 1 (lint) | Fixed | a.sh:1 |\n' "$3"; verdict "$C2" none yes
    [ -z "${4:-}" ] || { printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\n%s\n' "$4"; verdict "$C2" none yes; }
    printf -- '\n--- Round 9, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "$1: context failed: $out"
  case "$2" in
    kept) printf '%s\n' "$out" | grep -qF "F-LIST-ONE" || fail "$1: the fix after an unsure fence closed the finding: $out"
          if printf '%s\n' "$out" | grep -qF "closed by round"; then fail "$1: something was closed: $out"; fi ;;
    *) if printf '%s\n' "$out" | grep -qF "F-LIST-ONE"; then fail "$1: want the finding $2, it is still there: $out"; fi
       printf '%s\n' "$out" | grep -qF -- "- #1 (defect, minor): $2, status rows" || fail "$1: want '$2': $out" ;;
  esac
}
c_list_6() { unsure_case "a list-item fence before the fix" kept "- ~~~
  example
  ~~~"; }
c_list_8() { unsure_case "a quote fence before the fix" kept "> ~~~
> example
> ~~~"; }
c_list_9() { # the controls: the same fix row closes after a plain fence, and in the round after an unsure one
  unsure_case "a plain fence before the fix" "closed by round 2" "~~~
example
~~~"
  unsure_case "the round after a list-item fence" "closed by round 3" "- ~~~
  example
  ~~~" "## Round 1 defects
| # | Status | Evidence |
|---|---|---|
| 1 (lint) | Fixed | a.sh:1 |"
}

c_list_7() { # a list item that starts with a multibyte character is read, not a crash (BSD awk counts bytes)
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | minor | a.sh:1 | F-MULTI | eval | fix |\n- \342\200\234One reload\342\200\235 is conditional.\n1. \303\251t\303\251\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge 2>&1) || fail "context failed: $out"
  has "$out" "## notes/review.md: round 2 of 2"; has "$out" "F-MULTI"; hasnt "$out" "multibyte"
}

c_strict_fence_close() { # review 4, finding 1 (notes/review-probe-4.md): a top-level fence closes only on a top-level marker
  local out
  notes
  cat > "$T/notes/review.md" <<'PROBE4'
--- Round 1, 2026-11-19, reviewer: codex
| # | Class | Severity | Where | What is wrong | Violates | Fix |
|---|---|---|---|---|---|---|
| 1 | defect | major | a.sh:1 | F-KEEP-ME broken | eval | fix |
Reviewed commit: 1111111111111111111111111111111111111111
Max severity: major
Ship allowed: no

--- Round 2, 2026-11-19, reviewer: codex
An example of the prompt:
```
- an item
  - ```
--- Round 7, example
## Round 1 defects
| # | Status | Evidence |
|---|---|---|
| 1 (broken) | Fixed | x |
```
Reviewed commit: 2222222222222222222222222222222222222222
Max severity: major
Ship allowed: no
PROBE4
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-KEEP-ME"; hasnt "$out" "closed by round"; has "$out" "## notes/review.md: round 2 of 2"
}

# review 3, finding 2: what keeps a finding counts wherever it is written, code and quotes included
neg_case() { # neg_case <name> <round-3 text>: round 2 marks #7 fixed; round 3 takes it back in the text given
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 7 | defect | major | a.sh:7 | F-SEVEN-BACK | eval | fix |\n' "$FIND"; verdict "$C1" major no
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n## Round 1 defects\n| # | Status | Evidence |\n|---|---|---|\n| 7 (seven) | Fixed | x |\n'; verdict "$C2" none yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\n%s\n' "$2"; verdict "$C2" major no
    printf -- '\n--- Round 4, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" major no; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "$1: context failed: $out"
  printf '%s\n' "$out" | grep -qF "F-SEVEN-BACK" || fail "$1: the finding was dropped though a later round says it is not fixed: $out"
}
c_neg_1() { neg_case "an indented row" "## Round 1 defects
| # | Status | Evidence |
|---|---|---|
    | 7 (seven) | Not fixed | INDENTED-NEG |"; }
c_neg_2() { neg_case "a row in a fence" "## Round 1 defects
\`\`\`
| # | Status | Evidence |
|---|---|---|
| 7 (seven) | Not fixed | FENCED-NEG |
\`\`\`"; }
c_neg_3() { neg_case "a quoted table" "## Round 1 defects
> | # | Status | Evidence |
> |---|---|---|
> | 7 (seven) | Open | QUOTED-NEG |"; }
c_neg_4() { # a verdict that is not yes, even in code, keeps a round from passing
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | major | a.sh:1 | F-VERDICT-KEPT | eval | fix |\n' "$FIND"; verdict "$C1" major no
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n'; verdict "$C2" none yes
    printf '\n    Ship allowed: no\n\nSecond review, reviewer: claude (claude-opus-5-5)\n'; verdict "$C2" none yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "F-VERDICT-KEPT"
  sed '/^    Ship allowed: no$/d' "$T/notes/review.md" > "$T/notes/r.tmp" && cat "$T/notes/r.tmp" > "$T/notes/review.md" && rm -f "$T/notes/r.tmp"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  hasnt "$out" "F-VERDICT-KEPT"; has "$out" "- #1 (defect, major): closed by round 2, passing verdicts"   # the control: without it the round passes
}

c_cut_round_labels() { # review 1, finding 2: a status table names a round by its written number, never by its place
  local out
  notes
  # repeated labels: Round 1, Round 1 (gate format), Round 2, Round 3
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 7 | defect | minor | a:7 | F-R1-SEVEN | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 1 (gate format), 2026-11-19, reviewer: codex\n%s\n| 7 | defect | minor | a:7 | F-R1B-SEVEN | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\n%s\n| 7 | defect | minor | a:7 | F-R2-SEVEN | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\n## Round 2 defects\n| # | Finding | Status |\n|---|---|---|\n| 1 | 7 - seven | Fixed |\n\n## Round 1 defects\n| # | Finding | Status |\n|---|---|---|\n| 1 | 7 - seven | Fixed |\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  hasnt "$out" "F-R2-SEVEN"; has "$out" "- #7 (defect, minor): closed by round 3, status rows"   # the trace names written rounds
  has "$out" "F-R1-SEVEN"; has "$out" "F-R1B-SEVEN"                                    # "Round 1" is two rounds: nothing closed
  # skipped labels: Round 1, Round 3, Round 4; a reference to Round 2 matches no round
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | minor | a:1 | F-A-ONE | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 3, 2026-11-19, reviewer: codex\n%s\n| 1 | defect | minor | a:1 | F-B-ONE | eval | fix |\n| 2 | defect | minor | a:2 | F-C-TWO | eval | fix |\n' "$FIND"; verdict "$C1" minor yes
    printf -- '\n--- Round 4, 2026-11-19, reviewer: codex\n## Round 3 defects\n| # | Finding | Status |\n|---|---|---|\n| 1 | 2 - two | Fixed |\n\n## Round 2 defects\n| # | Finding | Status |\n|---|---|---|\n| 1 | 1 - one | Fixed |\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  hasnt "$out" "F-C-TWO"; has "$out" "- #2 (defect, minor): closed by round 4, status rows"
  has "$out" "F-A-ONE"; has "$out" "F-B-ONE"
}

two_rounds() { # two_rounds <round-2 text>: round 1 has a major and a minor defect; round 2 is the text given
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex (gpt-6-astra, effort high)\n%s\n| 1 | defect | major | a:1 | F-MAJOR | eval | fix |\n| 2 | defect | minor | a:2 | F-MINOR-NOMARK | eval | fix |\n' "$FIND"
    verdict "$C1" major no; printf '\n%s\n' "$1"; } > "$T/notes/review.md"
}
c_cut_verdict() { # a blocking finding is closed by verdict only when the later round is complete and passing, as the gate reads it
  local out h='--- Round 2, 2026-11-19, reviewer: codex (gpt-6-astra, effort high)' s='Second review, reviewer: claude (claude-fable-5-2)'
  notes
  two_rounds "$(printf '%s\nfixed it\n' "$h"; verdict "$C2" none yes)"
  out=$(ctx "$T" merge) || fail "context failed: $out"; has "$out" "F-MAJOR"            # no second review
  two_rounds "$(printf '%s\n' "$h"; verdict "$C2" none yes; printf '\n%s\nstill reading\n' "$s")"
  out=$(ctx "$T" merge) || fail "context failed: $out"; has "$out" "F-MAJOR"            # the second review is unfinished
  two_rounds "$(printf '%s\n' "$h"; verdict "$C2" none yes; printf '\n%s\n' "$s"; verdict "$C2" major no)"
  out=$(ctx "$T" merge) || fail "context failed: $out"; has "$out" "F-MAJOR"            # the second review says no
  two_rounds "$(printf '%s\n' "$h"; verdict "$C2" none yes; printf '\n%s\n' "$s"; verdict "$C1" none yes)"
  out=$(ctx "$T" merge) || fail "context failed: $out"; has "$out" "F-MAJOR"            # two different commits
  two_rounds "$(printf '%s\n' "$h"; verdict "$C2" major no; printf '\n%s\n' "$s"; verdict "$C2" major no
    printf -- '\n--- Decision room override, 2026-11-19\nOVERRIDE-TEXT merge despite the remaining defects (D9)\n'; verdict "$C2" major yes)"
  out=$(ctx "$T" merge) || fail "context failed: $out"; has "$out" "F-MAJOR"; has "$out" "OVERRIDE-TEXT"   # an override is not a fix
  two_rounds "$(printf '%s\n' "$h"; verdict "$C2" none yes; printf '\n%s\n' "$s"; verdict "$C2" none yes)"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  hasnt "$out" "F-MAJOR"; has "$out" "- #1 (defect, major): closed by round 2, passing verdicts"
  has "$out" "F-MINOR-NOMARK"                                                             # a verdict closes blocking rows only
}

c_cut_tests() { # a check leaves only when a later round passes that same check, whole; no round leaves as a whole
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19\nTested commit: %s\nResult: fail\n| Check | Result | Evidence | Note |\n|---|---|---|---|\n' "$C1"
    printf '| E-1 build | fail | T-NOTRUN | |\n| E-2 api | fail | T-BLOCKED | |\n| E-3 ui | fail | T-PARTLY | |\n| E-4 db | fail | T-FAIL | |\n'
    printf '| E-5 full build | fail | T-QUALIFIED | |\n| E-6 login | fail | T-PASSED | |\n| E-7 scope a | fail | T-OTHERCELL | |\n'
    printf '| A-1 cited evidence | pass | T-CITED | |\n| A-2 rerun | pass | T-RERUN | |\n| A-3 files | pass, 11 files / 88 tests | T-COUNTED | |\n'
    printf 'Bite check: R1-BITE broke one line, failed as expected\n'
    printf -- '\n--- Round 2, 2026-11-19\nTested commit: %s\nResult: pass\n| Check | Result | Evidence | Note |\n|---|---|---|---|\n' "$C2"
    printf '| E-1 build | not run | | |\n| E-2 api | blocked | | |\n| E-3 ui | partly | | |\n| E-4 db | fail | | |\n'
    printf '| E-5 full build | pass (compiles); page-data not verified | | |\n| E-6 login | pass | | |\n| E-7 scope b | pass | | |\n| A-2 rerun | pass | | |\n| A-3 files | pass, 12 files | | |\n'
    printf -- '\n--- Round 2 (gate format), 2026-11-19\nTested commit: %s\nResult: pass\nEvidence: the round 1 table above.\n' "$C2"; } > "$T/notes/test.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "T-NOTRUN"; has "$out" "T-BLOCKED"; has "$out" "T-PARTLY"; has "$out" "T-FAIL"; has "$out" "T-QUALIFIED"
  has "$out" "T-OTHERCELL"; has "$out" "T-CITED"; has "$out" "T-COUNTED"; has "$out" "R1-BITE"
  hasnt "$out" "T-PASSED"; hasnt "$out" "T-RERUN"
  has "$out" "--- Round 1, 2026-11-19"; has "$out" "the round 1 table above"
}

c_cut_requirements() { # a requirement row leaves only when its Met cell is exactly yes
  local out
  notes
  { printf -- '--- Round 1, 2026-11-19, reviewer: codex\n## Requirements\n| FR | Met | Evidence |\n|---|---|---|\n'
    printf '| FR-1 | yes | FR-EXACT |\n| FR-2 | Yes by inspection; partially tested | FR-QUALIFIED |\n| FR-3 | Partly | FR-PARTLY |\n| FR-4 | yes, with finding 1 | FR-WITH-FINDING |\n| FR-5 | **Yes.** | FR-BOLD |\n'
    verdict "$C1" minor yes; printf -- '\n--- Round 2, 2026-11-19, reviewer: codex\nNEWEST\n'; verdict "$C2" none yes; } > "$T/notes/review.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  hasnt "$out" "FR-EXACT"; hasnt "$out" "FR-BOLD"
  has "$out" "FR-QUALIFIED"; has "$out" "FR-PARTLY"; has "$out" "FR-WITH-FINDING"
}

role_table() { # the subject table of decision-room.md as "<subject> <note> <form>" lines
  awk -F'|' '
    /^\| *Subject *\|/ { for (i = 3; i < NF; i++) { n = $i; gsub(/[ `]/, "", n); col[i] = n } t = 1; next }
    t && /^\|[ :|-]+$/ { next }
    t && /^\|/ { s = $2; gsub(/[ `]/, "", s); for (i = 3; i < NF; i++) { f = $i; gsub(/^ +| +$/, "", f); print s, col[i], f } next }
    t { exit }' "$ROLE_DIR/decision-room.md"
}
c_subject_table() { # E-3: every note is where the table of the role file says, for every subject it names
  local out tab rows s n f seen=""
  all_notes
  tab=$(role_table)
  rows=$(printf '%s\n' "$tab" | grep -c .) || true
  [ "$rows" -ge 24 ] || fail "decision-room.md has no subject table of three rows and eight notes (got $rows cells)"
  while read -r s n f; do
    case " $seen " in *" $s "*) ;; *) seen="$seen $s"; out=$(ctx "$T" "$s") || fail "context failed for $s: $out" ;; esac
    case "$f" in
      whole) in_sect "$out" "## Read whole" "- $T/notes/$n ($(size "$T/notes/$n") bytes)" ;;
      rounds) has "$out" "## notes/$n: round 2 of 2"; has "$out" "new ${n%.md}"; has "$out" "$T/notes/$n ($(size "$T/notes/$n") bytes)" ;;
      open) in_sect "$out" "## Left out for $s" "- $T/notes/$n ($(size "$T/notes/$n") bytes)"; in_sect "$out" "## Open questions" "Which colour?" ;;
      "left out") in_sect "$out" "## Left out for $s" "- $T/notes/$n ($(size "$T/notes/$n") bytes)" ;;
      *) fail "the table has a form this test does not know: '$f' ($s, $n)" ;;
    esac
  done <<TABLE
$tab
TABLE
  for s in plan merge ready; do case " $seen " in *" $s "*) ;; *) fail "the table has no row for $s" ;; esac; done
}

stage_is() { sed "s/^Stage: .*/Stage: $1/" "$T/rd.md" > "$T/rd.tmp" && cat "$T/rd.tmp" > "$T/rd.md" && rm -f "$T/rd.tmp" || fail "could not set the stage"; }
c_stage_rows() { # Q<n>, S<n> and other read the row of the ticket's stage; S<n> prints its own suggestion
  local out
  all_notes
  out=$(ctx "$T" Q1) || fail "context failed: $out"                      # not started: the ready row
  in_sect "$out" "## Left out for Q1" "$T/notes/plan.md"; has "$out" "## notes/review.md: round 2 of 2"
  stage_is plan
  out=$(ctx "$T" Q1) || fail "context failed: $out"                      # a plan-stage question has the plan
  in_sect "$out" "## Read whole" "$T/notes/plan.md"; has "$out" "## notes/plan-review.md: round 2 of 2"
  stage_is check
  out=$(ctx "$T" other) || fail "context failed: $out"                   # the second-failed-check question has check.md
  in_sect "$out" "## Read whole" "$T/notes/check.md"; in_sect "$out" "## Read whole" "$T/notes/review-response.md"
  has "$out" "## notes/review.md: round 2 of 2"; has "$out" "## notes/test.md: round 2 of 2"
  sa suggest "$TK" "demo#001 worker" "SUGG-ONE-IDEA" "seen at a.sh:1" >/dev/null || fail "suggest failed"
  sa suggest "$TK" "demo#001 worker" "SUGG-TWO-IDEA" "seen at a.sh:2" >/dev/null || fail "suggest failed"
  out=$(ctx "$TK" S1) || fail "context failed for S1: $out"
  in_sect "$out" "## Suggestion S1" "SUGG-ONE-IDEA"; hasnt "$(sect "$out" "## Suggestion S1")" "SUGG-TWO-IDEA"
  out=$(ctx "$T" S2) || fail "context failed for S2 on a ticket: $out"
  in_sect "$out" "## Suggestion S2" "SUGG-TWO-IDEA"; hasnt "$(sect "$out" "## Suggestion S2")" "SUGG-ONE-IDEA"
}

decide_on() { # decide_on <dir> <subject> <question> <tag>
  sa room decide "$1" "$2" "$3" --option "yes: go" --option "no: wait" --fable a "fable says $4" --codex a "codex says $4" >/dev/null || fail "decide failed: $3"
}
c_set_decisions() { # E-4: the ticket's decisions (its subject in full), the project's as lines, nothing of another ticket
  local out
  second_ticket
  sa room on "$F" 2026-11-19 "$WORDS" >/dev/null || fail "room on failed"
  decide_on "$T" plan "Plan question?" p1
  decide_on "$T" merge "Merge question one?" m1
  decide_on "$T" merge "Merge question two?" m2
  decide_on "$T2" other "Other ticket asks about demo#001?" o1
  decide_on "$TK" other "Project question?" pr
  out=$(ctx "$T" merge) || fail "context failed: $out"
  has "$out" "Merge question one?"; has "$out" "fable says m1"; has "$out" "Merge question two?"; has "$out" "fable says m2"
  [ "$(printf '%s\n' "$out" | grep -c '^Decision: ')" = 2 ] || fail "want two decisions in full, got: $out"
  has "$out" "Plan question?"; hasnt "$out" "fable says p1"; has "$out" "D1 "
  in_sect "$out" "## Decisions on the whole project" "Project question?"; hasnt "$out" "fable says pr"
  hasnt "$out" "Other ticket asks"
  out=$(ctx "$T" plan) || fail "context failed for plan: $out"
  has "$out" "fable says p1"; hasnt "$out" "fable says m1"; has "$out" "Merge question two?"
}

c_set_folder_notes() { # review 1, finding 3: a tickets-folder question gets every project note, past 40 entries
  local out i
  sa room on "$F" 2026-11-01 "$WORDS" >/dev/null || fail "room on failed"
  sa room off "$F" "a pause" >/dev/null || fail "room off failed"
  sa room on "$F" 2026-11-19 "$WORDS" >/dev/null || fail "room on failed"
  sa room note "$TK" clerk "NOTE-FOLDER-OLDEST the owner wants squash merges" >/dev/null || fail "note failed"
  for i in $(seq 1 45); do logline demo note "clerk: folder note $i"; done
  for i in $(seq 1 5); do logline demo stage "router: stage line $i"; done
  out=$(ctx "$TK" other) || fail "context failed: $out"
  in_sect "$out" "## Notes of the project" "NOTE-FOLDER-OLDEST"; in_sect "$out" "## Notes of the project" "folder note 45"
  [ "$(sect "$out" "## Notes of the project" | grep -c 'decision room switched')" = 1 ] || fail "want only the last switch note: $(sect "$out" "## Notes of the project")"
  has "$out" "stage line 5"
  [ "$(printf '%s\n' "$out" | grep -c 'folder note 1$')" = 1 ] || fail "a note is printed twice: $out"
}

c_set_standing() { # nothing a guarantee names leaves by age: rules, notes, decisions, open questions
  local out i
  notes; second_ticket
  printf '\n## Rules from this repo that apply to tickets\n- RULE-REPO deploy the backend first\n\n## Rules from the user\n- 2026-11-01: RULE-OLD never touch live Stripe\n\n## Agents may not\n- RULE-MAYNOT print a secret\n\n## Sharp edges\n- EDGE\n\n## Owner decisions\n- OWNER-DEC\n' >> "$TK/PROJECT.md"
  sa room on "$F" 2026-11-01 "$WORDS" >/dev/null || fail "room on failed"
  sa room off "$F" "a pause" >/dev/null || fail "room off failed"
  sa room on "$F" 2026-11-19 "$WORDS" >/dev/null || fail "room on failed"
  sa room note "$TK" clerk "NOTE-OLD-RULE the owner wants squash merges" >/dev/null || fail "note failed"
  for i in $(seq 1 12); do logline demo note "clerk: newer note $i"; done
  sa learn "$TK" "demo#001 worker" "LESSON-TRAP node 20 cannot run the tests" >/dev/null || fail "learn failed"
  decide_on "$T" merge "Old merge question?" old
  printf '## Q1 [open]\nFrom: worker\nQuestion: OLD-OPEN-QUESTION?\n- (a) one\n- (b) two\n' > "$T/notes/questions.md"
  event "$T" "ready: oldest-line"
  for i in $(seq 1 40); do logline "demo#001" report "worker: ready: filler $i"; logline "demo#001" dispatch "worker: started by router: stage build, model sonnet, effort medium"; done
  out=$(ctx "$T" merge) || fail "context failed: $out"
  in_sect "$out" "## Notes of the project" "NOTE-OLD-RULE"; in_sect "$out" "## Notes of the project" "newer note 12"
  [ "$(sect "$out" "## Notes of the project" | grep -c 'decision room switched')" = 1 ] || fail "want only the last switch note: $(sect "$out" "## Notes of the project")"
  in_sect "$out" "## Notes of the project" "switched on (the user's standing order of 2026-11-19)"
  in_sect "$out" "## Read whole" "- $TK/PROJECT.md ($(size "$TK/PROJECT.md") bytes)"
  hasnt "$out" "LESSON-TRAP"; in_sect "$out" "## Left out for merge" "- $TK/LEARNED.md ($(size "$TK/LEARNED.md") bytes)"
  has "$out" "fable says old"; has "$out" "OLD-OPEN-QUESTION?"              # from their own records, not from the log slice
  hasnt "$out" "oldest-line"; hasnt "$out" "started by router"; has "$out" "filler 40"; has "$out" "filler 11"; hasnt "$out" "filler 10"
  has "$out" "(the last 30 of"
  printf -- '- 2026-11-19: RULE-NEW added a minute ago\n' >> "$TK/PROJECT.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  in_sect "$out" "## Read whole" "- $TK/PROJECT.md ($(size "$TK/PROJECT.md") bytes)"
  out=$(ctx "$TK" other) || fail "context failed for the tickets folder: $out"
  in_sect "$out" "## Read whole" "- $TK/PROJECT.md ("; has "$out" "NOTE-OLD-RULE"
}

c_set_no_growth() { # E-8: a redispatch adds the new log lines and nothing else
  local out1 out2 log l1 l2 i
  notes
  log="$F/decision-room/demo/LOG.md"
  for i in 1 2 3 4 5 6 7 8; do event "$T" "ready: line $i"; done
  out1=$(ctx "$T" plan) || fail "context failed: $out1"; l1=$(size "$log")
  sa room event "$T" question decision-room "ask agent (plan, round 1): which base?" >/dev/null || fail "event failed"
  sa room event "$T" answer worker "round 1: main | question: which base?" >/dev/null || fail "event failed"
  event "$T" "waiting: ask agent"; event "$T" "ready: answered"
  out2=$(ctx "$T" plan) || fail "context failed: $out2"; l2=$(size "$log")
  [ $(( ${#out2} - ${#out1} )) -le $(( l2 - l1 )) ] || fail "the set grew by $(( ${#out2} - ${#out1} )) for $(( l2 - l1 )) bytes of new lines"
  [ "${#out2}" -gt "${#out1}" ] || fail "the new lines are not in the set"
  [ "$(ctx "$T" plan)" = "$out2" ] || fail "two calls on unchanged files differ"
}

c_set_no_room_bad_input() { # X-1: no room still prints the notes; a folder or a subject that is none is refused
  local out rc before o="$D/outside/tickets/001-demo-ticket"
  mkdir -p "$o/notes" && printf 'results\n' > "$o/notes/results.md" || fail "no notes in the outside project"
  before=$(snap)
  out=$(ctx "$o" merge) || fail "a project with no room must not fail: $out"
  has "$out" "no decision room for this project"; in_sect "$out" "## Read whole" "- $o/notes/results.md (8 bytes)"
  out=$(ctx "$D" merge 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 for a folder that is no ticket and no tickets folder, got $rc: $out"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "want one line for a bad folder, got: $out"
  has "$out" "refused: "
  out=$(ctx "$T" bogus 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 for a subject that is none, got $rc: $out"
  has "$out" "refused: "
  [ "$(snap)" = "$before" ] || fail "a file changed"
}

c_set_no_markers() { # X-2: a note with no round line is listed to read whole; an empty one with 0 bytes
  local out
  notes
  printf 'UNMARKED-BODY one review with no round line\n' > "$T/notes/review.md"; : > "$T/notes/test.md"
  out=$(ctx "$T" merge) || fail "context failed: $out"
  in_sect "$out" "## Read whole" "- $T/notes/review.md ($(size "$T/notes/review.md") bytes)"
  in_sect "$out" "## Read whole" "- $T/notes/test.md (0 bytes)"
}

c_set_access_marks() { # X-3: the marks of an owner-only question survive
  local out
  notes
  printf '## Q1 [open]\nKind: access\nTried: the browser, blocked at the login\nFrom: worker\nQuestion: Which login?\n- (a) one\n- (b) two\n' > "$T/notes/questions.md"
  sed 's/^- None\.$/- **Q2**: Need the owner key? Options: (a) yes (b) no (access)/' "$T/rd.md" > "$T/rd.tmp" && cat "$T/rd.tmp" > "$T/rd.md" && rm -f "$T/rd.tmp"
  out=$(ctx "$T" Q1) || fail "context failed: $out"
  in_sect "$out" "## Open questions" "Kind: access"; in_sect "$out" "## Open questions" "Which login?"
  in_sect "$out" "## Open questions" "Need the owner key?"; in_sect "$out" "## Open questions" "(access)"
}

c_legacy_heading() { # the older output keeps the heading that step 1 of the role file falls back to
  local out
  out=$(sa room context "$T") || fail "context failed: $out"
  has "$out" "# Decision room context: demo#001"; has "$out" "## Files of this ticket"
}

between() { awk -v a="$2" -v b="$3" 'index($0, a) == 1 { f = 1 } f && index($0, b) == 1 && !(index($0, a) == 1) { exit } f' "$1"; }
c_text() { # E-6, E-7, E-10, E-11: the role files, PROTOCOL.md and help name the reading set, and no whole room file
  local room="$ROLE_DIR/decision-room.md" router="$ROLE_DIR/router.md" s1 s4 s6 s8 d p x
  s1=$(between "$room" "1. **" "2. **"); s4=$(between "$room" "4. **" "5. **"); s6=$(between "$room" "6. **" "7. **"); s8=$(between "$room" "8. **" "9. **")
  has "$s1" 'sa room context <ticket folder or tickets folder> <subject>'
  has "$s1" '## Read whole'; has "$s1" '## Files of this ticket'; has "$s1" 'already decided D<n>'
  hasnt "$s1" 'always on that list'; hasnt "$s1" '(every running project'
  for x in LOG.md DECISIONS.md INDEX.md; do hasnt "$s4" "$x"; hasnt "$s6" "$x"; done
  printf '%s\n' "$s4" | grep -F 'Context:' | grep -qF '$stem-context.md' || fail "the Codex prompt does not name the saved reading set"
  has "$s8" '<stem>-context.md'; hasnt "$s8" 'do step 1'
  # review 1, finding 4: no open-ended file list can carry the index or the room's whole files to a seat
  x=$(printf '%s\n' "$s4" | grep -F 'Context:'); hasnt "$x" 'any other file'; has "$x" 'never a whole room file'
  has "$s1" 'never goes on a seat'
  grep -qF '| Subject |' "$room" || fail "decision-room.md has no subject table"
  d=$(grep -F '**Dispatch.** One `decision-room` agent' "$router")
  has "$d" 'sa room context'; hasnt "$d" 'naming them is required'; hasnt "$d" 'DECISIONS.md'
  for x in 'Project room:' 'earlier `D<n>`' 'Clarifying rounds left: 2' '`model: sonnet`' 'holds no position' 'Fable seat unavailable:'; do has "$d" "$x"; done
  p=$(between "$PROTO_FILE" "  - **Before deciding**" "  - **")
  has "$p" 'sa room context <ticket-dir|tickets-dir> <subject>'; has "$p" 'reading set'
  sa help | grep -F 'sa room context' | grep -qF '[<Qn|ready|plan|merge|Sn|other>]' || fail "sa help does not show the subject of room context"
}

run_case "context: only this ticket's lines, plus the project's own" c_only_this_ticket
run_case "context: this ticket's decisions, the newest two in full" c_decisions
run_case "context: long lines are cut, a long history shows its last 40" c_caps
run_case "context: open questions and the ticket's files" c_questions_and_files
run_case "context: reads only; bad input refused; no room says so" c_reads_only
run_case "set: one read-only command, every listed size is the file's size" c_set_one_command
run_case "set: newest round whole, an earlier round without what is closed" c_e2_rounds
run_case "cut: prose and an unresolved status row stay" c_cut_prose_status
run_case "cut: a status row closes only the finding it names without doubt" c_cut_identity
run_case "cut: a verdict closes only in a complete passing round" c_cut_verdict
run_case "cut: a check leaves only on a later exact pass of the same check" c_cut_tests
run_case "cut: a fenced table or verdict closes nothing" c_cut_fenced
run_case "cut: fence form 1, tilde fence: closes nothing" c_fence_1
run_case "cut: fence form 2, tilde fence, backtick lines inside do not close it: closes nothing" c_fence_2
run_case "cut: fence form 3, fence indented by up to three spaces: closes nothing" c_fence_3
run_case "cut: fence form 4, four backticks around three: closes nothing" c_fence_4
run_case "cut: fence form 5, a closing line with text after it does not close: closes nothing" c_fence_5
run_case "cut: fence form 6, indented code: closes nothing" c_fence_6
run_case "cut: fence form 7, an unclosed tilde fence runs to the end: closes nothing" c_fence_7
run_case "cut: a fence that closes ends; a real fix after it still closes" c_fence_closes_again
run_case "cut: list fence 1, a tilde fence in a list item closes nothing" c_list_1
run_case "cut: list fence 2, a backtick fence in a list item closes nothing" c_list_2
run_case "cut: list fence 3, a fence in a numbered item closes nothing" c_list_3
run_case "cut: list fence 4, a quoted fence closes nothing" c_list_4
run_case "cut: list fence 5, a fence in a nested item closes nothing" c_list_5
run_case "cut: list fence 6, a fix after a list-item fence in the same round closes nothing" c_list_6
run_case "cut: list fence 8, a fix after a quote fence in the same round closes nothing" c_list_8
run_case "cut: list fence 9, controls: the fix closes after a plain fence, and in the next round" c_list_9
run_case "cut: a top-level fence closes only on a top-level marker" c_strict_fence_close
run_case "cut: list fence 7, a list item that starts with a multibyte character" c_list_7
run_case "cut: kept 1, an indented Not fixed row keeps the finding" c_neg_1
run_case "cut: kept 2, a fenced Not fixed row keeps the finding" c_neg_2
run_case "cut: kept 3, a quoted Open row keeps the finding" c_neg_3
run_case "cut: kept 4, a verdict that is not yes, in code, keeps a round from passing" c_neg_4
run_case "cut: a status table names a round by its written number" c_cut_round_labels
run_case "cut: a requirement row leaves only when Met is exactly yes" c_cut_requirements
run_case "set: notes by subject, as the role file's table says" c_subject_table
run_case "set: Q<n>, S<n> and other follow the ticket's stage" c_stage_rows
run_case "set: the ticket's decisions and the project's" c_set_decisions
run_case "set: standing content does not leave by age" c_set_standing
run_case "set: a tickets-folder question gets every project note" c_set_folder_notes
run_case "set: a redispatch does not grow it" c_set_no_growth
run_case "set: no room still prints the notes; bad input is refused" c_set_no_room_bad_input
run_case "set: no round markers, and an empty file" c_set_no_markers
run_case "set: the access marks survive" c_set_access_marks
run_case "legacy: without a subject the output keeps its headings" c_legacy_heading
run_case "text: the role files, PROTOCOL.md and help name the reading set" c_text
