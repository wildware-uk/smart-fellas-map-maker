@tool
extends RefCounted
## The Populate button: dresses a whole map in one step of undo. Rocks first, then coral on rock, grass and
## shells on the sand, kelp in the deep, anemones in the shelter of the rocks, then food and fish. The same
## seed on the same map gives the same result.
##
## It only adds, or redoes its own work: what it added is noted on the map, and all else stays. A marker of
## its own that has since been moved counts as placed by hand.

const Brush := preload("brush.gd")
const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const Recipes := preload("recipes.gd")
const SurfaceFinder := preload("surface_finder.gd")

## What it paints, in this order, because each grows on what came before. "recipe" is a brush recipe's name,
## "per_100" how many pieces it aims for in 100 square metres, "where" how it picks spots, and "wide" how
## far the brush reaches at each and how thick it paints: less than the recipes do by hand, so that the
## pieces spread over the whole map and not over a few spots. Where: anywhere; on a rock; in the deep, the
## lowest of a few tries, or the farthest out if it's all one height; or sheltered, in the sand beside a rock.
## "grows" is how much bigger its pieces get on a map too big to dress all over, as GROWS_ON_BIG_MAPS says.
const LAYERS := [
	{"recipe": "Rock rubble", "per_100": 2.5, "where": "anywhere", "wide": 2.5, "thick": 0.4, "keep_clear": true, "grows": 2.5},
	{"recipe": "Coral on rock", "per_100": 12.0, "where": "on_rock", "wide": 1.5, "thick": 2.5},
	{"recipe": "Sand garden", "per_100": 28.0, "where": "anywhere", "wide": 2.5, "thick": 1.5},
	{"recipe": "Kelp bed", "per_100": 5.0, "where": "deep", "wide": 3.0, "thick": 0.6},
	{"recipe": "Anemone patch", "per_100": 2.0, "where": "sheltered", "wide": 1.5, "thick": 1.0},
]
## The most it adds in all, under where the cost meter turns amber, leaving room to work by hand.
const MOST_PIECES := 3000
## How many spots a layer may try for each piece it aims for, so that a map with nowhere to grow gives up.
const SPOTS_PER_PIECE := 2.0
const FEWEST_SPOTS := 40
const TRIES_FOR_THE_DEEP := 8
## How far the edge of a rock keeps from a spawn point or food, in metres.
const KEEP_CLEAR := 2.0
## How much of the map's width it leaves out at the edge.
const EDGE_SHARE := 0.95
## The markers it adds: how many square metres to each, and how far apart food patches keep, as a share of
## the map's half width.
const SQUARE_METRES_A_PATCH := 600.0
const SQUARE_METRES_A_FISH := 450.0
const PATCHES_APART := 0.35
const MARKER_TRIES := 40
## How much of what it aims for must land before it stops being worth a mention.
const FELL_SHORT := 0.75
## A map too big for its share of pieces to cover it all is dressed in gardens: round patches as thick as
## this share of a small map's, with open sand between, so that it looks dressed and not thin. The less of
## the map they cover, the bigger the pieces grow, up to a layer's "grows", or this.
const GARDEN_THICKNESS := 0.6
const GROWS_ON_BIG_MAPS := 1.3
## How wide a garden is, as a share of the map's half width, and the least and most, in metres. How many
## tries each gets to keep two gardens apart.
const GARDEN_SHARE := 0.12
const GARDEN_RADII := Vector2(10.0, 20.0)
const GARDEN_TRIES := 20


## Dresses `map` from `seed_number`, as one step of `history`, a plain UndoRedo or the editor's. Gives back
## {"pieces", "markers", "words"}: what it added, and that in plain words.
static func dress(map: SmartFellasMap, seed_number: int, history: Object) -> Dictionary:
	return _redo(map, seed_number, history, LAYERS, "Populate the map")


## Takes away what it added, as one step of `history`, and leaves all else.
static func clear(map: SmartFellasMap, history: Object) -> Dictionary:
	return _redo(map, 0, history, [], "Clear what Populate added")


static func _redo(map: SmartFellasMap, seed_number: int, history: Object, layers: Array, words: String) -> Dictionary:
	var before_painted := map.painted
	var before_own := map.populated
	var old_markers := _own_markers(map)
	var base := _without_own(map.painted, map.populated)
	map.set_painted_quietly(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number
	var finder := SurfaceFinder.new(map)
	var scale := _budget_scale(map)
	var cover := minf(scale / GARDEN_THICKNESS, 1.0)
	var gardens := _gardens(map, cover, rng)
	var aimed := 0
	var landed := 0
	for layer: Dictionary in layers:
		var result := _paint_layer(map, layer, seed_number, scale, cover, gardens, rng, finder)
		aimed += result.x
		landed += result.y
	var own := _added_since(base, map.painted)
	var new_markers: Array[Marker3D] = []
	if not layers.is_empty():
		new_markers = _new_markers(map, old_markers, rng, finder)
	var after_painted := map.painted
	history.create_action(words)
	history.add_do_property(map, "painted", after_painted)
	history.add_undo_property(map, "painted", before_painted)
	history.add_do_property(map, "populated", own)
	history.add_undo_property(map, "populated", before_own)
	for marker in old_markers:
		Brush._on_do(history, map, "remove_child", [marker])
		Brush._on_undo(history, map, "add_child", [marker])
		Brush._on_undo(history, marker, "set_owner", [map])
		history.add_undo_reference(marker)
	for marker in new_markers:
		Brush._on_do(history, map, "add_child", [marker, true])
		Brush._on_do(history, marker, "set_owner", [map])
		Brush._on_undo(history, map, "remove_child", [marker])
		history.add_do_reference(marker)
	Brush._on_do(history, map, "notify_pieces_changed", [])
	Brush._on_undo(history, map, "notify_pieces_changed", [])
	map.set_painted_quietly(before_painted)
	history.commit_action()
	var pieces := 0
	for kit: String in own:
		pieces += own[kit].size() / Kit.STRIDE
	var said := "Took away what Populate added."
	if not layers.is_empty():
		said = "Added %d pieces, %d food patches and fish. Press undo to take them back." % [pieces, new_markers.size()]
		if landed < aimed * FELL_SHORT:
			said += " It aimed for %d, since ground too steep for a recipe stays bare." % aimed
	return {"pieces": pieces, "markers": new_markers.size(), "words": said}


## Less than one on a map so big that its share would pass MOST_PIECES.
static func _budget_scale(map: SmartFellasMap) -> float:
	var per_100 := 0.0
	for layer: Dictionary in LAYERS:
		per_100 += layer["per_100"]
	var wanted := per_100 * (_area_of(map) / 100.0)
	return minf(1.0, MOST_PIECES / wanted)


static func _area_of(map: SmartFellasMap) -> float:
	var width: float = map.half_width * 2.0
	return width * width


## Round patches to dress, as (x, z, radius), covering about `cover` of the map, or none if it all gets dressed.
static func _gardens(map: SmartFellasMap, cover: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var gardens := PackedVector3Array()
	if cover >= 1.0:
		return gardens
	var radius := clampf(map.half_width * GARDEN_SHARE, GARDEN_RADII.x, GARDEN_RADII.y)
	var count := maxi(ceili(cover * _area_of(map) / (PI * radius * radius)), 1)
	var reach: float = map.half_width * EDGE_SHARE - radius * 0.5
	for _garden in count:
		var best := Vector3(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach), radius)
		for _try in GARDEN_TRIES:
			if _clear_of_gardens(best, gardens):
				break
			best = Vector3(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach), radius)
		gardens.append(best)
	return gardens


static func _clear_of_gardens(garden: Vector3, gardens: PackedVector3Array) -> bool:
	for other in gardens:
		if Vector2(garden.x, garden.y).distance_to(Vector2(other.x, other.y)) < garden.z + other.z:
			return false
	return true


## Gives back how many pieces it aimed for and how many it placed, as (x, y).
static func _paint_layer(map: SmartFellasMap, layer: Dictionary, seed_number: int, scale: float, cover: float, gardens: PackedVector3Array, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Vector2i:
	var recipes := Recipes.all()
	if not recipes.has(layer["recipe"]):
		return Vector2i.ZERO
	var recipe: Dictionary = recipes[layer["recipe"]].duplicate(true)
	recipe["seed"] = clampi(seed_number + 1, Recipes.SEEDS.x, Recipes.SEEDS.y)
	var growth := lerpf(1.0, layer.get("grows", GROWS_ON_BIG_MAPS), 1.0 - cover)
	var biggest: float = Recipes.RANGES["size_high"].y
	recipe["size_low"] = minf(recipe["size_low"] * growth, biggest)
	recipe["size_high"] = minf(recipe["size_high"] * growth, biggest)
	recipe["wide"] = layer["wide"] * growth
	recipe["thick"] = layer["thick"] / (growth * growth)
	if Brush.why_it_cant_paint(map, recipe) != "":
		return Vector2i.ZERO
	var brush := Brush.new()
	brush.draws_as_it_goes = false
	brush.start_painting(map, recipe, seed_number + LAYERS.find(layer), finder)
	var aim := roundi(layer["per_100"] * (_area_of(map) / 100.0) * scale)
	var spots := maxi(roundi(aim * SPOTS_PER_PIECE), FEWEST_SPOTS)
	for _spot in spots:
		if brush.placed >= aim or not brush.stopped_because.is_empty():
			break
		var hit := _pick_spot(map, layer, recipe["wide"] + _widest_reach(recipe) + KEEP_CLEAR, gardens, rng, finder)
		if not hit.is_empty():
			brush.hold_at(hit["at"], hit["normal"])
	return Vector2i(aim, brush.placed)


## A spot for this layer, as SurfaceFinder.find gives it, or nothing if this try found none.
## `keep_clear` is how far from a marker the spot stays, if the layer keeps clear of them: how far its brush
## reaches, how far its biggest piece reaches past that, and room to spare.
static func _pick_spot(map: SmartFellasMap, layer: Dictionary, keep_clear: float, gardens: PackedVector3Array, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	match layer["where"]:
		"on_rock":
			return _on_a_rock(map, rng, finder)
		"sheltered":
			return _beside_a_rock(map, rng, finder)
		"deep":
			return _in_the_deep(map, gardens, rng, finder)
	var hit := _in_a_garden(map, gardens, rng, finder)
	if layer.get("keep_clear", false) and not hit.is_empty() and _near_a_marker(map, hit["at"], keep_clear):
		return {}
	return hit


static func _ray_down(map: SmartFellasMap, x: float, z: float, finder: SurfaceFinder) -> Dictionary:
	var top: float = finder.sand_height + map.ceiling + MapExporter.SCENERY_BEYOND
	return finder.find(Vector3(x, top, z), Vector3(x, finder.sand_height - 1.0, z))


static func _anywhere(map: SmartFellasMap, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	var reach: float = map.half_width * EDGE_SHARE
	return _ray_down(map, rng.randf_range(-reach, reach), rng.randf_range(-reach, reach), finder)


## How far the biggest piece this recipe can paint reaches from its middle, in metres.
static func _widest_reach(recipe: Dictionary) -> float:
	var widest := 0.0
	for entry: Dictionary in recipe["mix"]:
		if Kit.has(entry["kit"]):
			widest = maxf(widest, Kit.info(entry["kit"])["radius"] * recipe["size_high"])
	return widest


## Anywhere in one of the gardens, or anywhere at all if there are none.
static func _in_a_garden(map: SmartFellasMap, gardens: PackedVector3Array, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	if gardens.is_empty():
		return _anywhere(map, rng, finder)
	var garden := gardens[rng.randi_range(0, gardens.size() - 1)]
	var angle := rng.randf() * TAU
	var out := sqrt(rng.randf()) * garden.z
	var reach: float = map.half_width * EDGE_SHARE
	var x := clampf(garden.x + cos(angle) * out, -reach, reach)
	var z := clampf(garden.y + sin(angle) * out, -reach, reach)
	return _ray_down(map, x, z, finder)


static func _in_the_deep(map: SmartFellasMap, gardens: PackedVector3Array, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	var best := {}
	for _try in TRIES_FOR_THE_DEEP:
		var hit := _in_a_garden(map, gardens, rng, finder)
		if hit.is_empty():
			continue
		if best.is_empty() or _is_deeper(hit["at"], best["at"]):
			best = hit
	return best


static func _is_deeper(one: Vector3, other: Vector3) -> bool:
	if absf(one.y - other.y) > 0.01:
		return one.y < other.y
	return Vector2(one.x, one.z).length() > Vector2(other.x, other.z).length()


static func _on_a_rock(map: SmartFellasMap, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	if not finder.has_rock():
		return {}
	var box := finder.rock_box(rng.randi_range(0, finder.rock_count() - 1))
	var hit := _ray_down(map, rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.z, box.end.z), finder)
	return hit if not hit.is_empty() and hit["on"] == "rock" else {}


static func _beside_a_rock(map: SmartFellasMap, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	if not finder.has_rock():
		return {}
	var box := finder.rock_box(rng.randi_range(0, finder.rock_count() - 1))
	var middle := box.get_center()
	var out := maxf(box.size.x, box.size.z) * 0.5 + rng.randf_range(0.3, 1.5)
	var angle := rng.randf() * TAU
	var x := middle.x + cos(angle) * out
	var z := middle.z + sin(angle) * out
	if absf(x) > map.half_width or absf(z) > map.half_width:
		return {}
	var hit := _ray_down(map, x, z, finder)
	return hit if not hit.is_empty() and hit["on"] == "sand" else {}


static func _near_a_marker(map: SmartFellasMap, at: Vector3, within: float) -> bool:
	for child in map.get_children():
		var marker := child as Marker3D
		if marker != null and marker.global_position.distance_to(at) < within:
			return true
	return false


## New food patches and fish, not yet in the map. Those of its own that are going don't count against room.
static func _new_markers(map: SmartFellasMap, going: Array[Marker3D], rng: RandomNumberGenerator, finder: SurfaceFinder) -> Array[Marker3D]:
	var made: Array[Marker3D] = []
	var taken: Array[Vector3] = []
	var patches_held := 0
	for marker in MarkerKinds.markers_of(map, "food_patch"):
		if not marker in going:
			taken.append((marker as Node3D).global_position)
			patches_held += 1
	var patches := maxi(mini(roundi(_area_of(map) / SQUARE_METRES_A_PATCH), MapExporter.MOST_PATCHES) - patches_held, 0)
	var apart: float = map.half_width * PATCHES_APART
	for _patch in patches:
		var hit := _spot_for_food(map, taken, apart, rng, finder)
		if not hit.is_empty():
			taken.append(hit["at"])
			_add_marker(map, "food_patch", hit["at"], hit["normal"], made)
	var fish_held := 0
	for kind: String in ["fish_flounder", "fish_lionfish"]:
		for marker in MarkerKinds.markers_of(map, kind):
			if not marker in going:
				fish_held += 1
	var fish := mini(roundi(_area_of(map) / SQUARE_METRES_A_FISH), MapExporter.MOST_FISH - fish_held)
	for index in fish:
		if index % 2 == 0:
			var hit := _anywhere(map, rng, finder)
			if not hit.is_empty() and hit["on"] == "sand":
				_add_marker(map, "fish_flounder", hit["at"], Vector3.UP, made)
		else:
			var hit := _beside_a_rock(map, rng, finder)
			if not hit.is_empty():
				_add_marker(map, "fish_lionfish", hit["at"], Vector3.UP, made)
	return made


## Open sand for a patch with room for its ring of food, away from others, or nothing if it finds none.
static func _spot_for_food(map: SmartFellasMap, taken: Array[Vector3], apart: float, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	var reach: float = map.half_width - MapExporter.SPOT_RING - 0.1
	for _try in MARKER_TRIES:
		var hit := _ray_down(map, rng.randf_range(-reach, reach), rng.randf_range(-reach, reach), finder)
		if hit.is_empty() or hit["on"] != "sand":
			continue
		var at: Vector3 = hit["at"]
		var clear := true
		for other in taken:
			clear = clear and other.distance_to(at) >= apart
		if clear:
			return hit
	return {}


## A marker with a number of its own among those already made in this go.
static func _add_marker(map: SmartFellasMap, kind: String, at: Vector3, normal: Vector3, made: Array[Marker3D]) -> void:
	var marker := MarkerKinds.new_marker(map, kind, at, normal)
	var prefix: String = MarkerKinds.KINDS[kind]["prefix"]
	var number := String(marker.name).trim_prefix(prefix).to_int()
	for other in made:
		if String(other.name).begins_with(prefix):
			number += 1
	marker.name = "%s%d" % [prefix, number]
	marker.set_meta(MarkerKinds.OWN_MARK, marker.transform.origin)
	made.append(marker)


## The markers it put on the map and that are still where it put them.
static func _own_markers(map: SmartFellasMap) -> Array[Marker3D]:
	var own: Array[Marker3D] = []
	for child in map.get_children():
		var marker := child as Marker3D
		if marker != null and marker.has_meta(MarkerKinds.OWN_MARK) and marker.position.distance_to(marker.get_meta(MarkerKinds.OWN_MARK)) < MarkerKinds.STILL_THERE:
			own.append(marker)
	return own


## The map's painted pieces, less any that it added.
static func _without_own(painted: Dictionary[String, PackedFloat32Array], own: Dictionary[String, PackedFloat32Array]) -> Dictionary[String, PackedFloat32Array]:
	var left: Dictionary[String, PackedFloat32Array] = painted.duplicate()
	for kit: String in own:
		if not left.has(kit):
			continue
		var mine := {}
		var own_values := own[kit]
		for first in range(0, own_values.size(), Kit.STRIDE):
			mine[_piece_key(own_values, first)] = true
		var kept := PackedFloat32Array()
		var values: PackedFloat32Array = left[kit]
		for first in range(0, values.size(), Kit.STRIDE):
			if not mine.has(_piece_key(values, first)):
				kept.append_array(values.slice(first, first + Kit.STRIDE))
		if kept.is_empty():
			left.erase(kit)
		else:
			left[kit] = kept
	return left


static func _piece_key(values: PackedFloat32Array, first: int) -> Vector4:
	return Vector4(values[first], values[first + 1], values[first + 2], values[first + 6])


## What's in `now` past where each kind's list stood in `base`, as a brush only adds to the end.
static func _added_since(base: Dictionary[String, PackedFloat32Array], now: Dictionary[String, PackedFloat32Array]) -> Dictionary[String, PackedFloat32Array]:
	var added: Dictionary[String, PackedFloat32Array] = {}
	for kit: String in now:
		var had: int = base[kit].size() if base.has(kit) else 0
		if now[kit].size() > had:
			added[kit] = now[kit].slice(had)
	return added
