#!/usr/bin/env bash
# tier-doc.test.sh: the tier table the router reads (agents/router.md, between the tier-table markers) is the
# table sa applies (`sa run-options --table`), row for row. The hook refuses by sa's table; a router that reads
# another one would be refused without knowing why.
set -u
unset SA_ROLE
here=$(cd "$(dirname "$0")" && pwd)
S=${SA_UNDER_TEST:-$here/../sa}
ROUTER=${AGENTS_DIR:-$here/../../agents}/router.md

doc=$(awk '/<!-- tier-table:start -->/ { f = 1; next } /<!-- tier-table:end -->/ { f = 0 } f' "$ROUTER" | sed 's/^  //')
tab=$(bash "$S" run-options --table 2>&1)

if [ -n "$doc" ] && [ "$doc" = "$tab" ]; then
  echo "ok the router's tier table is sa's tier table"
else
  echo "FAIL the router's tier table is sa's tier table"
  diff <(printf '%s\n' "$tab") <(printf '%s\n' "$doc") | sed 's/^/    /' | head -20
fi

rows=$(printf '%s\n' "$tab" | grep -c '^| ')
if [ "$rows" -ge 10 ]; then echo "ok the table has its rows ($rows lines)"; else echo "FAIL the table has its rows ($rows lines)"; fi
