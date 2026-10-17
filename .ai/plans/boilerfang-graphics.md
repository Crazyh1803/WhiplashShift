# Boilerfang 88 production artwork

1. Claude asset lead rebuilds from godot/assets/vehicles/steam-punk.jpg in the
   reused asset worktree, branch asset/boilerfang-graphics. Preserve the heavy
   cowcatcher/plow truck vs ornate speedster, curved cab roof, boiler, smokestacks,
   brass piping, gauges/rivets, wire wheels and rugged truck wheels. Keep the
   central flywheel/belt-drive silhouette as visible body-mounted mechanism;
   retain the established four physical wheels and saved handling.
2. Deliver an idempotent headless Blender builder, native source, gameplay GLB,
   meaningful LODs, numeric validation, blueprint/full-body/close-up visual QA.
   Prefer symmetric paired mechanisms where the AI sheet is ambiguous, and
   document that interpretation. Do not edit existing vehicles' artwork.
3. Codex integrates the existing authored-hub rig and three paint channels.
   Permit blueprint-derived display radii independent of physical tire radii;
   preserve tuning-owned collider, hardpoints, mass, drive and swap behavior.
   Extend shared art/paint/hub/physics/player/CPU and GPU regression checks.
4. Full ak-test, source and integration Gemini review (max two actual code-review
   rounds), fix HIGH/MED or record evidence-backed dismissals/tiebreak. Rebuild
   comparison and relevant final visual checks must pass. Stop expanding checks
   after they pass; no long sleeps or unchanged-image review loops. Commit source,
   artwork and validation, finish with actual Boilerfang garage preview available.

## Runtime checkpoint

Added a default-preserving display-radius getter and Boilerfang paint/catalog/
factory/studio wiring. Shared tests now check actual wheel geometry against the
configured display radius, static ground contact, retained physical hardpoints,
and visible body-mounted central mechanism. Nightshift46 + Ramjet47 + CPU17 pass.
Blueprint display-radius values will be populated from the delivered model metadata.
