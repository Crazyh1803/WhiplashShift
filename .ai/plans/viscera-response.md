# First vehicle terrain-response layer: viscera

Read real wheel MUD contact, wheelspin, speed, throttle and active frame. Correct
B end gets restrained organic spray/shallow wet collars. Wrong A end gets heavier
clumps, taller spray/deeper collars and a bounded cosmetic body sink/pitch.

A fixed world-space MultiMesh pool and four contact collars keep effects bounded.
No forces, grip changes, rigid-body/collider/wheel transforms or camera edits.
Restore additive body visual pose on cleanup/rebuild; clear on recovery/retry,
teleports, freeze and teardown. Local random generator must not alter gameplay.

Test matched-input right/wrong responses, per-wheel contact seams, airborne/dry/
stationary gating, pool limits, decay/reset, customization and unchanged physical
state. Add player/CPU scene integration and rendered right/wrong comparisons.
Run ak-test focused/full, ak-look and ak-review. Only viscera in this pass; other
terrain, accumulated residue and sound are later layers.
