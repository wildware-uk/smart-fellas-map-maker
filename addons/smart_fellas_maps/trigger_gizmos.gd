@tool
extends EditorNode3DGizmoPlugin
## Draws trigger zones in the 3D view: a see-through box with clear edges, drawn over everything so it
## shows through rocks and sand, and a dot on three of its sides that sizes it as it's dragged, the
## opposite side moving with it. Clicking an edge selects the zone, to move it with Godot's own arrows. It
## lives only in the editor.

const TriggerZone := preload("trigger_zone.gd")
const ZoneGizmos := preload("zone_gizmos.gd")

const SIDE_ALPHA := 0.15
## What each handle is called, by the axis it sizes.
const HANDLE_NAMES: Array[String] = ["Width", "Height", "Depth"]
## The box's corners, as which way it reaches on each axis, and the edges and sides between them.
const CORNERS: Array[Vector3] = [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
	Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
]
const EDGES: Array[int] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
const SIDES: Array[int] = [
	0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1,
	1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0,
]

var undo: EditorUndoRedoManager


func _init() -> void:
	add_material("sides", ZoneGizmos.overlay_material(Color(TriggerZone.COLOUR, SIDE_ALPHA)))
	add_material("edges", ZoneGizmos.overlay_material(TriggerZone.COLOUR))
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "Smart Fellas trigger zone"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == TriggerZone


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var reach: Vector3 = gizmo.get_node_3d().reach
	var edges := PackedVector3Array()
	for corner in EDGES:
		edges.append(CORNERS[corner] * reach)
	var sides := PackedVector3Array()
	for corner in SIDES:
		sides.append(CORNERS[corner] * reach)
	gizmo.add_mesh(ZoneGizmos.mesh_of(sides), get_material("sides", gizmo))
	gizmo.add_lines(edges, get_material("edges", gizmo))
	# Only the edges pick the zone: a door or lever inside it must still be clickable through its sides.
	gizmo.add_collision_segments(edges)
	var handles := PackedVector3Array([Vector3(reach.x, 0.0, 0.0), Vector3(0.0, reach.y, 0.0), Vector3(0.0, 0.0, reach.z)])
	gizmo.add_handles(handles, get_material("handles", gizmo), [])


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return HANDLE_NAMES[handle_id]


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().reach


## The side follows the mouse along its own axis: the point on that axis nearest the mouse's ray.
func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var zone := gizmo.get_node_3d()
	var middle := zone.global_position
	var along := Vector3.ZERO
	along[handle_id] = 1.0
	var from := camera.project_ray_origin(screen_pos)
	var far := from + camera.project_ray_normal(screen_pos) * camera.far
	var nearest := Geometry3D.get_closest_points_between_segments(middle - along * TriggerZone.REACHES.y * 4.0, middle + along * TriggerZone.REACHES.y * 4.0, from, far)
	var reach: Vector3 = zone.reach
	reach[handle_id] = TriggerZone.reach_toward(zone, handle_id, nearest[0], TriggerZone.widest_in(zone))
	zone.reach = reach


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var zone := gizmo.get_node_3d()
	if cancel:
		zone.reach = restore
		return
	TriggerZone.sized(zone, restore, undo)
