extends Node

var _pass := 0
var _fail := 0
var _scratch := "user://season_codec_scratch_%d" % Time.get_ticks_usec()


func _ready() -> void:
	_test_validate()
	_test_decode()
	_test_library()
	_clean_scratch()
	print("SEASON_CODEC: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _season(laps: Variant = 3, reverse: Variant = false, course := "block_circuit") -> Dictionary:
	return {"format": "whiplash-season", "version": 1, "name": "Night Run",
		"races": [{"course_id": course, "laps": laps, "reverse": reverse}]}


func _test_validate() -> void:
	var good := SeasonDefinition.validate(_season())
	_check("valid season accepted", good["ok"] and good["season"]["races"][0]["laps"] == 3)
	_check("float laps with exact integer accepted", SeasonDefinition.validate(_season(5.0))["ok"])
	_check("float laps normalized to int", typeof(SeasonDefinition.validate(_season(5.0))["season"]["races"][0]["laps"]) == TYPE_INT)
	for bad: Variant in [2.5, 0, 100, -1, "3", null, true, INF, NAN, 1.0e30]:
		_check("laps %s rejected" % str(bad), not SeasonDefinition.validate(_season(bad))["ok"])
	_check("non-bool reverse rejected", not SeasonDefinition.validate(_season(3, 1))["ok"])
	_check("unknown track rejected", not SeasonDefinition.validate(_season(3, false, "nowhere"))["ok"])
	_check("non-dictionary rejected", not SeasonDefinition.validate([1, 2])["ok"])
	var wrong_version := _season()
	wrong_version["version"] = 2
	_check("unknown version rejected", not SeasonDefinition.validate(wrong_version)["ok"])
	var wrong_format := _season()
	wrong_format["format"] = "other"
	_check("unknown format rejected", not SeasonDefinition.validate(wrong_format)["ok"])
	var extra := _season()
	extra["admin"] = true
	_check("unknown season key rejected", not SeasonDefinition.validate(extra)["ok"])
	var extra_race := _season()
	extra_race["races"][0]["script"] = "x"
	_check("unknown race key rejected", not SeasonDefinition.validate(extra_race)["ok"])
	var missing := _season()
	missing.erase("name")
	_check("missing key rejected", not SeasonDefinition.validate(missing)["ok"])
	var empty_races := _season()
	empty_races["races"] = []
	_check("empty race list rejected", not SeasonDefinition.validate(empty_races)["ok"])
	var many := _season()
	many["races"] = []
	for i: int in SeasonDefinition.MAX_RACES + 1:
		many["races"].append({"course_id": "split_shift", "laps": 1, "reverse": true})
	_check("31 races rejected", not SeasonDefinition.validate(many)["ok"])
	many["races"].pop_back()
	_check("30 repeated races accepted", SeasonDefinition.validate(many)["ok"])
	var dirty := _season()
	dirty["name"] = "  Ni\u0001ght\n‮Run\t "
	_check("control characters cleaned from name", SeasonDefinition.validate(dirty)["season"]["name"] == "NightRun")
	dirty["name"] = "\u0001\n"
	_check("control-only name rejected", not SeasonDefinition.validate(dirty)["ok"])
	dirty["name"] = "x".repeat(SeasonDefinition.MAX_NAME + 1)
	_check("overlong name rejected", not SeasonDefinition.validate(dirty)["ok"])
	dirty["name"] = 42
	_check("non-string name rejected", not SeasonDefinition.validate(dirty)["ok"])
	var input := _season()
	SeasonDefinition.validate(input)
	_check("validate does not mutate input", input == _season())


func _test_decode() -> void:
	var season: Dictionary = SeasonDefinition.validate(_season(7, true, "split_shift"))["season"]
	var code := SeasonDefinition.encode_share(season)
	_check("share code has WS1 prefix", code.begins_with("WS1.") and code.split(".").size() == 3)
	var round_trip := SeasonDefinition.decode_text(code)
	_check("share code round-trips", round_trip["ok"] and round_trip["season"] == season)
	_check("share code tolerates whitespace", SeasonDefinition.decode_text("  " + code.left(20) + "\n " + code.substr(20) + "\n")["ok"])
	var json_text := SeasonDefinition.encode_json(season)
	_check("JSON round-trips", SeasonDefinition.decode_text(json_text)["season"] == season)
	var parts := code.split(".")
	_check("bad checksum rejected", not SeasonDefinition.decode_text("WS1.%s.00000000" % parts[1])["ok"])
	_check("truncated code rejected", not SeasonDefinition.decode_text(code.left(code.length() - 12))["ok"])
	_check("invalid base64 characters rejected", not SeasonDefinition.decode_text("WS1.@@@@.00000000")["ok"])
	_check("empty payload rejected", not SeasonDefinition.decode_text("WS1..00000000")["ok"])
	_check("extra segments rejected", not SeasonDefinition.decode_text(code + ".extra")["ok"])
	_check("plain text rejected", not SeasonDefinition.decode_text("hello")["ok"])
	_check("broken JSON rejected", not SeasonDefinition.decode_text("{\"format\": ")["ok"])
	var big_payload := Marshalls.raw_to_base64(("a".repeat(SeasonDefinition.MAX_BYTES + 100)).to_utf8_buffer())
	_check("oversized base64 rejected", not SeasonDefinition.decode_text("WS1.%s.00000000" % big_payload.replace("=", ""))["ok"])
	_check("oversized text rejected", not SeasonDefinition.decode_text("{" + " ".repeat(SeasonDefinition.MAX_BYTES * 2))["ok"])
	var wide := "{\"name\":\"" + "é".repeat(SeasonDefinition.MAX_BYTES / 2 + 10) + "\"}"
	_check("oversized UTF-8 rejected", not SeasonDefinition.decode_text(wide)["ok"])
	var nested := "[".repeat(5000) + "]".repeat(5000)
	_check("deep nesting rejected safely", not SeasonDefinition.decode_text(nested)["ok"])
	_check("invalid season encodes to empty", SeasonDefinition.encode_share({}) == "" and SeasonDefinition.encode_json({}) == "")
	var floaty := "{\"format\":\"whiplash-season\",\"version\":1.0,\"name\":\"F\",\"races\":[{\"course_id\":\"split_shift\",\"laps\":4.0,\"reverse\":false}]}"
	_check("JSON float integers accepted", SeasonDefinition.decode_text(floaty)["ok"])
	_check("JSON fractional laps rejected", not SeasonDefinition.decode_text(floaty.replace("4.0", "4.5"))["ok"])


func _test_library() -> void:
	var library := SeasonLibrary.new()
	library.directory = _scratch.path_join("seasons")
	_check("empty library lists nothing", library.list_seasons().is_empty())
	var season: Dictionary = SeasonDefinition.validate(_season(2, true))["season"]
	var saved := library.save(season)
	_check("save succeeds", saved["ok"] and SeasonLibrary.is_valid_id(saved["id"]))
	_check("no temp file left behind", not FileAccess.file_exists(library.directory.path_join(saved["id"] + ".json.tmp")))
	var loaded := library.load_season(saved["id"])
	_check("load round-trips", loaded["ok"] and loaded["season"] == season)
	var listed := library.list_seasons()
	_check("list returns summary", listed.size() == 1 and listed[0]["id"] == saved["id"] and listed[0]["name"] == "Night Run" and listed[0]["race_count"] == 1)
	season["races"].append({"course_id": "split_shift", "laps": 9, "reverse": false})
	_check("saving same name updates in place", library.save(season)["id"] == saved["id"] and library.list_seasons().size() == 1 and library.list_seasons()[0]["race_count"] == 2)
	var other := season.duplicate(true)
	other["name"] = "Night-Run"
	_check("similar names get distinct ids", library.save(other)["id"] != saved["id"])
	_check("invalid season is not saved", not library.save({"name": "x"})["ok"] and library.list_seasons().size() == 2)
	for evil: String in ["../x", "..", "a/b", "a\\b", "", "UPPER", "a.b", "x".repeat(33), "user://seasons/x", "c:evil"]:
		_check("id '%s' rejected" % evil.left(12), not SeasonLibrary.is_valid_id(evil) and not library.load_season(evil)["ok"])
	for name_text: String in ["../../evil", "Ünïcode ☃", "   ", "A".repeat(40)]:
		_check("generated id safe for '%s'" % name_text.left(12), SeasonLibrary.is_valid_id(SeasonLibrary.make_id(name_text)))
	_check("missing season fails", not library.load_season("missing")["ok"])
	var escaped := _scratch.path_join("evil.json")
	library.save(season)
	_check("saving never writes outside directory", not FileAccess.file_exists(escaped))

	var shared := _scratch.path_join("shared.json")
	_check("export succeeds", library.export_file(shared, season)["ok"])
	var count_before := library.list_seasons().size()
	var imported := library.import_file(shared)
	_check("import validates", imported["ok"] and imported["season"] == SeasonDefinition.validate(season)["season"])
	_check("import does not save", library.list_seasons().size() == count_before)
	_check("export of invalid season fails", not library.export_file(_scratch.path_join("bad.json"), {})["ok"] and not FileAccess.file_exists(_scratch.path_join("bad.json")))
	_write(_scratch.path_join("junk.json"), "not json")
	_check("junk file rejected", not library.import_file(_scratch.path_join("junk.json"))["ok"])
	_write(_scratch.path_join("huge.json"), " ".repeat(SeasonDefinition.MAX_BYTES + 1))
	_check("oversized file rejected before read", not library.import_file(_scratch.path_join("huge.json"))["ok"])
	_write(_scratch.path_join("empty.json"), "")
	_check("empty file rejected", not library.import_file(_scratch.path_join("empty.json"))["ok"])
	_check("missing file rejected", not library.import_file(_scratch.path_join("nope.json"))["ok"])
	var bad_utf := FileAccess.open(_scratch.path_join("latin.json"), FileAccess.WRITE)
	bad_utf.store_buffer(PackedByteArray([0x7B, 0xFF, 0xFE, 0x7D]))
	bad_utf.close()
	_check("invalid UTF-8 file rejected", not library.import_file(_scratch.path_join("latin.json"))["ok"])
	var share_file := _scratch.path_join("code.txt")
	_write(share_file, SeasonDefinition.encode_share(season))
	_check("share code file imports", library.import_file(share_file)["ok"])

	for i: int in SeasonLibrary.MAX_FILES + 10:
		_write(library.directory.path_join("filler-%03d.json" % i), "x")
	_check("directory scan is bounded and skips invalid files", library.list_seasons().size() <= 3)

	var built := SeasonLibrary.season_one()
	_check("Season 1 preview is one valid Block Circuit race", SeasonDefinition.validate(built["season"])["ok"] and built["season"]["races"].size() == 1 and built["season"]["races"][0]["course_id"] == "block_circuit")
	var plan: Array = built["plan"]
	_check("Season 1 plan has nine titles, one available", plan.size() == 9 and plan.filter(func(p: Dictionary) -> bool: return p["available"]).size() == 1 and plan[0]["title"] == "Block Circuit" and plan[8]["cup"] == 3 and built["preview"])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean_scratch() -> void:
	_remove_tree(_scratch)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)
