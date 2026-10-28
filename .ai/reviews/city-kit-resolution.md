# City kit review disposition

Independent review was split by author. Codex approved Claude's asset pipeline and regression tests. Claude reviewed the Godot integration twice and requested corrections; all HIGH/MED findings are now addressed, with no outstanding dispute. Individual reports are retained alongside this record.

- Route projection flattens endpoints before measuring horizontal distance. The authored slot layout is explicitly restricted to canonical Block Circuit; its non-crossing road spacing is independently tested. Other tracks can reuse CityKit assets with their own layouts.
- CityScenery checks course identity and all fourteen loadable assets before suppressing legacy towers. Unavailable kit data preserves the original scenery; the fallback has a regression assertion.
- Unknown/out-of-quarter/missing-mesh placements record explicit rejection reasons. Meshes resolve before acceptance, so metadata cannot count invisible placements. Mesh failures are cached, imported mesh type and material counts are checked, and bounds access avoids repeated catalog deep copies.
- The headless suite independently reads real mesh vertices, validates transformed footprint spacing and full-road clearance, checks all fourteen placed types, budgets, determinism, reverse invariance, unchanged course data and legacy survivors. Route sampling round-trips are checked too. Screenshots are a separate rendering check.
- Legacy obstacle collection intentionally includes the existing skyline and Crown. It scans only the scenery subtree, which contains no track ground mesh; the Crown receives an explicit footprint even under the dummy renderer.
- Capture paths are absolute and directory creation is checked. Runtime materials preserve the GLBs' double-sided setting. The hall roof's alternating steel/cavity slabs and narrow gaps are intentional and were inspected in Blender and Godot.
- Exchange-hall loading rollers now have distinct positions. Asset validation decodes actual vertex buffers, checks offsets/strides/ranges and finite declared bounds, and requires positive glow emission with finite strength. Eight corruption cases exercise these checks, including negative/fractional offsets and NaN values.

The asset source and tests received APPROVE verdicts. The integration's requested changes are resolved by the code and passing regression evidence, rather than another review round. No findings require a human exception.
