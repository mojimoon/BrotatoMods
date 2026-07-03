extends PanelContainer

# 物品选择弹窗：选择一个或多个目标物品 + 是否诅咒 + 一键清空 + 替换选项。
# 样式参考 cave-modtools 的 shop_override_ui。
# 稀有度底色由 InventoryElement.set_element 自动调用 update_background_color 实现。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAll/mod_main.gd")
const INVENTORY_ELEMENT = preload("res://items/global/inventory_element.tscn")
const FONT_26 = preload("res://resources/fonts/actual/base/font_26.tres")

# 物品图标尺寸（原版 InventoryElement 默认 96x96）
const EL_SCALE = 0.75
const EL_SIZE = 72.0
const GRID_COLUMNS = 16

# 稀有度底色基础 StyleBox（弹窗无游戏主题，Button.normal 默认为空样式，
# 需先注入 StyleBoxFlat 才能让 update_background_color 的 bg_color 生效）
var _base_stylebox: StyleBoxFlat

var _selected_grid: GridContainer
var _available_grid: GridContainer
var _selected_label: Label
var _cursed_checkbox: CheckBox
var _mod = null
# 选项 checkbox 引用，用于互斥联动与启用态着色
var _option_checkboxes: Dictionary = {}	# key -> CheckBox
const _OPTION_GREEN: Color = Color(0.45, 0.95, 0.45)


func _ready() -> void:
	_mod = ModMain._get_mod()
	# 准备稀有度底色基础 StyleBoxFlat（InventoryElement.update_background_color
	# 依赖 get_stylebox("normal") 返回有 bg_color 属性的 StyleBox）
	_base_stylebox = StyleBoxFlat.new()
	_base_stylebox.bg_color = Color(0, 0, 0, 0.25)
	_base_stylebox.corner_radius_top_left = 4
	_base_stylebox.corner_radius_top_right = 4
	_base_stylebox.corner_radius_bottom_left = 4
	_base_stylebox.corner_radius_bottom_right = 4
	_build_ui()
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
	title.text = tr("MOJI_TITLE")
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

	# ---- 替换选项 ----
	var options_label = Label.new()
	options_label.text = tr("MOJI_OPTIONS")
	_apply_font(options_label)
	vbox.add_child(options_label)

	var options_row = HBoxContainer.new()
	options_row.add_constant_override("separation", 16)
	vbox.add_child(options_row)

	_add_option_checkbox(options_row, "MOJI_REPLACE_STARTING", "cfg_replace_starting", "_on_option_toggled_starting")
	_add_option_checkbox(options_row, "MOJI_REPLACE_SHOP", "cfg_replace_shop", "_on_option_toggled_shop")
	_add_option_checkbox(options_row, "MOJI_SHOP_ALWAYS_APPEAR", "cfg_replace_shop_first", "_on_option_toggled_shop_first")
	_add_option_checkbox(options_row, "MOJI_REPLACE_CRATE", "cfg_replace_crate", "_on_option_toggled_crate")
	_add_option_checkbox(options_row, "MOJI_REPLACE_LEGENDARY", "cfg_replace_legendary_crate", "_on_option_toggled_legendary")
	# 初始着色
	_update_option_colors()

	# ---- 已选区 ----
	_selected_label = Label.new()
	_apply_font(_selected_label)
	vbox.add_child(_selected_label)

	var sel_header = HBoxContainer.new()
	sel_header.add_constant_override("separation", 10)
	vbox.add_child(sel_header)

	var cursed_lbl = Label.new()
	cursed_lbl.text = tr("MOJI_CURSE") + ":"
	_apply_font(cursed_lbl)
	sel_header.add_child(cursed_lbl)

	_cursed_checkbox = CheckBox.new()
	_cursed_checkbox.pressed = _mod.force_cursed if _mod else false
	_cursed_checkbox.focus_mode = Control.FOCUS_NONE
	_cursed_checkbox.connect("toggled", self, "_on_cursed_toggled")
	sel_header.add_child(_cursed_checkbox)

	var clear_btn = Button.new()
	clear_btn.text = tr("MOJI_CLEAR")
	clear_btn.rect_min_size = Vector2(160, 44)
	clear_btn.focus_mode = Control.FOCUS_NONE
	_apply_font(clear_btn)
	clear_btn.connect("pressed", self, "_on_clear_pressed")
	sel_header.add_child(clear_btn)

	var sel_scroll = ScrollContainer.new()
	sel_scroll.rect_min_size = Vector2(0, int(EL_SIZE) + 24)
	sel_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_scroll.scroll_horizontal_enabled = true
	vbox.add_child(sel_scroll)

	_selected_grid = _make_grid()
	sel_scroll.add_child(_selected_grid)

	# ---- 可选区 ----
	var avail_label = Label.new()
	avail_label.text = tr("MOJI_HINT")
	_apply_font(avail_label)
	avail_label.rect_min_size = Vector2(0, 30)
	vbox.add_child(avail_label)

	var avail_scroll = ScrollContainer.new()
	avail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avail_scroll.scroll_horizontal_enabled = true
	vbox.add_child(avail_scroll)

	_available_grid = _make_grid()
	avail_scroll.add_child(_available_grid)

	_refresh_selected()
	_populate_available()


func _make_grid() -> GridContainer:
	var g = GridContainer.new()
	g.columns = GRID_COLUMNS
	# 用 SHRINK_CENTER 让网格只占内容宽度，不撑满 ScrollContainer（避免溢出弹窗边界）
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	g.add_constant_override("hseparation", 4)
	g.add_constant_override("vseparation", 4)
	return g


func _add_option_checkbox(parent: Control, key: String, state_path: String, method: String) -> void:
	var cb = CheckBox.new()
	cb.text = tr(key)
	cb.focus_mode = Control.FOCUS_NONE
	_apply_font(cb)
	if _mod:
		cb.pressed = _mod.get(state_path)
	cb.connect("toggled", self, method)
	parent.add_child(cb)
	_option_checkboxes[key] = cb


# 启用态着色：勾选的选项文字绿色，未勾选恢复默认；
func _update_option_colors() -> void:
	for key in _option_checkboxes:
		var cb: CheckBox = _option_checkboxes[key]
		if cb.pressed:
			cb.add_color_override("font_color", _OPTION_GREEN)
			cb.add_color_override("font_color_hover", _OPTION_GREEN)
			cb.add_color_override("font_color_pressed", _OPTION_GREEN)
			cb.add_color_override("font_color_disabled", _OPTION_GREEN)
		else:
			cb.remove_color_override("font_color")
			cb.remove_color_override("font_color_hover")
			cb.remove_color_override("font_color_pressed")
			cb.remove_color_override("font_color_disabled")


# ---------- 物品网格 ----------
func _populate_available() -> void:
	var items = ItemService.items
	var sorted = items.duplicate()
	sorted.sort_custom(self, "_sort_by_tier_id")

	for item_data in sorted:
		var wrapper = Control.new()
		wrapper.rect_min_size = Vector2(EL_SIZE, EL_SIZE)
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
		_available_grid.add_child(wrapper)

		# 必须先 add_child 再 set_element：onready 变量入树 _ready 前为 null
		var el = INVENTORY_ELEMENT.instance()
		wrapper.add_child(el)
		# 注入 StyleBoxFlat 基础，让 update_background_color 的 bg_color 能生效（稀有度底色）
		el.add_stylebox_override("normal", _base_stylebox.duplicate())
		el.rect_scale = Vector2(EL_SCALE, EL_SCALE)
		el.set_element(item_data)
		el.connect("element_pressed", self, "_on_available_pressed", [item_data.my_id])


func _refresh_selected() -> void:
	for c in _selected_grid.get_children():
		c.free()

	if _mod == null:
		return
	_selected_label.text = tr("MOJI_SELECTED") % _mod.target_item_ids.size()

	for item_id in _mod.target_item_ids:
		var item_data = ItemService.get_element_safe(ItemService.items, item_id)
		if item_data == null:
			continue

		var wrapper = Control.new()
		wrapper.rect_min_size = Vector2(EL_SIZE, EL_SIZE)
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
		_selected_grid.add_child(wrapper)

		var el = INVENTORY_ELEMENT.instance()
		wrapper.add_child(el)
		# 注入 StyleBoxFlat 基础，让 update_background_color 的 bg_color 能生效（稀有度底色）
		el.add_stylebox_override("normal", _base_stylebox.duplicate())
		el.rect_scale = Vector2(EL_SCALE, EL_SCALE)
		# 诅咒预览：duplicate 一份并标记 is_cursed，不影响原物品
		if _mod.force_cursed:
			var d = item_data.duplicate()
			d.is_cursed = true
			el.set_element(d)
		else:
			el.set_element(item_data)
		el.connect("element_pressed", self, "_on_selected_pressed", [item_id])


# ---------- 信号回调 ----------
func _on_available_pressed(_element, item_id: String) -> void:
	if _mod == null:
		return
	if _mod.target_item_ids.has(item_id):
		return
	_mod.target_item_ids.append(item_id)
	call_deferred("_refresh_selected")


func _on_selected_pressed(_element, item_id: String) -> void:
	if _mod == null:
		return
	_mod.target_item_ids.erase(item_id)
	# 必须延迟刷新：当前 InventoryElement 正在发射 element_pressed 信号，
	# 直接 _refresh_selected() 会 free() 掉正在发信号的节点 → 闪退。
	call_deferred("_refresh_selected")


func _on_cursed_toggled(pressed: bool) -> void:
	if _mod == null:
		return
	_mod.force_cursed = pressed
	_refresh_selected()


func _on_clear_pressed() -> void:
	if _mod == null:
		return
	_mod.target_item_ids.clear()
	_refresh_selected()


# ---------- 替换选项回调 ----------
# shop / shop_first 互斥：勾选一个自动取消另一个
func _on_option_toggled_starting(pressed: bool) -> void:
	if _mod: _mod.cfg_replace_starting = pressed
	_update_option_colors()

func _on_option_toggled_shop(pressed: bool) -> void:
	if _mod: _mod.cfg_replace_shop = pressed
	if pressed and _mod:
		_mod.cfg_replace_shop_first = false
		var cb = _option_checkboxes.get("MOJI_SHOP_ALWAYS_APPEAR")
		if cb: cb.pressed = false
	_update_option_colors()

func _on_option_toggled_shop_first(pressed: bool) -> void:
	if _mod: _mod.cfg_replace_shop_first = pressed
	if pressed and _mod:
		_mod.cfg_replace_shop = false
		var cb = _option_checkboxes.get("MOJI_REPLACE_SHOP")
		if cb: cb.pressed = false
	_update_option_colors()

func _on_option_toggled_crate(pressed: bool) -> void:
	if _mod: _mod.cfg_replace_crate = pressed
	_update_option_colors()

func _on_option_toggled_legendary(pressed: bool) -> void:
	if _mod: _mod.cfg_replace_legendary_crate = pressed
	_update_option_colors()


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
