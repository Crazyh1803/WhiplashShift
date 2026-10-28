class_name SeasonLibrary
extends RefCounted

const DEFAULT_DIRECTORY := "user://seasons"
const MAX_FILES := 64
const MAX_ID := 32
const SEASON_ONE_TITLES: Array[String] = [
	"Block Circuit", "Drain Run", "Slagline",
	"Coolant Reach", "Skyway Exchange", "Pressure Main",
	"Crucible Ring", "Core Breach", "Blackout Grand Prix",
]

var directory: String = DEFAULT_DIRECTORY


## The only built-in season: a one-race Block Circuit preview plus the nine-race plan.
static func season_one() -> Dictionary:
	var plan: Array[Dictionary] = []
	for i: int in SEASON_ONE_TITLES.size():
		plan.append({"cup": i / 3 + 1, "title": SEASON_ONE_TITLES[i], "available": i == 0})
	var season := {"format": SeasonDefinition.FORMAT, "version": SeasonDefinition.VERSION, "name": "Season 1 Preview",
		"races": [{"course_id": "block_circuit", "laps": 3, "reverse": false}]}
	return {"season": SeasonDefinition.validate(season)["season"], "plan": plan, "preview": true}


static func is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > MAX_ID:
		return false
	for i: int in id.length():
		var code := id.unicode_at(i)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 45):
			return false
	return true


static func make_id(season_name: String) -> String:
	var lowered := season_name.to_lower()
	var slug := ""
	for i: int in lowered.length():
		var code := lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			slug += char(code)
		elif not slug.ends_with("-") and not slug.is_empty():
			slug += "-"
	slug = slug.left(MAX_ID - 7).trim_suffix("-")
	var tag := season_name.sha256_text().substr(0, 6)
	return tag if slug.is_empty() else "%s-%s" % [slug, tag]


func list_seasons() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	var names: Array[String] = []
	var scanned := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty() and scanned < MAX_FILES:
		scanned += 1
		if not dir.current_is_dir() and entry.get_extension() == "json":
			names.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for id: String in names:
		var result := load_season(id)
		if result["ok"]:
			found.append({"id": id, "name": result["season"]["name"], "race_count": (result["season"]["races"] as Array).size()})
	return found


func save(season: Dictionary) -> Dictionary:
	var result := SeasonDefinition.validate(season)
	if not result["ok"]:
		return {"ok": false, "id": "", "error": result["error"]}
	var id := make_id(result["season"]["name"])
	var error := _write_atomic(_path_for(id), SeasonDefinition.encode_json(result["season"]))
	if not error.is_empty():
		return {"ok": false, "id": "", "error": error}
	return {"ok": true, "id": id, "error": ""}


func load_season(id: String) -> Dictionary:
	if not is_valid_id(id):
		return _invalid("Invalid season id.")
	return import_file(_path_for(id))


## Reads and validates any file without saving it.
func import_file(path: String) -> Dictionary:
	var read := _read_bounded(path)
	if not read["ok"]:
		return _invalid(read["error"])
	return SeasonDefinition.decode_text(read["text"])


func export_file(path: String, season: Dictionary) -> Dictionary:
	var result := SeasonDefinition.validate(season)
	if not result["ok"]:
		return {"ok": false, "error": result["error"]}
	var error := _write_atomic(path, SeasonDefinition.encode_json(result["season"]))
	return {"ok": error.is_empty(), "error": error}


func _path_for(id: String) -> String:
	return directory.path_join(id + ".json")


func _read_bounded(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "text": "", "error": "Could not open the season file."}
	var length := file.get_length()
	if length <= 0 or length > SeasonDefinition.MAX_BYTES:
		return {"ok": false, "text": "", "error": "Season file is empty or larger than %d bytes." % SeasonDefinition.MAX_BYTES}
	var bytes := file.get_buffer(length)
	file.close()
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return {"ok": false, "text": "", "error": "Season file is not valid UTF-8 text."}
	return {"ok": true, "text": text, "error": ""}


func _write_atomic(path: String, content: String) -> String:
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder) != OK:
		return "Could not create the season folder."
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "Could not write the season file."
	file.store_string(content)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp)
		return "Could not write the complete season file."
	if DirAccess.rename_absolute(temp, path) != OK:
		DirAccess.remove_absolute(temp)
		return "Could not finish writing the season file."
	return ""


static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "season": {}, "error": message}
