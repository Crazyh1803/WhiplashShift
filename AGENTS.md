# Whiplash Shift chat workflow

## Starting and resuming work

Every new chat that changes this project gets its own `chat/*` branch and isolated
worktree. Before editing, run `python3 tools/workflow/chat.py start "short topic"`.
Use the returned absolute `worktree` as the working directory for all edits, tests,
commits and publishing in that chat. The command uses `CODEX_THREAD_ID` to resume
the same branch on later turns. If unavailable, supply `--chat-id` with a stable
identifier for this chat. Do not use the same identifier for different chats.
Do not run start again from a worktree already returned for this chat.

Start from `origin/main` unless the user explicitly requests a dependency branch
using `--base`. Never switch a shared checkout's branch to start another chat.
Never discard another chat's changes or reuse its branch.

## Delivering every correction

The user authorizes pushing tested work to its chat branch and making it available
through the Windows desktop preview. After each completed correction, run the
relevant checks, commit only the intended files, then run
`python3 tools/workflow/chat.py publish` from the chat worktree. Do not publish
known failures. Report the branch, commit, checks and preview status. Publishing
updates `desktop-preview`'s manifest only; it does not merge game code into main.
If another chat selects a different preview later, the latest selection wins.
The user can request `preview <branch>` to choose an existing branch again.

## Merge authorization

Do not merge or push game changes to `main` just because work is complete.
Only an explicit user instruction such as `merge`, `merge <branch>` or
`$whiplash merge <branch>` authorizes that step. Resolve ambiguity from the current
chat's branch when possible. After authorization, fetch current main and the branch,
merge in a separate integration worktree, resolve conflicts, and run checks on the
combined result. Push normally without force. Update the stable Windows release
manifest to the tested merge commit, publish it to main, and select main for preview.
Preserve task branches unless the user asks to delete them.

## Project command

`.agents/skills/whiplash/SKILL.md` defines `$whiplash` and the start, publish, preview
and merge forms. Ordinary requests to fix or add something use the same workflow
even when the user omits the command. See `docs/chat-workflow.md` for Windows setup
and the distinction between a preview and a merge.
