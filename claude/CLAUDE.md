# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# When to use graphify (all repos)
- In a repo that has `graphify-out/graph.json`, answer **structure questions** (how does it work, where is it called from, what does it affect) with `graphify query "<question>"` before grep or reading files. For how two concepts relate use `graphify path "<A>" "<B>"`; for one concept, `graphify explain "<concept>"`.
- Don't use it for edits whose location you already know, or for git, config or ops work.
- Subagents: in a repo with a graph, every brief tells the agent to orient with `graphify query` before reading files (agents re-reading the codebase cost many tokens on 2026-11-20).
- A repo with code and no graph: build it once, code-only (`graphify update .`, AST, no LLM tokens), and add `graphify-out/` to `.git/info/exclude`.
- After merging a lane into a base branch, run `graphify update .` there so the graph matches the code.
- The graph is not refreshed automatically. Don't install `graphify hook install` or any global git hook for it — rebuilding the combined `~/git` graph on every commit used up all the memory. If the graph is stale, run `graphify update .` in that repo; build a new one with `/graphify .`.

# Working rules (all repos)

## Communication
- **Answer in Korean**, unless the user writes in English. Commands, identifiers and code stay in the original.
- **Finish briefly**: after reporting completion, answer a short "done?" in one line — don't list the changes again.
- **READMEs**: edit by asking "does a first-time reader, reading top to bottom, need this?" Delete duplication, internal implementation narratives and dated status logs (keep common footers the user put there on purpose).

## Safety
- **The guard hook** (`~/.claude/hooks/guard.py`) blocks reading or printing secrets and irreversible commands. When it blocks, don't work around it: use the alternative in its message, or ask the user to run the command with `! <command>`.
- **Secrets**: load `.env` and credentials, never view them — `set -a; . ./.env; set +a`, unless the repo's CLAUDE.md names another loader. Check a variable exists with `[ -n "$VAR" ] && echo set`.
- **Commit messages are in English**, Conventional Commits (`fix(scope): …`), with the why in the body. This overrides any repo `CLAUDE.md` that asks for Korean commit messages; when you next work in such a repo, change its line to match. Answering the user stays in Korean.
- **Commit identity**: never override it (`git -c user.email=…`, `GIT_AUTHOR_*`) — use the repo's config; the global pre-commit hook enforces an allowlist. Agents appear only via `Co-Authored-By`.
- **Deletions**: if the user named the target, delete it without asking again. Confirm right before deleting only when the target is ambiguous or you widened the scope yourself (e.g. "and also these related files").
- **sudo** needs a password → ask the user to run `! sudo …`.

## How to work
- **Root cause**: fix the cause, not the symptom, and leave a check (test, lint, guard) so the same class of problem doesn't recur.
- **Done criteria first**: for long tasks, state in one line at the start what counts as done (the bar and how it's verified), and write it where the repo keeps its plans or ledgers.
- **On compaction, keep**: the goal and done criteria, branch and worktree paths, ledger and plan file paths, open review items, running background jobs.
- **Parallelism**: while a long job runs, hand independent analysis or drafts to worktree agents without asking.
- **Agents and tokens**: a new task gets a new agent with a tight brief. Resume an agent only to finish its own task, never to hand it round after round of new work: its context grows with every round and every tool call rereads it. Agents wait on one background command that notifies on exit, never on sleep or poll loops.
- **Switching repos**: read that repo's `CLAUDE.md` first — after `cd ~/git/<other-repo>` its CLAUDE.md and `.claude/settings.json` hooks are not loaded automatically.
- **Where knowledge lives**: repo rules and commands in that repo's `CLAUDE.md` (in git); preferences that span repos in this file; only a repo's in-progress state in auto memory. Memory loads per the path the session started from, so don't duplicate a repo's CLAUDE.md there.

## Worktrees
- All worktrees live under `~/git/.harness-wt/` — never next to `~/git`, in `wt/`, `<repo>-wt/` or a repo's `.claude/worktrees`.
- Repos listed in `orca repo list` create and remove worktrees through the `orca-cli` skill (`worktree create` / `worktree rm`; the skill picks the executable). `git worktree add/remove` falls out of sync with Orca's records, and Orca hides worktrees made outside it. Use git only to read. Repos without Orca: `git worktree add ~/git/.harness-wt/<repo>-<name> -b <branch>`.

## Public repos
- To strip something from a public repo, check HEAD, history, release assets and Actions artifacts. Old SHAs stay reachable through the GitHub API after a force push — confirm removal by an anonymous `curl` getting a 404 from the API.

# Personal additions (installed only with the personal profile)
@~/.claude/CLAUDE.personal.md
