@tool
extends AcceptDialog
## Says what came of Export Map or Test Map: what the game's checker thought, in plain words, with a
## button on each problem that shows the piece it's about, and a way to point at the game if it's lost.

const GameFinder := preload("game_finder.gd")
const MapTester := preload("map_tester.gd")

signal game_chosen(program: String)
signal maps_folder_chosen(folder: String)

const SIZE := Vector2i(720, 420)
const WORDS_WIDTH := 560.0

var _holder: VBoxContainer
## Where the map went, for Open folder.
var _folder := ""


func _init() -> void:
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_holder = VBoxContainer.new()
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_holder)


## Fills the dialog from what MapTester.export_and_check gave back.
func show_result(result: Dictionary) -> void:
	_holder.add_child(_words(result["words"]))
	for line: Dictionary in result["lines"]:
		_add_line(line)
	var state: MapTester.State = result["state"]
	if state == MapTester.State.NO_GAME:
		add_button("Find the game", true, "find")
	if state in [MapTester.State.NO_GAME, MapTester.State.NO_MAPS_FOLDER]:
		add_button("Choose the game's maps folder", true, "maps")
	elif result.get("into_game", false) and result.has("folder"):
		_folder = result["folder"]
		add_button("Open folder", true, "open")
	custom_action.connect(_on_custom_action)


func _words(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WORDS_WIDTH
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _add_line(line: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_child(_words("- " + line["words"]))
	var node: Node = line["node"]
	if node != null:
		var show_it := Button.new()
		show_it.text = "Show it"
		show_it.tooltip_text = "Select this in the scene."
		show_it.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		show_it.pressed.connect(_select.bind(node))
		row.add_child(show_it)
	_holder.add_child(row)


func _select(node: Node) -> void:
	if not is_instance_valid(node):
		return
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)


func _on_custom_action(action: StringName) -> void:
	match action:
		&"find":
			_pick_the_game()
		&"maps":
			_pick_the_maps_folder()
		&"open":
			OS.shell_open(_folder)


func _pick_the_maps_folder() -> void:
	var picker := EditorFileDialog.new()
	picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	picker.access = EditorFileDialog.ACCESS_FILESYSTEM
	picker.title = "Choose the folder Smart Fellas keeps its maps in"
	picker.dir_selected.connect(func(folder: String) -> void:
		maps_folder_chosen.emit(folder)
		queue_free())
	add_child(picker)
	picker.popup_file_dialog()


func _pick_the_game() -> void:
	var picker := EditorFileDialog.new()
	picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	picker.access = EditorFileDialog.ACCESS_FILESYSTEM
	picker.title = "Choose %s" % GameFinder.program_name()
	picker.file_selected.connect(_on_program_picked)
	add_child(picker)
	picker.popup_file_dialog()


func _on_program_picked(program: String) -> void:
	game_chosen.emit(program)
	queue_free()
