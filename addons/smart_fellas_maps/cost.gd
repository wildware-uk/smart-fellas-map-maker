@tool
extends RefCounted
## What a map costs to draw in the game: its pieces, triangles and draws, and how those stand against
## what 1080p Medium can afford on mid-level hardware.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")

enum Level { FINE, CLOSE, OVER }

## Pieces: what they cost in frame time, only advice (#299). The Reef places 10,170 and holds 60 a second;
## the owner's Boneyard places 13,323. The brush stops only at MapExporter.MOST_PIECES, far past these.
const PIECES_CLOSE := 12000
const PIECES_OVER := 20000
## Triangles, each counted once. Measured in the real game: see "The cost meter" in the README.
const TRIANGLES_CLOSE := 12000000
const TRIANGLES_OVER := 32000000
## Draws: one for each kind of piece the map uses, as each kind is drawn in one batch, and one for the sand.
## The whole kit comes to 85, which costs a couple of milliseconds. A map's own models add one for each
## material of each different model, so only a map with many of its own goes red.
const DRAWS_CLOSE := 60
const DRAWS_OVER := 86


## What `map` costs: {"pieces", "triangles", "draws", "missing"}, the last being the names of any kit pieces
## it uses that the kit doesn't have. Its own models count as `own`, from own_models_of; finding them walks
## the whole scene, so the meter keeps that until the map's nodes change, and not while a brush paints.
static func of(map: SmartFellasMap, own: Dictionary = {}) -> Dictionary:
	if own.is_empty():
		own = own_models_of(map)
	var cost := kit_of(map)
	for key in ["pieces", "triangles", "draws"]:
		cost[key] += own[key]
	return cost


## What `map`'s kit pieces cost, placed and painted, with one draw for the sand: as of, leaving out its own
## models. The brush's limit is on kit pieces alone.
static func kit_of(map: SmartFellasMap) -> Dictionary:
	var pieces := 0
	var triangles := 0
	var kinds := {}
	var missing: Array[String] = []
	for found in MapExporter.kit_pieces(map):
		pieces += 1
		triangles += Kit.info(found["kit"])["triangles"]
		kinds[found["kit"]] = true
	for kit: String in map.painted:
		var count: int = map.painted[kit].size() / Kit.STRIDE
		pieces += count
		triangles += count * Kit.info(kit)["triangles"]
		kinds[kit] = true
	for kit: String in kinds:
		if not Kit.has(kit):
			missing.append(kit)
	return {"pieces": pieces, "triangles": triangles, "draws": kinds.size() + 1 - missing.size(), "missing": missing}


## What `map`'s own models cost, {"pieces", "triangles", "draws"}, as Export takes them: each placed one, and
## each copy of a scattered mesh, is a piece of its triangles, and each different one draws once per
## material. Export makes a scattered mesh's stretched or tinted copies into models of their own, and cuts a
## very wide mesh into parts; those few extra draws aren't counted.
static func own_models_of(map: SmartFellasMap) -> Dictionary:
	var pieces := 0
	var triangles := 0
	var kinds := {}
	for found in MapExporter.own_model_pieces(map):
		var meshes: Array[MeshInstance3D] = MapExporter.meshes_in(found["node"])
		if found.has("alone"):
			# Meshes under a mesh on its own are pieces of their own.
			meshes = [found["node"]]
		var parts := 0
		for part in meshes:
			triangles += triangles_in(part.mesh)
			parts += part.mesh.get_surface_count()
		pieces += 1
		kinds[found["path"]] = parts
	for scatter in MapExporter.scatters(map):
		var many := scatter.multimesh
		var copies := MapExporter.copies_in(many)
		if copies == 0:
			continue
		pieces += copies
		triangles += copies * triangles_in(many.mesh)
		kinds["scattered %d" % many.mesh.get_instance_id()] = many.mesh.get_surface_count()
	var draws := 0
	for parts: int in kinds.values():
		draws += parts
	return {"pieces": pieces, "triangles": triangles, "draws": draws}


## How many triangles `mesh` draws.
static func triangles_in(mesh: Mesh) -> int:
	if not mesh is ArrayMesh:
		return mesh.get_faces().size() / 3
	var triangles := 0
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var corners: int = mesh.surface_get_array_index_len(surface)
		if corners <= 0:
			corners = mesh.surface_get_array_len(surface)
		triangles += corners / 3
	return triangles


static func level_of(value: int, close: int, over: int) -> Level:
	if value >= over:
		return Level.OVER
	if value >= close:
		return Level.CLOSE
	return Level.FINE


static func worst_level(cost: Dictionary) -> Level:
	return maxi(maxi(
		level_of(cost["pieces"], PIECES_CLOSE, PIECES_OVER),
		level_of(cost["triangles"], TRIANGLES_CLOSE, TRIANGLES_OVER)),
		level_of(cost["draws"], DRAWS_CLOSE, DRAWS_OVER)) as Level
