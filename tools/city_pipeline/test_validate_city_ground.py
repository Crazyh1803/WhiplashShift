"""Checks for validate_city_ground.py: the real ground kit is valid, a fresh rebuild is byte-identical, and corrupted copies are rejected (stdlib only).
Run: python tools/city_pipeline/test_validate_city_ground.py"""
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate_city_ground as V  # noqa: E402


class GroundKit(unittest.TestCase):
    def copy_root(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        for rel in ("godot/assets/city/ground", "assets/generated/city_ground", "godot/assets/city/realism/city_families_manifest.json"):
            src = os.path.join(V.ROOT, *rel.split("/"))
            dst = os.path.join(tmp, *rel.split("/"))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copytree(src, dst) if os.path.isdir(src) else shutil.copyfile(src, dst)
        return tmp

    def test_real_kit_is_valid_and_rebuilds_identically(self):
        self.assertEqual(V.validate(V.ROOT, rebuild=True), [])

    def test_stale_manifest_is_rejected(self):
        tmp = self.copy_root()
        path = os.path.join(tmp, "godot", "assets", "city", "ground", "city_ground_manifest.json")
        with open(path, encoding="utf-8") as f:
            man = json.load(f)
        man["assets"][0]["tris"] += 2
        man["assets"][1]["aabb"]["max"][1] = 0.2
        with open(path, "w", encoding="utf-8") as f:
            json.dump(man, f)
        problems = V.validate(tmp, rebuild=False)
        self.assertTrue(any("road_apron: manifest tris" in p for p in problems), problems)
        self.assertTrue(any("service_lane: manifest aabb" in p for p in problems), problems)

    def test_cap_and_height_limits_are_enforced(self):
        old = dict(V.TRI_CAP), V.Y_MAX
        self.addCleanup(lambda: (V.TRI_CAP.update(old[0]), setattr(V, "Y_MAX", old[1])))
        V.TRI_CAP["road_apron"] = 20
        V.Y_MAX = 0.01
        problems = V.validate(V.ROOT, rebuild=False)
        self.assertTrue(any("road_apron: 24 tris exceeds" in p for p in problems), problems)
        self.assertTrue(any("above 0.01" in p for p in problems), problems)

    def test_runtime_glb_with_a_texture_is_rejected(self):
        tmp = self.copy_root()
        src = os.path.join(tmp, "assets", "generated", "city_ground", "textured_exports", "utility_verge.glb")
        shutil.copyfile(src, os.path.join(tmp, "godot", "assets", "city", "ground", "utility_verge.glb"))
        problems = V.validate(tmp, rebuild=False)
        self.assertTrue(any("utility_verge: runtime GLB carries images" in p for p in problems), problems)

    def test_missing_textured_source_is_reported_on_rebuild(self):
        tmp = self.copy_root()
        os.remove(os.path.join(tmp, "assets", "generated", "city_ground", "textured_exports", "road_apron.glb"))
        problems = V.validate(tmp, rebuild=True)
        self.assertTrue(any("road_apron: textured source" in p and "is missing" in p for p in problems), problems)
        self.assertFalse(any("road_apron: textured source differs" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
