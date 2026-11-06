@tool
extends VBoxContainer
## The Pieces panel: the whole kit, with a picture of each, in groups, with a search box. Drag one into
## the 3D view to place it, or click one to add it to the brush's mix. The pictures are made once and
## checked in: thumbs_no_window.gd makes them, and opening the panel only reads them.

const Kit := preload("kit.gd")

## What a drag from this panel carries, so that nothing else takes it by mistake.
const DRAG_KIND := "smart_fellas_piece"
const TILE_SIDE := 72.0

## A piece was clicked.
signal piece_clicked(kit: String)
## A piece has started being dragged.
signal drag_started


## One piece's picture and name, which can be clicked or dragged.
class Tile extends VBoxContainer:
	signal clicked(kit: String)
	signal dragged

	var kit: String
	var picture: Texture2D

	func _init(kit_name: String, texture: Texture2D) -> void:
		kit = kit_name
		picture = texture
		var plain := Kit.plain_name(kit)
		tooltip_text = "%s\nDrag it into the 3D view to place one. Click it to add it to the brush's mix." % plain
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(TILE_SIDE, 0.0)
		add_theme_constant_override("separation", 1)
		var view := TextureRect.new()
		view.custom_minimum_size = Vector2(TILE_SIDE, TILE_SIDE)
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.texture = picture
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		var label := Label.new()
		label.text = plain
		label.add_theme_font_size_override("font_size", 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(TILE_SIDE, 0.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				clicked.emit(kit)

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(TILE_SIDE, TILE_SIDE)
		preview.size = Vector2(TILE_SIDE, TILE_SIDE)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.texture = picture
		preview.modulate.a = 0.8
		set_drag_preview(preview)
		dragged.emit()
		return {"type": DRAG_KIND, "kit": kit}


var _search: LineEdit
var _none_found: Label
var _groups: Array[Dictionary] = []


func _ready() -> void:
	name = "Pieces"
	custom_minimum_size = Vector2(200.0, 160.0)
	_search = LineEdit.new()
	_search.placeholder_text = "Search: kelp, pink, rock…"
	_search.clear_button_enabled = true
	_search.tooltip_text = "Shows only the pieces with these words in their name or group."
	_search.text_changed.connect(_apply_search)
	add_child(_search)
	var hint := Label.new()
	hint.text = "Drag a piece into the 3D view to place it. Click one to add it to the brush."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(180.0, 0.0)
	hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_none_found = Label.new()
	_none_found.text = "Nothing in the kit by that name."
	_none_found.visible = false
	list.add_child(_none_found)
	_add_groups(list)


func _add_groups(list: Control) -> void:
	for group in Kit.GROUPS:
		var fold := FoldableContainer.new()
		fold.title = group[0]
		var tiles := HFlowContainer.new()
		fold.add_child(tiles)
		list.add_child(fold)
		_groups.append({"fold": fold, "tiles": tiles, "words": (group[0] as String).to_lower()})
	for kit in Kit.names():
		var tile := Tile.new(kit, Kit.thumb_of(kit))
		tile.clicked.connect(func(clicked_kit: String) -> void: piece_clicked.emit(clicked_kit))
		tile.dragged.connect(func() -> void: drag_started.emit())
		var group: Dictionary = _groups[Kit.group_of(kit)]
		(group["tiles"] as Control).add_child(tile)


## Shows only what fits the words, in any order and against the piece's name, kind or group.
func _apply_search(words: String) -> void:
	var wanted := words.to_lower().split(" ", false)
	var any := false
	for group in _groups:
		var in_group := 0
		for tile: Tile in (group["tiles"] as Control).get_children():
			var fits := true
			var about := "%s %s %s" % [Kit.plain_name(tile.kit).to_lower(), tile.kit, group["words"]]
			for word in wanted:
				fits = fits and about.contains(word)
			tile.visible = fits
			if fits:
				in_group += 1
		(group["fold"] as Control).visible = in_group > 0
		any = any or in_group > 0
	_none_found.visible = not any
