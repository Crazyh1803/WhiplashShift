## Surface table and the per-end performance modifiers.
##
## Direct port of web/src/surfaces.js. Kept as code rather than a Resource: this
## is a lookup table that changes rarely, and a 2x9x3 modifier matrix is miserable
## to edit in an inspector. The knobs you actually reach for live in TuningProfile.
class_name Surfaces
extends RefCounted

enum Id { TARMAC, RUMBLE, GRAVEL, MUD, BOULDER, ICE, WATER, OIL, OFF }

const KEYS: Array[String] = [
	"tarmac", "rumble", "gravel", "mud", "boulder", "ice", "water", "oil", "off",
]

const NAMES: Array[String] = [
	"TARMAC", "RUMBLE", "GRAVEL", "MUD BOG", "BOULDERS", "ICE", "WATER", "OIL", "OFF TRACK",
]

## Multiplies the tyre friction coefficient.
const GRIP: Array[float] = [1.00, 0.86, 0.62, 0.40, 0.55, 0.20, 0.44, 0.13, 0.50]

## Rolling / bogging resistance coefficient (x normal load, opposing wheel travel).
const ROLL: Array[float] = [0.016, 0.060, 0.115, 0.430, 0.190, 0.012, 0.520, 0.010, 0.330]

## Punishment per second at speed when the wrong end is driving.
const DMG: Array[float] = [0.0, 0.0, 1.0, 4.0, 5.0, 0.0, 6.0, 0.0, 2.0]

const COLORS: Array[Color] = [
	Color("484e5b"), Color("6d5536"), Color("6f6855"), Color("55402a"), Color("5f5f6b"),
	Color("5d8194"), Color("2f5a69"), Color("191921"), Color("2c3726"),
]

## Which end the surface wants. Drives gates, copilot callouts and damage.
const PREFERRED: Array[String] = ["A", "A", "B", "B", "B", "A", "B", "A", "B"]

# End A is built for tarmac and helpless in the soft stuff; End B the reverse.
# The GDD's headline numbers are the anchors: A +30% top speed on tarmac and
# -70% acceleration in mud, B +40% traction in mud and -40% top speed on tarmac.
# Index order matches Id. Each entry is [top, accel, grip].
const MOD_A: Array = [
	[1.30, 1.00, 1.00],  # tarmac
	[1.05, 0.85, 0.90],  # rumble
	[0.74, 0.52, 0.68],  # gravel
	[0.52, 0.30, 0.52],  # mud
	[0.48, 0.34, 0.58],  # boulder
	[0.92, 0.48, 0.86],  # ice
	[0.44, 0.26, 0.50],  # water
	[1.00, 0.40, 0.70],  # oil
	[0.58, 0.40, 0.62],  # off
]

const MOD_B: Array = [
	[0.60, 0.88, 0.84],  # tarmac
	[0.80, 1.00, 1.05],  # rumble
	[0.96, 1.14, 1.28],  # gravel
	[1.00, 1.20, 1.40],  # mud
	[0.92, 1.18, 1.32],  # boulder
	[0.78, 0.86, 1.10],  # ice
	[0.90, 1.05, 1.25],  # water
	[0.85, 0.55, 0.80],  # oil
	[0.94, 1.10, 1.22],  # off
]

static func mod_top(end: String, id: int) -> float:
	return (MOD_A[id][0] if end == "A" else MOD_B[id][0]) as float

static func mod_accel(end: String, id: int) -> float:
	return (MOD_A[id][1] if end == "A" else MOD_B[id][1]) as float

static func mod_grip(end: String, id: int) -> float:
	return (MOD_A[id][2] if end == "A" else MOD_B[id][2]) as float

static func id_from_key(key: String) -> int:
	var i: int = KEYS.find(key)
	return i if i >= 0 else Id.OFF
