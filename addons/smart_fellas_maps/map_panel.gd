@tool
extends VBoxContainer
## The Map panel: the map's name and size, who may play on it, what lives there, and buttons that drop
## spawn points and food in. Every change goes through Godot's undo and is saved with the scene. What
## the game would refuse is said here as it's typed, and Export won't write it. All of it scrolls, so
## nothing is ever cut off, under a banner that says when a newer add-on is out.

const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const Populate := preload("populate.gd")
const Recipes := preload("recipes.gd")
const SeabedTool := preload("seabed_tool.gd")
const UpdateBanner := preload("update_banner.gd")
const UpdateBox := preload("update_box.gd")

signal placing_asked(kind: String)
signal sculpting_asked(mode: int)
signal flatten_asked
signal sculpting_settings_changed(wide: float, strength: float)

const MINIMUM_WIDTH := 200.0
const PROBLEM_COLOUR := Color(1.0, 0.45, 0.4)
const WARNING_COLOUR := Color(1.0, 0.75, 0.3)
## The most of the panel's height the problems and warnings take before they scroll on their own.
const NOTES_SHARE := 0.3
## Each number a map sets: its property, what a person calls it, its limits and its step.
const NUMBERS := [
	["half_width", "Half width (m)", MapExporter.HALF_WIDTHS, 1.0],
	["ceiling", "Highest swim (m)", MapExporter.CEILINGS, 0.5],
]
const PLAYER_NUMBERS := [
	["fewest_players", "Fewest players", Vector2(2.0, 32.0), 1.0],
	["most_divers", "Most divers (0: by spawn points)", Vector2(0.0, 32.0), 1.0],
	["most_octopuses", "Most octopuses (0: by spawn points)", Vector2(0.0, 32.0), 1.0],
]
const SWITCHES := [
	["hunters", "Shark and eels hunt"],
	["shark", "Big shark"],
	["clownfish", "Clownfish"],
	["whale", "Whale going over"],
	["stingrays", "Stingrays"],
	["goblin_shark", "Goblin shark"],
	["cave_sounds", "Cave sounds"],
]
const LIFE_NUMBERS := [
	["anglers_at_once", "Anglerfish at once", Vector2(1.0, 8.0), 1.0],
]
const SCULPT_MODES := [
	[SeabedTool.Mode.RAISE, "Raise"],
	[SeabedTool.Mode.LOWER, "Lower"],
	[SeabedTool.Mode.SMOOTH, "Smooth"],
	[SeabedTool.Mode.NOISE, "Roughen"],
	[SeabedTool.Mode.SAND, "Sand"],
	[SeabedTool.Mode.ROCK, "Rock"],
]
const PIECE_KINDS := ["spawn_octopus", "spawn_diver", "food_patch"]
## What a map's own model may be made of, in the order the list offers them.
const MODEL_GROUNDS := ["rock", "sand", "silt"]
const WILDLIFE_KINDS := [
	"fish_lionfish", "fish_flounder", "angler", "jellies", "lantern", "goblin_route", "wrasse", "stingray", "eel_hole", "groper_hole",
]

var undo: EditorUndoRedoManager

var _name_edit: LineEdit
var _numbers := {}
var _switches := {}
var _place_buttons := {}
var _counts: Label
var _problems: Label
var _warnings: Label
var _showing := false
var _seed_number: SpinBox
var _populate_said: Label
var _sculpt_buttons := {}
var _sculpt_wide: HSlider
var _sculpt_strength: HSlider
var _populate_surfaces: OptionButton
var _populate_groups := {}
var _models_list: VBoxContainer
## The models the list was last made for, so that it's made again only when they change.
var _models_listed: Array[String] = []
var _update_box: UpdateBox
var _notes_line: HSeparator
var _notes: ScrollContainer


func _ready() -> void:
	name = "Map"
	_update_box = UpdateBox.new()
	_update_box.minimum_width = MINIMUM_WIDTH
	var banner := UpdateBanner.new(_update_box)
	banner.minimum_width = MINIMUM_WIDTH
	add_child(banner)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_add_map_rows(column)
	_add_seabed(column)
	_add_populate(column)
	_add_heading(column, "Game pieces")
	_add_place_buttons(column, PIECE_KINDS)
	_add_heading(column, "Players")
	_add_numbers(column, PLAYER_NUMBERS)
	_add_heading(column, "Sea life")
	for row in SWITCHES:
		_add_switch(column, row[0], row[1])
	_add_numbers(column, LIFE_NUMBERS)
	_add_heading(column, "Wildlife")
	_label(column, "Press one, then click on the map. Drag to scatter fish. Select a jellyfish group or lantern school to set its size in the Inspector.")
	_add_place_buttons(column, WILDLIFE_KINDS)
	# Below every button, so that the buttons don't jump about under the mouse as it changes. Pinned
	# under the scrolling part, it took most of a dock's height and hid the rest (#214).
	column.add_child(HSeparator.new())
	_counts = _label(column, "")
	_add_version(column)
	# What the game would refuse stays in sight under the scrolling part, as it's typed, but takes at
	# most NOTES_SHARE of the panel: past that it scrolls on its own.
	_notes_line = HSeparator.new()
	add_child(_notes_line)
	_notes = ScrollContainer.new()
	_notes.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_notes)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes.add_child(notes)
	_problems = _label(notes, "")
	_problems.add_theme_color_override("font_color", PROBLEM_COLOUR)
	_warnings = _label(notes, "")
	_warnings.add_theme_color_override("font_color", WARNING_COLOUR)
	notes.minimum_size_changed.connect(_fit_notes)
	resized.connect(_fit_notes)
	show_map()


## Gives the problems and warnings the height they need, up to NOTES_SHARE of the panel.
func _fit_notes() -> void:
	var shown := _problems.visible or _warnings.visible
	_notes_line.visible = shown
	_notes.visible = shown
	var needed: float = (_notes.get_child(0) as Control).get_combined_minimum_size().y
	_notes.custom_minimum_size.y = minf(needed, size.y * NOTES_SHARE)


## The "This add-on" part, which the Tools menu's update check asks too.
func update_box() -> UpdateBox:
	return _update_box


func _add_seabed(column: Control) -> void:
	_add_heading(column, "Seabed")
	_add_switch(column, "has_seabed", "Seabed")
	_switches["has_seabed"].tooltip_text = "Untick for a map with no seabed: your pieces and models are the floor, and anyone who falls past them lands at the bottom of the map."
	_label(column, "Press one, then hold the mouse down on the seabed. Esc or the right mouse button stops. Painted pieces and markers move with the ground. Pieces placed by hand stay put, so sculpt first.")
	var grid := GridContainer.new()
	grid.columns = 3
	for row in SCULPT_MODES:
		var button := Button.new()
		button.text = row[1]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(_on_sculpt_toggled.bind(row[0]))
		_sculpt_buttons[row[0]] = button
		grid.add_child(button)
	column.add_child(grid)
	_sculpt_wide = _sculpt_slider(column, "How wide (m)", Vector3(1.0, 25.0, 0.5), 5.0)
	_sculpt_strength = _sculpt_slider(column, "How strong", Vector3(0.05, 1.0, 0.05), 0.5)
	var flatten := Button.new()
	flatten.text = "Flatten"
	flatten.tooltip_text = "Make the seabed flat sand again."
	flatten.pressed.connect(func() -> void: flatten_asked.emit())
	column.add_child(flatten)
	_add_heading(column, "Your own models")
	_label(column, "What each of your own models is made of. Octopuses can bury themselves in sand and silt. Anything else is rock.")
	_models_list = VBoxContainer.new()
	column.add_child(_models_list)


func _sculpt_slider(column: Control, words: String, limits: Vector3, value: float) -> HSlider:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = words
	line.add_child(label)
	var slider := HSlider.new()
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = limits.z
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(_value: float) -> void: sculpting_settings_changed.emit(_sculpt_wide.value, _sculpt_strength.value))
	line.add_child(slider)
	column.add_child(line)
	return slider


func _on_sculpt_toggled(on: bool, mode: int) -> void:
	if _showing:
		return
	sculpting_asked.emit(mode if on else -1)


## The button for the mode being sculpted with stays in, and no other. -1 is none.
func show_sculpting(mode: int) -> void:
	_showing = true
	for key: int in _sculpt_buttons:
		_sculpt_buttons[key].button_pressed = key == mode
	_showing = false


func sculpt_wide() -> float:
	return _sculpt_wide.value


func sculpt_strength() -> float:
	return _sculpt_strength.value


func _add_populate(column: Control) -> void:
	_add_heading(column, "Populate")
	_label(column, "Dresses the whole map with what's ticked, on the seabed and on your pieces and models, walls and overhangs too. Then fix it by hand. Doing it again only redoes its own work in what's ticked: what you placed yourself stays.")
	var groups := GridContainer.new()
	groups.columns = 2
	for group: String in Populate.GROUPS:
		var check := CheckBox.new()
		check.text = Populate.GROUP_WORDS[group]
		check.tooltip_text = Populate.GROUP_TIPS[group]
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.toggled.connect(_on_populate_group_toggled.bind(group))
		_populate_groups[group] = check
		groups.add_child(check)
	column.add_child(groups)
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = "Seed"
	label.tooltip_text = "The same seed on the same map gives the same result."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	_seed_number = SpinBox.new()
	_seed_number.min_value = 1.0
	_seed_number.max_value = 99999.0
	_seed_number.value = 1.0
	line.add_child(_seed_number)
	column.add_child(line)
	var on := HBoxContainer.new()
	var on_label := Label.new()
	on_label.text = "Surfaces"
	on_label.tooltip_text = "Where it dresses: the seabed, your pieces and models, or both."
	on_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	on.add_child(on_label)
	_populate_surfaces = OptionButton.new()
	for words in ["Seabed and meshes", "Seabed only", "Meshes only"]:
		_populate_surfaces.add_item(words)
	_populate_surfaces.item_selected.connect(func(index: int) -> void: _set_property("populate_surfaces", Recipes.SURFACES[index]))
	on.add_child(_populate_surfaces)
	column.add_child(on)
	var buttons := HBoxContainer.new()
	var dress := _populate_button("Populate", "Dress the map from this seed.")
	dress.pressed.connect(_on_populate)
	buttons.add_child(dress)
	var again := _populate_button("Try again", "Redo it from the next seed.")
	again.pressed.connect(_on_try_again)
	buttons.add_child(again)
	var clear := _populate_button("Clear", "Take away what Populate added.")
	clear.pressed.connect(_on_clear_populated)
	buttons.add_child(clear)
	column.add_child(buttons)
	_populate_said = _label(column, "")
	_populate_said.visible = false


func _populate_button(words: String, tip: String) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = tip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _on_populate() -> void:
	var map := _map()
	if map == null:
		return
	_say_populated(Populate.dress(map, int(_seed_number.value), undo, map.populate_surfaces, map.populate_groups))


func _on_try_again() -> void:
	_seed_number.value = _seed_number.value + 1.0 if _seed_number.value < _seed_number.max_value else _seed_number.min_value
	_on_populate()


func _on_clear_populated() -> void:
	var map := _map()
	if map == null:
		return
	_say_populated(Populate.clear(map, undo, map.populate_groups))


func _on_populate_group_toggled(on: bool, group: String) -> void:
	var map := _map()
	if _showing or map == null:
		return
	var groups: Dictionary[String, bool] = map.populate_groups.duplicate()
	groups[group] = on
	_set_property("populate_groups", groups)


func _say_populated(result: Dictionary) -> void:
	_populate_said.text = result["words"]
	_populate_said.visible = true
	show_map()


## Which add-on this is, and updating it.
func _add_version(column: Control) -> void:
	_add_heading(column, "This add-on")
	column.add_child(_update_box)


func _label(column: Control, words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# With no width of its own, a wrapping label behind another tab would ask for the height of the screen.
	label.custom_minimum_size.x = MINIMUM_WIDTH
	column.add_child(label)
	return label


func _add_heading(column: Control, words: String) -> void:
	column.add_child(HSeparator.new())
	var label := _label(column, words)
	label.add_theme_color_override("font_color", get_theme_color("accent_color", "Editor"))


func _add_map_rows(column: Control) -> void:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = "Name"
	line.add_child(label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_typed)
	line.add_child(_name_edit)
	column.add_child(line)
	_add_numbers(column, NUMBERS)


func _add_numbers(column: Control, rows: Array) -> void:
	for row in rows:
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = row[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = MINIMUM_WIDTH * 0.5
		line.add_child(label)
		var number := SpinBox.new()
		var limits: Vector2 = row[2]
		number.min_value = limits.x
		number.max_value = limits.y
		number.step = row[3]
		number.value_changed.connect(_on_number_changed.bind(row[0]))
		line.add_child(number)
		_numbers[row[0]] = number
		column.add_child(line)


func _add_switch(column: Control, key: String, words: String) -> void:
	var check := CheckBox.new()
	check.text = words
	check.toggled.connect(_on_switch_toggled.bind(key))
	_switches[key] = check
	column.add_child(check)


func _add_place_buttons(column: Control, kinds: Array) -> void:
	for kind: String in kinds:
		var button := Button.new()
		button.text = "Add: %s" % MarkerKinds.KINDS[kind]["words"]
		button.tooltip_text = "Press, then click on the map to drop some. Esc or the right mouse button stops."
		button.toggle_mode = true
		button.toggled.connect(_on_place_toggled.bind(kind))
		_place_buttons[kind] = button
		column.add_child(button)


func _map() -> SmartFellasMap:
	return EditorInterface.get_edited_scene_root() as SmartFellasMap


## Makes the panel say what the open map says.
func show_map() -> void:
	var map := _map()
	visible = map != null
	if map == null:
		return
	_showing = true
	if _name_edit.text != map.map_name:
		_name_edit.text = map.map_name
	for key: String in _numbers:
		_numbers[key].value = map.get(key)
	for key: String in _switches:
		_switches[key].button_pressed = map.get(key)
	# The big shark is one of the hunters, so it needs them on.
	_switches["shark"].disabled = not map.hunters
	for group: String in _populate_groups:
		_populate_groups[group].button_pressed = map.populate_groups.get(group, false)
	_populate_surfaces.select(maxi(Recipes.SURFACES.find(map.populate_surfaces), 0))
	_show_models(map)
	_showing = false
	var rules := MapExporter.read_rules(map)
	var sizes := MapExporter.team_sizes(map, rules)
	_counts.text = "%d octopus and %d diver spawn points, %d food patches. Up to %d divers and %d octopuses.\n%d fish, %d anglerfish spots, %d jellyfish in %d groups, %d lantern schools, %d goblin route points.\n%d wrasse spots, %d stingray stops, %d eel holes, %d groper holes." % [
		rules.octopus_spawns.size(), rules.diver_spawns.size(), rules.patches.size(), sizes["divers"], sizes["octopuses"],
		rules.fish.size(), rules.angler_spots.size(), rules.jelly_count(), rules.jellies.size(), rules.lantern_schools.size(), rules.goblin_route.size(),
		rules.haunts["wrasse"].size(), rules.haunts["stingrays"].size(), rules.haunts["eels"].size(), rules.haunts["gropers"].size()
	]
	_problems.text = "\n".join(rules.problems)
	_problems.visible = not rules.problems.is_empty()
	var warned: Array[String] = []
	for warning in rules.warnings:
		warned.append(warning["words"])
	_warnings.text = "\n".join(warned)
	_warnings.visible = not warned.is_empty()
	_fit_notes()


## A line for each of the map's own models, with what it's made of.
func _show_models(map: SmartFellasMap) -> void:
	var paths: Array[String] = []
	for found in MapExporter.own_model_pieces(map):
		# A mesh on its own has no file to mark, so it stays rock.
		if found.has("alone"):
			continue
		if not found["path"] in paths:
			paths.append(found["path"])
	paths.sort()
	if paths != _models_listed:
		_models_listed = paths
		for line in _models_list.get_children():
			_models_list.remove_child(line)
			line.queue_free()
		if paths.is_empty():
			_label(_models_list, "None yet. Drag a .glb from the FileSystem panel into the map.")
		for path in paths:
			var line := HBoxContainer.new()
			var label := Label.new()
			label.text = path.get_file()
			label.tooltip_text = path
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.clip_text = true
			line.add_child(label)
			var choice := OptionButton.new()
			for words in ["Rock", "Sand", "Silt"]:
				choice.add_item(words)
			choice.item_selected.connect(_on_model_ground_chosen.bind(path))
			line.add_child(choice)
			_models_list.add_child(line)
	for index in paths.size():
		var choice := _models_list.get_child(index).get_child(1) as OptionButton
		choice.select(MODEL_GROUNDS.find(map.soft_models.get(paths[index], "rock")))



func _on_model_ground_chosen(index: int, path: String) -> void:
	var map := _map()
	if _showing or map == null:
		return
	var grounds: Dictionary[String, String] = map.soft_models.duplicate()
	if MODEL_GROUNDS[index] == "rock":
		grounds.erase(path)
	else:
		grounds[path] = MODEL_GROUNDS[index]
	_set_property("soft_models", grounds)


## The button for the marker being dropped stays in, and no other.
func show_placing(kind: String) -> void:
	_showing = true
	for key: String in _place_buttons:
		_place_buttons[key].button_pressed = key == kind
	_showing = false


func _on_place_toggled(on: bool, kind: String) -> void:
	if _showing:
		return
	placing_asked.emit(kind if on else "")


func _on_name_typed(words: String) -> void:
	_set_property("map_name", words)


func _on_number_changed(value: float, key: String) -> void:
	_set_property(key, int(value) if key in ["fewest_players", "most_divers", "most_octopuses", "anglers_at_once"] else value)


func _on_switch_toggled(on: bool, key: String) -> void:
	_set_property(key, on)


func _set_property(key: String, value: Variant) -> void:
	var map := _map()
	if _showing or map == null or map.get(key) == value:
		return
	undo.create_action("Set the map's %s" % key.replace("_", " "), UndoRedo.MERGE_ENDS)
	undo.add_do_property(map, key, value)
	undo.add_undo_property(map, key, map.get(key))
	undo.add_do_method(self, "show_map")
	undo.add_undo_method(self, "show_map")
	undo.commit_action()
