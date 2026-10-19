# Smooth driving presentation

Diagnose reported driving jitter using real-time rendered frame measurements,
not the fixed-fps capture fixture. Preserve handling, physics rate and race rules.

1. Measure real frame pacing and identify active renderer; inspect physics/render
   sampling, follow-camera aim and transform reset paths.
2. Apply the smallest supported interpolation/camera fix, including discontinuous
   spawns/recovery/retry and frame-driven garage previews if global interpolation
   changes. Avoid renderer/quality changes without timing evidence.
3. Add tests for consistent camera sampling, swap orbit, recovery and interpolation
   resets; compare rendered frame metrics before/after at ordinary runtime timing.
4. Run ak-test and relevant rendered checks, obtain ak-review / ak-look where
   available, and record evidence and limits. Leave a build ready for user playtest.
