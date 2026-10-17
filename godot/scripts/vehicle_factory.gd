extends RefCounted


static func create(spec: Dictionary) -> Vehicle:
	var vehicle: Vehicle
	if spec.get("visual",{}).get("rig","")=="blackjack_blueprint":
		vehicle=load("res://scripts/blackjack_blueprint_vehicle.gd").new()
	elif spec.get("visual", {}).get("rig", "") == "deadbolt_blueprint":
		vehicle = load("res://scripts/deadbolt_blueprint_vehicle.gd").new()
	elif spec.get("visual", {}).get("rig", "") == "nightshift_blueprint":
		vehicle = load("res://scripts/nightshift_blueprint_vehicle.gd").new()
	else:
		vehicle=Vehicle.new()
	vehicle.apply_vehicle_spec(spec)
	return vehicle
