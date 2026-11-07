@tool
extends RefCounted
## The brush in the 3D view: turns the mouse into strokes, and draws the brush's circle on the surface
## and the map's edge. What a stroke does is in brush.gd.

const Brush := preload("brush.gd")
const Cost := preload("cost.gd")
const Kit := preload("kit.gd")
const SurfaceFinder := preload("surface_finder.gd")

const RAY_LENGTH := 2000.0
const CIRCLE_POINTS := 64
const EDGE_POINTS := 24
const PAINT_COLOUR := Color(0.45, 1.0, 0.85)
const ERASE_COLOUR := Color(1.0, 0.35, 0.3)
const FULL_COLOUR := Color(1.0, 0.75, 0.2)
const EDGE_COLOUR := Color(1.0, 0.85, 0.3, 0.55)
## How often a brush held still goes on growing, in seconds.
const HOLD_EVERY := 0.12
## How much one press of [ or ], or one notch of Ctrl and the wheel, changes how wide the brush is, and
## the least it changes it by: the panel's slider goes in steps of this.
const WIDTH_STEP := 1.15
const LEAST_WIDTH_STEP := 0.25
const WIDEST := 25.0
const NARROWEST := 0.25

## Something changed that the 3D view should redraw.
signal view_changed
## Says something the person should know, in plain words.
signal said(words: String)
## Asks to stop painting, as Esc does.
signal stop_asked

var active := false
var history: Object
## Gives the brush's settings: panel.recipe().
var panel: Object

var _map: SmartFellasMap
var _finder: SurfaceFinder
var _hover := {}
var _erase_held := false
var _stroke: Brush
var _stroke_number := 0
var _last_hit := {}
var _since_grown := 0.0
var _warned_close := false
var _told_full := false
var _pieces_told := 0


## Whether this key is undo or redo, which mustn't fall in the middle of a stroke.
static func is_undo_key(event: InputEventKey) -> bool:
	return event.pressed and not event.echo and event.is_command_or_control_pressed() and event.keycode in [KEY_Z, KEY_Y]


func is_idle() -> bool:
	return _stroke == null


## The map being edited has changed, or something on it has: rays must look again.
func forget_surfaces() -> void:
	if _stroke == null:
		_finder = null


func set_map(map: SmartFellasMap) -> void:
	end_stroke()
	_map = map
	_finder = null
	_hover = {}
	_warned_close = false
	_told_full = false


func _surfaces() -> SurfaceFinder:
	if _finder == null and _map != null:
		_finder = SurfaceFinder.new(_map)
	return _finder


## What's under the mouse in the 3D view, as SurfaceFinder.find gives it.
func surface_under(camera: Camera3D, mouse: Vector2) -> Dictionary:
	if _map == null:
		return {}
	var from := camera.project_ray_origin(mouse)
	return _surfaces().find(from, from + camera.project_ray_normal(mouse) * RAY_LENGTH)


## Takes one of the 3D view's input events. Gives back whether the brush used it, so that Godot doesn't.
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not active or _map == null:
		return false
	if event is InputEventKey:
		return _handle_key(event)
	if event is InputEventMouseMotion:
		_erase_held = event.shift_pressed
		var hit := surface_under(camera, event.position)
		_hover = hit
		view_changed.emit()
		if _stroke != null:
			if not hit.is_empty():
				_stroke_to(hit)
			return true
		return false
	if event is InputEventMouseButton:
		return _handle_button(camera, event)
	return false


func _handle_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_SHIFT:
		_erase_held = event.pressed
		view_changed.emit()
		return false
	if not event.pressed or event.echo:
		return false
	# Undo in the middle of a stroke takes back that stroke: it ends here, and Godot's undo goes on to it.
	if is_undo_key(event):
		end_stroke()
		return false
	match event.keycode:
		KEY_ESCAPE:
			stop_asked.emit()
			return true
		KEY_BRACKETLEFT:
			_change_width(false)
			return true
		KEY_BRACKETRIGHT:
			_change_width(true)
			return true
	return false


func _handle_button(camera: Camera3D, event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := surface_under(camera, event.position)
			_erase_held = event.shift_pressed
			_hover = hit
			if hit.is_empty():
				panel.say("There's no sand or rock under the mouse to paint on.")
			else:
				_start_stroke(hit)
			# Nothing under the mouse is still a click on the brush, not a click to pick something.
			return true
		if _stroke != null:
			end_stroke()
			return true
		return true
	if event.ctrl_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_change_width(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		return true
	return false


func _change_width(wider: bool) -> void:
	panel.set_wide(next_width(panel.recipe()["wide"], wider))
	view_changed.emit()


## The next width up or down from `wide`, far enough to survive the slider's rounding.
static func next_width(wide: float, wider: bool) -> float:
	var next := maxf(wide * WIDTH_STEP, wide + LEAST_WIDTH_STEP) if wider else minf(wide / WIDTH_STEP, wide - LEAST_WIDTH_STEP)
	return clampf(snappedf(next, LEAST_WIDTH_STEP), NARROWEST, WIDEST)


func _start_stroke(hit: Dictionary) -> void:
	var recipe: Dictionary = panel.recipe()
	_stroke = Brush.new()
	_stroke_number += 1
	_pieces_told = 0
	if _erase_held:
		_stroke.start_erasing(_map, recipe, panel.erase_hand_placed(), panel.erase_only_mix(), _surfaces())
	else:
		var why_not := Brush.why_it_cant_paint(_map, recipe)
		if not why_not.is_empty():
			said.emit(why_not)
			_stroke = null
			return
		_stroke.start_painting(_map, recipe, recipe["seed"] * 1000 + _stroke_number, _surfaces())
	_stroke_to(hit)


func _stroke_to(hit: Dictionary) -> void:
	_last_hit = hit
	_since_grown = 0.0
	_stroke.move_to(hit["at"], hit["normal"])
	_tell_about_the_count()


## To be called each frame: grows a stroke that is holding still, and ends one whose button has gone.
func tick(delta: float) -> void:
	if _stroke == null:
		return
	if _stroke.lost_its_place():
		_stroke.abandon()
		_stroke = null
		_finder = null
		panel.say("Undo came in the middle of a stroke, so that stroke was dropped.")
		view_changed.emit()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		end_stroke()
		return
	_since_grown += delta
	if _since_grown >= HOLD_EVERY and not _last_hit.is_empty():
		_since_grown = 0.0
		_stroke.hold_at(_last_hit["at"], _last_hit["normal"])
		_tell_about_the_count()


func _tell_about_the_count() -> void:
	if not _stroke.stopped_because.is_empty():
		if not _told_full:
			_told_full = true
			said.emit(_stroke.stopped_because)
		return
	if _stroke.placed == _pieces_told:
		return
	_pieces_told = _stroke.placed
	var pieces: int = Cost.of(_map)["pieces"]
	if pieces >= Cost.PIECES_CLOSE and not _warned_close:
		_warned_close = true
		said.emit("Getting close: this map has %d of the %d pieces a map can place." % [pieces, Cost.PIECES_OVER])
	elif pieces < Cost.PIECES_CLOSE:
		_warned_close = false
	if pieces < Cost.PIECES_OVER:
		_told_full = false


## Ends the stroke, if there is one, as one step of undo.
func end_stroke() -> void:
	if _stroke == null:
		return
	var stroke := _stroke
	_stroke = null
	var recipe: Dictionary = panel.recipe()
	var words := "Erase pieces" if stroke.removed > 0 else "Paint %s" % recipe["name"]
	stroke.finish(history, words)
	if stroke.placed == 0 and stroke.removed == 0 and stroke.stopped_because.is_empty():
		panel.say("Nothing grew there: it's as thick as this brush makes it, or Where it grows rules it out.")
	else:
		panel.say(stroke.stopped_because)
	_finder = null
	view_changed.emit()


## Draws the brush's circle lying on the surface, the map's edge, and what the keys do.
func draw(overlay: Control, camera: Camera3D) -> void:
	if not active or _map == null or camera == null:
		return
	_draw_edge(overlay, camera)
	if _hover.is_empty():
		return
	var colour := ERASE_COLOUR if _erase_held else PAINT_COLOUR
	if not _erase_held and Cost.of(_map)["pieces"] >= Cost.PIECES_OVER:
		colour = FULL_COLOUR
	var at: Vector3 = _hover["at"]
	var normal: Vector3 = _hover["normal"]
	var wide: float = panel.recipe()["wide"]
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var ahead := normal.cross(side)
	var points := PackedVector2Array()
	for index in CIRCLE_POINTS + 1:
		var angle := TAU * index / CIRCLE_POINTS
		var on_disc := at + (side * cos(angle) + ahead * sin(angle)) * wide
		var hit := _surfaces().find(on_disc + normal * wide, on_disc - normal * wide)
		var point: Vector3 = hit["at"] if not hit.is_empty() else on_disc
		if camera.is_position_behind(point):
			continue
		points.append(camera.unproject_position(point))
	if points.size() > 1:
		overlay.draw_polyline(points, Color(0.0, 0.0, 0.0, 0.5), 4.0, true)
		overlay.draw_polyline(points, colour, 2.0, true)
	if not camera.is_position_behind(at):
		var middle := camera.unproject_position(at)
		overlay.draw_circle(middle, 2.5, colour)
		if _erase_held:
			overlay.draw_string(ThemeDB.fallback_font, middle + Vector2(10.0, -8.0), "Erasing", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, colour)


func _draw_edge(overlay: Control, camera: Camera3D) -> void:
	var area := _map.area_box()
	var a := area.position
	var b := area.end
	var y: float = _surfaces().sand_height
	var corners := [Vector3(a.x, y, a.z), Vector3(b.x, y, a.z), Vector3(b.x, y, b.z), Vector3(a.x, y, b.z)]
	for side in 4:
		var line := PackedVector2Array()
		for index in EDGE_POINTS + 1:
			var point: Vector3 = (corners[side] as Vector3).lerp(corners[(side + 1) % 4], float(index) / EDGE_POINTS)
			if camera.is_position_behind(point):
				if line.size() > 1:
					overlay.draw_polyline(line, EDGE_COLOUR, 1.5, true)
				line = PackedVector2Array()
				continue
			line.append(camera.unproject_position(point))
		if line.size() > 1:
			overlay.draw_polyline(line, EDGE_COLOUR, 1.5, true)
