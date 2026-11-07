// A see-through reef piece, such as a decal or glass, that shows only its outside.
shader_type spatial;
render_mode cull_back;

#define SF_DITHERED
#include "res://addons/smart_fellas_maps/water/reef_lit.gdshaderinc"
