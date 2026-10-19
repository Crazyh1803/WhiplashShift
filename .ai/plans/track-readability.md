# Track readability and tactical swaps

Goal: drivers can anticipate terrain changes and prepare swaps on the existing
course. Preserve control, physics, CPU strategy and race rules.

1. Derive upcoming meaningful surface boundaries from the configured course;
   skip rumble as a destination, and describe ice/oil as low grip with no extra
   turnaround recommendation. Use route distance and speed for advance HUD cues.
2. Build lightweight, collision-free approach boards outside the rails, with
   surface names and end recommendations. Both sides face approaching traffic.
3. Add a compact upcoming-terrain HUD cue during racing, suppressed off-course
   and while travelling backwards. Avoid covering controls, race clock or results.
4. Test transition distances including the finish seam, advice for both ends,
   no course mutation, no forced swap, and actual scene/UI/board integration.
   Capture approach views, run ak-look, ak-test and ak-review against the completed
   race-loop branch; fix findings within the normal review-round limit.

No generated textures, new courses, weapons, handling changes or penalties.

Rendered QA exposed streamed-audio shutdown ordering in the short terrain fixture.
Apply the escalation engineer's explicit playback teardown and allow the live
mixer to retire it before fixture exit; verify with verbose rendered logs.
