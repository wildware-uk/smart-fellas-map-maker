@tool
extends HBoxContainer
## The cost meter: a bar along the bottom of the 3D view, always there. It shows what the open map costs
## against what the game can afford at 1080p Medium, amber before it's too much and red past the limit.

const Cost := preload("cost.gd")

const AMBER := Color(1.0, 0.72, 0.15)
const RED := Color(1.0, 0.3, 0.25)
const GREEN := Color(0.35, 0.82, 0.55)
const WORDS_FINE := "This map is fine for mid-level computers."
const WORDS_CLOSE := "Getting heavy. A little more is fine."
const WORDS_OVER := "Heavy: this will run slowly on mid-level computers. It still exports and plays."

var _rows := {}
var _verdict: Label
## What the open map's own models cost, as last counted.
var _own := {}


func _ready() -> void:
	name = "Cost meter"
	custom_minimum_size = Vector2(0.0, 26.0)
	_add_row("pieces", "Pieces", "How many pieces the map places. Many cost frame time: the colour is advice, and nothing stops you.")
	_add_row("triangles", "Triangles", "What all the pieces come to in triangles, your own models' too. This is what costs the most to draw: a coral bush is thousands, and a pebble is 80. The colours were measured in the real game at 1080p Medium, and are only advice.")
	_add_row("draws", "Draws", "How many different kinds of piece the map uses, and one for the sand. Each of your own models counts one for each of its materials. Each kind is drawn in one go, so many of one kind cost far less here than a few of many kinds.")
	_verdict = Label.new()
	_verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_verdict.clip_text = true
	_verdict.custom_minimum_size = Vector2(20.0, 0.0)
	add_child(_verdict)


func _add_row(key: String, words: String, tip: String) -> void:
	var box := HBoxContainer.new()
	box.tooltip_text = tip
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.text = words
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(30.0, 8.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(bar)
	var value := Label.new()
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	value.custom_minimum_size = Vector2(84.0, 0.0)
	box.add_child(value)
	add_child(box)
	var fill := StyleBoxFlat.new()
	bar.add_theme_stylebox_override("fill", fill)
	_rows[key] = {"bar": bar, "value": value, "fill": fill}


## Shows what `map` costs, or nothing if no map is open. Its own models are counted again only when
## `recount_own`, as finding them walks the whole scene and a brush stroke doesn't change them.
func show_cost(map: SmartFellasMap, recount_own := true) -> void:
	visible = map != null
	if map == null:
		_own = {}
		return
	if recount_own or _own.is_empty():
		_own = Cost.own_models_of(map)
	var cost := Cost.of(map, _own)
	_show_row("pieces", cost["pieces"], Cost.PIECES_CLOSE, Cost.PIECES_OVER)
	_show_row("triangles", cost["triangles"], Cost.TRIANGLES_CLOSE, Cost.TRIANGLES_OVER)
	_show_row("draws", cost["draws"], Cost.DRAWS_CLOSE, Cost.DRAWS_OVER)
	if not cost["missing"].is_empty():
		_verdict.text = "This map uses pieces the kit no longer has: %s." % ", ".join(cost["missing"])
		_verdict.add_theme_color_override("font_color", RED)
		return
	match Cost.worst_level(cost):
		Cost.Level.FINE:
			_verdict.text = WORDS_FINE
			_verdict.add_theme_color_override("font_color", GREEN)
		Cost.Level.CLOSE:
			_verdict.text = WORDS_CLOSE
			_verdict.add_theme_color_override("font_color", AMBER)
		Cost.Level.OVER:
			_verdict.text = WORDS_OVER
			_verdict.add_theme_color_override("font_color", RED)


func _show_row(key: String, value: int, close: int, over: int) -> void:
	var row: Dictionary = _rows[key]
	row["bar"].max_value = over
	row["bar"].value = mini(value, over)
	row["value"].text = "%s of %s" % [_short(value), _short(over)]
	var colour := GREEN
	match Cost.level_of(value, close, over):
		Cost.Level.CLOSE:
			colour = AMBER
		Cost.Level.OVER:
			colour = RED
	row["fill"].bg_color = colour
	row["value"].add_theme_color_override("font_color", colour)


static func _short(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 10000:
		return "%dk" % (value / 1000)
	return str(value)
