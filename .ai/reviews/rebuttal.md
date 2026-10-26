# Final review rationale

Both component reviews returned APPROVE; all HIGH findings are fixed. The short/narrow-road cases now sweep across the ribbon and check nonzero, bounded crowns. The loop-invariant offset is hoisted and the contact clamp is capped at one.

The remaining MED concern about the boulder support allowance is retained intentionally. Production physics runs at 120 Hz, so 0.3 seconds is 36 ticks, versus the observed maximum of 32 ticks: a four-tick margin. The test bounds every individual wheel gap, which also bounds simultaneous axle unloading, and samples a minimum of two contacts at every physics step. Full airborne steps must remain zero. Roll, yaw, lateral drift and forward travel retain explicit limits. The old two-tick all-wheel-contact rule applies to the softer surfaces. These checks permit an axle to follow a visible 16–20 cm rock without treating normal axle unloading as a chassis launch.

TrackBuilder constructs lateral edge offsets with zero Y, so interpolating the authored centreline Y is its correct base surface, including graded tracks. A unit check covers nonzero authored elevation. No lateral banking is implemented by this builder. The no-contact pose branch returns through its decay path before reaching the contact-dependent clamp.
