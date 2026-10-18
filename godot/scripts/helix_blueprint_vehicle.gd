## Helix paint uses the shared authored-hub visual adapter.
extends "res://scripts/deadbolt_blueprint_vehicle.gd"


func _authored_paint_colors() -> Dictionary:
	return {
		"Helix_Paint": vehicle_color,
		"Helix_Secondary": vehicle_secondary_color,
		"Helix_Stripe": vehicle_accent_color,
	}
