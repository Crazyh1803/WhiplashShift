# Bydo-Grid terrain materials and contact feedback

Road materials are procedural Godot shaders and cached code-generated meshes; no
external bitmap texture downloads are needed. The shared seamless noise map,
normal/roughness maps and fragment geometry are generated at runtime.

| Physical terrain ID | Visual theme | Preferred frame | Contact response |
|---|---|---|---|
| GRAVEL | Chitin rubble | B | Dry chips/grit, brief bounce and continuous body rattle |
| MUD | Parasitic viscera | B | Muscle shreds, entrails and small limb fragments; cosmetic immersion |
| BOULDER | Fractured spinal armor | B | Broken plates/ribs and spaced chassis jolts |
| ICE | Vitrified coolant | A | Thin flakes/splinters and a signed lateral skid pose |
| WATER | Reactor effluent | B | Spreading liquid sheets/droplets and nose-down plowing |
| OIL | Black ichor | A | Stretching oily strands/droplets and a signed slip pose |

Wrong-frame effects are deliberately exaggerated. The contact controller reads
actual wheel contacts, slip/spin and body-local velocity. It changes only the
visible body pose and cosmetic fragments; handling tables, physical forces,
wheel hardpoints and colliders remain authoritative. Mixed terrain is blended
per contacting wheel through one pose writer and a shared 96-live-fragment pool.
Recovery clears all transient poses and fragments.

Rough road runs have bounded real mesh/collision relief. Smooth road runs retain
the original flat collision geometry. External deposits stay outside the rails.
The black void, localized beacons and headlights on the active driving end retain
contrast without the former opposed-spotlight hourglass boundary.

Run `ak-test` for geometry, contact, recovery and vehicle regressions. For a chase
capture, override TEST_CMD with the appropriate scene, for example:

```sh
TEST_CMD='timeout 180 godot --path godot --resolution 960x540 --fixed-fps 60 res://tests/ichor_response_tests.tscn -- --capture' ak-test
```

Other capture scenes: `viscera_response_tests`, `rubble_response_tests`,
`armor_response_tests`, `coolant_response_tests`, and `effluent_response_tests`.
Captures are local verification output under `.ai/captures/` and are Git-ignored.
Rumble curbs and off-track carbon verges still need dedicated contact effects.
