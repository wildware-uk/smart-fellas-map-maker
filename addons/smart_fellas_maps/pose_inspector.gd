@tool
extends EditorInspectorPlugin
## Octopus poses, at the top of the Inspector of a piece or a model of the map's own: a box for each of the
## map's poses, ticked for those the piece offers. In the game, an octopus next to the piece is offered them
## on the near wheel (Q). A piece offers at most OctopusPose.MOST_A_PIECE.

const Kit := preload("kit.gd")
const OctopusPose := preload("octopus_pose.gd")
## Where the add-on's own scripts are: a node with one is a marker, a zone or a pose, not a piece.
const ADD_ON := "res://addons/smart_fellas_maps/"

var undo: EditorUndoRedoManager


func _can_handle(object: Object) -> bool:
	return object is Node3D and is_piece(object)


## Whether `node`, in the open map, is something Export makes a piece of: one of the kit's, a model or scene
## of the map maker's own, or a mesh on its own. Not the map, its seabed, nor anything of the add-on's.
static func is_piece(node: Node3D) -> bool:
	var map := EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null
	if map == null or node == map or not map.is_ancestor_of(node):
		return false
	var script: Script = node.get_script()
	if script != null and script.resource_path.begins_with(ADD_ON):
		return false
	if node.scene_file_path.begins_with(Kit.FOLDER) or not node.scene_file_path.is_empty():
		return true
	return node is MeshInstance3D and node.mesh != null and node.name != "Seabed"


func _parse_begin(object: Object) -> void:
	var piece := object as Node3D
	var map := EditorInterface.get_edited_scene_root()
	var column := VBoxContainer.new()
	var heading := Label.new()
	heading.text = "Octopus poses"
	heading.add_theme_color_override("font_color", OctopusPose.COLOUR.lightened(0.3))
	column.add_child(heading)
	var poses := OctopusPose.nodes_in(map)
	var offered := OctopusPose.offered_by(piece)
	var names: Array[String] = []
	for pose in poses:
		names.append(String(pose.name))
	# A pose deleted or hidden since it was ticked stays listed, so it can be unticked.
	var gone: Array[String] = []
	for pose_name in offered:
		if not names.has(pose_name):
			gone.append(pose_name)
	if names.is_empty() and gone.is_empty():
		var none := Label.new()
		none.text = "The map has no poses of its own yet. Add one from the Poses panel, then tick it here for an octopus next to this to be offered it."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = 160.0
		column.add_child(none)
		add_custom_control(column)
		return
	var boxes: Array[CheckBox] = []
	for pose_name in names + gone:
		var box := CheckBox.new()
		box.text = pose_name
		box.button_pressed = offered.has(pose_name)
		box.tooltip_text = "Tick for an octopus next to %s to be offered this pose on the near wheel (Q). A piece offers up to %d." % [piece.name, OctopusPose.MOST_A_PIECE]
		if gone.has(pose_name):
			box.text = "%s (no shown pose has this name)" % pose_name
			box.tooltip_text = "The map has no shown pose called %s any more: it was deleted, hidden or renamed with this piece offering it. Untick it." % pose_name
			box.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		boxes.append(box)
		column.add_child(box)
		box.toggled.connect(_on_toggled.bind(piece, pose_name, boxes))
	_keep_to_most(piece, boxes)
	add_custom_control(column)


func _on_toggled(on: bool, piece: Node3D, pose_name: String, boxes: Array[CheckBox]) -> void:
	var before := OctopusPose.offered_by(piece)
	var after := before.duplicate()
	if on and not after.has(pose_name):
		after.append(pose_name)
	elif not on:
		after.remove_at(after.find(pose_name))
	undo.create_action("%s %s on %s" % ["Offer" if on else "Stop offering", pose_name, piece.name])
	undo.add_do_method(piece, "set_meta", OctopusPose.OFFERS, after)
	undo.add_undo_method(piece, "set_meta", OctopusPose.OFFERS, before)
	# The Inspector and the octopus's look follow what the piece offers, undone or done again too.
	for pose in OctopusPose.nodes_in(EditorInterface.get_edited_scene_root()):
		undo.add_do_method(pose, "wear_offering_look")
		undo.add_undo_method(pose, "wear_offering_look")
	undo.add_do_method(piece, "notify_property_list_changed")
	undo.add_undo_method(piece, "notify_property_list_changed")
	undo.commit_action()
	_keep_to_most(piece, boxes)


## Greys out the boxes not ticked once `piece` offers as many poses as it may.
static func _keep_to_most(piece: Node3D, boxes: Array[CheckBox]) -> void:
	var full := OctopusPose.offered_by(piece).size() >= OctopusPose.MOST_A_PIECE
	for box in boxes:
		box.disabled = not box.button_pressed and full
