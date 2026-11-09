@tool
extends RefCounted
## Talks to the game's own pose helper, `smart-fellas --pose-editor`, so the Pose panel shapes the very
## octopus players see, skinned by the game's code, without the add-on carrying a copy of the octopus. One
## game runs for the whole editor session, with no window: the add-on sends one question a line, as JSON,
## and reads one answer a line.

## Where the game finder is: loaded when the game is first started, not with the add-on, as only drawing a
## pose needs it (see tests/startup_test.gd).
const GAME_FINDER := "res://addons/smart_fellas_maps/game_finder.gd"

## What the game says first, then the map maker version it speaks, as map_tester.gd reads it.
const VERSION_MARK := "map maker version: "
## The least map maker version that has the pose helper.
const NEEDS := 7
## How long the game may take to start, and to answer one question, in milliseconds.
const START_MILLISECONDS := 15000
const ANSWER_MILLISECONDS := 5000
## How long to wait between looks at the pipe, in microseconds.
const POLL_MICROSECONDS := 300

static var _pid := -1
static var _pipe: FileAccess
## What came down the pipe after the last whole line.
static var _waiting := PackedByteArray()
## What the game said when it started: the model's triangles, the dials, the built-in poses.
static var _start: Dictionary = {}
## Why the game can't draw poses, if it can't.
static var _trouble := ""
## Whether the game failed to start. A pose drawn again and again doesn't start it again and again, each
## time freezing the editor while it waits: it's only tried again after forget_trouble, from the Poses
## panel's Try the game again.
static var _failed := false


## What the game said when it started, or {"problem": why it can't draw poses}.
static func start() -> Dictionary:
	if not _running():
		return {"problem": _trouble}
	return _start


## The octopus in `pose` (a pose as a pose file holds it, as a Dictionary): {"skin", "web", "tips",
## "problem"} as src/pose/studio/godot.rs gives them, or {"problem"} alone if the game can't say. In still
## water, or with a `time` of 0 or more, that many seconds into the water's play, moving as the pose says,
## standing out from its surface along `up` in the map, which turns the current as the game does.
static func draw(pose: Dictionary, time := -1.0, up := Vector3.UP) -> Dictionary:
	var question := {"ask": "draw", "pose": pose}
	if time >= 0.0:
		question["time"] = time
		question["up"] = [up.x, up.y, up.z]
	return _ask(question)


## Arm `arm` of `pose` bent to bring its tip near `to`, in the pose's own frame: {"arm"} or {"problem"}.
static func reach(pose: Dictionary, arm: int, to: Vector3) -> Dictionary:
	return _ask({"ask": "reach", "pose": pose, "arm": arm, "to": [to.x, to.y, to.z]})


## Tries the game afresh next time, however soon: after the map maker updated it or chose another.
static func forget_trouble() -> void:
	_failed = false
	_trouble = ""


## Stops the game, when the add-on is turned off.
static func stop() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_pipe = null
	_waiting = PackedByteArray()
	_start = {}


## `packed`, base64 of little-endian 32-bit floats, as numbers.
static func floats(packed: String) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(packed).to_float32_array()


## `packed`, base64 of little-endian 32-bit whole numbers, as numbers.
static func whole_numbers(packed: String) -> PackedInt32Array:
	return Marshalls.base64_to_raw(packed).to_int32_array()


static func _ask(question: Dictionary) -> Dictionary:
	if not _running():
		return {"problem": _trouble}
	_pipe.store_line(JSON.stringify(question))
	var line: Variant = _line_within(ANSWER_MILLISECONDS)
	if line == null:
		stop()
		_trouble = "The game stopped answering while it drew the octopus. It starts again next time."
		return {"problem": _trouble}
	var answer: Variant = JSON.parse_string(line)
	if answer is Dictionary:
		return answer
	return {"problem": "The game said something the add-on couldn't read: %s" % line.left(200)}


## Whether the game is running and ready, starting it if it isn't.
static func _running() -> bool:
	if _pid > 0 and OS.is_process_running(_pid) and _pipe != null:
		return true
	stop()
	var finder: GDScript = load(GAME_FINDER)
	var game: String = finder.starter_of(finder.find(_chosen_game(finder)))
	if game.is_empty():
		_fail("Can't draw the octopus: %s" % finder.not_found_words())
		return false
	if _failed:
		return false
	var running := OS.execute_with_pipe(game, PackedStringArray(["--pose-editor"]), false)
	if running.is_empty():
		_fail("Can't run the game at %s to draw the octopus. Check that it's there and is allowed to run." % game)
		return false
	_pid = running["pid"]
	_pipe = running["stdio"]
	var first: Variant = _line_within(START_MILLISECONDS)
	if first == null:
		stop()
		_fail("The game at %s didn't start within %d seconds to draw the octopus. Press Try the game again." % [game, START_MILLISECONDS / 1000])
		return false
	if not String(first).begins_with(VERSION_MARK) or int(String(first).trim_prefix(VERSION_MARK)) < NEEDS:
		stop()
		_fail("The game at %s is too old to draw octopus poses. Update it, then press Try the game again." % game)
		return false
	_pipe.store_line(JSON.stringify({"ask": "start"}))
	var said: Variant = _line_within(START_MILLISECONDS)
	var start: Variant = null if said == null else JSON.parse_string(said)
	if not start is Dictionary or start.has("problem"):
		stop()
		_fail("The game at %s didn't say how to draw the octopus." % game)
		return false
	_start = start
	forget_trouble()
	return true


static func _fail(why: String) -> void:
	_trouble = why
	_failed = true


static func _chosen_game(finder: GDScript) -> String:
	if not Engine.is_editor_hint():
		return ""
	var settings := EditorInterface.get_editor_settings()
	var key: String = finder.get_script_constant_map()["CHOSEN_KEY"]
	return settings.get_setting(key) if settings.has_setting(key) else ""


## The next whole line from the game, waiting at most `milliseconds`, or null if none came or the game
## stopped.
static func _line_within(milliseconds: int) -> Variant:
	var started := Time.get_ticks_msec()
	while true:
		var end := _waiting.find(10)
		if end >= 0:
			var line := _waiting.slice(0, end).get_string_from_utf8()
			_waiting = _waiting.slice(end + 1)
			return line
		var waiting := _pipe.get_length()
		if waiting > 0:
			_waiting.append_array(_pipe.get_buffer(waiting))
			continue
		if not OS.is_process_running(_pid) or Time.get_ticks_msec() - started > milliseconds:
			return null
		OS.delay_usec(POLL_MICROSECONDS)
	return null
