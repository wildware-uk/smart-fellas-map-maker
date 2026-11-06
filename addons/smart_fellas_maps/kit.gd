@tool
extends RefCounted
## What the add-on knows about the kit's pieces: their names in plain words, which group each is in,
## what each costs to draw, and how a painted piece's numbers turn into a place in the world.

const FOLDER := "res://addons/smart_fellas_maps/models/kit/"
const THUMBS := "res://addons/smart_fellas_maps/thumbs/"

## How many numbers one painted piece takes in a map's `painted` list: where it stands (3), which way
## is up (3), its turn about that up, and its size. The same numbers as a piece in map.ron.
const STRIDE := 8

## The panel's groups, in order: a heading, and the starts of the names that belong under it. A name goes
## in the first group with a start that fits it.
const GROUPS := [
	["Coral", ["prop_branch", "prop_bush", "prop_brain", "table_coral", "foliage_fan"]],
	["Sponges", ["prop_tubes"]],
	["Anemones", ["foliage_anemone", "foliage_bigwig"]],
	["Kelp, grass and algae", ["foliage_kelp", "foliage_grass", "foliage_algae"]],
	["Glowing plants", [
		"foliage_bulb", "foliage_fern", "foliage_glowfan", "foliage_lantern", "foliage_mushroom",
		"foliage_strand", "foliage_tubeworm", "foliage_veil", "foliage_wisp",
	]],
	["Shells and pebbles", ["prop_clam", "prop_conch", "prop_pebble"]],
	["Rocks", ["rock_"]],
	["Wrecks and big shapes", ["arch", "wreck", "platform", "prop_crate", "prop_divebell", "prop_bell_lamp", "landmark"]],
]

## What a person calls each kind of piece. The kit's names say what the piece's mesh is called in the
## game, and a map maker shouldn't need to know them.
const PLAIN_NAMES := {
	"arch": "Rock arch",
	"foliage_algae": "Red algae",
	"foliage_anemone": "Teal anemone",
	"foliage_bigwig": "Big peach anemone",
	"foliage_bulb": "Glowing bulbs",
	"foliage_fan": "Sea fan",
	"foliage_fern": "Deep fern",
	"foliage_glowfan": "Pale glowing fan",
	"foliage_grass": "Seagrass tuft",
	"foliage_grass_meadow": "Seagrass patch",
	"foliage_kelp": "Kelp",
	"foliage_lantern": "Tall lantern plant",
	"foliage_mushroom": "Glowing mushrooms",
	"foliage_strand": "Glow-worm threads",
	"foliage_tubeworm": "Tube worms",
	"foliage_veil": "Hanging veil",
	"foliage_wisp": "Glowing wisps",
	"landmark_bell_cable": "Dive bell's broken cable",
	"landmark_buoy": "Buoy",
	"platform_deck": "Platform deck",
	"prop_brain": "Brain coral",
	"prop_branch_pink": "Pink branch coral",
	"prop_branch_purple": "Purple branch coral",
	"prop_bush_orange": "Orange bush coral",
	"prop_bush_peach": "Peach bush coral",
	"prop_bush_pink": "Pink bush coral",
	"prop_bush_purple": "Purple bush coral",
	"prop_bush_red": "Red bush coral",
	"prop_bell_lamp": "Dive bell's lamp",
	"prop_bush_yellow": "Yellow bush coral",
	"prop_clam": "Clam",
	"prop_conch": "Conch",
	"prop_crate": "Crate",
	"prop_divebell": "Dead dive bell",
	"prop_pebble": "Pebble",
	"prop_tubes": "Yellow tube sponge",
	"prop_tubes_blue": "Blue tube sponge",
	"prop_tubes_orange": "Orange tube sponge",
	"rock_boulder": "Boulder",
	"rock_cliff": "Cliff",
	"rock_leg": "Small rock",
	"rock_mossy_boulder": "Mossy boulder",
	"rock_mossy_shelf": "Mossy shelf",
	"rock_pillar": "Rock pillar",
	"rock_shelf": "Rock shelf",
	"rock_slab": "Rock slab",
	"rock_table": "Warm flat rock",
	"rock_warm_boulder": "Warm boulder",
	"rock_warm_shelf": "Warm shelf",
	"table_coral": "Table coral",
	"wreck": "Wreck",
	"wreck_mast": "Wreck's mast",
}

## The starts of the names of the pieces that a brush counts as rock: what things can grow on.
const SOLID_STARTS := ["rock_", "arch", "wreck", "platform"]
## The starts of the names of the pieces the game lets things pass through: plants, and thin landmarks.
const SOFT_STARTS := ["foliage_", "landmark_"]
## The starts of the names of the big solid pieces that aren't rock, which painted can be grown on too.
const BIG_STARTS := ["table_coral", "prop_crate", "prop_divebell"]

## How close to straight up or straight down `up` counts as exactly that: the same cutoff the game's
## maths library uses, one minus two 32-bit float epsilons.
const NEARLY_ONE := 1.0 - 2.0 * 1.1920929e-07

const MISSING := {"mesh": null, "material": null, "triangles": 0, "bounds": AABB(), "radius": 0.5, "solid": false}

static var _infos := {}
static var _triangle_meshes := {}
static var _faces := {}
static var _names: PackedStringArray


## Every piece's name, sorted.
static func names() -> PackedStringArray:
	if _names.is_empty():
		for file in ResourceLoader.list_directory(FOLDER):
			if file.ends_with(".glb"):
				_names.append(file.get_basename())
		_names.sort()
	return _names


static func path_of(kit: String) -> String:
	return FOLDER + kit + ".glb"


static func has(kit: String) -> bool:
	return names().has(kit)


## The name of a kind of piece, from one piece's: prop_bush_red_1 is one of prop_bush_red.
static func kind_of(kit: String) -> String:
	var at := kit.rfind("_")
	if at > 0 and kit.substr(at + 1).is_valid_int():
		return kit.substr(0, at)
	return kit


## This piece's picture, if it has one.
static func thumb_of(kit: String) -> Texture2D:
	var path := THUMBS + kit + ".png"
	if not FileAccess.file_exists(path):
		return null
	return ImageTexture.create_from_image(Image.load_from_file(path))


## What a person calls this piece. Pieces of a kind are numbered, from 1.
static func plain_name(kit: String) -> String:
	var kind := kind_of(kit)
	var words: String = PLAIN_NAMES.get(kind, kind.capitalize())
	if kind == kit:
		return words
	return "%s %d" % [words, int(kit.substr(kind.length() + 1)) + 1]


## Which of GROUPS this piece goes under, as an index.
static func group_of(kit: String) -> int:
	for group in GROUPS.size():
		for start: String in GROUPS[group][1]:
			if kit.begins_with(start):
				return group
	return GROUPS.size() - 1


## Whether things can grow on this piece.
static func is_solid(kit: String) -> bool:
	if not has(kit):
		return false
	for start: String in SOLID_STARTS:
		if kit.begins_with(start):
			return true
	return false


## Whether the game makes this piece solid, so that what's placed can land on it: anything but plants
## and thin landmarks, as the game's PartKind says.
static func is_surface(kit: String) -> bool:
	if not has(kit):
		return false
	for start: String in SOFT_STARTS:
		if kit.begins_with(start):
			return false
	return true


## Whether a painted piece of this kind is something to grow on: rock, or a big solid piece. Painted shells
## and small coral are solid in the game too, but growing on them would heap a brush's pieces on each other.
static func is_grown_on(kit: String) -> bool:
	if is_solid(kit):
		return true
	for start: String in BIG_STARTS:
		if kit.begins_with(start):
			return has(kit)
	return false


## What drawing this piece takes, loaded the first time it's asked for:
## {"mesh", "material", "triangles", "bounds", "radius", "solid"}. A piece the kit doesn't have, as in a map
## made before it went, has no mesh and costs nothing, and Export says so.
static func info(kit: String) -> Dictionary:
	if _infos.has(kit):
		return _infos[kit]
	if not has(kit):
		return MISSING
	var scene: PackedScene = load(path_of(kit))
	var whole := scene.instantiate()
	var part: MeshInstance3D = whole.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = part.mesh
	var bounds := mesh.get_aabb()
	var far := maxf(absf(bounds.position.x), absf(bounds.end.x))
	var deep := maxf(absf(bounds.position.z), absf(bounds.end.z))
	var found := {
		"mesh": mesh,
		"material": mesh.surface_get_material(0),
		"triangles": _triangles_of(mesh),
		"bounds": bounds,
		# How far the piece spreads from its foot: half its width, or its reach if it grows to one side.
		"radius": minf(maxf(far, deep), (bounds.size.x + bounds.size.z) * 0.35),
		"solid": is_solid(kit),
	}
	whole.free()
	_infos[kit] = found
	return found


## What a surface of this piece is, for rays to land on.
static func triangle_mesh(kit: String) -> TriangleMesh:
	if not _triangle_meshes.has(kit):
		var mesh: Mesh = info(kit)["mesh"]
		var surface := TriangleMesh.new()
		surface.create_from_faces(mesh.get_faces())
		_triangle_meshes[kit] = surface
	return _triangle_meshes[kit]


## The faces of this piece, three corners each, in the piece's own space.
static func faces_of(kit: String) -> PackedVector3Array:
	if not _faces.has(kit):
		_faces[kit] = (info(kit)["mesh"] as Mesh).get_faces()
	return _faces[kit]


## Which way face `index` of this piece really faces, in the piece's own space. A TriangleMesh only says
## which way it faces the ray, which can't tell the outside of a rock from the inside.
static func outward_of_face(kit: String, index: int) -> Vector3:
	var faces := faces_of(kit)
	var a := faces[index * 3]
	var b := faces[index * 3 + 1]
	var c := faces[index * 3 + 2]
	return (a - c).cross(a - b).normalized()


static func _triangles_of(mesh: Mesh) -> int:
	var triangles := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			triangles += arrays[Mesh.ARRAY_VERTEX].size() / 3
		else:
			triangles += indices.size() / 3
	return triangles


## The shortest turn from straight up to `up`, the same one the game works out from `up`, including
## for a piece that is exactly upside down.
static func arc_from_up(up: Vector3) -> Quaternion:
	var along := Vector3.UP.dot(up)
	if along < -NEARLY_ONE:
		return Quaternion(Vector3(0.0, 0.0, -1.0), PI)
	var across := Vector3.UP.cross(up)
	return Quaternion(across.x, across.y, across.z, 1.0 + along).normalized()


## Where a piece stands, from the same numbers as map.ron holds: Piece::place in the game.
static func place_of(at: Vector3, up: Vector3, turn: float, size: float) -> Transform3D:
	var rotation := arc_from_up(up) * Quaternion(Vector3.UP, turn)
	return Transform3D(Basis(rotation).scaled_local(Vector3.ONE * size), at)


## The place of painted piece `index` in a kit's list.
static func place_in_list(values: PackedFloat32Array, index: int) -> Transform3D:
	var first := index * STRIDE
	return place_of(
		Vector3(values[first], values[first + 1], values[first + 2]),
		Vector3(values[first + 3], values[first + 4], values[first + 5]),
		values[first + 6],
		values[first + 7]
	)
