# Remaining vehicle designs complete

Helix Wraith and Knifeedge XR complete the seven-vehicle production-art roster.
Each has native Blender source, a repeatable builder, gameplay GLB, two LODs,
reference/close-up renders, three paint channels and garage/player/CPU integration.

Helix preserves the sheet's biomechanical carapace, pincer claws, ribbed hoses,
tracked rear and wheel-less hover nose. Body-mounted track artwork uses the
existing embedded-wheel path; the original four simulation wheels and shafts
stay hidden through customization. Knifeedge joins a tube-frame sand rail,
exposed engine and suspension to a supercar nose with open arches and LED strips.
Its wheels use measured authored hubs and visual radii A0.390/B0.446 m.
Physical hardpoints, radii, tuning, mass, collider and swap behavior are unchanged.

| Vehicle | Gameplay triangles | LOD1 | LOD2 | Asset checks |
| --- | ---: | ---: | ---: | ---: |
| Helix | 35,576 | 25,678 | 20,050 | 39 PASS |
| Knifeedge | 35,186 | 25,068 | 14,542 | 51 PASS |

Verification:
- Full ak-test: 4,778 passed, zero failed before final artwork refinements.
- Exact final exports: Helix136 + Knifeedge62 + consolidation111 = 309 passed,
  zero failed. This includes repaint lifecycle, visible/hidden wheel contracts,
  track contact, player/CPU construction and independent physics parity.
- Independent builds have zero vertex/surface deviation (Helix79 native objects,
  Knifeedge206); all three exported GLBs match across builds for each vehicle.
- Integration Gemini review: APPROVE in both rounds, no findings. Asset source
  review scopes, fixes and late numeric/data edits are recorded in the handoffs.
- Helix final actual Godot visual QA PASS, no issues. Both vehicles accelerate
  and swap in the GPU captures (Helix56.92km/h, Knifeedge64.63km/h); captures save
  successfully. Final Knifeedge review is recorded in knifeedge-runtime-visual-final.md.

Tested/merged GLB SHA256:
- Helix: 593c14ea19beea2f844a0f5994cd3a32f5cee2163ae79071142c07d2a2614836
- Knifeedge: 374f6652c12b2d1cf7ece78143a15709230753b9f08529ab46d5ebafaaec9ec9

See helix-asset-handoff.md and knifeedge-asset-handoff.md for source measurements,
review evidence, AI-sheet ambiguities and minor art limits. Helix tracks are
body-mounted visual mechanisms over the preserved wheel simulation. Knifeedge's
pre-existing AI recovery/stall behavior is unchanged; long CPU regression uses
Boilerfang/Ramjet, while both new chassis are checked for CPU construction and
physics parity. This design pass does not change AI or handling.

The Knifeedge customization garage preview is open. All requested vehicle-design
work is complete. The temporary Knifeedge asset worktree was archived after its
commits were merged; its snapshot remains recoverable.
