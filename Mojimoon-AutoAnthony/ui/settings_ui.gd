extends Control

# 东尼算法设置弹窗。布局（自上而下）：
#   标题栏：标题 + 总开关 + 关闭
#   设置（三张卡片并排）：重组内容（道具 / 角色 / 武器 / 名称）、效果设置（更多角色效果 / 全部角色效果 / 更多双面效果）、
#     数值设置（平均数值、浮动范围、触发效果、保留原版道具、种子）；每个选项下方用灰色小字说明实际效果
#   道具预览：按当前设置与种子生成道具池，按稀有度分页，每件道具一张卡片（图标、名称、价格、效果）
# 样式沿用 OneItemToRuleThemAll / cave-modtools（base_theme + 圆角卡片 + 强调色开关 + 灰色说明文字）。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")
const FONT_TITLE = preload("res://resources/fonts/actual/base/font_32_outline.tres")
const FONT_NORMAL = preload("res://resources/fonts/actual/base/font_26.tres")
const FONT_SMALL = preload("res://resources/fonts/actual/base/font_22.tres")
const FONT_DESC = preload("res://resources/fonts/actual/base/font_very_smallest_text.tres")

const PANEL_SIZE = Vector2(1680, 1040)
const SECTION_WIDTH = 530
const PREVIEW_COLUMNS = 3

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

# [配置字段, 名称 key, 说明 key]
const CONTENT_SWITCHES = [
	["cfg_items", "AA_UI_ITEMS", "AA_UI_ITEMS_DESC"],
	["cfg_characters", "AA_UI_CHARACTERS", "AA_UI_CHARACTERS_DESC"],
	["cfg_weapons", "AA_UI_WEAPONS", "AA_UI_WEAPONS_DESC"],
	["cfg_rename", "AA_UI_RENAME", "AA_UI_RENAME_DESC"],
]
const EFFECT_SWITCHES = [
	["cfg_char_effects", "AA_UI_CHAR_EFFECTS", "AA_UI_CHAR_EFFECTS_DESC"],
	["cfg_all_char_effects", "AA_UI_ALL_CHAR_EFFECTS", "AA_UI_ALL_CHAR_EFFECTS_DESC"],
	["cfg_more_double", "AA_UI_MORE_DOUBLE", "AA_UI_MORE_DOUBLE_DESC"],
]
# [配置字段, 名称 key, 最小, 最大, 步长, 说明 key]
const SLIDERS = [
	["cfg_avg", "AA_UI_AVG", 50, 200, 5, "AA_UI_AVG_DESC"],
	["cfg_variance", "AA_UI_VARIANCE", 50, 200, 5, "AA_UI_VARIANCE_DESC"],
	["cfg_triggers", "AA_UI_TRIGGERS", 50, 200, 5, "AA_UI_TRIGGERS_DESC"],
	["cfg_native_ratio", "AA_UI_NATIVE", 0, 100, 5, "AA_UI_NATIVE_DESC"],
]

var _mod = null
var _enable_switch: CheckButton
var _switches: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_labels: Dictionary = {}
var _seed_switch: CheckButton
var _seed_edit: LineEdit
var _dimmable: Array = []
var _switch_icons: Dictionary = {}
# 预览
var _plan = null
var _preview_tier := 0
var _tier_buttons: Array = []
var _preview_grid: GridContainer
var _preview_scroll: ScrollContainer
var _preview_hint: Label


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

	var cols = HBoxContainer.new()
	cols.add_constant_override("separation", 12)
	root.add_child(cols)
	_build_switch_section(cols, "AA_UI_SEC_CONTENT", CONTENT_SWITCHES, C_ACCENT_2)
	_build_switch_section(cols, "AA_UI_SEC_EFFECTS", EFFECT_SWITCHES, C_ACCENT_3)
	_build_values_section(cols)

	_build_preview(root)


func _build_header(root: Control) -> void:
	var header = HBoxContainer.new()
	header.add_constant_override("separation", 16)
	root.add_child(header)
	var title = _label(tr("AA_TITLE"), FONT_TITLE, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_enable_switch = _switch(tr("AA_UI_ENABLE"), _mod.enabled)
	_enable_switch.connect("toggled", self, "_on_enable_toggled")
	header.add_child(_enable_switch)
	var close_btn = _button("X", FONT_NORMAL)
	close_btn.rect_min_size = Vector2(48, 44)
	_apply_action_style(close_btn, C_DANGER)
	close_btn.connect("pressed", self, "_on_close_pressed")
	header.add_child(close_btn)


# 一张开关卡片：标题 + 每个开关下方一行灰色说明
func _build_switch_section(parent: Control, title_key: String, defs: Array, accent: Color) -> void:
	var box = _section(parent, title_key, accent)
	for d in defs:
		var sw = _switch(tr(d[1]), _mod.get(d[0]))
		sw.connect("toggled", self, "_on_switch_toggled", [d[0]])
		box.add_child(sw)
		_switches[d[0]] = sw
		box.add_child(_desc(tr(d[2])))


func _build_values_section(parent: Control) -> void:
	var box = _section(parent, "AA_UI_SEC_VALUES", C_ACCENT)
	for d in SLIDERS:
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
	# 种子
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	box.add_child(row)
	_seed_switch = _switch(tr("AA_UI_FIXED_SEED"), _mod.cfg_fixed_seed)
	_seed_switch.connect("toggled", self, "_on_fixed_seed_toggled")
	row.add_child(_seed_switch)
	_seed_edit = LineEdit.new()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.rect_min_size = Vector2(0, 38)
	_seed_edit.add_font_override("font", FONT_SMALL)
	_seed_edit.add_color_override("font_color", C_TEXT)
	_seed_edit.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 10, 4))
	_seed_edit.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT, 6, 1, 10, 4))
	_seed_edit.text = str(_mod.cfg_seed)
	_seed_edit.connect("text_changed", self, "_on_seed_changed")
	row.add_child(_seed_edit)
	var rnd = _button(tr("AA_UI_RANDOM"), FONT_SMALL)
	_apply_action_style(rnd, C_ACCENT_2)
	rnd.connect("pressed", self, "_on_random_seed_pressed")
	row.add_child(rnd)
	box.add_child(_desc(tr("AA_UI_SEED_DESC")))


func _build_preview(root: Control) -> void:
	var card = _card(root)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dimmable.push_back(card)
	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	card.add_child(vbox)

	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	vbox.add_child(head)
	head.add_child(_label(tr("AA_UI_SEC_PREVIEW"), FONT_NORMAL, C_TEXT))
	var group = ButtonGroup.new()
	for t in 4:
		var btn = _button("", FONT_SMALL)
		btn.toggle_mode = true
		btn.group = group
		btn.pressed = t == _preview_tier
		btn.connect("pressed", self, "_on_tier_pressed", [t])
		head.add_child(btn)
		_tier_buttons.push_back(btn)
	head.add_child(_spacer())
	var prev_btn = _button(tr("AA_UI_PREVIEW"), FONT_SMALL)
	_apply_action_style(prev_btn, C_ACCENT)
	prev_btn.connect("pressed", self, "_on_preview_pressed")
	head.add_child(prev_btn)

	_preview_hint = _desc(tr("AA_UI_PREVIEW_HINT"))
	vbox.add_child(_preview_hint)

	_preview_scroll = ScrollContainer.new()
	_preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_scroll.scroll_horizontal_enabled = false
	vbox.add_child(_preview_scroll)
	_preview_grid = GridContainer.new()
	_preview_grid.columns = PREVIEW_COLUMNS
	_preview_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_grid.add_constant_override("hseparation", 10)
	_preview_grid.add_constant_override("vseparation", 10)
	_preview_scroll.add_child(_preview_grid)
	_refresh_tier_buttons()


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
		_switches[key].pressed = _mod.get(key)
	for key in _sliders:
		_slider_labels[key].text = str(int(_mod.get(key))) + "%"
	_seed_edit.editable = _mod.cfg_fixed_seed
	_seed_edit.modulate.a = 1.0 if _mod.cfg_fixed_seed else 0.5
	for c in _dimmable:
		c.modulate.a = 1.0 if _mod.enabled else 0.45


func _refresh_tier_buttons() -> void:
	for t in _tier_buttons.size():
		var text = tr("AA_UI_TIER").replace("{0}", str(t + 1))
		if _plan != null:
			text += " (" + str(_preview_entries(_plan, t).size()) + ")"
		_tier_buttons[t].text = text
		_apply_chip_style(_tier_buttons[t], t == _preview_tier, ItemService.get_color_from_tier(t))


# ============================================================
# 事件
# ============================================================
func _on_enable_toggled(pressed: bool) -> void:
	_mod.enabled = pressed
	_refresh_all()


func _on_switch_toggled(pressed: bool, key: String) -> void:
	_mod.set(key, pressed)
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


func _on_preview_pressed() -> void:
	_plan = _mod.preview_plan(_mod.cfg_seed)
	_preview_hint.text = tr("AA_UI_PREVIEW_SEED").replace("{0}", str(_mod.cfg_seed))
	_refresh_tier_buttons()
	_fill_preview()


func _on_tier_pressed(t: int) -> void:
	_preview_tier = t
	_refresh_tier_buttons()
	_fill_preview()


# ============================================================
# 预览：每件道具一张卡片（图标 + 名称 + 价格 + 效果）
# ============================================================
func _fill_preview() -> void:
	for c in _preview_grid.get_children():
		_preview_grid.remove_child(c)
		c.queue_free()
	if _plan == null:
		return
	var w = (_preview_scroll.rect_size.x - 30) / PREVIEW_COLUMNS
	if w < 200:
		w = (PANEL_SIZE.x - 110) / PREVIEW_COLUMNS
	for item in _preview_entries(_plan, _preview_tier):
		_preview_grid.add_child(_item_card(item, _plan.items[item.my_id], w))
	_preview_scroll.scroll_vertical = 0


func _preview_entries(plan: Dictionary, tier: int) -> Array:
	var entries = []
	for item in ItemService.items:
		if (tier < 0 or item.tier == tier) and plan.items.has(item.my_id):
			entries.push_back(item)
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


func _item_card(item, p: Dictionary, width: float) -> Control:
	var color = ItemService.get_color_from_tier(item.tier)
	var card = PanelContainer.new()
	card.rect_min_size = Vector2(width, 0)
	card.add_stylebox_override("panel", _style(C_BG_ITEM, color.darkened(0.25), 8, 2, 10, 8))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	card.add_child(row)
	var icon = TextureRect.new()
	icon.texture = item.icon
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(64, 64)
	icon.size_flags_vertical = 0
	row.add_child(icon)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_constant_override("separation", 2)
	row.add_child(col)
	var head = HBoxContainer.new()
	col.add_child(head)
	var nm = _label(_item_name(item, p), FONT_SMALL, color)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	head.add_child(nm)
	var price = str(_item_price(item, p))
	if p.get("unique", false):
		price = tr("AA_UI_UNIQUE") + "  " + price
	head.add_child(_label(price, FONT_DESC, C_TEXT_DIM))
	var fx = RichTextLabel.new()
	fx.bbcode_enabled = true
	fx.fit_content_height = true
	fx.scroll_active = false
	fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx.add_font_override("normal_font", FONT_DESC)
	fx.add_color_override("default_color", C_TEXT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines = []
	for e in p.effects:
		var line = e.get_text(0)
		if line != "":
			lines.push_back(line)
	fx.bbcode_text = PoolStringArray(lines).join("\n")
	col.add_child(fx)
	return card


# 纯文本预览（不修改任何游戏资源；测试与日志用）
func build_preview_text(p_seed: int) -> String:
	var plan = _mod.preview_plan(p_seed)
	var text = ""
	for item in _preview_entries(plan, -1):
		var p = plan.items[item.my_id]
		var color = ItemService.get_color_from_tier(item.tier).to_html(false)
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
	_dimmable.push_back(card)
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
