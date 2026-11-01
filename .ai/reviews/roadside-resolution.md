# Roadside expansion review resolution

Both independent Codex review rounds requested changes. All reported findings were accepted; there is no review disagreement and no third review round was requested.

The first correction replaces hidden podium apertures with real recessed entrances/windows, guards missing near/LOD tower meshes, counts all unrestricted landmark geometry, adds rendered material-ID aperture probes, and makes required builder imports and requested asset IDs fail fast. The second correction replaces capped barrel hoops with annuli and landmark handrails with tubular rings, repairs and validates shared texture URIs in all 19 retained exports, fixes both reversed weather-shader smoothsteps, and compares actual scene renders with and without each subject. Barrel body and flame contributions are checked separately; ground pools and smoke cannot satisfy the flame check.

Final asset-lead verification: ak-test exit 0, 191 roadside checks passed, 36 street/driver/detail captures plus two overhead barrel captures passed, and intentionally hidden bodies/flames each triggered their eight expected failures. Windows-only real-renderer negative checks remain scoped to the roadside QA runner; Linux headless checks are unchanged. Mesh validation reports zero problems across all 19 assets. Tower runtime geometry and original city assets were preserved during the final correction.

Measured peak: base 319710 triangles / 150 surfaces, roadside add-on 160100 / 79, combined 576502 / 254 against caps 625000 / 265. The 12-light limit, 66 original detailed frontages and two actor pairs remain intact. The final screenshots were inspected for both landmarks, near tower podiums, boarded frontages, camps, barrel flames and overhead open drums.

The final QA coordinate bug was resolved by deriving screen regions from the captured Image dimensions. The additional read-only escalation report ranks alternative diagnostics; its proposed matrix projection was unnecessary after this correction passed the healthy and hidden-subject tests.

Independent review verdicts remain recorded as CHANGES_REQUESTED; this document records the lead's verified resolution rather than claiming an additional independent APPROVE.

Temporary delegate folder cleanup was rejected by automatic approval review ("blocked by policy"). The completed delegate branches are integrated; leftover folders are housekeeping only.

Post-merge lead verification: ak-test exit 0 for the backdrop suite, 70 headless checks and 73 Vulkan checks passed. Earlier unchanged core city suites also passed: realism 227, density 46, kit 383, ground 192. No known game/test failures remain. The final delivery selects this chat branch for desktop preview and does not merge game code into main.
