@tool
extends VBoxContainer
## News of a newer add-on, from the Map panel's "This add-on" part (update_box.gd), where it can't be
## missed: "Update available: vX → vY" with Update and What's new, then how the download goes, then
## Restart Godot. At the top of the Map panel it shows only while there is news; in the Tools menu's
## dialog it always shows what the box last said.

const UpdateBox := preload("update_box.gd")

const NEWS_COLOUR := Color(0.55, 0.85, 1.0)

## Whether it shows even with no newer version to talk about, as the dialog's does.
var always_shown := false
## How wide its words may shrink.
var minimum_width := 200.0

var _box: UpdateBox
var _said: Label
var _update: Button
var _news: Button
var _restart: Button


func _init(box: UpdateBox) -> void:
	_box = box


func _ready() -> void:
	_said = Label.new()
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_said.custom_minimum_size.x = minimum_width
	add_child(_said)
	var buttons := HBoxContainer.new()
	_update = _button(buttons, "Update", "Download the newest version, check it, and put it in place of this one. Your maps stay as they are.")
	_update.pressed.connect(_box.update)
	_news = _button(buttons, "What's new", "Open the new version's page, with what changed.")
	_news.pressed.connect(func() -> void: OS.shell_open(_box.news_url()))
	_restart = _button(buttons, "Restart Godot", "Save your scenes and start Godot again, with the new add-on.")
	_restart.pressed.connect(func() -> void: EditorInterface.restart_editor(true))
	add_child(buttons)
	if not always_shown:
		add_child(HSeparator.new())
	_box.changed.connect(_show)
	_show()


func _show() -> void:
	var newer := _box.available()
	var news := not newer.is_empty() or _box.installed()
	visible = news or always_shown
	_said.text = _box.words()
	_said.visible = not _said.text.is_empty()
	_said.add_theme_color_override("font_color", _box.words_colour() if _said.visible else NEWS_COLOUR)
	_update.visible = not newer.is_empty()
	_update.disabled = _box.busy()
	_news.visible = not newer.is_empty()
	_restart.visible = _box.installed()


func _button(row: HBoxContainer, words: String, tip: String) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = tip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button
