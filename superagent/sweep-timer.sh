#!/bin/bash
# sweep-timer.sh: a macOS launchd user agent, com.superagent.sweep, that every N minutes writes the two
# follow-up reports of a workspace: `sa sweep <workspace> --write` and `sa queue <workspace> --write`.
#   sweep-timer.sh install <workspace> [minutes]   write ~/Library/LaunchAgents/com.superagent.sweep.plist and load it (default 10)
#   sweep-timer.sh remove                          unload it and delete the plist
#   sweep-timer.sh status                          is it installed, is it loaded
#   sweep-timer.sh print <workspace> [minutes]     the plist on stdout; touches nothing
# Output goes to ~/.superagent/sweep.log.
set -u
LABEL=com.superagent.sweep
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SA="$(cd "$(dirname "$0")" && pwd)/sa"
DOMAIN="gui/$(id -u)"

die() { echo "refused: $*" >&2; exit 1; }
xml() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

plist() { # plist <workspace> <minutes>
  local ws minutes="${2:-10}"
  ws=$(cd "$1" 2>/dev/null && pwd -P) || die "no such folder: $1"
  case "$minutes" in ''|*[!0-9]*|0) die "minutes must be a whole number above 0" ;; esac
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>"\$0" sweep "\$1" --write; "\$0" queue "\$1" --write</string>
    <string>$(xml "$SA")</string>
    <string>$(xml "$ws")</string>
  </array>
  <key>StartInterval</key><integer>$((minutes * 60))</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$(xml "$HOME/.superagent/sweep.log")</string>
  <key>StandardErrorPath</key><string>$(xml "$HOME/.superagent/sweep.log")</string>
</dict>
</plist>
PLIST
}

case "${1:-}" in
  print)
    [ $# -ge 2 ] || die "usage: sweep-timer.sh print <workspace> [minutes]"
    plist "$2" "${3:-10}" ;;
  install)
    [ $# -ge 2 ] || die "usage: sweep-timer.sh install <workspace> [minutes]"
    body=$(plist "$2" "${3:-10}") || exit 1
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.superagent"
    printf '%s\n' "$body" > "$PLIST"
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
    launchctl bootstrap "$DOMAIN" "$PLIST" || die "launchctl could not load $PLIST"
    echo "installed: $PLIST (every ${3:-10} min)" ;;
  remove)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
    rm -f "$PLIST"
    echo "removed" ;;
  status)
    [ -f "$PLIST" ] && echo "plist: $PLIST" || echo "plist: none"
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 && echo "loaded: yes" || echo "loaded: no" ;;
  *) die "usage: sweep-timer.sh install <workspace> [minutes] | remove | status | print <workspace> [minutes]" ;;
esac
