@tool
extends RefCounted
## Finds the surface under a ray: the seabed, any piece placed by hand that the game makes solid, painted
## rock and big pieces, and the map's own models. Plants aren't solid in the game, so rays pass through them.
## Painted shells and small coral are left out, so that a brush doesn't heap its pieces on each other. The
## editor has no physics to ask, and the rays have to land on what the game will have, so this reads the
## pieces' own triangles.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const SeabedGrid := preload("seabed_grid.gd")

## Which surfaces to land on: both, the seabed alone, or the pieces and models alone.
enum Surfaces { BOTH, SEABED, MESHES }

const CELL := 8.0
## A ray that crosses more cells than this just tries every piece.
const MOST_CELLS := 64
## How close together two surfaces count as the same place.
const TIE := 0.001
## How far off a spot picked on a surface a ray starts, to see that nothing covers it.
const CLEAR_ABOVE := 0.3
## A spot on a surface counts as open if a ray down at it lands within this of it.
const LANDS_WITHIN := 0.02

var has_sand := false
## Whether a flat floor of rock counts as open ground, for what grows on sand, food and fish: Populate says
## so on a map where little of the floor is sand.
var rock_floors_are_open := false
## The height of the flat sand, or the lowest of the sculpted ground. With no seabed, the lowest of the
## pieces.
var sand_height := 0.0
## The sculpted ground, if the map has any.
var _grid: RefCounted
var _map_sand := false

## One solid thing each: what its shape is called here, its surface, where it stands, the inverse of that,
## the box it fills, what its surface is to a brush ("rock" or "sand"), and the node it is, or null for a
## painted piece.
var _keys: Array = []
var _surfaces: Array[TriangleMesh] = []
var _faces: Array[PackedVector3Array] = []
var _places: Array[Transform3D] = []
var _inverses: Array[Transform3D] = []
var _boxes: Array[AABB] = []
var _grounds: PackedStringArray = []
var _nodes: Array[Node3D] = []
## Which pieces touch a cell of the map, as seen from above.
var _cells := {}
## How much surface each piece has in all, the pieces' running total, for picking spots on them.
var _areas := PackedFloat32Array()
## The same running total for each square picked within, by the square: a piece counts for as much of it
## as its box's footprint lies in the square.
var _areas_within := {}
## What rocks_within last found, what it was asked, and how many pieces it had looked at: pieces only join.
var _rocks_found := PackedInt32Array()
var _rocks_asked := []
var _rocks_counted := 0

## Each mesh's surface for rays, its faces, and its faces' running total of area, made once, by its
## key: a kit piece's name, or a model's mesh.
static var _mesh_surfaces := {}
static var _mesh_faces := {}
static var _mesh_areas := {}


func _init(map: SmartFellasMap, surfaces := Surfaces.BOTH) -> void:
	_map_sand = map_has_sand(map)
	if surfaces != Surfaces.MESHES and map.has_seabed:
		var seabed := map.find_child("Seabed", true, true)
		if seabed is Node3D and seabed.is_inside_tree():
			has_sand = true
			sand_height = seabed.global_position.y
			_grid = SeabedGrid.of(map)
			if _grid != null:
				sand_height = _grid.lowest
	if surfaces == Surfaces.SEABED:
		return
	for found in MapExporter.kit_pieces(map):
		if Kit.is_surface(found["kit"]) and found["node"].is_inside_tree():
			_add_kit(found["kit"], found["node"].global_transform, found["node"])
	for kit: String in map.painted:
		if Kit.is_grown_on(kit):
			var values: PackedFloat32Array = map.painted[kit]
			for index in values.size() / Kit.STRIDE:
				_add_kit(kit, Kit.place_in_list(values, index), null)
	for found in MapExporter.own_model_pieces(map):
		var node: Node3D = found["node"]
		if not node.is_inside_tree():
			continue
		var ground := MapExporter.ground_of(map, found)
		for part in own_model_parts(node):
			var mesh := part.mesh
			_add(mesh, _surface_of(mesh), _faces_of(mesh), mesh.get_aabb(), part.global_transform, "rock" if ground == "rock" else "sand", node)
	if not has_sand and not _boxes.is_empty():
		sand_height = INF
		for box in _boxes:
			sand_height = minf(sand_height, box.position.y)


## The meshes a model dropped into the map is drawn with, and the game makes solid.
static func own_model_parts(model: Node) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	# A mesh on its own is one model, and any mesh under it another, as Export counts them.
	var meshes := [model] if model is MeshInstance3D and model.scene_file_path.is_empty() and model.mesh != null else MapExporter.meshes_in(model)
	for part: MeshInstance3D in meshes:
		if part.mesh.get_faces().size() >= 3:
			parts.append(part)
	return parts


func has_rock() -> bool:
	return not _boxes.is_empty()


## Whether anything in the map is sand, the seabed or a model marked as sand or silt, even if this finder
## was made for other surfaces: so that "Meshes only" on a map with sand doesn't grow sand's plants on rock.
func has_any_sand() -> bool:
	return _map_sand


## Whether anything in the whole map is sand, whichever surfaces a finder was made for: the seabed, or one
## of the map's own models marked as sand or silt.
static func map_has_sand(map: SmartFellasMap) -> bool:
	var seabed := map.find_child("Seabed", true, true)
	if map.has_seabed and seabed is Node3D and seabed.is_inside_tree():
		return true
	for found in MapExporter.own_model_pieces(map):
		if MapExporter.ground_of(map, found) != "rock" and not own_model_parts(found["node"]).is_empty():
			return true
	return false


func rock_count() -> int:
	return _boxes.size()


## The box solid piece number `index` fills in the world.
func rock_box(index: int) -> AABB:
	return _boxes[index]


## The height of the ground under this place: the sand, the sculpted seabed there, or with no seabed the
## lowest of the pieces.
func ground_under(at: Vector3) -> float:
	return _grid.height_at(at.x, at.z) if _grid != null else sand_height


## The height the map's ceiling is measured from: the flat sand, or nothing on a map sculpted away from it
## or with no seabed.
func ceiling_measured_from() -> float:
	return sand_height if has_sand and _grid == null else 0.0


## A solid piece of the kit joined the map since this was made.
func add_rock(kit: String, place: Transform3D) -> void:
	_add_kit(kit, place, null)


func _add_kit(kit: String, place: Transform3D, node: Node3D) -> void:
	_add(kit, Kit.triangle_mesh(kit), Kit.faces_of(kit), Kit.info(kit)["bounds"], place, "rock", node)


func _add(key: Variant, surface: TriangleMesh, faces: PackedVector3Array, bounds: AABB, place: Transform3D, ground: String, node: Node3D) -> void:
	var index := _boxes.size()
	var box: AABB = place * bounds
	_keys.append(key)
	_surfaces.append(surface)
	_faces.append(faces)
	_places.append(place)
	_inverses.append(place.affine_inverse())
	_boxes.append(box)
	_grounds.append(ground)
	_nodes.append(node)
	if not _areas.is_empty():
		_areas.append(_areas[_areas.size() - 1] + _area_in_the_world(index))
	_areas_within.clear()
	var low := _cell_of(box.position)
	var high := _cell_of(box.end)
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var cell := Vector2i(x, z)
			if not _cells.has(cell):
				_cells[cell] = PackedInt32Array()
			_cells[cell].append(index)


static func _surface_of(mesh: Mesh) -> TriangleMesh:
	if not _mesh_surfaces.has(mesh):
		var surface := TriangleMesh.new()
		surface.create_from_faces(_faces_of(mesh))
		_mesh_surfaces[mesh] = surface
	return _mesh_surfaces[mesh]


static func _faces_of(mesh: Mesh) -> PackedVector3Array:
	if not _mesh_faces.has(mesh):
		_mesh_faces[mesh] = mesh.get_faces()
	return _mesh_faces[mesh]


## The running total of the area of the faces of the shape called `key`, in its own space, made once.
static func _areas_of(key: Variant, faces: PackedVector3Array) -> PackedFloat32Array:
	if _mesh_areas.has(key):
		return _mesh_areas[key]
	var areas := PackedFloat32Array()
	areas.resize(faces.size() / 3)
	var total := 0.0
	for face in faces.size() / 3:
		total += _face_area(faces, face)
		areas[face] = total
	_mesh_areas[key] = areas
	return areas


static func _face_area(faces: PackedVector3Array, face: int) -> float:
	var a := faces[face * 3]
	return (faces[face * 3 + 1] - a).cross(faces[face * 3 + 2] - a).length() * 0.5


static func _cell_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))


## The first surface between `from` and `to`, as {"at", "normal", "on", "seabed", "node"}, where "on" is
## "sand" or "rock", "seabed" whether it's the seabed and not a piece, and "node" the piece placed by hand
## that it's on, or null. Empty if the ray meets nothing, or if it starts inside a piece: nothing grows in
## there. The ray passes through `ignoring`, and anything in it.
func find(from: Vector3, to: Vector3, ignoring: Node3D = null) -> Dictionary:
	var best := {}
	var nearest := INF
	if _grid != null:
		var at: Vector3 = _grid.first_hit(from, to)
		if at != Vector3.INF:
			nearest = from.distance_to(at)
			best = {"at": at, "normal": _grid.normal_at(at.x, at.z), "on": "rock" if _grid.is_rock_at(at.x, at.z) else "sand", "seabed": true, "node": null}
	elif has_sand and from.y > sand_height and to.y < sand_height:
		var along := (from.y - sand_height) / (from.y - to.y)
		nearest = along * from.distance_to(to)
		best = {"at": from.lerp(to, along), "normal": Vector3.UP, "on": "sand", "seabed": true, "node": null}
	for index in _pieces_near(from, to):
		if not _boxes[index].intersects_segment(from, to):
			continue
		if ignoring != null and _nodes[index] != null and (_nodes[index] == ignoring or ignoring.is_ancestor_of(_nodes[index])):
			continue
		var hit := _surfaces[index].intersect_segment(_inverses[index] * from, _inverses[index] * to)
		if hit.is_empty():
			continue
		var at: Vector3 = _places[index] * (hit["position"] as Vector3)
		var distance := from.distance_to(at)
		var outward: Vector3 = _places[index].basis * _outward(_faces[index], hit["face_index"])
		var from_inside := outward.dot(to - from) > 0.0
		# From inside, a tie goes to the piece: a rock's flat foot lies on the sand.
		if distance < nearest or (from_inside and distance <= nearest + TIE):
			nearest = distance
			best = {} if from_inside else {"at": at, "normal": outward.normalized(), "on": _grounds[index], "seabed": false, "node": _nodes[index]}
	return best


## Which way face `index` of `faces` really faces. A TriangleMesh only says which way it faces the ray,
## which can't tell the outside of a rock from the inside.
static func _outward(faces: PackedVector3Array, index: int) -> Vector3:
	var a := faces[index * 3]
	var b := faces[index * 3 + 1]
	var c := faces[index * 3 + 2]
	return (a - c).cross(a - b).normalized()


## A spot picked at random on the pieces' surfaces, any way they face, every square metre as likely as
## any other, as find gives it: tops, sides and undersides alike. Empty if the spot is covered by something
## else, or there are no pieces. Given a square `within`, as seen from above, it picks among the pieces
## over it, by how much of each lies over it, so that a map's meshes reaching far past it don't take most
## of the picks; the spot itself may still lie outside it.
func random_spot(rng: RandomNumberGenerator, within := Rect2()) -> Dictionary:
	if _boxes.is_empty():
		return {}
	if _areas.is_empty():
		var total := 0.0
		_areas.resize(_boxes.size())
		for index in _boxes.size():
			total += _area_in_the_world(index)
			_areas[index] = total
	var totals := _areas
	if within.has_area():
		if not _areas_within.has(within):
			_areas_within[within] = _totals_within(within)
		totals = _areas_within[within]
	if totals[totals.size() - 1] <= 0.0:
		return {}
	var index := _pick(totals, rng.randf() * totals[totals.size() - 1])
	var faces := _faces[index]
	var areas := _areas_of(_keys[index], faces)
	var face := _pick(areas, rng.randf() * areas[areas.size() - 1])
	var one := rng.randf()
	var other := rng.randf()
	if one + other > 1.0:
		one = 1.0 - one
		other = 1.0 - other
	var a := faces[face * 3]
	var local := a + (faces[face * 3 + 1] - a) * one + (faces[face * 3 + 2] - a) * other
	var at: Vector3 = _places[index] * local
	var normal: Vector3 = (_places[index].basis * _outward(faces, face)).normalized()
	if not normal.is_finite() or normal.is_zero_approx():
		return {}
	var hit := find(at + normal * CLEAR_ABOVE, at - normal * CLEAR_ABOVE)
	if hit.is_empty() or (hit["at"] as Vector3).distance_to(at) > LANDS_WITHIN:
		return {}
	return hit


## The pieces' running total of surface, each counted for the share of its box's footprint over `within`.
func _totals_within(within: Rect2) -> PackedFloat32Array:
	var totals := PackedFloat32Array()
	totals.resize(_boxes.size())
	var total := 0.0
	for index in _boxes.size():
		total += _area_in_the_world(index) * _share_over(_boxes[index], within)
		totals[index] = total
	return totals


## How much of `box`'s footprint, seen from above, lies over `within`: from 0 to 1. A box with no width
## one way, a flat floor, counts by its length the other.
static func _share_over(box: AABB, within: Rect2) -> float:
	var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	var low := footprint.position.max(within.position)
	var high := footprint.end.min(within.end)
	if high.x < low.x or high.y < low.y:
		return 0.0
	var across := 1.0 if footprint.size.x <= 0.0 else (high.x - low.x) / footprint.size.x
	var along := 1.0 if footprint.size.y <= 0.0 else (high.y - low.y) / footprint.size.y
	return across * along


## The solid pieces to shelter beside within `within`, as seen from above: those whose box lies over it
## and is no wider than `widest` metres, as a rock or a wreck is and a map's whole ground isn't.
func rocks_within(within: Rect2, widest: float) -> PackedInt32Array:
	var asked := [within, widest]
	if _rocks_asked == asked:
		for index in range(_rocks_counted, _boxes.size()):
			_add_if_shelter(index, within, widest)
	else:
		_rocks_asked = asked
		_rocks_found = PackedInt32Array()
		for index in _boxes.size():
			_add_if_shelter(index, within, widest)
	_rocks_counted = _boxes.size()
	return _rocks_found


func _add_if_shelter(index: int, within: Rect2, widest: float) -> void:
	var box := _boxes[index]
	if maxf(box.size.x, box.size.z) <= widest and _share_over(box, within) > 0.0:
		_rocks_found.append(index)


## How much surface piece `index` has, at its size in the world.
func _area_in_the_world(index: int) -> float:
	var scale := _places[index].basis.get_scale().x
	var areas := _areas_of(_keys[index], _faces[index])
	return areas[areas.size() - 1] * scale * scale


## The first place in a running total past `value`.
static func _pick(totals: PackedFloat32Array, value: float) -> int:
	var low := 0
	var high := totals.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if totals[middle] < value:
			low = middle + 1
		else:
			high = middle
	return low


func _pieces_near(from: Vector3, to: Vector3) -> Array:
	var low := _cell_of(from.min(to))
	var high := _cell_of(from.max(to))
	if (high.x - low.x + 1) * (high.y - low.y + 1) > MOST_CELLS:
		return range(_boxes.size())
	var seen := {}
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			for index in _cells.get(Vector2i(x, z), PackedInt32Array()):
				seen[index] = true
	return seen.keys()
