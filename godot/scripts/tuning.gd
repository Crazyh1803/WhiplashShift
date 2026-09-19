## Every number that affects feel, in one inspector-editable Resource.
##
## Port of web/src/tuning.js. This is the point of the spike: open
## resources/default_tuning.tres in the inspector, run the game, and move values
## while it plays. Findings come back as numbers, not adjectives.
class_name TuningProfile
extends Resource

@export_group("Chassis")
@export var mass: float = 1400.0
@export var body_length: float = 4.6
@export var body_width: float = 2.0
@export var body_height: float = 1.2
## Wheel pair offset from centre of mass along body Z (End A sits at -Z).
@export var half_base: float = 1.6
## Wheel offset from the centreline along body X.
@export var half_track: float = 0.9
@export var aero_drag: float = 0.82
@export var yaw_damp: float = 0.9
## Resists roll and pitch. Has no web equivalent — the 2D model had neither axis.
@export var roll_damp: float = 2.6
## Extra restoring torque keeping the chassis upright. The 2D model got this free.
@export var anti_roll: float = 22000.0

@export_group("End A — Asphalt Racer")
@export var a_max_drive: float = 9800.0
@export var a_top_speed: float = 58.0
@export var a_tire_grip: float = 1.38
@export var a_max_steer: float = 0.50
@export var a_steer_rate: float = 3.6
@export var a_steer_falloff: float = 0.62
@export var a_downforce: float = 0.80
@export var a_brake: float = 15000.0
@export var a_wheel_radius: float = 0.34
@export var a_susp_rest: float = 0.30
@export var a_susp_stiffness: float = 57000.0
@export var a_susp_damp: float = 4000.0

@export_group("End B — Mud Brawler")
@export var b_max_drive: float = 17500.0
@export var b_top_speed: float = 34.0
@export var b_tire_grip: float = 1.02
@export var b_max_steer: float = 0.64
@export var b_steer_rate: float = 2.9
@export var b_steer_falloff: float = 0.42
@export var b_downforce: float = 0.0
@export var b_brake: float = 11500.0
@export var b_wheel_radius: float = 0.52
@export var b_susp_rest: float = 0.50
@export var b_susp_stiffness: float = 22900.0
@export var b_susp_damp: float = 2800.0

@export_group("Swap")
## Transmission ramp: drive torque climbs 0 -> 1 over this many seconds.
@export var swap_engage: float = 0.26
@export var swap_cooldown: float = 0.60
## Entry speed (m/s) above which a swap counts as a tactical whiplash.
@export var whiplash_min_speed: float = 22.0
@export var whiplash_window: float = 1.8

@export_group("Grip")
## Lateral saturation sharpness.
@export var slip_k: float = 1.15
## Lateral grip on the locked pair under handbrake.
@export var handbrake_grip: float = 0.44
## Longitudinal lock on that pair.
@export var handbrake_lock: float = 0.85

func drive(end: String) -> float:
	return a_max_drive if end == "A" else b_max_drive

func top_speed(end: String) -> float:
	return a_top_speed if end == "A" else b_top_speed

func tire_grip(end: String) -> float:
	return a_tire_grip if end == "A" else b_tire_grip

func max_steer(end: String) -> float:
	return a_max_steer if end == "A" else b_max_steer

func steer_rate(end: String) -> float:
	return a_steer_rate if end == "A" else b_steer_rate

func steer_falloff(end: String) -> float:
	return a_steer_falloff if end == "A" else b_steer_falloff

func downforce(end: String) -> float:
	return a_downforce if end == "A" else b_downforce

func brake_force(end: String) -> float:
	return a_brake if end == "A" else b_brake

func wheel_radius(end: String) -> float:
	return a_wheel_radius if end == "A" else b_wheel_radius

func susp_rest(end: String) -> float:
	return a_susp_rest if end == "A" else b_susp_rest

func susp_stiffness(end: String) -> float:
	return a_susp_stiffness if end == "A" else b_susp_stiffness

func susp_damp(end: String) -> float:
	return a_susp_damp if end == "A" else b_susp_damp
