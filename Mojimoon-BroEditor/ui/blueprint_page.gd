extends Reference

# 编辑器的"蓝图"页：原版 GraphEdit 节点图。
#   顶部：添加扳机 / 条件 / 效果节点的下拉菜单、清空；右侧：路径文本预览
#   节点之间拖线连接（扳机 → 条件 → 效果），不检查合法性；节点右上角 X 删除，可拖动、Ctrl+滚轮缩放
# 修改直接写入当前角色档案的 graph 字段。

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const GraphEffect = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
const TYPE_COLORS = {"trigger": Color(1.0, 0.72, 0.30), "cond": Color(0.40, 0.72, 1.0), "effect": Color(0.55, 0.85, 0.55)}
const PORT_TYPE = 0

var ui = null	# 编辑器（样式工具、档案读写）
var ge: GraphEdit
var preview: RichTextLabel
var _picker: Control = null
var _picker_node := -1
var _picker_list: VBoxContainer
var _picker_filter := ""


func build(p_ui, parent: Control) -> void:
	ui = p_ui
	var bar = HBoxContainer.new()
	bar.add_constant_override("separation", 8)
	parent.add_child(bar)
	for t in [["trigger", "BE_ADD_TRIGGER"], ["cond", "BE_ADD_COND"], ["effect", "BE_ADD_EFFECT"]]:
		var items = []
		for d in Catalog.NODES:
			if d[1] == t[0]:
				items.push_back([ui.tr("BE_N_" + d[0].to_upper()), d[0]])
		var mb = ui._search_select(items)
		mb.fixed_text = ui.tr(t[1])
		mb.set_key(null)
		mb.add_font_override("font", ui.FONT_SMALL)
		mb.align = Button.ALIGN_CENTER
		mb.rect_min_size = Vector2(110, 0)
		ui._apply_action_style(mb, TYPE_COLORS[t[0]])
		mb.connect("selected", self, "add_node_kind")
		bar.add_child(mb)
	var clear = ui._button(ui.tr("BE_GRAPH_CLEAR"), ui.FONT_SMALL)
	ui._apply_action_style(clear, ui.C_DANGER)
	clear.connect("pressed", self, "_on_clear")
	bar.add_child(clear)
	bar.add_child(ui._desc(ui.tr("BE_GRAPH_DESC")))

	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 10)
	parent.add_child(cols)
	ge = GraphEdit.new()
	ge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ge.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ge.right_disconnects = true
	# 原版自带的缩放 / 吸附工具条图标在本主题下显示异常：隐藏（Ctrl + 滚轮仍可缩放）
	ge.get_zoom_hbox().visible = false
	ge.minimap_enabled = false
	ge.add_stylebox_override("bg", ui._style(Color(0.05, 0.06, 0.08), ui.C_BORDER, 8, 1, 0, 0))
	ge.add_color_override("grid_major", Color(1, 1, 1, 0.07))
	ge.add_color_override("grid_minor", Color(1, 1, 1, 0.03))
	ge.add_valid_connection_type(PORT_TYPE, PORT_TYPE)
	ge.connect("connection_request", self, "_on_connect")
	ge.connect("disconnection_request", self, "_on_disconnect")
	ge.connect("delete_nodes_request", self, "_on_delete_selected")
	cols.add_child(ge)

	var card = ui._card(cols)
	card.size_flags_horizontal = 0
	card.rect_min_size = Vector2(430, 0)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(ui._label(ui.tr("BE_GRAPH_PATHS"), ui.FONT_NORMAL, ui.C_ACCENT))
	var scroll = ui._scroll()
	box.add_child(scroll)
	preview = RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.fit_content_height = true
	preview.scroll_active = false
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_font_override("normal_font", ui.FONT_DESC)
	preview.add_color_override("default_color", ui.C_TEXT)
	scroll.add_child(preview)
	rebuild()


# 当前角色的图（只读 / 编辑）
func _graph() -> Dictionary:
	var v = ui._view()
	return v.graph if v.graph is Dictionary else GraphEffect.new_graph()


func _edit_graph() -> Dictionary:
	var p = ui._p()
	if not p.graph is Dictionary:
		p.graph = GraphEffect.new_graph()
	return p.graph


func _changed() -> void:
	ui._changed()
	_refresh_preview()


func _refresh_preview() -> void:
	var t = GraphEffect.graph_text(_graph())
	preview.bbcode_text = t if t != "" else "[color=#" + ui.C_TEXT_DIM.to_html(false) + "]" + ui.tr("BE_GRAPH_EMPTY") + "[/color]"


# ============================================================
# 节点
# ============================================================
func rebuild() -> void:
	ge.clear_connections()
	for c in ge.get_children():
		if c is GraphNode:
			ge.remove_child(c)
			c.queue_free()
	var g = _graph()
	for n in g.nodes:
		ge.add_child(_make_node(n))
	for l in g.links:
		ge.connect_node("n" + str(l[0]), 0, "n" + str(l[1]), 0)
	_refresh_preview()


func _make_node(n: Dictionary) -> GraphNode:
	var t = Catalog.node_type(n.kind)
	var color = TYPE_COLORS.get(t, ui.C_TEXT)
	var gn = GraphNode.new()
	gn.name = "n" + str(n.id)
	gn.title = ui.tr("BE_N_" + n.kind.to_upper())
	gn.show_close = true
	gn.resizable = false
	gn.rect_min_size = Vector2(240, 0)
	var pos = n.get("pos", [0, 0])
	gn.offset = Vector2(float(pos[0]), float(pos[1]))
	gn.add_stylebox_override("frame", ui._style(ui.C_BG_CARD, color.darkened(0.3), 8, 2, 12, 30))
	gn.add_stylebox_override("selectedframe", ui._style(ui.C_BG_CARD, color, 8, 3, 12, 30))
	gn.add_font_override("title_font", ui.FONT_SMALL)
	gn.add_color_override("title_color", color)
	gn.add_constant_override("separation", 4)
	gn.connect("close_request", self, "_on_close_node", [int(n.id)])
	gn.connect("dragged", self, "_on_dragged", [int(n.id)])
	var head = ui._label(ui.tr("BE_TYPE_" + t.to_upper()), ui.FONT_DESC, ui.C_TEXT_DIM)
	gn.add_child(head)
	gn.set_slot(0, t != "trigger", PORT_TYPE, color, t != "effect", PORT_TYPE, color)
	var d = Catalog.node_def(n.kind)
	for p in d[2]:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 6)
		gn.add_child(row)
		var lbl = ui._label(ui.tr("BE_P_" + p[0].to_upper()), ui.FONT_DESC, ui.C_TEXT_DIM)
		lbl.rect_min_size = Vector2(70, 0)
		row.add_child(lbl)
		row.add_child(_param_control(n, p))
	return gn


func _param_control(n: Dictionary, p: Array) -> Control:
	var cur = n.params.get(p[0], p[2])
	var ptype: String = p[1]
	if ptype == "int":
		var sb = ui._spin(-99999, 99999, 1)
		sb.value = int(cur)
		sb.rect_min_size = Vector2(130, 0)
		sb.connect("value_changed", self, "_on_param", [int(n.id), p[0]])
		return sb
	if ptype == "stat":
		var opt = ui._stat_option(str(cur))
		opt.rect_min_size = Vector2(170, 0)
		opt.connect("selected", self, "_on_param_option", [int(n.id), p[0]])
		return opt
	if ptype.begins_with("mode:"):
		var items = []
		for m in ptype.substr(5).split("|"):
			items.push_back([ui.tr("BE_MODE_" + m.to_upper()), m])
		var opt = ui._search_select(items, str(cur))
		opt.connect("selected", self, "_on_param_option", [int(n.id), p[0]])
		return opt
	# effect：效果库引用
	var b = ui._button("", ui.FONT_DESC)
	b.text = ui._strip(GraphEffect._grant_text({"kind": "grant", "params": {"ref": cur, "n": 1}}, false)) if cur is Dictionary else ui.tr("BE_GRANT_PICK")
	b.clip_text = true
	b.rect_min_size = Vector2(200, 0)
	ui._apply_action_style(b, TYPE_COLORS.effect)
	b.connect("pressed", self, "_open_effect_picker", [int(n.id)])
	return b


func _find(g: Dictionary, id: int):
	for n in g.nodes:
		if int(n.id) == id:
			return n
	return null


func add_node_kind(kind: String) -> void:
	var g = _edit_graph()
	# 新节点放在可见区域中间，按类型错开
	var center = (ge.scroll_offset + ge.rect_size / 2.0) / ge.zoom
	var dx = {"trigger": -320, "cond": 0, "effect": 320}.get(Catalog.node_type(kind), 0)
	var id = GraphEffect.add_node(g, kind, center + Vector2(dx - 120, -60 + (g.nodes.size() % 5) * 24))
	ge.add_child(_make_node(_find(g, id)))
	_changed()


func _on_connect(from: String, _from_port: int, to: String, _to_port: int) -> void:
	if from == to:
		return
	GraphEffect.add_link(_edit_graph(), int(from.substr(1)), int(to.substr(1)))
	ge.connect_node(from, 0, to, 0)
	_changed()


func _on_disconnect(from: String, _from_port: int, to: String, _to_port: int) -> void:
	var g = _edit_graph()
	var a = int(from.substr(1))
	var b = int(to.substr(1))
	var links = []
	for l in g.links:
		if not (int(l[0]) == a and int(l[1]) == b):
			links.push_back(l)
	g.links = links
	ge.disconnect_node(from, 0, to, 0)
	_changed()


func _on_close_node(id: int) -> void:
	GraphEffect.remove_node(_edit_graph(), id)
	rebuild()
	_changed()


func _on_delete_selected() -> void:
	var g = _edit_graph()
	for c in ge.get_children():
		if c is GraphNode and c.selected:
			GraphEffect.remove_node(g, int(c.name.substr(1)))
	rebuild()
	_changed()


func _on_dragged(_from: Vector2, to: Vector2, id: int) -> void:
	var n = _find(_edit_graph(), id)
	if n != null:
		n.pos = [to.x, to.y]
		ui._changed()


func _on_param(value, id: int, key: String) -> void:
	var n = _find(_edit_graph(), id)
	if n != null:
		n.params[key] = int(value)
		_changed()


func _on_param_option(value, id: int, key: String) -> void:
	var n = _find(_edit_graph(), id)
	if n != null:
		n.params[key] = value
		_changed()


func _on_clear() -> void:
	ui._p().graph = null
	rebuild()
	_changed()


# ============================================================
# "获得效果"节点：从效果库选择
# ============================================================
func _open_effect_picker(id: int) -> void:
	_picker_node = id
	_picker_filter = ""
	_picker = Control.new()
	_picker.set_anchors_preset(Control.PRESET_WIDE)
	ui.add_child(_picker)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_WIDE)
	_picker.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_WIDE)
	_picker.add_child(center)
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(1000, 800)
	panel.add_stylebox_override("panel", ui._style(ui.C_BG_PANEL, TYPE_COLORS.effect, 12, 2, 18, 14))
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	panel.add_child(box)
	var head = HBoxContainer.new()
	box.add_child(head)
	var title = ui._label(ui.tr("BE_GRANT_PICK"), ui.FONT_NORMAL, TYPE_COLORS.effect)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var cancel = ui._button(ui.tr("BE_CANCEL"), ui.FONT_SMALL)
	ui._apply_action_style(cancel, ui.C_TEXT_DIM)
	cancel.connect("pressed", self, "close_picker")
	head.add_child(cancel)
	var search = ui._line_edit(ui.tr("BE_LIBRARY_SEARCH"))
	search.connect("text_changed", self, "_on_picker_search")
	box.add_child(search)
	var scroll = ui._scroll()
	box.add_child(scroll)
	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_picker_list)
	_fill_picker()
	search.call_deferred("grab_focus")


func _fill_picker() -> void:
	for c in _picker_list.get_children():
		_picker_list.remove_child(c)
		c.queue_free()
	var shown = 0
	for entry in ui._mod.library():
		var text = ui._mod.effect_text(entry.effect)
		if text == "":
			continue
		if _picker_filter != "" and (ui._strip(text) + " " + ui.tr(entry.src) + " " + str(entry.effect.key)).to_lower().find(_picker_filter) < 0:
			continue
		shown += 1
		if shown > ui.LIBRARY_LIMIT:
			break
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 6)
		_picker_list.add_child(row)
		var pick = ui._button(ui.tr("BE_PICK"), ui.FONT_DESC)
		ui._apply_action_style(pick, TYPE_COLORS.effect)
		pick.connect("pressed", self, "_on_picked", [{"from": entry.from, "i": entry.i}])
		row.add_child(pick)
		row.add_child(ui._rich(text))
		var src = ui._label(ui.tr(entry.src), ui.FONT_DESC, ui.C_TEXT_DIM)
		src.rect_min_size = Vector2(120, 0)
		src.clip_text = true
		row.add_child(src)


func _on_picker_search(text: String) -> void:
	_picker_filter = text.strip_edges().to_lower()
	_fill_picker()


func _on_picked(ref: Dictionary) -> void:
	var n = _find(_edit_graph(), _picker_node)
	if n != null:
		n.params["ref"] = ref
	close_picker()
	rebuild()
	_changed()


func close_picker() -> bool:
	if _picker == null or not is_instance_valid(_picker):
		return false
	_picker.queue_free()
	_picker = null
	return true
