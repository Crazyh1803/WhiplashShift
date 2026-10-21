# Bydo-Grid road depth and frame legibility

## Result

The texture-only secondary surfaces now have real shared mesh/collider relief
and larger raised roadside deposits. The intent is to distinguish rough/soft
B terrain from smooth A surfaces through geometry, silhouettes and parallax.
Aesthetic success still requires human inspection; no visual-review PASS exists.

- `TrackRelief` subdivides existing road quads, without resampling the course.
  Bounded positive height fields keep the track above the global ground plane.
  Bounds: chitin gravel 3 cm, viscera/mud 5 cm, fractured armor 8 cm, effluent
  2 cm. End fade 3.5 m, side fade 3 m; measured gradients stay below 0.08.
- Raised mesh vertices are exactly the collider faces. Normals follow the
  actual triangles; wheel rays see the visible bumps. Smooth ceramic, curbs,
  ice and ichor retain their exact original flat collision hashes.
- Large faceted chitin/armor heaps, wet tendon banks and effluent banks sit
  beyond the guardrails, at entries and through rough sections. Four MultiMesh
  batches; each footprint is checked against all course branches/proving ground.
  These deposits are decorative and outside the driveable racing boundary.
- Existing surface coefficients, vehicle tuning, frame behavior and route data
  are unchanged. Actual terrain relief can still change lap performance.
- Low chase captures now use a 2.5 m camera; gravel, armor and effluent gained
  actual track views. Material gallery rough surfaces now use production
  tessellated meshes rather than flat swatches.

## Validation

- Architecture/physics consultation:
  `.ai/escalations/20261019-215046-design-claude.md`. Conservative relief was
  chosen because single-ray wheels can alias and launch on large short bumps.
- Headless focused ak-test: 214 passed, 0 failed.
  `.ai/reports/bydo-road-depth-verification.log`.
- Rendered Vulkan ak-test: 250 passed, 0 failed; no engine/shader errors.
  `.ai/reports/bydo-road-depth-verification.log`.
- Height/gradient samples at 0.1 m intervals, flat edges/joins, geometric triangle
  normals >= 0.995 in Y, determinism, exact visual/collider equality, smooth
  golden hashes, footprint clearance and downward contact-ray coverage pass.
- Both frames physically entered all four raised surfaces at 50 m/s, with zero
  missed contact steps. Maximum measured roll <0.01 degrees; lateral drift
  <0.004 m. These coasting straight tests check stability, not a required shift
  or measured acceleration advantage. Existing surface modifiers still provide
  the frame preference.
- Controlled Hard CPU check: 46 passed. Flat control reproduces historical
  values exactly: leader 9,132.60 m and field 18,003.97 m in 420 s; unchanged
  20% leader/15% field improvement requirements pass. Live relief field distance
  is 18,006.03 m, within the added 2% maximum-loss bound.
  Log: `.ai/reports/bydo-road-depth-controlled-cpu.log`.
- Full ak-test: PASS (exit 0), all 17 scenes, no engine/script errors.
  Expanded CPU suite: 73 passed, 0 failed.
  Log: `.ai/reports/bydo-road-depth-full-test.log`.
- git diff --check: pass.

## Pace benchmark correction

The initial full run had one failure: the Hard leader covered 9,104.68 m,
compared with a historical flat-course threshold of 9,129.03 m (original flat
leader 9,132.60 m). Removing lateral relief did not recover it; broader swells
kept total field performance unchanged while redistributing progress between
racers. Physics advice is recorded in
`.ai/escalations/20261020-064344-debug-claude.md` and
`.ai/escalations/20261020-064619-debug-claude.md`.

The final shape retains the same peak heights, using broader longitudinal
swells (0.3 rad/m on gravel, 0.2 mud/armor, 0.15 effluent). Rather than tuning
terrain/AI to a historical benchmark with only 3.6 m of margin, the tests now
run an additional explicit flat control. Its every collision hash matches the
original course. The historical pace gates are unchanged and run on that control;
the live-relief scene still runs all difficulty/lap/stability checks and is
required to keep at least 98% of flat field progress. No new baseline was invented
and no historical pass threshold was lowered. The earlier failed full run and
two diagnostic probes remain saved as `bydo-road-depth-first-full-test.log`,
`bydo-road-depth-longitudinal-probe.log`, `bydo-road-depth-broad-wave-probe.log`.

## Review and outstanding checks

Independent code review used an isolated baseline of the pre-task working files,
so pending unrelated branch changes were not included. Both ak-review and ak-look
failed because Gemini's individual quota remains RESOURCE_EXHAUSTED (429).
Final-attempt logs: `.ai/reviews/road-depth-final-20261020-064927-gemini.md.log`
and `.ai/looks/20261020-064955.md.log`. No new latest.md verdict was produced.
Changes remain uncommitted. Review and driving-height visual acceptance remain
open, along with GPU/physics performance profiling on the target hardware.

Current captures: `.ai/captures/track-sample/mud-corner-driver.png`,
`gravel-depth-driver.png`, `boulder-depth-driver.png`, `water-depth-driver.png`.
The viscera/armor driver captures were opened in Codex for human inspection.
