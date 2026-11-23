#!/usr/bin/env bash
# run.sh [name]: run every superagent/tests/*.test.sh, or only <name>.test.sh.
# The sa under test is $SA_UNDER_TEST when set (e.g. the base branch's copy), else this checkout's sa.
# Prints "ok <case>" / "FAIL <case>" per case; exits 1 on any failure.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
SA_UNDER_TEST=$(cd "$(dirname "$SA_UNDER_TEST")" && pwd)/$(basename "$SA_UNDER_TEST")
export SA_UNDER_TEST
echo "sa under test: $SA_UNDER_TEST"

if [ $# -gt 0 ]; then files="$here/$1.test.sh"; else files=$(ls "$here"/*.test.sh); fi
failed=0
for f in $files; do
  [ -f "$f" ] || { echo "FAIL $(basename "$f") (no such test file)"; failed=1; continue; }
  out=$(bash "$f" 2>&1); rc=$?
  printf '%s\n' "$out"
  if [ "$rc" != "0" ] || printf '%s\n' "$out" | grep -q '^FAIL '; then failed=1; fi
done
exit "$failed"
