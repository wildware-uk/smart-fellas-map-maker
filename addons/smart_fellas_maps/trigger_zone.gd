@tool
extends Node3D
## A trigger zone for the map's script: an upright box, dropped from the Map panel and sized by the dots on
## its sides, that the script finds by its name with game.zone() and hears players and spears go into and
## out of. It's drawn in the editor only: in the game it's never seen. Export writes it in map.ron's
## triggers, with its middle and how far it reaches from there each way.

## The least and most a zone may reach from its middle each way, in metres, and how far a new one reaches.
const REACHES := Vector2(0.25, 400.0)
const NEW_REACH := Vector3(3.0, 2.0, 3.0)
## The group every trigger zone in the editor is in, so that it can be found without searching the map.
const GROUP := "smart_fellas_trigger_zones"
## Where a dragged side snaps to, in metres.
const SNAP := 0.25
## What the Map panel asks the marker tool to place, to drop a trigger zone.
const PLACING := "trigger zone"
## What a person calls one, and the colour it's drawn in.
const WORDS := "Trigger zone"
const COLOUR := Color(0.3, 0.75, 1.0)
## What a new zone is called, before Godot numbers it to keep it apart from the others.
const NEW_NAME := "zone"

## How far it reaches from its middle each way, along its own sides, before any scale.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var reach := NEW_REACH:
	set(value):
		reach = value.clamp(Vector3.ONE * REACHES.x, Vector3.ONE * REACHES.y)
		update_gizmos()


func _enter_tree() -> void:
	add_to_group(GROUP)


## How far it reaches each way in the world: its reach, times how far Godot's own scale tool stretched it.
func reach_in_world() -> Vector3:
	return reach * global_basis.get_scale().abs()


## Whether it's turned, which the game's upright boxes, lined up with the map, can't be. A half turn, or a
## mirror, leaves the same box; a quarter turn about the up axis doesn't, as the box would stand across the
## one drawn.
func is_turned() -> bool:
	var turn := global_basis.orthonormalized()
	return not (is_equal_approx(absf(turn.x.x), 1.0) and is_equal_approx(absf(turn.y.y), 1.0))


## The shown trigger zones in `map`.
static func nodes_in(map: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not map.is_inside_tree():
		return found
	for node in map.get_tree().get_nodes_in_group(GROUP):
		if map.is_ancestor_of(node) and (node as Node3D).is_visible_in_tree():
			found.append(node)
	return found


## A new trigger zone standing on `at`, in the map's own space, not yet in the map.
static func new_zone(at: Vector3) -> Node3D:
	var zone: Node3D = load("res://addons/smart_fellas_maps/trigger_zone.gd").new()
	zone.name = NEW_NAME
	zone.position = at + Vector3.UP * NEW_REACH.y
	return zone


## The most `zone` may reach from its middle each way in the world, as the game's checker allows: as wide
## as its map, which is twice its half width or ceiling, whichever is bigger.
static func widest_in(zone: Node3D) -> float:
	var map := zone.get_parent()
	while map != null and not map is SmartFellasMap:
		map = map.get_parent()
	return maxf(map.half_width, map.ceiling) * 2.0 if map != null else REACHES.y


## The reach on `axis` (0, 1 or 2) that puts that side of `zone` at `at` in the world, snapped, kept in
## REACHES and no further than `widest` in the world.
static func reach_toward(zone: Node3D, axis: int, at: Vector3, widest := REACHES.y) -> float:
	var across := maxf(absf(zone.global_basis.get_scale()[axis]), 0.001)
	var out := absf((at - zone.global_position)[axis])
	var most := minf(REACHES.y, floorf(widest / across / SNAP) * SNAP)
	return clampf(snappedf(out / across, SNAP), REACHES.x, maxf(most, REACHES.x))


## Makes a zone's new size, from `before`, one step of `history`, a plain UndoRedo or the editor's.
static func sized(zone: Node3D, before: Vector3, history: Object) -> void:
	history.create_action("Size %s" % zone.name)
	history.add_do_property(zone, "reach", zone.reach)
	history.add_undo_property(zone, "reach", before)
	history.commit_action(false)
