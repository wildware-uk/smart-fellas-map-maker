@tool
extends Node3D
## A zone for Populate: a round patch of the map, dropped from the Map panel and dragged in the 3D view,
## that changes what Populate puts there. A coral garden grows coral, anemones and rocks thick; open sand
## keeps to sand plants and shells, with no rocks; a kelp forest grows kelp thick; bare grows nothing; and
## keep clear has nothing at all, not even food, fish or spawn points. Only the editor and Populate read
## zones: Export and the game never see them.

enum Kind { CORAL, SAND, KELP, BARE, CLEAR }
## How a zone's disc is drawn besides its colour: plain, striped across like tape round a no-go patch, or
## nearly empty inside a thick dashed rim. Kinds that look alike in colour over the water are told apart by it.
enum Look { PLAIN, STRIPED, DASHED }

## For each kind: what the Map panel calls it, a line on what it does, the colour it's drawn in and its look,
## how many times thicker each of Populate's layers grows in it, by recipe, and which layers grow none
## there. A kind keeps markers out if "markers" is false.
const KINDS := {
	Kind.CORAL: {
		"words": "Coral garden",
		"tip": "Coral, anemones and rocks grow thick here.",
		"colour": Color(1.0, 0.45, 0.85),
		"look": Look.PLAIN,
		"more": {"Coral on rock": 3.0, "Coral on walls": 3.0, "Anemone patch": 3.0, "Rock rubble": 2.0},
		"none": ["Kelp bed"],
		"markers": true,
	},
	Kind.SAND: {
		"words": "Open sand",
		"tip": "Only sand plants and shells, with no rocks, coral or kelp: open ground to cross and bury in.",
		"colour": Color(1.0, 0.85, 0.3),
		"look": Look.PLAIN,
		"more": {"Sand garden": 2.0},
		"none": ["Rock rubble", "Coral on rock", "Coral on walls", "Kelp bed", "Anemone patch"],
		"markers": true,
	},
	Kind.KELP: {
		"words": "Kelp forest",
		"tip": "Kelp grows thick here.",
		"colour": Color(0.35, 0.85, 0.35),
		"look": Look.PLAIN,
		"more": {"Kelp bed": 4.0},
		"none": [],
		"markers": true,
	},
	Kind.BARE: {
		"words": "Bare",
		"tip": "Nothing grows here. Food, fish and spawn points may still go here.",
		"colour": Color(0.95, 0.95, 0.95),
		"look": Look.DASHED,
		"more": {},
		"none": ["*"],
		"markers": true,
	},
	Kind.CLEAR: {
		"words": "Keep clear",
		"tip": "Nothing at all goes here: no scenery, food, fish or spawn points.",
		"colour": Color(1.0, 0.12, 0.12),
		"look": Look.STRIPED,
		"more": {},
		"none": ["*"],
		"markers": false,
	},
}
## The least and most a zone may reach from its middle to its rim, in metres, and how far a new one reaches.
const RADII := Vector2(2.0, 100.0)
const NEW_RADIUS := 10.0
## The group every zone in the editor is in, so that it can be found without searching the whole map.
const GROUP := "smart_fellas_populate_zones"
## Where a dragged rim snaps to, in metres.
const SNAP := 0.5

## What the Map panel asks to place to drop a zone of a kind, as the marker tool takes it: this, then the
## kind's number.
const PLACING := "zone "

@export var kind := Kind.CORAL:
	set(value):
		kind = value
		update_gizmos()
@export_range(2.0, 100.0, 0.5, "suffix:m") var radius := NEW_RADIUS:
	set(value):
		radius = clampf(value, RADII.x, RADII.y)
		update_gizmos()


func _enter_tree() -> void:
	add_to_group(GROUP)


## How far it reaches from its middle to its rim in the world: its radius, times the most it's scaled
## across, as Godot's own scale tool may have stretched it.
func reach() -> float:
	var scale_now := global_basis.get_scale()
	return radius * maxf(absf(scale_now.x), absf(scale_now.z))


## The zone nodes in `map`, shown ones only.
static func nodes_in(map: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not map.is_inside_tree():
		return found
	for node in map.get_tree().get_nodes_in_group(GROUP):
		if map.is_ancestor_of(node) and (node as Node3D).is_visible_in_tree():
			found.append(node)
	return found


## The zones in `map`, shown ones only, as {"kind", "at", "radius"}, "at" being where its middle is seen
## from above, in the map's own space.
static func zones_in(map: Node3D) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var into_map := map.global_transform.affine_inverse()
	for node in nodes_in(map):
		var at: Vector3 = into_map * node.global_position
		found.append({"kind": node.kind, "at": Vector2(at.x, at.z), "radius": node.reach()})
	return found


## The radius that puts `zone`'s rim at `at`, seen from above, snapped and kept within RADII.
static func radius_toward(zone: Node3D, at: Vector3) -> float:
	var middle := zone.global_position
	var scale_now := zone.global_basis.get_scale()
	var across := maxf(maxf(absf(scale_now.x), absf(scale_now.z)), 0.001)
	return clampf(snappedf(Vector2(at.x - middle.x, at.z - middle.z).length() / across, SNAP), RADII.x, RADII.y)


## Makes a zone's new size, from `before`, one step of `history`, a plain UndoRedo or the editor's.
static func sized(zone: Node3D, before: float, history: Object) -> void:
	history.create_action("Size %s" % zone.name)
	history.add_do_property(zone, "radius", zone.radius)
	history.add_undo_property(zone, "radius", before)
	history.commit_action(false)


## What to ask the marker tool to place, to drop a zone of `kind`.
static func placing(kind: Kind) -> String:
	return PLACING + str(kind)


## The kind of zone `placing` drops, or -1 if it drops a marker.
static func kind_placed(placing: String) -> int:
	return placing.trim_prefix(PLACING).to_int() if placing.begins_with(PLACING) else -1


## A new zone of `kind` at `at`, in the map's own space, named for its kind, not yet in the map.
static func new_zone(map: Node3D, kind: Kind, at: Vector3) -> Node3D:
	var zone: Node3D = load("res://addons/smart_fellas_maps/populate_zone.gd").new()
	zone.kind = kind
	zone.name = (KINDS[kind]["words"] as String).to_pascal_case()
	zone.position = at
	return zone


## Whether `layer`, a recipe's name, grows nothing at (x, z) for the zones there.
static func keeps_out(zones: Array[Dictionary], layer: String, x: float, z: float) -> bool:
	for zone in zones:
		var none: Array = KINDS[zone["kind"]]["none"]
		if ("*" in none or layer in none) and _holds(zone, x, z):
			return true
	return false


## Whether no marker may go at (x, z) for the zones there.
static func keeps_markers_out(zones: Array[Dictionary], x: float, z: float) -> bool:
	for zone in zones:
		if not KINDS[zone["kind"]]["markers"] and _holds(zone, x, z):
			return true
	return false


## The zones `layer` grows thicker in, each with how many times thicker.
static func thicker_for(zones: Array[Dictionary], layer: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for zone in zones:
		var more: Dictionary = KINDS[zone["kind"]]["more"]
		if more.has(layer):
			found.append({"zone": zone, "times": more[layer]})
	return found


## Whether (x, z) lies in `zone`.
static func _holds(zone: Dictionary, x: float, z: float) -> bool:
	return (zone["at"] as Vector2).distance_to(Vector2(x, z)) <= zone["radius"]


## A point picked at random in `zone`, every square metre as likely as any other.
static func point_in(zone: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randf() * TAU
	return (zone["at"] as Vector2) + Vector2(cos(angle), sin(angle)) * sqrt(rng.randf()) * zone["radius"]
