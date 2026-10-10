# Blackjack paint coverage and fine-detail pass

- Preserve the accepted traced silhouette, dimensional rig, source references,
  protected hardware and all four-wheel physics. Snapshot current assets outside
  the active paths before regeneration.
- Fix exterior cage material assignments: primary/secondary/accent must cover
  designated body panels, while protected armor remains underbody/mechanical trim.
  Add independent surface-landmark paint checks, including a uniform-color render.
- Replace barely visible/degraded fasteners and handles with seated, low-cost
  geometry; retain their topology in gameplay/LOD. Cut shallow hood vent pockets
  with angled floors and visible collars; add protected lamp bezels and gaskets.
- Validate the 40k complete-vehicle limit, closed shell, seating, glass clearance,
  paint/decal protection and silhouette gates. Capture side/front/detail/color
  comparisons in Blender and Godot, including the actual garage lighting.
- Run ak-test and at most two ak-review rounds against narrowly scoped changes
  from 18c96da, preserving unrelated pending files. Commit the scoped pass and
  restart the real garage for inspection only after the visual checks pass.
