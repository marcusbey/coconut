#!/usr/bin/env bash
# install.sh: put the coconut setup into Claude Code's folder (~/.claude) and prepare a workspace.
#
#   ./install.sh                       install or update the setup
#   ./install.sh --workspace <dir>     also prepare <dir> as the folder the router runs from
#   ./install.sh --check               run the setup's own tests from this checkout; installs nothing
#   ./install.sh --dry-run [...]       say what would be done; change nothing
#   ./install.sh --no-rtk [...]        leave RTK alone (by default it is installed and switched on for Claude Code)
#
# What it installs:
#   agents/*.md            -> ~/.claude/agents/            the role files (router, worker, tester, decision-room, ...)
#   superagent/            -> ~/.claude/superagent/        sa, PROTOCOL.md, the scripts and their tests
#   skills/write-tickets/  -> ~/.claude/skills/write-tickets/
# RTK (the `rtk` command, https://www.rtk-ai.app/) condenses command output before it reaches a model, which is most
# of what an agent reads. The installer installs it with Homebrew when it is missing (`brew install rtk`), then lets
# RTK's own `rtk init --global --auto-patch` add its hook to ~/.claude/settings.json.
# Every file it replaces is first copied to ~/.claude/backups/coconut-<time>/, so an install can be undone.
# The role files name ~/.claude by path, so the setup always goes there.
set -u

here=$(cd "$(dirname "$0")" && pwd)
target="$HOME/.claude"
workspace=""; dry=0; check=0; rtk=1

die() { echo "install: $*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
run() { if [ "$dry" = 1 ]; then say "would: $*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) [ $# -ge 2 ] || die "--workspace needs a folder"; workspace=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --check) check=1; shift ;;
    --no-rtk) rtk=0; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$1' (see ./install.sh --help)" ;;
  esac
done

# ---- what must be on this machine ------------------------------------------------------------------------------
missing=""
for c in bash git perl python3; do command -v "$c" >/dev/null 2>&1 || missing="$missing $c"; done
[ -z "$missing" ] || die "missing:$missing. Install them and run this again."
perl -MJSON::PP -e 1 2>/dev/null || die "perl has no JSON::PP module (it ships with perl 5.14 and later)"
command -v claude >/dev/null 2>&1 || say "note: 'claude' (Claude Code) is not on PATH; install it before you start the router."
command -v codex >/dev/null 2>&1 || say "note: 'codex' is not on PATH: Claude reviews alone, and the decision room has one seat fewer."
command -v gemini >/dev/null 2>&1 || say "note: 'gemini' is not on PATH: the decision room's Google seat stays out."

if [ "$check" = 1 ]; then
  say "Running the setup's tests from $here (about 10 minutes) ..."
  exec bash "$here/superagent/tests/run.sh"
fi

for d in agents superagent skills/write-tickets; do [ -d "$here/$d" ] || die "this checkout has no $d folder"; done

# ---- install, with a backup of whatever is replaced ----------------------------------------------------------------
stamp=$(date '+%Y%m%d-%H%M%S')
backup="$target/backups/coconut-$stamp"
changed=0; kept=0

put() { # put <source file> <path under ~/.claude>
  local src=$1 rel=$2 dst="$target/$2"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then kept=$((kept + 1)); return 0; fi
  if [ -f "$dst" ]; then
    run mkdir -p "$backup/$(dirname "$rel")"
    run command cp -p "$dst" "$backup/$rel"
  fi
  run mkdir -p "$(dirname "$dst")"
  if [ "$dry" = 1 ]; then say "would: install $rel"; else cat "$src" > "$dst" || die "could not write $dst"; fi
  changed=$((changed + 1))
}

while IFS= read -r f; do put "$here/$f" "$f"; done < <(
  cd "$here" && find agents superagent skills/write-tickets -type f \
    ! -name '.DS_Store' ! -name '*.pyc' ! -path '*/__pycache__/*' | sort)

for x in superagent/sa superagent/seat.sh superagent/watchdog.sh superagent/sweep-timer.sh; do
  [ -f "$target/$x" ] && run chmod +x "$target/$x"
done

say "Setup: $changed file(s) installed or updated, $kept already current, in $target."
[ "$changed" -gt 0 ] && [ -d "$backup" ] && say "Replaced files were saved in $backup."

# ---- RTK: condensed command output for every agent ---------------------------------------------------------------
if [ "$rtk" = 1 ]; then
  if ! command -v rtk >/dev/null 2>&1; then
    if [ "$dry" = 1 ]; then
      say "would: brew install rtk"
    elif command -v brew >/dev/null 2>&1; then
      say "Installing RTK with Homebrew ..."
      brew install rtk >/dev/null 2>&1 || say "note: 'brew install rtk' failed; run it yourself to see why."
    else
      say "note: RTK is not installed and Homebrew is not here to install it. See https://www.rtk-ai.app/ , then run this again."
    fi
  fi
  if ! command -v rtk >/dev/null 2>&1; then
    [ "$dry" = 1 ] || say "note: without RTK agents read command output whole; everything else works."
  elif grep -q 'rtk hook claude' "$target/settings.json" 2>/dev/null; then
    say "RTK is already switched on for Claude Code."
  elif [ "$dry" = 1 ]; then
    say "would: rtk init --global --auto-patch"
  elif rtk init --global --auto-patch >/dev/null 2>&1; then
    say "RTK is switched on for Claude Code (its hook is in $target/settings.json; 'rtk init --global --uninstall' removes it)."
  else
    say "note: 'rtk init --global --auto-patch' failed; run it yourself to see why. The setup works without it."
  fi
fi

# ---- the workspace: the folder the router runs from ----------------------------------------------------------------
if [ -n "$workspace" ]; then
  [ -d "$workspace" ] || die "no such folder: $workspace"
  workspace=$(cd "$workspace" && pwd)
  if [ ! -f "$workspace/ACTIVE-PROJECTS.md" ]; then
    if [ "$dry" = 1 ]; then say "would: write $workspace/ACTIVE-PROJECTS.md"; else
      {
        cat "$here/templates/ACTIVE-PROJECTS.md"
        # every git repository one or two levels down, unticked: you tick the ones the router may work in
        find "$workspace" -mindepth 2 -maxdepth 3 -name .git -not -path '*/node_modules/*' 2>/dev/null | sort |
          while IFS= read -r g; do p=$(dirname "$g"); printf -- '- [ ] %s\n' "${p#"$workspace"/}"; done
      } > "$workspace/ACTIVE-PROJECTS.md"
      say "Wrote $workspace/ACTIVE-PROJECTS.md: tick the projects the router may work in."
    fi
  else
    say "Kept your $workspace/ACTIVE-PROJECTS.md."
  fi
  if [ ! -f "$workspace/ROUTER-PREFS.md" ]; then
    if [ "$dry" = 1 ]; then say "would: write $workspace/ROUTER-PREFS.md"; else
      cat "$here/templates/ROUTER-PREFS.md" > "$workspace/ROUTER-PREFS.md"
      say "Wrote $workspace/ROUTER-PREFS.md: your standing rules go here (the router adds them when you state one)."
    fi
  else
    say "Kept your $workspace/ROUTER-PREFS.md."
  fi
  say ""
  say "Start the router with this alias (add it to your shell profile):"
  say "  alias ccs='cd \"$workspace\" && claude --agent router --name router --permission-mode auto --remote-control router --settings ~/.claude/superagent/router-settings.json'"
  say ""
  say "Optional, keeps the queue and follow-up files current when no router is open (macOS):"
  say "  ~/.claude/superagent/sweep-timer.sh install \"$workspace\""
else
  say "Next: ./install.sh --workspace <the folder that holds your projects>"
fi
