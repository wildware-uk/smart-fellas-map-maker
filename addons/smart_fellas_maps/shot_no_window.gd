extends SceneTree
## Takes a picture of a map from a chosen spot, to hold beside the same spot in the game, and says how
## fast Godot draws it. It needs a display and a graphics card, though the window never has to be seen:
##
##   godot --path <this project> --resolution 1920x1080 \
##       --script res://addons/smart_fellas_maps/shot_no_window.gd \
##       -- res://maps/godot_test.tscn out.png x,y,z tx,ty,tz field_of_view_radians [depth]

const FRAMES_TO_SETTLE := 10
const FRAMES_TO_TIME := 240


func _initialize() -> void:
	# The tree only comes to life on its first frame, and nothing has a place in the world before it.
	await process_frame
	var words := OS.get_cmdline_user_args()
	var root: Node = load(words[0]).instantiate()
	if words.size() > 5:
		root.water_depth = float(words[5])
	get_root().add_child(root)
	# The game with INKOGNITO_STILL_TIME set stands still at the start of its clock, so this matches it.
	if OS.has_environment("INKOGNITO_STILL_TIME"):
		root.hold_water_time_at(0.0)
	var eye := _vector(words[2])
	var camera := Camera3D.new()
	# Both the game and Godot give the field of view from the bottom of the picture to the top.
	camera.fov = rad_to_deg(float(words[4]))
	camera.far = 1000.0
	get_root().add_child(camera)
	camera.look_at_from_position(eye, _vector(words[3]), Vector3.UP)
	camera.make_current()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_take(words[1])


func _vector(words: String) -> Vector3:
	var parts := words.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _take(path: String) -> void:
	for _frame in FRAMES_TO_SETTLE:
		await process_frame
	var started := Time.get_ticks_usec()
	for _frame in FRAMES_TO_TIME:
		await process_frame
	var each := (Time.get_ticks_usec() - started) / 1000.0 / FRAMES_TO_TIME
	print("Godot draws this at %.2f ms a frame, %.0f a second" % [each, 1000.0 / each])
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	quit(0)
