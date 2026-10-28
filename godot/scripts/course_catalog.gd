class_name CourseCatalog
extends RefCounted

const IDS: Array[String] = ["block_circuit", "split_shift"]
const LABELS := {"block_circuit": "Block Circuit // City", "split_shift": "Split Shift // Proving Ground"}


static func sanitize(id: String) -> String:
	return id if IDS.has(id) else "split_shift"


static func build_course(id: String) -> CourseDefinition:
	if sanitize(id) == "block_circuit":
		return BlockCircuitData.build_course()
	var course := TrackData.build_course()
	return course.configure(course.course_id, course.display_name, course.theme_id,
		course.default_laps, course.points.slice(16) + course.points.slice(0, 16))


static func build_scenery(parent: Node3D, course: CourseDefinition) -> void:
	if course.course_id == "block_circuit":
		CityScenery.build(parent, course)
	else:
		TrackScenery.build(parent, course)
		TrackScenery.build_deposits(parent, course)
		TrackBuilder.build_proving_ground(parent, Vector3(-620.0, 0.0, 0.0))
	TrackScenery.build_guidance(parent, course)
