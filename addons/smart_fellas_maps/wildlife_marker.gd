@tool
extends Marker3D
## A wildlife marker with settings of its own, set in the Inspector. Its name says which kind it is, and
## only that kind's settings mean anything: a jellies_... marker's first three, a lantern_... marker's last.

## How many jellyfish are in the group.
@export_range(1, 16) var count := 8:
	set(value):
		count = value
		update_gizmos()
## What colour the group glows.
@export_enum("Teal", "Blue", "Pink") var colour := 0
## How far the group spreads round its middle, in metres.
@export_range(0.5, 12.0, 0.1) var spread := 4.5:
	set(value):
		spread = value
		update_gizmos()
## How far a school of lantern fish roams from here, in metres.
@export_range(0.0, 25.0, 0.1) var roam := 4.0:
	set(value):
		roam = value
		update_gizmos()


## A scene saved before the colour had its name called it hue.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"hue":
		colour = value
		return true
	return false


## Shows only the settings this kind of marker has.
func _validate_property(property: Dictionary) -> void:
	var is_jellies := String(name).begins_with("jellies_")
	if property["name"] in ["count", "colour", "spread"] and not is_jellies:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR
	elif property["name"] == "roam" and is_jellies:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR
