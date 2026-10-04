extends Control

# 东尼算法设置弹窗。布局（自上而下）：
#   标题栏：标题 + 种子（固定开关、输入框、随机）+ 总开关 + 关闭
#   页签：重组道具 / 重组武器 / 重组角色，每个页签右边是本页的总开关（武器、角色默认关闭）
#   重组道具页：效果设置、更多选项（初始道具 / 保留原名 / 强制重组 / 究极混沌）、数值设置 + 道具预览
#   重组武器页：重组方式（仅重组效果 / 深度重组）、更多选项、数值设置 + 武器预览
#   重组角色页：说明
# 每个选项下方用灰色小字说明实际效果。
# 样式沿用 OneItemToRuleThemAll / cave-modtools（base_theme + 圆角卡片 + 强调色开关 + 灰色说明文字）。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")
const FONT_TITLE = preload("res://resources/fonts/actual/base/font_32_outline.tres")
const FONT_NORMAL = preload("res://resources/fonts/actual/base/font_26.tres")
const FONT_SMALL = preload("res://resources/fonts/actual/base/font_22.tres")
const FONT_DESC = preload("res://resources/fonts/actual/base/font_very_smallest_text.tres")

const PANEL_SIZE = Vector2(1680, 1040)
const SECTION_WIDTH = 530
const PREVIEW_COLUMNS = 4

const C_TEXT = Color(0.94, 0.96, 1.0)
const C_TEXT_DIM = Color(0.62, 0.67, 0.76)
const C_BACKDROP = Color(0, 0, 0, 0.6)
const C_BG_PANEL = Color(0.06, 0.07, 0.10, 0.98)
const C_BG_CARD = Color(0.11, 0.13, 0.18, 0.95)
const C_BG_ITEM = Color(0.08, 0.09, 0.13, 0.95)
const C_BG_CHIP = Color(0.13, 0.16, 0.22, 0.95)
const C_BORDER = Color(0.28, 0.33, 0.42)
const C_ACCENT = Color(1.0, 0.72, 0.30)
const C_ACCENT_2 = Color(0.40, 0.72, 1.0)
const C_ACCENT_3 = Color(0.55, 0.85, 0.55)
const C_DANGER = Color(0.92, 0.38, 0.44)

# 页签：[页 id, 名称 key, 总开关配置字段, 颜色（绿 / 蓝 / 黄，与下方三栏标题的颜色对应）]
const PAGES = [
	["items", "AA_UI_ITEMS", "cfg_items", Color(0.55, 0.85, 0.55)],
	["weapons", "AA_UI_TAB_WEAPONS", "cfg_weapons", Color(0.40, 0.72, 1.0)],
	["characters", "AA_UI_TAB_CHARACTERS", "cfg_characters", Color(1.0, 0.72, 0.30)],
]
# [配置字段, 名称 key, 说明 key, 反向显示]
const EFFECT_SWITCHES = [
	["cfg_char_effects", "AA_UI_CHAR_EFFECTS", "AA_UI_CHAR_EFFECTS_DESC"],
	["cfg_all_char_effects", "AA_UI_ALL_CHAR_EFFECTS", "AA_UI_ALL_CHAR_EFFECTS_DESC"],
	["cfg_more_double", "AA_UI_MORE_DOUBLE", "AA_UI_MORE_DOUBLE_DESC"],
]
const MORE_SWITCHES = [
	["cfg_starting_items", "AA_UI_STARTING_ITEMS", "AA_UI_STARTING_ITEMS_DESC"],
	["cfg_rename", "AA_UI_KEEP_NAMES", "AA_UI_KEEP_NAMES_DESC", true],
	["cfg_force_items", "AA_UI_FORCE", "AA_UI_FORCE_DESC"],
	["cfg_tier_chaos", "AA_UI_TIER_CHAOS", "AA_UI_TIER_CHAOS_DESC"],
	["cfg_chaos", "AA_UI_CHAOS", "AA_UI_CHAOS_DESC"],
]
# 重组方式（二选一）：[模式, 名称 key, 说明 key]
const WEAPON_MODES = [
	["effects", "AA_UI_W_EFFECTS", "AA_UI_W_EFFECTS_DESC"],
	["deep", "AA_UI_W_DEEP", "AA_UI_W_DEEP_DESC"],
]
# 武器的效果设置：两种重组方式下方的开关
const WEAPON_EFFECT_SWITCHES = [
	["cfg_w_item_effects", "AA_UI_W_ITEM_EFFECTS", "AA_UI_W_ITEM_EFFECTS_DESC"],
]
const WEAPON_SWITCHES = [
	["cfg_w_rename", "AA_UI_KEEP_NAMES", "AA_UI_W_KEEP_NAMES_DESC", true],
	["cfg_w_low_tiers", "AA_UI_W_LOW_TIERS", "AA_UI_W_LOW_TIERS_DESC"],
	["cfg_w_any_start", "AA_UI_W_ANY_START", "AA_UI_W_ANY_START_DESC"],
]
# 互斥的开关：打开一个时关闭另一个
const EXCLUSIVE = {
	"cfg_chaos": "cfg_tier_chaos", "cfg_tier_chaos": "cfg_chaos"
}
# [配置字段, 名称 key, 最小, 最大, 步长, 说明 key]
const SLIDERS = [
	["cfg_avg", "AA_UI_AVG", 50, 250, 5, "AA_UI_AVG_DESC"],
	["cfg_variance", "AA_UI_VARIANCE", 50, 250, 5, "AA_UI_VARIANCE_DESC"],
	["cfg_triggers", "AA_UI_TRIGGERS", 50, 250, 5, "AA_UI_TRIGGERS_DESC"],
	["cfg_native_ratio", "AA_UI_NATIVE", 0, 100, 5, "AA_UI_NATIVE_DESC"],
]
const WEAPON_SLIDERS = [
	["cfg_w_avg", "AA_UI_AVG", 50, 250, 5, "AA_UI_W_AVG_DESC"],
	["cfg_w_variance", "AA_UI_VARIANCE", 50, 250, 5, "AA_UI_W_VARIANCE_DESC"],
	["cfg_w_effects", "AA_UI_W_FX", 50, 250, 5, "AA_UI_W_FX_DESC"],
]

var _mod = null
var _enable_switch: CheckButton
var _switches: Dictionary = {}
var _inverted: Dictionary = {}
var _mode_switches: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_labels: Dictionary = {}
var _seed_switch: CheckButton
var _seed_edit: LineEdit
var _switch_icons: Dictionary = {}
# 页签与分页：页 id -> 控件
var _page := "items"
var _tab_buttons: Dictionary = {}
var _page_switches: Dictionary = {}
var _pages: Dictionary = {}
# 预览（道具 / 武器各一份，点击时只生成当前页）：页 id -> {tier, buttons, grid, scroll, hint, plan}
var _pv: Dictionary = {}


func _ready() -> void:
	_mod = AAMain.get_mod()
	if _mod == null:
		queue_free()
		return
	_build_ui()
	_refresh_all()
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_tree().set_input_as_handled()


# ============================================================
# 构建
# ============================================================
func _build_ui() -> void:
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
	_build_tabs(root)

	var items = _new_page(root, "items")
	var cols = _columns(items)
	_build_switch_section(cols, "AA_UI_SEC_EFFECTS", EFFECT_SWITCHES, C_ACCENT_3)
	_build_switch_section(cols, "AA_UI_SEC_MORE", MORE_SWITCHES, C_ACCENT_2)
	_build_slider_section(cols, SLIDERS)
	_build_preview(items, "items", "AA_UI_SEC_PREVIEW", "AA_UI_PREVIEW", "AA_UI_PREVIEW_HINT")

	var weapons = _new_page(root, "weapons")
	cols = _columns(weapons)
	_build_mode_section(cols)
	_build_switch_section(cols, "AA_UI_SEC_MORE", WEAPON_SWITCHES, C_ACCENT_2)
	_build_slider_section(cols, WEAPON_SLIDERS)
	_build_preview(weapons, "weapons", "AA_UI_SEC_PREVIEW_WEAPONS", "AA_UI_PREVIEW_WEAPONS", "AA_UI_PREVIEW_WEAPONS_HINT")

	var chars = _new_page(root, "characters")
	var box = _section(_columns(chars), "AA_UI_CHARACTERS", C_ACCENT_2)
	box.add_child(_desc(tr("AA_UI_CHARACTERS_DESC")))


# 标题 种子 [固定] [输入框] [随机]  启用 [开关] [X]
func _build_header(root: Control) -> void:
	var header = HBoxContainer.new()
	header.add_constant_override("separation", 10)
	root.add_child(header)
	var title = _label(tr("AA_TITLE"), FONT_TITLE, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var seed_lbl = _label(tr("AA_UI_SEED"), FONT_SMALL, C_TEXT)
	seed_lbl.hint_tooltip = tr("AA_UI_SEED_DESC")
	seed_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(seed_lbl)
	_seed_switch = _switch("", _mod.cfg_fixed_seed)
	_seed_switch.hint_tooltip = tr("AA_UI_SEED_DESC")
	_seed_switch.connect("toggled", self, "_on_fixed_seed_toggled")
	header.add_child(_seed_switch)
	_seed_edit = LineEdit.new()
	_seed_edit.rect_min_size = Vector2(190, 38)
	_seed_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_seed_edit.add_font_override("font", FONT_SMALL)
	_seed_edit.add_color_override("font_color", C_TEXT)
	_seed_edit.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 10, 4))
	_seed_edit.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT, 6, 1, 10, 4))
	_seed_edit.text = str(_mod.cfg_seed)
	_seed_edit.connect("text_changed", self, "_on_seed_changed")
	header.add_child(_seed_edit)
	var rnd = _button(tr("AA_UI_RANDOM"), FONT_SMALL)
	rnd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_action_style(rnd, C_ACCENT_2)
	rnd.connect("pressed", self, "_on_random_seed_pressed")
	header.add_child(rnd)
	var gap = Control.new()
	gap.rect_min_size = Vector2(40, 0)
	header.add_child(gap)
	_enable_switch = _switch(tr("AA_UI_ENABLE"), _mod.enabled)
	_enable_switch.connect("toggled", self, "_on_enable_toggled")
	header.add_child(_enable_switch)
	var close_btn = _button("X", FONT_NORMAL)
	close_btn.rect_min_size = Vector2(48, 44)
	_apply_action_style(close_btn, C_DANGER)
	close_btn.connect("pressed", self, "_on_close_pressed")
	header.add_child(close_btn)


# | 重组道具 [开关] | 重组武器 [开关] | 重组角色 [开关] |：整个页签可点击，选中时用本页颜色
func _build_tabs(root: Control) -> void:
	var tabs = HBoxContainer.new()
	tabs.add_constant_override("separation", 10)
	root.add_child(tabs)
	for d in PAGES:
		var tab = PanelContainer.new()
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab.connect("gui_input", self, "_on_tab_input", [d[0]])
		tabs.add_child(tab)
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(row)
		var lbl = _label(tr(d[1]), FONT_NORMAL, C_TEXT_DIM)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.align = Label.ALIGN_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		_tab_buttons[d[0]] = [tab, lbl, d[3]]
		var sw = _switch("", _mod.get(d[2]))
		sw.connect("toggled", self, "_on_switch_toggled", [d[2]])
		row.add_child(sw)
		_page_switches[d[0]] = sw


func _new_page(root: Control, id: String) -> VBoxContainer:
	var page = VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_constant_override("separation", 12)
	root.add_child(page)
	_pages[id] = page
	return page


func _columns(page: Control) -> HBoxContainer:
	var cols = HBoxContainer.new()
	cols.add_constant_override("separation", 12)
	page.add_child(cols)
	return cols


# 一张开关卡片：标题 + 每个开关下方一行灰色说明
func _build_switch_section(parent: Control, title_key: String, defs: Array, accent: Color) -> void:
	var box = _section(parent, title_key, accent)
	for d in defs:
		var inverted = d.size() > 3 and d[3]
		var sw = _switch(tr(d[1]), _mod.get(d[0]) != inverted)
		sw.connect("toggled", self, "_on_switch_toggled", [d[0]])
		box.add_child(sw)
		_switches[d[0]] = sw
		if inverted:
			_inverted[d[0]] = true
		box.add_child(_desc(tr(d[2])))


# 武器的效果设置：两种重组方式（互斥）+ 引入道具效果
func _build_mode_section(parent: Control) -> void:
	var box = _section(parent, "AA_UI_SEC_EFFECTS", C_ACCENT_3)
	for d in WEAPON_MODES:
		var sw = _switch(tr(d[1]), _mod.cfg_weapon_mode == d[0])
		sw.connect("toggled", self, "_on_mode_toggled", [d[0]])
		box.add_child(sw)
		_mode_switches[d[0]] = sw
		box.add_child(_desc(tr(d[2])))
	for d in WEAPON_EFFECT_SWITCHES:
		var sw = _switch(tr(d[1]), _mod.get(d[0]))
		sw.connect("toggled", self, "_on_switch_toggled", [d[0]])
		box.add_child(sw)
		_switches[d[0]] = sw
		box.add_child(_desc(tr(d[2])))


func _build_slider_section(parent: Control, defs: Array) -> void:
	var box = _section(parent, "AA_UI_SEC_VALUES", C_ACCENT)
	for d in defs:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		box.add_child(row)
		var lbl = _label(tr(d[1]), FONT_SMALL, C_TEXT)
		lbl.rect_min_size = Vector2(170, 0)
		row.add_child(lbl)
		var sl = HSlider.new()
		sl.min_value = d[2]
		sl.max_value = d[3]
		sl.step = d[4]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.rect_min_size = Vector2(0, 28)
		sl.focus_mode = Control.FOCUS_NONE
		_style_slider(sl)
		sl.value = _mod.get(d[0])
		sl.connect("value_changed", self, "_on_slider_changed", [d[0]])
		row.add_child(sl)
		var val = _label("", FONT_SMALL, C_ACCENT)
		val.rect_min_size = Vector2(70, 0)
		val.align = Label.ALIGN_RIGHT
		row.add_child(val)
		_sliders[d[0]] = sl
		_slider_labels[d[0]] = val
		box.add_child(_desc(tr(d[5])))


func _build_preview(parent: Control, kind: String, title_key: String, button_key: String, hint_key: String) -> void:
	var card = _card(parent)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	card.add_child(vbox)
	var pv = {"tier": 0, "buttons": [], "plan": null}
	_pv[kind] = pv

	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	vbox.add_child(head)
	head.add_child(_label(tr(title_key), FONT_NORMAL, C_TEXT))
	var group = ButtonGroup.new()
	for t in 4:
		var btn = _button("", FONT_SMALL)
		btn.toggle_mode = true
		btn.group = group
		btn.pressed = t == 0
		btn.connect("pressed", self, "_on_tier_pressed", [t, kind])
		head.add_child(btn)
		pv.buttons.push_back(btn)
	head.add_child(_spacer())
	# 导入 / 导出设置：分享码经由剪贴板
	var import_btn = _button(tr("AA_UI_IMPORT"), FONT_SMALL)
	_apply_action_style(import_btn, C_ACCENT_2)
	import_btn.connect("pressed", self, "_on_import_pressed")
	head.add_child(import_btn)
	var export_btn = _button(tr("AA_UI_EXPORT"), FONT_SMALL)
	_apply_action_style(export_btn, C_ACCENT_2)
	export_btn.connect("pressed", self, "_on_export_pressed")
	head.add_child(export_btn)
	var prev_btn = _button(tr(button_key), FONT_SMALL)
	_apply_action_style(prev_btn, C_ACCENT)
	prev_btn.connect("pressed", self, "_on_preview_pressed", [kind])
	head.add_child(prev_btn)

	pv.hint = _desc(tr(hint_key))
	vbox.add_child(pv.hint)

	pv.scroll = ScrollContainer.new()
	pv.scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.scroll.scroll_horizontal_enabled = false
	vbox.add_child(pv.scroll)
	pv.grid = GridContainer.new()
	pv.grid.columns = PREVIEW_COLUMNS
	pv.grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.grid.add_constant_override("hseparation", 10)
	pv.grid.add_constant_override("vseparation", 10)
	pv.scroll.add_child(pv.grid)
	_refresh_tier_buttons(kind)


func _style_slider(sl: HSlider) -> void:
	var track = _style(C_BG_CHIP, C_BORDER, 4, 1, 0, 3)
	var fill = _style(C_ACCENT.darkened(0.3), C_ACCENT, 4, 1, 0, 3)
	sl.add_stylebox_override("slider", track)
	sl.add_stylebox_override("grabber_area", fill)
	sl.add_stylebox_override("grabber_area_highlight", fill)


# ============================================================
# 刷新
# ============================================================
func _refresh_all() -> void:
	for key in _switches:
		_switches[key].pressed = _mod.get(key) != _inverted.has(key)
	for mode in _mode_switches:
		_mode_switches[mode].pressed = _mod.cfg_weapon_mode == mode
	for key in _sliders:
		_slider_labels[key].text = str(int(_mod.get(key))) + "%"
	_seed_edit.editable = _mod.cfg_fixed_seed
	_seed_edit.modulate.a = 1.0 if _mod.cfg_fixed_seed else 0.5
	for d in PAGES:
		_page_switches[d[0]].pressed = _mod.get(d[2])
		_pages[d[0]].visible = d[0] == _page
		_pages[d[0]].modulate.a = 1.0 if _mod.enabled and _mod.get(d[2]) else 0.45
		var tb = _tab_buttons[d[0]]
		var on = d[0] == _page
		tb[0].add_stylebox_override("panel", _style(tb[2].darkened(0.62) if on else C_BG_CHIP, tb[2] if on else C_BORDER, 8, 2 if on else 1, 14, 4))
		tb[1].add_color_override("font_color", tb[2] if on else C_TEXT_DIM)


func _refresh_tier_buttons(kind: String) -> void:
	var pv = _pv[kind]
	for t in pv.buttons.size():
		var text = tr("AA_UI_TIER").replace("{0}", str(t + 1))
		if pv.plan != null:
			text += " (" + str(_preview_entries(pv.plan, t, kind).size()) + ")"
		pv.buttons[t].text = text
		_apply_chip_style(pv.buttons[t], t == pv.tier, ItemService.get_color_from_tier(t))


# ============================================================
# 事件
# ============================================================
func _on_enable_toggled(pressed: bool) -> void:
	_mod.enabled = pressed
	_refresh_all()


func _on_tab_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		_on_page_pressed(id)


func _on_page_pressed(id: String) -> void:
	_page = id
	_refresh_all()


func _on_switch_toggled(pressed: bool, key: String) -> void:
	_mod.set(key, pressed != _inverted.has(key))
	if pressed and EXCLUSIVE.has(key):
		_mod.set(EXCLUSIVE[key], false)
	_refresh_all()


func _on_mode_toggled(pressed: bool, mode: String) -> void:
	if pressed:
		_mod.cfg_weapon_mode = mode
	_refresh_all()


func _on_slider_changed(value: float, key: String) -> void:
	_mod.set(key, int(value))
	_slider_labels[key].text = str(int(value)) + "%"


func _on_fixed_seed_toggled(pressed: bool) -> void:
	_mod.cfg_fixed_seed = pressed
	_refresh_all()


func _on_seed_changed(text: String) -> void:
	if text.is_valid_integer():
		_mod.cfg_seed = int(text)


func _on_random_seed_pressed() -> void:
	_mod.cfg_seed = randi() % 999999999
	_seed_edit.text = str(_mod.cfg_seed)
	_mod.cfg_fixed_seed = true
	_seed_switch.pressed = true
	_refresh_all()


# 预览：只按当前设置生成本页的内容（道具池或武器）
func _on_preview_pressed(kind: String = "items") -> void:
	var pv = _pv[kind]
	pv.plan = _mod.preview_plan(_mod.cfg_seed, kind)
	pv.hint.text = tr("AA_UI_PREVIEW_SEED").replace("{0}", str(_mod.cfg_seed))
	_refresh_tier_buttons(kind)
	_fill_preview(kind)


# 剪贴板（测试时用 test_clipboard 代替系统剪贴板）
var test_clipboard = null


func _clipboard_get() -> String:
	return test_clipboard if test_clipboard != null else OS.clipboard


func _clipboard_set(text: String) -> void:
	if test_clipboard != null:
		test_clipboard = text
	else:
		OS.clipboard = text


func _set_hints(text: String) -> void:
	for kind in _pv:
		_pv[kind].hint.text = text


func _on_export_pressed() -> void:
	_clipboard_set(_mod.export_settings_code())
	_set_hints(tr("AA_UI_EXPORTED"))


func _on_import_pressed() -> void:
	if _mod.import_settings_code(_clipboard_get()):
		_seed_edit.text = str(_mod.cfg_seed)
		_seed_switch.pressed = _mod.cfg_fixed_seed
		_enable_switch.pressed = _mod.enabled
		for key in _sliders:
			_sliders[key].value = _mod.get(key)
		_refresh_all()
		_set_hints(tr("AA_UI_IMPORTED"))
	else:
		_set_hints(tr("AA_UI_IMPORT_FAILED"))


func _on_tier_pressed(t: int, kind: String = "items") -> void:
	_pv[kind].tier = t
	_refresh_tier_buttons(kind)
	_fill_preview(kind)


# ============================================================
# 预览：每件道具 / 武器一张卡片（图标 + 名称 + 价格 + 效果）
# ============================================================
func _fill_preview(kind: String) -> void:
	var pv = _pv[kind]
	for c in pv.grid.get_children():
		pv.grid.remove_child(c)
		c.queue_free()
	var plan = pv.plan
	if plan == null:
		return
	var w = (pv.scroll.rect_size.x - 30) / PREVIEW_COLUMNS
	if w < 200:
		w = (PANEL_SIZE.x - 110) / PREVIEW_COLUMNS
	for res in _preview_entries(plan, pv.tier, kind):
		if kind == "weapons":
			pv.grid.add_child(_weapon_card(res, plan.weapons[res.my_id], w))
		else:
			pv.grid.add_child(_item_card(res, plan.items[res.my_id], w))
	pv.scroll.scroll_vertical = 0


func _preview_entries(plan: Dictionary, tier: int, kind: String = "items") -> Array:
	var entries = []
	var source = ItemService.weapons + plan.get("low_weapons", []) if kind == "weapons" else ItemService.items
	var gen: Dictionary = plan.weapons if kind == "weapons" else plan.items
	for res in source:
		# 究极混沌：按生成结果中的新稀有度分页
		if gen.has(res.my_id) and (tier < 0 or int(gen[res.my_id].get("tier", res.tier)) == tier):
			entries.push_back(res)
	entries.sort_custom(self, "_sort_by_tier_id")
	return entries


func _item_name(item, p: Dictionary) -> String:
	var nm = tr(item.name)
	if _mod.cfg_rename:
		nm = tr("AA_NAME_FMT").replace("{0}", tr(p.adj)).replace("{1}", nm)
	return nm


# 重组道具的价格由本 mod 生成（不继承原版价格）
func _item_price(item, p: Dictionary) -> int:
	return int(p.price) if int(p.get("price", 0)) > 0 else int(item.value)


func _card_shell(icon_tex: Texture, color: Color, width: float) -> VBoxContainer:
	var card = PanelContainer.new()
	card.rect_min_size = Vector2(width, 0)
	card.add_stylebox_override("panel", _style(C_BG_ITEM, color.darkened(0.25), 8, 2, 10, 8))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	card.add_child(row)
	var icon = TextureRect.new()
	icon.texture = icon_tex
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(64, 64)
	icon.size_flags_vertical = 0
	row.add_child(icon)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_constant_override("separation", 2)
	row.add_child(col)
	return col


func _card_head(col: Control, name_text: String, color: Color, right_text: String) -> void:
	var head = HBoxContainer.new()
	col.add_child(head)
	var nm = _label(name_text, FONT_SMALL, color)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	head.add_child(nm)
	head.add_child(_label(right_text, FONT_DESC, C_TEXT_DIM))


func _card_text(col: Control, bbcode: String) -> void:
	var fx = RichTextLabel.new()
	fx.bbcode_enabled = true
	fx.fit_content_height = true
	fx.scroll_active = false
	fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx.add_font_override("normal_font", FONT_DESC)
	fx.add_color_override("default_color", C_TEXT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.bbcode_text = bbcode
	col.add_child(fx)


func _item_card(item, p: Dictionary, width: float) -> Control:
	var color = ItemService.get_color_from_tier(int(p.get("tier", item.tier)))
	var col = _card_shell(p.get("icon", item.icon), color, width)
	var price = str(_item_price(item, p))
	if p.get("unique", false):
		price = tr("AA_UI_UNIQUE") + "  " + price
	elif int(p.get("limit", 0)) > 1:
		price = tr("LIMITED").replace("{0}/", "").replace("{1}", str(p.limit)) + "  " + price
	_card_head(col, _item_name(item, p), color, price)
	var lines = []
	for e in p.effects:
		var line = e.get_text(0)
		if line != "":
			lines.push_back(line)
	_card_text(col, PoolStringArray(lines).join("\n"))
	return col.get_parent().get_parent()


# 武器卡片：按生成结果临时组装一份武器数据，用原版的属性 / 效果文本
func _weapon_card(weapon, p: Dictionary, width: float) -> Control:
	var color = ItemService.get_color_from_tier(int(p.get("tier", weapon.tier)))
	var col = _card_shell(weapon.icon, color, width)
	var nm = tr(weapon.name)
	if _mod.cfg_w_rename and p.has("adj"):
		nm = tr("AA_NAME_FMT").replace("{0}", tr(p.adj)).replace("{1}", nm)
	_card_head(col, nm, color, str(int(p.get("price", weapon.value))))
	_card_text(col, weapon_preview_text(weapon, p))
	return col.get_parent().get_parent()


func weapon_preview_text(weapon, p: Dictionary) -> String:
	var w = weapon.duplicate()
	w.effects = p.effects
	if p.has("stats"):
		w.stats = p.stats
	if p.has("sets"):
		w.sets = p.sets
	var names = []
	for set in w.sets:
		names.push_back(tr(set.name))
	var text = "[color=#" + C_TEXT_DIM.to_html(false) + "]" + PoolStringArray(names).join(" / ") + "[/color]\n" + w.get_weapon_stats_text(0)
	var fx = w.get_effects_text(0, false)
	if fx != "":
		text += "\n" + fx
	return text


# 纯文本预览（不修改任何游戏资源；测试与日志用）
func build_preview_text(p_seed: int) -> String:
	var plan = _mod.preview_plan(p_seed, "items")
	var text = ""
	for item in _preview_entries(plan, -1):
		var p = plan.items[item.my_id]
		var color = ItemService.get_color_from_tier(int(p.get("tier", item.tier))).to_html(false)
		text += "[color=#" + color + "]" + _item_name(item, p) + "[/color]  [color=#" + C_TEXT_DIM.to_html(false) + "]" + str(_item_price(item, p)) + "[/color]\n"
		for e in p.effects:
			var line = e.get_text(0)
			if line != "":
				text += "    " + line + "\n"
	return text


func _sort_by_tier_id(a, b) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.my_id < b.my_id


func _on_close_pressed() -> void:
	if _mod != null:
		_mod.save_settings()
		# 选择武器界面已提前生成、设置有变：重新生成并重新载入界面（列出的武器随设置变化，例如关闭"允许低级武器"）
		if _mod.on_settings_closed() and get_tree().current_scene is WeaponSelection:
			get_tree().call_deferred("reload_current_scene")
	queue_free()


# ============================================================
# 样式 / 控件工具（与 OneItemToRuleThemAll 一致）
# ============================================================
func _style(bg: Color, border: Color, radius: int, border_w: int, margin_h: float, margin_v: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_top = border_w
	sb.border_width_bottom = border_w
	sb.border_width_left = border_w
	sb.border_width_right = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


func _card(parent: Control) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_stylebox_override("panel", _style(C_BG_CARD, C_BORDER, 8, 1, 14, 10))
	parent.add_child(card)
	return card


# 设置卡片：强调色标题 + 内容列
func _section(parent: Control, title_key: String, accent: Color) -> VBoxContainer:
	var card = _card(parent)
	card.rect_min_size = Vector2(SECTION_WIDTH, 0)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(_label(tr(title_key), FONT_NORMAL, accent))
	return box


# 灰色说明文字（自动换行，不做悬浮提示）
func _desc(text: String) -> Label:
	var lbl = _label(text, FONT_DESC, C_TEXT_DIM)
	lbl.autowrap = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _apply_chip_style(btn: Button, on: bool, accent: Color) -> void:
	var bg = accent.darkened(0.62) if on else C_BG_CHIP
	var border = accent if on else C_BORDER
	var font_color = C_TEXT if on else C_TEXT_DIM
	var normal = _style(bg, border, 6, 2 if on else 1, 12, 4)
	var hover = _style(bg.lightened(0.08), border.lightened(0.15), 6, 2 if on else 1, 12, 4)
	btn.add_stylebox_override("normal", normal)
	btn.add_stylebox_override("pressed", normal)
	btn.add_stylebox_override("hover", hover)
	btn.add_stylebox_override("hover_pressed", hover)
	btn.add_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_color_override("font_color", font_color)
	btn.add_color_override("font_color_pressed", font_color)
	btn.add_color_override("font_color_hover", C_TEXT)
	btn.add_color_override("font_color_hover_pressed", C_TEXT)


func _apply_action_style(btn: Button, accent: Color) -> void:
	btn.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 12, 4))
	btn.add_stylebox_override("hover", _style(accent.darkened(0.6), accent, 6, 1, 12, 4))
	btn.add_stylebox_override("pressed", _style(accent.darkened(0.7), accent, 6, 1, 12, 4))
	btn.add_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_color_override("font_color", C_TEXT_DIM)
	btn.add_color_override("font_color_hover", C_TEXT)
	btn.add_color_override("font_color_pressed", C_TEXT)


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
	for c in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed"]:
		sw.add_color_override(c, C_TEXT)
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


func _label(text: String, font: Font, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_font_override("font", font)
	lbl.add_color_override("font_color", color)
	return lbl


func _spacer() -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
