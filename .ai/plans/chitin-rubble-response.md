# Next terrain layer: chitin rubble (GRAVEL)

Extend the existing contact-response component rather than adding a second body
pose writer. Keep approved viscera behavior. GRAVEL gets dry broken armor/chitin
chips, carbon grit and occasional angular chunks, each with independent tumble
and one brief visual ground bounce. Correct B: restrained low debris and subtle
body rattle. Wrong A: stronger bursts, higher/larger debris and an exaggerated
bounded cosmetic chassis shudder. No sinking on dry rubble.

Use per-wheel surface selection on mixed seams, one shared 96-live-fragment pool,
separate wet/dry materials and six cached fragment meshes. Add bounded rattle to
the existing additive visual-root pose; no forces, camera shake, collider/wheel
transforms or handling changes. Existing recovery/freeze/customization/reset
hooks must clear both terrain layers.

Test matched-input frame differences, dry/mud isolation and mixed seams, all dry
mesh kinds, total live budget, finite geometry, ground bounce, stationary/airborne
gating, rattle decay, recovery and unchanged physics. Keep viscera checks passing.
Add actual CameraRig correct/wrong rubble GPU captures; run ak-test focused/full,
ak-look and isolated ak-review. Other road types remain future layers.
