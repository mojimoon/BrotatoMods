extends Button

# 下拉选择（代替 OptionButton）：弹出多列网格，长列表（道具标签等）不会超出屏幕。
# 提供筛选栏用到的 OptionButton 接口：clear / add_item / set_item_metadata / get_item_count / get_item_metadata / select / get_selected_metadata，
# 选择后发出 item_selected(index)。

signal item_selected(index)

const COLUMNS_LONG = 3	# 超过 LONG_LIST 项时的列数
const LONG_LIST = 10

var _texts = []
var _metas = []
var selected := -1
var _popup: PopupPanel
var _grid: GridContainer
var _font: Font


func _init() -> void:
	clip_text = true
	align = ALIGN_LEFT
	icon_align = ALIGN_RIGHT
	connect("pressed", self, "_open")


func _ready() -> void:
	icon = get_icon("arrow", "OptionButton")


func clear() -> void:
	_texts = []
	_metas = []
	selected = -1
	text = ""


func add_item(label: String) -> void:
	_texts.push_back(label)
	_metas.push_back(null)


func set_item_metadata(i: int, meta) -> void:
	_metas[i] = meta


func get_item_count() -> int:
	return _texts.size()


func get_item_metadata(i: int):
	return _metas[i]


func get_selected_metadata():
	return _metas[selected] if selected >= 0 and selected < _metas.size() else null


func select(i: int) -> void:
	selected = i
	text = _texts[i] if i >= 0 and i < _texts.size() else ""


func set_list_font(font: Font) -> void:
	_font = font
	add_font_override("font", font)


func _open() -> void:
	if _popup == null:
		_popup = PopupPanel.new()
		_grid = GridContainer.new()
		_grid.add_constant_override("hseparation", 4)
		_grid.add_constant_override("vseparation", 4)
		_popup.add_child(_grid)
		add_child(_popup)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_grid.columns = COLUMNS_LONG if _texts.size() > LONG_LIST else 1
	var focus_btn = null
	for i in _texts.size():
		var b = Button.new()
		b.text = _texts[i]
		b.align = ALIGN_LEFT
		b.toggle_mode = true
		b.pressed = i == selected
		if _font != null:
			b.add_font_override("font", _font)
		b.connect("pressed", self, "_on_pick", [i])
		_grid.add_child(b)
		if i == selected or focus_btn == null:
			focus_btn = b
	_popup.rect_size = Vector2.ZERO
	var size = _popup.get_combined_minimum_size()
	var view = get_viewport_rect().size
	var pos = rect_global_position + Vector2(0, rect_size.y)
	pos.x = clamp(pos.x, 0, max(0, view.x - size.x))
	pos.y = clamp(pos.y, 0, max(0, view.y - size.y))
	_popup.popup(Rect2(pos, size))
	if focus_btn != null:
		focus_btn.call_deferred("grab_focus")


func _on_pick(i: int) -> void:
	_popup.hide()
	select(i)
	emit_signal("item_selected", i)
	grab_focus()
