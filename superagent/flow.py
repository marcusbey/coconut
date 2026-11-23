#!/usr/bin/env python3
"""flow.py queue|sweep <workspace> [options]: two read-only reports over every ticked project's board.

queue  one computed start list (what to start next, what waits for a decision, what cannot start, drafts).
sweep  follow-up findings (disk, stalled, parked, unchecked, startable, paused, drafts, blocked, cleanup, watchdog),
       each with a stable key and a first-seen time kept in <workspace>/decision-room/.followup-state.json.
Both print; with --write they also write decision-room/QUEUE.md or FOLLOWUP.md (temp file, then os.replace).
Tests set SA_NOW (YYYY-MM-DD HH:MM) for "now", SA_WORKTREES for the worktrees root and SA_DISK_FREE_GB for the free space.
Format details: PROTOCOL.md sections 1 to 3.
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

BOARDS = ("tickets", "spec/tickets", "specs/tickets", "docs/tickets")
FINISHED = ("merged", "done", "dropped", "stopped", "failed")
LIVE = ("in-progress", "review")
WORKING_STAGES = ("research", "design", "plan", "build", "report", "test", "review", "merge", "check")
WAITING_STAGES = ("plan-review", "approve-plan", "approve-merge")
STAMP = "%Y-%m-%d %H:%M"
ROOM_LINE = re.compile(r"^(?:\S+ )?(\d{4}-\d\d-\d\d \d\d:\d\d) \| .*?#(\d{3}) \| (\w+) \|")
TICKETS_LINE = re.compile(r"^(?:\S+ )?(\d{4}-\d\d-\d\d \d\d:\d\d) \| (\d{3}) \|")


def now_dt():
    text = os.environ.get("SA_NOW")
    return datetime.datetime.strptime(text, STAMP) if text else datetime.datetime.now().replace(second=0, microsecond=0)


def fmt_wait(seconds):
    seconds = max(0, int(seconds))
    return "waiting %dd %dh" % (seconds // 86400, seconds % 86400 // 3600)


def read(path):
    try:
        with open(path, errors="ignore") as handle:
            return handle.read()
    except OSError:
        return ""


def write_atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as handle:
        handle.write(text)
    os.replace(tmp, path)


def git(*args):
    try:
        done = subprocess.run(("git", "--no-optional-locks") + args, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return 1, ""
    return done.returncode, done.stdout


# ---------------------------------------------------------------- reading the workspace

def repo_id(path):
    """The repository a folder belongs to (the same for every working copy of it), or None outside git."""
    code, out = git("-C", path, "rev-parse", "--git-common-dir")
    return os.path.realpath(os.path.join(path, out.strip())) if code == 0 and out.strip() else None


def projects(ws):
    """[(path as ticked, active)] from ACTIVE-PROJECTS.md, then every other folder one or two levels down that
    has a board, as not active: a project the owner started by word and never listed still leaves finished
    working copies and waiting tickets behind."""
    found = []
    for line in read(os.path.join(ws, "ACTIVE-PROJECTS.md")).splitlines():
        m = re.match(r"^- \[([ xX])\] (\S+)", line)
        if m:
            found.append((m.group(2).rstrip("/") or ".", m.group(1) != " "))
    listed = [p if os.path.isabs(p) else os.path.join(ws, p) for p, _ in found]
    boards = {os.path.realpath(b) for b in map(find_board, listed) if b}
    repos = {r for r in map(repo_id, listed) if r}
    for base in sorted(glob.glob(os.path.join(ws, "*", "")) + glob.glob(os.path.join(ws, "*", "*", ""))):
        rel = os.path.relpath(base, ws)
        board = None if any(part.startswith(".") for part in rel.split(os.sep)) else find_board(base)
        # not a second project: a listed project's docs/tickets, a second board in one repository, a working copy
        if not board or os.path.realpath(board) in boards or repo_id(base) in repos:
            continue
        boards.add(os.path.realpath(board))
        repos.add(repo_id(base) or base)
        found.append((rel, False))
    return found


def find_board(base):
    for rel in BOARDS:
        for name in ("BOARD.md", "board.md"):
            path = os.path.join(base, rel, name)
            if os.path.isfile(path):
                return path
    return None


def room_log(ws, project):
    return os.path.join(ws, "decision-room", "LOG.md" if project == "." else os.path.join(project, "LOG.md"))


def parse_stamp(text):
    return datetime.datetime.strptime(text, STAMP)


def log_times(ws, project, tickets_dir):
    """({id: time of last stage line}, {id: newest time of any log line}) from the room log and tickets/LOG.md."""
    stage, newest = {}, {}
    for line in read(room_log(ws, project)).splitlines():
        m = ROOM_LINE.match(line)
        if not m:
            continue
        t, tid, kind = parse_stamp(m.group(1)), m.group(2), m.group(3)
        if kind == "stage" and t > stage.get(tid, datetime.datetime.min):
            stage[tid] = t
        if t > newest.get(tid, datetime.datetime.min):
            newest[tid] = t
    for line in read(os.path.join(tickets_dir, "LOG.md")).splitlines():
        m = TICKETS_LINE.match(line)
        if m and parse_stamp(m.group(1)) > newest.get(m.group(2), datetime.datetime.min):
            newest[m.group(2)] = parse_stamp(m.group(1))
    return stage, newest


def rd_header(path):
    head = {}
    for line in read(path).splitlines():
        if line.startswith("## "):
            break
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m:
            head.setdefault(m.group(1), m.group(2).strip())
    return head


def load(ws):
    """Every project with its tickets. A ticket: id slug cell status stage deps dir since priority."""
    out = []
    for path, active in projects(ws):
        base = path if os.path.isabs(path) else os.path.join(ws, path)
        board = find_board(base)
        if not board:
            continue
        tdir = os.path.dirname(board)
        stage_t, any_t = log_times(ws, path, tdir)
        tickets = {}
        for line in read(board).splitlines():
            if not re.match(r"^\|\s*\d{3}\s*\|", line):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) < 6:
                continue
            tid, slug, cell, runs, stage = cells[0], cells[1], cells[2], cells[4], cells[5]
            status = (re.match(r"[A-Za-z-]*", cell).group(0) or "?").lower()
            tdir_t = os.path.join(tdir, "%s-%s" % (tid, slug))
            rd = os.path.join(tdir_t, "rd.md")
            since = stage_t.get(tid) or any_t.get(tid)
            if since is None:
                try:
                    since = datetime.datetime.fromtimestamp(os.path.getmtime(rd))
                except OSError:
                    since = now_dt()
            head = runs.split("(")[0]
            tickets[tid] = {
                "id": tid, "slug": slug, "cell": cell, "status": status, "stage": stage or "-",
                "deps": [] if head.strip().startswith("alongside") else re.findall(r"\b\d{3}\b", head),
                "dir": tdir_t, "since": since, "priority": rd_header(rd).get("Priority", "").lower(),
                "last_log": any_t.get(tid),
            }
        out.append({"path": path, "base": base, "active": active, "tdir": tdir, "tickets": tickets})
    return out


def analyse(project):
    """Adds unmet, startable and dependents to each ticket of one project."""
    ts = project["tickets"]
    unfinished = [t for t in ts.values() if t["status"] not in FINISHED]

    def ancestors(tid, seen):
        for d in ts[tid]["deps"]:
            if d in ts and d not in seen:
                seen.add(d)
                ancestors(d, seen)
        return seen

    count = {tid: 0 for tid in ts}
    for t in unfinished:
        for a in ancestors(t["id"], set()):
            if a != t["id"]:
                count[a] += 1
    for t in ts.values():
        t["unmet"] = [d for d in t["deps"] if d not in ts or ts[d]["status"] not in ("merged", "done")]
        t["dependents"] = count[t["id"]]
        t["startable"] = project["active"] and t["cell"] == "ready" and not t["unmet"]


def ref(project, t):
    return "%s#%s" % (project["path"], t["id"])


# ---------------------------------------------------------------- queue

def build_queue(ws, now, age_days):
    plist = load(ws)
    for p in plist:
        analyse(p)
    age = datetime.timedelta(days=age_days)
    wait = lambda t: (now - t["since"]).total_seconds()
    merge, review, ready, decide, blocked, not_startable, drafts = [], [], [], [], [], [], []
    for p in plist:
        oldest = None
        n_drafts = 0
        for t in p["tickets"].values():
            line = lambda reason: "%s %s | %s | %s | %s" % (ref(p, t), t["slug"], t["stage"] if t["stage"] != "-" else t["status"], reason, fmt_wait(wait(t)))
            if t["status"] == "draft":
                n_drafts += 1
                oldest = t["since"] if oldest is None or t["since"] < oldest else oldest
            if t["status"] == "ready" or t["cell"].startswith("ready"):
                if t["startable"]:
                    aged = now - t["since"] > age
                    why = ["ready"] + (["high priority"] if t["priority"] == "high" else []) + (["waited over %g days" % age_days] if aged else []) + (["unblocks %d" % t["dependents"]] if t["dependents"] else [])
                    key = (t["priority"] != "high", not aged, -t["dependents"], t["since"], ref(p, t))
                    ready.append((key, line(", ".join(why))))
                else:
                    if not p["active"]:
                        why = "paused project"
                    elif t["cell"] != "ready":
                        why = 'status says "%s"' % t["cell"]
                    else:
                        why = "waits on " + ", ".join("#%s%s" % (d, "" if d in p["tickets"] else " (no such ticket)") for d in t["unmet"])
                    not_startable.append((t["since"], ref(p, t), line(why)))
                continue
            if not p["active"]:
                continue
            if t["status"] in LIVE and t["stage"] == "merge":
                merge.append((t["since"], ref(p, t), line("landing")))
            elif t["status"] in LIVE and t["stage"] in ("test", "review"):
                review.append((t["since"], ref(p, t), line("%s next" % t["stage"])))
            elif t["status"] in LIVE and t["stage"] in WAITING_STAGES:
                decide.append((t["since"], ref(p, t), line("waiting for " + t["stage"])))
            elif t["status"] == "blocked":
                blocked.append((t["since"], ref(p, t), line("blocked: " + t["cell"])))
        if n_drafts:
            drafts.append("- %s | %d draft(s) | oldest %s" % (p["path"], n_drafts, fmt_wait(wait({"since": oldest})).replace("waiting ", "")))
    body = lambda rows: [r[-1] for r in sorted(rows, key=lambda r: r[:-1])] or ["(none)"]
    out = ["# Queue, built %s" % now.strftime(STAMP), "", "## Start next"]
    out += [r[-1] for r in sorted(merge, key=lambda r: r[:-1])] + [r[-1] for r in sorted(review, key=lambda r: r[:-1])]
    out += [r[1] for r in sorted(ready, key=lambda r: r[0])]
    if not (merge or review or ready):
        out.append("(none)")
    out += ["", "## Waiting for a decision"] + body(decide + blocked)
    out += ["", "## Not startable"] + body(not_startable)
    out += ["", "## Drafts"] + (drafts or ["(none)"])
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- sweep

def worktrees(project, repo):
    found = []
    code, text = git("-C", repo, "worktree", "list", "--porcelain")
    if code == 0:
        found += [l[9:] for l in text.splitlines() if l.startswith("worktree ")]
    root = os.environ.get("SA_WORKTREES") or os.path.expanduser("~/.superagent/worktrees")
    found += glob.glob(os.path.join(root, os.path.basename(project["path"]), "[0-9][0-9][0-9]-*"))
    seen, uniq = set(), []
    for w in found:
        real = os.path.realpath(w)
        if real not in seen and real != os.path.realpath(repo) and os.path.isdir(w):
            seen.add(real)
            uniq.append(w)
    return uniq


def own_worktrees(wts, tid, fallback):
    own = [w for w in wts if os.path.basename(w).startswith(tid + "-")]
    if not own and fallback and not any(re.match(r"\d{3}-", os.path.basename(w)) for w in wts):
        own = list(wts)
    return own


def worktree_activity(wt):
    best = 0
    code, text = git("-C", wt, "log", "-1", "--format=%ct")
    if code == 0 and text.strip().isdigit():
        best = int(text.strip())
    names = set()
    for args in (("ls-files", "-m", "-o", "--exclude-standard"), ("diff", "--cached", "--name-only")):
        names.update(git("-C", wt, *args)[1].splitlines())
    for name in sorted(names)[:2000]:
        try:
            best = max(best, int(os.path.getmtime(os.path.join(wt, name))))
        except OSError:
            pass
    return best


def folder_activity(path):
    best = 0
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules")]
        for f in files:
            full = os.path.join(root, f)
            if os.path.relpath(full, path) == os.path.join("notes", "digest.md"):
                continue
            try:
                best = max(best, int(os.path.getmtime(full)))
            except OSError:
                pass
    return best


def base_branch(tdir):
    m = re.search(r"^Base branch:\s*(\S+)", read(os.path.join(tdir, "PROJECT.md")), re.M)
    return m.group(1) if m else "main"


def cleanup_reason(repo, wt, base):
    code, branch = git("-C", wt, "rev-parse", "--abbrev-ref", "HEAD")
    branch = branch.strip()
    if code != 0 or branch in ("", "HEAD"):
        return "not removable: detached or unreadable HEAD"
    code, merged = git("-C", repo, "branch", "--merged", base, "--format=%(refname:short)")
    if code != 0:
        return "not removable: base branch %s not found" % base
    problems = []
    if branch not in merged.splitlines():
        problems.append("branch %s not merged into %s" % (branch, base))
    if git("-C", wt, "status", "--porcelain")[1].strip():
        problems.append("uncommitted changes")
    return "merged and clean" if not problems else "not removable: " + ", ".join(problems)


def disk_findings(ws, limit_gb):
    # a full disk stops every agent at once; what fills it is the agents' own memory overflow and working copies
    try:
        free = float(os.environ.get("SA_DISK_FREE_GB") or shutil.disk_usage(ws).free / 2 ** 30)
    except (OSError, ValueError):
        return []
    if not free < limit_gb:  # also a value that is not a number
        return []
    return [("disk", "machine", "%d GB free, under the limit of %g GB" % (free, limit_gb), "")]


def watchdog_findings(ws):
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "watchdog.sh")
    state = tempfile.mkdtemp(prefix="flow-watchdog.")  # its own memory file, never the live one
    try:
        env = dict(os.environ, SA_STATE_DIR=state)
        # stale 10^9 minutes: stalls are reported here; repeat 0: every problem is printed, none hidden as known
        done = subprocess.run(["bash", script, ws, "1000000000", "0"], capture_output=True, text=True, env=env, timeout=600)
    except (OSError, subprocess.SubprocessError):
        return []
    finally:
        shutil.rmtree(state, ignore_errors=True)
    found = []
    for line in done.stdout.splitlines():
        m = re.match(r"^(?:PROBLEM|KNOWN): \[(.*?)\] (.*)$", line)
        if m:
            found.append(("watchdog", m.group(1), m.group(2), m.group(2)))
    return found


def build_findings(ws, now, a):
    plist = load(ws)
    now_ts = now.timestamp()
    found = []  # (kind, ref, what, key extra)
    hours = lambda t: (now - t).total_seconds() / 3600
    for p in plist:
        analyse(p)
        ts = p["tickets"].values()
        repo = git("-C", p["tdir"], "rev-parse", "--show-toplevel")[1].strip() or p["base"]
        wts = None
        ready_n = sum(1 for t in ts if t["cell"].startswith("ready"))
        if not p["active"] and ready_n:
            found.append(("paused", p["path"], "paused project holds %d ready ticket(s)" % ready_n, ""))
        old = [t for t in ts if t["status"] == "draft" and hours(t["since"]) > a.draft_days * 24]
        if old:
            found.append(("drafts", p["path"], "%d draft(s) older than %g days" % (len(old), a.draft_days), ""))
        for t in ts:
            r = ref(p, t)
            if t["status"] == "done":
                wts = worktrees(p, repo) if wts is None else wts
                for wt in own_worktrees(wts, t["id"], False):
                    found.append(("cleanup", r, "%s: %s" % (wt, cleanup_reason(repo, wt, base_branch(p["tdir"]))), os.path.basename(wt)))
            if not p["active"]:
                continue
            if t["stage"] in WAITING_STAGES and t["status"] in LIVE and hours(t["since"]) > a.park_hours:
                found.append(("parked", r, "at %s for %.1f h" % (t["stage"], hours(t["since"])), ""))
            if t["status"] == "merged" and hours(t["since"]) > a.park_hours:
                found.append(("unchecked", r, "merged %.1f h ago, not checked" % hours(t["since"]), ""))
            if t["startable"] and hours(t["since"]) > 1:
                found.append(("startable", r, "ready and can start, waiting %.1f h" % hours(t["since"]), ""))
            if t["status"] == "blocked" and hours(t["since"]) > 24:
                found.append(("blocked", r, "blocked for %.1f days: %s" % (hours(t["since"]) / 24, t["cell"]), ""))
            working = t["status"] in LIVE or (t["status"] == "merged" and t["stage"] == "check")
            if working and t["stage"] in WORKING_STAGES:
                newest = folder_activity(t["dir"])
                if t["last_log"]:
                    newest = max(newest, int(t["last_log"].timestamp()))
                wts = worktrees(p, repo) if wts is None else wts
                for wt in own_worktrees(wts, t["id"], True):
                    newest = max(newest, worktree_activity(wt))
                idle = (now_ts - newest) / 60
                if idle >= a.stale_min:
                    found.append(("stalled", r, "stage %s, no activity for %d min" % (t["stage"], idle), ""))
    return disk_findings(ws, a.disk_gb) + found + watchdog_findings(ws)


def run_sweep(ws, now, a):
    state_path = os.path.join(ws, "decision-room", ".followup-state.json")
    try:
        seen = json.loads(read(state_path) or "{}")
    except ValueError:
        seen = {}
    findings = []
    for kind, r, what, extra in build_findings(ws, now, a):
        key = "|".join(x for x in (kind, r, extra) if x)
        findings.append((kind, r, what, key, seen.get(key)))
    new_state = {key: first or now.strftime(STAMP) for _, _, _, key, first in findings}
    kinds = ["disk", "stalled", "parked", "unchecked", "startable", "paused", "drafts", "blocked", "cleanup", "watchdog"]
    ordered = sorted(findings, key=lambda f: (kinds.index(f[0]), new_state[f[3]], f[1]))
    if not ordered:
        lines, doc = ["OK"], ["# Follow-up, built %s" % now.strftime(STAMP), "", "Nothing open."]
    else:
        lines = ["%s: %s | %s | %s | since %s" % ("KNOWN" if f[4] else "NEW", f[0], f[1], f[2], new_state[f[3]]) for f in ordered]
        doc = ["# Follow-up, built %s" % now.strftime(STAMP)]
        for kind in kinds:
            rows = [f for f in ordered if f[0] == kind]
            if rows:
                doc += ["", "## " + kind] + ["- %s | %s | since %s" % (f[1], f[2], new_state[f[3]]) for f in rows]
    if a.write:
        write_atomic(os.path.join(ws, "decision-room", "FOLLOWUP.md"), "\n".join(doc) + "\n")
        write_atomic(state_path, json.dumps(new_state, indent=1, sort_keys=True) + "\n")
    return "\n".join(lines) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(prog="flow.py")
    ap.add_argument("mode", choices=("queue", "sweep"))
    ap.add_argument("workspace")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--age-days", type=float, default=3)
    ap.add_argument("--stale-min", type=float, default=30)
    ap.add_argument("--park-hours", type=float, default=4)
    ap.add_argument("--draft-days", type=float, default=7)
    ap.add_argument("--disk-gb", type=float, default=25)
    a = ap.parse_args(argv)
    ws = os.path.realpath(a.workspace)
    if not os.path.isdir(ws):
        print("refused: no such folder: %s" % a.workspace)
        return 1
    now = now_dt()
    if a.mode == "queue":
        text = build_queue(ws, now, a.age_days)
        if a.write:
            write_atomic(os.path.join(ws, "decision-room", "QUEUE.md"), text)
    else:
        text = run_sweep(ws, now, a)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
