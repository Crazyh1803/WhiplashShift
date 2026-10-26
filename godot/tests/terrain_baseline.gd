## Terrain baseline for the default circuit: collider/mesh hashes and viscera transform hashes.
## Run against the commit BEFORE terrain profiles to (re)generate the fixture, then with --check
## on any later commit to prove the default course is unchanged:
##   godot --headless --path godot -s res://tests/terrain_baseline.gd            # write
##   godot --headless --path godot -s res://tests/terrain_baseline.gd -- --check # verify
extends SceneTree

const FIXTURE := "res://tests/fixtures/terrain_defaults.json"


func _initialize() -> void:
	var record := _capture()
	if "--check" in OS.get_cmdline_user_args():
		var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
		var same: bool = golden == record
		print("TERRAIN_BASELINE: ", "match" if same else "MISMATCH")
		quit(0 if same else 1)
		return
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t", true))
	file.close()
	print("TERRAIN_BASELINE: wrote %d runs" % record["runs"].size())
	quit(0)


func _capture() -> Dictionary:
	var points := TrackData.author()
	var root := Node3D.new()
	get_root().add_child(root)
	TrackBuilder.build(root, points)
	var runs := {}
	for body: StaticBody3D in root.get_children():
		var visual: MeshInstance3D = body.get_node("RoadMesh")
		var arrays: Array = visual.mesh.surface_get_arrays(0)
		var entry := {
			"surface": body.get_meta("surface_type"),
			"collider": _hash(body.get_child(1).shape.get_faces().to_byte_array()),
			"vertices": _hash((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array()),
			"normals": _hash((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).to_byte_array()),
			"uv": _hash((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array()),
			"uv2": _hash((arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).to_byte_array()),
		}
		var pit := visual.get_node_or_null("VisceraPit")
		if pit:
			var viscera := {}
			for batch: MultiMeshInstance3D in pit.get_children():
				var floats := PackedFloat32Array()
				for t: Transform3D in batch.get_meta("cpu_transforms"):
					floats.append_array([t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
						t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z])
				viscera[String(batch.name)] = {"count": floats.size() / 12, "sha256": _hash(floats.to_byte_array())}
			entry["viscera"] = viscera
		runs[String(body.name)] = entry
	root.free()
	return {"author": _hash(var_to_bytes(points)), "runs": runs}


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
