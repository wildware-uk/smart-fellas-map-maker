extends SceneTree
## Makes the pieces panel's pictures, once, into thumbs/. They're checked in, so that nobody opening the
## panel ever waits for them. It needs a display and a graphics card, though the window never has to be
## seen. Run it after a piece in the kit changes:
##
##   godot --path <this project> --script res://addons/smart_fellas_maps/thumbs_no_window.gd

const Kit := preload("kit.gd")

const SIDE := 96
## Drawn at twice the size and shrunk, so that thin plants don't break up.
const OVERSIZE := 2
const BACKDROP := Color(0.06, 0.2, 0.28)


func _initialize() -> void:
	await process_frame
	var view := SubViewport.new()
	view.size = Vector2i(SIDE * OVERSIZE, SIDE * OVERSIZE)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(view)
	var world := WorldEnvironment.new()
	world.environment = _environment()
	view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.6
	view.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 30.0
	view.add_child(camera)
	camera.make_current()
	for kit in Kit.names():
		var scene: PackedScene = load(Kit.path_of(kit))
		var piece := scene.instantiate()
		view.add_child(piece)
		_frame(camera, Kit.info(kit)["bounds"])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		image.resize(SIDE, SIDE, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		image.save_png(ProjectSettings.globalize_path(Kit.THUMBS + kit + ".png"))
		view.remove_child(piece)
		piece.free()
	print("Made pictures of %d pieces." % Kit.names().size())
	quit(0)


func _environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKDROP
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	return environment


## Looks from above and to one side, far enough back to fit the whole of `bounds`.
func _frame(camera: Camera3D, bounds: AABB) -> void:
	var middle := bounds.get_center()
	var reach := bounds.size.length() * 0.5
	var away := reach / sin(deg_to_rad(camera.fov * 0.5)) * 1.02
	camera.look_at_from_position(middle + Vector3(0.6, 0.55, 1.0).normalized() * away, middle, Vector3.UP)
	camera.near = maxf(away - reach * 1.5, 0.01)
	camera.far = away + reach * 1.5
