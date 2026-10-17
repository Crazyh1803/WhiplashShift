## Nightshift paint uses the shared authored-hub visual adapter.
extends "res://scripts/deadbolt_blueprint_vehicle.gd"


func _authored_paint_colors() -> Dictionary:
	return {
		"Nightshift_Paint": vehicle_color,
		"Nightshift_Secondary": vehicle_secondary_color,
		"Nightshift_Stripe": vehicle_accent_color,
	}
