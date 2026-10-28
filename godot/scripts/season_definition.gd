class_name SeasonDefinition
extends RefCounted

const FORMAT := "whiplash-season"
const VERSION := 1
const MAX_RACES := 30
const MAX_NAME := 40
const MAX_BYTES := 16384
const MAX_LAPS := 99
const SHARE_PREFIX := "WS1."
const CHECKSUM_CHARS := 8
const SEASON_KEYS: Array[String] = ["format", "version", "name", "races"]
const RACE_KEYS: Array[String] = ["course_id", "laps", "reverse"]


## Validates untrusted data into a fresh normalized dictionary; never returns partial results.
static func validate(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _fail("Season data must be an object.")
	var data: Dictionary = value
	var key_error := _check_keys(data, SEASON_KEYS, "season")
	if not key_error.is_empty():
		return _fail(key_error)
	if typeof(data["format"]) != TYPE_STRING or data["format"] != FORMAT:
		return _fail("Not a Whiplash Shift season file.")
	var version: Variant = _exact_int(data["version"])
	if version == null or version != VERSION:
		return _fail("Unsupported season version.")
	if typeof(data["name"]) != TYPE_STRING:
		return _fail("Season name must be text.")
	var clean_name := clean_name_text(data["name"])
	if clean_name.is_empty():
		return _fail("Season name is empty.")
	if clean_name.length() > MAX_NAME:
		return _fail("Season name is longer than %d characters." % MAX_NAME)
	if typeof(data["races"]) != TYPE_ARRAY:
		return _fail("Races must be a list.")
	var source: Array = data["races"]
	if source.is_empty() or source.size() > MAX_RACES:
		return _fail("A season needs 1 to %d races." % MAX_RACES)
	var races: Array = []
	for i: int in source.size():
		var entry := _validate_race(source[i], i + 1)
		if not str(entry["error"]).is_empty():
			return _fail(entry["error"])
		races.append(entry["race"])
	return {"ok": true, "season": {"format": FORMAT, "version": VERSION, "name": clean_name, "races": races}, "error": ""}


static func decode_text(text: String) -> Dictionary:
	if text.length() > MAX_BYTES * 2 or text.to_utf8_buffer().size() > MAX_BYTES * 2:
		return _fail("Season text is too large.")
	var trimmed := text.strip_edges()
	if trimmed.begins_with("{"):
		if trimmed.to_utf8_buffer().size() > MAX_BYTES:
			return _fail("Season text is too large.")
		return _parse_json(trimmed)
	if trimmed.begins_with(SHARE_PREFIX):
		return _decode_share(trimmed)
	return _fail("Unrecognised season text. Paste a WS1 share code or season JSON.")


static func encode_json(season: Dictionary) -> String:
	var result := validate(season)
	return JSON.stringify(result["season"], "\t") if result["ok"] else ""


static func encode_share(season: Dictionary) -> String:
	var result := validate(season)
	if not result["ok"]:
		return ""
	var json_text := JSON.stringify(result["season"])
	var payload := Marshalls.raw_to_base64(json_text.to_utf8_buffer()).replace("+", "-").replace("/", "_").replace("=", "")
	return "%s%s.%s" % [SHARE_PREFIX, payload, json_text.sha256_text().substr(0, CHECKSUM_CHARS)]


static func clean_name_text(raw: String) -> String:
	var kept := ""
	for i: int in raw.length():
		var code := raw.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159) or (code >= 0x200B and code <= 0x200F) \
				or (code >= 0x2028 and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or code == 0xFEFF:
			continue
		kept += raw.substr(i, 1)
	return kept.strip_edges()


static func _decode_share(text: String) -> Dictionary:
	var compact := text.replace("\n", "").replace("\r", "").replace("\t", "").replace(" ", "")
	var parts := compact.split(".")
	if parts.size() != 3 or parts[0] + "." != SHARE_PREFIX:
		return _fail("Share code is malformed.")
	var payload := parts[1]
	if payload.is_empty() or payload.length() > (MAX_BYTES * 4) / 3 + 4 or payload.length() % 4 == 1:
		return _fail("Share code is the wrong size.")
	for i: int in payload.length():
		var code := payload.unicode_at(i)
		var ok := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95
		if not ok:
			return _fail("Share code contains invalid characters.")
	var padded := payload.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0:
		padded += "="
	var bytes := Marshalls.base64_to_raw(padded)
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return _fail("Share code is the wrong size.")
	var json_text := bytes.get_string_from_utf8()
	if json_text.is_empty() or json_text.to_utf8_buffer() != bytes:
		return _fail("Share code is not valid text.")
	if json_text.sha256_text().substr(0, CHECKSUM_CHARS) != parts[2].to_lower():
		return _fail("Share code checksum does not match; it may be mistyped or cut off.")
	return _parse_json(json_text)


static func _parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("Season JSON is invalid (line %d)." % json.get_error_line())
	return validate(json.data)


static func _validate_race(value: Variant, number: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "Race %d must be an object." % number}
	var entry: Dictionary = value
	var key_error := _check_keys(entry, RACE_KEYS, "race %d" % number)
	if not key_error.is_empty():
		return {"error": key_error}
	if typeof(entry["course_id"]) != TYPE_STRING or not CourseCatalog.IDS.has(entry["course_id"]):
		return {"error": "Race %d uses an unknown track." % number}
	var laps: Variant = _exact_int(entry["laps"])
	if laps == null or laps < 1 or laps > MAX_LAPS:
		return {"error": "Race %d laps must be a whole number from 1 to %d." % [number, MAX_LAPS]}
	if typeof(entry["reverse"]) != TYPE_BOOL:
		return {"error": "Race %d direction must be true or false." % number}
	return {"error": "", "race": {"course_id": String(entry["course_id"]), "laps": int(laps), "reverse": bool(entry["reverse"])}}


static func _check_keys(data: Dictionary, allowed: Array[String], label: String) -> String:
	for key: Variant in data.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return "Unknown field in %s." % label
	for key: String in allowed:
		if not data.has(key):
			return "Missing field '%s' in %s." % [key, label]
	return ""


## Returns an int for ints or floats holding an exact finite integer, otherwise null.
static func _exact_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and absf(value) < 1.0e9 and value == floorf(value):
		return int(value)
	return null


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "season": {}, "error": message}
