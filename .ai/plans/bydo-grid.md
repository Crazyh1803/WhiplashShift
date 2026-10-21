# Bydo-Grid environment pass

Apply the supplied R-Type / 1980s retrofit art direction to the existing Godot code-native track visuals. Preserve all course geometry, collision, handling and surface IDs; existing unrelated working changes remain intact.

1. Save the master palette, material rules, modular kit and vehicle direction in docs/art-direction/bydo-grid.md.
2. Retheme the shared road shader to bone ceramic panels and diagonal carbon curbs, retaining readable special driving surfaces. Add stepped local lighting.
3. Centralize void environment/fog and local illumination; add compact cyan/amber guide lights around the entire course. Convert the scenery sample into ribbed mechanical silhouettes with coral sinew using dedicated normal/roughness textures and SSS.
4. Verify collision invariants, material calibration, no directional sunlight, beacon coverage and stable opaque spine silhouettes. Run ak-test, rendered captures and ak-look, then ak-review (maximum two rounds).

Vehicle geometry retrofits and production authored textures are follow-up asset-lane work. This pass uses procedural materials and code-native geometry on the current code feature branch.
