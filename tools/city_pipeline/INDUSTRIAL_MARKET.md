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
Modules: `industrial_market_textures.py` (numpy PBR recipes + skin/face atlas), `_common.py` (bmesh builders, UV, ray-cast AO, materials, GLB export),
`_people.py` (anatomy, hands, shoes, IK), `_dress.py` (draped apron/collars/headband), `_shop.py` + `_shop_detail.py` (stall, sign, menu, food), `_render.py` / `_shots.py` (QA renders).

## Layout contract (Godot world, metres)
Shop origin at the shop centre on the road plane; facade at z -2; floor/sidewalk top y 0.15; sidewalk to z -4.7; counter top y 1.20 (x +-2.37, z -1.5..-2.08).
- vendor `[0.40, 0.15, -1.33]` yaw 0; customer `[0.66, 0.15, -2.30]` yaw 180 (faces the shop); bowl centre `[0.55, 1.20, -1.78]`.
- Vehicle slot: centre `[-3, 0, -7.5]`, reserved strip z -5..-10, curb z -4.7 (the lead places the approved BLACKJACK X-17 there).
- Interaction: both right hands hold the bowl rim from opposite sides (vendor wrist `[0.66,1.25,-1.71]`-ish, customer wrist `[0.45,1.25,-1.84]`-ish; exact values in the manifest);
  vendor's left hand rests flat on the counter. `validate_industrial_market.py` checks mesh vertices of both people are within 3 cm of the bowl wall, soles sit at y 0.15 and no body penetrates the counter carcass.

## Construction
- **Anatomy:** swept elliptical tubes (continuous elbows/knees), lofted torso, displaced-sphere head with brow/nose/lip/chin/ear shaping, spherical eyes + eyelid tubes, articulated hands (palm, 4 fingers with 3 phalanges, thumb, nails), shaped shoes/boots. Two-bone IK places wrists at the real bowl/counter points.
- **Clothing:** sleeves, trousers, shirt/jacket shells carry fold ridges (knee/elbow/hem/waist), rolled cuffs, collars, hood roll, hem band; the apron, pockets, zip and flaps are ray-draped onto the body mesh with thickness; headband with knot.
- **Shop:** counter-wide H-columns on grouted plinths with base plates, anchor bolts + double nuts, base gussets, splice plates, bumper collar; header I-beam with end plates, web stiffeners, knee braces; roof/parapet; corrugated cladding with lap joints/rivets, bolted replacement panel; worn counter (rolled lip, ribs, toe kick, repaired lower panel); sliding door; cooking line (stock pot, noodle boiler, hood + roof duct, gas cylinder + hose); electrics; downspout; canvas awning with sag/scalloped valance; physical sign (frame, acrylic face, channel letters with one dead tube, bowl icon, brackets, cable gland + run to junction box); practical menu (text from `ak-qwen`) with gooseneck lamp; ramen food, bowls, caddy, tea set.
- **Materials / textures** (procedural numpy, albedo 512 / ORM 256 / normal 512): shop 9 surfaces (`steel_structure, cladding_main, cladding_patch, concrete, equipment_steel, awning_fabric, sign_emissive, ceramic (glaze+food atlas), rubber`), vendor 6, customer 5. Only `sign_emissive` (and a few lamp lenses using it) emits; people have no emission.
- **Wear:** AO from BVH ray casts in `COLOR_0` multiplied by gravity/shelter rules: ground-splash band, rain streaks under the sign/downspout/awning joints, sun-faded roofline, polished counter lip and door pull. Texture recipes add rust, drips, scuffs and stains.

## Measured costs (see manifest `costs`)
Shop 34,828 tris / 9 surfaces; vendor 17,836 / 6; customer 17,632 / 5; combined 70,296 tris, 20 surfaces. Texture working estimate: RGBA8 + full mips 57 MiB, 114 MiB with the duplicated imported copy (limit 128).
GLB sizes 7.6 / 5.1 / 3.9 MB. Local shadow/light cost is not measured here (Godot scene owns it).

## Previews (`assets/previews/industrial_market/`, EEVEE, re-imported GLBs; Blender lighting is diagnostic only)
`shop_approach_driver`, `shop_sidewalk_34(_b)`, `shop_counter`, `shop_handoff`, `shop_handoff_top`, `shop_support_contact`, `shop_sign_menu`, `shop_materials_menu`, `shop_interior_service`,
`vendor_front/side/face`, `hands_vendor`, `customer_front/face/back`, and `shop_night_approach`, `shop_night_counter` (night anchors from the manifest as point lights).

## Known limitations
Static pose, no rig/LODs. Faces use painted brows/lips on a displaced sphere and read best at 2-5 m; close-ups are doll-like. Shoes are plain wedges with a wide sole slab. Sign lens is a dark acrylic face (no transparency). Procedural textures, not photographic or ComfyUI generated (`comfyui_used: false`). No Godot capture was done here (lead's scene); import behaviour of embedded ORM/normal maps and `COLOR_0` should be confirmed in-engine.
