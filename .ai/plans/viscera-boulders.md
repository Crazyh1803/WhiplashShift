# Viscera pit and boulder motion

Goal: viscera reads as thick wet coiled entrails, organs and pooled blood; boulders produce visible, contact-driven pitch/roll and bounded yaw in both vehicle orientations.

Lead: inspect integration, preserve surface contracts, run headless and rendered checks, review delegated implementation, publish chat preview.
Claude escalation: diagnose safe boulder contact relief and vehicle response; current 8cm broad cosine and near-zero preferred-end impact are too subtle. Recommend bounds and real-contact measurements; no global handling retune.
Claude code/asset lead: scoped procedural viscera shader/geometry and boulder implementation following diagnosis, with regression coverage. Keep assets procedural and batched; no Blender or generated bitmap needed unless adding authored model assets.
Validation: test stationary/airborne/reset behavior, both ends, mixed surfaces, bounded relief/contacts, actual pitch/yaw/roll above flat control, rendered driver views. Run ak-test, independent ak-review, commit and publish.
