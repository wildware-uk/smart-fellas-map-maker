@tool
extends RefCounted
## The kinds of marker a map can hold, which a marker's name says, and how each is dropped in.

const Kit := preload("kit.gd")
const WildlifeMarker := preload("wildlife_marker.gd")

## For each kind: the start of its markers' names, what the buttons call it, its shape's colour, how far
## above the surface it's dropped, whether it lies square to the surface, and, if dragging the mouse
## scatters them, how far apart in metres.
const KINDS := {
	"spawn_octopus": {"prefix": "spawn_octopus_", "words": "Octopus spawn", "colour": Color(0.95, 0.45, 0.85), "lift": 1.0, "on_surface": false},
	"spawn_diver": {"prefix": "spawn_diver_", "words": "Diver spawn", "colour": Color(1.0, 0.75, 0.2), "lift": 1.5, "on_surface": false},
	"food_patch": {"prefix": "food_patch_", "words": "Food patch", "colour": Color(0.45, 0.95, 0.4), "lift": 0.0, "on_surface": true},
	"fish_lionfish": {"prefix": "fish_lionfish_", "words": "Lionfish", "colour": Color(1.0, 0.35, 0.3), "lift": 1.0, "on_surface": false, "paint_apart": 4.0},
	"fish_flounder": {"prefix": "fish_flounder_", "words": "Flounder", "colour": Color(0.85, 0.7, 0.45), "lift": 0.05, "on_surface": false, "paint_apart": 4.0},
	"angler": {"prefix": "angler_", "words": "Anglerfish spot", "colour": Color(0.7, 0.9, 1.0), "lift": 0.6, "on_surface": false},
	"jellies": {"prefix": "jellies_", "words": "Jellyfish group", "colour": Color(0.6, 0.6, 1.0), "lift": 5.0, "on_surface": false, "script": true},
	"lantern": {"prefix": "lantern_", "words": "Lantern school", "colour": Color(0.5, 1.0, 0.9), "lift": 4.0, "on_surface": false, "script": true},
	"goblin_route": {"prefix": "goblin_route_", "words": "Goblin route point", "colour": Color(1.0, 0.55, 0.8), "lift": 6.0, "on_surface": false},
	"wrasse": {"prefix": "wrasse_", "words": "Wrasse spot", "colour": Color(0.35, 0.6, 1.0), "lift": 1.5, "on_surface": false},
	"stingray": {"prefix": "stingray_", "words": "Stingray stop", "colour": Color(0.75, 0.75, 0.6), "lift": 0.05, "on_surface": false},
	"eel_hole": {"prefix": "eel_hole_", "words": "Eel hole", "colour": Color(0.55, 0.85, 0.3), "lift": 0.5, "on_surface": false},
	"groper_hole": {"prefix": "groper_hole_", "words": "Groper hole", "colour": Color(0.75, 0.5, 0.3), "lift": 1.0, "on_surface": false},
}


## Marks a marker the Populate button added, and says where it put it.
const OWN_MARK := &"populate_put_it_here"
## How far a marker may have moved and still count as where Populate put it, in metres.
const STILL_THERE := 0.001


## The kind of marker with this name, or "".
static func kind_of(marker_name: String) -> String:
	for kind: String in KINDS:
		if marker_name.begins_with(KINDS[kind]["prefix"]):
			return kind
	return ""


## The markers of this kind directly or further under `map`.
static func markers_of(map: Node, kind: String) -> Array[Node]:
	var found: Array[Node] = []
	for marker in map.find_children("%s*" % KINDS[kind]["prefix"], "Marker3D", true, false):
		found.append(marker)
	return found


## A new marker of this kind for a surface at `at`, facing `normal`, not yet in the map: the next free
## number, facing the middle of the map if it's a spawn point. It's lifted off the surface the way the
## surface faces, so one dropped on a wall or under a ledge stays out of the rock, and only a kind that lies
## square to the surface leans with it: the rest stand upright, as the game holds them.
static func new_marker(map: Node3D, kind: String, at: Vector3, normal: Vector3) -> Marker3D:
	var info: Dictionary = KINDS[kind]
	var marker: Marker3D = WildlifeMarker.new() if info.get("script", false) else Marker3D.new()
	marker.name = "%s%d" % [info["prefix"], _next_number(map, info["prefix"])]
	var ceiling: float = map.call("area_ceiling")
	var lift: float = info["lift"]
	var away := normal.normalized() if normal.is_finite() and not normal.is_zero_approx() else Vector3.UP
	var spot := at + away * lift
	spot.y = minf(spot.y, ceiling)
	var turn := 0.0
	if kind.begins_with("spawn") and Vector2(spot.x, spot.z).length() > 0.01:
		turn = atan2(spot.x, spot.z)
	var place := Kit.place_of(spot, normal if info["on_surface"] else Vector3.UP, turn, 1.0)
	marker.transform = map.global_transform.affine_inverse() * place
	return marker


static func _next_number(map: Node, prefix: String) -> int:
	var highest := 0
	for marker in map.find_children("%s*" % prefix, "Marker3D", true, false):
		highest = maxi(highest, String(marker.name).trim_prefix(prefix).to_int())
	return highest + 1


## The number at the end of a marker's name, or 0.
static func number_of(marker_name: String, kind: String) -> int:
	return marker_name.trim_prefix(KINDS[kind]["prefix"]).to_int()
