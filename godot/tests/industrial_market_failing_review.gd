## Test double: the real review script with a failing benchmark and a recorded (non-navigating) back request.
extends "res://scripts/industrial_market_review.gd"

var back_requests := 0


func _create_benchmark() -> IndustrialMarketBenchmark:
	return preload("res://tests/industrial_market_failing_benchmark.gd").new()


func _back() -> void:
	back_requests += 1
