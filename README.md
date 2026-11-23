# coconut

A multi-agent setup for Claude Code. You talk to one chat, the **router**. It writes tickets, starts the right
agent for each step on the right model, has every change tested and reviewed twice, and merges only what passed.
A **decision room** of several models can answer the questions you would otherwise be asked.

## Install

```bash
git clone https://github.com/marcusbey/coconut.git && cd coconut
./install.sh --workspace ~/code      # ~/code: the folder that holds your project repositories
```

The installer copies the setup into `~/.claude`, saves every file it replaces under `~/.claude/backups/`, writes
`ACTIVE-PROJECTS.md` and `ROUTER-PREFS.md` into the workspace if they are missing, installs RTK (with Homebrew) and switches it on, and
prints the alias that starts the router. Run it again at any time to update.

Then:

1. Open `ACTIVE-PROJECTS.md` in the workspace and tick the projects the router may work in.
2. Add the `ccs` alias the installer printed to your shell profile, and run `ccs`.
3. Say what you want: "add X to my-app", "Y is broken in my-app", "status".

`./install.sh --check` runs the setup's own tests (about 10 minutes). `./install.sh --dry-run` changes nothing.

## What you need

| Tool | For | Without it |
|---|---|---|
| Claude Code (`claude`), signed in to a subscription | everything | nothing runs |
| `git`, `bash`, `perl`, `python3` | `sa`, the state tool | the installer stops |
| Codex CLI (`codex`), signed in | the first review of every plan and change; a decision-room seat | Claude reviews alone |
| Gemini CLI (`gemini`), signed in with Google | a decision-room seat | the room has one seat fewer |
| RTK (`rtk`) | condensing command output before agents read it; the installer adds it with Homebrew | agents read output whole |

Every model call runs on the subscription its CLI is signed in to. The decision room removes API key variables
from its seat calls, so it never bills a key.

## What you can say to the router

| You say | What happens |
|---|---|
| `status` | What runs, what needs you (as buttons), what waits and why, what finished |
| "add X to my-app" | It asks what it must, writes the tickets and shows them for approval |
| "X is broken in my-app" | A bug ticket: reproduced first, then fixed with a regression test |
| "investigate / compare / plan X" | A report-only ticket |
| "approve 2", "approve all" | The tickets start |
| "do my-app#012 first" | That ticket goes to the front of the queue |
| "run my-app#009 on opus" | Sets the model for that ticket |
| "stop my-app#008", "resume my-app#008" | Stops survive a restart; only you lift them |
| "from now on ..." | Saved as a standing rule in `ROUTER-PREFS.md` |

## How it works

**Tickets.** A ticket says what to build and how to prove it: the user value, the acceptance criteria, the
complexity, what it depends on, the requirements and a check for each one. A ticket that delivers a product story
copies that story's own words.

**Stages.** A quick ticket goes build, test, review, merge. A larger one goes research, plan, plan review, your
approval, build, test, review, merge. The plan and the build are separate runs, so the model that plans never
builds. Nothing merges unless the recorded test and both reviews cover exactly the code that lands.

**Models.** One table decides which model each step gets, and the router's hook refuses a start above it:

| Model | Work |
|---|---|
| Fable 5.2 | Writing tickets, writing plans, design, the Claude review of every plan and change, a seat in the decision room |
| Opus | Investigations, bugs, high-risk builds |
| Sonnet | Research, building, merging, checking, follow-up |
| Haiku | Tests, small clerk jobs |

`~/.claude/superagent/sa run-options --table` prints the table; a `Model:` line on a ticket overrides it.

**Decision room.** Off by default. Switched on, the room answers what you would have been asked: approvals, open
questions, suggestions. Its seats are Claude Fable 5.2, Codex, and Gemini 4 (Carbon, or Neon when Carbon is not
available), each read-only and each given the same prompt. They debate once when they differ; a majority decides;
a tie goes to a read-only test or a referee. Logins, payments, stops and facts only you know always stay yours.

**Order and follow-up.** `sa queue` computes what starts next and gives every waiting ticket one reason.
`sa sweep` lists what was left on the side: a ticket with no agent, an approval parked for hours, a ready ticket
that could start, a paused project holding work, a finished working copy still on disk. A follow-up agent runs both
every 10 minutes and hands each new finding to the router.

**Cost.** `sa stats <workspace> [hours]` shows the spend by role, model, stage and price.

## Files

| Path | What it is |
|---|---|
| `agents/` | One file per role: what that agent does |
| `superagent/PROTOCOL.md` | The rules and file formats every agent shares |
| `superagent/README.md` | The full reference: every command, file and setting |
| `superagent/sa` | The state tool: the only way agents change a ticket, and the merge gate (`sa help`) |
| `superagent/tests/` | The tests of all of the above |
| `skills/write-tickets/` | The ticket and evaluation templates |
| `templates/` | The two workspace files the installer writes |

In each project the router creates `tickets/` (the board, one folder per ticket), and in the workspace
`decision-room/` (one log per project, the room's decisions, the queue and the follow-up files).

## Update and remove

Update: `git pull && ./install.sh`. Restart the router afterwards: it reads its role file when it starts.

Remove: delete `~/.claude/superagent`, `~/.claude/skills/write-tickets` and the role files listed in `agents/`
from `~/.claude/agents`, or copy back what `~/.claude/backups/coconut-<time>/` holds. `rtk init --global --uninstall`
removes RTK's hook. Your projects' `tickets/` folders and the workspace's `decision-room/` are yours to keep.
