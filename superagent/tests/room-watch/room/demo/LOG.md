# Badges: 🧭 router, 🏛️ decision-room/decision room, ✍️ clerk/ticket-writer, 🔨 worker, 🤝 teammate, 🐞 reproducer, 🧪 tester, 🔍 reviewer/codex-reviewer, 🔀 merger, 🌐 checker, 🐶 watchdog, 👤 user/owner/the user, ❔ anything else
2026-11-13 09:12 | demo#001 | stage | ready/- -> in-progress/build: worker starts
🔨 2026-11-14 09:00 | demo#001 | dispatch | worker: started by router: stage build, model sonnet, effort max
🔨 2026-11-14 09:01 | demo#001 | stage | ready/- -> in-progress/build: tests first

🔨 2026-11-14 09:05 | demo#001 | note | worker: baseline is 217 ok, 0 FAIL
🧪 2026-11-14 09:10 | demo#001 | note | tester: round 1 starts
🧪 2026-11-14 09:20 | demo#001 | report | tester: failed: one check fails
🔨 2026-11-14 09:21 | demo#001 | stage | in-progress/build -> blocked/build: waits for an answer
🔨 2026-11-14 09:21 | demo#001 | question | in-progress/build -> blocked/build: Q1 from worker: Use A or B? | options: (a) use A (recommended); (b) use B
👤 2026-11-14 09:22 | demo#001 | answer | Q1 answered by the user: use A | question: Use A or B?
🏛️ 2026-11-14 09:23 | demo#001 | decision | D1 (Q1): Use A or B? -> (a) use A; decided by both
🔨 2026-11-14 09:25 | demo#001 | stage | blocked/build -> failed/build: the build broke
🔍 2026-11-14 09:30 | demo#002 | report | codex-reviewer: refused: nothing to review
🔀 2026-11-14 09:50 | demo#002 | landing | 3f2a1bc on main
❔ 2026-11-14 09:51 | demo#002 | note | stranger: a line with no known role
🔨 2026-11-14 09:52 | demo#002 | note | worker: [31mredafter	tab
