# Consolidate saved Whiplash work

- Preserve the original Blackjack Git history and import the main worktree's saved
  gameplay, garage, catalog, source art, and browser prototype into this project.
- Cherry-pick the existing Deadbolt asset commit without rebuilding or changing art.
- Connect Deadbolt's existing model to the garage/player/CPU factory with visual-only
  transforms and semantic paint; retain the four-wheel physics and saved handling.
- Make the test wrapper use the installed Godot, add integration regression coverage,
  run `ak-test`, and check rendered garage/driving captures with `ak-look`.
- Run `ak-review`, fix actionable findings, and leave the consolidated project open
  in Godot. Keep both original source worktrees unchanged.

Sources: main worktree at 4c93eed plus saved uncommitted work; Deadbolt 2b0ee45.
The original main folder's historical `.ai` reports are retained under
`.ai/history/whiplash-shift/` so they cannot be mistaken for current test results.
Blender backup files and generated editor caches are not imported.
