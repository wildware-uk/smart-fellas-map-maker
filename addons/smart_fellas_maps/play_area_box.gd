@tool
class_name SmartFellasPlayArea
extends Node3D
## The map's play area: the box players may swim in. Move it anywhere with Godot's move tool, and size it
## with the dots on its faces. It sits where the middle of its floor is, and stays upright with its sides
## along X and Z, as the game holds it. Scenery may stand anywhere outside it; spawns, food, creatures and
## zones must be inside. Export writes it as the map's `area`.

## Its width along X, height, and depth along Z, in metres.
@export var size := Vector3(40.0, 25.5, 40.0):
	set(value):
		size = value
		_changed()


func _init() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		return
	# Turned or scaled, it would no longer be the box the game plays in.
	if basis != Basis.IDENTITY:
		basis = Basis.IDENTITY
	_changed()


## The box, in the map's own space.
func box() -> AABB:
	return AABB(position - Vector3(size.x * 0.5, 0.0, size.z * 0.5), size)


## Makes it `box`, in the map's own space.
func set_box(box: AABB) -> void:
	position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	size = box.size


func _changed() -> void:
	update_gizmos()
	var map := get_parent() as SmartFellasMap
	if map != null:
		map.area_moved()
