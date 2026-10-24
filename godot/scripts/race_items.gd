## Solo arcade items: one held or active item, identical rules for every racer.
class_name RaceItems
extends Node3D

const PICKUP_RESPAWN := 6.0
const HIT_PROTECTION := 0.4
const RECOVERY_PROTECTION := 2.0
const PICKUP_RADIUS := 3.0
const OIL_GRIP := 0.35
const MAX_HAZARDS := 48
const MAX_EMISSIONS_PER_TICK := 4

var art: RaceItemArt

var race: RaceDirector
var cars: Array[Vehicle] = []
var held: Array[String] = []
var active: Array[String] = []
var remaining: Array[float] = []
var protection: Array[float] = []
var oil_time: Array[float] = []
var obscured: Array[bool] = []
var pickups: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var previous_positions: Array[Vector3] = []
var feedback: String = ""
var feedback_time := 0.0
var rng := RandomNumberGenerator.new()
var _cpu_wait: Array[float] = []
var _next_emit: Array[float] = []
var _shields: Array[MeshInstance3D] = []


func setup(p_race: RaceDirector, racers: Array[Vehicle]) -> void:
	if art == null:
		art = RaceItemArt.new()
		art.name = "ItemGraphics"
		add_child(art)
	_clear_transients()
	for car: Vehicle in cars:
		if is_instance_valid(car):
			car.item_grip_multiplier = 1.0
	for pickup: Dictionary in pickups:
		pickup["visual"].queue_free()
	pickups.clear()
	race = p_race
	cars.assign(racers)
	rng.randomize()
	var distance := 0.0
	var next_row := 160.0
	for point: Dictionary in race.course.points:
		distance += float(point["dist"])
		if distance < next_row or distance > race.course.total_length - 80.0:
			continue
		next_row += 320.0
		var direction: Vector3 = point["dir"]
		var side := Vector3(-direction.z, 0.0, direction.x)
		for lane: float in [-0.25, 0.0, 0.25]:
			var pos: Vector3 = point["pos"] + side * float(point["w"]) * lane + Vector3.UP * 1.5
			var supply := art.supply(pos)
			supply["pos"] = pos
			supply["cooldown"] = 0.0
			pickups.append(supply)
	reset()


func reset() -> void:
	_clear_transients()
	for shield: MeshInstance3D in _shields:
		shield.queue_free()
	_shields.clear()
	held.clear()
	active.clear()
	remaining.clear()
	protection.clear()
	oil_time.clear()
	obscured.clear()
	previous_positions.clear()
	_cpu_wait.clear()
	_next_emit.clear()
	for car: Vehicle in cars:
		held.append("")
		active.append("")
		remaining.append(0.0)
		protection.append(0.0)
		oil_time.append(0.0)
		obscured.append(false)
		previous_positions.append(car.global_position)
		_cpu_wait.append(0.0)
		_next_emit.append(0.0)
		car.item_grip_multiplier = 1.0
		var shield := _visual(car.global_position, car.tuning.body_length * 0.65, Color(0.3, 0.8, 1.0, 0.16), true)
		shield.hide()
		_shields.append(shield)
	for pickup: Dictionary in pickups:
		pickup["cooldown"] = 0.0
		pickup["visual"].visible = true
		pickup["model"].visible = true
	feedback = ""
	feedback_time = 0.0


func reset_racer(index: int) -> void:
	held[index] = ""
	_stop(index)
	protection[index] = RECOVERY_PROTECTION
	oil_time[index] = 0.0
	obscured[index] = false
	cars[index].item_grip_multiplier = 1.0
	previous_positions[index] = cars[index].global_position
	_cpu_wait[index] = 0.0
	for i in range(shots.size() - 1, -1, -1):
		if int(shots[i]["owner"]) == index:
			_remove(shots, i)
	for i in range(hazards.size() - 1, -1, -1):
		if int(hazards[i]["owner"]) == index:
			_remove(hazards, i)


func available(index: int) -> bool:
	return race.state == RaceDirector.State.RACING and index >= 0 and index < cars.size() \
		and float(race.entrants[index]["finish_time"]) < 0.0 and not cars[index].freeze


func fire(index: int) -> bool:
	if not available(index) or held[index].is_empty() or not active[index].is_empty():
		return false
	var id := held[index]
	# With no visible target, keep the rare missile rather than silently waste it.
	if id == "homing" and _target(index) < 0:
		if index == 0:
			_message("NO MISSILE LOCK — ITEM SAVED")
		return false
	held[index] = ""
	active[index] = id
	remaining[index] = float(ItemCatalog.DATA[id]["duration"])
	_next_emit[index] = float(ItemCatalog.DATA[id]["interval"])
	if id == "shield":
		oil_time[index] = 0.0
		cars[index].item_grip_multiplier = 1.0
		_shields[index].global_position = cars[index].global_position
		_shields[index].show()
	else:
		_emit(index, id)
	if id == "homing":
		_stop(index)
	if index == 0:
		_message(ItemCatalog.label(id) + (" FIRED" if id == "homing" else " ACTIVE"))
	return true


func tick(delta: float) -> void:
	if race.state != RaceDirector.State.RACING:
		_clear_transients()
		for i in cars.size():
			held[i] = ""
			_stop(i)
			oil_time[i] = 0.0
			obscured[i] = false
			cars[i].item_grip_multiplier = 1.0
		return
	art.tick(delta)
	feedback_time = maxf(0.0, feedback_time - delta)
	for i in cars.size():
		protection[i] = maxf(0.0, protection[i] - delta)
		oil_time[i] = maxf(0.0, oil_time[i] - delta)
		_cpu_wait[i] = maxf(0.0, _cpu_wait[i] - delta)
		obscured[i] = false
		if not available(i):
			held[i] = ""
			_stop(i)
			oil_time[i] = 0.0
			cars[i].item_grip_multiplier = 1.0
			continue
		_tick_active(i, delta)
	_collect(delta)
	for i in cars.size():
		if i > 0 and available(i) and not held[i].is_empty() and _cpu_wait[i] <= 0.0:
			if held[i] in ["shield", "smoke", "oil"] or _target(i, held[i] != "homing") >= 0:
				fire(i)
	_tick_hazards(delta)
	for i in cars.size():
		previous_positions[i] = cars[i].global_position
	_tick_shots(delta)
	for i in cars.size():
		cars[i].item_grip_multiplier = OIL_GRIP if oil_time[i] > 0.0 else 1.0
		_shields[i].global_position = cars[i].global_position
	for i in range(effects.size() - 1, -1, -1):
		var effect := effects[i]
		effect["life"] = float(effect["life"]) - delta
		effect["visual"].scale += Vector3.ONE * delta * 7.0
		if float(effect["life"]) <= 0.0:
			_remove(effects, i)


func _tick_active(index: int, delta: float) -> void:
	if active[index].is_empty():
		return
	var id := active[index]
	var interval := float(ItemCatalog.DATA[id]["interval"])
	var step := minf(delta, remaining[index])
	remaining[index] = maxf(0.0, remaining[index] - step)
	if remaining[index] < 0.000001:
		remaining[index] = 0.0
	if interval > 0.0:
		_next_emit[index] -= step
		var emitted := 0
		while emitted < MAX_EMISSIONS_PER_TICK and _next_emit[index] <= 0.0 and (remaining[index] > 0.0 or _next_emit[index] < -0.00001):
			_emit(index, id)
			_next_emit[index] += interval
			emitted += 1
		if _next_emit[index] <= 0.0:
			_next_emit[index] = interval
	if remaining[index] <= 0.0:
		_stop(index)
		if index == 0:
			_message(ItemCatalog.label(id) + " EXPIRED")


func _stop(index: int) -> void:
	active[index] = ""
	remaining[index] = 0.0
	_next_emit[index] = 0.0
	_shields[index].hide()


func _collect(delta: float) -> void:
	for pickup: Dictionary in pickups:
		pickup["cooldown"] = maxf(0.0, float(pickup["cooldown"]) - delta)
		var visual: Node3D = pickup["model"]
		visual.visible = float(pickup["cooldown"]) <= 0.0
		visual.rotate_y(delta * 0.45)
		visual.position.y = sin(art.clock * 3.0) * 0.15
		visual.get_node("HolographicDisplay").rotate_y(-delta)
		var label: Label3D = pickup["label"]
		label.text = "ITEM BOX" if visual.visible else "RESPAWN %.0fs" % ceilf(float(pickup["cooldown"]))
		if not visual.visible:
			continue
		for i in cars.size():
			if not available(i) or not held[i].is_empty() or not active[i].is_empty():
				continue
			var start := previous_positions[i]
			var end := cars[i].global_position
			if start.distance_to(end) > maxf(12.0, cars[i].linear_velocity.length() * delta * 2.0):
				start = end
			var closest := Geometry3D.get_closest_point_to_segment(pickup["pos"], start, end)
			if closest.distance_to(pickup["pos"]) > PICKUP_RADIUS:
				continue
			held[i] = ItemCatalog.roll(rng.randf())
			_cpu_wait[i] = 0.8
			pickup["cooldown"] = PICKUP_RESPAWN
			visual.hide()
			art.burst(pickup["pos"], Color("ffc34d"), 10, false)
			if i == 0:
				_message(ItemCatalog.label(held[i]) + " READY  [E]")
			break


func _emit(index: int, id: String) -> void:
	var direction := _fire_direction(index)
	var origin := cars[index].global_position + Vector3.UP * 0.35
	if id in ["smoke", "oil"]:
		_drop(index, id, direction)
		return
	var data: Dictionary = ItemCatalog.DATA[id]
	var velocity := direction * float(data["speed"])
	if id == "grenades":
		velocity += Vector3.UP * 8.0
	var visual := art.projectile(origin, direction, id)
	art.muzzle(origin + direction * cars[index].tuning.body_length * 0.5, id != "machine_guns")
	shots.append({"owner": index, "id": id, "pos": origin, "velocity": velocity,
		"life": float(data["life"]), "target": _target(index) if id == "homing" else -1, "visual": visual})


func _drop(index: int, id: String, direction: Vector3) -> void:
	var start := cars[index].global_position
	var end := start - direction * (cars[index].tuning.body_length * 0.5 + 4.0)
	# A rear-facing wall or missing road must not receive a hazard on its far side.
	if not _ray(start, end, index).is_empty():
		return
	var ground := _ray(end + Vector3.UP * 2.0, end - Vector3.UP * 6.0, index)
	if ground.is_empty() or ground["collider"] is Vehicle:
		return
	var pos: Vector3 = ground["position"] + Vector3.UP * (3.0 if id == "smoke" else 0.06)
	var color := Color(0.12, 0.14, 0.18, 0.65) if id == "smoke" else Color("41235f")
	var visual := _visual(pos, 5.0 if id == "smoke" else 3.5, color, true)
	if id == "oil":
		visual.scale.y = 0.015
	if hazards.size() >= MAX_HAZARDS:
		_remove(hazards, 0)
	hazards.append({"id": id, "owner": index, "pos": pos, "life": 5.0 if id == "smoke" else 7.0,
		"radius": 5.0 if id == "smoke" else 3.5, "visual": visual})


func _tick_hazards(delta: float) -> void:
	for h in range(hazards.size() - 1, -1, -1):
		var hazard := hazards[h]
		hazard["life"] = float(hazard["life"]) - delta
		if float(hazard["life"]) <= 0.0 or not available(int(hazard["owner"])):
			_remove(hazards, h)
			continue
		for i in cars.size():
			if not available(i) or not _same_section(i, int(hazard["owner"])):
				continue
			var start := previous_positions[i]
			var end := cars[i].global_position
			if start.distance_to(end) > 12.0:
				start = end
			var pos: Vector3 = hazard["pos"]
			if hazard["id"] == "oil":
				pos.y = end.y
			var near := Geometry3D.get_closest_point_to_segment(pos, start, end)
			if near.distance_to(pos) > float(hazard["radius"]):
				continue
			if hazard["id"] == "smoke":
				obscured[i] = true
			elif active[i] != "shield":
				oil_time[i] = 1.2


func _target(index: int, straight: bool = false) -> int:
	var origin := cars[index].global_position + Vector3.UP * 0.35
	var forward := _fire_direction(index)
	var best := -1
	var best_distance := 140.0
	for other in cars.size():
		if other == index or not available(other) or not _same_section(index, other):
			continue
		var end := cars[other].global_position + Vector3.UP * 0.35
		var offset := end - origin
		var distance := offset.length()
		if distance < 7.0 or distance >= best_distance or forward.dot(offset.normalized()) < 0.5:
			continue
		if straight:
			var prediction := offset + cars[other].linear_velocity * (distance / 105.0)
			if (prediction - forward * prediction.dot(forward)).length() > 2.0:
				continue
		if _smoke_blocks(origin, end):
			continue
		var hit := _ray(origin, end, index)
		if not hit.is_empty() and hit["collider"] == cars[other]:
			best = other
			best_distance = distance
	return best


func _tick_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var shot := shots[i]
		var owner := int(shot["owner"])
		if not available(owner):
			_remove(shots, i)
			continue
		var id := String(shot["id"])
		var start: Vector3 = shot["pos"]
		var step := minf(delta, float(shot["life"]))
		var velocity: Vector3 = shot["velocity"]
		if id == "homing":
			var target := int(shot["target"])
			if target >= 0 and available(target) and _same_section(owner, target):
				var end_pos := cars[target].global_position + Vector3.UP * 0.35
				var sight := _ray(start, end_pos, owner)
				if not _smoke_blocks(start, end_pos) and not sight.is_empty() and sight["collider"] == cars[target]:
					velocity = velocity.normalized().slerp((end_pos - start).normalized(), minf(1.0, step * 2.5)) * float(ItemCatalog.DATA[id]["speed"])
		if id == "grenades":
			velocity.y -= 12.0 * step
		shot["velocity"] = velocity
		var end := start + velocity * step
		var hit := _ray(start, end, owner)
		shot["life"] = float(shot["life"]) - step
		if not hit.is_empty():
			_impact(shot, hit["position"], hit["normal"], hit["collider"])
			_remove(shots, i)
			continue
		shot["pos"] = end
		shot["visual"].global_position = end
		art.trail(shot, delta)
		if float(shot["life"]) <= 0.0:
			if id == "grenades":
				_impact(shot, end, Vector3.UP, null)
			_remove(shots, i)


func _impact(shot: Dictionary, pos: Vector3, normal: Vector3, collider: Object) -> void:
	var id := String(shot["id"])
	var owner := int(shot["owner"])
	var data: Dictionary = ItemCatalog.DATA[id]
	var radius := float(data.get("radius", 0.0))
	for i in cars.size():
		if i == owner or not available(i) or not _same_section(owner, i):
			continue
		var direct := collider == cars[i]
		if not direct:
			if radius <= 0.0 or cars[i].global_position.distance_to(pos) > radius:
				continue
			# Start outside the impacted surface so blast cannot pass through walls.
			var sight := _ray(pos + normal * 0.15, cars[i].global_position, owner)
			if not sight.is_empty() and sight["collider"] != cars[i]:
				continue
		_apply_hit(i, owner, id)
	art.burst(pos, Color(data["color"]), 12 if radius > 0 else 4, radius > 0)


func _apply_hit(victim: int, owner: int, id: String) -> void:
	if active[victim] == "shield":
		if victim == 0 or owner == 0:
			_message("SHIELD BLOCKED HIT")
		return
	if protection[victim] > 0.0:
		return
	var data: Dictionary = ItemCatalog.DATA[id]
	var car := cars[victim]
	var flat := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
	car.apply_central_impulse(-flat.normalized() * minf(flat.length() * float(data["loss"]), float(data["cap"])) * car.mass)
	protection[victim] = HIT_PROTECTION
	if victim == 0:
		_message("HIT — SPEED LOST")
	elif owner == 0:
		_message("HIT CONFIRMED")


func _smoke_blocks(start: Vector3, end: Vector3) -> bool:
	for hazard: Dictionary in hazards:
		if hazard["id"] != "smoke":
			continue
		var near := Geometry3D.get_closest_point_to_segment(hazard["pos"], start, end)
		if near.distance_to(hazard["pos"]) <= float(hazard["radius"]):
			return true
	return false


func _fire_direction(index: int) -> Vector3:
	var forward := cars[index].forward_vector()
	forward.y = 0.0
	return forward.normalized()


func _same_section(owner: int, victim: int) -> bool:
	var a: TrackProgress = race.entrants[owner]["progress"]
	var b: TrackProgress = race.entrants[victim]["progress"]
	var gap := fposmod(absf(a.route_distance - b.route_distance), race.course.total_length)
	return minf(gap, race.course.total_length - gap) <= 160.0


func _ray(start: Vector3, end: Vector3, owner: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [cars[owner].get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _visual(pos: Vector3, radius: float, color: Color, sphere: bool = false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	if sphere:
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 16
		mesh.rings = 8
		visual.mesh = mesh
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * radius * 2.0
		visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = color.a >= 1.0
	material.emission = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = material
	add_child(visual)
	visual.global_position = pos
	return visual


func _message(message: String) -> void:
	feedback = message
	feedback_time = 1.5


func _remove(collection: Array[Dictionary], index: int) -> void:
	collection[index]["visual"].queue_free()
	collection.remove_at(index)


func _clear_transients() -> void:
	if art:
		art.clear()
	for collection: Array[Dictionary] in [shots, effects, hazards]:
		for entry: Dictionary in collection:
			entry["visual"].queue_free()
		collection.clear()


func _exit_tree() -> void:
	for car: Vehicle in cars:
		if is_instance_valid(car):
			car.item_grip_multiplier = 1.0
