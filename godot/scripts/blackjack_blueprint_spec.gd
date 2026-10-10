extends RefCounted


static func visual(original: Dictionary) -> Dictionary:
	var result := original.duplicate(true)
	result["rig"]="blackjack_blueprint"
	result["scene"]="res://assets/vehicles/models/blackjack/blackjack_blueprint.glb"
	var dimensions := preload("res://assets/vehicles/models/blackjack/blackjack_blueprint_dimensions.tres")
	result["display_radius"]=dimensions.display_radius
	result["display_track"]=dimensions.display_track
	result["arch_centers"]=dimensions.arch_centers
	result["preview_pitch"]=dimensions.preview_pitch
	result["preview_height"]=dimensions.preview_height
	# Middle pair is visual-only. Its shared rugged assembly offset must not
	# displace it a second time from the authored arch center.
	var rear: Vector3 = dimensions.arch_centers["B_R"]
	var middle: Vector3 = dimensions.arch_centers["M_R"]
	result["middle_bogie_z"]=middle.z-(rear.z-1.6)
	result["part_scenes"]["hood_engine"]["supercharger"]="res://assets/vehicles/models/blackjack/blackjack_blueprint_supercharger.glb"
	for name: String in dimensions.part_socket_positions:
		result["part_sockets"][name]["position"]=dimensions.part_socket_positions[name]
	for style: Dictionary in result["wheel_styles"].values():
		style["wheel_scene_a"]="res://assets/vehicles/models/blackjack/blackjack_blueprint_rim_aero.glb"
		style["wheel_scene_b"]="res://assets/vehicles/models/blackjack/blackjack_blueprint_rim_rugged.glb"
		style["rim_rotation_degrees"]=Vector3.ZERO
		style["rim_scale_a"]=Vector3.ONE*.34*.78
		style["rim_scale_b"]=Vector3.ONE*.52*.69
		style["rim_offset_a"]=Vector3(.018,0,0)
		style["rim_offset_b"]=Vector3(.025,0,0)
	return result
