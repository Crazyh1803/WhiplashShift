# Main menu, race modes and shared custom seasons

## Outcome
New boot main menu: Season Race (Season 1), Single Race (track, 1-99 laps, forward/reverse), Custom Season (ordered editable playlist from available tracks; per-race laps/direction; named save/load, portable export/import/share code), Settings, About (appsbydan.com and buymeacoffee.com/AppsbyDan links). Preserve garage customization as vehicle selection after race setup. Return from race/garage to main menu coherently. Publish tested preview from existing chat worktree; no main merge.

## Scope and decisions
Only Block Circuit and Split Shift are playable. Season 1 is the approved nine-race plan: list planned races honestly and allow the currently available Block Circuit as a clearly labeled preview, as explicitly selected by the user. No fictitious playable tracks. Custom season sharing is local portable versioned JSON/share text with import validation, not a new online service. Repeated tracks with different laps/direction allowed; bounded playlist (1-30 races), laps 1-99. Championship scores 10/6/3 for the three finishing positions, stable player/rival entrant slots, explicit Continue to next race, retry does not double-score, final standings. No save/load of live physics state.

## Hand-offs
- Claude design escalation (read-only): minimal architecture for course reversal, preserving city dressing anchors, match options, campaign transitions/scoring and safely importing shared data. Save-format/security review is mandatory.
- Claude delegate 1: main menu UI plus isolated custom-season schema/codec, bounded file/share parsing, local library, and codec tests. New main_menu.gd/.tscn, season_definition.gd, season_library.gd, season_codec_tests.gd/.tscn only.
- Codex lead: course options/reversal, session/season orchestration and garage/results integration; tie existing systems together. Menu uses code-native controls, existing palette; no bitmap UI art.
- Claude delegate 2: independent integration/menu/reverse/season tests after contracts are in place (no production edits).
- Independent scoped reviews by non-author; asset/codec code by Codex, lead integration by Claude.

## Acceptance
Boot menu accessible by keyboard/mouse at 1600x900 and 1280x720. Track/laps/direction arrive unchanged in the race; reverse course positions remain identical, tangents and per-edge distance/surface/relief metadata correct, start/grid safely relocated onto dry straight. Existing Split Shift golden unchanged for defaults. City's scenery is built from original forward course so world geometry does not move when reversing. Three-lap defaults preserved when bypassing menu in old tests. Single Race offers only built courses. Custom seasons survive local save/load, round-trip exports, reject malformed/unknown/oversized data without partially mutating state, and can be played through standings. Season 1 accurately labels missing races and preview status. Settings retain current speed units/CPU choice; About opens only supplied HTTPS URLs on explicit button press. Verify with ak-test, rendered UI captures and independent review before publish.
