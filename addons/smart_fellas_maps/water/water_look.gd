@tool
extends RefCounted
## How the water looks at a depth: the same sums as the game's water look, for the view in Godot.
## The game's own tests hold this file and the game's up against each other, so they can't drift apart.

const SHALLOW_DEPTH := 28.0
const DEEP_DEPTH := 120.0
const MIDNIGHT_DEPTH := 500.0

const SHALLOW_VISIBILITY := 70.0

## What a map's water section may hold, as {name: [lowest, highest]}, as the game's checker has it.
const DEPTHS := Vector2(SHALLOW_DEPTH, 1000.0)
const LIMITS := {
	"visibility": Vector2(5.0, 300.0),
	"sun": Vector2(0.0, 50000.0),
	"fill": Vector2(0.0, 5000.0),
	"shafts": Vector2(0.0, 12.0),
	"caustics": Vector2(0.0, 1.0),
	"surface": Vector2(0.0, 1.0),
}

const _HAZE := Vector3(0.22, 0.68, 0.75)
const _SUN := Color(1.0, 0.97, 0.9)
const _SUN_LUX := 14000.0
const _FILL := Color(0.55, 0.85, 1.0)
const _FILL_BRIGHTNESS := 800.0
const _SPECK := Vector3(0.86, 0.97, 1.0)
const SHALLOW_SHAFT_STRENGTH := 12.0

const _RED_FADES := 0.055
const _GREEN_FADES := 0.003
const _FILL_HOLDS_ON := 0.65
const _QUICK_SHARE := 0.6
const _QUICK_FADE := 70.0
const _SLOW_FADE := 500.0
const _SHORTEST_VIEW := 18.0
const _VIEW_FADES_OVER := 170.0
const _SUN_GONE_AT := 180.0
const _CAUSTICS_GONE_AT := 250.0
const _SHAFTS_GONE_AT := 200.0
const _SURFACE_GONE_AT := 160.0


## The look at `depth` metres, with any of `overrides` in place of what depth gives: a colour under
## "haze", and numbers under the names in LIMITS.
static func look_of(depth: float, overrides: Dictionary = {}) -> Dictionary:
	var look := _look_at_depth(depth)
	if overrides.has("haze"):
		var haze: Color = overrides["haze"]
		look["haze"] = Vector3(haze.r, haze.g, haze.b)
	for name: String in LIMITS:
		if overrides.has(name):
			look[{"sun": "sun_lux", "fill": "fill_brightness", "shafts": "shaft_strength"}.get(name, name)] = overrides[name]
	return look


static func _look_at_depth(depth: float) -> Dictionary:
	var below := depth - SHALLOW_DEPTH
	var light := _QUICK_SHARE * exp(-below / _QUICK_FADE) + (1.0 - _QUICK_SHARE) * exp(-below / _SLOW_FADE)
	var tint := Vector3(exp(-_RED_FADES * below), exp(-_GREEN_FADES * below), 1.0)
	var perceived := Vector3(sqrt(tint.x), sqrt(tint.y), 1.0)
	return {
		"haze": _HAZE * perceived * light,
		"visibility": _SHORTEST_VIEW + (SHALLOW_VISIBILITY - _SHORTEST_VIEW) * exp(-below / _VIEW_FADES_OVER),
		"sun": _linear(_SUN) * tint,
		"sun_lux": _SUN_LUX * light * _still_there(depth, _SUN_GONE_AT),
		"fill": _linear(_FILL) * tint,
		"fill_brightness": _FILL_BRIGHTNESS * pow(light, _FILL_HOLDS_ON),
		"shaft_strength": SHALLOW_SHAFT_STRENGTH * light * _still_there(depth, _SHAFTS_GONE_AT),
		"caustics": _still_there(depth, _CAUSTICS_GONE_AT),
		"surface": light * _still_there(depth, _SURFACE_GONE_AT),
		"tint": tint,
		"speck": _SPECK * perceived * sqrt(light),
	}


## What is left of something that fades out from the shallows to nothing at `gone_at` metres.
static func _still_there(depth: float, gone_at: float) -> float:
	return 1.0 - smoothstep(SHALLOW_DEPTH, gone_at, depth)


static func _linear(colour: Color) -> Vector3:
	var linear := colour.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b)


## What is wrong with a map's water settings, in the words the game's checker uses.
static func problems_with(depth: float, overrides: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if depth < DEPTHS.x or depth > DEPTHS.y or is_nan(depth):
		found.append("The water's depth is %s. It must be from %s to %s." % [depth, DEPTHS.x, DEPTHS.y])
	for name: String in LIMITS:
		if not overrides.has(name):
			continue
		var value: float = overrides[name]
		var limits: Vector2 = LIMITS[name]
		if value < limits.x or value > limits.y or is_nan(value):
			found.append("The water's %s is %s. It must be from %s to %s." % [name, value, limits.x, limits.y])
	return found


## The map's water section as map.ron writes it, or nothing if it is all as the shallows would have it.
static func section_text(depth: float, overrides: Dictionary) -> String:
	if depth == SHALLOW_DEPTH and overrides.is_empty():
		return ""
	var parts: Array[String] = ["depth: %.9f" % depth]
	if overrides.has("haze"):
		var haze: Color = overrides["haze"]
		parts.append("haze: Some((%.9f, %.9f, %.9f))" % [haze.r, haze.g, haze.b])
	for name: String in LIMITS:
		if overrides.has(name):
			parts.append("%s: Some(%.9f)" % [name, overrides[name]])
	return "    water: (%s),\n" % ", ".join(parts)
