extends Node3D

var _pass := 0
var _fail := 0
var scene: Node3D
var items: RaceItems
var race: RaceDirector
var hud: Hud
var combat: CombatHud
var car: Vehicle
var foe: Vehicle
var view: Camera3D


func _ready() -> void:
	_test_angles()
	await _run()
	print("COMBAT HUD: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _test_angles() -> void:
	var b := Basis.IDENTITY
	_check("ahead is zero", absf(CombatHud.relative_angle(Vector3(0, 0, -10), b)) < 0.001)
	_check("right is +90", absf(CombatHud.relative_angle(Vector3(10, 0, 0), b) - PI * 0.5) < 0.001)
	_check("left is -90", absf(CombatHud.relative_angle(Vector3(-10, 0, 0), b) + PI * 0.5) < 0.001)
	_check("behind is 180", absf(absf(CombatHud.relative_angle(Vector3(0, 0, 10), b)) - PI) < 0.001)
	_check("height is ignored", absf(CombatHud.relative_angle(Vector3(0, 40, -10), b)) < 0.001)
	var turned := Basis(Vector3.UP, -PI * 0.5)
	_check("camera yaw rotates the reference", absf(CombatHud.relative_angle(Vector3(10, 0, 0), turned)) < 0.001)
	var down := Basis(Vector3.RIGHT, -PI * 0.5)
	_check("downward camera stays finite", is_finite(CombatHud.relative_angle(Vector3(3, 0, -4), down)))
	_check("damage wording grows with severity", CombatHud.damage_text(0.0) != CombatHud.damage_text(0.5)
		and CombatHud.damage_text(0.5) != CombatHud.damage_text(0.9))


func _run() -> void:
	GameSession.configure("COMBAT HUD TEST", "blackjack", ["boilerfang", "ramjet"])
	scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	items = scene.items
	race = scene.race
	hud = scene.hud
	combat = hud.combat
	car = scene.car
	scene.set_physics_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	foe = items.cars[1]
	car.freeze = true
	foe.freeze = true
	view = Camera3D.new()
	add_child(view)
	view.current = true
	hud.camera = view
	_check("combat readout is part of the HUD", combat != null and combat.get_parent() == hud)
	car.global_position = Vector3(0, 1, 0)
	foe.global_position = Vector3(0, 1, -20)

	hud._process(0.016)
	_check("countdown hides combat readout", not combat.visible)
	items.attack_hit.emit(0, foe.global_position, false, "rockets")
	_check("hits during countdown are ignored", combat.indicators.is_empty())
	race.tick(3.0)
	_check("racing shows combat readout", race.state == RaceDirector.State.RACING)
	hud._process(0.016)
	_check("combat visible while racing", combat.visible)
	_check("empty hands read EMPTY", combat.weapon["state"] == "EMPTY" and combat.utility["id"] == "")

	_test_weapon()
	_test_utility()
	_test_readiness()
	_test_damage()
	_test_attacks()
	_test_boundaries()
	scene.queue_free()
	await get_tree().process_frame


func _test_weapon() -> void:
	items.grant_item(0, "machine_guns")
	_deploy()
	hud._process(0.016)
	_check("machine guns ready with full magazine", combat.weapon["state"] == "READY" and combat.weapon["ammo"] == 30
		and combat.weapon["max"] == 30)
	items.ammo[0] = 27
	items.burst_left[0] = 2
	hud._process(0.016)
	_check("burst in progress reads FIRING with ammo spent", combat.weapon["state"] == "FIRING" and combat.weapon["ammo"] == 27)
	items.burst_left[0] = 0
	items.fire_cooldown[0] = 0.14
	hud._process(0.016)
	_check("cooldown reads COOLING with fraction", combat.weapon["state"] == "COOLING"
		and absf(float(combat.weapon["cooldown"]) - 0.5) < 0.01)
	items.fire_cooldown[0] = 0.0
	hud._process(0.016)
	_check("cooldown end returns READY", combat.weapon["state"] == "READY")
	# Last burst: ammo hits zero while the burst is still firing, then the gun disappears.
	items.ammo[0] = 3
	hud._process(0.016)
	items.ammo[0] = 0
	items.burst_left[0] = 2
	hud._process(0.016)
	_check("final burst still shows the gun", combat.weapon["state"] == "FIRING" and combat.weapon["ammo"] == 0)
	items.burst_left[0] = 0
	items.held[0] = ""
	items.fire_cooldown[0] = 0.2
	hud._process(0.016)
	_check("spent weapon reads EXHAUSTED by name", combat.weapon["state"] == "EXHAUSTED" and combat.weapon["name"] == "MACHINE GUNS")
	hud._process(1.0)
	_check("exhausted notice persists briefly", combat.weapon["state"] == "EXHAUSTED")
	hud._process(1.0)
	_check("exhausted notice clears to EMPTY", combat.weapon["state"] == "EMPTY")

	items.grant_item(0, "grenades")
	items.ammo[0] = 1
	hud._process(0.016)
	_check("single-shot weapon shows 1 / 5", combat.weapon["ammo"] == 1 and combat.weapon["max"] == 5)
	items.ammo[0] = 0
	items.held[0] = ""
	items.fire_cooldown[0] = 0.6
	hud._process(0.016)
	_check("last grenade used reads EXHAUSTED", combat.weapon["state"] == "EXHAUSTED" and combat.weapon["name"] == "GRENADES")
	hud._process(3.0)
	items.fire_cooldown[0] = 0.0
	# A weapon discarded by recovery is not "used up".
	items.grant_item(0, "rockets")
	hud._process(0.016)
	items.reset_racer(0)
	hud._process(0.016)
	_check("recovery discarding a weapon is not EXHAUSTED", combat.weapon["state"] == "EMPTY")
	items.grant_item(0, "shield")
	hud._process(0.016)
	_check("held utility reads READY without ammo", combat.weapon["state"] == "READY" and combat.held_utility == "shield"
		and combat.weapon["max"] == 0)
	items.held[0] = ""
	items.ammo[0] = 0


func _test_utility() -> void:
	items.active[0] = "shield"
	items.remaining[0] = 4.0
	items.grant_item(0, "rockets")
	_deploy()
	hud._process(0.016)
	_check("active utility shows time left", combat.utility["id"] == "shield" and absf(float(combat.utility["remaining"]) - 4.0) < 0.01
		and combat.utility["duration"] == 5.0 and not combat.utility["expiring"])
	_check("held weapon stays visible beside active utility", combat.weapon["id"] == "rockets" and combat.weapon["state"] == "WAIT")
	_check("WAIT matches the game refusing to fire", not items.fire(0) and items.ammo[0] == 4)
	items.remaining[0] = 0.6
	hud._process(0.016)
	_check("expiring utility is flagged", combat.utility["expiring"])
	items.active[0] = ""
	items.remaining[0] = 0.0
	hud._process(0.016)
	_check("expired utility leaves the held weapon", combat.utility["id"] == "" and combat.weapon["id"] == "rockets"
		and combat.weapon["state"] == "READY")
	items.held[0] = ""
	items.ammo[0] = 0
	items.active[0] = "oil"
	items.remaining[0] = 2.5
	hud._process(0.016)
	_check("every timed utility is tracked", combat.utility["id"] == "oil" and combat.utility["name"] == "OIL SLICK")
	items.active[0] = ""
	items.remaining[0] = 0.0


## Settle the weapon rig the way physics frames would, firing any queued shot.
func _deploy() -> void:
	items._tick_mounts(0, 2.0)


## READY must agree with what pressing E actually does, using the real mount state.
func _test_readiness() -> void:
	combat.clear()
	car.freeze = false # fire() refuses frozen cars; no physics frame runs inside this test
	items.held[0] = ""
	items.active[0] = ""
	items.remaining[0] = 0.0
	items.ammo[0] = 0
	items.fire_cooldown[0] = 0.0
	items.burst_left[0] = 0
	ItemWeaponMounts.hide(items._gun_mounts[0], true)
	items.grant_item(0, "rockets")
	hud._process(0.016)
	_check("undeployed rig reads DEPLOYING", combat.weapon["state"] == "DEPLOYING" and not items.weapon_deployed(0))
	_check("pressing E while deploying queues the shot", items.fire(0) and items.shot_queued(0) and items.ammo[0] == 4)
	hud._process(0.016)
	_check("queued shot reads QUEUED", combat.weapon["state"] == "QUEUED")
	_deploy()
	hud._process(0.016)
	_check("deployment fires the queued shot and cools down", items.ammo[0] == 3 and not items.shot_queued(0)
		and combat.weapon["state"] == "COOLING")
	items.fire_cooldown[0] = 0.0
	hud._process(0.016)
	_check("cooldown end is READY and E really fires", combat.weapon["state"] == "READY" and items.fire(0) and items.ammo[0] == 2)

	# Held utility is blocked while another utility runs, and READY again after.
	items.fire_cooldown[0] = 0.0
	items.held[0] = ""
	items.grant_item(0, "smoke")
	items.active[0] = "oil"
	items.remaining[0] = 3.0
	hud._process(0.016)
	_check("held utility reads WAIT while another is active", combat.weapon["state"] == "WAIT" and combat.held_utility == "smoke")
	_check("WAIT utility really cannot be used", not items.fire(0) and items.held[0] == "smoke")
	items.active[0] = ""
	items.remaining[0] = 0.0
	hud._process(0.016)
	_check("held utility is READY once the active one ends", combat.weapon["state"] == "READY")

	# Homing without a lock is refused by fire(), so it must not read READY.
	items.held[0] = ""
	ItemWeaponMounts.hide(items._gun_mounts[0], true)
	items.grant_item(0, "homing")
	_deploy()
	var home := foe.global_position
	foe.global_position = Vector3(0, 1, -500)
	hud._process(0.016)
	_check("homing with no target reads NO LOCK", combat.weapon["state"] == "NO LOCK" and not items.fire(0) and items.ammo[0] == 1)
	foe.global_position = home
	items.held[0] = ""
	items.ammo[0] = 0
	ItemWeaponMounts.hide(items._gun_mounts[0], true)
	hud._process(0.016)
	car.freeze = true
	combat.clear()


func _test_damage() -> void:
	car.damage = 0.0
	hud._process(0.016)
	_check("undamaged bodywork reads intact", combat.damage_level == 0.0 and combat.damage_label == "BODYWORK INTACT")
	car.apply_cosmetic_damage(0.5)
	hud._process(0.016)
	_check("cosmetic damage raises severity", absf(combat.damage_level - 0.5) < 0.001 and combat.damage_label == CombatHud.damage_text(0.5))
	car.damage = 0.2
	hud._process(0.016)
	_check("severity recovers with the vehicle", absf(combat.damage_level - 0.2) < 0.001)
	car.damage = 0.0
	hud._process(0.016)
	_check("full recovery returns to intact", combat.damage_label == "BODYWORK INTACT")
	_check("damage readout is not a health bar", not ("HEALTH" in combat.damage_label))


func _test_attacks() -> void:
	combat.clear()
	view.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 6, 9))
	car.damage = 0.0
	items.protection[0] = 0.0
	items._apply_hit(0, 1, "rockets")
	_check("hit raises one indicator", combat.indicators.size() == 1)
	_check("indicator keeps source position and unblocked flag", combat.indicators[0]["source"] == foe.global_position
		and combat.indicators[0]["blocked"] == false)
	hud._process(0.0)
	_check("source ahead of camera points up", absf(float(combat.indicators[0]["angle"])) < 0.01)
	view.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 6, 9))
	hud._process(0.0)
	_check("indicator follows camera swing without a new hit", absf(float(combat.indicators[0]["angle"]) - PI * 0.5) < 0.01)
	view.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 6, 9))
	hud._process(0.0)
	_check("indicator follows swap to the far end", absf(absf(float(combat.indicators[0]["angle"])) - PI) < 0.01)
	view.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 6, 9))
	hud._process(0.7)
	var half := float(combat.indicators[0]["life"])
	_check("indicator fades over time", half > 0.0 and half < CombatHud.INDICATOR_LIFE - 0.6)
	hud._process(1.0)
	_check("indicator expires", combat.indicators.is_empty())

	# Shield blocks are reported as blocked, and cost no bodywork.
	items.active[0] = "shield"
	items.remaining[0] = 3.0
	var before := car.damage
	items._apply_hit(0, 1, "grenades")
	_check("shield block shows a blocked indicator", combat.indicators.size() == 1 and combat.indicators[0]["blocked"] == true)
	_check("blocked hit causes no damage", car.damage == before)
	items.active[0] = ""
	items.remaining[0] = 0.0
	combat.clear()

	# Invulnerability windows and other racers' hits are not hits on the player.
	items.protection[0] = 1.0
	var worn := car.damage
	items._apply_hit(0, 1, "rockets")
	_check("invulnerable non-hit is suppressed", combat.indicators.is_empty() and car.damage == worn)
	items.protection[0] = 0.0
	items._apply_hit(1, 0, "rockets")
	_check("hits on other racers are not shown", combat.indicators.is_empty())
	items.protection[1] = 0.0

	# Source is where the attacker is at impact, not where it fired from.
	foe.global_position = Vector3(30, 1, 0)
	items._apply_hit(0, 1, "rockets")
	_check("source is the attacker's position at impact", combat.indicators.size() == 1
		and Vector3(combat.indicators[0]["source"]).is_equal_approx(Vector3(30, 1, 0)))
	hud._process(0.0)
	_check("source to the right points right", absf(float(combat.indicators[0]["angle"]) - PI * 0.5) < 0.01)
	foe.global_position = Vector3(0, 1, -20)
	combat.clear()
	items.protection[0] = 0.0


func _test_boundaries() -> void:
	items.protection[0] = 0.0
	items._apply_hit(0, 1, "rockets")
	items.grant_item(0, "rockets")
	car.damage = 0.4
	hud._process(0.0)
	_check("setup has indicator, weapon and damage", combat.indicators.size() == 1 and combat.weapon["id"] == "rockets"
		and combat.damage_level > 0.3)
	race.state = RaceDirector.State.RESULTS
	items.tick(0.016)
	hud._process(0.016)
	_check("results clear indicators, weapon and utility", combat.indicators.is_empty() and combat.weapon["state"] == "EMPTY"
		and combat.utility["id"] == "")
	_check("results hide combat readout and show the panel", not combat.visible and hud._results.visible)
	items.attack_hit.emit(0, foe.global_position, false, "rockets")
	_check("hits after the finish are ignored", combat.indicators.is_empty())
	car.damage = 0.4
	scene.restart_race()
	hud._process(0.016)
	_check("retry returns to countdown with a clean readout", race.state == RaceDirector.State.COUNTDOWN
		and combat.indicators.is_empty() and combat.damage_level == 0.0 and combat.weapon["state"] == "EMPTY"
		and not combat.visible)
	_check("retry hides results and keeps feedback label", not hud._results.visible and hud._item_status != null)
	race.tick(3.0)
	hud._process(0.016)
	_check("combat readout returns for the new race", combat.visible)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
