@tool
extends RefCounted
## Which release of the add-on this is. The packaging script writes it into plugin.cfg; in the game's
## own repository it says "dev".

const PLUGIN_CFG := "res://addons/smart_fellas_maps/plugin.cfg"
const RELEASES_URL := "https://github.com/wildware-uk/smart-fellas-map-maker/releases"
const UNKNOWN := "unknown"


static func number() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PLUGIN_CFG) != OK:
		return UNKNOWN
	return str(cfg.get_value("plugin", "version", UNKNOWN))


static func words() -> String:
	return "Smart Fellas map maker %s" % number()
