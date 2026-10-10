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
const DragRow = preload("res://mods-unpacked/Mojimoon-BroEditor/ui/drag_row.gd")
const Modal = preload("res://mods-unpacked/Mojimoon-BroEditor/ui/modal.gd")
const FONT_TITLE = preload("res://resources/fonts/actual/base/font_32_outline.tres")
const FONT_NORMAL = preload("res://resources/fonts/actual/base/font_26.tres")
const FONT_SMALL = preload("res://resources/fonts/actual/base/font_22.tres")
const FONT_DESC = preload("res://resources/fonts/actual/base/font_very_smallest_text.tres")

const PANEL_SIZE = Vector2(1760, 1010)
const LEFT_WIDTH = 380
const CHAR_ICON = 62
const GRID_ICON = 64
const LIBRARY_LIMIT = 150
# 预览栏（概览 / 武器属性页右侧）固定宽度；里面的图标格列数要能放下
const PREVIEW_WIDTH = 460
const PREVIEW_ICON_COLUMNS = 6

const C_TEXT = Color(0.94, 0.96, 1.0)
const C_TEXT_DIM = Color(0.62, 0.67, 0.76)
const C_BACKDROP = Color(0, 0, 0, 0.6)
const C_BG_PANEL = Color(0.06, 0.07, 0.10, 0.98)
const C_BG_CARD = Color(0.11, 0.13, 0.18, 0.95)
const C_BG_ITEM = Color(0.08, 0.09, 0.13, 0.95)
const C_BG_CHIP = Color(0.13, 0.16, 0.22, 0.95)
const C_BORDER = Color(0.28, 0.33, 0.42)
const C_ACCENT = Color(1.0, 0.72, 0.30) #FFB84D
const C_ACCENT_2 = Color(0.40, 0.72, 1.0) #66B8FF
const C_ACCENT_3 = Color(0.55, 0.85, 0.55) #8CD98C
const C_DANGER = Color(0.92, 0.38, 0.44) #E95C70
const C_CUSTOM = Color(0.78, 0.55, 1.0) #C8B0FF
const C_CUSTOM_2 = Color(1.0, 0.55, 0.35) #FF8C59

# 页签：[id, 名称 key, 颜色]
const TABS = [
	["overview", "BE_TAB_OVERVIEW", C_ACCENT],
	["effects", "BE_TAB_EFFECTS", C_CUSTOM],
	["stats", "BE_TAB_STATS", C_ACCENT_3],
	["blueprint", "BE_TAB_BLUEPRINT", C_ACCENT_2],
	["gear", "BE_TAB_GEAR", C_CUSTOM_2],
	["bans", "BE_TAB_BANS", C_DANGER],
]

# 三栏：[种类, 名称 key, 颜色]（同 AutoAnthony：整个页签可点，右侧是本栏总开关）
const KIND_TABS = [
	["character", "BE_KIND_CHARACTER", C_ACCENT],
	["item", "BE_KIND_ITEM", C_ACCENT_3],
	["weapon", "BE_KIND_WEAPON", C_ACCENT_2],
]
# 道具 / 武器的页签
const OBJECT_TABS = [
	["overview", "BE_TAB_OVERVIEW", C_ACCENT],
	["effects", "BE_TAB_EFFECTS", C_CUSTOM],
	["stats", "BE_TAB_STATS", C_ACCENT_3],
	["blueprint", "BE_TAB_BLUEPRINT", C_ACCENT_2],
]
const SOURCES = [["all", "BE_FILTER_ALL"], ["vanilla", "BE_SRC_VANILLA"], ["dlc1", "BE_SRC_DLC1"], ["mod", "BE_SRC_MOD"]]
const SORTS = [["tier", "BE_SORT_TIER"], ["name", "BE_SORT_NAME"], ["price", "BE_SORT_PRICE"]]

var initial_id := ""
# 打开中的可搜索下拉框（Esc 先关闭它）
var active_popup = null

var _mod = null
var _kind := "character"
var _id := ""
var _tab := "overview"
var _kind_ids: Dictionary = {}
var _kind_tabs: Dictionary = {}
var _filters := {
	"character": {"q": "", "src": "all"},
	"item": {"q": "", "src": "all", "tier": -1, "tag": "", "sort": "tier"},
	"weapon": {"q": "", "src": "all", "tier": -1, "tag": "", "sort": "tier"},
}
var _start_sig := ""
var _switch_icons: Dictionary = {}
var _regex_bb := RegEx.new()

# 控件引用
var _status: Label
var _search: LineEdit
var _char_grid: GridContainer
var _left_box: VBoxContainer
var _list_count: Label
var _tabs_row: HBoxContainer
var _head_icon: TextureRect
var _head_name: Label
var _head_info: Label
var _enable_switch: CheckButton
var _reset_btn: Button
var _disable_switch: CheckButton
var _tier_box: HBoxContainer
var _aspd_label: Label
# 当前页面里各属性名称的标签（按键名），数值改动时变色
var _name_labels: Dictionary = {}

# 武器属性页的排布：每行两项；"#type" = 近战 / 远战（只读），"#attack" = 横扫 / 突刺（仅近战）
const WSTAT_LAYOUT = [
	["damage", "cooldown"], ["recoil", "recoil_duration"],
	["additional_cooldown_every_x_shots", "additional_cooldown_multiplier"],
	["crit_chance", "crit_damage"], ["max_range", "min_range"], ["accuracy", "knockback"],
	["speed_percent_modifier", "effect_scale"], ["lifesteal", "#type"],
	["#attack"],
	["nb_projectiles"], ["piercing", "piercing_dmg_reduction"],
	["bounce", "bounce_dmg_reduction"], ["projectile_speed", "projectile_spread"],
]
# 界面显示方式：pct = 内部 0–1 显示为百分比
const WSTAT_SHOW = {
	"crit_chance": "pct", "accuracy": "pct", "lifesteal": "pct", "effect_scale": "pct",
	"piercing_dmg_reduction": "pct", "bounce_dmg_reduction": "pct",
}
var _delete_btn: Button
var _tab_buttons: Dictionary = {}
var _page: VBoxContainer
var _preview_text: VBoxContainer
# 效果页
var _effect_rows: Dictionary = {}
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
# 武器选择弹窗的筛选：稀有度（-1 = 全部）、近 / 远战（-1 = 全部）、来源
var _picker_f := {"tier": -1, "type": -1, "src": "all"}
var _picker_chips: Dictionary = {}
# 打开中的弹窗（Modal），Esc 关闭最上面的一个
var _modals: Array = []

var test_clipboard = null


func _ready() -> void:
	_mod = BEMain.get_mod()
	if _mod == null:
		queue_free()
		return
	_regex_bb.compile("\\[[^\\]]*\\]")
	_start_sig = _sig()
	_id = initial_id
	if _mod.find_character(_id) == null:
		var isvc = _isvc()
		_id = isvc.characters[0].my_id if not isvc.characters.empty() else ""
	_build_ui()
	_fill_left()
	_select(_id)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if active_popup != null and is_instance_valid(active_popup):
			active_popup.close()
		elif not _modals.empty():
			_modals[-1].close()
		else:
			_on_close_pressed()
		get_tree().set_input_as_handled()


func _isvc():
	return get_node("/root/ItemService")


func _sig() -> String:
	return JSON.print([_mod.profiles, _mod.item_profiles, _mod.weapon_profiles, _mod.kind_enabled, _mod.weapon_families, _mod.disabled])


func _profiles() -> Dictionary:
	return _mod.profiles_of(_kind)


# 当前对象的档案（只读；没有档案时返回空档案）
func _view() -> Dictionary:
	var ps = _profiles()
	return ps[_id] if ps.has(_id) else BEMain.new_profile()


# 当前对象的档案（编辑；没有时新建）
func _p() -> Dictionary:
	var ps = _profiles()
	if not ps.has(_id):
		ps[_id] = BEMain.new_profile()
	return ps[_id]


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
	_build_kind_tabs(root)
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
	var nums = _switch(tr("BE_HIDE_NUMBERS"), _mod.hide_numbers)
	nums.connect("toggled", self, "_on_hide_numbers_toggled")
	header.add_child(nums)
	var dbg = _switch(tr("BE_DEBUG"), _mod.debug)
	dbg.connect("toggled", self, "_on_debug_toggled")
	header.add_child(dbg)
	var import_btn = _button(tr("BE_IMPORT"), FONT_SMALL)
	_apply_action_style(import_btn, C_ACCENT_2)
	import_btn.connect("pressed", self, "_on_import_pressed")
	header.add_child(import_btn)
	# 导出：当前 / 本栏全部 / 三栏全部（右侧灰字是码的前缀）
	var export_btn = SearchSelect.new()
	export_btn.fixed_text = tr("BE_EXPORT")
	export_btn.setup(self, [
		[tr("BE_EXPORT_CURRENT"), BEMain.SHARE_PREFIX],
		[tr("BE_EXPORT_KIND_character"), BEMain.BUNDLE_PREFIX.character],
		[tr("BE_EXPORT_KIND_item"), BEMain.BUNDLE_PREFIX.item],
		[tr("BE_EXPORT_KIND_weapon"), BEMain.BUNDLE_PREFIX.weapon],
		[tr("BE_EXPORT_ALL"), BEMain.ALL_PREFIX],
	])
	export_btn.add_font_override("font", FONT_SMALL)
	export_btn.align = Button.ALIGN_CENTER
	export_btn.clip_text = false
	export_btn.connect("selected", self, "_on_export_selected")
	header.add_child(export_btn)
	var close_btn = _button("X", FONT_NORMAL)
	close_btn.rect_min_size = Vector2(48, 44)
	_apply_action_style(close_btn, C_DANGER)
	close_btn.connect("pressed", self, "_on_close_pressed")
	header.add_child(close_btn)


# | 角色 [开关] | 道具 [开关] | 武器 [开关] |：总开关关闭时该栏的全部修改都不生效
func _build_kind_tabs(root: Control) -> void:
	var tabs = HBoxContainer.new()
	tabs.add_constant_override("separation", 10)
	root.add_child(tabs)
	for d in KIND_TABS:
		var tab = PanelContainer.new()
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab.connect("gui_input", self, "_on_kind_input", [d[0]])
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
		var sw = _switch("", _mod.kind_enabled[d[0]])
		sw.connect("toggled", self, "_on_kind_switch", [d[0]])
		row.add_child(sw)
		_kind_tabs[d[0]] = [tab, lbl, d[2]]
	_refresh_kind_tabs()


func _refresh_kind_tabs() -> void:
	for k in _kind_tabs:
		var t = _kind_tabs[k]
		var on = k == _kind
		t[0].add_stylebox_override("panel", _style(t[2].darkened(0.65) if on else C_BG_CHIP, t[2] if on else C_BORDER, 8, 2 if on else 1, 14, 6))
		t[1].add_color_override("font_color", C_TEXT if on else C_TEXT_DIM)


func _on_kind_input(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		set_kind(kind)


func _on_kind_switch(pressed: bool, kind: String) -> void:
	_mod.kind_enabled[kind] = pressed
	_refresh_header()


func set_kind(kind: String) -> void:
	if kind == _kind:
		return
	_kind_ids[_kind] = _id
	_kind = kind
	_tab = _tab_defs()[0][0]
	_id = _kind_ids.get(kind, "")
	_fill_left()
	if _mod.find_target(_kind, _id) == null:
		_id = _first_listed()
	_rebuild_tabs()
	_refresh_kind_tabs()
	_select(_id)


func _tab_defs() -> Array:
	return TABS if _kind == "character" else OBJECT_TABS


func _build_left(body: Control) -> void:
	var card = _card(body)
	card.size_flags_horizontal = 0
	card.rect_min_size = Vector2(LEFT_WIDTH, 0)
	_left_box = VBoxContainer.new()
	_left_box.add_constant_override("separation", 8)
	card.add_child(_left_box)


# 左栏：角色 = 图标格 + 自定义角色按钮；道具 / 武器 = 搜索 + 来源 / 稀有度 / 标签筛选 + 排序
func _fill_left() -> void:
	for c in _left_box.get_children():
		_left_box.remove_child(c)
		c.queue_free()
	_delete_btn = null
	var box = _left_box
	var f = _filters[_kind]
	_search = _line_edit(tr("BE_SEARCH"))
	_search.text = f.q
	_search.connect("text_changed", self, "_on_char_search")
	if _kind == "character":
		box.add_child(_label(tr("BE_CHARACTERS"), FONT_NORMAL, C_ACCENT))
		box.add_child(_search)
		_filter_chips(box, "src", SOURCES)
	else:
		var head = HBoxContainer.new()
		box.add_child(head)
		var title = _label(tr("BE_KIND_" + _kind.to_upper()), FONT_NORMAL, _kind_tabs[_kind][2])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		_list_count = _label("", FONT_DESC, C_TEXT_DIM)
		head.add_child(_list_count)
		box.add_child(_search)
		_filter_chips(box, "src", SOURCES)
		var tiers = [[-1, "BE_FILTER_ALL"]]
		for t in 4:
			tiers.push_back([t, "T" + str(t + 1)])
		_filter_chips(box, "tier", tiers)
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 6)
		box.add_child(row)
		var tags = [[tr("BE_FILTER_ALL_TAGS"), ""]]
		for t in _list_tags():
			tags.push_back(t)
		var tag_sel = _search_select(tags, f.tag)
		tag_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag_sel.connect("selected", self, "_on_filter", ["tag"])
		row.add_child(tag_sel)
		var sorts = []
		for s in SORTS:
			sorts.push_back([tr(s[1]), s[0]])
		var sort_sel = _search_select(sorts, f.sort)
		sort_sel.rect_min_size = Vector2(140, 0)
		sort_sel.connect("selected", self, "_on_filter", ["sort"])
		row.add_child(sort_sel)
	var scroll = _scroll()
	box.add_child(scroll)
	_char_grid = GridContainer.new()
	_char_grid.columns = 5
	_char_grid.add_constant_override("hseparation", 6)
	_char_grid.add_constant_override("vseparation", 6)
	scroll.add_child(_char_grid)
	box.add_child(_desc(tr("BE_CHARACTERS_DESC")))
	if true:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 8)
		box.add_child(row)
		var new_btn = _button(tr("BE_NEW_CUSTOM" if _kind == "character" else "BE_NEW_CUSTOM_" + _kind.to_upper()), FONT_SMALL)
		new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_action_style(new_btn, C_CUSTOM)
		new_btn.connect("pressed", self, "_on_new_custom")
		row.add_child(new_btn)
		_delete_btn = _button(tr("BE_DELETE"), FONT_SMALL)
		_apply_action_style(_delete_btn, C_DANGER)
		_delete_btn.connect("pressed", self, "_on_delete_custom")
		row.add_child(_delete_btn)
	var reset_all = _button(tr("BE_RESET_KIND"), FONT_SMALL)
	_apply_action_style(reset_all, C_DANGER)
	reset_all.connect("pressed", self, "_on_reset_kind")
	box.add_child(reset_all)
	_refresh_char_list()


# 一行筛选按钮（等宽）
func _filter_chips(parent: Control, key: String, defs: Array) -> void:
	var row = GridContainer.new()
	row.columns = defs.size()
	row.add_constant_override("hseparation", 6)
	parent.add_child(row)
	for d in defs:
		var b = _button(tr(d[1]), FONT_DESC)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.rect_min_size = Vector2(40, 0)
		_apply_chip_style(b, _filters[_kind][key] == d[0], _kind_tabs[_kind][2])
		b.connect("pressed", self, "_on_filter", [d[0], key])
		row.add_child(b)


func _on_filter(value, key: String) -> void:
	_filters[_kind][key] = value
	_fill_left()


# 道具的词条 / 武器的类别（筛选用）：[[名称, 键]]
func _list_tags() -> Array:
	var seen = {}
	var out = []
	for r in _all_of_kind():
		for t in _tags_of(r):
			if not seen.has(t[1]):
				seen[t[1]] = true
				out.push_back(t)
	out.sort_custom(self, "_sort_by_first")
	return out


func _sort_by_first(a, b) -> bool:
	return a[0] < b[0]


func _tags_of(r) -> Array:
	var out = []
	if r is WeaponData:
		for s in r.sets:
			if s != null:
				out.push_back([tr(s.name), s.my_id])
	elif "tags" in r and r.tags is Array:
		for t in r.tags:
			out.push_back([_tag_name(t), t])
	return out


# 左栏对象：武器每个家族只列最低等级
func _all_of_kind() -> Array:
	var isvc = _isvc()
	var arr = isvc.characters if _kind == "character" else (isvc.items if _kind == "item" else isvc.weapons)
	var out = []
	var heads = {}
	for r in arr:
		if r == null:
			continue
		if _kind != "weapon":
			out.push_back(r)
		elif not heads.has(r.weapon_id) or r.tier < heads[r.weapon_id].tier:
			heads[r.weapon_id] = r
	for wid in heads:
		out.push_back(heads[wid])
	return out


func _first_listed() -> String:
	if _char_grid != null and _char_grid.get_child_count() > 0:
		return _char_grid.get_child(0).get_meta("id")
	var all = _all_of_kind()
	return all[0].my_id if not all.empty() else ""


func _matches(r, f: Dictionary) -> bool:
	var q = f.q.strip_edges().to_lower()
	if q != "" and tr(_mod.orig_name(r)).to_lower().find(q) < 0 and tr(r.name).to_lower().find(q) < 0 and r.my_id.find(q) < 0:
		return false
	if f.src != "all" and _source(r) != f.src:
		return false
	if _kind == "character":
		return true
	if f.tier >= 0:
		var found = false
		for m in (_mod.family_members(r.weapon_id) if _kind == "weapon" else [r]):
			found = found or int(_mod.backup_value(m, "tier")) == f.tier
		if not found:
			return false
	if f.tag != "":
		var found = false
		for t in _tags_of(r):
			found = found or t[1] == f.tag
		if not found:
			return false
	return true


func _sort_by_price(a, b) -> bool:
	var va = int(_mod.backup_value(a, "value"))
	var vb = int(_mod.backup_value(b, "value"))
	if va != vb:
		return va < vb
	return _sort_by_tier_then_name(a, b)


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
	_head_info.clip_text = true
	_head_name.clip_text = true
	col.add_child(_head_info)
	# 武器：同一家族的等级切换（右侧），可补等级
	_tier_box = HBoxContainer.new()
	_tier_box.add_constant_override("separation", 6)
	_tier_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_tier_box)
	_enable_switch = _switch(tr("BE_PROFILE_ENABLED"), true)
	_enable_switch.connect("toggled", self, "_on_enable_toggled")
	head.add_child(_enable_switch)
	_reset_btn = _button(tr("BE_RESET"), FONT_SMALL)
	_reset_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_action_style(_reset_btn, C_DANGER)
	_reset_btn.connect("pressed", self, "_on_reset_pressed")
	head.add_child(_reset_btn)
	_disable_switch = _switch(tr("BE_OBJ_DISABLE"), false)
	_disable_switch.connect("toggled", self, "_on_disable_toggled")
	head.add_child(_disable_switch)
	# 页签
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_constant_override("separation", 8)
	right.add_child(_tabs_row)
	_rebuild_tabs()
	_page = VBoxContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_constant_override("separation", 10)
	right.add_child(_page)


func _rebuild_tabs() -> void:
	for c in _tabs_row.get_children():
		_tabs_row.remove_child(c)
		c.queue_free()
	_tab_buttons = {}
	for d in _tab_defs():
		var b = _button(tr(d[1]), FONT_SMALL)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.connect("pressed", self, "_on_tab_pressed", [d[0]])
		_tabs_row.add_child(b)
		_tab_buttons[d[0]] = [b, d[2]]


# ============================================================
# 左栏列表（角色 / 道具 / 武器）
# ============================================================
func _refresh_char_list() -> void:
	for c in _char_grid.get_children():
		_char_grid.remove_child(c)
		c.queue_free()
	var f = _filters[_kind]
	var list = []
	for r in _all_of_kind():
		if _matches(r, f):
			list.push_back(r)
	if _kind == "character":
		# 自定义角色排在最前
		var customs = []
		var natives = []
		for c in list:
			if _mod.is_custom(c.my_id):
				customs.push_back(c)
			else:
				natives.push_back(c)
		list = customs + natives
	else:
		match f.sort:
			"name":
				list.sort_custom(self, "_sort_by_name")
			"price":
				list.sort_custom(self, "_sort_by_price")
			_:
				list.sort_custom(self, "_sort_by_tier_then_name")
		_list_count.text = str(list.size())
	for r in list:
		var b = _icon_button(r.icon, CHAR_ICON)
		b.set_meta("id", r.my_id)
		b.set_meta("key", _key_of(r))
		b.set_meta("tier", -1 if _kind == "character" else int(_mod.backup_value(r, "tier")))
		b.connect("pressed", self, "_select", [r.my_id])
		_char_grid.add_child(b)
	_refresh_char_marks()


func _refresh_char_marks() -> void:
	if _char_grid == null:
		return
	var ps = _profiles()
	var cur = _obj_key()
	for b in _char_grid.get_children():
		var id = b.get_meta("id")
		var key = b.get_meta("key")
		var tier = b.get_meta("tier")
		var color = C_BORDER if tier < 0 else ItemService.get_color_from_tier(tier).darkened(0.3)
		var w = 1
		if _mod.is_custom(id):
			color = C_CUSTOM
			w = 2
		elif ps.has(id) and ps[id].enabled or _kind == "weapon" and _is_modified(id):
			color = C_ACCENT_3
			w = 3
		if key == cur:
			color = C_ACCENT
			w = 3
		_set_icon_style(b, color, w)
		b.modulate = Color(1, 1, 1, 0.35) if _mod.is_disabled(_kind, key) else Color.white


func _on_char_search(t: String) -> void:
	_filters[_kind].q = t
	_refresh_char_list()


func _select(id: String) -> void:
	if _mod.find_target(_kind, id) == null:
		return
	_id = id
	_expanded = -1
	_refresh_header()
	_refresh_char_marks()
	_build_page()


# 当前对象（角色 / 道具 / 武器）
func _character():
	return _mod.find_target(_kind, _id)


func _refresh_header() -> void:
	var c = _character()
	if c == null:
		return
	var v = _view()
	var look = _look_view()
	var custom = _mod.is_custom(_id)
	_head_icon.texture = c.icon
	var nm = look.name if look.name != "" else tr(_orig_object_name())
	_head_name.text = nm
	_head_name.add_color_override("font_color", C_CUSTOM if _look_custom() else C_TEXT)
	var info = _obj_key()
	var src = _source(c)
	if src != "vanilla":
		info += "  ·  " + tr("BE_SRC_" + src.to_upper())
	if custom:
		if _kind == "character":
			info += "  ·  " + tr("BE_CUSTOM_TAG")
		var base = _base_res(look.base) if _look_custom() else null
		if base != null:
			info += "  ·  " + tr("BE_BASE").replace("{0}", tr(_mod.orig_name(base)))
	elif _is_modified(_id):
		info += "  ·  " + tr("BE_MODIFIED_TAG" if v.enabled else "BE_DISABLED_TAG")
	else:
		info += "  ·  " + tr("BE_ORIGINAL_TAG")
	var incomplete = _kind == "weapon" and not _mod.family_complete(c.weapon_id)
	if incomplete:
		info += "  ·  " + tr("BE_WEAPON_INCOMPLETE")
	elif _mod.is_disabled(_kind, _obj_key()):
		info += "  ·  " + tr("BE_OBJ_DISABLED_TAG")
	if not _mod.kind_enabled[_kind]:
		info += "  ·  " + tr("BE_KIND_OFF")
	_head_info.text = info
	_enable_switch.visible = not custom
	_enable_switch.set_block_signals(true)
	_enable_switch.pressed = v.enabled
	_enable_switch.set_block_signals(false)
	_reset_btn.disabled = custom or not _is_modified(_id)
	# 未完成的武器总是禁用（开关锁定为开）
	_disable_switch.set_block_signals(true)
	_disable_switch.pressed = incomplete or _obj_key() in _mod.disabled[_kind]
	_disable_switch.disabled = incomplete
	_disable_switch.set_block_signals(false)
	_refresh_tier_box()
	if _delete_btn != null:
		_delete_btn.disabled = not _look_custom()
	for t in _tab_buttons:
		var tb = _tab_buttons[t]
		_apply_chip_style(tb[0], t == _tab, tb[1])


# 等级按钮：已有等级可切换；可补的等级显示 "+Tn"；本模组加的两端等级可删除
func _refresh_tier_box() -> void:
	for ch in _tier_box.get_children():
		_tier_box.remove_child(ch)
		ch.queue_free()
	_tier_box.visible = _kind == "weapon"
	if _kind != "weapon":
		return
	var w = _character()
	var ms = _mod.family_members(w.weapon_id)
	var addable = _mod.addable_tiers(w.weapon_id)
	for t in 4:
		var m = null
		for x in ms:
			if x.tier == t:
				m = x
		if m != null:
			var b = _button("T" + str(t + 1), FONT_SMALL)
			b.rect_min_size = Vector2(56, 0)
			_apply_chip_style(b, m.my_id == _id, ItemService.get_color_from_tier(t))
			b.connect("pressed", self, "_select", [m.my_id])
			_tier_box.add_child(b)
		elif t in addable:
			var b = _button(tr("BE_TIER_ADD").replace("{0}", str(t + 1)), FONT_SMALL)
			_apply_action_style(b, C_ACCENT_3)
			b.connect("pressed", self, "_on_add_tier", [t])
			_tier_box.add_child(b)
	if _mod._custom_weapons.has(_id) and (w == ms[0] or w == ms[-1]):
		var del = _button(tr("BE_TIER_DELETE"), FONT_SMALL)
		_apply_action_style(del, C_DANGER)
		del.connect("pressed", self, "_on_delete_tier")
		_tier_box.add_child(del)


func _on_add_tier(t: int) -> void:
	var id = _mod.add_weapon_tier(_character().weapon_id, t)
	if id == "":
		return
	_refresh_char_list()
	_select(id)
	_set_status(tr("BE_TIER_ADDED"))


func _on_delete_tier() -> void:
	var wid = _character().weapon_id
	if not _mod.delete_weapon_tier(_id):
		return
	var ms = _mod.family_members(wid)
	_refresh_char_list()
	_select(ms[0].my_id if not ms.empty() else _first_listed())
	_set_status(tr("BE_TIER_DELETED"))


func _on_disable_toggled(pressed: bool) -> void:
	_mod.set_disabled(_kind, _obj_key(), pressed)
	_changed()


# 武器按家族（weapon_id）禁用 / 命名；其他按 my_id
func _obj_key() -> String:
	var r = _character()
	return r.weapon_id if _kind == "weapon" and r != null else _id


func _key_of(r) -> String:
	return r.weapon_id if _kind == "weapon" else r.my_id


func _fam_p() -> Dictionary:
	var wid = _obj_key()
	if not _mod.weapon_families.has(wid):
		_mod.weapon_families[wid] = BEMain.new_family()
	return _mod.weapon_families[wid]


# 名称 / 图标 / 基底所在的档案：武器为家族档案，其他为对象档案
func _look_view() -> Dictionary:
	if _kind == "weapon":
		return _mod.weapon_families.get(_obj_key(), BEMain.new_family())
	return _view()


func _look_p() -> Dictionary:
	return _fam_p() if _kind == "weapon" else _p()


func _look_custom() -> bool:
	return _mod.is_custom_family(_obj_key()) if _kind == "weapon" else _mod.is_custom(_id)


func _orig_object_name() -> String:
	var r = _character()
	if _kind == "weapon":
		var vm = _mod._vanilla_members(r.weapon_id)
		return _mod.orig_name(vm[0]) if not vm.empty() else "BE_NEW_WEAPON"
	return _mod.orig_name(r)


func _base_res(base: String):
	if _kind == "weapon":
		var vm = _mod._vanilla_members(base)
		return vm[0] if not vm.empty() else null
	return _mod.find_target(_kind, base)


# 自定义对象改了名称 / 外观后重新登记（列表图标、名称立即更新）
func _reregister() -> void:
	if not _look_custom():
		return
	match _kind:
		"character":
			_mod._register_custom(_id)
		"item":
			_mod._register_custom_item(_id)
		"weapon":
			_mod._register_weapon_families()


func _is_modified(id: String) -> bool:
	if _profiles().has(id):
		return true
	if _kind == "weapon":
		var r = _mod.find_target("weapon", id)
		var f = _mod.weapon_families.get(r.weapon_id if r != null else "", null)
		return f != null and not f.custom and (f.name != "" or f.sets is Array)
	return false


# 列表与筛选用的来源：武器按家族（含原版成员则取原版成员的来源）
func _source(r) -> String:
	if r is WeaponData:
		var vm = _mod._vanilla_members(r.weapon_id)
		return BEMain.source_of(vm[0]) if not vm.empty() else "mod"
	return BEMain.source_of(r)


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


var _page_key: Array = []


# 页面里各滚动区域的位置（按树中顺序）
func _scroll_values(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is ScrollContainer:
			out.push_back([c.scroll_vertical, c.scroll_horizontal])
		_scroll_values(c, out)
	return out


func _restore_scroll(n: Node, values: Array, i: int = 0) -> int:
	for c in n.get_children():
		if c is ScrollContainer and i < values.size():
			c.scroll_vertical = values[i][0]
			c.scroll_horizontal = values[i][1]
			i += 1
		i = _restore_scroll(c, values, i)
	return i


# 新页面排版完成后再恢复（排版前滚动范围为 0，会被截断）
func _restore_scroll_later(values: Array) -> void:
	yield(get_tree(), "idle_frame")
	if is_instance_valid(_page):
		var _n = _restore_scroll(_page, values)


func _build_page() -> void:
	var page_key = [_kind, _id, _tab]
	var scrolls = _scroll_values(_page, []) if page_key == _page_key else []
	_page_key = page_key
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_preview_text = null
	_name_labels = {}
	_effect_list = null
	_lib_list = null
	_ban_grids = {}
	if blueprint != null:
		blueprint.close_picker()
	blueprint = null
	match _tab:
		"overview":
			_build_overview()
		# 属性页：角色 = 开局状态 + 属性表；道具 = 数值 + 属性表；武器 = 数值 + 武器属性
		"stats":
			if _kind == "character":
				_build_stats()
			else:
				_build_attrs()
		"effects":
			_build_effects()
		"blueprint":
			blueprint = BlueprintPage.new()
			blueprint.build(self, _page)
		"gear":
			_build_gear()
		"bans":
			_build_bans()
	if not scrolls.empty():
		_restore_scroll_later(scrolls)


# ---------------- 概览 ----------------
# 概览：基础信息（名称；角色另有介绍）、外观（自定义对象）、词条 / 类别；右侧预览
func _build_overview() -> void:
	var cols = _page_columns()
	var left = _left_column(cols)
	_basic_section(left)
	if _look_custom():
		_look_section(left)
	_tag_section(left)
	_preview_card(cols)


# ---------------- 页面共通组件 ----------------
# 页面主体：左右分栏
func _page_columns() -> HBoxContainer:
	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 12)
	_page.add_child(cols)
	return cols


func _basic_section(left: Control) -> void:
	var look = _look_view()
	var box = _section(left, "BE_SEC_BASIC", C_ACCENT)
	box.add_child(_label(tr("BE_NAME"), FONT_SMALL, C_TEXT))
	var name_edit = _line_edit(tr(_orig_object_name()))
	name_edit.text = look.name
	name_edit.connect("text_changed", self, "_on_name_changed")
	box.add_child(name_edit)
	box.add_child(_desc(tr("BE_WEAPON_NAME_DESC" if _kind == "weapon" else "BE_NAME_DESC")))
	if _kind != "character":
		return
	box.add_child(_label(tr("BE_DESCRIPTION"), FONT_SMALL, C_TEXT))
	var desc_edit = TextEdit.new()
	desc_edit.rect_min_size = Vector2(0, 90)
	desc_edit.wrap_enabled = true
	desc_edit.add_font_override("font", FONT_SMALL)
	desc_edit.add_color_override("font_color", C_TEXT)
	desc_edit.add_stylebox_override("normal", _style(C_BG_CHIP, C_BORDER, 6, 1, 10, 6))
	desc_edit.add_stylebox_override("focus", _style(C_BG_CHIP, C_ACCENT, 6, 1, 10, 6))
	desc_edit.text = _view().desc
	desc_edit.connect("text_changed", self, "_on_desc_changed", [desc_edit])
	box.add_child(desc_edit)
	box.add_child(_desc(tr("BE_DESCRIPTION_DESC")))


# 自定义对象的外观：基底、图标、导入图片、ID
func _look_section(left: Control) -> void:
	var suffix = "" if _kind == "character" else "_" + _kind.to_upper()
	var cbox = _section(left, "BE_SEC_LOOK", C_CUSTOM)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	cbox.add_child(row)
	for d in [["BE_PICK_BASE" + suffix, "_open_picker", ["base"]], ["BE_PICK_ICON", "_open_picker", ["icon"]], ["BE_IMPORT_ICON", "_on_import_icon", []]]:
		var b = _button(tr(d[0]), FONT_SMALL)
		_apply_action_style(b, C_CUSTOM)
		b.connect("pressed", self, d[1], d[2])
		row.add_child(b)
	cbox.add_child(_desc(tr("BE_LOOK_DESC" + suffix)))
	_id_row(cbox)


# 词条 / 类别：角色 = 偏好词条，道具 = 道具词条，武器 = 武器类别（全部等级）
func _tag_section(left: Control) -> void:
	var r = _character()
	var title = {"character": "BE_SEC_TAGS", "item": "BE_SEC_ITEM_TAGS", "weapon": "BE_SEC_WEAPON_SETS"}[_kind]
	var tbox = _section(left, title, C_ACCENT_3)
	if _kind != "item":
		tbox.add_child(_desc(tr("BE_TAGS_DESC" if _kind == "character" else "BE_SETS_DESC")))
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_constant_override("hseparation", 6)
	grid.add_constant_override("vseparation", 6)
	tbox.add_child(grid)
	if _kind == "weapon":
		var look = _look_view()
		var cur = look.sets if look.sets is Array else _set_ids(_mod.backup_value(r, "sets"))
		for st in _isvc().sets:
			if st != null:
				var b = _chip(tr(st.name), st.my_id, st.my_id in cur, C_ACCENT_3)
				b.connect("pressed", self, "_on_set_pressed", [st.my_id])
				grid.add_child(b)
		return
	var v = _view()
	var field = "wanted_tags" if _kind == "character" else "tags"
	var tags = v[field] if v[field] is Array else _mod.backup_value(r, field)
	for tag in _all_tags():
		var b = _chip(_tag_name(tag), tag, tag in tags, C_ACCENT_3)
		b.connect("pressed", self, "_on_tag_pressed", [tag])
		grid.add_child(b)


const EFFECT_LINE = preload("res://items/global/effect_line.tscn")
const SAFE_TEXT_DIRS = ["res://items/", "res://dlcs/", "res://effects/", "res://weapons/"]


# 预览：与原版角色面板相同的效果行（左边图标，右边文本），下面是初始武器图标与禁用统计
func _refresh_preview() -> void:
	if _preview_text == null or not is_instance_valid(_preview_text):
		return
	for c in _preview_text.get_children():
		_preview_text.remove_child(c)
		c.queue_free()
	var v = _view()
	if not _mod.is_custom(_id) and _profiles().has(_id) and not v.enabled:
		_preview_text.add_child(_desc(tr("BE_PREVIEW_DISABLED")))
	if _kind == "weapon":
		for w in _mod.family_members(_character().weapon_id):
			var pv = _mod.weapon_profiles.get(w.my_id, BEMain.new_profile())
			var color = ItemService.get_color_from_tier(w.tier)
			var cur = w.my_id == _id
			var card = PanelContainer.new()
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.add_stylebox_override("panel", _style(color.darkened(0.72) if cur else C_BG_ITEM, color if cur else C_BORDER, 6, 2 if cur else 1, 10, 6))
			card.connect("gui_input", self, "_on_preview_tier_input", [w.my_id])
			_preview_text.add_child(card)
			var box = VBoxContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_constant_override("separation", 2)
			card.add_child(box)
			box.add_child(_label("T" + str(w.tier + 1) + "  ·  " + _price_text(w, pv), FONT_SMALL, color))
			_weapon_preview(box, w, pv)
			_effect_lines(_mod.build_effects(w.my_id, pv), box)
		return
	if _kind == "item":
		var limit = _limit_text(v.max_nb if v.max_nb != -2 else int(_mod.backup_value(_character(), "max_nb")))
		_preview_text.add_child(_label(_price_text(_character(), v) + ("  ·  " + limit if limit != "" else ""), FONT_SMALL, C_TEXT_DIM))
	_effect_lines(_mod.build_effects(_id, v))
	if _kind != "character":
		return
	var c = _character()
	var ws = _mod._weapons_by_ids(v.weapons) if v.weapons is Array else c.starting_weapons
	_preview_text.add_child(_label(tr("BE_PREVIEW_WEAPONS"), FONT_DESC, C_TEXT_DIM))
	# 6 列 × 60 像素正好放进固定宽度的预览栏（列数多了会把预览栏撑宽）
	var grid = _icon_grid(PREVIEW_ICON_COLUMNS)
	_preview_text.add_child(grid)
	for w in ws:
		grid.add_child(_icon_tile(w.icon, ItemService.get_color_from_tier(w.tier), 60))
	if v.ban_items.size() + v.ban_weapons.size() > 0:
		_preview_text.add_child(_desc(tr("BE_PREVIEW_BANS").replace("{0}", str(v.ban_items.size())).replace("{1}", str(v.ban_weapons.size()))))


# 数量限制（原版字符串）：1 = 独特；大于 1 = 限制 (X)；不限 = ""
func _limit_text(max_nb: int) -> String:
	if max_nb == 1:
		return tr("UNIQUE")
	if max_nb <= 0:
		return ""
	var t = tr("LIMITED")
	return t.replace("{0}/{1}", str(max_nb)).replace("{0}", "0").replace("{1}", str(max_nb))


func _price_text(r, v: Dictionary) -> String:
	return tr("BE_PRICE") + ": " + str(v.price if v.price >= 0 else int(_mod.backup_value(r, "value")))


func _on_preview_tier_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT and id != _id:
		call_deferred("_select", id)


# 原版效果行（左边图标，右边文本）
func _effect_lines(effects: Array, parent: Control = null) -> void:
	if parent == null:
		parent = _preview_text
	for e in effects:
		if e.get_script() == GraphEffect:
			_graph_lines(e.graph, parent)
			continue
		var path = e.get_script().resource_path if e.get_script() != null else ""
		var native = false
		for dir in SAFE_TEXT_DIRS:
			native = native or path.begins_with(dir)
		var line = EFFECT_LINE.instance()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(line)
		if native:
			line._display_effect(0, e, true, true)
		else:
			# 本 mod / 其他 mod 的效果：只显示文本（没有原版图标）
			line._display_special_text(_mod.effect_text(e), null)


# 蓝图：每条路径一行效果行，图标取效果节点的属性
func _graph_lines(g: Dictionary, parent: Control) -> void:
	var by_id = GraphEffect.nodes_by_id(g)
	for path in GraphEffect.paths(g):
		var stat = str(by_id[path[-1]].get("params", {}).get("stat", ""))
		var icon = ItemService.get_stat_small_icon(Keys.generate_hash(stat)) if stat != "" else null
		var line = EFFECT_LINE.instance()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(line)
		line._display_special_text(GraphEffect.path_text(by_id, path, true), icon)


# 武器属性文本（同原版武器面板：在武器副本上换成改写后的属性）
func _weapon_preview(parent: Control, w, v: Dictionary) -> void:
	var stats = _mod.weapon_stats_for(w, v)
	if stats == null:
		return
	var copy = w.duplicate()
	copy.stats = stats
	copy.effects = _mod.build_effects(w.my_id, v)
	var rt = _rich(copy.get_weapon_stats_text(0))
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rt)
	parent.add_child(_label(_aspd_text(stats), FONT_DESC, C_TEXT_DIM))


func _aspd_text(stats) -> String:
	return tr("BE_ATTACK_INTERVAL").replace("{0}", "%.2f" % Catalog.attack_interval(stats))


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
	return _mod.stat_name(tag)


func _on_name_changed(text: String) -> void:
	_look_p().name = text.strip_edges()
	_reregister()
	_changed()


func _on_desc_changed(edit: TextEdit) -> void:
	_p().desc = BEMain.clean_desc(edit.text)
	_changed()


# 角色 = 偏好词条（wanted_tags），道具 = 道具词条（tags）
func _on_tag_pressed(tag: String) -> void:
	var p = _p()
	var field = "wanted_tags" if _kind == "character" else "tags"
	if not p[field] is Array:
		p[field] = _mod.backup_value(_character(), field).duplicate()
	if tag in p[field]:
		p[field].erase(tag)
	else:
		p[field].push_back(tag)
	_reregister()
	_changed()
	_build_page()


# 武器类别：对全部等级生效（记在家族档案）
func _on_set_pressed(set_id: String) -> void:
	var f = _fam_p()
	if not f.sets is Array:
		f.sets = _set_ids(_mod.backup_value(_character(), "sets"))
	if set_id in f.sets:
		f.sets.erase(set_id)
	else:
		f.sets.push_back(set_id)
	_reregister()
	_changed()
	_build_page()


static func _set_ids(sets: Array) -> Array:
	var out = []
	for s in sets:
		if s != null:
			out.push_back(s.my_id)
	return out


# 原版武器家族的最低等级（选基底 / 图标用）
func _family_heads() -> Array:
	var heads = {}
	for w in _isvc().weapons:
		if w == null or _mod._custom_weapons.has(w.my_id):
			continue
		if not heads.has(w.weapon_id) or w.tier < heads[w.weapon_id].tier:
			heads[w.weapon_id] = w
	return heads.values()


# 自定义对象的 id：前缀 + 可编辑的后缀
func _id_row(parent: Control) -> void:
	var prefix = BEMain.ID_PREFIX[_kind]
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	parent.add_child(row)
	row.add_child(_label("ID", FONT_SMALL, C_TEXT))
	row.add_child(_label(prefix, FONT_SMALL, C_TEXT_DIM))
	var le = _line_edit("")
	le.text = _obj_key().trim_prefix(prefix)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.connect("text_entered", self, "_on_id_entered")
	row.add_child(le)
	var ok = _button(tr("BE_ID_APPLY"), FONT_SMALL)
	_apply_action_style(ok, C_CUSTOM)
	ok.connect("pressed", self, "_on_id_apply", [le])
	row.add_child(ok)


func _on_id_apply(le: LineEdit) -> void:
	_on_id_entered(le.text)


func _on_id_entered(text: String) -> void:
	var tier = _character().tier if _kind == "weapon" else 0
	var nid = _mod.rename_custom(_kind, _obj_key(), text)
	if nid == "":
		_set_status(tr("BE_CUSTOM_IN_USE" if _kind == "character" and _mod.is_in_saved_run(_obj_key()) else "BE_ID_TAKEN"))
		return
	_id = BEMain.tier_id(nid, tier, true) if _kind == "weapon" else nid
	_refresh_char_list()
	_select(_id)
	_set_status(tr("BE_ID_DONE"))


func _left_column(cols: Control) -> VBoxContainer:
	var scroll = _scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(scroll)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_constant_override("separation", 10)
	scroll.add_child(left)
	return left


func _preview_card(cols: Control) -> void:
	var pcard = _card(cols)
	pcard.size_flags_horizontal = 0
	pcard.rect_min_size = Vector2(PREVIEW_WIDTH, 0)
	pcard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pbox = VBoxContainer.new()
	pbox.add_constant_override("separation", 8)
	pcard.add_child(pbox)
	pbox.add_child(_label(tr("BE_SEC_PREVIEW"), FONT_NORMAL, C_ACCENT_2))
	var pscroll = _scroll()
	pbox.add_child(pscroll)
	_preview_text = VBoxContainer.new()
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_text.add_constant_override("separation", 4)
	pscroll.add_child(_preview_text)
	_refresh_preview()


# ---------------- 道具 / 武器：属性 ----------------
# 道具：价格、数量限制、稀有度 + 属性表；武器：本等级的价格、武器属性、属性加成（右侧预览整个家族）
func _build_attrs() -> void:
	var cols = _page_columns()
	var v = _view()
	var r = _character()
	var left = _left_column(cols)
	# 自定义道具没有"原值"：总是记下数值
	var custom_item = _kind == "item" and _mod.is_custom(_id)

	var box = _section(left, "BE_SEC_NUMBERS", C_ACCENT)
	var grid = _stat_grid(box)
	grid.columns = 2
	var orig_price = -999 if custom_item else int(_mod.backup_value(r, "value"))
	var price = _spin(0, 99999, 1)
	price.value = v.price if v.price >= 0 else int(_mod.backup_value(r, "value"))
	price.connect("value_changed", self, "_on_attr_changed", ["price", orig_price])
	_attr_row(grid, tr("BE_PRICE"), price, "value")
	_mark_name("value", int(price.value), int(_mod.backup_value(r, "value")))
	if _kind == "item":
		var orig_nb = -999 if custom_item else int(_mod.backup_value(r, "max_nb"))
		var nb = _spin(-1, 999, 1)
		nb.value = v.max_nb if v.max_nb != -2 else int(_mod.backup_value(r, "max_nb"))
		nb.connect("value_changed", self, "_on_attr_changed", ["max_nb", orig_nb])
		_attr_row(grid, tr("BE_MAX_NB"), nb, "max_nb")
		_mark_name("max_nb", int(nb.value), int(_mod.backup_value(r, "max_nb")))
		var tiers = HBoxContainer.new()
		tiers.add_constant_override("separation", 6)
		var orig_tier = int(_mod.backup_value(r, "tier"))
		var cur_tier = v.tier if v.tier >= 0 else orig_tier
		for t in 4:
			var tb = _button("T" + str(t + 1), FONT_SMALL)
			tb.rect_min_size = Vector2(64, 0)
			_apply_chip_style(tb, t == cur_tier, ItemService.get_color_from_tier(t))
			tb.connect("pressed", self, "_on_attr_changed", [t, "tier", -999 if custom_item else orig_tier])
			tiers.add_child(tb)
		_attr_row(grid, tr("BE_TIER"), tiers, "tier")
		_mark_name("tier", cur_tier, orig_tier)
		box.add_child(_desc(tr("BE_ITEM_BASIC_DESC")))
		_build_stat_tables(left, v)
	else:
		box.add_child(_desc(tr("BE_WEAPON_PRICE_DESC")))
		_build_weapon_stats(left, v, r)
		_preview_card(cols)


# 一行：名称（改过时绿色）+ 控件
func _attr_row(grid: Control, text: String, ctl: Control, key: String = "") -> void:
	grid.add_child(_name_cell(text, key))
	if ctl is SpinBox:
		ctl.rect_min_size = Vector2(150, 0)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(ctl)


# 价格 / 数量限制 / 稀有度：等于原值时记为"不修改"
func _on_attr_changed(value, field: String, orig: int) -> void:
	var unset = {"price": -1, "max_nb": -2, "tier": -1}[field]
	_p()[field] = unset if int(value) == orig else int(value)
	var label_key = "value" if field == "price" else field
	_mark_name(label_key, int(value), int(_mod.backup_value(_character(), label_key)))
	_reregister()
	_changed()
	if field == "tier":
		_build_page()


# 武器属性：原版字段（近战武器没有投射物字段）+ 属性加成
func _build_weapon_stats(parent: Control, v: Dictionary, w) -> void:
	var base = _mod.backup_value(w, "stats")
	if base == null:
		return
	var box = _section(parent, "BE_SEC_WEAPON_STATS", C_ACCENT_2)
	var head = HBoxContainer.new()
	box.add_child(head)
	var d = _desc(tr("BE_WEAPON_STATS_DESC"))
	head.add_child(d)
	var reset = _button(tr("BE_RESET"), FONT_SMALL)
	_apply_action_style(reset, C_DANGER)
	reset.connect("pressed", self, "_on_wstats_reset")
	head.add_child(reset)
	var grid = _stat_grid(box)
	grid.columns = 4
	var types = {}
	for f in BEMain.WSTAT_FIELDS:
		types[f[0]] = f[1]
	for row in WSTAT_LAYOUT:
		var cells = []
		for k in row:
			if k == "#type" or (k == "#attack" and "attack_type" in base) or (types.has(k) and k in base):
				cells.push_back(k)
		if cells.empty():
			continue
		while cells.size() < 2:
			cells.push_back("")
		for k in cells:
			_wstat_cell(grid, k, types.get(k, ""), base, v, w)
	_aspd_label = _label(_aspd_text(_mod.weapon_stats_for(w, v)), FONT_DESC, C_TEXT_DIM)
	box.add_child(_aspd_label)

	var sbox = _section(parent, "BE_SEC_SCALING", C_ACCENT_2)
	var scaling = v.scaling if v.scaling is Array else BEMain.scaling_names(base.scaling_stats)
	for i in scaling.size():
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 8)
		sbox.add_child(row)
		var icon = TextureRect.new()
		icon.texture = _stat_icon(str(scaling[i][0]))
		icon.expand = true
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.rect_min_size = Vector2(22, 22)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var opt = _stat_option(str(scaling[i][0]))
		opt.rect_min_size = Vector2(260, 0)
		opt.connect("selected", self, "_on_scaling_stat", [i])
		row.add_child(opt)
		var sb = _spin(-9999, 9999, 1)
		sb.suffix = "%"
		sb.rect_min_size = Vector2(150, 0)
		sb.value = round(float(scaling[i][1]) * 100)
		sb.connect("value_changed", self, "_on_scaling_coef", [i])
		row.add_child(sb)
		var del = _button("X", FONT_DESC)
		_apply_action_style(del, C_DANGER)
		del.connect("pressed", self, "_on_scaling_delete", [i])
		row.add_child(del)
	var add = _button(tr("BE_SCALING_ADD"), FONT_SMALL)
	add.size_flags_horizontal = 0
	_apply_action_style(add, C_ACCENT_3)
	add.connect("pressed", self, "_on_scaling_add")
	sbox.add_child(add)


# 一格武器属性（名称 + 控件）
func _wstat_cell(grid: Control, k: String, type: String, base, v: Dictionary, w) -> void:
	if k == "":
		grid.add_child(Control.new())
		grid.add_child(Control.new())
		return
	if k == "#type":
		grid.add_child(_name_cell(tr("BE_WS_TYPE"), "type"))
		grid.add_child(_label(tr("RANGED" if w.type == 1 else "MELEE"), FONT_SMALL, C_TEXT))
		return
	if k == "#attack":
		var sweep = int(v.wstats.get("attack_type", base.attack_type)) == 1
		var tb = _button(tr("BE_WS_SWEEP" if sweep else "BE_WS_THRUST"), FONT_DESC)
		tb.rect_min_size = Vector2(150, 0)
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_apply_chip_style(tb, sweep, C_ACCENT_2)
		tb.connect("pressed", self, "_on_wstat_changed", [0 if sweep else 1, ["attack_type", "int", ""]])
		_attr_row(grid, tr("BE_WS_ATTACK_TYPE"), tb, "attack_type")
		_mark_name("attack_type", str(int(sweep)), str(int(base.attack_type)))
		return
	var mode = WSTAT_SHOW.get(k, "")
	var cur = v.wstats.get(k, base.get(k))
	var ctl = _spin(-99999, 99999, 0.01 if type == "float" and mode == "" else 1)
	ctl.value = _wstat_shown(cur, mode)
	ctl.connect("value_changed", self, "_on_wstat_changed", [[k, type, mode]])
	_attr_row(grid, tr("BE_WS_" + k.to_upper()), ctl, k)
	_mark_name(k, cur, base.get(k))


# 界面显示值：pct = 百分比整数，neg = 取负
static func _wstat_shown(value, mode: String) -> float:
	match mode:
		"pct":
			return round(float(value) * 100)
		"neg":
			return -float(value)
	return float(value)


func _on_wstat_changed(value, f: Array) -> void:
	var p = _p()
	var base = _mod.backup_value(_character(), "stats")
	var stored
	match f[2]:
		"pct":
			stored = float(value) / 100.0
		"neg":
			stored = -float(value)
		_:
			stored = float(value)
	if f[1] == "int":
		stored = int(round(stored))
	if _wstat_shown(base.get(f[0]), f[2]) == _wstat_shown(stored, f[2]):
		stored = base.get(f[0])
	if stored == base.get(f[0]):
		p.wstats.erase(f[0])
	else:
		p.wstats[f[0]] = stored
	_mark_name(f[0], stored, base.get(f[0]))
	if f[0] == "attack_type":
		_changed()
		_build_page()
	else:
		_changed()
		if _aspd_label != null and is_instance_valid(_aspd_label):
			_aspd_label.text = _aspd_text(_mod.weapon_stats_for(_character(), p))


func _on_wstats_reset() -> void:
	var p = _p()
	p.wstats = {}
	p.scaling = null
	_changed()
	_build_page()


func _scaling_edit() -> Array:
	var p = _p()
	if not p.scaling is Array:
		p.scaling = BEMain.scaling_names(_mod.backup_value(_character(), "stats").scaling_stats)
	return p.scaling


func _on_scaling_stat(key, i: int) -> void:
	_scaling_edit()[i][0] = str(key)
	_changed()
	_build_page()


func _on_scaling_coef(value: float, i: int) -> void:
	_scaling_edit()[i][1] = value / 100.0
	_changed()


func _on_scaling_delete(i: int) -> void:
	_scaling_edit().remove(i)
	_changed()
	_build_page()


func _on_scaling_add() -> void:
	_scaling_edit().push_back(["stat_melee_damage", 1.0])
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
	_build_stat_tables(col, v)


# 属性表（基础属性 | 属性获取修改 % | 次要属性）与商店 / 地图 / 规则分组
func _build_stat_tables(col: Control, v: Dictionary) -> void:
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
	row.add_child(_name_cell(stat_name(key), key))
	var sb = _spin(-9999, 9999, 1)
	sb.rect_min_size = Vector2(110, 0)
	sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sb.value = int(v.stats.get(key, _stat_default(key)))
	sb.connect("value_changed", self, "_on_stat_changed", [key, null])
	row.add_child(sb)
	_mark_name(key, int(sb.value), _stat_default(key))
	return row


# 属性页的"不修改"值：一般为 0；设定值型规则为角色自身的值
func _stat_default(key: String) -> int:
	return _mod.native_set_value(_id, key) if key in BEMain.SET_KEYS else 0


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
		row.add_child(_name_cell(tr(f[1]), f[0]))
		var sb = _spin(f[2], f[3], 1)
		sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sb.allow_greater = false
		sb.allow_lesser = false
		sb.rect_min_size = Vector2(120, 0)
		sb.value = int(BEMain.start_value(v, f[0]))
		sb.connect("value_changed", self, "_on_start_changed", [f[0]])
		row.add_child(sb)
		_mark_name(f[0], int(sb.value), BEMain.START_DEFAULT[f[0]])
	var settle = _checkbox(tr("BE_START_LEVEL_SETTLE"), FONT_DESC)
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
	_mark_name(key, v, BEMain.START_DEFAULT[key])
	_changed()


func _on_stat_changed(value: float, key: String, _lbl = null) -> void:
	var p = _p()
	if int(value) == _stat_default(key):
		p.stats.erase(key)
	else:
		p.stats[key] = int(value)
	_mark_name(key, int(value), _stat_default(key))
	_changed()


func _on_stats_clear() -> void:
	_p().stats = {}
	_changed()
	_build_page()


# ---------------- 效果 ----------------
func _specs() -> Array:
	return _with_groups(_view())


# 档案的效果列表 + 生成效果（初始属性每项 / 每件额外初始装备 / 蓝图）的占位：
# 已有占位保持位置，旧的整组占位就地展开为条目，没有占位的条目接在最后，失效的占位丢弃
func _with_groups(p: Dictionary) -> Array:
	var specs = _mod.effect_specs(_id, p)
	var entries = _mod.group_entries(p)
	var sigs = {}
	for en in entries:
		sigs[BEMain.entry_sig(en.marker)] = en
	var referenced = {}
	for s in specs:
		if s is Dictionary and s.has("group") and not BEMain.is_group_marker(s):
			referenced[BEMain.entry_sig(s)] = true
	var out = []
	var placed = {}
	for s in specs:
		if s is Dictionary and s.has("group"):
			var group_entries = []
			if BEMain.is_group_marker(s):
				for en in entries:
					var sig = BEMain.entry_sig(en.marker)
					if en.marker.group == s.group and not referenced.has(sig):
						group_entries.push_back(en)
			elif sigs.has(BEMain.entry_sig(s)):
				group_entries.push_back(sigs[BEMain.entry_sig(s)])
			for en in group_entries:
				var sig = BEMain.entry_sig(en.marker)
				if not placed.has(sig):
					placed[sig] = true
					out.push_back(en.marker.duplicate())
			continue
		out.push_back(s)
	for en in entries:
		if not placed.has(BEMain.entry_sig(en.marker)):
			out.push_back(en.marker.duplicate())
	return out


# 编辑前把"原版效果"展开为 spec 列表（含生成效果的占位）
func _edit_specs() -> Array:
	var p = _p()
	var full = _with_groups(p)
	if not p.effects is Array or JSON.print(full) != JSON.print(p.effects):
		p.effects = full.duplicate(true)
	return p.effects


func _is_marker(spec) -> bool:
	return spec is Dictionary and spec.has("group")


# 占位对应的生成效果
func _marker_effect(spec):
	var found = _mod.entries_for_marker(_mod.group_entries(_view()), spec)
	return found[0].effect if not found.empty() else null


func _build_effects() -> void:
	var cols = _page_columns()

	# 左：角色效果列表
	var lcard = _card(cols)
	lcard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lbox = VBoxContainer.new()
	lbox.add_constant_override("separation", 8)
	lcard.add_child(lbox)
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	lbox.add_child(head)
	var title = _label(tr("BE_SEC_EFFECTS" if _kind == "character" else "BE_SEC_EFFECTS_" + _kind.to_upper()), FONT_NORMAL, C_CUSTOM)
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
	rbox.add_child(_desc(tr("BE_LIBRARY_DESC_WEAPON" if _kind == "weapon" else "BE_LIBRARY_DESC")))
	var cats = GridContainer.new()
	cats.columns = 4
	cats.add_constant_override("hseparation", 6)
	cats.add_constant_override("vseparation", 6)
	rbox.add_child(cats)
	for c in Catalog.CATEGORIES:
		var b = _button(tr(c[1]), FONT_DESC)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.rect_min_size = Vector2(60, 0)
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
	_effect_rows = {}
	var specs = _specs()
	for i in specs.size():
		if _is_marker(specs[i]):
			_effect_list.add_child(_group_row(i, specs[i]))
		elif _mod.make_effect(specs[i]) != null:
			_effect_list.add_child(_effect_row(i, specs[i]))
		# 模板不存在（来自已停用的 mod）的效果不显示，档案里保留
	if _effect_list.get_child_count() == 0:
		_effect_list.add_child(_desc(tr("BE_EFFECTS_EMPTY")))


# 可拖动的行（左侧把手；拖到另一行上松开即可移动）
func _drag_card(i: int, bg: Color, border: Color) -> PanelContainer:
	var card = DragRow.new()
	card.editor = self
	card.index = i
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	card.add_stylebox_override("panel", _style(bg, border, 6, 1, 10, 6))
	return card


func _drag_handle() -> Label:
	var h = _label("::", FONT_SMALL, C_TEXT_DIM)
	h.valign = Label.VALIGN_CENTER
	h.size_flags_vertical = Control.SIZE_FILL
	return h


# 键名（灰色小字，只在"显示键名"下显示）：key · custom_key · text_key
func _key_info(e) -> String:
	if e == null:
		return ""
	var parts = []
	for v in [e.key, e.custom_key, e.text_key]:
		if str(v) != "":
			parts.push_back(str(v))
	return PoolStringArray(parts).join("  ·  ")


func _key_label(text: String) -> Label:
	var l = _label(text, FONT_DESC, C_TEXT_DIM)
	l.set_message_translation(false)
	l.modulate.a = 0.8
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# 属性名称格：白字；显示键名时下方另起一行灰色键名
func _name_cell(text: String, key: String = "") -> Control:
	var lbl = _label(text, FONT_DESC, C_TEXT)
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if key != "":
		_name_labels[key] = lbl
	if not _mod.debug or key == "":
		return lbl
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_constant_override("separation", 0)
	col.add_child(lbl)
	col.add_child(_key_label(key))
	return col


# 名称颜色：与原值相同为白色，改大为绿色、改小为红色（非数值的改动为绿色）
func _mark_name(key: String, value, orig) -> void:
	var lbl = _name_labels.get(key)
	if lbl == null or not is_instance_valid(lbl):
		return
	var color = C_TEXT
	if typeof(value) in [TYPE_INT, TYPE_REAL] and typeof(orig) in [TYPE_INT, TYPE_REAL]:
		if float(value) > float(orig) + 0.00001:
			color = C_ACCENT_3
		elif float(value) < float(orig) - 0.00001:
			color = C_DANGER
	elif value != orig:
		color = C_ACCENT_3
	lbl.add_color_override("font_color", color)


# 词条 / 类别按钮：显示键名时按钮里另起一行灰色键名
func _chip(text: String, key: String, on: bool, accent: Color) -> Button:
	var b = _button(text, FONT_DESC)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	_apply_chip_style(b, on, accent)
	if _mod.debug:
		b.text = ""
		b.rect_min_size = Vector2(0, 44)
		var col = VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_WIDE)
		col.alignment = BoxContainer.ALIGN_CENTER
		col.add_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var name = _label(text, FONT_DESC, C_TEXT if on else C_TEXT_DIM)
		name.align = Label.ALIGN_CENTER
		name.clip_text = true
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name)
		var k = _key_label(key)
		k.align = Label.ALIGN_CENTER
		col.add_child(k)
	return b


# 初始属性 / 额外初始装备 / 蓝图生成的一条效果：只读，显示来源，可拖动排序
func _group_row(i: int, spec: Dictionary) -> Control:
	var card = _drag_card(i, C_BG_CHIP, C_BORDER)
	card.set_meta("be_group", spec.group)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(row)
	row.add_child(_drag_handle())
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(col)
	var e = _marker_effect(spec)
	col.add_child(_rich(_mod.effect_text(e) if e != null else ""))
	if _mod.debug:
		col.add_child(_key_label(_key_info(e)))
	var src = _label(tr("BE_SRC_GROUP_" + str(spec.group).to_upper()), FONT_DESC, C_ACCENT)
	src.rect_min_size = Vector2(120, 0)
	src.align = Label.ALIGN_RIGHT
	row.add_child(src)
	return card


# 拖动预览的文字
func drag_text(i: int) -> String:
	var specs = _specs()
	if i < 0 or i >= specs.size():
		return ""
	var e = _marker_effect(specs[i]) if _is_marker(specs[i]) else _mod.make_effect(specs[i])
	return _strip(_mod.effect_text(e)) if e != null else ""


# 把第 from 行移到第 to 行之前（after = 之后）
func move_effect_to(from: int, to: int, after: bool) -> void:
	var specs = _edit_specs()
	if from < 0 or from >= specs.size() or to < 0 or to >= specs.size() or from == to:
		return
	var item = specs[from]
	var expanded_item = specs[_expanded] if _expanded >= 0 and _expanded < specs.size() else null
	specs.remove(from)
	var t = to - 1 if from < to else to
	if after:
		t += 1
	specs.insert(clamp(t, 0, specs.size()), item)
	_expanded = specs.find(expanded_item) if expanded_item != null else -1
	_fill_effect_list()
	_changed()


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
	var card = _drag_card(i, C_BG_ITEM, C_ACCENT_2 if i == _expanded else C_BORDER)
	var col = VBoxContainer.new()
	col.add_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(col)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(row)
	row.add_child(_drag_handle())
	var e = _mod.make_effect(spec) if spec is Dictionary else null
	var tcol = VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(tcol)
	var txt = _rich(_effect_text(spec))
	tcol.add_child(txt)
	if _mod.debug:
		tcol.add_child(_key_label(_key_info(e)))
	var src = _label(_source_name(spec), FONT_DESC, C_TEXT_DIM)
	src.rect_min_size = Vector2(120, 0)
	src.clip_text = true
	src.align = Label.ALIGN_RIGHT
	row.add_child(src)
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
	_effect_rows[i] = txt
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
				var tb = _button(tr("BE_YES" if cur else "BE_NO"), FONT_DESC)
				tb.toggle_mode = true
				tb.pressed = cur
				tb.rect_min_size = Vector2(70, 0)
				tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_apply_chip_style(tb, cur, C_ACCENT_3)
				tb.connect("toggled", self, "_on_bool_field", [i, f.name, tb])
				grid.add_child(tb)
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


func _on_bool_field(pressed: bool, i: int, field: String, tb: Button) -> void:
	tb.text = tr("BE_YES" if pressed else "BE_NO")
	_apply_chip_style(tb, pressed, C_ACCENT_3)
	_set_field(i, field, pressed)


func _on_effect_edit(i: int) -> void:
	_expanded = -1 if _expanded == i else i
	_fill_effect_list()


func _on_effect_move(i: int, d: int) -> void:
	move_effect_to(i, i + d, d > 0)


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
	if _effect_rows.has(i):
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
	for entry in _mod.library(_kind == "weapon"):
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
		if _mod.debug:
			var tcol = VBoxContainer.new()
			tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tcol.add_child(_rich(text))
			tcol.add_child(_key_label(_key_info(entry.effect)))
			row.add_child(tcol)
		else:
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

	var wbox = _section(box, "BE_SEC_START_WEAPONS", C_CUSTOM_2)
	var wrow = HBoxContainer.new()
	wrow.add_constant_override("separation", 8)
	wbox.add_child(wrow)
	var pick = _button(tr("BE_PICK_WEAPONS"), FONT_SMALL)
	_apply_action_style(pick, C_CUSTOM_2)
	pick.connect("pressed", self, "_open_picker", ["start_weapons"])
	wrow.add_child(pick)
	var from_char = _button(tr("BE_IMPORT_FROM_CHARACTER"), FONT_SMALL)
	_apply_action_style(from_char, C_CUSTOM_2)
	from_char.connect("pressed", self, "_open_char_weapons")
	wrow.add_child(from_char)
	if not _mod.is_custom(_id):
		var orig = _button(tr("BE_RESTORE_ORIGINAL"), FONT_SMALL)
		_apply_action_style(orig, C_ACCENT)
		orig.connect("pressed", self, "_on_weapons_original")
		wrow.add_child(orig)
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
			var cb = _checkbox(tr("BE_CURSED"), FONT_DESC)
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


# 从角色导入初始武器：表格列出每个角色（本角色除外）的初始武器，点击一行即采用
func _open_char_weapons() -> void:
	var m = Modal.open(self, tr("BE_PICKER_CHAR_WEAPONS"), C_CUSTOM_2, Vector2(1240, 820))
	m.add_button(tr("BE_CANCEL"), C_TEXT_DIM, m, "close")
	var scroll = _scroll()
	m.body.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 14)
	grid.add_constant_override("vseparation", 6)
	scroll.add_child(grid)
	var chars = []
	for c in _isvc().characters:
		if c != null and c.my_id != _id:
			chars.push_back(c)
	chars.sort_custom(self, "_sort_by_name")
	for c in chars:
		var b = _button(tr(c.name), FONT_SMALL)
		b.icon = c.icon
		b.expand_icon = true
		b.align = Button.ALIGN_LEFT
		b.clip_text = true
		b.rect_min_size = Vector2(300, 56)
		_apply_action_style(b, C_CUSTOM_2)
		b.connect("pressed", self, "_on_char_weapons_picked", [c.my_id, m])
		grid.add_child(b)
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 4)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row)
		for w in c.starting_weapons:
			row.add_child(_icon_tile(w.icon, ItemService.get_color_from_tier(w.tier), 48))


func _on_char_weapons_picked(char_id: String, m) -> void:
	var ids = []
	for w in _mod.find_character(char_id).starting_weapons:
		if not w.my_id in ids:
			ids.push_back(w.my_id)
	m.close()
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
	_look_p().icon = v
	_reregister()
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
	var cols = _page_columns()
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
		var items = _isvc().items.duplicate()
		items.sort_custom(self, "_sort_by_tier_then_name")
		return items
	# 武器按系列（weapon_id）禁用，每个系列显示最低稀有度的那一把
	var by_family = {}
	for w in _isvc().weapons:
		if not by_family.has(w.weapon_id) or w.tier < by_family[w.weapon_id].tier:
			by_family[w.weapon_id] = w
	var out = by_family.values()
	out.sort_custom(self, "_sort_by_tier_then_name")
	return out


func _sort_by_tier_then_name(a, b) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	return tr(a.name) < tr(b.name)


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
			match _kind:
				"character":
					_picker_res = _native_characters()
				"item":
					_picker_res = _native_items()
				"weapon":
					_picker_res = _family_heads()
			_picker_sel = [_look_view().base]
		"icon":
			_picker_res = _native_characters() + _native_items() + _family_heads()
			_picker_sel = [_look_view().icon]
	_picker_res.sort_custom(self, "_sort_by_tier_name")

	var title = tr("BE_PICKER_" + mode.to_upper() + ("_" + _kind.to_upper() if mode == "base" and _kind != "character" else ""))
	_picker = Modal.open(self, title, C_ACCENT_2, Vector2(1240, 820))
	_picker.connect("closed", self, "_on_picker_closed")
	_picker_count = _label("", FONT_SMALL, C_TEXT_DIM)
	_picker.head.add_child(_picker_count)
	var box = _picker.body
	var search = _line_edit(tr("BE_SEARCH"))
	search.connect("text_changed", self, "_on_picker_search")
	box.add_child(search)
	_picker_f = {"tier": -1, "type": -1, "src": "all"}
	_picker_chips = {}
	if _picker_weapons():
		var tiers = [[-1, "BE_FILTER_ALL"]]
		for t in 4:
			tiers.push_back([t, "T" + str(t + 1)])
		var frow = HBoxContainer.new()
		frow.add_constant_override("separation", 16)
		box.add_child(frow)
		_picker_chip_row(frow, "tier", tiers)
		_picker_chip_row(frow, "type", [[-1, "BE_FILTER_ALL"], [0, "MELEE"], [1, "RANGED"]])
		_picker_chip_row(frow, "src", SOURCES)
	var scroll = _scroll()
	box.add_child(scroll)
	_picker_grid = _icon_grid(16)
	scroll.add_child(_picker_grid)
	var hint = _desc(tr("BE_PICKER_MULTI_DESC" if _picker_multi else "BE_PICKER_SINGLE_DESC"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.foot.add_child(hint)
	if mode == "start_weapons":
		_picker.add_button(tr("BE_PICKER_SELECT_SHOWN"), C_ACCENT_3, self, "_on_picker_shown", [true])
		_picker.add_button(tr("BE_PICKER_DESELECT_SHOWN"), C_TEXT_DIM, self, "_on_picker_shown", [false])
		_picker.add_button(tr("BE_PICKER_RESET_ALL"), C_DANGER, self, "_on_picker_reset")
	elif _picker_multi:
		_picker.add_button(tr("BE_PICKER_CLEAR"), C_DANGER, self, "_on_picker_clear")
	_picker.add_button(tr("BE_CANCEL"), C_TEXT_DIM, self, "_close_picker")
	_picker.add_button(tr("BE_CONFIRM"), C_ACCENT_3, self, "_on_picker_confirm")
	_fill_picker()
	search.call_deferred("grab_focus")


func _picker_weapons() -> bool:
	return _picker_mode in ["start_weapons", "start_items_w"]


# 一组筛选按钮（稀有度 / 近远战 / 来源）
func _picker_chip_row(parent: Control, key: String, defs: Array) -> void:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	parent.add_child(row)
	_picker_chips[key] = []
	for d in defs:
		var b = _button(tr(d[1]), FONT_DESC)
		b.rect_min_size = Vector2(56, 0)
		b.connect("pressed", self, "_on_picker_chip", [key, d[0]])
		row.add_child(b)
		_picker_chips[key].push_back([b, d[0]])
	_style_picker_chips(key)


func _style_picker_chips(key: String) -> void:
	for bv in _picker_chips[key]:
		_apply_chip_style(bv[0], bv[1] == _picker_f[key], C_ACCENT_2)


func _on_picker_chip(key: String, value) -> void:
	_picker_f[key] = value
	_style_picker_chips(key)
	_fill_picker()


func _picker_shown(r) -> bool:
	if _picker_filter != "" and tr(r.name).to_lower().find(_picker_filter) < 0 and r.my_id.find(_picker_filter) < 0:
		return false
	if not _picker_weapons():
		return true
	return (_picker_f.tier < 0 or r.tier == _picker_f.tier) and (_picker_f.type < 0 or r.type == _picker_f.type) and (_picker_f.src == "all" or _source(r) == _picker_f.src)


# 选中 / 取消当前筛选出的全部
func _on_picker_shown(on: bool) -> void:
	for r in _picker_res:
		if not _picker_shown(r):
			continue
		if on and not r.my_id in _picker_sel:
			_picker_sel.push_back(r.my_id)
		elif not on:
			_picker_sel.erase(r.my_id)
	_fill_picker()


# 重置全部：恢复为原版初始武器（自定义角色取基底角色的）
func _on_picker_reset() -> void:
	var c = _character()
	if _mod.is_custom(_id):
		c = _mod.find_character(_view().base)
	_picker_sel = []
	if c != null:
		for w in _mod.backup_value(c, "starting_weapons"):
			if not w.my_id in _picker_sel:
				_picker_sel.push_back(w.my_id)
	_fill_picker()


func _on_picker_closed() -> void:
	_picker = null


func _native_items() -> Array:
	var out = []
	for it in _isvc().items:
		if not _mod.is_custom(it.my_id):
			out.push_back(it)
	return out


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
		if not _picker_shown(r):
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
				_look_p().base = _kind_base(_picker_sel[0])
		"icon":
			if not _picker_sel.empty():
				_look_p().icon = _picker_sel[0]
	_close_picker()
	if _look_custom():
		_reregister()
		_refresh_char_list()
	_changed()
	_build_page()


# 武器的基底记家族 id
func _kind_base(id: String) -> String:
	if _kind == "weapon":
		var w = _mod.find_target("weapon", id)
		return w.weapon_id if w != null else id
	return id


func _close_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.close()
	_picker = null


# ============================================================
# 顶部事件
# ============================================================
# 重新登记自定义对象（图标重新生成）
func _on_hide_numbers_toggled(pressed: bool) -> void:
	_mod.hide_numbers = pressed
	_mod._icon_cache.clear()
	_mod.apply_all()
	_refresh_char_list()
	_refresh_header()
	_build_page()


func _on_debug_toggled(pressed: bool) -> void:
	_mod.debug = pressed
	_build_page()


func _on_enable_toggled(pressed: bool) -> void:
	_p().enabled = pressed
	_changed()


func _on_reset_pressed() -> void:
	Modal.confirm(self, [tr("BE_RESET_CONFIRM_MSG").replace("{0}", _head_name.text)], C_DANGER, self, "_do_reset")


func _do_reset() -> void:
	_mod.reset_profile(_id, _kind)
	if _kind == "weapon" and not _look_custom() and _mod.weapon_families.has(_obj_key()):
		var f = _mod.weapon_families[_obj_key()]
		f.name = ""
		f.sets = null
	_expanded = -1
	_changed()
	_build_page()
	_set_status(tr("BE_RESET_DONE"))


func _on_new_custom() -> void:
	var base = _look_view().base if _look_custom() else (_obj_key())
	var id = ""
	match _kind:
		"character":
			id = _mod.create_custom(base)
		"item":
			id = _mod.create_custom_item(base)
		"weapon":
			id = _mod.create_custom_weapon(base)
	_refresh_char_list()
	_select(id)
	_set_status(tr("BE_CUSTOM_CREATED" if _kind == "character" else "BE_CUSTOM_CREATED_OBJ"))


func _on_delete_custom() -> void:
	if not _look_custom():
		return
	Modal.confirm(self, [tr("BE_DELETE_CONFIRM_MSG").replace("{0}", _head_name.text)], C_DANGER, self, "_do_delete")


func _do_delete() -> void:
	var ok = false
	match _kind:
		"character":
			ok = _mod.delete_custom(_id)
		"item":
			ok = _mod.delete_custom_item(_id)
		"weapon":
			ok = _mod.delete_custom_weapon(_obj_key())
	if ok:
		_set_status(tr("BE_CUSTOM_DELETED" if _kind == "character" else "BE_CUSTOM_DELETED_OBJ"))
		_refresh_char_list()
		_select(_first_listed())
	else:
		if _kind == "character":
			_set_status(tr("BE_CUSTOM_IN_USE"))
		_refresh_header()


# 全部重置：第一个弹窗勾选重置哪些（禁用状态 / 修改内容 / 自定义内容），第二个弹窗最终确认
const RESET_PARTS = [["disabled", "BE_RESET_PART_DISABLED"], ["edits", "BE_RESET_PART_EDITS"], ["custom", "BE_RESET_PART_CUSTOM"]]
var _reset_parts: Dictionary = {}


func _on_reset_kind() -> void:
	var kind_name = tr("BE_KIND_" + _kind.to_upper())
	var m = Modal.open(self, tr("BE_RESET_KIND"), C_DANGER, Vector2(720, 0))
	m.body.add_child(_desc(tr("BE_RESET_KIND_PICK").replace("{0}", kind_name)))
	_reset_parts = {}
	for d in RESET_PARTS:
		var cb = _checkbox(tr(d[1]), FONT_SMALL)
		cb.pressed = true
		m.body.add_child(cb)
		_reset_parts[d[0]] = cb
	m.add_button(tr("BE_CANCEL"), C_TEXT_DIM, m, "close")
	m.ok_button = m.add_button(tr("BE_NEXT"), C_DANGER, self, "_on_reset_kind_next", [m])


func _on_reset_kind_next(m) -> void:
	var parts = []
	var names = []
	for d in RESET_PARTS:
		if _reset_parts[d[0]].pressed:
			parts.push_back(d[0])
			names.push_back(tr(d[1]))
	if parts.empty():
		return
	m.close()
	var msg = tr("BE_RESET_KIND_CONFIRM").replace("{0}", tr("BE_KIND_" + _kind.to_upper())).replace("{1}", PoolStringArray(names).join(tr("BE_LIST_SEP")))
	Modal.confirm(self, [msg], C_DANGER, self, "_do_reset_kind", [parts])


func _do_reset_kind(parts: Array) -> void:
	var kept = _mod.reset_kind(_kind, parts)
	_mod.apply_all()
	_expanded = -1
	_fill_left()
	if _mod.find_target(_kind, _id) == null:
		_id = _first_listed()
	_select(_id)
	_changed()
	_set_status(tr("BE_RESET_KIND_DONE") if kept == 0 else tr("BE_RESET_KIND_KEPT").replace("{0}", str(kept)))


func _clipboard_get() -> String:
	return test_clipboard if test_clipboard != null else OS.clipboard


func _clipboard_set(text: String) -> void:
	if test_clipboard != null:
		test_clipboard = text
	else:
		OS.clipboard = text


func _on_export_selected(prefix: String) -> void:
	var code = ""
	if prefix == BEMain.SHARE_PREFIX:
		code = _mod.export_code(_id, _kind)
	elif prefix == BEMain.ALL_PREFIX:
		code = _mod.export_bundle("")
	else:
		for k in BEMain.BUNDLE_PREFIX:
			if BEMain.BUNDLE_PREFIX[k] == prefix:
				code = _mod.export_bundle(k)
	if code == "":
		_set_status(tr("BE_EXPORT_NOTHING"))
		return
	_clipboard_set(code)
	_set_status(tr("BE_EXPORTED"))


func _on_import_pressed() -> void:
	var text = _clipboard_get()
	var n = _mod.import_bundle(text)
	if n >= 0:
		_refresh_char_list()
		_select(_id)
		_set_status(tr("BE_IMPORTED_N").replace("{0}", str(n)))
		return
	var id = _mod.import_code(text, _id, _kind)
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
		_mod.on_editor_closed(_sig() != _start_sig)
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


# 方形图标格（同原版物品格：稀有度色底 + 边框）
func _icon_tile(tex: Texture, color: Color, size: int) -> Control:
	var tile = PanelContainer.new()
	tile.rect_min_size = Vector2(size, size)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_stylebox_override("panel", _style(color.darkened(0.75), color, 6, 2, 4, 4))
	var icon = TextureRect.new()
	icon.texture = tex
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(size - 8, size - 8)
	tile.add_child(icon)
	return tile


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


# 勾选框：各状态用同一个样式（游戏主题的悬停样式边距不同，文字会左移、压到勾上）
func _checkbox(text: String, font: Font) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = text
	cb.add_font_override("font", font)
	var sb = StyleBoxEmpty.new()
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		cb.add_stylebox_override(st, sb)
	return cb


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
