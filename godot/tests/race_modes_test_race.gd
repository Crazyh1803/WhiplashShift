extends "res://scripts/proving_ground.gd"

var navigation_requests := 0
var navigation_complete: bool = false

func _navigate_next_round(_complete: bool) -> Error:
	navigation_requests += 1
	navigation_complete = _complete
	return OK
