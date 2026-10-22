VERDICT: APPROVE

FINDINGS:
- [LOW] [deadbolt_hardsurface_cuts.py](file:///home/crazyh/Documents/ChatGPT/Whiplash/tools/vehicle_pipeline/blender/deadbolt_hardsurface_cuts.py#L257-L284): `glass_panel` accepts a `thickness` parameter (passed by [`seat_glass`](file:///home/crazyh/Documents/ChatGPT/Whiplash/tools/vehicle_pipeline/blender/deadbolt_hardsurface_cabin.py#L72-L74) in `deadbolt_hardsurface_cabin.py`) but never uses it, leaving glass panels as single-sided open sheets offset by `clearance`.
- [LOW] [deadbolt_hardsurface_core.py](file:///home/crazyh/Documents/ChatGPT/Whiplash/tools/vehicle_pipeline/blender/deadbolt_hardsurface_core.py#L28-L43): `make_material` accepts `alpha=1.0` but hardcodes `1.0` in `Base Color` and `diffuse_color` without wiring `alpha` to the Principled BSDF `Alpha` input.
