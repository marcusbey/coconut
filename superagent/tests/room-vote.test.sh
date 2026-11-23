#!/usr/bin/env bash
# room-vote.test.sh: the vote rules of `sa room decide` (superagent#006): evidence, steelman, a test that
# settles a dispute, a majority of three or more seats, a referee, the safer option when the referee is
# unsure, and old calls that keep their exact record. Every case runs on its own throwaway fixture.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
sa() { bash "$SA_UNDER_TEST" "$@"; }
LINE='^[^ ]+ [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| decision \| .+$'

F=""; D=""; T=""; R=""; LOG=""; DEC=""
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
  drop_dir "$D"
}
state() { local f; for f in "$DEC" "$LOG"; do if [ -e "$f" ]; then cksum < "$f"; else echo absent; fi; done; }
refuses() { # refuses "<text>" <args of room decide>: exit 1, prints "refused: <text>", no record changed
  local want="$1" before out rc; shift
  before=$(state)
  out=$(sa room decide "$@" 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "want exit 1 for '$want', got $rc: $out"
  printf '%s\n' "$out" | grep -qF "refused: $want" || fail "want 'refused: $want', got: $out"
  [ "$(state)" = "$before" ] || fail "a refusal ('$want') changed DECISIONS.md or LOG.md"
}
block() { awk -v h="## D$1" '$0==h {f=1; next} /^## /{f=0} f' "$DEC"; }
has() { block "$1" | grep -qxF -- "$2" || fail "D$1 lacks the line '$2': $(block "$1")"; }
hasnt() { block "$1" | grep -qF -- "$2" && fail "D$1 has '$2': $(block "$1")"; return 0; }
decides() { # decides "<printed line>" <args of room decide>
  local want="$1" out; shift
  out=$(sa room decide "$@" 2>&1) || fail "exit $?: $out"
  [ "$out" = "$want" ] || fail "printed: $out (want: $want)"
}
logs() { # logs "<text after the kind>": the newest decision line, in the log format
  tail -1 "$LOG" | grep -E "$LINE" | grep -qF " | decision | $1" || fail "decision line wrong: $(tail -1 "$LOG")"
}
Q="Keep --legacy?"; O=(--option "Keep it" --option "Drop it")

# --- old calls: the same record as before, whatever the flag order (N-4) ---------------------------
LEGACY_BLOCK='Ticket: demo#001
Subject: Q1
Question: Keep --legacy?
Options:
(a) Keep it
(b) Drop it
🟣 Fable 5.2: a: keeps callers working
🟢 Codex Astra: b: nobody calls it
Decision: (a) Keep it
Decided by: safer-option tie-break (keeping it deletes nothing)'
c_legacy() {
  decides "D1: (a) Keep it; decided by safer-option tie-break (keeping it deletes nothing)" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "keeps callers working" --codex b "nobody calls it" --safer a "keeping it deletes nothing"
  [ "$(block 1 | sed 1d)" = "$LEGACY_BLOCK" ] || fail "block changed: $(block 1)"
  logs "D1 (Q1): Keep --legacy? -> (a) Keep it; decided by safer-option tie-break (keeping it deletes nothing)"
}
c_legacy_reversed() {
  decides "D1: (a) Keep it; decided by safer-option tie-break (keeping it deletes nothing)" "$T" Q1 "$Q" \
    --safer a "keeping it deletes nothing" --codex b "nobody calls it" "${O[@]}" --fable a "keeps callers working"
  [ "$(block 1 | sed 1d)" = "$LEGACY_BLOCK" ] || fail "block changed: $(block 1)"
}
c_legacy_alone() {
  decides "D1: (b) Drop it; decided by codex alone (fable unavailable: usage limit)" "$T" Q1 "$Q" "${O[@]}" \
    --codex b "nobody calls it" --fable-unavailable "usage limit"
  has 1 "🟣 Fable 5.2: unavailable: usage limit"; has 1 "🟢 Codex Astra: b: nobody calls it"; hasnt 1 "evidence"
}

# --- evidence (V-3, V-3b) -----------------------------------------------------------------------
c_no_evidence() {
  decides "D1: (a) Keep it; decided by fable alone (codex: no evidence)" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "why" --evidence fable "cli.ts:12" --codex b "why" --no-evidence codex
  has 1 "🟣 Fable 5.2: a: why"; has 1 "🟣 Fable 5.2 evidence: cli.ts:12"
  has 1 "🟢 Codex Astra: b: why"; has 1 "🟢 Codex Astra evidence: none (position does not count)"
  has 1 "Decided by: fable alone (codex: no evidence)"
  logs "D1 (Q1): Keep --legacy? -> (a) Keep it; decided by fable alone (codex: no evidence)"
}
c_omitted_evidence() { # an extended call: a position without --evidence does not count
  decides "D1: (b) Drop it; decided by codex alone (fable: no evidence)" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "why" --codex b "why" --evidence codex "cli.ts:12 never read"
  has 1 "🟣 Fable 5.2 evidence: none (position does not count)"
}
c_no_counting_seat() {
  refuses "no seat is available; this question reaches the user" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "why" --codex b "why" --no-evidence fable --no-evidence codex
  refuses "no seat is available; this question reaches the user" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "why" --codex b "why" --steelman fable "B is cheaper" "a caller list"
  refuses "no seat is available; this question reaches the user" "$T" Q1 "$Q" "${O[@]}" \
    --fable-unavailable "usage limit" --codex b "why" --no-evidence codex
  refuses "no seat is available; this question reaches the user" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "why" --codex-unavailable "usage limit" --no-evidence fable --referee opus a "x"
  [ ! -e "$DEC" ] || fail "a record was written"
}
c_bad_evidence() {
  local s=(--fable a "why" --codex b "why")
  refuses "--evidence for fable is empty" "$T" Q1 "$Q" "${O[@]}" "${s[@]}" --evidence fable ""
  refuses "fable has both --evidence and --no-evidence" "$T" Q1 "$Q" "${O[@]}" "${s[@]}" --evidence fable "x:1" --no-evidence fable
  refuses "fable has both --evidence and --no-evidence" "$T" Q1 "$Q" "${O[@]}" "${s[@]}" --no-evidence fable --evidence fable "x:1"
  refuses "--evidence for fable is given twice" "$T" Q1 "$Q" "${O[@]}" "${s[@]}" --evidence fable "x:1" --evidence fable "y:2"
  refuses "--evidence names no seat 'gemini'" "$T" Q1 "$Q" "${O[@]}" "${s[@]}" --evidence gemini "x:1"
  refuses "codex is unavailable; --evidence needs a position" "$T" Q1 "$Q" "${O[@]}" --fable a "why" --codex-unavailable "out" --evidence codex "x:1"
  refuses "--steelman for fable needs both texts" "$T" Q1 "$Q" "${O[@]}" "${s[@]}" --steelman fable "x" ""
  [ ! -e "$DEC" ] || fail "a record was written"
}
c_steelman() {
  decides "D1: (a) Keep it; decided by both" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "why" --evidence fable "cli.ts:12" --steelman fable "dropping it simplifies the CLI" "a caller list showing no use" \
    --codex a "why too" --evidence codex "grep: 3 callers"
  has 1 "🟣 Fable 5.2 best other argument: dropping it simplifies the CLI"
  has 1 "🟣 Fable 5.2 would change my mind: a caller list showing no use"
  has 1 "🟢 Codex Astra evidence: grep: 3 callers"
  [ "$(block 1 | grep -n '' | grep -E 'Fable 5.2|Codex Astra' | cut -d: -f2- | sed 's/^[^ ]* //' | cut -c1-11 | tr '\n' ,)" = "Fable 5.2: ,Fable 5.2 e,Fable 5.2 b,Fable 5.2 w,Codex Astra,Codex Astra," ] ||
    fail "lines out of order: $(block 1)"
}

# --- a test settles it (V-5, V-5b) -------------------------------------------------------------
EV=(--fable a "keeps callers" --evidence fable "cli.ts:12" --codex b "unused" --evidence codex "grep finds no caller")
c_test() {
  decides "D1: (b) Drop it; decided by test (grep -n legacy cli.ts)" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" \
    --test b "grep -n legacy cli.ts" "cli.ts:12: legacy unused"
  has 1 "Test: grep -n legacy cli.ts"; has 1 "Test result: cli.ts:12: legacy unused"; has 1 "Test settled: (b)"
  logs "D1 (Q1): Keep --legacy? -> (b) Drop it; decided by test (grep -n legacy cli.ts)"
}
c_test_none_referee() {
  decides "D1: (b) Drop it; decided by referee (opus)" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" \
    --test none "grep -rn legacy ." "no match either way" --referee opus b "Codex cites the failing test"
  has 1 "Test: grep -rn legacy ."; has 1 "Test result: no match either way"; has 1 "Test settled: nothing"
  has 1 "Referee (opus): b: Codex cites the failing test"
}
c_bad_test() {
  refuses "--test must name one of the held positions (a, b)" "$T" Q1 "$Q" "${O[@]}" --option "Later" "${EV[@]}" --test c "x" "y"
  refuses "a test settled it (b); no --referee" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --test b "x" "y" --referee opus a "z"
  refuses "--test needs a letter or none, the command and its result" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --test b "x" ""
  refuses "the seats differ (a, b); --safer must name one of them, with why" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --test none "x" "y"
  [ ! -e "$DEC" ] || fail "a record was written"
}

# --- three seats and a majority (V-7) ----------------------------------------------------------
c_majority() {
  decides "D1: (a) Keep it; decided by majority (2 of 3)" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" \
    --seat gemini a "two scripts use it" --evidence gemini "deploy.sh:4"
  has 1 "gemini: a: two scripts use it"; has 1 "gemini evidence: deploy.sh:4"
  [ "$(block 1 | grep -nE '^(🟣 Fable 5.2|🟢 Codex Astra|gemini):' | cut -d: -f2 | tr '\n' ,)" = "🟣 Fable 5.2,🟢 Codex Astra,gemini," ] || fail "seat order: $(block 1)"
  logs "D1 (Q1): Keep --legacy? -> (a) Keep it; decided by majority (2 of 3)"
  decides "D2: (a) Keep it; decided by majority (3 of 3)" "$T" Q2 "$Q" "${O[@]}" \
    --fable a "x" --evidence fable "e:1" --codex a "y" --evidence codex "e:2" --seat gemini a "z" --evidence gemini "e:3"
}
c_no_majority() {
  local three=("$T" Q1 "$Q" "${O[@]}" --option "Later" "${EV[@]}" --seat gemini c "wait" --evidence gemini "plan.md:3")
  refuses "the seats differ (a, b, c); --safer must name one of them, with why" "${three[@]}"
  decides "D1: (c) Later; decided by referee (opus)" "${three[@]}" --referee opus c "waiting costs nothing"
  refuses "the seats have a majority (a); --test with a letter and --referee are only for seats that differ" "$T" Q2 "$Q" "${O[@]}" "${EV[@]}" \
    --seat gemini a "x" --evidence gemini "e:3" --referee opus b "z"
  refuses "the seats have a majority (a); --test with a letter and --referee are only for seats that differ" "$T" Q2 "$Q" "${O[@]}" \
    --fable a "x" --evidence fable "e:1" --codex a "y" --evidence codex "e:2" --test a "x" "y"
}
c_bad_seat() {
  refuses "the fable seat is given twice" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --seat fable a "x"
  refuses "seat name 'Gem ini' must be lower-case letters, digits or -" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --seat "Gem ini" a "x"
  refuses "gemini's position 'z' is not one of the options (a-b)" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --seat gemini z "x"
  refuses "the codex seat is missing" "$T" Q1 "$Q" "${O[@]}" --fable a "x" --evidence fable "e:1" --seat gemini a "y"
}
c_seat_unavailable() {
  decides "D1: (a) Keep it; decided by both" "$T" Q1 "$Q" "${O[@]}" \
    --fable a "x" --evidence fable "e:1" --codex a "y" --evidence codex "e:2" --seat-unavailable gemini "no key"
  has 1 "gemini: unavailable: no key"
}

# --- the referee (V-9, V-10) -------------------------------------------------------------------
c_referee() {
  decides "D1: (b) Drop it; decided by referee (opus)" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" --referee opus b "Codex cites the failing test"
  has 1 "Referee (opus): b: Codex cites the failing test"; hasnt 1 "Test"
  logs "D1 (Q1): Keep --legacy? -> (b) Drop it; decided by referee (opus)"
}
c_referee_unsure() {
  decides "D1: (b) Drop it; decided by safer-option tie-break (referee unsure: both thin)" "$T" Q1 "$Q" "${O[@]}" "${EV[@]}" \
    --referee opus unsure "both thin" --safer b "does not merge"
  has 1 "Referee (opus): unsure: both thin"
  has 1 "Decided by: safer-option tie-break (referee unsure: both thin)"
  refuses "the seats differ (a, b); --safer must name one of them, with why" "$T" Q2 "$Q" "${O[@]}" "${EV[@]}" --referee opus unsure "both thin"
  refuses "--referee must name one of the held positions (a, b), or unsure" "$T" Q2 "$Q" "${O[@]}" --option "Later" "${EV[@]}" --referee opus c "x"
  refuses "--referee needs a model, a letter or unsure, and why" "$T" Q2 "$Q" "${O[@]}" "${EV[@]}" --referee opus b ""
}
c_help() {
  sa help | grep -q -- '--referee' || fail "help lacks --referee"
  sa help | grep -q -- '--evidence' || fail "help lacks --evidence"
}

run_case "N-4 an old call keeps its exact record" c_legacy
run_case "N-4 an old call in reversed flag order keeps the same record" c_legacy_reversed
run_case "N-4 an old call with one seat out writes no evidence line" c_legacy_alone
run_case "V-3 a position without evidence does not count" c_no_evidence
run_case "V-3b an extended call counts no position without --evidence" c_omitted_evidence
run_case "V-3b no counting seat reaches the user, nothing written" c_no_counting_seat
run_case "V-3b bad evidence flags are refused" c_bad_evidence
run_case "FR-12 the steelman lines are recorded in seat order" c_steelman
run_case "V-5 a test decides" c_test
run_case "V-5b an inconclusive test stays beside the referee" c_test_none_referee
run_case "V-5 bad test flags are refused" c_bad_test
run_case "V-7 three seats: a strict majority decides" c_majority
run_case "V-7 three seats without a majority: no option wins by majority" c_no_majority
run_case "FR-14 bad seats are refused" c_bad_seat
run_case "FR-14 an unavailable extra seat is recorded" c_seat_unavailable
run_case "V-9 the referee decides" c_referee
run_case "V-10 referee unsure: the safer option" c_referee_unsure
run_case "help lists the vote flags" c_help
