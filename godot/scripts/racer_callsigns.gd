## CPU callsign pool and per-match draw. Names are drawn once per match (never per frame);
## the proving ground stores them and the HUD, results and minimap all read that one list.
class_name RacerCallsigns
extends RefCounted

const POOL: Array[String] = [
	"GHOSTWIRE", "RED STATIC", "IRON VIPER", "DUST REAPER", "VOLT GHOST", "CHROME JACK",
	"DARK RELAY", "NEON WRAITH", "ROAD HEX", "FLATLINE", "GLITCH", "CROWBAR",
	"DREADNOUGHT", "NIGHT RAVEN", "VOID RUNNER", "SCARLET", "RAZORBACK", "COLD SIGNAL",
	"ASH DRIVER", "BLACK ICE", "WRAITH", "IRON CROW", "WIRE GHOST", "NEON FANG",
]


static func _key(name: String) -> String:
	return name.strip_edges().to_upper()


## `count` unique callsigns sampled without replacement. Anything matching `player` (any case) is
## excluded; names in `previous` are avoided while enough fresh ones remain. Pass a seeded `rng`
## for a deterministic draw. If the pool were ever too small, "CPU n" placeholders fill the rest.
static func draw(count: int, player: String, previous: Array[String], rng: RandomNumberGenerator) -> Array[String]:
	var banned := _key(player)
	var used: Array[String] = []
	for name in previous:
		used.append(_key(name))
	var fresh: Array[String] = []
	var stale: Array[String] = []
	for name in POOL:
		if _key(name) == banned:
			continue
		(stale if _key(name) in used else fresh).append(name)
	var picked: Array[String] = []
	for group: Array[String] in [fresh, stale]:
		while picked.size() < count and not group.is_empty():
			picked.append(group.pop_at(rng.randi_range(0, group.size() - 1)))
	var filler := 1
	while picked.size() < count:
		var name := "CPU %d" % filler
		filler += 1
		if _key(name) != banned and not picked.has(name):
			picked.append(name)
	return picked
