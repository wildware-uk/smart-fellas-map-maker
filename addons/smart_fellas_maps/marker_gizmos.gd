@tool
extends EditorNode3DGizmoPlugin
## Draws each marker on the map as a simple shape in its kind's colour, in front of everything, so that
## it can be seen and clicked. These live only in the editor: Export and the game never see them.

const MarkerKinds := preload("marker_kinds.gd")

## How big each kind's shape is, in metres.
const SHAPE_SIZE := 0.2
const FACING_LENGTH := 1.2
const RING_POINTS := 24


func _init() -> void:
	for kind: String in MarkerKinds.KINDS:
		create_material(kind, MarkerKinds.KINDS[kind]["colour"], false, true)


func _get_gizmo_name() -> String:
	return "Smart Fellas markers"


func _has_gizmo(node: Node3D) -> bool:
	return node is Marker3D and not MarkerKinds.kind_of(node.name).is_empty()


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var kind := MarkerKinds.kind_of(gizmo.get_node_3d().name)
	if kind.is_empty():
		return
	var material := get_material(kind, gizmo)
	var mesh := SphereMesh.new()
	mesh.radius = SHAPE_SIZE
	mesh.height = SHAPE_SIZE * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	gizmo.add_mesh(mesh, material)
	var lines := _ring(SHAPE_SIZE * 2.5)
	if kind.begins_with("spawn") or kind.begins_with("fish") or kind == "angler":
		lines.append_array(PackedVector3Array([Vector3.ZERO, Vector3.FORWARD * FACING_LENGTH]))
	# A marker named by hand has no settings, and so no reach to show.
	var reach: Variant = gizmo.get_node_3d().get("spread" if kind == "jellies" else "roam")
	if kind in ["jellies", "lantern"] and reach != null:
		lines.append_array(_ring(reach))
	gizmo.add_lines(lines, material)
	gizmo.add_collision_segments(lines)


static func _ring(radius: float) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for index in RING_POINTS:
		var from := TAU * index / RING_POINTS
		var to := TAU * (index + 1) / RING_POINTS
		lines.append(Vector3(cos(from), 0.0, sin(from)) * radius)
		lines.append(Vector3(cos(to), 0.0, sin(to)) * radius)
	return lines
