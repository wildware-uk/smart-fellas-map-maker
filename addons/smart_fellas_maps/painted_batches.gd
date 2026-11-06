@tool
extends Node3D
## Draws a map's painted pieces: one batch for each kind in the kit, as the game does. Thousands of
## pieces as nodes make the editor crawl, so painted pieces are numbers on the map and only these few
## nodes draw them. It sits inside the map as an internal node, so it is never saved.

const Kit := preload("kit.gd")

## kit name -> {"node", "values", "count"}. "values" is the list last drawn, to tell whether it changed.
var _shown := {}
var _water: Node3D


## `water` is the view that gives pieces the game's look, if there is one.
func set_water(water: Node3D) -> void:
	_water = water


func _ready() -> void:
	# Painted pieces hold places in the world, whatever the map's own node is doing.
	top_level = true
	transform = Transform3D.IDENTITY


## Draws everything in `painted`, changing only the kinds that differ from what's on screen.
func show_pieces(painted: Dictionary) -> void:
	for kit: String in _shown.keys():
		if not painted.has(kit):
			_shown[kit]["node"].queue_free()
			_shown.erase(kit)
	for kit: String in painted:
		if not Kit.has(kit):
			continue
		var values: PackedFloat32Array = painted[kit]
		var count := values.size() / Kit.STRIDE
		if _shown.has(kit) and _shown[kit]["count"] == count and _shown[kit]["values"] == values:
			continue
		_rebuild(kit, values)


## Adds to one kind what was appended to its list since it was last drawn, the cheap way: painting does
## this every moment of a stroke.
func show_added(kit: String, values: PackedFloat32Array) -> void:
	if not Kit.has(kit):
		return
	var count := values.size() / Kit.STRIDE
	if not _shown.has(kit) or _capacity(kit) < count:
		_rebuild(kit, values)
		return
	var shown: Dictionary = _shown[kit]
	var many: MultiMesh = shown["node"].multimesh
	for index in range(shown["count"], count):
		many.set_instance_transform(index, Kit.place_in_list(values, index))
	many.visible_instance_count = count
	shown["count"] = count
	shown["values"] = values


## Draws one kind again from nothing.
func show_kind(kit: String, values: PackedFloat32Array) -> void:
	if not Kit.has(kit):
		return
	_rebuild(kit, values)


func _capacity(kit: String) -> int:
	return (_shown[kit]["node"].multimesh as MultiMesh).instance_count


func _rebuild(kit: String, values: PackedFloat32Array) -> void:
	var count := values.size() / Kit.STRIDE
	if not _shown.has(kit):
		_shown[kit] = {"node": _batch_for(kit)}
	var shown: Dictionary = _shown[kit]
	var many: MultiMesh = shown["node"].multimesh
	# Room to grow, so that a stroke only rarely has to write the whole list again.
	var room := maxi(16, nearest_po2(count + 1))
	if many.instance_count < count or many.instance_count > room * 4:
		many.visible_instance_count = -1
		many.instance_count = room
	for index in count:
		many.set_instance_transform(index, Kit.place_in_list(values, index))
	many.visible_instance_count = count
	shown["count"] = count
	shown["values"] = values


func _batch_for(kit: String) -> MultiMeshInstance3D:
	var info := Kit.info(kit)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = info["mesh"]
	var batch := MultiMeshInstance3D.new()
	batch.name = kit
	batch.multimesh = many
	add_child(batch)
	if _water != null:
		_water.dress_batch(batch, info["mesh"])
	return batch
