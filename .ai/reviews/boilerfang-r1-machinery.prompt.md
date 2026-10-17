You are the REVIEWER in an agent-kit repo, running headless. Do NOT modify any files and do NOT run builds.
The diff is below. You have read access to the repo; open files only when the diff alone isn't enough context.
Follow the repo's AGENTS.md conventions.

Check these, in priority order:
1. Correctness and logic bugs
2. Edge cases, error handling, null/empty/boundary values
3. Whether the tests actually exercise the change
4. Violations of the repo's AGENTS.md conventions
5. Performance only where it matters (per-frame code, hot loops, allocations in update paths)
6. For Blender scripts: idempotence, hard-coded paths, and missing `report(...)` output

Skip style nits a linter or formatter would catch.

Your final answer must be EXACTLY this format, with no preamble, no praise, and no diff summary:

VERDICT: APPROVE | CHANGES_REQUESTED
FINDINGS:
- [HIGH|MED|LOW] path/file.ext:line — problem — suggested fix

If there are no findings, write `FINDINGS: none`. Use CHANGES_REQUESTED only if there is at least one HIGH.

File-only review kit. Do NOT run shell commands; use only the file-read tool.
Read this unified diff file in full: /home/crazyh/.codex/worktrees/deadbolt-graphics/Whiplash/.ai/reviews/boilerfang-r1-machinery.diff
It is the delta against eb49d0a, an unmodified renamed fork of the proven Ramjet Blender builder (template baseline). Files in this chunk:
- tools/vehicle_pipeline/blender/boilerfang_machinery.py
- tools/vehicle_pipeline/blender/boilerfang_details.py
Context: Blender 4.0 headless builder for a steam-punk vehicle (X long, +Z up, ground z=0, speedster +X, truck -X). Do not flag items listed in tools/vehicle_pipeline/BOILERFANG_BLUEPRINT.md as interpretation or known limits. Read the full source files only when the diff is not enough.
