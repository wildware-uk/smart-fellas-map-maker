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
const TriggerZone := preload("trigger_zone.gd")
const OctopusPose := preload("octopus_pose.gd")

const KIT_FOLDER := Kit.FOLDER
const FORMAT := 2
## The game's SCULPTED_FORMAT, for a map with a sculpted seabed.
const SCULPTED_FORMAT := 3
## The game's NO_SEABED_FORMAT, for a map with no seabed, or with models of its own that are sand or silt.
const NO_SEABED_FORMAT := 5
## The game's MODELS_FORMAT, for a map with models of its own.
const MODELS_FORMAT := 4
## The game's format for a map whose play area is a box placed anywhere (a PlayArea node), and otherwise as
## NO_SEABED_FORMAT.
const BOX_FORMAT := 6
## The game's GRID_MIDDLE_FORMAT, for a box map whose sculpted grid sits round a middle of its own, and
## otherwise as BOX_FORMAT.
const GRID_MIDDLE_FORMAT := 7
## The game's POSES_FORMAT, for a map with octopus poses of its own, which must have a play area box.
const POSES_FORMAT := 8
## The game's CRAWL_FORMAT, for a box map that says whether octopuses crawl on some of its own models, and
## otherwise as POSES_FORMAT.
const CRAWL_FORMAT := 9
## The game's SMALL_GROWTH_MOST in src/map/reef.rs: a model of the map's own under this many metres across
## and tall, once scaled, is a growth octopuses go round, unless the map says otherwise.
const SMALL_GROWTH_MOST := 1.1
## Where a map's own models go in its package.
const ASSETS_FOLDER := "assets"
## The end of a map package's file name: Smart Fellas Map.
const SFM_EXTENSION := "sfm"
## What a package held when it was a folder, before .sfm files: what Export takes out of an old one.
const OLD_PACKAGE_FILES := ["map.ron", "preview.png"]
## The game's MAX_ASSET_BYTES and MAX_MAP_MODELS.
const MOST_MODEL_BYTES := 1073741824
## The words a .glb starts with, and the kinds of its two parts, as little-endian numbers.
const GLB_MAGIC := 0x46546C67
const GLB_JSON := 0x4E4F534A
const GLB_BIN := 0x004E4942
## What Export says when a file it made itself would be refused by the game, with the file and why.
const OUR_BAD_FILE := "Export made a bad file, %s: %s That's our mistake, not yours. Please report it to us, and say which map."
const MOST_MODELS := 16384
## The game's MAX_ENTRIES: the most files and folders a map's package may hold.
const MOST_ENTRIES := 32768
## The game's limits on one model, from src/map/model.rs. Since #299 the ones on size only guard against a
## broken or hostile file, far past any real model: how heavy a map is goes in its performance score.
const MOST_MODEL_TRIANGLES := 10000000
const MOST_MODEL_CORNERS := 20000000
const MOST_MODEL_MATERIALS := 1024
const MOST_MODEL_PICTURES := 1024
## How many materials each model Export builds from a mesh holds at most: a mesh of more becomes several
## models in one place. The game takes far more in one (MOST_MODEL_MATERIALS); this is only how Export has
## always built them, which looks the same in the game.
const SPLIT_MATERIALS := 8
## The game's MAX_PRIMITIVES: the most surfaces one mesh of a model may have.
const MOST_PRIMITIVES := 4096
const MOST_PICTURE_SIDE := 8192
## What Export says of scenery left out for standing further than SCENERY_REACH from the middle of the map.
const TOO_FAR := "The game takes nothing further than 4 km from the middle of the map: move it in."
## The game's MAX_MODEL_REACH: how far from its own middle a model may reach, in metres.
const MOST_MODEL_REACH := 8000.0
## How far from its middle a mesh on its own may reach before Export cuts it into parts by place, as one
## imported from a whole level is: so the game can leave out drawing the parts out of view, and a model
## stands at the middle of what it draws.
const CUT_REACH := 100.0
## How wide Export cuts the parts of such a mesh, at most, so that a part with the odd triangle sticking
## out of it is still well within CUT_REACH.
const WIDEST_CUT := 160.0
const MOST_PICTURE_BYTES := 134217728
## How many pixels across the game draws a model's picture at most, so a bigger one is made this size,
## which loses nothing.
const PICTURE_SIDE_DRAWN := 1024
## What a material's glTF extras say to the game, from src/map/model.rs: "add" or "multiply" for a material
## Godot adds to or multiplies what is behind it, and false for one Godot draws without its mesh's corner
## colours, which glTF always multiplies by.
const BLEND_EXTRA := "smart_fellas_blend"
const CORNER_COLOURS_EXTRA := "smart_fellas_vertex_colour"
## The fewest pixels across Export makes every picture of a map whose pictures come to more than the game
## takes.
const SMALLEST_PICTURE_SIDE := 256
## The game's limits on all the map's own models together, from src/map/check.rs. Materials that look the
## same count once, and so does a picture many models share. Each only stops a broken or hostile file
## (#299): past 1,536 materials the game still draws each one, and an octopus copies the closest of those.
const MOST_MAP_MATERIALS := 60000
const MOST_MAP_TRIANGLES := 100000000
const MOST_MAP_CORNERS := 100000000
const MOST_MAP_PICTURE_BYTES := 2147483648
## The game's MAX_SCALED_MODEL_TRIANGLES: the most those pieces at a size other than their model's own may
## draw, as each keeps a copy of its model's shape for bumping into.
const MOST_SCALED_TRIANGLES := 50000000
## How near its own size a piece is taken as not resized at all: a tenth of a millimetre in a metre, too
## little to see, and well over what turning it rounds to.
const NOT_RESIZED := 0.0001
## The game's MAX_MAP_PICTURE_PIXELS: the most pixels the game draws the map's own pictures with between
## them, each different one once, no more than PICTURE_SIDE_DRAWN across. Export shrinks them to fit, which
## keeps them sharp where it can; the game shrinks them further itself, so it never refuses a map (#299).
const MOST_PICTURE_PIXELS := 100000000
## The most pixels Export lets the map's own models' pictures hold: MOST_PICTURE_PIXELS, but for a test
## that wants to reach it with a few small pictures.
static var picture_pixels_taken := MOST_PICTURE_PIXELS
## The game's MAX_PIECES: the most pieces a map may place, of the kit and of its own models together.
const MOST_ALL_PIECES := 100000
## How many problems of one kind are each said; more than this are said as one line, with the rest behind
## its Details button.
const FEW_TO_LIST := 3
## The most shades of colour Export keeps for the copies of one scattered mesh, each a model of its own.
const MOST_SHADES := 8
## How finely a scattered copy's colour and stretch are told apart, so that near ones share a model.
const SHADE_STEP := 0.125
const STRETCH_STEP := 0.02
## How long a model's name in the package may be, before ".glb".
const MOST_MODEL_NAME_LETTERS := 56
const SCALES := Vector2(0.1, 10.0)
## The game's limits on a map's size, on how far past its edge a sculpted seabed may reach, how far from
## the middle of the map scenery may stand (as TOO_FAR says), how far below the floor anything may be, on
## spawn points and patches, and on who may play.
const HALF_WIDTHS := Vector2(10.0, 2000.0)
const CEILINGS := Vector2(5.0, 1000.0)
## A play area box's width or depth, and its height, as the game's SIDES and HEIGHTS.
const SIDES := Vector2(20.0, 4000.0)
const HEIGHTS := Vector2(5.0, 1000.0)
const SCENERY_REACH := 4000.0
const BELOW_THE_FLOOR := 12.0
## How far inside the map's reach Export moves a part it cuts that would stand just past it, in metres.
const EDGE_HAIR := 0.01
const MOST_SPAWNS := 256
const MOST_PATCHES := 256
const MOST_PLAYERS := 32
## The game's MAX_SEABED_SIDE. The add-on makes a grid smaller than this.
const MOST_SEABED_SIDE := 257
## The game's limits on how close a sculpted seabed's points are and how steep it is.
const CLOSEST_SEABED_POINTS := 0.25
const MOST_SEABED_SLOPE := 6.0
const MOST_ANGLERS_AT_ONCE := 64
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
## The game's MAX_CUSTOM_PIECES: the most kit pieces a map may place. The game refuses anything over it
## however the package was made.
const MOST_PIECES := 50000
## The game's MAX_MAP_FILE_BYTES: the most map.ron may weigh.
const MOST_FILE_BYTES := 33554432
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
## The game's MAX_TRIGGERS.
const MOST_TRIGGERS := 256
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
	## The trigger zones for the map's script, as {"name", "at", "reach", "node"}.
	var triggers: Array[Dictionary] = []
	## The map's own octopus poses, as their nodes, in the order map.ron has them.
	var poses: Array[Node3D] = []
	## The map's own models, by their name in the package's assets/, as their file in this project.
	var models := {}
	## The pictures those models keep beside themselves, by their name in assets/, as their file here.
	var pictures := {}
	## What each of those models is made of, by its name in assets/: "rock", "sand" or "silt".
	var model_grounds := {}
	## Whether octopuses crawl on each of those models, by its name in assets/: "size", "always" or "never".
	var model_crawls := {}
	## The surfaces of the map's pieces and seabed, for what lies on them, made once Export needs it.
	var finder: RefCounted
	## The models Export made itself, from a model the game can't take as it is, by their name in assets/,
	## as the .glb's bytes. Their names are in `models` too.
	var built := {}
	## The models Export made of scattered meshes, by what they're made of, as their names in assets/, so
	## that two scatters of one mesh share a model.
	var scatter_models := {}
	## What all the map's own models come to between them, as the game counts it.
	var model_totals := {"triangles": 0, "corners": 0, "materials": 0, "picture_bytes": 0, "picture_pixels": 0}
	## How many triangles each of the map's own models draws, by its name in assets/.
	var model_triangles := {}
	## Where the middle of each model Export moved to its own middle was, under its node, by its name in
	## assets/: its pieces stand there instead, so it's drawn where it was.
	var model_middles := {}
	## The different looks of the map's own models' materials, and their different pictures by MD5 as
	## their weight: what the game counts once however many models share them.
	var looks := {}
	var picture_weights := {}
	## The same pictures' pixels, as the game draws them.
	var picture_pixels := {}
	## How many pixels across Export makes a picture it shrinks.
	var picture_side := PICTURE_SIDE_DRAWN
	## What Export did by itself, for one line to the map maker: scattered meshes (MultiMeshInstance3D)
	## made into copies, the copies, the models whose pictures it shrank.
	var changes := {"scatters": 0, "copies": 0, "shrunk": 0, "split": 0, "cut": 0, "cut_parts": 0}
	## Problems of one kind on many things, said as one line once the scene is read: by kind, as
	## {"many": words with %d for how many, "lines": what each would say alone, "nodes": each one's node,
	## "details": what Details says of each}.
	var grouped := {}
	## Warnings of one kind on many things, likewise.
	var grouped_warnings := {}
	## Each problem said for many things, as the lines behind its Details button.
	var problem_details := {}
	var problems: Array[String] = []
	## What the map maker should know, as {"words", "node"}, that doesn't stop the map.
	var warnings: Array[Dictionary] = []
	## The node each problem is on, if it's on one.
	var problem_nodes := {}
	## How many pieces, markers and trigger zones were left out for being hidden, and the first node whose eye hid any.
	var hidden := {"pieces": 0, "markers": 0, "zones": 0, "first": null}
	## What the map's lists hold, in the order map.ron has them, under the words the game's checker
	## calls them by: a node, or words for something with no node.
	var sources := {
		"Piece": [], "Octopus spawn": [], "Diver spawn": [], "Food patch": [], "Food spot": [], "Fish": [],
		"Anglerfish spot": [], "Lantern fish school": [], "Jellyfish group": [], "Goblin shark route point": [],
		"Wrasse spot": [], "Stingray stop": [], "Eel hole": [], "Groper hole": [],
		"Trigger zone": [], "Pose": [],
	}

	func jelly_count() -> int:
		var total := 0
		for group in jellies:
			total += group["count"]
		return total

	func problem_on(node: Node, words: String) -> void:
		problems.append(words)
		problem_nodes[words] = node

	## A problem on `node` that many things may share: said as `one` if few have it, or once as `many`,
	## with %d for how many, and `detail` for each behind its Details button: its name, unless said.
	func problem_among(node: Node, kind: String, one: String, many: String, detail := "") -> void:
		_add_to(grouped, node, kind, one, many, detail)

	## A warning many things may share, as problem_among.
	func warning_among(node: Node, kind: String, one: String, many: String, detail := "") -> void:
		_add_to(grouped_warnings, node, kind, one, many, detail)

	func _add_to(groups: Dictionary, node: Node, kind: String, one: String, many: String, detail: String) -> void:
		if not groups.has(kind):
			groups[kind] = {"many": many, "lines": PackedStringArray(), "nodes": [], "details": PackedStringArray()}
		groups[kind]["lines"].append(one)
		groups[kind]["nodes"].append(node)
		groups[kind]["details"].append(detail if not detail.is_empty() else String(node.name))

	## Says the problems and warnings problem_among and warning_among held back.
	func say_grouped() -> void:
		for kind: String in grouped:
			var group: Dictionary = grouped[kind]
			var lines: PackedStringArray = group["lines"]
			if lines.size() <= FEW_TO_LIST:
				for index in lines.size():
					problem_on(group["nodes"][index], lines[index])
				continue
			var words: String = group["many"] % lines.size()
			problem_on(group["nodes"][0], words)
			problem_details[words] = group["details"]
		for kind: String in grouped_warnings:
			var group: Dictionary = grouped_warnings[kind]
			var lines: PackedStringArray = group["lines"]
			if lines.size() <= FEW_TO_LIST:
				for index in lines.size():
					warnings.append({"words": lines[index], "node": group["nodes"][index]})
				continue
			warnings.append({"words": group["many"] % lines.size(), "node": group["nodes"][0], "details": group["details"]})
		grouped = {}
		grouped_warnings = {}

	## What Export did by itself, in one line, or nothing if it did nothing.
	func changes_words() -> String:
		var done: Array[String] = []
		if changes["scatters"] > 0:
			done.append("made %d scattered mesh%s (MultiMesh) into %d placed copies" % [changes["scatters"], "" if changes["scatters"] == 1 else "es", changes["copies"]])
		if changes["cut"] > 0:
			done.append("cut %d mesh%s far wider than a model into %d parts by where they lie" % [changes["cut"], "" if changes["cut"] == 1 else "es", changes["cut_parts"]])
		if changes["split"] > 0:
			done.append("split %d model%s with more than %d materials into parts" % [changes["split"], "" if changes["split"] == 1 else "s", SPLIT_MATERIALS])
		if changes["shrunk"] > 0:
			var why := "the most the game draws" if picture_side == PICTURE_SIDE_DRAWN else "so that they all fit in what the game takes"
			done.append("shrank the pictures of %d model%s to %d pixels across, %s" % [changes["shrunk"], "" if changes["shrunk"] == 1 else "s", picture_side, why])
		var materials: int = model_totals["materials"]
		if looks.size() < materials:
			done.append("found the models' %d materials are %d different looks, each drawn once" % [materials, looks.size()])
		if done.is_empty():
			return ""
		return "Export did this itself: %s." % "; ".join(done)

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
## {"problems": what stops it, in plain words, "nodes": the node each is on, if it's on one, "details": the
## lines behind a problem said once for many things, and "warnings" if the scene was read}.
## "warnings" says what doesn't stop it but is worth knowing, as {"words", "node"}, and "details" for one
## said once for many things. What Export did by itself is the first of them.
## `scripts` is a folder of built .js files to put in the map's scripts/, or "" for none.
static func export_map(root: Node, out_folder: String, scripts := "") -> Dictionary:
	if not (root is SmartFellasMap):
		return {"problems": ["This scene's top node isn't a SmartFellasMap. Open a map's scene first."]}
	if not root.is_inside_tree():
		return {"problems": ["The scene isn't open yet, so nothing in it has a place. Open it first."]}
	_pictures_drawn = {}
	_materials_drawn = {}
	var scene := _read_scene(root)
	_pictures_drawn = {}
	_materials_drawn = {}
	if not scene.problems.is_empty():
		return {"problems": scene.problems, "nodes": scene.problem_nodes, "details": scene.problem_details, "warnings": scene.warnings}
	var text := _map_text(root, scene)
	var too_heavy := file_problem(text.to_utf8_buffer().size())
	if not too_heavy.is_empty():
		return {"problems": [too_heavy]}
	var made := DirAccess.make_dir_recursive_absolute(out_folder)
	if made != OK:
		return {"problems": ["Can't make the folder %s: %s." % [out_folder, error_string(made)]]}
	var name := _folder_name(root.map_name)
	var folder := _building_folder(name)
	var built := _build_folder(scene, text, folder, scripts)
	var package := out_folder.path_join("%s.%s" % [name, SFM_EXTENSION])
	if built.is_empty():
		built = pack_folder(folder, package)
	_remove_folder(folder)
	if not built.is_empty():
		return {"problems": [built]}
	_remove_old_package(out_folder.path_join(name))
	var warnings := scene.warnings
	var changed := scene.changes_words()
	if not changed.is_empty():
		warnings.push_front({"words": changed, "node": null})
	return {"package": package, "sources": scene.sources, "warnings": warnings}


## Where Export puts a package together before packing it: a folder of the add-on's own, never where the
## game looks, so the game can't come across half a map.
static func _building_folder(name: String) -> String:
	return ProjectSettings.globalize_path("user://smart_fellas_export").path_join(name)


## Writes the package's files into `folder`, emptied first. Gives back what went wrong, or nothing.
static func _build_folder(scene: Scene, text: String, folder: String, scripts := "") -> String:
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
	return _copy_scripts(scripts, folder)


## Where a script runs is the folder it is in: scripts/ on the server, scripts/client/ on each player's
## own PC, scripts/shared/ on both.
const SCRIPT_PLACES: Array[String] = ["", "client", "shared"]


## Copies every built .js file in `scripts`, and in its client/ and shared/, into the same places in the
## package's scripts/ in `folder`. Gives back what went wrong, or nothing.
static func _copy_scripts(scripts: String, folder: String) -> String:
	if scripts.is_empty():
		return ""
	for place in SCRIPT_PLACES:
		var from := scripts.path_join(place)
		if not DirAccess.dir_exists_absolute(from):
			continue
		var into := folder.path_join("scripts").path_join(place)
		var made := DirAccess.make_dir_recursive_absolute(into)
		if made != OK:
			return "Can't make the folder %s: %s." % [into, error_string(made)]
		for name in DirAccess.get_files_at(from):
			if not name.ends_with(".js"):
				continue
			var copied := DirAccess.copy_absolute(from.path_join(name), into.path_join(name))
			if copied != OK:
				var shown := place.path_join(name) if not place.is_empty() else name
				return "Can't copy the script %s into the map: %s." % [shown, error_string(copied)]
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
	var unpacked := _packed_problem(partial, folder)
	if not unpacked.is_empty():
		DirAccess.remove_absolute(partial)
		return unpacked
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	var moved := DirAccess.rename_absolute(partial, to)
	if moved != OK:
		DirAccess.remove_absolute(partial)
		return "Can't write %s: %s." % [to, error_string(moved)]
	return ""


## Reads back every file of the .sfm `package` packed from `folder`, and says what the game would refuse:
## a file that comes out other than it went in, or a .glb laid out wrongly. Nothing if all is well.
static func _packed_problem(package: String, folder: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(package) != OK:
		return OUR_BAD_FILE % [package.get_file(), "It can't be opened as a zip."]
	var problem := ""
	for inside in _files_inside(folder, ""):
		var bytes := zip.read_file(inside) if zip.file_exists(inside) else PackedByteArray()
		if bytes != FileAccess.get_file_as_bytes(folder.path_join(inside)):
			problem = OUR_BAD_FILE % [inside, "It comes out of the .sfm other than it went in."]
		elif inside.ends_with(".glb"):
			var bad := glb_layout_problem(bytes)
			if not bad.is_empty():
				problem = OUR_BAD_FILE % [inside, bad]
		if not problem.is_empty():
			break
	zip.close()
	return problem


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
	var beside := {}
	for name in scene.models:
		var source: String = scene.models[name]
		var bytes: PackedByteArray = scene.built[name] if scene.built.has(name) else FileAccess.get_file_as_bytes(source)
		if bytes.is_empty():
			return "Can't read the model %s." % source
		if scene.built.has(name):
			var split := pictures_set_beside(bytes)
			bytes = split["glb"]
			beside.merge(split["pictures"])
		var bad := model_file_problem(bytes, scene.built.has(name), name, source)
		if not bad.is_empty():
			return bad
		var written := _write_file(assets.path_join(name), bytes)
		if not written.is_empty():
			return written
	for name: String in beside:
		var written := _write_file(assets.path_join(name), beside[name])
		if not written.is_empty():
			return written
	for name in scene.pictures:
		var written := _write_file(assets.path_join(name), FileAccess.get_file_as_bytes(scene.pictures[name]))
		if not written.is_empty():
			return written
	return ""


## `value` with every whole number in it an integer: Godot reads every JSON number as a float and would
## write 5 back as 5.0, which glTF's counts and indices must not be.
static func _whole_numbers_as_integers(value: Variant) -> Variant:
	if value is float and is_finite(value) and absf(value) < 9.0e15 and value == floorf(value):
		return int(value)
	if value is Array:
		return value.map(_whole_numbers_as_integers)
	if value is Dictionary:
		var each := {}
		for key: Variant in value:
			each[key] = _whole_numbers_as_integers(value[key])
		return each
	return value


## A .glb Export made, with its PNG pictures taken out to lie beside it in assets/, each named by what's in
## it: {"glb": the model, "pictures": each picture's bytes by its name}. A picture many models share is then
## one file in the package, not one inside each model. A .glb it can't read is given back as it is.
static func pictures_set_beside(bytes: PackedByteArray) -> Dictionary:
	var unchanged := {"glb": bytes, "pictures": {}}
	var description := glb_description(bytes)
	var views: Array = description.get("bufferViews", [])
	var images: Array = description.get("images", [])
	if description.is_empty() or images.is_empty() or description.get("buffers", []).size() != 1:
		return unchanged
	var json_length := bytes.decode_u32(12)
	var bin_start := 20 + json_length + 8
	if bytes.size() < bin_start:
		return unchanged
	var bin := bytes.slice(bin_start, bin_start + bytes.decode_u32(20 + json_length))
	var pictures := {}
	var dropped := {}
	for image: Dictionary in images:
		var view: int = image.get("bufferView", -1)
		if view < 0 or view >= views.size():
			continue
		var start: int = views[view].get("byteOffset", 0)
		var picture := bin.slice(start, start + int(views[view].get("byteLength", 0)))
		if picture.size() < 8 or picture.slice(1, 4).get_string_from_ascii() != "PNG":
			continue
		var name := "picture_%s.png" % _md5_of(picture).substr(0, 16)
		pictures[name] = picture
		image.erase("bufferView")
		image.erase("mimeType")
		image["uri"] = name
		dropped[view] = true
	if dropped.is_empty():
		return unchanged
	var kept := PackedByteArray()
	var new_index := {}
	var new_views: Array = []
	for index in views.size():
		if dropped.has(index):
			continue
		var view: Dictionary = views[index]
		var start: int = view.get("byteOffset", 0)
		while kept.size() % 4 != 0:
			kept.append(0)
		view["byteOffset"] = kept.size()
		kept.append_array(bin.slice(start, start + int(view.get("byteLength", 0))))
		new_index[index] = new_views.size()
		new_views.append(view)
	for accessor: Dictionary in description.get("accessors", []):
		if accessor.has("bufferView"):
			accessor["bufferView"] = new_index.get(int(accessor["bufferView"]), 0)
		var sparse: Dictionary = accessor.get("sparse", {})
		for part in ["indices", "values"]:
			if sparse.has(part):
				sparse[part]["bufferView"] = new_index.get(int(sparse[part]["bufferView"]), 0)
	for image: Dictionary in images:
		if image.has("bufferView"):
			image["bufferView"] = new_index.get(int(image["bufferView"]), 0)
	while kept.size() % 4 != 0:
		kept.append(0)
	description["bufferViews"] = new_views
	description["buffers"][0]["byteLength"] = kept.size()
	var text := JSON.stringify(_whole_numbers_as_integers(description), "", false, true).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var glb := PackedByteArray()
	glb.resize(20)
	glb.encode_u32(0, 0x46546C67)
	glb.encode_u32(4, 2)
	glb.encode_u32(8, 12 + 8 + text.size() + 8 + kept.size())
	glb.encode_u32(12, text.size())
	glb.encode_u32(16, 0x4E4F534A)
	glb.append_array(text)
	var bin_header := PackedByteArray()
	bin_header.resize(8)
	bin_header.encode_u32(0, kept.size())
	bin_header.encode_u32(4, 0x004E4942)
	glb.append_array(bin_header)
	glb.append_array(kept)
	return {"glb": glb, "pictures": pictures}


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
			scene.problem_on(node, "%s's model %s uses the picture %s. The game takes only a .png with a plain lowercase name beside the model, or pictures packed inside the .glb. Rename the picture, or save the model again with its pictures packed in." % [node.name, source.get_file(), picture])
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


## What Export says of the model `name` it's about to write, from `source`, if the game would refuse how its
## parts are laid out, or nothing: one Export `built` itself is Export's own mistake; one copied as it is,
## the map maker's file.
static func model_file_problem(bytes: PackedByteArray, built: bool, name: String, source: String) -> String:
	var bad := glb_layout_problem(bytes)
	if bad.is_empty():
		return ""
	if built:
		return OUR_BAD_FILE % ["%s/%s" % [ASSETS_FOLDER, name], bad]
	return "The game can't read the model %s: %s Save it again as glTF Binary (.glb) from the program that made it." % [source, bad]


## What the game's checker would refuse in how a .glb's parts are laid out, as `split_glb` in the game's
## src/map/model.rs reads them, in plain words ending in a full stop, or nothing.
static func glb_layout_problem(bytes: PackedByteArray) -> String:
	if bytes.size() < 12 or bytes.decode_u32(0) != GLB_MAGIC:
		return "It isn't a .glb."
	if bytes.decode_u32(4) != 2:
		return "It is an old kind of glTF."
	if bytes.decode_u32(8) != bytes.size():
		return "Its header says it is %d bytes long, but it is %d." % [bytes.decode_u32(8), bytes.size()]
	var kinds: Array[int] = []
	var at := 12
	while at < bytes.size():
		if bytes.size() - at < 8:
			return "Its last part is cut short."
		var length := bytes.decode_u32(at)
		if length > bytes.size() - at - 8:
			return "One of its parts says it is longer than the file."
		kinds.append(bytes.decode_u32(at + 4))
		at += 8 + length
		if kinds.size() > 2:
			return "It has more parts than a model has."
	if kinds.is_empty() or kinds[0] != GLB_JSON:
		return "Its first part isn't its description."
	if kinds.size() == 2 and kinds[1] != GLB_BIN:
		return "It has a part the game doesn't know."
	return ""


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
	return "The map's file comes to %.1f MB, past the %d MB the game reads. No real map needs that much: the scene looks broken." % [bytes / 1048576.0, MOST_FILE_BYTES / 1048576]


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


## What the map's soft_models knows `found`, one of own_model_pieces, by: a model's file, or for a mesh on
## its own, its mesh's file, or "::" and its name inside a scene for a mesh saved in one. Godot moves a mesh
## from another scene into the map's when it saves the map, keeping that name, so the key stays the same
## however often the map is saved. Nothing for a mesh that was never saved, until mark_key names it.
static func ground_key(found: Dictionary) -> String:
	if not found.has("alone"):
		return found["path"]
	var mesh: Mesh = (found["node"] as MeshInstance3D).mesh
	var path := mesh.resource_path
	if not path.is_empty() and not path.contains("::"):
		return path
	var id := mesh.get_scene_unique_id()
	return "" if id.is_empty() else "::" + id


## The key ground_key gives `found`, having first named its mesh inside the map's scene if it was never
## saved, so that it has one. Godot keeps that name when it saves the scene.
static func mark_key(found: Dictionary) -> String:
	if ground_key(found).is_empty():
		var mesh: Mesh = (found["node"] as MeshInstance3D).mesh
		mesh.set_scene_unique_id(Resource.generate_scene_unique_id())
	return ground_key(found)


## What `found`, one of own_model_pieces, is made of: "rock", "sand" or "silt".
static func ground_of(map: SmartFellasMap, found: Dictionary) -> String:
	var key := ground_key(found)
	return "rock" if key.is_empty() else map.soft_models.get(key, "rock")


## Whether octopuses crawl on `found`, one of own_model_pieces: "size" when the game judges it by its size,
## as it does unless the map maker chose, "always" or "never".
static func crawl_of(map: SmartFellasMap, found: Dictionary) -> String:
	var key := ground_key(found)
	return "size" if key.is_empty() else map.crawl_models.get(key, "size")


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
		if child is GeometryInstance3D and not child is MeshInstance3D and not _is_scatter(child):
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


## Whether `node`, somewhere under `root`, is out of the map for being hidden: it, or a group it's in, is
## hidden with the eye, as hidden_by_eye says.
static func hidden_in(node: Node, root: Node) -> bool:
	var at := node
	while at != null and at != root:
		if hidden_by_eye(at):
			return true
		at = at.get_parent()
	return false


## Whether `node` is the map's flat Seabed: the first node of that name, the one map_root.gd's show_seabed
## finds, not any other that happens to share the name.
static func _is_the_seabed(node: Node) -> bool:
	if node.name != "Seabed" or not (node is Node3D):
		return false
	var root := _root_of(node)
	return root != null and root.find_child("Seabed", true, true) == node


## How many kit pieces are anywhere under `node`, in scenes inside it and hidden ones too.
static func _count_kit_pieces(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		count += 1 if child.scene_file_path.begins_with(KIT_FOLDER) else _count_kit_pieces(child)
	return count


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


## Reads the scene with its own models' pictures as big as the game draws them, or, if they come to more
## than the game takes, again with them all made as big as should fit, half across holding a quarter of the
## pixels, and smaller again while they still come to too much, down to SMALLEST_PICTURE_SIDE.
static func _read_scene(root: SmartFellasMap) -> Scene:
	var scene := _read_scene_with(root, PICTURE_SIDE_DRAWN)
	var over := _pictures_over(scene)
	if over <= 1.0:
		return scene
	var side := PICTURE_SIDE_DRAWN
	while over > 1.0 and side > SMALLEST_PICTURE_SIDE:
		side /= 2
		over /= 4.0
	scene = _read_scene_with(root, side)
	# Pictures already small, or shared, shrink less than a quarter, so the first guess can fall short.
	while _pictures_over(scene) > 1.0 and side > SMALLEST_PICTURE_SIDE:
		side /= 2
		scene = _read_scene_with(root, side)
	return scene


## How many times what the scene's own models' pictures come to the game takes, by pixels or by bytes,
## whichever is more.
static func _pictures_over(scene: Scene) -> float:
	return maxf(float(scene.model_totals["picture_pixels"]) / picture_pixels_taken, float(scene.model_totals["picture_bytes"]) / MOST_MAP_PICTURE_BYTES)


## The scene, read with every picture of its own models made no more than `picture_side` across.
static func _read_scene_with(root: SmartFellasMap, picture_side: int) -> Scene:
	var scene := read_rules(root)
	scene.picture_side = picture_side
	for found in kit_pieces(root):
		_read_piece(found["node"], found["kit"], scene)
	_read_own_models(root, scene)
	_check_crawls(root, scene)
	_read_scatters(root, scene)
	_check_model_totals(scene)
	_read_painted(root, scene)
	_check_placed_triangles(scene)
	_check_piece_names(scene)
	_check_poses(root, scene)
	scene.finder = load("res://addons/smart_fellas_maps/surface_finder.gd").new(root)
	_warn_of_spawns_over_nothing(root, scene)
	_warn_of_food_over_nothing(root, scene)
	var kit := 0
	for piece in scene.pieces:
		if not piece.has("model"):
			kit += 1
	if kit > MOST_PIECES:
		scene.problems.append("The map places %d pieces of the kit, past the %d the game can hold in memory." % [kit, MOST_PIECES])
	if scene.pieces.size() > MOST_ALL_PIECES:
		var copies := ""
		if scene.changes["copies"] > 0:
			copies = " %d of them are copies of scattered meshes (MultiMesh): lower their instance count." % scene.changes["copies"]
		scene.problems.append("The map places %d pieces in all, past the %d the game reads.%s" % [scene.pieces.size(), MOST_ALL_PIECES, copies])
	scene.say_grouped()
	return scene


## Everything but the pieces, which is quick enough for the Map panel to say as things change.
static func read_rules(root: SmartFellasMap) -> Scene:
	var scene := Scene.new()
	var bad_name := name_problem(root.map_name)
	if not bad_name.is_empty():
		scene.problems.append(bad_name)
	_check_area(root, scene)
	_read_children(root, scene)
	if not root.has_seabed:
		scene.has_seabed = false
	elif not scene.has_seabed:
		scene.problems.append("The map has no seabed. Add a mesh called Seabed at the height of the sand, or untick Seabed in the Map panel for a map with none.")
	elif root.seabed_side == 0 and (scene.seabed_height < root.area_box().position.y or scene.seabed_height > root.area_ceiling()):
		scene.problems.append("The seabed is at a height of %s. It must be from the play area's floor, %s, to its ceiling, %s." % [scene.seabed_height, root.area_box().position.y, root.area_ceiling()])
	_check_sculpted(root, scene)
	for team in [["octopus", scene.octopus_spawns], ["diver", scene.diver_spawns]]:
		if team[1].is_empty():
			scene.problems.append("This map has no %s spawn points: place some from the Map panel, or tick Spawns in Populate." % team[0])
		elif team[1].size() > MOST_SPAWNS:
			scene.problems.append("The map has %d %s spawn points, past the %d the game takes." % [team[1].size(), team[0], MOST_SPAWNS])
	_check_patches(scene)
	_check_triggers(root, scene)
	_check_wildlife(root, scene)
	_check_players(root, scene)
	_warn_of_close_spawns(root, scene)
	_check_spawns_above_the_ground(root, scene)
	_warn_of_hidden(scene)
	scene.problems.append_array(WaterLook.problems_with(root.water_depth, root.water_overrides))
	return scene


## The play area is one the game takes: an older map's square, or a box of a size it plays in, near enough
## the middle of the map, as the game's check_play_area.
static func _check_area(root: SmartFellasMap, scene: Scene) -> void:
	if root.play_area() == null:
		_check_range("The map's half width", root.half_width, HALF_WIDTHS, scene)
		_check_range("The map's ceiling", root.ceiling, CEILINGS, scene)
		return
	var box := root.area_box()
	if not (box.position.is_finite() and box.size.is_finite()):
		scene.problems.append("The play area has a number that isn't a real number. Press Fit to map.")
		return
	for corner in [box.position, box.end]:
		if not scenery_kept(corner):
			scene.problems.append("The play area reaches past %d km from the middle of the map. Move it in." % roundi(SCENERY_REACH / 1000.0))
			break
	_check_range("The play area's width (X)", box.size.x, SIDES, scene)
	_check_range("The play area's depth (Z)", box.size.z, SIDES, scene)
	_check_range("The play area's height", box.size.y, HEIGHTS, scene)


## Where the play area runs, in words for a problem.
static func area_words(root: SmartFellasMap) -> String:
	var box := root.area_box()
	var words := PackedStringArray()
	for value in [box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z]:
		words.append(str(snappedf(value, 0.1)))
	return "It runs from %s to %s across (X), %s to %s up and %s to %s along (Z)." % Array(words)


## The game holds a sculpted seabed to these too.
static func _check_sculpted(root: SmartFellasMap, scene: Scene) -> void:
	if not root.has_seabed or (root.seabed_side == 0 and root.seabed_heights.is_empty()):
		return
	var side: int = root.seabed_side
	if side < 2 or side > MOST_SEABED_SIDE or root.seabed_heights.size() != side * side or root.seabed_rock.size() != (side - 1) * (side - 1):
		scene.problems.append("The sculpted seabed's numbers doesn't add up: %d points a side and %d heights. Press Flatten in the Map panel." % [side, root.seabed_heights.size()])
		return
	# The sculpted ground is scenery past the play area, so it may reach as far as anything may stand (#245).
	if not (root.seabed_reach >= 1.0 and root.seabed_reach <= SCENERY_REACH):
		scene.problems.append("The sculpted seabed reaches %s m from the middle. It must be from 1 to %s." % [root.seabed_reach, SCENERY_REACH])
	var middle: Vector2 = root.seabed_middle
	var farthest := maxf(absf(middle.x), absf(middle.y)) + root.seabed_reach
	if not middle.is_finite():
		scene.problems.append("The sculpted seabed's middle isn't a real place. Press Flatten in the Map panel.")
		return
	# Only a map with a play area box may have its ground off the middle: the game refuses it otherwise.
	if middle != Vector2.ZERO and root.play_area() == null:
		scene.problems.append("The sculpted seabed was made over a play area box that's gone. Press Fit to map in the Map panel to make a box again, or Flatten to start the ground again.")
		return
	if farthest > SCENERY_REACH:
		scene.problems.append("The sculpted seabed reaches %.0f m from the middle of the map. It must stay within %d km. Press Flatten in the Map panel." % [farthest, roundi(SCENERY_REACH / 1000.0)])
	var spacing: float = root.seabed_reach * 2.0 / (side - 1)
	# Inside the play area the ground stays between its floor and ceiling, as the game's check_sculpted;
	# outside, it's scenery, and only as far as anything may stand.
	var box := root.area_box()
	var highest := -INF
	var lowest := INF
	for index in side * side:
		var height: float = root.seabed_heights[index]
		if is_nan(height) or is_inf(height):
			scene.problems.append("The sculpted seabed has a height that isn't a real number. Press Flatten in the Map panel.")
			return
		if absf(height) > SCENERY_REACH:
			scene.problems.append("The sculpted seabed has a height of %.1f. It must be within %d km of the middle of the map." % [height, roundi(SCENERY_REACH / 1000.0)])
			return
		var x: float = middle.x - root.seabed_reach + (index % side) * spacing
		var z: float = middle.y - root.seabed_reach + (index / side) * spacing
		if x >= box.position.x and x <= box.end.x and z >= box.position.z and z <= box.end.z:
			highest = maxf(highest, height)
			lowest = minf(lowest, height)
	var floor_height := box.position.y
	if highest > root.area_ceiling() or lowest < floor_height:
		scene.problems.append("Inside the play area, the sculpted seabed reaches a height of %.1f and %.1f. It must stay from the play area's floor, %s, to its ceiling, %s. Move the floor or ceiling, or the ground." % [lowest, highest, floor_height, root.area_ceiling()])
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
		# A spawn tucked under a ledge looks down from inside it, and stands on the floor under it.
		if not scene.finder.meets(at, Vector3(at.x, root.area_box().position.y - 1.0, at.z)):
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
		if not scene.finder.meets(patch["at"] + up * FOOD_FOLLOWS_WITHIN, patch["at"] - up * FOOD_FOLLOWS_WITHIN):
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
		scene.problems.append("The map has %d food patches, past the %d the game takes." % [scene.patches.size(), MOST_PATCHES])


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
			scene.problems.append("The map has %d %s, past the %d the game takes." % [row[1], row[0], row[2]])
	if scene.goblin_route.size() == 1:
		scene.problem_on(scene.goblin_route[0]["node"], "The goblin shark's route has one point. It needs at least %d, or none to take the shark's." % FEWEST_ROUTE_POINTS)
	if not root.goblin_shark and not scene.goblin_route.is_empty():
		scene.warnings.append({"words": "The map has a goblin shark route, and no goblin shark. Turn it on under Sea life.", "node": scene.goblin_route[0]["node"]})
	if not root.stingrays and not scene.haunts["stingrays"].is_empty():
		scene.warnings.append({"words": "The map has stingray stops, and no stingrays. Turn them on under Sea life.", "node": scene.haunts["stingrays"][0]["node"]})
	for holes in ["eels", "gropers"]:
		if not root.hunters and not scene.haunts[holes].is_empty():
			scene.warnings.append({"words": "The map has %s, and nothing hunts on it. Turn on Shark and eels hunt under Sea life." % ("eel holes" if holes == "eels" else "groper holes"), "node": scene.haunts[holes][0]["node"]})


## How many each team is made for, as {"divers", "octopuses"}: as the map says, or by its spawn points, and
## never more than the game takes. Only advice for a lobby, which can go over it.
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
		scene.problems.append("The divers and octopuses it's made for must be 0 or more. 0 means one for each spawn point.")
		return
	if root.anglers_at_once < 1 or root.anglers_at_once > MOST_ANGLERS_AT_ONCE:
		scene.problems.append("Anglerfish at once is %d. It must be from 1 to %d." % [root.anglers_at_once, MOST_ANGLERS_AT_ONCE])
	var sizes := team_sizes(root, scene)
	var most: int = sizes["divers"] + sizes["octopuses"]
	if most > MOST_PLAYERS:
		scene.problems.append("The teams come to %d players, and the game takes %d. Lower the divers or octopuses it's made for." % [most, MOST_PLAYERS])
	if root.fewest_players < 2 or root.fewest_players > most:
		scene.problems.append("The map's fewest players is %d, and its teams come to %d. It must be at least 2 and no more than that." % [root.fewest_players, most])
	for team in [["divers", "diver", scene.diver_spawns], ["octopuses", "octopus", scene.octopus_spawns]]:
		if sizes[team[0]] > team[2].size() and not team[2].is_empty():
			scene.problems.append("The map is made for up to %d %s, and has %d %s spawn points. Each needs one: add some or lower the number." % [sizes[team[0]], team[0], team[2].size(), team[1]])


## Teams that start in sight of each other make for a short, dull round. It's the map maker's call.
static func _warn_of_close_spawns(root: SmartFellasMap, scene: Scene) -> void:
	for octopus in scene.octopus_spawns:
		for diver in scene.diver_spawns:
			var at_octopus: Vector3 = octopus["at"]
			var at_diver: Vector3 = diver["at"]
			var apart := Vector2(at_octopus.x, at_octopus.z).distance_to(Vector2(at_diver.x, at_diver.z))
			var box := root.area_box()
			var wanted := minf(box.size.x, box.size.z) * 0.5
			if apart < wanted:
				# Show it selects the diver spawn, the one to move.
				scene.warnings.append({
					"words": "The teams start close: %s and %s are %.0f m apart, and need %.0f m, half the play area's width. Show it selects %s: drag it and the other diver spawn points to the far end of the play area from the octopus ones." % [octopus["node"].name, diver["node"].name, apart, wanted, diver["node"].name],
					"node": diver["node"],
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
			elif hidden:
				# A scene of the map maker's own is left out whole, so the kit pieces in it needn't be made local.
				for _piece in _count_kit_pieces(child):
					scene.left_out_hidden(hidden_by, "pieces")
			elif not path.begins_with(KIT_FOLDER) and _holds_kit_pieces(child):
				scene.problem_on(child, "%s is a scene inside this one, and Export can't see the pieces in it. Right-click it in the Scene panel and choose Make Local." % child.name)
			continue
		if _is_the_seabed(child):
			if _root_of(child).has_seabed:
				_read_seabed(child, scene)
		elif child is Marker3D or child.get_script() == TriggerZone:
			if hidden:
				scene.left_out_hidden(hidden_by, "markers" if child is Marker3D else "zones")
			elif child is Marker3D:
				_read_marker(child, scene)
			else:
				_read_trigger(child, scene)
		_read_children(child, scene, hidden_by)


## Tells the map maker how many hidden things are out of the map, so hiding a group never loses half a
## map without a word.
static func _warn_of_hidden(scene: Scene) -> void:
	var counts: Array[String] = []
	var total := 0
	for kind: Array in [["pieces", "piece"], ["markers", "marker"], ["zones", "trigger zone"]]:
		var count: int = scene.hidden[kind[0]]
		total += count
		if count > 0:
			counts.append("%d %s%s" % [count, kind[1], "" if count == 1 else "s"])
	if total == 0:
		return
	var one := total == 1
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
		return root.area_box().position.y - at.y
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
		if not in_the_map(root, spot):
			scene.problem_on(marker, "%s is too near the play area's edge: its food would grow at (%.1f, %.1f, %.1f), outside it. %s Move it in by %s m." % [marker.name, spot.x, spot.y, spot.z, area_words(root), SPOT_RING])
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
	elif not in_the_map(root, at):
		scene.problem_on(marker, "%s is at (%.1f, %.1f, %.1f), outside the map's play area. %s" % [marker.name, at.x, at.y, at.z, area_words(root)])
		return false
	return true


## Each of the map's own models placed in it, given the name it has in the package. A model is checked
## here for what the game's checker would refuse, so the map maker hears why in Godot; the game's checker
## still reads every part of it. A model the game can't take as it is, but Godot can read, is turned into a
## .glb the game takes. Nothing is left out without a word.
static func _read_own_models(root: SmartFellasMap, scene: Scene) -> void:
	var names_of := {}
	var first_in_place := {}
	for found in own_model_pieces(root):
		var node: Node3D = found["node"]
		var path: String = found["path"]
		_warn_of_twin(node, found, first_in_place, scene)
		if not names_of.has(path) and found.has("alone") and _too_wide(node):
			var parts := _cut_wide_mesh(node, ground_of(root, found), crawl_of(root, found), scene)
			if parts > 0:
				scene.changes["cut"] += 1
				scene.changes["cut_parts"] += parts
			continue
		if not names_of.has(path):
			var alone: bool = found.has("alone")
			var source := ProjectSettings.globalize_path(path) if not alone else path
			var called := "%s's model %s" % [node.name, path.get_file()] if not alone else String(node.name)
			var bytes := PackedByteArray()
			if found["made"] == "copied":
				bytes = FileAccess.get_file_as_bytes(source)
				if bytes.is_empty():
					scene.problem_on(node, "%s's model %s can't be read." % [node.name, path])
					continue
				if glb_description(bytes).is_empty():
					scene.problem_on(node, "%s's model %s isn't a .glb the game can read. Save it again as glTF Binary (.glb) from the program that made it." % [node.name, path.get_file()])
					continue
				# Pictures the game won't take, such as JPEG, as models from Sketchfab often have, or ones
				# bigger than it draws, are made into ones it will.
				# So is one that needs a glTF extension the game can't read, such as WebP pictures or packed
				# meshes, which Godot can.
				# So is one with more pictures than the game takes in a model, as one with bump and shine
				# pictures has, which the game never draws.
				var big := _widest_picture(bytes, source) > scene.picture_side
				var tally := model_tally(glb_description(bytes))
				var crowded: bool = tally["pictures"] > MOST_MODEL_PICTURES or tally["materials"] > MOST_MODEL_MATERIALS
				if big or crowded or not _pictures_problem(bytes, source).is_empty() or not glb_description(bytes).get("extensionsRequired", []).is_empty():
					bytes = PackedByteArray()
			var base := model_name(path if not alone else String(node.name))
			var name := _free_model_name(base, scene)
			var names: Array[String] = [name]
			if bytes.is_empty():
				var split := split_glbs(node, alone, scene.picture_side, scene.changes)
				var made: Array[PackedByteArray] = split["glbs"]
				if made.is_empty():
					scene.problem_on(node, "%s can't be made into a model for the game. Save it as glTF Binary (.glb) from the program that made it, copy that into this project, and drag it in instead." % node.name)
					continue
				if made.size() > 1:
					scene.changes["split"] += 1
				var kept: Array[String] = []
				for index in made.size():
					if index > 0:
						names.append(_free_model_name("%s_part%d.glb" % [base.get_basename(), index + 1], scene))
					scene.built[names[index]] = made[index]
					scene.model_middles[names[index]] = split["middle"]
					if _take_model(node, called, names[index], source, made[index], scene):
						kept.append(names[index])
				if kept.is_empty():
					continue
				names = kept
			else:
				if not _take_model(node, called, name, source, bytes, scene):
					continue
				if not _read_model_pictures(node, source, bytes, scene):
					continue
			names_of[path] = names
			for each in names:
				scene.model_grounds[each] = ground_of(root, found)
				scene.model_crawls[each] = crawl_of(root, found)
		for index in names_of[path].size():
			_read_piece(node, "", scene, names_of[path][index], index == 0)
	# What maps can't use yet is left out with a word, and the map exports without it.
	for other in left_out(root):
		var node: Node = other["node"]
		var what: String = other["what"]
		var words := _left_out_words(node, what)
		# GPU and CPU particles are one line, as are CSG boxes and spheres.
		var kind := "particles" if what.contains("Particles") else "CSG" if what.begins_with("CSG") else what
		scene.warning_among(node, kind, words[0], words[1])


## Says so if `node`, a model of the map's own as own_model_pieces finds it, is the same mesh or model as one
## found before in the same place, which `first_in_place` keeps by mesh and place: the two flicker through
## each other in the game.
static func _warn_of_twin(node: Node3D, found: Dictionary, first_in_place: Dictionary, scene: Scene) -> void:
	var made_of: String = found["path"]
	if found.has("alone"):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		made_of = mesh.resource_path if not mesh.resource_path.is_empty() else "mesh %d" % mesh.get_instance_id()
	var key := "%s at %s" % [made_of, node.global_transform]
	if not first_in_place.has(key):
		first_in_place[key] = node
		return
	var first: Node = first_in_place[key]
	scene.warning_among(node, "twins", "%s is the same mesh as %s in the same place, so the two flicker through each other in the game. Delete one." % [node.name, first.name], "%d meshes are the same mesh as another in the same place, so they flicker through each other in the game. Delete one of each.", "%s, the same as %s" % [node.name, first.name])


## What Export says of `node`, of the class `what`, which it leaves out: as [words for it alone, words with
## %d for how many].
static func _left_out_words(node: Node, what: String) -> Array[String]:
	if what == EMPTY_SCENE:
		return [
			"%s is a scene with no mesh showing in it, so nothing of it comes out." % node.name,
			"%d scenes have no mesh showing in them, so nothing of them comes out.",
		]
	if what.begins_with("CSG"):
		return [
			"%s is a CSG shape, so it was left out. To keep it, select it, then CSG > Bake Mesh Instance." % node.name,
			"%d CSG shapes were left out. To keep one, select it, then CSG > Bake Mesh Instance.",
		]
	if what.contains("Particles"):
		return [
			"%s is a particle system, so it was left out (maps can't use them yet)." % node.name,
			"%d particle systems were left out (maps can't use them yet).",
		]
	return [
		"%s is a %s, so it was left out (maps can't use them yet)." % [node.name, what],
		"%%d nodes are %s, so they were left out (maps can't use them yet)." % what,
	]


## Takes `bytes` as the map's own model `name`, made from `source`, for `node`, which `called` names, once it
## has checked it as the game would. Gives back whether it was taken.
static func _take_model(node: Node, called: String, name: String, source: String, bytes: PackedByteArray, scene: Scene) -> bool:
	if bytes.size() > MOST_MODEL_BYTES:
		scene.problem_on(node, "%s is %.1f MB, past the %d MB the game can hold in memory." % [called, bytes.size() / 1048576.0, MOST_MODEL_BYTES / 1048576])
		return false
	var description := glb_description(bytes)
	var tally := model_tally(description)
	if tally["triangles"] == 0:
		var built := scene.built.has(name)
		scene.built.erase(name)
		scene.model_middles.erase(name)
		if built and _draws_triangles(node):
			scene.problem_on(node, OUR_BAD_FILE % [called, "It came out with nothing to draw, though its mesh has triangles."])
			return false
		scene.warning_among(node, "nothing to draw", "%s has nothing to draw in it, so it was left out." % called, "%d models have nothing to draw in them, so they were left out.")
		return false
	var too_much := _model_limits_problem(tally)
	if too_much.is_empty():
		too_much = _pictures_problem(bytes, source)
	if too_much.is_empty() and model_reach(description) > MOST_MODEL_REACH:
		too_much = _reach_problem(model_reach(description))
	if not too_much.is_empty():
		var many := _many_models_over(too_much)
		scene.problem_among(node, many, "%s %s" % [called, too_much], many, "%s %s" % [called, too_much])
		return false
	for key: String in ["triangles", "corners", "materials"]:
		scene.model_totals[key] += tally[key]
	scene.model_triangles[name] = tally["triangles"]
	var pictures := _colour_pictures(bytes, source)
	for look in _looks_of(description, tally["used"], pictures):
		scene.looks[look] = true
	for picture in pictures:
		var md5 := _md5_of(picture)
		scene.picture_weights[md5] = picture.size()
		scene.picture_pixels[md5] = _pixels_drawn(picture)
	var weight := 0
	for each: int in scene.picture_weights.values():
		weight += each
	scene.model_totals["picture_bytes"] = weight
	var pixels := 0
	for each: int in scene.picture_pixels.values():
		pixels += each
	scene.model_totals["picture_pixels"] = pixels
	if not model_has_a_picture(bytes):
		scene.warning_among(node, "no picture", "%s has no picture, only colours. An octopus copying it wears its plain colour." % node.name, "%d models have no picture, only colours. An octopus copying one wears its plain colour.")
	scene.models[name] = source
	return true


## Whether `node` has triangles to draw: a mesh's own, a scattered mesh's, or those of the meshes in a scene.
static func _draws_triangles(node: Node) -> bool:
	var meshes: Array[Mesh] = []
	if node is MeshInstance3D:
		meshes.append(node.mesh)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		meshes.append(node.multimesh.mesh)
	else:
		for part in meshes_in(node):
			meshes.append(part.mesh)
	meshes = meshes.filter(func(mesh: Mesh) -> bool: return mesh != null)
	for mesh in meshes:
		for surface in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES and mesh.surface_get_array_len(surface) > 0:
				return true
	return false


## How many pixels the game draws a PNG with: no more than PICTURE_SIDE_DRAWN across, as it shrinks one.
static func _pixels_drawn(png: PackedByteArray) -> int:
	if png.size() < 24 or png.slice(1, 4).get_string_from_ascii() != "PNG":
		return 0
	var width := _big_endian(png, 16)
	var height := _big_endian(png, 20)
	var widest := maxi(maxi(width, height), 1)
	var shrink := minf(1.0, float(PICTURE_SIDE_DRAWN) / widest)
	return maxi(roundi(width * shrink), 1) * maxi(roundi(height * shrink), 1)


static func _md5_of(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


## How each material a model draws with looks, as the game tells looks apart: two materials that look the
## same are one surface, however many models they're in. `used` is which materials its meshes draw with, and
## `pictures` the colour pictures, one for each material that has one, in the order of its materials.
static func _looks_of(description: Dictionary, used: Array, pictures: Array[PackedByteArray]) -> Array[String]:
	var materials: Array = description.get("materials", [])
	var textures: Array = description.get("textures", [])
	var picture_of := {}
	var next := 0
	for index in materials.size():
		var texture: int = materials[index].get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index", -1)
		if texture >= 0 and texture < textures.size() and textures[texture].get("source", -1) >= 0 and next < pictures.size():
			picture_of[index] = _md5_of(pictures[next])
			next += 1
	var looks: Array[String] = []
	for index: int in used:
		if index < 0 or index >= materials.size():
			looks.append("plain")
			continue
		var material: Dictionary = materials[index]
		var pbr: Dictionary = material.get("pbrMetallicRoughness", {})
		looks.append(str([
			pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]), picture_of.get(index, ""), pbr.get("metallicFactor", 1.0),
			pbr.get("roughnessFactor", 1.0), material.get("doubleSided", false), _seen_through(material),
			material.get("extensions", {}).has("KHR_materials_unlit"),
		]))
	return looks


## How what is behind a glTF material shows through it, as the game tells it: added to or multiplied, as the
## material's extras say; cut out where its alpha is below its cutoff; blended; or not at all, as null.
static func _seen_through(material: Dictionary) -> Variant:
	var extras: Variant = material.get("extras", {})
	if extras is Dictionary and (extras as Dictionary).get(BLEND_EXTRA) is String:
		return extras[BLEND_EXTRA]
	match material.get("alphaMode", "OPAQUE"):
		"MASK":
			return ["MASK", material.get("alphaCutoff", 0.5)]
		"BLEND":
			return "BLEND"
	return null


## The game's limits on all the map's own models together.
static func _check_model_totals(scene: Scene) -> void:
	var totals: Dictionary = scene.model_totals
	if scene.models.size() > MOST_MODELS:
		scene.problems.append("The map uses %d models of its own, past the %d the game reads. No real map needs that many." % [scene.models.size(), MOST_MODELS])
	# map.ron, the assets/ folder, the models and the pictures beside them.
	var files: int = 2 + scene.models.size() + scene.picture_weights.size()
	if files > MOST_ENTRIES:
		scene.problems.append("The map's package would hold %d files, past the %d the game reads. No real map needs that many." % [files, MOST_ENTRIES])
	if scene.looks.size() > MOST_MAP_MATERIALS:
		scene.problems.append("The map's own models use %d different materials between them, past the %d the game can number. No real map needs that many: the scene looks broken." % [scene.looks.size(), MOST_MAP_MATERIALS])
	if totals["triangles"] > MOST_MAP_TRIANGLES:
		scene.problems.append("The map's own models have %d triangles between them, past the %d the game can hold in memory." % [totals["triangles"], MOST_MAP_TRIANGLES])
	if totals["corners"] > MOST_MAP_CORNERS:
		scene.problems.append("The map's own models have %d corners between them, past the %d the game can hold in memory." % [totals["corners"], MOST_MAP_CORNERS])
	# Pictures still past picture_pixels_taken at their smallest here are fine: the game draws them smaller
	# again as it loads the map, rather than refusing it (#299).
	if totals["picture_bytes"] > MOST_MAP_PICTURE_BYTES:
		scene.problems.append("The map's own models' pictures come to %.1f MB between them, even made %d pixels across, past the %d MB the game can hold in memory." % [totals["picture_bytes"] / 1048576.0, scene.picture_side, MOST_MAP_PICTURE_BYTES / 1048576])


## The game's limit on the colliders the pieces made of the map's own models copy, which only guards memory.
## What they draw is the map's performance score, never a limit (#299).
static func _check_placed_triangles(scene: Scene) -> void:
	var resized := 0
	for piece in scene.pieces:
		if piece.has("model") and float(piece["scale"]) != 1.0:
			resized += scene.model_triangles.get(piece["model"], 0)
	if resized > MOST_SCALED_TRIANGLES:
		scene.problems.append("The map's own models placed at a size other than their own come to %d triangles, past the %d the game can hold in memory: each keeps a copy of its model's shape for bumping into." % [resized, MOST_SCALED_TRIANGLES])


## `wanted`, or the same with a number after it if another model has that name already.
static func _free_model_name(wanted: String, scene: Scene) -> String:
	var name := wanted
	var number := 2
	while scene.models.has(name):
		name = "%s_%d.glb" % [wanted.get_basename(), number]
		number += 1
	return name


## What a .glb holds as the game counts it, object by object from its scene, so that a mesh drawn twice
## counts twice: {"triangles", "corners", "materials", "pictures", "picture_bytes", "used", "surfaces"}, the
## last the most surfaces any one of its meshes has, the pictures as
## the materials it draws with refer to them, and "used" which materials those are. The same walk as
## src/map/model.rs.
static func model_tally(description: Dictionary) -> Dictionary:
	var tally := {"triangles": 0, "corners": 0, "materials": 0, "pictures": description.get("images", []).size(), "picture_bytes": 0, "surfaces": 0}
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
		tally["surfaces"] = maxi(tally["surfaces"], meshes[mesh].get("primitives", []).size())
		for primitive: Dictionary in meshes[mesh].get("primitives", []):
			var position: int = primitive.get("attributes", {}).get("POSITION", -1)
			var count: int = accessors[position].get("count", 0) if position >= 0 and position < accessors.size() else 0
			tally["corners"] += count
			var indices: int = primitive.get("indices", -1)
			tally["triangles"] += (accessors[indices].get("count", 0) if indices >= 0 and indices < accessors.size() else count) / 3
			used[primitive.get("material", -1)] = true
	tally["materials"] = used.size()
	tally["used"] = used.keys()
	return tally


## How far a .glb reaches from its middle along any one way, in metres, as the game's checker measures it:
## each mesh's box where its nodes put it.
static func model_reach(description: Dictionary) -> float:
	var nodes: Array = description.get("nodes", [])
	var meshes: Array = description.get("meshes", [])
	var accessors: Array = description.get("accessors", [])
	var scenes: Array = description.get("scenes", [])
	var index: int = description.get("scene", 0)
	var waiting: Array = []
	for top in (scenes[index].get("nodes", []) if index >= 0 and index < scenes.size() else []):
		waiting.append([int(top), Transform3D.IDENTITY])
	var reach := 0.0
	var seen := {}
	while not waiting.is_empty():
		var next: Array = waiting.pop_back()
		var at: int = next[0]
		if seen.has(at) or at < 0 or at >= nodes.size():
			continue
		seen[at] = true
		var node: Dictionary = nodes[at]
		var place: Transform3D = next[1] * _node_place(node)
		for child in node.get("children", []):
			waiting.append([int(child), place])
		var mesh: int = node.get("mesh", -1)
		if mesh < 0 or mesh >= meshes.size():
			continue
		for primitive: Dictionary in meshes[mesh].get("primitives", []):
			var position: int = primitive.get("attributes", {}).get("POSITION", -1)
			if position < 0 or position >= accessors.size() or not accessors[position].has("min"):
				continue
			var low: Array = accessors[position]["min"]
			var high: Array = accessors[position]["max"]
			for corner in 8:
				var point := Vector3(high[0] if corner & 1 else low[0], high[1] if corner & 2 else low[1], high[2] if corner & 4 else low[2])
				var placed := place * point
				reach = maxf(reach, maxf(absf(placed.x), maxf(absf(placed.y), absf(placed.z))))
	return reach


## Where a glTF node sits under its parent.
static func _node_place(node: Dictionary) -> Transform3D:
	if node.has("matrix"):
		var m: Array = node["matrix"]
		return Transform3D(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10]), Vector3(m[12], m[13], m[14]))
	var t: Array = node.get("translation", [0.0, 0.0, 0.0])
	var r: Array = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
	var k: Array = node.get("scale", [1.0, 1.0, 1.0])
	var basis := Basis(Quaternion(r[0], r[1], r[2], r[3]).normalized()).scaled(Vector3(k[0], k[1], k[2]))
	return Transform3D(basis, Vector3(t[0], t[1], t[2]))


## What Export says, with %d for how many, of many models over the limit `too_much`, as
## _model_limits_problem, _pictures_problem or _take_model says it of one.
static func _many_models_over(too_much: String) -> String:
	var what := "are over a limit the game has for one model"
	for kind: String in ["triangles", "corners", "materials", "pictures"]:
		if too_much.begins_with("has ") and too_much.get_slice(",", 0).ends_with(" " + kind):
			what = "have more %s than the game takes in one model" % kind
	if too_much.begins_with("has a mesh of"):
		what = "have a mesh of more surfaces than the game takes"
	elif too_much.begins_with("has a picture that isn't a PNG"):
		what = "have a picture that isn't a PNG"
	elif too_much.begins_with("has a picture of"):
		what = "have a picture heavier than the game takes"
	elif too_much.begins_with("has a picture"):
		what = "have a picture bigger than the game takes"
	elif too_much.begins_with("reaches"):
		what = "reach further from their middle than the game takes"
	return "%%d models %s. Details says which, and what to do." % what


## What the game's checker would refuse in a model that counts up to `tally`, in plain words ending in a
## full stop, or nothing.
static func _model_limits_problem(tally: Dictionary) -> String:
	if tally["triangles"] > MOST_MODEL_TRIANGLES:
		return "has %d triangles, past the %d the game can hold in memory for one model." % [tally["triangles"], MOST_MODEL_TRIANGLES]
	if tally["corners"] > MOST_MODEL_CORNERS:
		return "has %d corners, past the %d the game can hold in memory for one model." % [tally["corners"], MOST_MODEL_CORNERS]
	if tally["materials"] > MOST_MODEL_MATERIALS:
		return "has %d materials, and the game takes at most %d in one model. Drag its mesh into the scene in place of the model, and Export splits it by material." % [tally["materials"], MOST_MODEL_MATERIALS]
	if tally["surfaces"] > MOST_PRIMITIVES:
		return "has a mesh of %d surfaces, and the game takes at most %d. Drag its mesh into the scene in place of the model, and Export joins surfaces of one material." % [tally["surfaces"], MOST_PRIMITIVES]
	if tally["pictures"] > MOST_MODEL_PICTURES:
		return "has %d pictures, and the game takes at most %d in one model. Drag its mesh into the scene in place of the model, and Export splits it by material." % [tally["pictures"], MOST_MODEL_PICTURES]
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
		var problem := _picture_problem(picture)
		if not problem.is_empty():
			return problem
	return ""


## What the game's checker would refuse in one picture of a model, in plain words, or nothing.
static func _picture_problem(picture: PackedByteArray) -> String:
	if picture.size() < 24 or picture.slice(1, 4).get_string_from_ascii() != "PNG":
		return "has a picture that isn't a PNG. Save its pictures as PNG, then save the model again."
	var width := _big_endian(picture, 16)
	var height := _big_endian(picture, 20)
	if width > MOST_PICTURE_SIDE or height > MOST_PICTURE_SIDE:
		return "has a picture %d x %d, past the %d x %d the game can decode." % [width, height, MOST_PICTURE_SIDE, MOST_PICTURE_SIDE]
	if picture.size() > MOST_PICTURE_BYTES:
		return "has a picture of %.1f MB, past the %d MB the game can hold in memory." % [picture.size() / 1048576.0, MOST_PICTURE_BYTES / 1048576]
	return ""


## What Export says of a model reaching `reach` metres from its middle, past MOST_MODEL_REACH.
static func _reach_problem(reach: float) -> String:
	return "reaches %.0f m from its middle, past the %.0f m the game can draw exactly." % [reach, MOST_MODEL_REACH]


## How many pixels across the widest or tallest of a .glb's colour pictures is, if they're PNGs.
static func _widest_picture(bytes: PackedByteArray, source: String) -> int:
	var widest := 0
	for picture in _colour_pictures(bytes, source):
		if picture.size() >= 24 and picture.slice(1, 4).get_string_from_ascii() == "PNG":
			widest = maxi(widest, maxi(_big_endian(picture, 16), _big_endian(picture, 20)))
	return widest


## The number in the four bytes of `bytes` from `at`, biggest first, as a PNG keeps its sizes.
static func _big_endian(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Takes off what only draws a mesh here: the editor's underwater preview, or any shader, which the game
## never draws, and every picture but the colour one, which is all the game reads. What it's made of
## underneath is what the game wears.
##
## A picture more than `side` pixels across is made that size, and one Godot keeps packed for the graphics
## card is unpacked, so that Godot can write it as a PNG. Gives back whether it shrank one.
static func _undress(part: MeshInstance3D, side: int) -> bool:
	if part.material_override != null and not part.material_override is BaseMaterial3D:
		part.material_override = null
	for surface in part.get_surface_override_material_count():
		var over := part.get_surface_override_material(surface)
		if over != null and not over is BaseMaterial3D:
			part.set_surface_override_material(surface, null)
	# One material laid over the whole mesh wins over each surface's, so it's the one dressed.
	if part.material_override != null:
		var shrunk := _widest(part.material_override) > side
		part.material_override = _drawn_material(part.material_override, side)
		return shrunk
	var any := false
	for surface in part.get_surface_override_material_count():
		var material := part.get_active_material(surface)
		if material is BaseMaterial3D:
			any = any or _widest(material) > side
			part.set_surface_override_material(surface, _drawn_material(material, side))
	return any


## What `part` wears on `surface` in the game: what Godot draws there, unless that's a material the game can't
## read, such as the editor's underwater preview, when it's what's beneath.
static func _material_worn(part: MeshInstance3D, surface: int) -> Material:
	if part.material_override is BaseMaterial3D:
		return part.material_override
	var over := part.get_surface_override_material(surface)
	if over is BaseMaterial3D:
		return over
	return part.mesh.surface_get_material(surface)


## Joins the surfaces of `part`'s mesh that are drawn with the same material into one, as one draw: the
## game reads at most MOST_PRIMITIVES surfaces in a mesh, and a mesh imported from another game can have many
## surfaces of a few materials. Only meshes of triangles are joined.
static func _join_same_materials(part: MeshInstance3D) -> void:
	if not part.mesh is ArrayMesh:
		return
	var mesh: ArrayMesh = part.mesh
	var groups := {}
	var order: Array[Material] = []
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return
		var material := part.get_active_material(surface)
		if not groups.has(material):
			groups[material] = []
			order.append(material)
		groups[material].append(surface)
	if order.size() == mesh.get_surface_count():
		return
	var joined := ArrayMesh.new()
	for material in order:
		var tool := SurfaceTool.new()
		for surface: int in groups[material]:
			tool.append_from(mesh, surface, Transform3D.IDENTITY)
		tool.commit(joined)
		joined.surface_set_material(joined.get_surface_count() - 1, material)
	part.material_override = null
	part.mesh = joined
	for surface in joined.get_surface_count():
		part.set_surface_override_material(surface, null)


## Materials made ready for a .glb, by the material they were made from and the most pixels across, so
## that surfaces sharing a material still share one in the .glb. Emptied at the start of each export.
static var _materials_drawn := {}


## `material` as the game draws it: only its colour picture, unpacked and no more than `side` across, and
## what glTF has no words for in its extras: whether it adds to or multiplies what is behind it, and whether
## it is drawn without its mesh's corner colours.
static func _drawn_material(material: BaseMaterial3D, side: int) -> BaseMaterial3D:
	var key := "%d %d" % [material.get_instance_id(), side]
	if _materials_drawn.has(key):
		return _materials_drawn[key]
	var drawn := _with_picture_drawn(material, side)
	if drawn == null:
		drawn = material.duplicate()
	for texture in BaseMaterial3D.TEXTURE_MAX:
		if texture != BaseMaterial3D.TEXTURE_ALBEDO:
			drawn.set_texture(texture, null)
	var extras: Dictionary = {}
	if drawn.has_meta("extras") and drawn.get_meta("extras") is Dictionary:
		extras = (drawn.get_meta("extras") as Dictionary).duplicate()
	extras.erase(BLEND_EXTRA)
	extras.erase(CORNER_COLOURS_EXTRA)
	match drawn.blend_mode:
		BaseMaterial3D.BLEND_MODE_ADD:
			extras[BLEND_EXTRA] = "add"
		BaseMaterial3D.BLEND_MODE_MUL:
			extras[BLEND_EXTRA] = "multiply"
	if not drawn.vertex_color_use_as_albedo:
		extras[CORNER_COLOURS_EXTRA] = false
	if extras.is_empty():
		if drawn.has_meta("extras"):
			drawn.remove_meta("extras")
	else:
		drawn.set_meta("extras", extras)
	_materials_drawn[key] = drawn
	return drawn


## How many pixels across the widest side of a material's colour picture is, or 0 if it has none.
static func _widest(material: Material) -> int:
	if not material is BaseMaterial3D or (material as BaseMaterial3D).albedo_texture == null:
		return 0
	var texture: Texture2D = (material as BaseMaterial3D).albedo_texture
	return maxi(texture.get_width(), texture.get_height())


## Pictures made ready for a .glb, by the picture they were made from and the most pixels across: a picture
## many materials share is shrunk once. Emptied at the start of each export.
static var _pictures_drawn := {}


## A copy of `material` with its colour picture unpacked and no more than `side` pixels across, or null if
## it needs neither.
static func _with_picture_drawn(material: Material, side: int) -> BaseMaterial3D:
	if not material is BaseMaterial3D or (material as BaseMaterial3D).albedo_texture == null:
		return null
	var key := "%d %d" % [(material as BaseMaterial3D).albedo_texture.get_instance_id(), side]
	if _pictures_drawn.has(key):
		var drawn: Texture2D = _pictures_drawn[key]
		if drawn == null:
			return null
		var reused: BaseMaterial3D = (material as BaseMaterial3D).duplicate()
		reused.albedo_texture = drawn
		return reused
	var picture: Image = (material as BaseMaterial3D).albedo_texture.get_image()
	if picture == null:
		return null
	var packed: bool = picture.is_compressed()
	if packed:
		picture.decompress()
	var widest := maxi(picture.get_width(), picture.get_height())
	if widest <= side and not packed:
		_pictures_drawn[key] = null
		return null
	if widest > side:
		var shrink := float(side) / widest
		picture.resize(maxi(roundi(picture.get_width() * shrink), 1), maxi(roundi(picture.get_height() * shrink), 1), Image.INTERPOLATE_LANCZOS)
	var copy: BaseMaterial3D = (material as BaseMaterial3D).duplicate()
	copy.albedo_texture = ImageTexture.create_from_image(picture)
	_pictures_drawn[key] = copy.albedo_texture
	return copy


## A .glb the game takes, made by Godot from `node` and what's under it as they're drawn now, with its
## pictures as PNG, and `node` itself at the middle: the piece holds where it stands. With `alone`, only
## `node`'s own mesh, as the meshes under it are pieces of their own. Pictures are made no more than `side`
## pixels across, and `changes["shrunk"]` counts it if any was. With `middle`, that point under `node` is the
## model's middle instead. Empty if Godot can't make one.
static func built_glb(node: Node3D, alone: bool, side := PICTURE_SIDE_DRAWN, changes := {}, middle := Vector3.ZERO) -> PackedByteArray:
	var copy := node.duplicate() as Node3D
	if copy == null:
		return PackedByteArray()
	copy.transform = Transform3D(Basis.IDENTITY, -middle)
	if alone:
		for child in copy.get_children():
			copy.remove_child(child)
			child.free()
	# Scattered meshes in it are made into copies of their own, by _read_scatters.
	for scatter in copy.find_children("*", "MultiMeshInstance3D", true, false):
		scatter.get_parent().remove_child(scatter)
		scatter.free()
	var shrunk := false
	for part in meshes_in(copy):
		shrunk = _undress(part, side) or shrunk
		_join_same_materials(part)
	if shrunk and changes.has("shrunk"):
		changes["shrunk"] += 1
	# In the editor, Godot leaves out of a .glb every node under the top one that has no owner, taking it for
	# a tool script's passing node. Export's copies and holders are made of such nodes.
	for inside in copy.find_children("*", "", true, false):
		inside.owner = copy
	var document := GLTFDocument.new()
	document.image_format = "PNG"
	var state := GLTFState.new()
	var bytes := PackedByteArray()
	if document.append_from_scene(copy, state) == OK:
		bytes = length_set_right(document.generate_buffer(state))
	copy.free()
	return bytes


## `bytes`, a .glb Godot made, with the length in its header made right: for one with nothing in its
## binary part, as a model with nothing to draw, Godot counts that part's header though it leaves it out.
static func length_set_right(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() >= 20 and bytes.decode_u32(8) == bytes.size() + 8 and 20 + bytes.decode_u32(12) == bytes.size():
		bytes.encode_u32(8, bytes.size())
	return bytes


## Whether the game takes a marker, a food spot or a trigger zone's middle at `at` in `root`'s map: inside its
## play area, edges, floor and ceiling included. The game's `PlayArea::contains` in `src/map/play_area.rs`.
static func in_the_map(root: SmartFellasMap, at: Vector3) -> bool:
	var box := root.area_box()
	return at.x >= box.position.x and at.x <= box.end.x and at.y >= box.position.y and at.y <= box.end.y and at.z >= box.position.z and at.z <= box.end.z


## Whether the game takes scenery (a piece of the kit or of the map's own models, a copy of a scattered mesh)
## standing at `at`: anywhere in or out of the play area, up to SCENERY_REACH from the middle of the map each
## way, where numbers stay exact enough to draw. The one rule Export keeps scenery by. It is the game's
## `Area::SCENERY` in `src/map/check.rs`: keep the two the same.
static func scenery_kept(at: Vector3) -> bool:
	return at.is_finite() and absf(at.x) <= SCENERY_REACH and absf(at.y) <= SCENERY_REACH and absf(at.z) <= SCENERY_REACH


## `at` moved the shortest way to where scenery_kept takes it, a hair inside, so a number written in the
## map's file and read back a little rounded is still in.
static func into_scenery_reach(at: Vector3) -> Vector3:
	return at.clamp(Vector3.ONE * -(SCENERY_REACH - EDGE_HAIR), Vector3.ONE * (SCENERY_REACH - EDGE_HAIR))


## Whether `node`, a mesh on its own, reaches further from its middle than CUT_REACH, as a mesh imported
## from a whole level, holding everything of one material across it, does.
static func _too_wide(node: MeshInstance3D) -> bool:
	var box: AABB = node.global_transform * node.mesh.get_aabb()
	return box.size.x > CUT_REACH * 2.0 or box.size.z > CUT_REACH * 2.0 or box.size.y > CUT_REACH * 2.0


## Cuts `node`, a mesh on its own too wide for one model, into parts by where its triangles lie, each a model
## of the map's own standing at its own middle: as few as cover the mesh with parts no wider than the game
## takes in a model, each made of `ground`. Triangles further out than the game takes scenery are left out.
## Gives back how many parts.
static func _cut_wide_mesh(node: MeshInstance3D, ground: String, crawl: String, scene: Scene) -> int:
	var place := node.global_transform
	# The squares the parts are cut by cover the mesh, as far as the game takes scenery.
	var box: AABB = place * node.mesh.get_aabb()
	var start := Vector2(box.position.x, box.position.z).clamp(-Vector2.ONE * SCENERY_REACH, Vector2.ONE * SCENERY_REACH)
	var span := (Vector2(box.end.x, box.end.z).clamp(-Vector2.ONE * SCENERY_REACH, Vector2.ONE * SCENERY_REACH) - start).max(Vector2.ONE)
	var cells := Vector2i(maxi(ceili(span.x / WIDEST_CUT), 1), maxi(ceili(span.y / WIDEST_CUT), 1))
	var cell := span / Vector2(cells)
	var turn := place.basis.orthonormalized()
	var mesh := node.mesh
	# Each part's triangles, by its cell, as {surface number: PackedInt32Array of corners}.
	var parts := {}
	var left_out := 0
	var lists := []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		lists.append(arrays)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(points.size()))
		for first in range(0, corners.size() - 2, 3):
			var middle := place * ((points[corners[first]] + points[corners[first + 1]] + points[corners[first + 2]]) / 3.0)
			if not scenery_kept(middle):
				left_out += 1
				continue
			var key := Vector2i(clampi(floori((middle.x - start.x) / cell.x), 0, cells.x - 1), clampi(floori((middle.z - start.y) / cell.y), 0, cells.y - 1))
			if not parts.has(key):
				parts[key] = {}
			if not parts[key].has(surface):
				parts[key][surface] = PackedInt32Array()
			parts[key][surface].append_array([corners[first], corners[first + 1], corners[first + 2]])
	var made := 0
	var base := model_name(String(node.name)).get_basename()
	var keys: Array = parts.keys()
	keys.sort()
	for key: Vector2i in keys:
		var cut := ArrayMesh.new()
		var low := Vector3.INF
		var high := -Vector3.INF
		for surface: int in parts[key]:
			for corner in parts[key][surface]:
				var at: Vector3 = place * lists[surface][Mesh.ARRAY_VERTEX][corner]
				low = low.min(at)
				high = high.max(at)
		# Its triangles' middles are all in, but the middle of all its corners can lie past the edge, or
		# under the floor where the ground dips below it.
		var middle := into_scenery_reach((low + high) / 2.0)
		for surface: int in parts[key]:
			cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cut_arrays(lists[surface], parts[key][surface], place, turn, middle))
			cut.surface_set_material(cut.get_surface_count() - 1, _material_worn(node, surface))
		var holder := MeshInstance3D.new()
		holder.mesh = cut
		var bytes := built_glb(holder, true, scene.picture_side, scene.changes)
		holder.free()
		if bytes.is_empty():
			scene.problem_on(node, "%s can't be made into models for the game. Save it as glTF Binary (.glb) in smaller parts from the program that made it, and drag those in instead." % node.name)
			return made
		var name := _free_model_name("%s_%d_%d.glb" % [base, key.x, key.y], scene)
		scene.built[name] = bytes
		if not _take_model(node, String(node.name), name, "cut %d %s" % [node.get_instance_id(), key], bytes, scene):
			continue
		scene.model_grounds[name] = ground
		scene.model_crawls[name] = crawl
		scene.pieces.append({"model": name, "at": middle, "up": Vector3.UP, "turn": 0.0, "scale": 1.0})
		scene.sources["Piece"].append("Part %d of %s" % [made + 1, node.name])
		made += 1
	if left_out > 0:
		scene.warning_among(node, "cut away", "%d triangles of %s lie too far out, so they're left out. %s" % [left_out, node.name, TOO_FAR], "Parts of %%d meshes lie too far out, so they're left out. %s" % TOO_FAR, "%s: %d triangles" % [node.name, left_out])
	return made


## The arrays of a part of a mesh: only `corners` of `arrays`, numbered afresh, placed by `place` and then
## about `middle`, with their normals turned by `turn`.
static func _cut_arrays(arrays: Array, corners: PackedInt32Array, place: Transform3D, turn: Basis, middle: Vector3) -> Array:
	var renumbered := {}
	var order := PackedInt32Array()
	var indices := PackedInt32Array()
	for corner in corners:
		if not renumbered.has(corner):
			renumbered[corner] = order.size()
			order.append(corner)
		indices.append(renumbered[corner])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var points := PackedVector3Array()
	for corner in order:
		points.append(place * arrays[Mesh.ARRAY_VERTEX][corner] - middle)
	out[Mesh.ARRAY_VERTEX] = points
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals := PackedVector3Array()
		for corner in order:
			normals.append((turn * arrays[Mesh.ARRAY_NORMAL][corner]).normalized())
		out[Mesh.ARRAY_NORMAL] = normals
	for kind in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[kind] != null:
			var uvs := PackedVector2Array()
			for corner in order:
				uvs.append(arrays[kind][corner])
			out[kind] = uvs
	if arrays[Mesh.ARRAY_COLOR] != null:
		var colours := PackedColorArray()
		for corner in order:
			colours.append(arrays[Mesh.ARRAY_COLOR][corner])
		out[Mesh.ARRAY_COLOR] = colours
	out[Mesh.ARRAY_INDEX] = indices
	return out


## The .glbs the game takes made of `node`, as built_glb makes one, as {"glbs", "middle"}: one, or for a model
## with more than SPLIT_MATERIALS materials, several, each of at most SPLIT_MATERIALS of them,
## which together draw the whole model. A model whose meshes lie far from its node, as one imported with
## its place built into its mesh has, is made about its own middle, and "middle" says where that was under
## the node; it's nothing otherwise. "glbs" is empty if Godot can't make them.
static func split_glbs(node: Node3D, alone: bool, side := PICTURE_SIDE_DRAWN, changes := {}) -> Dictionary:
	var made: Array[PackedByteArray] = []
	var result := {"glbs": made, "middle": Vector3.ZERO}
	var copy := node.duplicate() as Node3D
	if copy == null:
		return result
	copy.transform = Transform3D.IDENTITY
	if alone:
		for child in copy.get_children():
			copy.remove_child(child)
			child.free()
	var middle := _far_middle(copy)
	result["middle"] = middle
	# Each group of surfaces sharing at most SPLIT_MATERIALS materials, as {"materials", "surfaces"},
	# each surface as [part, surface number].
	var groups: Array[Dictionary] = []
	for part in meshes_in(copy):
		for surface in part.mesh.get_surface_count():
			var material := _material_worn(part, surface)
			var id := material.get_instance_id() if material != null else 0
			var into: Dictionary = {}
			for group in groups:
				if group["materials"].has(id):
					into = group
					break
			if into.is_empty():
				for group in groups:
					if group["materials"].size() < SPLIT_MATERIALS:
						into = group
						break
			if into.is_empty():
				into = {"materials": {}, "surfaces": []}
				groups.append(into)
			into["materials"][id] = true
			into["surfaces"].append([part, surface])
	if groups.size() <= 1:
		copy.free()
		var whole := built_glb(node, alone, side, changes, middle)
		if not whole.is_empty():
			made.append(whole)
		return result
	for group in groups:
		var holder := Node3D.new()
		var by_part := {}
		for entry: Array in group["surfaces"]:
			var part: MeshInstance3D = entry[0]
			if not by_part.has(part):
				var piece := MeshInstance3D.new()
				piece.mesh = ArrayMesh.new()
				piece.transform = _place_under(part, copy).translated(-middle)
				holder.add_child(piece)
				by_part[part] = piece
			var mesh: ArrayMesh = by_part[part].mesh
			mesh.add_surface_from_arrays(part.mesh.surface_get_primitive_type(entry[1]), part.mesh.surface_get_arrays(entry[1]))
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material_worn(part, entry[1]))
		var bytes := built_glb(holder, false, side, changes)
		holder.free()
		if bytes.is_empty():
			copy.free()
			made.clear()
			return result
		made.append(bytes)
	copy.free()
	return result


## Where Export measures `found`, one of own_model_pieces, from when it checks it is within reach: its origin
## point, or for a model it builds itself whose meshes lie far from that, as split_glbs makes it, their middle.
static func measured_from(found: Dictionary) -> Vector3:
	var node: Node3D = found["node"]
	if found["made"] != "built":
		return node.global_position
	return node.global_transform * _far_middle(node, found.has("alone"))


## The middle of the box the meshes under `top` fill, if any of them reach further than CUT_REACH from
## `top`'s own middle; nothing otherwise. With `alone`, only `top`'s own mesh counts, as a mesh on its own
## is built without what hangs under it.
static func _far_middle(top: Node3D, alone := false) -> Vector3:
	var box := AABB()
	var any := false
	var parts := meshes_in(top)
	if alone and top is MeshInstance3D:
		parts = [top as MeshInstance3D]
	for part in parts:
		var placed := _place_under(part, top) * part.mesh.get_aabb()
		box = placed if not any else box.merge(placed)
		any = true
	if not any:
		return Vector3.ZERO
	var reach := 0.0
	for corner in 8:
		reach = maxf(reach, box.get_endpoint(corner).length())
	return box.get_center() if reach > CUT_REACH else Vector3.ZERO


## Where `part` is under `top`, which it hangs below, whether or not either is in the scene tree.
static func _place_under(part: Node3D, top: Node3D) -> Transform3D:
	if part == top:
		return Transform3D.IDENTITY
	var place := part.transform
	var above := part.get_parent()
	while above != null and above != top:
		if above is Node3D:
			place = (above as Node3D).transform * place
		above = above.get_parent()
	return place


## Reads `node` as a piece of the kit `kit`, or of the map's own model `model`. Only a `named` one goes in
## under the node's name for the map's script: a model split in parts is named on its first.
static func _read_piece(node: Node3D, kit: String, scene: Scene, model := "", named := true) -> void:
	if model.is_empty() and not Kit.has(kit):
		scene.problem_on(node, "%s uses %s, which the kit no longer has. Delete it." % [node.name, kit])
		return
	var place := node.global_transform
	# A model made about its own middle stands where that middle was.
	place.origin = place * scene.model_middles.get(model, Vector3.ZERO)
	var at := place.origin
	if not model.is_empty() and not scenery_kept(at):
		scene.warning_among(node, "far model", "%s stands at (%.0f, %.0f, %.0f), too far out, so it's left out. %s" % [node.name, at.x, at.y, at.z, TOO_FAR], "%%d of the map's own models stand too far out, so they're left out. %s" % TOO_FAR)
		return
	if not scenery_kept(at):
		scene.problem_among(node, "far", "%s is at (%.1f, %.1f, %.1f), too far out. %s" % [node.name, at.x, at.y, at.z, TOO_FAR], "%%d pieces are too far out. %s" % TOO_FAR)
		return
	var scale := place.basis.get_scale()
	var unequal := maxf(absf(scale.x - scale.y), absf(scale.y - scale.z))
	if unequal > STRETCH_SLACK * scale.x:
		scene.problem_among(node, "stretched", "%s is stretched %s. Scale all three sides the same." % [node.name, scale], "%d pieces are stretched. Scale all three sides of each the same.")
		return
	if place.basis.determinant() < 0.0:
		scene.problem_among(node, "mirrored", "%s is mirrored. The game can't draw a piece inside out: scale it by a positive number." % node.name, "%d pieces are mirrored. The game can't draw a piece inside out: scale each by a positive number.")
		return
	if scale.x < SCALES.x or scale.x > SCALES.y:
		scene.problem_among(node, "scaled", "%s is scaled by %s. It must be from %s to %s." % [node.name, scale.x, SCALES.x, SCALES.y], "%%d pieces are scaled outside %s to %s." % [SCALES.x, SCALES.y])
		return
	var rotation := place.basis.get_rotation_quaternion()
	var up := (rotation * Vector3.UP).normalized()
	var twist := Kit.arc_from_up(up).inverse() * rotation
	var turn := wrapf(2.0 * atan2(twist.y, twist.w), -PI, PI)
	var size := own_size_snapped(scale.x)
	var piece := {"kit": kit, "at": place.origin, "up": up, "turn": turn, "scale": size}
	if not model.is_empty():
		piece = {"model": model, "at": place.origin, "up": up, "turn": turn, "scale": size}
	var is_switch := node.is_in_group(SWITCH_GROUP)
	if named and (is_switch or node.is_in_group(SCRIPT_GROUP)):
		piece["name"] = String(node.name)
		piece["switch"] = is_switch
		piece["node"] = node
	var offers := OctopusPose.offered_by(node)
	if not offers.is_empty():
		piece["poses"] = offers
		piece["node"] = node
	scene.pieces.append(piece)
	scene.sources["Piece"].append(node)


## `size`, or exactly 1 if it is within NOT_RESIZED of it. A piece only turned comes out of Godot a hair off
## its own size, such as 0.99999994, and the game would take it as resized: it would copy its collider, and
## count toward MOST_SCALED_TRIANGLES (#236).
static func own_size_snapped(size: float) -> float:
	return 1.0 if absf(size - 1.0) < NOT_RESIZED else size


## What's wrong with a piece's name for the map's script, in plain words, or nothing: the game's
## name_problem. A trigger zone's message leaves out dots, which Godot never keeps in a node's name.
static func piece_name_problem(piece_name: String, letters := "lowercase letters, digits, dashes, underscores and dots") -> String:
	if piece_name.length() > MOST_PIECE_NAME_LETTERS:
		return "its name has %d letters, and the limit is %d" % [piece_name.length(), MOST_PIECE_NAME_LETTERS]
	for letter in piece_name:
		var plain := (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9") or letter in ["_", "-", "."]
		if not plain:
			return "names may only use %s" % letters
	if piece_name.contains("..") or piece_name.begins_with(".") or piece_name.ends_with("."):
		return "names can't start or end with a dot, or have two in a row"
	if piece_name.get_slice(".", 0) in WINDOWS_NAMES:
		return "that name is kept for Windows itself"
	return ""


static func _read_trigger(zone: Node3D, scene: Scene) -> void:
	scene.triggers.append({"name": String(zone.name), "at": zone.global_position, "reach": zone.reach_in_world(), "node": zone})
	scene.sources["Trigger zone"].append(zone)


## Each trigger zone is named as the game's checker wants, its own name, upright, inside the map and no
## bigger than it, as the game's check_triggers.
static func _check_triggers(root: SmartFellasMap, scene: Scene) -> void:
	if scene.triggers.size() > MOST_TRIGGERS:
		scene.problems.append("The map has %d trigger zones, past the %d the game takes." % [scene.triggers.size(), MOST_TRIGGERS])
		return
	var box := root.area_box()
	var widest := maxf(maxf(box.size.x, box.size.z) * 0.5, root.area_ceiling() - root.area_base()) * 2.0
	var seen := {}
	for trigger in scene.triggers:
		var zone: Node3D = trigger["node"]
		var why := piece_name_problem(trigger["name"], "lowercase letters, digits, dashes and underscores")
		if not why.is_empty():
			scene.problem_on(zone, "%s is a trigger zone, so the map's script finds it by its name, but %s. Rename it." % [zone.name, why])
		elif seen.has(trigger["name"]):
			scene.problem_on(zone, "%s is the name of two trigger zones. Rename one." % zone.name)
		seen[trigger["name"]] = true
		var at: Vector3 = trigger["at"]
		var reach: Vector3 = trigger["reach"]
		if not (at.is_finite() and reach.is_finite()):
			scene.problem_on(zone, "%s has a number that isn't a real number. Delete it and drop in another." % zone.name)
		elif zone.is_turned():
			scene.problem_on(zone, "%s is turned. The game's trigger zones stand upright, lined up with the map: set its rotation to 0 and size it with the dots on its sides." % zone.name)
		elif not in_the_map(root, at):
			scene.problem_on(zone, "%s has its middle at (%.1f, %.1f, %.1f), outside the map's play area. %s" % [zone.name, at.x, at.y, at.z, area_words(root)])
		elif reach.x <= 0.0 or reach.y <= 0.0 or reach.z <= 0.0 or reach.x > widest or reach.y > widest or reach.z > widest:
			scene.problem_on(zone, "%s reaches (%.1f, %.1f, %.1f) m from its middle. It must reach more than 0 and at most %s m each way, as wide as the map: set its scale back to 1 and size it with the dots on its sides." % [zone.name, reach.x, reach.y, reach.z, widest])


## Reads the map's own octopus poses, and checks them and what its pieces offer as the game's checker
## does: at most MOST_POSES, each a name of its own of at most MOST_NAME_LETTERS, every pose a piece offers
## one of them, and at most MOST_A_PIECE on a piece. A map with poses needs a play area box.
static func _check_poses(root: SmartFellasMap, scene: Scene) -> void:
	scene.poses = OctopusPose.nodes_in(root)
	scene.sources["Pose"] = scene.poses.duplicate()
	if scene.poses.is_empty() and not _offers_any(scene):
		return
	if root.play_area() == null:
		scene.problems.append("This map has octopus poses, and only a map with a play area box can have them. This older map has none: add a PlayArea from a new bare map (Paint panel), then export again.")
	if scene.poses.size() > OctopusPose.MOST_POSES:
		scene.problems.append("The map has %d octopus poses, past the %d the game takes." % [scene.poses.size(), OctopusPose.MOST_POSES])
		return
	var seen := {}
	for pose in scene.poses:
		var pose_name := String(pose.name)
		if pose_name.strip_edges().is_empty():
			scene.problem_on(pose, "An octopus pose has no name. Rename it in the Scene panel.")
		elif pose_name.length() > OctopusPose.MOST_NAME_LETTERS:
			scene.problem_on(pose, "The octopus pose %s has a name of %d letters, and the most is %d. Rename it in the Scene panel." % [pose_name, pose_name.length(), OctopusPose.MOST_NAME_LETTERS])
		elif seen.has(pose_name.to_lower()):
			scene.problem_on(pose, "Two octopus poses are called %s. Rename one in the Scene panel." % pose_name)
		seen[pose_name.to_lower()] = true
		var whole: Dictionary = pose.file_pose()
		var arms: Variant = whole["arms"]
		var plain: bool = arms is Array and arms.size() == OctopusPose.ARMS
		for key: String in POSE_WORDS:
			plain = plain and whole[key] in POSE_WORDS[key]
		if not plain:
			scene.problem_on(pose, "The octopus pose %s is broken. Select it and press Back to rest in the Poses panel, or delete it." % pose_name)
	var known := {}
	for pose in scene.poses:
		known[String(pose.name)] = true
	for piece in scene.pieces:
		if not piece.has("poses"):
			continue
		var node: Node = piece["node"]
		var offers: PackedStringArray = piece["poses"]
		if offers.size() > OctopusPose.MOST_A_PIECE:
			scene.problem_on(node, "%s offers %d octopus poses, and a piece offers at most %d. Untick some under Octopus poses in its Inspector." % [node.name, offers.size(), OctopusPose.MOST_A_PIECE])
		for pose_name in offers:
			if not known.has(pose_name):
				scene.problem_on(node, "%s offers the octopus pose %s, and the map has no shown pose called that. Untick it under Octopus poses in its Inspector, or show or add the pose." % [node.name, pose_name])


## The words a pose may say for how it sits and shows, as the game's Sits, Suckers, Eyes and Lit.
const POSE_WORDS := {
	"sits": ["Floor", "Wall", "Ceiling", "Buried"],
	"suckers": ["Hidden", "Shown"],
	"eyes": ["Covered", "Bare"],
	"lit": ["OwnShape", "AsGround"],
}


## Whether any piece offers one of the map's poses.
static func _offers_any(scene: Scene) -> bool:
	for piece in scene.pieces:
		if piece.has("poses"):
			return true
	return false


## `words` as a string in map.ron, with what would end it early made safe.
static func _quoted(words: String) -> String:
	return "\"%s\"" % words.replace("\\", "\\\\").replace("\"", "\\\"")


## A number of a pose as map.ron writes it, or nothing if the pose leaves it out or it isn't a number.
static func _pose_number(part: Dictionary, key: String) -> String:
	var value: Variant = part.get(key)
	return _number(float(value)) if value is float or value is int else ""


## A part of a pose, its arm or its body, as a map.ron tuple of the numbers it sets.
static func _pose_part(part: Dictionary) -> String:
	var keys := part.keys()
	keys.sort()
	var numbers: Array[String] = []
	for key: Variant in keys:
		var number := _pose_number(part, String(key))
		if not number.is_empty():
			numbers.append("%s: %s" % [key, number])
	return "(%s)" % ", ".join(numbers)


## The map's own poses as map.ron holds them, or nothing for a map with none.
static func _poses_text(scene: Scene) -> String:
	if scene.poses.is_empty():
		return ""
	var text := "    poses: [\n"
	for node in scene.poses:
		var pose: Dictionary = node.file_pose()
		var arms: Array[String] = []
		for arm: Variant in pose["arms"]:
			arms.append(_pose_part(arm if arm is Dictionary else {}))
		var water: Variant = pose.get("water", {})
		text += "        (version: %d, name: %s, sits: %s, suckers: %s, eyes: %s, lit: %s, body: %s, arms: (%s), water: %s),\n" % [
			OctopusPose.VERSION, _quoted(String(node.name)), pose["sits"], pose["suckers"], pose["eyes"], pose["lit"],
			_pose_part(pose["body"] if pose["body"] is Dictionary else {}), ", ".join(arms),
			_pose_part(water if water is Dictionary else {}),
		]
	return text + "    ],\n"


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


## Whether `node` is a scattered mesh Export makes into copies: a MultiMeshInstance3D of a mesh, placed in 3D.
static func _is_scatter(node: Node) -> bool:
	if not node is MultiMeshInstance3D:
		return false
	var many: MultiMesh = (node as MultiMeshInstance3D).multimesh
	return many != null and many.mesh != null and many.transform_format == MultiMesh.TRANSFORM_3D


## Every scattered mesh under `root` Export makes into copies, wherever left_out would look for one.
static func scatters(root: Node) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	_collect_scatters(root, found)
	return found


static func _collect_scatters(node: Node, found: Array[MultiMeshInstance3D]) -> void:
	for child in node.get_children():
		if child is Node3D and not child.visible:
			continue
		var path: String = child.scene_file_path
		if path.begins_with(KIT_FOLDER) or path.get_extension().to_lower() == "glb":
			continue
		if not path.is_empty() and not _holds_kit_pieces(child) and meshes_in(child).is_empty():
			continue
		if _is_scatter(child):
			found.append(child)
		_collect_scatters(child, found)


## How many of `many`'s copies show, and so become pieces.
static func copies_in(many: MultiMesh) -> int:
	return many.instance_count if many.visible_instance_count < 0 else mini(many.visible_instance_count, many.instance_count)


## Makes each copy of each scattered mesh (MultiMeshInstance3D) a piece of a model of that mesh, as if each
## had been placed by hand. Copies that are stretched one way more than another, or tinted by their
## material, get a model of their own for each stretch and shade, so the game draws them as Godot does.
static func _read_scatters(root: SmartFellasMap, scene: Scene) -> void:
	for scatter in scatters(root):
		var many := scatter.multimesh
		var count := copies_in(many)
		if count == 0:
			continue
		var buffer := many.buffer
		if buffer.size() < count * _copy_stride(many):
			scene.problem_on(scatter, "%s's copies can't be read. Clear it and scatter it again." % scatter.name)
			continue
		var places: Array[Transform3D] = []
		var sizes := PackedFloat32Array()
		for index in count:
			var place: Transform3D = scatter.global_transform * copy_place(many, buffer, index)
			places.append(place)
			sizes.append(absf(place.basis.get_scale().x))
		var shades := _shades_of(scatter, count)
		# Copies too small or too big for a piece share a model made to their middle size.
		var base := 1.0
		var smallest := Array(sizes).min() as float
		var biggest := Array(sizes).max() as float
		if smallest < SCALES.x or biggest > SCALES.y:
			var logs := 0.0
			for size in sizes:
				logs += log(maxf(size, 0.000001))
			base = exp(logs / count)
		var outside := 0
		var off_scale := 0
		var taken := 0
		for index in count:
			var place := places[index]
			var signed := place.basis.get_scale()
			var size := maxf(absf(signed.x), maxf(absf(signed.y), absf(signed.z)))
			if minf(absf(signed.x), minf(absf(signed.y), absf(signed.z))) < FLAT_AS_NOTHING:
				off_scale += 1
				continue
			var stretch := (signed / size).snapped(Vector3.ONE * STRETCH_STEP)
			if stretch.is_equal_approx(Vector3.ONE):
				stretch = Vector3.ONE
			var override := scatter.material_override.get_instance_id() if scatter.material_override != null else 0
			var key := "%d %d %s %s" % [many.mesh.get_instance_id(), override, stretch * base, shades[index]]
			if not scene.scatter_models.has(key):
				scene.scatter_models[key] = _scatter_model(scatter, stretch * base, shades[index], scene)
			var name: String = scene.scatter_models[key]
			if name.is_empty():
				continue
			var turn := Basis(place.basis.x / signed.x, place.basis.y / signed.y, place.basis.z / signed.z).orthonormalized()
			var piece := _scatter_piece(Transform3D(turn, place.origin), size / base, name)
			if piece.is_empty():
				outside += 1
				continue
			if piece.has("off_scale"):
				off_scale += 1
				continue
			scene.pieces.append(piece)
			scene.sources["Piece"].append("Copy %d of %s" % [index + 1, scatter.name])
			taken += 1
		if outside > 0:
			scene.warning_among(scatter, "far copies", "%d copies in %s stand too far out, so they're left out. %s" % [outside, scatter.name, TOO_FAR], "Copies in %%d scattered meshes stand too far out, so they're left out. %s" % TOO_FAR, "%s: %d copies" % [scatter.name, outside])
		if off_scale > 0:
			scene.problem_on(scatter, "%d copies in %s are sized too far apart for the game: it takes a scattered mesh's copies up to %d times bigger or smaller than the middle one. Even their sizes out." % [off_scale, scatter.name, roundi(SCALES.y)])
		if taken > 0:
			scene.changes["scatters"] += 1
			scene.changes["copies"] += taken


## How many numbers each copy of a scattered mesh takes in its buffer: its place, then its colour and its
## custom data if it has them.
static func _copy_stride(many: MultiMesh) -> int:
	return 12 + (4 if many.use_colors else 0) + (4 if many.use_custom_data else 0)


## Where copy `index` of `many` is, under its scatter, read from its buffer, which holds each copy's place
## row by row. The buffer is what Godot saves, and holds the copies even with no graphics card to draw them.
static func copy_place(many: MultiMesh, buffer: PackedFloat32Array, index: int) -> Transform3D:
	var at := index * _copy_stride(many)
	var columns := Basis(
		Vector3(buffer[at], buffer[at + 4], buffer[at + 8]),
		Vector3(buffer[at + 1], buffer[at + 5], buffer[at + 9]),
		Vector3(buffer[at + 2], buffer[at + 6], buffer[at + 10]),
	)
	return Transform3D(columns, Vector3(buffer[at + 3], buffer[at + 7], buffer[at + 11]))


## A piece of `model` at `place`, which holds no scale, scaled by `size`: {} if it stands too far out,
## or {"off_scale": true} if `size` is more than a piece can be scaled.
static func _scatter_piece(place: Transform3D, size: float, model: String) -> Dictionary:
	var at := place.origin
	if not scenery_kept(at):
		return {}
	if size < SCALES.x or size > SCALES.y:
		return {"off_scale": true}
	var rotation := place.basis.get_rotation_quaternion()
	var up := (rotation * Vector3.UP).normalized()
	var twist := Kit.arc_from_up(up).inverse() * rotation
	var turn := wrapf(2.0 * atan2(twist.y, twist.w), -PI, PI)
	return {"model": model, "at": at, "up": up, "turn": turn, "scale": own_size_snapped(size)}


## The shade each copy of `scatter` is tinted, as words, or "" for each if its material doesn't show the
## copies' colours: Godot only tints a copy by its colour if the material uses vertex colour as albedo. At
## most MOST_SHADES shades are kept, the commonest, and every other copy wears the nearest of them.
static func _shades_of(scatter: MultiMeshInstance3D, count: int) -> PackedStringArray:
	var shades := PackedStringArray()
	shades.resize(count)
	var many := scatter.multimesh
	if not many.use_colors or not _shows_copy_colours(scatter):
		return shades
	var colours: Array[Color] = []
	var counts := {}
	var buffer := many.buffer
	for index in count:
		var at := index * _copy_stride(many) + 12
		var colour := Color(buffer[at], buffer[at + 1], buffer[at + 2])
		colour = Color(snappedf(colour.r, SHADE_STEP), snappedf(colour.g, SHADE_STEP), snappedf(colour.b, SHADE_STEP), 1.0)
		colours.append(colour)
		counts[colour] = counts.get(colour, 0) + 1
	var kept: Array = counts.keys()
	kept.sort_custom(func(one: Color, other: Color) -> bool: return counts[one] > counts[other] or (counts[one] == counts[other] and one.to_rgba32() < other.to_rgba32()))
	kept = kept.slice(0, MOST_SHADES)
	for index in count:
		var nearest: Color = kept[0]
		for shade: Color in kept:
			if _colour_gap(shade, colours[index]) < _colour_gap(nearest, colours[index]):
				nearest = shade
		shades[index] = nearest.to_html(false)
	return shades


static func _colour_gap(one: Color, other: Color) -> float:
	return Vector3(one.r - other.r, one.g - other.g, one.b - other.b).length_squared()


## Whether a scattered mesh's material shows each copy's colour.
static func _shows_copy_colours(scatter: MultiMeshInstance3D) -> bool:
	var mesh := scatter.multimesh.mesh
	for surface in mesh.get_surface_count():
		var material: Material = scatter.material_override if scatter.material_override != null else mesh.surface_get_material(surface)
		if material is BaseMaterial3D and (material as BaseMaterial3D).vertex_color_use_as_albedo:
			return true
	return false


## The map's own model of `scatter`'s mesh, stretched by `stretch` and tinted `shade` (as HTML, or "" for
## none), made, checked and named: its name, or "" if it can't be, which is said on `scatter`.
static func _scatter_model(scatter: MultiMeshInstance3D, stretch: Vector3, shade: String, scene: Scene) -> String:
	var holder := Node3D.new()
	var part := MeshInstance3D.new()
	part.mesh = scatter.multimesh.mesh
	part.scale = stretch
	holder.add_child(part)
	var mesh := part.mesh
	for surface in mesh.get_surface_count():
		var material: Material = scatter.material_override if scatter.material_override != null else mesh.surface_get_material(surface)
		if not shade.is_empty() and material is BaseMaterial3D:
			var tinted: BaseMaterial3D = material.duplicate()
			tinted.albedo_color *= Color.html(shade)
			tinted.vertex_color_use_as_albedo = false
			material = tinted
		if material != null:
			part.set_surface_override_material(surface, material)
	var bytes := built_glb(holder, false, scene.picture_side, scene.changes)
	holder.free()
	if bytes.is_empty():
		scene.problem_on(scatter, "%s's mesh can't be made into a model for the game. Save it as glTF Binary (.glb) from the program that made it, and scatter that instead." % scatter.name)
		return ""
	var name := _free_model_name(model_name(String(scatter.name)), scene)
	scene.built[name] = bytes
	if not _take_model(scatter, String(scatter.name), name, "scattered %d %s %s" % [scatter.get_instance_id(), stretch, shade], bytes, scene):
		return ""
	return name


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
		for first in range(0, values.size(), Kit.STRIDE):
			if values[first + 7] < SCALES.x or values[first + 7] > SCALES.y:
				wrong_size += 1
			if not scenery_kept(Vector3(values[first], values[first + 1], values[first + 2])):
				too_far += 1
		if too_far > 0:
			scene.problems.append("%d painted pieces of %s are too far out. %s Or hold Shift and brush over them." % [too_far, Kit.plain_name(kit), TOO_FAR])
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


static func _trigger_lines(scene: Scene) -> String:
	var lines := ""
	for trigger in scene.triggers:
		lines += "\n        (name: \"%s\", at: %s, reach: %s)," % [trigger["name"], _xyz(trigger["at"]), _xyz(trigger["reach"])]
	return lines + ("\n    " if not lines.is_empty() else "")


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
		if piece.has("poses"):
			var names: Array[String] = []
			for pose_name: String in piece["poses"]:
				names.append(_quoted(pose_name))
			named += ", poses: [%s]" % ", ".join(names)
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
	var base := root.area_base()
	var up := root.area_ceiling() - base
	if root.seabed_side == 0 and root.has_seabed:
		return _number(base + up * 0.6)
	var heights := PackedStringArray()
	for share in [0.6, 0.75, 0.85, 0.45]:
		heights.append(_number(base + up * share))
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
	# A grid round the map's middle says nothing of where it is, so its file reads as it did before (#264).
	var middle := ""
	if root.seabed_middle != Vector2.ZERO:
		middle = " middle: (%s, %s)," % [_number(root.seabed_middle.x), _number(root.seabed_middle.y)]
	return "Sculpted((reach: %s,%s side: %d, heights: [%s], rock_cells: [%s]))" % [_number(root.seabed_reach), middle, root.seabed_side, ", ".join(heights), ", ".join(rock)]


## The names in the package of the map's own models some piece is made of, in order. A model whose only
## piece was left out, as too far out, has none, and the game refuses a choice made for it.
static func _placed_model_names(scene: Scene) -> Array:
	var placed := {}
	for piece in scene.pieces:
		if piece.has("model"):
			placed[piece["model"]] = true
	var names: Array = placed.keys()
	names.sort()
	return names


## Which of the map's own models are sand or silt, by their names in the package, or nothing if none is, as
## the game leaves it out.
static func _soft_models_text(scene: Scene) -> String:
	var names := _placed_model_names(scene)
	var entries := ""
	for name: String in names:
		var ground: String = scene.model_grounds.get(name, "rock")
		if ground == "sand" or ground == "silt":
			entries += "(model: \"%s\", ground: %s), " % [name, ground.capitalize()]
	if entries.is_empty():
		return ""
	return "    soft_models: [%s],\n" % entries


## Which of the map's own models octopuses always crawl on or never do, by their names in the package, or
## nothing if every one is judged by its size, as the game leaves it out.
static func _crawl_models_text(scene: Scene) -> String:
	var names := _placed_model_names(scene)
	var entries := ""
	for name: String in names:
		var crawl: String = scene.model_crawls.get(name, "size")
		if crawl == "always" or crawl == "never":
			entries += "(model: \"%s\", crawl: %s), " % [name, crawl.capitalize()]
	if entries.is_empty():
		return ""
	return "    crawl_models: [%s],\n" % entries


## What Export says of a map with no play area box that chose whether octopuses crawl on its own models.
const NEEDS_A_BOX_TO_CRAWL := "You chose whether octopuses crawl on some of your own models, and only a map with a play area box can say so. Press Fit to map in the Map panel to make one."


## Only a map with a play area box can say whether octopuses crawl on its own models: the format that
## carries it has one.
static func _check_crawls(root: SmartFellasMap, scene: Scene) -> void:
	if root.play_area() == null and not _crawl_models_text(scene).is_empty():
		scene.problems.append(NEEDS_A_BOX_TO_CRAWL)


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
	var soft := _soft_models_text(scene)
	if not root.has_seabed or not soft.is_empty():
		format = NO_SEABED_FORMAT
	if root.play_area() != null:
		format = BOX_FORMAT
	# A grid round the map's middle keeps the format older games read (#264).
	if root.play_area() != null and root.has_seabed and root.seabed_side != 0 and root.seabed_middle != Vector2.ZERO:
		format = GRID_MIDDLE_FORMAT
	if not scene.poses.is_empty() or _offers_any(scene):
		format = POSES_FORMAT
	# Only a map that says whether octopuses crawl on its models needs the newer format.
	var crawls := _crawl_models_text(scene)
	if root.play_area() != null and not crawls.is_empty():
		format = CRAWL_FORMAT
	var text := "(\n    format: %d,\n    name: \"%s\",\n" % [format, root.map_name]
	if root.play_area() != null:
		var area := root.area_box()
		text += "    area: (min: %s, max: %s),\n" % [_xyz(area.position), _xyz(area.end)]
	else:
		text += "    size: (half_width: %s, ceiling: %s),\n" % [_number(root.half_width), _number(root.ceiling)]
	text += "    seabed: %s,\n" % _seabed_text(root, scene)
	text += "    pieces: [\n%s    ],\n" % _piece_lines(scene.pieces)
	text += "    spawns: (\n        octopus: [\n%s        ],\n        diver: [\n%s        ],\n    ),\n" % [
		_spawn_lines(scene.octopus_spawns), _spawn_lines(scene.diver_spawns)
	]
	text += "    food: (\n        growing: (1, %d),\n        patches: [\n%s        ],\n        spots: [\n%s        ],\n    ),\n" % [
		most_growing, food["patches"], food["spots"]
	]
	text += "    fish: [%s],\n    triggers: [%s],\n    hunters: %s,\n    clownfish: %s,\n" % [_fish_lines(scene), _trigger_lines(scene), _switch(root.hunters), _switch(root.clownfish)]
	text += "    players: (fewest: %d, most: %d, max_divers: %d, max_octopuses: %d),\n" % [root.fewest_players, divers + octopuses, divers, octopuses]
	text += "    far_side: 0.0,\n"
	var box := root.area_box()
	var widest: float = minf(box.size.x, box.size.z) * 0.5 * 0.6
	text += "    shark: (widest: %s, narrowest: %s, points: 8, heights: [%s], room: 1.7),\n" % [
		_number(widest), _number(widest * 0.5), _shark_heights(root)
	]
	var survey := maxf(maxf(box.size.x, box.size.z) / 32.0, 2.0)
	text += "    rock_survey_step: %s,\n    small_fish_share: 0.35,\n" % _number(survey)
	text += WaterLook.section_text(root.water_depth, root.water_overrides)
	text += _life_text(root)
	text += _deep_fauna_text(root, scene)
	text += _anglers_text(root, scene)
	text += _lantern_text(scene)
	text += _haunts_text(scene)
	text += soft
	text += _poses_text(scene)
	text += crawls
	text += ")\n"
	return text
