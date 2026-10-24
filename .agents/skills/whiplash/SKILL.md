---
name: whiplash
description: Start or resume a Whiplash Shift chat branch, publish tested corrections to desktop preview, select a preview, or merge a branch when explicitly requested by the user.
---

Use this project command for Whiplash Shift development. Follow the repository's
AGENTS.md. Read `docs/chat-workflow.md` when setting up a desktop or resolving a
workflow problem.

- `$whiplash <topic or request>` or `$whiplash start <topic>`: run
  `python3 tools/workflow/chat.py start "<short topic>"` from the repository.
  Continue all work from the returned worktree. Implement the request, run relevant
  checks, commit, then publish. Start/resume alone is enough if the user supplied
  only a topic and no concrete implementation request; ask for missing scope then.
- `$whiplash publish`: run relevant checks for unverified changes, commit intended
  files if needed, then run `python3 tools/workflow/chat.py publish` from this
  chat's worktree. Every delivered correction should do this automatically.
- `$whiplash preview <branch>`: run
  `python3 tools/workflow/chat.py preview "<branch>"`. This changes the desktop
  selection without merging anything.
- `$whiplash merge [branch]`: this explicit user command authorizes merging the
  specified branch (or this chat's branch) into main. Fetch both branches and use
  a separate integration worktree based on current `origin/main`. Merge normally,
  resolve conflicts, run appropriate checks, commit and push to main. Then set
  `tools/launcher/windows-release.json`'s `source_commit` to the tested merge SHA
  and `source_branch` to `main`, commit and push that manifest, and select main
  using the preview command. Never force-push main or delete branches by default.

State the branch and desktop preview result on completion. Do not imply that this
cloud session can modify the user's Windows computer directly. The Windows launcher
needs a one-time installation of the preview-aware script; thereafter the same
shortcut follows the manifest on `desktop-preview`.
