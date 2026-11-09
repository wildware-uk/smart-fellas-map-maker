@tool
extends VBoxContainer
## The Pose panel: drops octopus poses on the map, and shapes the one selected with the same dials as the
## game's pose studio: each arm's lift, spread, curl, twist, length and thickness, the head and mantle, how
## it sits, and whether its suckers and eyes show. Dragging the dot on an arm's tip in the 3D view bends that
## arm to follow the mouse. Wave and Sway set how it moves with the water, which Play the water shows. Every
## change goes through Godot's undo and is saved with the map.

## The Add button was pressed, to drop a pose with the marker tool, or let go ("").
signal placing_asked(kind: String)

const OctopusPose := preload("octopus_pose.gd")
const PoseLink := preload("pose_link.gd")

const MINIMUM_WIDTH := 200.0
## The arm choice that bends every arm at once.
const ALL_ARMS := -1
## How finely the dials step.
const STEP := 0.01

var undo: EditorUndoRedoManager

var _add_button: Button
var _nothing_chosen: Label
var _editor: VBoxContainer
var _title: Label
var _problem: Label
var _start_from: OptionButton
var _choices := {}
var _arm_choice: OptionButton
var _arm_dials := {}
var _body_dials := {}
var _water_dials := {}
var _play: CheckButton
var _pose: Node3D
## Whether the controls are being set to what the pose says, so their signals change nothing.
var _showing := false
## The dials, choices and built-in poses as the game gave them, once it has.
var _start: Dictionary = {}


func _ready() -> void:
	name = "Poses"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# As the Map panel's: a scroll bar that came and went would rewrap the words, back and forth.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_label(column, "Make octopus poses of the map's own, for players to hide with beside your pieces. Press Add, then click a rock, a wall or the sand to drop one. Shape it with the dials below, or drag the dot on the tip of an arm. Rename it in the Scene panel: that's its name in the game. Then select a piece or one of your models and tick the pose under Octopus poses in the Inspector: an octopus next to it is offered the pose on the near wheel (Q).")
	_add_button = Button.new()
	_add_button.text = "Add: %s" % OctopusPose.WORDS
	_add_button.tooltip_text = "Press, then click on the map to drop one. Esc or the right mouse button stops."
	_add_button.toggle_mode = true
	_add_button.add_theme_color_override("font_color", OctopusPose.COLOUR.lightened(0.3))
	_add_button.toggled.connect(func(on: bool) -> void: placing_asked.emit(OctopusPose.PLACING if on else ""))
	column.add_child(_add_button)
	column.add_child(HSeparator.new())
	_nothing_chosen = _label(column, "Select a pose in the 3D view or the Scene panel to shape it.")
	_editor = VBoxContainer.new()
	column.add_child(_editor)
	show_pose(null)


## Shows the Add button pressed while a pose is being dropped, and up when it isn't.
func show_placing(placing: bool) -> void:
	_add_button.set_pressed_no_signal(placing)


## Shapes `pose`, an octopus pose node, or shows that none is selected.
func show_pose(pose: Node3D) -> void:
	if _pose != null and is_instance_valid(_pose):
		if _pose.drawn.is_connected(_show_values):
			_pose.drawn.disconnect(_show_values)
		if _pose != pose:
			_pose.playing = false
	_pose = pose
	_nothing_chosen.visible = pose == null
	_editor.visible = pose != null
	if pose == null:
		return
	pose.drawn.connect(_show_values)
	if _start.is_empty():
		_start = PoseLink.start()
		_build_editor()
	pose.playing = _play != null and is_instance_valid(_play) and _play.button_pressed
	_show_values()


func _build_editor() -> void:
	for child in _editor.get_children():
		child.queue_free()
	_arm_dials.clear()
	_body_dials.clear()
	_water_dials.clear()
	_play = null
	_choices.clear()
	_title = _label(_editor, "")
	_title.add_theme_color_override("font_color", OctopusPose.COLOUR.lightened(0.3))
	_problem = _label(_editor, "")
	_problem.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	if _start.has("problem"):
		var retry := Button.new()
		retry.text = "Try the game again"
		retry.pressed.connect(func() -> void:
			PoseLink.forget_trouble()
			_start = {}
			show_pose(_pose)
			if _pose != null:
				_pose.redraw())
		_editor.add_child(retry)
		return
	var from_line := HBoxContainer.new()
	var from_words := Label.new()
	from_words.text = "Start from"
	from_line.add_child(from_words)
	_start_from = OptionButton.new()
	_start_from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_from.fit_to_longest_item = false
	_start_from.add_item("Choose a pose of the game's...")
	_start_from.add_item("At rest, arms out")
	for entry: Dictionary in _start.get("built_in", []):
		_start_from.add_item(entry["name"])
	_start_from.tooltip_text = "Replaces this pose's shape with one of the game's own, to change from there."
	_start_from.item_selected.connect(_on_start_from)
	from_line.add_child(_start_from)
	_editor.add_child(from_line)
	for key: String in ["sits", "suckers", "eyes", "lit"]:
		var choice := OptionButton.new()
		for option: Dictionary in _start["choices"][key]:
			choice.add_item(option["label"])
		choice.item_selected.connect(_on_choice.bind(key))
		_choices[key] = choice
		_editor.add_child(choice)
	_heading("Arms")
	_arm_choice = OptionButton.new()
	for arm in OctopusPose.ARMS:
		_arm_choice.add_item("Arm %d" % (arm + 1), arm)
	_arm_choice.add_item("All arms", OctopusPose.ARMS)
	_arm_choice.tooltip_text = "Which arm the dials bend. Dragging an arm's tip in the 3D view picks it too."
	_arm_choice.item_selected.connect(_on_arm_chosen)
	_editor.add_child(_arm_choice)
	for dial: Dictionary in _start["arm_dials"]:
		_arm_dials[dial["part"]] = _dial_row(dial, _on_arm_dial.bind(dial["part"]))
	var arm_buttons := HFlowContainer.new()
	_button(arm_buttons, "Copy to all arms", "Gives every arm this arm's shape.", _copy_to_all)
	_button(arm_buttons, "Left side to right", "Copies the arms on the octopus's left onto its right, mirrored.", _mirror.bind(true))
	_button(arm_buttons, "Right side to left", "Copies the arms on the octopus's right onto its left, mirrored.", _mirror.bind(false))
	_editor.add_child(arm_buttons)
	_heading("Head and mantle")
	for dial: Dictionary in _start["body_dials"]:
		_body_dials[dial["part"]] = _dial_row(dial, _on_body_dial.bind(dial["part"]))
	_heading("In the water")
	_label(_editor, "Wave runs ripples up the arms, as the water moves weed. Sway lets the current bend the arms, from stiff like coral at 0 to streaming like weed at 1.")
	for dial: Dictionary in _start.get("water_dials", []):
		_water_dials[dial["part"]] = _dial_row(dial, _on_water_dial.bind(dial["part"]))
	_play = CheckButton.new()
	_play.text = "Play the water"
	_play.tooltip_text = "Shows the selected pose moving with the water, as players will see it. Turn it off to drag the dots on the arms' tips again."
	_play.toggled.connect(func(on: bool) -> void:
		if _pose != null and is_instance_valid(_pose):
			_pose.playing = on)
	_editor.add_child(_play)
	_editor.add_child(HSeparator.new())
	var rest := HFlowContainer.new()
	_button(rest, "Back to rest", "Puts every arm, the head and the mantle back at rest, holding still.", _back_to_rest)
	_editor.add_child(rest)


func _show_values() -> void:
	if _pose == null or not is_instance_valid(_pose) or _title == null:
		return
	_showing = true
	_title.text = "%s: rename it in the Scene panel." % _pose.name
	var problem: String = _start.get("problem", _pose.problem)
	if not _start.has("problem") and not _pose.problem.is_empty():
		problem = "The game won't take this pose: %s." % _pose.problem
	_problem.text = problem
	_problem.visible = not problem.is_empty()
	if _start.has("problem"):
		_showing = false
		return
	var pose: Dictionary = _pose.file_pose()
	for key: String in _choices:
		var options: Array = _start["choices"][key]
		for at in options.size():
			if options[at]["value"] == pose[key]:
				_choices[key].select(at)
	var arm: int = _pose.chosen_arm
	_arm_choice.select(OctopusPose.ARMS if arm == ALL_ARMS else arm)
	var shown: Dictionary = _arm_of(pose, maxi(arm, 0))
	for part: String in _arm_dials:
		_set_row(_arm_dials[part], shown[part])
	var body := _body_of(pose)
	for part: String in _body_dials:
		_set_row(_body_dials[part], body[part])
	var water := _water_of(pose)
	for part: String in _water_dials:
		_set_row(_water_dials[part], water[part])
	_showing = false


## Arm `arm` of `pose`, with every part the pose leaves out at rest.
func _arm_of(pose: Dictionary, arm: int) -> Dictionary:
	var whole: Dictionary = _start["fresh"]["arms"][arm].duplicate()
	whole.merge(pose["arms"][arm], true)
	return whole


func _body_of(pose: Dictionary) -> Dictionary:
	var whole: Dictionary = _start["fresh"]["body"].duplicate()
	whole.merge(pose["body"], true)
	return whole


func _water_of(pose: Dictionary) -> Dictionary:
	var whole: Dictionary = _start["fresh"].get("water", {}).duplicate()
	var given: Variant = pose.get("water", {})
	whole.merge(given if given is Dictionary else {}, true)
	return whole


## Changes the selected pose as `change` says, given the whole pose to change, as one step of undo. Steps
## named alike in a row, such as a dial dragged, merge into one.
func _change(words: String, change: Callable) -> void:
	if _pose == null or not is_instance_valid(_pose):
		return
	var before: Dictionary = _pose.pose.duplicate(true)
	var after: Dictionary = _pose.file_pose()
	change.call(after)
	after.erase("version")
	after.erase("name")
	undo.create_action("%s: %s" % [words, _pose.name], UndoRedo.MERGE_ENDS, _pose)
	undo.add_do_property(_pose, "pose", after)
	undo.add_undo_property(_pose, "pose", before)
	undo.commit_action()


func _on_start_from(index: int) -> void:
	if _showing or index == 0:
		return
	_start_from.select(0)
	var from: Dictionary = _start["fresh"] if index == 1 else _start["built_in"][index - 2]["pose"]
	var words := "Start from %s" % _start_from.get_item_text(index)
	_change(words, func(pose: Dictionary) -> void:
		for key in from:
			if key != "name" and key != "version":
				pose[key] = from[key].duplicate(true) if from[key] is Dictionary or from[key] is Array else from[key])


func _on_choice(index: int, key: String) -> void:
	if _showing:
		return
	var value: String = _start["choices"][key][index]["value"]
	_change("Change how it sits" if key == "sits" else "Change %s" % key, func(pose: Dictionary) -> void: pose[key] = value)


func _on_arm_chosen(index: int) -> void:
	var arm := _arm_choice.get_item_id(index)
	_pose.chosen_arm = ALL_ARMS if arm == OctopusPose.ARMS else arm
	_show_values()


func _on_arm_dial(value: float, part: String) -> void:
	if _showing:
		return
	var chosen: int = _pose.chosen_arm
	_change("Bend arms" if chosen == ALL_ARMS else "Bend arm %d" % (chosen + 1), func(pose: Dictionary) -> void:
		for arm in OctopusPose.ARMS:
			if chosen == ALL_ARMS or arm == chosen:
				var shape: Dictionary = pose["arms"][arm].duplicate()
				shape[part] = value
				pose["arms"][arm] = shape)


func _on_body_dial(value: float, part: String) -> void:
	if _showing:
		return
	_change("Shape the body", func(pose: Dictionary) -> void:
		var body: Dictionary = pose["body"].duplicate()
		body[part] = value
		pose["body"] = body)


func _on_water_dial(value: float, part: String) -> void:
	if _showing:
		return
	_change("Change how it moves", func(pose: Dictionary) -> void:
		var water: Variant = pose.get("water", {})
		water = (water as Dictionary).duplicate() if water is Dictionary else {}
		water[part] = value
		pose["water"] = water)


func _copy_to_all() -> void:
	var from := maxi(_pose.chosen_arm, 0)
	_change("Copy arm %d to all" % (from + 1), func(pose: Dictionary) -> void:
		pose["arms"] = OctopusPose.copied_to_all(pose, from)["arms"])


## Copies the arms on one side of the octopus onto the other, mirrored: from its left if `from_left`.
func _mirror(from_left: bool) -> void:
	_change("Copy %s side to %s" % ["left" if from_left else "right", "right" if from_left else "left"], func(pose: Dictionary) -> void:
		pose["arms"] = OctopusPose.mirrored_side(pose, _start, from_left)["arms"])


func _back_to_rest() -> void:
	_change("Back to rest", func(pose: Dictionary) -> void:
		pose["body"] = {}
		pose["arms"] = OctopusPose.rest_pose()["arms"]
		pose["water"] = {})


func _dial_row(dial: Dictionary, changed: Callable) -> Dictionary:
	var line := HBoxContainer.new()
	var words := Label.new()
	words.text = dial["label"]
	words.custom_minimum_size.x = 80.0
	line.add_child(words)
	var slider := HSlider.new()
	slider.min_value = dial["least"]
	slider.max_value = dial["most"]
	slider.step = STEP
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(slider)
	var number := SpinBox.new()
	number.min_value = dial["least"]
	number.max_value = dial["most"]
	number.step = STEP
	number.custom_minimum_size.x = 72.0
	line.add_child(number)
	slider.value_changed.connect(func(value: float) -> void:
		if not _showing:
			number.set_value_no_signal(value)
			changed.call(value))
	number.value_changed.connect(func(value: float) -> void:
		if not _showing:
			slider.set_value_no_signal(value)
			changed.call(value))
	_editor.add_child(line)
	return {"slider": slider, "number": number}


func _set_row(row: Dictionary, value: float) -> void:
	# Adding nought turns -0 into 0, which would read "-0.0".
	row["slider"].set_value_no_signal(value + 0.0)
	row["number"].set_value_no_signal(snappedf(value, STEP) + 0.0)


func _button(row: Control, words: String, tip: String, pressed: Callable) -> void:
	var button := Button.new()
	button.text = words
	button.tooltip_text = tip
	button.pressed.connect(pressed)
	row.add_child(button)


func _heading(words: String) -> void:
	_editor.add_child(HSeparator.new())
	var label := _label(_editor, words)
	label.add_theme_color_override("font_color", get_theme_color("accent_color", "Editor"))


func _label(column: Control, words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# With no width of its own, a wrapping label behind another tab would ask for the height of the screen.
	label.custom_minimum_size.x = MINIMUM_WIDTH
	column.add_child(label)
	return label
