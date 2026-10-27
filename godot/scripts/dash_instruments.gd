## Code-native dashboard parts shared by the HUD scripts: the instrument band layout,
## true polygon seven-segment digits, the restrained red scanner sweep and text fitting.
## Everything here is pure (no nodes), so tests assert on the geometry directly.
class_name DashInstruments
extends RefCounted

const BASE_VIEW := Vector2(1600.0, 900.0)
const RED := Color("ff2a1c")
const RED_DIM := Color(0.28, 0.035, 0.03, 0.9)
const AMBER := Color("ffb02e")
const AMBER_DIM := Color(1.0, 0.69, 0.18, 0.4)
const BAND_FILL := Color(0.012, 0.014, 0.02, 0.94)
const WELL_FILL := Color(0.0, 0.0, 0.0, 0.55)
## Instrument widths at 1600x900: velocity, systems, route, combat; the map takes the rest.
const WIDTHS: Array[float] = [260.0, 220.0, 430.0, 284.0]
const NAMES: Array[String] = ["velocity", "systems", "route", "combat"]
const SEG_A := 1
const SEG_B := 2
const SEG_C := 4
const SEG_D := 8
const SEG_E := 16
const SEG_F := 32
const SEG_G := 64
const DIGIT_MASKS: Array[int] = [
	SEG_A | SEG_B | SEG_C | SEG_D | SEG_E | SEG_F,
	SEG_B | SEG_C,
	SEG_A | SEG_B | SEG_D | SEG_E | SEG_G,
	SEG_A | SEG_B | SEG_C | SEG_D | SEG_G,
	SEG_B | SEG_C | SEG_F | SEG_G,
	SEG_A | SEG_C | SEG_D | SEG_F | SEG_G,
	SEG_A | SEG_C | SEG_D | SEG_E | SEG_F | SEG_G,
	SEG_A | SEG_B | SEG_C,
	SEG_A | SEG_B | SEG_C | SEG_D | SEG_E | SEG_F | SEG_G,
	SEG_A | SEG_B | SEG_C | SEG_D | SEG_F | SEG_G,
]
const SCANNER_CELLS := 10


static func view_scale(view: Vector2) -> float:
	return maxf(0.25, minf(view.x / BASE_VIEW.x, view.y / BASE_VIEW.y))


## Instrument rectangles for a viewport. Keys: scale, band, scanner (the red strip just
## above the band), velocity, systems, route, combat, map, hint_top (first y below the band).
static func layout(view: Vector2) -> Dictionary:
	var s := view_scale(view)
	var band := Rect2(18.0 * s, view.y - 250.0 * s, view.x - 36.0 * s, 210.0 * s)
	var pad := 8.0 * s
	var gap := 6.0 * s
	var result := {"scale": s, "band": band, "hint_top": band.end.y + 4.0 * s,
		"scanner": Rect2(band.position.x, band.position.y - 14.0 * s, band.size.x, 6.0 * s)}
	var x := band.position.x + pad
	var y := band.position.y + pad
	var h := band.size.y - pad * 2.0
	for i in WIDTHS.size():
		result[NAMES[i]] = Rect2(x, y, WIDTHS[i] * s, h)
		x += WIDTHS[i] * s + gap
	result["map"] = Rect2(x, y, maxf(band.end.x - pad - x, 40.0 * s), h)
	return result


## Interior of an instrument below its title strip.
static func body(rect: Rect2, s: float) -> Rect2:
	var top := 22.0 * s
	return Rect2(rect.position + Vector2(8.0 * s, top), rect.size - Vector2(16.0 * s, top + 6.0 * s))


## Directional attack ring: centre and radius chosen so the outermost triangle tip stays
## above the scanner strip. `reach` is the tip distance beyond the radius.
static func ring_geometry(view: Vector2, reach := 34.0, half_base := 22.0) -> Dictionary:
	var l := layout(view)
	var center := Vector2(view.x * 0.5, view.y * 0.4)
	var floor_y := (l["scanner"] as Rect2).position.y - 8.0
	var radius := minf(minf(view.x, view.y) * 0.24, floor_y - center.y - reach)
	radius = maxf(radius, 20.0)
	return {"center": center, "radius": radius, "reach": reach, "half_base": half_base}


## Digit masks for a right-justified value; leading digits stay blank (mask 0).
static func speed_masks(value: int, count := 3) -> Array[int]:
	var limit := int(pow(10.0, count)) - 1
	var shown := clampi(value, 0, limit)
	var text := str(shown)
	var masks: Array[int] = []
	for i in count:
		var from_right := count - 1 - i
		masks.append(DIGIT_MASKS[int(text[text.length() - 1 - from_right])] if from_right < text.length() else 0)
	return masks


## The seven hexagonal segment polygons of one digit cell, keyed by segment bit.
static func segment_polygons(cell: Rect2) -> Dictionary:
	var t := cell.size.x * 0.2
	var h := t * 0.5
	var g := t * 0.14
	var x0 := cell.position.x
	var x1 := cell.end.x
	var y0 := cell.position.y
	var y1 := cell.end.y
	var ym := (y0 + y1) * 0.5
	return {
		SEG_A: _horizontal(x0 + g, x1 - g, y0 + h, h),
		SEG_G: _horizontal(x0 + g + h, x1 - g - h, ym, h),
		SEG_D: _horizontal(x0 + g, x1 - g, y1 - h, h),
		SEG_F: _vertical(x0 + h, y0 + t, ym - g, h),
		SEG_B: _vertical(x1 - h, y0 + t, ym - g, h),
		SEG_E: _vertical(x0 + h, ym + g, y1 - t, h),
		SEG_C: _vertical(x1 - h, ym + g, y1 - t, h),
	}


static func _horizontal(xa: float, xb: float, yc: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(xa, yc), Vector2(xa + h, yc - h), Vector2(xb - h, yc - h),
		Vector2(xb, yc), Vector2(xb - h, yc + h), Vector2(xa + h, yc + h)])


static func _vertical(xc: float, ya: float, yb: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(xc, ya), Vector2(xc + h, ya + h), Vector2(xc + h, yb - h),
		Vector2(xc, yb), Vector2(xc - h, yb - h), Vector2(xc - h, ya + h)])


## Velocity instrument interior: three digit cells, unit label and reverse lamp rects.
static func speed_layout(rect: Rect2, s: float) -> Dictionary:
	var inner := body(rect, s)
	var unit_w := 66.0 * s
	var gap := 8.0 * s
	var cell_w := (inner.size.x - unit_w - gap * 3.0) / 3.0
	var cell_h := minf(inner.size.y * 0.92, cell_w * 1.9)
	var top := inner.position.y + (inner.size.y - cell_h) * 0.5
	var cells: Array[Rect2] = []
	for i in 3:
		cells.append(Rect2(inner.position.x + i * (cell_w + gap), top, cell_w, cell_h))
	var unit_x := inner.position.x + 3.0 * (cell_w + gap)
	return {"cells": cells,
		"unit": Rect2(unit_x, top + cell_h - 28.0 * s, unit_w, 28.0 * s),
		"reverse": Rect2(unit_x, top, unit_w, 24.0 * s)}


## Systems instrument interior: boost text, lamp/feedback text, bodywork label and bar.
static func systems_layout(rect: Rect2, s: float) -> Dictionary:
	var inner := body(rect, s)
	var p := inner.position
	var w := inner.size.x
	return {"boost": Rect2(p, Vector2(w, 46.0 * s)),
		"status": Rect2(p + Vector2(0.0, 50.0 * s), Vector2(w, 60.0 * s)),
		"damage_label": Rect2(p + Vector2(0.0, 116.0 * s), Vector2(w, 18.0 * s)),
		"damage_bar": Rect2(p + Vector2(0.0, 138.0 * s), Vector2(w, 10.0 * s))}


## Scanner cells for `phase` (one full there-and-back sweep per 1.0): the bright head and a
## fading trail behind it, all inside `strip`. Each entry is {rect, alpha, head}.
static func scanner_cells(strip: Rect2, phase: float) -> Array[Dictionary]:
	var p := fposmod(phase, 1.0)
	var along := 1.0 - absf(2.0 * p - 1.0)
	var dir := 1.0 if p < 0.5 else -1.0
	var cw := strip.size.x * 0.04
	var head_x := strip.position.x + along * (strip.size.x - cw)
	var cells: Array[Dictionary] = []
	for i in SCANNER_CELLS:
		var x := head_x - dir * i * cw
		if x < strip.position.x - 0.001 or x + cw > strip.end.x + 0.001:
			continue
		var fade := 1.0 - float(i) / float(SCANNER_CELLS)
		cells.append({"rect": Rect2(x, strip.position.y, cw - 1.0, strip.size.y), "alpha": 1.0 if i == 0 else 0.55 * fade * fade, "head": i == 0})
	return cells


## Largest font size in [min_size, max_size] at which `text` fits `box` (wrapped to the
## box width when `wrap`, otherwise one unwrapped line per text line).
static func fit_font_size(font: Font, text: String, box: Vector2, max_size: int, min_size := 9, wrap := false) -> int:
	var size := max_size
	while size > min_size:
		var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.x if wrap else -1.0, size)
		if measured.x <= box.x and measured.y <= box.y:
			break
		size -= 1
	return size
