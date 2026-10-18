## Matched before/after captures of Blackjack's actual frozen garage preview.
extends Node


func _ready() -> void:
	var phase := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var output := ProjectSettings.globalize_path("res://../.ai/captures/blackjack_junction")
	DirAccess.make_dir_recursive_absolute(output)
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	# Let the popup and its SubViewport complete their first layout before opening.
	for frame in 3:
		await get_tree().process_frame
	garage._open_customization()
	var custom := VehicleCatalog.default_customization("blackjack")
	custom["primary_color"] = "2558a4"
	custom["secondary_color"] = "101820"
	custom["accent_color"] = "c5a468"
	garage._refresh_customization_preview("blackjack", custom)
	garage._preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = garage._preview_camera
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var views := [
		["side", 3.7, Vector3(7, 0.8, 0), Vector3(0, 0.8, 0)],
		["three_quarter", 4.2, Vector3(5, 3.1, -5.2), Vector3(0, 0.9, 0)],
		["junction", 1.9, Vector3(5, 2.2, 1.2), Vector3(0, 0.85, 0.45)],
		["top", 4.1, Vector3(0.01, 7, 0), Vector3.ZERO],
	]
	for view: Array in views:
		camera.size = view[1]
		camera.look_at_from_position(view[2], view[3])
		for frame in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = garage._preview_viewport.get_texture().get_image()
		var path := output.path_join("%s_%s.png" % [phase, view[0]])
		var error := picture.save_png(path)
		var visible := 0
		for x in range(0, picture.get_width(), 8):
			for y in range(0, picture.get_height(), 8):
				if picture.get_pixel(x, y).get_luminance() > 0.15:
					visible += 1
		if visible < 100:
			push_error("Blackjack junction capture contains no visible vehicle")
			get_tree().quit(1)
			return
		print("BLACKJACK_JUNCTION_CAPTURE ", path, " error=", error)
		if error != OK:
			get_tree().quit(1)
			return
	get_tree().quit()
