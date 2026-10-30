"""Geometry-only runtime GLBs for the city realism library (stdlib only).

Godot reimports (and resets the sidecars of) every PNG a scene import loads, so the shipped runtime GLBs carry NO images, textures or samplers.
Each material is a named stub whose extras.library_binding equals its exact name; CityRealismCatalog replaces every material by that name from
the shared material library. The full textured exports are retained outside godot/ in assets/generated/city_realism/textured_exports/ and
reference the shared PNGs by relative URI (../textures/<material>_<slot>.png).

    strip_to_library(js)        in-place: drop images/textures/samplers/texture slots, stamp extras.library_binding
    split_runtime(path)         textured GLB at `path` -> (textured_export, runtime stub) written by `convert`
Usage: python city_realism_bind.py convert [realism_dir]     (idempotent: already-stripped GLBs are left alone)
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REAL = os.path.join(ROOT, "godot", "assets", "city", "realism")
TEXTURED = os.path.join(ROOT, "assets", "generated", "city_realism", "textured_exports")
TEXTURE_SLOTS = ("baseColorTexture", "metallicRoughnessTexture", "normalTexture", "emissiveTexture", "occlusionTexture")


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    off, js, binary = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        body = data[off + 8:off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(body.decode("utf-8"))
        elif ctype == b"BIN\x00":
            binary = body
        off += 8 + clen
    return js, binary


def glb_bytes(js, binary):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    binary = bytes(binary) + b"\0" * ((4 - len(binary) % 4) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(jb) + 8 + len(binary))
    return out + struct.pack("<I4s", len(jb), b"JSON") + jb + struct.pack("<I4s", len(binary), b"BIN\x00") + binary


def _has_texture_ref(value):
    if isinstance(value, dict):
        return "index" in value or any(_has_texture_ref(v) for v in value.values())
    return False


def strip_to_library(js):
    """Remove every image reference from a glTF dict and stamp each material with extras.library_binding = its exact name."""
    for k in ("images", "textures", "samplers"):
        js.pop(k, None)
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for slot in TEXTURE_SLOTS:
            pbr.pop(slot, None)
            m.pop(slot, None)
        for ext in list(m.get("extensions", {})):
            if _has_texture_ref(m["extensions"][ext]) or ext == "KHR_texture_transform":
                del m["extensions"][ext]
        if not m.get("extensions"):
            m.pop("extensions", None)
        m["extras"] = {"library_binding": m["name"]}
    used = {e for m in js.get("materials", []) for e in m.get("extensions", {})}
    for key in ("extensionsUsed", "extensionsRequired"):
        if key in js:
            js[key] = [e for e in js[key] if e != "KHR_texture_transform" and (e in used or not e.startswith("KHR_materials_"))]
            if not js[key]:
                del js[key]
    return js


def textured_uri(uri):
    return "../" + uri if uri and not uri.startswith(("../", "/")) and ":" not in uri else uri


def write_pair(js, binary, textured_path, runtime_path):
    """js still carries images with uri textures/<name>.png. Writes the retained textured export (uris relative to its own folder) and the stripped runtime GLB."""
    import copy
    full = copy.deepcopy(js)
    for im in full.get("images", []):
        im["uri"] = textured_uri(im["uri"])
    os.makedirs(os.path.dirname(textured_path), exist_ok=True)
    with open(textured_path, "wb") as f:
        f.write(glb_bytes(full, binary))
    with open(runtime_path, "wb") as f:
        f.write(glb_bytes(strip_to_library(copy.deepcopy(js)), binary))


def convert(real=REAL, textured=TEXTURED):
    done = []
    for name in sorted(f for f in os.listdir(real) if f.endswith(".glb")):
        path = os.path.join(real, name)
        js, binary = read_glb(path)
        if not js.get("images"):
            continue
        write_pair(js, binary, os.path.join(textured, name), path)
        done.append(name)
    return done


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if argv[:1] != ["convert"]:
        raise SystemExit(__doc__)
    print(json.dumps({"converted": convert(*(argv[1:2] or [REAL]))}))
