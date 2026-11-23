#!/usr/bin/env python3
"""sa stats <workspace> [hours]: what the superagent spent and how tickets flowed. Reads only.

Spend comes from the transcripts Claude Code keeps of the router's agents
(<projects>/<workspace slug>/<session>/subagents/agent-*.jsonl and its .meta.json); flow comes from
the decision-room logs (<workspace>/decision-room/<project>/LOG.md). Tokens are weighted the way they
are billed relative to fresh input: cache write 1.25, cache read 0.1, output 5. Prices per model are
not applied to the weights, so compare those shares within a model, not across models; `by cost`
applies the USD prices of prices.json (override the path with SA_PRICES) and is printed only when every
model family that appears has a price.
"""
import collections
import datetime
import glob
import json
import os
import re
import sys

W_WRITE, W_READ, W_OUT = 1.25, 0.1, 5
LONG_PROMPT = 100000  # tokens; a price entry may carry a "long" set above this prompt size
FAMILIES = ("fable", "opus", "sonnet", "haiku")
BUILDERS = ("worker", "teammate", "reproducer")
STAGE = re.compile(r"^Stage:\s*(\S+)", re.M)
PLAN_ENTRY = re.compile(r"-> in-progress/plan(?![\w-])")
REVISIONS_LISTED = 3  # a ticket is named under `most:` from this many plan revisions


def family(model):
    return next((f for f in FAMILIES if f in (model or "")), model or "?")


def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def parse_utc(text):
    try:
        return datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def read_run(path, since):
    """(the last usage record of every assistant message newer than `since`, the brief = first user message)."""
    seen, brief = {}, ""
    with open(path, errors="ignore") as lines:
        for line in lines:
            if not brief and '"type":"user"' in line[:600]:  # the brief is the first user row
                try:
                    content = (json.loads(line).get("message") or {}).get("content")
                except ValueError:
                    content = None
                if isinstance(content, list):
                    content = " ".join(b.get("text", "") for b in content if isinstance(b, dict))
                brief = content if isinstance(content, str) else ""
            if '"usage"' not in line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            msg = row.get("message") or {}
            when = parse_utc(row.get("timestamp"))
            if row.get("type") != "assistant" or not msg.get("usage") or when is None or when < since:
                continue
            seen[msg.get("id")] = (family(msg.get("model")), msg["usage"])
    return list(seen.values()), brief


def stage_of(brief):
    found = STAGE.search(brief)
    return found.group(1).lower() if found else "unknown"


def spend(projects, workspace, since):
    roles = collections.defaultdict(collections.Counter)
    efforts = collections.defaultdict(collections.Counter)
    parts = collections.Counter()
    models = collections.Counter()
    tokens = collections.defaultdict(collections.Counter)  # (family, tier) -> fresh/write/read/out, for prices

    def count(key, f, fresh, write, read, out):
        role = roles[key]
        weighted = fresh + W_WRITE * write + W_READ * read + W_OUT * out
        role["turns"] += 1
        role["context"] += fresh + write + read
        role["fresh"] += fresh
        role["write"] += write
        role["read"] += read
        role["out"] += out
        role["weighted"] += weighted
        models[f] += weighted
        parts["conversation re-read"] += W_READ * read
        parts["new content read in"] += fresh + W_WRITE * write
        parts["output"] += W_OUT * out
        tier = tokens[(f, "long" if fresh + write + read > LONG_PROMPT else "std")]
        tier["input"] += fresh
        tier["cache_write"] += write
        tier["cache_read"] += read
        tier["output"] += out

    dirs = {os.path.join(projects, slug(p)) for p in (os.path.abspath(workspace), os.path.realpath(workspace))}
    for base in dirs:
        for meta_path in glob.glob(os.path.join(base, "*", "subagents", "*.meta.json")):
            run_path = meta_path[: -len(".meta.json")] + ".jsonl"
            if not os.path.exists(run_path) or os.path.getmtime(run_path) < since:
                continue
            try:
                with open(meta_path) as fh:
                    meta = json.load(fh)
            except (OSError, ValueError):
                continue
            turns, brief = read_run(run_path, since)
            if not turns:
                continue
            fam = collections.Counter(f for f, _ in turns).most_common(1)[0][0]
            name = meta.get("agentType") or "?"
            key = ("%s@%s" % (name, stage_of(brief)) if name in BUILDERS else name, fam)
            roles[key]["runs"] += 1
            efforts[key][str(meta.get("effort") or "default")] += 1
            first = turns[0][1]
            roles[key]["first"] += sum(first.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            for f, use in turns:
                count(key, f, use.get("input_tokens") or 0, use.get("cache_creation_input_tokens") or 0,
                      use.get("cache_read_input_tokens") or 0, use.get("output_tokens") or 0)
    # decision-room seats run headless, outside a subagent: one usage file per call
    for path in glob.glob(os.path.join(workspace, "decision-room", "*", "debate", "*-fable-*-usage.json")):
        try:
            if os.path.getmtime(path) < since:
                continue
            with open(path) as fh:
                use = json.load(fh)["usage"]
            fresh, write, read, out = (int(use.get(k) or 0) for k in (
                "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"))
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            continue
        key = ("room-seat", "fable")
        roles[key]["runs"] += 1
        efforts[key]["default"] += 1
        roles[key]["first"] += fresh + write + read
        count(key, "fable", fresh, write, read, out)
    return roles, efforts, parts, models, tokens


def load_prices():
    path = os.environ.get("SA_PRICES") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "prices.json")
    try:
        with open(path) as fh:
            return json.load(fh).get("models") or {}
    except (OSError, ValueError, AttributeError):
        return None


def cost_line(tokens, prices):
    """`by cost:` line, or None without a price file. Never guesses: one missing family refuses the whole line."""
    if prices is None:
        return None
    seen = sorted({f for (f, _), use in tokens.items() if any(use.values())})  # <synthetic> turns carry no tokens
    missing = [f for f in seen if not isinstance(prices.get(f), dict)]
    if missing:
        return "  by cost: no price for %s" % missing[0]
    dollars = collections.Counter()
    for (f, tier), use in tokens.items():
        if not any(use.values()):
            continue
        price = prices[f]
        price = price.get("long", price) if tier == "long" else price
        try:
            dollars[f] += sum(n * price[k] for k, n in use.items()) / 1e6
        except (KeyError, TypeError):
            return "  by cost: no price for %s" % f
    total = sum(dollars.values())
    if not total:
        return None
    return "  by cost: %s, total $%.2f" % (", ".join("%s %d%%" % (f, round(100 * v / total)) for f, v in dollars.most_common()), total)


LINE = re.compile(r"(\d{4}-\d\d-\d\d \d\d:\d\d)$")


def flow(workspace, since):
    counts = collections.Counter()
    ready, landed, plans = {}, {}, collections.defaultdict(list)
    for log in glob.glob(os.path.join(workspace, "decision-room", "*", "LOG.md")):
        with open(log, errors="ignore") as lines:
            for line in lines:
                cells = line.rstrip("\n").split(" | ", 3)
                stamp = LINE.search(cells[0]) if len(cells) == 4 else None
                if not stamp:
                    continue
                when = datetime.datetime.strptime(stamp.group(1), "%Y-%m-%d %H:%M").timestamp()
                ref, kind, text = cells[1], cells[2], cells[3]
                if kind == "stage" and "-> ready/" in text:
                    ready[ref] = when
                if kind == "stage" and PLAN_ENTRY.search(text):
                    plans[ref].append(when)
                if when < since:
                    continue
                if kind == "landing":
                    counts["landed"] += 1
                    landed[ref] = when
                elif kind == "decision":
                    counts["room decisions"] += 1
                elif kind == "question":
                    counts["questions to you" if "asked the user" in text else "questions (agents)"] += 1
                elif kind == "stage":
                    step = text.split(": ", 1)[-1]
                    if "stale" in step:
                        counts["sent back: base moved"] += 1
                    elif re.search(r"test round \d+ failed", step):
                        counts["sent back: test failed"] += 1
                    elif "to fix" in step:
                        counts["sent back: review"] += 1
                    elif "must-fix" in step or "concerns remain" in step:
                        counts["sent back: plan review"] += 1
                    elif re.match(r"test round \d+$", step):
                        counts["test rounds"] += 1
                    elif re.match(r"review round \d+$", step):
                        counts["review rounds"] += 1
    hours = sorted((landed[r] - ready[r]) / 3600 for r in landed if r in ready and landed[r] >= ready[r])
    revisions = {r: sum(1 for t in sorted(ts)[1:] if t >= since) for r, ts in plans.items()}
    return counts, hours, {r: n for r, n in revisions.items() if n}


def millions(n):
    return "%.1fM" % (n / 1e6)


def report(workspace, hours, projects, now):
    since = now - hours * 3600
    roles, efforts, parts, models, tokens = spend(projects, workspace, since)
    counts, to_land, revisions = flow(workspace, since)
    total = sum(parts.values())
    out = ["# sa stats: last %g h" % hours, ""]
    if not total:
        out.append("spend: no agent runs found for this workspace in %s" % projects)
    else:
        out.append("spend: %s weighted tokens" % millions(total))
        out.append("  by part:  " + ", ".join("%s %d%%" % (k, round(100 * v / total)) for k, v in parts.most_common()))
        out.append("  by model: " + ", ".join("%s %d%%" % (k, round(100 * v / total)) for k, v in models.most_common()))
        cost = cost_line(tokens, load_prices())
        if cost:
            out.append(cost)
        out.append("")
        out.append("%-20s %-7s %4s %6s %9s %6s %6s %8s %6s  %s" % (
            "role", "model", "runs", "t/run", "ctx/turn", "first", "cache", "out/run", "share", "effort"))
        for (role, fam), r in sorted(roles.items(), key=lambda kv: -kv[1]["weighted"]):
            mix = ", ".join("%s %d" % (e, n) for e, n in efforts[(role, fam)].most_common())
            out.append("%-20s %-7s %4d %6.0f %8.0fk %5.0fk %5.0f%% %7.1fk %5.0f%%  %s" % (
                role, fam, r["runs"], r["turns"] / r["runs"], r["context"] / r["turns"] / 1000,
                r["first"] / r["runs"] / 1000, 100 * r["read"] / (r["context"] or 1),
                r["out"] / r["runs"] / 1000, 100 * r["weighted"] / total, mix))
    out.append("")
    out.append("flow:")
    for key in ("landed", "test rounds", "review rounds", "sent back: base moved", "sent back: test failed",
                "sent back: review", "sent back: plan review", "room decisions", "questions (agents)", "questions to you"):
        out.append("  %-24s %d" % (key, counts[key]))
    out.append("  plan revisions %d" % sum(revisions.values()))
    worst = sorted(((n, r) for r, n in revisions.items() if n >= REVISIONS_LISTED), key=lambda x: (-x[0], x[1]))[:5]
    if worst:
        out.append("  most: " + ", ".join("%s (%d)" % (r, n) for n, r in worst))
    if to_land:
        out.append("  ready to landed: median %.1f h, longest %.1f h (%d tickets)" % (to_land[len(to_land) // 2], to_land[-1], len(to_land)))
    return "\n".join(out)


def main(argv):
    if not 1 <= len(argv) <= 2:
        sys.exit("refused: usage: sa stats <workspace> [hours, default 24]")
    workspace = argv[0].rstrip("/") or "/"
    if not os.path.isdir(workspace):
        sys.exit("refused: no such folder: %s" % workspace)
    try:
        hours = float(argv[1]) if len(argv) == 2 else 24.0
    except ValueError:
        hours = 0
    if hours <= 0:
        sys.exit("refused: hours must be a number above 0, got '%s'" % argv[1])
    projects = os.environ.get("SA_CLAUDE_PROJECTS") or os.path.expanduser("~/.claude/projects")
    print(report(workspace, hours, projects, datetime.datetime.now().timestamp()))


if __name__ == "__main__":
    main(sys.argv[1:])
