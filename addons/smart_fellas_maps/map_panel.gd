@tool
extends VBoxContainer
## The Map panel: the map's name and size, who may play on it, what lives there, and buttons that drop
## spawn points and food in. Every change goes through Godot's undo and is saved with the scene. What
## the game would refuse is said here as it's typed, and Export won't write it. All of it scrolls, so
## nothing is ever cut off, under a banner that says when a newer add-on is out.

const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const PlayArea := preload("play_area.gd")
const PopulateGroups := preload("populate_groups.gd")
const Recipes := preload("recipes.gd")
## What the Performance part says before the open map has been graded.
const NOT_GRADED := "Not graded yet. Press Grade it, or Export Map or Test Map, and the game grades it."
const SeabedTool := preload("seabed_tool.gd")
const UpdateBanner := preload("update_banner.gd")
const UpdateBox := preload("update_box.gd")
const Zone := preload("populate_zone.gd")
const TriggerZone := preload("trigger_zone.gd")

signal placing_asked(kind: String)
signal sculpting_asked(mode: int)
signal flatten_asked
signal sculpting_settings_changed(wide: float, strength: float)
signal play_area_toggled(on: bool)
## The map maker pressed Grade it: the plugin exports the map somewhere of its own and has the game grade it.
signal grade_asked

const MINIMUM_WIDTH := 200.0
const PROBLEM_COLOUR := Color(1.0, 0.45, 0.4)
const WARNING_COLOUR := Color(1.0, 0.75, 0.3)
## The most of the panel's height the problems and warnings take before they scroll on their own.
const NOTES_SHARE := 0.3
## Each number a map sets: its property, what a person calls it, its limits and its step. These are the
## play area box's: where the middle of its floor is, and its size.
const NUMBERS := [
	["area_x", "Play area middle, X (m)", Vector2(-MapExporter.SCENERY_REACH, MapExporter.SCENERY_REACH), 0.5],
	["area_z", "Play area middle, Z (m)", Vector2(-MapExporter.SCENERY_REACH, MapExporter.SCENERY_REACH), 0.5],
	["area_floor", "Floor height (m)", Vector2(-MapExporter.SCENERY_REACH, MapExporter.SCENERY_REACH), 0.5],
	["area_width", "Width, X (m)", MapExporter.SIDES, 1.0],
	["area_depth", "Depth, Z (m)", MapExporter.SIDES, 1.0],
	["area_height", "Height (m)", MapExporter.HEIGHTS, 0.5],
]
const PLAYER_NUMBERS := [
	["fewest_players", "Fewest players", Vector2(2.0, 32.0), 1.0],
	["most_divers", "Divers it's made for (0: by spawn points)", Vector2(0.0, 32.0), 1.0],
	["most_octopuses", "Octopuses it's made for (0: by spawn points)", Vector2(0.0, 32.0), 1.0],
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
	["anglers_at_once", "Anglerfish at once", Vector2(1.0, MapExporter.MOST_ANGLERS_AT_ONCE), 1.0],
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
const GROUND_WORDS := ["Rock", "Sand", "Silt"]
const MODEL_CRAWLS := ["size", "always", "never"]
## The widest a model's name is kept on its line in the list, in pixels before the editor's scale: past
## it, it's cut short with "…", and its whole name is in its tip.
const MOST_NAME_WIDTH := 260.0
const CRAWL_WORDS := ["By size", "Crawl on", "Go round"]
const BLEND_TIP := "Whether it blends into the ground it stands on, as the game's own rocks do: the sand or silt round it creeps up its base and fades out, so it looks settled in, not set down on top."
const CRAWL_TIP := "Whether octopuses crawl on it or go round it. By size, they go round one under %s m across and tall, as they go round a coral or a bush, and crawl on anything bigger, and on sand and silt." % MapExporter.SMALL_GROWTH_MOST
const WILDLIFE_KINDS := [
	"fish_lionfish", "fish_flounder", "angler", "jellies", "lantern", "goblin_route", "wrasse", "stingray", "eel_hole", "groper_hole",
	"garden_eels",
]

var undo: EditorUndoRedoManager
## Gives what PlayArea.gather finds in a map, kept between changes: the play area's outlines share it.
var gathered: Callable = func(map: SmartFellasMap) -> Dictionary: return PlayArea.gather(map)

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
## The one pick list every model's line opens. A list of its own on each line took half a second to make on a
## map of hundreds of models.
var _ground_menu: PopupMenu
var _crawl_menu: PopupMenu
## The lines for the one model selected in the scene, above the list: its name, wrapped, and its choice.
var _selected_line: VBoxContainer
var _selected_label: Label
var _selected_choice: OptionButton
var _selected_crawl: OptionButton
var _selected_blend: CheckBox
## The one node selected in the scene, if one is. Untyped, as it may have been freed since.
var _selected: Variant = null
var _update_box: UpdateBox
var _notes_line: HSeparator
var _notes: ScrollContainer
var _show_area: CheckBox
var _area_shown := true
var _fit_said: Label
var _grade_said: Label
var _grade_button: Button
## The map the grade shown is for, so another map opened doesn't show it. Untyped, as it may have been freed.
var _graded: Variant = null
## Whether show_map left the map unread while the panel's tab was hidden behind Paint or Water. Reading it
## takes a tenth of a second or more on a map of thousands of pieces, which every map's opening paid (#291).
var _unread := false


func _ready() -> void:
	name = "Map"
	_update_box = UpdateBox.new()
	_update_box.minimum_width = MINIMUM_WIDTH
	var banner := UpdateBanner.new(_update_box)
	banner.minimum_width = MINIMUM_WIDTH
	add_child(banner)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A scroll bar that came and went would narrow the column and rewrap its words, which could make it
	# tall enough to need the bar again, back and forth until the editor ran out of room for messages.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_add_map_rows(column)
	_add_seabed(column)
	_add_populate(column)
	_add_own_models(column)
	_add_heading(column, "Game pieces")
	_add_place_buttons(column, PIECE_KINDS)
	_add_heading(column, "Players")
	_label(column, "How many the map is made for. They aren't limits: a lobby can go over them, and the game warns it may feel crowded.")
	_add_numbers(column, PLAYER_NUMBERS)
	_add_heading(column, "Sea life")
	for row in SWITCHES:
		_add_switch(column, row[0], row[1])
	_add_numbers(column, LIFE_NUMBERS)
	_add_heading(column, "Wildlife")
	_label(column, "Press one, then click on the map. Drag to scatter fish. Select a jellyfish group or lantern school to set its size in the Inspector.")
	_add_place_buttons(column, WILDLIFE_KINDS)
	_add_script_zones(column)
	# Below every button, so that the buttons don't jump about under the mouse as it changes. Pinned
	# under the scrolling part, it took most of a dock's height and hid the rest (#214).
	column.add_child(HSeparator.new())
	_counts = _label(column, "")
	_add_performance(column)
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
	var dock := get_parent() as Control
	if dock != null:
		dock.visibility_changed.connect(_on_tab_shown)
	show_map()


func _tab_shown() -> bool:
	var dock := get_parent() as Control
	return dock == null or dock.is_visible_in_tree()


func _on_tab_shown() -> void:
	if _unread and _tab_shown():
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


## What each of the map's own models is made of. Under Populate, as a map made of its own meshes can list
## hundreds, which would push Populate out of reach.
func _add_own_models(column: Control) -> void:
	_add_heading(column, "Your own models")
	_label(column, "What each of your own models and meshes is made of, whether octopuses crawl on it or go round it, and whether it blends into the ground. Octopuses can bury themselves in sand and silt, and Populate grows sand's plants there. Anything else is rock. By size, octopuses go round a small model, as they go round a coral, and crawl on a bigger one. Blend lets the ground creep up its base, as it does on the game's own rocks. Select one in the scene to set it here too.")
	_selected_line = VBoxContainer.new()
	_selected_label = _label(_selected_line, "")
	_selected_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_selected_choice = _ground_choice()
	_selected_choice.size_flags_horizontal = Control.SIZE_SHRINK_END
	_selected_choice.item_selected.connect(func(index: int) -> void: _on_model_ground_chosen(index, str(_selected_choice.get_meta("line", ""))))
	_selected_line.add_child(_selected_choice)
	_selected_crawl = _crawl_choice()
	_selected_crawl.size_flags_horizontal = Control.SIZE_SHRINK_END
	_selected_crawl.item_selected.connect(func(index: int) -> void: _on_model_crawl_chosen(index, str(_selected_crawl.get_meta("line", ""))))
	_selected_line.add_child(_selected_crawl)
	_selected_blend = _blend_box()
	_selected_blend.size_flags_horizontal = Control.SIZE_SHRINK_END
	_selected_blend.toggled.connect(func(on: bool) -> void: _on_model_blend_chosen(on, str(_selected_blend.get_meta("line", ""))))
	_selected_line.add_child(_selected_blend)
	_selected_line.add_child(HSeparator.new())
	_selected_line.visible = false
	column.add_child(_selected_line)
	_models_list = VBoxContainer.new()
	column.add_child(_models_list)
	_ground_menu = PopupMenu.new()
	for words in GROUND_WORDS:
		_ground_menu.add_radio_check_item(words)
	_ground_menu.index_pressed.connect(func(index: int) -> void: _on_model_ground_chosen(index, str(_ground_menu.get_meta("line", ""))))
	add_child(_ground_menu)
	_crawl_menu = PopupMenu.new()
	for words in CRAWL_WORDS:
		_crawl_menu.add_radio_check_item(words)
	_crawl_menu.index_pressed.connect(func(index: int) -> void: _on_model_crawl_chosen(index, str(_crawl_menu.get_meta("line", ""))))
	add_child(_crawl_menu)


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
	_label(column, "Dresses the whole map with what's ticked, on the seabed and on your pieces and models, walls and overhangs too. Then fix it by hand. Doing it again only redoes its own work in what's ticked: what you placed or painted yourself stays.")
	var groups := GridContainer.new()
	groups.columns = 2
	for group: String in PopulateGroups.GROUPS:
		var check := CheckBox.new()
		check.text = PopulateGroups.GROUP_WORDS[group]
		check.tooltip_text = PopulateGroups.GROUP_TIPS[group]
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.toggled.connect(_on_populate_group_toggled.bind(group))
		_populate_groups[group] = check
		groups.add_child(check)
	column.add_child(groups)
	_label(column, "Zones, if you want them: press one, then click on the map to drop it. It's selected then: drag its arrows to move it, and the dot on its rim to size it. Select it in the Scene panel and press Delete to take it away. Populate uses them.")
	var zones := GridContainer.new()
	zones.columns = 2
	for kind: Zone.Kind in Zone.KINDS:
		var button := Button.new()
		button.text = Zone.KINDS[kind]["words"]
		button.tooltip_text = "%s Press, then click on the map to drop one. Esc or the right mouse button stops." % Zone.KINDS[kind]["tip"]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_color_override("font_color", (Zone.KINDS[kind]["colour"] as Color).lightened(0.3))
		button.toggled.connect(_on_place_toggled.bind(Zone.placing(kind)))
		_place_buttons[Zone.placing(kind)] = button
		zones.add_child(button)
	column.add_child(zones)
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
	_say_populated(_populate().dress(map, int(_seed_number.value), undo, map.populate_surfaces, map.populate_groups))


## Populate, loaded on the first press rather than compiled as the editor opens (#291).
static func _populate() -> GDScript:
	return load("res://addons/smart_fellas_maps/populate.gd")


func _on_try_again() -> void:
	_seed_number.value = _seed_number.value + 1.0 if _seed_number.value < _seed_number.max_value else _seed_number.min_value
	_on_populate()


func _on_clear_populated() -> void:
	var map := _map()
	if map == null:
		return
	_say_populated(_populate().clear(map, undo, map.populate_groups))


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


## The map's performance grade, as the game works it out: only after Export, Test Map or Grade it, never as
## the map changes, as it takes the game a moment (#287, #299).
func _add_performance(column: Control) -> void:
	_add_heading(column, "Performance")
	_label(column, "How heavy the map is to run, as the game grades it: Light, Medium, Heavy or Very heavy. It never stops a map: it shows on its Workshop page and in the lobby, so players know what to expect.")
	_grade_said = _label(column, NOT_GRADED)
	_grade_button = Button.new()
	_grade_button.text = "Grade it"
	_grade_button.tooltip_text = "Exports the map to a folder of the add-on's own and asks the game to grade it. Your exported map in the game is left as it was."
	_grade_button.pressed.connect(func() -> void:
		_grade_button.disabled = true
		_grade_said.text = "Grading..."
		grade_asked.emit())
	column.add_child(_grade_button)


## Shows the grade in `result`, from Export, Test Map or Grade it on the open map, or why there's none.
func show_grade(result: Dictionary) -> void:
	_grade_button.disabled = false
	_graded = _map()
	var tester: GDScript = load("res://addons/smart_fellas_maps/map_tester.gd")
	var graded: String = tester.grade_words(result)
	if not graded.is_empty():
		_grade_said.text = graded
		return
	match result.get("state"):
		tester.State.FINE:
			_grade_said.text = "Your Smart Fellas is too old to grade maps. Update it in Steam (on the beta branch, if you play the beta), then press Grade it."
		tester.State.NO_GAME, tester.State.CANT_CHECK, tester.State.NO_MAPS_FOLDER:
			_grade_said.text = "The game grades maps, and it couldn't be asked. Export Map says why."
		_:
			_grade_said.text = "Not graded: the game can't take the map yet. Export Map says why."


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
	_add_play_area(column)


func _add_play_area(column: Control) -> void:
	_show_area = CheckBox.new()
	_show_area.text = "Show play area"
	_show_area.tooltip_text = "Draw the area players can swim in, in the 3D view. It's only drawn here: the game never sees it."
	_show_area.button_pressed = _area_shown
	_show_area.toggled.connect(func(on: bool) -> void: play_area_toggled.emit(on))
	column.add_child(_show_area)
	_label(column, "The play area is the box players swim in: the PlayArea node in the Scene panel. Click its outline in the 3D view to select it, move it with Godot's move tool, and drag the dots on its faces to size it. They snap to 1 m, or 5 m with Ctrl held. Scenery may stand anywhere outside it. Markers outside it are outlined red, as the game refuses them, and so are pieces too far out for Export to take. Pieces wholly outside it are outlined amber: players can see them but never reach them.")
	var fit := Button.new()
	fit.text = "Fit to map"
	fit.tooltip_text = "Make the box hold where players go, the markers, with %s m to spare round them, its floor just under them and the ground, and %s m over the tallest marker, ground or piece wholly inside. Scenery outside never grows it. An older map's square becomes a box." % [PlayArea.FIT_MARGIN, PlayArea.FIT_HEADROOM]
	fit.pressed.connect(_on_fit)
	column.add_child(fit)
	_fit_said = _label(column, "")
	_fit_said.visible = false


## Ticks or clears Show play area without asking for it again.
func show_play_area_shown(on: bool) -> void:
	_area_shown = on
	if _show_area != null:
		_show_area.set_pressed_no_signal(on)


func _on_fit() -> void:
	var map := _map()
	if map == null:
		return
	var fitted := PlayArea.fit(map, PlayArea.gather(map), true)
	_fit_said.visible = true
	if fitted.is_empty():
		_fit_said.text = "No markers yet, so there's nothing to fit: the area is fitted to where players go. Place spawns and food first, or tick them in Populate."
		return
	var box: AABB = fitted["box"]
	var words := "%s m across, %s m along and %s m high, from a floor at %s m" % [box.size.x, box.size.z, box.size.y, box.position.y]
	if map.play_area() != null and map.area_box().is_equal_approx(box):
		_fit_said.text = "It fits already: %s." % words
		return
	# The numbers follow by the map's area_changed, and the rest once the history changes.
	PlayArea.apply_fit(map, fitted, undo)
	_fit_said.text = "Fitted: %s." % words


## Makes the play area's numbers say what the map's box says, as a handle or the move tool drags it. An
## older map's square has no box to change until Fit to map makes one.
func show_area() -> void:
	var map := _map()
	if map == null:
		return
	_showing = true
	var boxed := map.play_area() != null
	for row in NUMBERS:
		_numbers[row[0]].value = map.get(row[0])
		_numbers[row[0]].editable = boxed
	_showing = false


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


func _add_script_zones(column: Control) -> void:
	_add_heading(column, "Map scripts")
	_label(column, "A trigger zone is a box the map's script hears players and spears go into and out of, found by its name with game.zone(\"name\"). Press, then click on the map to drop one. It's selected then: drag its arrows to move it, and the dots on its sides to size it. Rename it in the Scene panel, using lowercase letters, digits, dashes and underscores. Only the editor shows it: players never see it.")
	var button := Button.new()
	button.text = "Add: %s" % TriggerZone.WORDS
	button.tooltip_text = "Press, then click on the map to drop one. Esc or the right mouse button stops."
	button.toggle_mode = true
	button.add_theme_color_override("font_color", TriggerZone.COLOUR.lightened(0.3))
	button.toggled.connect(_on_place_toggled.bind(TriggerZone.PLACING))
	_place_buttons[TriggerZone.PLACING] = button
	column.add_child(button)


func _map() -> SmartFellasMap:
	return EditorInterface.get_edited_scene_root() as SmartFellasMap


## Makes the panel say what the open map says.
func show_map() -> void:
	var map := _map()
	visible = map != null
	if map == null:
		return
	_unread = not _tab_shown()
	if _unread:
		return
	if _graded == null or not is_instance_valid(_graded) or _graded != map:
		_grade_said.text = NOT_GRADED
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
	show_area()
	var rules := MapExporter.read_rules(map)
	var sizes := MapExporter.team_sizes(map, rules)
	_counts.text = "%d octopus and %d diver spawn points, %d food patches. Up to %d divers and %d octopuses.\n%d fish, %d anglerfish spots, %d jellyfish in %d groups, %d lantern schools, %d goblin route points.\n%d wrasse spots, %d stingray stops, %d eel holes, %d groper holes, %d garden eel fields.\nTrigger zones for the map's script: %d." % [
		rules.octopus_spawns.size(), rules.diver_spawns.size(), rules.patches.size(), sizes["divers"], sizes["octopuses"],
		rules.fish.size(), rules.angler_spots.size(), rules.jelly_count(), rules.jellies.size(), rules.lantern_schools.size(), rules.goblin_route.size(),
		rules.haunts["wrasse"].size(), rules.haunts["stingrays"].size(), rules.haunts["eels"].size(), rules.haunts["gropers"].size(), rules.haunts["garden_eels"].size(),
		rules.triggers.size(),
	]
	_problems.text = "\n".join(rules.problems)
	_problems.visible = not rules.problems.is_empty()
	var warned: Array[String] = []
	for warning in rules.warnings:
		warned.append(warning["words"])
	warned.append_array(PlayArea.warnings(map, gathered.call(map)))
	_warnings.text = "\n".join(warned)
	_warnings.visible = not warned.is_empty()
	_fit_notes()


## A line for each of the map's own models, with what it's made of, and one for the model selected.
func _show_models(map: SmartFellasMap) -> void:
	var lines := model_lines(map)
	var listed: Array[String] = []
	for line in lines:
		listed.append("%s|%s|%d" % [line["id"], line["words"], line["count"]])
	if listed != _models_listed:
		_models_listed = listed
		for old in _models_list.get_children():
			_models_list.remove_child(old)
			old.queue_free()
		if lines.is_empty():
			_label(_models_list, "None yet. Drag a .glb or a mesh from the FileSystem panel into the map.")
		for line in lines:
			# The picks drop under a name too long to share its line with them, so the name stays whole.
			var row := HFlowContainer.new()
			var name_line := HBoxContainer.new()
			name_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label := Label.new()
			label.text = line["words"]
			label.tooltip_text = line["tip"]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			var font := label.get_theme_font("font")
			var wide := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			label.custom_minimum_size.x = minf(ceilf(wide) + 2.0, MOST_NAME_WIDTH * EditorInterface.get_editor_scale())
			name_line.add_child(label)
			# Beside the name rather than in it, so that a long name cut short never hides it.
			if line["count"] > 1:
				var placed := Label.new()
				placed.text = "×%d" % line["count"]
				placed.tooltip_text = "Placed %d times in the map." % line["count"]
				placed.mouse_filter = Control.MOUSE_FILTER_PASS
				placed.modulate.a = 0.7
				name_line.add_child(placed)
			row.add_child(name_line)
			var picks := HBoxContainer.new()
			picks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			picks.alignment = BoxContainer.ALIGNMENT_END
			var choice := _pick_button("Ground")
			choice.pressed.connect(_pick_ground.bind(choice, line["id"]))
			picks.add_child(choice)
			var crawl := _pick_button("Crawl")
			crawl.tooltip_text = CRAWL_TIP
			crawl.pressed.connect(_pick_crawl.bind(crawl, line["id"]))
			picks.add_child(crawl)
			var blend := _blend_box()
			blend.toggled.connect(func(on: bool) -> void: _on_model_blend_chosen(on, line["id"]))
			picks.add_child(blend)
			row.add_child(picks)
			_models_list.add_child(row)
	for index in lines.size():
		var row := _models_list.get_child(index)
		var choice := row.find_child("Ground", true, false) as Button
		var ground := maxi(MODEL_GROUNDS.find(lines[index]["ground"]), 0)
		choice.text = GROUND_WORDS[ground]
		choice.set_meta("ground", ground)
		var crawl := row.find_child("Crawl", true, false) as Button
		var how := maxi(MODEL_CRAWLS.find(lines[index]["crawl"]), 0)
		crawl.text = CRAWL_WORDS[how]
		crawl.set_meta("crawl", how)
		var blend := row.find_child("Blend", true, false) as CheckBox
		blend.set_pressed_no_signal(lines[index]["blends"])
	var selected := line_of(lines, _selected, map)
	_selected_line.visible = not selected.is_empty()
	if selected.is_empty():
		return
	_selected_label.text = "Selected: %s" % selected["words"]
	if selected["count"] > 1:
		_selected_label.text += " (%d placed)" % selected["count"]
	_selected_label.tooltip_text = selected["tip"]
	_selected_choice.select(MODEL_GROUNDS.find(selected["ground"]))
	_selected_choice.set_meta("line", selected["id"])
	_selected_crawl.select(MODEL_CRAWLS.find(selected["crawl"]))
	_selected_crawl.set_meta("line", selected["id"])
	_selected_blend.set_pressed_no_signal(selected["blends"])
	_selected_blend.set_meta("line", selected["id"])


## A button on a model's line that opens a pick list, called `called`.
func _pick_button(called: String) -> Button:
	var button := Button.new()
	button.name = called
	button.icon = get_theme_icon("arrow", "OptionButton")
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return button


## Opens the pick list under `choice`, the button on model line `id`, with what it's made of ticked.
func _pick_ground(choice: Button, id: String) -> void:
	var ticked: int = choice.get_meta("ground", 0)
	for index in GROUND_WORDS.size():
		_ground_menu.set_item_checked(index, index == ticked)
	_ground_menu.set_meta("line", id)
	_ground_menu.popup(Rect2i(Vector2i(choice.get_screen_position() + Vector2(0.0, choice.size.y)), Vector2i(int(choice.size.x), 0)))


func _ground_choice() -> OptionButton:
	var choice := OptionButton.new()
	for words in GROUND_WORDS:
		choice.add_item(words)
	return choice


## Opens the crawl pick list under `crawl`, the button on model line `id`, with its choice ticked.
func _pick_crawl(crawl: Button, id: String) -> void:
	var ticked: int = crawl.get_meta("crawl", 0)
	for index in CRAWL_WORDS.size():
		_crawl_menu.set_item_checked(index, index == ticked)
	_crawl_menu.set_meta("line", id)
	_crawl_menu.popup(Rect2i(Vector2i(crawl.get_screen_position() + Vector2(0.0, crawl.size.y)), Vector2i(int(crawl.size.x), 0)))


## A tick for whether a model blends into the ground.
func _blend_box() -> CheckBox:
	var box := CheckBox.new()
	box.name = "Blend"
	box.text = "Blend"
	box.tooltip_text = BLEND_TIP
	return box


func _crawl_choice() -> OptionButton:
	var choice := OptionButton.new()
	for words in CRAWL_WORDS:
		choice.add_item(words)
	choice.tooltip_text = CRAWL_TIP
	return choice


## The lines the list shows, one for each model file and each mesh, sorted by their words, as {"id",
## "words", "count", "tip", "ground", "crawl", "blends", "found"}: "count" is how many times it's placed, and "found" the first
## of own_model_pieces it stands for.
static func model_lines(map: SmartFellasMap) -> Array[Dictionary]:
	var by_id := {}
	var counts := {}
	for found in MapExporter.own_model_pieces(map):
		var key := MapExporter.ground_key(found)
		# A mesh never saved has no key until it's marked, so it's told apart by the mesh itself.
		var id := key if not key.is_empty() else "unsaved %d" % (found["node"] as MeshInstance3D).mesh.get_instance_id()
		counts[id] = counts.get(id, 0) + 1
		if not by_id.has(id):
			by_id[id] = {"id": id, "found": found, "ground": MapExporter.ground_of(map, found), "crawl": MapExporter.crawl_of(map, found), "blends": MapExporter.blends_of(map, found)}
	var lines: Array[Dictionary] = []
	for id: String in by_id:
		var line: Dictionary = by_id[id]
		var found: Dictionary = line["found"]
		line["count"] = counts[id]
		if not found.has("alone"):
			line["words"] = String(found["path"]).get_file()
			line["tip"] = found["path"]
		elif id.begins_with("::") or id.begins_with("unsaved "):
			line["words"] = "%s (mesh saved in the map)" % found["node"].name
			line["tip"] = "A mesh saved inside this map's scene, first used by %s." % found["node"].name
		else:
			line["words"] = id.get_file()
			line["tip"] = id
		lines.append(line)
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["words"] as String).naturalnocasecmp_to(b["words"]) < 0)
	return lines


## The line of `lines` that `node` belongs to: the model it is or is inside, the nearest one up. Empty if
## none, or if `node` has been freed since it was selected: untyped, as Godot refuses a freed object for a
## typed argument.
static func line_of(lines: Array[Dictionary], node: Variant, map: SmartFellasMap) -> Dictionary:
	if not is_instance_valid(node) or not node is Node:
		return {}
	var by_node := {}
	for found in MapExporter.own_model_pieces(map):
		var key := MapExporter.ground_key(found)
		by_node[found["node"]] = key if not key.is_empty() else "unsaved %d" % (found["node"] as MeshInstance3D).mesh.get_instance_id()
	var above := node as Node
	while above != null and above != map:
		if by_node.has(above):
			for line in lines:
				if line["id"] == by_node[above]:
					return line
		above = above.get_parent()
	return {}


## Shows the line for `node`, selected in the scene alone, or none.
func show_selected(node: Node) -> void:
	_selected = node
	var map := _map()
	if map != null and _selected_line != null:
		_showing = true
		_show_models(map)
		_showing = false


func _on_model_ground_chosen(index: int, id: String) -> void:
	var map := _map()
	if _showing or map == null or id.is_empty():
		return
	var line := {}
	for each in model_lines(map):
		if each["id"] == id:
			line = each
	if line.is_empty():
		return
	var key := MapExporter.mark_key(line["found"])
	var grounds: Dictionary[String, String] = map.soft_models.duplicate()
	if MODEL_GROUNDS[index] == "rock":
		grounds.erase(key)
	else:
		grounds[key] = MODEL_GROUNDS[index]
	_set_property("soft_models", grounds)


func _on_model_crawl_chosen(index: int, id: String) -> void:
	var map := _map()
	if _showing or map == null or id.is_empty():
		return
	var line := {}
	for each in model_lines(map):
		if each["id"] == id:
			line = each
	if line.is_empty():
		return
	var key := MapExporter.mark_key(line["found"])
	var crawls: Dictionary[String, String] = map.crawl_models.duplicate()
	if MODEL_CRAWLS[index] == "size":
		crawls.erase(key)
	else:
		crawls[key] = MODEL_CRAWLS[index]
	_set_property("crawl_models", crawls)


func _on_model_blend_chosen(on: bool, id: String) -> void:
	var map := _map()
	if _showing or map == null or id.is_empty():
		return
	var line := {}
	for each in model_lines(map):
		if each["id"] == id:
			line = each
	if line.is_empty():
		return
	var key := MapExporter.mark_key(line["found"])
	var blends: Dictionary[String, bool] = map.blend_models.duplicate()
	if on:
		blends[key] = true
	else:
		blends.erase(key)
	_set_property("blend_models", blends)


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
