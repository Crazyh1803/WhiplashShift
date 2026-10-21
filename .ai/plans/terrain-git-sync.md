# Sync the accumulated terrain work

Stage all procedural road/scenery materials, physical relief, six contact layers,
UIDs, fixtures, tests and documentation. Stage only terrain integration in shared
vehicle, race and CPU scripts; preserve unrelated combat/difficulty edits locally.
Verify the exact staged tree in an isolated temporary checkout using ak-test.
Record review availability, commit on codex/track-visuals and push normally to
origin. Verify the remote branch hash equals local HEAD; do not merge or force-push.
