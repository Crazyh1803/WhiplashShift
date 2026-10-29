# Inhabited industrial city: vehicle-matched benchmark

User-approved direction, 2026-10-29: grounded, worn industrial science fiction. A believable human neighborhood lives inside the same technological world as the vehicles. Repaired machinery, heavy infrastructure, modest human comforts and small pockets of warm light establish the mood.

This refines close-range civilian scenery within [Bydo-Grid](bydo-grid.md). Preserve its distant skyline, bone/steel palette, compact cyan/amber accents, dark sky and biomechanical context. The current cars and track provide the standard for construction, weight and material response. The recent market identity pass is useful layout/signage groundwork; its people and architectural finish still need the realism benchmark below.

## First deliverable

Build one small Redline Ramen storefront with one vendor, one customer, two structural supports, an awning, signage and a short sidewalk segment. Park an existing approved playable vehicle beside it. Choose the current vehicle with the strongest finished presentation during setup; record the exact vehicle/version used.

Keep this a separate candidate scene until it establishes the standard for the wider city. The current street block remains the layout reference. The first pass is an art benchmark for later work with Claude, with no new driving, pedestrian simulation, NPC animation or city-wide population system implied.

## Shared realism standard

### People

- Convincing anatomy and proportions at 2-5 m: rounded shoulders, shaped faces and hands, believable necks, hips, elbows and knees.
- Relaxed weight distribution and planted feet. The vendor works at the counter; the customer interacts with the shop. Their poses should communicate an ordinary activity.
- Clothing hangs over a body. Major folds, seams, cuffs, collars, aprons and footwear explain its construction. Joints sit naturally beneath the clothing.
- Skin, hair, fabric, leather and protective equipment have distinct material responses. Use texture detail and normal/roughness maps where they improve the result. Facial features should survive the actual game lighting.
- Retain useful stylistic edges while matching the vehicles' sense of physical objects. Evaluate the people in context and in a clear face/body view.

### Storefront

- Give the shop a history: an aging sign, repaired fascia, replacement panel, practical menu, worn counter edge and a few deliberately placed cooking/serving objects.
- Use the approved name and familiar bowl/chopstick imagery. Invented glyphs can supplement recognizable information. Establish a clear hierarchy between the main sign, menu and small labels.
- Build the sign as equipment: enclosure, lens or tubes, mounting brackets, fasteners and a plausible electrical connection. Keep emission localized and the backing appropriately dark.
- Show different generations of fittings and repairs. Avoid making every element equally new, equally clean, equally luminous or identically manufactured.
- Goods and appliances should communicate ramen preparation and service. Favor a small number of recognizable objects over repeated generic containers.

### Structure

- Explain how the building stands up: a steel frame or cast pier, load transfer into beams, gussets, flange plates, fasteners and a grounded footing.
- Cladding has thickness, edges, attachments and service access. Structural joints and panel joints have different purposes.
- Supports use the same manufacturing vocabulary as vehicle frames and armor mounts. Collars, braces and bolts should have a visible function.
- Recesses, doors, counter height, awning clearance and walking space use a consistent human scale.

### Surfaces and lighting

- Separate painted metal, exposed steel, concrete, glass, plastic, fabric and skin through roughness, reflectance, color variation and appropriately scaled surface detail.
- Place wear where use and weather cause it: touched handles, counter lips, foot traffic, gutter deposits, leaking joints, sheltered grime and repair seams.
- Establish readable masses and real depth before adding fine weathering. Avoid using uniform noise or bolt scatter as a substitute for construction.
- Check contact shadows, recessed lighting and local occlusion. The current shadowless batches and material fill can flatten volume; the benchmark should expose that tradeoff and establish a measured solution.
- Keep a neutral inspection setup and a genuine game-night setup. The night version follows the dark-world direction with local illumination. Labels must distinguish diagnostic lighting from proposed runtime lighting.

## Review setup and acceptance

1. Show the approved vehicle, storefront and both people together at consistent scale, camera height, field of view and lighting. Keep these reference settings fixed between iterations.
2. Include a driver-height approach, a sidewalk three-quarter view, the working counter, a face/body detail and a support/ground-contact detail. Include neutral and night views.
3. The viewer should believe the driver could stop here for dinner: people, surfaces, goods and construction share the vehicle's level of credibility.
4. Shop identity reads from the approach through its silhouette and icon; its name and menu read at closer inspection distances. Check glare, occlusion and thin-detail shimmer in Godot.
5. Show actual exported assets in Godot. Studio or concept images supplement those captures. Retain reproducible source files and measured geometry/material data.
6. Record triangle counts, surface draws, texture memory and the local shadow/light cost. Compare the same view before/after; distinguish a static render sample from a full-race performance test.
7. Use the accepted result to define reusable people, supports, storefront assemblies and material treatments before extending the rest of the block.

## Ownership and execution

- Codex lead: retain the approved brief, arrange the vehicle comparison, integrate the candidate review scene, inspect the real exports, coordinate checks/review and publish the tested chat preview.
- Claude asset lead, when available: build the complete benchmark asset task in its delegated worktree, using `ak-blender` for geometry and baking, and `ak-comfy` for generated raster art where appropriate. Keep reusable components in source. Run one heavy local job at a time.
- Agree implementation budgets from measured benchmark results. The current block's 220k cap, neighborhood models' 50k cap and eight-material layout describe the existing implementation; any proposed changes need an explicit measured rationale. Avoid sacrificing recognizable anatomy or construction merely to repeat the previous prototype method.
- Follow the repository workflow for independent review, targeted `ak-test` checks, generated/candidate asset locations and preview publication. Human review determines whether the benchmark should become the wider city's reference. Promotion to `assets/final/` and merging main retain their existing authorization gates.

This document prepares the next asset pass. Its creation does not mark a new benchmark model or a city-wide realism pass complete.
