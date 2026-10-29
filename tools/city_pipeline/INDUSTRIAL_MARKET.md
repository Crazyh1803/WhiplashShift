# Industrial market realism benchmark (candidate, not promoted)

One Redline Ramen stall + vendor + customer, built for `docs/art-direction/inhabited-city-benchmark.md` and the frozen interface in
`.ai/plans/industrial-market-execution.md`. Candidate only: nothing in `assets/final/`, the kit, streets, neighborhood, workshop or any vehicle was touched.

## Outputs
| Path | What |
|---|---|
| `godot/assets/city/candidates/industrial_market/{redline_shop,ramen_vendor,ramen_customer}.glb` | three separate metre / Y-up / front -Z GLBs, one static mesh each, embedded PBR textures, `COLOR_0` = AO x wear, no lights/cameras/colliders/animation |
| `.../benchmark_manifest.json` | version 1, `candidate-review`: tris, AABB, ordered surfaces, texture slots/sizes, placements, `vehicle_slot`, `review_targets`, light anchors (data only), interaction points, costs, limitations |
| `assets/generated/industrial_market/` | `*.blend` sources, `*_build.json` measured records, `texture_provenance.json`, all source texture PNGs (`textures/<asset>/<material>_{albedo,orm,normal}.png`) |
| `assets/previews/industrial_market/` | studio renders re-imported from the exported GLBs (see below) |

## Rebuild
```
ak-blender tools/city_pipeline/build_industrial_market.py                 # textures -> geometry -> AO -> GLB/.blend -> manifest (~20 s)
ak-blender tools/city_pipeline/industrial_market_shots.py -- --set all    # previews (neutral + night)
ak-blender tools/city_pipeline/build_industrial_market.py -- --manifest-only
python tools/city_pipeline/validate_industrial_market.py                  # stdlib only
```
Flags: `--only vendor,customer,shop`, `--fast` (256 px textures / fewer AO rays for iteration; do not ship). Everything is deterministic (fixed seeds).
People only (never touches `redline_shop.glb`): `ak-blender tools/city_pipeline/build_industrial_market.py -- --only vendor,customer`; clay anatomy previews: `industrial_market_shots.py -- --set people --clay`.
The retained base-human source is prepared once by `ak-blender tools/city_pipeline/industrial_market_base_source.py` (downloads the CC0 bundle, checks sha256, keeps only the used meshes).
Modules: `industrial_market_textures.py` (numpy PBR recipes for cloth/hair/leather/shop), `_common.py` (bmesh builders, UV, ray-cast AO, materials, GLB export),
`_humans.py` (base body load/orient/landmarks), `_rig.py` (capsule skinning, IK/FK pose, finger curls), `_figure.py` (garment shells, boots, hair, skin UV, eyes, pose), `_skin.py` (skin + eye texture bake),
`_people.py` (person assembly + thick-sheet helper), `_dress.py` (draped apron/collars/headband), `_shop.py` + `_shop_detail.py` (stall, sign, menu, food), `_render.py` / `_shots.py` (QA renders).

## Layout contract (Godot world, metres)
Shop origin at the shop centre on the road plane; facade at z -2; floor/sidewalk top y 0.15; sidewalk to z -4.7; counter top y 1.20 (x +-2.37, z -1.5..-2.08).
- vendor `[0.40, 0.15, -1.33]` yaw 0; customer `[0.66, 0.15, -2.30]` yaw 180 (faces the shop); bowl centre `[0.55, 1.20, -1.78]`.
- Vehicle slot: centre `[-3, 0, -7.5]`, reserved strip z -5..-10, curb z -4.7 (the lead places the approved BLACKJACK X-17 there).
- Interaction: both right hands hold the bowl rim from opposite sides (vendor wrist `[0.66,1.25,-1.71]`-ish, customer wrist `[0.45,1.25,-1.84]`-ish; exact values in the manifest);
  vendor's left hand rests flat on the counter. `validate_industrial_market.py` checks mesh vertices of both people are within 3 cm of the bowl wall, soles sit at y 0.15 and no body penetrates the counter carcass.

## Construction
- **Anatomy (replaces the first delivery's primitive tubes / painted displaced-sphere head):** the official Blender Human Base Meshes v1.4.1 (CC0) realistic adult male (vendor) and female (customer) bodies at multires level 0 (10.6k quads each, real eyelids/eye sockets/nose/lips/ears, five-finger hands, base eyeball spheres). Source, license, download URL, bundle sha256 and the retained blend (`assets/generated/industrial_market/sources/`, ~1 MB, only the two bodies + eyes) are recorded in `PROVENANCE.json` and the manifest `human_base` block; the validator checks them.
- **Pose:** own capsule-bone linear-blend skinning (no armature/add-on). Weights depend only on the rest position, so garments/boots/hair built on the rest anatomy deform with it. 2-bone IK puts the wrists at the bowl/counter points, legs IK to the foot targets (weight leg nearly straight, sole lifted 2 cm for the boot sole), spine lean, head tilt, per-finger curls and thumb direction; the pose is baked into the exported vertices. Eyeballs are turned towards the other person's face.
- **Clothing:** garment shells are offset copies of the base body surface (ease + procedural folds at elbows/knees/hem), boundaries snapped to clean hem / cuff / neck planes with a thickness rim; covered body faces are removed (3-ring margin kept). Boots/shoes are lofted from foot/shin cross-sections measured on the base mesh (flat 2 cm sole with welt, enclosed heel/toe, customer shaft). Hair is a clumped scalp shell with a hairline curve (+ ponytail tube). The apron, pockets, zip and flaps are ray-draped onto the clothed mesh with thickness; collar, hood roll, headband with knot.
- **Skin / eyes:** smart-project UVs per group (head / hands / rest) packed into one 1024 atlas square layout with an eye tile; the albedo is baked by evaluating 3D functions at each texel's rest-pose position (brows, lash lines, lips, nostrils, stubble/freckles, cheek warmth, nails), so features follow the real mesh. Skin normal map is deliberately subtle (typical slope 0.045, material normal strength 0.7); ORM roughness varies by region (lips/forehead/nails shinier, eyes 0.10).
- **Shop:** counter-wide H-columns on grouted plinths with base plates, anchor bolts + double nuts, base gussets, splice plates, bumper collar; header I-beam with end plates, web stiffeners, knee braces; roof/parapet; corrugated cladding with lap joints/rivets, bolted replacement panel; worn counter (rolled lip, ribs, toe kick, repaired lower panel); sliding door; cooking line (stock pot, noodle boiler, hood + roof duct, gas cylinder + hose); electrics; downspout; canvas awning with sag/scalloped valance; physical sign (frame, acrylic face, channel letters with one dead tube, bowl icon, brackets, cable gland + run to junction box); practical menu (text from `ak-qwen`) with gooseneck lamp; ramen food, bowls, caddy, tea set.
- **Materials / textures** (procedural numpy, albedo 512 / ORM 256 / normal 512): shop 9 surfaces (`steel_structure, cladding_main, cladding_patch, concrete, equipment_steel, awning_fabric, sign_emissive, ceramic (glaze+food atlas), rubber`), vendor 6, customer 5. Only `sign_emissive` (and a few lamp lenses using it) emits; people have no emission.
- **Wear:** AO from BVH ray casts in `COLOR_0` multiplied by gravity/shelter rules: ground-splash band, rain streaks under the sign/downspout/awning joints, sun-faded roofline, polished counter lip and door pull. Texture recipes add rust, drips, scuffs and stains.

## Measured costs (see manifest `costs`)
Shop 34,828 tris / 9 surfaces; vendor 27,756 / 6; customer 26,040 / 5; combined 88,624 tris, 20 surfaces. Texture working estimate: RGBA8 + full mips 63 MiB, 126 MiB with the duplicated imported copy (limit 128; hair textures are 256 px to stay inside it with the 1024 skin atlases).
Person triangles rose from ~17.7k to ~27k because real face/hand topology is ~21k tris for the bare body alone (head ~5k, hands ~2.5k each) plus fitted garments; the validator person cap moved 18k -> 40k, the combined 120k cap is unchanged.
GLB sizes 7.6 / 5.1 / 3.9 MB. Local shadow/light cost is not measured here (Godot scene owns it).

## Previews (`assets/previews/industrial_market/`, EEVEE, re-imported GLBs; Blender lighting is diagnostic only)
`shop_approach_driver`, `shop_sidewalk_34(_b)`, `shop_counter`, `shop_handoff`, `shop_handoff_top`, `shop_support_contact`, `shop_sign_menu`, `shop_materials_menu`, `shop_interior_service`,
`vendor_front/side/face`, `hands_vendor`, `customer_front/face/back`, and `shop_night_approach`, `shop_night_counter` (night anchors from the manifest as point lights).

## Known limitations
Static baked pose, no rig/LODs. Faces/hands are the unmodified generic base-human anatomy (neutral expression, closed mouth, no teeth); the customer's base face reads young and a little wide-eyed, the vendor's lip paint is flat, nostrils/lips are painted not modelled. Hair is a thin shell (hard hairline, bold strand texture), not cards. Boots are lofted shells: slightly pointed, lumpy leather, no laces. Cloth folds are procedural; jacket pockets/flap sheets are flat. Both figures use the same smart-project UV method, so islands have visible but dilated seams. Eyes follow gaze but eyelids do not. Source maps live under assets/generated/industrial_market/textures; Godot imports the embedded GLB images as Basis Universal textures. Redundant first-delivery texture copies have been removed from the Godot resource tree. Sign lens is a dark acrylic face (no transparency). Procedural textures, not photographic or ComfyUI generated (`comfyui_used: false`). No Godot capture was done here (lead's scene); import behaviour of embedded ORM/normal maps and `COLOR_0` should be confirmed in-engine.
