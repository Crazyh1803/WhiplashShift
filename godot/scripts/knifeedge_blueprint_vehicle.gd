## Knifeedge paint uses the shared authored-hub visual adapter.
extends "res://scripts/deadbolt_blueprint_vehicle.gd"


func _authored_paint_colors() -> Dictionary:
	return {
		"Knifeedge_Paint": vehicle_color,
		"Knifeedge_Secondary": vehicle_secondary_color,
		"Knifeedge_Stripe": vehicle_accent_color,
	}
