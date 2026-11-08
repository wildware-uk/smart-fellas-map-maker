@tool
extends RefCounted
## The map's play area, as the editor shows it: its PlayArea box, or an older map's square round the middle.
## Says what lies outside it, the box that fits what players go to, and where a dragged face puts it. Only
## the editor uses it: Export writes the box, and the game holds players to it.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const PlayAreaBox := preload("play_area_box.gd")
const SeabedGrid := preload("seabed_grid.gd")
const SurfaceFinder := preload("surface_finder.gd")

## How many rays a side Fit to map casts down over the box, on a map with no seabed, to find its lowest ground.
const GROUND_RAYS := 16
## How far Fit to map leaves the sides and floor past the outermost and lowest things placed, and the ceiling
## over the highest, in metres: room for a diver to swim over the tallest rock.
const FIT_MARGIN := 2.0
const FIT_HEADROOM := 8.0
## An area this many times wider (or higher) than what it holds, and this much more besides, is much bigger
## than it needs to be.
const TOO_BIG_SHARE := 1.5
const TOO_BIG_SLACK := 5.0
## Where a dragged face snaps to, in metres: SNAP, or SNAP_WITH_CTRL with Ctrl held.
const SNAP := 1.0
const SNAP_WITH_CTRL := 5.0
## What a new PlayArea node is called.
const NODE_NAME := "PlayArea"

## Which handle is which: one on each face of the box.
enum Handle { EAST, WEST, SOUTH, NORTH, TOP, BOTTOM }
## The way each face's handle drags, in the map's own space.
const FACE_WAYS := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.UP, Vector3.DOWN]
const HANDLE_NAMES := ["East edge", "West edge", "South edge", "North edge", "Ceiling", "Floor"]


## Whether `at` lies inside the map's area as the game holds markers to it.
static func holds(map: SmartFellasMap, at: Vector3) -> bool:
	return MapExporter.in_the_map(map, at)


## Whether the whole of `box` lies outside `area`, the map's: nothing in it can be reached.
static func wholly_outside(area: AABB, box: AABB) -> bool:
	return not area.intersects(box) and not area.encloses(box)


## Everything placed that the area is measured against: the markers, each as {"node", "points"}, the
## points the game holds to the area (a food patch's spots as well as its middle), and the pieces, each as
## {"node", "words", "box", "at"}: placed by hand, the map's own models, each copy of a scattered mesh (its
## node the scatter, and "copy" its number in place of "words"), and painted (with no node). words_of() says
## what any of them is called. "at" is where Export measures a piece from. Hidden ones are out of the map,
## so out of this.
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
			# Its words are made only when said: a big map has thousands of copies.
			pieces.append({"node": scatter, "copy": index + 1, "box": place * bounds, "at": place.origin})
	for kit: String in map.painted:
		var values: PackedFloat32Array = map.painted[kit]
		var bounds: AABB = Kit.info(kit)["bounds"]
		var words := "A painted %s" % Kit.plain_name(kit)
		for index in values.size() / Kit.STRIDE:
			var place := Kit.place_in_list(values, index)
			pieces.append({"node": null, "words": words, "box": place * bounds, "at": place.origin})
	return {"markers": markers, "pieces": pieces}


## What a piece gather() found is called, in plain words.
static func words_of(piece: Dictionary) -> String:
	if piece.has("copy"):
		return "Copy %d of %s" % [piece["copy"], piece["node"].name]
	return piece["words"]


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
	# Found once: finding it looks through the map's children, and a big map has thousands of pieces.
	var area := map.area_box()
	for piece: Dictionary in gathered["pieces"]:
		if not within_reach(piece["at"]):
			far.append(piece)
		elif wholly_outside(area, piece["box"]):
			pieces.append(piece)
	return {"markers": markers, "far": far, "pieces": pieces}


## The box that holds where players go, as {"box": AABB} within what the game takes, or {} if there are no
## markers. Its sides hold the markers (spawns, food, creatures, zones: where players go) with FIT_MARGIN
## round them, each way on its own, so a long map gets a long box. Its floor is FIT_MARGIN under the lowest
## marker or ground, and its ceiling FIT_HEADROOM over the highest marker, ground, or piece standing wholly
## inside its sides. Pieces may stand anywhere, as far out as they like (#245), so they never push the sides
## out, and nor does a sculpted seabed reaching past them: ground outside is scenery too. It never looks at
## the area as it is now, so pressing it again changes nothing. Only the ground inside its sides counts. With
## no seabed, the ground is the map's own pieces: with `look_under`, rays down over the box pass through every
## layer to the lowest top they meet, so the solid floor never shuts off a hollow, even one under a roof;
## without, as the warnings measure, the markers say how low players go.
static func fit(map: SmartFellasMap, gathered: Dictionary, look_under := false) -> Dictionary:
	var low := Vector3.INF
	var high := -Vector3.INF
	for marker: Dictionary in gathered["markers"]:
		for point in marker["points"] as PackedVector3Array:
			low = low.min(point)
			high = high.max(point)
	if low == Vector3.INF:
		return {}
	var west := floorf(low.x - FIT_MARGIN)
	var east := ceilf(high.x + FIT_MARGIN)
	var north := floorf(low.z - FIT_MARGIN)
	var south := ceilf(high.z + FIT_MARGIN)
	var sides := _within(Vector2(west, east), MapExporter.SIDES)
	var ends := _within(Vector2(north, south), MapExporter.SIDES)
	var flat := Rect2(sides.x, ends.x, sides.y - sides.x, ends.y - ends.x)
	var top := high.y
	for piece: Dictionary in gathered["pieces"]:
		var box: AABB = piece["box"]
		if box.position.x >= sides.x and box.end.x <= sides.y and box.position.z >= ends.x and box.end.z <= ends.y:
			top = maxf(top, box.end.y)
	var ground := _ground_within(map, flat)
	top = maxf(top, ground.y)
	var lowest := minf(low.y, ground.x)
	if look_under and not map.has_seabed:
		lowest = minf(lowest, _lowest_piece_ground(map, flat, top, low.y))
	var ceiling := ceilf((top + FIT_HEADROOM) * 2.0) / 2.0
	var bottom := maxf(floorf((lowest - FIT_MARGIN) * 2.0) / 2.0, ceiling - MapExporter.HEIGHTS.y)
	var height := maxf(ceiling - bottom, MapExporter.HEIGHTS.x)
	return {"box": AABB(Vector3(sides.x, bottom, ends.x), Vector3(sides.y - sides.x, height, ends.y - ends.x))}


## The span from `span.x` to `span.y`, grown or shrunk about its middle to what the game takes, `limits`.
static func _within(span: Vector2, limits: Vector2) -> Vector2:
	var size := clampf(span.y - span.x, limits.x, limits.y)
	var middle := (span.x + span.y) / 2.0
	return Vector2(middle - size / 2.0, middle + size / 2.0)


## Whether the map's seabed is sculpted, as Export checks it.
static func is_sculpted(map: SmartFellasMap) -> bool:
	return map.has_seabed and not (map.seabed_side == 0 and map.seabed_heights.is_empty())


## Sets the area to `fitted`, from fit(), as one step of `history`: Godot's editor history, or an UndoRedo. A
## map from before the area was a box gets its PlayArea node in the same step.
static func apply_fit(map: SmartFellasMap, fitted: Dictionary, history: Object) -> void:
	var box: AABB = fitted["box"]
	var node := map.play_area()
	history.create_action("Fit the play area to the map")
	if node == null:
		node = PlayAreaBox.new()
		node.name = NODE_NAME
		node.set_box(box)
		# Godot's editor history names a method by its object and name, and an UndoRedo takes a Callable.
		if history is UndoRedo:
			history.add_do_method(map.add_child.bind(node, true))
			history.add_undo_method(map.remove_child.bind(node))
		else:
			history.add_do_method(map, "add_child", node, true)
			history.add_undo_method(map, "remove_child", node)
		history.add_do_property(node, "owner", map.owner if map.owner != null else map)
		history.add_do_reference(node)
	else:
		var floor_middle := Vector3(box.get_center().x, box.position.y, box.get_center().z)
		history.add_do_property(node, "position", floor_middle)
		history.add_do_property(node, "size", box.size)
		history.add_undo_property(node, "position", node.position)
		history.add_undo_property(node, "size", node.size)
	history.commit_action()


## The lowest and highest the seabed is over `flat`, as (lowest, highest): the sculpted ground's points
## inside it, or the flat seabed's height. With no seabed, (INF, -INF): its pieces are the ground.
static func _ground_within(map: SmartFellasMap, flat: Rect2) -> Vector2:
	if not map.has_seabed:
		return Vector2(INF, -INF)
	var grid: RefCounted = SeabedGrid.of(map)
	if grid == null:
		var height := floor_height(map)
		return Vector2(height, height)
	var found := Vector2(INF, -INF)
	for row in grid.side:
		for column in grid.side:
			var point: Vector3 = grid.point_at(column, row)
			if flat.has_point(Vector2(point.x, point.z)):
				found = Vector2(minf(found.x, point.y), maxf(found.y, point.y))
	# A grid too coarse to have a point inside the box still has ground under it.
	if found.x == INF:
		var middle := flat.get_center()
		var height: float = grid.height_at(middle.x, middle.y)
		found = Vector2(height, height)
	return found


## The lowest ground the map's own pieces make over `flat`, as rays straight down find it: the lowest top they
## meet, passing through everything over it, from over `top` to far under `low`.
static func _lowest_piece_ground(map: SmartFellasMap, flat: Rect2, top: float, low: float) -> float:
	var finder := SurfaceFinder.new(map)
	var lowest := INF
	for row in GROUND_RAYS:
		for column in GROUND_RAYS:
			var x := lerpf(flat.position.x, flat.end.x, (column + 0.5) / GROUND_RAYS)
			var z := lerpf(flat.position.y, flat.end.y, (row + 0.5) / GROUND_RAYS)
			lowest = minf(lowest, finder.lowest_top(Vector3(x, top + FIT_HEADROOM, z), Vector3(x, low - MapExporter.HEIGHTS.y, z)))
	return lowest


## The height of the flat seabed, where an older square's outline is drawn: the bottom of the map with none.
static func floor_height(map: SmartFellasMap) -> float:
	var seabed := map.find_child("Seabed", true, true) as Node3D
	if not map.has_seabed or seabed == null:
		return -MapExporter.BELOW_THE_FLOOR
	return seabed.global_position.y


## What to tell the map maker about the area, beside what Export refuses: lines for pieces too far out
## for Export to take, and for pieces wholly outside it, one if it's much bigger than what it holds, and one
## if it's still an older square. Export says each marker outside it already.
static func warnings(map: SmartFellasMap, gathered: Dictionary) -> Array[String]:
	var said: Array[String] = []
	if map.play_area() == null:
		said.append("The play area is an older square round the middle of the map. Press Fit to map to make it a box you can move and size.")
	var out := outside(map, gathered)
	var far: Array = out["far"]
	if far.size() == 1:
		said.append("%s stands more than %d km from the middle of the map, outlined red in the 3D view. Export leaves it out or refuses it: move it in." % [words_of(far[0]), roundi(MapExporter.SCENERY_REACH / 1000.0)])
	elif far.size() > 1:
		said.append("%d pieces stand more than %d km from the middle of the map, outlined red in the 3D view. Export leaves them out or refuses them: move them in." % [far.size(), roundi(MapExporter.SCENERY_REACH / 1000.0)])
	var pieces: Array = out["pieces"]
	if pieces.size() == 1:
		said.append("%s stands wholly outside the play area, outlined amber in the 3D view. Swimmers can see it but never reach it." % words_of(pieces[0]))
	elif pieces.size() > 1:
		said.append("%d pieces stand wholly outside the play area, outlined amber in the 3D view. Swimmers can see them but never reach them." % pieces.size())
	var fitted := fit(map, gathered)
	if not fitted.is_empty():
		var box := map.area_box()
		var fit_box: AABB = fitted["box"]
		var needed := fit_box.size
		# Room under the sand to sculpt into costs little, so only the ceiling counts going up.
		var now := Vector3(box.size.x, box.end.y - fit_box.position.y, box.size.z)
		for axis in 3:
			if now[axis] > needed[axis] * TOO_BIG_SHARE + TOO_BIG_SLACK:
				said.append("The play area is much bigger than where players go: the markers fit in %s m across, %s m up and %s m along. Empty water wastes space, and the bots take longer to chart it. Press Fit to map." % [needed.x, needed.y, needed.z])
				break
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


## The axis a handle moves along: 0 for X, 1 for up, 2 for Z.
static func axis_of(handle: int) -> int:
	return Vector3(FACE_WAYS[handle]).abs().max_axis_index()


## What the game takes of the box's size along a handle's axis.
static func limits_of(handle: int) -> Vector2:
	return MapExporter.HEIGHTS if axis_of(handle) == 1 else MapExporter.SIDES


## Where each handle sits on `box`: in the middle of its face.
static func handle_points(box: AABB) -> PackedVector3Array:
	var points := PackedVector3Array()
	for handle in Handle.size():
		var way: Vector3 = FACE_WAYS[handle]
		points.append(box.get_center() + way * box.size * 0.5)
	return points


## The box dragging `handle` with the mouse's ray, from `from` going `toward` in the map's own space, makes of
## `box`: its face moved to the ray, snapped to SNAP_WITH_CTRL with Ctrl held or SNAP without, the face
## opposite staying put, and its size held to what the game takes.
static func dragged_box(box: AABB, handle: int, from: Vector3, toward: Vector3, ctrl: bool) -> AABB:
	var way: Vector3 = FACE_WAYS[handle]
	var axis := axis_of(handle)
	var forward := way[axis] > 0.0
	var kept: float = box.position[axis] if forward else box.end[axis]
	var start := box.get_center()
	start[axis] = kept
	var reached := kept + way[axis] * along(start, way, from, toward)
	var limits := limits_of(handle)
	var size := clampf(absf(snappedf(reached, SNAP_WITH_CTRL if ctrl else SNAP) - kept), limits.x, limits.y)
	var moved := box
	moved.size[axis] = size
	if not forward:
		moved.position[axis] = kept - size
	return moved


## A handle let go: puts back `restore`, the box before the drag, if the drag was cancelled or changed
## nothing, or else makes the drag one step of `history`, already done.
static func let_go(node: SmartFellasPlayArea, restore: AABB, cancel: bool, history: Object) -> void:
	var now := node.box()
	if cancel or now == restore:
		node.set_box(restore)
		return
	var before := Vector3(restore.get_center().x, restore.position.y, restore.get_center().z)
	history.create_action("Resize the play area")
	history.add_do_property(node, "position", node.position)
	history.add_do_property(node, "size", node.size)
	history.add_undo_property(node, "position", before)
	history.add_undo_property(node, "size", restore.size)
	history.commit_action(false)
