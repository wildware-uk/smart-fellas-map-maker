// The bright rippling surface overhead, seen from below: the port of the game's own. The game
// has two planes, a base and a layer of glints laid over it. This does both on one plane, so that the
// glints don't need the see-through pass, which runs after the screen shader.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://addons/smart_fellas_maps/water/water_common.gdshaderinc"

uniform sampler2D base_ripples : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glint_ripples : source_color, filter_linear_mipmap, repeat_enable;

const float PLANE_HALF = 180.0;
const float BASE_TILE = 11.0;
// The game's drifts: a whole number of tiles every 600 s (19 and 10 here, -19 and 27 for the glints).
const vec2 BASE_DRIFT = vec2(19.0, 10.0) * BASE_TILE / 600.0;
const vec3 BASE_COLOUR = vec3(4.2, 6.8, 7.0);
const float GLINTS_TILE = 7.0;
const vec2 GLINTS_DRIFT = vec2(-19.0, 27.0) * GLINTS_TILE / 600.0;
const vec3 GLINTS_COLOUR = vec3(3.0, 3.4, 3.2);
// How far under the base the game's glints lie, in metres.
const float GLINTS_UNDER = 0.3;

varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 place(vec2 where, vec2 drift, float tile) {
	vec2 moved = where - drift * sf_time;
	return vec2(PLANE_HALF - moved.x, PLANE_HALF + moved.y) / tile;
}

void fragment() {
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float to_glints = (world_at.y - GLINTS_UNDER - eye.y) / (world_at.y - eye.y);
	vec3 at_glints = eye + (world_at - eye) * to_glints;
	vec3 base = texture(base_ripples, place(world_at.xz, BASE_DRIFT, BASE_TILE)).rgb * BASE_COLOUR;
	vec4 glint = texture(glint_ripples, place(at_glints.xz, GLINTS_DRIFT, GLINTS_TILE));
	vec3 colour = mix(base, glint.rgb * GLINTS_COLOUR, glint.a) * sf_surface;
	vec3 from_eye = world_at - eye;
	float distance = length(from_eye);
	vec4 haze = sf_haze_at(from_eye / distance, distance);
	ALBEDO = mix(colour, haze.rgb, haze.a);
}
