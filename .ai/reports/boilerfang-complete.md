# Boilerfang 88 complete

Rebuilt from steam-punk.jpg as a boiler truck with cowcatcher plow opposite an
ornate Victorian speedster. Curved cab, boiler, smokestack, brass/copper piping,
valves, gauges, rivets, spiked truck tires and wire speedster wheels are included.
The paired central flywheel/belt mechanisms remain body artwork. Four physical
wheels, saved tuning, hardpoints, collider, drive and swap behavior are preserved.
Three paint channels retain fixed brass, copper, glass, rubber and lamp materials.

Native Blender source, repeatable builder, gameplay GLB, two LODs and Godot import
settings are committed. The measured visual radii are A0.256/B0.348 m; source hub
origins determine visual track independently of physical hardpoints.

Validation:
- Full ak-test: 4,564 passed, zero failed before the final hardware refinements.
- Final gameplay export: Boilerfang68 + consolidation95 + Nightshift46 + Ramjet47
  = 256 affected checks passed. A former symmetric tire-bounds assertion was
  corrected to check the radial center because outboard studs shift axial bounds;
  Gemini checked the assertion's coordinate math (boilerfang-hub-assertion-review.md).
- The final tested and merged GLB SHA256 is identical:
  1c98257483df552d817c74f6f8527b62193f735e4a4d09372e1d226f27403880.
- Asset numeric validation: 44 checks PASS. Independent rebuild: 287 objects,
  zero vertex/surface deviation; all three GLBs identical across builds.
- Triangles: gameplay48,116 / LOD1 35,492 / LOD2 17,842.
- Gemini integration review APPROVE in both rounds. Asset source reviewed in five
  chunks, two rounds; HIGH/MED resolved or justified in boilerfang-asset-handoff.md.
- Final source full-body, close-up and LOD visual QA PASS. Final actual Godot
  visual QA PASS, no issues: garage from both ends, custom paint, driving59.34km/h
  and a finite End B swap; all captures saved successfully.
- CPU regression: Boilerfang and Ramjet complete over two laps with swaps and
  zero recoveries.

The Boilerfang customization garage preview is open. No required work or open
questions remain. Minor limits are recorded in boilerfang-asset-handoff.md:
level skylight boxes on a falling roof, broad speedster fenders, solid interior
under glass, flat PBR colours and source-sheet interpretation/measurement limits.
Raw review prompts/diffs were removed from the current tree to avoid duplicating
source; their reviewed snapshots remain in Git history. Verdict records are kept.
