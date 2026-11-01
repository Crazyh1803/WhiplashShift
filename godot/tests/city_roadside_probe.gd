extends Node3D


func _ready() -> void:
	var course := BlockCircuitData.build_course()
	var host := Node3D.new()
	add_child(host)
	var t0 := Time.get_ticks_msec()
	var scenery := CityScenery.build(host, course)
	print("PROBE build ms=", Time.get_ticks_msec() - t0, " total_length=", course.total_length)
	print("PROBE catalog avail=", CityRoadsideCatalog.entries.size(), " err=", CityRoadsideCatalog.error)
	var rs := scenery.get_node_or_null("CityRoadside")
	if rs == null:
		print("PROBE no roadside")
		get_tree().quit(1)
		return
	for key in ["towers", "camps", "barrels", "boards", "landmarks"]:
		var arr: Array = rs.get_meta(key)
		print("PROBE ", key, " ", arr.size())
		for p: Dictionary in arr:
			print("   ", p["id"], " q=", p.get("quarter", "-"), " s=", snappedf(p["s"], 0.1), " side=", p["side"], " setback=", p.get("setback", "-"), " clear=", snappedf(CityScenery.road_clearance(p["bounds"], course), 0.1))
	print("PROBE rejected ", rs.get_meta("rejected"))
	var t1 := Time.get_ticks_msec()
	var m := CityRoadside.measure(scenery, course)
	print("PROBE measure ms=", Time.get_ticks_msec() - t1, " ", m)
	print("PROBE backdrop buildings=", scenery.get_node("CityBackdrop").get_meta("building_count"))
	get_tree().quit(0)
