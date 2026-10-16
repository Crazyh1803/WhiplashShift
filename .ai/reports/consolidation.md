# Whiplash consolidation — 2026-10-16

The current `Whiplash` repository now contains the latest saved gameplay/garage work
from `Whiplash Shift`, its Blackjack sources and revisions, and the existing Deadbolt
asset commit from `Whiplash Shift - Deadbolt`. Original worktrees were not edited.
Branch: `codex/consolidate-latest`.

## Preservation and integration

- Original Blackjack history retained from 4c93eed.
- Deadbolt 2b0ee45 cherry-picked as 8b61cb3.
- Main worktree's saved, previously uncommitted work preserved in 20da55e.
- All 20 Blackjack GLBs and three Deadbolt GLBs match their source files byte-for-byte.
- Native Blender/Krita sources, material graphs, blueprint references, browser
  prototype, plans and historical reports are retained. Blender backup files,
  generated editor caches and browser bridge metadata were excluded.
- Deadbolt is connected to the actual garage/player/CPU factory. Its authored wheels
  follow suspension/steering and its axles follow the rendered hubs. Only the three
  paint materials are recolored; original handling and collider are preserved.
- Generation config resolves this project's seven saved reference images and no
  longer writes into the original worktree.
- Garage canvas scaling, opaque customization popup, CPU HUD width and chase camera
  framing are repaired for the available display. Godot 4.7.2 updated normal import
  metadata and project version on first editor open.

## Validation

Latest results for each suite, using installed Godot 4.7.2/Jolt:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Core handling | 61 | 0 |
| CPU integration | 17 | 0 |
| Blackjack refined | 670 | 0 |
| Blackjack blueprint | 3555 | 0 |
| Consolidation | 54 | 0 |
| Total | 4357 | 0 |

The full `ak-test` wrapper passed before the final review corrections (4351 checks).
The affected blueprint and consolidation suites then passed through `ak-test` again
after the axle correction and expanded paint tests (3609 checks). Logs are preserved
as `headless-full.log` and `headless-final-affected.log` beside this report.
The last full CPU run included Deadbolt and Ramjet: both completed two laps with
zero recoveries. Deadbolt artwork vs greybox parity is checked in independent worlds
through settling, acceleration, braking and swapping at identical coordinates.

Native Forward+ GPU captures exercised the real garage, previews and keyboard driving.
Deadbolt reached approximately 58 km/h on the tarmac proving strip, swapped to End B,
and remained finite. Visual QA returned PASS for corrected UI and final camera framing.
Editor and game were launched successfully; only the host's X11 input-method warning
remains on fresh launch, with no project/script errors.

Gemini returned APPROVE in both integration review rounds. The second round's medium
axle alignment finding and low missing-paint-test finding were fixed and regression
checked. Reviews are scoped to the integration diff against `imported/latest-saved`;
the inherited project was not freshly audited line by line. A combined historical
diff exceeded the review helper's command argument limit. Historical review records
are retained separately under `.ai/history/whiplash-shift/`.

## Remaining limitations

- Deadbolt's saved Blender preview already has the overly smooth body and detached
  side-window panels seen in Godot. This is confirmed by visual comparison with the
  unchanged original preview. A dedicated asset pass is needed to improve the art.
- The other five roster vehicles retain their saved blueprints/stats and greybox
  models; no production GLBs for those vehicles were present in either source folder.
- Visual QA noted a steeper camera angle after an End B swap. The chassis now remains
  framed; further camera feel/polish is subjective and remains future work.
- Race countdowns, results and the four-course arcade mode remain planned features.
