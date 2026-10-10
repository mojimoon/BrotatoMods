extends Button

# 可搜索的下拉选择：点击后在按钮下方弹出列表（顶部搜索框），每行左边是本地化名称、右边灰色小字是键名。
# items: [[名称, 键]...]；选中后发出 selected(键)。按名称或键名搜索，回车选第一项。

signal selected(key)

const ROW_HEIGHT = 34
const LIST_HEIGHT = 420

var items: Array = []
var key = null
var placeholder := ""
var fixed_text := ""	# 非空时按钮始终显示这段文字（例如"+ 扳机"），不显示选中项
var ui = null

var _popup: Control = null
var _list: VBoxContainer
var _search: LineEdit


func setup(p_ui, p_items: Array, p_key = null) -> void:
	ui = p_ui
	items = p_items
	key = p_key
	focus_mode = Control.FOCUS_NONE
	clip_text = true
	align = Button.ALIGN_LEFT
	add_font_override("font", ui.FONT_DESC)
	ui._apply_action_style(self, ui.C_ACCENT_2)
	_refresh_text()
	var _e = connect("pressed", self, "open")


func set_key(k) -> void:
	key = k
	_refresh_text()


func _refresh_text() -> void:
	if fixed_text != "":
		text = fixed_text
		return
	text = placeholder
	for it in items:
		if it[1] == key:
			text = it[0]
			return
	if key != null and str(key) != "":
		text = str(key)


func open() -> void:
	close()
	_popup = Control.new()
	_popup.set_anchors_preset(Control.PRESET_WIDE)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.connect("gui_input", self, "_on_backdrop_input")
	ui.add_child(_popup)
	ui.active_popup = self
	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", ui._style(ui.C_BG_PANEL, ui.C_ACCENT_2, 8, 2, 8, 8))
	_popup.add_child(panel)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 6)
	panel.add_child(box)
	_search = ui._line_edit(ui.tr("BE_SEARCH"))
	_search.connect("text_changed", self, "_on_search")
	_search.connect("text_entered", self, "_on_enter")
	box.add_child(_search)
	var scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.rect_min_size = Vector2(0, min(LIST_HEIGHT, max(1, items.size()) * (ROW_HEIGHT + 2) + 4))
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_constant_override("separation", 2)
	scroll.add_child(_list)
	_fill("")
	# 位置：按钮下方，超出屏幕时放到上方 / 向左收
	var w = max(rect_size.x, 380)
	panel.rect_min_size = Vector2(w, 0)
	var vp = get_viewport_rect().size
	var h = scroll.rect_min_size.y + 70
	var pos = rect_global_position + Vector2(0, rect_size.y + 4)
	if pos.y + h > vp.y:
		pos.y = max(4, rect_global_position.y - h - 4)
	pos.x = clamp(pos.x, 4, max(4, vp.x - w - 4))
	panel.rect_global_position = pos
	_search.call_deferred("grab_focus")


func close() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null
	if ui != null and ui.active_popup == self:
		ui.active_popup = null


func _exit_tree() -> void:
	close()


func _fill(filter: String) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for it in items:
		if filter != "" and str(it[0]).to_lower().find(filter) < 0 and str(it[1]).to_lower().find(filter) < 0:
			continue
		_list.add_child(_row(it))


func _row(it: Array) -> Button:
	var b = Button.new()
	b.rect_min_size = Vector2(0, ROW_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on = it[1] == key
	b.add_stylebox_override("normal", ui._style(ui.C_BG_CHIP if on else ui.C_BG_ITEM, ui.C_ACCENT_2 if on else ui.C_BG_ITEM, 4, 1, 8, 2))
	b.add_stylebox_override("hover", ui._style(ui.C_ACCENT_2.darkened(0.6), ui.C_ACCENT_2, 4, 1, 8, 2))
	b.add_stylebox_override("pressed", ui._style(ui.C_ACCENT_2.darkened(0.7), ui.C_ACCENT_2, 4, 1, 8, 2))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	var row = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_WIDE)
	row.margin_left = 10
	row.margin_right = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var name_lbl = ui._label(str(it[0]), ui.FONT_SMALL, ui.C_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.valign = Label.VALIGN_CENTER
	name_lbl.size_flags_vertical = Control.SIZE_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)
	var key_lbl = ui._label(str(it[1]), ui.FONT_DESC, ui.C_TEXT_DIM)
	key_lbl.valign = Label.VALIGN_CENTER
	key_lbl.size_flags_vertical = Control.SIZE_FILL
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key_lbl)
	b.connect("pressed", self, "_pick", [it[1]])
	return b


var _filter := ""


func _on_search(t: String) -> void:
	_filter = t.strip_edges().to_lower()
	_fill(_filter)


# 回车：完全匹配名称 / 键名的优先，否则第一个匹配项
func _on_enter(_t: String) -> void:
	var f = _filter
	for it in items:
		if str(it[0]).to_lower() == f or str(it[1]).to_lower() == f:
			_pick(it[1])
			return
	for it in items:
		if f == "" or str(it[0]).to_lower().find(f) >= 0 or str(it[1]).to_lower().find(f) >= 0:
			_pick(it[1])
			return


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [BUTTON_LEFT, BUTTON_RIGHT]:
		close()


func _pick(k) -> void:
	close()
	if fixed_text == "":
		set_key(k)
	emit_signal("selected", k)
