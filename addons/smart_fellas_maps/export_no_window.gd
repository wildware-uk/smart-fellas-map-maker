extends SceneTree
## Does what the Export Map button does, with no window, for tests and scripts:
##
##   godot --headless --path <this project> --script res://addons/smart_fellas_maps/export_no_window.gd \
##       -- res://maps/godot_test.tscn [<out folder> [<view file>]]
##
## With no out folder it writes where the Export Map button does.
## The view file, if asked for, says where each kit piece really is in Godot, so that a test can
## compare it with where the running game put it.

const MapExporter := preload("map_exporter.gd")
const Version := preload("version.gd")


func _initialize() -> void:
	# The tree only comes to life on its first frame, and nothing has a place in the world before it.
	await process_frame
	print(Version.words())
	var words := OS.get_cmdline_user_args()
	if words.is_empty():
		printerr("Give a scene, and optionally an out folder and a view file.")
		quit(2)
		return
	var root: Node = load(words[0]).instantiate()
	get_root().add_child(root)
	var out_folder := words[1] if words.size() > 1 else MapExporter.default_out_folder()
	var result := MapExporter.export_map(root, out_folder)
	print(MapExporter.result_words(result))
	if result.has("package") and words.size() > 2:
		_write_view(root, words[2])
	quit(0 if result.has("package") else 1)


## One line per piece: its kit name, its origin and three axes as Godot holds them, then the box its
## mesh's real points fill in the world. Then one line per marker: its name, origin and three axes.
func _write_view(root: Node, path: String) -> void:
	var lines := PackedStringArray()
	for found in MapExporter.kit_pieces(root):
		for mesh_node in found["node"].find_children("*", "MeshInstance3D", true, false):
			lines.append(_view_line(found["kit"], mesh_node))
	for marker in root.find_children("*", "Marker3D", true, false):
		var place: Transform3D = marker.global_transform
		lines.append(_numbers(marker.name, [place.origin, place.basis.x, place.basis.y, place.basis.z]))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()


func _view_line(kit: String, mesh_node: MeshInstance3D) -> String:
	var place: Transform3D = mesh_node.global_transform
	var low := Vector3.INF
	var high := -Vector3.INF
	var mesh: Mesh = mesh_node.mesh
	for surface in mesh.get_surface_count():
		var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for point in points:
			var world := place * point
			low = low.min(world)
			high = high.max(world)
	return _numbers(kit, [place.origin, place.basis.x, place.basis.y, place.basis.z, low, high])


func _numbers(name: String, vectors: Array) -> String:
	var words := PackedStringArray([name])
	for at in vectors:
		words.append("%.7f %.7f %.7f" % [at.x, at.y, at.z])
	return " ".join(words)
