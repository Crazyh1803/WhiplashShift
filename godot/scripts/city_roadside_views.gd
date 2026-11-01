## QA camera plan for the roadside layer: driver-height views of every quarter, closeups of both landmarks, both skyscraper types (full and podium),
## boarded frontages, camps and barrel fires. Pure data (eye, target, subject box): tests check the framing, the QA scene captures it.
class_name CityRoadsideViews
extends RefCounted

const DRIVER_EYE := 1.5


static func plan(roadside: Node3D, course: CourseDefinition) -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	var towers: Array = roadside.get_meta("towers", [])
	for q in 4:
		var s := course.total_length * (q + 0.2) / 4.0
		for tower: Dictionary in towers:
			if tower["quarter"] == q:
				s = maxf(8.0, float(tower["s"]) - 70.0)
		var at := CityDistrict.sample(course, s)
		var direction: Vector3 = at["dir"]
		var subject := AABB((at["pos"] as Vector3) + direction * 60.0 - Vector3(30, 0, 30), Vector3(60, 30, 60))
		var tower_box := AABB()
		for tower: Dictionary in towers:
			if tower["quarter"] == q:
				tower_box = tower["bounds"]
		views.append({"name": "driver-q%d" % (q + 1), "kind": "driver", "eye": (at["pos"] as Vector3) + Vector3.UP * DRIVER_EYE, "target": (at["pos"] as Vector3) + direction * 85.0 + Vector3.UP * 3.0,
				"subject": tower_box if tower_box.size != Vector3.ZERO else subject, "fov": 75.0})
	for placement: Dictionary in roadside.get_meta("landmarks", []):
		var xf: Transform3D = placement["transform"]
		var box := CityRoadsideCatalog.bounds(placement["id"])
		var span := maxf(box.size.x, box.size.y * 1.2)
		views.append({"name": "landmark-%s-front" % placement["asset"], "kind": "landmark", "eye": xf * Vector3(box.get_center().x, 2.0, box.position.z - span * 0.9),
				"target": xf * Vector3(box.get_center().x, box.size.y * 0.32, 0.0), "subject": placement["bounds"], "fov": 62.0})
		views.append({"name": "landmark-%s-street" % placement["asset"], "kind": "landmark_detail", "eye": xf * Vector3(box.get_center().x + box.size.x * 0.22, 1.7, box.position.z - span * 0.32),
				"target": xf * Vector3(box.get_center().x - box.size.x * 0.05, 4.0, 0.0), "subject": placement["bounds"], "fov": 70.0})
	for tower: Dictionary in towers:
		var xf: Transform3D = tower["transform"]
		var box := CityRoadsideCatalog.bounds(tower["id"])
		views.append({"name": "%s-q%d-full" % [tower["id"], int(tower["quarter"]) + 1], "kind": "tower", "eye": xf * Vector3(box.get_center().x + 8.0, 20.0, box.position.z - box.size.y * 1.05),
				"target": xf * Vector3(box.get_center().x, box.size.y * 0.48, 0.0), "subject": tower["bounds"], "fov": 55.0})
		views.append({"name": "%s-q%d-podium" % [tower["id"], int(tower["quarter"]) + 1], "kind": "podium", "eye": xf * Vector3(box.get_center().x + 2.0, 1.7, box.position.z - 19.0),
				"target": xf * Vector3(box.get_center().x, 5.0, 0.0), "subject": AABB(tower["bounds"].position, Vector3(tower["bounds"].size.x, 12.0, tower["bounds"].size.z)), "fov": 75.0})
	for board: Dictionary in roadside.get_meta("boards", []):
		var xf: Transform3D = board["transform"]
		var host: AABB = board["host_bounds"]
		var local := CityRoadsideCatalog.bounds(board["id"])
		var distance := clampf(local.size.x * 0.62, 11.0, 30.0)
		views.append({"name": "boards-%s-q%d-s%d" % [board["host"], int(board["quarter"]) + 1, int(board["s"])], "kind": "boards", "eye": xf * Vector3(local.get_center().x, 1.7, local.position.z - distance),
				"target": xf * Vector3(local.get_center().x, minf(local.size.y, 8.0) * 0.45, 0.0), "subject": board["bounds"], "fov": 80.0})
	for camp: Dictionary in roadside.get_meta("camps", []):
		var xf: Transform3D = camp["transform"]
		var box := CityRoadsideCatalog.bounds(camp["id"])
		views.append({"name": "%s-q%d" % [camp["id"], int(camp["quarter"]) + 1], "kind": "camp", "eye": xf * Vector3(box.get_center().x + 1.0, 1.7, box.position.z - 7.5),
				"target": xf * Vector3(box.get_center().x, 0.8, box.get_center().z), "subject": camp["bounds"], "fov": 66.0})
	var shown := 0
	for barrel: Dictionary in roadside.get_meta("barrels", []):
		var xf: Transform3D = barrel["transform"]
		views.append({"name": "barrel-%d-%s" % [shown, "camp" if String(barrel["camp"]) != "" else "free"], "kind": "barrel", "eye": xf * Vector3(1.0, 1.5, -3.2),
				"target": xf * Vector3(0.0, 1.1, 0.0), "subject": barrel["effect"], "fov": 62.0})
		shown += 1
	return views


## Which roadside nodes overlap the view's subject and whether each is drawn at the view's eye, by the same node-bounds rule as CityRoadside.measure.
## Returns {"drawn": [kinds of overlapping nodes that are active], "culled": [kinds that are not]}.
static func subject_activity(roadside: Node3D, view: Dictionary) -> Dictionary:
	var drawn: Array[String] = []
	var culled: Array[String] = []
	var scenery := roadside.get_parent() as Node3D
	var subject: AABB = (view["subject"] as AABB).grow(1.0)
	for instance: MultiMeshInstance3D in roadside.find_children("*", "MultiMeshInstance3D", true, false):
		if not instance.custom_aabb.intersects(subject):
			continue
		var kind := String(instance.get_meta("roadside_kind", ""))
		if CityRoadside.active_tris(instance, scenery, view["eye"]) > 0:
			drawn.append(kind)
		else:
			culled.append(kind)
	return {"drawn": drawn, "culled": culled}


## Empty when the view's subject geometry is really drawn at its eye: full detail for towers, boards, camps, barrels and fires, never only the far LOD.
static func subject_problem(roadside: Node3D, view: Dictionary) -> String:
	var activity := subject_activity(roadside, view)
	var drawn: Array = activity["drawn"]
	var culled: Array = activity["culled"]
	match String(view["kind"]):
		"tower", "podium":
			if not "tower" in drawn or "tower_lod1" in drawn:
				return "tower near detail not the active tower geometry %s" % [activity]
		"boards":
			if not "boards" in drawn:
				return "boards not drawn %s" % [activity]
		"camp":
			if not "camp" in drawn:
				return "camp not drawn %s" % [activity]
		"barrel":
			if not ("barrel" in drawn and "fire" in drawn):
				return "barrel body and fire not both drawn %s" % [activity]
		"landmark", "landmark_detail":
			if not "landmark" in drawn:
				return "landmark overlay not drawn %s" % [activity]
		"driver":
			if (drawn.is_empty() and not culled.is_empty()):
				return "driver view subject entirely culled %s" % [activity]
	return ""


## True when `point` lies inside the view's frustum (vertical fov, 16:9), computed from the look-at basis so it does not depend on a viewport.
static func frames(view: Dictionary, point: Vector3, aspect: float = 16.0 / 9.0, margin: float = 0.95) -> bool:
	var xf := Transform3D(Basis.IDENTITY, view["eye"]).looking_at(view["target"], Vector3.UP)
	var local := xf.affine_inverse() * point
	if local.z >= -0.05 or -local.z > 2500.0:
		return false
	var half_v := tan(deg_to_rad(float(view.get("fov", 70.0))) * 0.5) * margin
	return absf(local.y / -local.z) <= half_v and absf(local.x / -local.z) <= half_v * aspect


## Camera3D for a planned view.
static func camera(view: Dictionary) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = view.get("fov", 70.0)
	cam.far = 2500.0
	cam.position = view["eye"]
	return cam
