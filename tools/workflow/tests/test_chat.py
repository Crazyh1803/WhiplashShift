import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("chat_workflow", Path(__file__).parents[1] / "chat.py")
workflow = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(workflow)


class ChatWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="whiplash chat tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote.git"
        subprocess.run(["git", "init", "--bare", "-b", "main", str(self.remote)], check=True, capture_output=True)
        self.repo = self.root / "checkout"
        subprocess.run(["git", "clone", str(self.remote), str(self.repo)], check=True, capture_output=True)
        workflow.git(self.repo, "config", "user.name", "Workflow Test")
        workflow.git(self.repo, "config", "user.email", "workflow@example.com")
        (self.repo / "game.txt").write_text("stable\n")
        workflow.git(self.repo, "add", "game.txt")
        workflow.git(self.repo, "commit", "-m", "Initial game")
        workflow.git(self.repo, "push", "origin", "main")
        self.main = workflow.remote_head(self.repo, "main")

    def begin(self, identity="chat-one", topic="Fix lights"):
        return workflow.start(self.repo, topic, identity)

    def change(self, worktree, name="correction.txt"):
        Path(worktree, name).write_text(name + "\n")
        workflow.git(worktree, "add", name)
        workflow.git(worktree, "commit", "-m", name)
        return workflow.git(worktree, "rev-parse", "HEAD")

    def manifest(self):
        head = workflow.remote_head(self.repo, workflow.PREVIEW)
        return json.loads(workflow.git(self.repo, "show", head + ":tools/launcher/windows-release.json"))

    def test_new_chats_are_isolated_and_same_chat_resumes(self):
        (self.repo / "uncommitted.txt").write_text("keep me")
        one = self.begin()
        two = self.begin("chat-two", "Another feature")
        resumed = self.begin(topic="Updated topic")
        self.assertEqual(one, resumed)
        self.assertNotEqual(one["branch"], two["branch"])
        self.assertNotEqual(one["worktree"], two["worktree"])
        self.assertEqual(workflow.git(self.repo, "branch", "--show-current"), "main")
        self.assertEqual((self.repo / "uncommitted.txt").read_text(), "keep me")
        self.change(one["worktree"])
        self.assertFalse(Path(two["worktree"], "correction.txt").exists())

    def test_publish_pushes_task_and_manifest_without_touching_main(self):
        task = self.begin()
        revision = self.change(task["worktree"])
        release = workflow.publish(task["worktree"])
        self.assertEqual(release["source_commit"], revision)
        self.assertEqual(workflow.remote_head(self.repo, task["branch"]), revision)
        self.assertEqual(self.manifest()["source_branch"], task["branch"])
        self.assertEqual(workflow.remote_head(self.repo, "main"), self.main)
        preview = workflow.remote_head(self.repo, workflow.PREVIEW)
        self.assertEqual(workflow.git(self.repo, "ls-tree", "-r", "--name-only", preview),
                         "tools/launcher/windows-release.json")

    def test_preview_switches_between_branches_and_main(self):
        one, two = self.begin(), self.begin("chat-two", "Second feature")
        for task in (one, two):
            self.change(task["worktree"])
            workflow.publish(task["worktree"])
        workflow.preview(self.repo, one["branch"])
        self.assertEqual(self.manifest()["source_branch"], one["branch"])
        workflow.preview(self.repo, "main")
        self.assertEqual(self.manifest()["source_commit"], self.main)
        self.assertEqual(workflow.remote_head(self.repo, "main"), self.main)
        head = workflow.remote_head(self.repo, workflow.PREVIEW)
        self.assertEqual(workflow.git(self.repo, "rev-list", "--count", head), "4")

    def test_dirty_or_non_chat_worktrees_cannot_publish(self):
        with self.assertRaisesRegex(RuntimeError, "chat/\\*"):
            workflow.publish(self.repo)
        task = self.begin()
        Path(task["worktree"], "uncommitted.txt").write_text("not checked yet")
        with self.assertRaisesRegex(RuntimeError, "Commit the tested changes"):
            workflow.publish(task["worktree"])
        self.assertIsNone(workflow.remote_head(self.repo, task["branch"]))
        self.assertIsNone(workflow.remote_head(self.repo, workflow.PREVIEW))

    def test_failed_task_push_does_not_overwrite_remote_or_preview(self):
        task = self.begin()
        revision = self.change(task["worktree"])
        workflow.publish(task["worktree"])
        outsider = self.root / "another worktree"
        workflow.git(self.repo, "worktree", "add", "--detach", str(outsider), revision)
        remote_revision = self.change(outsider, "remote.txt")
        workflow.git(outsider, "push", "origin", f"HEAD:refs/heads/{task['branch']}")
        self.change(task["worktree"], "local.txt")
        with self.assertRaises(RuntimeError):
            workflow.publish(task["worktree"])
        self.assertEqual(workflow.remote_head(self.repo, task["branch"]), remote_revision)
        self.assertEqual(self.manifest()["source_commit"], revision)
        self.assertEqual(workflow.remote_head(self.repo, "main"), self.main)

    def test_explicit_dependency_base_is_preserved(self):
        parent = self.begin()
        revision = self.change(parent["worktree"])
        workflow.publish(parent["worktree"])
        child = workflow.start(self.repo, "Dependent correction", "chat-child", parent["branch"])
        self.assertEqual(workflow.git(child["worktree"], "rev-parse", "HEAD"), revision)
        self.assertEqual(child["base"], parent["branch"])

    def test_missing_chat_identity_or_preview_branch_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "stable --chat-id"):
            workflow.start(self.repo, "Topic", None)
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            workflow.preview(self.repo, "chat/missing")
        self.assertIsNone(workflow.remote_head(self.repo, workflow.PREVIEW))


if __name__ == "__main__":
    unittest.main()
