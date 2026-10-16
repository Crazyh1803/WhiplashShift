# Deadbolt selection and Claude handoff — 2026-10-16

The garage now exposes seven named chassis buttons, including DEADBOLT, plus labeled
previous/next controls. The selected chassis is highlighted and retained on return
from a race. VIEW 3D // PAINT & PARTS makes the actual model preview discoverable.
Blueprint metadata no longer overlaps the drawing. Compact header/dossier typography
keeps both selector rows, navigation and ignition controls inside the viewport.

Validation: `ak-test` affected suites passed: 3555 Blackjack blueprint checks and
59 consolidation checks, zero failures. New checks exercise direct Deadbolt selection,
the actual preview, retained selection, and bounds of every roster/navigation/ignition
button and the dossier. Native Forward+ screenshots passed `ak-look` with no issues.
Driving and end swapping in the same capture run remained successful.

The user chose a Claude handoff for the asset work. No vehicle geometry was modified.
`.ai/handoffs/deadbolt-graphics.md` is the complete task brief, with blueprint and
Blackjack references, specific visual defects, proposed rebuild, integration contracts,
test constraints, Blender/visual validation and delivery requirements. Claude's design
memo and the expanded plan are included. The separate `asset/deadbolt-graphics`
worktree is intended for Claude, the configured asset lead.
