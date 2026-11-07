@tool
extends EditorNode3DGizmoPlugin
## Draws Populate's zones in the 3D view: a see-through disc in the zone's colour with a clear rim, drawn
## over everything so it shows through rocks and sand, and a handle on the rim that sizes it as it's dragged.
## Clicking the rim selects the zone, to move it with Godot's own arrows. It lives only in the editor.

const Zone := preload("populate_zone.gd")

const DISC_ALPHA := 0.3
## How many straight bits a rim is drawn with.
const RIM_STEPS := 64

var undo: EditorUndoRedoManager


func _init() -> void:
	for kind: Zone.Kind in Zone.KINDS:
		var colour: Color = Zone.KINDS[kind]["colour"]
		add_material("disc %d" % kind, _material(Color(colour, DISC_ALPHA)))
		add_material("rim %d" % kind, _material(colour))
	create_handle_material("handles")


## Unshaded and drawn over everything: the water's own screen pass draws over anything see-through that
## tests depth.
static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if colour.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	material.albedo_color = colour
	return material


func _get_gizmo_name() -> String:
	return "Smart Fellas Populate zone"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == Zone


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var zone := gizmo.get_node_3d()
	var radius: float = zone.radius
	var rim := PackedVector3Array()
	var disc := PackedVector3Array()
	for step in RIM_STEPS:
		var here := _on_rim(radius, step)
		var next := _on_rim(radius, step + 1)
		rim.append_array([here, next])
		disc.append_array([Vector3.ZERO, here, next])
	gizmo.add_mesh(_mesh_of(disc), get_material("disc %d" % zone.kind, gizmo))
	gizmo.add_lines(rim, get_material("rim %d" % zone.kind, gizmo))
	gizmo.add_collision_segments(rim)
	gizmo.add_collision_triangles(_triangles_of(disc))
	gizmo.add_handles(PackedVector3Array([Vector3(radius, 0.0, 0.0)]), get_material("handles", gizmo), [])


static func _on_rim(radius: float, step: int) -> Vector3:
	var angle := TAU * step / RIM_STEPS
	return Vector3(cos(angle), 0.0, sin(angle)) * radius


static func _mesh_of(points: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _triangles_of(points: PackedVector3Array) -> TriangleMesh:
	var triangles := TriangleMesh.new()
	triangles.create_from_faces(points)
	return triangles


func _get_handle_name(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> String:
	return "Size"


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().radius


## The rim follows the mouse across the flat the zone lies on.
func _set_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var zone := gizmo.get_node_3d()
	var flat := Plane(Vector3.UP, zone.global_position.y)
	var at: Variant = flat.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if at != null:
		zone.radius = Zone.radius_toward(zone, at)


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var zone := gizmo.get_node_3d()
	if cancel:
		zone.radius = restore
		return
	Zone.sized(zone, restore, undo)
