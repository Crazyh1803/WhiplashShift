## Shared item odds and timing. No position-based bonuses or CPU-only items.
class_name ItemCatalog
extends RefCounted

const IDS := ["shield", "machine_guns", "rockets", "grenades", "smoke", "oil", "homing"]
const DATA := {
	"shield": {"name": "SHIELD", "weight": 20, "duration": 5.0, "interval": 0.0, "color": "64cfff"},
	"machine_guns": {"name": "MACHINE GUNS", "weight": 24, "duration": 6.0, "interval": 0.15, "speed": 180.0, "life": 0.8, "loss": 0.06, "cap": 1.8, "color": "ffe577"},
	"rockets": {"name": "ROCKETS", "weight": 18, "duration": 5.0, "interval": 1.0, "speed": 105.0, "life": 1.4, "loss": 0.25, "cap": 8.0, "radius": 5.0, "color": "ff7547"},
	"grenades": {"name": "GRENADES", "weight": 12, "duration": 6.0, "interval": 1.2, "speed": 48.0, "life": 1.5, "loss": 0.25, "cap": 8.0, "radius": 8.0, "color": "9be364"},
	"smoke": {"name": "SMOKE SCREEN", "weight": 13, "duration": 5.0, "interval": 0.5, "color": "7e8595"},
	"oil": {"name": "OIL SLICK", "weight": 12, "duration": 5.0, "interval": 0.65, "color": "9e7bd4"},
	"homing": {"name": "HOMING MISSILE", "weight": 1, "duration": 0.0, "interval": 0.0, "speed": 85.0, "life": 3.5, "loss": 0.3, "cap": 10.0, "radius": 5.0, "color": "ff68c1"},
}


static func roll(unit_roll: float) -> String:
	var value := clampf(unit_roll, 0.0, 0.999999) * 100.0
	for id: String in IDS:
		value -= float(DATA[id]["weight"])
		if value < 0.0:
			return id
	return "homing"


static func label(id: String) -> String:
	return String(DATA[id]["name"]) if DATA.has(id) else "EMPTY"
