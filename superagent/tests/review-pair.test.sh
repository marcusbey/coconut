#!/bin/bash
# review_pair: the gate needs both Codex and Claude to allow the same commit in the newest round
D=$(mktemp -d); trap "rm -rf $D" EXIT
cd "$D"; eval "$(sed -n '/^review_pair()/,/^}/p' "$(dirname "$0")/../sa")"; A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; F=0
chk(){ r=$(review_pair "$2"); if { [ "$1" = pass ] && [ -z "$r" ]; } || { [ "$1" = fail ] && [ -n "$r" ]; }; then echo "ok $3"; else F=1; echo "FAIL $3 :: $r"; fi; }
printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\n' $A > solo; chk fail solo "codex alone blocked"
printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\nSecond review, reviewer: claude (claude-fable-5-2)\nReviewed commit: %s\nShip allowed: no\n' $A $A > cno; chk fail cno "claude no blocks"
printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: no\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A $A > xno; chk fail xno "codex no + claude yes last blocks"
printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A $B > diff; chk fail diff "different commits block"
printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: no\n--- Round 2, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A $B $B > both; chk pass both "both yes, old round ignored"
printf -- '--- Round 1, d, reviewer: claude (claude-fable-5-2; codex unavailable: usage limit)\nReviewed commit: %s\nShip allowed: yes\n' $A > cu; chk pass cu "claude alone when codex unavailable"
# superagent#004: an override block after the newest round decides, under both headers (decision room D1)
chkr(){ r=$(review_pair "$1"); case "$r" in *"$2"*) echo "ok $3";; *) F=1; echo "FAIL $3 :: $r";; esac; }
R3(){ printf -- '--- Round 3, d, reviewer: codex (gpt-6-astra)\nReviewed commit: %s\nMax severity: major\nShip allowed: no\n' "$1"; }
OV(){ printf -- "--- $1 override, d\nThey chose to merge despite the remaining defects\nReviewed commit: $2\nMax severity: major\n$3"; }
N1=1000000000000000000000000000000000000001; N0=1000000000000000000000000000000000000000
for H in User "Decision room"; do
  p=${H%% *}; mkdir "$p"; cd "$p"
  { R3 $A; OV "$H" $A 'Ship allowed: yes\n'; } > e1; chk pass e1 "$H override after a codex-only no round"
  { R3 $A; printf 'Second review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: no\n' $A; OV "$H" $A 'Ship allowed: yes\n'; } > e2; chk pass e2 "$H override after both said no"
  { printf -- '--- Round 3, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: no\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A $A; OV "$H" $A 'Ship allowed: yes\n'; } > cnoy; chk pass cnoy "$H override after codex no, claude yes"
  { printf -- '--- Round 3, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: no\n' $A $A; OV "$H" $A 'Ship allowed: yes\n'; } > cyesn; chk pass cyesn "$H override after codex yes, claude no"
  { R3 $A; OV "$H" $A 'Ship allowed: yes \r\n'; } > vcr; chk pass vcr "$H override verdict yes with trailing space and CR"
  { R3 $A; OV "$H" $A 'Ship allowed: yes\n'; printf 'An explanatory note.\n'; } > prose; chk pass prose "$H plain text after the override"
  { R3 $A; OV "$H" $B 'Ship allowed: yes\n'; } > x1; chk fail x1 "$H override names another commit"
  { R3 $A; OV "$H" $A 'Ship allowed: yes\n'; printf -- '--- Round 4, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: no\n' $A; } > x2; chk fail x2 "$H a later round makes the override stale"
  OV "$H" $A 'Ship allowed: yes\n' > x3; chk fail x3 "$H override with no round before it"
  { R3 $A; OV "$H" $A 'Ship allowed: no\n'; } > x4a; chk fail x4a "$H override says no"
  { R3 $A; OV "$H" $A ''; } > x4b; chk fail x4b "$H override without a verdict"
  { R3 $A; OV "$H" aaaaaaa 'Ship allowed: yes\n'; } > x5a; chk fail x5a "$H override with a short id"
  { R3 $A; OV "$H" HEAD 'Ship allowed: yes\n'; } > x5b; chk fail x5b "$H override with HEAD"
  { R3 $A; printf -- "--- $H override, d\nquoted\nMax severity: major\nShip allowed: yes\n"; } > nocommit; chk fail nocommit "$H override without a Reviewed commit line"
  { R3 $A; OV "$H" '' 'Ship allowed: yes\n'; } > emptyov; chk fail emptyov "$H override with an empty commit"
  { printf -- '--- Round 3, d, reviewer: codex (x)\nReviewed commit:\nShip allowed: no\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: no\n' $A; OV "$H" $A 'Ship allowed: yes\n'; } > emptyround; chk fail emptyround "$H round with an empty commit, then A"
  { R3 $N1; OV "$H" $N0 'Ship allowed: yes\n'; } > numeric; chk fail numeric "$H numeric-looking ids compared as strings"
  { R3 $A; printf -- "--- $H override, d\nquoted\nReviewed commit: %s\nReviewed commit: %s\nShip allowed: yes\n" $B $A; } > ba; chk fail ba "$H override naming B then A"
  { R3 $A; OV "$H" $A 'Ship allowed: Yes\n'; } > vYes; chk fail vYes "$H override verdict Yes"
  { R3 $A; OV "$H" $A 'Ship allowed: YES\n'; } > vYES; chk fail vYES "$H override verdict YES"
  { R3 $A; printf -- "--- $H overrides are fun\nReviewed commit: %s\nShip allowed: yes\n" $A; } > unanch; chk fail unanch "$H header not anchored"
  { R3 $A; OV "$H" $A 'Ship allowed: yes\n'; printf 'Second review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A; } > after; chk fail after "$H second review after the override"
  { R3 $A; OV "$H" $A 'Ship allowed: no\n'; printf 'Reviewed commit: %s\nShip allowed: yes\n' $A; } > afterv; chk fail afterv "$H verdict lines after the override"
  { R3 $A; printf -- '```\n'; R3 $A; OV "$H" $A 'Ship allowed: yes\n'; printf -- '```\n'; } > fround; chkr fround "does not name both reviewers" "$H fenced quote of a round plus override keeps the round's reason"
  { printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\n~~~\n--- %s override, <date>\n~~~\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A "$H" $A; } > tilde; chk fail tilde "$H header in a ~~~ fence counts as a header and refuses"
  { printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\n```\n--- %s override, <date>\n```\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A "$H" $A; } > p1; chk pass p1 "$H header quoted in a fence, both yes"
  { printf -- '--- Round 1, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: no\nSecond review, reviewer: claude (f)\n```\n--- %s override, <date>\n```\nReviewed commit: %s\nShip allowed: yes\n' $A "$H" $A; } > p3; chk fail p3 "$H header quoted in a fence, codex no"
  { R3 $A; OV "$H" "$A $B" 'Ship allowed: yes\n'; } > twoids; chk fail twoids "$H override commit field with trailing text"
  { printf -- '--- Round 3, d, reviewer: codex (x)\nReviewed commit: %s (see above)\nShip allowed: no\n' $A; OV "$H" $A 'Ship allowed: yes\n'; } > rtrail; chk fail rtrail "$H round commit field with trailing text"
  { R3 $A; OV "$H" $A 'Ship allowed: yes\n'; printf -- '--- Round 4, d, reviewer: codex (x)\nSecond review, reviewer: claude (f)\n'; } > bare4; chk fail bare4 "$H a later round without its own commit and verdict"
  { R3 $A; OV "$H" $A 'Ship allowed: yes\n'; printf -- '--- Round 4, d, reviewer: codex (x)\nReviewed commit: %s\nShip allowed: yes\nSecond review, reviewer: claude (f)\nReviewed commit: %s\nShip allowed: yes\n' $A $A; } > yes4; chk pass yes4 "$H a later dual-yes round decides"
  cd "$D"
done
exit $F
