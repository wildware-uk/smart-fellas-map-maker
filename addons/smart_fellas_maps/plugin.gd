@tool
extends EditorPlugin
## Puts the add-on's tools in the editor: the Export Map and Test Map buttons above the 3D view, the Pieces panel in
## the dock on the left, the Map, Paint and Water panels in a dock of their own on the right, the cost meter
## below the 3D view, and Project > Tools > Smart Fellas: Check for updates.

const Brush := preload("brush.gd")
const BrushTool := preload("brush_tool.gd")
const Carrier := preload("carrier.gd")
const CostBar := preload("cost_bar.gd")
const GameFinder := preload("game_finder.gd")
const MapExporter := preload("map_exporter.gd")
const MapPanel := preload("map_panel.gd")
const MapTester := preload("map_tester.gd")
const MarkerGizmos := preload("marker_gizmos.gd")
const MarkerTool := preload("marker_tool.gd")
const SeabedTool := preload("seabed_tool.gd")
const ShaderGlobals := preload("water/shader_globals.gd")
const PaintPanel := preload("paint_panel.gd")
const PlayAreaGizmos := preload("play_area_gizmos.gd")
const ZoneGizmos := preload("zone_gizmos.gd")
const TriggerGizmos := preload("trigger_gizmos.gd")
const PieceDrop := preload("piece_drop.gd")
const PiecesPanel := preload("pieces_panel.gd")
const TestResults := preload("test_results.gd")
const UpdateBanner := preload("update_banner.gd")
const WaterPanel := preload("water_panel.gd")

## Where the Map, Paint and Water panels go: under the Inspector, in a dock of their own. Beside the Inspector,
## Node and Groups, a narrow dock hid their tabs behind its arrows.
const TOOLS_SLOT := DOCK_SLOT_RIGHT_BL
## Godot keeps where each dock was by its name, so a project opened before they moved would put them back
## beside the Inspector. New names start them afresh in their own dock. Godot keeps a dock's names in a list
## split at commas, so these must have none.
const TOOLS_LAYOUT := "Smart Fellas %s"

const CHECK_FOR_UPDATES := "Smart Fellas: Check for updates"
## Where the Map panel's Show play area is kept, in the project's editor settings rather than the map, as
## the game has no use for it.
const SHOW_PLAY_AREA := ["smart_fellas_maps", "show_play_area"]

## How many 3D views Godot can split into.
const VIEWS := 4
## How long after opening the game to see whether it has fallen over, in seconds.
const GAME_STARTS_WITHIN := 4.0

var _button: Button
var _folder_button: Button
var _test_button: Button
var _game_process := -1
## Whether the add-on has been turned off. A check under way comes back to nothing.
var _closed := false
var _water_panel: Control
var _water_dock: EditorDock
var _pieces_panel: Control
var _paint_panel: Control
var _map_panel: Control
var _pieces_dock: EditorDock
var _paint_dock: EditorDock
var _map_dock: EditorDock
var _markers: MarkerTool
var _marker_gizmos: EditorNode3DGizmoPlugin
var _play_area: PlayAreaGizmos
var _zone_gizmos: ZoneGizmos
var _trigger_gizmos: TriggerGizmos
var _sculptor: SeabedTool
var _cost_bar: Control
var _tool: BrushTool
var _carrier: Carrier
var _drops: Array[Control] = []
var _map: SmartFellasMap
var _cost_is_stale := true
## Whether the Map panel should look at the map again. That reads every piece: 70 ms on the owner's map of
## thousands. So while a stroke is under way only the cost meter keeps up, and the panel catches up after.
var _panel_is_stale := true
var _camera: Camera3D
var _update_dialog: AcceptDialog
var _drops_awake := false


func _enter_tree() -> void:
	_add_missing_shader_globals()
	_button = Button.new()
	_button.text = "Export Map"
	_button.tooltip_text = "Write this map straight into Smart Fellas, where it shows under My maps, and check it with the game. Exporting again replaces it."
	_button.pressed.connect(_export)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
	_folder_button = Button.new()
	_folder_button.text = "Export to Folder..."
	_folder_button.flat = true
	_folder_button.tooltip_text = "Write the map package to a folder you choose instead, to share it by hand."
	_folder_button.pressed.connect(_export_to_folder)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _folder_button)
	_test_button = Button.new()
	_test_button.text = "Test Map"
	_test_button.tooltip_text = "Export this map, check it with the game's own checker, and open the game hosted on it with bots."
	_test_button.pressed.connect(_test)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _test_button)
	_water_panel = WaterPanel.new()
	_water_panel.undo = get_undo_redo()

	_tool = BrushTool.new()
	_tool.history = get_undo_redo()
	_tool.view_changed.connect(update_overlays)
	_tool.said.connect(_say)
	_tool.stop_asked.connect(func() -> void: _paint_panel.set_painting(false))

	_paint_panel = PaintPanel.new()
	_paint_panel.painting_toggled.connect(_on_painting_toggled)
	_paint_panel.recipe_changed.connect(_say_why_the_brush_cant_paint)
	_tool.panel = _paint_panel
	_map_panel = MapPanel.new()
	_map_panel.undo = get_undo_redo()
	_map_panel.placing_asked.connect(_on_placing_asked)
	# In the order their tabs show.
	_map_dock = _dock_of(_map_panel, "Map", TOOLS_SLOT, TOOLS_LAYOUT % "Map")
	_paint_dock = _dock_of(_paint_panel, "Paint", TOOLS_SLOT, TOOLS_LAYOUT % "Paint")
	_water_dock = _dock_of(_water_panel, "Water", TOOLS_SLOT, TOOLS_LAYOUT % "Water")
	_markers = MarkerTool.new()
	_markers.history = get_undo_redo()
	_markers.surface_under = _tool.surface_under
	_markers.view_changed.connect(update_overlays)
	_markers.said.connect(_say_about_markers)
	_markers.stopped.connect(func() -> void: _map_panel.show_placing(""))
	_markers.zone_dropped.connect(_select_alone)
	_sculptor = SeabedTool.new()
	_sculptor.history = get_undo_redo()
	_sculptor.surface_under = _tool.surface_under
	_sculptor.forget_surfaces = _tool.forget_surfaces
	_sculptor.view_changed.connect(update_overlays)
	_sculptor.said.connect(_say_about_markers)
	_sculptor.stopped.connect(func() -> void: _map_panel.show_sculpting(-1))
	_map_panel.sculpting_asked.connect(_on_sculpting_asked)
	_map_panel.flatten_asked.connect(_sculptor.flatten)
	_map_panel.sculpting_settings_changed.connect(func(wide: float, strength: float) -> void:
		_sculptor.wide = wide
		_sculptor.strength = strength
		update_overlays())
	_carrier = Carrier.new()
	_carrier.history = get_undo_redo()
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_marker_gizmos = MarkerGizmos.new()
	add_node_3d_gizmo_plugin(_marker_gizmos)
	_play_area = PlayAreaGizmos.new()
	_play_area.undo = get_undo_redo()
	_play_area.shown = EditorInterface.get_editor_settings().get_project_metadata(SHOW_PLAY_AREA[0], SHOW_PLAY_AREA[1], true)
	add_node_3d_gizmo_plugin(_play_area)
	_zone_gizmos = ZoneGizmos.new()
	_zone_gizmos.undo = get_undo_redo()
	add_node_3d_gizmo_plugin(_zone_gizmos)
	_trigger_gizmos = TriggerGizmos.new()
	_trigger_gizmos.undo = get_undo_redo()
	add_node_3d_gizmo_plugin(_trigger_gizmos)
	_map_panel.gathered = _play_area.gathered
	_map_panel.show_play_area_shown(_play_area.shown)
	_map_panel.play_area_toggled.connect(_on_play_area_toggled)
	_pieces_panel = PiecesPanel.new()
	_pieces_panel.piece_clicked.connect(_on_piece_clicked)
	_pieces_panel.drag_started.connect(_on_piece_drag_started)
	_pieces_dock = _dock_of(_pieces_panel, "Pieces", DOCK_SLOT_LEFT_BR)

	_cost_bar = CostBar.new()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _cost_bar)
	_add_drops()
	add_tool_menu_item(CHECK_FOR_UPDATES, _check_for_updates)

	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	get_undo_redo().version_changed.connect(_on_history_changed)
	# version_changed is undo and redo only. A step done, such as the Scene panel's eye, is this one.
	get_undo_redo().history_changed.connect(_on_history_changed)
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)
	_on_scene_changed.call_deferred(EditorInterface.get_edited_scene_root())
	# So that a person opening the project sees the tools, not Godot's own panels behind them.
	_pieces_dock.make_visible.call_deferred()
	_paint_dock.make_visible.call_deferred()


func _exit_tree() -> void:
	_closed = true
	scene_changed.disconnect(_on_scene_changed)
	get_undo_redo().version_changed.disconnect(_on_history_changed)
	get_undo_redo().history_changed.disconnect(_on_history_changed)
	EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	get_tree().node_added.disconnect(_on_tree_changed)
	get_tree().node_removed.disconnect(_on_tree_changed)
	_tool.end_stroke()
	_sculptor.end_stroke()
	_watch_map(null)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
	_button.queue_free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _folder_button)
	_folder_button.queue_free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _test_button)
	_test_button.queue_free()
	remove_dock(_water_dock)
	_water_dock.queue_free()
	remove_dock(_paint_dock)
	_paint_dock.queue_free()
	remove_dock(_map_dock)
	_map_dock.queue_free()
	remove_node_3d_gizmo_plugin(_marker_gizmos)
	remove_node_3d_gizmo_plugin(_play_area)
	remove_node_3d_gizmo_plugin(_zone_gizmos)
	remove_node_3d_gizmo_plugin(_trigger_gizmos)
	remove_dock(_pieces_dock)
	_pieces_dock.queue_free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _cost_bar)
	_cost_bar.queue_free()
	remove_tool_menu_item(CHECK_FOR_UPDATES)
	if _update_dialog != null:
		_update_dialog.queue_free()
		_update_dialog = null
	for drop in _drops:
		drop.queue_free()
	_drops.clear()


## A project that came with an older add-on lacks the water's newer shader settings, which live in its
## project.godot and not in the add-on's folder. Without them the map draws plain white (#294).
func _add_missing_shader_globals() -> void:
	var added := ShaderGlobals.add_missing()
	if added.is_empty():
		return
	var saved := ProjectSettings.save()
	if saved != OK:
		push_warning("Smart Fellas Maps: added the water's shader settings %s for now, but couldn't save them into project.godot: %s." % [", ".join(added), error_string(saved)])
		return
	print("Smart Fellas Maps: added the water's shader settings this project lacked: %s." % ", ".join(added))


## `layout_key` is the name Godot keeps where it is under, or its title if that's "".
func _dock_of(panel: Control, title: String, slot: int, layout_key := "") -> EditorDock:
	var dock := EditorDock.new()
	dock.title = title
	dock.layout_key = layout_key
	dock.default_slot = slot
	dock.add_child(panel)
	add_dock(dock)
	return dock


## Asks GitHub for a newer add-on, as the Map panel's Check for updates does, and shows what it finds in a
## small window with Update in it.
func _check_for_updates() -> void:
	if _update_dialog == null:
		_update_dialog = AcceptDialog.new()
		_update_dialog.title = "Smart Fellas map maker"
		_update_dialog.ok_button_text = "Close"
		var banner := UpdateBanner.new(_map_panel.update_box())
		banner.always_shown = true
		banner.minimum_width = 360.0
		_update_dialog.add_child(banner)
		EditorInterface.get_base_control().add_child(_update_dialog)
	_update_dialog.popup_centered()
	# Once the new version is in place, what's left is to restart, which the window already says.
	if not _map_panel.update_box().installed():
		_map_panel.update_box().check(false)


## One drop catcher over each 3D view.
func _add_drops() -> void:
	for index in VIEWS:
		var view := EditorInterface.get_editor_viewport_3d(index)
		var holder := view.get_parent().get_parent() as Control
		if holder == null:
			continue
		var drop := PieceDrop.new()
		drop.viewport_3d = view
		drop.history = get_undo_redo()
		drop.surface_under = _tool.surface_under
		drop.map_getter = func() -> SmartFellasMap: return _map
		holder.add_child(drop)
		_drops.append(drop)


func _process(delta: float) -> void:
	_carrier.tick()
	_tool.tick(delta)
	_sculptor.tick(delta)
	_markers.tick()
	if _drops_awake and not get_viewport().gui_is_dragging():
		_drops_awake = false
		for drop in _drops:
			drop.sleep()
	if _cost_is_stale:
		_cost_is_stale = false
		_cost_bar.show_cost(_map)
	if _panel_is_stale and _tool.is_idle():
		_panel_is_stale = false
		_map_panel.show_map()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	_camera = camera
	if _sculptor.handle_input(camera, event) or _markers.handle_input(camera, event) or _tool.handle_input(camera, event):
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	_tool.draw(overlay, _camera)
	_markers.draw(overlay, _camera)
	_sculptor.draw(overlay, _camera)


func _on_painting_toggled(on: bool) -> void:
	_tool.end_stroke()
	_tool.active = on
	if on:
		_markers.stop()
		_sculptor.stop()
		EditorInterface.set_main_screen_editor("3D")
		# A selected piece's handles would sit in the way of the brush.
		EditorInterface.get_selection().clear()
	_say_why_the_brush_cant_paint()
	update_overlays()


## A brush that's on and can't paint shouldn't leave anyone clicking and wondering.
func _say_why_the_brush_cant_paint() -> void:
	if _map != null and _paint_panel.is_painting():
		_paint_panel.say(Brush.why_it_cant_paint(_map, _paint_panel.recipe(), _tool.surfaces()))
	else:
		_paint_panel.say("")


## A button in the Map panel asks to drop markers of this kind, or "" to stop.
func _on_placing_asked(kind: String) -> void:
	if kind.is_empty():
		_markers.stop()
		return
	_paint_panel.set_painting(false)
	_sculptor.stop()
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.get_selection().clear()
	_map_panel.show_placing(kind)
	_markers.start(kind)


func _select_alone(node: Node) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)


## A button in the Map panel asks to sculpt in this mode, or -1 to stop.
func _on_sculpting_asked(mode: int) -> void:
	if mode == -1:
		_sculptor.stop()
		return
	if _map != null and not _map.has_seabed:
		_map_panel.show_sculpting(-1)
		_say("This map has no seabed to sculpt. Tick Seabed in the Map panel first.")
		return
	_paint_panel.set_painting(false)
	_markers.stop()
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.get_selection().clear()
	_sculptor.wide = _map_panel.sculpt_wide()
	_sculptor.strength = _map_panel.sculpt_strength()
	_map_panel.show_sculpting(mode)
	_sculptor.start(mode)


func _say_about_markers(words: String) -> void:
	EditorInterface.get_editor_toaster().push_toast(words, EditorToaster.SEVERITY_WARNING)


func _on_piece_drag_started() -> void:
	_drops_awake = true
	for drop in _drops:
		drop.wake()


func _on_piece_clicked(kit: String) -> void:
	_paint_panel.add_to_mix(kit)


func _say(words: String) -> void:
	_paint_panel.say(words)
	EditorInterface.get_editor_toaster().push_toast(words, EditorToaster.SEVERITY_WARNING)


func _on_scene_changed(scene: Node) -> void:
	# The Map panel shares the play area's gathering of the map's pieces: the last map's mustn't show here.
	_play_area.forget()
	_water_panel.show_map()
	_map_panel.show_map()
	var map := scene as SmartFellasMap
	_watch_map(map)
	_tool.set_map(map)
	_markers.stop()
	_markers.map = map
	_sculptor.stop()
	_sculptor.map = map
	_carrier.watch(null)
	_carrier.map = map
	_paint_panel.set_has_map(map != null)
	_say_why_the_brush_cant_paint()
	_map_changed()


## One piece or model selected alone is watched, so that what stands on it moves with it, and the Map
## panel offers what it's made of.
func _on_selection_changed() -> void:
	var selected := EditorInterface.get_selection().get_top_selected_nodes()
	_carrier.watch(selected[0] as Node3D if selected.size() == 1 else null)
	_map_panel.show_selected(selected[0] if selected.size() == 1 else null)


func _watch_map(map: SmartFellasMap) -> void:
	if _map != null and is_instance_valid(_map) and _map.pieces_changed.is_connected(_on_pieces_changed):
		_map.pieces_changed.disconnect(_on_pieces_changed)
		_map.area_changed.disconnect(_map_panel.show_area)
	_map = map
	_play_area.forget()
	if _map != null:
		_map.pieces_changed.connect(_on_pieces_changed)
		# As a handle drags, the numbers follow it at once; what's outside is said again once it's let go.
		_map.area_changed.connect(_map_panel.show_area)


func _on_play_area_toggled(on: bool) -> void:
	_play_area.shown = on
	EditorInterface.get_editor_settings().set_project_metadata(SHOW_PLAY_AREA[0], SHOW_PLAY_AREA[1], on)
	_redraw_play_area()


## Something on the map may have moved in or out of the play area.
func _redraw_play_area() -> void:
	_play_area.forget()
	if _map != null and is_instance_valid(_map):
		_map.update_gizmos()
		var box := _map.play_area()
		if box != null:
			box.update_gizmos()


## The cost meter and the Map panel should look at the map again.
func _map_changed() -> void:
	_cost_is_stale = true
	_panel_is_stale = true


func _on_pieces_changed() -> void:
	_play_area.forget()
	_map_changed()


func _on_history_changed() -> void:
	_tool.forget_surfaces()
	if _tool.is_idle():
		_say_why_the_brush_cant_paint()
	_map_changed()
	_redraw_play_area()
	update_overlays()


## Godot adds and takes away nodes of its own all the time, for tooltips and menus. Only the map's count.
func _on_tree_changed(node: Node) -> void:
	if _map == null or not is_instance_valid(_map) or not (node == _map or _map.is_ancestor_of(node)):
		return
	_map_changed()
	_redraw_play_area()


func _export() -> void:
	var result := await _export_and_check("")
	if _closed:
		return
	_show_results("Export Map", result)


## Asks for a folder, then exports there rather than into the game.
func _export_to_folder() -> void:
	var picker := EditorFileDialog.new()
	picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	picker.access = EditorFileDialog.ACCESS_FILESYSTEM
	picker.title = "Choose a folder to export the map into"
	picker.dir_selected.connect(func(folder: String) -> void:
		picker.queue_free()
		var result := await _export_and_check(folder)
		if _closed:
			return
		_show_results("Export to Folder", result))
	picker.canceled.connect(picker.queue_free)
	EditorInterface.get_base_control().add_child(picker)
	picker.popup_file_dialog()


func _test() -> void:
	var result := await _export_and_check("")
	if _closed:
		return
	if result["state"] == MapTester.State.NO_MAPS_FOLDER:
		# A game too old to say where its maps go can still try the map out.
		result = await _export_and_check(MapExporter.default_out_folder())
		if _closed:
			return
	if result["state"] != MapTester.State.FINE:
		_show_results("Test Map", result)
		return
	for warning: Dictionary in result["lines"]:
		EditorInterface.get_editor_toaster().push_toast(warning["words"], EditorToaster.SEVERITY_WARNING)
	_open_the_game(result["game"], result["folder"])


## Exports into `folder`, or into the game's own maps folder if that's "", and checks it with the game.
func _export_and_check(folder: String) -> Dictionary:
	_button.disabled = true
	_folder_button.disabled = true
	_test_button.disabled = true
	var chosen := _setting(GameFinder.CHOSEN_KEY)
	var scene := EditorInterface.get_edited_scene_root()
	var result: Dictionary
	if folder.is_empty():
		result = await MapTester.export_into_game(scene, chosen, _setting(MapTester.CHOSEN_MAPS_KEY), get_tree())
	else:
		result = await MapTester.export_and_check(scene, folder, chosen, get_tree())
	if _closed:
		return result
	_button.disabled = false
	_folder_button.disabled = false
	_test_button.disabled = false
	return result


func _setting(key: String) -> String:
	var settings := EditorInterface.get_editor_settings()
	return settings.get_setting(key) if settings.has_setting(key) else ""


func _show_results(title: String, result: Dictionary) -> void:
	var dialog := TestResults.new()
	dialog.title = title
	dialog.show_result(result)
	dialog.game_chosen.connect(_on_game_chosen.bind(title))
	dialog.maps_folder_chosen.connect(_on_maps_folder_chosen.bind(title))
	EditorInterface.popup_dialog_centered(dialog, TestResults.SIZE)


## The game has been found, so does again what the map maker asked for.
func _on_game_chosen(program: String, asked_by: String) -> void:
	EditorInterface.get_editor_settings().set_setting(GameFinder.CHOSEN_KEY, program)
	_again(asked_by)


## The map maker has shown where the game keeps its maps, so that is remembered and tried again.
func _on_maps_folder_chosen(folder: String, asked_by: String) -> void:
	EditorInterface.get_editor_settings().set_setting(MapTester.CHOSEN_MAPS_KEY, folder)
	_again(asked_by)


func _again(asked_by: String) -> void:
	if asked_by == "Test Map":
		_test()
	else:
		_export()


## Opens the game on the map. Only the newest try is of any use, so a test game still open goes first.
func _open_the_game(game: String, folder: String) -> void:
	if _game_process != -1 and OS.is_process_running(_game_process):
		OS.kill(_game_process)
	_game_process = MapTester.play(game, folder)
	var toaster := EditorInterface.get_editor_toaster()
	if _game_process == -1:
		toaster.push_toast("Can't start the game at %s." % game, EditorToaster.SEVERITY_ERROR)
		return
	toaster.push_toast("Opening the game on this map, with bots. It can take a moment.")
	var started := _game_process
	await get_tree().create_timer(GAME_STARTS_WITHIN).timeout
	if _closed:
		return
	if not OS.is_process_running(started) and OS.get_process_exit_code(started) != 0:
		toaster.push_toast("The game stopped as it opened. Try opening it by itself, to see why.", EditorToaster.SEVERITY_ERROR)
