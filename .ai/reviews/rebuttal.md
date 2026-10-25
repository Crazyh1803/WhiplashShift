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
