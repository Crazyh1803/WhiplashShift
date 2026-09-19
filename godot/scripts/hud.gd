## Minimal readout: everything you need to judge the swap, nothing you don't.
class_name Hud
extends CanvasLayer

@export var target: Vehicle
var _main: Label
var _banner: Label
var _hint: Label


func _ready() -> void:
	_main = _label(16, Vector2(18, 14))
	_main.add_theme_font_size_override("font_size", 17)
	_banner = _label(28, Vector2(0, 0))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 90.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 28)
	_hint = _label(12, Vector2(18, 0))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_top = -34.0
	_hint.offset_left = 18.0
	_hint.text = "W/S throttle-brake  A/D steer  SPACE swap  SHIFT handbrake  R reset  C camera  F1 debug"
	_hint.modulate = Color(1, 1, 1, 0.45)


func _label(size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if target == null:
		return
	var a_surf: int = target.wheels[0].surface_id
	var b_surf: int = target.wheels[2].surface_id
	var swap_state: String = "READY" if target.can_swap() else "LOCK %.2fs" % target.cooldown
	if target.power_cut > 0.0:
		swap_state = "POWER CUT"
	_main.text = "\n".join([
		"%3d KM/H   %s" % [roundi(target.speed * 3.6), "REVERSE" if target.reversing else ""],
		"END %s DRIVING   %s" % [target.active_end, Surfaces.NAMES[target.surface_under]],
		"  A pair on %-9s  B pair on %s" % [Surfaces.NAMES[a_surf], Surfaces.NAMES[b_surf]],
		"transmission %3d%%   swap %s" % [roundi(target.engage * 100.0), swap_state],
		"WRONG END" if target.wrong_end and target.speed > 11.0 else "",
	])
	_main.modulate = Color("4fd2ff") if target.active_end == "A" else Color("ffa63d")

	var wl: Dictionary = target.last_whiplash
	if wl.is_empty() or float(wl.get("age", 99.0)) > 2.2:
		_banner.text = ""
	else:
		_banner.text = "%s   %d%% MOMENTUM RETAINED" % [wl["kind"], roundi(float(wl["retained"]) * 100.0)]
