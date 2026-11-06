@tool
extends RefCounted
## Brush recipes: a mix of pieces and how they grow, under a name. The add-on ships a few, and a map
## maker's own live in the project, as plain JSON files that can be passed around.

const Kit := preload("kit.gd")

const SHIPPED := "res://addons/smart_fellas_maps/recipes/"
const OWN := "res://brush_recipes/"

## A recipe's settings, with what a new brush starts on. Sizes are in metres, and angles in degrees.
const DEFAULTS := {
	"name": "New brush",
	# Each entry: {"kit": a piece's name, "weight": how often it comes up against the others}.
	"mix": [],
	# How wide the brush reaches from the middle, and how many pieces grow in a square metre of a clump.
	"wide": 3.0,
	"thick": 1.5,
	# Random turn about the piece's up, either way, and random size.
	"turn": 180.0,
	"size_low": 0.8,
	"size_high": 1.3,
	# A random lean off true, and how far a piece follows the slope it stands on: 0 is straight up, as kelp
	# grows, and 1 is square to the surface, as a limpet sits.
	"wobble": 5.0,
	"follow": 1.0,
	# Where it grows.
	"on_sand": true,
	"on_rock": true,
	"slope_low": 0.0,
	"slope_high": 50.0,
	"height_low": 0.0,
	"height_high": 100.0,
	# How strongly pieces gather in clumps, from 0 (evenly everywhere) to 1, and how far apart clumps sit.
	"clumps": 0.7,
	"clump_size": 3.0,
	# A different number gives a different pattern of clumps.
	"seed": 1,
}


## The lowest and highest each number may be. The panel's sliders have the same ends.
const RANGES := {
	"wide": Vector2(0.25, 25.0),
	"thick": Vector2(0.05, 20.0),
	"turn": Vector2(0.0, 180.0),
	"size_low": Vector2(0.1, 10.0),
	"size_high": Vector2(0.1, 10.0),
	"wobble": Vector2(0.0, 45.0),
	"follow": Vector2(0.0, 1.0),
	"slope_low": Vector2(0.0, 180.0),
	"slope_high": Vector2(0.0, 180.0),
	"height_low": Vector2(0.0, 100.0),
	"height_high": Vector2(0.0, 100.0),
	"clumps": Vector2(0.0, 1.0),
	"clump_size": Vector2(1.0, 25.0),
}
const MOST_WEIGHT := 10.0
const SEEDS := Vector2i(1, 99999)
## Each low limit, and the high limit it can't pass.
const LOW_AND_HIGH := [["size_low", "size_high"], ["slope_low", "slope_high"], ["height_low", "height_high"]]


## A full recipe from however much of one `given` has. Anything of the wrong type goes back to its
## default, every number comes into its range, and pieces the kit doesn't have are left out, so that a
## hand-edited file can't paint what the game would refuse, or trip up the panel.
static func completed(given: Dictionary) -> Dictionary:
	var recipe: Dictionary = DEFAULTS.duplicate(true)
	if given.get("name") is String and not given["name"].strip_edges().is_empty():
		recipe["name"] = given["name"].strip_edges()
	for key: String in RANGES:
		var value: Variant = given.get(key)
		if value is float or value is int:
			var limits: Vector2 = RANGES[key]
			recipe[key] = clampf(float(value), limits.x, limits.y)
	for key in ["on_sand", "on_rock"]:
		if given.get(key) is bool:
			recipe[key] = given[key]
	var seed_given: Variant = given.get("seed")
	if seed_given is float or seed_given is int:
		recipe["seed"] = clampi(int(seed_given), SEEDS.x, SEEDS.y)
	for pair in LOW_AND_HIGH:
		recipe[pair[0]] = minf(recipe[pair[0]], recipe[pair[1]])
	recipe["mix"] = _completed_mix(given.get("mix"))
	return recipe


static func _completed_mix(given: Variant) -> Array:
	var mix: Array = []
	if not given is Array:
		return mix
	for entry in given:
		if not entry is Dictionary or not entry.get("kit") is String or not Kit.has(entry["kit"]):
			continue
		var weight: Variant = entry.get("weight", 1.0)
		var number: float = clampf(float(weight), 0.0, MOST_WEIGHT) if weight is float or weight is int else 1.0
		mix.append({"kit": entry["kit"], "weight": number})
	return mix


## Every recipe by name, the add-on's first, sorted. A map maker's own replaces a shipped one of the
## same name, so that a shipped one can be tuned and kept.
static func all() -> Dictionary:
	var found := {}
	for folder in [SHIPPED, OWN]:
		var files := DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray()
		for file in files:
			if file.ends_with(".json"):
				var recipe := read(folder + file)
				if not recipe.is_empty():
					found[recipe["name"]] = recipe
	return found


## The recipe in this file, or nothing if it isn't one, which says so once in Godot's output.
static func read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("%s isn't a brush recipe, so it was left out." % path)
		return {}
	return completed(parsed)


## Whether `name` is one of the add-on's.
static func is_shipped(name: String) -> bool:
	return _name_in(SHIPPED + file_name(name)) == name


## Whether `name` is a map maker's own, saved in the project, which can be deleted. It may have a shipped
## one's name, and replace it.
static func is_own(name: String) -> bool:
	return _name_in(OWN + file_name(name)) == name


## The name of a map maker's recipe that saving under `name` would write over, if it's a different name
## that makes the same file, or "".
static func clash(name: String) -> String:
	var there := _name_in(OWN + file_name(name))
	return there if not there.is_empty() and there != name else ""


## The name of the recipe in this file, or "" if there's none.
static func _name_in(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return completed(parsed)["name"] if parsed is Dictionary else ""


## Saves `recipe` under its name, in the project. Gives back what went wrong in plain words, or "".
static func save(recipe: Dictionary) -> String:
	var other := clash(recipe["name"])
	if not other.is_empty():
		return "%s would save over your recipe %s, as both make the file %s. Choose another name." % [recipe["name"], other, file_name(recipe["name"])]
	var made := DirAccess.make_dir_recursive_absolute(OWN)
	if made != OK:
		return "Can't make the folder %s: %s." % [OWN, error_string(made)]
	var path := OWN + file_name(recipe["name"])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Can't write %s: %s." % [path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(recipe, "\t", false))
	file.close()
	return ""


## Removes a map maker's own recipe.
static func remove(name: String) -> void:
	DirAccess.remove_absolute(OWN + file_name(name))


## A file name for a recipe's name: lowercase letters, digits and underscores.
static func file_name(name: String) -> String:
	var plain := ""
	for letter in name.to_lower().strip_edges():
		plain += letter if (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9") else "_"
	return plain + ".json"
