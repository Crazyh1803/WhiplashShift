# KITT-inspired dashboard HUD

User confirmed Knight Rider/KITT-inspired dark instrument panels, red segmented speed digits, amber status lights and a red scanner, with clear racing information.

Direction: a cohesive bottom dashboard band with velocity, vehicle systems (boost/bodywork), route advice, weapons/utility and course map instruments. Retain a clear race header, readable combat directional markers above the dashboard, saved speed units, true racer positions and gameplay state. Restrained scanner animation; no audio, decorative fake readings or new external assets.

Split:
- Claude (code and asset lead) via ak-delegate: code-native dashboard styling/layout, segment digits and scanner, Hud/DrivingHud/CombatHud integration, focused regression updates and deterministic rendered QA. Use existing public state and preserve mechanics.
- Codex lead: integration, real rendered inspection at1280x720, scoped ak-test, independent review, fixes to any clipping/overlap, commit and desktop preview publishing.

Validation: numbers0/13/112/200/999 readable, mph/kmh and reverse legible; speed/map/combat behavior preserved, full route-advice and low-grip/smoke feedback fits instruments; markers above dashboard, top race/whiplash announcements clear; no interactive controls blocked; countdown/results/retry remain correct. Keep static minimap layer cached during scanner animation. No generated raster/3D assets needed.
