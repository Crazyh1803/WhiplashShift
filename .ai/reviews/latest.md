VERDICT: APPROVE
FINDINGS:
- [MED] godot/tests/combat_hud_visual_qa.gd:60 — The “exhausted-expiring-wrecked” capture shows EMPTY: the previous rockets ammo count is 2, so clearing the weapon fails the exhaustion check requiring at most 1 remaining round. — Render an update with one rocket remaining before consuming it, and assert EXHAUSTED before capturing.