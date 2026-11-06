@tool
extends RefCounted
## Finds the surface under a ray: the flat sand or a rock, whether placed by hand or painted. The editor
## has no physics to ask, and the rays have to land on what the game will have, so this reads the kit's
## own meshes.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const SeabedGrid := preload("seabed_grid.gd")

const CELL := 8.0
## A ray that crosses more cells than this just tries every rock.
const MOST_CELLS := 64
## How close together two surfaces count as the same place.
const TIE := 0.001

var has_sand := false
## The height of the flat sand, or the lowest of the sculpted ground.
var sand_height := 0.0
## The sculpted ground, if the map has any.
var _grid: RefCounted

## One rock each: its name in the kit, where it stands, the inverse of that, and the box it fills.
var _kits: Array[String] = []
var _places: Array[Transform3D] = []
var _inverses: Array[Transform3D] = []
var _boxes: Array[AABB] = []
## Which rocks touch a cell of the map, as seen from above.
var _cells := {}


func _init(map: SmartFellasMap) -> void:
	var seabed := map.find_child("Seabed", true, true)
	if seabed is Node3D and seabed.is_inside_tree():
		has_sand = true
		sand_height = seabed.global_position.y
		_grid = SeabedGrid.of(map)
		if _grid != null:
			sand_height = _grid.lowest
	for found in MapExporter.kit_pieces(map):
		if Kit.is_solid(found["kit"]) and found["node"].is_inside_tree():
			_add(found["kit"], found["node"].global_transform)
	for kit: String in map.painted:
		if Kit.is_solid(kit):
			var values: PackedFloat32Array = map.painted[kit]
			for index in values.size() / Kit.STRIDE:
				_add(kit, Kit.place_in_list(values, index))


func has_rock() -> bool:
	return not _kits.is_empty()


func rock_count() -> int:
	return _kits.size()


## The box rock number `index` fills in the world.
func rock_box(index: int) -> AABB:
	return _boxes[index]


## The height of the ground under this place: the sand, or the sculpted seabed there.
func ground_under(at: Vector3) -> float:
	return _grid.height_at(at.x, at.z) if _grid != null else sand_height


## The height the map's ceiling is measured from: the flat sand, or nothing on a map sculpted away from it.
func ceiling_measured_from() -> float:
	return 0.0 if _grid != null else sand_height


## A rock joined the map since this was made.
func add_rock(kit: String, place: Transform3D) -> void:
	_add(kit, place)


func _add(kit: String, place: Transform3D) -> void:
	var index := _kits.size()
	var box: AABB = place * (Kit.info(kit)["bounds"] as AABB)
	_kits.append(kit)
	_places.append(place)
	_inverses.append(place.affine_inverse())
	_boxes.append(box)
	var low := _cell_of(box.position)
	var high := _cell_of(box.end)
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var cell := Vector2i(x, z)
			if not _cells.has(cell):
				_cells[cell] = PackedInt32Array()
			_cells[cell].append(index)


static func _cell_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.z / CELL))


## The first surface between `from` and `to`, as {"at", "normal", "on"}, where "on" is "sand" or
## "rock". Empty if the ray meets nothing, or if it starts inside a rock: nothing grows in there.
func find(from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var nearest := INF
	if _grid != null:
		var at: Vector3 = _grid.first_hit(from, to)
		if at != Vector3.INF:
			nearest = from.distance_to(at)
			best = {"at": at, "normal": _grid.normal_at(at.x, at.z), "on": "rock" if _grid.is_rock_at(at.x, at.z) else "sand"}
	elif has_sand and from.y > sand_height and to.y < sand_height:
		var along := (from.y - sand_height) / (from.y - to.y)
		nearest = along * from.distance_to(to)
		best = {"at": from.lerp(to, along), "normal": Vector3.UP, "on": "sand"}
	for index in _rocks_near(from, to):
		if not _boxes[index].intersects_segment(from, to):
			continue
		var hit := Kit.triangle_mesh(_kits[index]).intersect_segment(_inverses[index] * from, _inverses[index] * to)
		if hit.is_empty():
			continue
		var at: Vector3 = _places[index] * (hit["position"] as Vector3)
		var distance := from.distance_to(at)
		var outward: Vector3 = _places[index].basis * Kit.outward_of_face(_kits[index], hit["face_index"])
		var from_inside := outward.dot(to - from) > 0.0
		# From inside, a tie goes to the rock: its flat foot lies on the sand.
		if distance < nearest or (from_inside and distance <= nearest + TIE):
			nearest = distance
			best = {} if from_inside else {"at": at, "normal": outward.normalized(), "on": "rock"}
	return best


func _rocks_near(from: Vector3, to: Vector3) -> Array:
	var low := _cell_of(from.min(to))
	var high := _cell_of(from.max(to))
	if (high.x - low.x + 1) * (high.y - low.y + 1) > MOST_CELLS:
		return range(_kits.size())
	var seen := {}
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			for index in _cells.get(Vector2i(x, z), PackedInt32Array()):
				seen[index] = true
	return seen.keys()
