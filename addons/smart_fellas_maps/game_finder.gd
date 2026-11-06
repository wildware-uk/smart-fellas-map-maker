@tool
extends RefCounted
## Finds the game on this computer, for the Test Map button. It looks, in this order:
## 1. the SMART_FELLAS_GAME variable, which names the program;
## 2. the program a map maker chose earlier, kept in Godot's editor settings;
## 3. Steam: its own record of where it installed Smart Fellas, in every Steam library.

const STEAM_APP_ID := "3655280"
const GAME_VAR := "SMART_FELLAS_GAME"
const LINUX_PROGRAM := "smart-fellas.sh"
const WINDOWS_PROGRAM := "smart-fellas.exe"
## Where the Steam settings live, inside the home folder on Linux. On Windows, see _steam_folders.
const LINUX_STEAM_FOLDERS := [
	".local/share/Steam",
	".steam/steam",
	".var/app/com.valvesoftware.Steam/.local/share/Steam",
]
const CHOSEN_KEY := "smart_fellas/game_program"


## The program to run, or "" if it can't be found. `chosen` is what the map maker picked earlier, if anything.
static func find(chosen: String) -> String:
	var named := OS.get_environment(GAME_VAR)
	if not named.is_empty():
		return named if FileAccess.file_exists(named) else ""
	if not chosen.is_empty() and FileAccess.file_exists(chosen):
		return chosen
	return find_in_steam(_steam_folders())


## The program as Steam installed it, looking through each of `steam_folders`.
static func find_in_steam(steam_folders: Array[String]) -> String:
	for steam in steam_folders:
		for library in _libraries_of(steam):
			var program := _program_in_library(library)
			if not program.is_empty():
				return program
	return ""


## What to say when the game can't be found, for a person to act on.
static func not_found_words() -> String:
	var named := OS.get_environment(GAME_VAR)
	if not named.is_empty():
		return "Can't find the game. %s says it's at %s, and there's nothing there. Fix or remove that variable." % [GAME_VAR, named]
	return "Can't find Smart Fellas on this computer, so the map hasn't been tried in it. Install it from Steam, or press Find the game and choose %s in the folder it's in." % program_name()


## What the game's program is called on this system.
static func program_name() -> String:
	return WINDOWS_PROGRAM if OS.get_name() == "Windows" else LINUX_PROGRAM


## On Linux the game comes with a starter beside the real program, which finds the libraries next to it.
## A person is likely to choose the program itself, so this swaps it for the starter.
static func starter_of(program: String) -> String:
	if program.get_file() == "smart-fellas":
		var starter := program.get_base_dir().path_join(LINUX_PROGRAM)
		if FileAccess.file_exists(starter):
			return starter
	return program


static func _steam_folders() -> Array[String]:
	var folders: Array[String] = []
	if OS.get_name() == "Windows":
		for variable in ["ProgramFiles(x86)", "ProgramFiles"]:
			var programs := OS.get_environment(variable)
			if not programs.is_empty():
				folders.append(programs.path_join("Steam"))
	else:
		var home := OS.get_environment("HOME")
		for inside: String in LINUX_STEAM_FOLDERS:
			folders.append(home.path_join(inside))
	return folders


## The Steam library folders a Steam install knows of: itself, and those in libraryfolders.vdf.
static func _libraries_of(steam: String) -> Array[String]:
	var libraries: Array[String] = [steam]
	var listed := FileAccess.get_file_as_string(steam.path_join("steamapps/libraryfolders.vdf"))
	for path in values_called("path", listed):
		if not libraries.has(path):
			libraries.append(path)
	return libraries


static func _program_in_library(library: String) -> String:
	var steamapps := library.path_join("steamapps")
	var record := FileAccess.get_file_as_string(steamapps.path_join("appmanifest_%s.acf" % STEAM_APP_ID))
	var folders := values_called("installdir", record)
	if folders.is_empty():
		return ""
	var program := steamapps.path_join("common").path_join(folders[0]).path_join(program_name())
	return program if FileAccess.file_exists(program) else ""


## Every value of `key` in Steam's text files, which have lines like: "path"  "D:\\Games\\Steam"
static func values_called(key: String, text: String) -> Array[String]:
	var found: Array[String] = []
	var finder := RegEx.create_from_string('"%s"\\s+"([^"]*)"' % key)
	for match_found in finder.search_all(text):
		found.append(match_found.get_string(1).replace("\\\\", "/"))
	return found
