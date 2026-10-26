# Terrain combinations for future course design

Goal: preserve accepted default boulder layout as medium roughness; allow track authors to apply boulder-shaped relief beneath other surface materials (especially viscera), vary bump height, and opt into broad dirt-bike-style ramp mounds. User explicitly authorizes publication and merge to main after checks.

Scope: opt-in point/run terrain profile dictionary; shared rendered/collision geometry; viscera dressing follows profile; run boundaries split by profile and taper without cracks; documented examples. Existing courses retain default behavior. No new art assets, editor UI, vehicle physics retune, or changing present circuit geometry by default.

Hand-offs: Claude architecture/physics escalation for constraints and contract; Claude implementation in isolated delegate branch; separate Claude test author via subsequent delegation, including native physics ray checks and authoring boundaries. Lead integrates, reviews differences, runs checks, publishes chat branch, integrates current main separately, verifies combined tree and stable manifest, pushes main and selects main preview. Independent ak-review on each code delta; no Gemini unless requested.

Verification: targeted authoring/profile tests, existing relief/viscera/track visual tests, representative ramp rendering, bounded physical traversal for both driving ends; full suite on integrated main; workflow and launcher checks for merged delivery.
