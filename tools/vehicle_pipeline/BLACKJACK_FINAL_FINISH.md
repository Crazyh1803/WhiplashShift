# Blackjack X-17: final finishing pass

Follow-up to `fc3433c`. The approved traced body proportions, wheel hardpoints,
axles and accessory sockets are retained. Original production, v2 and refined
assets remain intact. This pass updates the already integrated blueprint asset.

## Visual changes

- Three mirrored brush-guard rails have analytic rounded elbows, circular tube
  sections, two uprights and two seated bumper mounts. Budget reduction no longer
  crushes the guard. Native surface measurements check horizontal centers,
  section radii and mirror symmetry in both gameplay and LOD exports.
- Primary paint unifies the main shell and both roofs. Secondary paint belongs
  to the truck's inset service panels and folded fenders, the coupe's hood
  shoulders and lower-side blades. A narrow coupe shoulder ribbon is accent.
  Underside armor and all mechanical, glass, lamp and weapon surfaces remain
  protected. Independent raycasts verify material assignments.
- Metallic paint uses metallic 0.58, roughness 0.24, clearcoat 0.85 and coat
  roughness 0.12, in both the native source and Godot's paint-only overrides.
  A cached neutral HDR softbox panorama supplies actual specular reflections
  in the garage and QA studio. Each viewport owns its environment/world; the
  immutable sky is shared. AGX tone mapping, restrained ambient fill and existing
  contact shadows reveal folds and recesses. No fake baked highlight texture
  or protected-material override is added. This environment is Blackjack-only;
  other vehicles retain their original ambient/color preview environment.
- Blackjack's three channels offer exactly twelve named metallic swatches:
  Obsidian, Graphite, Titanium Silver, Pearl Ivory, Midnight Blue, Cobalt,
  Racing Red, Burgundy, British Racing Green, Recon Olive, Ember Copper and
  Champagne Gold. The factory scheme is copper/obsidian/gold. Other vehicles
  retain unrestricted color pickers. Existing custom hex colors are displayed
  as SAVED CUSTOM and are never quantized or rewritten just by loading a garage.
  Choosing a swatch changes only that channel using the existing save path.
- LOD omits subpixel rivet heads/contact disks while retaining the entire guard.
  Window-supporting shell faces and their adjacent ring are protected during
  collapse. Glass is seated at the same clearance as gameplay, not floated
  farther out to conceal reduction errors. Gameplay retains all 90 fasteners,
  handles, recessed hood pockets and protected headlight bezels.
- Native windshield seals and wipers also retain their complete profiles in
  both exports. An unshaded-glass diagnostic traced visible triangular glazing
  artifacts to these collapsed trims, not to glass intersections or reflections.
- The changed seam network exposed a collapsed roof-corner UV island. Local
  outlier seams and native re-unwrapping repair the optimized shells while
  retaining the editable subdivision cage and large door/hood/roof islands.
  The native gate now rejects nonfinite ratios, maximum anisotropy above four
  or a 95th percentile above two, rather than merely reporting distortion.

The reflection environment follows Godot's distinction between visible
background and sky-driven ambient/reflected light:
[Environment documentation](https://docs.godotengine.org/en/latest/tutorials/3d/environment_and_post_processing.html).

## Verification

Gameplay body: 17,081 triangles; LOD body: 9,699 (56.8%). The complete Godot
stock assembly is 37,537; the optional supercharger brings it to 39,881. These
counts include six rendered wheels, axles, supports and accessories. Gameplay
retains all 90 fastener heads; LOD omits their subpixel detail. The two hood
intakes retain 17.25 mm geometric recesses.

Blender checks gameplay/LOD shell manifoldness, positive volume, degenerate
faces, glass triangle interiors and guard geometry. Maximum mirror error is
1.69e-7 source units, maximum horizontal rail-center error 6.71e-8. All glass
samples have positive clearance; maximum is 0.00448 source units, below the
0.010 float gate. MeshLab confirms one closed two-manifold component with
2,244 vertices / 4,484 shell triangles, no holes/nonmanifold vertices or edges,
positive volume and correct vehicle scale. Native and MeshLab receipts are
tied to the final GLB/PLY hashes. Gameplay paint UV anisotropy: median 1.026,
p95 1.356, maximum 3.392. LOD: median 1.001, p95 1.109, maximum 3.711. Both
pass the independent distortion gate after the native atlas repair.

`ak-test`: 4,303 passed, zero failed (61 core, 17 CPU, 670 refined, 3,555
blueprint). The tests cover the exact twelve swatches, factory paint, unchanged
legacy colors and reload behavior, other-vehicle controls, no-op reselection,
reflection sky, paint/protected material behavior, guard/trim preservation,
wheel/module/accessory seating, complete triangle budget and physics parity.
The fixture uses in-memory customization snapshots; QA does not write user
profile data. Physics script checksums match the pre-pass snapshot exactly.

Forward+ captures and actual garage checks completed without script/runtime
errors; blue/black/gold and red/graphite/silver finishes, guard front, protection
diagnostics and garage UI were inspected. After two seconds warmup, 300-frame
orbit means were 6.99 ms Forward+ and 6.94 ms Compatibility on local AMD
integrated graphics, in separate runs. These VSync/display-influenced timings
are not a mobile performance claim. Compatibility used AMD OpenGL after the
existing NVIDIA lookup warnings; Forward+-only decals/SSAO are not certified
by its smoke test.

First scoped `ak-review`: APPROVE (`20261011-063933.md`). Its LOW cleanup
findings were addressed: softbox/chip caching, no-op swatch selections, the
typed picker constructor, tube-resolution documentation and this report's
verification totals. Second scoped `ak-review`: APPROVE (`20261011-065740.md`).
Its MED environment-scope finding was fixed by gating the HDR environment to
Blackjack and testing switches away/back. Follow-up LOW fixes skip hidden
swatch updates, test the loading save guard, explicitly finalize export UVs
(no polygon-count shortcut), reject missing materials and sample guard depth
as well as height. These last changes are verified by regression/native checks;
no third review was requested.

The eleven semantic slots remain Paint_Primary, Paint_Secondary, Paint_Accent,
Glass, Mirror, Rubber, Grille, Lights, Gunmetal, BrushedMetal and ArmorProtected.
Only Paint_* surfaces accept customizable colors and projected liveries.
The four-wheel collision, mass, suspension, steering, drivetrain and grip code
are not edited by this pass; the middle wheels remain visual-only.

## Sources and evidence

Editable native source: `blender/blackjack_blueprint.blend`; UV/channel guide:
`krita/blackjack_blueprint_paint_masks.kra`. Existing Material Maker metal,
rubber, grille and wear maps are reused. No image-to-3D reconstruction is used.

Generated assets and captures are under
`godot/assets/vehicles/models/blackjack/`: gameplay/LOD GLBs, neutral Blender
side/three-quarter/front renders, Godot side/three-quarter and detail views,
paint-protection diagnostics, straight-on guard image, blue/black/gold and
red/graphite/silver metallic showcase images, and actual garage preview/UI.
Neutral grey/olive QA colors are diagnostic, not the factory livery.

Rebuild with installed Blender 5.2.2 LTS and `build_blackjack_blueprint.py`;
validate the saved source with `validate_blackjack_blueprint.py`. Run pinned
local PyMeshLab 2025.7.post1 through `../validate_blackjack_meshlab.py` only
after the successful native receipt: GLB/PLY hashes must match. Regenerate the
Krita guide from the paint-ID PNG. Run `ak-test` and the Forward+ blueprint QA
scene, then inspect the actual garage. Compatibility checks are not a claim
that Forward+-only decals/SSAO are supported on that renderer.

Changes include the geometry/builder/validator, paint override, palette/picker
and studio helper, tests/QA capture script, source/Krita guide, generated
blueprint assets/receipts, plan and this report. Small scoped garage/catalog
hunks remain in the user's already untracked integration files; those files
are not committed wholesale. Review compares them to exact pre-pass snapshots.
`blackjack_final_finish_integration.patch` records just those already-applied
hunks; its reverse check matches the working files. Do not reapply it here.
The tested workspace still depends on the user's preexisting untracked garage,
catalog and related integration files; this asset commit is not claimed to be
a self-contained clean-checkout game build. No save schema or user profile
file is modified by QA.

Recovery snapshot: `/tmp/blackjack-before-final-finish.NHFGgO/`; pre-pass code
is in `fc3433c`.
