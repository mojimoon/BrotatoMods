extends Control

# BroEditor 编辑器弹窗。布局：
#   标题栏：标题 + 状态提示 + 导入 / 导出（剪贴板分享码）+ 关闭
#   左栏：角色列表（搜索、自定义角色 / 已修改角色标记、新建 / 删除自定义角色）
#   右栏：角色头（图标、名称、档案开关、重置）+ 页签：概览 / 初始属性 / 效果 / 初始装备 / 禁用
# 所有修改直接写入 mod 的档案字典；关闭时保存，并在设置有变时重新应用（选角界面重新载入）。
# 样式沿用 AutoAnthony / cave-modtools（base_theme + 圆角卡片 + 强调色 + 灰色说明文字）。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")
const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const GraphEffect = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
const BlueprintPage = preload("res://mods-unpacked/Mojimoon-BroEditor/ui/blueprint_page.gd")
const SearchSelect = preload("res://mods-unpacked/Mojimoon-BroEditor/ui/search_select.gd")
const FONT_TITLE = preload("res://resources/fonts/actual/base/font_32_outline.tres")
const FONT_NORMAL = preload("res://resources/fonts/actual/base/font_26.tres")
const FONT_SMALL = preload("res://resources/fonts/actual/base/font_22.tres")
const FONT_DESC = preload("res://resources/fonts/actual/base/font_very_smallest_text.tres")

const PANEL_SIZE = Vector2(1760, 1010)
const LEFT_WIDTH = 380
const CHAR_ICON = 62
const GRID_ICON = 64
const LIBRARY_LIMIT = 150

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
const C_CUSTOM = Color(0.78, 0.55, 1.0)

# 页签：[id, 名称 key, 颜色]
const TABS = [
	["overview", "BE_TAB_OVERVIEW", Color(1.0, 0.72, 0.30)],
	["stats", "BE_TAB_STATS", Color(0.55, 0.85, 0.55)],
	["effects", "BE_TAB_EFFECTS", Color(0.40, 0.72, 1.0)],
	["blueprint", "BE_TAB_BLUEPRINT", Color(1.0, 0.55, 0.35)],
	["gear", "BE_TAB_GEAR", Color(0.78, 0.55, 1.0)],
	["bans", "BE_TAB_BANS", Color(0.92, 0.38, 0.44)],
]

var initial_id := ""
# 打开中的可搜索下拉框（Esc 先关闭它）
var active_popup = null

var _mod = null
var _id := ""
var _tab := "overview"
var _start_sig := ""
var _delete_armed := false
var _switch_icons: Dictionary = {}
var _regex_bb := RegEx.new()

# 控件引用
var _status: Label
var _search: LineEdit
var _char_grid: GridContainer
var _head_icon: TextureRect
var _head_name: Label
var _head_info: Label
var _enable_switch: CheckButton
var _reset_btn: Button
var _delete_btn: Button
var _tab_buttons: Dictionary = {}
var _page: VBoxContainer
var _preview_text: RichTextLabel
# 效果页
var _effect_rows: Array = []
var _effect_list: VBoxContainer
var _expanded := -1
var _lib_cat := "all"
var _lib_search := ""
var _lib_list: VBoxContainer
var _lib_count: Label
var blueprint = null
# 禁用页
var _ban_filter := ""
var _ban_grids: Dictionary = {}
# 选择器
var _picker: Control = null
var _picker_mode := ""
var _picker_sel: Array = []
var _picker_res: Array = []
var _picker_grid: GridContainer
var _picker_filter := ""
var _picker_count: Label
var _picker_multi := true

var test_clipboard = null


func _ready() -> void:
	_mod = BEMain.get_mod()
	if _mod == null:
		queue_free()
		return
	_regex_bb.compile("\\[[^\\]]*\\]")
	_start_sig = JSON.print(_mod.profiles)
	_id = initial_id
	if _mod.find_character(_id) == null:
		var isvc = _isvc()
		_id = isvc.characters[0].my_id if not isvc.characters.empty() else ""
	_build_ui()
	_refresh_char_list()
	_select(_id)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if active_popup != null and is_instance_valid(active_popup):
			active_popup.close()
		elif _picker != null:
			_close_picker()
		elif blueprint != null and blueprint.close_picker():
			pass
		else:
			_on_close_pressed()
		get_tree().set_input_as_handled()


func _isvc():
	return get_node("/root/ItemService")


# 当前角色的档案（只读；没有档案时返回空档案）
func _view() -> Dictionary:
	return _mod.profiles[_id] if _mod.profiles.has(_id) else BEMain.new_profile()


# 当前角色的档案（编辑；没有时新建）
func _p() -> Dictionary:
	if not _mod.profiles.has(_id):
		_mod.profiles[_id] = BEMain.new_profile()
	return _mod.profiles[_id]


func _changed() -> void:
	_refresh_header()
	_refresh_preview()
	_refresh_char_marks()


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
	var vp = get_viewport_rect().size
	panel.rect_min_size = Vector2(min(PANEL_SIZE.x, vp.x - 20), min(PANEL_SIZE.y, vp.y - 20))
	panel.add_stylebox_override("panel", _style(C_BG_PANEL, C_BORDER, 12, 2, 18, 14))
	center.add_child(panel)
	var root = VBoxContainer.new()
	root.add_constant_override("separation", 10)
	panel.add_child(root)
	_build_header(root)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_constant_override("separation", 12)
	root.add_child(body)
	_build_left(body)
	_build_right(body)


func _build_header(root: Control) -> void:
	var header = HBoxContainer.new()
	header.add_constant_override("separation", 10)
	root.add_child(header)
	header.add_child(_label(tr("BE_TITLE"), FONT_TITLE, C_TEXT))
	_status = _label("", FONT_SMALL, C_TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.align = Label.ALIGN_RIGHT
	_status.clip_text = true
	header.add_child(_status)
	var import_btn = _button(tr("BE_IMPORT"), FONT_SMALL)
	_apply_action_style(import_btn, C_ACCENT_2)
	import_btn.connect("pressed", self, "_on_import_pressed")
	header.add_child(import_btn)
	var export_btn = _button(tr("BE_EXPORT"), FONT_SMALL)
	_apply_action_style(export_btn, C_ACCENT_2)
	export_btn.connect("pressed", self, "_on_export_pressed")
	header.add_child(export_btn)
	var close_btn = _button("X", FONT_NORMAL)
	close_btn.rect_min_size = Vector2(48, 44)
	_apply_action_style(close_btn, C_DANGER)
	close_btn.connect("pressed", self, "_on_close_pressed")
	header.add_child(close_btn)


func _build_left(body: Control) -> void:
	var card = _card(body)
	card.size_flags_horizontal = 0
	card.rect_min_size = Vector2(LEFT_WIDTH, 0)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	card.add_child(box)
	box.add_child(_label(tr("BE_CHARACTERS"), FONT_NORMAL, C_ACCENT))
	_search = _line_edit(tr("BE_SEARCH"))
	_search.connect("text_changed", self, "_on_char_search")
	box.add_child(_search)
	var scroll = _scroll()
	box.add_child(scroll)
	_char_grid = GridContainer.new()
	_char_grid.columns = 5
	_char_grid.add_constant_override("hseparation", 6)
	_char_grid.add_constant_override("vseparation", 6)
	scroll.add_child(_char_grid)
	box.add_child(_desc(tr("BE_CHARACTERS_DESC")))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	box.add_child(row)
	var new_btn = _button(tr("BE_NEW_CUSTOM"), FONT_SMALL)
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_action_style(new_btn, C_CUSTOM)
	new_btn.connect("pressed", self, "_on_new_custom")
	row.add_child(new_btn)
	_delete_btn = _button(tr("BE_DELETE"), FONT_SMALL)
	_apply_action_style(_delete_btn, C_DANGER)
	_delete_btn.connect("pressed", self, "_on_delete_custom")
	row.add_child(_delete_btn)


func _build_right(body: Control) -> void:
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_constant_override("separation", 10)
	body.add_child(right)
	# 角色头
	var head_card = _card(right)
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 14)
	head_card.add_child(head)
	_head_icon = TextureRect.new()
	_head_icon.expand = true
	_head_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_head_icon.rect_min_size = Vector2(72, 72)
	head.add_child(_head_icon)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGN_CENTER
	head.add_child(col)
	_head_name = _label("", FONT_NORMAL, C_TEXT)
	col.add_child(_head_name)
	_head_info = _label("", FONT_DESC, C_TEXT_DIM)
	col.add_child(_head_info)
	_enable_switch = _switch(tr("BE_PROFILE_ENABLED"), true)
	_enable_switch.connect("toggled", self, "_on_enable_toggled")
	head.add_child(_enable_switch)
	_reset_btn = _button(tr("BE_RESET"), FONT_SMALL)
	_reset_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_action_style(_reset_btn, C_DANGER)
	_reset_btn.connect("pressed", self, "_on_reset_pressed")
	head.add_child(_reset_btn)
	# 页签
	var tabs = HBoxContainer.new()
	tabs.add_constant_override("separation", 8)
	right.add_child(tabs)
	for d in TABS:
		var b = _button(tr(d[1]), FONT_SMALL)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.connect("pressed", self, "_on_tab_pressed", [d[0]])
		tabs.add_child(b)
		_tab_buttons[d[0]] = [b, d[2]]
	_page = VBoxContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_constant_override("separation", 10)
	right.add_child(_page)


# ============================================================
# 角色列表
# ============================================================
func _refresh_char_list() -> void:
	for c in _char_grid.get_children():
		_char_grid.remove_child(c)
		c.queue_free()
	var filter = _search.text.strip_edges().to_lower()
	var chars = []
	for c in _isvc().characters:
		if c == null:
			continue
		if filter != "" and tr(c.name).to_lower().find(filter) < 0 and c.my_id.find(filter) < 0:
			continue
		chars.push_back(c)
	# 自定义角色排在最前
	var customs = []
	var natives = []
	for c in chars:
		if _mod.is_custom(c.my_id):
			customs.push_back(c)
		else:
			natives.push_back(c)
	for c in customs + natives:
		var b = _icon_button(c.icon, CHAR_ICON)
		b.set_meta("id", c.my_id)
		b.connect("pressed", self, "_select", [c.my_id])
		_char_grid.add_child(b)
	_refresh_char_marks()


func _refresh_char_marks() -> void:
	for b in _char_grid.get_children():
		var id = b.get_meta("id")
		var color = C_BORDER
		var w = 1
		if _mod.is_custom(id):
			color = C_CUSTOM
			w = 2
		elif _mod.profiles.has(id) and _mod.profiles[id].enabled:
			color = C_ACCENT_3
			w = 2
		if id == _id:
			color = C_ACCENT
			w = 3
		_set_icon_style(b, color, w)


func _on_char_search(_t: String) -> void:
	_refresh_char_list()


func _select(id: String) -> void:
	if _mod.find_character(id) == null:
		return
	_id = id
	_expanded = -1
	_delete_armed = false
	_refresh_header()
	_refresh_char_marks()
	_build_page()


func _character():
	return _mod.find_character(_id)


func _refresh_header() -> void:
	var c = _character()
	if c == null:
		return
	var v = _view()
	var custom = _mod.is_custom(_id)
	_head_icon.texture = _custom_icon(v) if custom else c.icon
	var nm = v.name if v.name != "" else tr(_mod.orig_name(c))
	_head_name.text = nm
	_head_name.add_color_override("font_color", C_CUSTOM if custom else C_TEXT)
	var info = _id
	if custom:
		info += "  ·  " + tr("BE_CUSTOM_TAG")
		var base = _mod.find_character(v.base)
		if base != null:
			info += "  ·  " + tr("BE_BASE").replace("{0}", tr(_mod.orig_name(base)))
	elif _mod.profiles.has(_id):
		info += "  ·  " + tr("BE_MODIFIED_TAG" if v.enabled else "BE_DISABLED_TAG")
	else:
		info += "  ·  " + tr("BE_ORIGINAL_TAG")
	_head_info.text = info
	_enable_switch.visible = not custom
	_enable_switch.set_block_signals(true)
	_enable_switch.pressed = v.enabled
	_enable_switch.set_block_signals(false)
	_reset_btn.disabled = custom or not _mod.profiles.has(_id)
	_delete_btn.disabled = not custom
	_delete_btn.text = tr("BE_DELETE_CONFIRM" if _delete_armed else "BE_DELETE")
	for t in _tab_buttons:
		var tb = _tab_buttons[t]
		_apply_chip_style(tb[0], t == _tab, tb[1])


func _custom_icon(v: Dictionary) -> Texture:
	var c = _character()
	return c.icon if c != null else null


# ============================================================
# 页面
# ============================================================
func _on_tab_pressed(id: String) -> void:
	_tab = id
	_expanded = -1
	_refresh_header()
	_build_page()


func _build_page() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_preview_text = null
	_effect_list = null
	_lib_list = null
	_ban_grids = {}
	if blueprint != null:
		blueprint.close_picker()
	blueprint = null
	match _tab:
		"overview":
			_build_overview()
		"stats":
			_build_stats()
		"effects":
			_build_effects()
		"blueprint":
			blueprint = BlueprintPage.new()
			blueprint.build(self, _page)
		"gear":
			_build_gear()
		"bans":
			_build_bans()


# ---------------- 概览 ----------------
func _build_overview() -> void:
	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 12)
	_page.add_child(cols)
	var v = _view()
	var c = _character()
	var custom = _mod.is_custom(_id)

	var left_scroll = _scroll()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left_scroll)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_constant_override("separation", 10)
	left_scroll.add_child(left)

	var box = _section(left, "BE_SEC_BASIC", C_ACCENT)
	box.add_child(_label(tr("BE_NAME"), FONT_SMALL, C_TEXT))
	var name_edit = _line_edit(tr(_mod.orig_name(c)))
	name_edit.text = v.name
	name_edit.connect("text_changed", self, "_on_name_changed")
	box.add_child(name_edit)
	box.add_child(_desc(tr("BE_NAME_DESC")))
	box.add_child(_label(tr("BE_DESCRIPTION"), FONT_SMALL, C_TEXT))
	var desc_edit = TextEdit.new()
	desc_edit.rect_min_size = Vector2(0, 90)
	desc_edit.wrap_enabled = true
	desc_edit.add_font_override("font", FONT_SMALL)
	desc_edit.add_color_override("font_color", C_TEXT)
	desc_edit.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 10, 6))
	desc_edit.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT, 6, 1, 10, 6))
	desc_edit.text = v.desc
	desc_edit.connect("text_changed", self, "_on_desc_changed", [desc_edit])
	box.add_child(desc_edit)
	box.add_child(_desc(tr("BE_DESCRIPTION_DESC")))

	if custom:
		var cbox = _section(left, "BE_SEC_LOOK", C_CUSTOM)
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		cbox.add_child(row)
		var base_btn = _button(tr("BE_PICK_BASE"), FONT_SMALL)
		_apply_action_style(base_btn, C_CUSTOM)
		base_btn.connect("pressed", self, "_open_picker", ["base"])
		row.add_child(base_btn)
		var icon_btn = _button(tr("BE_PICK_ICON"), FONT_SMALL)
		_apply_action_style(icon_btn, C_CUSTOM)
		icon_btn.connect("pressed", self, "_open_picker", ["icon"])
		row.add_child(icon_btn)
		var import_btn = _button(tr("BE_IMPORT_ICON"), FONT_SMALL)
		_apply_action_style(import_btn, C_CUSTOM)
		import_btn.connect("pressed", self, "_on_import_icon")
		row.add_child(import_btn)
		cbox.add_child(_desc(tr("BE_LOOK_DESC")))

	var tbox = _section(left, "BE_SEC_TAGS", C_ACCENT_3)
	tbox.add_child(_desc(tr("BE_TAGS_DESC")))
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_constant_override("hseparation", 6)
	grid.add_constant_override("vseparation", 6)
	tbox.add_child(grid)
	var tags = v.wanted_tags if v.wanted_tags is Array else c.wanted_tags
	for tag in _all_tags():
		var b = _button(_tag_name(tag), FONT_DESC)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		_apply_chip_style(b, tag in tags, C_ACCENT_3)
		b.connect("pressed", self, "_on_tag_pressed", [tag])
		grid.add_child(b)

	var pcard = _card(cols)
	pcard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pbox = VBoxContainer.new()
	pbox.add_constant_override("separation", 8)
	pcard.add_child(pbox)
	pbox.add_child(_label(tr("BE_SEC_PREVIEW"), FONT_NORMAL, C_ACCENT_2))
	var pscroll = _scroll()
	pbox.add_child(pscroll)
	_preview_text = RichTextLabel.new()
	_preview_text.bbcode_enabled = true
	_preview_text.fit_content_height = true
	_preview_text.scroll_active = false
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_text.add_font_override("normal_font", FONT_SMALL)
	_preview_text.add_color_override("default_color", C_TEXT)
	pscroll.add_child(_preview_text)
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview_text == null or not is_instance_valid(_preview_text):
		return
	var v = _view()
	var lines = []
	for e in _mod.build_effects(_id, v):
		var t = _mod.effect_text(e)
		if t != "":
			lines.push_back(t)
	var text = PoolStringArray(lines).join("\n")
	var dim = "[color=#" + C_TEXT_DIM.to_html(false) + "]"
	var c = _character()
	var ws = _mod._weapons_by_ids(v.weapons) if v.weapons is Array else c.starting_weapons
	var names = []
	for w in ws:
		names.push_back(tr(w.name))
	text += "\n\n" + dim + tr("BE_PREVIEW_WEAPONS") + "[/color] " + PoolStringArray(names).join(" / ")
	var bans = v.ban_items.size() + v.ban_weapons.size()
	if bans > 0:
		text += "\n" + dim + tr("BE_PREVIEW_BANS").replace("{0}", str(v.ban_items.size())).replace("{1}", str(v.ban_weapons.size())) + "[/color]"
	if not _mod.is_custom(_id) and _mod.profiles.has(_id) and not v.enabled:
		text = dim + tr("BE_PREVIEW_DISABLED") + "[/color]\n\n" + text
	_preview_text.bbcode_text = text


func _all_tags() -> Array:
	var out = []
	for it in _isvc().items:
		for t in it.tags:
			if not t in out:
				out.push_back(t)
	for c in _isvc().characters:
		for t in c.wanted_tags:
			if not t in out:
				out.push_back(t)
	out.sort()
	return out


func _tag_name(tag: String) -> String:
	if tag.begins_with("stat_"):
		return tr(tag.to_upper())
	var k = "BE_K_" + tag.to_upper()
	var t = tr(k)
	return t if t != k else tag


func _on_name_changed(text: String) -> void:
	_p().name = text.strip_edges()
	_changed()


func _on_desc_changed(edit: TextEdit) -> void:
	_p().desc = BEMain.clean_desc(edit.text)
	_changed()


func _on_tag_pressed(tag: String) -> void:
	var p = _p()
	if not p.wanted_tags is Array:
		p.wanted_tags = _character().wanted_tags.duplicate()
	if tag in p.wanted_tags:
		p.wanted_tags.erase(tag)
	else:
		p.wanted_tags.push_back(tag)
	_changed()
	_build_page()


# ---------------- 初始属性 ----------------
var _valid_keys = null


func _is_valid_stat(key: String) -> bool:
	if _valid_keys == null:
		_valid_keys = {}
		var probe = load("res://singletons/player_run_data.gd").init_effects()
		for k in Catalog.stat_keys():
			var h = Keys.generate_hash(k)
			if probe.has(h) and typeof(probe[h]) in [TYPE_INT, TYPE_REAL]:
				_valid_keys[k] = true
	return _valid_keys.has(key)


func stat_name(key: String) -> String:
	return _mod.stat_name(key)


# 三列：开局状态；属性表（基础属性 | 属性获取修改 % | 次要属性，同一行对齐）；其余分组
func _build_stats() -> void:
	var head = HBoxContainer.new()
	_page.add_child(head)
	var d = _desc(tr("BE_STATS_DESC"))
	head.add_child(d)
	var clear = _button(tr("BE_STATS_CLEAR"), FONT_SMALL)
	_apply_action_style(clear, C_DANGER)
	clear.connect("pressed", self, "_on_stats_clear")
	head.add_child(clear)
	var scroll = _scroll()
	_page.add_child(scroll)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_constant_override("separation", 10)
	scroll.add_child(col)
	var v = _view()
	_build_start_state(col, v)

	var groups = {}
	for g in Catalog.STAT_GROUPS:
		groups[g[0]] = []
		for k in g[1]:
			if _is_valid_stat(k):
				groups[g[0]].push_back(k)
	# 基础属性（含诅咒）与其属性获取修改逐行对齐；多出的获取修改接在后面
	var primary = groups.BE_GRP_PRIMARY.duplicate()
	var caps = groups.BE_GRP_CAPS.duplicate()
	var secondary = groups.BE_GRP_SECONDARY.duplicate()
	if "stat_curse" in secondary:
		secondary.erase("stat_curse")
		primary.push_back("stat_curse")
	var gains = []
	var extra_gains = groups.BE_GRP_GAIN.duplicate()
	for k in primary:
		var gk = "gain_" + k
		gains.push_back(gk if gk in extra_gains else "")
		extra_gains.erase(gk)
	gains += extra_gains
	extra_gains = []
	for gk in extra_gains:
		primary.push_back("")
		gains.push_back(gk)
	# 第一列：基础属性之后是"属性上限"小标题与上限（与右边两列的剩余行并排）
	var first = []
	for k in primary:
		if k != "":
			first.push_back(k)
	first.push_back("#BE_GRP_CAPS")
	first += caps
	primary = first
	var box = _section(col, "BE_GRP_STATS", C_ACCENT_3)
	var table = _stat_grid(box)
	for t in ["BE_GRP_PRIMARY", "BE_GRP_GAIN", "BE_GRP_SECONDARY"]:
		table.add_child(_label(tr(t), FONT_SMALL, C_ACCENT_3))
	for r in max(primary.size(), secondary.size()):
		for k in [primary[r] if r < primary.size() else "", gains[r] if r < gains.size() else "", secondary[r] if r < secondary.size() else ""]:
			if k.begins_with("#"):
				table.add_child(_label(tr(k.substr(1)), FONT_SMALL, C_ACCENT_3))
			else:
				table.add_child(_stat_row(k, v) if k != "" else Control.new())
	for g in ["BE_GRP_SHOP", "BE_GRP_MAP", "BE_GRP_RULES"]:
		var gb = _section(col, g, C_ACCENT_3)
		var grid = _stat_grid(gb)
		for k in groups[g]:
			grid.add_child(_stat_row(k, v))


func _stat_grid(parent: Control) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 24)
	grid.add_constant_override("vseparation", 4)
	parent.add_child(grid)
	return grid


# 一行属性：图标 + 名称 + 数值
func _stat_row(key: String, v: Dictionary) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_constant_override("separation", 6)
	var icon = TextureRect.new()
	icon.texture = _stat_icon(key)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var lbl = _label(stat_name(key), FONT_DESC, C_TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)
	var sb = _spin(-9999, 9999, 1)
	sb.rect_min_size = Vector2(110, 0)
	sb.value = int(v.stats.get(key, 0))
	sb.connect("value_changed", self, "_on_stat_changed", [key, lbl])
	row.add_child(sb)
	_mark_stat_label(lbl, int(sb.value))
	return row


# 属性图标：原版属性图标；属性获取修改用对应属性的图标；其余按 cave-modtools 的对应表
var _icon_cache: Dictionary = {}


func _stat_icon(key: String) -> Texture:
	if _icon_cache.has(key):
		return _icon_cache[key]
	var base = key
	if key.begins_with("gain_") and key != "gain_pct_gold_start_wave":
		base = key.substr(5)
	var tex = null
	for path in Catalog.STAT_ICON_PATHS.get(base, []):
		if tex == null and ResourceLoader.exists(path):
			tex = load(path)
	for k in [base, Catalog.STAT_ICON_ALIASES.get(base, "")]:
		if k != "" and tex == null:
			tex = ItemService.get_stat_small_icon(Keys.generate_hash(k))
	_icon_cache[key] = tex
	return tex


# 开局状态（同 cave-modtools）：[字段, 名称 key, 最小, 最大]
const START_FIELDS = [
	["materials", "BE_START_MATERIALS", 0, 99999],
	["levels", "BE_START_LEVELS", 0, 300],
	["crates", "BE_START_CRATES", 0, 300],
	["legendary_crates", "BE_START_LEGENDARY_CRATES", 0, 300],
	["ban_tokens", "BE_START_BAN_TOKENS", 0, 300],
	["start_wave", "BE_START_WAVE", 1, 1000],
	["wave_delta", "BE_START_WAVE_DELTA", -120, 120],
	["wave_lock", "BE_START_WAVE_LOCK", 0, 600],
]


func _build_start_state(parent: Control, v: Dictionary) -> void:
	var box = _section(parent, "BE_GRP_START", C_ACCENT)
	var sub = GridContainer.new()
	sub.columns = 3
	sub.add_constant_override("hseparation", 24)
	sub.add_constant_override("vseparation", 4)
	box.add_child(sub)
	for f in START_FIELDS:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_constant_override("separation", 6)
		sub.add_child(row)
		var lbl = _label(tr(f[1]), FONT_DESC, C_TEXT)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)
		var sb = _spin(f[2], f[3], 1)
		sb.allow_greater = false
		sb.allow_lesser = false
		sb.rect_min_size = Vector2(120, 0)
		sb.value = int(BEMain.start_value(v, f[0]))
		sb.connect("value_changed", self, "_on_start_changed", [f[0]])
		row.add_child(sb)
	var settle = CheckBox.new()
	settle.text = tr("BE_START_LEVEL_SETTLE")
	settle.add_font_override("font", FONT_DESC)
	settle.pressed = bool(BEMain.start_value(v, "level_settle"))
	settle.connect("toggled", self, "_on_start_changed", ["level_settle"])
	box.add_child(settle)
	box.add_child(_desc(tr("BE_START_DESC")))


func _on_start_changed(value, key: String) -> void:
	var p = _p()
	var v = bool(value) if typeof(BEMain.START_DEFAULT[key]) == TYPE_BOOL else int(value)
	if v == BEMain.START_DEFAULT[key]:
		p.start.erase(key)
	else:
		p.start[key] = v
	_changed()


func _mark_stat_label(lbl: Label, value: int) -> void:
	lbl.add_color_override("font_color", C_ACCENT_3 if value > 0 else (C_DANGER if value < 0 else C_TEXT_DIM))


func _on_stat_changed(value: float, key: String, lbl: Label) -> void:
	var p = _p()
	if int(value) == 0:
		p.stats.erase(key)
	else:
		p.stats[key] = int(value)
	_mark_stat_label(lbl, int(value))
	_changed()


func _on_stats_clear() -> void:
	_p().stats = {}
	_changed()
	_build_page()


# ---------------- 效果 ----------------
func _specs() -> Array:
	return _mod.effect_specs(_id, _view())


# 编辑前把"原版效果"展开为 spec 列表
func _edit_specs() -> Array:
	var p = _p()
	if not p.effects is Array:
		p.effects = _mod.effect_specs(_id, p).duplicate(true)
	return p.effects


func _build_effects() -> void:
	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 12)
	_page.add_child(cols)

	# 左：角色效果列表
	var lcard = _card(cols)
	lcard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lbox = VBoxContainer.new()
	lbox.add_constant_override("separation", 8)
	lcard.add_child(lbox)
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	lbox.add_child(head)
	var title = _label(tr("BE_SEC_EFFECTS"), FONT_NORMAL, C_ACCENT_2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not _mod.is_custom(_id):
		var orig = _button(tr("BE_EFFECTS_ORIGINAL"), FONT_SMALL)
		_apply_action_style(orig, C_ACCENT)
		orig.connect("pressed", self, "_on_effects_original")
		head.add_child(orig)
	var clear = _button(tr("BE_EFFECTS_CLEAR"), FONT_SMALL)
	_apply_action_style(clear, C_DANGER)
	clear.connect("pressed", self, "_on_effects_clear")
	head.add_child(clear)
	lbox.add_child(_desc(tr("BE_EFFECTS_DESC")))
	var scroll = _scroll()
	lbox.add_child(scroll)
	_effect_list = VBoxContainer.new()
	_effect_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_list.add_constant_override("separation", 6)
	scroll.add_child(_effect_list)
	_fill_effect_list()

	# 右：添加效果（蓝图 + 效果库）
	var rcard = _card(cols)
	rcard.size_flags_horizontal = 0
	rcard.rect_min_size = Vector2(600, 0)
	rcard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rbox = VBoxContainer.new()
	rbox.add_constant_override("separation", 8)
	rcard.add_child(rbox)
	rbox.add_child(_label(tr("BE_SEC_LIBRARY"), FONT_NORMAL, C_ACCENT))
	rbox.add_child(_desc(tr("BE_LIBRARY_DESC")))
	var cats = GridContainer.new()
	cats.columns = 5
	cats.add_constant_override("hseparation", 6)
	cats.add_constant_override("vseparation", 6)
	rbox.add_child(cats)
	for c in Catalog.CATEGORIES:
		var b = _button(tr(c[1]), FONT_DESC)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_chip_style(b, c[0] == _lib_cat, C_ACCENT)
		b.connect("pressed", self, "_on_lib_cat", [c[0]])
		cats.add_child(b)
	var srow = HBoxContainer.new()
	srow.add_constant_override("separation", 8)
	rbox.add_child(srow)
	var search = _line_edit(tr("BE_LIBRARY_SEARCH"))
	search.text = _lib_search
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.connect("text_changed", self, "_on_lib_search")
	srow.add_child(search)
	_lib_count = _label("", FONT_DESC, C_TEXT_DIM)
	srow.add_child(_lib_count)
	var lscroll = _scroll()
	rbox.add_child(lscroll)
	_lib_list = VBoxContainer.new()
	_lib_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_list.add_constant_override("separation", 4)
	lscroll.add_child(_lib_list)
	_fill_library()


func _fill_effect_list() -> void:
	for c in _effect_list.get_children():
		_effect_list.remove_child(c)
		c.queue_free()
	_effect_rows = []
	var specs = _specs()
	if specs.empty():
		_effect_list.add_child(_desc(tr("BE_EFFECTS_EMPTY")))
	for i in specs.size():
		_effect_list.add_child(_effect_row(i, specs[i]))


func _effect_text(spec) -> String:
	var e = _mod.make_effect(spec) if spec is Dictionary else null
	if e == null:
		return "[color=#" + C_DANGER.to_html(false) + "]" + tr("BE_EFFECT_MISSING") + "[/color]"
	var t = _mod.effect_text(e)
	if t == "":
		t = "[color=#" + C_TEXT_DIM.to_html(false) + "]" + tr("BE_EFFECT_NO_TEXT").replace("{0}", str(e.key if e.key != "" else e.custom_key)) + "[/color]"
	return t


func _source_name(spec) -> String:
	var from = str(spec.get("from", "")) if spec is Dictionary else ""
	if from == "":
		return tr("BE_SRC_PLAIN")
	var r = _mod._find_any(from)
	if r == null:
		return from
	return tr(_mod.orig_name(r) if r is CharacterData else r.name)


func _effect_row(i: int, spec) -> Control:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_stylebox_override("panel", _style(C_BG_ITEM, C_ACCENT_2 if i == _expanded else C_BORDER, 6, 1, 10, 6))
	var col = VBoxContainer.new()
	col.add_constant_override("separation", 4)
	card.add_child(col)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	col.add_child(row)
	var txt = _rich(_effect_text(spec))
	row.add_child(txt)
	var src = _label(_source_name(spec), FONT_DESC, C_TEXT_DIM)
	src.rect_min_size = Vector2(120, 0)
	src.clip_text = true
	src.align = Label.ALIGN_RIGHT
	row.add_child(src)
	for a in [["▲", "_on_effect_move", -1], ["▼", "_on_effect_move", 1]]:
		var b = _button(a[0], FONT_DESC)
		_apply_action_style(b, C_ACCENT_2)
		b.connect("pressed", self, a[1], [i, a[2]])
		row.add_child(b)
	var e = _mod.make_effect(spec) if spec is Dictionary else null
	if e != null and Catalog.NATIVE_SPLIT.has(e.custom_key) and Catalog.is_plain_effect(e):
		var split = _button(tr("BE_SPLIT"), FONT_DESC)
		_apply_action_style(split, Color(1.0, 0.55, 0.35))
		split.connect("pressed", self, "_on_effect_split", [i])
		row.add_child(split)
	var edit = _button(tr("BE_EDIT"), FONT_DESC)
	_apply_chip_style(edit, i == _expanded, C_ACCENT_2)
	edit.connect("pressed", self, "_on_effect_edit", [i])
	row.add_child(edit)
	var del = _button("X", FONT_DESC)
	_apply_action_style(del, C_DANGER)
	del.connect("pressed", self, "_on_effect_delete", [i])
	row.add_child(del)
	_effect_rows.push_back(txt)
	if i == _expanded and spec is Dictionary:
		_build_effect_fields(col, i, spec)
	return card


# 展开的效果：扳机（属性型扳机效果可换扳机）+ 全部可编辑字段
func _build_effect_fields(col: Control, i: int, spec: Dictionary) -> void:
	var e = _mod.make_effect(spec)
	if e == null:
		return
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 4)
	col.add_child(grid)
	if Catalog.is_plain_effect(e) and Catalog.is_stat_key(e.key) and (e.custom_key == "" or e.custom_key in Catalog.trigger_keys()):
		grid.add_child(_label(tr("BE_FIELD_TRIGGER"), FONT_DESC, C_TEXT_DIM))
		var items = []
		for t in Catalog.TRIGGERS:
			if t[0] == "" or _mod.trigger_template(t[0]) != null:
				items.push_back([tr(t[1]), t[0]])
		var opt = _search_select(items, e.custom_key)
		opt.connect("selected", self, "_on_effect_trigger", [i])
		grid.add_child(opt)
	for f in Catalog.editable_fields(e):
		var name_key = "BE_FIELD_" + f.name.to_upper()
		var lbl_text = tr(name_key)
		if lbl_text == name_key:
			lbl_text = f.name
		var lbl = _label(lbl_text, FONT_DESC, C_TEXT_DIM)
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(lbl)
		var cur = e.get(f.name)
		match f.type:
			TYPE_INT, TYPE_REAL:
				var sb = _spin(-99999, 99999, 1 if f.type == TYPE_INT else 0.01)
				sb.value = cur
				sb.rect_min_size = Vector2(130, 0)
				sb.connect("value_changed", self, "_on_field_changed", [i, f.name])
				grid.add_child(sb)
			TYPE_BOOL:
				var cb = CheckBox.new()
				cb.pressed = cur
				cb.connect("toggled", self, "_on_field_changed", [i, f.name])
				grid.add_child(cb)
			TYPE_STRING:
				if Catalog.is_stat_key(str(cur)) or (f.name in ["key", "stat", "stat_scaled", "stat_displayed"] and str(cur).begins_with("stat_")):
					var opt = _stat_option(str(cur))
					opt.connect("selected", self, "_on_field_option", [i, f.name])
					grid.add_child(opt)
				else:
					var le = _line_edit("")
					le.text = str(cur)
					le.rect_min_size = Vector2(200, 0)
					le.connect("text_changed", self, "_on_field_changed", [i, f.name])
					grid.add_child(le)


func _on_effect_edit(i: int) -> void:
	_expanded = -1 if _expanded == i else i
	_fill_effect_list()


func _on_effect_move(i: int, d: int) -> void:
	var specs = _edit_specs()
	var j = i + d
	if j < 0 or j >= specs.size():
		return
	var t = specs[i]
	specs[i] = specs[j]
	specs[j] = t
	if _expanded == i:
		_expanded = j
	_fill_effect_list()
	_changed()


func _on_effect_delete(i: int) -> void:
	var specs = _edit_specs()
	if i < specs.size():
		specs.remove(i)
	_expanded = -1
	_fill_effect_list()
	_changed()


# 拆解：原版触发型效果 -> 蓝图里的一条路径（扳机 → 效果），并从效果列表移除
func _on_effect_split(i: int) -> void:
	var specs = _edit_specs()
	var e = _mod.make_effect(specs[i])
	var p = _p()
	if not p.graph is Dictionary:
		p.graph = GraphEffect.new_graph()
	var y = 0
	for n in p.graph.nodes:
		y = max(y, float(n.pos[1]) + 180)
	if GraphEffect.split_native(p.graph, e, Vector2(40, y)):
		specs.remove(i)
		_expanded = -1
		_fill_effect_list()
		_changed()
		_set_status(tr("BE_SPLIT_DONE"))


func _on_effects_original() -> void:
	_p().effects = null
	_expanded = -1
	_fill_effect_list()
	_changed()


func _on_effects_clear() -> void:
	_p().effects = []
	_expanded = -1
	_fill_effect_list()
	_changed()


func _set_field(i: int, field: String, value) -> void:
	var specs = _edit_specs()
	if i >= specs.size():
		return
	if not specs[i].has("set"):
		specs[i]["set"] = {}
	specs[i].set[field] = value
	if i < _effect_rows.size():
		_effect_rows[i].bbcode_text = _effect_text(specs[i])
	_changed()


func _on_field_changed(value, i: int, field: String) -> void:
	_set_field(i, field, value)


func _on_field_option(key, i: int, field: String) -> void:
	_set_field(i, field, key)


# 换扳机：换模板（text_key、额外参数随模板），保留属性与数值
func _on_effect_trigger(custom_key, i: int) -> void:
	var specs = _edit_specs()
	var e = _mod.make_effect(specs[i])
	if e == null:
		return
	specs[i] = _trigger_spec(custom_key, e.key, e.value)
	_fill_effect_list()
	_changed()


func _trigger_spec(custom_key: String, key: String, value: int) -> Dictionary:
	if custom_key == "":
		return {"set": {"key": key, "value": value, "text_key": _mod.stat_text_key(key)}}
	var t = _mod.trigger_template(custom_key)
	return {"from": t.from, "i": t.i, "set": {"key": key, "value": value}}


func _add_spec(spec: Dictionary) -> void:
	var specs = _edit_specs()
	specs.push_back(spec)
	_expanded = specs.size() - 1
	_fill_effect_list()
	_changed()
	_set_status(tr("BE_EFFECT_ADDED"))


func _on_lib_cat(cat: String) -> void:
	_lib_cat = cat
	_build_page()


func _on_lib_search(text: String) -> void:
	_lib_search = text.strip_edges().to_lower()
	_fill_library()


func _fill_library() -> void:
	for c in _lib_list.get_children():
		_lib_list.remove_child(c)
		c.queue_free()
	var shown = 0
	var total = 0
	for entry in _mod.library():
		if _lib_cat != "all" and entry.cat != _lib_cat:
			continue
		var text = _mod.effect_text(entry.effect)
		if text == "":
			continue
		if _lib_search != "":
			var plain = _strip(text).to_lower() + " " + tr(entry.src).to_lower() + " " + str(entry.effect.key) + " " + str(entry.effect.custom_key)
			if plain.find(_lib_search) < 0:
				continue
		total += 1
		if shown >= LIBRARY_LIMIT:
			continue
		shown += 1
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 6)
		_lib_list.add_child(row)
		var add = _button("+", FONT_SMALL)
		_apply_action_style(add, C_ACCENT_3)
		add.connect("pressed", self, "_add_spec", [{"from": entry.from, "i": entry.i}])
		row.add_child(add)
		row.add_child(_rich(text))
		var src = _label(tr(entry.src), FONT_DESC, C_TEXT_DIM)
		src.rect_min_size = Vector2(110, 0)
		src.clip_text = true
		src.align = Label.ALIGN_RIGHT
		row.add_child(src)
	_lib_count.text = tr("BE_LIBRARY_COUNT").replace("{0}", str(shown)).replace("{1}", str(total))


func _strip(bb: String) -> String:
	return _regex_bb.sub(bb, "", true)


# ---------------- 初始装备 ----------------
func _build_gear() -> void:
	var scroll = _scroll()
	_page.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_constant_override("separation", 10)
	scroll.add_child(box)
	var v = _view()
	var c = _character()

	var wbox = _section(box, "BE_SEC_START_WEAPONS", C_CUSTOM)
	wbox.add_child(_desc(tr("BE_START_WEAPONS_DESC")))
	var wrow = HBoxContainer.new()
	wrow.add_constant_override("separation", 8)
	wbox.add_child(wrow)
	var pick = _button(tr("BE_PICK_WEAPONS"), FONT_SMALL)
	_apply_action_style(pick, C_CUSTOM)
	pick.connect("pressed", self, "_open_picker", ["start_weapons"])
	wrow.add_child(pick)
	if not _mod.is_custom(_id):
		var orig = _button(tr("BE_RESTORE_ORIGINAL"), FONT_SMALL)
		_apply_action_style(orig, C_ACCENT)
		orig.connect("pressed", self, "_on_weapons_original")
		wrow.add_child(orig)
	# 全部 T1–T4：点击全部加入，再次点击全部移除
	var cur_ids = _start_weapon_ids()
	for t in 4:
		var tier_ids = _tier_weapon_ids(t)
		var all_in = not tier_ids.empty()
		for id in tier_ids:
			if not id in cur_ids:
				all_in = false
				break
		var tb = _button(tr("BE_ALL_TIER").replace("{0}", str(t + 1)), FONT_SMALL)
		_apply_chip_style(tb, all_in, ItemService.get_color_from_tier(t))
		tb.connect("pressed", self, "_on_tier_weapons", [t])
		wrow.add_child(tb)
	var ws = _mod._weapons_by_ids(v.weapons) if v.weapons is Array else c.starting_weapons
	var wgrid = _icon_grid(14)
	wbox.add_child(wgrid)
	for w in ws:
		var b = _res_button(w)
		_set_icon_style(b, ItemService.get_color_from_tier(w.tier), 2)
		wgrid.add_child(b)
	if ws.empty():
		wbox.add_child(_desc(tr("BE_START_WEAPONS_EMPTY")))

	var ibox = _section(box, "BE_SEC_START_ITEMS", C_ACCENT_3)
	ibox.add_child(_desc(tr("BE_START_ITEMS_DESC")))
	var irow = HBoxContainer.new()
	irow.add_constant_override("separation", 8)
	ibox.add_child(irow)
	for m in [["BE_ADD_ITEMS", "start_items"], ["BE_ADD_WEAPONS", "start_items_w"]]:
		var b = _button(tr(m[0]), FONT_SMALL)
		_apply_action_style(b, C_ACCENT_3)
		b.connect("pressed", self, "_open_picker", [m[1]])
		irow.add_child(b)
	var dlc = ProgressData.is_dlc_available_and_active("abyssal_terrors")
	for i in v.start_items.size():
		var s = v.start_items[i]
		var r = _mod._find_any(str(s.get("id", "")))
		if r == null:
			continue
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		ibox.add_child(row)
		var b = _res_button(r)
		_set_icon_style(b, ItemService.get_color_from_tier(r.tier), 2)
		row.add_child(b)
		var nm = _label(tr(r.name), FONT_SMALL, ItemService.get_color_from_tier(r.tier))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(_label(tr("BE_COUNT"), FONT_DESC, C_TEXT_DIM))
		var sb = _spin(1, 99, 1)
		sb.value = max(1, int(s.get("n", 1)))
		sb.connect("value_changed", self, "_on_start_item_count", [i])
		row.add_child(sb)
		if dlc:
			var cb = CheckBox.new()
			cb.text = tr("BE_CURSED")
			cb.add_font_override("font", FONT_DESC)
			cb.pressed = bool(s.get("cursed", false))
			cb.connect("toggled", self, "_on_start_item_cursed", [i])
			row.add_child(cb)
		var del = _button("X", FONT_DESC)
		_apply_action_style(del, C_DANGER)
		del.connect("pressed", self, "_on_start_item_delete", [i])
		row.add_child(del)


func _start_weapon_ids() -> Array:
	var v = _view()
	if v.weapons is Array:
		return v.weapons.duplicate()
	var out = []
	for w in _character().starting_weapons:
		out.push_back(w.my_id)
	return out


func _tier_weapon_ids(t: int) -> Array:
	var out = []
	for w in _isvc().weapons:
		if w.tier == t and not w.my_id in out:
			out.push_back(w.my_id)
	return out


func _on_tier_weapons(t: int) -> void:
	var ids = _start_weapon_ids()
	var tier_ids = _tier_weapon_ids(t)
	var all_in = true
	for id in tier_ids:
		if not id in ids:
			all_in = false
	for id in tier_ids:
		if all_in:
			ids.erase(id)
		elif not id in ids:
			ids.push_back(id)
	_p().weapons = ids
	_changed()
	_build_page()


# 导入图片（同 BroLab）：系统文件对话框选择 png / jpg
func _on_import_icon() -> void:
	var fd = FileDialog.new()
	fd.mode = FileDialog.MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PoolStringArray(["*.png ; PNG", "*.jpg, *.jpeg ; JPG", "*.webp ; WEBP"])
	fd.window_title = tr("BE_IMPORT_ICON")
	fd.connect("file_selected", self, "_on_icon_file_selected")
	fd.connect("popup_hide", fd, "queue_free")
	add_child(fd)
	fd.popup_centered(Vector2(1100, 720))


func _on_icon_file_selected(path: String) -> void:
	var v = _mod.import_icon(path, _id)
	if v == "":
		_set_status(tr("BE_IMPORT_ICON_FAILED"))
		return
	_p().icon = v
	_mod._register_custom(_id)
	_changed()
	_refresh_char_list()
	_build_page()
	_set_status(tr("BE_IMPORT_ICON_DONE"))


func _on_weapons_original() -> void:
	_p().weapons = null
	_changed()
	_build_page()


func _on_start_item_count(value: float, i: int) -> void:
	_p().start_items[i]["n"] = int(value)
	_changed()


func _on_start_item_cursed(pressed: bool, i: int) -> void:
	_p().start_items[i]["cursed"] = pressed
	_changed()


func _on_start_item_delete(i: int) -> void:
	_p().start_items.remove(i)
	_changed()
	_build_page()


# ---------------- 禁用 ----------------
func _build_bans() -> void:
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	_page.add_child(head)
	var d = _desc(tr("BE_BANS_DESC"))
	head.add_child(d)
	var search = _line_edit(tr("BE_SEARCH"))
	search.rect_min_size = Vector2(260, 0)
	search.text = _ban_filter
	search.connect("text_changed", self, "_on_ban_search")
	head.add_child(search)
	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 12)
	_page.add_child(cols)
	for kind in ["items", "weapons"]:
		var card = _card(cols)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box = VBoxContainer.new()
		box.add_constant_override("separation", 6)
		card.add_child(box)
		var row = HBoxContainer.new()
		box.add_child(row)
		var title = _label("", FONT_NORMAL, C_DANGER)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var clear = _button(tr("BE_BANS_CLEAR"), FONT_DESC)
		_apply_action_style(clear, C_DANGER)
		clear.connect("pressed", self, "_on_bans_clear", [kind])
		row.add_child(clear)
		var scroll = _scroll()
		box.add_child(scroll)
		var grid = _icon_grid(8)
		scroll.add_child(grid)
		_ban_grids[kind] = [grid, title]
	_fill_bans()


func _ban_list(kind: String) -> Array:
	return _view().ban_items if kind == "items" else _view().ban_weapons


func _ban_candidates(kind: String) -> Array:
	if kind == "items":
		return _isvc().items
	# 武器按系列（weapon_id）禁用，每个系列显示最低稀有度的那一把
	var by_family = {}
	for w in _isvc().weapons:
		if not by_family.has(w.weapon_id) or w.tier < by_family[w.weapon_id].tier:
			by_family[w.weapon_id] = w
	var out = by_family.values()
	out.sort_custom(self, "_sort_by_name")
	return out


func _sort_by_name(a, b) -> bool:
	return tr(a.name) < tr(b.name)


func _fill_bans() -> void:
	for kind in _ban_grids:
		var grid = _ban_grids[kind][0]
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()
		var banned = _ban_list(kind)
		for r in _ban_candidates(kind):
			if _ban_filter != "" and tr(r.name).to_lower().find(_ban_filter) < 0 and r.my_id.find(_ban_filter) < 0:
				continue
			var id = r.my_id if kind == "items" else r.weapon_id
			var b = _res_button(r)
			var on = id in banned
			_set_icon_style(b, C_DANGER if on else ItemService.get_color_from_tier(r.tier).darkened(0.4), 3 if on else 1)
			b.modulate = Color(1, 0.55, 0.55) if on else Color.white
			b.connect("pressed", self, "_on_ban_toggle", [kind, id])
			grid.add_child(b)
		_ban_grids[kind][1].text = tr("BE_BAN_ITEMS" if kind == "items" else "BE_BAN_WEAPONS").replace("{0}", str(banned.size()))


func _on_ban_search(text: String) -> void:
	_ban_filter = text.strip_edges().to_lower()
	_fill_bans()


func _on_ban_toggle(kind: String, id: String) -> void:
	var p = _p()
	var list: Array = p.ban_items if kind == "items" else p.ban_weapons
	if id in list:
		list.erase(id)
	else:
		list.push_back(id)
	_changed()
	_fill_bans()


func _on_bans_clear(kind: String) -> void:
	var p = _p()
	if kind == "items":
		p.ban_items = []
	else:
		p.ban_weapons = []
	_changed()
	_fill_bans()


# ============================================================
# 选择器（武器 / 道具 / 角色），点击切换，确认后写回
# ============================================================
func _open_picker(mode: String) -> void:
	_picker_mode = mode
	_picker_filter = ""
	_picker_multi = mode in ["start_weapons", "start_items", "start_items_w"]
	_picker_sel = []
	var v = _view()
	match mode:
		"start_weapons":
			_picker_res = _isvc().weapons.duplicate()
			if v.weapons is Array:
				_picker_sel = v.weapons.duplicate()
			else:
				for w in _character().starting_weapons:
					_picker_sel.push_back(w.my_id)
		"start_items":
			_picker_res = _isvc().items.duplicate()
		"start_items_w":
			_picker_res = _isvc().weapons.duplicate()
		"base":
			_picker_res = _native_characters()
			_picker_sel = [v.base]
		"icon":
			_picker_res = _native_characters() + _isvc().items
			_picker_sel = [v.icon]
	_picker_res.sort_custom(self, "_sort_by_tier_name")

	_picker = Control.new()
	_picker.set_anchors_preset(Control.PRESET_WIDE)
	add_child(_picker)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_WIDE)
	_picker.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_WIDE)
	_picker.add_child(center)
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(1240, 820)
	panel.add_stylebox_override("panel", _style(C_BG_PANEL, C_ACCENT_2, 12, 2, 18, 14))
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	panel.add_child(box)
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 10)
	box.add_child(head)
	var title = _label(tr("BE_PICKER_" + mode.to_upper()), FONT_NORMAL, C_ACCENT_2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_picker_count = _label("", FONT_SMALL, C_TEXT_DIM)
	head.add_child(_picker_count)
	var search = _line_edit(tr("BE_SEARCH"))
	search.connect("text_changed", self, "_on_picker_search")
	box.add_child(search)
	var scroll = _scroll()
	box.add_child(scroll)
	_picker_grid = _icon_grid(16)
	scroll.add_child(_picker_grid)
	var foot = HBoxContainer.new()
	foot.add_constant_override("separation", 10)
	box.add_child(foot)
	foot.add_child(_desc(tr("BE_PICKER_MULTI_DESC" if _picker_multi else "BE_PICKER_SINGLE_DESC")))
	if _picker_multi:
		var clear = _button(tr("BE_PICKER_CLEAR"), FONT_SMALL)
		_apply_action_style(clear, C_DANGER)
		clear.connect("pressed", self, "_on_picker_clear")
		foot.add_child(clear)
	var cancel = _button(tr("BE_CANCEL"), FONT_SMALL)
	_apply_action_style(cancel, C_TEXT_DIM)
	cancel.connect("pressed", self, "_close_picker")
	foot.add_child(cancel)
	var ok = _button(tr("BE_CONFIRM"), FONT_SMALL)
	_apply_action_style(ok, C_ACCENT_3)
	ok.connect("pressed", self, "_on_picker_confirm")
	foot.add_child(ok)
	_fill_picker()
	search.call_deferred("grab_focus")


func _native_characters() -> Array:
	var out = []
	for c in _isvc().characters:
		if not _mod.is_custom(c.my_id):
			out.push_back(c)
	return out


func _sort_by_tier_name(a, b) -> bool:
	if a.get_category() != b.get_category():
		return a.get_category() > b.get_category()
	if a.tier != b.tier:
		return a.tier < b.tier
	return tr(a.name) < tr(b.name)


func _fill_picker() -> void:
	for c in _picker_grid.get_children():
		_picker_grid.remove_child(c)
		c.queue_free()
	for r in _picker_res:
		if _picker_filter != "" and tr(r.name).to_lower().find(_picker_filter) < 0 and r.my_id.find(_picker_filter) < 0:
			continue
		var b = _res_button(r)
		var on = r.my_id in _picker_sel
		_set_icon_style(b, C_ACCENT_3 if on else ItemService.get_color_from_tier(r.tier).darkened(0.3), 3 if on else 1)
		b.connect("pressed", self, "_on_picker_toggle", [r.my_id])
		_picker_grid.add_child(b)
	_picker_count.text = tr("BE_PICKER_COUNT").replace("{0}", str(_picker_sel.size())) if _picker_multi else ""


func _on_picker_search(text: String) -> void:
	_picker_filter = text.strip_edges().to_lower()
	_fill_picker()


func _on_picker_toggle(id: String) -> void:
	if not _picker_multi:
		_picker_sel = [id]
		_on_picker_confirm()
		return
	if id in _picker_sel:
		_picker_sel.erase(id)
	else:
		_picker_sel.push_back(id)
	_fill_picker()


func _on_picker_clear() -> void:
	_picker_sel = []
	_fill_picker()


func _on_picker_confirm() -> void:
	var p = _p()
	match _picker_mode:
		"start_weapons":
			p.weapons = _picker_sel.duplicate()
		"start_items", "start_items_w":
			for id in _picker_sel:
				p.start_items.push_back({"id": id, "n": 1, "cursed": false})
		"base":
			if not _picker_sel.empty():
				p.base = _picker_sel[0]
		"icon":
			if not _picker_sel.empty():
				p.icon = _picker_sel[0]
	_close_picker()
	if _mod.is_custom(_id):
		_mod._register_custom(_id)
		_refresh_char_list()
	_changed()
	_build_page()


func _close_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


# ============================================================
# 顶部事件
# ============================================================
func _on_enable_toggled(pressed: bool) -> void:
	_p().enabled = pressed
	_changed()


func _on_reset_pressed() -> void:
	_mod.reset_profile(_id)
	_expanded = -1
	_changed()
	_build_page()
	_set_status(tr("BE_RESET_DONE"))


func _on_new_custom() -> void:
	var base = _id if not _mod.is_custom(_id) else _view().base
	var id = _mod.create_custom(base)
	_refresh_char_list()
	_select(id)
	_set_status(tr("BE_CUSTOM_CREATED"))


func _on_delete_custom() -> void:
	if not _mod.is_custom(_id):
		return
	if not _delete_armed:
		_delete_armed = true
		_refresh_header()
		return
	_delete_armed = false
	if _mod.delete_custom(_id):
		_set_status(tr("BE_CUSTOM_DELETED"))
		var isvc = _isvc()
		_refresh_char_list()
		_select(isvc.characters[0].my_id if not isvc.characters.empty() else "")
	else:
		_set_status(tr("BE_CUSTOM_IN_USE"))
		_refresh_header()


func _clipboard_get() -> String:
	return test_clipboard if test_clipboard != null else OS.clipboard


func _clipboard_set(text: String) -> void:
	if test_clipboard != null:
		test_clipboard = text
	else:
		OS.clipboard = text


func _on_export_pressed() -> void:
	if not _mod.profiles.has(_id):
		_set_status(tr("BE_EXPORT_NOTHING"))
		return
	_clipboard_set(_mod.export_code(_id))
	_set_status(tr("BE_EXPORTED"))


func _on_import_pressed() -> void:
	var id = _mod.import_code(_clipboard_get(), _id)
	if id == "":
		_set_status(tr("BE_IMPORT_FAILED"))
		return
	_refresh_char_list()
	_select(id)
	_set_status(tr("BE_IMPORTED"))


func _set_status(text: String) -> void:
	_status.text = text


func _on_close_pressed() -> void:
	if _mod != null:
		_mod.on_editor_closed(JSON.print(_mod.profiles) != _start_sig)
	queue_free()


# ============================================================
# 控件 / 样式工具（与 AutoAnthony 一致）
# ============================================================
func _style(bg: Color, border: Color, radius: int, border_w: int, margin_h: float, margin_v: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
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


func _section(parent: Control, title_key: String, accent: Color) -> VBoxContainer:
	var card = _card(parent)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(_label(tr(title_key), FONT_NORMAL, accent))
	return box


func _scroll() -> ScrollContainer:
	var s = ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.scroll_horizontal_enabled = false
	return s


func _icon_grid(columns: int) -> GridContainer:
	var g = GridContainer.new()
	g.columns = columns
	g.add_constant_override("hseparation", 6)
	g.add_constant_override("vseparation", 6)
	return g


func _desc(text: String) -> Label:
	var lbl = _label(text, FONT_DESC, C_TEXT_DIM)
	lbl.autowrap = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _rich(bb: String) -> RichTextLabel:
	var fx = RichTextLabel.new()
	fx.bbcode_enabled = true
	fx.fit_content_height = true
	fx.scroll_active = false
	fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx.add_font_override("normal_font", FONT_DESC)
	fx.add_color_override("default_color", C_TEXT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.bbcode_text = bb
	return fx


func _icon_button(tex: Texture, size: int) -> Button:
	var b = Button.new()
	b.rect_min_size = Vector2(size, size)
	b.icon = tex
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


# 道具 / 武器 / 角色图标按钮
func _res_button(r) -> Button:
	return _icon_button(r.icon, GRID_ICON)


func _set_icon_style(b: Button, color: Color, w: int) -> void:
	var normal = _style(C_BG_ITEM, color, 6, w, 4, 4)
	var hover = _style(C_BG_CHIP, color.lightened(0.25), 6, w, 4, 4)
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("pressed", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("focus", StyleBoxEmpty.new())


func _apply_chip_style(btn: Button, on: bool, accent: Color) -> void:
	var bg = accent.darkened(0.62) if on else C_BG_CHIP
	var border = accent if on else C_BORDER
	var font_color = C_TEXT if on else C_TEXT_DIM
	var normal = _style(bg, border, 6, 2 if on else 1, 12, 4)
	var hover = _style(bg.lightened(0.08), border.lightened(0.15), 6, 2 if on else 1, 12, 4)
	btn.add_stylebox_override("normal", normal)
	btn.add_stylebox_override("pressed", normal)
	btn.add_stylebox_override("hover", hover)
	btn.add_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_color_override("font_color", font_color)
	btn.add_color_override("font_color_pressed", font_color)
	btn.add_color_override("font_color_hover", C_TEXT)


func _apply_action_style(btn: Button, accent: Color) -> void:
	btn.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 12, 4))
	btn.add_stylebox_override("hover", _style(accent.darkened(0.6), accent, 6, 1, 12, 4))
	btn.add_stylebox_override("pressed", _style(accent.darkened(0.7), accent, 6, 1, 12, 4))
	btn.add_stylebox_override("disabled", _style(C_BG_ITEM, C_BG_CHIP, 6, 1, 12, 4))
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


func _line_edit(placeholder: String) -> LineEdit:
	var le = LineEdit.new()
	le.placeholder_text = placeholder
	le.add_font_override("font", FONT_SMALL)
	le.add_color_override("font_color", C_TEXT)
	le.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 10, 4))
	le.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT, 6, 1, 10, 4))
	return le


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var sb = SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.allow_greater = true
	sb.allow_lesser = true
	var le = sb.get_line_edit()
	le.add_font_override("font", FONT_SMALL)
	le.add_color_override("font_color", C_TEXT)
	le.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 8, 2))
	le.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT, 6, 1, 8, 2))
	return sb


# 可搜索下拉框：items = [[名称, 键]...]
func _search_select(items: Array, current = null) -> Button:
	var b = SearchSelect.new()
	b.setup(self, items, current)
	b.rect_min_size = Vector2(170, 0)
	return b


# 属性下拉框（current 不在列表中时追加）
func _stat_option(current: String) -> Button:
	var items = []
	var found = false
	for k in Catalog.stat_keys():
		if _is_valid_stat(k):
			items.push_back([stat_name(k), k])
			found = found or k == current
	if not found and current != "":
		items.push_back([stat_name(current), current])
	return _search_select(items, current)
