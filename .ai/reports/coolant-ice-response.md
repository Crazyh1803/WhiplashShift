# Vitrified coolant terrain response (ICE)

Added cold thin closed-prism coolant flakes and elongated splinters with opaque specular material (roughness .28, clearcoat .5, no emission/alpha). Low tyre-contact ejecta skitter outward, tumble and briefly bounce; correct A is restrained, wrong B has five times the matched-input emission rate with larger/higher fragments. No standing contact discs or smoke geometry.

The existing single cosmetic body-pose writer now adds smooth bounded yaw (max 3.15 degrees) and roll (max .69 degrees), signed by actual body-local lateral velocity and active driving end. Straight rolling and stationary wheelspin cannot invent a sideways skid. Skid strength scales with ICE contact coverage and is five times stronger on wrong B. This layer reads physics only; physical body, forces, wheel mounts, handling tables, collision and camera behavior are unchanged. Ten cached mesh batches share the existing 96-live-fragment pool. Existing resets clear skid, pose and fragments.

The chase fixture now labels frames according to Surfaces.PREFERRED, so ICE correctly compares A against B. Identical initial velocity (2.5, 0, -10), throttle .8 and steering .16 expose a real early lateral slide. ICE captures use .5–1.5s while that initial slide is visible; other terrain capture windows are unchanged. Production vehicle lighting is retained.

Verification:
- Focused headless: 20 passed, 0 failed.
- Vulkan Forward+ actual chase captures: 26 passed, 0 failed.
- Correct A: 46 fragments emitted, peak captured skid .125, final speed 11.59m/s.
- Wrong B: 252 fragments emitted, peak captured skid .628, final speed 11.56m/s.
- Tests cover sign and rotated-body coordinates, physical isolation, material/geometry bounds, pool isolation/budget, mixed four-surface seams, stationary/spin/airborne gating, pose decay and player/CPU recovery.
- Full ak-test passed all 21 test scenes, including existing terrain layers, lighting contracts, geometry, CPU/race/camera and vehicle suites. Logs: coolant-ice-focused.log, coolant-ice-rendered.log and coolant-ice-full-test.log.

Review: ak-scout and ak-review failed because Gemini quota is exhausted; no independent approval. Claude design escalation failed because its OAuth session expired. ak-look also failed due to Gemini quota; no independent visual verdict. No images were loaded into the lead's context. Work remains uncommitted. Previews: .ai/captures/coolant-ice-response/correct-A.gif and wrong-B.gif.
