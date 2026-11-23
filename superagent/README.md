# Superagent

One router chat runs every ticket in every project of the workspace. You talk only to the router; every other agent reports to it.

Start it with `ccs` (it runs `claude --agent router --name router --permission-mode auto --remote-control router --settings ~/.claude/superagent/router-settings.json` from `~/code`).

## What you can say to the router

| You say | What happens |
|---|---|
| `status` | What is running, what needs you (as buttons), what to try yourself, suggestions, what finished |
| "add X to shop-site", "clean up Y in my-app and studio-app" | It asks what it must, writes the tickets, and shows them for approval |
| "X is broken in my-app" | A bug ticket: reproduced first, then fixed with a regression test |
| "investigate / compare / plan X" | A report-only ticket; you decide afterwards whether to build |
| "approve 2", "approve my-app#009,010", "approve all" | The tickets start |
| "run my-app#009 on opus", "max effort on shop-site#005", "fable for this one" | Sets the model and effort for that ticket |
| "use opus by default in my-app", "review 012 at xhigh" | A project default, or the effort of the Codex review |
| "what is 009 running on?" | The model and effort, and where the choice came from |
| "stop my-app#008", "resume my-app#008", "stop all", "resume all" | Stops survive a restart; only you lift them |
| "do my-app#012 first" | Marks it `Priority: high`: it starts before the other ready tickets |
| "what is waiting, and why?" | Every waiting ticket with its reason: waits on another ticket, paused project, no free agent, a seat unavailable, or waiting for you |
| "clean up done tickets" | Removes merged, clean working copies and their branches (in a `Cleanup: auto` project the follow-up agent does this by itself) |
| "from now on, merge quick low-risk tickets in my-app without asking" | Saved as a standing rule for that project |
| "what should I try?" | The checks only you can do (device, microphone, purchases) |

Models: haiku, sonnet, opus, fable. Effort: low, medium, high, xhigh, max. With nothing set, the tier table decides (`sa run-options --table`): Fable 5.2 writes tickets and plans and holds a seat in the decision room, and nothing else; Opus does design, second reviews, investigations, bugs and high-risk builds; Sonnet researches, builds, merges, checks and follows up; Haiku tests and does the clerk's one-command jobs. A plan and its build are separate runs, so the plan's model never builds. The router's hook refuses a start above the table (`refused: ... runs on <model> at most`) unless a `Model:` or `Plan model:` line of the ticket or the project allows it. A router that was already running when these rules landed is logged and never refused; start it again to switch the check on. Every agent the router starts gets a name, `Andrea-my-app-009` (a first name, the project, the ticket), and a short description of its task, `build: permissions onboarding`: the agent list shows them side by side, and the agent's start line in the room log ends with both. The router's settings set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` to 40, so its context is compacted once it passes 40% of the window; the value is read when the router starts. When every ticket is finished, the router asks you to run `/clear` before the next task. Every review has two reviewers: Codex Astra, then Claude; both must allow, and `sa gate` checks it. `sa stats <workspace>` shows what each role spent and how tickets flowed. Standing rules live in `ROUTER-PREFS.md`.

## How a ticket moves

Quick ticket: build, test, Codex review, your merge approval, merge, check.
Ticket with a plan: research, plan, Codex checks the plan, your plan approval, then the same as above.

Nothing merges unless the recorded test and review cover exactly the code that lands (`sa gate`). A review blocks only on real defects against what you asked; extra hardening ideas become suggestions.

## Files

| Path | What it is |
|---|---|
| `~/.claude/agents/router.md` and the eleven role files next to it | What each agent does |
| `~/.claude/agents/follow-up.md` | The follow-up agent: finds what was left on the side and removes finished working copies |
| `~/.claude/agents/decision-room.md` | The decision room: Fable 5.2 and Codex Astra decide one question and record it |
| `~/.claude/superagent/PROTOCOL.md` | The rules and file formats all agents share |
| `~/.claude/superagent/sa` | The only way agents change ticket state, and the merge gate (`sa help`) |
| `~/.claude/superagent/watchdog.sh` | Finds stuck tickets and broken board rows (`sa sweep` runs it) |
| `~/.claude/superagent/flow.py` | `sa queue` and `sa sweep` |
| `~/.claude/superagent/seat.sh` | `sa room seat`: one call of one decision-room seat |
| `~/.claude/superagent/sweep-timer.sh` | Installs or removes the timer that runs `sa sweep` and `sa queue` every 10 minutes |
| `~/.claude/skills/write-tickets/SKILL.md` | Ticket and eval templates |
| `<project>/tickets/` | `BOARD.md`, `PROJECT.md`, one folder per ticket, plus `LOG.md`, `SUGGESTIONS.md`, `LEARNED.md`, `QA.md` |
| `<workspace>/ACTIVE-PROJECTS.md` | Which projects the router looks at (ticked lines) |
| `<workspace>/ROUTER-PREFS.md` | Your standing preferences for every project (created when you state one) |
| `<workspace>/decision-room/<project>/LOG.md` | Every change in that project, one line each, appended by `sa` |
| `<workspace>/decision-room/<project>/DECISIONS.md` | Every decision of the room for that project, one `## D<n>` block each, appended by `sa room decide` |
| `<workspace>/decision-room/<project>/debate/` | The prompts and answers of each decision's debate |
| `<workspace>/decision-room/INDEX.md` | What runs in every ticked project, rewritten by `sa room index <workspace>` |
| `<workspace>/decision-room/QUEUE.md` | What starts next, in order, and why each other ready ticket waits (`sa queue`) |
| `<workspace>/decision-room/FOLLOWUP.md` | What was left on the side, each finding with its age (`sa sweep`) |
| `<workspace>/decision-room/<project>/digest/NNN.md` | A short summary of ticket NNN that `sa` keeps current, read first by a builder that takes the ticket over |

Per-project choices live in `tickets/PROJECT.md`: `Merge` (ask, auto, auto-low-risk), `Cleanup` (ask, auto: with `auto` the follow-up agent removes the merged, clean working copy of a finished ticket by itself; with `ask` you are asked once per project), `Delivery` (local-only, direct-PR), `Browser checks`, `Plan review`, `Suggestions`, `Bug tickets`, and default `Model` / `Plan model` / `Effort`.

## Order, follow-up and clean-up

`sa queue <workspace>` prints what starts next: tickets landing, then tests and reviews, then ready tickets, `Priority: high` first, then one that has waited more than three days, then the one most others wait on, then the oldest. Every other ready ticket gets one reason (waits on a ticket, paused project).

`sa sweep <workspace>` prints what was left on the side: a ticket in flight with no agent, an approval parked for hours, a ticket merged and never checked, a ready ticket that could start, old drafts, a paused project holding ready work, a finished ticket whose working copy is still there. A finding keeps the time it was first seen until it is fixed.

The `follow-up` agent runs both every 10 minutes while the router is open, hands each new finding to the router, and removes the working copy of a finished ticket with `sa cleanup <ticket-dir>` (only when the project says `Cleanup: auto`, the ticket is `done`, its branch is merged and nothing is uncommitted; removing a working copy also deletes its ignored files, such as a local `.env`). With no router open, `superagent/sweep-timer.sh install <workspace>` keeps the two files current (`remove` undoes it); the findings then wait in `FOLLOWUP.md` for the next session.

`sa stats <workspace> [hours]` shows the spend by role, model, stage and cost, the context each role starts with, and how often plans were sent back.

## Decision room

Every project the router runs has its own folder in `<workspace>/decision-room/` (a project outside the workspace names its folder with `Room: <absolute path>` in PROJECT.md). Its `LOG.md` gets one line for every stage change, question, answer, suggestion, lesson, check, landing, note, decision, agent dispatch and agent report:

```
<badge> <YYYY-MM-DD HH:MM> | <project>#NNN or <project> | <kind> | <text>
```

The badge says which agent wrote the line: 🧭 router, 🏛️ decision room, ✍️ clerk and ticket-writer, 🔨 worker, 🤝 teammate, 🐞 reproducer, 🧪 tester, 🔍 reviewer, 🔀 merger, 🌐 checker, 🐶 follow-up (and the older watchdog), 👤 you, ❔ not known (each agent runs `sa` as `SA_ROLE=<its role> sa ...`; a call without it still works and gets ❔). The first line of a new log is that legend; `tickets/LOG.md` lines carry the badge too, and the two seats in `DECISIONS.md` are 🟣 Fable 5.2 and 🟢 Codex Astra. Lines written before the badges have none and stay as they are.

The text is everything after the third ` | `. The log is written only by `sa` and never edited by hand. An agent that changes something outside `sa` (a hand edit of rd.md or PROJECT.md, a preference, a finished implementation step) registers it with `sa room note <ticket-dir|tickets-dir> <who> "<what changed>"`. `sa room index <workspace>` writes `INDEX.md`: each ticked project's open tickets, open questions and log path.

Watch it live with `~/.claude/superagent/sa room watch` (add `--since 60` to start with the last hour, `--project <name>` to follow one project; Ctrl-C stops it). It follows every project's `LOG.md` at once and shows the whole run: each agent's lines in that agent's own colour (the legend is its first line), a decision in bold magenta, a failure or a refusal in red and a landing in bold green, with a coloured line naming the project whenever it changes and `· · ·` between tickets. The log files stay plain text; only the viewer adds colour (`--color never` or `NO_COLOR=1` turns it off, `--color always` keeps it for `less -R`). The kinds of line:

- `question`: who asked, the question and every option, the recommended one marked (`Q1 from worker: ... | options: (a) ... (recommended); (b) ...`).
- `answer`: who answered (the user, or the decision room through `sa answer --by`), the answer and the question it answers.
- `dispatch`: an agent starting on a ticket: its role, who started it, the stage, the model and the effort. The router's start of an agent is logged by the router session's own hooks (`superagent/router-settings.json`, loaded by the `--settings` flag above) with the model and effort the Agent call really carried; an agent started any other way logs its own start first, with `sa room event`.
- The router's questions to you (its buttons) and your answers are logged by the same hooks, in the log of each project the question names (else the room's own `LOG.md`): `router: asked the user: ... | options: ...`, then `router: <header> answered by the user: <your answer> | question: ...`.
- `report`: an agent handing back: its role, its status (`ready`, `blocked`, `failed`, `dropped`, `waiting: ...`; the clerk `done` or `refused: ...`) and its one-sentence summary. Each role logs it last; the follow-up agent only when it returns with a finding.
- `decision`: the room's verdict: the question, the chosen option and who decided.

Questions and answers that `sa ask` and `sa answer` do not record (a draft ticket's open question, a plan or merge approval, an override) are logged with `sa room event ... question|answer`: the router passes each such answer on as a `User answer:` line (the question as asked, the user's words), and the agent that gets it logs it; for a "Not yet" with no agent to send, the clerk's log mode does.

The `decision-room` agent is the room's host, on Sonnet: it builds the reading set, calls the seats and records, and holds no position. The seats decide: Claude Fable 5.2, through one headless call per round (`sa room seat fable`), and Codex on `gpt-6-astra`, both read-only and both given the same prompt. They debate once when they differ, the safer option wins a lasting disagreement, and one seat decides alone when the other is unavailable. `sa room decide` writes the record to `DECISIONS.md` and a `decision` line to the log; it works out who decided itself. The room only records: it changes no ticket.

### Who decides: the decision room switch

`sa room on <workspace> <YYYY-MM-DD> "<the user's words>"` switches the decision room on; `sa room off <workspace> "<why>"` switches it off; `sa room status <workspace>` prints which. Off (the default): you decide everything, as above. On: the router sends every approval and choice to the decision room, the clerk carries the room's decision out, and every record says the decision room decided on your standing order. What stays yours either way: stops, logins, credentials and access an agent could not get with computer use, OS permission prompts, payments, your own uncommitted files, facts only you know, questions no seat could take, and anything Claude Code's safety check refuses. Agents ask those with `sa ask --access`; `sa room owner` marks one after the fact. With `Delivery: direct-PR`, the merger merges a ticket's own PR on GitHub only past `sa room pr-ok`.
