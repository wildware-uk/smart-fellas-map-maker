@tool
extends ScrollContainer
## The Paint panel: the button that turns the brush on, its recipe, its mix of pieces, and how and where
## they grow. A person who has never seen Godot should be able to work it out by looking at it.

const Kit := preload("kit.gd")
const NewMap := preload("new_map.gd")
const Recipes := preload("recipes.gd")

const HINT_ON := "Left mouse paints. Hold Shift to erase.\nRight mouse and W A S D fly around, the middle mouse button turns the view.\n[ and ] or Ctrl + wheel change how wide. Esc stops."
const HINT_OFF := "Press the button, then paint on the sand or rock in the 3D view."
const HINT_NO_MAP := "Open a map first: double-click one in the maps folder, in the FileSystem panel, or make a new one."
const PICTURE_SIDE := 32.0
const LABEL_WIDTH := 112.0
const SAVED_KEY := "brush"

## The brush was turned on or off.
signal painting_toggled(on: bool)
## Something about the brush changed, by a person's hand.
signal recipe_changed

## Each slider: its setting, what a person calls it, its lowest and highest, its step, what it says after
## the number, and a tooltip.
const HOW_IT_GROWS := [
	["wide", "How wide", 0.25, 25.0, 0.25, " m", "How far the brush reaches from its middle. The circle in the 3D view shows it."],
	["thick", "How thick", 0.05, 20.0, 0.05, " a m²", "How many pieces grow in each square metre of a clump. Painting over a spot fills it up to this, and no further."],
	["clumps", "Clumps", 0.0, 1.0, 0.05, "", "0 spreads pieces evenly everywhere. 1 gathers them all in clumps, with bare ground between. About 0.7 looks grown."],
	["clump_size", "Clumps apart", 1.0, 25.0, 0.5, " m", "About how far apart the clumps sit, so also how big they get."],
]
const HOW_IT_SITS := [
	["size_low", "Smallest", 0.1, 10.0, 0.05, "×", "The smallest a piece may be, against its usual size. Pieces at a clump's edge come out smaller."],
	["size_high", "Biggest", 0.1, 10.0, 0.05, "×", "The biggest a piece may be, against its usual size. Pieces at a clump's middle come out bigger."],
	["turn", "Random turn", 0.0, 180.0, 5.0, "°", "How far a piece may be turned about its own up, either way. 180 is any way round."],
	["wobble", "Random lean", 0.0, 45.0, 1.0, "°", "How far a piece may lean off true, so that a row doesn't look planted."],
	["follow", "Follows the slope", 0.0, 1.0, 0.05, "", "0 grows straight up, as kelp does. 1 grows square to the surface, as a limpet sits."],
]
const WHERE_IT_GROWS := [
	["slope_low", "Slope from", 0.0, 180.0, 1.0, "°", "The flattest surface it grows on. 0 is flat, and a number above 60 keeps it to walls."],
	["slope_high", "Slope to", 0.0, 180.0, 1.0, "°", "The steepest surface it grows on. 90 is a wall, and past that is overhanging."],
	["height_low", "Height from", 0.0, 100.0, 0.5, " m", "The lowest it grows, in metres above the sand."],
	["height_high", "Height to", 0.0, 100.0, 0.5, " m", "The highest it grows, in metres above the sand."],
]

var _recipe: Dictionary = Recipes.completed({})
var _toggle: Button
var _hint: Label
var _new_map: Button
var _recipe_choice: OptionButton
var _delete_recipe: Button
var _mix_rows: VBoxContainer
var _mix_empty: Label
var _sliders := {}
var _on_sand: CheckBox
var _on_rock: CheckBox
var _seed: SpinBox
var _erase_hand: CheckBox
var _erase_only_mix: CheckBox
var _status: Label
var _body: VBoxContainer
var _showing := false
var _has_map := false


func _ready() -> void:
	name = "Paint"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(240.0, 200.0)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_add_top()
	_add_recipes()
	_add_mix()
	_add_sliders("How it grows", HOW_IT_GROWS)
	_add_sliders("Size and turn", HOW_IT_SITS, true)
	_add_where()
	_add_erasing()
	_load_starting_recipe()


func _add_top() -> void:
	_toggle = Button.new()
	_toggle.toggle_mode = true
	_toggle.text = "Start painting"
	_toggle.custom_minimum_size = Vector2(0.0, 36.0)
	_toggle.tooltip_text = "Turns the brush on and off. While it's on, the left mouse button paints in the 3D view."
	_toggle.toggled.connect(_on_toggled)
	_body.add_child(_toggle)
	_hint = _wrapped_label(HINT_OFF)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	_body.add_child(_hint)
	_new_map = Button.new()
	_new_map.text = "Make a new bare map"
	_new_map.tooltip_text = "Makes a map of flat sand, with spawn points and food, in the maps folder, and opens it."
	_new_map.pressed.connect(_make_new_map)
	_body.add_child(_new_map)
	_status = _wrapped_label("")
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	_status.visible = false
	_body.add_child(_status)


func _add_recipes() -> void:
	_body.add_child(HSeparator.new())
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = "Recipe"
	line.add_child(label)
	_recipe_choice = OptionButton.new()
	_recipe_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_choice.clip_text = true
	_recipe_choice.fit_to_longest_item = false
	_recipe_choice.custom_minimum_size = Vector2(70.0, 0.0)
	_recipe_choice.tooltip_text = "A recipe is a saved brush: its mix and all the settings below."
	_recipe_choice.item_selected.connect(_on_recipe_chosen)
	line.add_child(_recipe_choice)
	_body.add_child(line)
	line = HBoxContainer.new()
	var save := Button.new()
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.text = "Save as…"
	save.tooltip_text = "Saves this brush under a name, in the project's brush_recipes folder."
	save.pressed.connect(_ask_recipe_name)
	line.add_child(save)
	_delete_recipe = Button.new()
	_delete_recipe.text = "Delete"
	_delete_recipe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_recipe.tooltip_text = "Deletes this recipe, if it's one you saved. The add-on's own stay."
	_delete_recipe.pressed.connect(_delete_this_recipe)
	line.add_child(_delete_recipe)
	_body.add_child(line)
	_fill_recipe_choice()


func _add_mix() -> void:
	var heading := Label.new()
	heading.text = "The mix: what it paints"
	heading.tooltip_text = "The slider beside a piece says how often it comes up against the others."
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(heading)
	_mix_rows = VBoxContainer.new()
	_body.add_child(_mix_rows)
	_mix_empty = _wrapped_label("Click pieces in the Pieces panel to add them here.")
	_mix_empty.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	_body.add_child(_mix_empty)
	var note := _wrapped_label("Click pieces in the Pieces panel to add more.")
	note.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	_body.add_child(note)


func _add_sliders(heading: String, rows: Array, folded := false) -> void:
	var fold := FoldableContainer.new()
	fold.title = heading
	fold.folded = folded
	var list := VBoxContainer.new()
	fold.add_child(list)
	for row in rows:
		_add_slider(list, row)
	_body.add_child(fold)


func _add_slider(list: Control, row: Array) -> void:
	var key: String = row[0]
	var line := HBoxContainer.new()
	line.tooltip_text = row[6]
	var label := Label.new()
	label.text = row[1]
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(label)
	var slider := HSlider.new()
	slider.min_value = row[2]
	slider.max_value = row[3]
	slider.step = row[4]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = row[6]
	line.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(58.0, 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)
	slider.value_changed.connect(func(number: float) -> void: _on_slider(key, number))
	_sliders[key] = {"slider": slider, "value": value, "unit": row[5]}
	list.add_child(line)


func _add_where() -> void:
	var fold := FoldableContainer.new()
	fold.title = "Where it grows"
	var list := VBoxContainer.new()
	fold.add_child(list)
	var line := HBoxContainer.new()
	_on_sand = CheckBox.new()
	_on_sand.text = "On sand"
	_on_sand.tooltip_text = "Grows on the seabed."
	_on_sand.toggled.connect(func(on: bool) -> void: _set_setting("on_sand", on))
	line.add_child(_on_sand)
	_on_rock = CheckBox.new()
	_on_rock.text = "On rock"
	_on_rock.tooltip_text = "Grows on rocks and wrecks, whether placed by hand or painted."
	_on_rock.toggled.connect(func(on: bool) -> void: _set_setting("on_rock", on))
	line.add_child(_on_rock)
	list.add_child(line)
	for row in WHERE_IT_GROWS:
		_add_slider(list, row)
	var pattern := HBoxContainer.new()
	var label := Label.new()
	label.text = "Pattern"
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	pattern.add_child(label)
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 99999
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.tooltip_text = "Where the clumps fall. The same number gives the same clumps, whichever way you stroke."
	_seed.value_changed.connect(func(number: float) -> void: _set_setting("seed", int(number)))
	pattern.add_child(_seed)
	var shuffle := Button.new()
	shuffle.text = "Shuffle"
	shuffle.tooltip_text = "Picks another pattern of clumps."
	shuffle.pressed.connect(func() -> void: _seed.value = randi_range(1, 99999))
	pattern.add_child(shuffle)
	list.add_child(pattern)
	_body.add_child(fold)


func _add_erasing() -> void:
	var fold := FoldableContainer.new()
	fold.title = "Erasing (hold Shift)"
	fold.folded = true
	var list := VBoxContainer.new()
	fold.add_child(list)
	_erase_hand = CheckBox.new()
	_erase_hand.text = "Also erase pieces placed by hand"
	_erase_hand.tooltip_text = "Off, the eraser only takes what a brush painted, so your hand-placed pieces are safe."
	list.add_child(_erase_hand)
	_erase_only_mix = CheckBox.new()
	_erase_only_mix.text = "Only erase what's in this mix"
	_erase_only_mix.tooltip_text = "Takes out only the pieces in the mix above, and leaves everything else."
	list.add_child(_erase_only_mix)
	_body.add_child(fold)


func _wrapped_label(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200.0, 0.0)
	return label


## The brush's settings as they stand.
func recipe() -> Dictionary:
	return _recipe


func set_wide(wide: float) -> void:
	_sliders["wide"]["slider"].value = wide


func erase_hand_placed() -> bool:
	return _erase_hand.button_pressed


func erase_only_mix() -> bool:
	return _erase_only_mix.button_pressed


func is_painting() -> bool:
	return _toggle.button_pressed


## Turns the brush on or off, as the button does.
func set_painting(on: bool) -> void:
	_toggle.button_pressed = on


## Says whether a map is open, since the brush can't do anything without one.
func set_has_map(has_map: bool) -> void:
	_has_map = has_map
	_new_map.visible = not has_map
	_toggle.disabled = not has_map
	if not has_map:
		set_painting(false)
	_update_hint()


## Shows something the person should know, until the next thing.
func say(words: String) -> void:
	_status.text = words
	_status.visible = not words.is_empty()


func _update_hint() -> void:
	if not _has_map:
		_hint.text = HINT_NO_MAP
	elif _toggle.button_pressed:
		_hint.text = HINT_ON
	else:
		_hint.text = HINT_OFF


func _on_toggled(on: bool) -> void:
	_toggle.text = "Stop painting (Esc)" if on else "Start painting"
	_update_hint()
	painting_toggled.emit(on)


## Adds a piece to the mix, or gives it more weight if it's there already.
func add_to_mix(kit: String) -> void:
	for entry in _recipe["mix"]:
		if entry["kit"] == kit:
			entry["weight"] = minf(entry["weight"] + 1.0, 10.0)
			_show_recipe()
			_keep()
			return
	_recipe["mix"].append({"kit": kit, "weight": 1.0})
	_show_recipe()
	_keep()


func _on_slider(key: String, number: float) -> void:
	_sliders[key]["value"].text = _number_words(number, _sliders[key]["slider"].step) + _sliders[key]["unit"]
	if _showing:
		return
	_recipe[key] = number
	# A low limit can't pass its high limit, whichever one moved.
	for pair in Recipes.LOW_AND_HIGH:
		if key == pair[0] and number > _recipe[pair[1]]:
			_sliders[pair[1]]["slider"].value = number
		elif key == pair[1] and number < _recipe[pair[0]]:
			_sliders[pair[0]]["slider"].value = number
	_keep()


static func _number_words(number: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % roundi(number)
	if step >= 0.25:
		return "%.1f" % number
	return "%.2f" % number


func _set_setting(key: String, value: Variant) -> void:
	if _showing:
		return
	_recipe[key] = value
	_keep()


## Makes the panel say what the recipe says.
func _show_recipe() -> void:
	_showing = true
	for key: String in _sliders:
		_sliders[key]["slider"].value = _recipe[key]
		_on_slider(key, _recipe[key])
	_on_sand.button_pressed = _recipe["on_sand"]
	_on_rock.button_pressed = _recipe["on_rock"]
	_seed.value = _recipe["seed"]
	_show_mix()
	_showing = false


func _show_mix() -> void:
	for row in _mix_rows.get_children():
		_mix_rows.remove_child(row)
		row.queue_free()
	var total := 0.0
	for entry in _recipe["mix"]:
		total += entry["weight"]
	for entry in _recipe["mix"]:
		_mix_rows.add_child(_mix_row(entry, total))
	_mix_empty.visible = _recipe["mix"].is_empty()


func _mix_row(entry: Dictionary, _total: float) -> Control:
	var kit: String = entry["kit"]
	var line := HBoxContainer.new()
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(PICTURE_SIDE, PICTURE_SIDE)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture = Kit.thumb_of(kit)
	line.add_child(picture)
	var label := Label.new()
	label.text = Kit.plain_name(kit)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.custom_minimum_size = Vector2(60.0, 0.0)
	line.add_child(label)
	var weight := HSlider.new()
	weight.min_value = 0.0
	weight.max_value = 10.0
	weight.step = 0.1
	weight.value = entry["weight"]
	weight.custom_minimum_size = Vector2(70.0, 0.0)
	weight.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weight.tooltip_text = "How often this comes up against the others in the mix."
	weight.value_changed.connect(func(number: float) -> void:
		entry["weight"] = number
		_keep())
	line.add_child(weight)
	var remove := Button.new()
	remove.text = "×"
	remove.flat = true
	remove.tooltip_text = "Takes this out of the mix."
	remove.pressed.connect(func() -> void:
		_recipe["mix"].erase(entry)
		_show_recipe()
		_keep())
	line.add_child(remove)
	return line


func _fill_recipe_choice(selected := "") -> void:
	_recipe_choice.clear()
	var names: Array = Recipes.all().keys()
	names.sort()
	for name_here: String in names:
		_recipe_choice.add_item(name_here)
		if name_here == selected:
			_recipe_choice.select(_recipe_choice.item_count - 1)
	_delete_recipe.disabled = not Recipes.is_own(selected)


func _on_recipe_chosen(index: int) -> void:
	var chosen := _recipe_choice.get_item_text(index)
	var recipes := Recipes.all()
	if recipes.has(chosen):
		_recipe = recipes[chosen]
		_delete_recipe.disabled = not Recipes.is_own(chosen)
		_show_recipe()
		_keep()


func _load_starting_recipe() -> void:
	var settings := EditorInterface.get_editor_settings()
	var kept: Dictionary = settings.get_project_metadata("smart_fellas", SAVED_KEY, {})
	var recipes := Recipes.all()
	if not kept.is_empty():
		_recipe = Recipes.completed(kept)
	elif recipes.has("Sand garden"):
		_recipe = recipes["Sand garden"]
	_fill_recipe_choice(_recipe["name"])
	_show_recipe()


## Remembers the brush between sittings.
func _keep() -> void:
	recipe_changed.emit()
	EditorInterface.get_editor_settings().set_project_metadata("smart_fellas", SAVED_KEY, _recipe)


func _ask_recipe_name() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Save this brush"
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "What should this brush be called?"
	box.add_child(label)
	var words := LineEdit.new()
	words.text = _recipe["name"]
	words.select_all()
	box.add_child(words)
	dialog.add_child(box)
	dialog.register_text_enter(words)
	dialog.confirmed.connect(func() -> void:
		_save_recipe(words.text.strip_edges())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.popup_dialog_centered(dialog, Vector2i(360, 120))
	words.grab_focus.call_deferred()


func _save_recipe(words: String) -> void:
	if words.is_empty():
		return
	var other := Recipes.clash(words)
	if not other.is_empty():
		say("%s would save over your recipe %s, as both make the same file. Choose another name." % [words, other])
		return
	if Recipes.is_own(words):
		_ask("Replace your recipe %s with this brush?" % words, "Replace", _really_save_recipe.bind(words))
		return
	_really_save_recipe(words)


func _really_save_recipe(words: String) -> void:
	var replaces_shipped := Recipes.is_shipped(words) and not Recipes.is_own(words)
	_recipe["name"] = words
	var problem := Recipes.save(_recipe)
	if problem.is_empty():
		problem = "Saved as %s." % words
		if replaces_shipped:
			problem += " It replaces the add-on's own. Delete yours to bring that back."
	say(problem)
	_fill_recipe_choice(words)
	_keep()


func _delete_this_recipe() -> void:
	var name_here: String = _recipe["name"]
	if not Recipes.is_own(name_here):
		return
	var words := "Delete your recipe %s? This can't be undone." % name_here
	if Recipes.is_shipped(name_here):
		words = "Delete your recipe %s? The add-on's own %s comes back in its place." % [name_here, name_here]
	_ask(words, "Delete", _really_delete_recipe.bind(name_here))


func _really_delete_recipe(name_here: String) -> void:
	Recipes.remove(name_here)
	say("Deleted %s." % name_here)
	var recipes := Recipes.all()
	if recipes.has(name_here):
		_recipe = recipes[name_here]
	elif recipes.has("Sand garden"):
		_recipe = recipes["Sand garden"]
	_fill_recipe_choice(_recipe["name"])
	_show_recipe()
	_keep()


## Asks a yes or no question in a window, and does `then` on yes.
func _ask(question: String, yes: String, then: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Brush recipes"
	dialog.dialog_text = question
	dialog.dialog_autowrap = true
	dialog.ok_button_text = yes
	dialog.confirmed.connect(func() -> void:
		then.call()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.popup_dialog_centered(dialog, Vector2i(360, 120))


func _make_new_map() -> void:
	var made := NewMap.write_in("res://maps/")
	if made.has("problem"):
		say(made["problem"])
		return
	var path: String = made["path"]
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	EditorInterface.set_main_screen_editor("3D")
