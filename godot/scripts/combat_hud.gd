## Native combat readout: weapon ammo/readiness, timed utility bar, cosmetic bodywork
## damage and fading camera-relative attack indicators. Pure state is updated by
## `update()`; `_draw()` only paints it, so tests assert on the state.
class_name CombatHud
extends Control

const INDICATOR_LIFE := 1.4
const EXHAUSTED_TIME := 1.6
const EXPIRY_WARNING := 1.0

var weapon := {"state": "EMPTY", "id": "", "name": "", "ammo": 0, "max": 0, "cooldown": 0.0, "burst": 0}
var utility := {"id": "", "name": "", "remaining": 0.0, "duration": 0.0, "expiring": false}
var held_utility := ""
var damage_level := 0.0
var damage_label := "BODYWORK INTACT"
var indicators: Array[Dictionary] = []
var _prev_id := ""
var _prev_ammo := 0
var _prev_burst := 0
var _exhausted := 0.0
var _exhausted_name := ""


func _ready() -> void:
	name = "CombatHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Angle of `delta` (world) in the camera's ground plane: 0 ahead, +PI/2 right, PI behind.
static func relative_angle(delta: Vector3, cam_basis: Basis) -> float:
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z)
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
	if forward.length_squared() < 0.0001:
		# Looking straight down: fall back to the camera's up vector as "ahead".
		forward = Vector3(cam_basis.y.x, 0.0, cam_basis.y.z)
	forward = forward.normalized()
	right = right.normalized()
	return atan2(delta.dot(right), delta.dot(forward))


static func damage_text(level: float) -> String:
	if level < 0.02:
		return "BODYWORK INTACT"
	if level < 0.34:
		return "BODYWORK SCUFFED"
	if level < 0.67:
		return "BODYWORK BATTERED"
	return "BODYWORK WRECKED"


func clear() -> void:
	indicators.clear()
	_exhausted = 0.0
	_prev_id = ""
	_prev_ammo = 0
	_prev_burst = 0
	weapon = {"state": "EMPTY", "id": "", "name": "", "ammo": 0, "max": 0, "cooldown": 0.0, "burst": 0}
	utility = {"id": "", "name": "", "remaining": 0.0, "duration": 0.0, "expiring": false}
	held_utility = ""
	damage_level = 0.0
	damage_label = damage_text(0.0)
	queue_redraw()


## Record an incoming attack. `source` is the attacker's world position at impact.
func add_hit(source: Vector3, blocked: bool) -> void:
	indicators.append({"source": source, "blocked": blocked, "life": INDICATOR_LIFE})
	if indicators.size() > 6:
		indicators.pop_front()


func update(delta: float, items: RaceItems, car: Vehicle, camera: Camera3D) -> void:
	_update_weapon(delta, items)
	_update_utility(items)
	damage_level = clampf(car.damage, 0.0, 1.0) if car != null else 0.0
	damage_label = damage_text(damage_level)
	for i in range(indicators.size() - 1, -1, -1):
		indicators[i]["life"] = float(indicators[i]["life"]) - delta
		if float(indicators[i]["life"]) <= 0.0:
			indicators.remove_at(i)
	for entry: Dictionary in indicators:
		if car != null and camera != null:
			var offset := Vector3(entry["source"]) - car.global_position
			offset.y = 0.0
			entry["angle"] = relative_angle(offset, camera.global_basis) if offset.length_squared() > 0.01 else 0.0
	queue_redraw()


func _update_weapon(delta: float, items: RaceItems) -> void:
	_exhausted = maxf(0.0, _exhausted - delta)
	var id := items.held[0]
	var burst := items.burst_left[0]
	if id.is_empty() or not ItemCatalog.is_ammo(id):
		# An ammo weapon that vanished right after its last round was used up, not discarded.
		if not _prev_id.is_empty() and id.is_empty() and _prev_ammo <= int(ItemCatalog.DATA[_prev_id]["cost"]) \
				and (items.fire_cooldown[0] > 0.0 or _prev_burst > 0 or burst > 0):
			_exhausted = EXHAUSTED_TIME
			_exhausted_name = ItemCatalog.label(_prev_id)
		_prev_id = ""
		held_utility = id
		var state := "EXHAUSTED" if _exhausted > 0.0 and id.is_empty() else ("READY" if not id.is_empty() else "EMPTY")
		if state == "READY" and not items.active[0].is_empty():
			state = "WAIT"
		weapon = {"state": state, "id": id, "name": _exhausted_name if state == "EXHAUSTED" else ItemCatalog.label(id),
			"ammo": 0, "max": 0, "cooldown": 0.0, "burst": burst}
		return
	held_utility = ""
	var data: Dictionary = ItemCatalog.DATA[id]
	var state := "READY"
	var cooldown := 0.0
	if burst > 0:
		state = "FIRING"
	elif items.fire_cooldown[0] > 0.0:
		state = "COOLING"
		cooldown = clampf(items.fire_cooldown[0] / float(data["cooldown"]), 0.0, 1.0)
	elif items.ammo[0] < int(data["cost"]):
		state = "EXHAUSTED"
	elif not items.active[0].is_empty():
		state = "WAIT"
	elif items.shot_queued(0):
		state = "QUEUED"
	elif not items.weapon_deployed(0):
		state = "DEPLOYING"
	elif id == "homing" and not items.has_lock(0):
		state = "NO LOCK"
	weapon = {"state": state, "id": id, "name": ItemCatalog.label(id), "ammo": items.ammo[0],
		"max": int(data["ammo"]), "cooldown": cooldown, "burst": burst}
	_prev_id = id
	_prev_ammo = items.ammo[0]
	_prev_burst = burst


func _update_utility(items: RaceItems) -> void:
	var id := items.active[0]
	if id.is_empty():
		utility = {"id": "", "name": "", "remaining": 0.0, "duration": 0.0, "expiring": false}
		return
	var remaining := items.remaining[0]
	utility = {"id": id, "name": ItemCatalog.label(id), "remaining": remaining,
		"duration": float(ItemCatalog.DATA[id]["duration"]), "expiring": remaining <= EXPIRY_WARNING}


func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_panel(font)
	_draw_damage(font)
	_draw_indicators()


## Weapon and utility readout inside the dashboard's combat instrument (drawn by DrivingHud's band).
func _draw_panel(font: Font) -> void:
	var l := DashInstruments.layout(size)
	var s: float = l["scale"]
	var panel := DashInstruments.body(l["combat"], s)
	var wide := panel.size.x
	var x := panel.position.x
	var y := panel.position.y + 14.0 * s
	var wid := String(weapon["id"])
	var accent := Color(String(ItemCatalog.DATA[wid]["color"])) if ItemCatalog.DATA.has(wid) else Color("a7adb7")
	var shown_name := String(weapon["name"]) if not String(weapon["name"]).is_empty() else "NO WEAPON"
	draw_string(font, Vector2(x, y), shown_name, HORIZONTAL_ALIGNMENT_LEFT, wide, maxi(10, roundi(17.0 * s)), accent)
	var state := String(weapon["state"])
	var state_color := {"READY": Color("7dff9b"), "FIRING": Color("ffd24d"), "COOLING": Color("ff9a4d"),
		"EXHAUSTED": Color("ff5a5a"), "EMPTY": Color("a7adb7"),
		"WAIT": Color("ff9a4d"), "DEPLOYING": Color("ffd24d"), "QUEUED": Color("ffd24d"), "NO LOCK": Color("ff9a4d")}[state] as Color
	var hint := ""
	if state == "READY":
		hint = " [E] " + ("ACTIVATE" if not ItemCatalog.is_ammo(wid) else ("3-ROUND BURST" if wid == "machine_guns" else "FIRE ONE"))
	elif state == "EMPTY":
		hint = " - COLLECT A GOLD BOX"
	draw_string(font, Vector2(x, y + 18.0 * s), state + hint, HORIZONTAL_ALIGNMENT_LEFT, wide, maxi(10, roundi(14.0 * s)), state_color)
	var max_ammo := int(weapon["max"])
	if max_ammo > 0:
		var count_w := 56.0 * s
		var bar := Rect2(x, y + 26.0 * s, wide - count_w, 11.0 * s)
		draw_rect(bar, Color(1, 1, 1, 0.12))
		var segments := max_ammo if max_ammo <= 6 else 10
		var filled := float(weapon["ammo"]) / float(max_ammo)
		for n in segments:
			var seg := Rect2(bar.position.x + bar.size.x * n / segments + 1.0, bar.position.y + 1.0,
				bar.size.x / segments - 2.0, bar.size.y - 2.0)
			var amount := clampf(filled * segments - n, 0.0, 1.0)
			if amount > 0.0:
				draw_rect(Rect2(seg.position, Vector2(seg.size.x * amount, seg.size.y)), accent)
		draw_string(font, Vector2(bar.end.x + 6.0 * s, bar.end.y), "%d/%d" % [weapon["ammo"], max_ammo], HORIZONTAL_ALIGNMENT_LEFT, count_w, maxi(10, roundi(13.0 * s)), Color.WHITE)
		if float(weapon["cooldown"]) > 0.0:
			draw_rect(Rect2(x, bar.end.y + 3.0 * s, wide * (1.0 - float(weapon["cooldown"])), 4.0 * s), state_color)
	elif not held_utility.is_empty():
		draw_string(font, Vector2(x, y + 34.0 * s), "HELD UTILITY", HORIZONTAL_ALIGNMENT_LEFT, wide, maxi(9, roundi(12.0 * s)), Color(1, 1, 1, 0.7))
	if String(utility["id"]).is_empty():
		return
	var uy := y + 66.0 * s
	var ucolor := Color(String(ItemCatalog.DATA[String(utility["id"])]["color"]))
	if bool(utility["expiring"]) and int(Time.get_ticks_msec() / 120) % 2 == 0:
		ucolor = Color("ff5a5a")
	draw_string(font, Vector2(x, uy), "%s  %.1fs" % [utility["name"], utility["remaining"]], HORIZONTAL_ALIGNMENT_LEFT, wide, maxi(10, roundi(14.0 * s)), ucolor)
	var fraction := clampf(float(utility["remaining"]) / maxf(float(utility["duration"]), 0.001), 0.0, 1.0)
	draw_rect(Rect2(x, uy + 5.0 * s, wide, 8.0 * s), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(x, uy + 5.0 * s, wide * fraction, 8.0 * s), ucolor)


## Bodywork label and bar live in the systems instrument.
func _draw_damage(font: Font) -> void:
	var l := DashInstruments.layout(size)
	var parts := DashInstruments.systems_layout(l["systems"], l["scale"])
	var label_rect: Rect2 = parts["damage_label"]
	var bar: Rect2 = parts["damage_bar"]
	draw_string(font, label_rect.position + Vector2(0.0, label_rect.size.y - 4.0), damage_label, HORIZONTAL_ALIGNMENT_LEFT, label_rect.size.x,
		DashInstruments.fit_font_size(font, damage_label, label_rect.size, 14), Color(1, 1, 1, 0.7))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var heat := Color("ffd24d").lerp(Color("ff4a3a"), damage_level)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * damage_level, bar.size.y)), heat)


## Triangle (tip, base corners) of a directional marker at `angle` (0 ahead, +PI/2 right).
static func ring_triangle(view: Vector2, angle: float) -> PackedVector2Array:
	var ring := DashInstruments.ring_geometry(view)
	var center: Vector2 = ring["center"]
	var radius: float = ring["radius"]
	var dir := Vector2(sin(angle), -cos(angle))
	var side := Vector2(-dir.y, dir.x)
	var base := center + dir * radius
	var half: float = ring["half_base"]
	return PackedVector2Array([center + dir * (radius + float(ring["reach"])), base + side * half, base - side * half])


func _draw_indicators() -> void:
	for entry: Dictionary in indicators:
		if not entry.has("angle"):
			continue
		var alpha := clampf(float(entry["life"]) / INDICATOR_LIFE, 0.0, 1.0)
		var blocked := bool(entry["blocked"])
		var color := Color("5fd7ff") if blocked else Color("ff3d2e")
		color.a = alpha
		var points := ring_triangle(size, float(entry["angle"]))
		if blocked:
			draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), color, 3.0)
		else:
			draw_colored_polygon(points, color)
