#!/usr/bin/env python3
"""Isolated chat worktrees and a desktop preview pointer; never updates main."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone


PREVIEW = "desktop-preview"


def git(repo, *args, text=None, check=True):
    result = subprocess.run(
        ["git", "-C", str(repo), *args], input=text, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip() if check else result


def validate_branch(repo, branch):
    if branch.startswith("-"):
        raise RuntimeError("Invalid branch name")
    git(repo, "check-ref-format", "--branch", branch)


def remote_head(repo, branch):
    validate_branch(repo, branch)
    result = git(repo, "ls-remote", "--heads", "origin", f"refs/heads/{branch}")
    return result.split()[0] if result else None


def start(repo, topic, chat_id, base="main"):
    if not chat_id:
        raise RuntimeError("CODEX_THREAD_ID is unavailable; provide a stable --chat-id for this chat.")
    validate_branch(repo, base)
    root = Path(git(repo, "rev-parse", "--show-toplevel"))
    common = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
    identity = hashlib.sha256(chat_id.encode()).hexdigest()[:12]
    registry = common / "whiplash-chats" / f"{identity}.json"
    if registry.exists():
        existing = json.loads(registry.read_text())
        if Path(existing["worktree"]).exists():
            branch = git(existing["worktree"], "branch", "--show-current")
            if branch != existing["branch"]:
                raise RuntimeError("This chat's worktree changed branches; inspect it before continuing.")
            return existing
        raise RuntimeError("This chat's recorded worktree is missing; recover it before starting another.")
    current = git(repo, "branch", "--show-current")
    if current.startswith("chat/") and current.endswith("-" + identity):
        branch, worktree = current, root
    else:
        slug = re.sub(r"[^a-z0-9]+", "-", topic.lower()).strip("-")[:45] or "task"
        branch = f"chat/{slug}-{identity}"
        git(repo, "fetch", "--no-write-fetch-head", "origin", f"refs/heads/{base}:refs/remotes/origin/{base}")
        worktree = common.parent.parent / ".whiplash-worktrees" / branch.removeprefix("chat/")
        worktree.parent.mkdir(parents=True, exist_ok=True)
        git(repo, "worktree", "add", "-b", branch, str(worktree), f"refs/remotes/origin/{base}")
    record = {"branch": branch, "worktree": str(worktree), "base": base, "chat_id": chat_id}
    registry.parent.mkdir(parents=True, exist_ok=True)
    registry.write_text(json.dumps(record, indent=2) + "\n")
    return record


def preview(repo, branch):
    revision = remote_head(repo, branch)
    if not revision:
        raise RuntimeError(f"Remote branch {branch} does not exist; publish it first.")
    release = {
        "source_commit": revision,
        "source_branch": branch,
        "channel": "preview",
        "published_at": datetime.now(timezone.utc).isoformat(),
    }
    blob = git(repo, "hash-object", "-w", "--stdin", text=json.dumps(release, indent=2) + "\n")
    tree = git(repo, "mktree", text=f"100644 blob {blob}\twindows-release.json\n")
    tree = git(repo, "mktree", text=f"040000 tree {tree}\tlauncher\n")
    tree = git(repo, "mktree", text=f"040000 tree {tree}\ttools\n")
    # This branch contains only a manifest, not merged game files. A regular
    # fast-forward push detects competing previews without force-pushing them.
    for _ in range(3):
        parent = remote_head(repo, PREVIEW)
        parents = []
        if parent:
            git(repo, "fetch", "--no-write-fetch-head", "origin", f"refs/heads/{PREVIEW}")
            parents = ["-p", parent]
        commit = git(repo, "commit-tree", tree, *parents, "-m", f"Preview {branch} at {revision[:8]}")
        pushed = git(repo, "push", "origin", f"{commit}:refs/heads/{PREVIEW}", check=False)
        if pushed.returncode == 0:
            return release
        if remote_head(repo, PREVIEW) == parent:
            raise RuntimeError(pushed.stderr.strip())
    raise RuntimeError("Another chat changed the preview repeatedly; retry preview publishing.")


def publish(repo):
    branch = git(repo, "branch", "--show-current")
    if not branch.startswith("chat/"):
        raise RuntimeError("Publish from this chat's chat/* worktree, never main or a shared checkout.")
    if git(repo, "status", "--porcelain"):
        raise RuntimeError("Commit the tested changes before publishing; the worktree must be clean.")
    git(repo, "push", "--set-upstream", "origin", f"HEAD:refs/heads/{branch}")
    return preview(repo, branch)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    commands = parser.add_subparsers(dest="command", required=True)
    begin = commands.add_parser("start", help="Start or resume an isolated worktree for this chat")
    begin.add_argument("topic")
    begin.add_argument("--chat-id", default=os.environ.get("CODEX_THREAD_ID"))
    begin.add_argument("--base", default="main", help="An explicitly chosen remote dependency branch")
    commands.add_parser("publish", help="Push committed changes and select them for desktop preview")
    select = commands.add_parser("preview", help="Select an existing remote branch for the desktop")
    select.add_argument("branch")
    args = parser.parse_args()
    try:
        if args.command == "start":
            result = start(args.repo, args.topic, args.chat_id, args.base)
        elif args.command == "publish":
            result = publish(args.repo)
        else:
            result = preview(args.repo, args.branch)
        print(json.dumps(result, indent=2))
    except (RuntimeError, OSError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
