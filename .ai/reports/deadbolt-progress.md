# Deadbolt hard-surface rebuild: progress

Branch asset/deadbolt-graphics. Asset lead: Claude. Blender in this environment is 4.0.2 (/usr/bin/blender); no 5.x installed.

## Milestones
- [x] 1. Read handoff/plan/escalation/Blackjack source; traced 80sFord.jpg numerically (wheelbase 321 px = 3.38 m, S = 0.010530 m/px, ground y = 241 px, wheel centres x = 346 / 667 px, silhouettes from column edge scans).
- [x] 2. Trace module + station cage shell (modules deadbolt_hardsurface_{trace,core,shell,cuts,cabin,prims,wheels,qa}.py). Shell alone: 0 open edges, vol 9.85 m3; side silhouette within ~2-4 px of the sheet (ak-look overlay).
- [~] 3. Arches + glass recess cutters verified individually (0 open edges each); combined leaves 8 open edges at the coupe nose corner, fixed by a 0.5-4 mm weld pass (repair_manifold -> 0). Escalation patch (axial depth, flat caps, inset windshield) applied.
- [ ] 4. Truck/coupe ends, trim, lamps, wheels
- [ ] 5. Export, LODs, validation, renders, ak-look
- [ ] 6. ak-test, ak-review, commit
