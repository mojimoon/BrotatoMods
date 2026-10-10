extends Reference

# 效果详细信息弹窗（同 BroLab）：编辑效果里的子资源——燃烧数据、投射物 / 爆炸 / 构筑物的武器属性（含属性伤害加成）。
# 修改写入效果 spec 的 "sub"：{字段: {子字段: 值, "scaling_stats": [[属性, 系数]...]}}，由 mod_main.make_effect 应用。
# with_top = true 时同时编辑效果本身的数值（写入 spec 的 "set"；蓝图的"获得效果"节点用）。
# 每次修改后调用 target.method()。

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")

var ui = null
var spec: Dictionary
var with_top := false
var target: Object = null
var method := ""
var modal = null
var _preview: RichTextLabel


static func open(p_ui, p_spec: Dictionary, p_with_top: bool, p_target: Object, p_method: String):
	var d = load("res://mods-unpacked/Mojimoon-BroEditor/ui/effect_detail.gd").new()
	d.ui = p_ui
	d.spec = p_spec
	d.with_top = p_with_top
	d.target = p_target
	d.method = p_method
	d._build()
	return d


# 效果是否有可编辑的详细信息（子资源；with_top 时也算本身的数值）
static func has_details(e, p_with_top: bool = false) -> bool:
	return e != null and (not Catalog.sub_fields(e).empty() or (p_with_top and not Catalog.editable_fields(e).empty()))


func _build() -> void:
	modal = ui.Modal.open(ui, ui.tr("BE_EFFECT_DETAILS"), ui.C_CUSTOM, Vector2(1100, 820))
	# 弹窗关闭前本对象（Reference）由弹窗持有
	modal.set_meta("detail", self)
	var back = ui._button(ui.tr("MENU_BACK"), ui.FONT_SMALL)
	ui._apply_action_style(back, ui.C_TEXT_DIM)
	back.connect("pressed", modal, "close")
	modal.head.add_child(back)
	_preview = ui._rich("")
	modal.body.add_child(_preview)
	var scroll = ui._scroll()
	modal.body.add_child(scroll)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_constant_override("separation", 10)
	scroll.add_child(col)
	var e = ui._mod.make_effect(spec)
	if e == null:
		return
	if with_top and not Catalog.editable_fields(e).empty():
		var box = ui._section(col, "BE_EFFECT_DETAILS_SELF", ui.C_ACCENT)
		var grid = _grid(box)
		for f in Catalog.editable_fields(e):
			_field(grid, f, e.get(f.name), "", "set")
	for f in Catalog.sub_fields(e):
		var r = e.get(f)
		var box = ui._section(col, _field_name(f), ui.C_ACCENT_3)
		var grid = _grid(box)
		for cf in Catalog.sub_child_fields(r):
			_field(grid, cf, r.get(cf.name), f, "sub")
		if "scaling_stats" in r:
			_scaling_editor(box, f, ui._mod.scaling_names(r.scaling_stats))
	_refresh_preview()


func _grid(parent: Control) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_constant_override("hseparation", 12)
	grid.add_constant_override("vseparation", 4)
	parent.add_child(grid)
	return grid


func _field_name(name: String) -> String:
	for k in ["BE_FIELD_" + name.to_upper(), "BE_WS_" + name.to_upper()]:
		if ui.tr(k) != k:
			return ui.tr(k)
	return name


func _field(grid: Control, f: Dictionary, cur, sub: String, where: String) -> void:
	var lbl = ui._label(_field_name(f.name), ui.FONT_DESC, ui.C_TEXT_DIM)
	grid.add_child(lbl)
	match f.type:
		TYPE_INT, TYPE_REAL:
			var sb = ui._spin(-99999, 99999, 1 if f.type == TYPE_INT else 0.01)
			sb.value = cur
			sb.rect_min_size = Vector2(150, 0)
			sb.connect("value_changed", self, "_on_value", [where, sub, f.name, f.type])
			grid.add_child(sb)
		TYPE_BOOL:
			var cb = ui._checkbox("", ui.FONT_DESC)
			cb.pressed = bool(cur)
			cb.connect("toggled", self, "_on_value", [where, sub, f.name, f.type])
			grid.add_child(cb)
		_:
			if Catalog.is_stat_key(str(cur)) or str(cur).begins_with("stat_"):
				var opt = ui._stat_option(str(cur))
				opt.connect("selected", self, "_on_value", [where, sub, f.name, f.type])
				grid.add_child(opt)
			else:
				var le = ui._line_edit("")
				le.text = str(cur)
				le.rect_min_size = Vector2(200, 0)
				le.connect("text_changed", self, "_on_value", [where, sub, f.name, f.type])
				grid.add_child(le)


func _on_value(value, where: String, sub: String, field: String, type: int) -> void:
	if type == TYPE_INT:
		value = int(value)
	elif type == TYPE_REAL:
		value = float(value)
	if where == "set":
		if not spec.has("set") or not spec.set is Dictionary:
			spec["set"] = {}
		spec.set[field] = value
	else:
		_sub(sub)[field] = value
	_notify()


func _sub(field: String) -> Dictionary:
	if not spec.has("sub") or not spec.sub is Dictionary:
		spec["sub"] = {}
	if not spec.sub.has(field) or not spec.sub[field] is Dictionary:
		spec.sub[field] = {}
	return spec.sub[field]


# ---------------- 属性伤害加成（scaling_stats）
var _scaling: Dictionary = {}
var _scaling_boxes: Dictionary = {}


func _scaling_editor(parent: Control, sub: String, rows: Array) -> void:
	_scaling[sub] = rows.duplicate(true)
	parent.add_child(ui._label(ui.tr("BE_SEC_SCALING"), ui.FONT_DESC, ui.C_TEXT_DIM))
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 4)
	parent.add_child(box)
	_scaling_boxes[sub] = box
	_fill_scaling(sub)


func _fill_scaling(sub: String) -> void:
	var box = _scaling_boxes[sub]
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var rows = _scaling[sub]
	for i in rows.size():
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 8)
		box.add_child(row)
		var opt = ui._stat_option(str(rows[i][0]))
		opt.connect("selected", self, "_on_scaling_stat", [sub, i])
		row.add_child(opt)
		var sb = ui._spin(-100, 100, 0.01)
		sb.value = float(rows[i][1])
		sb.rect_min_size = Vector2(150, 0)
		sb.connect("value_changed", self, "_on_scaling_coef", [sub, i])
		row.add_child(sb)
		var del = ui._button("X", ui.FONT_DESC)
		ui._apply_action_style(del, ui.C_DANGER)
		del.connect("pressed", self, "_on_scaling_delete", [sub, i])
		row.add_child(del)
	var add = ui._button(ui.tr("BE_SCALING_ADD"), ui.FONT_SMALL)
	ui._apply_action_style(add, ui.C_ACCENT_3)
	add.connect("pressed", self, "_on_scaling_add", [sub])
	box.add_child(add)


func _store_scaling(sub: String) -> void:
	_sub(sub)["scaling_stats"] = _scaling[sub].duplicate(true)
	_notify()


func _on_scaling_stat(key, sub: String, i: int) -> void:
	_scaling[sub][i][0] = str(key)
	_store_scaling(sub)


func _on_scaling_coef(value: float, sub: String, i: int) -> void:
	_scaling[sub][i][1] = value
	_store_scaling(sub)


func _on_scaling_delete(sub: String, i: int) -> void:
	_scaling[sub].remove(i)
	_store_scaling(sub)
	_fill_scaling(sub)


func _on_scaling_add(sub: String) -> void:
	_scaling[sub].push_back(["stat_max_hp", 0.5])
	_store_scaling(sub)
	_fill_scaling(sub)


func _notify() -> void:
	_refresh_preview()
	if target != null and is_instance_valid(target):
		target.call(method)


func _refresh_preview() -> void:
	var e = ui._mod.make_effect(spec)
	_preview.bbcode_text = ui._mod.effect_text(e) if e != null else ""
