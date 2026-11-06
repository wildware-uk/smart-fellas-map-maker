@tool
extends VBoxContainer
## The Water panel: the map's depth with its quick choices, and any one value set by hand. Every change
## shows at once, goes through Godot's undo, and is saved with the scene for Export to write to map.ron.

const WaterLook := preload("water/water_look.gd")

const QUICK_CHOICES := [
	["Shallow", WaterLook.SHALLOW_DEPTH],
	["Deep", WaterLook.DEEP_DEPTH],
	["Midnight", WaterLook.MIDNIGHT_DEPTH],
]
## Each value a map can set by hand, what a person calls it, and how finely to step it.
const ROWS := [
	["visibility", "How far you can see (m)", 1.0],
	["sun", "Sun (lux)", 100.0],
	["fill", "Light in the shadows", 10.0],
	["shafts", "Light shafts", 0.5],
	["caustics", "Caustics", 0.05],
	["surface", "Surface overhead", 0.05],
]

const MINIMUM_WIDTH := 200.0

var undo: EditorUndoRedoManager

var _depth_slider: HSlider
var _depth_number: SpinBox
var _haze_on: CheckBox
var _haze_colour: ColorPickerButton
var _rows := {}
var _summary: Label
var _showing := false


func _ready() -> void:
	name = "Water"
	_add_quick_choices()
	_add_depth()
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# With no width of its own, a wrapping label behind another tab would ask for the height of the screen.
	_summary.custom_minimum_size.x = MINIMUM_WIDTH
	add_child(_summary)
	add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Set by hand, in place of what the depth gives:"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size.x = MINIMUM_WIDTH
	add_child(heading)
	_add_haze_row()
	for row in ROWS:
		_add_row(row[0], row[1], row[2])
	show_map()


func _add_quick_choices() -> void:
	var line := HBoxContainer.new()
	for choice in QUICK_CHOICES:
		var button := Button.new()
		button.text = choice[0]
		button.tooltip_text = "%s m down." % choice[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_depth.bind(choice[1]))
		line.add_child(button)
	add_child(line)


func _add_depth() -> void:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = "Depth (m)"
	line.add_child(label)
	_depth_slider = HSlider.new()
	_depth_slider.min_value = WaterLook.DEPTHS.x
	_depth_slider.max_value = WaterLook.DEPTHS.y
	_depth_slider.step = 1.0
	_depth_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depth_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_depth_slider.value_changed.connect(_set_depth)
	line.add_child(_depth_slider)
	_depth_number = SpinBox.new()
	_depth_number.min_value = WaterLook.DEPTHS.x
	_depth_number.max_value = WaterLook.DEPTHS.y
	_depth_number.step = 1.0
	_depth_number.value_changed.connect(_set_depth)
	line.add_child(_depth_number)
	add_child(line)


func _add_haze_row() -> void:
	var line := HBoxContainer.new()
	_haze_on = CheckBox.new()
	_haze_on.text = "Haze colour"
	_haze_on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_haze_on.toggled.connect(func(_on: bool) -> void: _haze_changed())
	line.add_child(_haze_on)
	_haze_colour = ColorPickerButton.new()
	_haze_colour.edit_alpha = false
	_haze_colour.custom_minimum_size = Vector2(60.0, 0.0)
	_haze_colour.color_changed.connect(func(_colour: Color) -> void: _haze_changed())
	line.add_child(_haze_colour)
	add_child(line)


func _add_row(key: String, words: String, step: float) -> void:
	var limits: Vector2 = WaterLook.LIMITS[key]
	var line := HBoxContainer.new()
	var on := CheckBox.new()
	on.text = words
	on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(on)
	var number := SpinBox.new()
	number.min_value = limits.x
	number.max_value = limits.y
	number.step = step
	line.add_child(number)
	on.toggled.connect(func(_on: bool) -> void: _row_changed(key))
	number.value_changed.connect(func(_value: float) -> void: _row_changed(key))
	_rows[key] = {"on": on, "number": number}
	add_child(line)


func _map() -> SmartFellasMap:
	return EditorInterface.get_edited_scene_root() as SmartFellasMap


## Makes the panel say what the open map says.
func show_map() -> void:
	var map := _map()
	visible = map != null
	if map == null:
		return
	map.show_water()
	_showing = true
	_depth_slider.value = map.water_depth
	_depth_number.value = map.water_depth
	var look := WaterLook.look_of(map.water_depth, map.water_overrides)
	var overrides: Dictionary = map.water_overrides
	_haze_on.button_pressed = overrides.has("haze")
	_haze_colour.color = Color(look["haze"].x, look["haze"].y, look["haze"].z)
	for key: String in _rows:
		var value: float = overrides.get(key, _given_by_depth(look, key))
		_rows[key]["on"].button_pressed = overrides.has(key)
		_rows[key]["number"].value = value
	_summary.text = _summary_of(look)
	_showing = false


## What the water comes to, for a map maker: what's gone and how far anyone can see.
static func _summary_of(look: Dictionary) -> String:
	var gone: Array[String] = []
	if look["sun_lux"] <= 0.0:
		gone.append("sun")
	if look["shaft_strength"] <= 0.0:
		gone.append("light shafts")
	if look["caustics"] <= 0.0:
		gone.append("caustics")
	if look["surface"] <= 0.0:
		gone.append("surface")
	var words := "You can see about %.0f m." % look["visibility"]
	if not gone.is_empty():
		words += " Gone at this depth: %s." % ", ".join(gone)
	return words


static func _given_by_depth(look: Dictionary, key: String) -> float:
	return look[{"sun": "sun_lux", "fill": "fill_brightness", "shafts": "shaft_strength"}.get(key, key)]


func _set_depth(depth: float) -> void:
	var map := _map()
	if _showing or map == null or map.water_depth == depth:
		return
	undo.create_action("Set the water's depth", UndoRedo.MERGE_ENDS)
	undo.add_do_property(map, "water_depth", depth)
	undo.add_undo_property(map, "water_depth", map.water_depth)
	undo.add_do_method(self, "show_map")
	undo.add_undo_method(self, "show_map")
	undo.commit_action()


func _haze_changed() -> void:
	if _showing:
		return
	var overrides: Dictionary = _map().water_overrides.duplicate()
	if _haze_on.button_pressed:
		overrides["haze"] = _haze_colour.color
	else:
		overrides.erase("haze")
	_set_overrides(overrides)


func _row_changed(key: String) -> void:
	if _showing:
		return
	var overrides: Dictionary = _map().water_overrides.duplicate()
	if _rows[key]["on"].button_pressed:
		overrides[key] = _rows[key]["number"].value
	else:
		overrides.erase(key)
	_set_overrides(overrides)


func _set_overrides(overrides: Dictionary) -> void:
	var map := _map()
	undo.create_action("Set the water's look", UndoRedo.MERGE_ENDS)
	undo.add_do_property(map, "water_overrides", overrides)
	undo.add_undo_property(map, "water_overrides", map.water_overrides)
	undo.add_do_method(self, "show_map")
	undo.add_undo_method(self, "show_map")
	undo.commit_action()
