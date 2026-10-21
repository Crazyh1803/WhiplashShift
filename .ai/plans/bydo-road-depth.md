# Make road hazards explain the frame change

The shader-only pass reads as painted flat ground. Give B-preferred rough/soft
sections actual bounded road relief shared by visual and collision meshes, plus
large raised verge deposits at transitions. Keep A-preferred ice/ichor smooth so
the silhouette difference explains speed frame versus terrain frame.

1. Add deterministic metre-space height profiles for chitin ballast, wet viscera,
   fractured armor and low effluent ripples. Fade to zero at run joins and road
   edges. Tessellate only these surface runs; retain exact original flat geometry
   for ceramic, curbs, ice and oil. Use the same vertices for mesh and collider.
2. Add batched larger bone fragments/tendon heaps outside the guardrails at rough
   run entries and along rough runs, with clearance against other course branches.
   No isolated fake obstacles in driving lanes; keep height bounds conservative.
3. Test deterministic bounded relief, flat joins/edges, upward nondegenerate
   triangles, visual/collision equality and wheel raycast contacts. Golden flat
   collider hashes stay authoritative for smooth surfaces. Run physics/race/CPU
   regression and rendered driver-height captures with ak-test; request ak-look
   and ak-review. Existing physics coefficients and frame tuning remain unchanged.

Physics regression follow-up: the old Hard-leader speed gate had only 3.6 m
margin on a 420 s flat-track control. Real relief changed the field's distance
split by ~0.2–0.3%, while total field distance remained unchanged. Two profile
probes and physics escalation are recorded in the task report. Keep both 20%
leader and 15% field gates on an explicit original-flat-geometry control, verified
against all original collider hashes. Live relief still runs the full multi-lap
stability/difficulty tests and must retain at least 98% of flat-control field
progress. No CPU tuning, vehicle coefficients or historical thresholds change.
