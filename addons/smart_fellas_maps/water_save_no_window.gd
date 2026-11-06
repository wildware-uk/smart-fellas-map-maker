extends SceneTree
## Does to a map what the editor does on saving, with no window, so that a test can see the water stays
## out of the file and comes back after:
##
##   godot --headless --path <this project> --script res://addons/smart_fellas_maps/water_save_no_window.gd \
##       -- res://maps/godot_test.tscn <out file>
##
## It prints whether the Seabed was dressed before the save, during it, and after it.


func _initialize() -> void:
	# The tree only comes to life on its first frame, and nothing has a place in the world before it.
	await process_frame
	var words := OS.get_cmdline_user_args()
	var root: Node = load(words[0]).instantiate()
	get_root().add_child(root)
	root.draw_water()
	var seabed: MeshInstance3D = root.get_node("Seabed")
	print("dressed before saving: ", seabed.get_surface_override_material(0) != null)
	root.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	print("dressed while saving: ", seabed.get_surface_override_material(0) != null)
	var packed := PackedScene.new()
	packed.pack(root)
	var saved := ResourceSaver.save(packed, words[1])
	root.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	print("dressed after saving: ", seabed.get_surface_override_material(0) != null)
	quit(0 if saved == OK else 1)
