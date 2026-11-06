@tool
extends RefCounted
## What a map costs to draw in the game: its pieces, triangles and draws, and how those stand against
## what 1080p Medium can afford on mid-level hardware.

const Kit := preload("kit.gd")
const MapExporter := preload("map_exporter.gd")

enum Level { FINE, CLOSE, OVER }

## Pieces: the game refuses a stranger's map past MOST_PIECES. The brush warns at CLOSE and stops at OVER.
const PIECES_CLOSE := 3400
const PIECES_OVER := MapExporter.MOST_PIECES
## Triangles, each counted once. Measured in the real game: see "The cost meter" in the README.
const TRIANGLES_CLOSE := 12000000
const TRIANGLES_OVER := 32000000
## Draws: one for each kind of piece the map uses, as each kind is drawn in one batch, and one for the sand.
## The whole kit comes to 85, which costs a couple of milliseconds, so this can warn but never go red.
const DRAWS_CLOSE := 60
const DRAWS_OVER := 86


## What `map` costs: {"pieces", "triangles", "draws", "missing"}, the last being the names of any pieces it
## uses that the kit doesn't have.
static func of(map: SmartFellasMap) -> Dictionary:
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
