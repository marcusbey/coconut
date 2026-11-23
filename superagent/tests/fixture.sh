#!/usr/bin/env bash
# fixture.sh: build a throwaway workspace in a new temp folder and print its path.
#   <tmp>/ws/ACTIVE-PROJECTS.md ticks demo and group/app, leaves off unticked
#   <tmp>/ws/{demo,group/app,off} and <tmp>/outside: git repos with a one-ticket tickets folder
# Refuses to build anything under a folder that holds ACTIVE-PROJECTS.md (a real workspace).
set -u

D=$(mktemp -d "${TMPDIR:-/tmp}/sa-fixture.XXXXXX") || { echo "fixture: mktemp failed" >&2; exit 1; }
D=$(cd "$D" && pwd)
p=$(dirname "$D")
while :; do
  if [ -f "$p/ACTIVE-PROJECTS.md" ]; then echo "fixture: refused, $p holds ACTIVE-PROJECTS.md" >&2; rmdir "$D"; exit 1; fi
  [ "$p" = "/" ] && break
  p=$(dirname "$p")
done

project() { # project <folder> <name>
  local r="$1" t="$1/tickets"
  mkdir -p "$t/001-demo-ticket"
  printf '# Project: %s\n\nBase branch: main\n' "$2" > "$t/PROJECT.md"
  printf '# Board\n\n| ID | Ticket | Status | Mode | Runs | Stage |\n|----|--------|--------|------|------|-------|\n| 001 | demo-ticket | ready | solo | alongside | - |\n' > "$t/BOARD.md"
  printf '# 001: Demo ticket\n\nStatus: ready\nKind: ship\nTrack: full\nStage: -\n\n## Goal\nA fixture ticket.\n\n## Open questions\n- None.\n' > "$t/001-demo-ticket/rd.md"
  printf '# 001: Demo ticket: Evaluation\n\n## Automated checks\n- none\n' > "$t/001-demo-ticket/eval.md"
  git init -q -b main "$r" &&
    git -C "$r" config user.name fixture &&
    git -C "$r" config user.email fixture@example.invalid &&
    git -C "$r" config commit.gpgsign false &&
    git -C "$r" add -A && git -C "$r" commit -q -m "fixture" || { echo "fixture: git failed in $r" >&2; exit 1; }
}

W="$D/ws"
mkdir -p "$W"
printf '# Active projects\n\n- [x] demo  <!-- fixture -->\n- [x] group/app  <!-- fixture -->\n- [ ] off  <!-- fixture -->\n' > "$W/ACTIVE-PROJECTS.md"
project "$W/demo" demo
project "$W/group/app" app
project "$W/off" off
project "$D/outside" outside
echo "$W"
