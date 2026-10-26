# Weapon detail review resolutions

The two routine runtime review rounds were Claude 20261025-102451 (APPROVE with findings) and 20261025-103422 (CHANGES_REQUESTED). All HIGH findings are fixed. No further review loop or Gemini tiebreak was requested. This note records the resolutions; it is not a new approval.

- HIGH: keep headlight script/shader UIDs tracked. Both are now included with stable generated IDs.
- MED: missing muzzle markers now produce a named error and safe mount-position fallback. Independent attachment tests validate every expected marker on all seven vehicles and both ends. Gun/Launcher roots are created by the attachment code itself.
- MED: smoke stream ownership is an explicit racer index, rather than inferred from stream creation order.
- MED: unknown emitted items are guarded and report a warning.
- MED: owner/rival gameplay masking, targeting, swapping and stream layers have headless checks. Rendered QA also asserts mesh/particle masks, preserves its original camera mask, and captures clear owner versus obscured rival views.
- MED: straight weapon lead has a guarded speed divisor. Projectile velocities are world-space and do not inherit the firing car velocity, so subtracting shooter velocity would change the existing model. This remains a bounded arcade lead estimate rather than an exact intercept solver.
- MED: actual hit tests exercise both target convergence and blind roof-height rockets. The independent fixtures now keep uninvolved cars out of the blind-fire lane, avoiding two racers occupying the exact same target position. The six-line fixture correction preserves the hit assertions.
- LOW: explicit owner_index names, original camera-mask restoration, unknown-item warning and release-visible palette error are implemented.
- Asset review MEDs (hidden Helix glow floor and successful exports after validation failure) were returned to Claude and fixed through Blender. The independent final asset review is APPROVE with no findings. The forced-invalid build exited 1 and preserved outputs.
- Independent test review is APPROVE with no findings. Physics escalation confirmed the elevated-muzzle regression and supplied the blind-shot split-trajectory correction applied by the lead. No vehicle tuning or collider was changed.

Validation results are recorded in docs/weapon-attachments.md and the final task report. All review findings are addressed or have a concrete applicability explanation above; no unresolved HIGH remains.

## Subsequent VFX refinement

The owner-layer hiding approach was replaced at the user's request by visible full-volume smoke with a soft owner-only view corridor. Initial VFX review HIGH (incorrect get_camera_3D spelling) and MED (impact call not yet integrated) are fixed. Live owner emitter bindings now survive transient cleanup. Follow-up owner correction and visual polish reviews APPROVE with no findings. Integration/QA reviews APPROVE; capture rectangles are clipped, FOV is restored, explosive normals are covered, rival pixel change has a minimum threshold, and glancing oil captures explicitly select and frame an oil hazard. Focused checks pass 1,128/0. No unresolved finding requires user action.

## Industrial crates / folding weapons / persistent oil

The initial asset HIGH findings (new crate API not called and no rig tick/readiness gating) are integrated and covered by collection, queue/muzzle, swap and retraction tests. The integration HIGH on the active dispenser consuming its own oil is fixed and tested; the corrupted message byte is replaced with ASCII. Queue reset is already performed by _stop, which reset_racer calls, and regression cases confirm cancellation. Oil life=1 is documented as an opacity sentinel, never decremented.

The proposed size-based oil eviction is intentionally not adopted: the user explicitly requires oil to remain until driven over, so deleting an unconsumed trap at an arbitrary cap would violate the requested behavior. Smoke remains bounded independently, oil is cleared at race reset/results, and redundant per-frame oil material updates are skipped. The owner may hit old oil after active dispensing ends; this is documented and tested. QA restores prior gravity/freeze/FOV state. Independent test review and the second integration review are APPROVE; no unresolved HIGH or user approval gate remains.

# Final review rationale

Both component reviews returned APPROVE; all HIGH findings are fixed. The short/narrow-road cases now sweep across the ribbon and check nonzero, bounded crowns. The loop-invariant offset is hoisted and the contact clamp is capped at one.

The remaining MED concern about the boulder support allowance is retained intentionally. Production physics runs at 120 Hz, so 0.3 seconds is 36 ticks, versus the observed maximum of 32 ticks: a four-tick margin. The test bounds every individual wheel gap, which also bounds simultaneous axle unloading, and samples a minimum of two contacts at every physics step. Full airborne steps must remain zero. Roll, yaw, lateral drift and forward travel retain explicit limits. The old two-tick all-wheel-contact rule applies to the softer surfaces. These checks permit an axle to follow a visible 16–20 cm rock without treating normal axle unloading as a chassis launch.

TrackBuilder constructs lateral edge offsets with zero Y, so interpolating the authored centreline Y is its correct base surface, including graded tracks. A unit check covers nonzero authored elevation. No lateral banking is implemented by this builder. The no-contact pose branch returns through its decay path before reaching the contact-dependent clamp.

# Terrain authoring profile review resolution

The implementation review approved the production profile code. Its requested profile-specific tests are wired into the runner. The independent test review identified UID conflict markers, missing-hit coverage, and a missing assertion for 24 m / 1.5 m ramps; all are resolved. Its second round found a stale capture helper reference; that one-line correction has independent Claude APPROVE. The combined integration tree passes 463 profile checks, including real mesh/collider rays, constructor refusal, baseline hashes, both driving ends at three entry speeds, and landing support. No HIGH or MED remains unresolved and there is no review disagreement requiring a tiebreak.
