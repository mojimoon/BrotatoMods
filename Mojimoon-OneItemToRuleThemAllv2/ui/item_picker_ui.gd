extends Control

# 物品选择弹窗。布局（自上而下）：
#   标题栏：标题 + 关闭
#   选项卡片：总开关 / 替换对象（起始 / 商店 / 商店通常销售 / 箱子）/ 诅咒开关
#   通用替换池卡片：说明（随替换对象变化）+ 已选物品（带序号）+ 清空
#   T4 箱子池卡片：四种模式 + 模式说明 + 独立替换池（仅独立/单次模式显示）
#   全部物品卡片：搜索 + 物品网格（点击添加到"当前替换池"）
# 两个替换池通过点击卡片切换"当前替换池"，当前池高亮边框，网格中已在当前池的物品带同色描边。
# 样式参考 cave-modtools（base_theme + StyleBoxFlat 圆角卡片 / 强调色按钮）。
# 稀有度底色由 InventoryElement.set_element 自动调用 update_background_color 实现。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAllv2/mod_main.gd")
const INVENTORY_ELEMENT = preload("res://items/global/inventory_element.tscn")
const FONT_TITLE = preload("res://resources/fonts/actual/base/font_32_outline.tres")
const FONT_NORMAL = preload("res://resources/fonts/actual/base/font_26.tres")
const FONT_SMALL = preload("res://resources/fonts/actual/base/font_22.tres")
const FONT_BADGE = preload("res://resources/fonts/actual/base/font_very_smallest_text.tres")

const PANEL_SIZE = Vector2(1280, 1000)
# 物品图标尺寸（原版 InventoryElement 默认 96x96）
const EL_SCALE = 0.625
const EL_SIZE = 60.0
const EL_SEP = 6

const POOL_REGULAR = 0
const POOL_LEGENDARY = 1

const MODE_KEYS = ["MOJI_LEG_NONE", "MOJI_LEG_UNIFIED", "MOJI_LEG_SEQUENTIAL", "MOJI_LEG_ONCE"]
const MODE_DESC_KEYS = ["MOJI_LEG_NONE_DESC", "MOJI_LEG_UNIFIED_DESC", "MOJI_LEG_SEQUENTIAL_DESC", "MOJI_LEG_ONCE_DESC"]
# [配置字段, 翻译 key]
const OPTIONS = [
	["cfg_replace_starting", "MOJI_REPLACE_STARTING"],
	["cfg_replace_shop", "MOJI_REPLACE_SHOP"],
	["cfg_replace_shop_first", "MOJI_SHOP_ALWAYS_APPEAR"],
	["cfg_replace_crate", "MOJI_REPLACE_CRATE"],
]

# ---------- 配色 ----------
const C_TEXT = Color(0.94, 0.96, 1.0)
const C_TEXT_DIM = Color(0.62, 0.67, 0.76)
const C_BACKDROP = Color(0, 0, 0, 0.6)
const C_BG_PANEL = Color(0.06, 0.07, 0.10, 0.98)
const C_BG_CARD = Color(0.11, 0.13, 0.18, 0.95)
const C_BG_CHIP = Color(0.13, 0.16, 0.22, 0.95)
const C_BORDER = Color(0.28, 0.33, 0.42)
const C_ACCENT_OPTION = Color(0.40, 0.72, 1.0)
const C_ACCENT_REGULAR = Color(0.30, 0.85, 0.55)
const C_ACCENT_LEGENDARY = Color(1.0, 0.45, 0.40)
const C_ACCENT_CURSE = Color(0.72, 0.52, 0.95)
const C_DANGER = Color(0.92, 0.38, 0.44)

var _mod = null
# 稀有度底色基础 StyleBox（InventoryElement.update_background_color 依赖
# get_stylebox("normal") 返回有 bg_color 属性的 StyleBox）
var _base_stylebox: StyleBoxFlat

var _option_chips: Dictionary = {}	# 配置字段 -> Button
var _enable_switch: CheckButton
var _curse_switch: CheckButton
var _mode_buttons: Array = []
var _mode_desc: Label
var _regular_desc: Label
# 总开关关闭时变暗的区域
var _dimmable: Array = []
# 缩小后的开关图标（原图 100x50 太大）
var _switch_icons: Dictionary = {}

# 按 POOL_* 索引
var _pool_cards: Array = [null, null]
var _pool_rows: Array = [null, null]
var _pool_counts: Array = [null, null]
var _pool_clear_btns: Array = [null, null]
var _legendary_pool_box: Control
var _active_pool: int = POOL_REGULAR

var _add_target_label: Label
var _search: LineEdit
var _avail_scroll: ScrollContainer
var _avail_grid: GridContainer
# 每个可选物品：{ "id", "key"（搜索用小写名称）, "wrapper", "marker" }
var _avail_entries: Array = []


func _ready() -> void:
	_mod = ModMain._get_mod()
	if _mod == null:
		queue_free()
		return
	if not ProgressData.is_dlc_available_and_active("abyssal_terrors"):
		_mod.force_cursed = false

	_base_stylebox = StyleBoxFlat.new()
	_base_stylebox.bg_color = Color(0, 0, 0, 0.25)
	_set_radius(_base_stylebox, 4)

	_build_ui()
	if _is_legendary_pool_visible() and _mod.target_item_ids.empty() and not _mod.legendary_item_ids.empty():
		_active_pool = POOL_LEGENDARY
	_refresh_all()
	set_process_unhandled_input(true)


# 点击卡片切换当前替换池。卡片里的按钮 / 物品 / 滚动容器会吞掉鼠标事件，
# gui_input 冒泡不可靠，所以在 _input（GUI 分发之前）按卡片矩形判断，且不消费事件。
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	_select_pool_at(get_global_mouse_position())


# 把 point（画布全局坐标）所在卡片设为当前替换池；T4 箱子池仅在独立/单次模式下可选
func _select_pool_at(point: Vector2) -> void:
	var pool = _pool_at(point)
	if pool == -1:
		return
	if pool == POOL_LEGENDARY and not _is_legendary_pool_visible():
		return
	if _active_pool != pool:
		_active_pool = pool
		_refresh_active_pool()


# 返回 point 所在的替换池卡片，不在任何卡片内返回 -1
func _pool_at(point: Vector2) -> int:
	for pool in [POOL_REGULAR, POOL_LEGENDARY]:
		var card: Control = _pool_cards[pool]
		if card != null and card.is_visible_in_tree() and card.get_global_rect().has_point(point):
			return pool
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_tree().set_input_as_handled()


# ============================================================
# 构建 UI
# ============================================================
func _build_ui() -> void:
	# 半透明遮罩：同时阻止点击穿透到底层菜单
	var backdrop = ColorRect.new()
	backdrop.color = C_BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_WIDE)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel = PanelContainer.new()
	panel.rect_min_size = PANEL_SIZE
	panel.add_stylebox_override("panel", _style(C_BG_PANEL, C_BORDER, 12, 2, 20, 16))
	center.add_child(panel)

	var root = VBoxContainer.new()
	root.add_constant_override("separation", 12)
	panel.add_child(root)

	_build_header(root)
	_build_options_card(root)
	_build_regular_card(root)
	_build_legendary_card(root)
	_build_available_card(root)

	var footer = _label(tr("MOJI_HINT"), FONT_SMALL, C_TEXT_DIM)
	footer.align = Label.ALIGN_CENTER
	footer.autowrap = true
	root.add_child(footer)


func _build_header(parent: Control) -> void:
	var header = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	parent.add_child(header)

	var title = _label(tr("MOJI_BTN_OPEN"), FONT_TITLE, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = _button("X", FONT_NORMAL)
	close_btn.rect_min_size = Vector2(48, 44)
	_apply_action_style(close_btn, C_DANGER)
	close_btn.connect("pressed", self, "_on_close_pressed")
	header.add_child(close_btn)


func _build_options_card(parent: Control) -> void:
	var card = _card(parent)
	card.add_stylebox_override("panel", _card_style(C_BORDER, false))

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	card.add_child(vbox)

	# 第一行：选项 + 总开关
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 10)
	vbox.add_child(head)
	head.add_child(_label(tr("MOJI_OPTIONS"), FONT_NORMAL, C_TEXT))
	head.add_child(_spacer())
	_enable_switch = _switch(tr("MOJI_ENABLE"), _mod.enabled)
	_enable_switch.connect("toggled", self, "_on_enable_toggled")
	head.add_child(_enable_switch)

	# 第二行：替换对象 + 诅咒开关
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	vbox.add_child(row)
	_dimmable.push_back(row)

	row.add_child(_label(tr("MOJI_WHAT_TO_REPLACE"), FONT_SMALL, C_TEXT_DIM))
	for opt in OPTIONS:
		var chip = _button(tr(opt[1]), FONT_SMALL)
		chip.toggle_mode = true
		chip.pressed = bool(_mod.get(opt[0]))
		chip.connect("toggled", self, "_on_option_toggled", [opt[0]])
		row.add_child(chip)
		_option_chips[opt[0]] = chip

	row.add_child(_spacer())

	var dlc_active = ProgressData.is_dlc_available_and_active("abyssal_terrors")
	var curse_text = tr("MOJI_CURSE")
	if not dlc_active:
		curse_text += " (" + tr("MOJI_CURSE_DLC_REQUIRED") + ")"
	_curse_switch = _switch(curse_text, dlc_active and _mod.force_cursed)
	_curse_switch.disabled = not dlc_active
	_curse_switch.connect("toggled", self, "_on_cursed_toggled")
	row.add_child(_curse_switch)


func _build_regular_card(parent: Control) -> void:
	var card = _card(parent)
	_pool_cards[POOL_REGULAR] = card
	_dimmable.push_back(card)

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	card.add_child(vbox)

	var head = HBoxContainer.new()
	head.add_constant_override("separation", 10)
	vbox.add_child(head)
	head.add_child(_label(tr("MOJI_POOL_REGULAR"), FONT_NORMAL, C_ACCENT_REGULAR))
	_add_pool_count_and_clear(head, POOL_REGULAR)

	_regular_desc = _label("", FONT_SMALL, C_TEXT_DIM)
	_regular_desc.autowrap = true
	vbox.add_child(_regular_desc)

	vbox.add_child(_pool_row(POOL_REGULAR))


func _build_legendary_card(parent: Control) -> void:
	var card = _card(parent)
	_pool_cards[POOL_LEGENDARY] = card
	_dimmable.push_back(card)

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	card.add_child(vbox)

	var head = HBoxContainer.new()
	head.add_constant_override("separation", 10)
	vbox.add_child(head)
	head.add_child(_label(tr("MOJI_LEGENDARY"), FONT_NORMAL, C_ACCENT_LEGENDARY))

	# 四种模式：分段按钮（ButtonGroup 保证单选）
	var modes = HBoxContainer.new()
	modes.add_constant_override("separation", 4)
	head.add_child(modes)
	var group = ButtonGroup.new()
	for i in MODE_KEYS.size():
		var btn = _button(tr(MODE_KEYS[i]), FONT_SMALL)
		btn.toggle_mode = true
		btn.group = group
		btn.pressed = i == _mod.legendary_mode
		btn.connect("pressed", self, "_on_mode_pressed", [i])
		modes.add_child(btn)
		_mode_buttons.push_back(btn)

	_add_pool_count_and_clear(head, POOL_LEGENDARY)

	_mode_desc = _label("", FONT_SMALL, C_TEXT_DIM)
	_mode_desc.autowrap = true
	vbox.add_child(_mode_desc)

	_legendary_pool_box = _pool_row(POOL_LEGENDARY)
	vbox.add_child(_legendary_pool_box)


func _build_available_card(parent: Control) -> void:
	var card = _card(parent)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dimmable.push_back(card)
	card.add_stylebox_override("panel", _card_style(C_BORDER, false))

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	card.add_child(vbox)

	var head = HBoxContainer.new()
	head.add_constant_override("separation", 14)
	vbox.add_child(head)
	head.add_child(_label(tr("MOJI_ALL_ITEMS"), FONT_NORMAL, C_TEXT))
	_add_target_label = _label("", FONT_SMALL, C_ACCENT_REGULAR)
	head.add_child(_add_target_label)
	head.add_child(_spacer())

	_search = LineEdit.new()
	_search.rect_min_size = Vector2(320, 0)
	_search.placeholder_text = tr("MOJI_SEARCH")
	_search.clear_button_enabled = true
	_search.add_font_override("font", FONT_SMALL)
	_search.add_color_override("font_color", C_TEXT)
	_search.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 10, 4))
	_search.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT_OPTION, 6, 1, 10, 4))
	_search.connect("text_changed", self, "_on_search_changed")
	head.add_child(_search)

	_avail_scroll = ScrollContainer.new()
	_avail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_avail_scroll.scroll_horizontal_enabled = false
	_avail_scroll.connect("resized", self, "_fit_available_columns")
	vbox.add_child(_avail_scroll)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avail_scroll.add_child(center)

	_avail_grid = GridContainer.new()
	_avail_grid.columns = 16
	_avail_grid.add_constant_override("hseparation", EL_SEP)
	_avail_grid.add_constant_override("vseparation", EL_SEP)
	center.add_child(_avail_grid)

	_populate_available()


# 卡片头部右侧：已选数量 + 清空按钮
func _add_pool_count_and_clear(head: HBoxContainer, pool: int) -> void:
	head.add_child(_spacer())
	var count = _label("", FONT_SMALL, C_TEXT_DIM)
	head.add_child(count)
	_pool_counts[pool] = count

	var clear_btn = _button(tr("MOJI_CLEAR"), FONT_SMALL)
	_apply_action_style(clear_btn, C_DANGER)
	clear_btn.connect("pressed", self, "_on_clear_pressed", [pool])
	head.add_child(clear_btn)
	_pool_clear_btns[pool] = clear_btn


# 单行横向滚动的已选物品列表
func _pool_row(pool: int) -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, EL_SIZE + 18)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_vertical_enabled = false

	var row = HBoxContainer.new()
	row.add_constant_override("separation", EL_SEP)
	scroll.add_child(row)
	_pool_rows[pool] = row
	return scroll


# ============================================================
# 数据 / 刷新
# ============================================================
func _get_pool(pool: int) -> Array:
	return _mod.legendary_item_ids if pool == POOL_LEGENDARY else _mod.target_item_ids


func _pool_accent(pool: int) -> Color:
	return C_ACCENT_LEGENDARY if pool == POOL_LEGENDARY else C_ACCENT_REGULAR


func _pool_title(pool: int) -> String:
	return tr("MOJI_LEGENDARY") if pool == POOL_LEGENDARY else tr("MOJI_POOL_REGULAR")


func _is_legendary_pool_visible() -> bool:
	return _mod.legendary_mode == ModMain.LegendaryMode.SEQUENTIAL or _mod.legendary_mode == ModMain.LegendaryMode.ONCE


func _refresh_all() -> void:
	_refresh_option_styles()
	_refresh_enabled()
	_refresh_legendary_mode()
	_refresh_pool(POOL_REGULAR)
	_refresh_pool(POOL_LEGENDARY)


func _refresh_option_styles() -> void:
	for path in _option_chips:
		var chip: Button = _option_chips[path]
		_apply_chip_style(chip, chip.pressed, C_ACCENT_OPTION)
	_refresh_regular_desc()


# 总开关关闭时其余区域变暗（仍可编辑）
func _refresh_enabled() -> void:
	var m = Color(1, 1, 1, 1) if _mod.enabled else Color(1, 1, 1, 0.4)
	for c in _dimmable:
		c.modulate = m


# 通用替换池说明：按已启用的替换对象拼接
func _refresh_regular_desc() -> void:
	var nouns: Array = []
	if _mod.cfg_replace_starting:
		nouns.push_back(tr("MOJI_NOUN_STARTING"))
	if _mod.cfg_replace_shop:
		nouns.push_back(tr("MOJI_NOUN_SHOP"))
	if _mod.cfg_replace_crate:
		nouns.push_back(tr("MOJI_NOUN_CRATE"))

	var parts: Array = []
	if not nouns.empty():
		var sep = tr("MOJI_LIST_SEP")
		var joined = ""
		for i in nouns.size():
			if i > 0:
				joined += sep
			joined += nouns[i]
		parts.push_back(_capitalize_first(tr("MOJI_DESC_REPLACED") % joined))
	if _mod.cfg_replace_shop_first:
		parts.push_back(tr("MOJI_DESC_SHOP_SELLS"))
	if parts.empty():
		parts.push_back(tr("MOJI_DESC_NOTHING"))

	var text = ""
	for p in parts:
		if text != "" and not _is_cjk():
			text += " "
		text += p
	_regular_desc.text = text


func _refresh_legendary_mode() -> void:
	var mode: int = _mod.legendary_mode
	for i in _mode_buttons.size():
		_apply_chip_style(_mode_buttons[i], i == mode, C_ACCENT_LEGENDARY)
	_refresh_mode_desc()

	var pool_visible = _is_legendary_pool_visible()
	_legendary_pool_box.visible = pool_visible
	_pool_counts[POOL_LEGENDARY].visible = pool_visible
	_pool_clear_btns[POOL_LEGENDARY].visible = pool_visible
	if not pool_visible and _active_pool == POOL_LEGENDARY:
		_active_pool = POOL_REGULAR
	_refresh_active_pool()


func _refresh_mode_desc() -> void:
	var mode: int = _mod.legendary_mode
	var text = tr(MODE_DESC_KEYS[mode])
	if mode == ModMain.LegendaryMode.ONCE:
		text = text % _mod.legendary_item_ids.size()
	_mode_desc.text = text


# 当前替换池：卡片高亮 + "点击添加到"提示 + 网格描边
func _refresh_active_pool() -> void:
	for pool in [POOL_REGULAR, POOL_LEGENDARY]:
		var active = pool == _active_pool
		_pool_cards[pool].add_stylebox_override("panel", _card_style(_pool_accent(pool) if active else C_BORDER, active))

	var accent = _pool_accent(_active_pool)
	_add_target_label.text = tr("MOJI_ADD_TO") % _pool_title(_active_pool)
	_add_target_label.add_color_override("font_color", accent)

	var ids = _get_pool(_active_pool)
	var marker_style = _style(Color(0, 0, 0, 0), accent, 6, 3, 0, 0)
	for entry in _avail_entries:
		var marker: Panel = entry["marker"]
		marker.visible = ids.has(entry["id"])
		marker.add_stylebox_override("panel", marker_style)


func _refresh_pool(pool: int) -> void:
	var row: HBoxContainer = _pool_rows[pool]
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()

	var ids = _get_pool(pool)
	_pool_counts[pool].text = tr("MOJI_SELECTED") % ids.size()
	if pool == POOL_LEGENDARY:
		_refresh_mode_desc()

	if ids.empty():
		var empty = _label(tr("MOJI_EMPTY_POOL"), FONT_SMALL, C_TEXT_DIM)
		empty.rect_min_size = Vector2(0, EL_SIZE)
		empty.valign = Label.VALIGN_CENTER
		row.add_child(empty)
		return

	for i in ids.size():
		var item_data = ItemService.get_element_safe(ItemService.items, ids[i])
		if item_data == null:
			continue
		var wrapper = _make_element(row, item_data, _mod.force_cursed, "_on_pool_item_pressed", [pool, ids[i]])
		var badge = _label(str(i + 1), FONT_BADGE, C_TEXT)
		var badge_style = _style(Color(0, 0, 0, 0.75), _pool_accent(pool), 4, 1, 4, 0)
		badge.add_stylebox_override("normal", badge_style)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.rect_position = Vector2(2, 2)
		wrapper.add_child(badge)


func _populate_available() -> void:
	var sorted = ItemService.items.duplicate()
	sorted.sort_custom(self, "_sort_by_tier_id")

	for item_data in sorted:
		var wrapper = _make_element(_avail_grid, item_data, false, "_on_available_pressed", [item_data.my_id])
		var marker = Panel.new()
		marker.rect_size = Vector2(EL_SIZE, EL_SIZE)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.visible = false
		wrapper.add_child(marker)
		_avail_entries.push_back({
			"id": item_data.my_id,
			"key": (tr(item_data.name) + " " + item_data.my_id).to_lower(),
			"wrapper": wrapper,
			"marker": marker,
		})


# 创建一个缩放后的 InventoryElement，包在固定尺寸的 wrapper 里，返回 wrapper
func _make_element(parent: Control, item_data, cursed: bool, method: String, binds: Array) -> Control:
	var wrapper = Control.new()
	wrapper.rect_min_size = Vector2(EL_SIZE, EL_SIZE)
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(wrapper)

	# 必须先 add_child 再 set_element：onready 变量入树 _ready 前为 null
	var el = INVENTORY_ELEMENT.instance()
	wrapper.add_child(el)
	el.add_stylebox_override("normal", _base_stylebox.duplicate())
	el.rect_scale = Vector2(EL_SCALE, EL_SCALE)
	el.focus_mode = Control.FOCUS_NONE
	# 诅咒预览：duplicate 一份并标记 is_cursed，不影响原物品
	if cursed:
		var d = item_data.duplicate()
		d.is_cursed = true
		el.set_element(d)
	else:
		el.set_element(item_data)
	el.connect("element_pressed", self, method, binds)
	return wrapper


func _fit_available_columns() -> void:
	# 构建过程中 ScrollContainer 先于网格触发 resized
	if _avail_grid == null:
		return
	# 预留滚动条宽度
	var width: float = _avail_scroll.rect_size.x - 16.0
	_avail_grid.columns = int(max(1, floor((width + EL_SEP) / (EL_SIZE + EL_SEP))))


# ============================================================
# 信号回调
# 注意：InventoryElement 发射 element_pressed 期间不能释放它，刷新一律 call_deferred。
# ============================================================
func _on_available_pressed(_element, item_id: String) -> void:
	var ids = _get_pool(_active_pool)
	if ids.has(item_id):
		ids.erase(item_id)
	else:
		ids.append(item_id)
	_mod._save_settings()
	call_deferred("_refresh_pool", _active_pool)
	call_deferred("_refresh_active_pool")


func _on_pool_item_pressed(_element, pool: int, item_id: String) -> void:
	_get_pool(pool).erase(item_id)
	_mod._save_settings()
	call_deferred("_refresh_pool", pool)
	call_deferred("_refresh_active_pool")


func _on_clear_pressed(pool: int) -> void:
	_get_pool(pool).clear()
	_mod._save_settings()
	_refresh_pool(pool)
	_refresh_active_pool()


func _on_mode_pressed(mode: int) -> void:
	_mod.legendary_mode = mode
	_mod._save_settings()
	# 切到带专用池的模式时，自动把"当前替换池"切到传奇箱子
	if _is_legendary_pool_visible():
		_active_pool = POOL_LEGENDARY
	_refresh_legendary_mode()


# 商店全部替换 / 商店总是有售 互斥
func _on_option_toggled(pressed: bool, path: String) -> void:
	_mod.set(path, pressed)
	if pressed:
		var other = ""
		if path == "cfg_replace_shop":
			other = "cfg_replace_shop_first"
		elif path == "cfg_replace_shop_first":
			other = "cfg_replace_shop"
		if other != "":
			_mod.set(other, false)
			_option_chips[other].pressed = false
	_mod._save_settings()
	_refresh_option_styles()


func _on_enable_toggled(pressed: bool) -> void:
	_mod.enabled = pressed
	_mod._save_settings()
	_refresh_enabled()


func _on_cursed_toggled(pressed: bool) -> void:
	_mod.force_cursed = pressed
	_mod._save_settings()
	_refresh_option_styles()
	_refresh_pool(POOL_REGULAR)
	_refresh_pool(POOL_LEGENDARY)


func _on_search_changed(text: String) -> void:
	var query = text.strip_edges().to_lower()
	for entry in _avail_entries:
		entry["wrapper"].visible = query == "" or entry["key"].find(query) != -1
	_avail_scroll.scroll_vertical = 0


func _on_close_pressed() -> void:
	if _mod != null:
		_mod._save_settings()
	queue_free()


# ============================================================
# 样式 / 控件工具
# ============================================================
func _style(bg: Color, border: Color, radius: int, border_w: int, margin_h: float, margin_v: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_top = border_w
	sb.border_width_bottom = border_w
	sb.border_width_left = border_w
	sb.border_width_right = border_w
	_set_radius(sb, radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


func _set_radius(sb: StyleBoxFlat, radius: int) -> void:
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius


func _card_style(border: Color, active: bool) -> StyleBoxFlat:
	var bg = C_BG_CARD.linear_interpolate(Color(border.r, border.g, border.b, C_BG_CARD.a), 0.08) if active else C_BG_CARD
	return _style(bg, border, 8, 2 if active else 1, 14, 10)


func _card(parent: Control) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	return card


# 开关类按钮：开启时强调色描边 + 暗色强调底，关闭时中性灰
func _apply_chip_style(btn: Button, on: bool, accent: Color) -> void:
	var bg = accent.darkened(0.62) if on else C_BG_CHIP
	var border = accent if on else C_BORDER
	var font_color = C_TEXT if on else C_TEXT_DIM
	var normal = _style(bg, border, 6, 2 if on else 1, 12, 4)
	var hover = _style(bg.lightened(0.08), border.lightened(0.15), 6, 2 if on else 1, 12, 4)
	var disabled = _style(Color(bg.r, bg.g, bg.b, 0.5), Color(border.r, border.g, border.b, 0.5), 6, 1, 12, 4)
	btn.add_stylebox_override("normal", normal)
	btn.add_stylebox_override("pressed", normal)
	btn.add_stylebox_override("hover", hover)
	btn.add_stylebox_override("disabled", disabled)
	btn.add_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_color_override("font_color", font_color)
	btn.add_color_override("font_color_pressed", font_color)
	btn.add_color_override("font_color_hover", C_TEXT)
	btn.add_color_override("font_color_hover_pressed", C_TEXT)
	btn.add_color_override("font_color_disabled", C_TEXT_DIM.darkened(0.4))


# 普通动作按钮（关闭 / 清空）：中性底 + 强调色悬停
func _apply_action_style(btn: Button, accent: Color) -> void:
	btn.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 12, 4))
	btn.add_stylebox_override("hover", _style(accent.darkened(0.6), accent, 6, 1, 12, 4))
	btn.add_stylebox_override("pressed", _style(accent.darkened(0.7), accent, 6, 1, 12, 4))
	btn.add_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_color_override("font_color", C_TEXT_DIM)
	btn.add_color_override("font_color_hover", C_TEXT)
	btn.add_color_override("font_color_pressed", C_TEXT)


# 开关（CheckButton，沿用游戏的开关图标，缩小到 56x28）
func _switch(text: String, on: bool) -> CheckButton:
	var sw = CheckButton.new()
	sw.text = text
	sw.pressed = on
	sw.focus_mode = Control.FOCUS_NONE
	sw.add_font_override("font", FONT_SMALL)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		sw.add_stylebox_override(state, StyleBoxEmpty.new())
	for icon_name in ["on", "off", "on_disabled", "off_disabled"]:
		var src_name = "on" if icon_name.begins_with("on") else "off"
		var icon = _small_switch_icon(sw.get_icon(src_name))
		if icon != null:
			sw.add_icon_override(icon_name, icon)
	sw.add_color_override("font_color", C_TEXT)
	sw.add_color_override("font_color_hover", C_TEXT)
	sw.add_color_override("font_color_pressed", C_TEXT)
	sw.add_color_override("font_color_hover_pressed", C_TEXT)
	sw.add_color_override("font_color_disabled", C_TEXT_DIM.darkened(0.3))
	return sw


func _small_switch_icon(src: Texture) -> Texture:
	if src == null:
		return null
	var key = src.get_rid().get_id()
	if _switch_icons.has(key):
		return _switch_icons[key]
	var img: Image = src.get_data()
	if img == null:
		return src
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(56, 28, Image.INTERPOLATE_BILINEAR)
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	_switch_icons[key] = tex
	return tex


func _button(text: String, font: Font) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_font_override("font", font)
	return btn


# base_theme 的默认字体是 40 号，所有 Label 都显式指定字体
func _label(text: String, font: Font, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_font_override("font", font)
	lbl.add_color_override("font_color", color)
	return lbl


func _capitalize_first(text: String) -> String:
	if text.empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1)


# 中日文句子之间不加空格
func _is_cjk() -> bool:
	var locale = TranslationServer.get_locale()
	return locale.begins_with("zh") or locale.begins_with("ja")


func _spacer() -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _sort_by_tier_id(a, b) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.my_id < b.my_id
