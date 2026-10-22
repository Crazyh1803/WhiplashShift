# Stronger spray on the correct frame

All six special terrains now emit twice as frequently on the preferred frame.
Correct-frame size and throw-power settings increase by 20%. Wrong-frame rates,
size/power settings, body poses, handling, motion/contact gating and the shared
96-live-fragment budget are unchanged. Matched wrong-frame emission remains more
than twice the new correct-frame rate. Existing contrast tests reflect this
intentional rebalance; six new baseline checks verify doubled preferred output
and unchanged wrong-frame rates.

Actual chase captures use the same vehicle, initial motion, input and production
lighting as before. All six GPU scenes passed (163 checks total):

| Terrain | Correct frame | Old emitted | New emitted | Wrong emitted (unchanged) |
|---|---|---:|---:|---:|
| Viscera | B | 50 | 100 | 146 |
| Chitin rubble | B | 70 | 138 | 250 |
| Spinal armor | B | 28 | 58 | 146 |
| Vitrified coolant | A | 46 | 94 | 252 |
| Reactor effluent | B | 58 | 120 | 136 |
| Black ichor | A | 50 | 100 | 274 |

Emission counts include motion/spin variation and fractional carry. Matched-input
policy rates are exactly doubled. Captured speeds and pose metrics match the
previous captures for both frames. Preview folders use the `-boosted` suffix,
leaving prior images available for comparison. `--spray-preview` opts into these
capture folders without changing production behavior.

Validation: focused base scene 31 passed; GPU scenes 35/23/23/26/25/31 passed.
All 21 terrain-branch regression scenes passed in an isolated checkout containing
only this adjustment. Unrelated combat/CPU work remains untouched locally.
Logs: correct-frame-spray-focused.log, correct-frame-spray-rendered.log and
correct-frame-spray-full-test.log.

Independent ak-review and ak-look both failed due to exhausted Gemini quota.
No independent review or visual verdict was obtained. No images were loaded into
the lead's context. Prior correct-frame previews are retained alongside boosted
captures for human comparison.

Git synchronization: this focused adjustment follows the user's earlier request
to sync the terrain work on codex/track-visuals; independent review remains
unavailable as disclosed.
