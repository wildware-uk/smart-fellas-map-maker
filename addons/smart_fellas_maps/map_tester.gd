@tool
extends RefCounted
## What the Export Map and Test Map buttons ask of the game: to run its checker over a package, and to
## host a game on it with bots. Nothing here has a window, so a test can run all of it.

const GameFinder := preload("game_finder.gd")
const MapExporter := preload("map_exporter.gd")
const Version := preload("version.gd")

## The bots a test game starts with, octopuses then divers. The game keeps to the map's team sizes.
const BOTS := "2,2"
const BOTS_VAR := "INKOGNITO_BOTS"
## The game's usual port, and how many after it to look through for a free one.
const FIRST_PORT := 5888
const PORTS_TO_TRY := 32
## How long the checker gets, in seconds. A game from before Test Map doesn't know the checker's flag and
## would open its menu instead, so it can't be left to run for ever.
const CHECK_MILLISECONDS := 30000
## What the checker leaves with when it has found problems, and what marks each line of them. On Linux
## the game's starter can also leave with 1, and print lines of its own, when a library is missing.
const PROBLEMS_EXIT := 1
const PROBLEM_MARK := "map problem: "
## What marks the line where the game says which folder its maps are in.
const MAPS_FOLDER_MARK := "maps folder: "
## What marks the line where the game says which map maker version it is at. A game from before it said
## one says nothing.
const GAME_VERSION_MARK := "map maker version: "
## What marks the line where the game says a map's performance grade, and each line saying one of the things
## that cost it the most, heaviest first (#299). A game from before maps were graded says neither.
const GRADE_MARK := "map grade: "
const MEANING_MARK := "map grade means: "
const HEAVIEST_MARK := "map heaviest: "
## What marks each line where the game says what is wrong with one of the map's scripts.
const SCRIPT_PROBLEM_MARK := "script problem: "
## The types file Export keeps in a map's scripts folder, so the map maker's editor completes and checks
## their scripts, and the editor settings it puts beside it if there are none.
const TYPES_FILE := "res://addons/smart_fellas_maps/scripting/smart-fellas.d.ts"
const EDITOR_SETTINGS_FILE := "res://addons/smart_fellas_maps/scripting/tsconfig.json"
## Said beside a map with scripts that passed: where they run, wherever the map goes.
const SCRIPTS_RUN_WHERE := "This map has scripts. Those in its scripts folder run in the host's game, those in client/ on each player's own PC, and those in shared/ on both: in Test Map, My maps, lobbies and on the Workshop."
## Where a map maker's own choice of the game's maps folder is kept, in Godot's editor settings, for
## when the game can't say.
const CHOSEN_MAPS_KEY := "smart_fellas/maps_folder"
## What the checker calls the things on a map, which its problems about them start with, then a number.
const NAMED_THINGS := [
	"Piece", "Octopus spawn", "Diver spawn", "Food patch", "Food spot", "Fish", "Anglerfish spot",
	"Lantern fish school", "Jellyfish group", "Goblin shark route point", "Wrasse spot", "Stingray stop", "Eel hole",
	"Groper hole", "Garden eel field", "Trigger zone",
]


enum State { EXPORT_REFUSED, NO_GAME, NO_MAPS_FOLDER, CANT_CHECK, OLD_GAME, PROBLEMS, FINE }


## What to run to check the package in `folder`.
static func check_command(game: String, folder: String) -> Dictionary:
	return {"program": game, "args": PackedStringArray(["--check-map", folder])}


## What to run to build the scripts in `folder` into `out`.
static func build_command(game: String, folder: String, out: String) -> Dictionary:
	return {"program": game, "args": PackedStringArray(["--build-script", folder, out])}


## What to run to ask the game where it keeps its maps.
static func maps_folder_command(game: String) -> Dictionary:
	return {"program": game, "args": PackedStringArray(["--maps-folder"])}


## What to run to play the package in `folder` on `port`, with what it needs in its surroundings.
static func play_command(game: String, folder: String, port: int) -> Dictionary:
	return {"program": game, "args": PackedStringArray(["--test-map", folder, str(port)]), "variables": {BOTS_VAR: BOTS}}


## The first port nothing else on this computer is using, so that a game left open doesn't stop the test.
static func free_port() -> int:
	for port in range(FIRST_PORT, FIRST_PORT + PORTS_TO_TRY):
		var probe := PacketPeerUDP.new()
		var free := probe.bind(port) == OK
		probe.close()
		if free:
			return port
	return FIRST_PORT


## Starts the game on `folder`. Gives back its process number, or -1 if it wouldn't start.
static func play(game: String, folder: String) -> int:
	var command := play_command(game, folder, free_port())
	for variable: String in command["variables"]:
		OS.set_environment(variable, command["variables"][variable])
	var process := OS.create_process(command["program"], command["args"])
	for variable: String in command["variables"]:
		OS.unset_environment(variable)
	return process


## Runs the game's checker over `folder`, frame by frame so that the editor doesn't freeze.
## Gives back {"problems": what it said} or {"failed": what went wrong, in plain words}.
static func check(game: String, folder: String, tree: SceneTree) -> Dictionary:
	if folder.begins_with("//") or folder.begins_with("\\\\") or not folder.is_absolute_path():
		return {"failed": "The game only opens maps on this computer, and this one went to %s. Keep the project on a local drive." % folder}
	var command := check_command(game, folder)
	var running := OS.execute_with_pipe(command["program"], command["args"], false)
	if running.is_empty():
		return {"failed": "Can't run the game at %s. Check that it's there and is allowed to run." % game}
	var pid: int = running["pid"]
	var pipe: FileAccess = running["stdio"]
	var said := ""
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		said += _read_what_waits(pipe)
		if Time.get_ticks_msec() - started > CHECK_MILLISECONDS:
			OS.kill(pid)
			return {"failed": "The game at %s didn't answer. It may be too old to check maps: update it and try again." % game}
		await tree.process_frame
	said += _read_what_waits(pipe)
	return read_answer(OS.get_process_exit_code(pid), said, game)


## Asks the game which folder it lists maps from, frame by frame so the editor doesn't freeze.
## Gives back {"folder": where} or {"failed": what went wrong, in plain words}.
static func ask_maps_folder(game: String, tree: SceneTree) -> Dictionary:
	var command := maps_folder_command(game)
	var running := OS.execute_with_pipe(command["program"], command["args"], false)
	if running.is_empty():
		return {"failed": "Can't run the game at %s. Check that it's there and is allowed to run." % game}
	var pid: int = running["pid"]
	var pipe: FileAccess = running["stdio"]
	var said := ""
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		said += _read_what_waits(pipe)
		if Time.get_ticks_msec() - started > CHECK_MILLISECONDS:
			OS.kill(pid)
			return {"failed": "The game at %s didn't say where its maps go. It may be too old: update it and try again." % game}
		await tree.process_frame
	said += _read_what_waits(pipe)
	return read_maps_folder(OS.get_process_exit_code(pid), said, game)


## Builds the map's scripts in `folder` with the game, frame by frame so that the editor doesn't freeze,
## into a folder of the add-on's own for the map called `map_name`. Keeps the types file in `folder`
## first. Gives back {"built": the folder of .js files}, {"problems": what is wrong, a line each, naming
## the file and line}, or {"failed": what went wrong, in plain words}.
static func build_scripts(game: String, folder: String, map_name: String, tree: SceneTree) -> Dictionary:
	var source := ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(source):
		return {"problems": ["The map's scripts folder %s isn't there. Choose it again under Scripts in the Inspector, or empty it for none." % folder]}
	keep_types_file(source)
	var out := ProjectSettings.globalize_path("user://smart_fellas_scripts").path_join(MapExporter._folder_name(map_name))
	MapExporter._remove_folder(out)
	var command := build_command(game, source, out)
	var running := OS.execute_with_pipe(command["program"], command["args"], false)
	if running.is_empty():
		return {"failed": "Can't run the game at %s. Check that it's there and is allowed to run." % game}
	var pid: int = running["pid"]
	var pipe: FileAccess = running["stdio"]
	var said := ""
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		said += _read_what_waits(pipe)
		if Time.get_ticks_msec() - started > CHECK_MILLISECONDS:
			OS.kill(pid)
			return {"failed": "The game at %s didn't build the map's scripts. It may be too old: update it and try again." % game}
		await tree.process_frame
	said += _read_what_waits(pipe)
	return read_build_answer(OS.get_process_exit_code(pid), said, game, out)


## What the game's answer to building scripts means: 0 is built, 1 with marked lines is problems with the
## scripts, and anything else is the game not getting as far as them.
## Either answer has "older" too if the game is older than the add-on.
static func read_build_answer(code: int, said: String, game: String, out: String) -> Dictionary:
	var older := is_older(said)
	if code == 0:
		return _noting_older({"built": out}, older)
	var problems: Array[String] = []
	var others: Array[String] = []
	for line in _lines_of(said):
		if line.begins_with(SCRIPT_PROBLEM_MARK):
			problems.append(line.trim_prefix(SCRIPT_PROBLEM_MARK))
		elif not line.begins_with(GAME_VERSION_MARK):
			others.append(line)
	if code == PROBLEMS_EXIT and not problems.is_empty():
		return _noting_older({"problems": problems}, older)
	var words := "The game at %s stopped with error %d before it could build the map's scripts." % [game, code]
	if others.is_empty():
		return {"failed": words + " Try opening it by itself."}
	return {"failed": "%s It said:\n%s" % [words, "\n".join(others)]}


## Puts the add-on's types file in the scripts folder `source`, in place of an older one, and editor
## settings beside it if it has none, so the map maker's editor knows the game's API.
static func keep_types_file(source: String) -> void:
	var types := FileAccess.get_file_as_bytes(TYPES_FILE)
	var kept := source.path_join(TYPES_FILE.get_file())
	if not types.is_empty() and FileAccess.get_file_as_bytes(kept) != types:
		var file := FileAccess.open(kept, FileAccess.WRITE)
		if file != null:
			file.store_buffer(types)
			file.close()
	var settings := source.path_join(EDITOR_SETTINGS_FILE.get_file())
	if not FileAccess.file_exists(settings):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(EDITOR_SETTINGS_FILE), settings)


## What the game said about its maps folder: the marked line, if it left with 0.
static func read_maps_folder(code: int, said: String, game: String) -> Dictionary:
	if code == 0:
		for line in _lines_of(said):
			if line.begins_with(MAPS_FOLDER_MARK):
				return {"folder": line.trim_prefix(MAPS_FOLDER_MARK)}
	return {"failed": "The game at %s didn't say where its maps go. It may be too old: update it and try again." % game}


## Where Export puts maps so that the game lists them under My maps: the folder the game names, or the
## one the map maker chose before if the game can't say. Gives back {"folder", "game"} or {"failed",
## and "game" if it was found}.
static func find_maps_folder(chosen_game: String, chosen_maps: String, tree: SceneTree) -> Dictionary:
	var game := GameFinder.starter_of(GameFinder.find(chosen_game))
	var why := ""
	if game.is_empty():
		why = GameFinder.not_found_words()
	else:
		var asked := await ask_maps_folder(game, tree)
		if asked.has("folder"):
			return {"folder": asked["folder"], "game": game}
		why = asked["failed"]
	if not chosen_maps.is_empty() and DirAccess.dir_exists_absolute(chosen_maps):
		return {"folder": chosen_maps, "game": game}
	var lost := {"failed": "Can't find the game's maps folder, so the map hasn't been exported. %s\n\nYou can choose the game's maps folder once and it's remembered, or use Export to Folder to write it somewhere else." % why}
	if not game.is_empty():
		lost["game"] = game
	return lost


## What the Export Map and Test Map buttons do: export straight into the game's maps folder, where it
## shows under My maps, then check it with the game. As export_and_check, plus "into_game" when it went
## to the game's folder.
static func export_into_game(root: Node, chosen_game: String, chosen_maps: String, tree: SceneTree) -> Dictionary:
	var found := await find_maps_folder(chosen_game, chosen_maps, tree)
	if found.has("failed"):
		var state := State.NO_MAPS_FOLDER if found.has("game") else State.NO_GAME
		return {"state": state, "words": found["failed"], "lines": []}
	var result := await export_and_check(root, found["folder"], chosen_game, tree, true)
	result["into_game"] = true
	return result


## What the game's answer means: 0 is fine whatever it printed, 1 with marked lines is problems with the
## map, and anything else is the game not getting as far as the map. Either of the first two has "older"
## too if the game is older than the add-on, as its problems may be ones a newer game has done away with.
static func read_answer(code: int, said: String, game: String) -> Dictionary:
	var problems: Array[String] = []
	var older := is_older(said)
	if code == 0:
		return _noting_older(read_grade(said, {"problems": problems}), older)
	var others: Array[String] = []
	for line in _lines_of(said):
		if line.begins_with(PROBLEM_MARK):
			problems.append(line.trim_prefix(PROBLEM_MARK))
		elif not line.begins_with(GAME_VERSION_MARK):
			others.append(line)
	if code == PROBLEMS_EXIT and not problems.is_empty():
		return _noting_older({"problems": problems}, older)
	var words := "The game at %s stopped with error %d before it could check the map." % [game, code]
	if others.is_empty():
		return {"failed": words + " Try opening it by itself."}
	return {"failed": "%s It said:\n%s" % [words, "\n".join(others)]}


## `answer` with the performance grade the game said, as "grade", what it means for a player, as
## "meaning", and what costs the map the most, as "heaviest", if it said them.
static func read_grade(said: String, answer: Dictionary) -> Dictionary:
	var heaviest: Array[String] = []
	for line in _lines_of(said):
		if line.begins_with(GRADE_MARK):
			answer["grade"] = line.trim_prefix(GRADE_MARK)
		elif line.begins_with(MEANING_MARK):
			answer["meaning"] = line.trim_prefix(MEANING_MARK)
		elif line.begins_with(HEAVIEST_MARK):
			heaviest.append(line.trim_prefix(HEAVIEST_MARK))
	if answer.has("grade"):
		answer["heaviest"] = heaviest
	return answer


## The grade in a few lines, as the Map panel and Export's results say it: "Performance: Heavy, may run
## slowly on mid-level computers." and what costs it the most. Empty if the game said no grade.
static func grade_words(answer: Dictionary) -> String:
	if not answer.has("grade"):
		return ""
	var words := "Performance: %s" % answer["grade"]
	if answer.has("meaning"):
		words += ", %s." % answer["meaning"]
	var heaviest: Array = answer.get("heaviest", [])
	if not heaviest.is_empty():
		words += " What costs it the most:"
		for weight: String in heaviest:
			words += "\n  - %s" % weight
	return words


## Whether what the game said shows it older than this add-on: a map maker version below what the add-on
## needs, or none, as a game from before it said one.
static func is_older(said: String) -> bool:
	for line in _lines_of(said):
		if line.begins_with(GAME_VERSION_MARK):
			var number := line.trim_prefix(GAME_VERSION_MARK)
			return not number.is_valid_int() or number.to_int() < Version.GAME_NEEDS
	return true


## What to tell a map maker whose game is older than the add-on and found fault with `what`, before
## anything that game said.
static func older_words(game: String, what: String) -> String:
	return "Your Smart Fellas is older than this map maker, so it can't %s properly. Update the game in Steam (if you play the beta, on the beta branch), then try again.\n\n(The game is at %s.)" % [what, game]


## Said first beside a map an older game took: it still opens, but the map maker should update it.
static func older_but_took_it(game: String) -> Dictionary:
	return {"words": "Your Smart Fellas is older than this map maker. It took this map, but update the game in Steam (if you play the beta, on the beta branch) so it knows everything the map maker does. (The game is at %s.)" % game, "node": null}


## What an older game said was wrong, put away behind Details, as the newer game may not say it.
static func _said_by_older(problems: Array, about: String) -> Dictionary:
	var count := "1 problem" if problems.size() == 1 else "%d problems" % problems.size()
	return {"words": "The older game also listed %s with %s, which an up-to-date game may not:" % [count, about], "node": null, "details": problems}


static func _noting_older(answer: Dictionary, older: bool) -> Dictionary:
	if older:
		answer["older"] = true
	return answer


static func _read_what_waits(pipe: FileAccess) -> String:
	var bytes := pipe.get_buffer(pipe.get_length())
	return bytes.get_string_from_utf8()


static func _lines_of(text: String) -> Array[String]:
	var lines: Array[String] = []
	for line in text.split("\n", false):
		var words := line.strip_edges()
		if not words.is_empty():
			lines.append(words)
	return lines


## What on the map a problem from the checker is about, as export_map's "sources" hold it: a node, or
## words for something that has none. Null if the problem isn't about any one thing.
static func source_of(problem: String, sources: Dictionary) -> Variant:
	for thing: String in NAMED_THINGS:
		if not problem.begins_with(thing + " "):
			continue
		var number := problem.substr(thing.length() + 1).get_slice(" ", 0)
		if not number.is_valid_int() or not sources.has(thing):
			return null
		var index := number.to_int() - 1
		var list: Array = sources[thing]
		return list[index] if index >= 0 and index < list.size() else null
	return null


## What the buttons do up to the game opening: exports the map under `root`, finds the game and checks
## the map with it. Gives back what came of it in plain words:
## - "state": EXPORT_REFUSED, NO_GAME, CANT_CHECK, OLD_GAME (the game is older than the add-on and found
##   fault, which can't be trusted), PROBLEMS or FINE (an older game that took it adds a line first);
## - "folder": the .sfm the map went into, and "game": what was found, once they're known;
## - "words": what to tell the map maker first;
## - "lines": each problem or warning, as {"words", "node"}, with the node it's on if it's on one, and
##   "details", the lines behind it, if it was said once for many things.
## `into_game` says the folder is the game's own maps folder, which is said in words a map maker knows.
static func export_and_check(root: Node, out_folder: String, chosen_game: String, tree: SceneTree, into_game := false) -> Dictionary:
	var scripts := ""
	var scripts_folder: String = root.scripts_folder if root is SmartFellasMap else ""
	if not scripts_folder.is_empty():
		var builder := GameFinder.starter_of(GameFinder.find(chosen_game))
		if builder.is_empty():
			return {"state": State.NO_GAME, "words": "This map has scripts, and the game builds them, so the map hasn't been exported.\n\n%s" % GameFinder.not_found_words(), "lines": []}
		var built := await build_scripts(builder, scripts_folder, root.map_name, tree)
		if built.has("failed"):
			return {"state": State.CANT_CHECK, "game": builder, "words": built["failed"], "lines": []}
		if built.has("problems") and built.has("older"):
			return {"state": State.OLD_GAME, "game": builder, "words": "%s\n\nSo the map hasn't been exported." % older_words(builder, "build this map's scripts"), "lines": [_said_by_older(built["problems"], "the map's scripts")]}
		if built.has("problems"):
			var problems: Array[Dictionary] = []
			for words: String in built["problems"]:
				problems.append({"words": words, "node": null})
			return {"state": State.EXPORT_REFUSED, "words": "This map's scripts don't build yet:", "lines": problems}
		# A folder with no scripts in it yet makes a map with none.
		if DirAccess.get_files_at(built["built"]).size() > 0:
			scripts = built["built"]
	var exported := MapExporter.export_map(root, out_folder, scripts)
	var lines: Array[Dictionary] = []
	if exported.has("problems"):
		for words: String in exported["problems"]:
			var line := {"words": words, "node": exported.get("nodes", {}).get(words)}
			if exported.get("details", {}).has(words):
				line["details"] = exported["details"][words]
			lines.append(line)
		lines.append_array(_marked(exported.get("warnings", [])))
		return {"state": State.EXPORT_REFUSED, "words": "This map can't be exported yet:", "lines": lines}
	var folder: String = exported["package"]
	var went := "Exported to Smart Fellas: My maps\n(%s)" % folder if into_game else "Exported to %s" % folder
	lines.append_array(exported["warnings"])
	if not scripts.is_empty():
		lines.append({"words": SCRIPTS_RUN_WHERE, "node": null})
	var game := GameFinder.starter_of(GameFinder.find(chosen_game))
	if game.is_empty():
		return {"state": State.NO_GAME, "folder": folder, "words": "%s\n\n%s" % [went, GameFinder.not_found_words()], "lines": lines}
	var checked := await check(game, folder, tree)
	if checked.has("failed"):
		return {"state": State.CANT_CHECK, "folder": folder, "game": game, "words": "%s\n\n%s" % [went, checked["failed"]], "lines": lines}
	var problems: Array[String] = checked["problems"]
	if checked.has("older") and not problems.is_empty():
		var heard: Array[Dictionary] = [_said_by_older(problems, "the map")]
		heard.append_array(lines)
		return {"state": State.OLD_GAME, "folder": folder, "game": game, "words": "%s\n\n%s" % [older_words(game, "check this map"), went], "lines": heard}
	if checked.has("older"):
		# A map the older game takes still opens in it, to try what it can.
		lines.push_front(older_but_took_it(game))
	if problems.is_empty():
		var fine := "%s\n\nThe game's checker found nothing wrong." % went
		var graded := grade_words(checked)
		if not graded.is_empty():
			fine += "\n\n" + graded
		if not lines.is_empty():
			fine += "\n\nWorth a look, though:"
		var done := {"state": State.FINE, "folder": folder, "game": game, "words": fine, "lines": lines}
		for key in ["grade", "meaning", "heaviest"]:
			if checked.has(key):
				done[key] = checked[key]
		return done
	lines.clear()
	for words in problems:
		lines.append(_line_about(words, exported["sources"]))
	lines.append_array(_marked(exported["warnings"]))
	return {"state": State.PROBLEMS, "folder": folder, "game": game, "words": "The game would refuse this map:", "lines": lines}


## Warnings said after a map's problems, each marked as only a warning, so that it isn't taken for one more
## reason the map can't be used.
static func _marked(warnings: Array) -> Array[Dictionary]:
	var marked: Array[Dictionary] = []
	for warning: Dictionary in warnings:
		var line := warning.duplicate()
		line["words"] = "Warning: %s" % warning["words"]
		marked.append(line)
	return marked


## One of the checker's problems, saying which thing on the map it means.
static func _line_about(words: String, sources: Dictionary) -> Dictionary:
	var source: Variant = source_of(words, sources)
	# The scene may have been closed while the game was checking.
	if typeof(source) == TYPE_OBJECT and not is_instance_valid(source):
		return {"words": words, "node": null}
	if source is Node:
		return {"words": "%s: %s" % [source.name, words], "node": source}
	if source is String:
		return {"words": "%s: %s" % [source, words], "node": null}
	return {"words": words, "node": null}
