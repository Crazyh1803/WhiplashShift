extends Node3D
## Folding weapon rigs and persistent oil, exercised through ItemWeaponMounts and the real RaceItems.tick.
## Assertions read node poses/visibility, emitted cues and hit results rather than restating private math.

var _pass := 0
var _fail := 0
var scene: Node3D
var items: RaceItems
var race: RaceDirector
var cues: Array[Dictionary] = []


func _ready() -> void:
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
	var road := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(250, 2, 250)
	shape.shape = box
	road.add_child(shape)
	add_child(road)
	road.position = Vector3(1100, 7, 1100)
	items.audio.cue.connect(_on_cue)
	await _test_mount_api()
	await _test_queued_fire()
	await _test_end_changes()
	await _test_burst_and_exhaustion()
	await _test_queue_cancellation()
	await _test_oil_persistence()
	await _test_oil_contact()
	await _test_oil_refill_and_caps()
	await _test_resets()
	print("DEPLOYMENT/OIL: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


# ---------------------------------------------------------------- ItemWeaponMounts

func _test_mount_api() -> void:
	await _fixture()
	var mounts := _mounts()
	var a: Node3D = mounts["A"]
	var b: Node3D = mounts["B"]
	_check("fresh rigs are folded away and not ready", not a.visible and not b.visible and not ItemWeaponMounts.ready(mounts, "A", "rockets"))
	ItemWeaponMounts.show_weapon(mounts, "A", "rockets")
	_check("show_weapon only requests: nothing appears or becomes ready", not a.visible and not ItemWeaponMounts.ready(mounts, "A", "rockets"))
	var door: Node3D = a.get_node("Hatch/DoorL")
	var launcher: Node3D = a.get_node("Launcher")
	var closed_door := door.rotation.z
	ItemWeaponMounts.tick(mounts, 0.1)
	_check("a short tick opens the hatch and starts a lift that is not yet ready", a.visible and not b.visible
		and absf(door.rotation.z - closed_door) > 0.1 and launcher.visible and launcher.position.y < -0.1
		and not ItemWeaponMounts.ready(mounts, "A", "rockets"))
	ItemWeaponMounts.tick(mounts, 1.0)
	_check("a long tick leaves the launcher standing at its mount and ready", ItemWeaponMounts.ready(mounts, "A", "rockets")
		and launcher.position.length() < 0.001 and not a.get_node("Gun").visible and (a.get_node("Hatch/ArmL") as Node3D).rotation.x > 0.5)
	_check("ready is specific to the end and weapon family", ItemWeaponMounts.ready(mounts, "A", "homing") and ItemWeaponMounts.ready(mounts, "A", "grenades")
		and not ItemWeaponMounts.ready(mounts, "A", "machine_guns") and not ItemWeaponMounts.ready(mounts, "B", "rockets")
		and not ItemWeaponMounts.ready(mounts, "A", "smoke") and not ItemWeaponMounts.ready(mounts, "C", "rockets"))
	# A different weapon on the same end: the old one fully folds before the new one opens.
	ItemWeaponMounts.show_weapon(mounts, "A", "machine_guns")
	_check("changing the request makes the old weapon not ready at once", not ItemWeaponMounts.ready(mounts, "A", "rockets")
		and not ItemWeaponMounts.ready(mounts, "A", "machine_guns"))
	ItemWeaponMounts.tick(mounts, 0.1)
	ItemWeaponMounts.tick(mounts, 0.2)
	_check("the old launcher is still retracting and the gun has not appeared", a.visible and launcher.visible and not a.get_node("Gun").visible)
	ItemWeaponMounts.tick(mounts, 2.0)
	_check("a large delta completes the retract and then the deploy", ItemWeaponMounts.ready(mounts, "A", "machine_guns")
		and a.get_node("Gun").visible and not launcher.visible)
	# Moving to the other end: A retracts before B opens.
	ItemWeaponMounts.show_weapon(mounts, "B", "machine_guns")
	ItemWeaponMounts.tick(mounts, 0.1)
	ItemWeaponMounts.tick(mounts, 0.2)
	_check("the old end is still retracting while the new end stays closed", a.visible and not b.visible
		and not ItemWeaponMounts.ready(mounts, "A", "machine_guns"))
	ItemWeaponMounts.tick(mounts, 2.0)
	_check("the new end ends up deployed and the old end folded", ItemWeaponMounts.ready(mounts, "B", "machine_guns") and not a.visible and b.get_node("Gun").visible)
	# Reversal mid-retract resumes from the current pose without hiding the rig.
	ItemWeaponMounts.show_weapon(mounts, "B", "")
	ItemWeaponMounts.tick(mounts, 0.15)
	_check("a requested fold is gradual", b.visible and not ItemWeaponMounts.ready(mounts, "B", "machine_guns"))
	ItemWeaponMounts.show_weapon(mounts, "B", "machine_guns")
	ItemWeaponMounts.tick(mounts, 0.05)
	_check("reversing mid-fold keeps the gun visible, not snapped shut or ready", b.visible and b.get_node("Gun").visible
		and not ItemWeaponMounts.ready(mounts, "B", "machine_guns"))
	ItemWeaponMounts.tick(mounts, 1.0)
	_check("the reversed fold finishes ready", ItemWeaponMounts.ready(mounts, "B", "machine_guns"))
	# hide(): graceful by default, snapped when immediate.
	ItemWeaponMounts.hide(mounts)
	_check("hide requests a fold: not ready yet but still drawn", b.visible and not ItemWeaponMounts.ready(mounts, "B", "machine_guns"))
	ItemWeaponMounts.tick(mounts, 0.05)
	_check("a graceful hide takes time", b.visible)
	ItemWeaponMounts.tick(mounts, 2.0)
	_check("a graceful hide finishes folded", not b.visible and not a.visible)
	ItemWeaponMounts.show_weapon(mounts, "A", "rockets")
	ItemWeaponMounts.tick(mounts, 2.0)
	ItemWeaponMounts.hide(mounts, true)
	_check("an immediate hide snaps every rig shut with the hatch closed", not a.visible and not b.visible
		and not a.get_node("Launcher").visible and absf((a.get_node("Hatch/DoorL") as Node3D).rotation.z) < 0.001
		and not ItemWeaponMounts.ready(mounts, "A", "rockets"))
	ItemWeaponMounts.tick(mounts, 2.0)
	_check("a hidden rig stays folded when nothing is requested", not a.visible and not b.visible)
	ItemWeaponMounts.show_weapon(mounts, "A", "smoke")
	ItemWeaponMounts.tick(mounts, 2.0)
	_check("utility items never open a rig", not a.visible and not b.visible)


# ---------------------------------------------------------------- RaceItems fire queue

func _test_queued_fire() -> void:
	await _fixture()
	_clear_lane()
	items.grant_item(0, "rockets")
	_check("pressing fire with a folded rig is accepted", items.fire(0))
	_check("a queued press spends nothing, fires nothing and says nothing", items.ammo[0] == 4 and items.shots.is_empty() and cues.is_empty())
	_check("a second press cannot stack another queued shot", not items.fire(0) and items.ammo[0] == 4)
	items.tick(0.1)
	_check("while deploying the shot is still held back", items.ammo[0] == 4 and items.shots.is_empty() and cues.is_empty()
		and _mounts()["A"].visible and not ItemWeaponMounts.ready(_mounts(), "A", "rockets"))
	items.tick(0.5)
	_check("the queued press fires exactly once when the rig is ready", items.ammo[0] == 3 and _cue_count("rockets") == 1)
	_check("the rocket leaves a deployed, visible launcher (no hidden muzzle)", cues.size() == 1 and cues[0]["ready"] and cues[0]["visible"])
	items.tick(1.0)
	_check("the queue is consumed and does not repeat", items.ammo[0] == 3 and _cue_count("rockets") == 1 and items.held[0] == "rockets")
	# Machine guns: one queued press becomes one three-round burst, every round from the deployed gun.
	await _fixture()
	_clear_lane()
	items.grant_item(0, "machine_guns")
	items.fire(0)
	items.tick(0.2)
	_check("a queued burst spends no ammo before the gun is ready", items.ammo[0] == 30 and items.shots.is_empty() and cues.is_empty())
	items.tick(0.5)
	_check("the queued burst releases three rounds for three ammo", items.ammo[0] == 27 and _cue_count("machine_guns") == 3)
	_check("every round came from a deployed visible gun", _all_cues_deployed())
	items.tick(0.5)
	_check("no extra rounds follow", items.ammo[0] == 27 and _cue_count("machine_guns") == 3)


func _test_end_changes() -> void:
	await _fixture()
	_clear_lane()
	_equip(0, "rockets")
	items.cars[0].active_end = "B"
	_check("a press on the wrong end queues instead of firing", items.fire(0) and items.ammo[0] == 4 and cues.is_empty())
	var a: Node3D = _mounts()["A"]
	var b: Node3D = _mounts()["B"]
	items.tick(0.1)
	_check("the old end starts folding while the new end stays shut", a.visible and not b.visible and cues.is_empty())
	items.tick(0.2)
	_check("the new end does not open before the old end has fully retracted", a.visible and not b.visible and items.ammo[0] == 4 and cues.is_empty())
	items.tick(0.2)
	_check("once the old end is folded the new end begins to open", not a.visible and b.visible and items.ammo[0] == 4)
	items.tick(1.0)
	_check("the queued shot leaves the new end only after it deployed", items.ammo[0] == 3 and cues.size() == 1
		and cues[0]["end"] == "B" and cues[0]["ready"] and cues[0]["visible"] and not a.visible)


func _test_burst_and_exhaustion() -> void:
	# A burst pauses while the rig is relocating and resumes from the new end.
	await _fixture()
	_clear_lane()
	_equip(0, "machine_guns")
	items.fire(0)
	_check("the first round leaves immediately from a ready gun", _cue_count("machine_guns") == 1 and items.burst_left[0] == 2 and items.ammo[0] == 27)
	items.cars[0].active_end = "B"
	items.tick(0.1)
	items.tick(0.1)
	var a: Node3D = _mounts()["A"]
	var b: Node3D = _mounts()["B"]
	_check("the burst pauses while the gun is undeployed", _cue_count("machine_guns") == 1 and items.burst_left[0] == 2 and items.ammo[0] == 27
		and a.visible and not b.visible)
	items.tick(2.0)
	_check("the burst resumes and finishes from the deployed end", _cue_count("machine_guns") == 3 and items.burst_left[0] == 0 and items.ammo[0] == 27
		and cues[1]["end"] == "B" and cues[2]["end"] == "B" and _all_cues_deployed() and items.held[0] == "machine_guns")
	# Fast reversal: swapping back before the other end opened never shows that end.
	await _fixture()
	_clear_lane()
	_equip(0, "machine_guns")
	items.fire(0)
	items.cars[0].active_end = "B"
	a = _mounts()["A"]
	b = _mounts()["B"]
	var other_end_shown := false
	items.tick(0.1)
	other_end_shown = other_end_shown or b.visible
	items.cars[0].active_end = "A"
	items.tick(0.05)
	other_end_shown = other_end_shown or b.visible
	_check("reversing keeps the burst paused and the gun on A drawn", _cue_count("machine_guns") == 1 and a.visible and not other_end_shown)
	items.tick(1.0)
	other_end_shown = other_end_shown or b.visible
	_check("the burst finishes from the original end without ever opening B", _cue_count("machine_guns") == 3 and items.ammo[0] == 27
		and not other_end_shown and cues[2]["end"] == "A" and _all_cues_deployed())
	# Final launcher round folds the rig away.
	await _fixture()
	_clear_lane()
	_equip(0, "rockets")
	items.ammo[0] = 1
	a = _mounts()["A"]
	_check("the last rocket fires and empties the slot", items.fire(0) and items.ammo[0] == 0 and items.held[0].is_empty())
	_check("the launcher is still standing at that instant", a.visible and a.get_node("Launcher").visible)
	items.tick(0.1)
	_check("the empty launcher folds back gradually", a.visible and not ItemWeaponMounts.ready(_mounts(), "A", "rockets"))
	items.tick(1.0)
	_check("the empty launcher ends folded away", not a.visible and not _mounts()["B"].visible)
	# Final machine-gun burst keeps the gun until the burst ends, then folds.
	await _fixture()
	_clear_lane()
	_equip(0, "machine_guns")
	items.ammo[0] = 3
	items.fire(0)
	a = _mounts()["A"]
	items.tick(0.01)
	_check("the gun stays out while the final burst is pending", a.visible and a.get_node("Gun").visible and items.ammo[0] == 0)
	items.tick(0.5)
	_check("the final burst completes all three rounds and empties the slot", _cue_count("machine_guns") == 3 and items.held[0].is_empty())
	items.tick(1.0)
	_check("the gun folds away after the final burst", not a.visible and not _mounts()["B"].visible)


func _test_queue_cancellation() -> void:
	await _fixture()
	_clear_lane()
	items.grant_item(0, "rockets")
	items.fire(0)
	items.reset_racer(0)
	# Re-supply without grant_item so only a stale queue could fire.
	items.held[0] = "rockets"
	items.ammo[0] = 4
	items.tick(1.0)
	_check("recovery cancels a queued press", items.shots.is_empty() and items.ammo[0] == 4 and cues.is_empty()
		and ItemWeaponMounts.ready(_mounts(), "A", "rockets"))
	await _fixture()
	_clear_lane()
	items.grant_item(0, "rockets")
	items.fire(0)
	items.grant_item(0, "machine_guns")
	items.tick(1.0)
	_check("a new pickup replaces a queued press", cues.is_empty() and items.ammo[0] == 30 and items.held[0] == "machine_guns")
	await _fixture()
	_clear_lane()
	items.grant_item(0, "rockets")
	items.fire(0)
	race.entrants[0]["finish_time"] = 5.0
	items.tick(0.1)
	race.entrants[0]["finish_time"] = -1.0
	items.held[0] = "rockets"
	items.ammo[0] = 4
	items.tick(1.0)
	_check("finishing cancels a queued press", cues.is_empty() and items.ammo[0] == 4)
	await _fixture()
	_clear_lane()
	items.grant_item(0, "rockets")
	items.fire(0)
	items.reset()
	_check("a full item reset folds every rig and drops the queue", cues.is_empty() and not _mounts()["A"].visible and not _mounts()["B"].visible)


# ---------------------------------------------------------------- oil

func _test_oil_persistence() -> void:
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	items.grant_item(1, "smoke")
	items.fire(1)
	var patch: Dictionary = _oils()[0]
	_check("oil and smoke both deploy", _oils().size() == 1 and _count("smoke") == 1)
	for i in 14:
		items.tick(1.0)
	_check("owner streams have ended", items.active[0].is_empty() and items.active[1].is_empty())
	_check("smoke has expired but oil has not", _count("smoke") == 0 and _oils().size() == 1 and _oils()[0]["visual"] == patch["visual"]
		and is_instance_valid(patch["visual"]) and patch["visual"].is_inside_tree())
	for i in 40:
		items.tick(1.0)
	_check("oil stays on the road long after any timer would have run out", _oils().size() == 1)
	# Owner availability: smoke follows its owner, oil does not.
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	items.grant_item(1, "smoke")
	items.fire(1)
	race.entrants[0]["finish_time"] = 5.0
	race.entrants[1]["finish_time"] = 6.0
	items.tick(0.1)
	_check("when the owners finish their smoke clears but their oil stays", _count("smoke") == 0 and _oils().size() == 1)
	var pos: Vector3 = _oils()[0]["pos"]
	race.entrants[2]["progress"].route_distance = 10.0
	_sweep(2, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("oil laid by a finished racer still catches a rival", items.oil_time[2] > 1.0 and _oils().is_empty())
	race.entrants[0]["finish_time"] = -1.0
	race.entrants[1]["finish_time"] = -1.0
	# Recovery removes the owner's smoke but keeps the owner's oil.
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	items.grant_item(1, "smoke")
	items.fire(1)
	items.reset_racer(1)
	_check("recovery clears that racer's smoke", _count("smoke") == 0 and _oils().size() == 1)
	var kept: Dictionary = _oils()[0]
	items.reset_racer(0)
	_check("recovery keeps the racer's own oil", _oils().size() == 1 and _oils()[0]["visual"] == kept["visual"] and is_instance_valid(kept["visual"]))
	pos = kept["pos"]
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("retained oil still works afterwards", items.oil_time[1] > 1.0)
	# Race reset and results wipe everything, oil included.
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	items.reset()
	_check("a race reset clears oil", items.hazards.is_empty())
	items.grant_item(0, "oil")
	items.fire(0)
	race.state = RaceDirector.State.RESULTS
	items.tick(0.01)
	_check("results clear oil", items.hazards.is_empty())


func _test_oil_contact() -> void:
	var pos: Vector3 = await _lay_patch()
	_check("a laid patch sits behind the owner", pos.z > items.cars[0].global_position.z)
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("a fast sweep between ticks catches oil neither endpoint touches", items.oil_time[1] > 1.0
		and items.cars[1].item_grip_multiplier == RaceItems.OIL_GRIP)
	_check("the first crossing consumes the patch", _oils().is_empty())
	items.oil_time[1] = 0.0
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("a consumed patch cannot oil anybody again", items.oil_time[1] == 0.0 and items.cars[1].item_grip_multiplier == 1.0)
	# A live dispenser may cross its own tail without wasting it; that exemption ends with the power-up.
	pos = await _lay_patch()
	var own_patch: Dictionary = _oils()[0]
	items.active[0] = "oil"
	items.remaining[0] = 1.0
	_sweep(0, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("a live dispenser neither consumes nor slips on its own oil", items.oil_time[0] == 0.0 and not own_patch["consumed"])
	items._stop(0)
	_sweep(0, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("the owner can consume its oil after dispensing ends", items.oil_time[0] > 1.0 and own_patch["consumed"])
	# Shield consumes the patch without grip loss.
	pos = await _lay_patch()
	items.grant_item(1, "shield")
	items.fire(1)
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("a shielded racer consumes oil without losing grip", _oils().is_empty() and items.oil_time[1] == 0.0
		and items.cars[1].item_grip_multiplier == 1.0 and items.active[1] == "shield")
	# Height window: below the patch or more than 2.5 m above it never counts.
	pos = await _lay_patch()
	for dy in [-0.4, 2.7, 8.0]:
		_sweep(1, pos + Vector3(-5.5, dy, 0), pos + Vector3(5.5, dy, 0))
		_check("a pass at %.1f m relative height misses the oil" % dy, items.oil_time[1] == 0.0 and _oils().size() == 1)
	_sweep(1, pos + Vector3(-5.5, 2.4, 0), pos + Vector3(5.5, 2.4, 0))
	_check("a pass within the height window hits the oil", items.oil_time[1] > 1.0 and _oils().is_empty())
	# Route isolation (layers of track above/below the same XZ) including the lap wrap.
	pos = await _lay_patch()
	var tracker: TrackProgress = race.entrants[1]["progress"]
	for far_route in [45.0, race.course.total_length * 0.5]:
		tracker.route_distance = far_route
		_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
		_check("a racer %.0f m along the route cannot hit this oil" % far_route, items.oil_time[1] == 0.0 and _oils().size() == 1)
	tracker.route_distance = race.course.total_length - 10.0
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("route proximity wraps across the start line", items.oil_time[1] > 1.0 and _oils().is_empty())
	# Teleports (> 12 m between ticks) never sweep.
	pos = await _lay_patch()
	_sweep(1, pos + Vector3(-13.0, 1.0, 0), pos + Vector3(0, 1.0, 0))
	_check("a teleport onto the patch does not oil the racer", items.oil_time[1] == 0.0 and _oils().size() == 1)
	_sweep(1, pos + Vector3(-11.0, 1.0, 0), pos + Vector3(0, 1.0, 0))
	_check("the same approach within the sweep limit does", items.oil_time[1] > 1.0 and _oils().is_empty())


func _test_oil_refill_and_caps() -> void:
	# A stationary owner whose live tail was consumed re-deposits in place; it never stacks.
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	var pos: Vector3 = _oils()[0]["pos"]
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("the owner's live trail patch was consumed by the rival", items.oil_time[1] > 1.0 and _oils().is_empty())
	_park(1, Vector3(1180, 10, 1080))
	items.tick(0.01)
	_check("a consumed tail re-deposits at the stationary owner", _oils().size() == 1 and Vector3(_oils()[0]["pos"]).distance_to(pos) < 0.5)
	for i in 5:
		items.tick(0.01)
	_check("a stationary owner does not stack duplicate oil", _oils().size() == 1)
	items.oil_time[1] = 0.0
	_sweep(1, pos + Vector3(-5.5, 1.0, 0), pos + Vector3(5.5, 1.0, 0))
	_check("the refilled patch is live", items.oil_time[1] > 1.0)
	# Smoke is capped and recycled, oil is neither capped nor evictable by smoke.
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	items.grant_item(1, "smoke")
	items.fire(1)
	var first_oil: Node = _oils()[0]["visual"]
	for i in 210:
		# Alternating between two spots keeps each car depositing a fresh patch every tick.
		var shifted := i % 2 == 0
		items.cars[0].global_position.x = 1100.0 + (2.6 if shifted else 0.0)
		items.cars[1].global_position.x = 1100.0 + (4.0 if shifted else 0.0)
		items.tick(0.001)
	_check("smoke is capped at its limit", _count("smoke") == RaceItems.MAX_HAZARDS)
	var oil_alive := false
	for patch in _oils():
		oil_alive = oil_alive or patch["visual"] == first_oil
	_check("smoke eviction never removed any oil, including the oldest", oil_alive and _oils().size() > RaceItems.MAX_HAZARDS)


func _test_resets() -> void:
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	items.grant_item(1, "rockets")
	items.fire(1)
	_check("oil is on the road before the race ends", _oils().size() == 1)
	race.state = RaceDirector.State.RESULTS
	items.tick(0.01)
	scene.restart_race()
	await get_tree().physics_frame
	items = scene.items
	race = scene.race
	_check("retry returns to the countdown", race.state == RaceDirector.State.COUNTDOWN)
	_check("retry clears oil, queued weapons and inventory", items.hazards.is_empty() and items.held[0].is_empty() and items.held[1].is_empty()
		and items.shots.is_empty() and not _mounts(1)["A"].visible and not _mounts(1)["B"].visible)
	race.tick(3.0)
	items.tick(1.0)
	_check("nothing reappears after the retry's countdown", items.hazards.is_empty() and items.shots.is_empty())


# ---------------------------------------------------------------- helpers

func _on_cue(id: String) -> void:
	if id not in ["machine_guns", "rockets", "homing", "grenades"]:
		return
	var end: String = items.cars[0].active_end
	var mounts := _mounts()
	var mount: Node3D = mounts[end]
	var model: Node3D = mount.get_node("Gun" if id == "machine_guns" else "Launcher")
	cues.append({"id": id, "end": end, "ready": ItemWeaponMounts.ready(mounts, end, id),
		"visible": mount.is_visible_in_tree() and model.is_visible_in_tree()})


func _all_cues_deployed() -> bool:
	for cue: Dictionary in cues:
		if not cue["ready"] or not cue["visible"]:
			return false
	return not cues.is_empty()


func _cue_count(id: String) -> int:
	var total := 0
	for cue: Dictionary in cues:
		total += int(cue["id"] == id)
	return total


func _mounts(index := 0) -> Dictionary:
	return items._gun_mounts[index]


func _equip(index: int, id: String) -> void:
	items.grant_item(index, id)
	ItemWeaponMounts.tick(_mounts(index), 2.0)


func _oils() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for hazard: Dictionary in items.hazards:
		if hazard["id"] == "oil":
			found.append(hazard)
	return found


func _count(id: String) -> int:
	var total := 0
	for hazard: Dictionary in items.hazards:
		total += int(hazard["id"] == id)
	return total


## Fresh fixture with one oil patch from racer 0 whose stream has been stopped (no refills).
func _lay_patch() -> Vector3:
	await _fixture()
	items.grant_item(0, "oil")
	items.fire(0)
	var pos: Vector3 = _oils()[0]["pos"]
	items._stop(0)
	return pos


## Moves racer `index` from `from` to `to` in a single RaceItems tick. No physics frame may pass in between.
func _sweep(index: int, from: Vector3, to: Vector3) -> void:
	items.cars[index].global_position = to
	items.previous_positions[index] = from
	items.tick(0.01)


func _park(index: int, pos: Vector3) -> void:
	items.cars[index].global_position = pos
	items.previous_positions[index] = pos


## Keeps rival 1 out of the rocket/tracer lane so shots are not absorbed by a hit.
func _clear_lane() -> void:
	_park(1, items.cars[1].global_position + Vector3(80, 0, 0))


func _fixture() -> void:
	items.reset()
	cues.clear()
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
