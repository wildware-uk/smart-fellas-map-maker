@tool
extends RefCounted
## Carries what stands on a piece or model of the map's own when the map maker moves or turns it. Painted
## pieces, markers and pieces placed by hand that were on it move with it, once the mouse lets go, as a step
## of undo of their own, just after the move. Undo takes them back first, then the move.
##
## Only a move the map maker has just made is carried: one that undo or redo makes isn't, as undo has
## already taken back what was carried, and redo brings it back by itself.

const Brush := preload("brush.gd")
const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const SurfaceFinder := preload("surface_finder.gd")

## How far along its up a painted or placed piece's foot may be from the surface and still stand on it.
const FOOT_REACH := 0.35
## How much further than its lift a marker may be from the surface and still stand on it.
const MARKER_REACH := 0.5
## How much further a ray slanted off a surface's facing reaches, to make up for the slant.
const SLANT := 1.1
## How far past a piece's box what's on it can be.
const BOX_MARGIN := 2.0

## A plain UndoRedo or the editor's.
var history: Object
var map: SmartFellasMap

var _watched: Node3D
var _was: Transform3D


## Whether `node` is something things can stand on and that the map maker can move: a solid kit piece or
## one of the map's own models.
static func carries(node: Node) -> bool:
	if not node is Node3D:
		return false
	var path: String = node.scene_file_path
	if path.begins_with(Kit.FOLDER):
		return Kit.is_surface(path.get_file().get_basename())
	return path.get_extension().to_lower() == "glb"


## Watches `node` from now, or nothing if it's null. What it had moved by then is carried first.
func watch(node: Node3D) -> void:
	tick(true)
	_watched = node if node != null and carries(node) else null
	if _watched != null:
		_was = _watched.global_transform


## The history the map's changes go in: a plain UndoRedo, or the editor's for the map's scene.
func _scene_history() -> UndoRedo:
	if history is UndoRedo:
		return history
	return history.get_history_undo_redo(history.get_object_history_id(map))


## Whether the newest change in the history is one just made, and not an undo or a redo: nothing is left
## to redo after a new change.
func _was_just_made() -> bool:
	var scene := _scene_history()
	return scene == null or not scene.has_redo()


## To be called each frame: carries what was on the watched piece once it has moved and the mouse is up.
## `now` carries it even with the mouse still down.
func tick(now := false) -> void:
	if _watched == null or not is_instance_valid(_watched) or not _watched.is_inside_tree() or map == null:
		_watched = null
		return
	var place := _watched.global_transform
	if place.is_equal_approx(_was):
		return
	if not now and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var was := _was
	_was = place
	if _was_just_made():
		carry(_watched, was, place)


## Moves what stood on `node` at `was` to stand on it at `now`, as one step of undo. Gives back how many
## things it moved.
func carry(node: Node3D, was: Transform3D, now: Transform3D) -> int:
	var shapes := _shapes_of(node, was)
	if shapes.is_empty():
		return 0
	var box: AABB = shapes[0]["box"]
	for shape in shapes:
		box = box.merge(shape["box"])
	box = box.grow(BOX_MARGIN)
	var move := now * was.affine_inverse()
	var turn := move.basis.orthonormalized()
	var painted_after: Dictionary[String, PackedFloat32Array] = map.painted.duplicate()
	var populated_after: Dictionary[String, PackedFloat32Array] = map.populated.duplicate()
	var moved := 0
	for kit: String in map.painted:
		var values: PackedFloat32Array = map.painted[kit]
		var changed := values.duplicate()
		var own: PackedFloat32Array = map.populated.get(kit, PackedFloat32Array()).duplicate()
		var any := false
		for first in range(0, values.size(), Kit.STRIDE):
			var foot := Vector3(values[first], values[first + 1], values[first + 2])
			var up := Vector3(values[first + 3], values[first + 4], values[first + 5])
			if not box.has_point(foot) or not _stands_on(shapes, foot, up, FOOT_REACH):
				continue
			var place := Kit.place_in_list(values, first / Kit.STRIDE)
			var carried := _carried(move, turn, place)
			var numbers := PackedFloat32Array([carried["at"].x, carried["at"].y, carried["at"].z, carried["up"].x, carried["up"].y, carried["up"].z, carried["turn"], values[first + 7]])
			for index in Kit.STRIDE:
				changed[first + index] = numbers[index]
			_carry_own(own, values, first, numbers)
			any = true
			moved += 1
		if any:
			painted_after[kit] = changed
			if map.populated.has(kit):
				populated_after[kit] = own
	var nodes: Array[Node3D] = []
	var places: Array[Transform3D] = []
	for found in MapExporter.kit_pieces(map) + MapExporter.own_model_pieces(map):
		var piece: Node3D = found["node"]
		if piece == node or node.is_ancestor_of(piece) or piece.is_ancestor_of(node):
			continue
		var place := piece.global_transform
		# Something bigger than what moved isn't on it, however near its middle is: the floor under a rock.
		if not box.encloses(_box_of(piece)):
			continue
		if _stands_on(shapes, place.origin, place.basis.y.normalized(), FOOT_REACH):
			nodes.append(piece)
			places.append(_moved(move, turn, place))
	# The map's other surfaces, made only if a marker beside the piece needs them.
	var finder: SurfaceFinder = null
	for marker in map.find_children("*", "Marker3D", true, false):
		var kind := MarkerKinds.kind_of(marker.name)
		if kind.is_empty() or node.is_ancestor_of(marker):
			continue
		var place: Transform3D = marker.global_transform
		var lift: float = MarkerKinds.KINDS[kind]["lift"]
		var down := place.basis.y.normalized()
		var on := _stands_on(shapes, place.origin, down, lift + MARKER_REACH) or _stands_on(shapes, place.origin, Vector3.UP, lift + MARKER_REACH)
		# An upright marker dropped on a wall stands out from it sideways, not over it. One beside the piece
		# with anything else under it, such as the floor at a rock's foot, stands on that and stays, as does
		# one tucked under another rock's ledge, where the look starts inside that rock. The piece itself is
		# left out of that look, as it has moved already.
		if not on and box.has_point(place.origin) and _beside(shapes, place.origin, lift + MARKER_REACH):
			if finder == null:
				finder = SurfaceFinder.new(map)
			var above := place.origin + Vector3.UP * FOOT_REACH
			on = not finder.meets(above, place.origin + Vector3.DOWN * (lift + MARKER_REACH), node)
		if box.has_point(place.origin) and on:
			nodes.append(marker)
			# A marker keeps its own up: spawn points and fish stand upright wherever they are.
			var kept := place
			kept.origin = move * place.origin
			if MarkerKinds.KINDS[kind]["on_surface"]:
				kept = _moved(move, turn, place)
			places.append(kept)
	moved += nodes.size()
	if moved == 0:
		return 0
	history.create_action("Carry what stands on %s" % node.name)
	if painted_after != map.painted:
		history.add_do_property(map, "painted", painted_after)
		history.add_undo_property(map, "painted", map.painted)
		history.add_do_property(map, "populated", populated_after)
		history.add_undo_property(map, "populated", map.populated)
	for index in nodes.size():
		var carried := nodes[index]
		var local := carried.get_parent_node_3d().global_transform.affine_inverse() * places[index] if carried.get_parent_node_3d() != null else places[index]
		history.add_do_property(carried, "transform", local)
		history.add_undo_property(carried, "transform", carried.transform)
		if carried.has_meta(MarkerKinds.OWN_MARK) and carried.position.distance_to(carried.get_meta(MarkerKinds.OWN_MARK)) < MarkerKinds.STILL_THERE:
			Brush._on_do(history, carried, "set_meta", [MarkerKinds.OWN_MARK, local.origin])
			Brush._on_undo(history, carried, "set_meta", [MarkerKinds.OWN_MARK, carried.position])
	Brush._on_do(history, map, "notify_pieces_changed", [])
	Brush._on_undo(history, map, "notify_pieces_changed", [])
	history.commit_action()
	return moved


## The box a piece placed by hand fills in the world.
static func _box_of(piece: Node3D) -> AABB:
	var path := piece.scene_file_path
	if path.begins_with(Kit.FOLDER):
		return piece.global_transform * (Kit.info(path.get_file().get_basename())["bounds"] as AABB)
	var parts := SurfaceFinder.own_model_parts(piece)
	if parts.is_empty():
		return AABB(piece.global_position, Vector3.ZERO)
	var box := parts[0].global_transform * parts[0].mesh.get_aabb()
	for part in parts:
		box = box.merge(part.global_transform * part.mesh.get_aabb())
	return box


## The surfaces of `node` as it stood at `place`: each {"surface", "faces", "place", "inverse", "box"}.
static func _shapes_of(node: Node3D, place: Transform3D) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var path := node.scene_file_path
	if path.begins_with(Kit.FOLDER):
		var kit := path.get_file().get_basename()
		shapes.append(_shape(Kit.triangle_mesh(kit), Kit.info(kit)["bounds"], place))
		return shapes
	var inverse := node.global_transform.affine_inverse()
	for part in SurfaceFinder.own_model_parts(node):
		var surface := TriangleMesh.new()
		surface.create_from_faces(part.mesh.get_faces())
		shapes.append(_shape(surface, part.mesh.get_aabb(), place * (inverse * part.global_transform)))
	return shapes


static func _shape(surface: TriangleMesh, bounds: AABB, place: Transform3D) -> Dictionary:
	return {"surface": surface, "place": place, "inverse": place.affine_inverse(), "box": place * bounds}


## Whether something at `at` facing `up` stands on one of the shapes: a ray down its up from a little above
## meets one within `reach`.
static func _stands_on(shapes: Array[Dictionary], at: Vector3, up: Vector3, reach: float) -> bool:
	var from := at + up * FOOT_REACH
	var to := at - up * reach
	for shape in shapes:
		var inverse: Transform3D = shape["inverse"]
		if not (shape["box"] as AABB).grow(reach).intersects_segment(from, to):
			continue
		if not (shape["surface"] as TriangleMesh).intersect_segment(inverse * from, inverse * to).is_empty():
			return true
	return false


## Whether one of the shapes is within `reach` of `at` in any of the 26 ways out of a cube, so that a
## marker standing out from a wall or hanging under a ledge counts as on it. The ways are up to 22.5
## degrees off the nearest surface's, so they reach a little further.
static func _beside(shapes: Array[Dictionary], at: Vector3, reach: float) -> bool:
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				var way := Vector3(x, y, z)
				if way != Vector3.ZERO and _stands_on(shapes, at, -way.normalized(), reach * SLANT):
					return true
	return false


## Where a piece placed at `place` goes when what it stands on moves by `move`, turning by `turn`.
static func _moved(move: Transform3D, turn: Basis, place: Transform3D) -> Transform3D:
	return Transform3D(turn * place.basis, move * place.origin)


## A painted piece's numbers once carried: its foot, its up, and its turn about that up.
static func _carried(move: Transform3D, turn: Basis, place: Transform3D) -> Dictionary:
	var moved := _moved(move, turn, place)
	var rotation := moved.basis.get_rotation_quaternion()
	var up := (rotation * Vector3.UP).normalized()
	var twist := Kit.arc_from_up(up).inverse() * rotation
	return {"at": moved.origin, "up": up, "turn": wrapf(2.0 * atan2(twist.y, twist.w), -PI, PI)}


## Moves the same piece in Populate's own list, if it's one Populate added, so that it still knows it.
static func _carry_own(own: PackedFloat32Array, values: PackedFloat32Array, first: int, numbers: PackedFloat32Array) -> void:
	for other in range(0, own.size(), Kit.STRIDE):
		if own[other] == values[first] and own[other + 1] == values[first + 1] and own[other + 2] == values[first + 2] and own[other + 6] == values[first + 6]:
			for index in Kit.STRIDE:
				own[other + index] = numbers[index]
			return
