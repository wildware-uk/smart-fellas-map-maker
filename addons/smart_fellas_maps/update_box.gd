@tool
extends VBoxContainer
## The Map panel's "This add-on" part: which version this is, and updating it from GitHub. It asks
## GitHub about releases when Godot opens, at most once a day, and when Check for updates is pressed.
## With no internet it says nothing unless asked. Update downloads the newest release, checks it, and
## swaps it in for the add-on's folder; Restart Godot then starts using it. The banner at the top of the
## panel and the Tools menu's dialog show the same news (see update_banner.gd), through `changed`.

const Updater := preload("updater.gd")
const Version := preload("version.gd")

const AUTO_KEY := "smart_fellas/check_for_updates"
const LAST_CHECK_KEY := "last_update_check"
const METADATA := "smart_fellas"
const DAY_SECONDS := 24 * 60 * 60
const ASK_SECONDS := 20.0
const DOWNLOAD_SECONDS := 300.0
const HEADERS := ["Accept: application/vnd.github+json", "User-Agent: smart-fellas-map-maker"]
const NEWS_COLOUR := Color(0.55, 0.85, 1.0)
const PROBLEM_COLOUR := Color(1.0, 0.45, 0.4)

enum Step { IDLE, CHECKING, SUM, DOWNLOAD }

## Whenever what it says, or what can be done, changes.
signal changed

## How wide its labels may shrink, as the Map panel's are.
var minimum_width := 200.0

var _web: HTTPRequest
var _step := Step.IDLE
var _quiet := false
var _latest := {}
var _said: Label
var _notes: Label
var _check: Button
var _update: Button
var _restart: Button
var _auto: CheckBox
var _announcing := false


func _ready() -> void:
	_web = HTTPRequest.new()
	_web.use_threads = true
	# GitHub sends a release's files from its own storage. HTTPRequest follows the redirect wherever it
	# points, so what proves a download is ours is its SHA-256, not where it came from.
	_web.max_redirects = 4
	_web.request_completed.connect(_on_answer)
	add_child(_web)
	_label("Version %s" % Version.number())
	_said = _label("")
	_said.visible = false
	_notes = _label("")
	_notes.visible = false
	_update = _button("Update", "Download the newest version, check it, and put it in place of this one. Your maps stay as they are.")
	_update.pressed.connect(update)
	_update.visible = false
	_restart = _button("Restart Godot", "Save your scenes and start Godot again, with the new add-on.")
	_restart.pressed.connect(func() -> void: EditorInterface.restart_editor(true))
	_restart.visible = false
	_check = _button("Check for updates", "Ask GitHub whether a newer version is out.")
	_check.pressed.connect(check.bind(false))
	_auto = CheckBox.new()
	_auto.text = "Check for updates automatically"
	_auto.tooltip_text = "Once a day, when Godot opens."
	_auto.button_pressed = _checks_automatically()
	_auto.toggled.connect(func(on: bool) -> void: EditorInterface.get_editor_settings().set_setting(AUTO_KEY, on))
	add_child(_auto)
	var link := LinkButton.new()
	link.text = "See every version and what's new"
	link.uri = Version.RELEASES_URL
	link.tooltip_text = Version.RELEASES_URL
	link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	link.add_theme_color_override("font_color", get_theme_color("accent_color", "Editor"))
	# In line with the labels' words, which sit inside their box's margin.
	var inset := MarginContainer.new()
	var words_start := maxf(get_theme_stylebox("normal", "Label").content_margin_left, 0.0)
	inset.add_theme_constant_override("margin_left", int(words_start))
	inset.add_theme_constant_override("margin_bottom", 6)
	inset.add_child(link)
	add_child(inset)
	Updater.forget_backup(Updater.WORK_DIR)
	# Godot with no window, importing for a script or a check, has nobody to tell, and would use up the day's check.
	if DisplayServer.get_name() != "headless" and _checks_automatically() and _is_a_day_since_the_last_check():
		check.call_deferred(true)


## Asks GitHub about releases. `quiet` says nothing if GitHub can't be reached, for the check Godot
## makes by itself.
func check(quiet: bool) -> void:
	# plugin.cfg on disk is the new version now, so a check would wrongly say this is the newest.
	if installed():
		return
	if _step == Step.CHECKING and not quiet:
		# Godot's own check is under way: say what it finds, as if asked.
		_quiet = false
		_say("Checking...", Color.WHITE)
		return
	if _step != Step.IDLE:
		return
	if Version.number() == Updater.DEV:
		if not quiet:
			_say("This is the game's own copy of the add-on. It changes with the game's code.", Color.WHITE)
		return
	_quiet = quiet
	_web.timeout = ASK_SECONDS
	_web.download_file = ""
	_web.body_size_limit = -1
	if _web.request(Updater.RELEASES_API, HEADERS) != OK:
		_couldnt_reach()
		return
	_step = Step.CHECKING
	_check.disabled = true
	if not quiet:
		_say("Checking...", Color.WHITE)


## The newer version found, or "" when there is none to update to.
func available() -> String:
	return "" if _latest.is_empty() or installed() else str(_latest["version"])


## Whether it is asking GitHub or downloading.
func busy() -> bool:
	return _step != Step.IDLE


## Whether the newer version is in place, waiting for Godot to start again.
func installed() -> bool:
	return _restart != null and _restart.visible


## What it last said, and in which colour.
func words() -> String:
	return _said.text if _said != null and _said.visible else ""


func words_colour() -> Color:
	return _said.get_theme_color("font_color") if _said != null else Color.WHITE


## The newer version's release page, with what changed in it.
func news_url() -> String:
	return Version.RELEASES_URL.path_join("tag").path_join("v" + str(_latest.get("version", "")))


## Downloads the newer version found, checks it, and puts it in place of this one.
func update() -> void:
	if _step != Step.IDLE or _latest.is_empty() or installed():
		return
	_update.disabled = true
	_check.disabled = true
	if _latest["sum"].is_empty():
		_download(_latest["digest"])
		return
	_web.timeout = ASK_SECONDS
	_web.download_file = ""
	_web.body_size_limit = Updater.MOST_SUM_BYTES
	_step = Step.SUM
	_say("Downloading version %s..." % _latest["version"], Color.WHITE)
	if _web.request(_latest["sum"]) != OK:
		_failed("Couldn't start the download.")


func _download(sum: String) -> void:
	DirAccess.make_dir_recursive_absolute(Updater.WORK_DIR)
	_latest["expected"] = sum
	_web.timeout = DOWNLOAD_SECONDS
	_web.download_file = _zip_path()
	_web.body_size_limit = Updater.MOST_BYTES
	_step = Step.DOWNLOAD
	_say("Downloading version %s..." % _latest["version"], Color.WHITE)
	if _web.request(_latest["zip"]) != OK:
		_failed("Couldn't start the download.")


func _on_answer(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var step := _step
	_step = Step.IDLE
	_announce()
	var reached := result == HTTPRequest.RESULT_SUCCESS and code == 200
	match step:
		Step.CHECKING:
			_check.disabled = false
			if result != HTTPRequest.RESULT_SUCCESS:
				_couldnt_reach()
				return
			if code != 200:
				if not _quiet and code in [403, 429]:
					_say("GitHub has had too many checks from your connection for now. Try again in an hour.", PROBLEM_COLOUR)
				elif not _quiet:
					_say("GitHub didn't answer the check (it said %d). Try again later." % code, PROBLEM_COLOUR)
				return
			EditorInterface.get_editor_settings().set_project_metadata(METADATA, LAST_CHECK_KEY, int(Time.get_unix_time_from_system()))
			_show_releases(body.get_string_from_utf8())
		Step.SUM:
			var sum := Updater.sum_in(body.get_string_from_utf8())
			if not reached or sum.is_empty():
				_failed("Couldn't get the release's SHA-256 to check the download against.")
				return
			_download(sum)
		Step.DOWNLOAD:
			if not reached:
				_failed("The download didn't finish.")
				return
			_install()


func _show_releases(text: String) -> void:
	_announce()
	var found := Updater.read_releases(text, Version.number())
	if found.has("problem"):
		if not _quiet:
			_say(found["problem"], PROBLEM_COLOUR)
		return
	if not Updater.is_newer(found["version"], Version.number()):
		_latest = {}
		_update.visible = false
		_notes.visible = false
		if not _quiet:
			_say("You have the newest version.", Color.WHITE)
		return
	_latest = found
	_say("Update available: %s → %s" % [Version.number(), found["version"]], NEWS_COLOUR)
	var lines: Array[String] = []
	for line: String in found["notes"]:
		lines.append("• " + line)
	if found.get("more", false):
		lines.append("And more: see every version below.")
	_notes.text = "\n".join(lines)
	_notes.visible = not lines.is_empty()
	_update.visible = true
	_update.disabled = false


func _install() -> void:
	var problem := Updater.check_zip(_zip_path(), _latest["version"], _latest["expected"])
	if problem.is_empty():
		problem = Updater.install(_zip_path(), ProjectSettings.globalize_path(Updater.ADDON_DIR), ProjectSettings.globalize_path(Updater.WORK_DIR))
	DirAccess.remove_absolute(_zip_path())
	if not problem.is_empty():
		_failed(problem)
		return
	_update.visible = false
	_notes.visible = false
	_check.visible = false
	_say("Updated to version %s. Restart Godot to start using it." % _latest["version"], NEWS_COLOUR)
	_restart.visible = true


func _couldnt_reach() -> void:
	if not _quiet:
		_say("Couldn't reach GitHub to check. Are you online?", PROBLEM_COLOUR)


func _failed(words: String) -> void:
	_check.disabled = false
	_update.disabled = false
	_say(words, PROBLEM_COLOUR)


func _say(words: String, colour: Color) -> void:
	_said.text = words
	_said.add_theme_color_override("font_color", colour)
	_said.visible = true
	_announce()


## Emits `changed` once this frame's steps are done, so whoever listens sees where they ended.
func _announce() -> void:
	if _announcing:
		return
	_announcing = true
	(func() -> void:
		_announcing = false
		changed.emit()).call_deferred()


func _zip_path() -> String:
	return ProjectSettings.globalize_path(Updater.WORK_DIR.path_join(Updater.ZIP_NAME))


func _checks_automatically() -> bool:
	var settings := EditorInterface.get_editor_settings()
	return not settings.has_setting(AUTO_KEY) or bool(settings.get_setting(AUTO_KEY))


func _is_a_day_since_the_last_check() -> bool:
	var last := int(EditorInterface.get_editor_settings().get_project_metadata(METADATA, LAST_CHECK_KEY, 0))
	return Time.get_unix_time_from_system() - last >= DAY_SECONDS


func _label(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = minimum_width
	add_child(label)
	return label


func _button(words: String, tip: String) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = tip
	add_child(button)
	return button
