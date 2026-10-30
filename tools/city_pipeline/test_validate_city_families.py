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

    def test_rejects_missing_texture_and_bad_lod(self):
        def bad(man):
            man["materials"]["brick"]["albedo"] = "textures/missing.png"
            man["assets"][0]["lod1_surfaces"] = ["brick"]
        errs = self._mutated(bad)
        self.assertTrue(any("missing" in e for e in errs))
        self.assertTrue(any("lod1 surfaces" in e for e in errs))


if __name__ == "__main__":
    unittest.main()
