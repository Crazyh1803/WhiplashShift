# Ramjet K-6 complete

The saved Dodge Ram D150 / Conquest TSi blueprint is integrated into the garage,
player and CPU paths, with its stepped roof, closed pop-up light covers, hood
scoop, Ram crosshair grille, seated glass, detailed distinct wheels and three
paint channels. Native source, repeatable builder, gameplay GLB and two LODs are
committed. Physical tuning, hardpoints, tire radii and collider are unchanged.
The authored half-track of 0.86 m is picked up from the hub geometry automatically.

Validation:
- Full ak-test: 4,483 passed, zero failed before the final artwork refinements.
- Final model: Ramjet47 + Nightshift46 + consolidation87 = 180 affected checks
  passed. The tested GLB SHA256 matches the merged file exactly:
  2f14146f2938225337d99d32253539f5820bd3c389c1c5127ec85bb555f31a7a.
- Asset numeric validation PASS (85 checks); independent rebuilds have zero
  vertex/surface deviation and identical gameplay GLBs. 33,932 / 27,034 / 20,568
  triangles across the three levels.
- Gemini integration review APPROVE; both asset-source rounds APPROVE, no findings.
- Studio, close-up, blueprint overlay and LOD verification PASS. Final actual GPU
  review PASS, no issues: both garage angles, custom paint, driving57.95km/h and
  a finite End B swap. All captures saved successfully.

The Ramjet garage preview is open. No required Ramjet work remains. Minor source
and visual limits are recorded in ramjet-asset-handoff.md (closed static pop-ups,
small source-drawn coupe glass, flat PBR, minor trim/shading notes).
