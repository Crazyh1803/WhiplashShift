## Runtime contract shared by track construction, CPU drivers, and race modes.
##
## Physics still reads the sampled point dictionaries directly. This resource
## adds course identity and derived race metadata without coupling either system
## to presentation assets.
class_name CourseDefinition
extends Resource

const CHECKPOINT_SPACING := 110.0

var course_id: String = ""
var display_name: String = ""
var theme_id: String = ""
var default_laps: int = 1
var points: Array = []
var total_length: float = 0.0
var checkpoints: Array = []


func configure(
		p_id: String,
		p_name: String,
		p_theme: String,
		p_laps: int,
		p_points: Array) -> CourseDefinition:
	course_id = p_id
	display_name = p_name
	theme_id = p_theme
	default_laps = p_laps
	points = p_points
	_rebuild_derived_data()
	return self


func start_transform(spawn_lift: float = 0.0) -> Transform3D:
	if checkpoints.is_empty():
		var fallback := Transform3D.IDENTITY
		fallback.origin.y = spawn_lift
		return fallback
	var result: Transform3D = checkpoints[0]["transform"]
	result.origin.y += spawn_lift
	return result


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if course_id.is_empty():
		errors.append("course_id is empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is empty")
	if theme_id.is_empty():
		errors.append("theme_id is empty")
	if default_laps <= 0:
		errors.append("default_laps must be positive")
	if points.size() < 3:
		errors.append("a closed course needs at least three points")
	if total_length <= 0.0:
		errors.append("total_length must be positive")
	if checkpoints.size() < 2:
		errors.append("course needs at least two checkpoints")
	for i in points.size():
		var point: Dictionary = points[i]
		for key: String in ["pos", "dir", "w", "s", "dist"]:
			if not point.has(key):
				errors.append("point %d is missing %s" % [i, key])
	errors.append_array(TrackRelief.validation(points))
	return errors


func _rebuild_derived_data() -> void:
	total_length = 0.0
	checkpoints.clear()
	if points.is_empty():
		return

	checkpoints.append(_make_checkpoint(0, 0.0))
	var next_checkpoint := CHECKPOINT_SPACING
	for i in points.size():
		var point: Dictionary = points[i]
		total_length += float(point.get("dist", 0.0))
		var next_index := (i + 1) % points.size()
		if total_length >= next_checkpoint and next_index != 0:
			checkpoints.append(_make_checkpoint(next_index, total_length))
			while next_checkpoint <= total_length:
				next_checkpoint += CHECKPOINT_SPACING


func _make_checkpoint(index: int, distance: float) -> Dictionary:
	var point: Dictionary = points[index]
	var direction: Vector3 = point.get("dir", Vector3.FORWARD)
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var transform := Transform3D.IDENTITY
	# Vehicle End A points down body -Z.
	transform.basis = Basis(Vector3.UP, atan2(-direction.x, -direction.z))
	transform.origin = point.get("pos", Vector3.ZERO)
	return {"index": index, "distance": distance, "transform": transform}
