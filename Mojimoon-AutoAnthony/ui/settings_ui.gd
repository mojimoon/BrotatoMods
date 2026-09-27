extends Control

# 东尼算法设置弹窗。布局（自上而下）：
#   标题栏：标题 + 总开关 + 关闭
#   选项卡片（两列）：左列开关（重组道具 / 角色 / 武器、角色效果、重组名称），右列滑条（平均数值、浮动范围、触发效果、保留原版道具）
#   种子：固定种子开关 + 输入框 + 随机 + 预览
#   预览：按当前设置与种子生成道具池，按稀有度列出
# 样式沿用 OneItemToRuleThemAll / cave-modtools（base_theme + 圆角卡片 + 强调色开关）。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")
const FONT_TITLE = preload("res://resources/fonts/actual/base/font_32_outline.tres")
const FONT_NORMAL = preload("res://resources/fonts/actual/base/font_26.tres")
const FONT_SMALL = preload("res://resources/fonts/actual/base/font_22.tres")

const PANEL_SIZE = Vector2(1200, 900)

const C_TEXT = Color(0.94, 0.96, 1.0)
const C_TEXT_DIM = Color(0.62, 0.67, 0.76)
const C_BACKDROP = Color(0, 0, 0, 0.6)
const C_BG_PANEL = Color(0.06, 0.07, 0.10, 0.98)
const C_BG_CARD = Color(0.11, 0.13, 0.18, 0.95)
const C_BG_CHIP = Color(0.13, 0.16, 0.22, 0.95)
const C_BORDER = Color(0.28, 0.33, 0.42)
const C_ACCENT = Color(1.0, 0.72, 0.30)
const C_ACCENT_2 = Color(0.40, 0.72, 1.0)
const C_DANGER = Color(0.92, 0.38, 0.44)

# [配置字段, 翻译 key]
const SWITCHES = [
	["cfg_items", "AA_UI_ITEMS"],
	["cfg_characters", "AA_UI_CHARACTERS"],
	["cfg_weapons", "AA_UI_WEAPONS"],
	["cfg_char_effects", "AA_UI_CHAR_EFFECTS"],
	["cfg_rename", "AA_UI_RENAME"],
]
# [配置字段, 翻译 key, 最小, 最大, 步长]
const SLIDERS = [
	["cfg_avg", "AA_UI_AVG", 50, 200, 5],
	["cfg_variance", "AA_UI_VARIANCE", 50, 200, 5],
	["cfg_triggers", "AA_UI_TRIGGERS", 50, 200, 5],
	["cfg_native_ratio", "AA_UI_NATIVE", 0, 100, 5],
]

var _mod = null
var _enable_switch: CheckButton
var _switches: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_labels: Dictionary = {}
var _seed_switch: CheckButton
var _seed_edit: LineEdit
var _preview: RichTextLabel
var _dimmable: Array = []
var _switch_icons: Dictionary = {}


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

	# 标题栏
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

	# 选项：两列
	var card = _card(root)
	_dimmable.push_back(card)
	var cols = HBoxContainer.new()
	cols.add_constant_override("separation", 40)
	card.add_child(cols)

	var left = VBoxContainer.new()
	left.add_constant_override("separation", 6)
	left.rect_min_size = Vector2(360, 0)
	cols.add_child(left)
	for sw_def in SWITCHES:
		var sw = _switch(tr(sw_def[1]), _mod.get(sw_def[0]))
		sw.connect("toggled", self, "_on_switch_toggled", [sw_def[0]])
		left.add_child(sw)
		_switches[sw_def[0]] = sw

	var right = VBoxContainer.new()
	right.add_constant_override("separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	for sl_def in SLIDERS:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 12)
		right.add_child(row)
		var lbl = _label(tr(sl_def[1]), FONT_SMALL, C_TEXT)
		lbl.rect_min_size = Vector2(200, 0)
		row.add_child(lbl)
		var sl = HSlider.new()
		sl.min_value = sl_def[2]
		sl.max_value = sl_def[3]
		sl.step = sl_def[4]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.rect_min_size = Vector2(0, 32)
		sl.focus_mode = Control.FOCUS_NONE
		_style_slider(sl)
		sl.value = _mod.get(sl_def[0])
		sl.connect("value_changed", self, "_on_slider_changed", [sl_def[0]])
		row.add_child(sl)
		var val = _label("", FONT_SMALL, C_ACCENT)
		val.rect_min_size = Vector2(80, 0)
		val.align = Label.ALIGN_RIGHT
		row.add_child(val)
		_sliders[sl_def[0]] = sl
		_slider_labels[sl_def[0]] = val

	# 种子 + 预览
	card = _card(root)
	_dimmable.push_back(card)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	card.add_child(row)
	row.add_child(_label(tr("AA_UI_SEED"), FONT_NORMAL, C_TEXT))
	_seed_switch = _switch(tr("AA_UI_FIXED_SEED"), _mod.cfg_fixed_seed)
	_seed_switch.connect("toggled", self, "_on_fixed_seed_toggled")
	row.add_child(_seed_switch)
	_seed_edit = LineEdit.new()
	_seed_edit.rect_min_size = Vector2(260, 40)
	_seed_edit.add_font_override("font", FONT_SMALL)
	_seed_edit.text = str(_mod.cfg_seed)
	_seed_edit.connect("text_changed", self, "_on_seed_changed")
	row.add_child(_seed_edit)
	var rnd = _button(tr("AA_UI_RANDOM"), FONT_SMALL)
	_apply_action_style(rnd, C_ACCENT_2)
	rnd.connect("pressed", self, "_on_random_seed_pressed")
	row.add_child(rnd)
	row.add_child(_spacer())
	var prev_btn = _button(tr("AA_UI_PREVIEW"), FONT_SMALL)
	_apply_action_style(prev_btn, C_ACCENT)
	prev_btn.connect("pressed", self, "_on_preview_pressed")
	row.add_child(prev_btn)

	card = _card(root)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dimmable.push_back(card)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.scroll_active = true
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.rect_min_size = Vector2(0, 420)
	_preview.add_font_override("normal_font", FONT_SMALL)
	_preview.add_color_override("default_color", C_TEXT)
	card.add_child(_preview)


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
	_preview.bbcode_text = build_preview_text(_mod.cfg_seed)
	_preview.scroll_to_line(0)


# 生成预览文本（不修改任何游戏资源）
func build_preview_text(p_seed: int) -> String:
	var plan = _mod.preview_plan(p_seed)
	var entries = []
	for item in ItemService.items:
		if plan.items.has(item.my_id):
			entries.push_back(item)
	entries.sort_custom(self, "_sort_by_tier_id")
	var text = ""
	for item in entries:
		var p = plan.items[item.my_id]
		var color = ItemService.get_color_from_tier(item.tier).to_html(false)
		var nm = tr(item.name)
		if _mod.cfg_rename:
			nm = tr("AA_NAME_FMT").replace("{0}", tr(p.adj)).replace("{1}", nm)
		text += "[color=#" + color + "]" + nm + "[/color]  [color=#" + C_TEXT_DIM.to_html(false) + "]" + str(item.value) + "[/color]\n"
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
