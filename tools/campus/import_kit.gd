extends SceneTree
## Converts the Blender kit's raw meshes (art_src/campus/raw/*.utm, written
## by tools/campus/build_kit.py) into one MeshLibrary the game loads:
## game/assets/campus/campus_kit.res.  Run through tools/campus/build.sh.
##
## Each mesh keeps exactly the vertex layout the campus world shaders read:
## position, normal, sRGB vertex colour, UV (material id, parameter) and
## CUSTOM0 (emission, sway) - the same as MeshKit's runtime meshes.

const OUT := "res://assets/campus/campus_kit.res"


func _initialize() -> void:
	var raw := ProjectSettings.globalize_path("res://").path_join("../art_src/campus/raw").simplify_path()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("manifest.json")))
	var names: Array = manifest.keys()
	names.sort()
	var lib := MeshLibrary.new()
	var total_tris := 0
	for i in names.size():
		var nm: String = names[i]
		var mesh := _load_utm(raw.path_join(nm + ".utm"))
		if mesh == null:
			push_error("could not read %s" % nm)
			quit(1)
			return
		mesh.resource_name = nm
		lib.create_item(i)
		lib.set_item_name(i, nm)
		lib.set_item_mesh(i, mesh)
		total_tris += int(manifest[nm]["tris"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("campus kit: %d meshes, %d triangles in total -> %s (%s)" % [names.size(), total_tris, OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _load_utm(path: String) -> ArrayMesh:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "UTM1":
		return null
	var nv := b.decode_u32(4)
	var ni := b.decode_u32(8)
	var o := 12
	var pos := b.slice(o, o + nv * 12).to_float32_array()
	o += nv * 12
	var nrm := b.slice(o, o + nv * 12).to_float32_array()
	o += nv * 12
	var col := b.slice(o, o + nv * 4)
	o += nv * 4
	var uv := b.slice(o, o + nv * 8).to_float32_array()
	o += nv * 8
	var cu := b.slice(o, o + nv * 8).to_float32_array()
	o += nv * 8
	var idx := b.slice(o, o + ni * 4).to_int32_array()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()
	v.resize(nv)
	n.resize(nv)
	c.resize(nv)
	u.resize(nv)
	for k in nv:
		v[k] = Vector3(pos[k * 3], pos[k * 3 + 1], pos[k * 3 + 2])
		n[k] = Vector3(nrm[k * 3], nrm[k * 3 + 1], nrm[k * 3 + 2])
		c[k] = Color8(col[k * 4], col[k * 4 + 1], col[k * 4 + 2], col[k * 4 + 3])
		u[k] = Vector2(uv[k * 2], uv[k * 2 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = u
	arr[Mesh.ARRAY_CUSTOM0] = cu
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m
