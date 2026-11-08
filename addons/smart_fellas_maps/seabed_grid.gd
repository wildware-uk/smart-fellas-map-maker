@tool
extends RefCounted
## A sculpted seabed: a square grid of heights kept on the map, read and changed here. The grid sits round
## its own middle, over the play area wherever that is, or round the map's middle on a map made before it
## could (#264). Past the grid's edge the seabed runs on flat at the height of the edge. The game builds the
## same thing from the same numbers, in its sculpted seabed, which says how painted rock gets its cut corners
## and its moss.

## How far apart the points are to begin with, in metres, and the fewest and most a side of the grid has.
const SPACING := 1.0
const FEWEST_A_SIDE := 33
const MOST_A_SIDE := 129
## How far past the map's edge the seabed runs on, as the game has it: SEABED_BEYOND.
const BEYOND := 60.0
## How many times the ground's pictures repeat in a metre, as in the game's REPEATS_A_METRE.
const PICTURE_REPEATS := 0.3
## How much room a ray's steps leave to miss a bump, as a share of the spacing.
const RAY_STEP := 0.5
const RAY_REFINES := 8
## What painted ground is made of, as the game's sculpted::Painted.
enum Painted { SAND, ROCK, MOSS }
## Where moss grows on painted rock, as the game's MOSS_EVERY and MOSS_FROM.
const MOSS_EVERY := 6
const MOSS_FROM := 140
## A square's corners, as steps to the squares beside it, top left first and round past the top right.
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]


var reach: float
## The grid's middle, as (x, z).
var centre: Vector2
## Its first point, the corner towards -X and -Z, as (x, z).
var origin: Vector2
var side: int
var heights: PackedFloat32Array
var rock: PackedByteArray
var spacing: float
var lowest := 0.0
var highest := 0.0


## The grid a map holds, or null if its seabed is flat.
static func of(map: SmartFellasMap) -> RefCounted:
	if map.seabed_side < 2 or map.seabed_heights.size() != map.seabed_side * map.seabed_side:
		return null
	return from_numbers(map.seabed_reach, map.seabed_side, map.seabed_heights, map.seabed_rock, map.seabed_middle)


## A grid from its numbers, which must agree in size.
static func from_numbers(reach_given: float, side_given: int, heights_given: PackedFloat32Array, rock_given: PackedByteArray, middle_given := Vector2.ZERO) -> RefCounted:
	var grid: RefCounted = (load("res://addons/smart_fellas_maps/seabed_grid.gd") as GDScript).new()
	grid.reach = reach_given
	grid.centre = middle_given
	grid.origin = middle_given - Vector2(reach_given, reach_given)
	grid.side = side_given
	grid.heights = heights_given
	grid.rock = rock_given
	grid.spacing = reach_given * 2.0 / (side_given - 1)
	grid.measure()
	return grid


## How many points a new grid has along each side, for a grid reaching this far from its middle.
static func side_for(reach: float) -> int:
	return clampi(roundi(reach * 2.0 / SPACING) + 1, FEWEST_A_SIDE, MOST_A_SIDE)


func measure() -> void:
	lowest = INF
	highest = -INF
	for height in heights:
		lowest = minf(lowest, height)
		highest = maxf(highest, height)


## The grid's point nearest (x, z), kept to the grid: x, then z, as whole numbers.
func nearest_point(x: float, z: float) -> Vector2i:
	return Vector2i(
		clampi(roundi((x - origin.x) / spacing), 0, side - 1),
		clampi(roundi((z - origin.y) / spacing), 0, side - 1)
	)


func point_at(column: int, row: int) -> Vector3:
	return Vector3(origin.x + column * spacing, heights[row * side + column], origin.y + row * spacing)


## The height of the seabed at (x, z), on the same two triangles the game has in each square.
func height_at(x: float, z: float) -> float:
	var across := clampf((x - origin.x) / spacing, 0.0, side - 1.0)
	var down := clampf((z - origin.y) / spacing, 0.0, side - 1.0)
	var column := mini(floori(across), side - 2)
	var row := mini(floori(down), side - 2)
	var along := across - column
	var deep := down - row
	var near := heights[row * side + column]
	var right := heights[row * side + column + 1]
	var below := heights[(row + 1) * side + column]
	var far := heights[(row + 1) * side + column + 1]
	# Each square is cut from its top right to its bottom left.
	if along + deep <= 1.0:
		return near + (right - near) * along + (below - near) * deep
	return far + (below - far) * (1.0 - along) + (right - far) * (1.0 - deep)


func normal_at(x: float, z: float) -> Vector3:
	var left := height_at(x - spacing, z)
	var right := height_at(x + spacing, z)
	var ahead := height_at(x, z - spacing)
	var behind := height_at(x, z + spacing)
	return Vector3(left - right, spacing * 2.0, ahead - behind).normalized()


## The number of the square holding (x, z), or -1 if it's past the grid.
func cell_at(x: float, z: float) -> int:
	var across := (x - origin.x) / spacing
	var down := (z - origin.y) / spacing
	if across < 0.0 or down < 0.0 or across >= side - 1 or down >= side - 1:
		return -1
	return floori(down) * (side - 1) + floori(across)


func is_rock_at(x: float, z: float) -> bool:
	return ground_at(x, z) != Painted.SAND


## What the ground at (x, z) is made of, a Painted, cut at the corners as the mesh is.
func ground_at(x: float, z: float) -> int:
	var across := (x - origin.x) / spacing
	var down := (z - origin.y) / spacing
	if across < 0.0 or down < 0.0 or across >= side - 1 or down >= side - 1:
		return Painted.SAND
	var column := floori(across)
	var row := floori(down)
	var along := across - column
	var deep := down - row
	var corner := Vector2i(-1 if along < 0.5 else 1, -1 if deep < 0.5 else 1)
	var own := painted_square(column, row)
	if minf(along, 1.0 - along) + minf(deep, 1.0 - deep) >= 0.5:
		return own
	return corner_piece(own, painted_square(column + corner.x, row), painted_square(column, row + corner.y), painted_square(column + corner.x, row + corner.y))


## What the grid's square at (column, row) is painted, sand past the grid.
func painted_square(column: int, row: int) -> int:
	var cells := side - 1
	if column < 0 or row < 0 or column >= cells or row >= cells:
		return Painted.SAND
	var cell := row * cells + column
	if cell >= rock.size() or rock[cell] == 0:
		return Painted.SAND
	return Painted.MOSS if grows_moss(column, row) else Painted.ROCK


## What a square painted `own` gives the small triangle at one of its corners, with `one_side` and
## `other_side` the squares beside it there and `diagonal` the one across: the game's corner_piece.
static func corner_piece(own: int, one_side: int, other_side: int, diagonal: int) -> int:
	var own_rock := own != Painted.SAND
	var odd_one_out := (one_side != Painted.SAND) != own_rock and (other_side != Painted.SAND) != own_rock and (diagonal != Painted.SAND) != own_rock
	var rock_joins_across := not own_rock and diagonal == Painted.SAND and one_side != Painted.SAND and other_side != Painted.SAND
	if odd_one_out or rock_joins_across:
		if own_rock:
			return Painted.SAND
		var moss := 0
		var plain := 0
		for other in [one_side, other_side, diagonal]:
			if other == Painted.MOSS:
				moss += 1
			elif other == Painted.ROCK:
				plain += 1
		return Painted.MOSS if moss >= plain else Painted.ROCK
	if not own_rock or one_side == Painted.SAND or other_side == Painted.SAND or diagonal == Painted.SAND:
		return own
	var odd_rock := one_side != own and other_side == one_side and diagonal == one_side
	var moss_joins_across := diagonal == own and other_side == one_side and one_side == Painted.MOSS and own != one_side
	return one_side if odd_rock or moss_joins_across else own


## Whether rock in the grid's square at (column, row) is mossy: the game's grows_moss, in whole numbers.
static func grows_moss(column: int, row: int) -> bool:
	var left := column / MOSS_EVERY
	var along := column % MOSS_EVERY
	var top := row / MOSS_EVERY
	var down := row % MOSS_EVERY
	var blend := moss_number(left, top) * (MOSS_EVERY - along) * (MOSS_EVERY - down) \
		+ moss_number(left + 1, top) * along * (MOSS_EVERY - down) \
		+ moss_number(left, top + 1) * (MOSS_EVERY - along) * down \
		+ moss_number(left + 1, top + 1) * along * down
	return blend >= MOSS_FROM * MOSS_EVERY * MOSS_EVERY


## The game's moss_number: 0 to 255 for a moss point, kept under 2^62 as Godot's whole numbers are signed.
static func moss_number(column: int, row: int) -> int:
	var mixed := ((column * 73856093) ^ (row * 19349663)) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 13)) * 1274126177) & 0x7FFFFFFF
	return (mixed ^ (mixed >> 16)) & 255


## Where the segment from `from` to `to` first comes down onto the seabed, as Vector3.INF if it doesn't.
func first_hit(from: Vector3, to: Vector3) -> Vector3:
	if from.y < lowest and to.y < lowest:
		return Vector3.INF
	var start := 0.0
	var end := 1.0
	# Only the part of the ray between the highest and lowest ground needs looking at.
	if absf(from.y - to.y) > 0.0001:
		var at_top := (from.y - highest) / (from.y - to.y)
		var at_bottom := (from.y - lowest) / (from.y - to.y)
		start = clampf(minf(at_top, at_bottom), 0.0, 1.0)
		end = clampf(maxf(at_top, at_bottom), 0.0, 1.0)
	var flat_length := Vector2(to.x - from.x, to.z - from.z).length() * (end - start)
	var steps := clampi(ceili(flat_length / (spacing * RAY_STEP)), 1, 4096)
	var before := from.lerp(to, start)
	if before.y < height_at(before.x, before.z):
		return Vector3.INF
	var before_t := start
	for step in steps:
		var t := lerpf(start, end, float(step + 1) / steps)
		var here := from.lerp(to, t)
		if here.y <= height_at(here.x, here.z):
			return _refine(from, to, before_t, t)
		before_t = t
	return Vector3.INF


func _refine(from: Vector3, to: Vector3, above: float, below: float) -> Vector3:
	for _try in RAY_REFINES:
		var middle := (above + below) * 0.5
		var here := from.lerp(to, middle)
		if here.y <= height_at(here.x, here.z):
			below = middle
		else:
			above = middle
	var at := from.lerp(to, below)
	at.y = height_at(at.x, at.z)
	return at


## The meshes' numbers: {"points", "normals", "pictures", "sand", "rock", "moss"}, where the last three are
## lists of triangles. The game's SeabedShape::of does the same, though its points may come in another order.
## `area_reach` is how far the play area's farthest edge is from the middle of the map. The ground runs on
## that far and BEYOND past it from the map's middle, and at least a metre past the grid, as the game's.
func shape(area_reach: float) -> Dictionary:
	var outer := area_reach + BEYOND
	var wide := side + 2
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	points.resize(wide * wide)
	normals.resize(wide * wide)
	var made := {"points": points, "normals": normals, "across": _along(origin.x, outer), "down": _along(origin.y, outer)}
	_fill_points(made, 0, wide - 1, 0, wide - 1)
	recut(made)
	return made


## Where the mesh's points stand along one way, from the grid's first point there: a point past each end of
## the grid, and the grid's own between.
func _along(first: float, outer: float) -> PackedFloat32Array:
	var wide := side + 2
	var along := PackedFloat32Array()
	along.resize(wide)
	along[0] = minf(-outer, first - 1.0)
	along[wide - 1] = maxf(outer, first + reach * 2.0 + 1.0)
	for index in side:
		along[index + 1] = first + index * spacing
	return along


## Brings `made`, from `shape`, up to date with the heights between grid points `low` and `high`, and
## leaves the rest as it was: the cheap way, since a stroke changes only round the tool.
func reshape(made: Dictionary, low: Vector2i, high: Vector2i) -> void:
	var last := side + 1
	# The mesh has a ring past the grid, so grid point n is mesh point n + 1, and a point's slope reads the
	# heights either side of it.
	_fill_points(made, maxi(low.y, 0), mini(high.y + 2, last), maxi(low.x, 0), mini(high.x + 2, last))
	_place_between(made)


func _fill_points(made: Dictionary, first_row: int, last_row: int, first_column: int, last_column: int) -> void:
	var wide := side + 2
	var points: PackedVector3Array = made["points"]
	var normals: PackedVector3Array = made["normals"]
	var across: PackedFloat32Array = made["across"]
	var down: PackedFloat32Array = made["down"]
	for row in range(first_row, last_row + 1):
		var row_in := clampi(row - 1, 0, side - 1)
		var ahead_row := clampi(row - 2, 0, side - 1) * side
		var behind_row := clampi(row, 0, side - 1) * side
		for column in range(first_column, last_column + 1):
			var column_in := clampi(column - 1, 0, side - 1)
			points[row * wide + column] = Vector3(across[column], heights[row_in * side + column_in], down[row])
			var left := heights[row_in * side + clampi(column - 2, 0, side - 1)]
			var right := heights[row_in * side + clampi(column, 0, side - 1)]
			var ahead := heights[ahead_row + column_in]
			var behind := heights[behind_row + column_in]
			normals[row * wide + column] = Vector3(left - right, spacing * 2.0, ahead - behind).normalized()
	made["points"] = points
	made["normals"] = normals


## Cuts the mesh into sand, rock and moss again, for the rock as it is now: after painting, or from new.
## The points the cuts add come after the grid's, and each is a set share of the way between two of them.
func recut(made: Dictionary) -> void:
	var wide := side + 2
	var points: PackedVector3Array = made["points"]
	var normals: PackedVector3Array = made["normals"]
	points.resize(wide * wide)
	normals.resize(wide * wide)
	made["points"] = points
	made["normals"] = normals
	var cutter := {
		"made": made, "wide": wide, "between": {},
		"from": PackedInt32Array(), "to": PackedInt32Array(), "share": PackedFloat32Array(),
		"lists": [[], [], []],
	}
	var cells := wide - 1
	# Only squares near rock can be cut, so the rest are looked at no further.
	var near_rock := PackedByteArray()
	near_rock.resize(cells * cells)
	# What each of the mesh's squares is painted, with a ring of sand round them to look past the edge at.
	var padded := cells + 2
	var painted_at := PackedByteArray()
	painted_at.resize(padded * padded)
	var grid_cells := side - 1
	for cell in mini(rock.size(), grid_cells * grid_cells):
		if rock[cell] == 0:
			continue
		var column := cell % grid_cells + 1
		var row := cell / grid_cells + 1
		painted_at[(row + 1) * padded + column + 1] = painted_square(column - 1, row - 1)
		for down in range(-1, 2):
			for across in range(-1, 2):
				near_rock[(row + down) * cells + column + across] = 1
	var pieces := {}
	for row in cells:
		for column in cells:
			if near_rock[row * cells + column] == 0:
				continue
			var at := (row + 1) * padded + column + 1
			var own := painted_at[at]
			var corners := PackedByteArray()
			var split := false
			for corner in CORNERS:
				var piece := corner_piece(own, painted_at[at + corner.x], painted_at[at + corner.y * padded], painted_at[at + corner.x + corner.y * padded])
				corners.append(piece)
				split = split or piece != own
			if split:
				pieces[row * cells + column] = corners
	var cut := PackedByteArray()
	cut.resize(cells * cells)
	var near_cut := PackedByteArray()
	near_cut.resize(cells * cells)
	for key: int in pieces:
		cut[key] = 1
		for beside in [key - cells, key - 1, key + 1, key + cells]:
			if beside >= 0 and beside < cells * cells:
				near_cut[beside] = 1
	# Most squares are whole, with no cut square beside them: those go straight into these, as two triangles,
	# the same as the game's but wound the other way.
	var plain: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var sand := PackedInt32Array()
	for row in cells:
		for column in cells:
			var key := row * cells + column
			var own := painted_at[(row + 1) * padded + column + 1]
			if cut[key] != 0:
				_cut_square(cutter, column, row, own, pieces[key])
				continue
			if near_cut[key] != 0:
				var beside := [
					row > 0 and cut[key - cells] != 0,
					column > 0 and cut[key - 1] != 0,
					column < cells - 1 and cut[key + 1] != 0,
					row < cells - 1 and cut[key + cells] != 0,
				]
				_whole_square(cutter, column, row, own, beside)
				continue
			var first := row * wide + column
			var triangles := [first, first + 1, first + wide, first + 1, first + wide + 1, first + wide]
			if own == Painted.SAND:
				sand.append_array(triangles)
			else:
				plain[own].append_array(triangles)
	plain[Painted.SAND] = sand
	for painted in 3:
		plain[painted].append_array(PackedInt32Array(cutter["lists"][painted]))
	made["sand"] = plain[Painted.SAND]
	made["rock"] = plain[Painted.ROCK]
	made["moss"] = plain[Painted.MOSS]
	made["between_from"] = cutter["from"]
	made["between_to"] = cutter["to"]
	made["between_share"] = cutter["share"]
	_place_between(made)
	var placed: PackedVector3Array = made["points"]
	var pictures := PackedVector2Array()
	pictures.resize(placed.size())
	for index in placed.size():
		pictures[index] = Vector2(placed[index].x, placed[index].z) * PICTURE_REPEATS
	made["pictures"] = pictures


## Puts the points the cuts added where they belong between their two grid points, which a stroke moves.
func _place_between(made: Dictionary) -> void:
	var wide := side + 2
	var from: PackedInt32Array = made["between_from"]
	var to: PackedInt32Array = made["between_to"]
	var share: PackedFloat32Array = made["between_share"]
	var points: PackedVector3Array = made["points"]
	var normals: PackedVector3Array = made["normals"]
	points.resize(wide * wide + from.size())
	normals.resize(wide * wide + from.size())
	for index in from.size():
		points[wide * wide + index] = points[from[index]].lerp(points[to[index]], share[index])
		normals[wide * wide + index] = normals[from[index]].lerp(normals[to[index]], share[index]).normalized()
	made["points"] = points
	made["normals"] = normals


## The point `quarters` quarters of the way from mesh point `from` to `to`, added if it's new.
static func _between(cutter: Dictionary, from: int, to: int, quarters: int) -> int:
	if from > to:
		var swap := from
		from = to
		to = swap
		quarters = 4 - quarters
	var wide: int = cutter["wide"]
	var key := (from * wide * wide + to) * 4 + quarters
	var known: Dictionary = cutter["between"]
	if known.has(key):
		return known[key]
	var froms: PackedInt32Array = cutter["from"]
	froms.append(from)
	cutter["from"] = froms
	var tos: PackedInt32Array = cutter["to"]
	tos.append(to)
	cutter["to"] = tos
	var shares: PackedFloat32Array = cutter["share"]
	shares.append(quarters / 4.0)
	cutter["share"] = shares
	var point := wide * wide + froms.size() - 1
	known[key] = point
	return point


## Adds a triangle of `painted`, facing up: clockwise seen from above, as Godot's front faces are.
static func _triangle(cutter: Dictionary, painted: int, one: int, two: int, three: int) -> void:
	var first := _flat(cutter, one)
	var facing := (_flat(cutter, two) - first).cross(_flat(cutter, three) - first)
	var list: Array = cutter["lists"][painted]
	if facing < 0.0:
		list.append_array([one, three, two])
	else:
		list.append_array([one, two, three])


## Where a mesh point is across the grid, counted in squares, which is enough to say which way a triangle in
## one square faces.
static func _flat(cutter: Dictionary, point: int) -> Vector2:
	var wide: int = cutter["wide"]
	if point < wide * wide:
		return Vector2(point % wide, point / wide)
	var index: int = point - wide * wide
	var from: int = cutter["from"][index]
	var to: int = cutter["to"][index]
	return Vector2(from % wide, from / wide).lerp(Vector2(to % wide, to / wide), cutter["share"][index])


## The game's Cutter::cut_square: a small triangle at each corner, and the rest of the square's own.
static func _cut_square(cutter: Dictionary, column: int, row: int, own: int, corners: PackedByteArray) -> void:
	var wide: int = cutter["wide"]
	var top_left := row * wide + column
	var top_right := top_left + 1
	var bottom_left := top_left + wide
	var bottom_right := bottom_left + 1
	var top := _between(cutter, top_left, top_right, 2)
	var left := _between(cutter, top_left, bottom_left, 2)
	var right := _between(cutter, top_right, bottom_right, 2)
	var bottom := _between(cutter, bottom_left, bottom_right, 2)
	var middle := _between(cutter, top_right, bottom_left, 2)
	var near_top_right := _between(cutter, top_right, bottom_left, 1)
	var near_bottom_left := _between(cutter, top_right, bottom_left, 3)
	_triangle(cutter, corners[0], top_left, top, left)
	_triangle(cutter, own, middle, top, left)
	_triangle(cutter, corners[2], bottom_right, right, bottom)
	_triangle(cutter, own, middle, right, bottom)
	for side_of in [[top_right, corners[1], top, right, near_top_right], [bottom_left, corners[3], left, bottom, near_bottom_left]]:
		for side_point in [side_of[2], side_of[3]]:
			_triangle(cutter, side_of[1], side_of[0], side_point, side_of[4])
			_triangle(cutter, own, middle, side_point, side_of[4])


## The game's Cutter::whole_square: two triangles, with the middle of a side shared with a cut square put in.
## `beside` says which squares are cut: above, left, right and below.
static func _whole_square(cutter: Dictionary, column: int, row: int, own: int, beside: Array) -> void:
	var wide: int = cutter["wide"]
	var top_left := row * wide + column
	var top_right := top_left + 1
	var bottom_left := top_left + wide
	var bottom_right := bottom_left + 1
	for half in [[top_left, top_right, bottom_left, beside[0], beside[1]], [bottom_right, top_right, bottom_left, beside[2], beside[3]]]:
		var corner: int = half[0]
		var one_side: int = half[1]
		var other_side: int = half[2]
		var one_middle := _between(cutter, corner, one_side, 2) if half[3] else -1
		var other_middle := _between(cutter, corner, other_side, 2) if half[4] else -1
		if one_middle >= 0 and other_middle >= 0:
			_triangle(cutter, own, one_middle, corner, other_middle)
			_triangle(cutter, own, one_middle, other_middle, other_side)
			_triangle(cutter, own, one_middle, other_side, one_side)
		elif one_middle >= 0:
			_triangle(cutter, own, one_middle, corner, other_side)
			_triangle(cutter, own, one_middle, other_side, one_side)
		elif other_middle >= 0:
			_triangle(cutter, own, other_middle, other_side, one_side)
			_triangle(cutter, own, other_middle, one_side, corner)
		else:
			_triangle(cutter, own, corner, one_side, other_side)
