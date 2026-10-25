# Smoke, oil and impact refinement

User correction: keep the full visible smoke stream, keep the sprayer's view usable, make oil black and viscous, and replace toy-like weapon impacts with more grounded VFX.

- Claude asset lead: native Godot VFX pass in race_item_art.gd, particle_smoke.gdshader, item_oil.gdshader and camera_rig.gd (plus small dedicated shader/helper if needed). Restore owner smoke visibility; use a smooth per-pixel camera-to-player sight corridor / near-camera fade only on owner smoke, including particle stream. Preserve broad spray quantity. Rival smoke remains dense. Black wet oil with subtle thick ripples and dark droplets, no rainbow emission. Normal-directed hot sparks, dark ballistic debris and textured dust/soot explosions with a short flash; remove weapon-colored star confetti and glowing shock rings. Keep pickup feedback separate.
- Codex lead: integrate the impact call, independently update smoke visibility/ownership and impact tests, render the effects and inspect owner/rival/swap smoke views, oil and impact sequences. No physics, damage, ammo, audio or pickup changes.
- Run focused ak-test for changed effects, item rules, attachments and camera; review Claude-authored VFX independently with Codex and lead integration/tests with Claude. Fix findings, publish this chat branch and verify the remote manifest.

Use existing textures and native meshes/shaders for transient VFX. Keep particles/effects bounded and clear safely on reset/results/recovery. No new dependencies, no assets/final promotion, no main merge.
