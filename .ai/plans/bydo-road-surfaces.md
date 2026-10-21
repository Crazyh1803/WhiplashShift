# Bydo-Grid secondary road materials

Keep the approved ceramic deck and environment. Replace the remaining procedural
surface appearances: gravel -> chitin rubble; mud -> living viscera; boulder ->
fractured armor/spine slabs; ice -> vitrified coolant; water -> reactor effluent;
oil -> black ichor; off-track -> crushed carbon/chitin. Preserve all physics IDs,
coefficients and HUD hazard names. Rumble remains the approved hazard curb.

Use world/metre-space procedural masks, filtered hard seams, restrained relief
normals and distinctive dry/wet responses. Viscera reuses the existing dedicated
sinew normal/roughness maps with active shader SSS. No vertex displacement.

Extend the rendered fixture to capture every material under matching local lights,
and inspect by ak-look. Run focused and full ak-test, then ak-review. Save a small
isolated review snapshot before editing to avoid the accumulated branch diff's
argument-size failure. No architecture change or asset-lane work is required.
