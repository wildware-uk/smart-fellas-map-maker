@tool
extends RefCounted
## The Populate button: dresses a whole map in one step of undo, with the groups ticked for it. Scenery:
## rocks first, then coral on rock and on its walls and overhangs, grass and shells on the sand, kelp in the
## deep, anemones in the shelter of the rocks. Food: food patches. Creatures: fish, stingray stops and wrasse
## spots. Spawns: spawn points for a team that has none. The same seed on the same map gives the same
## result. It dresses a map made only of pieces and models of its own, with no seabed, the same way:
## on one with little or no sand showing, what grows on sand grows on the floors of the rock as well, and
## it keeps to the play area however far the map's own meshes reach.
##
## It only adds, or redoes its own work in the groups ticked: what it added is noted on the map, and all else
## stays. A marker of its own that has since been moved counts as placed by hand.

const Brush := preload("brush.gd")
const Kit := preload("kit.gd")
const PopulateGroups := preload("populate_groups.gd")
const MapExporter := preload("map_exporter.gd")
const MarkerKinds := preload("marker_kinds.gd")
const Recipes := preload("recipes.gd")
const SurfaceFinder := preload("surface_finder.gd")
const Zone := preload("populate_zone.gd")

## How far over the map's ceiling a ray looking for the ground starts, in metres: over the tallest thing
## standing above the play area.
const RAY_HEADROOM := 60.0

## What it paints, in this order, because each grows on what came before. "recipe" is a brush recipe's name,
## "per_100" how many pieces it aims for in 100 square metres, "where" how it picks spots, and "wide" how
## far the brush reaches at each and how thick it paints: less than the recipes do by hand, so that the
## pieces spread over the whole map and not over a few spots. Where: anywhere; on a rock; in the deep, the
## lowest of a few tries, or the farthest out if it's all one height; or sheltered, in the sand beside a rock.
## "grows" is how much bigger its pieces get on a map too big to dress all over, as GROWS_ON_BIG_MAPS says.
const LAYERS := [
	{"recipe": "Rock rubble", "per_100": 2.5, "where": "anywhere", "wide": 2.5, "thick": 0.4, "keep_clear": true, "grows": 2.5},
	{"recipe": "Coral on rock", "per_100": 12.0, "where": "on_rock", "wide": 1.5, "thick": 2.5},
	{"recipe": "Coral on walls", "per_100": 3.0, "where": "on_walls", "wide": 1.0, "thick": 2.0},
	{"recipe": "Sand garden", "per_100": 28.0, "where": "anywhere", "wide": 2.5, "thick": 1.5},
	{"recipe": "Kelp bed", "per_100": 5.0, "where": "deep", "wide": 3.0, "thick": 0.6},
	{"recipe": "Anemone patch", "per_100": 2.0, "where": "sheltered", "wide": 1.5, "thick": 1.0},
]
## The most it adds in all, under where the cost meter turns amber, leaving room to work by hand, and the
## most of that that zones growing thicker may take.
const MOST_PIECES := 3000
const MOST_FOR_ZONES := 1500
## How many of the most a map holds it leaves free, for the map maker to paint by hand after: about, as a
## brush may place a few past its aim with its last hold.
const HAND_ROOM := 500
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
## How many spots on the pieces' surfaces one try may look at, for one that suits the layer.
const TRIES_ON_MESHES := 8
## How far up a surface may face and still count as floor, as the up of its facing: about 37 degrees.
const FLOOR_LIKE := 0.8
## On a map with less than this share of sand among its sand and its own meshes, seen from above, what grows
## on sand grows on the floors of the rock and the map's own meshes as well, and food and fish go there: an
## imported map's ground is its own meshes, with the seabed hidden under them. Kit rock doesn't count, as
## _sand_share says. It looks down this many rays a side to see.
const SCARCE_SAND := 0.25
const SAND_RAYS := 16
## The widest a piece may be, in metres, for what shelters beside a rock to shelter beside it: a rock or a
## wreck, and not a map's whole ground.
const SHELTER_WIDEST := 12.0
## Spawn points it adds for a team that has none: how many, how much open water each has above it, how far
## apart a team's keep, and how far they keep from where an eel, a groper or an anglerfish lies in wait.
const SPAWNS_A_TEAM := 4
const ROOM_ABOVE := 3.0
const SPAWNS_APART := 6.0
const CLEAR_OF_CREATURES := 8.0
const CREATURE_KINDS := ["eel_hole", "groper_hole", "angler"]
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
## The group of each kind of marker it adds. The groups themselves are in populate_groups.gd.
const GROUP_OF_KIND := {
	"food_patch": "food",
	"fish_flounder": "creatures", "fish_lionfish": "creatures", "stingray": "creatures", "wrasse": "creatures",
	"spawn_octopus": "spawns", "spawn_diver": "spawns",
}
## Scenery alone, so that markers a map maker places by hand are never Populate's to redo.
const FIRST_GROUPS: Dictionary[String, bool] = {"scenery": true, "food": false, "creatures": false, "spawns": false}
## How many square metres to each stingray stop and wrasse spot it adds, and the fewest and most of each.
const SQUARE_METRES_A_HAUNT := 1500.0
const HAUNTS_A_KIND := Vector2i(2, 6)


## Dresses `map` from `seed_number`, as one step of `history`, a plain UndoRedo or the editor's, on
## `surfaces`: "both", "seabed" or "meshes", as Recipes.SURFACES, with the `groups` ticked, as
## PopulateGroups.GROUPS names them. Gives back {"pieces", "markers", "words"}: what it added, and that in plain words.
static func dress(map: SmartFellasMap, seed_number: int, history: Object, surfaces := "both", groups: Dictionary[String, bool] = FIRST_GROUPS) -> Dictionary:
	return _redo(map, seed_number, history, true, "Populate the map", surfaces, groups)


## Takes away what it added in the `groups` ticked, as one step of `history`, and leaves all else.
static func clear(map: SmartFellasMap, history: Object, groups: Dictionary[String, bool] = FIRST_GROUPS) -> Dictionary:
	return _redo(map, 0, history, false, "Clear what Populate added", "both", groups)


static func _redo(map: SmartFellasMap, seed_number: int, history: Object, adding: bool, words: String, surfaces: String, groups: Dictionary[String, bool]) -> Dictionary:
	var ticked: Array[String] = []
	for group: String in PopulateGroups.GROUPS:
		if groups.get(group, false):
			ticked.append(group)
	if ticked.is_empty():
		return {"pieces": 0, "markers": 0, "words": "Nothing is ticked, so nothing changed. Tick Scenery, Food, Creatures or Spawns."}
	var scenery := "scenery" in ticked
	var before_painted := map.painted
	var before_own := map.populated
	var old_markers: Array[Marker3D] = []
	old_markers.assign(_own_markers(map).filter(func(marker: Marker3D) -> bool: return GROUP_OF_KIND.get(MarkerKinds.kind_of(marker.name), "") in ticked))
	var base := _without_own(map.painted, map.populated) if scenery else map.painted
	map.set_painted_quietly(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number
	var finder := SurfaceFinder.new(map, Recipes.SURFACES.find(surfaces))
	var sand_share := _sand_share(map, finder if surfaces == "both" else SurfaceFinder.new(map))
	finder.rock_floors_are_open = not finder.has_any_sand() or sand_share < SCARCE_SAND
	var zones := Zone.zones_in(map)
	var aimed := 0
	var landed := 0
	# A map holds MapExporter.MOST_PIECES at most, and what's there already stays.
	var room := MapExporter.MOST_PIECES - MapExporter.kit_pieces(map).size() - map.painted_count()
	var budget := clampi(room - HAND_ROOM, 0, MOST_PIECES)
	# Whether the room left made it aim for fewer than it would on an empty map of this size.
	var held_back := false
	if adding and scenery:
		var thicker := _thicker_aims(map, zones, mini(MOST_FOR_ZONES, budget / 2))
		var for_zones := 0
		for layer: String in thicker:
			for_zones += thicker[layer]
		var scale := _budget_scale(map, budget - for_zones)
		var free_for_zones := 0
		var free_thicker := _thicker_aims(map, zones, MOST_FOR_ZONES)
		for layer: String in free_thicker:
			free_for_zones += free_thicker[layer]
		held_back = for_zones < free_for_zones or scale < _budget_scale(map, MOST_PIECES - free_for_zones)
		var cover := minf(scale / GARDEN_THICKNESS, 1.0)
		var gardens := _gardens(map, cover, rng)
		for layer: Dictionary in LAYERS:
			var plan := {"scale": scale, "cover": cover, "gardens": gardens, "zones": zones, "thicker": thicker.get(layer["recipe"], 0)}
			var result := _paint_layer(map, layer, seed_number, plan, rng, finder, surfaces)
			aimed += result.x
			landed += result.y
	var own := _added_since(base, map.painted) if scenery else before_own
	var new_markers: Array[Marker3D] = []
	if adding:
		new_markers = _new_markers(map, old_markers, rng, finder, ticked, zones)
	var after_painted := map.painted
	history.create_action(words)
	if scenery:
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
	if scenery:
		for kit: String in own:
			pieces += own[kit].size() / Kit.STRIDE
	var names: Array[String] = []
	for group in ticked:
		names.append(PopulateGroups.GROUP_WORDS[group])
	var said := "Took away what Populate added in %s." % _listed(names)
	if adding:
		var parts: Array[String] = []
		if scenery:
			parts.append("%d pieces of scenery" % pieces)
		var counts := {}
		for marker in new_markers:
			var kind := MarkerKinds.kind_of(marker.name)
			counts[kind] = counts.get(kind, 0) + 1
		for kind: String in counts:
			var called := (MarkerKinds.KINDS[kind]["words"] as String).to_lower()
			# One lionfish, two lionfish.
			parts.append("%d %s" % [counts[kind], _plural(called, counts[kind])])
		said = "Added %s. Press undo to take them back." % (_listed(parts) if not parts.is_empty() else "nothing")
		var there := MapExporter.MOST_PIECES - room
		if scenery and budget == 0:
			said += " The map is too full for more scenery: a map holds %d pieces at most, %d were there already, and Populate keeps about %d free for you to paint by hand." % [MapExporter.MOST_PIECES, there, HAND_ROOM]
		elif scenery and held_back:
			said += " The map was nearly full, so it added fewer: a map holds %d pieces at most, %d were there already, and Populate keeps about %d free for you to paint by hand." % [MapExporter.MOST_PIECES, there, HAND_ROOM]
		elif scenery and landed < aimed * FELL_SHORT:
			said += " It aimed for %d pieces, since ground too steep for a recipe stays bare." % aimed
		if "spawns" in ticked and not counts.has("spawn_octopus") and not counts.has("spawn_diver"):
			said += " Each team had spawn points already, so it added none."
		if finder.rock_floors_are_open and finder.has_any_sand():
			var on_floors: Array[String] = []
			if scenery:
				on_floors.append("what grows on sand")
			if "food" in ticked:
				on_floors.append("food")
			if "creatures" in ticked:
				on_floors.append("fish")
			if not on_floors.is_empty():
				said += " Little of this map's floor is sand, so %s went on the floors of your meshes too. To keep %s to your ground, mark it as Sand or Silt under Your own models." % [_listed(on_floors), "it" if on_floors.size() == 1 else "them"]
		# Only scenery always wants to place something; food, fish and spawns may already be enough.
		if scenery and budget > 0 and pieces == 0 and new_markers.is_empty():
			said = _why_nothing_landed(map, finder)
	return {"pieces": pieces, "markers": new_markers.size(), "words": said}


## How much of the floor inside the play area that is sand or the map's own meshes is sand, seen from
## above: from 0 to 1, or 1 with neither. Kit rock, painted or placed by hand, and the seabed's own rock
## don't count: a map built of the kit's rocks keeps what grows on sand on the sand.
static func _sand_share(map: SmartFellasMap, finder: SurfaceFinder) -> float:
	var counted := 0
	var sand := 0
	for hit in _rays_over(map, finder):
		var node: Node = hit["node"]
		if hit["on"] == "sand":
			sand += 1
			counted += 1
		elif not hit["seabed"] and node != null and not node.scene_file_path.begins_with(Kit.FOLDER):
			counted += 1
	return float(sand) / counted if counted > 0 else 1.0


## What rays straight down on a grid over the play area land on, those that land.
static func _rays_over(map: SmartFellasMap, finder: SurfaceFinder) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var middle := _middle(map)
	var reach := _half(map) * EDGE_SHARE
	for row in SAND_RAYS:
		for column in SAND_RAYS:
			var x := lerpf(middle.x - reach.x, middle.x + reach.x, (column + 0.5) / SAND_RAYS)
			var z := lerpf(middle.y - reach.y, middle.y + reach.y, (row + 0.5) / SAND_RAYS)
			var hit := _ray_down(map, x, z, finder)
			if not hit.is_empty():
				hits.append(hit)
	return hits


## Why it added nothing at all, in plain words, and what to do about it.
static func _why_nothing_landed(map: SmartFellasMap, finder: SurfaceFinder) -> String:
	var hits := _rays_over(map, finder)
	if hits.is_empty():
		return "Added nothing. Nothing inside the play area to grow on: it has no seabed, and none of your pieces or meshes reach into it. Tick Seabed in the Map panel, move your meshes into the play area, or drag its edges out over them."
	if not hits.any(func(hit: Dictionary) -> bool: return (hit["normal"] as Vector3).y >= FLOOR_LIKE):
		return "Added nothing. The ground inside the play area is all too steep for anything to grow or stand on."
	return "Added nothing. Every spot it tried was taken, or the map is full. Try again from another seed, or take some pieces away."


## One lionfish, two lionfish; one food patch, two food patches; one spot, two spots.
static func _plural(word: String, count: int) -> String:
	if count == 1 or word.ends_with("fish"):
		return word
	return word + ("es" if word.ends_with("ch") else "s")


## "a", "a and b", or "a, b and c".
static func _listed(words: Array[String]) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words.back()]


## Less than one on a map so big that its share would pass `budget` pieces.
static func _budget_scale(map: SmartFellasMap, budget: int) -> float:
	var per_100 := 0.0
	for layer: Dictionary in LAYERS:
		per_100 += layer["per_100"]
	var wanted := per_100 * (_area_of(map) / 100.0)
	return minf(1.0, budget / wanted)


## How many more pieces each layer aims for in the zones it grows thicker in, by its recipe: as thick as on a
## small map, times the zone's "more", and no more in all than `most`.
static func _thicker_aims(map: SmartFellasMap, zones: Array[Dictionary], most: int) -> Dictionary:
	var wanted := {}
	var total := 0.0
	for layer: Dictionary in LAYERS:
		var pieces := 0.0
		for thicker in Zone.thicker_for(zones, layer["recipe"]):
			var zone: Dictionary = thicker["zone"]
			pieces += layer["per_100"] * thicker["times"] * _zone_area(map, zone) / 100.0
		wanted[layer["recipe"]] = pieces
		total += pieces
	var share := minf(1.0, most / total) if total > 0.0 else 1.0
	var aims := {}
	for recipe: String in wanted:
		if wanted[recipe] > 0.0:
			aims[recipe] = roundi(wanted[recipe] * share)
	return aims


## How many square metres of `zone` lie in the play area, about: its circle, cut to the map's square.
static func _zone_area(map: SmartFellasMap, zone: Dictionary) -> float:
	var at: Vector2 = zone["at"]
	var radius: float = zone["radius"]
	var box := Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0).intersection(_play_square(map))
	return PI * radius * radius * box.get_area() / (radius * radius * 4.0)


## The play area, as seen from above.
static func _play_square(map: SmartFellasMap) -> Rect2:
	var box := map.area_box()
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


static func _area_of(map: SmartFellasMap) -> float:
	return _play_square(map).get_area()


## The play area's middle on the flat, as (x, z).
static func _middle(map: SmartFellasMap) -> Vector2:
	return _play_square(map).get_center()


## How far the play area reaches from its middle along X and along Z.
static func _half(map: SmartFellasMap) -> Vector2:
	return _play_square(map).size * 0.5


## Half the side of a square as big as the play area: what spaces things out by its size.
static func _even_half(map: SmartFellasMap) -> float:
	var half := _half(map)
	return sqrt(half.x * half.y)


## Whether (x, z) is inside the play area's sides.
static func _inside(map: SmartFellasMap, x: float, z: float) -> bool:
	var square := _play_square(map)
	return x >= square.position.x and x <= square.end.x and z >= square.position.y and z <= square.end.y


## `point` kept within `reach` of the play area's middle along X and along Z.
static func _clamp_in(map: SmartFellasMap, point: Vector2, reach: Vector2) -> Vector2:
	var middle := _middle(map)
	return middle + (point - middle).clamp(-reach, reach)


## A place within `reach` of the play area's middle along X and along Z.
static func _random_in(map: SmartFellasMap, reach: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var middle := _middle(map)
	return middle + Vector2(rng.randf_range(-reach.x, reach.x), rng.randf_range(-reach.y, reach.y))


## The highest anyone can swim. An older map's square measured it from the sand; a box's is where it is.
static func _ceiling(map: SmartFellasMap, finder: SurfaceFinder) -> float:
	return map.area_ceiling() + (finder.ceiling_measured_from() if map.play_area() == null else 0.0)


## Round patches to dress, as (x, z, radius), covering about `cover` of the map, or none if it all gets dressed.
static func _gardens(map: SmartFellasMap, cover: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var gardens := PackedVector3Array()
	if cover >= 1.0:
		return gardens
	var radius := clampf(_even_half(map) * GARDEN_SHARE, GARDEN_RADII.x, GARDEN_RADII.y)
	var count := maxi(ceili(cover * _area_of(map) / (PI * radius * radius)), 1)
	var reach := (_half(map) * EDGE_SHARE - Vector2.ONE * radius * 0.5).max(Vector2.ZERO)
	for _garden in count:
		var place := _random_in(map, reach, rng)
		var best := Vector3(place.x, place.y, radius)
		for _try in GARDEN_TRIES:
			if _clear_of_gardens(best, gardens):
				break
			place = _random_in(map, reach, rng)
			best = Vector3(place.x, place.y, radius)
		gardens.append(best)
	return gardens


static func _clear_of_gardens(garden: Vector3, gardens: PackedVector3Array) -> bool:
	for other in gardens:
		if Vector2(garden.x, garden.y).distance_to(Vector2(other.x, other.y)) < garden.z + other.z:
			return false
	return true


## Gives back how many pieces it aimed for and how many it placed, as (x, y).
## `plan` holds the map's "scale" and "cover", as _budget_scale and _gardens use them, its "gardens", its
## "zones", and how many pieces this layer aims for in the zones it grows "thicker" in.
static func _paint_layer(map: SmartFellasMap, layer: Dictionary, seed_number: int, plan: Dictionary, rng: RandomNumberGenerator, finder: SurfaceFinder, surfaces: String) -> Vector2i:
	var scale: float = plan["scale"]
	var cover: float = plan["cover"]
	var gardens: PackedVector3Array = plan["gardens"]
	var zones: Array[Dictionary] = plan["zones"]
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
	recipe["surfaces"] = surfaces
	# With little or no sand, what grows on sand grows on the rock's floors.
	if finder.rock_floors_are_open:
		recipe["on_rock"] = true
	if Brush.why_it_cant_paint(map, recipe) != "":
		return Vector2i.ZERO
	var brush := Brush.new()
	brush.draws_as_it_goes = false
	var called: String = layer["recipe"]
	if not zones.is_empty():
		brush.keeps_out = func(at: Vector3) -> bool: return Zone.keeps_out(zones, called, at.x, at.z)
	brush.start_painting(map, recipe, seed_number + LAYERS.find(layer), finder)
	var thicker: int = plan["thicker"]
	var thicker_in := Zone.thicker_for(zones, called)
	for _spot in maxi(roundi(thicker * SPOTS_PER_PIECE), FEWEST_SPOTS) if thicker > 0 else 0:
		if brush.placed >= thicker or not brush.stopped_because.is_empty():
			break
		var hit := _in_a_zone(map, layer, recipe, thicker_in, rng, finder)
		if not hit.is_empty():
			brush.hold_at(hit["at"], hit["normal"])
	var in_zones := brush.placed
	var aim := roundi(layer["per_100"] * (_area_of(map) / 100.0) * scale)
	var spots := maxi(roundi(aim * SPOTS_PER_PIECE), FEWEST_SPOTS)
	for _spot in spots:
		if brush.placed >= in_zones + aim or not brush.stopped_because.is_empty():
			break
		var hit := _pick_spot(map, layer, recipe, recipe["wide"] + _widest_reach(recipe) + KEEP_CLEAR, gardens, rng, finder)
		if hit.is_empty():
			continue
		var at: Vector3 = hit["at"]
		if not Zone.keeps_out(zones, called, at.x, at.z):
			brush.hold_at(at, hit["normal"])
	return Vector2i(thicker + aim, brush.placed)


## A spot for this layer in one of the zones it grows thicker in, `thicker_in` as Zone.thicker_for gives
## them, picked by how many pieces each wants: on the pieces for what grows on rock, as _on_the_pieces
## looks, else straight down.
static func _in_a_zone(map: SmartFellasMap, layer: Dictionary, recipe: Dictionary, thicker_in: Array[Dictionary], rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	var weights := PackedFloat32Array()
	var total := 0.0
	for thicker in thicker_in:
		total += thicker["times"] * _zone_area(map, thicker["zone"])
		weights.append(total)
	if total <= 0.0:
		return {}
	var pick := rng.randf() * total
	var zone: Dictionary = thicker_in[0]["zone"]
	for index in weights.size():
		if pick <= weights[index]:
			zone = thicker_in[index]["zone"]
			break
	var reach := _half(map) * EDGE_SHARE
	if not layer["where"] in ["on_rock", "on_walls"]:
		var point := _clamp_in(map, Zone.point_in(zone, rng), reach)
		return _ray_down(map, point.x, point.y, finder)
	var at: Vector2 = zone["at"]
	var radius: float = zone["radius"]
	for try in TRIES_ON_MESHES:
		var hit := {}
		if layer["where"] == "on_rock" and try % 2 == 1:
			var point := _clamp_in(map, Zone.point_in(zone, rng), reach)
			hit = _ray_down(map, point.x, point.y, finder)
		else:
			hit = finder.random_spot(rng, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
		if hit.is_empty() or not Brush.lands_on(recipe, hit):
			continue
		var spot: Vector3 = hit["at"]
		if Vector2(spot.x, spot.z).distance_to(at) > radius or not _inside(map, spot.x, spot.z):
			continue
		var slope := rad_to_deg(acos(clampf((hit["normal"] as Vector3).y, -1.0, 1.0)))
		if slope >= recipe["slope_low"] and slope <= recipe["slope_high"]:
			return hit
	return {}


## A spot for this layer, as SurfaceFinder.find gives it, or nothing if this try found none.
## `keep_clear` is how far from a marker the spot stays, if the layer keeps clear of them: how far its brush
## reaches, how far its biggest piece reaches past that, and room to spare.
static func _pick_spot(map: SmartFellasMap, layer: Dictionary, recipe: Dictionary, keep_clear: float, gardens: PackedVector3Array, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	match layer["where"]:
		"on_rock", "on_walls":
			return _on_the_pieces(map, layer, recipe, rng, finder)
		"sheltered":
			return _beside_a_rock(map, rng, finder)
		"deep":
			return _in_the_deep(map, gardens, rng, finder)
	var hit := _in_a_garden(map, gardens, rng, finder)
	if layer.get("keep_clear", false) and not hit.is_empty() and _near_a_marker(map, hit["at"], keep_clear):
		return {}
	return hit


static func _ray_down(map: SmartFellasMap, x: float, z: float, finder: SurfaceFinder) -> Dictionary:
	var top: float
	if map.play_area() == null:
		# An older map's square measured its ceiling from the sand.
		top = maxf(finder.sand_height, finder.ceiling_measured_from()) + map.area_ceiling() + RAY_HEADROOM
	else:
		top = maxf(finder.sand_height, map.area_ceiling()) + RAY_HEADROOM
	var bottom: float = finder.sand_height - 1.0 if finder.has_sand else map.area_box().position.y - 1.0
	return finder.find(Vector3(x, top, z), Vector3(x, bottom, z))


static func _anywhere(map: SmartFellasMap, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	var point := _random_in(map, _half(map) * EDGE_SHARE, rng)
	return _ray_down(map, point.x, point.y, finder)


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
	var point := _clamp_in(map, Vector2(garden.x + cos(angle) * out, garden.y + sin(angle) * out), _half(map) * EDGE_SHARE)
	return _ray_down(map, point.x, point.y, finder)


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


## A spot anywhere on the pieces' surfaces, tops, sides and undersides alike, that the recipe grows on and is
## steep enough or flat enough for, in the map. Every other try for what grows on rock looks straight down
## instead, so that a floor of the map's own reaching far past the play area still gets its share.
static func _on_the_pieces(map: SmartFellasMap, layer: Dictionary, recipe: Dictionary, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	for try in TRIES_ON_MESHES:
		var looks_down: bool = layer["where"] == "on_rock" and try % 2 == 1
		var hit := _anywhere(map, rng, finder) if looks_down else finder.random_spot(rng, _play_square(map))
		if hit.is_empty() or not Brush.lands_on(recipe, hit):
			continue
		var at: Vector3 = hit["at"]
		if not _inside(map, at.x, at.z):
			continue
		var slope := rad_to_deg(acos(clampf((hit["normal"] as Vector3).y, -1.0, 1.0)))
		if slope >= recipe["slope_low"] and slope <= recipe["slope_high"]:
			return hit
	return {}


## Whether `hit` is open ground: sand, or with little or no sand, a floor of the rock.
static func _is_open_ground(hit: Dictionary, finder: SurfaceFinder) -> bool:
	if hit.is_empty():
		return false
	if hit["on"] == "sand":
		return true
	return finder.rock_floors_are_open and (hit["normal"] as Vector3).y >= FLOOR_LIKE


static func _beside_a_rock(map: SmartFellasMap, rng: RandomNumberGenerator, finder: SurfaceFinder) -> Dictionary:
	var shelters := finder.rocks_within(_play_square(map), SHELTER_WIDEST)
	if shelters.is_empty():
		return {}
	var box := finder.rock_box(shelters[rng.randi_range(0, shelters.size() - 1)])
	var middle := box.get_center()
	var out := maxf(box.size.x, box.size.z) * 0.5 + rng.randf_range(0.3, 1.5)
	var angle := rng.randf() * TAU
	var x := middle.x + cos(angle) * out
	var z := middle.z + sin(angle) * out
	if not _inside(map, x, z):
		return {}
	var hit := _ray_down(map, x, z, finder)
	return hit if _is_open_ground(hit, finder) else {}


static func _near_a_marker(map: SmartFellasMap, at: Vector3, within: float) -> bool:
	for child in map.get_children():
		var marker := child as Marker3D
		if marker != null and not MapExporter.hidden_by_eye(marker) and marker.global_position.distance_to(at) < within:
			return true
	return false


## The map's markers of `kind` that are in the map: not those hidden with the eye in the Scene panel, or in
## a hidden group, which Export leaves out.
static func _markers_in_map(map: SmartFellasMap, kind: String) -> Array[Node]:
	var found: Array[Node] = []
	for marker in MarkerKinds.markers_of(map, kind):
		if not MapExporter.hidden_in(marker, map):
			found.append(marker)
	return found


## New markers in the groups `ticked`, not yet in the map.
## Those of its own that are going don't count against room, and none go where a zone keeps them out.
static func _new_markers(map: SmartFellasMap, going: Array[Marker3D], rng: RandomNumberGenerator, finder: SurfaceFinder, ticked: Array[String], zones: Array[Dictionary]) -> Array[Marker3D]:
	var made: Array[Marker3D] = []
	if "food" in ticked:
		_add_food(map, going, rng, finder, made, zones)
	if "creatures" in ticked:
		_add_creatures(map, going, rng, finder, made, zones)
	if "spawns" in ticked:
		for team: String in ["spawn_octopus", "spawn_diver"]:
			var held := _markers_in_map(map, team).filter(func(marker: Node) -> bool: return not marker in going)
			if held.is_empty():
				_add_spawns(map, team, rng, finder, made, zones)
	return made


static func _add_food(map: SmartFellasMap, going: Array[Marker3D], rng: RandomNumberGenerator, finder: SurfaceFinder, made: Array[Marker3D], zones: Array[Dictionary]) -> void:
	var taken: Array[Vector3] = []
	var patches_held := 0
	for marker in _markers_in_map(map, "food_patch"):
		if not marker in going:
			taken.append((marker as Node3D).global_position)
			patches_held += 1
	# At least as many as the game needs, on the smallest map.
	var wanted := clampi(roundi(_area_of(map) / SQUARE_METRES_A_PATCH), MapExporter.FEWEST_PATCHES, MapExporter.MOST_PATCHES)
	var patches := maxi(wanted - patches_held, 0)
	var apart: float = _even_half(map) * PATCHES_APART
	for _patch in patches:
		var hit := _spot_for_food(map, taken, apart, rng, finder, zones)
		if not hit.is_empty() and _add_marker(map, "food_patch", hit["at"], hit["normal"], made, zones):
			taken.append(hit["at"])


## Fish, stingray stops and wrasse spots, as many as the map's size calls for, less those it has already.
static func _add_creatures(map: SmartFellasMap, going: Array[Marker3D], rng: RandomNumberGenerator, finder: SurfaceFinder, made: Array[Marker3D], zones: Array[Dictionary]) -> void:
	var fish_held := 0
	for kind: String in ["fish_flounder", "fish_lionfish"]:
		for marker in _markers_in_map(map, kind):
			if not marker in going:
				fish_held += 1
	var fish := mini(roundi(_area_of(map) / SQUARE_METRES_A_FISH), MapExporter.MOST_FISH - fish_held)
	for index in fish:
		if index % 2 == 0:
			var hit := _anywhere(map, rng, finder)
			if _is_open_ground(hit, finder):
				_add_marker(map, "fish_flounder", hit["at"], Vector3.UP, made, zones)
		else:
			var hit := _beside_a_rock(map, rng, finder)
			if not hit.is_empty():
				_add_marker(map, "fish_lionfish", hit["at"], Vector3.UP, made, zones)
	var haunts := clampi(roundi(_area_of(map) / SQUARE_METRES_A_HAUNT), HAUNTS_A_KIND.x, HAUNTS_A_KIND.y)
	# Stingrays glide from stop to stop over open ground; wrasse keep a cleaning spot beside a rock.
	for kind: String in ["stingray", "wrasse"]:
		if kind == "stingray" and not map.stingrays:
			continue
		var held := _markers_in_map(map, kind).filter(func(marker: Node) -> bool: return not marker in going).size()
		var placed := 0
		for _try in MARKER_TRIES:
			if placed >= mini(haunts, MapExporter.MOST_HAUNTS) - held:
				break
			var hit := _anywhere(map, rng, finder) if kind == "stingray" else _beside_a_rock(map, rng, finder)
			if kind == "stingray" and not _is_open_ground(hit, finder):
				continue
			if not hit.is_empty() and _add_marker(map, kind, hit["at"], Vector3.UP, made, zones):
				placed += 1


## SPAWNS_A_TEAM spawn points for a team that has none: on open floor with room above, a team's at one end
## of the map and the other's at the other, apart from each other and clear of what lies in wait.
static func _add_spawns(map: SmartFellasMap, team: String, rng: RandomNumberGenerator, finder: SurfaceFinder, made: Array[Marker3D], zones: Array[Dictionary]) -> void:
	var side := -1.0 if team == "spawn_octopus" else 1.0
	var reach := _half(map) * EDGE_SHARE
	var middle := _middle(map)
	var lurking: Array[Vector3] = []
	for kind: String in CREATURE_KINDS:
		for marker in _markers_in_map(map, kind):
			lurking.append((marker as Node3D).global_position)
	var placed: Array[Vector3] = []
	for _try in MARKER_TRIES * SPAWNS_A_TEAM * 2:
		if placed.size() >= SPAWNS_A_TEAM:
			break
		var x := middle.x + side * rng.randf_range(reach.x * 0.5, reach.x)
		var hit := _ray_down(map, x, middle.y + rng.randf_range(-reach.y, reach.y), finder)
		if hit.is_empty() or (hit["normal"] as Vector3).y < FLOOR_LIKE:
			continue
		var at: Vector3 = hit["at"]
		if not finder.find(at + Vector3.UP * 0.05, at + Vector3.UP * ROOM_ABOVE).is_empty():
			continue
		if at.y + ROOM_ABOVE > _ceiling(map, finder):
			continue
		if placed.any(func(other: Vector3) -> bool: return other.distance_to(at) < SPAWNS_APART):
			continue
		if lurking.any(func(other: Vector3) -> bool: return other.distance_to(at) < CLEAR_OF_CREATURES):
			continue
		if _add_marker(map, team, at, hit["normal"], made, zones):
			placed.append(at)


## Open sand for a patch with room for its ring of food, away from others, or nothing if it finds none.
## The first half of its tries look in the open sand zones, if the map has any.
static func _spot_for_food(map: SmartFellasMap, taken: Array[Vector3], apart: float, rng: RandomNumberGenerator, finder: SurfaceFinder, zones: Array[Dictionary]) -> Dictionary:
	var reach := (_half(map) - Vector2.ONE * (MapExporter.SPOT_RING + 0.1)).max(Vector2.ZERO)
	var sands := zones.filter(func(zone: Dictionary) -> bool: return zone["kind"] == Zone.Kind.SAND)
	for try in MARKER_TRIES:
		var point := _random_in(map, reach, rng)
		if not sands.is_empty() and try < MARKER_TRIES / 2:
			point = _clamp_in(map, Zone.point_in(sands[rng.randi_range(0, sands.size() - 1)], rng), reach)
		var hit := _ray_down(map, point.x, point.y, finder)
		if not _is_open_ground(hit, finder) or not _ring_lies_on_ground(hit, finder):
			continue
		var at: Vector3 = hit["at"]
		var clear := true
		for other in taken:
			clear = clear and other.distance_to(at) >= apart
		if clear:
			return hit
	return {}


## Whether each of a patch's food spots, round `hit`, has ground right under it, so that none floats off the
## edge of a rock or sinks into it.
static func _ring_lies_on_ground(hit: Dictionary, finder: SurfaceFinder) -> bool:
	if hit["seabed"]:
		return true
	var up: Vector3 = hit["normal"]
	var basis := Basis(Kit.arc_from_up(up))
	for index in MapExporter.SPOTS_IN_A_PATCH:
		var angle := TAU * index / MapExporter.SPOTS_IN_A_PATCH
		var spot: Vector3 = hit["at"] + basis * (Vector3(cos(angle), 0.0, sin(angle)) * MapExporter.SPOT_RING)
		var under := finder.find(spot + up * MapExporter.FOOD_FOLLOWS_WITHIN, spot - up * MapExporter.FOOD_FOLLOWS_WITHIN)
		if under.is_empty():
			return false
	return true


## A marker with a number of its own among those already made in this go, unless a zone keeps markers out
## of `at`: then it gives back false and adds none.
static func _add_marker(map: SmartFellasMap, kind: String, at: Vector3, normal: Vector3, made: Array[Marker3D], zones: Array[Dictionary]) -> bool:
	if Zone.keeps_markers_out(zones, at.x, at.z):
		return false
	var marker := MarkerKinds.new_marker(map, kind, at, normal)
	var prefix: String = MarkerKinds.KINDS[kind]["prefix"]
	var number := String(marker.name).trim_prefix(prefix).to_int()
	for other in made:
		if String(other.name).begins_with(prefix):
			number += 1
	marker.name = "%s%d" % [prefix, number]
	marker.set_meta(MarkerKinds.OWN_MARK, marker.transform.origin)
	made.append(marker)
	return true


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
