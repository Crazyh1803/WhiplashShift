# Competitive CPU difficulty

Player feedback: all levels were easily outpaced, even with imperfect cornering. This revision improves their actual driving instead of reducing Easy to manufacture contrast.

## Changes

- Configured CPU racers use distance-aware braking. A distant corner no longer caps the entire approach. Planning accounts for both ends' grip, vehicle mass and brakes, surface-specific limits and a braking margin.
- End swaps begin on the approach. Every level uses the same reliable turn technique and commits to the chosen end until the new surface, including when the spin carries it behind the trigger point.
- Racers maintain more throttle around their requested cruising speed. Difficulty controls requested pace, cornering confidence, braking caution and traffic decisions; native power/grip/top-speed multipliers remain unchanged.
- Hard may pass on clear, wide mud/water/boulder straights with a consistent active end. Existing corridor, bend, rear-traffic and merge checks remain active. Easy/Medium retain conservative passing surfaces.
- The test harness records first-lap times and sampled speed/braking/turning time by surface. It checks actual gains against the previous playtested build and at least 10% adjacent difficulty separation.

## Validation

Full `ak-test`: PASS (exit 0), all 15 scenes, with no runtime errors. Includes 59 CPU checks and 46 racecraft checks, plus complete race/retry integration, handling, garage and all seven vehicles. Output is preserved in `.ai/reviews/difficulty-contrast-full-test.log`. `git diff --check` also passes.

Controlled benchmark: two production-model opponents (Boilerfang and Ramjet), identical course/grid, 420 seconds. Previous combined distances: Easy 12,722.95 m, Medium 14,425.87 m, Hard 15,215.05 m. Hard's leading opponent must exceed the previous opponent average by 20%; the field must improve at least 15%. Easy and Medium are also compared with their respective old builds.

Final combined distances and first-lap times:

| Level | Combined distance | Gain over the same old level | First full laps |
|---|---:|---:|---|
| Easy | 14,414.53 m | +13.3% | 155 / 153 s |
| Medium | 15,965.24 m | +10.7% | 142 / 143 s |
| Hard | 18,003.97 m | +18.3% | 126 / 130 s |

Medium is 10.8% ahead of Easy; Hard is 12.8% ahead of Medium. All six racers have zero recoveries during these runs.

The Hard run covers 18,003.97 m combined (+18.3%), with the leader covering 9,132.60 m (+20.0% against the previous average opponent). First full laps: 126 / 130 seconds. Both opponents have zero recoveries.

46 racecraft checks pass, including the new anticipatory swap commitment checks and a physical rough-surface pass without contact or recovery.

## Review

Independent review pending. The configured Gemini reviewer was quota-blocked in the preceding work; this change will be submitted again after validation. Changes remain uncommitted until the required review completes.

`ak-escalate debug` identified the shared swap bottleneck and recommended beginning swaps earlier, planning their entry speed, and improving braking confidence. More aggressive corner/steering experiments that slowed racers or introduced recoveries were discarded.
