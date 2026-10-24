# Chat branches and desktop previews

Use one chat per focused change and one branch/worktree per chat. Continue fixes to
the same feature in the same chat. Separate worktrees let chats run concurrently
without sharing edited files or changing each other's checked-out branches.

## Commands in Codex

| Command | Result |
| --- | --- |
| `$whiplash <request>` | Start/resume this chat's branch and implement the request. |
| `$whiplash publish` | Commit tested changes, push the chat branch and select it for desktop preview. |
| `$whiplash preview <branch>` | Preview an already published branch again. |
| `$whiplash merge <branch>` | Explicitly authorize merging that branch into main. |

AGENTS.md applies the start/publish behavior to ordinary implementation requests
too, once this setup branch is merged. `$whiplash` is a repository skill command,
not a Windows terminal command or a desktop app slash command. New chats must open
this repository (and a revision containing the setup files). Until setup is merged,
select `chat/workflow-20261024` as the starting revision for new chats using it.

The command is backed by `tools/workflow/chat.py`. Python 3.9+ and Git are required
in the development environment, not on the Windows desktop. `start` uses
`CODEX_THREAD_ID`, or explicit `--chat-id`, to retain a chat's branch across turns.
It prints an absolute worktree path; all subsequent commands must use that path.
Its registry lives in the common Git directory, outside versioned game files.
Dirty files in another worktree stay untouched. A fresh environment can resume
an existing chat branch by checking it out before invoking start.

By default, new work starts at current main. For a user-requested dependency, use
`start "topic" --base "chat/dependency-branch"`. Separate unfinished branches are
not automatically combined. Published corrections must be committed and checked
before `publish` is run; it refuses a dirty worktree or a non-chat branch.

## Desktop behavior

`desktop-preview` is a small shared branch containing only
`tools/launcher/windows-release.json`. Publishing a chat pushes its game commit to
its own branch, then adds a manifest commit selecting that exact SHA. It never
merges the game's files into main. Updates use regular fast-forward pushes and
retry competing preview selections without force-pushing.

There is one shared desktop selection: the last published/selected branch wins.
The Windows launcher prints the selected branch and revision. Reopen the same
shortcut after publishing to test that version; an already running game does not
change underneath you. Ask `preview <branch>` to select a different task again.
Use `preview main` to see current main without merging a task.

The earlier Windows launcher follows only main, so install the preview-aware
version once in PowerShell (this URL works before this setup branch is merged):

```powershell
$installer = Join-Path $env:TEMP 'Install-WhiplashShift.ps1'
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Crazyh1803/WhiplashShift/chat/workflow-20261024/tools/launcher/whiplash-shift.ps1' -OutFile $installer
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Install
```

This updates the same desktop shortcut to use the preview channel. Keep the
original Godot engine and old game versions. Offline/update failures launch the
last working version. To set the shortcut to merged releases only, rerun the
installer with `-Install -Channel stable`. State and logs remain under
`%LOCALAPPDATA%\WhiplashShift`. Only reinstall the launcher when its code changes;
normal game corrections arrive through the manifest automatically.

## Finishing a task

Push tested corrections as you work. Do not merge main automatically, including
when a task looks finished. The user's explicit merge command is the authorization.
At that point merge current main and the task in a separate integration worktree,
resolve conflicts, check the combined result, and push main normally. Commit the
stable release manifest pointing to that checked merge commit, then select main
for preview. Keep the task branch unless deletion is requested.

The setup itself follows this rule: it is published on `chat/workflow-20261024`
and available for review without changing main. Merge it before expecting every
fresh main-based chat to discover the project skill and instructions.

## Checks

```sh
python3 -m unittest discover -s tools/workflow/tests -v
pwsh -NoProfile -File tools/launcher/tests/windows-updater.tests.ps1
```

Workflow tests use local bare Git repositories, exercise isolated/resumed chats,
branch publication, preview selection, dirty-worktree refusal and main protection.
Windows tests mock downloads and Godot while exercising the real updater logic.
