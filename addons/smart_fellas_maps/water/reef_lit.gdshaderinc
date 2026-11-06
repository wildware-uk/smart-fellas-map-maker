// A reef piece lit as the game lights one: the port of the game's reef_lit and sway shaders.
// It does the game's lighting by hand, because only here can the sun carry the moving caustics:
// Godot's directional lights can't project a picture.
//
// The haze goes on after the light through Godot's FOG, as the game's does in its material, so that
// bloom later on spreads the hazed picture.

#include "res://addons/smart_fellas_maps/water/water_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
uniform sampler2DArray caustic_frames : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D shade_bands : filter_linear, repeat_enable;
uniform vec4 base_colour = vec4(1.0);
uniform float perceptual_roughness = 0.5;
// Lays the picture out by place in the world rather than by the mesh, for the sand: repeats a metre,
// then how far the middle of the map is from a corner of the seabed.
uniform vec2 world_layout = vec2(0.0);

// How freely this piece bends, and for a stiff coral, the height of its foot and how tall it is.
instance uniform float flex = 0.0;
instance uniform float stiff_foot = 0.0;
instance uniform float stiff_height = 0.0;

varying vec3 world_at;
varying vec2 uv_here;

// How the sun's picture repeats: the game's CAUSTICS_TILE, CAUSTICS_SLIDE and LOOP_SECONDS, and how many
// frames its loop has.
const float CAUSTICS_TILE = 5.0;
// 13 and 6 tiles every 600 s, as in the game.
const vec2 CAUSTICS_DRIFT = vec2(13.0, 6.0) * CAUSTICS_TILE / 600.0;
const float LOOP_SECONDS = 5.0;
const float FRAMES = 32.0;

// How far one m/s of current pushes a free tip, how fast a bend climbs a plant, the shortest height a
// bend is worked out over, and the most a bent point drops: the game's sway numbers.
const vec4 SWAY = vec4(4.2, 2.0, 0.1, 0.5);

vec3 current_at(vec3 position, float t) {
	vec3 sum = SF_DRIFT;
	for (int index = 0; index < 5; index++) {
		vec4 shape = SF_WAVE_SHAPE[index];
		vec4 push = SF_WAVE_PUSH[index];
		sum += push.xyz * sin(dot(shape.xyz, position) - shape.w * t + push.w);
	}
	return sum;
}

vec3 sway_offset(vec3 position, float height, float weight, float bend) {
	float above = max(height, 0.0);
	float t = sf_time - above / SWAY.y;
	vec3 push = current_at(position, t) * weight * bend * SWAY.x;
	float reach = max(above, SWAY.z);
	float drop = min(dot(push.xz, push.xz) / (2.0 * reach), above * SWAY.w);
	return push - vec3(0.0, drop, 0.0);
}

void vertex() {
	vec3 rest = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_at = rest;
	if (flex > 0.0) {
		float weight = COLOR.r;
		if (stiff_height > 0.0) {
			weight = clamp((VERTEX.y - stiff_foot) / stiff_height, 0.0, 1.0);
		}
		vec3 bent = sway_offset(rest, rest.y - MODEL_MATRIX[3].y, weight, flex);
		world_at = rest + bent;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * bent;
	}
	uv_here = UV;
	if (world_layout.x > 0.0) {
		uv_here = (rest.xz + world_layout.y) * world_layout.x;
	}
}

varying float sunlight_through;

// How much of the sun gets through at `at`, going by the caustics web, as the game's sun does with its
// light texture.
float caustic_web(vec3 at) {
	if (sf_caustics <= 0.0) {
		return 1.0;
	}
	vec2 slide = mod(CAUSTICS_DRIFT * sf_time, CAUSTICS_TILE);
	vec2 across = vec2(dot(at, sf_sun_right), dot(at, sf_sun_up)) - slide;
	vec2 place = across / (2.0 * CAUSTICS_TILE / 2.0) * vec2(-1.0, 1.0) + 0.5;
	float position = fract(sf_time / LOOP_SECONDS) * FRAMES;
	float from = floor(position);
	float to = mod(from + 1.0, FRAMES);
	float one = texture(caustic_frames, vec3(fract(place), from)).r;
	float other = texture(caustic_frames, vec3(fract(place), to)).r;
	float web = mix(one, other, position - from);
	return web + (1.0 - web) * (1.0 - sf_caustics);
}

// How much of the light in the shadows a surface mirrors, as Bevy works it out for a surface that
// reflects 4% head on.
float mirror_of_the_fill(float rough, float along_view) {
	vec4 r = rough * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
	float a004 = min(r.x * r.x, exp(-9.28 * along_view * log(2.0))) * r.x + r.y;
	vec2 f_ab = max(vec2(-1.04, 1.04) * a004 + r.zw, vec2(0.00005));
	return 0.04 * f_ab.x + f_ab.y;
}

void fragment() {
	vec4 colour = texture(albedo_tex, uv_here) * base_colour;
	ALBEDO = colour.rgb;
	ROUGHNESS = perceptual_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	sunlight_through = caustic_web(world_at);
	EMISSION = sf_fill * mirror_of_the_fill(perceptual_roughness, max(dot(NORMAL, VIEW), 0.0001));
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	if (sf_shaft_light > 0.0) {
		// The game's shaft light falls faintly on the reef too, shadows or not. Godot has no way to make a
		// real light see only the shade, so this does its sums by hand.
		vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
		float facing = max(dot(world_normal, sf_sun_to), 0.0);
		float reaching = sf_shaft_light_reaching(world_at, eye, shade_bands);
		EMISSION += ALBEDO * sf_shaft_colour * sf_shaft_light * reaching * facing / SF_PI;
	}
	vec3 from_eye = world_at - eye;
	float distance = length(from_eye);
	FOG = sf_haze_at(from_eye / distance, distance);
}

float schlick(float f0, float f90, float u) {
	float m = clamp(1.0 - u, 0.0, 1.0);
	return f0 + (f90 - f0) * m * m * m * m * m;
}

void light() {
	vec3 towards = normalize(LIGHT + VIEW);
	float along_light = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float along_view = max(dot(NORMAL, VIEW), 0.0001);
	float along_half = clamp(dot(NORMAL, towards), 0.0, 1.0);
	float light_half = clamp(dot(LIGHT, towards), 0.0, 1.0);
	float rough = max(ROUGHNESS, 0.089);
	rough = rough * rough;

	float f90 = 0.5 + 2.0 * rough * light_half * light_half;
	float burley = schlick(1.0, f90, along_light) * schlick(1.0, f90, along_view) / SF_PI;

	float a2 = rough * rough;
	float d = (along_half * along_half) * (a2 - 1.0) + 1.0;
	float spread = a2 / (SF_PI * d * d);
	float seen = along_view * sqrt(along_light * along_light * (1.0 - a2) + a2);
	float blocked = along_light * sqrt(along_view * along_view * (1.0 - a2) + a2);
	float visible = 0.5 / max(seen + blocked, 0.0001);
	float mirror = spread * visible * schlick(0.04, 1.0, light_half);

	float through = LIGHT_IS_DIRECTIONAL ? sunlight_through : 1.0;
	vec3 arriving = LIGHT_COLOR * ATTENUATION * through * along_light;
	DIFFUSE_LIGHT += arriving * burley;
	SPECULAR_LIGHT += arriving * mirror;
}
