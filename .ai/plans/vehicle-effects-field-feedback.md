# Vehicle effects field feedback
- Resume chat/vehicle-effects-a04b9fa12641 at c9e165c; preserve all existing gameplay rules and physics.
- Lead: make contact-driven tyre smoke and fading skid strips readable on the real dark road, confirm live handbrake/turn effects from chase camera; make smoke deployment irregular in spread/drift/fade while preserving hazard placement, five-second lifetime, blocking radius and owner sight corridor.
- Claude audio delegation: item_audio.gd and vehicle_audio.gd plus audio tests/QA. Replace cheery pickup lift and ringing rail/car impacts with grounded industrial/mechanical cues. Preserve engine/swap and other item cues; add bounded car-contact audio routing. Export local WAV previews for inspection.
- Claude follow-up test delegation if needed: actual driving and dark-road visual regression/QA for tyre/skid and irregular deployed smoke.
- Validation: ak-test import + affected effects/item/audio/deployment/vehicle tests; rendered captures from actual dark-road chase camera and cloud dispersal sequence; independent scoped ak-review; fix findings, commit and publish existing chat preview. No main merge.
