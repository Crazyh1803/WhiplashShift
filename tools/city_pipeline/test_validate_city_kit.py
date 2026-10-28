"""Corruption checks for validate_city_kit.py using copies of the real kit (stdlib only).
Run: python tools/city_pipeline/test_validate_city_kit.py"""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "godot", "assets", "city", "kit")
VALIDATOR = os.path.join(HERE, "validate_city_kit.py")


def parse(data):
    clen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + clen])
    boff = 20 + clen
    return js, boff + 8, boff


def rebuild(js, binary):
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    body = struct.pack("<I4s", len(j), b"JSON") + j + struct.pack("<I4s", len(binary), b"BIN\x00") + binary
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def run(mutate):
    tmp = tempfile.mkdtemp(prefix="citykit_")
    try:
        for f in os.listdir(KIT):
            if f.endswith((".glb", ".json")):
                shutil.copy(os.path.join(KIT, f), tmp)
        p = os.path.join(tmp, "exchange_hall.glb")
        if mutate:
            data = bytearray(open(p, "rb").read())
            js, bstart, _ = parse(bytes(data))
            binary = bytearray(data[bstart:])
            js = mutate(js, binary)
            open(p, "wb").write(rebuild(js, bytes(binary)))
        r = subprocess.run([sys.executable, "-I", VALIDATOR], env={**os.environ, "CITY_KIT_DIR": tmp},
                           capture_output=True, text=True)
        return r.returncode, r.stdout
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def move_vertex(js, binary):
    # Push one vertex 50 m away while leaving the declared accessor min/max untouched.
    a = js["accessors"][js["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    bv = js["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    x = struct.unpack_from("<f", binary, off)[0]
    struct.pack_into("<f", binary, off, x + 50.0)
    return js


def blacken_glow(js, binary):
    for m in js["materials"]:
        if m["name"].startswith("glow_"):
            m["emissiveFactor"] = [0, 0, 0]
    return js


def drop_strength(js, binary):
    for m in js["materials"]:
        m.get("extensions", {}).pop("KHR_materials_emissive_strength", None)
    return js


def truncate_view(js, binary):
    a = js["accessors"][js["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    a["count"] += 100000
    return js


def main():
    fails = []
    code, out = run(None)
    if code != 0:
        fails.append(f"pristine copy should pass: {out}")
    for name, mut, needle in (("moved vertex", move_vertex, "POSITION min/max"),
                              ("blackened glow", blacken_glow, "emissiveFactor"),
                              ("no emissive strength", drop_strength, "emissive_strength"),
                              ("bad count", truncate_view, "outside bufferView"),
                              ("negative offset", lambda js, b: change_position(js, "byteOffset", -12), "nonnegative integers"),
                              ("fractional offset", lambda js, b: change_position(js, "byteOffset", 0.5), "nonnegative integers"),
                              ("NaN bounds", lambda js, b: change_position(js, "min", [float("nan"), 0, 0]), "finite numeric"),
                              ("NaN glow strength", nan_strength, "emissive_strength")):
        code, out = run(mut)
        ok = code == 1 and needle in out
        print(("ok   " if ok else "FAIL ") + name)
        if not ok:
            fails.append(f"{name}: exit {code}\n{out}")
    for f in fails:
        print(f)
    return 1 if fails else 0


def change_position(js, field, value):
    js["accessors"][js["meshes"][0]["primitives"][0]["attributes"]["POSITION"]][field] = value
    return js


def nan_strength(js, binary):
    for material in js["materials"]:
        if material["name"].startswith("glow_"):
            material["extensions"]["KHR_materials_emissive_strength"]["emissiveStrength"] = float("nan")
    return js


sys.exit(main())
