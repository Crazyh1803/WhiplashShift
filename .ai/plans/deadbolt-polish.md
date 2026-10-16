# Deadbolt visual parity and vehicle selection

1. Replace the garage's unlabeled selection ticks with named chassis buttons and
   clear previous/next controls. Keep the selected chassis when returning from a race.
2. Add regression checks for direct Deadbolt selection and preview switching, run
   the affected suites through `ak-test`, then review and visually check the garage.
3. In a separate asset worktree, refine Deadbolt against its Ford/Mustang blueprint
   and Blackjack's current finish: crisp continuous shell, flush glass, readable ends,
   seated lights/trim/guards, wheels, semantic paint, protected PBR materials and LODs.
   The user chose a Claude handoff. Codex prepares the reference/acceptance package
   and asset worktree; Claude leads the actual modeling work.
4. Keep the physical hardpoints/radii, handling, collision and swap behavior intact.
   Validate art numerically with headless Blender, compare renders with `ak-look`,
   and validate garage/player/CPU integration in Godot before delivery.

## Asset acceptance criteria

- Use `80sFord.jpg` as the shape authority. Retain the squared pickup grille/hood,
  upright truck cab, low Mustang-derived nose and the shared reversible cockpit.
  Remove the current globally smoothed capsule rather than decorating it further.
- Trace a continuous hard-surface cage with controlled bevels/creases. Cut real
  wheel openings; seat fender lips, doors, rockers and trim against the actual shell.
- Include both windshields and flush side glass with recessed dark seals, correctly
  seated pillars, mirrors, wipers, lamps, grille, bumper/brush bar and coupe splitter.
- Match Blackjack's visible detail density at garage and chase-camera distances:
  wheel depth, tire tread, panel seams, paint finish, glass and protected metal/rubber.
- Keep `Deadbolt_Paint`, `Deadbolt_Secondary` and `Deadbolt_Stripe` material channels
  and protect all other materials from recoloring. Use clearcoat/metallic studio
  lighting comparable to Blackjack for the final Godot comparison.
- Preserve source longitudinal/vertical centers: coupe `(1.66, y, 0.40)`, truck
  `(-1.72, y, 0.43)`. Fit lateral visual hubs to the blueprint/fenders; the draft
  +/-0.91 visual track is superseded. Keep physical hardpoints unchanged. Preserve `Wheel_Coupe_*` / `Wheel_Truck_*` groups consumed
  by the existing visual adapter. Merge added tread/bolt details into their semantic
  tire/rim meshes where practical, instead of changing physics or adding colliders.
- Keep the finished visible vehicle within the existing 20–40k triangle target;
  supply lower-detail exports and an editable, idempotently rebuilt native source.
- Validate meaningful properties rather than only fixed object counts: closed main
  shell, positive volume, UV/material coverage, mirror symmetry, wheel orientation,
  dimensions, glass-to-shell seating, LOD reduction and stable repeat-build results.
- Compare neutral side, both end views and three-quarter renders with the blueprint,
  then inspect the actual garage preview, three paint channels, steering/suspension,
  driving and end swap in Godot. Final visual QA must not retain the current high
  findings about pill-shaped body, missing windshields or floating panels/fenders.
