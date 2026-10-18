# Finish Helix Wraith and Knifeedge XR

The remaining roster entries are Helix (r-type.jpg, biomechanical racer) and
Knifeedge (hot-wheels.jpg, sand rail/supercar). Finish both to the reference-led
standard established by the five production vehicles.

1. Claude asset lead authors each in its own asset branch/worktree, in parallel.
   Reuse safe primitive/export conventions, preserve distinct source silhouettes,
   native Blender source, repeatable headless builders, production GLB/two LODs,
   semantic paint, authored hubs and measured visual radii. No physics changes.
2. Codex wires the existing authored-wheel adapter, palette/studio/garage and
   gameplay captures. Extend shared geometry/paint/player/CPU/physics regression
   checks for both. No new architecture or tuned handling changes.
3. Asset numeric/rebuild checks and source/close-up/LOD visual QA; Gemini source
   review (max two rounds). Keep verification focused, fix actual defects, use
   measurements for ambiguous/noisy image findings. Commit coherent artwork
   early and deliver final handoffs.
4. Merge both asset deliveries, import in Godot, run full ak-test plus exact final
   affected checks and actual GPU capture QA, review integration, commit concise
   evidence and completion report. Finish with the final vehicle garage available.

Helix source inspection establishes a tracked rear and wheel-less hover nose.
Use the existing embedded_wheels path and a no-op authored-wheel installation
override to preserve four hidden simulation wheels/shafts. Visible Prop_Track_*
is body-mounted art, scaled uniformly to about5m overall rather than a nonexistent
visible four-wheel wheelbase. Dedicated tests cover track presence/ground/palette,
hidden wheels through refresh, player/CPU and independent physics parity. Design
escalation 20261018-092208 confirms this existing lifecycle path is sufficient.
