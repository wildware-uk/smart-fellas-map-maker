@tool
extends RefCounted
## Updates the add-on from the GitHub releases of its public repository: reads what the releases say,
## checks a downloaded release zip, and swaps it in for the add-on's folder. The Map panel does the
## asking and the downloading (update_box.gd); none of this needs the editor, so the tests run it too.
##
## Only the add-on's own folder is ever written. Nothing else in a release is unpacked, and nothing
## downloaded is run until Godot starts again with the new add-on in place.

const RELEASES_API := "https://api.github.com/repos/wildware-uk/smart-fellas-map-maker/releases?per_page=20"
## Every download comes from under here, over HTTPS. GitHub hands the file itself out from its own
## storage, which HTTPRequest follows to.
const DOWNLOADS := "https://github.com/wildware-uk/smart-fellas-map-maker/releases/download/"
const ZIP_NAME := "smart-fellas-map-maker.zip"
const SUM_NAME := "smart-fellas-map-maker.zip.sha256"
## The release zip holds the whole map-making project in this folder.
const TOP := "smart-fellas-map-maker/"
const ADDON_IN_ZIP := "smart-fellas-map-maker/addons/smart_fellas_maps/"
const ADDON_DIR := "res://addons/smart_fellas_maps"
## Downloads, the unpacked add-on and the old one's backup live here, outside the project, so that Godot
## never imports a second copy of the add-on.
const WORK_DIR := "user://smart_fellas_maps_update"
## A release is about 10 MB. Anything far bigger isn't ours.
const MOST_BYTES := 100 * 1024 * 1024
const MOST_SUM_BYTES := 1024
## What an add-on folder can't be without.
const NEEDED := ["plugin.cfg", "plugin.gd", "version.gd"]
const DEV := "dev"
const MOST_NOTES := 6
## Where install leaves the old add-on when it couldn't put it back, each time in a numbered folder of
## its own so a later failure never overwrites an earlier copy. Nothing deletes them.
const KEPT := "kept_backup"

static var _version_shape: RegEx
static var _link: RegEx


## Whether a release is newer than the add-on here. Versions are "<date>-<commit>", and releases only go
## forwards, so a different version from the same day or later is newer. The game's own copy, "dev",
## is never updated.
static func is_newer(latest: String, installed: String) -> bool:
	if installed == DEV or not _is_version(latest) or latest == installed:
		return false
	if not _is_version(installed):
		return true
	return latest.get_slice("-", 0) >= installed.get_slice("-", 0)


static func _is_version(words: String) -> bool:
	if _version_shape == null:
		_version_shape = RegEx.create_from_string("^\\d{4}\\.\\d{2}\\.\\d{2}-[0-9a-f]{7,40}$")
	return _version_shape.search(words) != null


## What GitHub's list of releases says about the newest one, for the add-on at `installed`:
## { version, zip, sum (the .sha256 file's address, or ""), digest (GitHub's own SHA-256 of the zip,
## or ""), size, notes (what changed since `installed`, newest first, at most MOST_NOTES lines), and
## more if there was more to say }, or { problem } in plain words.
## When `installed` is the newest, it is only { version, notes }.
static func read_releases(text: String, installed: String) -> Dictionary:
	var releases: Variant = JSON.parse_string(text)
	if not releases is Array:
		return {"problem": "GitHub's answer wasn't a list of releases."}
	var out: Array[Dictionary] = []
	for release: Variant in releases:
		if release is Dictionary and not release.get("draft", false) and not release.get("prerelease", false):
			out.append(release)
	# GitHub doesn't list them newest first.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("published_at", "")) > str(b.get("published_at", "")))
	var latest := {}
	var notes: Array[String] = []
	for release in out:
		var version := str(release.get("tag_name", "")).trim_prefix("v")
		if version == installed:
			if latest.is_empty():
				latest = {"version": version}
			break
		if latest.is_empty():
			latest = _release_files(release, version)
			if latest.has("problem"):
				return latest
		for line in str(release.get("body", "")).split("\n", false):
			var said := plain(line)
			if said.is_empty() or said in notes:
				continue
			if notes.size() == MOST_NOTES:
				latest["more"] = true
				break
			notes.append(said)
	if latest.is_empty():
		return {"problem": "There are no releases yet."}
	latest["notes"] = notes
	return latest


## A changelog line as plain words: no list mark, bold, code marks or link addresses.
static func plain(line: String) -> String:
	if _link == null:
		_link = RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")
	var said := line.strip_edges().trim_prefix("- ").trim_prefix("* ")
	said = _link.sub(said, "$1", true)
	return said.replace("**", "").replace("__", "").replace("`", "").strip_edges()


static func _release_files(release: Dictionary, version: String) -> Dictionary:
	if not _is_version(version):
		return {"problem": "The newest release, %s, has no version number." % release.get("tag_name", "")}
	var found := {"version": version, "zip": "", "sum": "", "digest": "", "size": 0}
	var folder := DOWNLOADS + "v" + version + "/"
	for asset: Variant in release.get("assets", []):
		if not asset is Dictionary:
			continue
		var url := str(asset.get("browser_download_url", ""))
		match str(asset.get("name", "")):
			ZIP_NAME:
				if url == folder + ZIP_NAME:
					found["zip"] = url
					found["size"] = int(asset.get("size", 0))
					found["digest"] = str(asset.get("digest", "")).trim_prefix("sha256:").to_lower()
			SUM_NAME:
				if url == folder + SUM_NAME:
					found["sum"] = url
	if found["zip"].is_empty():
		return {"problem": "Version %s has no zip to download." % version}
	if found["size"] > MOST_BYTES:
		return {"problem": "Version %s's zip is far bigger than it should be, so it wasn't downloaded." % version}
	if found["sum"].is_empty() and not _is_sum(found["digest"]):
		return {"problem": "Version %s has no SHA-256 to check the download against, so it wasn't downloaded." % version}
	return found


## The SHA-256 a .sha256 file gives ("<64 hex digits>  <file name>"), or "".
static func sum_in(text: String) -> String:
	var sum := text.strip_edges().get_slice(" ", 0).to_lower()
	return sum if _is_sum(sum) else ""


static func _is_sum(words: String) -> bool:
	return words.length() == 64 and words.is_valid_hex_number()


static func sha256_of(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		hashing.update(file.get_buffer(1 << 20))
	return hashing.finish().hex_encode()


## Why the zip at `path` mustn't be installed as `version`, in plain words, or "" if it may. It must
## match `sum`, be no bigger than a release can be, hold nothing outside the project folder, hold a
## whole add-on, and say it is `version`.
static func check_zip(path: String, version: String, sum: String) -> String:
	var length := FileAccess.get_size(path)
	if length <= 0:
		return "The download is empty."
	if length > MOST_BYTES:
		return "The download is far bigger than a release should be."
	if sha256_of(path) != sum.to_lower():
		return "The download doesn't match the SHA-256 published with the release, so it wasn't installed. Try again later."
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return "The download isn't a zip Godot can read."
	var files := zip.get_files()
	var problem := ""
	for name in files:
		if not _is_safe(name):
			problem = "The download holds a file outside the add-on's project: %s" % name
			break
	if problem.is_empty():
		for needed: String in NEEDED:
			if not ADDON_IN_ZIP + needed in files:
				problem = "The download has no %s, so it isn't a whole add-on." % needed
				break
	if problem.is_empty():
		var cfg := ConfigFile.new()
		var said := cfg.parse(zip.read_file(ADDON_IN_ZIP + "plugin.cfg").get_string_from_utf8())
		if said != OK or str(cfg.get_value("plugin", "version", "")) != version:
			problem = "The download doesn't say it is version %s." % version
	zip.close()
	return problem


static func _is_safe(name: String) -> bool:
	if not name.begins_with(TOP) or name.contains("\\") or name.contains(":"):
		return false
	for part in name.split("/"):
		if part == "..":
			return false
	return true


## Puts the add-on in the checked zip at `zip_path` in place of the folder `addon_dir`, keeping the old
## folder in `work_dir`/backup until forget_backup. Nothing outside `addon_dir` is touched. Returns why
## it couldn't, in plain words, or "". If the swap fails part way, the old add-on is put back; if even
## that fails, its copy goes to a new folder in `work_dir`/KEPT, which forget_backup leaves alone, and
## the words say where.
static func install(zip_path: String, addon_dir: String, work_dir: String) -> String:
	var fresh := work_dir.path_join("new")
	var backup := work_dir.path_join("backup")
	_remove(fresh)
	var unpacked := _unpack_addon(zip_path, fresh)
	if not unpacked.is_empty():
		_remove(fresh)
		return unpacked
	_remove(backup)
	if _copy(addon_dir, backup) != OK:
		_remove(backup)
		_remove(fresh)
		return "Couldn't keep a copy of the add-on you have, so nothing was changed."
	if _empty(addon_dir) != OK or _copy(fresh, addon_dir) != OK:
		_empty(addon_dir)
		var restored := _copy(backup, addon_dir)
		_remove(fresh)
		if restored == OK:
			return "Couldn't write the new add-on into its folder, so the one you had is back."
		var kept := _keep_for_good(backup, work_dir.path_join(KEPT))
		if kept.is_empty():
			return "Couldn't write the new add-on into its folder, or put the old one back, or keep a copy where it lasts. The only copy of the one you had is in %s, and Godot deletes it when it starts: copy it into addons/smart_fellas_maps before restarting Godot." % ProjectSettings.globalize_path(backup)
		return "Couldn't write the new add-on into its folder, or put the old one back. A copy of the one you had is in %s: copy it into addons/smart_fellas_maps before restarting Godot." % ProjectSettings.globalize_path(kept)
	_remove(fresh)
	return ""


## Moves (or failing that, copies) `backup` into the first numbered folder of `kept_dir` not yet taken.
## Returns that folder, or "" if the copy couldn't be kept there.
static func _keep_for_good(backup: String, kept_dir: String) -> String:
	if DirAccess.make_dir_recursive_absolute(kept_dir) != OK:
		return ""
	var number := 1
	while DirAccess.dir_exists_absolute(kept_dir.path_join(str(number))) or FileAccess.file_exists(kept_dir.path_join(str(number))):
		number += 1
	var kept := kept_dir.path_join(str(number))
	if DirAccess.rename_absolute(backup, kept) == OK:
		return kept
	if _copy(backup, kept) == OK:
		return kept
	_remove(kept)
	return ""


## Throws away the old add-on kept by install. The add-on calls this when Godot starts it.
static func forget_backup(work_dir: String) -> void:
	_remove(work_dir.path_join("backup"))
	_remove(work_dir.path_join("new"))


static func _unpack_addon(zip_path: String, into: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The download isn't a zip Godot can read."
	var problem := ""
	for name in zip.get_files():
		if not name.begins_with(ADDON_IN_ZIP) or name.ends_with("/"):
			continue
		if not _is_safe(name):
			problem = "The download holds a file outside the add-on's project: %s" % name
			break
		var path := into.path_join(name.trim_prefix(ADDON_IN_ZIP))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null or not file.store_buffer(zip.read_file(name)):
			problem = "Couldn't unpack the download."
			break
		file.close()
	zip.close()
	return problem


static func _copy(from: String, to: String) -> Error:
	if DirAccess.make_dir_recursive_absolute(to) != OK:
		return FAILED
	var dir := DirAccess.open(from)
	if dir == null:
		return FAILED
	dir.include_hidden = true
	for file in dir.get_files():
		if dir.copy(from.path_join(file), to.path_join(file)) != OK:
			return FAILED
	for folder in dir.get_directories():
		if _copy(from.path_join(folder), to.path_join(folder)) != OK:
			return FAILED
	return OK


## Takes everything out of the folder `path`, leaving it there, empty.
static func _empty(path: String) -> Error:
	var dir := DirAccess.open(path)
	if dir == null:
		return FAILED
	dir.include_hidden = true
	var result := OK
	for folder in dir.get_directories():
		if _remove(path.path_join(folder)) != OK:
			result = FAILED
	for file in dir.get_files():
		if dir.remove(file) != OK:
			result = FAILED
	return result


static func _remove(path: String) -> Error:
	if not DirAccess.dir_exists_absolute(path):
		return OK
	if _empty(path) != OK:
		return FAILED
	return DirAccess.remove_absolute(path)
