extends Node3D
## Behavioral coverage of weapon sockets on all seven vehicles and of owner-safe smoke.
## Markers are read from the instanced GLBs and vehicles are compared with a mount-free
## baseline, so these checks do not restate ItemWeaponMounts' own tables.

const SETS := [
	["blackjack", ["boilerfang", "ramjet"]],
	["deadbolt", ["nightshift", "helix"]],
	["knifeedge", ["blackjack", "helix"]],
]
const FIXTURE_IDS := ["blackjack", "boilerfang", "ramjet", "deadbolt", "nightshift", "helix", "knifeedge"]

var _pass := 0
var _fail := 0
var scene: Node3D
var items: RaceItems
var race: RaceDirector
var road: StaticBody3D
var seen := {}


func _ready() -> void:
	for i in SETS.size():
		var cpus: Array[String] = []
		cpus.assign(SETS[i][1])
		await _run_set(String(SETS[i][0]), cpus, i == 0)
	for id: String in FIXTURE_IDS:
		_check("%s was exercised end to end" % id, seen.has(id))
	print("WEAPON ATTACHMENTS: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _run_set(player_id: String, cpus: Array[String], with_smoke: bool) -> void:
	GameSession.configure("WEAPON TEST", player_id, cpus)
	scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	items = scene.items
	race = scene.race
	race.tick(3.0)
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	for car: Vehicle in items.cars:
		car.gravity_scale = 0.0
		car.freeze = false
		car.linear_velocity = Vector3.ZERO
	road = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(250, 2, 250)
	shape.shape = box
	road.add_child(shape)
	add_child(road)
	road.position = Vector3(1100, 7, 1100)
	await _fixture()
	for i in items.cars.size():
		var car := items.cars[i]
		seen[car.vehicle_id] = true
		await _test_socket_geometry(car, i)
	for i in items.cars.size():
		await _test_projectile_origins(i)
	await _test_inventory_display()
	await _test_wall_blocking()
	await _test_resets()
	if with_smoke:
		await _test_smoke_ownership()
	road.queue_free()
	scene.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- sockets

func _test_socket_geometry(car: Vehicle, index: int) -> void:
	var id := car.vehicle_id
	var mounts: Dictionary = items._gun_mounts[index]
	_check("%s has one mount per end" % id, mounts.has("A") and mounts.has("B") and mounts["A"] != mounts["B"])
	_check("%s mounts are hidden until a weapon is shown" % id, not mounts["A"].visible and not mounts["B"].visible)
	var forward := -car.global_basis.z
	for end: String in ["A", "B"]:
		var mount: Node3D = mounts[end]
		_check("%s end %s mount is parented to the chassis" % [id, end], mount.get_parent() == car)
		var heading := -mount.global_basis.z
		var driving := forward if end == "A" else -forward
		_check("%s end %s mount faces its own driving direction" % [id, end], heading.dot(driving) > 0.999)
		var side := 1.0 if end == "A" else -1.0
		_check("%s end %s mount sits on its own end of the chassis" % [id, end],
			(mount.global_position - car.global_position).dot(forward) * side > 1.0)
		for kind in ["Gun", "Launcher"]:
			var model: Node3D = mount.get_node(kind)
			var names: Array = ["MuzzleLeft", "MuzzleRight"] if kind == "Gun" else ["Muzzle"]
			var positions: Array[Vector3] = []
			for marker_name in names:
				var marker := model.find_child(marker_name, true, false) as Node3D
				_check("%s end %s %s has %s" % [id, end, kind, marker_name], marker != null)
				if marker == null:
					continue
				positions.append(marker.global_position)
				_check("%s end %s %s %s points the barrel out of the car" % [id, end, kind, marker_name],
					(marker.global_position - mount.global_position).dot(driving) > 0.1)
				_check("%s end %s %s %s is above the road and below roof height" % [id, end, kind, marker_name],
					marker.global_position.y > car.global_position.y - 0.6 and marker.global_position.y < car.global_position.y + 2.5)
			if kind == "Gun" and positions.size() == 2:
				_check("%s end %s guns have two distinct barrels" % [id, end], positions[0].distance_to(positions[1]) > 0.05)
		_check("%s end %s mount has no collision objects" % [id, end],
			mount.find_children("*", "CollisionObject3D", true, false).is_empty()
			and mount.find_children("*", "CollisionShape3D", true, false).is_empty())
	# Mounts ride the body rather than world space.
	var before: Vector3 = mounts["A"].get_node("Launcher").find_child("Muzzle", true, false).global_position - car.global_position
	var parked := car.global_transform
	car.global_transform = Transform3D(Basis(Vector3.UP, 0.9), parked.origin + Vector3(7, 0, 3))
	var after: Vector3 = mounts["A"].get_node("Launcher").find_child("Muzzle", true, false).global_position - car.global_position
	_check("%s muzzle follows body rotation" % id, absf(after.length() - before.length()) < 0.001 and after.distance_to(before) > 0.1)
	car.global_transform = parked
	# Physical identity against a vehicle built without any mounts.
	var baseline := _spawn_baseline(id)
	_check("%s physics matches a mount-free vehicle" % id, _same_physics(_physics_signature(car), _physics_signature(baseline)))
	_check("%s hull size matches a mount-free vehicle" % id, (_hull_aabb(car).size - _hull_aabb(baseline).size).length() < 0.01)
	baseline.queue_free()
	# Cycling every display state never touches physical properties.
	var signature := _physics_signature(car)
	for weapon in ["machine_guns", "rockets", "homing", "grenades", "smoke", "oil", "shield", ""]:
		for end: String in ["A", "B"]:
			ItemWeaponMounts.show_weapon(mounts, end, weapon)
	ItemWeaponMounts.show_weapon(mounts, "A", "")
	_check("%s showing and hiding weapons mutates no physics" % id, _same_physics(signature, _physics_signature(car)))


func _spawn_baseline(id: String) -> Vehicle:
	var baseline: Vehicle = preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle(id))
	baseline.tuning = scene.car.tuning
	baseline.freeze = true
	baseline.gravity_scale = 0.0
	add_child(baseline)
	baseline.global_position = Vector3(3000, 100, 3000)
	return baseline


func _physics_signature(car: Vehicle) -> Array:
	var shapes: Array = []
	for node in car.find_children("*", "CollisionShape3D", true, false):
		var collision := node as CollisionShape3D
		if collision.shape == null:
			continue
		shapes.append([car.global_transform.affine_inverse() * collision.global_transform, collision.shape.get_debug_mesh().get_aabb()])
	return [car.mass, car.center_of_mass, car.inertia, shapes]


func _same_physics(a: Array, b: Array) -> bool:
	if not is_equal_approx(a[0], b[0]) or not (a[1] as Vector3).is_equal_approx(b[1]) or not (a[2] as Vector3).is_equal_approx(b[2]):
		return false
	if a[3].size() != b[3].size():
		return false
	for i in a[3].size():
		# Blackjack's bogie hull settles by about a millimetre while running, so allow a centimetre.
		var moved: float = ((a[3][i][0] as Transform3D).origin - (b[3][i][0] as Transform3D).origin).length()
		var resized: float = ((a[3][i][1] as AABB).size - (b[3][i][1] as AABB).size).length()
		if moved > 0.01 or resized > 0.01 or not (a[3][i][0] as Transform3D).basis.is_equal_approx((b[3][i][0] as Transform3D).basis):
			return false
	return true


func _hull_aabb(car: Vehicle) -> AABB:
	var hull := AABB()
	var first := true
	for node in car.find_children("*", "CollisionShape3D", true, false):
		var collision := node as CollisionShape3D
		if collision.shape == null:
			continue
		var box := (car.global_transform.affine_inverse() * collision.global_transform) * collision.shape.get_debug_mesh().get_aabb()
		hull = box if first else hull.merge(box)
		first = false
	return hull


# ---------------------------------------------------------------- projectile origins

func _test_projectile_origins(index: int) -> void:
	for end: String in ["A", "B"]:
		for weapon in ["machine_guns", "rockets", "grenades", "homing"]:
			await _fixture()
			var car := items.cars[index]
			car.active_end = end
			var label := "%s end %s %s" % [car.vehicle_id, end, weapon]
			if weapon == "homing":
				var other := items.cars[(index + 1) % items.cars.size()]
				other.global_position = car.global_position + car.forward_vector() * 25.0
				items.previous_positions[(index + 1) % items.cars.size()] = other.global_position
				await get_tree().physics_frame
			if weapon == "rockets":
				# Keep blind-fire targets isolated; moving the rival later must not overlap a third car.
				for other_index in items.cars.size():
					if other_index != index:
						items.cars[other_index].global_position = car.global_position + Vector3(70 + other_index * 10, 0, 0)
				await get_tree().physics_frame
			_equip(index, weapon)
			_check(label + " fires", items.fire(index) and items.shots.size() == 1)
			var mount: Node3D = items._gun_mounts[index][end]
			var model: Node3D = mount.get_node("Gun" if weapon == "machine_guns" else "Launcher")
			_check(label + " shows only the matching model on the driving end",
				mount.visible and model.visible and not mount.get_node("Launcher" if weapon == "machine_guns" else "Gun").visible
				and not items._gun_mounts[index]["B" if end == "A" else "A"].visible)
			var first_marker := model.find_child("MuzzleLeft" if weapon == "machine_guns" else "Muzzle", true, false) as Node3D
			var origin: Vector3 = items.shots[0]["pos"]
			_check(label + " projectile starts at the real muzzle node", first_marker != null and origin.distance_to(first_marker.global_position) < 0.01)
			var ahead := (origin - car.global_position).dot(car.forward_vector())
			_check(label + " projectile starts ahead of the car and not at its center", ahead > 1.0)
			var heading: Vector3 = Vector3(items.shots[0]["velocity"])
			heading.y = 0.0
			_check(label + " heads along the driving direction", heading.normalized().dot(car.forward_vector()) > 0.995)
			if weapon == "rockets":
				# A level rocket from this launcher must strike a same-height rival dead ahead.
				var rival_index := (index + 1) % items.cars.size()
				var rival := items.cars[rival_index]
				rival.global_position = car.global_position + car.forward_vector() * 20.0
				items.previous_positions[rival_index] = rival.global_position
				await get_tree().physics_frame
				items._tick_shots(0.6)
				_check(label + " rocket strikes a same-height rival dead ahead", items.protection[rival_index] > 0.0)
			if weapon == "machine_guns":
				items._tick_weapon(index, 0.065)
				var right := model.find_child("MuzzleRight", true, false) as Node3D
				_check(label + " second round alternates to the other barrel",
					items.shots.size() == 2 and Vector3(items.shots[1]["pos"]).distance_to(right.global_position) < 0.01
					and Vector3(items.shots[1]["pos"]).distance_to(origin) > 0.05)
				items._tick_weapon(index, 0.065)
				_check(label + " third round returns to the first barrel",
					items.shots.size() == 3 and Vector3(items.shots[2]["pos"]).distance_to(first_marker.global_position) < 0.01)


# ---------------------------------------------------------------- display follows inventory

func _test_inventory_display() -> void:
	var id := items.cars[0].vehicle_id
	await _fixture()
	var expectations := {"machine_guns": "Gun", "rockets": "Launcher", "homing": "Launcher", "grenades": "Launcher",
		"smoke": "", "oil": "", "shield": ""}
	for end: String in ["A", "B"]:
		items.cars[0].active_end = end
		var other := "B" if end == "A" else "A"
		for weapon: String in expectations:
			items.reset_racer(0)
			items.grant_item(0, weapon)
			items.tick(0.01)
			_advance(0)
			var shown := String(expectations[weapon])
			var mount: Node3D = items._gun_mounts[0][end]
			_check("%s held %s on end %s displays %s" % [id, weapon, end, shown if not shown.is_empty() else "nothing"],
				mount.visible == not shown.is_empty() and not items._gun_mounts[0][other].visible
				and (shown.is_empty() or (mount.get_node(shown).visible and not mount.get_node("Gun" if shown == "Launcher" else "Launcher").visible)))
		items.reset_racer(0)
		items.tick(0.01)
		_check("%s empty hands on end %s display no weapon" % [id, end], not items._gun_mounts[0]["A"].visible and not items._gun_mounts[0]["B"].visible)
	# Swapping ends while holding a weapon moves the model; the other end never shows.
	items.cars[0].active_end = "A"
	items.reset_racer(0)
	items.grant_item(0, "rockets")
	items.tick(0.01)
	_advance(0)
	items.cars[0].swap_ends()
	items.tick(0.01)
	_advance(0)
	_check("%s swapping ends moves the launcher" % id, items.cars[0].active_end == "B"
		and items._gun_mounts[0]["B"].visible and not items._gun_mounts[0]["A"].visible)
	items.cars[0].active_end = "A"
	# Final burst round keeps the gun visible, then it disappears with the empty inventory.
	items.reset_racer(0)
	_equip(0, "machine_guns")
	items.ammo[0] = 3
	items.fire(0)
	items.tick(0.01)
	_check("%s gun stays shown while the last burst is pending" % id, items.ammo[0] == 0 and items._gun_mounts[0]["A"].visible)
	items._tick_weapon(0, 1.0)
	items.tick(0.01)
	_advance(0)
	_check("%s gun hides once the final burst finishes" % id, items.held[0].is_empty() and not items._gun_mounts[0]["A"].visible)
	# Switching items replaces rather than accumulates: collect-style regrant after expiry.
	items.grant_item(0, "grenades")
	items.tick(0.01)
	_advance(0)
	var mount: Node3D = items._gun_mounts[0]["A"]
	_check("%s regranting a different weapon swaps the displayed model" % id, mount.get_node("Launcher").visible and not mount.get_node("Gun").visible)


# ---------------------------------------------------------------- blocking

func _test_wall_blocking() -> void:
	var id := items.cars[0].vehicle_id
	for end: String in ["A", "B"]:
		# Control: with a clear lane the rocket reaches the rival twenty metres away.
		await _fixture()
		var car := items.cars[0]
		car.active_end = end
		var lane := car.forward_vector()
		_place_rival_in_line_with_launcher(end, lane)
		await get_tree().physics_frame
		_equip(0, "rockets")
		items.fire(0)
		items._tick_shots(0.6)
		_check("%s end %s control rocket reaches the rival" % [id, end], items.protection[1] > 0.0)
		# A wall just ahead of the muzzle swallows tracers before they spawn.
		await _fixture()
		car = items.cars[0]
		car.active_end = end
		lane = car.forward_vector()
		var marker := items._gun_mounts[0][end].get_node("Gun").find_child("MuzzleLeft", true, false) as Node3D
		var reach := (marker.global_position - car.global_position).dot(lane)
		var wall := _wall(car.global_position + lane * (reach + 0.3))
		await get_tree().physics_frame
		_equip(0, "machine_guns")
		items.fire(0)
		_check("%s end %s wall at the muzzle prevents a tracer" % [id, end], items.shots.is_empty())
		wall.queue_free()
		# A wall mid-lane stops the rocket and its splash.
		await _fixture()
		car = items.cars[0]
		car.active_end = end
		lane = car.forward_vector()
		_place_rival_in_line_with_launcher(end, lane)
		wall = _wall(car.global_position + lane * 17.0)
		await get_tree().physics_frame
		_equip(0, "rockets")
		items.fire(0)
		items._tick_shots(0.6)
		# Car 2 sits off to one side and may legitimately be targetable from the B end.
		_check("%s end %s wall blocks rocket and splash" % [id, end], items.shots.is_empty() and items.protection[1] == 0.0 and items._target(0) != 1)
		wall.queue_free()
		await get_tree().physics_frame


## Rival twenty metres down the lane, vertically centred on the launcher muzzle so a
## level rocket cannot miss for reasons of mount height (that is checked separately).
func _place_rival_in_line_with_launcher(end: String, lane: Vector3) -> void:
	var car := items.cars[0]
	var marker := items._gun_mounts[0][end].get_node("Launcher").find_child("Muzzle", true, false) as Node3D
	var rival := items.cars[1]
	rival.global_position = car.global_position + lane * 20.0
	rival.global_position.y = marker.global_position.y - 0.25
	items.previous_positions[1] = rival.global_position


func _wall(pos: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 20, 1)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.position = Vector3(pos.x, 10, pos.z)
	return wall


# ---------------------------------------------------------------- resets

func _test_resets() -> void:
	var id := items.cars[0].vehicle_id
	await _fixture()
	items.grant_item(0, "rockets")
	items.tick(0.01)
	_advance(0)
	_check("%s precondition: launcher shown" % id, items._gun_mounts[0]["A"].visible)
	items.reset_racer(0)
	_check("%s recovery hides the launcher" % id, not items._gun_mounts[0]["A"].visible and not items._gun_mounts[0]["B"].visible)
	_equip(0, "machine_guns")
	items.fire(0)
	_check("%s precondition: a burst is pending" % id, items.burst_left[0] > 0 and items._gun_mounts[0]["A"].visible)
	race.entrants[0]["finish_time"] = 5.0
	items.tick(0.01)
	_check("%s finishing hides the gun and drops the burst" % id, not items._gun_mounts[0]["A"].visible and items.burst_left[0] == 0)
	race.entrants[0]["finish_time"] = -1.0
	items.grant_item(0, "rockets")
	items.tick(0.01)
	race.state = RaceDirector.State.RESULTS
	items.tick(0.01)
	_check("%s results screen hides every mount" % id, not items._gun_mounts[0]["A"].visible and not items._gun_mounts[0]["B"].visible)
	for i in 3:
		await _fixture()
	for car: Vehicle in items.cars:
		var mount_count := 0
		for child in car.get_children():
			if String(child.name).begins_with("ItemGun") and not child.is_queued_for_deletion():
				mount_count += 1
		_check("%s repeated resets leave exactly two mounts on %s" % [id, car.vehicle_id], mount_count == 2)
	for pair in items._gun_mounts:
		_check("%s reset mounts start hidden" % id, not pair["A"].visible and not pair["B"].visible)
	items.grant_item(0, "rockets")
	items.tick(0.01)
	race.state = RaceDirector.State.RESULTS
	scene.restart_race()
	await get_tree().physics_frame
	items = scene.items
	_check("%s restart clears held items and mounts" % id, items.held[0].is_empty()
		and not items._gun_mounts[0]["A"].visible and not items._gun_mounts[0]["B"].visible)
	race = scene.race
	race.tick(3.0)


# ---------------------------------------------------------------- owner-safe smoke

func _test_smoke_ownership() -> void:
	var layer := RaceItemArt.PLAYER_SMOKE_LAYER
	var cull: int = scene.rig.cam.cull_mask
	_check("chase camera renders owner smoke and the world", cull & 1 == 1)
	# Own smoke is rendered; its shader preserves the driver's sightline.
	await _fixture()
	items.grant_item(0, "smoke")
	items.fire(0)
	items.art.sync_streams(items.cars, items.active)
	var own: Dictionary = items.hazards[0]
	_check("player cloud is owned by the player", own["owner"] == 0)
	var puffs: Array = own["visual"].get_children()
	var all_visible := not puffs.is_empty()
	for puff: MeshInstance3D in puffs:
		all_visible = all_visible and (puff.layers & cull) != 0
	_check("every puff of the player's cloud is camera-visible", all_visible)
	_check("both owner and rival smoke streams are camera-visible",
		(items.art.streams[0]["smoke"].layers & cull) != 0 and (items.art.streams[1]["smoke"].layers & cull) != 0)
	_check("owner smoke retains the broad spray quantity", items.art.streams[0]["smoke"].amount >= 32)
	_check("player smoke is behind the active end", Vector3(own["pos"]).z > items.cars[0].global_position.z)
	items.cars[0].active_end = "B"
	items.cars[1].global_position = items.cars[0].global_position + Vector3.BACK * 25.0
	items.previous_positions[1] = items.cars[1].global_position
	await get_tree().physics_frame
	var pos0 := items.cars[0].global_position
	var pos1 := items.cars[1].global_position
	_check("own cloud sits between owner and a target but obstructs rivals only", items._smoke_blocks(pos0, pos1) and not items._smoke_blocks(pos0, pos1, 0))
	_check("owner keeps its missile lock through its own cloud", items._target(0) == 1)
	items._stop(0)
	_equip(0, "homing")
	_check("owner can fire homing through its own cloud", items.fire(0) and items.shots.size() == 1 and items.shots[0]["target"] == 1)
	items.cars[0].global_position = own["pos"]
	items.previous_positions[0] = own["pos"]
	items._tick_hazards(0.01)
	_check("owner inside its own cloud is not obscured", not items.obscured[0])
	items.cars[1].global_position = own["pos"]
	items.previous_positions[1] = own["pos"]
	items._tick_hazards(0.01)
	_check("rival inside the player's cloud is obscured", items.obscured[1])
	# Rival cloud: normal render layer, masks the player, obscures the player, not its owner.
	await _fixture()
	items.grant_item(1, "smoke")
	items.fire(1)
	items.art.sync_streams(items.cars, items.active)
	var rival: Dictionary = items.hazards[0]
	_check("rival cloud is owned by the rival", rival["owner"] == 1)
	var visible_to_camera: bool = not rival["visual"].get_children().is_empty()
	for puff: MeshInstance3D in rival["visual"].get_children():
		visible_to_camera = visible_to_camera and puff.layers & layer == 0 and puff.layers & 1 == 1
	_check("rival smoke stays visible to the player's camera", visible_to_camera)
	_check("rival smoke stream emits on the shared layer", items.art.streams[1]["smoke"].emitting and items.art.streams[1]["smoke"].layers & layer == 0)
	_check("rival cloud blocks the player's lock on the rival", items._target(0) < 0)
	_equip(0, "homing")
	_check("rival cloud keeps the player's homing missile unfired", not items.fire(0) and items.held[0] == "homing")
	items.cars[0].global_position = rival["pos"]
	items.previous_positions[0] = rival["pos"]
	items._tick_hazards(0.01)
	_check("player inside a rival cloud is obscured", items.obscured[0])
	items.cars[0].global_position = Vector3(1100, 10, 1100)
	items.previous_positions[0] = items.cars[0].global_position
	items.obscured[0] = false
	items.cars[1].global_position = rival["pos"]
	items.previous_positions[1] = rival["pos"]
	items._tick_hazards(0.01)
	_check("rival inside its own cloud is not obscured", not items.obscured[1])
	items.cars[1].global_position = Vector3(1100, 10, 1080)
	items.previous_positions[1] = items.cars[1].global_position
	items.cars[1].active_end = "B"
	await get_tree().physics_frame
	_check("rival keeps its own lock through its own cloud after swapping ends", items._target(1) == 0)
	items.cars[1].active_end = "A"
	items._tick_hazards(10.0)
	_check("player lock returns once the rival cloud expires", items._target(0) == 1)
	# The player's cloud is an obstruction for rivals.
	await _fixture()
	items.grant_item(0, "smoke")
	items.fire(0)
	items.cars[1].global_position = items.cars[0].global_position + Vector3.BACK * 25.0
	items.previous_positions[1] = items.cars[1].global_position
	await get_tree().physics_frame
	_check("player cloud blocks a rival's lock on the player", items._target(1) < 0)
	items._tick_hazards(10.0)
	_check("rival lock on the player returns after the cloud expires", items._target(1) == 0)
	# Deployment follows the active end.
	await _fixture()
	items.cars[0].active_end = "B"
	items.grant_item(0, "smoke")
	items.fire(0)
	_check("smoke from the B end deploys on the A side", Vector3(items.hazards[0]["pos"]).z < items.cars[0].global_position.z)


# ---------------------------------------------------------------- shared

## Grants an item and runs the deploy animation to completion so the weapon can fire at once.
func _equip(index: int, id: String) -> void:
	items.grant_item(index, id)
	_advance(index)


## Lets the fold rig finish whatever retract/deploy the last request started.
func _advance(index: int) -> void:
	ItemWeaponMounts.tick(items._gun_mounts[index], 2.0)


func _fixture() -> void:
	items.reset()
	race.state = RaceDirector.State.RACING
	for i in items.cars.size():
		var car := items.cars[i]
		car.global_position = Vector3(1100 + (50.0 if i == 2 else 0.0), 10, 1150.0 if i == 2 else 1100.0 - i * 20.0)
		car.global_basis = Basis.IDENTITY
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.active_end = "A"
		car.freeze = false
		items.previous_positions[i] = car.global_position
		race.entrants[i]["finish_time"] = -1.0
		var tracker: TrackProgress = race.entrants[i]["progress"]
		tracker.route_distance = float(i) * 20.0
	await get_tree().physics_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		push_error("FAIL: " + label)
