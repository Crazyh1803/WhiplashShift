## Helix keeps its tracked/hover artwork over the unchanged wheel simulation.
extends "res://scripts/deadbolt_blueprint_vehicle.gd"


func _authored_paint_colors() -> Dictionary:
	return {
		"Helix_Paint": vehicle_color,
		"Helix_Secondary": vehicle_secondary_color,
		"Helix_Stripe": vehicle_accent_color,
	}


func _install_authored_wheels() -> void:
	# Embedded mode hides physics wheels/shafts; Prop_Track_* stays body artwork.
	pass
