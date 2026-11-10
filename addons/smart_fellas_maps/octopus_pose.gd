@tool
extends Node3D
## One of the map's own octopus poses: dropped from the Pose panel onto a rock, a wall or the sand, shaped
## there by eye with the panel's dials and by dragging the arms' tips, and offered by the pieces that name
## it in the Inspector. Its node's name is the pose's name. The octopus is drawn by the game itself (see
## pose_link.gd), so it looks just as players will see it. Export writes the pose in map.ron's poses; the
## node itself never shows in the game.

const PoseLink := preload("pose_link.gd")

## The group every pose in the editor is in, so that it can be found without searching the map.
const GROUP := "smart_fellas_poses"
## What the Pose panel asks the marker tool to place, to drop a pose.
const PLACING := "octopus pose"
## What a person calls one, and the colour its name and handles are drawn in.
const WORDS := "Octopus pose"
const COLOUR := Color(1.0, 0.6, 0.4)
## What a new pose is called, before Godot numbers it to keep it apart from the others.
const NEW_NAME := "Pose"
## The most letters a pose's name may have: the game's MAX_POSE_NAME_CHARS.
const MOST_NAME_LETTERS := 24
## The most poses a map may have, and one piece may offer: the game's MOST_MAP_POSES and MOST_POSES_A_PIECE.
const MOST_POSES := 128
const MOST_A_PIECE := 7
## Where a piece keeps the names of the poses it offers, as a PackedStringArray in its metadata.
const OFFERS := "smart_fellas_poses"
## The pose file version the add-on writes. Every game since the first reads it, so a map's poses load in
## older games too. The game's own pose files are at its POSE_FORMAT_VERSION, 2 since its studio got a
## Grip dial; a map's poses always kept the grip they were written with, as the add-on has had one all along.
const VERSION := 1
## The octopus's own skin, until a piece offering the pose lends it a look.
const SKIN := Color(0.63, 0.42, 0.34)
## How the arms are counted, in the order the game holds them.
const ARMS := 8

## How often the octopus is drawn again while the water plays, in seconds.
const PLAY_EVERY := 0.1

## Says the octopus has been drawn again, with new tips for the handles.
signal drawn

## The pose's numbers as a pose file holds them, but for its name, which is the node's. A part left out
## stays as the octopus has it at rest.
@export_storage var pose: Dictionary = {}:
	set(value):
		pose = value
		_stale = true

## Where each arm's tip is drawn, in the pose's own frame, for the handles that drag it.
var tips := PackedVector3Array()
## Why the octopus can't be drawn, or why the game would refuse the pose, in plain words; "" if neither.
var problem := ""
## The arm the Pose panel's dials bend, 0 to 7, or -1 for every arm, which its handle shows.
var chosen_arm := 0:
	set(value):
		chosen_arm = value
		update_gizmos()
## Whether the octopus moves with the water as the pose says, rippling and swaying, or holds still.
var playing := false:
	set(value):
		playing = value
		_played = 0.0
		_stale = true

var _drawing: MeshInstance3D
var _stale := true
## How long the water has played, and how long since the octopus was last drawn moving, in seconds.
var _played := 0.0
var _since_drawn := 0.0
var _known_name := ""
static var _triangles := PackedInt32Array()


func _enter_tree() -> void:
	add_to_group(GROUP)
	_known_name = String(name)
	if not renamed.is_connected(_on_renamed):
		renamed.connect(_on_renamed)


func _ready() -> void:
	if _drawing == null:
		_drawing = MeshInstance3D.new()
		_drawing.material_override = _skin()
		add_child(_drawing, false, INTERNAL_MODE_FRONT)
	if Engine.is_editor_hint():
		wear_offering_look.call_deferred()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or not is_visible_in_tree():
		return
	if playing:
		_played += delta
		_since_drawn += delta
		if _stale or _since_drawn >= PLAY_EVERY:
			redraw()
	elif _stale:
		redraw()


## The whole pose as the game reads it, named after the node.
func file_pose() -> Dictionary:
	var whole := rest_pose()
	whole.merge(pose.duplicate(true), true)
	whole["version"] = VERSION
	whole["name"] = String(name)
	return whole


## Asks the game to draw the octopus in the pose again, now.
func redraw() -> void:
	_stale = false
	_since_drawn = 0.0
	var up := global_basis.y.normalized() if is_inside_tree() else Vector3.UP
	var answer := PoseLink.draw(file_pose(), _played if playing else -1.0, up)
	problem = str(answer.get("problem", "")) if answer.get("problem") != null else ""
	if not answer.has("skin"):
		_drawing.mesh = null
		tips = PackedVector3Array()
		drawn.emit()
		update_gizmos()
		return
	_drawing.mesh = mesh_of(answer)
	tips = PackedVector3Array()
	for tip: Array in answer.get("tips", []):
		tips.append(Vector3(tip[0], tip[1], tip[2]))
	drawn.emit()
	update_gizmos()


## The octopus drawn, as a mesh: its skin, and the web between its arms.
static func mesh_of(answer: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var skin := PoseLink.floats(answer["skin"])
	var count := skin.size() / 6
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	points.resize(count)
	normals.resize(count)
	for vertex in count:
		var at := vertex * 6
		points[vertex] = Vector3(skin[at], skin[at + 1], skin[at + 2])
		normals[vertex] = Vector3(skin[at + 3], skin[at + 4], skin[at + 5])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = _godot_triangles()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var web := PoseLink.floats(answer.get("web", ""))
	if web.size() >= 9:
		var corners := PackedVector3Array()
		var faces := PackedVector3Array()
		for at in range(0, web.size() - 8, 9):
			var a := Vector3(web[at], web[at + 1], web[at + 2])
			var b := Vector3(web[at + 3], web[at + 4], web[at + 5])
			var c := Vector3(web[at + 6], web[at + 7], web[at + 8])
			var face := (c - a).cross(b - a).normalized()
			corners.append_array([a, c, b])
			faces.append_array([face, face, face])
		var webbing := []
		webbing.resize(Mesh.ARRAY_MAX)
		webbing[Mesh.ARRAY_VERTEX] = corners
		webbing[Mesh.ARRAY_NORMAL] = faces
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, webbing)
	return mesh


## The model's triangles, turned to face the way Godot draws: glTF winds them the other way round.
static func _godot_triangles() -> PackedInt32Array:
	if _triangles.is_empty():
		var start := PoseLink.start()
		var corners := PoseLink.whole_numbers(start.get("triangles", ""))
		for at in range(0, corners.size() - 2, 3):
			_triangles.append_array([corners[at], corners[at + 2], corners[at + 1]])
	return _triangles


func _skin() -> StandardMaterial3D:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.75
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	return skin


## Dresses the octopus in the look of the first piece that offers the pose, laid over it from every side as
## camouflage copies a surface, or in its own skin if none offers it or that piece's look can't be borrowed.
func wear_offering_look() -> void:
	if _drawing == null:
		return
	var skin := _skin()
	var look := _offering_look()
	if look != null:
		skin.albedo_color = look.albedo_color
		skin.albedo_texture = look.albedo_texture
		skin.uv1_triplanar = true
		skin.uv1_world_triplanar = true
	_drawing.material_override = skin


## The material of the first piece in the map offering this pose, if it's one that can be borrowed.
func _offering_look() -> BaseMaterial3D:
	var map := get_owner()
	if map == null:
		return null
	for piece in map.find_children("*", "Node3D", true, false):
		if not offered_by(piece).has(String(name)):
			continue
		var meshes := piece.find_children("*", "MeshInstance3D", true, false)
		if piece is MeshInstance3D:
			meshes.push_front(piece)
		for part: MeshInstance3D in meshes:
			if part.mesh != null and part.mesh.get_surface_count() > 0:
				# The model's own material: the water view draws pieces with ones of its own over it.
				var own := part.mesh.surface_get_material(0) as BaseMaterial3D
				return own if own != null else part.get_active_material(0) as BaseMaterial3D
	return null


## `pose` (a whole pose, as file_pose gives) with every arm on one side of the octopus copied onto the arm
## across from it, mirrored: from its left side if `from_left`. `start` is what the game said when it
## started: which arms are on the left, which arm is across from each, and which parts flip in a mirror.
static func mirrored_side(pose: Dictionary, start: Dictionary, from_left: bool) -> Dictionary:
	var across: Array = start.get("mirror", [])
	var left: Array = start.get("left", [])
	var flipped: Array = start.get("mirrored_parts", [])
	var result := pose.duplicate(true)
	if across.size() != ARMS or left.size() != ARMS:
		return result
	for arm in ARMS:
		if bool(left[arm]) != from_left or int(across[arm]) == arm:
			continue
		var shape: Dictionary = pose["arms"][arm].duplicate()
		for part: String in flipped:
			if shape.has(part):
				shape[part] = -float(shape[part])
		result["arms"][int(across[arm])] = shape
	return result


## `pose` with every arm shaped as arm `from` is.
static func copied_to_all(pose: Dictionary, from: int) -> Dictionary:
	var result := pose.duplicate(true)
	for arm in ARMS:
		result["arms"][arm] = (pose["arms"][from] as Dictionary).duplicate()
	return result


## The octopus at rest, as the game makes a new pose: lying flat, arms out, gripping nothing, so
## arms raised later hold where they are put.
static func rest_pose() -> Dictionary:
	var arms := []
	for arm in ARMS:
		arms.append({})
	return {"version": VERSION, "name": "", "sits": "Floor", "suckers": "Hidden", "eyes": "Covered", "lit": "OwnShape", "body": {"grip": 0.0}, "arms": arms, "water": {}}


## How a pose dropped on a surface facing `normal` sits: on a floor, a wall or a ceiling.
static func sits_facing(normal: Vector3) -> String:
	if normal.y > 0.5:
		return "Floor"
	if normal.y < -0.5:
		return "Ceiling"
	return "Wall"


## A new pose standing on `at`, facing out along `normal`, in the map's own space, not yet in the map.
static func new_pose(at: Vector3, normal: Vector3) -> Node3D:
	var made: Node3D = load("res://addons/smart_fellas_maps/octopus_pose.gd").new()
	made.name = NEW_NAME
	var up := normal.normalized() if normal.length() > 0.0 else Vector3.UP
	var ahead := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.UP
	var side := ahead.cross(up).normalized()
	made.transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), at)
	made.pose = {"sits": sits_facing(up)}
	return made


## The shown poses in `map`, in the order of the scene.
static func nodes_in(map: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not map.is_inside_tree():
		return found
	for node in map.get_tree().get_nodes_in_group(GROUP):
		if map.is_ancestor_of(node) and (node as Node3D).is_visible_in_tree():
			found.append(node)
	return found


## The names of the poses `piece` offers.
static func offered_by(piece: Node) -> PackedStringArray:
	return piece.get_meta(OFFERS, PackedStringArray())


## Keeps what the map's pieces offer pointing at this pose when the Scene panel renames it.
func _on_renamed() -> void:
	var was := _known_name
	_known_name = String(name)
	_stale = true
	wear_offering_look.call_deferred()
	if was.is_empty() or was == _known_name:
		return
	var map := get_owner() if get_owner() != null else get_parent()
	if map == null:
		return
	for piece in map.find_children("*", "Node3D", true, false):
		var offers := offered_by(piece)
		var at := offers.find(was)
		if at >= 0:
			offers[at] = _known_name
			piece.set_meta(OFFERS, offers)
