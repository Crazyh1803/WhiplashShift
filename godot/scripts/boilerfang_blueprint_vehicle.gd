## Boilerfang paint uses the shared authored-hub visual adapter.
extends "res://scripts/deadbolt_blueprint_vehicle.gd"


func _authored_paint_colors() -> Dictionary:
	return {
		"Boilerfang_Paint": vehicle_color,
		"Boilerfang_Secondary": vehicle_secondary_color,
		"Boilerfang_Stripe": vehicle_accent_color,
	}
