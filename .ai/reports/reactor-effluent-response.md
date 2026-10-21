# Reactor effluent contact response (WATER)

WATER now emits irregular open liquid ribbons with pale scum/foam rims and separate elongated droplets. Low sheets move outward, spread and flatten while trailing behind the car; droplets rise separately and align with their flight velocity. The material is wet (roughness .14, clearcoat .65) with dirty teal vertex colors, no emission and no alpha flood. Liquid particles disappear on re-entry; only solid terrain fragments use the shared bounce path. Nothing remains attached around the tyres.

Correct B has restrained spray and shallow immersion; wrong A has a 28:6 matched-input emission rate, larger/higher splashes, stronger smooth immersion and a nose-down plowing pitch. Contact coverage and motion/WATER-wheel spin gate the effect. Stationary unspinning contact and airborne wheels cannot produce liquid drag or spray. The shared VisualRoot pose writer blends effluent with previous surfaces; 12 cached mesh batches share the same 96-live-fragment budget. Existing reset paths clear wash, immersion, pitch and spray. No physical transforms, handling tables, forces, camera or lighting changed.

Verification:
- Focused headless: 20 passed, 0 failed.
- Final Vulkan Forward+ chase capture: 25 passed, 0 failed, using actual production lighting/CameraRig and equal initial 10m/s speed plus throttle .8.
- Correct B: speed 11.34m/s, cosmetic sink .015m, wash .180, 4 live / 58 emitted particles.
- Wrong A: speed 4.62m/s, cosmetic sink .045m, wash .595, 14 live / 136 emitted particles. Speed difference comes from existing WATER handling.
- Tests cover materials/geometry/silhouettes, pool isolation/budget, no liquid bounce, correct/wrong pose, physical isolation, mixed seams, spin isolation, motion/airborne gating, decay and player/CPU recovery.
- Full ak-test: all 22 scenes passed. Final liquid-spreading refinement then passed its complete focused/rendered scene (25 checks). Logs: reactor-effluent-focused.log, reactor-effluent-full-test.log and reactor-effluent-rendered.log.

Review status: ak-scout/ak-review fail because Gemini quota is exhausted; no independent approval. Claude design escalation fails because its OAuth session expired. ak-look also fails due to Gemini quota; no independent visual verdict. No images were loaded into the lead's context. Work remains uncommitted. Human previews: .ai/captures/reactor-effluent-response/correct-B.gif and wrong-A.gif.

Remaining: black ichor (OIL) is the last main special road surface. Rumble curbs (RUMBLE) and off-track carbon verges (OFF) also still lack dedicated contact-effect passes. Normal tarmac retains its existing baseline presentation.
