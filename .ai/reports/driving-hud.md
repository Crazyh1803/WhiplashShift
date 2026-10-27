# Driving HUD validation

Added a prominent digital speedometer, Garage > Settings speed-unit choice saved separately from profiles/customization, and a cached full-course minimap with player heading, opponent positions and start/finish. CPU speeds and corner advisories follow the selected unit.

Delegated: Claude implementation and tests; independent Codex review of that implementation. Lead fixed three-digit clipping, added persistence-error feedback, and corrected staged capture camera/state. Claude independently approved those fixes. Qwen was asked for five function-comment drafts but returned null; existing reviewed comments were retained.

Checks through ak-test: driving HUD 71 passed, combat HUD 67 passed, course cues 26 passed, camera 12 passed. Rendered Forward+ QA: 12 passed, four 1280x720 captures inspected. Godot import and diff whitespace checks passed.

Review findings: MED ignored save errors fixed with a tested dialog message. LOW font concern does not apply: drawing and test both use ThemeDB.fallback_font at size74. LOW invalid save-path concern does not apply: the test first creates the parent as a file, so it cannot be a directory. Review reports are intentionally tracked as validation evidence.

Bodywork damage currently remains cosmetic/recovering; weapon hits separately apply immediate speed loss. A separate delegated change is adding visible wear without changing race balance.
