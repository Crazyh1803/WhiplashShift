# Bydo-Grid secondary road surfaces

## Change

Replaced the remaining natural terrain appearances with seven procedural
biomechanical skins. The approved ceramic road and hazard-curb designs remain.

| Physical ID | Appearance |
| --- | --- |
| Gravel | Small angular chitin rubble over pulverized carbon |
| Mud | Wet coral viscera, muscle ropes, dark vessels and scar tissue |
| Boulder | Broad fractured spinal armor with chipped lips and deep joints |
| Ice | Vitrified coolant with pale glass fractures and faint cyan capillaries |
| Water | Slowly circulating reactor effluent with cellular scum and foam |
| Oil | Black ichor with restrained oily interference swirls |
| Off | Matte carbon debris with sparse chitin fragments |

World-space irregular shard masks separate rubble, slabs and coolant fractures
by scale and response. Derivative relief normals add lighting detail without
vertex displacement. The viscera shader binds the scenery flesh's dedicated
normal/roughness textures and outputs SSS plus wet clearcoat; other materials
have distinct roughness/specular responses. Broad emission stays subdued.

Driving surface IDs, grip/drag/damage, preferred ends, HUD names and all collision
geometry remain unchanged. This is code-native material work in the existing
feature branch; pending user work was preserved.

## Verification

- Headless focused ak-test: 189 passed, 0 failed.
- Rendered Vulkan ak-test: 221 passed, 0 failed; no shader/engine errors.
  Log: `.ai/reports/bydo-road-surfaces-rendered.log`.
- Added material-map binding checks. Existing golden collider hashes, road UVs,
  clearance, local-light and environment checks continue to pass.
- Added nine material captures under identical neutral, cyan and amber local
  lights in `.ai/captures/bydo-surfaces/`. Six actual track captures in
  `.ai/captures/track-sample/` also rendered. Viscera and rubble opened for the
  user's inspection. Captures exercise every surface shader branch on Vulkan;
  they do not constitute automated aesthetic approval.
- Full ak-test: PASS (exit 0), all 17 scenes, no engine/script errors.
  Log: `.ai/reports/bydo-road-surfaces-full-test.log`.
- git diff --check: pass.

## Review

An isolated four-file Git snapshot captured the pre-task working files, allowing
ak-review HEAD to review only this task's patch without the prior branch's
argument-size failure. No changes to the primary repo's commit history or index
were needed for this review snapshot.

Both code review and visual QA failed because Gemini's individual quota is
exhausted (RESOURCE_EXHAUSTED 429). Logs:
`.ai/reviews/road-surfaces-20261019-212731-gemini.md.log` and
`.ai/looks/20261019-212731.md.log`. No independent verdict or visual PASS was
produced; the previous `.ai/reviews/latest.md` is unrelated. Changes remain
uncommitted. Aesthetic inspection and GPU performance profiling remain open.
