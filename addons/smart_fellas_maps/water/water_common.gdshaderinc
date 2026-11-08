// The game's water, in Godot's shader language: what several of the add-on's shaders share.
//
// water_view.gd sets these numbers from the map's water section, through water_look.gd. The game's
// side of them is its water look, its sea effects and Bevy's fog and tone mapping shaders.

// The water's clock, in seconds.
global uniform float sf_time;
// The haze's colour as light, and how quickly it thickens: the square of distance times this.
global uniform vec3 sf_haze;
global uniform float sf_haze_density;
// The sun on the scale the picture is drawn at, the way to it, and the sideways and upward directions
// across its beam, which the caustics are laid out in.
global uniform vec3 sf_sun_direct;
global uniform vec3 sf_sun_to;
global uniform vec3 sf_sun_right;
global uniform vec3 sf_sun_up;
// The light in the shadows, on the scale the picture is drawn at.
global uniform vec3 sf_fill;
// How much of the caustics web shows, from 0 to 1.
global uniform float sf_caustics;
// How bright the shaft light is, on the scale the picture is drawn at, and its colour.
global uniform float sf_shaft_light;
global uniform vec3 sf_shaft_colour;
// The surface overhead's share of its full brightness, per colour.
global uniform vec3 sf_surface;
// The height the surface and the shade are measured up from: the map's sea base, as the game's
// surface::sea_base. Then the ground the shaft light aims at and the lit water reaches down to: the play
// area's base, under the sea base only on a box taller than the Reef.
global uniform float sf_sea_base;
global uniform float sf_sea_ground;

const float SF_PI = 3.14159265358979;
// The share of the sun's glow the haze picks up, and how tightly it gathers round the sun: the game's
// SUN_GLOW and SUN_GLOW_EXPONENT.
const vec3 SF_SUN_GLOW = vec3(0.68990, 1.0, 0.78741) * 0.08;
const float SF_SUN_GLOW_EXPONENT = 8.0;

// The water current, as `water::current_at` in the game: the steady drift, then per wave its wave
// vector and angular speed, then its push and phase.
const vec3 SF_DRIFT = vec3(0.12, 0.0, 0.05);
const vec4 SF_WAVE_SHAPE[5] = {
	vec4(0.09, 0.0, 0.03, 40.0 * 6.283185307 / 600.0),
	vec4(-0.05, 0.0, 0.16, 68.0 * 6.283185307 / 600.0),
	vec4(0.31, 0.04, -0.22, 131.0 * 6.283185307 / 600.0),
	vec4(-0.42, 0.0, -0.37, 184.0 * 6.283185307 / 600.0),
	vec4(0.13, 0.0, 0.21, 85.0 * 6.283185307 / 600.0)
};
const vec4 SF_WAVE_PUSH[5] = {
	vec4(0.16, 0.0, 0.06, 0.0),
	vec4(-0.04, 0.0, 0.11, 1.3),
	vec4(0.06, 0.0, -0.05, 2.9),
	vec4(-0.04, 0.0, -0.04, 4.4),
	vec4(0.0, 0.035, 0.0, 0.7)
};

// The shaft light, as the game's distant spot light: how high along the sun it sits, how far it reaches,
// and its cone.
const float SF_SHAFT_HEIGHT = 150.0;
const float SF_SHAFT_RANGE = 375.0;
const float SF_SHAFT_COS_INNER = 0.97590;
const float SF_SHAFT_COS_OUTER = 0.95534;
// The shade it shines through: its height over the sea base, one repeat's width, its drift, and how far from a repeat's edge
// the plane's middle sits.
const float SF_SHADE_HEIGHT = 26.5;
const float SF_SHADE_TILE = 24.0;
// 6 and 3 tiles every 600 s, as in the game.
const vec2 SF_SHADE_DRIFT = vec2(6.0, 3.0) * SF_SHADE_TILE / 600.0;
const float SF_PLANE_HALF = 180.0;

// The share of the shaft light that reaches `at`, for an eye at `eye`: how far it has come, how far inside
// its cone that is, and whether it got past the shade.
float sf_shaft_light_reaching(vec3 at, vec3 eye, sampler2D bands) {
	vec3 from = vec3(eye.x, sf_sea_ground, eye.z) + sf_sun_to * SF_SHAFT_HEIGHT;
	vec3 to_light = from - at;
	float apart = dot(to_light, to_light);
	float range = apart / (SF_SHAFT_RANGE * SF_SHAFT_RANGE);
	range = clamp(1.0 - range * range, 0.0, 1.0);
	float in_cone = clamp((dot(sf_sun_to, normalize(to_light)) - SF_SHAFT_COS_OUTER) / (SF_SHAFT_COS_INNER - SF_SHAFT_COS_OUTER), 0.0, 1.0);
	float past = 1.0;
	float share = (sf_sea_base + SF_SHADE_HEIGHT - at.y) / (from.y - at.y);
	if (share >= 0.0) {
		vec3 hit = at + to_light * share;
		vec2 moved = hit.xz - SF_SHADE_DRIFT * sf_time;
		vec2 place = vec2(SF_PLANE_HALF - moved.x, SF_PLANE_HALF + moved.y) / SF_SHADE_TILE;
		past = 1.0 - smoothstep(0.2, 0.8, texture(bands, place).a);
	}
	return range * range / apart * in_cone * in_cone * past;
}

// The distance haze seen `distance` metres away along `way`, a unit direction: its colour, and in the
// alpha how much of what lies there it hides.
vec4 sf_haze_at(vec3 way, float distance) {
	float glow = pow(max(dot(way, sf_sun_to), 0.0), SF_SUN_GLOW_EXPONENT);
	float thick = distance * sf_haze_density;
	return vec4(sf_haze + glow * sf_sun_direct * SF_SUN_GLOW, 1.0 - exp(-thick * thick));
}

// The game's colour grading and tone mapping, in Bevy's order: contrast on the middle tones, then the
// TonyMcMapface table, then saturation on what comes out.
vec3 sf_graded(vec3 colour, sampler3D table) {
	vec3 graded = max(colour, vec3(0.0));
	float level = (graded.r + graded.g + graded.b) / 3.0;
	float middle = 0.0;
	if (level < 0.1) {
		middle = 0.0;
	} else if (level < 0.3) {
		middle = (level - 0.2) * 5.0 + 0.5;
	} else if (level < 0.6) {
		middle = 1.0;
	} else if (level < 0.8) {
		middle = 1.0 - ((level - 0.7) * 5.0 + 0.5);
	} else {
		middle = 0.0;
	}
	float contrast = mix(1.0, 1.1, middle);
	graded = max(0.5 + (graded - 0.5) * contrast, vec3(0.0));
	vec3 place = graded / (graded + 1.0) * (47.0 / 48.0) + 0.5 / 48.0;
	graded = textureLod(table, clamp(place, 0.0, 1.0), 0.0).rgb;
	float luma = dot(graded, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(luma), graded, 1.25);
}
