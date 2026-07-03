extends PanelContainer

# 物品选择弹窗：选择一个或多个目标物品 + 是否诅咒 + 一键清空。
# 样式参考 cave-modtools 的 shop_override_ui。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAll/mod_main.gd")
const INVENTORY_ELEMENT = preload("res://items/global/inventory_element.tscn")
const FONT_26 = preload("res://resources/fonts/actual/base/font_26.tres")

var _selected_grid: GridContainer
var _available_grid: GridContainer
var _selected_label: Label
var _cursed_checkbox: CheckBox
var _mod = null


func _ready() -> void:
	_mod = ModMain._get_mod()
	_build_ui()
	# 拦截 ui_cancel，避免被底层菜单处理导致界面错乱
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_tree().set_input_as_handled()


func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 14)
	margin.add_constant_override("margin_bottom", 14)
	margin.add_constant_override("margin_left", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 10)
	margin.add_child(vbox)

	# ---- Header ----
	var header = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "替换物品设置"
	_apply_font(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.rect_min_size = Vector2(50, 50)
	close_btn.focus_mode = Control.FOCUS_NONE
	_apply_font(close_btn)
	close_btn.connect("pressed", self, "_on_close_pressed")
	header.add_child(close_btn)

	# ---- 已选区 ----
	_selected_label = Label.new()
	_apply_font(_selected_label)
	vbox.add_child(_selected_label)

	var sel_header = HBoxContainer.new()
	sel_header.add_constant_override("separation", 10)
	vbox.add_child(sel_header)

	var cursed_lbl = Label.new()
	cursed_lbl.text = "诅咒:"
	_apply_font(cursed_lbl)
	sel_header.add_child(cursed_lbl)

	_cursed_checkbox = CheckBox.new()
	_cursed_checkbox.pressed = _mod.force_cursed
	_cursed_checkbox.focus_mode = Control.FOCUS_NONE
	_cursed_checkbox.connect("toggled", self, "_on_cursed_toggled")
	sel_header.add_child(_cursed_checkbox)

	var clear_btn = Button.new()
	clear_btn.text = "一键清空"
	clear_btn.rect_min_size = Vector2(160, 44)
	clear_btn.focus_mode = Control.FOCUS_NONE
	_apply_font(clear_btn)
	clear_btn.connect("pressed", self, "_on_clear_pressed")
	sel_header.add_child(clear_btn)

	var sel_scroll = ScrollContainer.new()
	sel_scroll.rect_min_size = Vector2(0, 150)
	sel_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_scroll.scroll_horizontal_enabled = true
	vbox.add_child(sel_scroll)

	_selected_grid = GridContainer.new()
	_selected_grid.columns = 20
	_selected_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_grid.add_constant_override("hseparation", 4)
	_selected_grid.add_constant_override("vseparation", 4)
	sel_scroll.add_child(_selected_grid)

	# ---- 可选区 ----
	var avail_label = Label.new()
	avail_label.text = "点击物品添加为替换目标（多个目标将轮流替换；点击已选物品可移除）"
	_apply_font(avail_label)
	avail_label.rect_min_size = Vector2(0, 30)
	vbox.add_child(avail_label)

	var avail_scroll = ScrollContainer.new()
	avail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avail_scroll.scroll_horizontal_enabled = true
	vbox.add_child(avail_scroll)

	_available_grid = GridContainer.new()
	_available_grid.columns = 20
	_available_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available_grid.add_constant_override("hseparation", 4)
	_available_grid.add_constant_override("vseparation", 4)
	avail_scroll.add_child(_available_grid)

	_refresh_selected()
	_populate_available()


func _populate_available() -> void:
	var items = ItemService.items
	var sorted = items.duplicate()
	sorted.sort_custom(self, "_sort_by_tier_id")

	for item_data in sorted:
		var wrapper = Control.new()
		wrapper.rect_min_size = Vector2(48, 48)
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

		var el = INVENTORY_ELEMENT.instance()
		el.rect_scale = Vector2(0.5, 0.5)
		el.set_element(item_data)
		el.connect("element_pressed", self, "_on_available_pressed", [item_data.my_id])
		wrapper.add_child(el)
		_available_grid.add_child(wrapper)


func _refresh_selected() -> void:
	for c in _selected_grid.get_children():
		c.free()

	_selected_label.text = "已选目标：%d 个" % _mod.target_item_ids.size()

	for item_id in _mod.target_item_ids:
		var item_data = ItemService.get_element_safe(ItemService.items, item_id)
		if item_data == null:
			continue

		var wrapper = Control.new()
		wrapper.rect_min_size = Vector2(48, 48)
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

		var el = INVENTORY_ELEMENT.instance()
		el.rect_scale = Vector2(0.5, 0.5)
		if _mod.force_cursed:
			var d = item_data.duplicate()
			d.is_cursed = true
			el.set_element(d)
		else:
			el.set_element(item_data)
		el.connect("element_pressed", self, "_on_selected_pressed", [item_id])
		wrapper.add_child(el)
		_selected_grid.add_child(wrapper)


# ---------- 信号回调 ----------
func _on_available_pressed(_element, item_id: String) -> void:
	if _mod.target_item_ids.has(item_id):
		return
	_mod.target_item_ids.append(item_id)
	_refresh_selected()


func _on_selected_pressed(_element, item_id: String) -> void:
	_mod.target_item_ids.erase(item_id)
	_refresh_selected()


func _on_cursed_toggled(pressed: bool) -> void:
	_mod.force_cursed = pressed
	_refresh_selected()


func _on_clear_pressed() -> void:
	_mod.target_item_ids.clear()
	_refresh_selected()


func _on_close_pressed() -> void:
	queue_free()


# ---------- 工具 ----------
func _apply_font(control: Control) -> void:
	if FONT_26 != null:
		control.add_font_override("font", FONT_26)


func _sort_by_tier_id(a, b) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.my_id < b.my_id
