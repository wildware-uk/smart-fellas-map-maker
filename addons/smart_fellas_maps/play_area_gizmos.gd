@tool
extends EditorNode3DGizmoPlugin
## Draws the map's play area in the 3D view: faint walls at its edges, a ceiling, and a clear outline on the
## floor, with handles on the edges and the ceiling that resize it as they're dragged. Markers outside it are
## outlined red, as the game refuses them, and so are pieces too far out for Export to take; pieces wholly
## outside it, which players can see but never reach, are outlined amber. It lives only in the editor:
## Export and the game never see it.

const PlayArea := preload("play_area.gd")

## A deep blue, which stands out against both the pale sand and the water's cyan haze.
const AREA_COLOUR := Color(0.1, 0.2, 0.9)
const WALL_ALPHA := 0.16
const CEILING_ALPHA := 0.1
const REFUSED_COLOUR := Color(1.0, 0.25, 0.2)
const WARNED_COLOUR := Color(1.0, 0.7, 0.2)
## How far round a marker its outline is drawn, in metres. A post runs up from it to the ceiling too, so
## that it shows from far off.
const MARKER_OUTLINE := 1.0
## The most pieces outlined at once: a brush can paint thousands outside, and the panel counts them all.
const MOST_OUTLINED := 500

## Whether the area is drawn at all: the Map panel's "Show play area".
var shown := true
var undo: EditorUndoRedoManager
## What gather() found, kept while nothing in the map changes: a drag redraws on every move of the mouse.
var _gathered := {}


func _init() -> void:
	add_material("walls", _see_through(WALL_ALPHA))
	add_material("ceiling", _see_through(CEILING_ALPHA))
	add_material("outline", _lines(AREA_COLOUR))
	add_material("refused", _lines(REFUSED_COLOUR))
	add_material("warned", _lines(WARNED_COLOUR))
	create_handle_material("handles")


static func _see_through(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# The water's own screen pass draws over anything see-through that tests depth, so these don't.
	material.no_depth_test = true
	material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	material.disable_fog = true
	material.albedo_color = Color(AREA_COLOUR, alpha)
	return material


## Lines drawn over everything, so an edge or an outline behind a rock or under the sand still shows.
static func _lines(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = StandardMaterial3D.RENDER_PRIORITY_MAX
	material.albedo_color = colour
	return material


func _get_gizmo_name() -> String:
	return "Smart Fellas play area"


func _has_gizmo(node: Node3D) -> bool:
	return node is SmartFellasMap


## Something in the map moved, came or went: gather it again at the next draw.
func forget() -> void:
	_gathered = {}


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var map := gizmo.get_node_3d() as SmartFellasMap
	if not shown or map == null or not map.is_inside_tree():
		return
	var low := PlayArea.floor_height(map)
	var half: float = map.half_width
	var top: float = map.ceiling
	var corners := [Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half), Vector3(half, 0.0, half), Vector3(-half, 0.0, half)]
	# From the floor up: drawn over everything, walls below the sand would show through it.
	gizmo.add_mesh(_walls(corners, low, top), get_material("walls", gizmo))
	gizmo.add_mesh(_ceiling(corners, top), get_material("ceiling", gizmo))
	var lines := PackedVector3Array()
	for index in corners.size():
		var here: Vector3 = corners[index]
		var next: Vector3 = corners[(index + 1) % corners.size()]
		for height in [low, top]:
			lines.append(here + Vector3.UP * height)
			lines.append(next + Vector3.UP * height)
		lines.append(here + Vector3.UP * low)
		lines.append(here + Vector3.UP * top)
	gizmo.add_lines(lines, get_material("outline", gizmo))
	# Clicking the outline selects the map, which shows the handles.
	gizmo.add_collision_segments(lines)
	gizmo.add_handles(PlayArea.handle_points(map), get_material("handles", gizmo), [])
	_outline_what_is_outside(gizmo, map)


func _outline_what_is_outside(gizmo: EditorNode3DGizmo, map: SmartFellasMap) -> void:
	if _gathered.is_empty():
		_gathered = PlayArea.gather(map)
	var out := PlayArea.outside(map, _gathered)
	var into_map := map.global_transform.affine_inverse()
	var refused := PackedVector3Array()
	for marker: Node3D in out["markers"]:
		if is_instance_valid(marker):
			var at := into_map * marker.global_position
			refused.append_array(_box_lines(AABB(at - Vector3.ONE * MARKER_OUTLINE, Vector3.ONE * MARKER_OUTLINE * 2.0)))
			refused.append_array([Vector3(at.x, PlayArea.floor_height(map), at.z), Vector3(at.x, maxf(map.ceiling, at.y), at.z)])
	refused.append_array(_boxes_of(out["far"], into_map))
	if not refused.is_empty():
		gizmo.add_lines(refused, get_material("refused", gizmo))
	var warned := _boxes_of(out["pieces"], into_map)
	if not warned.is_empty():
		gizmo.add_lines(warned, get_material("warned", gizmo))


## The outlines of up to MOST_OUTLINED pieces, in the map's own space.
static func _boxes_of(pieces: Array, into_map: Transform3D) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for index in mini(pieces.size(), MOST_OUTLINED):
		var piece: Dictionary = pieces[index]
		if piece["node"] == null or is_instance_valid(piece["node"]):
			lines.append_array(_box_lines(into_map * (piece["box"] as AABB)))
	return lines


static func _walls(corners: Array, bottom: float, top: float) -> ArrayMesh:
	var points := PackedVector3Array()
	for index in corners.size():
		var here: Vector3 = corners[index]
		var next: Vector3 = corners[(index + 1) % corners.size()]
		points.append_array([here + Vector3.UP * bottom, next + Vector3.UP * bottom, next + Vector3.UP * top])
		points.append_array([here + Vector3.UP * bottom, next + Vector3.UP * top, here + Vector3.UP * top])
	return _mesh_of(points)


static func _ceiling(corners: Array, top: float) -> ArrayMesh:
	var lift := Vector3.UP * top
	return _mesh_of(PackedVector3Array([
		corners[0] + lift, corners[1] + lift, corners[2] + lift,
		corners[0] + lift, corners[2] + lift, corners[3] + lift,
	]))


static func _mesh_of(points: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The twelve edges of a box, as pairs of points: each corner joined to the next along each way it can go.
static func _box_lines(box: AABB) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for corner in 8:
		for way in [1, 2, 4]:
			if corner & way == 0:
				lines.append(box.get_endpoint(corner))
				lines.append(box.get_endpoint(corner | way))
	return lines


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return "Highest swim" if handle_id == PlayArea.Handle.CEILING else "Half width"


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().get(PlayArea.property_of(handle_id))


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var map := gizmo.get_node_3d() as SmartFellasMap
	var into_map := map.global_transform.affine_inverse()
	var from := into_map * camera.project_ray_origin(screen_pos)
	var toward := (into_map.basis * camera.project_ray_normal(screen_pos)).normalized()
	var value := PlayArea.dragged_handle(map, handle_id, from, toward, Input.is_key_pressed(KEY_CTRL))
	var key := PlayArea.property_of(handle_id)
	if map.get(key) != value:
		map.set(key, value)


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	PlayArea.let_go(gizmo.get_node_3d() as SmartFellasMap, handle_id, restore, cancel, undo)
