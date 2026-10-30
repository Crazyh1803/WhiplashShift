class_name CityRealismLighting
extends Node3D

var anchors: Array[Dictionary] = []
var pool: Array[Light3D] = []
var elapsed := 0.0
var selected: Array[int] = []
const STREET_SLOTS := 9


func _ready() -> void:
	for index in STREET_SLOTS + 2:
		var light: Light3D = SpotLight3D.new() if index >= STREET_SLOTS else OmniLight3D.new()
		light.name = "ShopSpot%d" % index if index >= STREET_SLOTS else "StreetLight%d" % index
		light.shadow_enabled = index >= STREET_SLOTS
		light.shadow_bias = 0.015
		light.shadow_normal_bias = 0.04
		light.distance_fade_enabled = true
		light.distance_fade_begin = 95.0
		light.distance_fade_length = 35.0
		light.visible = false
		add_child(light)
		pool.append(light)
	_refresh(Vector3.ZERO)


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.2:
		return
	elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_refresh(camera.global_position)


func _refresh(at: Vector3) -> void:
	var order: Array[int] = []
	for index in anchors.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := at.distance_squared_to(anchors[a]["position"])
		var db := at.distance_squared_to(anchors[b]["position"])
		return a < b if is_equal_approx(da, db) else da < db)
	selected.clear()
	var street := 0
	var shop := STREET_SLOTS
	for index in order:
		var anchor: Dictionary = anchors[index]
		if at.distance_to(anchor["position"]) > 135.0:
			continue
		var shadowed := bool(anchor.get("shadow", false))
		var slot := shop if shadowed else street
		if slot >= (STREET_SLOTS + 2 if shadowed else STREET_SLOTS):
			continue
		shop += 1 if shadowed else 0
		street += 0 if shadowed else 1
		var light := pool[slot]
		light.position = anchor["position"]
		light.light_color = anchor.get("color", Color("ffce9a"))
		light.light_energy = float(anchor.get("energy", 5.0))
		if light is SpotLight3D:
			light.spot_range = float(anchor.get("range", 22.0))
			light.spot_angle = 62.0
			var direction: Vector3 = anchor.get("direction", Vector3(0, -1, 0.05)).normalized()
			light.look_at(light.global_position + direction, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP)
		else:
			light.omni_range = float(anchor.get("range", 24.0))
		light.visible = true
		selected.append(index)
	for index in pool.size():
		if (index < STREET_SLOTS and index >= street) or (index >= STREET_SLOTS and index >= shop):
			pool[index].visible = false
	set_meta("selected_anchors", selected.duplicate())
