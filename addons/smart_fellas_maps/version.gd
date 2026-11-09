@tool
extends RefCounted
## Which release of the add-on this is. The packaging script writes it into plugin.cfg; in the game's
## own repository it says "dev".

const PLUGIN_CFG := "res://addons/smart_fellas_maps/plugin.cfg"
const RELEASES_URL := "https://github.com/wildware-uk/smart-fellas-map-maker/releases"
const UNKNOWN := "unknown"
## The map maker version the game must say, at least, for this add-on: what it can take from the add-on.
## The game's MAP_MAKER_VERSION in src/map/check.rs; raise the two together. 5: the game takes maps of
## any size and detail, with only guards against broken files (#299). 6: it takes any number of materials,
## play areas up to 4 km across and pictures past what fits, and grades every map it checks (#299). 7: it takes
## maps' own octopus poses, and draws them for the Pose panel with --pose-editor (#173).
const GAME_NEEDS := 7


static func number() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PLUGIN_CFG) != OK:
		return UNKNOWN
	return str(cfg.get_value("plugin", "version", UNKNOWN))


static func words() -> String:
	return "Smart Fellas map maker %s" % number()
