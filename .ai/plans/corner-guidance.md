# Corner approach guidance

Build on accepted terrain cues and smooth rendering. Derive contiguous bends
from signed centreline curvature; describe direction and severity, including the
hairpin and bends that cross the finish seam. Ignore sampling noise and straight
segments. Keep terrain advice visible alongside corner information.

Provide advisory corner speeds using the selected vehicle's current end, tuning,
grip and upcoming surface; estimate braking lead from braking capability with a
conservative margin. Advisory only: never write controls, swap, tuning, CPU policy
or race progress. Show a prominent slowing cue when approaching too quickly,
hold the corner label through the bend, and suppress advice off-route/wrong-way,
during countdown/results. Use one existing lower HUD region with layout tests.

Test synthetic straight/left/right/hairpin/seam/noise courses, speed/braking
response to grip/end/vehicle modifiers, no control/physics mutation, and real
course/HUD integration. Capture rendered approaches at both window sizes. Run
ak-test, ak-look and ak-review; document quota blockers explicitly if still present.
Do not add final art or change road geometry/handling in this milestone.
