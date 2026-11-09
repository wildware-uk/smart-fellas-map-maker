@tool
extends RefCounted
## Drops markers on the map, Populate's zones and trigger zones: after a button in the Map panel, a click in
## the 3D view puts one on the surface under the mouse. A click, or a drag that scatters fish, is one step of
## undo. Esc or the right mouse button stops, and so does dropping a zone.

const Brush := preload("brush.gd")
const BrushTool := preload("brush_tool.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const Zone := preload("populate_zone.gd")
const TriggerZone := preload("trigger_zone.gd")

signal view_changed
signal said(words: String)
signal stopped
## A zone was dropped: the tool has stopped, so that the zone can be selected to drag and size.
signal zone_dropped(zone: Node3D)

const SPOT_COLOUR := Color(1.0, 1.0, 1.0, 0.9)
const DOT_RADIUS := 3.5
const ZONE_WORDS_SIZE := 15

## A plain UndoRedo or the editor's.
var history: Object
## Asks where the mouse lands, as (camera, mouse) -> what SurfaceFinder.find gives.
var surface_under: Callable
var map: SmartFellasMap
## The kind of marker being dropped, Zone.placing of a zone's, TriggerZone.PLACING, or "" while this tool
## is off.
var kind := ""

var _hover := {}
var _last_dropped_at := Vector3.INF
var _dragging := false
## What this click or drag has dropped so far, in the map already, and made one step of undo when it ends.
var _dropped: Array[Node3D] = []


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
		var apart: float = 0.0 if _drops_zone() else MarkerKinds.KINDS[kind].get("paint_apart", 0.0)
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
				if _drops_zone() and not _dropped.is_empty():
					var zone := _dropped[0]
					stop()
					zone_dropped.emit(zone)
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			stop()
			return true
	return false


func _drop_at(hit: Dictionary) -> void:
	if hit.is_empty():
		said.emit("There's no seabed, rock or model under the mouse to drop it on.")
		return
	var at: Vector3 = hit["at"]
	var area: AABB = map.area_box()
	if at.x < area.position.x or at.x > area.end.x or at.z < area.position.z or at.z > area.end.z:
		said.emit("That's outside the play area. Drop it inside the blue box, or move the box.")
		return
	_last_dropped_at = at
	var dropped: Node3D
	if kind == TriggerZone.PLACING:
		dropped = TriggerZone.new_zone(map.global_transform.affine_inverse() * at)
	elif _zone_kind() >= 0:
		dropped = Zone.new_zone(map, _zone_kind(), map.global_transform.affine_inverse() * at)
	else:
		dropped = MarkerKinds.new_marker(map, kind, at, hit["normal"])
	map.add_child(dropped, true)
	dropped.owner = map
	_dropped.append(dropped)
	map.notify_pieces_changed()


## The kind of Populate zone being dropped, or -1 for anything else.
func _zone_kind() -> int:
	return Zone.kind_placed(kind)


## Whether what's being dropped is a zone, of Populate's or a trigger zone, which goes one at a time.
func _drops_zone() -> bool:
	return kind == TriggerZone.PLACING or _zone_kind() >= 0


## What a person calls what's being dropped, and the colour it's shown in.
func _words() -> String:
	if kind == TriggerZone.PLACING:
		return TriggerZone.WORDS
	return Zone.KINDS[_zone_kind()]["words"] if _zone_kind() >= 0 else MarkerKinds.KINDS[kind]["words"]


func _colour() -> Color:
	if kind == TriggerZone.PLACING:
		return TriggerZone.COLOUR
	return Zone.KINDS[_zone_kind()]["colour"] if _zone_kind() >= 0 else MarkerKinds.KINDS[kind]["colour"]


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
	var words := "Add %s" % dropped[0].name if dropped.size() == 1 else "Scatter %d %s" % [dropped.size(), _words().to_lower()]
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
	_draw_zones(overlay, camera)
	_draw_route(overlay, camera)
	if kind.is_empty() or _hover.is_empty():
		return
	var at: Vector3 = _hover["at"]
	if camera.is_position_behind(at):
		return
	var middle := camera.unproject_position(at)
	overlay.draw_circle(middle, 6.0, _colour())
	overlay.draw_string(ThemeDB.fallback_font, middle + Vector2(12.0, -8.0), _words(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, SPOT_COLOUR)


## A dot on each marker, the same size however far off it is, so that a map's markers can be seen from afar.
func _draw_markers(overlay: Control, camera: Camera3D) -> void:
	for marker in dotted_markers():
		if not camera.is_position_behind(marker.global_position):
			var colour: Color = MarkerKinds.KINDS[MarkerKinds.kind_of(marker.name)]["colour"]
			overlay.draw_circle(camera.unproject_position(marker.global_position), DOT_RADIUS, colour)


## The markers that get a dot: the map's own, not one hidden with its eye, which Export leaves out.
func dotted_markers() -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for child in map.get_children():
		var marker := child as Marker3D
		if marker != null and not MapExporter.hidden_by_eye(marker) and not MarkerKinds.kind_of(marker.name).is_empty():
			found.append(marker)
	return found


## What each of Populate's zones is, and each trigger zone's name for the map's script, written at its
## middle, so that they can be told apart.
func _draw_zones(overlay: Control, camera: Camera3D) -> void:
	for zone in Zone.nodes_in(map):
		_draw_words_at(overlay, camera, zone.global_position, Zone.KINDS[zone.kind]["words"], Zone.KINDS[zone.kind]["colour"])
	for zone in TriggerZone.nodes_in(map):
		_draw_words_at(overlay, camera, zone.global_position, String(zone.name), TriggerZone.COLOUR)


func _draw_words_at(overlay: Control, camera: Camera3D, at: Vector3, words: String, colour: Color) -> void:
	if camera.is_position_behind(at):
		return
	var font := ThemeDB.fallback_font
	var middle := camera.unproject_position(at) - font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ZONE_WORDS_SIZE) * 0.5
	overlay.draw_string_outline(font, middle, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ZONE_WORDS_SIZE, 4, Color.BLACK)
	overlay.draw_string(font, middle, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ZONE_WORDS_SIZE, colour)


## The goblin shark's loop, point to point and back to the first, in the order of their numbers.
func _draw_route(overlay: Control, camera: Camera3D) -> void:
	var route := route_points()
	if route.size() < 2:
		return
	var colour: Color = MarkerKinds.KINDS["goblin_route"]["colour"]
	for index in route.size():
		var from: Vector3 = route[index].global_position
		var to: Vector3 = route[(index + 1) % route.size()].global_position
		if not camera.is_position_behind(from) and not camera.is_position_behind(to):
			overlay.draw_line(camera.unproject_position(from), camera.unproject_position(to), colour, 2.0, true)


## The goblin shark's route points in the map, in the order of their numbers: not one hidden with the eye,
## or in a hidden group, which Export leaves out.
func route_points() -> Array[Node]:
	var route: Array[Node] = []
	for point in MarkerKinds.markers_of(map, "goblin_route"):
		if not MapExporter.hidden_in(point, map):
			route.append(point)
	route.sort_custom(func(one: Node, other: Node) -> bool:
		return MarkerKinds.number_of(one.name, "goblin_route") < MarkerKinds.number_of(other.name, "goblin_route"))
	return route
