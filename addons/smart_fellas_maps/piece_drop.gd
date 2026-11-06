@tool
extends Control
## Lies over one 3D view, and only wakes while a piece is being dragged from the Pieces panel. Godot's
## own drop asks physics where a thing lands, and the editor has none, so this lands it on the surface
## under the mouse, facing out from it.

const Kit := preload("kit.gd")
const PiecesPanel := preload("pieces_panel.gd")

## Asks where the mouse lands, as (camera, mouse) -> what SurfaceFinder.find gives.
var surface_under: Callable
## Gives the map being edited.
var map_getter: Callable
var history: EditorUndoRedoManager
var viewport_3d: SubViewport

var _ghost: Node3D
var _ghost_kit := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A piece is being dragged from the panel: this takes the mouse from the 3D view until it's dropped.
func wake() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func sleep() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lose_ghost()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_lose_ghost()


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or data.get("type", "") != PiecesPanel.DRAG_KIND:
		return false
	var map: SmartFellasMap = map_getter.call()
	if map == null:
		return false
	var hit: Dictionary = surface_under.call(viewport_3d.get_camera_3d(), at)
	if hit.is_empty():
		_lose_ghost()
		return false
	_show_ghost(map, data["kit"], hit)
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	var map: SmartFellasMap = map_getter.call()
	var hit: Dictionary = surface_under.call(viewport_3d.get_camera_3d(), at)
	_lose_ghost()
	if map == null or hit.is_empty():
		return
	var kit: String = data["kit"]
	var scene: PackedScene = load(Kit.path_of(kit))
	var piece: Node3D = scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	piece.name = Kit.plain_name(kit)
	# Places in the world, which a map's top node may have moved away from.
	piece.transform = map.global_transform.affine_inverse() * Kit.place_of(hit["at"], hit["normal"], 0.0, 1.0)
	history.create_action("Place %s" % Kit.plain_name(kit))
	history.add_do_method(map, "add_child", piece, true)
	history.add_do_method(piece, "set_owner", map)
	history.add_do_method(map, "notify_pieces_changed")
	history.add_do_reference(piece)
	history.add_undo_method(map, "remove_child", piece)
	history.add_undo_method(map, "notify_pieces_changed")
	history.commit_action()
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(piece)


func _show_ghost(map: SmartFellasMap, kit: String, hit: Dictionary) -> void:
	if _ghost == null or _ghost_kit != kit:
		_lose_ghost()
		var scene: PackedScene = load(Kit.path_of(kit))
		_ghost = scene.instantiate()
		_ghost_kit = kit
		# Internal and with no owner, so that it's never saved and Export never sees it.
		map.add_child(_ghost, false, Node.INTERNAL_MODE_BACK)
	_ghost.global_transform = Kit.place_of(hit["at"], hit["normal"], 0.0, 1.0)


func _lose_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_kit = ""
