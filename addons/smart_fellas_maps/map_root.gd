@tool
class_name SmartFellasMap
extends Node3D
## The top of a map's scene. Its children are what the map holds:
## - a mesh called Seabed, whose height is the height of the flat sand, unless the map has been sculpted, or
##   has no seabed at all;
## - kit pieces, dragged in from addons/smart_fellas_maps/models/kit/;
## - Marker3Ds that the Map panel drops in, whose names say what they are: spawn_octopus_..., spawn_diver_...,
##   food_patch_..., fish_lionfish_..., fish_flounder_..., angler_..., jellies_..., lantern_..., goblin_route_..., wrasse_...,
##   stingray_..., eel_hole_... and groper_hole_...
##
## It also draws the map with the game's water, so that it looks here as it will in the game.

const WaterView := preload("water/water_view.gd")
const WaterLook := preload("water/water_look.gd")
const Kit := preload("kit.gd")
const PaintedBatches := preload("painted_batches.gd")
const SeabedGrid := preload("seabed_grid.gd")

## The pieces on this map changed, whether by a brush, by undo or by hand.
signal pieces_changed
## The play area's half width or ceiling changed, by the panel, a handle, the Inspector or undo.
signal area_changed

## What players call the map.
@export var map_name := "New Map"
## The playable area runs from minus this to plus this on X and Z, in metres.
@export_range(10.0, 250.0) var half_width := 20.0:
	set(value):
		half_width = value
		# The sculpted ground runs on flat past the area's edge, so it's drawn to it.
		show_seabed()
		_show_area()
## The highest anyone can swim, in metres above the valley floor.
@export_range(5.0, 100.0) var ceiling := 13.5:
	set(value):
		ceiling = value
		_show_area()

@export_group("Seabed")
## Whether the map has a seabed. With none, its pieces and models are the only floor, and the game catches
## anyone who falls past them on an unseen floor at the bottom of the map.
@export var has_seabed := true:
	set(value):
		has_seabed = value
		show_seabed()
		pieces_changed.emit()
## Which of the map's own models are soft ground: "sand" or "silt". An octopus can bury itself in them.
## Any other model is rock. They're known by MapExporter.ground_key: a model's file, or a loose mesh's.
@export_storage var soft_models: Dictionary[String, String] = {}:
	set(value):
		soft_models = value
		pieces_changed.emit()

@export_group("Players")
## The fewest players the map is good for, counting everyone in the lobby.
@export_range(2, 32) var fewest_players := 2
## The most on each team, each with a spawn point of their own. 0 means one for each spawn point.
@export_range(0, 32) var most_divers := 0
@export_range(0, 32) var most_octopuses := 0

@export_group("Sea life")
## Whether the shark and the eels may hunt here. The lobby can still turn each off.
@export var hunters := false
## Whether clownfish live round the anemones here.
@export var clownfish := false
@export var whale := true
@export var stingrays := true
## The big shark on its loop, if the map has hunters at all.
@export var shark := true
## Far-off groans, drips and falls of rock, with the sea's bed of sound turned down: this is a cave.
@export var cave_sounds := false
@export var goblin_shark := false
## How many anglerfish lie about at once, of the spots the map lists.
@export_range(1, 8) var anglers_at_once := 3

@export_group("Water")
## How deep the map is, in metres: the deeper, the darker. The Water panel has quick choices.
@export_range(28.0, 1000.0, 0.1) var water_depth := WaterLook.SHALLOW_DEPTH:
	set(value):
		water_depth = value
		show_water()
## Values that replace what the depth gives: a colour under "haze", and numbers under the names in
## WaterLook.LIMITS. The Water panel edits these.
@export var water_overrides := {}:
	set(value):
		water_overrides = value
		show_water()

@export_group("Scripts")
## The folder of this map's scripts: TypeScript (.ts) or plain JavaScript (.js) files, directly inside
## it. Export and Test Map build them into the map, and keep the types file smart-fellas.d.ts there for
## your editor. Empty for a map with no scripts.
@export_dir var scripts_folder := ""

## What the brush has painted: for each kind in the kit, a flat list of numbers, Kit.STRIDE to a piece.
## Thousands of pieces as nodes would make the editor crawl, so these are numbers, drawn in batches, and
## kept out of the Inspector. Export writes them with the rest.
@export_storage var painted: Dictionary[String, PackedFloat32Array] = {}:
	set(value):
		painted = value
		if _batches != null:
			_batches.show_pieces(painted)
		pieces_changed.emit()

## The pieces the Populate button added, which are all in `painted` too, so that it can redo its own work
## and nothing else.
@export_storage var populated: Dictionary[String, PackedFloat32Array] = {}
## What the Populate button places here, by group, as Populate.GROUPS names them. Only scenery, unless the
## map maker ticks the others, so that markers placed by hand as part of the design are never Populate's.
@export_storage var populate_groups: Dictionary[String, bool] = {"scenery": true, "food": false, "creatures": false, "spawns": false}
## Where the Populate button dresses: "both", "seabed" or "meshes", as Recipes.SURFACES.
@export_storage var populate_surfaces := "both"

## The sculpted seabed: how far its grid runs from the middle each way, how many points each side has, the
## height of each a row at a time, and which squares are rock. With no grid, the seabed is flat.
@export_storage var seabed_reach := 0.0:
	set(value):
		seabed_reach = value
		show_seabed()
@export_storage var seabed_side := 0:
	set(value):
		seabed_side = value
		show_seabed()
@export_storage var seabed_heights := PackedFloat32Array():
	set(value):
		seabed_heights = value
		if not _drawing_in_part:
			show_seabed()
@export_storage var seabed_rock := PackedByteArray():
	set(value):
		seabed_rock = value
		if not _drawing_in_part:
			show_seabed()

var _water: Node3D
var _sculpted_sand: MeshInstance3D
var _sculpted_rock: MeshInstance3D
var _sculpted_moss: MeshInstance3D
var _batches: Node3D
## The sculpted ground's numbers as last drawn, from SeabedGrid.shape, with the grid they came from, so that
## a stroke redraws only what it changed.
var _ground_shape := {}
var _ground_grid: RefCounted
var _ground_half_width := 0.0
var _drawing_in_part := false


func _ready() -> void:
	# With no screen, as when exporting from a script, there is nothing to draw on.
	if DisplayServer.get_name() == "headless":
		return
	draw_water()


## Starts drawing this map with the game's water. A test may call it with no screen.
func draw_water() -> void:
	_water = WaterView.new()
	_water.name = "Water view"
	add_child(_water, false, Node.INTERNAL_MODE_BACK)
	show_water()
	_batches = PaintedBatches.new()
	_batches.name = "Painted pieces"
	_batches.set_water(_water)
	add_child(_batches, false, Node.INTERNAL_MODE_BACK)
	_batches.show_pieces(painted)
	_sculpted_sand = _ground_mesh("Sculpted sand")
	_sculpted_rock = _ground_mesh("Sculpted rock")
	_sculpted_moss = _ground_mesh("Sculpted moss")
	show_seabed()


func _ground_mesh(words: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = words
	mesh.mesh = ArrayMesh.new()
	add_child(mesh, false, Node.INTERNAL_MODE_BACK)
	return mesh


## Draws the sculpted seabed, if the map has one, in place of the flat one. It's made from the map's numbers
## each time, and never saved.
func show_seabed() -> void:
	if _sculpted_sand == null:
		return
	var plane := find_child("Seabed", true, true) as MeshInstance3D
	var grid: RefCounted = SeabedGrid.of(self)
	if plane != null:
		plane.visible = grid == null and has_seabed
	_sculpted_sand.visible = grid != null and has_seabed
	_sculpted_rock.visible = grid != null and has_seabed
	_sculpted_moss.visible = grid != null and has_seabed
	_ground_grid = grid
	_ground_shape = {}
	if grid == null:
		return
	_ground_shape = grid.shape(half_width)
	_ground_half_width = half_width
	_fill_every_ground()
	_sculpted_sand.material_override = _water.material_for_sand()
	_sculpted_rock.material_override = _water.material_for_rock(WaterView.ROCK_PICTURE)
	_sculpted_moss.material_override = _water.material_for_rock(WaterView.MOSS_PICTURE)


## A stroke changed the heights between grid points `low` and `high`, and nothing else: draws only that
## part again. A stroke redraws every frame, and drawing the biggest grid whole took 22 ms.
func show_seabed_heights(heights: PackedFloat32Array, low: Vector2i, high: Vector2i) -> void:
	_drawing_in_part = true
	seabed_heights = heights
	_drawing_in_part = false
	if not _can_draw_in_part():
		show_seabed()
		return
	_ground_grid.heights = heights
	_ground_grid.reshape(_ground_shape, low, high)
	_fill_every_ground()


## A stroke painted sand or rock, and changed nothing else.
func show_seabed_rock(rock: PackedByteArray) -> void:
	_drawing_in_part = true
	seabed_rock = rock
	_drawing_in_part = false
	if not _can_draw_in_part():
		show_seabed()
		return
	_ground_grid.rock = rock
	_ground_grid.recut(_ground_shape)
	_fill_every_ground()


func _can_draw_in_part() -> bool:
	if _sculpted_sand == null:
		return false
	return _ground_grid != null and _ground_half_width == half_width and _ground_grid.side == seabed_side and _ground_grid.reach == seabed_reach and seabed_heights.size() == seabed_side * seabed_side and seabed_rock.size() == (seabed_side - 1) * (seabed_side - 1)


func _fill_every_ground() -> void:
	_fill_ground(_sculpted_sand, _ground_shape, _ground_shape["sand"])
	_fill_ground(_sculpted_rock, _ground_shape, _ground_shape["rock"])
	_fill_ground(_sculpted_moss, _ground_shape, _ground_shape["moss"])


static func _fill_ground(ground: MeshInstance3D, shape: Dictionary, triangles: PackedInt32Array) -> void:
	var mesh: ArrayMesh = ground.mesh
	mesh.clear_surfaces()
	if triangles.is_empty():
		return
	var points: PackedVector3Array = shape["points"]
	var pictures: PackedVector2Array = shape["pictures"]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = shape["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = pictures
	arrays[Mesh.ARRAY_INDEX] = triangles
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _show_area() -> void:
	area_changed.emit()
	update_gizmos()


## How many pieces the brush has painted on this map.
func painted_count() -> int:
	var count := 0
	for kit: String in painted:
		count += painted[kit].size() / Kit.STRIDE
	return count


## Swaps in the list a stroke works on, which holds the same pieces to begin with, so nothing to redraw.
func set_painted_quietly(list: Dictionary[String, PackedFloat32Array]) -> void:
	painted = list


## A stroke has appended to this kind's list.
func show_added(kit: String, values: PackedFloat32Array) -> void:
	if _batches != null:
		_batches.show_added(kit, values)
	pieces_changed.emit()


## A stroke has taken pieces out of this kind's list.
func show_kind(kit: String, values: PackedFloat32Array) -> void:
	if _batches != null:
		_batches.show_kind(kit, values)
	pieces_changed.emit()


## Hand-placed pieces came or went.
func notify_pieces_changed() -> void:
	pieces_changed.emit()


## Stops the water's clock at `seconds`, to hold a picture beside the same moment in the game.
func hold_water_time_at(seconds: float) -> void:
	if _water != null:
		_water.hold_time_at(seconds)


## Draws this map's water. The numbers its shaders read are shared by every map open in the editor, so
## the editor calls this on coming to a map's tab.
func show_water() -> void:
	if _water != null:
		_water.show_water(water_depth, water_overrides)
