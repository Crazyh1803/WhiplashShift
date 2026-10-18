# Helix source review (Gemini, file-only prompts, scope = helix_* delta against baseline 8f03f5e)
Chunks: (1) trace/core/prims/body, (2) organic/tracks/details, (3) export/qa/build/validate. Deleted/unchanged baseline code not reviewed.

## Round 1 (tree d09f7c7)
- chunk 1: VERDICT APPROVE. LOW helix_body.py Surface leaks an evaluated mesh datablock -> fixed.
- chunk 2: VERDICT APPROVE. MED helix_tracks.py cleat spacing used the wrong loop perimeter (first/last pad overlapped by ~37 mm) -> fixed.
- chunk 3: VERDICT APPROVE, none.
Visual (ak-look, full-body + close-ups): two MEDs. (a) "upper pincer curves up instead of down": disproved numerically, the upper jaw top edge
sits at sheet py 180/182/184/188/191/195 for px 232/250/260/270/280/290 against the ink silhouette 176/176/187/184/191/197 (<=5 px).
(b) dark cap on the rear face between the claws: real, Body_Maw widened and extended (px 288..342) so it covers the hull end cap.
LOWs not changed: hose flange slightly overhangs carapace bevel, hull/carapace seam stepping, hoses shorter than the sheet's.

## Round 2 (changed chunks only: helix_body.py, helix_tracks.py)
Both VERDICT APPROVE, FINDINGS none. Visual re-look of the changed views and the three LODs: VERDICT PASS, none.
No tiebreak needed.
