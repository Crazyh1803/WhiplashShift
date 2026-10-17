## Ramjet paint uses the shared authored-hub visual adapter.
extends "res://scripts/deadbolt_blueprint_vehicle.gd"


func _authored_paint_colors() -> Dictionary:
	return {
		"Ramjet_Paint": vehicle_color,
		"Ramjet_Secondary": vehicle_secondary_color,
		"Ramjet_Stripe": vehicle_accent_color,
	}
