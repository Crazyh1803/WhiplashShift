extends RefCounted


static func spec() -> Dictionary:
	var result := VehicleCatalog.get_vehicle("blackjack")
	result["visual"] = preload("res://scripts/blackjack_blueprint_spec.gd").visual(result["visual"])
	result["customization"] = VehicleCatalog.default_customization("blackjack")
	result["customization"]["parts"]["hood_engine"] = "stock"
	return result
