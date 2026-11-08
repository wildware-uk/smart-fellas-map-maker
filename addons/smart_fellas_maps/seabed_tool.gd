@tool
extends RefCounted
## Sculpts the seabed: raises, lowers, smooths and roughens it, and paints sand or rock. The panel and the
## mouse only say where and when, so that a test can run a stroke with no window. A stroke is one step of
## undo. What stands on the ground, painted pieces and markers, moves with it. Pieces placed by hand stay put.

const Brush := preload("brush.gd")
const BrushTool := preload("brush_tool.gd")
const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const SeabedGrid := preload("seabed_grid.gd")

signal view_changed
signal said(words: String)
signal stopped

enum Mode { RAISE, LOWER, SMOOTH, NOISE, SAND, ROCK }

## How fast each mode works at full strength: metres a second, or a share a second.
const RAISE_SPEED := 3.0
const SMOOTH_SPEED := 6.0
const NOISE_SPEED := 2.5
const NOISE_SIZE := 0.25
## The ground can't come closer to the map's ceiling than this, in metres, so there's room to swim.
const ROOM_UNDER_THE_CEILING := 1.0
## How many metres the ground may rise in a metre. The game refuses a little over this, MAX_SEABED_SLOPE in
## its map checker, so that a map sculpted here never comes to that.
const STEEPEST := 5.0
## How near the ground a painted piece's foot must be to move with it, in metres.
const ON_THE_GROUND := 0.4
const CIRCLE_POINTS := 48
const CIRCLE_COLOUR := Color(0.6, 0.9, 1.0)

var history: Object
## Asks where the mouse lands, as (camera, mouse) -> what SurfaceFinder.find gives.
var surface_under: Callable
## Says the surfaces changed, so that the brush and this look afresh.
var forget_surfaces: Callable
var map: SmartFellasMap
var active := false
var mode := Mode.RAISE
## How far the tool reaches from the mouse, in metres, and how strongly it works, from 0 to 1.
var wide := 5.0
var strength := 0.5

var _hover := {}
var _stroking := false
var _at := Vector3.ZERO
var _grid: RefCounted
var _heights_before := PackedFloat32Array()
var _rock_before := PackedByteArray()
var _side_before := 0
var _reach_before := 0.0
var _middle_before := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _stroke_number := 0
var _told_too_steep := false


func start(new_mode: Mode) -> void:
	end_stroke()
	mode = new_mode
	active = true
	_hover = {}
	view_changed.emit()


func stop() -> void:
	end_stroke()
	if not active:
		return
	active = false
	_hover = {}
	view_changed.emit()
	stopped.emit()


## Takes one of the 3D view's input events. Gives back whether it used it, so that Godot doesn't.
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not active or map == null:
		return false
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			stop()
			return true
		# Undo in the middle of a stroke takes back that stroke: it ends here, and Godot's undo goes on to it.
		if BrushTool.is_undo_key(event):
			end_stroke()
		return false
	if event is InputEventMouseMotion:
		_hover = surface_under.call(camera, event.position)
		if not _hover.is_empty():
			_at = _hover["at"]
		view_changed.emit()
		return _stroking
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit: Dictionary = surface_under.call(camera, event.position)
				if hit.is_empty():
					said.emit("There's no seabed under the mouse to sculpt.")
				else:
					_at = hit["at"]
					begin_stroke()
			else:
				end_stroke()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			stop()
			return true
	return false


## To be called each frame while a stroke is on, with how long the last frame took.
func tick(delta: float) -> void:
	if not _stroking:
		return
	if _lost_its_place():
		_stroking = false
		_grid = null
		if forget_surfaces.is_valid():
			forget_surfaces.call()
		said.emit("Undo came in the middle of a stroke, so that stroke was dropped.")
		view_changed.emit()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		end_stroke()
		return
	work_at(_at, delta)


## Whether something else, such as undo, has changed the seabed since this stroke began. Ending the stroke
## then would put back what it had to begin with.
func _lost_its_place() -> bool:
	return map.seabed_side != _grid.side or map.seabed_middle != _grid.centre or map.seabed_heights != _grid.heights or map.seabed_rock != _grid.rock


## Starts a stroke, making the map's grid first if its seabed is flat. A test may call this.
func begin_stroke() -> void:
	_heights_before = map.seabed_heights
	_rock_before = map.seabed_rock
	_side_before = map.seabed_side
	_reach_before = map.seabed_reach
	_middle_before = map.seabed_middle
	if SeabedGrid.of(map) == null:
		_make_the_grid()
	map.seabed_heights = map.seabed_heights.duplicate()
	map.seabed_rock = map.seabed_rock.duplicate()
	_grid = SeabedGrid.of(map)
	_stroke_number += 1
	_told_too_steep = false
	_noise.seed = _stroke_number
	_noise.frequency = NOISE_SIZE
	_stroking = true


## The grid sits over the play area, wherever the box is, so its points are as close as the box's size lets
## them be (#264).
func _make_the_grid() -> void:
	var seabed := map.find_child("Seabed", true, true) as Node3D
	var height := seabed.global_position.y if seabed != null else 0.0
	var box: AABB = map.area_box()
	var reach := maxf(box.size.x, box.size.z) * 0.5
	var side := SeabedGrid.side_for(reach)
	map.seabed_middle = Vector2(box.get_center().x, box.get_center().z)
	map.seabed_reach = reach
	map.seabed_side = side
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	heights.fill(height)
	map.seabed_heights = heights
	var rock := PackedByteArray()
	rock.resize((side - 1) * (side - 1))
	map.seabed_rock = rock


## Works the ground round `at` for `seconds`.
func work_at(at: Vector3, seconds: float) -> void:
	if _grid == null:
		return
	if mode == Mode.SAND or mode == Mode.ROCK:
		_paint_at(at)
		return
	var low: Vector2i = _grid.nearest_point(at.x - wide, at.z - wide)
	var high: Vector2i = _grid.nearest_point(at.x + wide, at.z + wide)
	var side: int = _grid.side
	var heights: PackedFloat32Array = _grid.heights
	var before := heights.duplicate() if mode == Mode.SMOOTH else PackedFloat32Array()
	var top: float = map.area_ceiling() - ROOM_UNDER_THE_CEILING
	var bottom: float = map.area_box().position.y
	for row in range(low.y, high.y + 1):
		for column in range(low.x, high.x + 1):
			var point: Vector3 = _grid.point_at(column, row)
			var away := Vector2(point.x - at.x, point.z - at.z).length()
			if away > wide:
				continue
			var share := smoothstep(wide, wide * 0.3, away) * strength * seconds
			var height: float = point.y
			match mode:
				Mode.RAISE:
					height += RAISE_SPEED * share
				Mode.LOWER:
					height -= RAISE_SPEED * share
				Mode.SMOOTH:
					height = lerpf(height, _average_round(before, column, row, side), minf(SMOOTH_SPEED * share, 1.0))
				Mode.NOISE:
					height += NOISE_SPEED * share * _noise.get_noise_2d(point.x, point.z) * 2.0
			var wanted := clampf(height, bottom, top)
			heights[row * side + column] = _kept_from_being_too_steep(heights, wanted, column, row, side)
	_grid.heights = heights
	map.show_seabed_heights(heights, low, high)


## `height`, as near as it can be to its four neighbours as they stand now. Taken in turn across the whole
## area, this leaves no two neighbours too far apart.
func _kept_from_being_too_steep(heights: PackedFloat32Array, height: float, column: int, row: int, side: int) -> float:
	var most_rise: float = STEEPEST * _grid.spacing
	var kept := height
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var near := Vector2i(column + step.x, row + step.y)
		if near.x < 0 or near.y < 0 or near.x >= side or near.y >= side:
			continue
		kept = clampf(kept, heights[near.y * side + near.x] - most_rise, heights[near.y * side + near.x] + most_rise)
	if absf(kept - height) > 0.001 and not _told_too_steep:
		_told_too_steep = true
		said.emit("That's as steep as the seabed can go, %s m up in a metre. Widen the tool to go higher." % STEEPEST)
	return kept


static func _average_round(heights: PackedFloat32Array, column: int, row: int, side: int) -> float:
	var total := 0.0
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var near := Vector2i(clampi(column + step.x, 0, side - 1), clampi(row + step.y, 0, side - 1))
		total += heights[near.y * side + near.x]
	return total / 4.0


func _paint_at(at: Vector3) -> void:
	var low: Vector2i = _grid.nearest_point(at.x - wide, at.z - wide)
	var high: Vector2i = _grid.nearest_point(at.x + wide, at.z + wide)
	var cells: int = _grid.side - 1
	var rock: PackedByteArray = _grid.rock
	var value := 1 if mode == Mode.ROCK else 0
	for row in range(low.y, mini(high.y + 1, cells)):
		for column in range(low.x, mini(high.x + 1, cells)):
			var point: Vector3 = _grid.point_at(column, row)
			if Vector2(point.x + _grid.spacing * 0.5 - at.x, point.z + _grid.spacing * 0.5 - at.z).length() <= wide:
				rock[row * cells + column] = value
	_grid.rock = rock
	map.show_seabed_rock(rock)


## Ends the stroke, if there is one, as one step of undo, and moves what stands on the ground with it.
func end_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	_commit("Sculpt the seabed")
	_grid = null
	if forget_surfaces.is_valid():
		forget_surfaces.call()
	view_changed.emit()


## Makes the seabed flat sand again, as one step of undo, and moves what stands on it with it.
func flatten() -> void:
	end_stroke()
	if map == null or map.seabed_side == 0:
		return
	_heights_before = map.seabed_heights
	_rock_before = map.seabed_rock
	_side_before = map.seabed_side
	_reach_before = map.seabed_reach
	_middle_before = map.seabed_middle
	map.seabed_side = 0
	map.seabed_reach = 0.0
	map.seabed_middle = Vector2.ZERO
	map.seabed_heights = PackedFloat32Array()
	map.seabed_rock = PackedByteArray()
	_commit("Flatten the seabed")
	if forget_surfaces.is_valid():
		forget_surfaces.call()
	view_changed.emit()


## Makes what has changed since `_heights_before` one step of undo, with the pieces and markers moved.
func _commit(words: String) -> void:
	var after_heights := map.seabed_heights
	var after_rock := map.seabed_rock
	var after_side := map.seabed_side
	var after_reach := map.seabed_reach
	var after_middle := map.seabed_middle
	var before: RefCounted = null
	if _side_before >= 2:
		before = SeabedGrid.from_numbers(_reach_before, _side_before, _heights_before, _rock_before, _middle_before)
	var after: RefCounted = SeabedGrid.of(map)
	var flat := _flat_height()
	history.create_action(words)
	history.add_do_property(map, "seabed_side", after_side)
	history.add_undo_property(map, "seabed_side", _side_before)
	history.add_do_property(map, "seabed_reach", after_reach)
	history.add_undo_property(map, "seabed_reach", _reach_before)
	history.add_do_property(map, "seabed_middle", after_middle)
	history.add_undo_property(map, "seabed_middle", _middle_before)
	history.add_do_property(map, "seabed_heights", after_heights)
	history.add_undo_property(map, "seabed_heights", _heights_before)
	history.add_do_property(map, "seabed_rock", after_rock)
	history.add_undo_property(map, "seabed_rock", _rock_before)
	# Populate's list holds the same pieces as the map's, and must go on matching them.
	history.add_do_property(map, "painted", _moved_with_the_ground(map.painted, before, after, flat))
	history.add_undo_property(map, "painted", map.painted)
	history.add_do_property(map, "populated", _moved_with_the_ground(map.populated, before, after, flat))
	history.add_undo_property(map, "populated", map.populated)
	for child in map.get_children():
		var marker := child as Marker3D
		if marker != null:
			_move_marker(marker, _ground_on(before, marker.global_position, flat), _ground_on(after, marker.global_position, flat))
	history.commit_action()


func _move_marker(marker: Marker3D, then: float, now: float) -> void:
	if then == now:
		return
	var moved := marker.position + Vector3.UP * (now - then)
	history.add_do_property(marker, "position", moved)
	history.add_undo_property(marker, "position", marker.position)
	# Populate knows its own markers by being where it put them, so this isn't a move by hand.
	if marker.has_meta(MarkerKinds.OWN_MARK) and marker.position.distance_to(marker.get_meta(MarkerKinds.OWN_MARK)) < MarkerKinds.STILL_THERE:
		Brush._on_do(history, marker, "set_meta", [MarkerKinds.OWN_MARK, moved])
		Brush._on_undo(history, marker, "set_meta", [MarkerKinds.OWN_MARK, marker.position])


func _flat_height() -> float:
	var seabed := map.find_child("Seabed", true, true) as Node3D
	return seabed.global_position.y if seabed != null else 0.0


static func _ground_on(grid: RefCounted, at: Vector3, flat: float) -> float:
	return grid.height_at(at.x, at.z) if grid != null else flat


## These pieces, with those that stood on the ground moved with it.
static func _moved_with_the_ground(pieces: Dictionary[String, PackedFloat32Array], before: RefCounted, after: RefCounted, flat: float) -> Dictionary[String, PackedFloat32Array]:
	var moved: Dictionary[String, PackedFloat32Array] = {}
	for kit: String in pieces:
		var values: PackedFloat32Array = pieces[kit].duplicate()
		for first in range(0, values.size(), Kit.STRIDE):
			var at := Vector3(values[first], values[first + 1], values[first + 2])
			var then := _ground_on(before, at, flat)
			if absf(at.y - then) <= ON_THE_GROUND:
				values[first + 1] += _ground_on(after, at, flat) - then
		moved[kit] = values
	return moved


func draw(overlay: Control, camera: Camera3D) -> void:
	if not active or camera == null or _hover.is_empty():
		return
	var at: Vector3 = _hover["at"]
	var line := PackedVector2Array()
	var grid: RefCounted = SeabedGrid.of(map)
	for index in CIRCLE_POINTS + 1:
		var angle := TAU * index / CIRCLE_POINTS
		var point := at + Vector3(cos(angle), 0.0, sin(angle)) * wide
		point.y = grid.height_at(point.x, point.z) if grid != null else at.y
		if not camera.is_position_behind(point):
			line.append(camera.unproject_position(point))
	if line.size() > 1:
		overlay.draw_polyline(line, Color(0.0, 0.0, 0.0, 0.5), 4.0, true)
		overlay.draw_polyline(line, CIRCLE_COLOUR, 2.0, true)
