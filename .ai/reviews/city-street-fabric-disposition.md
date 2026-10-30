# Connected street fabric review disposition

Scope: optional ground kit, connected layout, regression coverage and source validation.

- Asset review 20261030-171100-codex: APPROVE. Both medium findings are fixed: weed fringe is raised 5 mm above its slab; missing textured source files produce diagnostics rather than FileNotFoundError. Five Python regressions pass.
- The follow-up command-line Codex review hit its usage quota and provided no approval. A separate read-only Codex reviewer independently checked the fixes and deterministic rebuilds: APPROVE, no findings. See city-ground-fix-independent.md.
- Independent test review 20261030-172637-codex: APPROVE, no findings.
- Runtime reviews 20261030-171414-claude and 20261030-225637-claude: APPROVE. Null material bindings now reject the optional kit before committing any entries or costs. Retry subdivision requires a new rejection. Remainders below 0.5 m are skipped. Invalid manifest tests assert no partial entries. Ground dimensions come from validated shared constants. Missing optional assets preserve the earlier layout.
- Existing Block Circuit building/prop/detail counts are compared per model against the original layout. All 29 buildings, 134 props and 44 details remain. A second course scaled 20 percent longer exercises the same budgets and count comparison.

Current scenery totals: 887,544 triangles; quarters 231,776 / 220,264 / 199,452 / 236,052; sampled visible maximum 223,986 triangles and 113 surfaces. Hard caps remain 900,000 total, 240,000 per quarter, 320,000 visible and 160 surfaces. No new lights, textures, colliders or changes to driving geometry.

Independent read-only verification of the final review fixes: APPROVE, no new actionable findings. Atomic material rejection, retry and remainder guards, strengthened fallback assertions, the longer-course stress test and the ground-only timeout change were checked against the diff. Arbitrary course lengths are outside this Block Circuit pass.

Final verification results are recorded in docs/city-realism.md.
