extends RefCounted


static func spec() -> Dictionary:
	var result := VehicleCatalog.get_vehicle("blackjack")
	result["visual"] = result["visual"].duplicate(true)
	result["visual"]["scene"] = "res://assets/vehicles/models/blackjack/blackjack_refined.glb"
	for style: Dictionary in result["visual"]["wheel_styles"].values():
		style["wheel_scene_a"] = "res://assets/vehicles/models/blackjack/blackjack_refined_rim_aero.glb"
		style["wheel_scene_b"] = "res://assets/vehicles/models/blackjack/blackjack_refined_rim_rugged.glb"
		style["rim_scale_a"] = Vector3.ONE * .2176
		style["rim_scale_b"] = Vector3.ONE * .3328
		style["rim_offset_a"] = Vector3(.03, 0, 0)
		style["rim_offset_b"] = Vector3(.05, 0, 0)
		style["rim_rotation_degrees"] = Vector3.ZERO
	return result
