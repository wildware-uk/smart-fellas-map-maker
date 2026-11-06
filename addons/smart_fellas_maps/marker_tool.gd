@tool
extends RefCounted
## Drops markers on the map: after a button in the Map panel, a click in the 3D view puts one on the
## surface under the mouse. A click, or a drag that scatters fish, is one step of undo. Esc or the right
## mouse button stops.

const Brush := preload("brush.gd")
const BrushTool := preload("brush_tool.gd")
const MarkerKinds := preload("marker_kinds.gd")

signal view_changed
signal said(words: String)
signal stopped

const SPOT_COLOUR := Color(1.0, 1.0, 1.0, 0.9)
const DOT_RADIUS := 3.5

## A plain UndoRedo or the editor's.
var history: Object
## Asks where the mouse lands, as (camera, mouse) -> what SurfaceFinder.find gives.
var surface_under: Callable
var map: SmartFellasMap
## The kind of marker being dropped, or "" while this tool is off.
var kind := ""

var _hover := {}
var _last_dropped_at := Vector3.INF
var _dragging := false
## What this click or drag has dropped so far, in the map already, and made one step of undo when it ends.
var _dropped: Array[Marker3D] = []


func start(new_kind: String) -> void:
	_end_drag()
	kind = new_kind
	_hover = {}
	view_changed.emit()


func stop() -> void:
	_end_drag()
	if kind.is_empty():
		return
	kind = ""
	_hover = {}
	view_changed.emit()
	stopped.emit()


## Takes one of the 3D view's input events. Gives back whether it used it, so that Godot doesn't.
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if kind.is_empty() or map == null:
		return false
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			stop()
			return true
		# Undo in the middle of a drag takes back the drag: it ends here, and Godot's undo goes on to it.
		if BrushTool.is_undo_key(event):
			_end_drag()
		return false
	if event is InputEventMouseMotion:
		_hover = surface_under.call(camera, event.position)
		view_changed.emit()
		var apart: float = MarkerKinds.KINDS[kind].get("paint_apart", 0.0)
		# The button may have come up over another panel, where this never heard of it.
		if _dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_end_drag()
		if not _dragging:
			return false
		if apart > 0.0 and not _hover.is_empty():
			var at: Vector3 = _hover["at"]
			if at.distance_to(_last_dropped_at) >= apart:
				_drop_at(_hover)
		return true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_end_drag()
			if event.pressed:
				_dragging = true
				_drop_at(surface_under.call(camera, event.position))
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			stop()
			return true
	return false


func _drop_at(hit: Dictionary) -> void:
	if hit.is_empty():
		said.emit("There's no sand or rock under the mouse to drop it on.")
		return
	var at: Vector3 = hit["at"]
	if absf(at.x) > map.half_width or absf(at.z) > map.half_width:
		said.emit("That's outside the map. It reaches %s m each way from the middle." % map.half_width)
		return
	_last_dropped_at = at
	var marker := MarkerKinds.new_marker(map, kind, at, hit["normal"])
	map.add_child(marker, true)
	marker.owner = map
	_dropped.append(marker)
	map.notify_pieces_changed()


## To be called each frame: ends a drag whose button came up where this never heard of it.
func tick() -> void:
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag()


## Makes what this click or drag dropped one step of undo. They're in the map already.
func _end_drag() -> void:
	_dragging = false
	if _dropped.is_empty():
		return
	var dropped := _dropped
	_dropped = []
	# A scene closed in the middle of a drag takes what it dropped with it.
	if not is_instance_valid(map):
		return
	var words := "Add %s" % dropped[0].name if dropped.size() == 1 else "Scatter %d %s" % [dropped.size(), MarkerKinds.KINDS[MarkerKinds.kind_of(dropped[0].name)]["words"].to_lower()]
	history.create_action(words)
	for marker in dropped:
		Brush._on_do(history, map, "add_child", [marker, true])
		Brush._on_do(history, marker, "set_owner", [map])
		Brush._on_undo(history, map, "remove_child", [marker])
		history.add_do_reference(marker)
	Brush._on_do(history, map, "notify_pieces_changed", [])
	Brush._on_undo(history, map, "notify_pieces_changed", [])
	history.commit_action(false)


func draw(overlay: Control, camera: Camera3D) -> void:
	if camera == null or map == null:
		return
	_draw_markers(overlay, camera)
	_draw_route(overlay, camera)
	if kind.is_empty() or _hover.is_empty():
		return
	var at: Vector3 = _hover["at"]
	if camera.is_position_behind(at):
		return
	var colour: Color = MarkerKinds.KINDS[kind]["colour"]
	var middle := camera.unproject_position(at)
	overlay.draw_circle(middle, 6.0, colour)
	overlay.draw_string(ThemeDB.fallback_font, middle + Vector2(12.0, -8.0), MarkerKinds.KINDS[kind]["words"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, SPOT_COLOUR)


## A dot on each marker, the same size however far off it is, so that a map's markers can be seen from afar.
func _draw_markers(overlay: Control, camera: Camera3D) -> void:
	for child in map.get_children():
		var marker := child as Marker3D
		if marker == null or camera.is_position_behind(marker.global_position):
			continue
		var kind_here := MarkerKinds.kind_of(marker.name)
		if not kind_here.is_empty():
			overlay.draw_circle(camera.unproject_position(marker.global_position), DOT_RADIUS, MarkerKinds.KINDS[kind_here]["colour"])


## The goblin shark's loop, point to point and back to the first, in the order of their numbers.
func _draw_route(overlay: Control, camera: Camera3D) -> void:
	var route := MarkerKinds.markers_of(map, "goblin_route")
	if route.size() < 2:
		return
	route.sort_custom(func(one: Node, other: Node) -> bool:
		return MarkerKinds.number_of(one.name, "goblin_route") < MarkerKinds.number_of(other.name, "goblin_route"))
	var colour: Color = MarkerKinds.KINDS["goblin_route"]["colour"]
	for index in route.size():
		var from: Vector3 = route[index].global_position
		var to: Vector3 = route[(index + 1) % route.size()].global_position
		if not camera.is_position_behind(from) and not camera.is_position_behind(to):
			overlay.draw_line(camera.unproject_position(from), camera.unproject_position(to), colour, 2.0, true)
