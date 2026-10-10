# Blackjack X-17: paint coverage and fine details

Follow-up to the accepted blueprint build (`18c96da`). The traced proportions,
wheel/axle/socket rig, and four-wheel physics are unchanged. Original production,
v2 and refined assets remain untouched. The existing blueprint catalog entry is
retained; this pass updates its native source and exported visual assets.

## Changes

- Exterior shell panels and folded truck fenders now use the three customizable
  paint channels. Protected armor is reserved for underside and mechanical parts.
  Independent raycast samples verify both truck doors, equipment panels,
  transition panels, coupe doors, both hoods, roof and protected underside.
- Reduction preserves material-boundary vertices instead of collapsing triangles
  across paint zones. LOD also preserves the skin supporting glass panels. The
  zero-weight exclusion follows Blender's native
  [collapse implementation](https://raw.githubusercontent.com/blender/blender/main/source/blender/bmesh/tools/bmesh_decimate_collapse.cc).
- Paint uses metallic 0.28, roughness 0.32, clearcoat 0.50 and coat roughness 0.16,
  avoiding the previous near-chrome washout. Protected materials receive no
  customization override or livery decal layer.
- 90 seated fastener heads remain 28 triangles each in the gameplay mesh, with
  dark contact disks. Four door handles have pockets, mounts, bridges and locks.
  Four coupe headlamp bezels and rugged lamp gaskets/edging remain protected metal.
- Two shallow angled hood pockets create actual recesses and occlusion, with
  seated grilles, slats and collars. Small-scale contact shading is enabled in
  the actual garage preview as well as the neutral QA scene.

## Verification

Gameplay body: 16,965 triangles. Body LOD1: 9,893 (58.3% of gameplay). The complete
stock Godot assembly is 37,421; with the optional supercharger it is 39,765. These
assembled counts include the six rendered wheels, axles, supports and accessories,
not merely the exported body. Each optimized hood intake retains 17.25 mm depth.

Blender independently verifies the gameplay and LOD shells are manifold, positive
volume and free of degenerate faces, and samples window triangle interiors for
intersection/floating. The LOD uses a slightly larger bounded glass clearance to
accommodate its faceted skin; it passes the same clearance gates. MeshLab reports
2,244 vertices / 4,484 shell triangles, one closed two-manifold component, no
holes or nonmanifold vertices/edges, and positive volume. Receipts are tied to
the current GLB/PLY SHA-256 hashes. Paint UV anisotropy: median 1.029, p95 1.170;
maximum 7.396 on small boundary triangles, so UV distortion is measured, not
represented as zero.

All-orange paint coverage and protected RGB/checker renders were visually
inspected, alongside hood/door close-ups and the actual garage preview. The
remaining uncolored metal is protected hardware. Native neutral front/side views
retain the accepted silhouette; quantitative roof/width/sill gates still pass.
Final `ak-test`: 4,256 checks passed, zero failed (61 core, 17 CPU, 670 refined,
3,508 blueprint). Forward+ QA completed without runtime errors. The old known
unseeded CPU-roster flake did not occur in the complete runs of this pass.
The physics script SHA-256 hashes match the pre-pass snapshot exactly.
Both scoped `ak-review` rounds: APPROVE (`20261010-210052.md`,
`20261010-210357.md`). First-round cleanup findings were addressed:
explicit paint regions, ring-derived underside indices plus a second protected
sample, cover-ramp documentation, triangle division warning, and garage rendering
only while visible. The second-round MED was fixed by applying the finish at the
override-creation hook, with complete initial-build and repaint property checks;
those final changes were regression-tested, not submitted for a third round.
The coordinate-frame concern is covered by a new explicit cancellation check:
POSE and the baked INVERSE_POSE must produce identity within 1e-6. This verifies
that landmark rays and the BVH share the level blueprint frame. The tall-cabin
secondary roof branch is now explicit and documented.

Local visible/orbiting garage check after two seconds warmup, 300 measured frames:
Forward+ mean 6.97 ms, Compatibility mean 6.94 ms on AMD Radeon integrated
graphics. Separate runs, display/VSync-influenced, not a mobile performance claim.
Compatibility completed without SSAO-related or script errors; it is not used
to certify Forward+-only decal/contact-shading quality. The existing system's
NVIDIA driver lookup warnings fell back successfully to AMD OpenGL.

The 11 semantic slots remain: Paint_Primary, Paint_Secondary, Paint_Accent,
Glass, Mirror, Rubber, Grille, Lights, Gunmetal, BrushedMetal, ArmorProtected.
Only Paint_* surfaces accept customization and decals.

## Evidence and reproducibility

Native source: `blender/blackjack_blueprint.blend`. Editable UV paint-ID guide:
`krita/blackjack_blueprint_paint_masks.kra`. Existing Material Maker procedural
metal/rubber/grille/wear maps are reused; no reconstruction or generated bitmap
is substituted for geometry.

Godot captures under `godot/assets/vehicles/models/blackjack/`:
`blackjack_blueprint_godot_side.png`, `_godot_three_quarter.png`,
`_godot_door_detail.png`, `_godot_hood_detail.png`, `_godot_paint_coverage.png`,
`_godot_paint_qa.png`, `_garage_side.png` and `_garage_three_quarter.png`.
The neutral images intentionally use grey/olive paint; the all-orange coverage
capture is the diagnostic for unpainted exterior leaks, not a new default livery.

Rebuild using the installed Blender with
`blender/build_blackjack_blueprint.py`, then open the resulting blend and run
`blender/validate_blackjack_blueprint.py`. Run `validate_blackjack_meshlab.py`
with pinned local `pymeshlab==2025.7.post1`; its GLB/PLY hashes must match the
successful Blender receipt. Regenerate the Krita guide from the native paint-ID
PNG. Run `ak-test`, then the Forward+ `blackjack_blueprint_visual_qa.tscn` scene.

Task-owned changes: geometry/builder/native validator, blueprint visual paint
override, blueprint tests and capture scene, native source/Krita guide, generated
blueprint GLBs/renders/QA receipts, plan and this report. Seven garage preview lines
are kept with the user's preexisting untracked garage file, not committed as an
unrelated whole-file addition. The scoped review compares those seven lines against
the exact pre-pass snapshot.

Recovery snapshot of the accepted assets:
`/tmp/blackjack-before-paint-detail.TzoeiL/`; previous source code is in `18c96da`.
