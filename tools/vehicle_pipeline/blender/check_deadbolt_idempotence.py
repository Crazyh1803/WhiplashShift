"""Compare two validator reports (plain Python): rebuilds must give the same geometry.

Usage: python3 check_deadbolt_idempotence.py qa_a.json qa_b.json
Per-object vertex/face counts must match exactly; the coordinate checksum may differ by
exact-Boolean floating noise only (< 0.05 on a sum of ~3.6k coordinates, i.e. micrometres).
Decimated LOD triangle counts may differ by +/-2 from tie-breaking.
"""
import json
import sys

a = json.load(open(sys.argv[1]))["results"]
b = json.load(open(sys.argv[2]))["results"]
problems = []
sig_a, sig_b = a["object_signatures"], b["object_signatures"]
if sorted(sig_a) != sorted(sig_b):
    problems.append("object name sets differ")
for name in sorted(set(sig_a) & set(sig_b)):
    (va, fa, ca), (vb, fb, cb) = sig_a[name], sig_b[name]
    if (va, fa) != (vb, fb) or abs(ca - cb) > 0.05:
        problems.append(f"{name}: {sig_a[name]} vs {sig_b[name]}")
for level in ("gameplay", "lod1", "lod2"):
    if abs(a["triangles"][level] - b["triangles"][level]) > (0 if level == "gameplay" else 2):
        problems.append(f"{level} triangles {a['triangles'][level]} vs {b['triangles'][level]}")
print(json.dumps({"idempotent": not problems, "objects": len(sig_a), "problems": problems[:10]}))
sys.exit(1 if problems else 0)
