# Fractured spinal armor and vehicle light pool

BOULDER now emits larger bent ceramic/carbon laminate plates and broken curved ribs, with dry materials, independent tumble and one short visual ground bounce. Correct B has restrained ejecta and impact strength 0.14; wrong A has five times the matched-input emission rate, larger fragments, higher throws and impact strength 1.0. Spaced smooth chassis kicks distinguish armor from continuous GRAVEL rattle. Effects share the existing 96-live-fragment pool and single cosmetic VisualRoot pose writer. No handling coefficients, physical forces, colliders or wheel hardpoints changed.

Replaced the player's two opposed SpotLight3D cones with one continuous local OmniLight3D pool: warm cream, energy 5, range 65m, attenuation 1.5. It represents scattered local illumination and does not cast a self-shadow wedge. The black void, fog, disabled ambient and absence of directional sunlight remain. Chase captures now use this production helper instead of the former brighter test-only light.

Verification so far:
- Focused headless armor/lifecycle/lighting: 17 passed, 0 failed.
- Final Vulkan Forward+ lighting probe and chase captures: 23 passed, 0 failed.
- Same initial speed/throttle, correct B: speed 13.06m/s, sink 0, rattle 0, impact .140, 28 fragments emitted.
- Wrong A: speed 8.86m/s, sink 0, rattle 0, impact 1.000, 146 fragments emitted. Speed difference comes from existing terrain handling, not this visual layer.
- Full ak-test: all 20 scenes passed, including original viscera/rubble, track geometry, CPU, race, camera and all vehicle suites. Final rendered probe confirms equal brightness at left/right/front/back: 0.110 at 9m and 0.032 at 18m. The first probe run used logical viewport coordinates against physical capture pixels and failed; scaling coordinates corrected the fixture. Production lighting required no change. Logs: spinal-armor-full-test.log and spinal-armor-rendered.log.

Review status: ak-scout, ak-review and ak-look cannot run because Gemini reports RESOURCE_EXHAUSTED (429). ak-escalate design fails because Claude's OAuth session expired. No independent approval or visual verdict was obtained; work remains uncommitted. No image was loaded into the lead's context. Captures are available for human review under .ai/captures/spinal-armor-response/.
