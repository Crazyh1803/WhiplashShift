"""Rewrite the image URIs of every retained roadside textured export so they resolve to the shared city_realism textures (BIN chunk untouched).
    ak-blender tools/city_pipeline/repair_roadside_texture_uris.py
Idempotent; fails if any URI still does not resolve afterwards."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_roadside_common as R  # noqa: E402
from ak_util import report  # noqa: E402

fixed, bad = [], []
for name in sorted(os.listdir(R.TEXTURED)):
    if not name.endswith(".glb"):
        continue
    path = os.path.join(R.TEXTURED, name)
    js, binary = R.BIND.read_glb(path)
    for im in js.get("images", []):
        want = R.texture_uri(os.path.splitext(os.path.basename(im["uri"]))[0])
        if im["uri"] != want:
            im["uri"] = want
            if name not in fixed:
                fixed.append(name)
    if name in fixed:
        with open(path, "wb") as fh:
            fh.write(R.BIND.glb_bytes(js, binary))
    bad += R.validate_texture_uris(path)
report(files=len(os.listdir(R.TEXTURED)), repaired=fixed, unresolved=len(bad))
for b in bad:
    print("AK: PROBLEM", b)
if bad:
    raise SystemExit(1)
