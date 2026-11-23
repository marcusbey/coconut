#!/usr/bin/env bash
# Lists stuck superagent work across every project under a root.
# Usage: watchdog.sh [root] [stale_minutes] [repeat_minutes] [extra-project ...]
#   root: a project repo or a workspace holding several (default: cwd).
#   stale_minutes: a ticket with an agent at work and no activity for this long is stuck (default 20).
#   repeat_minutes: a problem already reported is not reported again for this long (default 60).
#   extra-project: projects to watch although ACTIVE-PROJECTS.md leaves them unticked
#     (the user included them for this session); paths relative to root, or absolute.
# Activity is the newest of: any file in the ticket folder, the last commit in the ticket's
# worktree, and any changed or new file there. Tickets waiting for the user (stages
# approve-plan, approve-merge) and stopped, blocked or finished tickets are never "stuck".
# Prints "PROBLEM: [project] ..." for new problems, "KNOWN: ..." for ones already reported,
# or "OK". Exit 0 always. Read-only except for its own memory file.
set -u
ROOT="${1:-$(pwd)}"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || { echo "OK (no such folder: ${1:-})"; exit 0; }
STALE_MIN="${2:-20}"
REPEAT_MIN="${3:-60}"
now=$(date +%s)
[ $# -gt 3 ] && shift 3 || shift $#
EXTRA=("$@")
STATE_DIR="${SA_STATE_DIR:-$HOME/.superagent/state}"
# one memory file per workspace, so two routers never share or overwrite one
SEEN="$STATE_DIR/watchdog-seen-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
mkdir -p "$STATE_DIR" 2>/dev/null
[ -f "$SEEN" ] || : > "$SEEN"
PROJECT="-"
STATUSES=" draft ready in-progress review merged done blocked failed dropped stopped "

trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

problem() { # problem <key> <message>
  local key="$PROJECT|$1" last
  last=$(SA_K="$key" awk -F'\t' '$2==ENVIRON["SA_K"] {t=$1} END{print t+0}' "$SEEN")
  if [ "$REPEAT_MIN" -gt 0 ] && [ $(( (now - last) / 60 )) -lt "$REPEAT_MIN" ]; then
    echo "KNOWN: [$PROJECT] $2"
  else
    echo "PROBLEM: [$PROJECT] $2"
    printf '%s\t%s\n' "$now" "$key" >> "$SEEN"
  fi
}

boards() {
  # With ACTIVE-PROJECTS.md, only ticked projects ("- [x] <path>") are checked.
  if [ -f "$ROOT/ACTIVE-PROJECTS.md" ]; then
    { sed -n 's/^- \[[xX]\] \([^ ]*\).*/\1/p' "$ROOT/ACTIVE-PROJECTS.md"; [ ${#EXTRA[@]} -gt 0 ] && printf '%s\n' "${EXTRA[@]}"; } | while read -r p; do
      case "$p" in /*) base="$p" ;; *) base="$ROOT/$p" ;; esac
      for d in tickets spec/tickets specs/tickets docs/tickets; do for b in BOARD.md board.md; do
        [ -f "$base/$d/$b" ] && { echo "$base/$d/$b"; break 2; }
      done; done
    done | sort -u
    return
  fi
  find "$ROOT" -maxdepth 5 \( -name node_modules -o -name .git -o -name .claude \) -prune -o \
    -type f \( -name BOARD.md -o -name board.md \) -path '*tickets/*' -print 2>/dev/null
}

newest_in() { # newest mtime of any file under a folder
  find "$1" -type f -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1
}

worktree_activity() { # newest of last commit and changed/new files in one worktree
  local wt="$1" t best
  best=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo 0)
  # changed, new and staged files; not the index file itself, which any "git status" touches
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    t=$(mtime "$wt/$f")
    [ "$t" -gt "$best" ] && best=$t
  done < <( { git -C "$wt" ls-files -m -o --exclude-standard; git -C "$wt" diff --cached --name-only; } 2>/dev/null | sort -u | head -2000)
  echo "${best:-0}"
}

check_board() {
  local board="$1" tickets repo wts
  tickets=$(dirname "$board")
  repo=$(git -C "$tickets" rev-parse --show-toplevel 2>/dev/null) || { PROJECT="$tickets"; problem "not-git" "board not inside a git repo"; return; }
  # the project's path under the workspace names it; two repos may share a folder name
  case "$repo" in "$ROOT"/*) PROJECT=${repo#"$ROOT"/} ;; *) PROJECT=$(basename "$repo") ;; esac
  wts=$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}')

  while IFS='|' read -r _ id slug cell _ _ stage _; do
    id=$(trim "$id"); slug=$(trim "$slug"); cell=$(trim "$cell"); stage=$(trim "$stage")
    status=${cell%%[ :(]*}
    [ -n "$stage" ] || stage="-"
    dir="$tickets/$id-$slug"

    case "$STATUSES" in *" $status "*) ;; *) problem "word:$id" "$id has an unknown status '$status'. Fix: sa stage $dir <stage>"; continue ;; esac
    [ "$cell" = "$status" ] || problem "cell:$id" "$id has free text in its status cell ('$cell'). Fix: sa stage $dir <stage>, and put the reason in notes/questions.md"
    if [ -f "$dir/rd.md" ]; then
      rdst=$(awk '/^## /{exit} /^Status:/{print $2; exit}' "$dir/rd.md")
      [ -z "$rdst" ] || [ "$rdst" = "$status" ] || problem "mismatch:$id" "$id: the board says '$status' but its rd.md says '$rdst'. Fix: sa stage $dir <stage>"
    fi

    want=""
    case "$stage" in
      research|design|plan|plan-review|approve-plan|build|report) want=in-progress ;;
      test|review|approve-merge|merge) want=review ;;
      check) want=merged ;;
      done) want="done" ;;
    esac
    case "$status" in in-progress|review|merged|done)
      if [ -n "$want" ] && [ "$want" != "$status" ]; then
        problem "state:$id" "$id: status '$status' does not fit stage '$stage'. Fix: sa stage $dir <the stage it is really at>"
        continue
      fi ;;
    esac

    active=0
    case "$status" in in-progress|review) active=1 ;; merged) [ "$stage" = "check" ] && active=1 ;; esac
    case "$stage" in approve-plan|approve-merge) active=0 ;; esac
    [ "$active" = "1" ] || continue
    [ -d "$dir" ] || { problem "folder:$id" "$id is $status but its folder $dir is missing"; continue; }

    newest=$(newest_in "$dir"); newest=${newest:-$(mtime "$dir")}
    # The ticket's own worktree is named NNN-slug. A project whose tickets share one linked
    # worktree has none by that name; then any linked worktree's activity counts.
    own=$(echo "$wts" | awk -F/ -v id="$id" '$NF ~ "^" id "-"')
    [ -n "$own" ] || [ -n "$(echo "$wts" | awk -F/ '$NF ~ /^[0-9][0-9][0-9]-/' | head -1)" ] || own=$(echo "$wts" | grep -vxF "$repo")
    while IFS= read -r wt; do
      [ -n "$wt" ] || continue
      t=$(worktree_activity "$wt")
      [ "$t" -gt "$newest" ] && newest=$t
      [ -n "$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)" ] && problem "conflict:$id" "$id: worktree $wt has unresolved merge conflicts"
    done <<< "$own"
    age=$(( (now - newest) / 60 ))
    [ "$age" -ge "$STALE_MIN" ] && problem "stall:$id" "$id ($slug) at stage $stage: no activity for ${age}m (ticket notes, worktree files and commits all unchanged)"
  done < <(grep -E '^\|[[:space:]]*[0-9]{3}[[:space:]]*\|' "$board")

  # Two unfinished tickets waiting on each other.
  grep -E '^\|[[:space:]]*[0-9]{3}[[:space:]]*\|' "$board" | awk -F'|' '
    { id=$2; gsub(/[ \t]/,"",id); s=$4; sub(/^[ \t]+/,"",s); split(s,a,/[ \t:(]/); st[id]=a[1]; runs[id]=$6 }
    END {
      for (x in runs) if (match(runs[x], /after [0-9][0-9][0-9]/)) {
        y=substr(runs[x], RSTART+6, 3)
        if (x < y && (y in runs) && runs[y] ~ ("after " x) && live(st[x]) && live(st[y])) print x, y
      }
    }
    function live(s) { return !(s=="merged" || s=="done" || s=="dropped" || s=="stopped" || s=="failed") }' |
  while read -r a b; do problem "deadlock:$a-$b" "$a and $b wait on each other (deadlock)"; done
}

# forget reports older than a day
awk -F'\t' -v n="$now" 'n - $1 < 86400' "$SEEN" > "$SEEN.$$" 2>/dev/null && command mv -f "$SEEN.$$" "$SEEN"; rm -f "$SEEN.$$"

list=$(boards)
[ -n "$list" ] || { echo "OK (no tickets/BOARD.md under $ROOT)"; exit 0; }

out=$(while read -r b; do check_board "$b"; done <<< "$list")
n=$(echo "$list" | wc -l | xargs)
if echo "$out" | grep -q '^PROBLEM:'; then
  echo "$out"
elif [ -n "$out" ]; then
  echo "OK ($n boards; $(echo "$out" | grep -c '^KNOWN:') known problem(s) already reported, not repeated)"
else
  echo "OK ($n boards)"
fi
exit 0
