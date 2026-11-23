#!/usr/bin/env bash
# seat.sh: the decision room's seat runner (`sa room seat ...`). Runs one seat's call for one try, read-only,
# and prints one last line the host acts on. Text from prompts and answers only moves through files.
#
#   seat.sh <seat> <round> <stem> <project_dir> <try> [effort]
#     reads  <stem>-<seat>-<round>-prompt.md
#     writes <stem>-<seat>-<round>-try<k>-answer.md (exact command line, a blank line, the answer)
#            <stem>-<seat>-<round>-try<k>-stderr.log
#            <stem>-fable-<round>-usage.json (fable: the CLI's whole JSON result)
#     last line: answer <letter> <file> | noletter <file> | retry <reason> | unavailable <reason>
#
#   seat.sh field <answer file> <Position|Reasoning|Evidence|Best other argument|Would change my mind>
#     prints that field of the position on one line (bold labels and continuation lines included)
#
#   seat.sh answer-logged <LOG.md> <ticket id or ""> <subject> <round> <who> <answer file> <question file>
#     prints logged | not logged
#
# A new seat is one row in the seat table of agents/decision-room.md and one case in seat_cmd below.
# Seats today: codex (gpt-6-astra), fable (claude-fable-5-2), carbon (gemini-4-carbon; gemini-4-neon when Carbon
# itself is not available: <stem>-carbon-<round>-model then names the model that answered and why).
set -u

MAX_TRIES=3
SEAT_TIMEOUT=${SEAT_TIMEOUT:-540}   # seconds; below the host's 10-minute shell cap, so a hang still prints `retry`

die() { echo "seat.sh: $*" >&2; exit 2; }
oneline() { tr '\r\n\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c1-300; }

answer_logged() { # unchanged in behaviour from the awk check the role file carried; answer and question from files
  [ $# -eq 7 ] || die "usage: seat.sh answer-logged <LOG.md> <ticket id or \"\"> <subject> <round> <who> <answer file> <question file>"
  local log="$1" ans q
  [ -f "$6" ] && [ -f "$7" ] || die "answer-logged: no such answer or question file"
  ans=$(cat "$6"); q=$(cat "$7")
  [ -f "$log" ] || { echo "not logged"; return 0; }
  TID="$2" SUBJ="$3" K="$4" WHO="$5" ANS="$ans" Q="$q" awk '
    function nl(s) { gsub(/[\r\n]/, " ", s); return s }
    BEGIN { q = nl(ENVIRON["Q"]); tail = ", round " ENVIRON["K"] "): " q
            want = nl(ENVIRON["WHO"]) ": round " ENVIRON["K"] ": " nl(ENVIRON["ANS"]) " | question: " q }
    { n = split($0, f, / \| /); if (n < 4) next
      if (ENVIRON["TID"] == "") { if (index(f[2], "#")) next } else if (f[2] !~ ("#" ENVIRON["TID"] "$")) next
      text = substr($0, length(f[1]) + length(f[2]) + length(f[3]) + 10)
      if (f[3] == "question") {
        if (index(text, "decision-room: ask agent (") == 1) s = substr(text, 27)
        else if (index(text, "decision-room: ask router (") == 1) s = substr(text, 28)
        else next
        if (length(s) > length(tail) && substr(s, length(s) - length(tail) + 1) == tail) owner = substr(s, 1, length(s) - length(tail))
      } else if (f[3] == "answer" && text == want && owner == ENVIRON["SUBJ"]) found = 1 }
    END { print (found ? "logged" : "not logged") }' "$log"
}

seat_field() { # one field of a position, whole: bold marks around the label are skipped and continuation lines are joined
  [ $# -eq 2 ] && [ -f "$1" ] || die "usage: seat.sh field <answer file> <Position|Reasoning|Evidence|Best other argument|Would change my mind>"
  LABEL="$2" awk '
    BEGIN { n = split("position|reasoning|evidence|best other argument|would change my mind", L, "|"); want = tolower(ENVIRON["LABEL"]) }
    NR <= 2 { next }   # the command line and the blank line that start every answer file
    { line = $0; sub(/^[[:space:]*_#>-]+/, "", line); low = tolower(line); hit = ""
      for (i = 1; i <= n; i++) if (index(low, L[i]) == 1) {
        rest = substr(line, length(L[i]) + 1)
        if (rest ~ /^[*_[:space:]]*:/) { hit = L[i]; sub(/^[*_[:space:]]*:[*_[:space:]]*/, "", rest); break } }
      if (hit != "") { on = (hit == want); if (on) out = rest; next }
      if (on && $0 !~ /^[[:space:]]*$/) out = out " " $0 }
    END { gsub(/[[:space:]]+/, " ", out); sub(/^ /, "", out); sub(/ $/, "", out); print out }' "$1"
}

[ "${1:-}" = "answer-logged" ] && { shift; answer_logged "$@"; exit $?; }
[ "${1:-}" = "field" ] && { shift; seat_field "$@"; exit $?; }

[ $# -ge 5 ] && [ $# -le 6 ] || die "usage: seat.sh <seat> <round> <stem> <project_dir> <try> [effort]"
seat=$1; round=$2; stem=$3; project_dir=$4; try=$5; effort=${6:-high}
case "$round" in 1|2) ;; *) die "round must be 1 or 2" ;; esac
case "$try" in 1|2|3) ;; *) die "try must be 1, 2 or 3" ;; esac
case "$effort" in low|medium|high|xhigh) ;; *) effort=high ;; esac
[ -d "$project_dir" ] || die "no project folder: $project_dir"
prompt="$stem-$seat-$round-prompt.md"
[ -f "$prompt" ] || die "no prompt file: $prompt"
answer="$stem-$seat-$round-try$try-answer.md"
errlog="$stem-$seat-$round-try$try-stderr.log"
raw="$stem-$seat-$round-try$try-raw.out"

seat_cmd() { # sets cmd: the exact, read-only command of each seat
  case "$seat" in
    codex) cmd=(codex exec -m gpt-6-astra -c "model_reasoning_effort=$effort" -s read-only --skip-git-repo-check -C "$project_dir" -) ;;
    # --safe-mode keeps the owner's hooks, CLAUDE.md, plugins, skills, MCP servers and output style out of the call
    fable) cmd=(claude -p --model claude-fable-5-2 --effort "$effort" --safe-mode --strict-mcp-config
                --tools Read,Grep,Glob --allowedTools Read,Grep,Glob --permission-mode dontAsk
                --add-dir "$(dirname "$stem")" --no-session-persistence --output-format json) ;;
    # Google's strongest reasoning model of its newest family (aistudio.google.com/docs/models, read 2026-11-22).
    # --approval-mode plan is the CLI's read-only mode. It runs on the CLI's own Google sign-in (the owner's
    # subscription), never an API key; until the owner has signed in with Google there, the seat is out.
    # The owner's rule of 2026-11-22: Carbon, and Neon only when Carbon is not available.
    carbon) cmd=(gemini -m "${GOOGLE_MODEL:-gemini-4-carbon}" --approval-mode plan --include-directories "$(dirname "$stem")"
                 -o json -p "Follow the instructions given on standard input.") ;;
    *) die "unknown seat: $seat" ;;
  esac
}
GOOGLE_MODEL=""   # set only by the fallback below, never taken from the caller
seat_cmd

run_limited() { # run "${cmd[@]}" < prompt with a time limit; sets rc (124 on timeout)
  local pid w
  # The owner's rule of 2026-11-22: a seat runs on the subscription its CLI is signed in to, never on an API key,
  # so the four key variables are taken out of the seat's environment.
  (cd "$project_dir" && exec env -u ANTHROPIC_API_KEY -u GEMINI_API_KEY -u GOOGLE_API_KEY -u OPENAI_API_KEY "${cmd[@]}") < "$prompt" > "$raw" 2> "$errlog" &
  pid=$!
  ( n=0; while kill -0 "$pid" 2>/dev/null; do
      [ "$n" -ge "$SEAT_TIMEOUT" ] && { touch "$raw.timeout"; kill "$pid" 2>/dev/null; break; }
      sleep 1; n=$((n + 1)); done ) 2>/dev/null &
  w=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  if [ -f "$raw.timeout" ]; then rm -f "$raw.timeout"; rc=124; fi
  return 0
}

modelfile="$stem-$seat-$round-model"   # the model that answered, when a seat has more than one
{ printf '%q ' "${cmd[@]}"; printf '< %q\n\n' "$prompt"; } > "$answer"
if ! command -v "${cmd[0]}" >/dev/null 2>&1; then
  echo "${cmd[0]}: command not found" >> "$errlog"; rm -f "$raw"
  echo "unavailable ${cmd[0]}: command not found"; exit 0
fi
run_limited
# The Google seat's second model: when Carbon itself is not available (the model is not found or not offered to this
# account, or its quota is used up) and the CLI is otherwise working, the same try asks Neon once. A sign-in
# failure is not such a case: then both models are out.
if [ "$seat" = carbon ] && [ -z "${GOOGLE_MODEL:-}" ] && [ "$rc" != 0 ] && [ "$rc" != 124 ]; then
  case "$(tail -n 5 "$errlog" 2>/dev/null | tr 'A-Z' 'a-z')" in
    *"gemini_api_key"*|*"auth method"*|*"login with google"*|*"unauthenticated"*) : ;;
    *"not found"*|*"not_found"*|*"not supported"*|*"not available"*|*"unavailable"*|*"quota"*|*"resource_exhausted"*|*"limit reached"*|*"usage limit"*)
      first=$(grep -v '^[[:space:]]*$' "$errlog" | tail -1 | oneline)
      GOOGLE_MODEL=gemini-4-neon; seat_cmd
      { printf '%q ' "${cmd[@]}"; printf '< %q\n\n' "$prompt"; } > "$answer"
      printf 'gemini-4-neon (gemini-4-carbon was not available: %s)\n' "$first" > "$modelfile"
      run_limited ;;
  esac
fi
[ "$seat" = carbon ] && [ ! -s "$modelfile" ] && [ "$rc" = 0 ] && echo "gemini-4-carbon" > "$modelfile"

# The answer text, and for fable the error fields, from the CLI's JSON.
is_error=0; errtext=""
if [ "$seat" = fable ] && [ -s "$raw" ]; then
  usage="$stem-fable-$round-usage.json"
  if python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$raw" 2>/dev/null; then
    cat "$raw" > "$usage"
    python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.stdout.write(str(d.get("result") or ""))' "$raw" >> "$answer"
    errtext=$(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
if d.get("is_error") or d.get("subtype") != "success":
    print("is_error", d.get("api_error_status") or "", d.get("api_error_type") or "", d.get("terminal_reason") or "", str(d.get("result") or "")[:300])' "$raw" | oneline)
    [ -n "$errtext" ] && is_error=1
  else
    cat "$raw" >> "$answer"
  fi
elif [ "$seat" = carbon ] && [ -s "$raw" ] && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d.get("response"), str)' "$raw" 2>/dev/null; then
  python3 -I -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))["response"])' "$raw" >> "$answer"
else
  cat "$raw" >> "$answer" 2>/dev/null
fi
rm -f "$raw"

# Failures: a final one ends the seat at once; everything else is temporary until the last try.
if [ "$rc" != 0 ] || [ "$is_error" = 1 ]; then
  last=$( { [ -n "$errtext" ] && printf '%s\n' "$errtext"; grep -v '^[[:space:]]*$' "$errlog" | tail -1; } | oneline)
  [ "$rc" = 124 ] && last="timed out after $SEAT_TIMEOUT seconds"
  [ -n "$last" ] || last="exit $rc"
  # only the error itself: codex echoes the prompt on stderr, so its last lines, never the whole log
  all=$( { printf '%s\n' "$errtext"; tail -n 5 "$errlog"; } | tr 'A-Z' 'a-z')
  case "$all" in
    *"rate limit"*|*"rate_limit"*|*"429"*|*"overloaded"*) : ;;   # temporary, though "limit reached" may follow
    *"command not found"*|*"not logged in"*|*"please run /login"*|*"login required"*|*"log in again"*|*"authentication_error"*|*"invalid api key"*|*"unauthorized"*|*" 401 "*|*"is_error 401"*|*"is_error 403"*|*"oauth"*" expired"*|*"gemini_api_key"*|*"auth method"*|*"login with google"*|*"api key not valid"*|*"api_key_invalid"*|*"permission_denied"*|*"unauthenticated"*|\
    *"model unavailable"*|*"model_not_found"*|*"not_found_error"*|*"is_error 404"*|*"model is not supported"*|*"models/"*"is not found"*|*"issue with the selected model"*|\
    *"usage limit"*|*"limit reached"*|*"quota"*|*"insufficient_quota"*|*"credit balance"*)
      [ "$rc" = 124 ] || { echo "unavailable $last"; exit 0; } ;;
  esac
  # anything else (HTTP 5xx, network error, timeout, an unknown failure) is temporary
  if [ "$try" -ge "$MAX_TRIES" ]; then echo "unavailable $MAX_TRIES failed tries: $last"; else echo "retry $last"; fi
  exit 0
fi

# An answer: its Position letter must be one of the prompt's lettered options (any letter when it lists none).
letters=$(sed -n 's/^(\([A-Za-z]\)) .*/\1/p' "$prompt" | tr 'A-Z' 'a-z' | tr -d '\n')
letter=$(sed -n '1,2d; s/^[[:space:]*]*Position:[[:space:]*]*(\{0,1\}\([A-Za-z]\))\{0,1\}\([[:space:].,:;*].*\)\{0,1\}$/\1/p' "$answer" | head -1 | tr 'A-Z' 'a-z')
if [ -n "$letter" ] && { [ -z "$letters" ] || case "$letters" in *"$letter"*) true ;; *) false ;; esac; }; then
  echo "answer $letter $answer"
else
  echo "noletter $answer"
fi
