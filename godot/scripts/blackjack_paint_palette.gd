extends RefCounted

const SWATCHES: Array[Dictionary] = [
	{"name":"Obsidian", "hex":"101820"},
	{"name":"Graphite", "hex":"303943"},
	{"name":"Titanium Silver", "hex":"9ca6ad"},
	{"name":"Pearl Ivory", "hex":"f2efe6"},
	{"name":"Midnight Blue", "hex":"1c2c48"},
	{"name":"Cobalt", "hex":"2558a4"},
	{"name":"Racing Red", "hex":"b51f32"},
	{"name":"Burgundy", "hex":"642a3c"},
	{"name":"British Racing Green", "hex":"184e39"},
	{"name":"Recon Olive", "hex":"59634b"},
	{"name":"Ember Copper", "hex":"ff4d2e"},
	{"name":"Champagne Gold", "hex":"c5a468"},
]


static func label_for(color: Color) -> String:
	for swatch in SWATCHES:
		if color.to_html(false)==swatch["hex"]:
			return swatch["name"]
	return "SAVED CUSTOM"
