class_name VehicleCatalog
extends RefCounted

const VEHICLES: Array[Dictionary] = [
	{
		"id": "blackjack", "name": "BLACKJACK X-17", "class_name": "INTERCEPTOR", "origin": "REDLINE DIVISION",
		"description": "Balanced twin-vector hardware. Fast enough to hunt, armored enough to finish.",
		"image": "res://assets/vehicles/spy-hunter.jpg", "color": "ff4d2e",
		"stats": {"speed": 78, "accel": 76, "handling": 82, "armor": 72},
		"physics": {"top_speed": 1.0, "drive": 1.0, "grip": 1.0, "mass": 1.0, "brake": 1.0},
	},
	{
		"id": "boilerfang", "name": "BOILERFANG 88", "class_name": "DREADNOUGHT", "origin": "FOUNDRY NINE",
		"description": "Brutal traction and plate steel. It arrives late, then refuses to leave.",
		"image": "res://assets/vehicles/steam-punk.jpg", "color": "ffb238",
		"stats": {"speed": 58, "accel": 84, "handling": 60, "armor": 96},
		"physics": {"top_speed": 0.88, "drive": 1.12, "grip": 1.04, "mass": 1.14, "brake": 0.94},
	},
	{
		"id": "helix", "name": "HELIX WRAITH", "class_name": "BIO-RACER", "origin": "NULL LABS",
		"description": "Living aero wraps a surgical chassis. Unstable-looking. Disturbingly precise.",
		"image": "res://assets/vehicles/r-type.jpg", "color": "ef3c67",
		"stats": {"speed": 94, "accel": 88, "handling": 72, "armor": 48},
		"physics": {"top_speed": 1.10, "drive": 1.08, "grip": 0.94, "mass": 0.88, "brake": 0.96},
	},
	{
		"id": "ramjet", "name": "RAMJET K-6", "class_name": "BRAWLER", "origin": "MOTOR CULT",
		"description": "A street-fight drivetrain in a split-body shell. Point it through the problem.",
		"image": "res://assets/vehicles/dodge.jpg", "color": "b9ef45",
		"stats": {"speed": 72, "accel": 91, "handling": 65, "armor": 82},
		"physics": {"top_speed": 0.96, "drive": 1.11, "grip": 0.96, "mass": 1.08, "brake": 0.92},
	},
	{
		"id": "knifeedge", "name": "KNIFEEDGE XR", "class_name": "RAZORBUG", "origin": "APEX WORKS",
		"description": "Half sand rail, half supercar. Changes direction before the driver finishes thinking.",
		"image": "res://assets/vehicles/hot-wheels.jpg", "color": "27d7ff",
		"stats": {"speed": 86, "accel": 80, "handling": 96, "armor": 42},
		"physics": {"top_speed": 1.04, "drive": 1.02, "grip": 1.10, "mass": 0.90, "brake": 1.08},
	},
	{
		"id": "deadbolt", "name": "DEADBOLT RS", "class_name": "ROAD WARDEN", "origin": "BLACK COUNTY",
		"description": "Old-world iron, new-world violence. Calm on entry and merciless under braking.",
		"image": "res://assets/vehicles/80s-ford.jpg", "color": "8cb6ff",
		"stats": {"speed": 74, "accel": 68, "handling": 86, "armor": 78},
		"physics": {"top_speed": 0.98, "drive": 0.96, "grip": 1.07, "mass": 1.05, "brake": 1.08},
	},
	{
		"id": "nightshift", "name": "NIGHTSHIFT 84", "class_name": "OUTRUNNER", "origin": "GHOST MOTOR CO.",
		"description": "High-speed contraband geometry. Light, eager, and allergic to straight lines.",
		"image": "res://assets/vehicles/80s.jpg", "color": "c378ff",
		"stats": {"speed": 90, "accel": 82, "handling": 88, "armor": 52},
		"physics": {"top_speed": 1.08, "drive": 1.04, "grip": 1.05, "mass": 0.92, "brake": 1.02},
	},
]

# Imported models are visual-only. The bespoke RigidBody3D and suspension remain
# authoritative, so swapping art cannot silently change the tuned force model.
const VISUALS: Dictionary = {
	"blackjack": {
		"scene": "res://assets/vehicles/models/blackjack/blackjack_blueprint.glb",
		"wheel_scene_a": "res://assets/vehicles/models/blackjack/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/blackjack/wheel_b.glb",
		"scale": Vector3.ONE * 2.345,
		"offset": Vector3(0.0, 0.35, 0.0),
		"rotation_degrees": Vector3(0.0, 90.0, 0.0),
		"embedded_wheels": false,
		"semantic_materials": true,
		"visual_middle_bogie": true,
		"middle_bogie_z": 0.66,
		"wheel_styles": {
			"stock": {
				"embedded": false,
				"wheel_scene_a": "res://assets/vehicles/models/blackjack/wheel_aero.glb",
				"wheel_scene_b": "res://assets/vehicles/models/blackjack/wheel_rugged.glb",
				"rim_scale_a": Vector3.ONE * 0.29,
				"rim_scale_b": Vector3.ONE * 0.34,
				"rim_offset_a": Vector3(0.11, 0.0, 0.0),
				"rim_offset_b": Vector3(0.15, 0.0, 0.0),
				"rim_rotation_degrees": Vector3(0.0, 90.0, 0.0),
				"tire_inner_ratio": 0.64,
				"tire_color": "111418",
				"tread_scale_a": 0.90,
				"tread_scale_b": 1.35,
			},
			"interceptor": {
				"embedded": false,
				"wheel_scene_a": "res://assets/vehicles/models/blackjack/wheel_aero.glb",
				"wheel_scene_b": "res://assets/vehicles/models/blackjack/wheel_rugged.glb",
				"rim_scale_a": Vector3.ONE * 0.29,
				"rim_scale_b": Vector3.ONE * 0.34,
				"rim_offset_a": Vector3(0.11, 0.0, 0.0),
				"rim_offset_b": Vector3(0.15, 0.0, 0.0),
				"rim_rotation_degrees": Vector3(0.0, 90.0, 0.0),
				"tire_inner_ratio": 0.64,
				"tire_color": "111418",
				"tread_scale_a": 0.90,
				"tread_scale_b": 1.35,
			},
		},
		"part_scenes": {
			"hood_engine": {
				"supercharger": "res://assets/vehicles/models/blackjack/supercharger.glb",
			},
		},
	},
	"boilerfang": {
		"scene": "res://assets/vehicles/models/boilerfang/boilerfang.glb",
		"wheel_scene_a": "res://assets/vehicles/models/boilerfang/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/boilerfang/wheel_b.glb",
	},
	"helix": {
		"scene": "res://assets/vehicles/models/helix/helix.glb",
		"wheel_scene_a": "res://assets/vehicles/models/helix/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/helix/wheel_b.glb",
	},
	"ramjet": {
		"scene": "res://assets/vehicles/models/ramjet/ramjet.glb",
		"wheel_scene_a": "res://assets/vehicles/models/ramjet/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/ramjet/wheel_b.glb",
	},
	"knifeedge": {
		"scene": "res://assets/vehicles/models/knifeedge/knifeedge.glb",
		"wheel_scene_a": "res://assets/vehicles/models/knifeedge/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/knifeedge/wheel_b.glb",
	},
	"deadbolt": {
		"scene": "res://assets/vehicles/models/deadbolt/deadbolt.glb",
		"wheel_scene_a": "res://assets/vehicles/models/deadbolt/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/deadbolt/wheel_b.glb",
	},
	"nightshift": {
		"scene": "res://assets/vehicles/models/nightshift/nightshift.glb",
		"wheel_scene_a": "res://assets/vehicles/models/nightshift/wheel_a.glb",
		"wheel_scene_b": "res://assets/vehicles/models/nightshift/wheel_b.glb",
	},
}

const VISUAL_DEFAULTS: Dictionary = {
	"scale": Vector3.ONE,
	"offset": Vector3.ZERO,
	"rotation_degrees": Vector3.ZERO,
	"collision_boxes": [
		{"size": Vector3(1.56, 0.50, 2.00), "position": Vector3(0.0, 0.25, 0.0)},
		{"size": Vector3(1.44, 0.34, 1.30), "position": Vector3(0.0, 0.14, -1.65)},
		{"size": Vector3(1.90, 0.78, 1.30), "position": Vector3(0.0, 0.39, 1.65)},
	],
	"wheel_mounts": {
		"A_L": Vector3(-0.90, 0.0, -1.60),
		"A_R": Vector3(0.90, 0.0, -1.60),
		"B_L": Vector3(-0.90, 0.0, 1.60),
		"B_R": Vector3(0.90, 0.0, 1.60),
	},
	"part_sockets": {
		"front_a": {"position": Vector3(0.0, 0.10, -2.34), "rotation_degrees": Vector3.ZERO},
		"front_b": {"position": Vector3(0.0, 0.34, 2.34), "rotation_degrees": Vector3(0.0, 180.0, 0.0)},
		"roof": {"position": Vector3(0.0, 1.08, 0.25), "rotation_degrees": Vector3.ZERO},
		"left": {"position": Vector3(-1.02, 0.28, 0.0), "rotation_degrees": Vector3(0.0, 0.0, 90.0)},
		"right": {"position": Vector3(1.02, 0.28, 0.0), "rotation_degrees": Vector3(0.0, 0.0, -90.0)},
		"hood_engine": {
			"position": Vector3(0.0, 0.55, -1.45),
			"rotation_degrees": Vector3(0.0, 90.0, 0.0),
			"scale": Vector3.ONE * 0.42,
		},
	},
	"part_scenes": {},
	"wheel_styles": {},
}


static func get_vehicle(vehicle_id: String) -> Dictionary:
	for vehicle: Dictionary in VEHICLES:
		if String(vehicle["id"]) == vehicle_id:
			return _with_visual(vehicle)
	return _with_visual(VEHICLES[0])


static func default_customization(vehicle_id: String) -> Dictionary:
	var primary := "ff4d2e"
	for vehicle: Dictionary in VEHICLES:
		if String(vehicle["id"]) == vehicle_id:
			primary = String(vehicle["color"])
			break
	var accent := Color.from_string("#" + primary, Color("ff4d2e")).lightened(0.20).to_html(false)
	if vehicle_id == "blackjack":
		accent = "c5a468" # Factory gold belongs to the twelve metallic finishes.
	return {
		"primary_color": primary,
		"secondary_color": "101820",
		"accent_color": accent,
		"wheel_style": "stock",
		"parts": {
			"front_a": "stock",
			"front_b": "stock",
			"roof": "stock",
			"left": "stock",
			"right": "stock",
			"hood_engine": "supercharger" if vehicle_id == "blackjack" else "stock",
		},
	}


static func _with_visual(vehicle: Dictionary) -> Dictionary:
	var result := vehicle.duplicate(true)
	var visual := VISUAL_DEFAULTS.duplicate(true)
	visual.merge(VISUALS.get(String(vehicle["id"]), {}), true)
	if String(vehicle["id"])=="blackjack":
		visual=load("res://scripts/blackjack_blueprint_spec.gd").visual(visual)
	result["visual"] = visual
	return result


static func random_cpu_roster(count: int, exclude_id: String = "") -> Array[String]:
	var candidates: Array[String] = []
	for vehicle: Dictionary in VEHICLES:
		var vehicle_id := String(vehicle["id"])
		if vehicle_id != exclude_id:
			candidates.append(vehicle_id)
	candidates.shuffle()
	var result: Array[String] = []
	for i: int in mini(count, candidates.size()):
		result.append(candidates[i])
	while result.size() < count and not candidates.is_empty():
		result.append(candidates[result.size() % candidates.size()])
	return result
