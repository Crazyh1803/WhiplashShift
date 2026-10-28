# Season City validation

Code baseline: 11dd66c. Full regression run reached consolidation_tests; all preceding suites passed. Consolidation reported 110 passing checks and one garage bounds failure: the new course row pushed Next below the viewport.

Completed passing suites before that layout correction:

- block_circuit_tests
- season_course_tests
- vehicle_audio_tests
- vehicle_feedback_tests
- vehicle_effects_tests
- bodywork_visual_tests
- test_main
- viscera_response_tests
- rubble_response_tests
- armor_response_tests
- coolant_response_tests
- effluent_response_tests
- ichor_response_tests
- track_visual_tests
- viscera_pit_tests
- boulder_motion_tests
- item_tests
- combat_hud_tests
- driving_hud_tests
- dashboard_hud_tests
- compact_hud_tests
- weapon_attachment_tests
- deployment_oil_tests
- racecraft_tests
- cpu_main
- race_tests
- course_cues_tests
- camera_tests
- corner_tests
- terrain_profile_tests
- blackjack_refined_tests
- blackjack_blueprint_tests

Follow-up: reduce only dossier inter-control spacing from 6 px to 4 px, then rerun consolidation and the five remaining blueprint suites, plus render the garage and gameplay views.

## Final outcome

The targeted follow-up passed all six suites: consolidation_tests (111 checks), nightshift_blueprint_tests (46), ramjet_blueprint_tests (47), boilerfang_blueprint_tests (68), helix_blueprint_tests (136), and knifeedge_blueprint_tests (62). Together with the 32 passing suites above, every one of the 38 default suites passed after the relevant corrections. A second complete endurance run was unnecessary because the only subsequent production change was the two-pixel garage spacing correction, directly covered by consolidation and visual captures.

Season coverage: 54 layout/scenery checks and 33 course/session/race checks passed. City physical race: 215.28 seconds, zero pilot recoveries. Existing circuit physical race: 436.91 seconds, zero pilot recoveries. CPU suite: 73 checks passed across all difficulties and the flat control. Both tracks retain three-lap rules and retry coverage.

Final `ak-test` invocation: `python tools/workflow/test_season.py --scenes consolidation_tests nightshift_blueprint_tests ramjet_blueprint_tests boilerfang_blueprint_tests helix_blueprint_tests knifeedge_blueprint_tests && python tools/workflow/test_season.py --capture`, exit 0. Final Vulkan captures include the opening, first corner, gravel approach, skyline, QA-lit overview, garage and actual gameplay camera. The revised garage has fully visible navigation and ignition buttons. Final spacing review by Claude: APPROVE (`20261028-131412-claude.md`); the requested visual confirmation is complete.

The Python test runner retains the original full scene list and adds the two season suites, replacing the default dependency on GNU timeout/temp-path shell behavior. This Windows machine uses the installed Python 3 through `python`; its `python3` alias is a Store stub.

Temporary delegation checkouts were unregistered and their reports/captures preserved. Git could not remove some long-named generated import files in the second render folder. Automatic approval review then rejected native folder cleanup as "blocked by policy"; those leftover files remain and do not affect the game or preview.
