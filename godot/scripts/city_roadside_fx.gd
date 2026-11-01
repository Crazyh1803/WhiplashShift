## Burning-barrel effects: one shared three-surface mesh (flame, ground pool, smoke) drawn as a MultiMesh with one instance per barrel.
## Animation is shader time only; there are no particle systems and no light nodes. The effect volume is fixed by the geometry and the smoke shader's
## clamps (radius 2 m, height 5.8 m), which is exactly the box the layout reserves for every barrel.
class_name CityRoadsideFx
extends RefCounted

const FLAME_SHADER := preload("res://shaders/roadside_fire.gdshader")
const SMOKE_SHADER := preload("res://shaders/roadside_smoke.gdshader")
const FLAME_QUADS := 3
const FLAME_WIDTH := 0.5
const FLAME_HEIGHT := 0.9
const PUFFS := 6
const POOL_RADIUS := 2.0
const MAX_BARRELS := 16
static var _mesh: ArrayMesh


## Surfaces: 0 flame, 1 ground pool, 2 smoke puffs. Cached; the custom AABB covers the whole bounded volume.
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var result := ArrayMesh.new()
	_surface(result, _flame_arrays(), _material(0.0, 1.55, 1))
	_surface(result, _pool_arrays(), _material(1.0, 1.4, 0))
	_surface(result, _smoke_arrays(), _smoke_material())
	result.custom_aabb = AABB(Vector3(-CityRoadsideLayout.EFFECT_RADIUS, 0.0, -CityRoadsideLayout.EFFECT_RADIUS), Vector3(CityRoadsideLayout.EFFECT_RADIUS * 2.0, CityRoadsideLayout.EFFECT_HEIGHT, CityRoadsideLayout.EFFECT_RADIUS * 2.0))
	_mesh = result
	return result


static func _surface(target: ArrayMesh, arrays: Array, material: Material) -> void:
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.surface_set_material(target.get_surface_count() - 1, material)


static func _quad(vertices: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, corners: Array, uv_rect: Rect2, color: Color) -> void:
	var base := vertices.size()
	for i in 4:
		vertices.append(corners[i])
		colors.append(color)
	uvs.append(uv_rect.position + Vector2(0.0, uv_rect.size.y))
	uvs.append(uv_rect.position + uv_rect.size)
	uvs.append(uv_rect.position + Vector2(uv_rect.size.x, 0.0))
	uvs.append(uv_rect.position)
	indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))


static func _arrays(vertices: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _flame_arrays() -> Array:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for k in FLAME_QUADS:
		var axis := Vector3(cos(PI * k / FLAME_QUADS), 0.0, sin(PI * k / FLAME_QUADS)) * (FLAME_WIDTH * 0.5)
		# rows of three quads' worth of height give the vertex sway something to bend
		_quad(v, uv, c, idx, [-axis, axis, axis + Vector3.UP * FLAME_HEIGHT, -axis + Vector3.UP * FLAME_HEIGHT], Rect2(0, 0, 1, 1), Color.WHITE)
	return _arrays(v, uv, c, idx)


static func _pool_arrays() -> Array:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var r := POOL_RADIUS
	_quad(v, uv, c, idx, [Vector3(-r, 0.05, r), Vector3(r, 0.05, r), Vector3(r, 0.05, -r), Vector3(-r, 0.05, -r)], Rect2(0, 0, 1, 1), Color.WHITE)
	return _arrays(v, uv, c, idx)


static func _smoke_arrays() -> Array:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for k in PUFFS:
		_quad(v, uv, c, idx, [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)], Rect2(0, 0, 1, 1), Color(float(k) / PUFFS, 0, 0, 1))
	return _arrays(v, uv, c, idx)


static func _material(mode: float, intensity: float, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("intensity", intensity)
	material.render_priority = priority
	return material


static func _smoke_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	material.render_priority = 2
	return material


## One instance per barrel, placed at the barrel's foot; `coal_heights` lifts flame and smoke to the coal bed. Phase offsets de-synchronise the flames deterministically.
static func build(parent: Node3D, fire_bases: Array[Vector3], coal_heights: Array[float], yaw: Array[float]) -> MultiMeshInstance3D:
	if fire_bases.is_empty():
		return null
	var count := mini(fire_bases.size(), MAX_BARRELS)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh()
	multimesh.instance_count = count
	var placed: Array[Transform3D] = []
	for i in count:
		var xf := Transform3D(Basis(Vector3.UP, yaw[i]), fire_bases[i])
		placed.append(xf)
		multimesh.set_instance_transform(i, xf)
		multimesh.set_instance_custom_data(i, Color(fposmod(float(i) * 0.37 + 0.11, 1.0), coal_heights[i], 0, 0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "BarrelFire"
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 180.0
	instance.visibility_range_end_margin = 10.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.set_meta("city_transforms", placed)
	instance.set_meta("roadside_kind", "fire")
	parent.add_child(instance)
	return instance
