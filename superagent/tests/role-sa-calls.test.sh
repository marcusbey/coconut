#!/usr/bin/env bash
# role-sa-calls.test.sh: every `sa` call that one of the twelve superagent role files shows is written in full as
# `SA_ROLE=<role> ~/.claude/superagent/sa <subcommand> ...`, so that no line an agent writes to a room log or to
# tickets/LOG.md carries the unknown badge (superagent#010, FR-8). A call is `sa <subcommand> <argument>` (or with the
# path `~/.claude/superagent/`) standing where a command can: first in a code span or in a line of a code block, or
# after `&&`, `||`, `;`, `|` or `$(`. A bare `sa stage` with no argument, used as a name in prose, and text that quotes
# a tool's own output (`Fix: sa stage <dir> ...`) are not calls. The role is the file's own; ticket-writer.md may use
# ticket-writer or clerk, and router.md any role of the badge table (the one the shown call is for).
# AGENTS_DIR names another folder holding the twelve files, e.g. main's, to see this test fail on them.
set -u
unset SA_ROLE
here=$(cd "$(dirname "$0")" && pwd)
SA_UNDER_TEST=${SA_UNDER_TEST:-$here/../sa}
S=$SA_UNDER_TEST
AGENTS=${AGENTS_DIR:-$here/../../agents}
ROLE_FILES='router ticket-writer worker teammate reproducer tester codex-reviewer merger checker watchdog decision-room follow-up'
TABLE_ROLES='router|decision-room|clerk|ticket-writer|worker|teammate|reproducer|tester|reviewer|codex-reviewer|merger|checker|watchdog|follow-up|user|owner'

W=""; D=""
fail() { echo "$*"; exit 1; }
sa() { bash "$S" "$@"; }
drop_dir() {
  case "${1:-}" in */sa-fixture.*) [ -d "$1" ] && { chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; } ;; esac
  return 0
}
run_case() { # run_case <name> <function>
  local rc
  W=$(bash "$here/fixture.sh") || { echo "FAIL $1 (no fixture)"; return; }
  D=$(dirname "$W")
  ( "$2" ) > "$D/case.out" 2>&1; rc=$?
  if [ "$rc" = "0" ]; then echo "ok $1"; else echo "FAIL $1"; sed 's/^/    /' "$D/case.out"; fi
  drop_dir "$D"
}

# scan_file <file> <name> <allowed roles, as a regex alternation>: one "<name>:<line>: <call>" per call without its role
scan_file() {
  perl -e '
    my ($path, $name, $allowed) = @ARGV;
    my $sub = qr/(?:stage|ask|answer|suggest-close|suggest|learn|qa-pass|qa|fresh|dirty|selfcheck|gate|land|room)/;
    open(my $fh, "<", $path) or do { print "$name: cannot read $path\n"; exit 0 };
    my ($n, $fence) = (0, 0);
    while (my $line = <$fh>) {
      chomp $line; $n++;
      if ($line =~ /^\s*```/) { $fence = !$fence; next }
      my @code = $fence ? ($line) : do { my @p = split /`/, $line, -1; map { $p[$_] } grep { $_ % 2 } 0 .. $#p };
      for my $c (@code) {
        while ($c =~ /(?:^|&&|\|\||;|\||\$\()\s*((?:SA_ROLE=\S+\s+)?(?:~\/\.claude\/superagent\/)?sa)\s+($sub)\s+(\S.*)/g) {
          my ($head, $s, $rest) = ($1, $2, $3);
          next if $head =~ m{^SA_ROLE=(?:$allowed) ~/\.claude/superagent/sa$};
          printf "%s:%d: %s %s %s\n", $name, $n, $head, $s, substr($rest, 0, 60);
        }
      }
    }' "$1" "$2" "$3"
}
offenders() { # offenders <dir>: the calls of the twelve files that are not written in full
  local f allowed
  for f in $ROLE_FILES; do
    case "$f" in
      router) allowed=$TABLE_ROLES ;;
      ticket-writer) allowed='ticket-writer|clerk' ;;
      *) allowed=$f ;;
    esac
    scan_file "$1/$f.md" "$f.md" "$allowed"
  done
}

# --- the scanner itself: it must be able to fail --------------------------------------------------------------------

c_scanner_bites() {
  local f="$D/sample.md" out
  scan() { scan_file "$f" sample.md "${1:-merger}"; }
  line() { printf '%s\n' "$1" > "$f"; }
  for c in '`sa stage <ticket-dir> done "x"`' \
           '`~/.claude/superagent/sa stage <ticket-dir> done "x"`' \
           '`SA_ROLE=merger sa stage <ticket-dir> done "x"`' \
           '`SA_ROLE=worker ~/.claude/superagent/sa stage <ticket-dir> done "x"`' \
           'then `cd <worktree> && sa fresh <worktree> <base>` and so on' \
           'a pipe `echo x | sa learn <tickets> <from> "x"`' \
           'a substitution `$(sa room status <workspace>)`' \
           '`sa ask --access`' \
           '`sa room decide`' \
           '    sa land <ticket-dir> <worktree> <base>'; do
    case "$c" in '    '*) printf '%s\n' '```' "$c" '```' > "$f" ;; *) line "$c" ;; esac
    [ -n "$(scan)" ] || fail "the scanner lets this call through: $c"
  done
  for c in '`SA_ROLE=merger ~/.claude/superagent/sa stage <ticket-dir> done "x"`' \
           '`cd <worktree> && SA_ROLE=merger ~/.claude/superagent/sa fresh <worktree> <base>`' \
           '`sa stage` and `sa ask`, `sa land` are names' \
           'the script prints `Fix: sa stage <dir> ...`' \
           '`SA_ROLE=merger ~/.claude/superagent/sa` (`sa` below)' \
           '`SA_ROLE=<your role> ~/.claude/superagent/sa ...`' \
           'Prose with sa stage <ticket-dir> done and no code span' \
           '`git -C <repo> worktree add <path>`'; do
    line "$c"
    out=$(scan); [ -z "$out" ] || fail "the scanner flags what is not a call: $c -> $out"
  done
  printf '%s\n' '```' 'SA_ROLE=merger ~/.claude/superagent/sa land <ticket-dir> <worktree> <base>' '```' > "$f"
  [ -z "$(scan)" ] || fail "a call in full in a code block is flagged: $(scan)"
  line '`SA_ROLE=clerk ~/.claude/superagent/sa room note <ticket-dir> clerk "x"`'
  [ -z "$(scan 'ticket-writer|clerk')" ] || fail "the clerk is refused in ticket-writer.md"
  [ -n "$(scan merger)" ] || fail "the clerk is accepted in merger.md"
  out=$(scan); case "$out" in 'sample.md:1: '*) ;; *) fail "the finding does not name the file and the line: $out" ;; esac
}

# --- the role files ---------------------------------------------------------------------------------------------------

c_role_files() {
  local out f
  for f in $ROLE_FILES; do [ -f "$AGENTS/$f.md" ] || fail "no $AGENTS/$f.md"; done
  out=$(offenders "$AGENTS")
  [ -z "$out" ] || fail "calls without SA_ROLE=<role> ~/.claude/superagent/sa:
$out"
}

# --- E-13: the merger's own calls, run as agents/merger.md shows them, give lines with the merger's badge ----------------

c_e13_merger_lines() {
  local T="$W/demo/tickets/001-demo-ticket" LOG="$W/decision-room/demo/LOG.md" cmds cmd n
  cmds=$(perl -e '
    my ($file, $sa, $ticket) = @ARGV;
    open(my $fh, "<", $file) or die "$file: $!";
    while (my $line = <$fh>) {
      my @p = split /`/, $line, -1;
      for my $i (grep { $_ % 2 } 0 .. $#p) {
        my $c = $p[$i];
        next unless $c =~ m{^((?:SA_ROLE=\S+ )?)(?:~/\.claude/superagent/)?sa (qa <ticket-dir> |stage <ticket-dir> done )(.*)$};
        my ($env, $what, $rest) = ($1, $2, $3);
        $what =~ s/<ticket-dir>/$ticket/;
        print "$env" . "bash \"$sa\" $what$rest\n";
      }
    }' "$AGENTS/merger.md" "$S" "$T")
  n=$(printf '%s\n' "$cmds" | grep -c .)
  [ "$n" -ge 2 ] || fail "agents/merger.md shows $n 'sa qa <ticket-dir>' or 'sa stage <ticket-dir> done' calls, want at least 2"
  while IFS= read -r cmd; do
    out=$(eval "$cmd" 2>&1) || fail "the call as the merger file shows it fails: $cmd -> $out"
  done <<< "$cmds"
  [ "$(grep -vc '^# ' "$LOG")" = "$n" ] || fail "want $n lines in the room log, got: $(cat "$LOG")"
  grep -v '^# ' "$LOG" | grep -qv '^🔀 ' && fail "a line of the merger's calls does not start with the merger's badge: $(grep -v '^# ' "$LOG" | grep -v '^🔀 ' | head -2)"
  return 0
}

run_case "the scanner finds a call without its role and passes a call in full" c_scanner_bites
run_case "every sa call of the twelve role files is written SA_ROLE=<role> ~/.claude/superagent/sa ..." c_role_files
run_case "E-13 the merger's qa and stage calls, as its file shows them, log lines with its badge" c_e13_merger_lines
