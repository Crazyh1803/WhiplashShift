# Terrain shapes for track authors

A track section has two independent choices: `s` supplies its material and handling, and optional `relief` supplies its physical shape. The rendered road and collision use the same vertices. Viscera dressing follows that shape.

The existing circuit uses the original defaults. Its accepted boulders are the **medium** height. New combinations are opt-in when authoring a course; no track editor UI is required.

## Recipes

These dictionaries belong on the sampled centreline points for a section:

```gdscript
# Viscera covering the accepted boulder shape.
{"s": Surfaces.Id.MUD, "relief": {"shape": "boulders", "preset": "medium"}}

# Smaller or larger bumps under gravel, viscera, or another material.
{"s": Surfaces.Id.GRAVEL, "relief": {"shape": "boulders", "preset": "low"}}
{"s": Surfaces.Id.MUD, "relief": {"shape": "boulders", "preset": "high", "seed": 42}}

# A broad viscera tabletop: 1.2 m high, 14 m climb, 16 m descent.
# The section needs at least 34 m of length to include a 4 m tabletop.
{"s": Surfaces.Id.MUD, "relief": {"shape": "ramp", "height": 1.2, "rise": 14.0, "fall": 16.0}}

# An explicitly flat section.
{"s": Surfaces.Id.BOULDER, "relief": {"shape": "none"}}
```

Keep the same relief settings on every point in a section. A change of material or relief starts a new run, returning smoothly to the shared boundary. Use an explicit seed to reproduce a particular boulder layout. Omit `relief` to use the material's existing shape.

| Shape | Height | Use |
| --- | --- | --- |
| Boulders, low | up to 0.12 m | Small uneven bumps |
| Boulders, medium | up to 0.20 m | Current accepted terrain |
| Boulders, high | up to 0.30 m | Stronger roughness |
| Ramp | authored 0.50–1.50 m | Broad climb, tabletop, and landing slope |

Ramp height and footprint must be designed together. Validation requires a straight section, a descent at least as long as the climb, at least 4 m of tabletop, and at least 8 m of flat crest across the road. Rise/fall slopes are limited to 0.25; lateral slopes to 0.30. A 24 m road can support the full 1.5 m height. Ice and oil ramps are rejected.

`CourseDefinition.validate()` reports invalid settings before construction. Handling, surface audio, cues, and eligibility for viscera decoration continue to follow `s`. A viscera-covered boulder section therefore keeps viscera grip rather than rock grip. Ramp shape does not guarantee a jump: airtime depends on speed, vehicle, and approach. One relief shape applies per section; a separate rock overlay on a ramp is not part of this contract.
