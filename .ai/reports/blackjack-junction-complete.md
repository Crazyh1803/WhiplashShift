# Blackjack junction complete

The truck and coupe now meet through a continuous roof ramp, broad shoulder and
eased lower sill. The local redesign removes the waist pinch and roof notch,
re-seats the transition frame/rivets and supports the side pipe. Native Blender
source, repeatable builder, gameplay/LOD exports and hash-bound mesh receipts
are integrated from asset commits eda2483 and 38c418e.

## Verification
- Final merged export: full `ak-test` **4,781 passed, zero failed**. See
  `blackjack-junction-tests.log` for the tested SHA256 and suite summaries.
- Gemini integration review **APPROVE**, no findings. Capture helper also APPROVE;
  asset source reviewed independently in two Codex rounds, both APPROVE, with
  first-round validation findings corrected in round two.
- Native Blender 5.2.2 LTS validation and pinned PyMeshLab checks pass, with
  receipt hashes matching the final gameplay GLB. Gameplay body 17,143 triangles,
  LOD1 9,545; actual assembled runtime model 37,599 (within the 40,000 budget).
- Two fresh builds pass validation. Root independently compared the committed
  geometry with the rebuilt gameplay and LOD: 397 / 217 meshes have identical
  node transforms, materials, and triangle/UV data rounded to six decimals.
  GLB byte hashes differ; this does not represent a geometry change. See
  `blackjack-junction-rebuild-geometry.json`.
- All wheel arch positions, visual radii/tracks, preview pose and six attachment
  positions match the original metadata exactly. Physics and other cars unchanged.
- Source studio visual QA PASS; actual garage, paint, driving and end-swap visual
  QA PASS with no issues. Final runtime capture drives at 59.25 km/h and swaps to
  end B with a finite position. All images saved successfully. Blackjack's actual
  garage preview is left open; matched before/after captures are available in
  `.ai/captures/blackjack_junction/` and committed studio views in
  `.ai/qa/blackjack-junction/`.

## Remaining notes
- LOW: a faint existing paint-channel seam remains on the lower sill near source
  pixel 550. The current paint-ID PNG is rebuilt; the older editable Krita guide
  was retained because headless Krita export hung.
- Reserved left/right attachment origins are deliberately unchanged and now lie
  inside the wider body skin. Future side accessories will need surface offsets.
  Current Blackjack optional artwork is the hood supercharger.

No required junction work or review findings remain. Detailed authoring evidence
and limits are in `blackjack-junction-asset-handoff.md`.
