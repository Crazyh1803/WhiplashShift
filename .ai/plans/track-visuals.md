# First road and scenery visual sample

Build a readable industrial scrubland sample around the opening straight and first tarmac-to-mud corner. Rendering code only: procedural seamless materials and code-native geometry. No bitmap generation, Blender assets or changes to tyre physics/collision surfaces.

- Replace flat road colors with a shared world-space procedural surface shader: asphalt aggregate/patches, gravel, muddy ruts/puddles, boulders, ice cracks, water ripples and sparse off-track scrub. Supply longitudinal/across-road UVs for worn markings and wheel paths; retain exact collision vertices and metadata.
- Build visual-only shoulders, edge treatments and rail posts. Concentrate industrial landmarks, distant landforms and trackside details on a straight/corner sample. Check full-course clearance for every prop; avoid clutter in racing lanes and existing warning boards.
- Improve daylight/sky/ground composition for material readability without costly fullscreen effects.
- Add numerical mesh/material/clearance and collision invariance checks, plus a rendered capture fixture for straight, transition and corner views. Verify shader compilation on Vulkan. Run ak-test, ak-review and ak-look; report quota blockers honestly.
- Preserve pending CPU, item and launcher changes. Procedural rendering belongs to the code lane; authored asset work remains Claude's asset lane.
