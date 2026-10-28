class_name SeasonRun
extends RefCounted

const POINTS: Array[int] = [10, 6, 3]

var definition: Dictionary = {}
var round_index: int = 0
var entrants: Array[Dictionary] = []
var points: Array[int] = [0, 0, 0]
var wins: Array[int] = [0, 0, 0]
var pending: Array[int] = []
var results: Array = []
var builtin: bool = false


func configure(data: Dictionary, is_builtin: bool = false) -> SeasonRun:
	definition = data.duplicate(true)
	builtin = is_builtin
	round_index = 0
	entrants.clear()
	points.assign([0, 0, 0])
	wins.assign([0, 0, 0])
	pending.clear()
	results.clear()
	return self


func is_complete() -> bool:
	return not definition.is_empty() and round_index >= definition["races"].size()


func race_options() -> Dictionary:
	return {} if is_complete() or definition.is_empty() else definition["races"][round_index].duplicate(true)


func set_roster(roster: Array[Dictionary]) -> void:
	if entrants.is_empty() and roster.size() == 3:
		entrants.assign(roster.duplicate(true))


func set_pending(order: Array[int]) -> bool:
	if is_complete() or order.size() != 3:
		return false
	var checked := order.duplicate()
	checked.sort()
	if checked != [0, 1, 2]:
		return false
	pending.assign(order)
	return true


func commit() -> bool:
	if pending.size() != 3 or is_complete():
		return false
	for rank in 3:
		points[pending[rank]] += POINTS[rank]
	wins[pending[0]] += 1
	results.append(pending.duplicate())
	round_index += 1
	pending.clear()
	return true


func table_lines(include_pending: bool = false) -> PackedStringArray:
	var totals := points.duplicate()
	var victories := wins.duplicate()
	if include_pending and pending.size() == 3:
		for rank in 3:
			totals[pending[rank]] += POINTS[rank]
		victories[pending[0]] += 1
	var order: Array[int] = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool:
		if totals[a] != totals[b]:
			return totals[a] > totals[b]
		if victories[a] != victories[b]:
			return victories[a] > victories[b]
		return a < b)
	var lines := PackedStringArray(["SEASON STANDINGS" + ("  //  PROVISIONAL" if include_pending and not pending.is_empty() else "")])
	for rank in 3:
		var slot := order[rank]
		var pilot: String = String(entrants[slot]["callsign"]) if entrants.size() == 3 else ["YOU", "RIVAL 1", "RIVAL 2"][slot]
		lines.append("%d. %s   %d PTS   %d WINS" % [rank + 1, pilot, totals[slot], victories[slot]])
	return lines
