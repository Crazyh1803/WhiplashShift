"""Tests for validate_city_families (stdlib unittest): the shipped realism library passes, and the validator really rejects broken data.
Run: python -m unittest tools/city_pipeline/test_validate_city_families.py   (or ak-blender tools/city_pipeline/validate_city_families.py)"""
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_city_families as V  # noqa: E402


class CityRealism(unittest.TestCase):
    def setUp(self):
        V.errors.clear()

    def test_shipped_library_passes(self):
        costs, tex = V.validate(V.DEFAULT_DIR)
        self.assertEqual(V.errors, [])
        self.assertEqual(sorted(costs["buildings"]), sorted(V.BUILDINGS))
        self.assertEqual(sorted(costs["streets"]), sorted(V.STREETS))
        self.assertLess(tex, 128.0)

    def test_manifest_contract(self):
        man = V.load_manifest(V.DEFAULT_DIR)
        self.assertEqual(man["version"], 2)
        self.assertEqual(set(man["emission_whitelist"]), {"sign_atlas", "lamp_glass"})
        for a in man["assets"]:
            self.assertIn("light_anchors", a)
            if a["role"] == "building":
                self.assertLessEqual(a["lod1_tris"], 2000)
                self.assertLessEqual(len(a["lod1_surfaces"]), 3)

    def _mutated(self, fn):
        d = tempfile.mkdtemp()
        try:
            for root, _, files in os.walk(V.DEFAULT_DIR):
                for f in files:
                    rel = os.path.relpath(os.path.join(root, f), V.DEFAULT_DIR)
                    os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
                    shutil.copyfile(os.path.join(root, f), os.path.join(d, rel))
            man = V.load_manifest(d)
            fn(man)
            with open(os.path.join(d, "city_families_manifest.json"), "w", encoding="utf-8") as fh:
                json.dump(man, fh)
            V.errors.clear()
            V.validate(d)
            return list(V.errors)
        finally:
            shutil.rmtree(d)

    def test_rejects_wrong_tris_and_emission_flag(self):
        def bad(man):
            man["assets"][0]["tris"] += 1
            man["materials"]["concrete"]["emission"]["allowed"] = True
        errs = self._mutated(bad)
        self.assertTrue(any("tris" in e for e in errs))
        self.assertTrue(any("emission flag" in e for e in errs))

    def test_redline_actor_sockets(self):
        man = V.load_manifest(V.DEFAULT_DIR)
        sk = next(a for a in man["assets"] if a["id"] == "redline_shop")["actor_sockets"]
        self.assertEqual(sk["vendor"]["yaw_degrees"], 0.0)
        self.assertEqual(sk["customer"]["yaw_degrees"], 180.0)
        self.assertAlmostEqual(sk["counter_top_y"] - sk["vendor"]["position"][1], 1.05)
        self.assertEqual(sk["vendor"]["position"][1], sk["customer"]["position"][1])

    def test_rejects_bad_actor_sockets(self):
        def bad(man):
            sk = next(a for a in man["assets"] if a["id"] == "redline_shop")["actor_sockets"]
            sk["customer"]["yaw_degrees"] = 0.0
            sk["customer"]["position"][1] = 0.0
            sk["light"] = {"id": "nope"}
        errs = self._mutated(bad)
        self.assertTrue(any("customer socket yaw" in e for e in errs))
        self.assertTrue(any("one floor" in e for e in errs))
        self.assertTrue(any("actor light" in e for e in errs))

    def test_rejects_missing_actor_sockets(self):
        def bad(man):
            del next(a for a in man["assets"] if a["id"] == "redline_shop")["actor_sockets"]
        self.assertTrue(any("actor_sockets missing" in e for e in self._mutated(bad)))

    @staticmethod
    def _quad(us):
        """One glTF-space quad facing +Z; v = 1 - y (image top at +y, as the Blender exporter writes it); us = per-vertex u."""
        import struct
        pos = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
        uv = [(us[i], 1.0 - p[1]) for i, p in enumerate(pos)]
        blob = b"".join(struct.pack("<3f", *p) for p in pos) + b"".join(struct.pack("<3f", 0, 0, 1) for _ in pos)
        blob += b"".join(struct.pack("<2f", *t) for t in uv) + struct.pack("<6H", 0, 1, 2, 0, 2, 3)
        blob += b"\0\0"
        js = {"materials": [{"normalTexture": {"index": 0}}], "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
              "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 48}, {"buffer": 0, "byteOffset": 48, "byteLength": 48}, {"buffer": 0, "byteOffset": 96, "byteLength": 32},
                              {"buffer": 0, "byteOffset": 128, "byteLength": 12}],
              "accessors": [{"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3"}, {"bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"},
                            {"bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"}, {"bufferView": 3, "componentType": 5123, "count": 6, "type": "SCALAR"}]}
        return js, blob

    def test_tangent_handedness_from_exported_uv(self):
        # unmirrored: u grows with +x, exported v decreases with +y (dP/dv = -y) -> tangent +x, cross(n, t) = +y, so w = -1
        js, blob = self._quad([0, 1, 1, 0])
        t = V.compute_tangents(js, blob)[(0, 0)]
        for tx, ty, tz, w in t:
            self.assertAlmostEqual(tx, 1.0, places=5)
            self.assertEqual(w, -1.0)
        # mirrored in u: tangent follows +u (-x), cross(n, t) = -y = dP/dv, so w = +1
        js2, blob2 = self._quad([1, 0, 0, 1])
        for tx, ty, tz, w in V.compute_tangents(js2, blob2)[(0, 0)]:
            self.assertAlmostEqual(tx, -1.0, places=5)
            self.assertEqual(w, 1.0)

    def test_tangent_frame_check_catches_reversed_handedness(self):
        import struct
        js, blob = self._quad([0, 1, 1, 0])
        good = V.compute_tangents(js, blob)[(0, 0)]

        def with_tangents(rows):
            b = bytes(blob) + b"".join(struct.pack("<4f", *r) for r in rows)
            j = json.loads(json.dumps(js))
            j["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": 64})
            j["accessors"].append({"bufferView": 4, "componentType": 5126, "count": 4, "type": "VEC4"})
            j["meshes"][0]["primitives"][0]["attributes"]["TANGENT"] = 4
            return j, b
        self.assertEqual(V.tangent_frame_errors(*with_tangents(good)), 0)
        self.assertGreater(V.tangent_frame_errors(*with_tangents([(a, b, c, -w) for a, b, c, w in good])), 0)

    def test_shipped_tangents_and_emissive_strengths(self):
        man = V.load_manifest(V.DEFAULT_DIR)
        for a in man["assets"]:
            an = V.analyze(os.path.join(V.DEFAULT_DIR, a["glb"]))
            self.assertEqual(an["tangent_bad"], 0, a["id"])
            for m in an["materials"]:
                if m["name"] in V.EMISSIVE_WHITELIST:
                    self.assertAlmostEqual(m["emissive_strength"], man["materials"][m["name"]]["emission"]["strength"], places=3, msg=a["id"])

    def test_market_arcade_is_open(self):
        """No brick surface may sit inside the arcade volume between the colonnade and the recessed back wall (glTF: front z=0, depth +z)."""
        an = V.analyze(os.path.join(V.DEFAULT_DIR, "market_habitat.glb"))
        js, binary = an["js"], V.VIM.read_glb(os.path.join(V.DEFAULT_DIR, "market_habitat.glb"))[1]
        for mesh in js["meshes"]:
            for prim in mesh["primitives"]:
                if js["materials"][prim["material"]]["name"] != "brick":
                    continue
                pos = V.VIM.accessor(js, binary, prim["attributes"]["POSITION"])
                idx = [r[0] for r in V.VIM.accessor(js, binary, prim["indices"])]
                for t in range(0, len(idx), 3):
                    c = [sum(pos[idx[t + j]][k] for j in range(3)) / 3 for k in range(3)]
                    self.assertFalse(abs(c[0]) < 8.8 and 0.1 < c[2] < 2.2 and c[1] < 3.6, f"brick inside the arcade at {c}")

    def test_rejects_missing_texture_and_bad_lod(self):
        def bad(man):
            man["materials"]["brick"]["albedo"] = "textures/missing.png"
            man["assets"][0]["lod1_surfaces"] = ["brick"]
        errs = self._mutated(bad)
        self.assertTrue(any("missing" in e for e in errs))
        self.assertTrue(any("lod1 surfaces" in e for e in errs))


if __name__ == "__main__":
    unittest.main()
