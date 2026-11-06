extends SceneTree
## Writes out how the water looks at a range of depths, by the add-on's sums, for a test to hold against
## the game's:
##
##   godot --headless --path <this project> --script res://addons/smart_fellas_maps/water_table_no_window.gd -- <out file>

const WaterLook := preload("water/water_look.gd")
const WaterView := preload("water/water_view.gd")

## Meshes as Godot names them on importing a kit piece, one of every kind that bends and one that doesn't.
const IMPORTED_MESHES := [
	"kelp_foliage_kelp_0",
	"seagrass_foliage_grass_0",
	"fan_foliage_fan_0",
	"anemone_teal_foliage_anemone_0",
	"coral_branch_pink_prop_branch_pink_0",
	"coral_brain_prop_brain_orange_0",
	"coral_tubes_prop_tubes_yellow_0",
	"rock_boulder_rock_boulder_0",
]
const DEPTHS: Array[float] = [28.0, 30.0, 40.0, 60.0, 90.0, 120.0, 160.0, 200.0, 250.0, 280.0, 350.0, 500.0, 750.0, 1000.0]
const NUMBERS := ["visibility", "sun_lux", "fill_brightness", "shaft_strength", "caustics", "surface"]
const COLOURS := ["haze", "sun", "fill", "tint", "speck"]


func _initialize() -> void:
	var lines := PackedStringArray()
	for depth in DEPTHS:
		var look := WaterLook.look_of(depth)
		var words := PackedStringArray(["%.1f" % depth])
		for name: String in NUMBERS:
			words.append("%.5f" % look[name])
		for name: String in COLOURS:
			var colour: Vector3 = look[name]
			words.append("%.5f %.5f %.5f" % [colour.x, colour.y, colour.z])
		lines.append(" ".join(words))
	for imported in IMPORTED_MESHES:
		var name_in_game := WaterView._name_in_the_game(imported)
		lines.append("flex %s %.4f" % [name_in_game, WaterView._flex_of(name_in_game)])
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	quit(0)
