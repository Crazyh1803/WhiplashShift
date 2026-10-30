"""Idempotently rewrite the TANGENT accessor bytes of every shipped city realism GLB with the canonical frame from
validate_city_families.compute_tangents (bitangent = cross(n, t) * w follows increasing exported v). Geometry, JSON and file size are untouched."""
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.expanduser("~/agent-kit/blender"))
from ak_util import report

sys.path.insert(0, os.path.join(os.getcwd(), "tools", "city_pipeline"))
import validate_city_families as VAL

REAL = VAL.DEFAULT_DIR
changed = []
for name in sorted(f for f in os.listdir(REAL) if f.endswith(".glb")):
    path = os.path.join(REAL, name)
    with open(path, "rb") as f:
        data = bytearray(f.read())
    size = len(data)
    js, binary = VAL.VIM.read_glb(path)
    off = 12
    bin_start = None
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        if ctype == b"BIN\x00":
            bin_start = off + 8
        off += 8 + clen
    tans = VAL.compute_tangents(js, binary)
    nbytes = 0
    flipped = 0
    for (mi, pi), rows in tans.items():
        acc = js["accessors"][js["meshes"][mi]["primitives"][pi]["attributes"]["TANGENT"]]
        bv = js["bufferViews"][acc["bufferView"]]
        start = bin_start + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        blob = b"".join(struct.pack("<4f", *r) for r in rows)
        assert len(blob) == acc["count"] * 16 and bv.get("byteStride", 16) == 16
        old = bytes(data[start:start + len(blob)])
        if old != blob:
            flipped += sum(1 for i in range(len(rows)) if old[i * 16:i * 16 + 16] != blob[i * 16:i * 16 + 16])
            nbytes += len(blob)
            data[start:start + len(blob)] = blob
    if nbytes:
        with open(path, "wb") as f:
            f.write(data)
    assert len(data) == size
    an = VAL.analyze(path)
    changed.append(f"{name} size={size} tris={an['tris']} tangent_rewritten_verts={flipped} bad={an['tangent_bad']} sha={hashlib.sha256(bytes(data)).hexdigest()[:12]}")
report(files=len(changed), out=changed)
