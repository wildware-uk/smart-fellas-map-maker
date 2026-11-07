@tool
extends RefCounted
## The map's play area, as the editor shows it: a square from minus the half width to plus it on X and Z,
## from below the floor up to the ceiling. Says what lies outside it, how big it must be to hold everything
## placed, and where a dragged handle puts an edge. Only the editor uses it: Export and the game never do.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")

## How far Fit to map leaves the edge past the outermost thing placed, and the ceiling over the highest, in
## metres: room for a diver to swim over the tallest rock.
const FIT_MARGIN := 2.0
const FIT_HEADROOM := 8.0
## An area this many times wider (or higher) than what it holds, and this much more besides, is much bigger
## than it needs to be.
const TOO_BIG_SHARE := 1.5
const TOO_BIG_SLACK := 5.0
## Where a dragged edge or ceiling snaps to, in metres: SNAP, or SNAP_WITH_CTRL with Ctrl held.
const SNAP := 1.0
const SNAP_WITH_CTRL := 5.0

## Which handle is which: the four edges, then the ceiling.
enum Handle { EAST, WEST, SOUTH, NORTH, CEILING }
## The way each edge handle drags, in the map's own space.
const EDGE_WAYS := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]


## Whether `at` lies inside the map's area as the game holds markers to it.
static func holds(map: SmartFellasMap, at: Vector3) -> bool:
	return MapExporter.in_the_map(map, at)


## Whether the whole of `box` lies outside the map's area: nothing in it can be reached.
static func wholly_outside(map: SmartFellasMap, box: AABB) -> bool:
	var area := AABB(
		Vector3(-map.half_width, -MapExporter.BELOW_THE_FLOOR, -map.half_width),
		Vector3(map.half_width * 2.0, map.ceiling + MapExporter.BELOW_THE_FLOOR, map.half_width * 2.0)
	)
	return not area.intersects(box) and not area.encloses(box)


## Everything placed that the area is measured against: the markers, each as {"node", "points"}, the
## points the game holds to the area (a food patch's spots as well as its middle), and the pieces, each as
## {"node", "words", "box", "at"}: placed by hand, the map's own models, each copy of a scattered mesh (its
## node the scatter), and painted (with no node). "at" is where Export measures a piece from. Hidden ones are
## out of the map, so out of this.
static func gather(map: SmartFellasMap) -> Dictionary:
	var markers: Array[Dictionary] = []
	for node in map.find_children("*", "Marker3D", true, false):
		var marker := node as Marker3D
		if MarkerKinds.kind_of(marker.name).is_empty() or not marker.is_visible_in_tree():
			continue
		var points := PackedVector3Array([marker.global_position])
		if String(marker.name).begins_with(MapExporter.FOOD_PATCH):
			var patch := {"at": marker.global_position, "basis": marker.global_basis.orthonormalized()}
			for index in MapExporter.SPOTS_IN_A_PATCH:
				points.append(MapExporter._food_spot(patch, index))
		markers.append({"node": marker, "points": points})
	var pieces: Array[Dictionary] = []
	for found in MapExporter.kit_pieces(map):
		var piece: Node3D = found["node"]
		var box: AABB = piece.global_transform * (Kit.info(found["kit"])["bounds"] as AABB)
		pieces.append({"node": piece, "words": String(piece.name), "box": box, "at": piece.global_position})
	for found in MapExporter.own_model_pieces(map):
		var meshes := MapExporter.meshes_in(found["node"])
		if not meshes.is_empty():
			var box := _box_of_meshes(meshes)
			pieces.append({"node": found["node"], "words": String(found["node"].name), "box": box, "at": box.get_center()})
	for scatter in MapExporter.scatters(map):
		var many := scatter.multimesh
		var bounds := many.mesh.get_aabb()
		var buffer := many.buffer
		var count := many.instance_count if many.visible_instance_count < 0 else mini(many.visible_instance_count, many.instance_count)
		# As Export reads them: from the buffer Godot saves, which holds them with no graphics card too.
		if buffer.size() < count * MapExporter._copy_stride(many):
			continue
		for index in count:
			var place := scatter.global_transform * MapExporter.copy_place(many, buffer, index)
			pieces.append({"node": scatter, "words": "Copy %d of %s" % [index + 1, scatter.name], "box": place * bounds, "at": place.origin})
	for kit: String in map.painted:
		var values: PackedFloat32Array = map.painted[kit]
		var bounds: AABB = Kit.info(kit)["bounds"]
		var words := "A painted %s" % Kit.plain_name(kit)
		for index in values.size() / Kit.STRIDE:
			var place := Kit.place_in_list(values, index)
			pieces.append({"node": null, "words": words, "box": place * bounds, "at": place.origin})
	return {"markers": markers, "pieces": pieces}


static func _box_of_meshes(meshes: Array[MeshInstance3D]) -> AABB:
	var box := meshes[0].global_transform * meshes[0].mesh.get_aabb()
	for part in meshes:
		box = box.merge(part.global_transform * part.mesh.get_aabb())
	return box


## Whether Export takes a piece measured from `at`: pieces may stand anywhere in or out of the area, up to
## SCENERY_REACH from the middle of the map.
static func within_reach(at: Vector3) -> bool:
	return MapExporter.scenery_kept(at)


## What of `gathered` lies outside the area: {"markers": the marker nodes the game refuses, "far": the
## pieces too far out for Export to take, "pieces": the rest wholly outside it, which players can see but
## never reach}. Pieces are gather()'s dictionaries.
static func outside(map: SmartFellasMap, gathered: Dictionary) -> Dictionary:
	var markers: Array[Node3D] = []
	for marker: Dictionary in gathered["markers"]:
		for point in marker["points"] as PackedVector3Array:
			if not holds(map, point):
				markers.append(marker["node"])
				break
	var far: Array[Dictionary] = []
	var pieces: Array[Dictionary] = []
	for piece: Dictionary in gathered["pieces"]:
		if not within_reach(piece["at"]):
			far.append(piece)
		elif wholly_outside(map, piece["box"]):
			pieces.append(piece)
	return {"markers": markers, "far": far, "pieces": pieces}


## The smallest area that holds where players go, with FIT_MARGIN round it and FIT_HEADROOM over it, as
## {"half_width", "ceiling"} within what the game takes, or {} if there are no markers. Its edges hold the
## markers: spawns, food, creatures and zones are where players go. Pieces may stand anywhere, as far out as
## they like (#245), so they never push the edges out; a piece standing wholly inside them raises the
## ceiling to swim over it, but one crossing an edge doesn't, as its whole box would overshoot: a hill of a
## ground mesh wider than the area can reach through the ceiling. It never looks at the area as it is now,
## so pressing it again changes nothing. A sculpted seabed must stay within SEABED_BEYOND of the edge, so
## the area keeps that close to its grid.
static func fit(map: SmartFellasMap, gathered: Dictionary) -> Dictionary:
	var reach := -INF
	var top := -INF
	for marker: Dictionary in gathered["markers"]:
		for point in marker["points"] as PackedVector3Array:
			reach = maxf(reach, maxf(absf(point.x), absf(point.z)))
			top = maxf(top, point.y)
	if reach == -INF:
		return {}
	var half := ceilf(reach + FIT_MARGIN)
	if is_sculpted(map):
		half = maxf(half, ceilf(map.seabed_reach - MapExporter.SEABED_BEYOND))
	half = clampf(half, MapExporter.HALF_WIDTHS.x, MapExporter.HALF_WIDTHS.y)
	for piece: Dictionary in gathered["pieces"]:
		var box: AABB = piece["box"]
		var inside := box.position.x >= -half and box.end.x <= half and box.position.z >= -half and box.end.z <= half
		if inside:
			top = maxf(top, box.end.y)
	top = maxf(top, _ground_top(map))
	return {
		"half_width": half,
		"ceiling": clampf(ceilf((top + FIT_HEADROOM) * 2.0) / 2.0, MapExporter.CEILINGS.x, MapExporter.CEILINGS.y),
	}


## Whether the map's seabed is sculpted, as Export checks it.
static func is_sculpted(map: SmartFellasMap) -> bool:
	return map.has_seabed and not (map.seabed_side == 0 and map.seabed_heights.is_empty())


## Sets the area to `fitted`, from fit(), as one step of `history`: Godot's editor history, or an UndoRedo.
static func apply_fit(map: SmartFellasMap, fitted: Dictionary, history: Object) -> void:
	history.create_action("Fit the play area to the map")
	for key: String in fitted:
		history.add_do_property(map, key, fitted[key])
		history.add_undo_property(map, key, map.get(key))
	history.commit_action()


## The highest the seabed reaches: its sculpted top, or the flat seabed's height.
static func _ground_top(map: SmartFellasMap) -> float:
	if not map.has_seabed:
		return -INF
	if not map.seabed_heights.is_empty():
		var top := -INF
		for height in map.seabed_heights:
			top = maxf(top, height)
		return top
	return floor_height(map)


## The height of the flat seabed, where the floor's outline is drawn: the bottom of the map with none.
static func floor_height(map: SmartFellasMap) -> float:
	var seabed := map.find_child("Seabed", true, true) as Node3D
	if not map.has_seabed or seabed == null:
		return -MapExporter.BELOW_THE_FLOOR
	return seabed.global_position.y


## What to tell the map maker about the area, beside what Export refuses: lines for pieces too far out
## for Export to take, and for pieces wholly outside it, and one if it's much bigger than what it holds.
## Export says each marker outside it already.
static func warnings(map: SmartFellasMap, gathered: Dictionary) -> Array[String]:
	var said: Array[String] = []
	var out := outside(map, gathered)
	var far: Array = out["far"]
	if far.size() == 1:
		said.append("%s stands more than %d km from the middle of the map, outlined red in the 3D view. Export leaves it out or refuses it: move it in." % [far[0]["words"], roundi(MapExporter.SCENERY_REACH / 1000.0)])
	elif far.size() > 1:
		said.append("%d pieces stand more than %d km from the middle of the map, outlined red in the 3D view. Export leaves them out or refuses them: move them in." % [far.size(), roundi(MapExporter.SCENERY_REACH / 1000.0)])
	var pieces: Array = out["pieces"]
	if pieces.size() == 1:
		said.append("%s stands wholly outside the play area, outlined amber in the 3D view. Swimmers can see it but never reach it." % pieces[0]["words"])
	elif pieces.size() > 1:
		said.append("%d pieces stand wholly outside the play area, outlined amber in the 3D view. Swimmers can see them but never reach them." % pieces.size())
	var fitted := fit(map, gathered)
	if not fitted.is_empty() and (map.half_width > fitted["half_width"] * TOO_BIG_SHARE + TOO_BIG_SLACK or map.ceiling > fitted["ceiling"] * TOO_BIG_SHARE + TOO_BIG_SLACK):
		said.append("The play area is much bigger than where players go: the markers fit in %s m each way and %s m up. Empty water wastes space, and the bots take longer to chart it. Press Fit to map." % [fitted["half_width"], fitted["ceiling"]])
	return said


## How far along `way` from `start` the line nearest the ray from `from` going `toward` passes. The ray is a
## mouse's, and the line a handle's.
static func along(start: Vector3, way: Vector3, from: Vector3, toward: Vector3) -> float:
	var apart := start - from
	var turn := way.dot(toward)
	var square := way.dot(way) * toward.dot(toward) - turn * turn
	# A ray running along the line meets it nowhere in particular: the nearest point to where it starts.
	if is_zero_approx(square):
		return (from - start).dot(way) / way.dot(way)
	return (turn * toward.dot(apart) - toward.dot(toward) * way.dot(apart)) / square


## What a handle dragged to `reach` metres from the middle (or up, for the ceiling) sets: snapped to `step`
## and held to what the game takes, `limits`.
static func dragged_to(reach: float, step: float, limits: Vector2) -> float:
	return clampf(snappedf(reach, step), limits.x, limits.y)


## The property a handle sets, and what the game takes of it.
static func property_of(handle: int) -> String:
	return "ceiling" if handle == Handle.CEILING else "half_width"


static func limits_of(handle: int) -> Vector2:
	return MapExporter.CEILINGS if handle == Handle.CEILING else MapExporter.HALF_WIDTHS


## Where each handle sits, in the map's own space: each edge's in its middle, just over the floor, and the
## ceiling's at its north-east corner, clear of Godot's own arrows at the map's middle.
static func handle_points(map: SmartFellasMap) -> PackedVector3Array:
	var points := PackedVector3Array()
	for handle in Handle.size():
		points.append(line_of(map, handle) + way_of(handle) * reach_of(map, handle))
	return points


## The line a handle drags along: it starts here, and runs way_of(handle).
static func line_of(map: SmartFellasMap, handle: int) -> Vector3:
	if handle == Handle.CEILING:
		return Vector3(map.half_width, 0.0, -map.half_width)
	return Vector3.UP * (floor_height(map) + 1.0)


static func way_of(handle: int) -> Vector3:
	return Vector3.UP if handle == Handle.CEILING else EDGE_WAYS[handle]


## How far along its line a handle is now.
static func reach_of(map: SmartFellasMap, handle: int) -> float:
	return map.get(property_of(handle))


## Where dragging `handle` with the mouse's ray, from `from` going `toward` in the map's own space, puts its
## edge or the ceiling, snapped to SNAP_WITH_CTRL with Ctrl held or SNAP without.
static func dragged_handle(map: SmartFellasMap, handle: int, from: Vector3, toward: Vector3, ctrl: bool) -> float:
	var reach := along(line_of(map, handle), way_of(handle), from, toward)
	return dragged_to(reach, SNAP_WITH_CTRL if ctrl else SNAP, limits_of(handle))


## A handle let go: puts back `restore` if the drag was cancelled or changed nothing, or else makes the drag
## one step of `history`, already done.
static func let_go(map: SmartFellasMap, handle: int, restore: Variant, cancel: bool, history: Object) -> void:
	var key := property_of(handle)
	if cancel or map.get(key) == restore:
		map.set(key, restore)
		return
	history.create_action("Resize the play area")
	history.add_do_property(map, key, map.get(key))
	history.add_undo_property(map, key, restore)
	history.commit_action(false)
