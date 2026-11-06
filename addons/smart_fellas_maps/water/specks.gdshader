// The specks drifting around the camera: the port of the game's own. Each one rides the same
// current as the plants and wraps round in a box that follows the camera. The game moves them on the
// CPU a frame at a time. Here a speck's place is worked out from the time alone, which comes to the same
// drift. These come after the screen shader, so they do their own haze and grading.
shader_type spatial;
render_mode unshaded, skip_vertex_transform, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, blend_mix;

#include "res://addons/smart_fellas_maps/water/water_common.gdshaderinc"

uniform sampler3D tone_table : filter_linear, repeat_disable;
uniform vec3 speck_colour = vec3(0.7, 0.93, 1.0);

const float BOX_HALF = 15.0;
const float SPECK_ALPHA = 0.55;

varying vec3 view_at;
varying vec2 round_uv;

// Where a speck has drifted from `start` in `t` seconds: the sum of its own slow drift and the current.
vec3 drifted(vec3 start, vec3 own, float t) {
	vec3 sum = start + (SF_DRIFT + own) * t;
	for (int index = 0; index < 5; index++) {
		vec4 shape = SF_WAVE_SHAPE[index];
		vec4 push = SF_WAVE_PUSH[index];
		sum += push.xyz / shape.w * cos(dot(shape.xyz, start) - shape.w * t + push.w);
	}
	return sum;
}

void vertex() {
	vec3 start = INSTANCE_CUSTOM.xyz;
	vec3 own = COLOR.xyz * 2.0 - 1.0;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 at = drifted(start, own * 0.02, sf_time);
	vec3 wrapped = eye + mod(at - eye + BOX_HALF, BOX_HALF * 2.0) - BOX_HALF;
	vec4 in_view = VIEW_MATRIX * vec4(wrapped, 1.0);
	in_view.xy += VERTEX.xy * INSTANCE_CUSTOM.w * 2.0;
	view_at = in_view.xyz;
	round_uv = VERTEX.xy * 2.0;
	VERTEX = in_view.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	if (dot(round_uv, round_uv) > 1.0) {
		discard;
	}
	vec3 way = (INV_VIEW_MATRIX * vec4(normalize(view_at), 0.0)).xyz;
	vec4 haze = sf_haze_at(way, length(view_at));
	ALBEDO = sf_graded(mix(speck_colour, haze.rgb, haze.a), tone_table);
	ALPHA = SPECK_ALPHA;
}
