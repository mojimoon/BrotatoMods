extends Reference

# 通用的对象选择弹窗（角色 / 道具 / 武器）：搜索 + 筛选（稀有度 / 近远战 / 来源 / 词条或武器类别下拉框）+ 图标格，
# 点击切换选中；多选时确认后、单选时点击后调用 target.method(选中的 id 数组)。
# opts：
#   title, color      标题与强调色
#   res               候选对象
#   sel               初始选中的 id
#   multi             多选（默认 true）
#   key               对象的 id 字段（默认 "my_id"；按武器系列选择时为 "weapon_id"）
#   filters           ["tier", "type", "src", "tag"] 的子集
#   shown_buttons     显示"选中 / 取消当前全部"
#   reset             [对象, 方法]：显示"重置全部"，选中项改为该方法返回的 id
# 弹窗关闭前本对象由弹窗持有（meta "picker"）。

var ui
var res: Array = []
var sel: Array = []
var multi := true
var key := "my_id"
var f := {"tier": -1, "type": -1, "src": "all", "tag": ""}
var filter := ""
var grid: GridContainer
var modal = null
var target: Object = null
var method := ""
var _count: Label
var _chips: Dictionary = {}
var _reset = null


static func open(p_ui, opts: Dictionary, p_target: Object, p_method: String):
	var p = load("res://mods-unpacked/Mojimoon-BroEditor/ui/object_picker.gd").new()
	p.ui = p_ui
	p.target = p_target
	p.method = p_method
	p._build(opts)
	return p


func _build(opts: Dictionary) -> void:
	res = opts.get("res", [])
	sel = opts.get("sel", []).duplicate()
	multi = opts.get("multi", true)
	key = opts.get("key", "my_id")
	_reset = opts.get("reset")
	var filters: Array = opts.get("filters", [])
	modal = ui.Modal.open(ui, opts.get("title", ""), opts.get("color", ui.C_ACCENT_2), Vector2(1240, 820))
	modal.set_meta("picker", self)
	_count = ui._label("", ui.FONT_SMALL, ui.C_TEXT_DIM)
	modal.head.add_child(_count)
	var box = modal.body
	var search = ui._line_edit(ui.tr("BE_SEARCH"))
	search.connect("text_changed", self, "_on_search")
	box.add_child(search)
	if not filters.empty():
		var frow = HBoxContainer.new()
		frow.add_constant_override("separation", 16)
		box.add_child(frow)
		if "tier" in filters:
			var tiers = [[-1, "BE_FILTER_ALL"]]
			for t in 4:
				tiers.push_back([t, "T" + str(t + 1)])
			_chip_row(frow, "tier", tiers)
		if "type" in filters:
			_chip_row(frow, "type", [[-1, "BE_FILTER_ALL"], [0, "MELEE"], [1, "RANGED"]])
		if "src" in filters:
			_chip_row(frow, "src", ui.SOURCES)
		if "tag" in filters:
			# 道具的词条 / 武器的类别
			var seen = {}
			var tags = []
			for r in res:
				for t in ui._tags_of(r):
					if not seen.has(t[1]):
						seen[t[1]] = true
						tags.push_back(t)
			tags.sort_custom(ui, "_sort_by_first")
			var all_key = "BE_FILTER_ALL_SETS" if not res.empty() and res[0] is WeaponData else "BE_FILTER_ALL_TAGS"
			var tag_sel = ui._search_select([[ui.tr(all_key), ""]] + tags, "")
			tag_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tag_sel.connect("selected", self, "on_chip", ["tag"])
			frow.add_child(tag_sel)
	var scroll = ui._scroll()
	box.add_child(scroll)
	grid = ui._icon_grid(16)
	scroll.add_child(grid)
	var hint = ui._desc(ui.tr("BE_PICKER_MULTI_DESC" if multi else "BE_PICKER_SINGLE_DESC"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal.foot.add_child(hint)
	if opts.get("shown_buttons", false):
		modal.add_button(ui.tr("BE_PICKER_SELECT_SHOWN"), ui.C_ACCENT_3, self, "on_shown", [true])
		modal.add_button(ui.tr("BE_PICKER_DESELECT_SHOWN"), ui.C_TEXT_DIM, self, "on_shown", [false])
	if _reset != null:
		modal.add_button(ui.tr("BE_PICKER_RESET_ALL"), ui.C_DANGER, self, "reset")
	elif multi:
		modal.add_button(ui.tr("BE_PICKER_CLEAR"), ui.C_DANGER, self, "clear")
	modal.add_button(ui.tr("BE_CANCEL"), ui.C_TEXT_DIM, self, "close")
	if multi:
		modal.add_button(ui.tr("BE_CONFIRM"), ui.C_ACCENT_3, self, "confirm")
	fill()
	search.call_deferred("grab_focus")


# 一组筛选按钮
func _chip_row(parent: Control, k: String, defs: Array) -> void:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	parent.add_child(row)
	_chips[k] = []
	for d in defs:
		var b = ui._button(ui.tr(d[1]), ui.FONT_DESC)
		b.rect_min_size = Vector2(56, 0)
		b.connect("pressed", self, "on_chip", [d[0], k])
		row.add_child(b)
		_chips[k].push_back([b, d[0]])
	_style_chips(k)


func _style_chips(k: String) -> void:
	for bv in _chips.get(k, []):
		ui._apply_chip_style(bv[0], bv[1] == f[k], ui.C_ACCENT_2)


func on_chip(value, k: String) -> void:
	f[k] = value
	_style_chips(k)
	fill()


func id_of(r) -> String:
	return str(r.get(key))


func shown(r) -> bool:
	if filter != "" and ui.tr(r.name).to_lower().find(filter) < 0 and r.my_id.find(filter) < 0:
		return false
	if f.src != "all" and ui._source(r) != f.src:
		return false
	if f.tier >= 0 and "tier" in r and r.tier != f.tier:
		return false
	if f.type >= 0 and "type" in r and r.type != f.type:
		return false
	if f.tag != "":
		var found = false
		for t in ui._tags_of(r):
			found = found or t[1] == f.tag
		if not found:
			return false
	return true


func fill() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for r in res:
		if not shown(r):
			continue
		var b = ui._res_button(r)
		var on = id_of(r) in sel
		ui._set_icon_style(b, ui.C_ACCENT_3 if on else ItemService.get_color_from_tier(r.tier).darkened(0.3), 3 if on else 1)
		b.connect("pressed", self, "toggle", [id_of(r)])
		grid.add_child(b)
	_count.text = ui.tr("BE_PICKER_COUNT").replace("{0}", str(sel.size())) if multi else ""


func _on_search(text: String) -> void:
	filter = text.strip_edges().to_lower()
	fill()


func toggle(id: String) -> void:
	if not multi:
		sel = [id]
		confirm()
		return
	if id in sel:
		sel.erase(id)
	else:
		sel.push_back(id)
	fill()


# 选中 / 取消当前筛选出的全部
func on_shown(on: bool) -> void:
	for r in res:
		if not shown(r):
			continue
		var id = id_of(r)
		if on and not id in sel:
			sel.push_back(id)
		elif not on:
			sel.erase(id)
	fill()


func clear() -> void:
	sel = []
	fill()


func reset() -> void:
	sel = _reset[0].call(_reset[1])
	fill()


func confirm() -> void:
	var out = sel.duplicate()
	close()
	if target != null and is_instance_valid(target):
		target.call(method, out)


func close() -> void:
	if modal != null and is_instance_valid(modal):
		modal.close()
	modal = null
