@tool
extends RefCounted
## The shader settings the water view's shaders share, which Godot keeps in the project's settings, not in
## the add-on's folder. The updater only replaces the add-on's folder, so a project that came with an
## older add-on lacks any added since, and every water shader then fails and the map draws plain white
## (#294). The add-on puts back any that are missing when it starts.

## Each setting's name, with its type as Godot writes it in project.godot and its starting value. The
## same as the [shader_globals] section of this project's project.godot.
const GLOBALS := {
	"sf_time": ["float", 0.0],
	"sf_haze": ["vec3", Vector3(0, 0, 0)],
	"sf_haze_density": ["float", 0.0],
	"sf_sun_direct": ["vec3", Vector3(0, 0, 0)],
	"sf_sun_to": ["vec3", Vector3(0, 1, 0)],
	"sf_sun_right": ["vec3", Vector3(1, 0, 0)],
	"sf_sun_up": ["vec3", Vector3(0, 0, 1)],
	"sf_fill": ["vec3", Vector3(0, 0, 0)],
	"sf_caustics": ["float", 0.0],
	"sf_shaft_light": ["float", 0.0],
	"sf_shaft_colour": ["vec3", Vector3(1, 1, 1)],
	"sf_surface": ["vec3", Vector3(1, 1, 1)],
	"sf_sea_base": ["float", 0.0],
	"sf_sea_ground": ["float", 0.0],
}

const TYPES := {
	"float": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
	"vec3": RenderingServer.GLOBAL_VAR_TYPE_VEC3,
}


## Adds every one of GLOBALS the project lacks, to its settings and to what draws now, and gives back the
## names added. The caller saves the settings, so that the next start has them too.
static func add_missing() -> PackedStringArray:
	var added := PackedStringArray()
	# Godot warns that asking for the list is slow, so it's asked once.
	var drawn := RenderingServer.global_shader_parameter_get_list()
	for global_name: String in GLOBALS:
		var key := "shader_globals/" + global_name
		if ProjectSettings.has_setting(key) and drawn.has(global_name):
			continue
		var type: String = GLOBALS[global_name][0]
		var value: Variant = GLOBALS[global_name][1]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, {"type": type, "value": value})
		if not drawn.has(global_name):
			RenderingServer.global_shader_parameter_add(global_name, TYPES[type], value)
		added.append(global_name)
	return added
