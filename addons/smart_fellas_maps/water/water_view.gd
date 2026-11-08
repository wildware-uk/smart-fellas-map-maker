@tool
extends Node3D
## Draws a map with the game's water: its lights, haze, caustics, surface, specks and plants' sway. It
## sits inside a SmartFellasMap as an internal node, so that it is never saved and Export never sees it.

const WaterLook := preload("water_look.gd")

const PICTURES := "res://addons/smart_fellas_maps/water/pictures/"
const TONE_TABLE := "res://addons/smart_fellas_maps/water/tony_mc_mapface.bin"
const TONE_TABLE_SIDE := 48
const CAUSTIC_FRAMES := 32
const CAUSTIC_SIZE := 256

## The picture is drawn at the scale of Bevy's default exposure.
const EXPOSURE := 1.0 / (pow(2.0, 9.7) * 1.2)
## How much of the light in the shadows Bevy lets a rough surface's colour have, where Godot lets it
## have all of it.
const FILL_ON_A_ROUGH_SURFACE := 0.452
## Where the sun shines from: the game's SUN_FROM.
const SUN_FROM := Vector3(-6.0, 30.0, -14.0)
## The sun's shadow cascades, as the game has them on Medium.
const SHADOW_REACH := 70.0
const SHADOW_FIRST_BOUND := 12.0
## The game's shaft light at its full: SHAFT_LUMENS, over all the directions a light shines in.
const SHAFT_CANDELA := 1.0e8 / (4.0 * PI)
## How long the water takes to repeat exactly, in seconds: the game's WATER_PERIOD.
const WATER_PERIOD := 600.0
## How high the surface sits over the map's sea base: the game's SURFACE_HEIGHT.
const SURFACE_HEIGHT := 28.0
const SURFACE_SPAN := 360.0
## On Medium: the game's particle count, and the seed and box its specks are placed with.
const SPECK_COUNT := 400
const SPECK_SEED := 41
const SPECK_BOX_HALF := 15.0
## How far a flat seabed runs past the map's edge, and how often the sand repeats in a metre.
const SEABED_BEYOND := 60.0
const SAND_REPEATS_A_METRE := 0.3

## What sculpted rock looks like: the same picture as in the game.
const ROCK_PICTURE := "res://addons/smart_fellas_maps/textures/surfaces/rock_grey.png"
## The patches of moss on it, as the game's SEABED_MOSS_MATERIAL.
const MOSS_PICTURE := "res://addons/smart_fellas_maps/textures/surfaces/rock_mossy.png"
## The name a seabed mesh goes by, as the exporter has it.
const SEABED := "Seabed"

## How a material lets what's behind it show.
enum Seen { SOLID, CUT_OUT, DITHERED }

## The pictures the game makes for itself, loaded once however many maps are open.
static var _pictures := {}

var _sand_look: StandardMaterial3D
## Each painted rock picture's look, by the picture.
var _rock_looks := {}
var _surface: MeshInstance3D
var _sun: DirectionalLight3D
var _environment: Environment
var _speck_material: ShaderMaterial
var _dressed := {}
var _seconds := 0.0
## The sea base and the ground last given to the shaders, which a test with no screen can't read back.
var sea_shown := Vector2.ZERO
var _time_held := false
## The game's lighting, by how a piece lets what's behind it show and then whether it shows both its sides.
var _reef_lit := {
	Seen.SOLID: {false: preload("reef_lit.gdshader"), true: preload("reef_lit_two_sided.gdshader")},
	Seen.CUT_OUT: {false: preload("reef_lit_cut_out.gdshader"), true: preload("reef_lit_cut_out_two_sided.gdshader")},
	Seen.DITHERED: {false: preload("reef_lit_dithered.gdshader"), true: preload("reef_lit_dithered_two_sided.gdshader")},
}


func _ready() -> void:
	top_level = true
	_build()
	_dress_all_under(get_parent())


## Coming back to a map's tab brings this into the tree again, so this has to look out for new pieces.
func _enter_tree() -> void:
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


## The water's look is only for the view. The editor would save it into the map's scene with its
## pictures, megabytes of them, for any mesh that is the scene's own, such as the Seabed.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_undress_all_under(get_parent())
		NOTIFICATION_EDITOR_POST_SAVE:
			_dress_all_under(get_parent())


func _process(delta: float) -> void:
	if _time_held:
		return
	_seconds = fposmod(_seconds + delta, WATER_PERIOD)
	RenderingServer.global_shader_parameter_set_override("sf_time", _seconds)


## Stops the water's clock at `seconds`, to hold a picture beside the same moment in the game.
func hold_time_at(seconds: float) -> void:
	_time_held = true
	_seconds = seconds
	RenderingServer.global_shader_parameter_set_override("sf_time", _seconds)


## Shows the water of a map `depth` metres down, with any of `overrides` as water_look.gd takes them: the
## surface and shade over `sea_base`, as the map's sea_base() gives it, and the shafts aimed at `ground`,
## as its area_base().
func show_water(depth: float, overrides: Dictionary, sea_base: float, ground: float) -> void:
	var look := WaterLook.look_of(depth, overrides)
	_set_globals(look)
	RenderingServer.global_shader_parameter_set_override("sf_sea_base", sea_base)
	RenderingServer.global_shader_parameter_set_override("sf_sea_ground", ground)
	sea_shown = Vector2(sea_base, ground)
	_surface.position.y = sea_base + SURFACE_HEIGHT
	_environment.background_color = _as_colour(look["haze"])
	_environment.ambient_light_color = Color(_as_colour(look["fill"])).linear_to_srgb()
	_environment.ambient_light_energy = look["fill_brightness"] * EXPOSURE * FILL_ON_A_ROUGH_SURFACE
	var lux: float = look["sun_lux"]
	_sun.visible = lux > 0.0
	_sun.shadow_enabled = lux > 0.0
	_sun.light_color = Color(_as_colour(look["sun"])).linear_to_srgb()
	_sun.light_energy = lux * EXPOSURE / PI
	_surface.visible = look["surface"] > 0.0
	_speck_material.set_shader_parameter("speck_colour", _as_colour(look["speck"]).srgb_to_linear())


static func _as_colour(value: Vector3) -> Color:
	return Color(value.x, value.y, value.z)


func _set_globals(look: Dictionary) -> void:
	var haze: Color = _as_colour(look["haze"]).srgb_to_linear()
	var sun: Vector3 = look["sun"] * look["sun_lux"] * EXPOSURE
	var to_sun := SUN_FROM.normalized()
	var facing := Basis.looking_at(-to_sun, Vector3.UP)
	# An override, since the editor puts every plain global back to the project's value whenever it saves
	# the project's settings.
	var set_global := RenderingServer.global_shader_parameter_set_override
	set_global.call("sf_haze", Vector3(haze.r, haze.g, haze.b))
	# How the game's fog turns a distance one can see into how fast it thickens: the distance at which
	# only 5% of what lies there still shows.
	set_global.call("sf_haze_density", sqrt(-log(0.05)) / look["visibility"])
	set_global.call("sf_sun_direct", sun)
	set_global.call("sf_fill", look["fill"] * look["fill_brightness"] * EXPOSURE)
	set_global.call("sf_sun_to", to_sun)
	set_global.call("sf_sun_right", facing.x)
	set_global.call("sf_sun_up", facing.y)
	set_global.call("sf_caustics", look["caustics"])
	set_global.call("sf_shaft_light", SHAFT_CANDELA * EXPOSURE * look["shaft_strength"] / WaterLook.SHALLOW_SHAFT_STRENGTH)
	set_global.call("sf_shaft_colour", look["sun"])
	set_global.call("sf_surface", look["tint"] * look["surface"])


func _build() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)

	_sun = DirectionalLight3D.new()
	_sun.basis = Basis.looking_at(-SUN_FROM.normalized(), Vector3.UP)
	# Godot has two or four cascades, and the game's Medium three. Three of these lie where the game's do.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = SHADOW_REACH
	_sun.directional_shadow_split_1 = SHADOW_FIRST_BOUND / SHADOW_REACH
	_sun.directional_shadow_split_2 = sqrt(SHADOW_FIRST_BOUND / SHADOW_REACH)
	_sun.directional_shadow_split_3 = 0.7
	add_child(_sun)

	_surface = _surface_plane()
	add_child(_surface)
	add_child(_screen_quad())
	add_child(_specks())


func _surface_plane() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = preload("sea_surface.gdshader")
	material.set_shader_parameter("base_ripples", _picture("ripples_base.png"))
	material.set_shader_parameter("glint_ripples", _picture("ripples_glints.png"))
	var plane := PlaneMesh.new()
	plane.size = Vector2(SURFACE_SPAN, SURFACE_SPAN)
	plane.material = material
	var surface := MeshInstance3D.new()
	surface.mesh = plane
	surface.position.y = SURFACE_HEIGHT
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return surface


func _screen_quad() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = preload("screen.gdshader")
	material.render_priority = Material.RENDER_PRIORITY_MIN
	material.set_shader_parameter("tone_table", _tone_table())
	material.set_shader_parameter("shade_bands", _picture("shade_bands.png"))
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = material
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	return screen


func _specks() -> MultiMeshInstance3D:
	_speck_material = ShaderMaterial.new()
	_speck_material.shader = preload("specks.gdshader")
	_speck_material.set_shader_parameter("tone_table", _tone_table())
	var quad := QuadMesh.new()
	quad.material = _speck_material
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = SPECK_COUNT
	for index in SPECK_COUNT:
		var at := Vector3(_unit(index, 1), _unit(index, 2), _unit(index, 3)) * 2.0 - Vector3.ONE
		at *= SPECK_BOX_HALF
		var size := 0.008 + 0.022 * pow(_unit(index, 7), 3.0)
		many.set_instance_transform(index, Transform3D.IDENTITY)
		many.set_instance_color(index, Color(_unit(index, 4), _unit(index, 5), _unit(index, 6)))
		many.set_instance_custom_data(index, Color(at.x, at.y, at.z, size))
	var specks := MultiMeshInstance3D.new()
	specks.multimesh = many
	specks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	specks.custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	return specks


## A repeatable random number in 0..1: the game's pattern::unit, with its seed for specks.
static func _unit(index: int, salt: int) -> float:
	const WORD := 0xFFFFFFFF
	var x := (SPECK_SEED * 0x9E3779B9 + index * 0x85EBCA6B + salt * 0xC2B2AE35) & WORD
	x ^= x >> 16
	x = (x * 0x7FEB352D) & WORD
	x ^= x >> 15
	x = (x * 0x846CA68B) & WORD
	x ^= x >> 16
	return float(x >> 8) / float(1 << 24)


static func _picture(file: String) -> Texture2D:
	if not _pictures.has(file):
		var image := Image.load_from_file(PICTURES + file)
		image.generate_mipmaps()
		_pictures[file] = ImageTexture.create_from_image(image)
	return _pictures[file]


static func _tone_table() -> ImageTexture3D:
	if not _pictures.has("tone"):
		var bytes := FileAccess.get_file_as_bytes(TONE_TABLE)
		var slice_size := TONE_TABLE_SIDE * TONE_TABLE_SIDE * 4
		var slices: Array[Image] = []
		for z in TONE_TABLE_SIDE:
			var slice := bytes.slice(z * slice_size, (z + 1) * slice_size)
			slices.append(Image.create_from_data(TONE_TABLE_SIDE, TONE_TABLE_SIDE, false, Image.FORMAT_RGBE9995, slice))
		var table := ImageTexture3D.new()
		table.create(Image.FORMAT_RGBE9995, TONE_TABLE_SIDE, TONE_TABLE_SIDE, TONE_TABLE_SIDE, false, slices)
		_pictures["tone"] = table
	return _pictures["tone"]


static func _caustic_frames() -> Texture2DArray:
	if not _pictures.has("caustics"):
		var strip := Image.load_from_file(PICTURES + "caustics.png")
		strip.convert(Image.FORMAT_L8)
		var frames: Array[Image] = []
		for frame in CAUSTIC_FRAMES:
			frames.append(strip.get_region(Rect2i(frame * CAUSTIC_SIZE, 0, CAUSTIC_SIZE, CAUSTIC_SIZE)))
		var array := Texture2DArray.new()
		array.create_from_images(frames)
		_pictures["caustics"] = array
	return _pictures["caustics"]


func _on_node_added(node: Node) -> void:
	if get_parent().is_ancestor_of(node) and not is_ancestor_of(node):
		_dress_all_under.call_deferred(node)


func _dress_all_under(node: Node) -> void:
	if node == self or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		_dress_mesh(node)
	for child in node.get_children():
		_dress_all_under(child)


## Gives a mesh the game's lighting, in place of what it came with. An instanced piece's changes are
## never saved, so the scene stays as its maker left it.
func _dress_mesh(piece: MeshInstance3D) -> void:
	if piece.mesh == null:
		return
	var is_seabed := piece.name == SEABED
	for surface in piece.mesh.get_surface_count():
		var from := piece.mesh.surface_get_material(surface)
		if _is_dressed(from) and piece.get_surface_override_material(surface) == null:
			piece.set_surface_override_material(surface, _material_for(from, is_seabed))
	var name_of_mesh := _name_in_the_game(piece.mesh.resource_name)
	var flex := _flex_of(name_of_mesh)
	if flex <= 0.0 or piece.get_instance_shader_parameter("flex") != null:
		return
	piece.set_instance_shader_parameter("flex", flex)
	if name_of_mesh.begins_with("prop_"):
		var bounds := piece.mesh.get_aabb()
		piece.set_instance_shader_parameter("stiff_foot", bounds.position.y)
		piece.set_instance_shader_parameter("stiff_height", bounds.size.y)


## Gives a batch of painted pieces the look a single one gets from `_dress_mesh`. Every kit mesh has one
## surface, so one material does for the batch. A batch is never saved, so it never needs undressing.
func dress_batch(batch: MultiMeshInstance3D, mesh: Mesh) -> void:
	var from := mesh.surface_get_material(0)
	if _is_dressed(from):
		batch.material_override = _material_for(from, false)
	var name_of_mesh := _name_in_the_game(mesh.resource_name)
	var flex := _flex_of(name_of_mesh)
	if flex <= 0.0:
		return
	batch.set_instance_shader_parameter("flex", flex)
	if name_of_mesh.begins_with("prop_"):
		var bounds := mesh.get_aabb()
		batch.set_instance_shader_parameter("stiff_foot", bounds.position.y)
		batch.set_instance_shader_parameter("stiff_height", bounds.size.y)


## Only what the scene owns can be saved with it. A mesh inside a placed piece belongs to that piece's
## model, and taking its numbers away and back on every save only upsets the renderer.
func _undress_all_under(node: Node) -> void:
	if node == self:
		return
	if node is MeshInstance3D and node.mesh != null and node.owner == get_parent():
		for surface in node.mesh.get_surface_count():
			if _dressed.values().has(node.get_surface_override_material(surface)):
				node.set_surface_override_material(surface, null)
		for parameter in ["flex", "stiff_foot", "stiff_height"]:
			if node.get_instance_shader_parameter(parameter) != null:
				node.set_instance_shader_parameter(parameter, null)
	for child in node.get_children():
		_undress_all_under(child)


## Whether a material is drawn with the game's lighting. One that adds to or darkens what's behind it, such
## as a glow or a stain, is unlit anyway, so it keeps its own.
static func _is_dressed(material: Material) -> bool:
	return material is BaseMaterial3D and (material as BaseMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_MIX


## How `material` lets what's behind it show: a fence has holes cut at its threshold, and a decal or glass,
## blended or dithered, is dithered.
static func _seen_through(material: BaseMaterial3D) -> Seen:
	match material.transparency:
		BaseMaterial3D.TRANSPARENCY_DISABLED:
			return Seen.SOLID
		BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			return Seen.CUT_OUT
	return Seen.DITHERED


func _material_for(from: BaseMaterial3D, is_seabed: bool) -> ShaderMaterial:
	if _dressed.has(from):
		return _dressed[from]
	var material := ShaderMaterial.new()
	var two_sided := from.cull_mode == BaseMaterial3D.CULL_DISABLED
	var seen := _seen_through(from)
	material.shader = _reef_lit[seen][two_sided]
	if seen == Seen.CUT_OUT:
		material.set_shader_parameter("alpha_cut", from.alpha_scissor_threshold)
	material.set_shader_parameter("vertex_colour", from.vertex_color_use_as_albedo)
	material.set_shader_parameter("vertex_colour_srgb", from.vertex_color_is_srgb)
	material.set_shader_parameter("grow", from.grow_amount if from.grow else 0.0)
	material.set_shader_parameter("caustic_frames", _caustic_frames())
	material.set_shader_parameter("shade_bands", _picture("shade_bands.png"))
	var tint := from.albedo_color.srgb_to_linear()
	material.set_shader_parameter("perceptual_roughness", from.roughness)
	if is_seabed:
		var reach: float = get_parent().area_reach()
		material.set_shader_parameter("albedo_tex", _picture("sand.png"))
		material.set_shader_parameter("perceptual_roughness", 0.9)
		material.set_shader_parameter("world_layout", Vector2(SAND_REPEATS_A_METRE, reach + SEABED_BEYOND))
	else:
		material.set_shader_parameter("albedo_tex", from.albedo_texture)
		material.set_shader_parameter("base_colour", tint)
	_dressed[from] = material
	return material


## The material for sculpted sand, with the game's lighting.
func material_for_sand() -> ShaderMaterial:
	if _sand_look == null:
		_sand_look = StandardMaterial3D.new()
	return _material_for(_sand_look, true)


## The material for painted rock wearing `picture`, ROCK_PICTURE or MOSS_PICTURE, with the game's lighting.
func material_for_rock(picture: String) -> ShaderMaterial:
	if not _rock_looks.has(picture):
		var look := StandardMaterial3D.new()
		look.albedo_texture = load(picture)
		_rock_looks[picture] = look
	return _material_for(_rock_looks[picture], false)


## What the game calls a mesh: Godot puts the file's name in front, as in kelp_foliage_kelp_0.
static func _name_in_the_game(imported: String) -> String:
	for start in ["foliage_", "prop_"]:
		var at := imported.find(start)
		if at >= 0:
			return imported.substr(at)
	return imported


## How freely a piece bends, from its mesh's name: the game's sway::flex_of.
static func _flex_of(mesh_name: String) -> float:
	var parts := mesh_name.split("_")
	if parts.size() < 2:
		return 0.0
	match parts[0]:
		"foliage":
			match parts[1]:
				"kelp":
					return 1.0
				"grass":
					return 0.18
				"fan":
					return 0.1
			return 0.17
		"prop":
			match parts[1]:
				"branch", "bush", "tubes":
					return 0.01
				"brain":
					return 0.005
	return 0.0
