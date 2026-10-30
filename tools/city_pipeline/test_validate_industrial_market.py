"""Negative COLOR_0 checks for validate_industrial_market.analyze() using temporary one-triangle GLBs (stdlib only).
Shipped assets are never touched. Run: python -I tools/city_pipeline/test_validate_industrial_market.py"""
import importlib.util
import json
import math
import os
import struct
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("validate_industrial_market", os.path.join(HERE, "validate_industrial_market.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

FLOAT, UBYTE, USHORT = 5126, 5121, 5123


def glb(color=None, color_type="VEC4", component=FLOAT, count=3, normalized=False):
    """One triangle with POSITION/NORMAL/TEXCOORD_0 and an optional COLOR_0 accessor."""
    chunks = [struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0), struct.pack("<9f", 0, 0, 1, 0, 0, 1, 0, 0, 1), struct.pack("<6f", 0, 0, 1, 0, 0, 1)]
    views = [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 36}, {"buffer": 0, "byteOffset": 72, "byteLength": 24}]
    accessors = [{"bufferView": 0, "componentType": FLOAT, "count": 3, "type": "VEC3"}, {"bufferView": 1, "componentType": FLOAT, "count": 3, "type": "VEC3"},
                 {"bufferView": 2, "componentType": FLOAT, "count": 3, "type": "VEC2"}]
    attributes = {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}
    if color is not None:
        code = {FLOAT: "f", UBYTE: "B", USHORT: "H"}[component]
        data = struct.pack("<%d%s" % (len(color), code), *color)
        data += b"\0" * (-len(data) % 4)
        views.append({"buffer": 0, "byteOffset": 96, "byteLength": len(data)})
        chunks.append(data)
        accessor = {"bufferView": 3, "componentType": component, "count": count, "type": color_type}
        if normalized:
            accessor["normalized"] = True
        accessors.append(accessor)
        attributes["COLOR_0"] = 3
    binary = b"".join(chunks)
    js = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}], "buffers": [{"byteLength": len(binary)}],
          "bufferViews": views, "accessors": accessors, "materials": [{"name": "m"}], "meshes": [{"primitives": [{"attributes": attributes, "material": 0}]}]}
    text = json.dumps(js, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(binary), b"BIN\x00") + binary
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


class ColorZeroTests(unittest.TestCase):
    def analyze(self, data):
        with tempfile.TemporaryDirectory(prefix="market_color_") as tmp:
            path = os.path.join(tmp, "fixture.glb")
            with open(path, "wb") as handle:
                handle.write(data)
            validator.errors.clear()
            return validator.analyze(path)

    def rejected(self, data):
        with self.assertRaises(ValueError) as caught:
            self.analyze(data)
        self.assertIn("COLOR_0", str(caught.exception))

    def test_valid_vec4_and_vec3_float_colors_pass(self):
        self.assertEqual(self.analyze(glb([0.5] * 12))["tris"], 1)
        self.assertEqual(self.analyze(glb([1.0] * 9, "VEC3"))["tris"], 1)

    def test_valid_normalized_integer_colors_pass(self):
        self.assertEqual(self.analyze(glb([255, 128, 0, 255] * 3, component=UBYTE, normalized=True))["tris"], 1)

    def test_missing_color_is_rejected(self):
        self.rejected(glb(None))

    def test_wrong_vertex_count_is_rejected(self):
        self.rejected(glb([0.5] * 8, count=2))

    def test_wrong_accessor_type_is_rejected(self):
        self.rejected(glb([0.5] * 6, "VEC2", count=3))
        self.rejected(glb([0.5] * 3, "SCALAR"))

    def test_nonfinite_values_are_rejected(self):
        for bad in (math.nan, math.inf, -math.inf):
            self.rejected(glb([0.5] * 11 + [bad]))

    def test_out_of_range_values_are_rejected(self):
        for bad in (-0.01, 1.01, 1e30):
            self.rejected(glb([0.5] * 11 + [bad]))
        self.rejected(glb([1] * 11 + [200], component=UBYTE))

    def test_flat_color_on_a_small_materialless_fixture_passes_analyze(self):
        info = self.analyze(glb([0.5] * 12))
        self.assertEqual(info["color_spread"], 0.0)       # real-asset flatness is gated per asset in check_asset, not per primitive

    def test_bad_color_surfaces_as_unreadable_glb_failure(self):
        with tempfile.TemporaryDirectory(prefix="market_color_") as tmp:
            with open(os.path.join(tmp, "redline_shop.glb"), "wb") as handle:
                handle.write(glb(None))
            validator.errors.clear()
            self.assertIsNone(validator.check_asset("redline_shop", {"glb": "redline_shop.glb"}, tmp))
            self.assertTrue(any("unreadable GLB" in message and "COLOR_0" in message for message in validator.errors))
            validator.errors.clear()


class ShippedAssetAttributes(unittest.TestCase):
    """Read-only checks of the real GLBs. Godot reads only COLOR_0 and TEXCOORD_0 for albedo/normal/ORM."""

    def glbs(self):
        for asset in validator.ASSETS:
            yield asset, validator.read_glb(os.path.join(validator.DEFAULT_DIR, asset + ".glb"))

    def analyze(self, asset):
        validator.errors.clear()
        return validator.analyze(os.path.join(validator.DEFAULT_DIR, asset + ".glb"))

    def test_color_0_carries_the_baked_wear(self):
        for asset, (js, _) in self.glbs():
            self.assertGreater(self.analyze(asset)["color_spread"], validator.MIN_WEAR_SPREAD, asset)
            for prim in js["meshes"][0]["primitives"]:
                self.assertEqual([k for k in prim["attributes"] if k.startswith(("COLOR_", "TEXCOORD_")) and k not in ("COLOR_0", "TEXCOORD_0")], [], asset)

    def test_texcoord_0_is_mapped_for_every_textured_material(self):
        for asset in validator.ASSETS:
            spans = self.analyze(asset)["uv_span"]
            self.assertTrue(spans, asset)
            for name, (du, dv) in spans.items():
                self.assertGreater(max(du, dv), validator.MIN_UV_SPAN, f"{asset}/{name}")

    def test_texture_maps_use_texcoord_0(self):
        for asset, (js, binary) in self.glbs():
            for material in js["materials"]:
                refs = [material.get("normalTexture"), material.get("emissiveTexture"), material.get("occlusionTexture"),
                        material.get("pbrMetallicRoughness", {}).get("baseColorTexture"), material.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")]
                for ref in refs:
                    if ref:
                        self.assertEqual(ref.get("texCoord", 0), 0, f"{asset}/{material.get('name')}")


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
