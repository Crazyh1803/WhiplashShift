# Deadbolt hard-surface rebuild: progress

Branch asset/deadbolt-graphics. Asset lead: Claude. Blender in this environment is 4.0.2 (/usr/bin/blender); no 5.x installed.

## Milestones
- [x] 1. Read handoff/plan/escalation/Blackjack source; traced 80sFord.jpg numerically (wheelbase 321 px = 3.38 m, S = 0.010530 m/px, ground y = 241 px, wheel centres x = 346 / 667 px, silhouettes from column edge scans).
- [x] 2. Trace module + station cage shell (modules deadbolt_hardsurface_{trace,core,shell,cuts,cabin,prims,wheels,qa}.py). Shell alone: 0 open edges, vol 9.85 m3; side silhouette within ~2-4 px of the sheet (ak-look overlay).
- [~] 3. Arches + glass recess cutters verified individually (0 open edges each); combined leaves 8 open edges at the coupe nose corner, fixed by a 0.5-4 mm weld pass (repair_manifold -> 0). Escalation patch (axial depth, flat caps, inset windshield) applied.
- [x] 4. (first full pass) Truck/coupe ends, trim, lamps, grooves, wheels built. Bug found+fixed by numeric validation: +Y arch cutter had inward normals (cut never happened on that side); assert_cutters_outward now guards it.
- [x] 5. Export/LOD/validator/renders running (Blender 4.0.2; glTF exporter needs numpy: PYTHONPATH=~/.cache/ak-pylibs). Gameplay 32.0k tris, LOD1 23.1k, LOD2 16.2k; validator passes shell/glass/wheel/arch/UV/material checks. Visual polish rounds continuing with ak-look.
- [~] 6. ak-test PASS (59 consolidation + existing suites on the untouched runtime). Candidate also ran consolidation_tests 59/59 in a throw-away copy with only the catalog scene path swapped. Commit + ak-review next.

## Numbers (validate_deadbolt_hardsurface.py -> deadbolt_hardsurface_qa.json, PASS)
- Shell: 0 open edges, 8.95 m3, silhouette vs sheet: top max 2.6 px, sill 0.3 px, half-width 0.9 px; mirror: 6 of ~3.7k vertices differ by more than 0.8 mm (max 12.8 mm at one groove crossing).
- Glass: 6 panels, 2.9-4.5 mm off the cut shell, 0 shell crossings.
- Wheels: 9 parts per truck wheel, 13 per coupe wheel, origins at hubs (0.0 mm), tyre 0.86x0.34 / 0.80x0.29, arch clearance 69 mm truck / 60 mm coupe.
- Triangles of the complete visible vehicle: 32.3k gameplay, 23.3k LOD1, 16.3k LOD2. Bounds 5.33 x 2.23 x 1.82 m, ground contact z=0.
- Rebuilds idempotent (same topology, coordinates to micrometres).
