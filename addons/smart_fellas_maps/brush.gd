@tool
extends RefCounted
## The paint brush: what one stroke does to a map. The panel and the mouse only say where and when, so
## that a test can run a stroke with no window and get the same pieces.
##
## Where things grow goes by a pattern fixed in the world, not by the stroke: the world is cut into cells,
## each with a clump in it of one main kind, biggest at the middle and thinning out towards the edge. So
## strokes that cross each other agree on where the clumps are, and painting over a spot fills it in up to
## how thick the brush says, then stops. That's what makes it look grown, not sprinkled.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const SurfaceFinder := preload("surface_finder.gd")
const Recipes := preload("recipes.gd")

## How many tries a stroke makes for each piece it expects to land, since many fall outside a clump or
## break a rule, and the most it makes at one spot, so that a wide brush can't stall the editor.
const TRIES_PER_PIECE := 3.0
const MOST_TRIES := 200
## How far apart two spots of a stroke are, as a share of how wide the brush is.
const SPOT_SPACING := 0.4
## How far apart pieces of a brush keep, from how thick it is: this much over the square root of pieces
## to a square metre is about as thick as such a rule can fill.
const SPACING_AT_THICKNESS := 0.8
## Pieces may overlap this much: two whose spread is 1 m each can stand this many metres apart.
const CROWDING := 0.5
## How far into the surface a piece's foot goes, as a share of its size, so that it doesn't float.
const SINK := 0.02
## How much of a clump's kinds is its main kind or second kind, the rest being any of the mix.
const CLUMP_MAIN_KIND := 0.75
const CLUMP_SECOND_KIND := 0.2
## The spacing grid's cell, in metres.
const SPACING_CELL := 1.5

## What to say when the map can't take another piece.
const FULL_WORDS := "This map has all the %d pieces a map can place. Erase some to paint more."

## How many pieces this stroke placed or removed.
var placed := 0
var removed := 0
## Set when the map is full: what to tell the person, in plain words.
var stopped_because := ""
## Where nothing may grow, if set: given a spot, true if it's kept clear. Populate's zones set it.
var keeps_out := Callable()
## Whether each piece is drawn as it lands. Populate turns this off and draws them all at the end.
var draws_as_it_goes := true

var _map: SmartFellasMap
var _recipe: Dictionary
var _finder: SurfaceFinder
var _rng := RandomNumberGenerator.new()
var _erasing := false
var _before: Dictionary[String, PackedFloat32Array]
var _working: Dictionary[String, PackedFloat32Array]
var _copied := {}
var _pieces_in_map := 0
var _weights := 0.0
var _mix: Array = []
var _last_spot := Vector3.INF
## Where the pieces are, for keeping them apart: (cell x, cell z, 1 if rock) -> [x, y, z, spread, ...].
## Rocks are only kept apart from rocks, since other things grow on them.
var _spacing := {}
var _widest_spread := 0.0
var _hand_erased: Array[Node] = []
var _hand_erase := false
var _only_mix := false


## Why this brush can't paint on this map as it stands, in plain words, or nothing if it can. `surfaces`, if
## given, are the map's as they stand, which saves reading them again.
static func why_it_cant_paint(map: SmartFellasMap, recipe: Dictionary, surfaces: SurfaceFinder = null) -> String:
	var any_weight := false
	for entry in recipe["mix"]:
		any_weight = any_weight or (entry["weight"] > 0.0 and Kit.has(entry["kit"]))
	if recipe["mix"].is_empty():
		return "The brush has nothing to paint. Click some pieces in the Pieces panel to add them to its mix."
	if not any_weight:
		return "Every slider in the mix is at 0, so the brush has nothing to paint. Move one up."
	if not recipe["on_sand"] and not recipe["on_rock"]:
		return "This brush grows on neither sand nor rock. Tick one under Where it grows."
	var finder := surfaces if surfaces != null else SurfaceFinder.new(map)
	var grows_on: String = recipe.get("surfaces", "both")
	if grows_on == "seabed" and not finder.has_sand:
		return "This map has no seabed, and this brush only grows on the seabed. Set Surfaces to meshes, or tick Seabed in the Map panel."
	if grows_on == "meshes" and not finder.has_rock():
		return "This brush only grows on meshes, and the map has none. Place a rock or a model of your own first."
	if not finder.has_sand and not finder.has_rock():
		return "This map has nothing to paint on. Tick Seabed in the Map panel, or place a rock or a model of your own."
	if not finder.has_any_sand() and not recipe["on_rock"]:
		return "This map has no sand, and this brush only grows on sand. Tick Seabed in the Map panel, mark one of your own models as sand in it, or tick On rock."
	if MapExporter.kit_pieces(map).size() + map.painted_count() >= MapExporter.MOST_PIECES:
		return FULL_WORDS % MapExporter.MOST_PIECES
	return ""


## Starts painting `recipe` on `map`, with `stroke_seed` for what's random within the pattern.
func start_painting(map: SmartFellasMap, recipe: Dictionary, stroke_seed: int, finder: SurfaceFinder = null) -> void:
	_start(map, recipe, stroke_seed, finder)
	_mix = recipe["mix"].filter(func(entry: Dictionary) -> bool: return entry["weight"] > 0.0 and Kit.has(entry["kit"]))
	_weights = 0.0
	for entry in _mix:
		_weights += entry["weight"]
	_fill_spacing()


## Starts erasing from `map`. Only painted pieces go, unless `hand_placed_too`, and only kinds in the
## recipe's mix if `only_mix`.
func start_erasing(map: SmartFellasMap, recipe: Dictionary, hand_placed_too: bool, only_mix: bool, finder: SurfaceFinder = null) -> void:
	_start(map, recipe, 0, finder)
	_erasing = true
	_hand_erase = hand_placed_too
	_only_mix = only_mix


func _start(map: SmartFellasMap, recipe: Dictionary, stroke_seed: int, finder: SurfaceFinder) -> void:
	_map = map
	_recipe = recipe
	_finder = finder if finder != null else SurfaceFinder.new(map)
	_rng.seed = stroke_seed
	_before = map.painted
	_working = map.painted.duplicate()
	map.set_painted_quietly(_working)
	_pieces_in_map = MapExporter.kit_pieces(map).size() + map.painted_count()


## The stroke has got to `at`, on a surface facing `normal`. It fills the way from the last spot. Gives
## back how many pieces this added or removed.
func move_to(at: Vector3, normal: Vector3) -> int:
	var before := placed + removed
	if _last_spot == Vector3.INF:
		_spot(at, normal)
	else:
		var step: float = maxf(_recipe["wide"] * SPOT_SPACING, 0.05)
		var away := _last_spot.distance_to(at)
		if away < step:
			return 0
		var spots := floori(away / step)
		for index in spots:
			_spot(_last_spot.lerp(at, float(index + 1) / spots), normal)
	_last_spot = at
	return placed + removed - before


## The mouse is holding still at `at`: goes on growing there.
func hold_at(at: Vector3, normal: Vector3) -> int:
	var before := placed + removed
	_spot(at, normal)
	_last_spot = at
	return placed + removed - before


func _spot(at: Vector3, normal: Vector3) -> void:
	if _erasing:
		_erase_around(at)
	else:
		_paint_around(at, normal)


func _paint_around(centre: Vector3, normal: Vector3) -> void:
	if _mix.is_empty():
		return
	var wide: float = _recipe["wide"]
	var thick: float = _recipe["thick"]
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var ahead := normal.cross(side)
	var tries := clampi(ceili(thick * wide * wide * SPOT_SPACING * 2.0 * TRIES_PER_PIECE), 4, MOST_TRIES)
	for _try in tries:
		var angle := _rng.randf() * TAU
		var out := sqrt(_rng.randf()) * wide
		var above := centre + (side * cos(angle) + ahead * sin(angle)) * out + normal * wide
		var hit := _finder.find(above, above - normal * wide * 2.5)
		if not hit.is_empty() and _grows_on(hit):
			if not _try_piece(hit):
				return


## Whether the surface `hit` meets the brush's rules on where things grow, and is in the map.
func _grows_on(hit: Dictionary) -> bool:
	if not lands_on(_recipe, hit):
		return false
	var at: Vector3 = hit["at"]
	var area := _map.area_box()
	if at.x < area.position.x or at.x > area.end.x or at.z < area.position.z or at.z > area.end.z:
		return false
	if keeps_out.is_valid() and keeps_out.call(at):
		return false
	var above_sand := at.y - _finder.ground_under(at)
	if above_sand < _recipe["height_low"] or above_sand > _recipe["height_high"]:
		return false
	# An older map's square measured its ceiling from the sand; a box's is where it is.
	var ceiling := _map.area_ceiling() + (_finder.ceiling_measured_from() if _map.play_area() == null else 0.0)
	if at.y > ceiling:
		return false
	var slope := rad_to_deg(acos(clampf((hit["normal"] as Vector3).y, -1.0, 1.0)))
	return slope >= _recipe["slope_low"] and slope <= _recipe["slope_high"]


## Whether a recipe grows on the surface `hit`, as its sand, rock and surfaces settings say.
static func lands_on(recipe: Dictionary, hit: Dictionary) -> bool:
	match recipe.get("surfaces", "both"):
		"seabed":
			if not hit["seabed"]:
				return false
		"meshes":
			if hit["seabed"]:
				return false
	return recipe["on_sand" if hit["on"] == "sand" else "on_rock"]


## Places a piece on the surface `hit`, if the clumps and the spacing allow. Gives back false if the
## map is full.
func _try_piece(hit: Dictionary) -> bool:
	var at: Vector3 = hit["at"]
	var normal: Vector3 = hit["normal"]
	var clumps: float = _recipe["clumps"]
	var clump := _clump_at(at, normal)
	# How far out from the middle of its clump this spot is, where 1 is the clump's edge.
	var out: float = clump["out"]
	var inside := 1.0 - smoothstep(0.55, 1.0, out)
	if clump["empty"]:
		inside = 0.0
	if _rng.randf() > lerpf(1.0, inside, clumps):
		return true
	var kit := _pick_kind(clump, clumps)
	var growth := _rng.randf() * (1.0 - clampf(out, 0.0, 1.0) * 0.7 * clumps)
	var size: float = lerpf(_recipe["size_low"], _recipe["size_high"], growth)
	var spread: float = Kit.info(kit)["radius"] * size
	if not _has_room(at, spread, Kit.is_solid(kit)):
		return true
	if _pieces_in_map >= MapExporter.MOST_PIECES:
		stopped_because = FULL_WORDS % MapExporter.MOST_PIECES
		return false
	_place(kit, at, normal, size, spread)
	return true


func _pick_kind(clump: Dictionary, clumps: float) -> String:
	var choice := _rng.randf()
	if choice < clumps * CLUMP_MAIN_KIND:
		return _weighted(clump["main"])
	if choice < clumps * (CLUMP_MAIN_KIND + CLUMP_SECOND_KIND):
		return _weighted(clump["second"])
	return _weighted(_rng.randf())


## The kind in the mix that `choice`, from 0 to 1, comes to by weight.
func _weighted(choice: float) -> String:
	var left := choice * _weights
	for entry in _mix:
		left -= entry["weight"]
		if left <= 0.0:
			return entry["kit"]
	return _mix[-1]["kit"]


func _place(kit: String, at: Vector3, normal: Vector3, size: float, spread: float) -> void:
	var up := normal
	if _recipe["follow"] < 1.0 and normal.dot(Vector3.UP) > -0.999:
		up = Vector3.UP.slerp(normal, _recipe["follow"]).normalized()
	var wobble := deg_to_rad(_recipe["wobble"]) * _rng.randf()
	if wobble > 0.0:
		var across := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		up = up.rotated(across.rotated(up, _rng.randf() * TAU), wobble).normalized()
	var limit := deg_to_rad(_recipe["turn"])
	var turn := _rng.randf_range(-limit, limit)
	var foot := at - normal * size * SINK
	var values := _editable(kit)
	values.append_array(PackedFloat32Array([foot.x, foot.y, foot.z, up.x, up.y, up.z, turn, size]))
	_working[kit] = values
	_note_spacing(at, spread, Kit.is_solid(kit))
	if draws_as_it_goes:
		_map.show_added(kit, values)
	if Kit.is_grown_on(kit):
		_finder.add_rock(kit, Kit.place_in_list(values, values.size() / Kit.STRIDE - 1))
	placed += 1
	_pieces_in_map += 1


## This kind's list, safe to change: what undo holds is never touched.
func _editable(kit: String) -> PackedFloat32Array:
	if not _copied.has(kit):
		_copied[kit] = true
		_working[kit] = _working[kit].duplicate() if _working.has(kit) else PackedFloat32Array()
	return _working[kit]


## The clump this spot belongs to, from the world's pattern: which cell's middle is nearest, how far out
## from it this spot is, and the kinds that cell likes.
func _clump_at(at: Vector3, normal: Vector3) -> Dictionary:
	var size: float = maxf(_recipe["clump_size"], 0.5)
	# On a wall, the pattern is laid out on the wall.
	var flat := Vector2(at.x, at.z)
	var facing := normal.abs()
	if facing.x > facing.y and facing.x > facing.z:
		flat = Vector2(at.y, at.z)
	elif facing.z > facing.y:
		flat = Vector2(at.x, at.y)
	flat /= size
	# Bends the pattern, so that a clump's edge wanders.
	flat += Vector2(sin(flat.y * 2.3), cos(flat.x * 2.1)) * 0.14
	var seed_number: int = _recipe["seed"]
	var home := Vector2i(floori(flat.x), floori(flat.y))
	var nearest := INF
	var cell := home
	for x in range(home.x - 1, home.x + 2):
		for y in range(home.y - 1, home.y + 2):
			var middle := Vector2(x + _cell_random(x, y, seed_number, 1), y + _cell_random(x, y, seed_number, 2))
			var away := flat.distance_squared_to(middle)
			if away < nearest:
				nearest = away
				cell = Vector2i(x, y)
	var reach := lerpf(0.32, 0.62, _cell_random(cell.x, cell.y, seed_number, 3))
	return {
		"out": sqrt(nearest) / reach,
		"empty": _cell_random(cell.x, cell.y, seed_number, 4) < 0.18,
		"main": _cell_random(cell.x, cell.y, seed_number, 5),
		"second": _cell_random(cell.x, cell.y, seed_number, 6),
	}


## A repeatable random number from 0 to 1 for a cell of the world's pattern.
static func _cell_random(x: int, y: int, seed_number: int, salt: int) -> float:
	const WORD := 0xFFFFFFFF
	var mixed := (x * 0x9E3779B9 + y * 0x85EBCA6B + seed_number * 0xC2B2AE35 + salt * 0x27D4EB2F) & WORD
	mixed ^= mixed >> 16
	mixed = (mixed * 0x7FEB352D) & WORD
	mixed ^= mixed >> 15
	mixed = (mixed * 0x846CA68B) & WORD
	mixed ^= mixed >> 16
	return float(mixed >> 8) / float(1 << 24)


func _fill_spacing() -> void:
	_spacing.clear()
	_widest_spread = 0.0
	for kit: String in _working:
		var values := _working[kit]
		var info := Kit.info(kit)
		for index in values.size() / Kit.STRIDE:
			var first := index * Kit.STRIDE
			var at := Vector3(values[first], values[first + 1], values[first + 2])
			_note_spacing(at, info["radius"] * values[first + 7], info["solid"])


func _note_spacing(at: Vector3, spread: float, solid: bool) -> void:
	var cell := Vector3i(floori(at.x / SPACING_CELL), floori(at.z / SPACING_CELL), 1 if solid else 0)
	var list: PackedFloat32Array = _spacing.get(cell, PackedFloat32Array())
	list.append_array(PackedFloat32Array([at.x, at.y, at.z, spread]))
	_spacing[cell] = list
	_widest_spread = maxf(_widest_spread, spread)


## Whether a piece spreading `spread` can stand at `at` without crowding its neighbours.
func _has_room(at: Vector3, spread: float, solid: bool) -> bool:
	var apart: float = SPACING_AT_THICKNESS / sqrt(maxf(_recipe["thick"], 0.001))
	var furthest := maxf(apart, (spread + _widest_spread) * CROWDING)
	var cells := ceili(furthest / SPACING_CELL)
	var home_x := floori(at.x / SPACING_CELL)
	var home_z := floori(at.z / SPACING_CELL)
	for x in range(home_x - cells, home_x + cells + 1):
		for z in range(home_z - cells, home_z + cells + 1):
			var list: PackedFloat32Array = _spacing.get(Vector3i(x, z, 1 if solid else 0), PackedFloat32Array())
			for first in range(0, list.size(), 4):
				var other := Vector3(list[first], list[first + 1], list[first + 2])
				var keep := maxf(apart, (spread + list[first + 3]) * CROWDING)
				if at.distance_squared_to(other) < keep * keep:
					return false
	return true


func _erase_around(centre: Vector3) -> void:
	var wide: float = _recipe["wide"]
	var reach := wide * wide
	var kinds := {}
	if _only_mix:
		for entry in _recipe["mix"]:
			kinds[entry["kit"]] = true
	for kit: String in _working.keys():
		if _only_mix and not kinds.has(kit):
			continue
		var values := _working[kit]
		var gone := PackedInt32Array()
		for index in values.size() / Kit.STRIDE:
			var first := index * Kit.STRIDE
			if centre.distance_squared_to(Vector3(values[first], values[first + 1], values[first + 2])) <= reach:
				gone.append(index)
		if gone.is_empty():
			continue
		removed += gone.size()
		_pieces_in_map -= gone.size()
		var kept := _without(values, gone)
		_copied[kit] = true
		if kept.is_empty():
			_working.erase(kit)
		else:
			_working[kit] = kept
		_map.show_kind(kit, kept)
	if _hand_erase:
		_erase_hand_placed(centre, reach, kinds)


## `values` less the pieces at `gone`, which runs low to high.
static func _without(values: PackedFloat32Array, gone: PackedInt32Array) -> PackedFloat32Array:
	var kept := PackedFloat32Array()
	var from := 0
	for index in gone:
		kept.append_array(values.slice(from, index * Kit.STRIDE))
		from = (index + 1) * Kit.STRIDE
	kept.append_array(values.slice(from))
	return kept


func _erase_hand_placed(centre: Vector3, reach: float, kinds: Dictionary) -> void:
	for found in MapExporter.kit_pieces(_map):
		var node: Node3D = found["node"]
		if not node.visible or node in _hand_erased or (_only_mix and not kinds.has(found["kit"])):
			continue
		if centre.distance_squared_to(node.global_position) <= reach:
			# Hidden until the stroke ends, when undo takes it out of the scene properly.
			node.visible = false
			_hand_erased.append(node)
			removed += 1
			_pieces_in_map -= 1


## Whether something else, such as undo, has changed the map's pieces since this stroke began, so that
## what it holds no longer follows on from them.
func lost_its_place() -> bool:
	return not is_same(_map.painted, _working)


## Drops the stroke without a step of undo, and leaves the map's pieces as they now are.
func abandon() -> void:
	for node in _hand_erased:
		node.visible = true
	_hand_erased.clear()


## Ends the stroke as one step of `history`, a plain UndoRedo or the editor's. Gives back the number of
## pieces it changed.
func finish(history: Object, words: String) -> int:
	if placed == 0 and removed == 0:
		_map.set_painted_quietly(_before)
		return 0
	history.create_action(words)
	history.add_do_property(_map, "painted", _working)
	history.add_undo_property(_map, "painted", _before)
	# Lowest place first on the way back, so that each goes where it was with those before it home already.
	_hand_erased.sort_custom(func(one: Node, other: Node) -> bool: return one.get_index() < other.get_index())
	for node in _hand_erased:
		node.visible = true
		var parent := node.get_parent()
		_on_do(history, parent, "remove_child", [node])
		_on_undo(history, parent, "add_child", [node])
		_on_undo(history, parent, "move_child", [node, node.get_index()])
		_on_undo(history, node, "set_owner", [node.owner])
		history.add_undo_reference(node)
	if not _hand_erased.is_empty():
		_on_do(history, _map, "notify_pieces_changed", [])
		_on_undo(history, _map, "notify_pieces_changed", [])
	history.commit_action()
	return placed + removed


## The editor's history takes an object and a method's name, and a plain UndoRedo takes a Callable.
static func _on_do(history: Object, target: Object, method: String, arguments: Array) -> void:
	if history is UndoRedo:
		history.add_do_method(Callable(target, method).bindv(arguments))
	else:
		history.callv("add_do_method", [target, method] + arguments)


static func _on_undo(history: Object, target: Object, method: String, arguments: Array) -> void:
	if history is UndoRedo:
		history.add_undo_method(Callable(target, method).bindv(arguments))
	else:
		history.callv("add_undo_method", [target, method] + arguments)
