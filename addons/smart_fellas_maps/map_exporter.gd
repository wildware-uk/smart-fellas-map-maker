@tool
extends RefCounted
## Writes a scene as a map package: one <map>.sfm file, a zip holding map.ron and the map's own models,
## which the game's checker reads.
##
## Godot and the game agree on what the numbers mean: Y up, right-handed, one unit a metre. A piece's
## turn is about its own up, in the same order as Piece::rotation in the game.

const Kit := preload("kit.gd")
const NameLetters := preload("name_letters.gd")
const SeabedGrid := preload("seabed_grid.gd")
const WaterLook := preload("water/water_look.gd")

const KIT_FOLDER := Kit.FOLDER
const FORMAT := 2
## The game's SCULPTED_FORMAT, for a map with a sculpted seabed.
const SCULPTED_FORMAT := 3
## The game's NO_SEABED_FORMAT, for a map with no seabed, or with models of its own that are sand or silt.
const NO_SEABED_FORMAT := 5
## The game's MODELS_FORMAT, for a map with models of its own.
const MODELS_FORMAT := 4
## Where a map's own models go in its package.
const ASSETS_FOLDER := "assets"
## The end of a map package's file name: Smart Fellas Map.
const SFM_EXTENSION := "sfm"
## What a package held when it was a folder, before .sfm files: what Export takes out of an old one.
const OLD_PACKAGE_FILES := ["map.ron", "preview.png"]
## The game's MAX_ASSET_BYTES and MAX_MAP_MODELS.
const MOST_MODEL_BYTES := 67108864
const MOST_MODELS := 32
## The game's limits on one model, from src/map/model.rs.
const MOST_MODEL_TRIANGLES := 30000
const MOST_MODEL_CORNERS := 60000
const MOST_MODEL_MATERIALS := 8
const MOST_MODEL_PICTURES := 8
const MOST_PICTURE_SIDE := 2048
const MOST_PICTURE_BYTES := 8388608
## How many pixels across the game draws a model's picture at most, so a bigger one Export rebuilds is made
## this size, which loses nothing.
const PICTURE_SIDE_DRAWN := 1024
## The game's limits on all the map's own models together, from src/map/check.rs.
const MOST_MAP_MATERIALS := 16
const MOST_MAP_TRIANGLES := 300000
const MOST_MAP_CORNERS := 300000
const MOST_MAP_PICTURE_BYTES := 25165824
## How long a model's name in the package may be, before ".glb".
const MOST_MODEL_NAME_LETTERS := 56
const SCALES := Vector2(0.1, 10.0)
## The game's limits on a map's size, on how far past it scenery may stand, how far below the floor
## anything may be, on spawn points and patches, and on who may play.
const HALF_WIDTHS := Vector2(10.0, 250.0)
const CEILINGS := Vector2(5.0, 100.0)
const SCENERY_BEYOND := 60.0
const BELOW_THE_FLOOR := 12.0
const MOST_SPAWNS := 256
const MOST_PATCHES := 256
const MOST_PLAYERS := 32
## The game's MAX_SEABED_SIDE. The add-on makes a grid smaller than this.
const MOST_SEABED_SIDE := 257
## The game's limits on how close a sculpted seabed's points are and how steep it is.
const CLOSEST_SEABED_POINTS := 0.25
const MOST_SEABED_SLOPE := 6.0
const MOST_ANGLERS_AT_ONCE := 8
## The game grows food in at most two thirds of a map's patches, and in at least one.
const FEWEST_PATCHES := 2
## The game's limits on wildlife.
const MOST_FISH := 256
const MOST_ANGLER_SPOTS := 64
const MOST_LANTERN_SCHOOLS := 10
const MOST_JELLY_GROUPS := 16
const MOST_JELLIES := 80
const MOST_IN_A_JELLY_GROUP := 16
const JELLY_SPREADS := Vector2(0.5, 12.0)
const LANTERN_ROAMS := Vector2(0.0, 25.0)
const MOST_ROUTE_POINTS := 64
## The game's MAX_HAUNTS: the most of each of wrasse spots, stingray stops, eel holes and groper holes.
const MOST_HAUNTS := 64
const FEWEST_ROUTE_POINTS := 2
const FISH_FLOUNDER := "fish_flounder_"
const FISH_LIONFISH := "fish_lionfish_"
const ANGLER := "angler_"
const JELLIES := "jellies_"
const LANTERN := "lantern_"
const GOBLIN_ROUTE := "goblin_route_"
## Where some animals keep to: each list of map.ron's haunts section, the start of its markers' names, and
## what the checker calls one and many of them.
const HAUNTS := [
	["wrasse", "wrasse_", "Wrasse spot", "wrasse spots"],
	["stingrays", "stingray_", "Stingray stop", "stingray stops"],
	["eels", "eel_hole_", "Eel hole", "eel holes"],
	["gropers", "groper_hole_", "Groper hole", "groper holes"],
]
const JELLY_HUES := ["Teal", "Blue", "Pink"]
## The game's MAX_CUSTOM_PIECES. The game refuses anything over it however the package was made.
const MOST_PIECES := 4096
## The game's MAX_MAP_FILE_BYTES: the most map.ron may weigh.
const MOST_FILE_BYTES := 2097152
## How unequal a piece's sides may be scaled before it counts as stretched.
const STRETCH_SLACK := 0.0001
## The game takes food and fish under the ground, but nobody would ever find them there. A marker dropped
## on the ground may sit a hair under it, so only more than this counts, in metres.
const UNDER_THE_GROUND := 0.05
## The most letters a map's name may have, and the everyday punctuation it may use: the game's check_name.
const MOST_NAME_LETTERS := 40
const NAME_PUNCTUATION := " '-.,!&:()"
## Folder names Windows keeps for itself, whatever comes after them.
const WINDOWS_NAMES := ["con", "prn", "aux", "nul", "com0", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt0", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]
## How many food spots ring each food patch, and how far out.
const SPOTS_IN_A_PATCH := 4
const SPOT_RING := 0.6
## How near sculpted ground a patch must be for its food to lie on that ground, in metres.
const FOOD_FOLLOWS_WITHIN := 1.0
## How small a marker's scale can get before it no longer says which way it faces.
const FLAT_AS_NOTHING := 0.000001
## A piece placed by hand in this Godot group goes in the map under its node's name, so the map's
## script can find it; one in SWITCH_GROUP is a switch players can use as well.
const SCRIPT_GROUP := "script"
const SWITCH_GROUP := "switch"
## The game's MAX_NAMED_PIECES and MAX_NAME_LENGTH.
const MOST_NAMED_PIECES := 256
const MOST_PIECE_NAME_LETTERS := 64
const SPAWN_OCTOPUS := "spawn_octopus_"
const SPAWN_DIVER := "spawn_diver_"
const FOOD_PATCH := "food_patch_"


## What Export needs from a scene, once it has been read.
class Scene:
	var seabed_height := 0.0
	var has_seabed := false
	var pieces: Array[Dictionary] = []
	var octopus_spawns: Array[Dictionary] = []
	var diver_spawns: Array[Dictionary] = []
	var patches: Array[Dictionary] = []
	var fish: Array[Dictionary] = []
	var angler_spots: Array[Dictionary] = []
	var lantern_schools: Array[Dictionary] = []
	var jellies: Array[Dictionary] = []
	var goblin_route: Array[Dictionary] = []
	## Each list of the haunts section by its name in map.ron, as {"at", "node"}.
	var haunts := {"wrasse": [], "stingrays": [], "eels": [], "gropers": []}
	## The map's own models, by their name in the package's assets/, as their file in this project.
	var models := {}
	## The pictures those models keep beside themselves, by their name in assets/, as their file here.
	var pictures := {}
	## The surfaces of the map's pieces and seabed, for what lies on them, made once Export needs it.
	var finder: RefCounted
	## The models Export made itself, from a model the game can't take as it is, by their name in assets/,
	## as the .glb's bytes. Their names are in `models` too.
	var built := {}
	## What all the map's own models come to between them, as the game counts it.
	var model_totals := {"triangles": 0, "corners": 0, "materials": 0, "picture_bytes": 0}
	var problems: Array[String] = []
	## What the map maker should know, as {"words", "node"}, that doesn't stop the map.
	var warnings: Array[Dictionary] = []
	## The node each problem is on, if it's on one.
	var problem_nodes := {}
	## How many pieces and markers were left out for being hidden, and the first node whose eye hid any.
	var hidden := {"pieces": 0, "markers": 0, "first": null}
	## What the map's lists hold, in the order map.ron has them, under the words the game's checker
	## calls them by: a node, or words for something with no node.
	var sources := {
		"Piece": [], "Octopus spawn": [], "Diver spawn": [], "Food patch": [], "Food spot": [], "Fish": [],
		"Anglerfish spot": [], "Lantern fish school": [], "Jellyfish group": [], "Goblin shark route point": [],
		"Wrasse spot": [], "Stingray stop": [], "Eel hole": [], "Groper hole": [],
	}

	func jelly_count() -> int:
		var total := 0
		for group in jellies:
			total += group["count"]
		return total

	func problem_on(node: Node, words: String) -> void:
		problems.append(words)
		problem_nodes[words] = node

	## Counts a piece or a marker left out, hidden by `hider`, the node whose eye is off.
	func left_out_hidden(hider: Node, what: String) -> void:
		hidden[what] += 1
		if hidden["first"] == null:
			hidden["first"] = hider


## Where the Export button writes. In the game's own repository that's target/godot/out/, beside its
## other build output. Anywhere else, such as the add-on's download, it's exported_maps/ in the project,
## made with a .gdignore so that Godot doesn't import what's written there.
static func default_out_folder() -> String:
	return out_folder_for(ProjectSettings.globalize_path("res://"))


## Where Export writes for the project in the folder `project`, as default_out_folder says.
static func out_folder_for(project: String) -> String:
	if _is_the_games_repository(project.path_join("../..")):
		return project.path_join("../../target/godot/out").simplify_path()
	var folder := project.path_join("exported_maps")
	DirAccess.make_dir_recursive_absolute(folder)
	var ignore := folder.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var file := FileAccess.open(ignore, FileAccess.WRITE)
		if file != null:
			file.close()
	return folder


## Whether `folder` is the game's own repository: a Cargo.toml there that names the game's crate, not
## some other Rust project a map maker happens to keep the add-on inside.
static func _is_the_games_repository(folder: String) -> bool:
	var cargo := FileAccess.get_file_as_string(folder.path_join("Cargo.toml"))
	return cargo.contains('name = "inkognito"')


## Writes the scene under `root` as `out_folder`/<map>.sfm, in place of any it wrote there before.
## Gives back {"package": the .sfm it wrote, "sources": what its lists came from, as in Scene}, or
## {"problems": what stops it, in plain words, "nodes": the node each is on, if it's on one}.
## "warnings" says what doesn't stop it but is worth knowing, as {"words", "node"}.
static func export_map(root: Node, out_folder: String) -> Dictionary:
	if not (root is SmartFellasMap):
		return {"problems": ["This scene's top node isn't a SmartFellasMap. Open a map's scene first."]}
	if not root.is_inside_tree():
		return {"problems": ["The scene isn't open yet, so nothing in it has a place. Open it first."]}
	var scene := _read_scene(root)
	if not scene.problems.is_empty():
		return {"problems": scene.problems, "nodes": scene.problem_nodes}
	var text := _map_text(root, scene)
	var too_heavy := file_problem(text.to_utf8_buffer().size())
	if not too_heavy.is_empty():
		return {"problems": [too_heavy]}
	var made := DirAccess.make_dir_recursive_absolute(out_folder)
	if made != OK:
		return {"problems": ["Can't make the folder %s: %s." % [out_folder, error_string(made)]]}
	var name := _folder_name(root.map_name)
	var folder := _building_folder(name)
	var built := _build_folder(scene, text, folder)
	var package := out_folder.path_join("%s.%s" % [name, SFM_EXTENSION])
	if built.is_empty():
		built = pack_folder(folder, package)
	_remove_folder(folder)
	if not built.is_empty():
		return {"problems": [built]}
	_remove_old_package(out_folder.path_join(name))
	return {"package": package, "sources": scene.sources, "warnings": scene.warnings}


## Where Export puts a package together before packing it: a folder of the add-on's own, never where the
## game looks, so the game can't come across half a map.
static func _building_folder(name: String) -> String:
	return ProjectSettings.globalize_path("user://smart_fellas_export").path_join(name)


## Writes the package's files into `folder`, emptied first. Gives back what went wrong, or nothing.
static func _build_folder(scene: Scene, text: String, folder: String) -> String:
	_remove_folder(folder)
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if made != OK:
		return "Can't make the folder %s: %s." % [folder, error_string(made)]
	var copied := _copy_models(scene, folder)
	if not copied.is_empty():
		return copied
	var file := FileAccess.open(folder.path_join("map.ron"), FileAccess.WRITE)
	if file == null:
		var why := error_string(FileAccess.get_open_error())
		return "Can't write to %s: %s." % [folder, why]
	file.store_string(text)
	file.close()
	return ""


## Packs every file in `folder` into the .sfm `to`, by its path inside the folder with forward slashes.
## It is written beside `to` first and then takes its place, so the game never reads half of one. Gives
## back what went wrong, or nothing.
static func pack_folder(folder: String, to: String) -> String:
	var partial := to + ".part"
	var zip := ZIPPacker.new()
	var opened := zip.open(partial)
	if opened != OK:
		return "Can't write %s: %s." % [to, error_string(opened)]
	for inside in _files_inside(folder, ""):
		var bytes := FileAccess.get_file_as_bytes(folder.path_join(inside))
		var read := FileAccess.get_open_error()
		var went := zip.start_file(inside)
		if went == OK:
			went = zip.write_file(bytes)
		if went == OK:
			went = zip.close_file()
		if read != OK or went != OK:
			zip.close()
			DirAccess.remove_absolute(partial)
			var why := error_string(read if read != OK else went)
			return "Can't pack %s into %s: %s." % [inside, to.get_file(), why]
	zip.close()
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	var moved := DirAccess.rename_absolute(partial, to)
	if moved != OK:
		DirAccess.remove_absolute(partial)
		return "Can't write %s: %s." % [to, error_string(moved)]
	return ""


## The bytes of the file `inside` the .sfm `package`, or nothing if it isn't there.
static func packed_file(package: String, inside: String) -> PackedByteArray:
	var zip := ZIPReader.new()
	if zip.open(package) != OK:
		return PackedByteArray()
	var bytes := zip.read_file(inside) if zip.file_exists(inside) else PackedByteArray()
	zip.close()
	return bytes


## The text of the file `inside` the .sfm `package`, or "" if it isn't there.
static func packed_text(package: String, inside: String) -> String:
	return packed_file(package, inside).get_string_from_utf8()


## Every file under `folder`, by its path from there, in order.
static func _files_inside(folder: String, under: String) -> Array[String]:
	var found: Array[String] = []
	var here := folder.path_join(under) if not under.is_empty() else folder
	var files := Array(DirAccess.get_files_at(here))
	files.sort()
	for file: String in files:
		found.append(under.path_join(file) if not under.is_empty() else file)
	var folders := Array(DirAccess.get_directories_at(here))
	folders.sort()
	for inner: String in folders:
		found.append_array(_files_inside(folder, under.path_join(inner) if not under.is_empty() else inner))
	return found


## Takes away a folder Export built, and everything in it.
static func _remove_folder(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for inside in _files_inside(folder, ""):
		DirAccess.remove_absolute(folder.path_join(inside))
	var folders := [folder]
	var at := 0
	while at < folders.size():
		for inner in DirAccess.get_directories_at(folders[at]):
			folders.append(folders[at].path_join(inner))
		at += 1
	folders.reverse()
	for each: String in folders:
		DirAccess.remove_absolute(each)


## Takes out the folder an older Export wrote for this map before maps were one .sfm file, so the game
## doesn't list the map twice. Only what Export put there goes: map.ron, preview.png and the models in
## assets/. If anything else is in it, it's someone's own, and the folder stays.
static func _remove_old_package(folder: String) -> void:
	if not FileAccess.file_exists(folder.path_join("map.ron")):
		return
	var assets := folder.path_join(ASSETS_FOLDER)
	for file in DirAccess.get_files_at(folder):
		if not file in OLD_PACKAGE_FILES:
			return
	for inner in DirAccess.get_directories_at(folder):
		if inner != ASSETS_FOLDER:
			return
	if DirAccess.dir_exists_absolute(assets):
		if not DirAccess.get_directories_at(assets).is_empty():
			return
		for file in DirAccess.get_files_at(assets):
			if not (file.ends_with(".glb") or file.ends_with(".png")):
				return
		for file in DirAccess.get_files_at(assets):
			DirAccess.remove_absolute(assets.path_join(file))
		DirAccess.remove_absolute(assets)
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


## Puts each of the map's own models in the package's assets/, by the name map.ron calls it, with any
## picture it keeps beside itself, and takes out whatever an earlier export left there. Gives back
## what went wrong, or nothing.
static func _copy_models(scene: Scene, folder: String) -> String:
	var assets := folder.path_join(ASSETS_FOLDER)
	if DirAccess.dir_exists_absolute(assets):
		for old in DirAccess.get_files_at(assets):
			DirAccess.remove_absolute(assets.path_join(old))
	if scene.models.is_empty():
		if DirAccess.dir_exists_absolute(assets):
			DirAccess.remove_absolute(assets)
		return ""
	var made := DirAccess.make_dir_recursive_absolute(assets)
	if made != OK:
		return "Can't make the folder %s: %s." % [assets, error_string(made)]
	for name in scene.models:
		var source: String = scene.models[name]
		var bytes: PackedByteArray = scene.built[name] if scene.built.has(name) else FileAccess.get_file_as_bytes(source)
		if bytes.is_empty():
			return "Can't read the model %s." % source
		var written := _write_file(assets.path_join(name), bytes)
		if not written.is_empty():
			return written
	for name in scene.pictures:
		var written := _write_file(assets.path_join(name), FileAccess.get_file_as_bytes(scene.pictures[name]))
		if not written.is_empty():
			return written
	return ""


static func _write_file(path: String, bytes: PackedByteArray) -> String:
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return "Can't write to %s: %s." % [path.get_base_dir(), error_string(FileAccess.get_open_error())]
	out.store_buffer(bytes)
	out.close()
	return ""


## Whether a picture's name, as a model gives it, is one the game takes beside the model in assets/:
## a plain lowercase file name ending .png, never a path.
static func plain_picture_name(name: String) -> bool:
	if name.length() > 64 or not name.ends_with(".png") or name.contains("..") or name.begins_with("."):
		return false
	for letter in name:
		var ok := (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9") or letter in ["_", "-", "."]
		if not ok:
			return false
	return true


## Checks the pictures a model keeps beside itself and adds them to what Export copies, or says on
## `node` what's wrong. Gives back whether they're all fine.
static func _read_model_pictures(node: Node, source: String, bytes: PackedByteArray, scene: Scene) -> bool:
	for picture in model_pictures_beside(bytes):
		if not plain_picture_name(picture):
			scene.problem_on(node, "%s's model %s uses the picture %s. The game takes only a .png with a plain lowercase name beside the model. Pack its pictures into the .glb when you export it from Blender." % [node.name, source.get_file(), picture])
			return false
		var beside := source.get_base_dir().path_join(picture)
		if not FileAccess.file_exists(beside):
			scene.problem_on(node, "%s's model %s uses the picture %s, which isn't beside it. Put it there, or pack its pictures into the .glb." % [node.name, source.get_file(), picture])
			return false
		var taken: String = scene.pictures.get(picture, beside)
		if taken != beside and FileAccess.get_md5(taken) != FileAccess.get_md5(beside):
			scene.problem_on(node, "Two of the map's models use different pictures called %s. Rename one, or pack the pictures into each .glb." % picture)
			return false
		scene.pictures[picture] = beside
	return true


## The description inside a .glb, or an empty Dictionary if it isn't one.
static func glb_description(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "glTF":
		return {}
	var length := bytes.decode_u32(12)
	if bytes.decode_u32(16) != 0x4E4F534A or 20 + length > bytes.size():
		return {}
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## The pictures a .glb keeps outside itself, by their names.
static func model_pictures_beside(bytes: PackedByteArray) -> Array[String]:
	var found: Array[String] = []
	for image in glb_description(bytes).get("images", []):
		if image is Dictionary and image.has("uri"):
			found.append(String(image["uri"]))
	return found


## Whether a .glb gives any of its materials a picture.
static func model_has_a_picture(bytes: PackedByteArray) -> bool:
	for material in glb_description(bytes).get("materials", []):
		if material is Dictionary and material.get("pbrMetallicRoughness", {}).has("baseColorTexture"):
			return true
	return false


## The name a model in this project gets in a package: its file's name, made plain, and kept the same
## from one export to the next.
static func model_name(path: String) -> String:
	var plain := ""
	for letter in path.get_file().get_basename().to_lower():
		var ok := (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9") or letter in ["_", "-"]
		plain += letter if ok else "_"
	plain = plain.substr(0, MOST_MODEL_NAME_LETTERS).lstrip("_-")
	if plain.is_empty() or plain in WINDOWS_NAMES:
		plain = "model_" + plain
	return plain + ".glb"


## What's wrong with a map's file weighing this many bytes, in plain words, or nothing.
static func file_problem(bytes: int) -> String:
	if bytes <= MOST_FILE_BYTES:
		return ""
	return "The map's file comes to %.1f MB, and the most it can weigh is 2 MB. Remove some pieces." % (bytes / 1048576.0)


## What's wrong with a map's name, in plain words, or nothing. The game would refuse the same.
static func name_problem(map_name: String) -> String:
	if map_name.strip_edges().is_empty():
		return "The map has no name. Give it one, on the top node, in the Inspector."
	if map_name.length() > MOST_NAME_LETTERS:
		return "The map's name has %d letters. The limit is %d." % [map_name.length(), MOST_NAME_LETTERS]
	for letter in map_name:
		if not NameLetters.is_letter_or_digit(letter.unicode_at(0)) and not NAME_PUNCTUATION.contains(letter):
			return "The map's name, %s, has an odd character: %s. Use letters, digits and everyday punctuation." % [map_name, letter]
	return ""


## What `export_map` gave back, for a person to read.
static func result_words(result: Dictionary) -> String:
	if result.has("package"):
		return "Exported to %s" % result["package"]
	return "This map can't be exported yet:\n- %s" % "\n- ".join(result["problems"])


## Every one of the map's own models under `root`, as {"node", "path", "made"}: a model dropped into the
## scene, however it came. "made" is "copied" for a .glb, which goes in the package as it is, or "built" for
## anything else Export turns into a .glb itself: a .gltf, .fbx, .obj or .blend, a scene of its own, a
## model made local, or a mesh on its own. "path" is the file it came from, or for a mesh on its own, what
## tells it apart from other meshes.
static func own_model_pieces(root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	_collect_own_models(root, found)
	return found


static func _collect_own_models(node: Node, found: Array[Dictionary]) -> void:
	for child in node.get_children():
		if hidden_by_eye(child):
			continue
		var path: String = child.scene_file_path
		if path.begins_with(KIT_FOLDER):
			continue
		if path.get_extension().to_lower() == "glb":
			found.append({"node": child, "path": path, "made": "copied"})
		elif not path.is_empty():
			# A scene holding kit pieces is said to be a problem in _read_children, and one with nothing to
			# draw in left_out.
			if not _holds_kit_pieces(child) and not meshes_in(child).is_empty():
				found.append({"node": child, "path": path, "made": "built"})
		elif child is MeshInstance3D and child.mesh != null and child.name != "Seabed":
			found.append({"node": child, "path": _look_of(child), "made": "built", "alone": true})
			_collect_own_models(child, found)
		else:
			_collect_own_models(child, found)


## What tells a mesh on its own apart from others: its mesh and whatever it's drawn with in place of that
## mesh's own materials, so that two copies coloured apart come out apart.
static func _look_of(part: MeshInstance3D) -> String:
	var mesh: Mesh = part.mesh
	var look := mesh.resource_path if not mesh.resource_path.is_empty() else "mesh %d" % mesh.get_instance_id()
	if part.material_override != null:
		look += " over %d" % part.material_override.get_instance_id()
	for surface in part.get_surface_override_material_count():
		var over := part.get_surface_override_material(surface)
		if over != null and over is BaseMaterial3D:
			look += " %d:%d" % [surface, over.get_instance_id()]
	return look


## The meshes drawn in `node` and under it, that a model made from it would hold.
static func meshes_in(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.mesh != null:
		meshes.append(node)
	for part in node.find_children("*", "MeshInstance3D", true, false):
		if part.mesh != null and part.is_visible_in_tree():
			meshes.append(part)
	return meshes


## What left_out calls a scene of the map maker's own with no mesh showing in it.
const EMPTY_SCENE := "scene with no mesh showing"

## Anything under `root` that draws something and that neither the kit, a model of the map's own nor the
## add-on accounts for, which Export would leave out, as {"node", "what"}: a CSG shape, a MultiMesh, words
## or a sprite in 3D, particles, or a scene of the map maker's own with none of its meshes showing.
static func left_out(root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	_collect_left_out(root, found)
	return found


static func _collect_left_out(node: Node, found: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child is Node3D and not child.visible:
			continue
		var path: String = child.scene_file_path
		if path.begins_with(KIT_FOLDER) or path.get_extension().to_lower() == "glb":
			continue
		if not path.is_empty() and not _holds_kit_pieces(child) and meshes_in(child).is_empty():
			found.append({"node": child, "what": EMPTY_SCENE})
			continue
		if child is GeometryInstance3D and not child is MeshInstance3D:
			found.append({"node": child, "what": child.get_class()})
		_collect_left_out(child, found)


## Every kit piece under `root`, as {"node", "kit"}, in the order of the scene.
static func kit_pieces(root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	_collect_pieces(root, root, found)
	return found


static func _collect_pieces(root: Node, node: Node, found: Array[Dictionary]) -> void:
	for child in node.get_children():
		if hidden_by_eye(child):
			continue
		if child.scene_file_path.begins_with(KIT_FOLDER):
			found.append({"node": child, "kit": child.scene_file_path.get_file().get_basename()})
		elif child.scene_file_path.is_empty():
			_collect_pieces(root, child, found)


## Whether `node` is hidden with the eye in the Scene panel, which takes it, and all in it, out of the map.
## Not the flat Seabed: the add-on hides that itself on a sculpted map, and what's in it stays in.
static func hidden_by_eye(node: Node) -> bool:
	return node is Node3D and not node.visible and not _is_the_seabed(node)


## Whether `node` is the map's flat Seabed: the first node of that name, the one map_root.gd's show_seabed
## finds, not any other that happens to share the name.
static func _is_the_seabed(node: Node) -> bool:
	if node.name != "Seabed" or not (node is Node3D):
		return false
	var root := _root_of(node)
	return root != null and root.find_child("Seabed", true, true) == node


## Whether there are kit pieces inside this scene-in-a-scene, where Export can't see them.
static func _holds_kit_pieces(node: Node) -> bool:
	for child in node.get_children():
		if child.scene_file_path.begins_with(KIT_FOLDER) or _holds_kit_pieces(child):
			return true
	return false


static func _folder_name(map_name: String) -> String:
	var words := map_name.to_lower().strip_edges()
	var folder := ""
	for letter in words:
		var plain := (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9")
		folder += letter if plain else "_"
	# Windows won't make a folder called con, or anything like it.
	return folder + "_map" if folder in WINDOWS_NAMES else folder


static func _read_scene(root: SmartFellasMap) -> Scene:
	var scene := read_rules(root)
	for found in kit_pieces(root):
		_read_piece(found["node"], found["kit"], scene)
	_read_own_models(root, scene)
	_read_painted(root, scene)
	_check_piece_names(scene)
	scene.finder = load("res://addons/smart_fellas_maps/surface_finder.gd").new(root)
	_warn_of_spawns_over_nothing(root, scene)
	_warn_of_food_over_nothing(root, scene)
	if scene.pieces.size() > MOST_PIECES:
		scene.problems.append("The map places %d pieces, and the most a map can place is %d. Remove some." % [scene.pieces.size(), MOST_PIECES])
	return scene


## Everything but the pieces, which is quick enough for the Map panel to say as things change.
static func read_rules(root: SmartFellasMap) -> Scene:
	var scene := Scene.new()
	var bad_name := name_problem(root.map_name)
	if not bad_name.is_empty():
		scene.problems.append(bad_name)
	_check_range("The map's half width", root.half_width, HALF_WIDTHS, scene)
	_check_range("The map's ceiling", root.ceiling, CEILINGS, scene)
	_read_children(root, scene)
	if not root.has_seabed:
		scene.has_seabed = false
	elif not scene.has_seabed:
		scene.problems.append("The map has no seabed. Add a mesh called Seabed at the height of the sand, or untick Seabed in the Map panel for a map with none.")
	elif root.seabed_side == 0 and (scene.seabed_height < -BELOW_THE_FLOOR or scene.seabed_height > root.ceiling):
		scene.problems.append("The seabed is at a height of %s. It must be from %s to the map's ceiling, %s." % [scene.seabed_height, -BELOW_THE_FLOOR, root.ceiling])
	_check_sculpted(root, scene)
	for team in [["octopus", scene.octopus_spawns], ["diver", scene.diver_spawns]]:
		if team[1].is_empty():
			scene.problems.append("This map has no %s spawn points: place some from the Map panel, or tick Spawns in Populate." % team[0])
		elif team[1].size() > MOST_SPAWNS:
			scene.problems.append("The map has %d %s spawn points. The limit is %d. Remove some." % [team[1].size(), team[0], MOST_SPAWNS])
	_check_patches(scene)
	_check_wildlife(root, scene)
	_check_players(root, scene)
	_warn_of_close_spawns(root, scene)
	_check_spawns_above_the_ground(root, scene)
	_warn_of_hidden(scene)
	scene.problems.append_array(WaterLook.problems_with(root.water_depth, root.water_overrides))
	return scene


## The game holds a sculpted seabed to these too.
static func _check_sculpted(root: SmartFellasMap, scene: Scene) -> void:
	if not root.has_seabed or (root.seabed_side == 0 and root.seabed_heights.is_empty()):
		return
	var side: int = root.seabed_side
	if side < 2 or side > MOST_SEABED_SIDE or root.seabed_heights.size() != side * side or root.seabed_rock.size() != (side - 1) * (side - 1):
		scene.problems.append("The sculpted seabed's numbers doesn't add up: %d points a side and %d heights. Press Flatten in the Map panel." % [side, root.seabed_heights.size()])
		return
	if not (root.seabed_reach >= 1.0 and root.seabed_reach <= root.half_width + SCENERY_BEYOND):
		scene.problems.append("The sculpted seabed reaches %s m from the middle. It must be from 1 to %s." % [root.seabed_reach, root.half_width + SCENERY_BEYOND])
	var highest := -INF
	var lowest := INF
	for height in root.seabed_heights:
		if is_nan(height) or is_inf(height):
			scene.problems.append("The sculpted seabed has a height that isn't a real number. Press Flatten in the Map panel.")
			return
		highest = maxf(highest, height)
		lowest = minf(lowest, height)
	if highest > root.ceiling or lowest < -BELOW_THE_FLOOR:
		scene.problems.append("The sculpted seabed reaches a height of %.1f and %.1f. It must stay from %s to the map's ceiling, %s. Raise the ceiling, or lower the ground." % [lowest, highest, -BELOW_THE_FLOOR, root.ceiling])
	var spacing: float = root.seabed_reach * 2.0 / (side - 1)
	if spacing < CLOSEST_SEABED_POINTS:
		scene.problems.append("The sculpted seabed's points are %.2f m apart. They must be at least %s m apart. Press Flatten in the Map panel." % [spacing, CLOSEST_SEABED_POINTS])
		return
	var steepest := 0.0
	for index in side * side:
		if index % side != side - 1:
			steepest = maxf(steepest, absf(root.seabed_heights[index] - root.seabed_heights[index + 1]))
		if index + side < side * side:
			steepest = maxf(steepest, absf(root.seabed_heights[index] - root.seabed_heights[index + side]))
	if steepest / spacing > MOST_SEABED_SLOPE:
		scene.problems.append("The sculpted seabed rises %.1f m in a metre somewhere, and the most the game takes is %s m. Smooth it." % [steepest / spacing, MOST_SEABED_SLOPE])


## With no seabed, a spawn point with nothing under it drops whoever starts there to the bottom of the map.
## The map maker may mean it, so it's only a warning.
static func _warn_of_spawns_over_nothing(root: SmartFellasMap, scene: Scene) -> void:
	if root.has_seabed:
		return
	for spawn in scene.octopus_spawns + scene.diver_spawns:
		var at: Vector3 = spawn["at"]
		if scene.finder.find(at, Vector3(at.x, -BELOW_THE_FLOOR - 1.0, at.z)).is_empty():
			scene.warnings.append({
				"words": "%s has nothing under it, and the map has no seabed: anyone starting there falls to the bottom of the map. Move it over a piece." % spawn["node"].name,
				"node": spawn["node"],
			})


## With no seabed, a food patch with nothing under it hangs in open water, where its food floats.
static func _warn_of_food_over_nothing(root: SmartFellasMap, scene: Scene) -> void:
	if root.has_seabed:
		return
	for patch in scene.patches:
		var up: Vector3 = patch["up"]
		if scene.finder.find(patch["at"] + up * FOOD_FOLLOWS_WITHIN, patch["at"] - up * FOOD_FOLLOWS_WITHIN).is_empty():
			scene.warnings.append({
				"words": "%s has nothing under it, and the map has no seabed: its food floats in open water. Move it onto a piece." % patch["node"].name,
				"node": patch["node"],
			})


## The game refuses a spawn point under the seabed, where anyone starting would be stuck.
static func _check_spawns_above_the_ground(root: SmartFellasMap, scene: Scene) -> void:
	var grid: RefCounted = SeabedGrid.of(root)
	for spawn in scene.octopus_spawns + scene.diver_spawns:
		var at: Vector3 = spawn["at"]
		var ground: float = grid.height_at(at.x, at.z) if grid != null else scene.seabed_height
		if scene.has_seabed and at.y < ground:
			scene.problem_on(spawn["node"], "%s is under the seabed, where anyone starting there would be stuck. Lift it." % spawn["node"].name)


static func _check_range(what: String, value: float, limits: Vector2, scene: Scene) -> void:
	if not (value >= limits.x and value <= limits.y):
		scene.problems.append("%s is %s. It must be from %s to %s." % [what, value, limits.x, limits.y])


static func _check_patches(scene: Scene) -> void:
	if scene.patches.is_empty():
		scene.problems.append("This map has no food patches: place at least %d from the Map panel, or tick Food in Populate." % FEWEST_PATCHES)
	elif scene.patches.size() < FEWEST_PATCHES:
		scene.problems.append("The map has one food patch. Food only grows in two thirds of them at once, so it needs at least %d." % FEWEST_PATCHES)
	elif scene.patches.size() > MOST_PATCHES:
		scene.problems.append("The map has %d food patches. The limit is %d. Remove some." % [scene.patches.size(), MOST_PATCHES])


static func _check_wildlife(root: SmartFellasMap, scene: Scene) -> void:
	var counted := [
		["fish", scene.fish.size(), MOST_FISH],
		["anglerfish spots", scene.angler_spots.size(), MOST_ANGLER_SPOTS],
		["schools of lantern fish", scene.lantern_schools.size(), MOST_LANTERN_SCHOOLS],
		["groups of jellyfish", scene.jellies.size(), MOST_JELLY_GROUPS],
		["jellyfish", scene.jelly_count(), MOST_JELLIES],
		["goblin shark route points", scene.goblin_route.size(), MOST_ROUTE_POINTS],
	]
	for haunt in HAUNTS:
		counted.append([haunt[3], scene.haunts[haunt[0]].size(), MOST_HAUNTS])
	for row in counted:
		if row[1] > row[2]:
			scene.problems.append("The map has %d %s. The limit is %d. Remove some." % [row[1], row[0], row[2]])
	if scene.goblin_route.size() == 1:
		scene.problem_on(scene.goblin_route[0]["node"], "The goblin shark's route has one point. It needs at least %d, or none to take the shark's." % FEWEST_ROUTE_POINTS)
	if not root.goblin_shark and not scene.goblin_route.is_empty():
		scene.warnings.append({"words": "The map has a goblin shark route, and no goblin shark. Turn it on under Sea life.", "node": scene.goblin_route[0]["node"]})
	if not root.stingrays and not scene.haunts["stingrays"].is_empty():
		scene.warnings.append({"words": "The map has stingray stops, and no stingrays. Turn them on under Sea life.", "node": scene.haunts["stingrays"][0]["node"]})
	for holes in ["eels", "gropers"]:
		if not root.hunters and not scene.haunts[holes].is_empty():
			scene.warnings.append({"words": "The map has %s, and nothing hunts on it. Turn on Shark and eels hunt under Sea life." % ("eel holes" if holes == "eels" else "groper holes"), "node": scene.haunts[holes][0]["node"]})


## How many may play on each team, as {"divers", "octopuses"}: as the map says, or by its spawn points, and
## never more than the game takes.
static func team_sizes(root: SmartFellasMap, scene: Scene) -> Dictionary:
	var divers: int = root.most_divers
	var octopuses: int = root.most_octopuses
	if octopuses == 0:
		octopuses = mini(scene.octopus_spawns.size(), MOST_PLAYERS / 2 if divers == 0 else MOST_PLAYERS - divers)
	if divers == 0:
		divers = mini(scene.diver_spawns.size(), maxi(MOST_PLAYERS - octopuses, 1))
	if root.most_octopuses == 0:
		octopuses = mini(scene.octopus_spawns.size(), maxi(MOST_PLAYERS - divers, 1))
	return {"divers": divers, "octopuses": octopuses}


static func _check_players(root: SmartFellasMap, scene: Scene) -> void:
	if root.most_divers < 0 or root.most_octopuses < 0:
		scene.problems.append("Most divers and Most octopuses must be 0 or more. 0 means one for each spawn point.")
		return
	if root.anglers_at_once < 1 or root.anglers_at_once > MOST_ANGLERS_AT_ONCE:
		scene.problems.append("Anglerfish at once is %d. It must be from 1 to %d." % [root.anglers_at_once, MOST_ANGLERS_AT_ONCE])
	var sizes := team_sizes(root, scene)
	var most: int = sizes["divers"] + sizes["octopuses"]
	if most > MOST_PLAYERS:
		scene.problems.append("The teams come to %d players, and the game takes %d. Lower Most divers or Most octopuses." % [most, MOST_PLAYERS])
	if root.fewest_players < 2 or root.fewest_players > most:
		scene.problems.append("The map's fewest players is %d, and its teams come to %d. It must be at least 2 and no more than that." % [root.fewest_players, most])
	for team in [["divers", "diver", scene.diver_spawns], ["octopuses", "octopus", scene.octopus_spawns]]:
		if sizes[team[0]] > team[2].size() and not team[2].is_empty():
			scene.problems.append("The map takes up to %d %s, and has %d %s spawn points. Each needs one: add some or lower the limit." % [sizes[team[0]], team[0], team[2].size(), team[1]])


## Teams that start in sight of each other make for a short, dull round. It's the map maker's call.
static func _warn_of_close_spawns(root: SmartFellasMap, scene: Scene) -> void:
	for octopus in scene.octopus_spawns:
		for diver in scene.diver_spawns:
			var at_octopus: Vector3 = octopus["at"]
			var at_diver: Vector3 = diver["at"]
			var apart := Vector2(at_octopus.x, at_octopus.z).distance_to(Vector2(at_diver.x, at_diver.z))
			if apart < root.half_width:
				scene.warnings.append({
					"words": "The teams start close: %s and %s are %.0f m apart, under half the map's width." % [octopus["node"].name, diver["node"].name, apart],
					"node": octopus["node"],
				})
				return


## Reads the seabed and the markers under `node`. A marker hidden with the eye in the Scene panel, or in a
## hidden group, is out of the map, as a piece is, and counted so the map maker is told. The flat Seabed
## is read hidden or not.
static func _read_children(node: Node, scene: Scene, hider: Node = null) -> void:
	for child in node.get_children():
		# The node whose eye is off, so that Show it on the warning goes to the eye to click.
		var hidden_by: Node = hider if hider != null else (child if hidden_by_eye(child) else null)
		var hidden := hidden_by != null
		if not child.scene_file_path.is_empty():
			var path: String = child.scene_file_path
			if hidden and (path.begins_with(KIT_FOLDER) or path.get_extension().to_lower() in ["glb", "gltf"]):
				scene.left_out_hidden(hidden_by, "pieces")
			elif not path.begins_with(KIT_FOLDER) and _holds_kit_pieces(child):
				scene.problem_on(child, "%s is a scene inside this one, and Export can't see the pieces in it. Right-click it in the Scene panel and choose Make Local." % child.name)
			continue
		if _is_the_seabed(child):
			if _root_of(child).has_seabed:
				_read_seabed(child, scene)
		elif child is Marker3D:
			if hidden:
				scene.left_out_hidden(hidden_by, "markers")
			else:
				_read_marker(child, scene)
		_read_children(child, scene, hidden_by)


## Tells the map maker how many hidden things are out of the map, so hiding a group never loses half a
## map without a word.
static func _warn_of_hidden(scene: Scene) -> void:
	var pieces: int = scene.hidden["pieces"]
	var markers: int = scene.hidden["markers"]
	if pieces + markers == 0:
		return
	var counts: Array[String] = []
	if pieces > 0:
		counts.append("%d piece%s" % [pieces, "" if pieces == 1 else "s"])
	if markers > 0:
		counts.append("%d marker%s" % [markers, "" if markers == 1 else "s"])
	var one := pieces + markers == 1
	scene.warnings.append({
		"words": "%s %s hidden, so %s left out of the map. Show %s with the eye in the Scene panel to put %s back." % [
			" and ".join(counts), "is" if one else "are", "it's" if one else "they're", "it" if one else "them", "it" if one else "them"
		],
		"node": scene.hidden["first"],
	})


static func _read_seabed(seabed: Node3D, scene: Scene) -> void:
	var up := seabed.global_transform.basis.y.normalized()
	if not up.is_equal_approx(Vector3.UP):
		scene.problem_on(seabed, "The Seabed is tilted. It must lie flat: only its height counts.")
	scene.has_seabed = true
	scene.seabed_height = seabed.global_position.y


## Which way a marker faces, however it's scaled: Basis.get_euler only reads a basis with no scale in it.
## A marker scaled by a negative number is mirrored, which a turn can't be, so that's taken back out.
static func _yaw_of(basis: Basis) -> float:
	var turn := basis.orthonormalized()
	if turn.determinant() < 0.0:
		turn = turn.scaled(Vector3(-1.0, -1.0, -1.0))
	return turn.get_euler().y


static func _read_marker(marker: Marker3D, scene: Scene) -> void:
	var words := String(marker.name)
	var place := marker.global_transform
	if absf(place.basis.determinant()) < FLAT_AS_NOTHING:
		scene.problem_on(marker, "%s is scaled down to nothing, so it faces no way at all. Set its scale back to 1." % words)
		return
	if words.begins_with(SPAWN_OCTOPUS):
		scene.octopus_spawns.append({"at": place.origin, "yaw": _yaw_of(place.basis), "node": marker})
		scene.sources["Octopus spawn"].append(marker)
	elif words.begins_with(SPAWN_DIVER):
		scene.diver_spawns.append({"at": place.origin, "yaw": _yaw_of(place.basis), "node": marker})
		scene.sources["Diver spawn"].append(marker)
	elif words.begins_with(FOOD_PATCH):
		scene.patches.append({"at": place.origin, "up": place.basis.y.normalized(), "basis": place.basis.orthonormalized(), "node": marker})
		scene.sources["Food patch"].append(marker)
		for _spot in SPOTS_IN_A_PATCH:
			scene.sources["Food spot"].append(marker)
		_warn_if_under_the_ground(marker, scene)
	elif not _read_wildlife(marker, words, place, scene):
		scene.problem_on(marker, "The marker %s means nothing. Drop markers in from the Map panel." % words)
		return
	if _check_in_the_map(marker, _root_of(marker), scene) and words.begins_with(FOOD_PATCH):
		_check_food_spots_in_the_map(marker, _root_of(marker), scene.patches.back(), scene)


## Takes a wildlife marker. Gives back whether this was one.
static func _read_wildlife(marker: Marker3D, words: String, place: Transform3D, scene: Scene) -> bool:
	var yaw := _yaw_of(place.basis)
	if words.begins_with(FISH_FLOUNDER) or words.begins_with(FISH_LIONFISH):
		var kind := "Flounder" if words.begins_with(FISH_FLOUNDER) else "Lionfish"
		scene.fish.append({"kind": kind, "at": place.origin, "yaw": yaw})
		scene.sources["Fish"].append(marker)
		_warn_if_under_the_ground(marker, scene)
	elif words.begins_with(ANGLER):
		scene.angler_spots.append({"at": place.origin, "yaw": yaw})
		scene.sources["Anglerfish spot"].append(marker)
		_warn_if_under_the_ground(marker, scene)
	elif words.begins_with(LANTERN):
		_warn_if_under_the_ground(marker, scene)
		var roam: float = marker.get("roam") if marker.get("roam") != null else 4.0
		if not (roam >= LANTERN_ROAMS.x and roam <= LANTERN_ROAMS.y):
			scene.problem_on(marker, "%s roams %s m. It must be from %s to %s." % [marker.name, roam, LANTERN_ROAMS.x, LANTERN_ROAMS.y])
		scene.lantern_schools.append({"at": place.origin, "roam": roam})
		scene.sources["Lantern fish school"].append(marker)
	elif words.begins_with(JELLIES):
		_read_jellies(marker, place, scene)
	elif _read_haunt(marker, words, place, scene):
		pass
	elif words.begins_with(GOBLIN_ROUTE):
		_check_above_the_ground(marker, scene)
		scene.goblin_route.append({"at": place.origin, "node": marker, "number": words.trim_prefix(GOBLIN_ROUTE).to_int()})
		scene.goblin_route.sort_custom(func(one: Dictionary, other: Dictionary) -> bool: return one["number"] < other["number"])
		scene.sources["Goblin shark route point"].clear()
		for point in scene.goblin_route:
			scene.sources["Goblin shark route point"].append(point["node"])
	else:
		return false
	return true


## Takes a marker of one of the haunts lists. Gives back whether it was one.
static func _read_haunt(marker: Marker3D, words: String, place: Transform3D, scene: Scene) -> bool:
	for haunt in HAUNTS:
		if words.begins_with(haunt[1]):
			_check_above_the_ground(marker, scene)
			scene.haunts[haunt[0]].append({"at": place.origin, "node": marker})
			scene.sources[haunt[2]].append(marker)
			return true
	return false


static func _read_jellies(marker: Marker3D, place: Transform3D, scene: Scene) -> void:
	_check_above_the_ground(marker, scene)
	var count: int = marker.get("count") if marker.get("count") != null else 8
	var spread: float = marker.get("spread") if marker.get("spread") != null else 4.5
	var hue: int = marker.get("colour") if marker.get("colour") != null else 0
	if count < 1 or count > MOST_IN_A_JELLY_GROUP:
		scene.problem_on(marker, "%s has %d jellyfish. It must have from 1 to %d." % [marker.name, count, MOST_IN_A_JELLY_GROUP])
	if not (spread >= JELLY_SPREADS.x and spread <= JELLY_SPREADS.y):
		scene.problem_on(marker, "%s spreads %s m. It must be from %s to %s." % [marker.name, spread, JELLY_SPREADS.x, JELLY_SPREADS.y])
	if hue < 0 or hue >= JELLY_HUES.size():
		scene.problem_on(marker, "%s has a colour the game doesn't know. Choose Teal, Blue or Pink." % marker.name)
		hue = 0
	scene.jellies.append({"at": place.origin, "count": count, "hue": JELLY_HUES[hue], "spread": spread})
	scene.sources["Jellyfish group"].append(marker)


## What swims can't go under the ground.
static func _check_above_the_ground(marker: Marker3D, scene: Scene) -> void:
	var under := _how_far_under_the_ground(marker)
	if under > 0.0:
		scene.problem_on(marker, "%s is %.1f m below the floor. Raise it." % [marker.name, under])


static func _warn_if_under_the_ground(marker: Marker3D, scene: Scene) -> void:
	var under := _how_far_under_the_ground(marker)
	if under > UNDER_THE_GROUND:
		scene.warnings.append({"words": "%s is %.1f m under the ground, where nobody will find it. Lift it." % [marker.name, under], "node": marker})


## How far under the ground this marker is, in metres, or 0 or less if it isn't.
static func _how_far_under_the_ground(marker: Marker3D) -> float:
	var root := _root_of(marker)
	var at := marker.global_position
	if not root.has_seabed:
		return -BELOW_THE_FLOOR - at.y
	var grid: RefCounted = SeabedGrid.of(root)
	var seabed := root.find_child("Seabed", true, true) as Node3D
	var flat: float = seabed.global_position.y if seabed != null else 0.0
	var ground: float = grid.height_at(at.x, at.z) if grid != null else flat
	return ground - at.y


static func _root_of(node: Node) -> SmartFellasMap:
	var above := node
	while above != null and not (above is SmartFellasMap):
		above = above.get_parent()
	return above as SmartFellasMap


## The game refuses a food spot outside the map too, and they ring the marker.
static func _check_food_spots_in_the_map(marker: Marker3D, root: SmartFellasMap, patch: Dictionary, scene: Scene) -> void:
	for index in SPOTS_IN_A_PATCH:
		var spot := _food_spot(patch, index)
		if absf(spot.x) > root.half_width or absf(spot.z) > root.half_width or spot.y < -BELOW_THE_FLOOR or spot.y > root.ceiling:
			scene.problem_on(marker, "%s is too near the map's edge: its food would grow at (%.1f, %.1f, %.1f), and the map reaches %s m each way from the middle and %s m up. Move it in by %s m." % [marker.name, spot.x, spot.y, spot.z, root.half_width, root.ceiling, SPOT_RING])
			return


## Where food spot `index` of a patch is, on the patch's own ground.
static func _food_spot(patch: Dictionary, index: int) -> Vector3:
	var angle := TAU * index / SPOTS_IN_A_PATCH
	return patch["at"] + patch["basis"] * (Vector3(cos(angle), 0.0, sin(angle)) * SPOT_RING)


## The game refuses a marker outside the map, so this says so first, and which one.
## Gives back whether it's in.
static func _check_in_the_map(marker: Marker3D, root: SmartFellasMap, scene: Scene) -> bool:
	var at := marker.global_position
	if not at.is_finite():
		scene.problem_on(marker, "%s has a number that isn't a real number. Delete it and drop in another." % marker.name)
		return false
	elif absf(at.x) > root.half_width or absf(at.z) > root.half_width or at.y < -BELOW_THE_FLOOR or at.y > root.ceiling:
		scene.problem_on(marker, "%s is at (%.1f, %.1f, %.1f), outside the map. It reaches %s m each way from the middle and %s m up." % [marker.name, at.x, at.y, at.z, root.half_width, root.ceiling])
		return false
	return true


## Each of the map's own models placed in it, given the name it has in the package. A model is checked
## here for what the game's checker would refuse, so the map maker hears why in Godot; the game's checker
## still reads every part of it. A model the game can't take as it is, but Godot can read, is turned into a
## .glb the game takes. Nothing is left out without a word.
static func _read_own_models(root: SmartFellasMap, scene: Scene) -> void:
	var names_of := {}
	for found in own_model_pieces(root):
		var node: Node3D = found["node"]
		var path: String = found["path"]
		if not names_of.has(path):
			var name := _free_model_name(model_name(path if not found.has("alone") else String(node.name)), scene)
			var bytes := PackedByteArray()
			var source := ProjectSettings.globalize_path(path) if not found.has("alone") else path
			if found["made"] == "copied":
				bytes = FileAccess.get_file_as_bytes(source)
				if bytes.is_empty():
					scene.problem_on(node, "%s's model %s can't be read." % [node.name, path])
					continue
				if glb_description(bytes).is_empty():
					scene.problem_on(node, "%s's model %s isn't a .glb the game can read. Export it again from Blender as glTF Binary (.glb)." % [node.name, path.get_file()])
					continue
				# Pictures the game won't take, such as JPEG, as models from Sketchfab often have, or ones too
				# big, are made into ones it will.
				# So is one that needs a glTF extension the game can't read, such as WebP pictures or packed
				# meshes, which Godot can.
				if not _pictures_problem(bytes, source).is_empty() or not glb_description(bytes).get("extensionsRequired", []).is_empty():
					bytes = PackedByteArray()
			if bytes.is_empty():
				bytes = built_glb(node, found.has("alone"))
				if bytes.is_empty():
					scene.problem_on(node, "%s can't be made into a model for the game. Export it from Blender as glTF Binary (.glb), copy that into this project, and drag it in instead." % node.name)
					continue
				scene.built[name] = bytes
			if bytes.size() > MOST_MODEL_BYTES:
				scene.problem_on(node, "%s's model %s is %.1f MB. The most is 64 MB. Make it smaller." % [node.name, path.get_file(), bytes.size() / 1048576.0])
				continue
			var called := "%s's model %s" % [node.name, path.get_file()] if not found.has("alone") else String(node.name)
			var tally := model_tally(glb_description(bytes))
			var too_much := _model_limits_problem(tally)
			if too_much.is_empty():
				too_much = _pictures_problem(bytes, source)
			if not too_much.is_empty():
				scene.problem_on(node, "%s %s" % [called, too_much])
				continue
			for key: String in scene.model_totals:
				scene.model_totals[key] += tally[key] if key != "picture_bytes" else _picture_bytes(bytes, source)
			if not scene.built.has(name) and not _read_model_pictures(node, source, bytes, scene):
				continue
			if not model_has_a_picture(bytes):
				scene.warnings.append({"words": "%s has no picture, only colours. An octopus copying it wears its plain colour." % node.name, "node": node})
			names_of[path] = name
			scene.models[name] = source
		_read_piece(node, "", scene, names_of[path])
	for other in left_out(root):
		if other["what"] == EMPTY_SCENE:
			scene.problem_on(other["node"], "%s is a scene with no mesh showing in it, so nothing of it would come out of Export. Show its meshes, or delete it." % other["node"].name)
		else:
			scene.problem_on(other["node"], "%s is a %s, which the game can't draw. Only kit pieces and models come out of Export. Turn it into a mesh (for a CSG shape: select it, then CSG > Bake Mesh Instance), or delete it." % [other["node"].name, other["what"]])
	if scene.models.size() > MOST_MODELS:
		scene.problems.append("The map uses %d models of its own. The most is %d. Remove some." % [scene.models.size(), MOST_MODELS])
	_check_model_totals(scene)


## The game's limits on all the map's own models together.
static func _check_model_totals(scene: Scene) -> void:
	var totals: Dictionary = scene.model_totals
	if totals["materials"] > MOST_MAP_MATERIALS:
		scene.problems.append("The map's own models use %d materials between them, and the game takes %d. Share materials between models, or remove some." % [totals["materials"], MOST_MAP_MATERIALS])
	if totals["triangles"] > MOST_MAP_TRIANGLES:
		scene.problems.append("The map's own models have %d triangles between them, and the game takes %d. Simplify them." % [totals["triangles"], MOST_MAP_TRIANGLES])
	if totals["corners"] > MOST_MAP_CORNERS:
		scene.problems.append("The map's own models have %d corners between them, and the game takes %d. Simplify them." % [totals["corners"], MOST_MAP_CORNERS])
	if totals["picture_bytes"] > MOST_MAP_PICTURE_BYTES:
		scene.problems.append("The map's own models' pictures come to %.1f MB between them, and the game takes %d MB. Make them smaller, or share pictures between models." % [totals["picture_bytes"] / 1048576.0, MOST_MAP_PICTURE_BYTES / 1048576])


## `wanted`, or the same with a number after it if another model has that name already.
static func _free_model_name(wanted: String, scene: Scene) -> String:
	var name := wanted
	var number := 2
	while scene.models.has(name):
		name = "%s_%d.glb" % [wanted.get_basename(), number]
		number += 1
	return name


## What a .glb holds as the game counts it, object by object from its scene, so that a mesh drawn twice
## counts twice: {"triangles", "corners", "materials", "pictures", "picture_bytes"}, the last two as the
## materials it draws with refer to them. The same walk as src/map/model.rs.
static func model_tally(description: Dictionary) -> Dictionary:
	var tally := {"triangles": 0, "corners": 0, "materials": 0, "pictures": description.get("images", []).size(), "picture_bytes": 0}
	var accessors: Array = description.get("accessors", [])
	var meshes: Array = description.get("meshes", [])
	var nodes: Array = description.get("nodes", [])
	var scenes: Array = description.get("scenes", [])
	var scene_index: int = description.get("scene", 0)
	var waiting: Array = scenes[scene_index].get("nodes", []).duplicate() if scene_index >= 0 and scene_index < scenes.size() else []
	var seen := {}
	var used := {}
	while not waiting.is_empty():
		var index: int = waiting.pop_back()
		if seen.has(index) or index < 0 or index >= nodes.size():
			continue
		seen[index] = true
		var node: Dictionary = nodes[index]
		waiting.append_array(node.get("children", []))
		var mesh: int = node.get("mesh", -1)
		if mesh < 0 or mesh >= meshes.size():
			continue
		for primitive: Dictionary in meshes[mesh].get("primitives", []):
			var position: int = primitive.get("attributes", {}).get("POSITION", -1)
			var count: int = accessors[position].get("count", 0) if position >= 0 and position < accessors.size() else 0
			tally["corners"] += count
			var indices: int = primitive.get("indices", -1)
			tally["triangles"] += (accessors[indices].get("count", 0) if indices >= 0 and indices < accessors.size() else count) / 3
			used[primitive.get("material", -1)] = true
	tally["materials"] = used.size()
	return tally


## What the game's checker would refuse in a model that counts up to `tally`, in plain words ending in a
## full stop, or nothing.
static func _model_limits_problem(tally: Dictionary) -> String:
	if tally["triangles"] > MOST_MODEL_TRIANGLES:
		return "has %d triangles, and the game takes at most %d in one model. Simplify it (in Blender, the Decimate modifier)." % [tally["triangles"], MOST_MODEL_TRIANGLES]
	if tally["corners"] > MOST_MODEL_CORNERS:
		return "has %d corners, and the game takes at most %d in one model. Simplify it (in Blender, the Decimate modifier)." % [tally["corners"], MOST_MODEL_CORNERS]
	if tally["materials"] > MOST_MODEL_MATERIALS:
		return "has %d materials, and the game takes at most %d. Join some in Blender." % [tally["materials"], MOST_MODEL_MATERIALS]
	if tally["pictures"] > MOST_MODEL_PICTURES:
		return "has %d pictures, and the game takes at most %d. Join some in Blender." % [tally["pictures"], MOST_MODEL_PICTURES]
	return ""


## The pictures a .glb holds or keeps beside itself at `source`, as PackedByteArrays, in its order.
static func _pictures_of(bytes: PackedByteArray, source: String) -> Array[PackedByteArray]:
	var pictures: Array[PackedByteArray] = []
	var description := glb_description(bytes)
	var json_length := bytes.decode_u32(12)
	var binary := 20 + json_length + 8
	var views: Array = description.get("bufferViews", [])
	for image: Dictionary in description.get("images", []):
		if image.has("bufferView"):
			var view: int = image["bufferView"]
			if view < 0 or view >= views.size():
				pictures.append(PackedByteArray())
				continue
			var start: int = binary + int(views[view].get("byteOffset", 0))
			pictures.append(bytes.slice(start, start + int(views[view].get("byteLength", 0))))
		elif image.has("uri"):
			pictures.append(FileAccess.get_file_as_bytes(source.get_base_dir().path_join(String(image["uri"]))))
		else:
			pictures.append(PackedByteArray())
	return pictures


## The pictures a .glb's materials wear as their colour, once for each material: the only ones the game
## reads, as src/map/model.rs does. Bump and other pictures it never draws.
static func _colour_pictures(bytes: PackedByteArray, source: String) -> Array[PackedByteArray]:
	var description := glb_description(bytes)
	var pictures := _pictures_of(bytes, source)
	var textures: Array = description.get("textures", [])
	var worn: Array[PackedByteArray] = []
	for material: Dictionary in description.get("materials", []):
		var texture: int = material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index", -1)
		if texture < 0 or texture >= textures.size():
			continue
		var image: int = textures[texture].get("source", -1)
		if image >= 0 and image < pictures.size():
			worn.append(pictures[image])
	return worn


## What the game would refuse in a .glb's colour pictures, in plain words ending in a full stop, or
## nothing: one that isn't a PNG, or one too big.
static func _pictures_problem(bytes: PackedByteArray, source: String) -> String:
	for picture in _colour_pictures(bytes, source):
		if picture.size() < 24 or picture.slice(1, 4).get_string_from_ascii() != "PNG":
			return "has a picture that isn't a PNG. Save its pictures as PNG in Blender, then export it again."
		var width := (picture[16] << 24) | (picture[17] << 16) | (picture[18] << 8) | picture[19]
		var height := (picture[20] << 24) | (picture[21] << 16) | (picture[22] << 8) | picture[23]
		if width > MOST_PICTURE_SIDE or height > MOST_PICTURE_SIDE:
			return "has a picture %d x %d, and the game takes at most %d x %d. Make it smaller." % [width, height, MOST_PICTURE_SIDE, MOST_PICTURE_SIDE]
		if picture.size() > MOST_PICTURE_BYTES:
			return "has a picture of %.1f MB, and the game takes at most 8 MB. Make it smaller." % (picture.size() / 1048576.0)
	return ""


## How much a .glb's pictures weigh, as the game adds them up: once for each material drawn with one.
static func _picture_bytes(bytes: PackedByteArray, source: String) -> int:
	var total := 0
	for picture in _colour_pictures(bytes, source):
		total += picture.size()
	return total


## Takes off what only draws a mesh here: the editor's underwater preview, or any shader, which the game
## never draws. What it's made of underneath is what the game wears.
##
## A picture bigger than the game draws is made that size, and one Godot keeps packed for the graphics
## card is unpacked, so that Godot can write it as a PNG.
static func _undress(part: MeshInstance3D) -> void:
	if part.material_override != null and not part.material_override is BaseMaterial3D:
		part.material_override = null
	for surface in part.get_surface_override_material_count():
		var over := part.get_surface_override_material(surface)
		if over != null and not over is BaseMaterial3D:
			part.set_surface_override_material(surface, null)
	# One material laid over the whole mesh wins over each surface's, so it's the one shrunk.
	if part.material_override != null:
		var shrunk := _with_picture_drawn(part.material_override)
		if shrunk != null:
			part.material_override = shrunk
		return
	for surface in part.get_surface_override_material_count():
		var shrunk := _with_picture_drawn(part.get_active_material(surface))
		if shrunk != null:
			part.set_surface_override_material(surface, shrunk)


## A copy of `material` with its colour picture unpacked and no bigger than the game draws, or null if it
## needs neither.
static func _with_picture_drawn(material: Material) -> BaseMaterial3D:
	if not material is BaseMaterial3D or (material as BaseMaterial3D).albedo_texture == null:
		return null
	var picture: Image = (material as BaseMaterial3D).albedo_texture.get_image()
	if picture == null:
		return null
	var packed: bool = picture.is_compressed()
	if packed:
		picture.decompress()
	var widest := maxi(picture.get_width(), picture.get_height())
	if widest <= PICTURE_SIDE_DRAWN and not packed:
		return null
	if widest > PICTURE_SIDE_DRAWN:
		var shrink := float(PICTURE_SIDE_DRAWN) / widest
		picture.resize(maxi(roundi(picture.get_width() * shrink), 1), maxi(roundi(picture.get_height() * shrink), 1), Image.INTERPOLATE_LANCZOS)
	var copy: BaseMaterial3D = (material as BaseMaterial3D).duplicate()
	copy.albedo_texture = ImageTexture.create_from_image(picture)
	return copy


## A .glb the game takes, made by Godot from `node` and what's under it as they're drawn now, with its
## pictures as PNG, and `node` itself at the middle: the piece holds where it stands. With `alone`, only
## `node`'s own mesh, as the meshes under it are pieces of their own. Empty if Godot can't make one.
static func built_glb(node: Node3D, alone: bool) -> PackedByteArray:
	var copy := node.duplicate() as Node3D
	if copy == null:
		return PackedByteArray()
	copy.transform = Transform3D.IDENTITY
	if alone:
		for child in copy.get_children():
			copy.remove_child(child)
			child.free()
	for part in meshes_in(copy):
		_undress(part)
	var document := GLTFDocument.new()
	document.image_format = "PNG"
	var state := GLTFState.new()
	var bytes := PackedByteArray()
	if document.append_from_scene(copy, state) == OK:
		bytes = document.generate_buffer(state)
	copy.free()
	return bytes


static func _read_piece(node: Node3D, kit: String, scene: Scene, model := "") -> void:
	if model.is_empty() and not Kit.has(kit):
		scene.problem_on(node, "%s uses %s, which the kit no longer has. Delete it." % [node.name, kit])
		return
	var place := node.global_transform
	var root := _root_of(node)
	var reach: float = root.half_width + SCENERY_BEYOND
	var at := place.origin
	if absf(at.x) > reach or absf(at.z) > reach or at.y < -BELOW_THE_FLOOR or at.y > root.ceiling + SCENERY_BEYOND:
		scene.problem_on(node, "%s is at (%.1f, %.1f, %.1f), too far outside the map. Pieces may stand up to %s m past its edge and ceiling." % [node.name, at.x, at.y, at.z, SCENERY_BEYOND])
		return
	var scale := place.basis.get_scale()
	var unequal := maxf(absf(scale.x - scale.y), absf(scale.y - scale.z))
	if unequal > STRETCH_SLACK * scale.x:
		scene.problem_on(node, "%s is stretched (%s). Scale all three sides the same." % [node.name, scale])
		return
	if place.basis.determinant() < 0.0:
		scene.problem_on(node, "%s is mirrored. The game can't draw a piece inside out: scale it by a positive number." % node.name)
		return
	if scale.x < SCALES.x or scale.x > SCALES.y:
		scene.problem_on(node, "%s is scaled by %s. It must be from %s to %s." % [node.name, scale.x, SCALES.x, SCALES.y])
		return
	var rotation := place.basis.get_rotation_quaternion()
	var up := (rotation * Vector3.UP).normalized()
	var twist := Kit.arc_from_up(up).inverse() * rotation
	var turn := wrapf(2.0 * atan2(twist.y, twist.w), -PI, PI)
	var piece := {"kit": kit, "at": place.origin, "up": up, "turn": turn, "scale": scale.x}
	if not model.is_empty():
		piece = {"model": model, "at": place.origin, "up": up, "turn": turn, "scale": scale.x}
	var is_switch := node.is_in_group(SWITCH_GROUP)
	if is_switch or node.is_in_group(SCRIPT_GROUP):
		piece["name"] = String(node.name)
		piece["switch"] = is_switch
		piece["node"] = node
	scene.pieces.append(piece)
	scene.sources["Piece"].append(node)


## What's wrong with a piece's name for the map's script, in plain words, or nothing: the game's
## name_problem.
static func piece_name_problem(piece_name: String) -> String:
	if piece_name.length() > MOST_PIECE_NAME_LETTERS:
		return "its name has %d letters, and the limit is %d" % [piece_name.length(), MOST_PIECE_NAME_LETTERS]
	for letter in piece_name:
		var plain := (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9") or letter in ["_", "-", "."]
		if not plain:
			return "names may only use lowercase letters, digits, dashes, underscores and dots"
	if piece_name.contains("..") or piece_name.begins_with(".") or piece_name.ends_with("."):
		return "names can't start or end with a dot, or have two in a row"
	if piece_name.get_slice(".", 0) in WINDOWS_NAMES:
		return "that name is kept for Windows itself"
	return ""


## Each named piece's name is plain and its own, as the game's checker wants.
static func _check_piece_names(scene: Scene) -> void:
	var seen := {}
	for piece in scene.pieces:
		if not piece.has("name"):
			continue
		var node: Node = piece["node"]
		var why := piece_name_problem(piece["name"])
		if not why.is_empty():
			scene.problem_on(node, "%s is in the %s group, so the map's script finds it by its name, but %s. Rename it." % [node.name, SWITCH_GROUP if piece["switch"] else SCRIPT_GROUP, why])
		elif seen.has(piece["name"]):
			scene.problem_on(node, "%s is the name of two pieces the map's script can find. Rename one." % node.name)
		seen[piece["name"]] = true
	if seen.size() > MOST_NAMED_PIECES:
		scene.problems.append("The map names %d pieces for its script, and the most it can name is %d." % [seen.size(), MOST_NAMED_PIECES])


## Painted pieces already hold what map.ron wants, so they go in as they are, each kind together.
static func _read_painted(root: SmartFellasMap, scene: Scene) -> void:
	var kits: Array[String] = root.painted.keys()
	kits.sort()
	for kit in kits:
		var values: PackedFloat32Array = root.painted[kit]
		if not Kit.has(kit):
			scene.problems.append("The map has %d painted pieces of %s, which the kit no longer has. Hold Shift and brush over the whole map to erase them." % [values.size() / Kit.STRIDE, kit])
			continue
		var wrong_size := 0
		var too_far := 0
		var reach: float = root.half_width + SCENERY_BEYOND
		for first in range(0, values.size(), Kit.STRIDE):
			if values[first + 7] < SCALES.x or values[first + 7] > SCALES.y:
				wrong_size += 1
			if absf(values[first]) > reach or absf(values[first + 2]) > reach or values[first + 1] < -BELOW_THE_FLOOR or values[first + 1] > root.ceiling + SCENERY_BEYOND:
				too_far += 1
		if too_far > 0:
			scene.problems.append("%d painted pieces of %s are too far outside the map, which has shrunk since. Make it bigger, or hold Shift and brush over them." % [too_far, Kit.plain_name(kit)])
		if wrong_size > 0:
			scene.problems.append("%d painted pieces of %s are sized outside %s to %s. Erase them and paint again." % [wrong_size, Kit.plain_name(kit), SCALES.x, SCALES.y])
		for first in range(0, values.size(), Kit.STRIDE):
			var at := Vector3(values[first], values[first + 1], values[first + 2])
			scene.sources["Piece"].append("The painted %s at (%.1f, %.1f, %.1f)" % [Kit.plain_name(kit), at.x, at.y, at.z])
			scene.pieces.append({
				"kit": kit,
				"at": at,
				"up": Vector3(values[first + 3], values[first + 4], values[first + 5]),
				"turn": values[first + 6],
				"scale": values[first + 7],
			})


## Nine decimal places is more than a 32-bit float holds, so the game reads back the same number.
static func _number(value: float) -> String:
	return "%.9f" % value


static func _xyz(at: Vector3) -> String:
	return "(%s, %s, %s)" % [_number(at.x), _number(at.y), _number(at.z)]


static func _spawn_lines(spawns: Array[Dictionary]) -> String:
	var lines := ""
	for spawn in spawns:
		lines += "            (at: %s, yaw: %s),\n" % [_xyz(spawn["at"]), _number(spawn["yaw"])]
	return lines


static func _piece_lines(pieces: Array[Dictionary]) -> String:
	var lines := ""
	for piece in pieces:
		var named := ""
		if piece.has("name"):
			named = ", name: Some(\"%s\")" % piece["name"]
			if piece["switch"]:
				named += ", switch: true"
		var made_of := ("model: Some(\"%s\")" % piece["model"]) if piece.has("model") else ("kit: \"%s\"" % piece["kit"])
		lines += "        (%s, at: %s, up: %s, turn: %s, scale: %s%s),\n" % [
			made_of, _xyz(piece["at"]), _xyz(piece["up"]), _number(piece["turn"]), _number(piece["scale"]), named
		]
	return lines


## A ring of spots round each patch, lying on the patch's own ground: the seabed, or the piece it's on,
## which also says whether that ground is sand or rock. The real rules for filling a map with food come in a
## later step.
static func _food_lines(patches: Array[Dictionary], grid: RefCounted, finder: RefCounted) -> Dictionary:
	var patch_lines := ""
	var spot_lines := ""
	var number := 0
	for patch in patches:
		var up: Vector3 = patch["up"]
		var under: Dictionary = {} if finder == null else finder.find(patch["at"] + up * FOOD_FOLLOWS_WITHIN, patch["at"] - up * FOOD_FOLLOWS_WITHIN)
		var on_a_piece: bool = not under.is_empty() and not under["seabed"]
		var ground := "Rock" if grid != null and grid.is_rock_at(patch["at"].x, patch["at"].z) else "Sand"
		if on_a_piece:
			ground = "Sand" if under["on"] == "sand" else "Rock"
		patch_lines += "            (at: %s, up: %s, ground: %s),\n" % [_xyz(patch["at"]), _xyz(patch["up"]), ground]
		for index in SPOTS_IN_A_PATCH:
			var spot := _food_spot(patch, index)
			if on_a_piece:
				# A patch lying on a piece has its food on that piece, however it curves.
				var on_it: Dictionary = finder.find(spot + up * FOOD_FOLLOWS_WITHIN, spot - up * FOOD_FOLLOWS_WITHIN)
				if not on_it.is_empty():
					spot = on_it["at"]
			# A patch lying on sculpted ground has its food on that ground, however it curves.
			elif grid != null and absf(patch["at"].y - grid.height_at(patch["at"].x, patch["at"].z)) < FOOD_FOLLOWS_WITHIN:
				spot.y = grid.height_at(spot.x, spot.z)
			spot_lines += "            (at: %s, up: %s, ground: %s, patch: %d),\n" % [_xyz(spot), _xyz(patch["up"]), ground, number]
		number += 1
	return {"patches": patch_lines, "spots": spot_lines}


## The heights the shark may swim at. On flat sand, one does. Over sculpted hills it has others to try.
static func _shark_heights(root: SmartFellasMap) -> String:
	if root.seabed_side == 0 and root.has_seabed:
		return _number(root.ceiling * 0.6)
	var heights := PackedStringArray()
	for share in [0.6, 0.75, 0.85, 0.45]:
		heights.append(_number(root.ceiling * share))
	return ", ".join(heights)


static func _seabed_text(root: SmartFellasMap, scene: Scene) -> String:
	if not root.has_seabed:
		return "None"
	if root.seabed_side == 0:
		return "Flat(height: %s)" % _number(scene.seabed_height)
	var heights := PackedStringArray()
	for height in root.seabed_heights:
		heights.append("%.3f" % height)
	var rock := PackedStringArray()
	for cell in root.seabed_rock.size():
		if root.seabed_rock[cell] != 0:
			rock.append(str(cell))
	return "Sculpted((reach: %s, side: %d, heights: [%s], rock_cells: [%s]))" % [_number(root.seabed_reach), root.seabed_side, ", ".join(heights), ", ".join(rock)]


## Which of the map's own models are sand or silt, by their names in the package, or nothing if none is, as
## the game leaves it out.
static func _soft_models_text(root: SmartFellasMap, scene: Scene) -> String:
	var names: Array = scene.models.keys()
	names.sort()
	var entries := ""
	var grounds := {}
	for path: String in root.soft_models:
		grounds[ProjectSettings.globalize_path(path)] = root.soft_models[path]
	for name: String in names:
		var ground: String = grounds.get(scene.models[name], "rock")
		if ground == "sand" or ground == "silt":
			entries += "(model: \"%s\", ground: %s), " % [name, ground.capitalize()]
	if entries.is_empty():
		return ""
	return "    soft_models: [%s],\n" % entries


static func _switch(on: bool) -> String:
	return "On" if on else "Off"


## The map's life section, or nothing if it's what any map has by default, as the game leaves it out.
static func _life_text(root: SmartFellasMap) -> String:
	if root.whale and root.stingrays and root.shark and not root.cave_sounds:
		return ""
	return "    life: (whale: %s, stingrays: %s, shark: %s, cave_sounds: %s),\n" % [
		_switch(root.whale), _switch(root.stingrays), _switch(root.shark), _switch(root.cave_sounds)
	]


static func _fish_lines(scene: Scene) -> String:
	if scene.fish.is_empty():
		return ""
	var lines := "\n"
	for fish in scene.fish:
		lines += "        (kind: %s, at: %s, yaw: %s),\n" % [fish["kind"], _xyz(fish["at"]), _number(fish["yaw"])]
	return lines + "    "


static func _deep_fauna_text(root: SmartFellasMap, scene: Scene) -> String:
	if not root.goblin_shark and scene.goblin_route.is_empty() and scene.jellies.is_empty():
		return ""
	var route := ""
	for point in scene.goblin_route:
		route += "%s, " % _xyz(point["at"])
	var jellies := ""
	for group in scene.jellies:
		jellies += "(at: %s, count: %d, hue: %s, spread: %s), " % [_xyz(group["at"]), group["count"], group["hue"], _number(group["spread"])]
	return "    deep_fauna: (goblin: %s, goblin_route: [%s], jellies: [%s]),\n" % [_switch(root.goblin_shark), route, jellies]


static func _anglers_text(root: SmartFellasMap, scene: Scene) -> String:
	if scene.angler_spots.is_empty():
		return ""
	var spots := ""
	for spot in scene.angler_spots:
		spots += "(at: %s, yaw: %s), " % [_xyz(spot["at"]), _number(spot["yaw"])]
	return "    anglers: (at_once: %d, spots: [%s]),\n" % [root.anglers_at_once, spots]


static func _lantern_text(scene: Scene) -> String:
	if scene.lantern_schools.is_empty():
		return ""
	var schools := ""
	for school in scene.lantern_schools:
		schools += "(at: %s, roam: %s), " % [_xyz(school["at"]), _number(school["roam"])]
	return "    lantern_fish: (schools: [%s]),\n" % schools


## The haunts section, or nothing if every list is empty, as the game leaves it out.
static func _haunts_text(scene: Scene) -> String:
	var lists := ""
	for haunt in HAUNTS:
		var places: Array = scene.haunts[haunt[0]]
		if places.is_empty():
			continue
		var points := ""
		for place in places:
			points += "%s, " % _xyz(place["at"])
		lists += "%s: [%s], " % [haunt[0], points]
	if lists.is_empty():
		return ""
	return "    haunts: (%s),\n" % lists


static func _map_text(root: SmartFellasMap, scene: Scene) -> String:
	var food := _food_lines(scene.patches, SeabedGrid.of(root) if root.has_seabed else null, scene.finder)
	var most_growing := maxi(scene.patches.size() * 2 / 3, 1)
	var sizes := team_sizes(root, scene)
	var divers: int = sizes["divers"]
	var octopuses: int = sizes["octopuses"]
	var format := SCULPTED_FORMAT if root.seabed_side != 0 else FORMAT
	if not scene.models.is_empty():
		format = MODELS_FORMAT
	var soft := _soft_models_text(root, scene)
	if not root.has_seabed or not soft.is_empty():
		format = NO_SEABED_FORMAT
	var text := "(\n    format: %d,\n    name: \"%s\",\n" % [format, root.map_name]
	text += "    size: (half_width: %s, ceiling: %s),\n" % [_number(root.half_width), _number(root.ceiling)]
	text += "    seabed: %s,\n" % _seabed_text(root, scene)
	text += "    pieces: [\n%s    ],\n" % _piece_lines(scene.pieces)
	text += "    spawns: (\n        octopus: [\n%s        ],\n        diver: [\n%s        ],\n    ),\n" % [
		_spawn_lines(scene.octopus_spawns), _spawn_lines(scene.diver_spawns)
	]
	text += "    food: (\n        growing: (1, %d),\n        patches: [\n%s        ],\n        spots: [\n%s        ],\n    ),\n" % [
		most_growing, food["patches"], food["spots"]
	]
	text += "    fish: [%s],\n    triggers: [],\n    hunters: %s,\n    clownfish: %s,\n" % [_fish_lines(scene), _switch(root.hunters), _switch(root.clownfish)]
	text += "    players: (fewest: %d, most: %d, max_divers: %d, max_octopuses: %d),\n" % [root.fewest_players, divers + octopuses, divers, octopuses]
	text += "    far_side: 0.0,\n"
	var widest: float = root.half_width * 0.6
	text += "    shark: (widest: %s, narrowest: %s, points: 8, heights: [%s], room: 1.7),\n" % [
		_number(widest), _number(widest * 0.5), _shark_heights(root)
	]
	var survey := maxf(root.half_width * 2.0 / 32.0, 2.0)
	text += "    rock_survey_step: %s,\n    small_fish_share: 0.35,\n" % _number(survey)
	text += WaterLook.section_text(root.water_depth, root.water_overrides)
	text += _life_text(root)
	text += _deep_fauna_text(root, scene)
	text += _anglers_text(root, scene)
	text += _lantern_text(scene)
	text += _haunts_text(scene)
	text += soft
	text += ")\n"
	return text
