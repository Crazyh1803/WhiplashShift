# Black ichor (OIL) contact response

OIL now throws curved dark oily strands and elongated droplets. Strands thin and stretch with age, and both forms follow their flight direction. They disappear on re-entry, with no solid bounce or persistent tyre geometry. Material: opaque, non-emissive, roughness .08, clearcoat 1, muted violet/green film colors. The shared tube helper accepts optional end colors so oil has dark/film ends while existing anatomical colors stay unchanged.

Correct A is restrained. Wrong B gets a 27:5 matched-input emission multiplier, larger/higher spray and approximately seven times the lateral slip pose. Signed body-local lateral velocity and actual OIL contact coverage drive smooth bounded yaw (max 4.01 degrees) and roll (max 1.03 degrees). No sink, water drag, ice chips or fake stationary/straight-line lateral wobble. The existing single VisualRoot pose writer and shared 96-live-fragment pool now cover 14 cached meshes. No forces, handling tables, wheel/collider transforms, camera or production lighting changed.

Verification:
- Final GPU/Vulkan production-chase scene: 31 passed, 0 failed, including 25 focused checks and six capture checks.
- Correct A: 50 emitted, 6 live, peak captured oil-slide .117, final speed 10.93m/s.
- Wrong B: 274 emitted, 53 live, peak captured oil-slide .828, final speed 10.82m/s.
- Equal initial velocity (2.5, 0, -10), throttle .8, steering .16; captures cover the early measured slide, as with ICE.
- Focused headless in full run: 24 passed, 0 failed; actual strand-transform readback is GPU-only. The initial headless run exposed dummy-renderer MultiMesh identity readback and an overly strict small-triangle threshold on thin tube caps. GPU validates stretch; mesh checks reject degenerate triangles at the existing thin-mesh tolerance.
- The preceding effluent test also now explicitly skips its GPU-only transform-readback assertion in headless mode. Its production sheet behavior is unchanged.
- Full ak-test passed all 23 scenes, including the previous terrain layers, lighting, track geometry, items, CPU/race/camera and all vehicle suites. Logs: black-ichor-rendered.log and black-ichor-full-test.log.

Review: ak-scout, ak-review and ak-look fail because Gemini quota is exhausted; no independent approval or visual verdict. Claude design escalation fails because OAuth expired. Work remains uncommitted. No images were loaded into the lead's context. Previews: .ai/captures/black-ichor-response/correct-A.gif and wrong-B.gif.

Remaining dedicated contact layers: rumble curbs and off-track carbon verges.
