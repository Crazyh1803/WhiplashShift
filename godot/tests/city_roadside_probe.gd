## Test-only probes for the roadside layer. Geometry probes (first surface hit by a ray, per material) work headless; the rendered probes draw the
## real meshes into private SubViewports (own World3D) with temporary unshaded material-ID overrides on the *probe* MeshInstance3D only, so the shared
## meshes, their materials and the live scene's render layers are never touched.
extends RefCounted

const LEVELS := [0.0, 0.5, 1.0]
static var _faces: Dictionary = {}


## Triangle soup of one surface (indexed or not).
static func surface_faces(mesh: ArrayMesh, surface: int) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
		for i in (indices as PackedInt32Array):
			out.append(vertices[i])
	else:
		out = vertices
	return out


## FIRST surface hit by a ray cast along +Z from (at.x, at.y, from_z): {"material": resource name, "depth": hit z, "surface": index}; material "" on a miss.
static func first_hit(mesh: ArrayMesh, at: Vector3, from_z: float = -8.0) -> Dictionary:
	var key := mesh.get_instance_id()
	if not _faces.has(key):
		var meshes: Array[TriangleMesh] = []
		for surface in mesh.get_surface_count():
			var triangles := TriangleMesh.new()
			triangles.create_from_faces(surface_faces(mesh, surface))
			meshes.append(triangles)
		_faces[key] = meshes
	var best := {"material": "", "depth": INF, "surface": -1}
	var meshes_for: Array = _faces[key]
	for surface in meshes_for.size():
		var hit: Dictionary = (meshes_for[surface] as TriangleMesh).intersect_ray(Vector3(at.x, at.y, from_z), Vector3.BACK)
		if not hit.is_empty() and (hit["position"] as Vector3).z < float(best["depth"]):
			best = {"material": mesh.surface_get_material(surface).resource_name, "depth": (hit["position"] as Vector3).z, "surface": surface}
	return best


## FIRST surface hit by a ray cast straight down (-Y) from (at.x, from_y, at.z): {"material", "height": hit y, "surface"}; material "" on a miss.
static func first_hit_down(mesh: ArrayMesh, at: Vector3, from_y: float = 3.0) -> Dictionary:
	var best := {"material": "", "height": -INF, "surface": -1}
	for surface in mesh.get_surface_count():
		var triangles := TriangleMesh.new()
		triangles.create_from_faces(surface_faces(mesh, surface))
		var hit: Dictionary = triangles.intersect_ray(Vector3(at.x, from_y, at.z), Vector3.DOWN)
		if not hit.is_empty() and (hit["position"] as Vector3).y > float(best["height"]):
			best = {"material": mesh.surface_get_material(surface).resource_name, "height": (hit["position"] as Vector3).y, "surface": surface}
	return best


## Looking down into a burning drum: every sample inside the fire radius must first hit the coal bed (never steel, i.e. a hoop or lid spanning the opening),
## with glowing coal visible, while the hoop ring itself is still there. `radius` is the fire radius, `drum` the drum radius. Returns the problems.
static func barrel_interior_problems(mesh: ArrayMesh, radius: float, drum: float) -> Array[String]:
	var problems: Array[String] = []
	var glow := 0
	var samples := 0
	for ring in [0.0, 0.35, 0.7, 0.95]:
		for k in (1 if ring == 0.0 else 8):
			var a := TAU * float(k) / 8.0
			var hit := first_hit_down(mesh, Vector3(cos(a), 0.0, sin(a)) * radius * ring)
			var material := String(hit["material"])
			samples += 1
			glow += int(material == "lamp_glass")
			if not material in ["lamp_glass", "plastic_rubber"]:
				problems.append("interior sample at %.0f%% of the fire radius, angle %.0f first hits %s at y=%.2f" % [ring * 100.0, rad_to_deg(a), material if material != "" else "nothing", float(hit["height"])])
	if glow * 3 < samples:
		problems.append("only %d of %d interior samples see glowing coal" % [glow, samples])
	var hoops := 0
	for k in 16:
		var a := TAU * float(k) / 16.0
		hoops += int(first_hit_down(mesh, Vector3(cos(a), 0.0, sin(a)) * drum * 1.025)["material"] == "steel_structure")
	if hoops < 12:
		problems.append("rolling hoops missing: only %d of 16 samples on the hoop ring hit steel" % hoops)
	return problems


## Probes of one tower mesh against its declared apertures: returns the list of problems (empty when every declared opening shows an allowed, recessed surface).
static func aperture_problems(mesh: ArrayMesh, apertures: Array, masonry: Array) -> Array[String]:
	var problems: Array[String] = []
	for probe: Dictionary in apertures:
		var at := Vector3(float(probe["position"][0]), float(probe["position"][1]), 0.0)
		var hit := first_hit(mesh, at)
		var material := String(hit["material"])
		var depth := float(hit["depth"])
		if material == "" or material in masonry or not material in probe["expect"] or depth < float(probe["min_depth"]):
			problems.append("%s at (%.2f, %.2f) first hit %s at depth %.2f (want %s >= %.2f deep)" % [probe["kind"], at.x, at.y, material, depth, probe["expect"], probe["min_depth"]])
	return problems


static func id_color(index: int) -> Color:
	var n := index + 1
	return Color(LEVELS[n % 3], LEVELS[(n / 3) % 3], LEVELS[(n / 9) % 3])


## Surface index encoded by a rendered ID pixel (-1 = background); robust to sRGB conversion because only 3 well-separated levels are used.
static func decode(color: Color) -> int:
	var l: Array[int] = []
	for v in [color.r, color.g, color.b]:
		l.append(0 if v < 0.25 else (1 if v < 0.85 else 2))
	return l[0] + 3 * l[1] + 9 * l[2] - 1


static func _viewport(size: Vector2i, ambient: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = ambient
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	return viewport


static func _read(host: Node, viewport: SubViewport) -> Image:
	host.add_child(viewport)
	for frame in 3:
		await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	host.remove_child(viewport)
	viewport.free()
	return image


## Material-ID render of a tower facade seen straight on (orthographic, looking along +Z): the surface under each declared aperture centre must be an allowed,
## non-masonry material. Hull occlusion (masonry in front of the opening) or a missing draw (background) fails.
static func rendered_aperture_problems(host: Node, mesh: ArrayMesh, apertures: Array, masonry: Array) -> Array[String]:
	var size := Vector2i(2048, 1024)
	var height := 12.5
	var centre := Vector2(0.0, height * 0.5)
	var viewport := _viewport(size, 0.0)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	for surface in mesh.get_surface_count():
		var id := StandardMaterial3D.new()
		id.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		id.albedo_color = id_color(surface)
		instance.set_surface_override_material(surface, id)
	viewport.add_child(instance)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = height
	camera.near = 0.1
	camera.far = 60.0
	camera.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(centre.x, centre.y, -12.0))
	viewport.add_child(camera)
	camera.current = true
	var image := await _read(host, viewport)
	var metres_per_pixel := height / float(size.y)
	var problems: Array[String] = []
	for probe: Dictionary in apertures:
		var x := float(probe["position"][0])
		var y := float(probe["position"][1])
		var pixel := Vector2i(int(roundf(size.x * 0.5 - (x - centre.x) / metres_per_pixel)), int(roundf(size.y * 0.5 - (y - centre.y) / metres_per_pixel)))
		pixel = pixel.clamp(Vector2i.ZERO, size - Vector2i.ONE)
		var index := decode(image.get_pixelv(pixel))
		var material := mesh.surface_get_material(index).resource_name if index >= 0 and index < mesh.get_surface_count() else ""
		if material == "" or material in masonry or not material in probe["expect"]:
			problems.append("%s at (%.2f, %.2f) renders %s (want %s)" % [probe["kind"], x, y, material if material != "" else "background", probe["expect"]])
	return problems


## Roadside nodes overlapping a view's subject (same rule as CityRoadsideViews.subject_activity).
static func subject_nodes(roadside: Node3D, view: Dictionary) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	var subject: AABB = (view["subject"] as AABB).grow(1.0)
	for instance: MultiMeshInstance3D in roadside.find_children("*", "MultiMeshInstance3D", true, false):
		if instance.custom_aabb.intersects(subject):
			out.append(instance)
	return out


## Isolated readback of a view's subject: only copies of the overlapping roadside nodes (shared MultiMesh, mesh and materials; the originals are not
## modified) are drawn from the view's camera against black. Returns {"image", "coverage" (non-black fraction), "mean" (mean luminance of covered pixels)}.
static func render_subject(host: Node, roadside: Node3D, view: Dictionary, size: Vector2i = Vector2i(640, 360)) -> Dictionary:
	var viewport := _viewport(size, 0.6)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 0.8
	viewport.add_child(light)
	var copies := 0
	for instance in subject_nodes(roadside, view):
		var copy := instance.duplicate() as MultiMeshInstance3D
		viewport.add_child(copy)
		copy.global_transform = instance.global_transform
		copies += 1
	var camera := Camera3D.new()
	camera.fov = view["fov"]
	camera.far = 2500.0
	viewport.add_child(camera)
	camera.global_transform = Transform3D(Basis.IDENTITY, view["eye"]).looking_at(view["target"], Vector3.UP)
	camera.current = true
	var image := await _read(host, viewport)
	var covered := 0
	var luminance := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var v := image.get_pixel(x, y).get_luminance()
			if v > 0.012:
				covered += 1
				luminance += v
	return {"image": image, "copies": copies, "coverage": float(covered) / float(size.x * size.y), "mean": luminance / maxf(1.0, float(covered))}
