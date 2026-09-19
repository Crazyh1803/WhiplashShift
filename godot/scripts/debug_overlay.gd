## Per-wheel truth, on F1.
##
## This exists so "it feels floaty" can come back as "wheel loads drop 40% over
## crests". The force budget is logged by vehicle.gd every step and reconciles
## against measured acceleration — if `net/mass` and `actual` ever disagree here,
## something is applying a force the model does not know about.
class_name DebugOverlay
extends CanvasLayer

@export var target: Vehicle
var _text: Label


func _ready() -> void:
	_text = Label.new()
	_text.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_text.offset_left = -430.0
	_text.offset_top = 14.0
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_text.add_theme_constant_override("shadow_offset_x", 1)
	_text.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_text)
	visible = false


func toggle() -> void:
	visible = not visible


func _process(_delta: float) -> void:
	if not visible or target == null:
		return
	var lines: Array[String] = ["wheel  surface    load   slip  spin  comp   contact"]
	for w: Wheel in target.wheels:
		lines.append("%-6s %-9s %6.0f  %.2f  %.2f  %.3f  %s" % [
			w.name.replace("Wheel_", ""), Surfaces.KEYS[w.surface_id],
			w.normal_load, w.slip, w.spin, w.compression, "yes" if w.contact else "AIR"])
	var d: Dictionary = target.dbg
	if not d.is_empty():
		var net: Vector3 = d.get("net", Vector3.ZERO)
		var act: Vector3 = d.get("actual_a", Vector3.ZERO)
		lines.append("")
		lines.append("drive/wheel %7.0f N   taper %.2f" % [d.get("drive_per_wheel", 0.0), d.get("taper", 0.0)])
		lines.append("tyre  %s" % _v(d.get("tyre", Vector3.ZERO)))
		lines.append("susp  %s" % _v(d.get("susp", Vector3.ZERO)))
		lines.append("aero  %s" % _v(d.get("aero", Vector3.ZERO)))
		lines.append("predicted a %s" % _v(net / target.mass))
		lines.append("actual    a %s" % _v(act))
	_text.text = "\n".join(lines)


func _v(v: Vector3) -> String:
	return "%8.1f %8.1f %8.1f" % [v.x, v.y, v.z]
