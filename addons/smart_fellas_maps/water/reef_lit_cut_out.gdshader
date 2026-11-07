// A reef piece with holes cut by its picture, such as a fence, that shows only its outside.
shader_type spatial;
render_mode cull_back;

#define SF_CUT_OUT
#include "res://addons/smart_fellas_maps/water/reef_lit.gdshaderinc"
