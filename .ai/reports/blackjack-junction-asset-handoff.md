# Blackjack central junction: asset handoff

Branch `asset/blackjack-junction`. Commits: `eda2483` (rebuild) plus the follow-up
commit holding review fixes, final rebuild, receipts and this report (`git log`).

## What changed (junction only)
- Bounded region: source pixels **469..596** (~0.52 m of 2.4 m, between the truck
  wheel arch and the coupe door). Stations strictly inside are now authored
  smoothstep curves (`blackjack_blueprint_trace.py`: `JUNCTION_PX`, `_junction_row`,
  `LEGACY_STATIONS`); both bounding rows and everything outside keep the hand trace.
- Fixed: roof notch (old 70→76→80→93→110→123→133→126), staircase sill
  (157→…→216 in kinks), hourglass waist (half-width 79→52→83). Now: monotone
  roof ramp (drop 58 px, max slope 34°), eased sill, level flank (belt half-width
  range 1.2 px, 77.0→75.8 px), shoulder creases faded across the region.
- Removed the stray triangular quarter-light; transition inset frame/rivets now
  follow the eased roof/belt lines; side pipe rides the flank with two brackets;
  tank/straps hang from the eased sill.
- Gates: legacy roof/width/sill gates skipped only inside the region; new
  `junction_measurements` (roof/sill monotone, slope < 40°, slope change < 14°,
  no waist pinch, flank range < 8 px, both endpoints sampled) stored in
  `blackjack_blueprint_qa.json -> junction_region`.

## Rig contract (unchanged)
Wheel arch centres, radii, tracks, preview pitch/height, and all six part sockets
are byte-equal in `blackjack_blueprint_dimensions.tres` (unchanged file). Sockets
are pinned constants in the builder. NOTE: `left`/`right` were sampled on the old
pinched waist (|z| 0.6018 m game); the flank is now wider there, so those two
sockets sit ~5 cm inside the skin. Rim/tire/supercharger GLBs and PBR files are
HEAD-identical (reverted after rebuild; byte noise only).

## Counts
Body 17,143 tris (was 17,081), LOD1 9,545, assembled minimum 33,279; 11 semantic
materials. Paint UV p95 1.29 / LOD 1.11, max 3.39 / 3.44 (gates pass).

## Evidence
- Blender **5.2.2 LTS** (official tarball, sha256 verified, installed in
  `~/.local/share/blender-bin/`; system `/usr/bin/blender` is 4.0.2, not used).
- Build, `validate_blackjack_blueprint.py` (exit 0, `validation_passed` true),
  PyMeshLab 2025.7.post1 in a venv (1 closed manifold component, 4,484 tris);
  receipts hash-bound to the committed GLB.
- Two independent full builds: identical shell PLY, QA JSON, paint-ID PNG,
  dimensions; GLBs differ in bytes only (exporter noise), same triangle counts.
- Reviews (Codex, via ak_ask file-only prompt; `ak-review` refused the 33k-line
  diff): round 1 APPROVE with 2 MED (endpoint sampling, sill slope gates) + 1 LOW,
  all fixed; round 2 APPROVE. Files `.ai/reviews/20261018-blackjack-junction-source-r{1,2}.md`.
- ak-look: before critique FAIL (2 HIGH: waist pinch, roof notch/sill; 1 MED stray glazing);
  after PASS. Images in `.ai/qa/blackjack-junction/{before,after}/`
  (side, three-quarter, top, and `*_junction_*` close-ups via
  `render_blackjack_junction.py`).

## Limits / for Codex
- LOW: faint paint-channel step on the lower sill near x≈550 (existing
  Paint_Secondary rail rule starts at px>550; paint semantics left unchanged).
- Krita guide `krita/blackjack_blueprint_paint_masks.kra` NOT regenerated
  (headless Krita hung); paint-ID PNG is current. Regenerate if needed.
- Gemini ak-scout unavailable; not used. No GDScript edited. Tests asserting the
  old central roof/width/sill values, the `Glass_CoupeQuarter_*` objects, or
  `Drivetrain_ExternalPipe` positions may need updating; `left`/`right` socket
  values are unchanged. Godot re-import of the changed GLBs is needed.
