# Weapon detail and owner-safe smoke

Base: main plus the current combat preview (92b816a), preserving recent audio and mystery crates.

- Claude asset lead via ak-delegate: Blender-authored twin gun/launcher models, restrained Helix biomechanical variant, named barrel sockets, generation script, source .blend and GLB, numeric QA and renders. Asset generation only, no assets/final promotion.
- Codex integration: vehicle-specific attachment positioning, consistent muzzle/projectile origins, retain weapon cues, trails, hits and warnings. Use mount profiles grounded in vehicle artwork bounds, both active ends.
- Claude escalation: diagnose smoke owner gameplay and camera obscuration. Codex applies owner immunity plus rendering that leaves opponent smoke effective, including stream particles.
- Independent tests for changed gameplay and attachments; headless item/camera/vehicle checks via ak-test, rendered visual QA, ak-review. Publish tested chat branch to desktop preview. No merge into main.

Keep existing pickup/audio behavior and physics. No dependencies. Preserve unrelated restored checkout edits by working in this chat worktree.
