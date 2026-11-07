// A reef piece with holes cut by its picture, such as a fence or a leaf, that shows both its sides.
shader_type spatial;
render_mode cull_disabled;

#define SF_CUT_OUT
#include "res://addons/smart_fellas_maps/water/reef_lit.gdshaderinc"
