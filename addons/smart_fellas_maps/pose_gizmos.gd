@tool
extends EditorNode3DGizmoPlugin
## Draws a dot on the tip of each of a pose's arms, which bends that arm as it's dragged so the tip follows
## the mouse, as the game's pose studio does. The arm the Pose panel's dials bend has a bigger dot. Clicking
## the octopus selects its pose. It lives only in the editor.

const OctopusPose := preload("octopus_pose.gd")

## What each handle is called, by its arm.
const HANDLE_WORDS := "Arm %d"

var undo: EditorUndoRedoManager
## Where the dragged tip was when the drag began, in the world: the mouse moves it in the plane square on to
## the camera through there.
var _drag_from := Vector3.ZERO
var _dragging := -1


func _init() -> void:
	create_handle_material("handles")
	var chosen := StandardMaterial3D.new()
	chosen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chosen.albedo_color = OctopusPose.COLOUR
	chosen.vertex_color_use_as_albedo = false
	chosen.use_point_size = true
	chosen.point_size = 18.0
	chosen.no_depth_test = true
	chosen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chosen.render_priority = StandardMaterial3D.RENDER_PRIORITY_MAX
	add_material("chosen", chosen)


func _get_gizmo_name() -> String:
	return "Smart Fellas octopus pose"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == OctopusPose


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var pose: Node3D = gizmo.get_node_3d()
	var drawing: MeshInstance3D = pose.get_child(0, true) as MeshInstance3D
	if drawing != null and drawing.mesh != null:
		gizmo.add_collision_triangles(drawing.mesh.generate_triangle_mesh())
	var tips: PackedVector3Array = pose.tips
	# While the water plays, the arms move off where their tips rest, so there's nothing steady to drag.
	if tips.is_empty() or pose.playing:
		return
	var others := PackedVector3Array()
	var other_ids := PackedInt32Array()
	for arm in tips.size():
		if arm != pose.chosen_arm:
			others.append(tips[arm])
			other_ids.append(arm)
	gizmo.add_handles(others, get_material("handles", gizmo), other_ids)
	if pose.chosen_arm >= 0 and pose.chosen_arm < tips.size():
		gizmo.add_handles(PackedVector3Array([tips[pose.chosen_arm]]), get_material("chosen", gizmo), PackedInt32Array([pose.chosen_arm]))


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return HANDLE_WORDS % (handle_id + 1)


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().pose.duplicate(true)


## The tip follows the mouse in the plane square on to the camera through where it was when the drag began.
func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var pose: Node3D = gizmo.get_node_3d()
	if handle_id >= pose.tips.size():
		return
	var frame := pose.global_transform.orthonormalized()
	if _dragging != handle_id:
		_dragging = handle_id
		_drag_from = frame * pose.tips[handle_id]
		pose.chosen_arm = handle_id
	var facing := Plane(camera.global_basis.z, _drag_from)
	var hit: Variant = facing.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	var placed := OctopusPose.PoseLink.reach(pose.file_pose(), handle_id, frame.affine_inverse() * (hit as Vector3))
	if not placed.has("arm"):
		return
	var changed: Dictionary = pose.pose.duplicate(true)
	var arms: Array = changed.get("arms", OctopusPose.rest_pose()["arms"]).duplicate(true)
	arms[handle_id] = placed["arm"]
	changed["arms"] = arms
	pose.pose = changed
	pose.redraw()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	_dragging = -1
	var pose: Node3D = gizmo.get_node_3d()
	if cancel:
		pose.pose = restore
		return
	undo.create_action("Bend arm %d of %s" % [handle_id + 1, pose.name])
	undo.add_do_property(pose, "pose", pose.pose.duplicate(true))
	undo.add_undo_property(pose, "pose", restore)
	undo.commit_action(false)
