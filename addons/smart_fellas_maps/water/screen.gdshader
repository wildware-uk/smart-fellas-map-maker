// What the game does to the whole picture: light shafts, bloom, colour grading and tone mapping. A quad
// covers the screen and runs before anything see-through. Distance haze is already in the picture, from
// each solid thing's own material.
//
// Godot's own tone mapping is set to do nothing, so this picture is what reaches the screen. The bloom
// goes on before the shafts, the other way round from the game, because Godot's blurred copies of the
// picture come from before this pass. The shafts are faint and soft, so it hardly shows.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://addons/smart_fellas_maps/water/water_common.gdshaderinc"

uniform sampler2D screen_picture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler3D tone_table : filter_linear, repeat_disable;
uniform sampler2D shade_bands : filter_linear, repeat_enable;

// The lit water, as the game's FogVolume: how thick, how much light it scatters, its size and where its
// middle sits.
const float WATER_DENSITY = 0.03;
const float WATER_SCATTERING = 0.3;
const vec3 WATER_HALF = vec3(35.0, 15.5, 35.0);
const float WATER_MIDDLE = 11.5;
const vec3 FOG_COLOUR = vec3(0.52711, 0.88792, 1.0);
const vec3 LIGHT_TINT = vec3(1.0, 0.95597, 0.78741);
// The strength the water's light is worked out from, when the shaft light is at its full.
const float SHAFT_FOG_STRENGTH = 12.0;
// How many steps it marches: Medium's.
const int STEPS = 24;

// The light the water scatters toward the eye along `way`, up to `reach` metres, and how much of what
// lies behind still shows, in the alpha. `ahead` is where the camera faces.
vec4 shafts(vec3 eye, vec3 way, vec3 ahead, float reach) {
	vec3 low = vec3(eye.x, WATER_MIDDLE, eye.z) - WATER_HALF;
	vec3 high = vec3(eye.x, WATER_MIDDLE, eye.z) + WATER_HALF;
	vec3 inverse_way = 1.0 / way;
	vec3 one = (low - eye) * inverse_way;
	vec3 other = (high - eye) * inverse_way;
	vec3 near = min(one, other);
	vec3 far = max(one, other);
	float enter = max(max(max(near.x, near.y), near.z), 0.0);
	float leave = min(min(min(far.x, far.y), far.z), reach);
	if (leave <= enter) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	// Bevy shares the depth into the screen among its steps and then takes them along the ray, so a ray
	// off to the side of the view stops short. It shapes how the game's shafts look, so this does too.
	float forward = dot(way, ahead);
	float step_metres = (leave - enter) * forward / float(STEPS);
	float bounding = length(WATER_HALF);
	float falloff = exp(-WATER_DENSITY * bounding * WATER_SCATTERING);
	vec3 per_metre = sf_shaft_colour * FOG_COLOUR * LIGHT_TINT * falloff * WATER_SCATTERING * WATER_DENSITY * SHAFT_FOG_STRENGTH * sf_shaft_light;
	float each_step_lets_through = exp(-step_metres * WATER_DENSITY * WATER_SCATTERING);
	vec3 gathered = vec3(0.0);
	float behind = 1.0;
	for (int index = 0; index < STEPS; index++) {
		vec3 at = eye + way * (enter + step_metres * float(index));
		float light = sf_shaft_light_reaching(at, eye, shade_bands);
		behind *= each_step_lets_through;
		gathered += per_metre * step_metres * light * behind;
	}
	return vec4(gathered, behind);
}

// The game's bloom, as Bloom::NATURAL's sums come out: each smaller picture takes a share of the one
// above, and the first takes 15% of the screen.
vec3 bloomed(vec2 where, vec3 colour) {
	vec3 small = textureLod(screen_picture, where, 7.0).rgb;
	for (float level = 6.0; level >= 1.0; level -= 1.0) {
		small = mix(textureLod(screen_picture, where, level).rgb, small, 0.72);
	}
	return mix(colour, small, 0.15);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 colour = textureLod(screen_picture, SCREEN_UV, 0.0).rgb;
	colour = bloomed(SCREEN_UV, colour);
	if (sf_shaft_light > 0.0) {
		float depth = texture(screen_depth, SCREEN_UV).r;
		vec4 in_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vec3 at = (INV_VIEW_MATRIX * vec4(in_view.xyz / in_view.w, 1.0)).xyz;
		vec3 eye = INV_VIEW_MATRIX[3].xyz;
		vec3 way = normalize(at - eye);
		vec4 water = shafts(eye, way, -INV_VIEW_MATRIX[2].xyz, depth <= 0.0 ? 1000.0 : length(at - eye));
		colour = water.rgb + colour * water.a;
	}
	ALBEDO = sf_graded(colour, tone_table);
}
