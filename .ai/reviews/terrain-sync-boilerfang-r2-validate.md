VERDICT: APPROVE
FINDINGS:
- [MED] tools/vehicle_pipeline/blender/validate_boilerfang.py:468 — `lod_tire_radius_preserved` takes `min(tire_r.values())` across all four tires and compares against `0.95 * mm(T.WHEEL_R["coupe"])` (243.2 mm), which allows the larger `Wheel_Truck_Tire_*` (348 mm radius) to shrink by up to 30% in LOD1/LOD2 without failing — compare each tire in `tire_r` against its own end's `T.WHEEL_R["truck" if "Truck" in name else "coupe"]`.
- [LOW] tools/vehicle_pipeline/blender/validate_boilerfang.py:450 — `bb` only records 5 bounds (`min_x, max_x, min_y, max_y, max_z`), omitting `min(p.z for p in pts)` when checking `lod_envelope_matches_gameplay` — include `min(p.z for p in pts)` in `bb`.
