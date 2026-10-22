extends VBoxContainer

# 分享站（编辑器第四栏）：服务端是 mods/tools/broeditor-cloud 的 Cloudflare Worker。
#   浏览 / 已下载：两栏卡片；查看（详情、复制 ID、包内对象）、下载；已下载的包可卸载、管理
#   管理：左栏列出包内对象，右栏启用 / 停用、在同 id 对象的各版本（原版、自修改、各数据包）间预览与切换
#   上传：左栏只列自修改层的对象（依赖由 bundle_data 带上）；我的上传：本机上传的包（删除令牌存 UPLOADS_PATH）
# 数据见 mod_main 的"数据包与版本"。test_responses：测试用，"方法 路径" -> [状态码, 正文]，有值时不发网络请求

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")
const Modal = preload("res://mods-unpacked/Mojimoon-BroEditor/ui/modal.gd")
const API = "https://broeditor-6myuzuteg3xe5jtk.mojimoon.top"
const UPLOADS_PATH = "user://Mojimoon-BroEditor/uploads.json"
const THUMB_SIZE = 256
const THUMB_SHOW = 96
const LEFT_COLUMNS = 5
# 与 worker.js 的 MAX 一致
const MAX_TITLE = 60
const MAX_AUTHOR = 40
const MAX_DESC = 500
const MAX_CODE = 512 * 1024
const PAGES = ["browse", "installed", "upload", "mine"]

var ui = null
var test_responses = null
var _mod = null
var _page := "browse"
var _tab_btns := {}
var _content: VBoxContainer
var _status: Label
# 浏览
var _q := ""
var _kind := ""
var _sort := "new"
var _packs := []
var _more := false
var _busy := false
var _grid: GridContainer
var _thumbs := {}	# 包 id -> 纹理
# 左栏（上传 / 管理共用）
var _left := {"kind": "character", "q": ""}
var _left_units := []
var _left_grid: GridContainer
# 管理
var _pid := ""
var _unit := []
var _preview_src := ""
var _right: VBoxContainer
# 上传
var _sel := []	# [[种类, id]...]
var _thumb: Image = null
var _title := ""
var _desc := ""
var _deps: Label
var _preview: TextureRect
var _uploads := {"author": "", "packs": []}


func setup(p_ui) -> void:
	ui = p_ui
	_mod = ui._mod
	test_responses = ui.test_cloud
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_constant_override("separation", 8)
	_load_uploads()
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	add_child(row)
	for t in PAGES:
		var b = ui._button(ui.tr("BE_CLOUD_TAB_" + t), ui.FONT_SMALL)
		b.rect_min_size = Vector2(150, 0)
		b.connect("pressed", self, "set_page", [t])
		row.add_child(b)
		_tab_btns[t] = b
	_status = ui._label("", ui.FONT_DESC, ui.C_TEXT_DIM)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.align = Label.ALIGN_RIGHT
	_status.clip_text = true
	row.add_child(_status)
	_content = VBoxContainer.new()
	_content.size_flags_vertical = SIZE_EXPAND_FILL
	_content.add_constant_override("separation", 8)
	add_child(_content)
	set_page("browse")


func set_page(t: String) -> void:
	ui._commit_focus()
	_page = t
	for k in _tab_btns:
		ui._apply_chip_style(_tab_btns[k], k == t or k == "installed" and t == "manage", ui.C_CUSTOM)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	call("_build_" + t)


# 重新显示当前页（编辑器切回本栏时、数据变化后）
func refresh() -> void:
	set_page(_page)


func set_status(text: String) -> void:
	_status.text = text


# ============================================================
# 网络
# ============================================================
func _request(path: String, method: int, body: String, headers: Array, cb: String, binds: Array = []) -> void:
	if test_responses != null:
		var r = test_responses.get(_method_name(method) + " " + path, [404, ""])
		callv(cb, [r[0], str(r[1]).to_utf8()] + binds)
		return
	var h = HTTPRequest.new()
	h.timeout = 30
	add_child(h)
	h.connect("request_completed", self, "_on_request_done", [h, cb, binds])
	if h.request(API + path, PoolStringArray(headers + ["User-Agent: BroEditor/" + _mod_version()]), true, method, body) != OK:
		h.queue_free()
		callv(cb, [-1, PoolByteArray()] + binds)


static func _method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
	return "GET"


func _on_request_done(result: int, code: int, _headers, body: PoolByteArray, h: Node, cb: String, binds: Array) -> void:
	h.queue_free()
	callv(cb, [code if result == HTTPRequest.RESULT_SUCCESS else -1, body] + binds)


static func _json(body: PoolByteArray):
	var parsed = JSON.parse(body.get_string_from_utf8())
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}


func _net_error(code: int) -> void:
	set_status(ui.tr("BE_CLOUD_NET_ERROR").replace("{0}", str(code)))


static func _mod_version() -> String:
	var file = File.new()
	if file.open(BEMain.MOD_DIR + "manifest.json", File.READ) != OK:
		return ""
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return str(parsed.result.get("version_number", "")) if parsed.error == OK and parsed.result is Dictionary else ""


# ============================================================
# 浏览 / 已下载
# ============================================================
func _build_browse() -> void:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	_content.add_child(row)
	var le = ui._line_edit(ui.tr("BE_SEARCH"))
	le.text = _q
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	le.connect("text_entered", self, "_on_search")
	row.add_child(le)
	for k in ["", "character", "item", "weapon"]:
		var b = ui._button(ui.tr("BE_FILTER_ALL" if k == "" else "BE_KIND_" + k.to_upper()), ui.FONT_DESC)
		ui._apply_chip_style(b, k == _kind, ui.C_ACCENT)
		b.connect("pressed", self, "_on_browse_filter", ["kind", k])
		row.add_child(b)
	for s in ["new", "hot"]:
		var b = ui._button(ui.tr("BE_CLOUD_SORT_" + s), ui.FONT_DESC)
		ui._apply_chip_style(b, s == _sort, ui.C_ACCENT_3)
		b.connect("pressed", self, "_on_browse_filter", ["sort", s])
		row.add_child(b)
	var refresh = ui._button(ui.tr("BE_CLOUD_REFRESH"), ui.FONT_DESC)
	ui._apply_action_style(refresh, ui.C_ACCENT_2)
	refresh.connect("pressed", self, "fetch", [0])
	row.add_child(refresh)
	_grid = _card_grid()
	_fill_browse()
	if _packs.empty() and not _busy:
		fetch(0)


func _card_grid() -> GridContainer:
	var sc = ui._scroll()
	_content.add_child(sc)
	var g = GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = SIZE_EXPAND_FILL
	g.add_constant_override("hseparation", 8)
	g.add_constant_override("vseparation", 8)
	sc.add_child(g)
	return g


func _on_search(text: String) -> void:
	_q = text.strip_edges()
	fetch(0)


func _on_browse_filter(key: String, value: String) -> void:
	set("_" + key, value)
	_packs = []
	set_page("browse")


func fetch(offset: int) -> void:
	if _busy:
		return
	_busy = true
	set_status(ui.tr("BE_CLOUD_LOADING"))
	var path = "/packs?kind=%s&q=%s&sort=%s&offset=%d" % [_kind, _q.percent_encode(), _sort, offset]
	_request(path, HTTPClient.METHOD_GET, "", [], "_on_list", [offset])


func _on_list(code: int, body: PoolByteArray, offset: int) -> void:
	_busy = false
	if code != 200:
		_net_error(code)
		return
	var r = _json(body)
	if offset == 0:
		_packs = []
	for p in r.get("packs", []):
		if p is Dictionary:
			_packs.push_back(p)
	_more = bool(r.get("more", false))
	set_status("")
	if _page == "browse" and is_instance_valid(_grid):
		_fill_browse()


func _fill_browse() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if _packs.empty() and not _busy:
		_grid.add_child(ui._desc(ui.tr("BE_CLOUD_EMPTY")))
	for p in _packs:
		_pack_card(_grid, p)
	if _more:
		var b = ui._button(ui.tr("BE_CLOUD_MORE"), ui.FONT_SMALL)
		ui._apply_action_style(b, ui.C_ACCENT_2)
		b.connect("pressed", self, "fetch", [_packs.size()])
		_grid.add_child(b)


func _build_installed() -> void:
	_grid = _card_grid()
	var ids = _mod.pack_ids()
	ids.invert()
	if ids.empty():
		_grid.add_child(ui._desc(ui.tr("BE_CLOUD_EMPTY")))
	for pid in ids:
		_pack_card(_grid, _mod.packs[pid].meta)


func _pack_card(parent: Control, p: Dictionary) -> void:
	var id = str(p.get("id", ""))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	ui._card(parent).add_child(row)
	row.add_child(_thumb_rect(p, THUMB_SHOW))
	var col = VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_constant_override("separation", 2)
	row.add_child(col)
	var title = ui._label(str(p.get("title", "")), ui.FONT_NORMAL, ui.C_TEXT)
	title.clip_text = true
	col.add_child(title)
	var info = ui._label(_info(p), ui.FONT_DESC, ui.C_ACCENT_2)
	info.clip_text = true
	col.add_child(info)
	if str(p.get("contents", "")) != "":
		var contents = ui._label(str(p.contents), ui.FONT_DESC, ui.C_CUSTOM)
		contents.clip_text = true
		col.add_child(contents)
	if str(p.get("desc", "")) != "":
		var d = ui._desc(str(p.desc))
		d.add_color_override("font_color", ui.C_TEXT)
		d.max_lines_visible = 2
		col.add_child(d)
	var btns = VBoxContainer.new()
	btns.add_constant_override("separation", 6)
	btns.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(btns)
	_card_button(btns, "BE_CLOUD_VIEW", ui.C_ACCENT_2, "open_view", [p])
	if _mod.packs.has(id):
		_card_button(btns, "BE_CLOUD_MANAGE", ui.C_ACCENT, "open_manage", [id])
		_card_button(btns, "BE_CLOUD_UNINSTALL", ui.C_DANGER, "_on_uninstall_ask", [id])
	else:
		_card_button(btns, "BE_CLOUD_DOWNLOAD", ui.C_ACCENT_3, "download", [p])


func _card_button(parent: Control, key: String, accent: Color, method: String, args: Array) -> Button:
	var b = ui._button(ui.tr(key), ui.FONT_DESC)
	b.rect_min_size = Vector2(110, 0)
	ui._apply_action_style(b, accent)
	b.connect("pressed", self, method, args)
	parent.add_child(b)
	return b


func _info(p: Dictionary) -> String:
	var info = []
	if str(p.get("author", "")) != "":
		info.push_back(str(p.author))
	info.push_back(_date(p.get("created", 0)))
	info.push_back(ui.tr("BE_CLOUD_DOWNLOADS").replace("{0}", str(int(p.get("downloads", 0)))))
	var kinds = []
	for k in str(p.get("kinds", "")).split(",", false):
		kinds.push_back(ui.tr("BE_KIND_" + k.to_upper()))
	if not kinds.empty():
		info.push_back(PoolStringArray(kinds).join(" / "))
	return PoolStringArray(info).join("  ·  ")


static func _date(ms) -> String:
	var d = OS.get_datetime_from_unix_time(int(float(ms) / 1000))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _thumb_rect(p: Dictionary, size: int) -> TextureRect:
	var img = TextureRect.new()
	img.rect_min_size = Vector2(size, size)
	img.expand = true
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var id = str(p.get("id", ""))
	var path = BEMain.PACK_DIR + id + ".png"
	if not _thumbs.has(id) and File.new().file_exists(path):
		var image = Image.new()
		if image.load(path) == OK:
			_thumbs[id] = _texture(image)
	if _thumbs.has(id):
		img.texture = _thumbs[id]
	elif int(p.get("thumb", 0)):
		_request("/packs/" + id + "/thumb", HTTPClient.METHOD_GET, "", [], "_on_thumb", [id, img])
	return img


static func _texture(image: Image) -> ImageTexture:
	var tex = ImageTexture.new()
	tex.create_from_image(image)
	return tex


func _on_thumb(code: int, body: PoolByteArray, id: String, img: TextureRect) -> void:
	var image = Image.new()
	if code != 200 or image.load_png_from_buffer(body) != OK:
		return
	_thumbs[id] = _texture(image)
	if is_instance_valid(img):
		img.texture = _thumbs[id]


func download(p: Dictionary) -> void:
	set_status(ui.tr("BE_CLOUD_LOADING"))
	_request("/packs/" + str(p.id), HTTPClient.METHOD_GET, "", [], "_on_code", [p])


func _on_code(code: int, body: PoolByteArray, p: Dictionary) -> void:
	if code != 200:
		_net_error(code)
		return
	var n = _mod.install_pack(p, body.get_string_from_utf8())
	if n < 0:
		set_status(ui.tr("BE_CLOUD_IMPORT_FAILED"))
		return
	var id = str(p.id)
	if _thumbs.has(id) and _thumbs[id].get_data() != null:
		_thumbs[id].get_data().save_png(BEMain.PACK_DIR + id + ".png")
	set_status(ui.tr("BE_CLOUD_INSTALLED").replace("{0}", str(p.get("title", ""))).replace("{1}", str(n)))
	refresh()


func _on_uninstall_ask(pid: String) -> void:
	Modal.confirm(ui, [ui.tr("BE_CLOUD_UNINSTALL_CONFIRM").replace("{0}", _pack_title(pid))], ui.C_DANGER, self, "uninstall", [pid])


func uninstall(pid: String) -> void:
	var title = _pack_title(pid)
	_mod.uninstall_pack(pid)
	Directory.new().remove(BEMain.PACK_DIR + pid + ".png")
	set_status(ui.tr("BE_CLOUD_UNINSTALLED").replace("{0}", title))
	set_page("installed" if _page == "manage" else _page)


func _pack_title(pid: String) -> String:
	return str(_mod.packs[pid].meta.get("title", pid)) if _mod.packs.has(pid) else pid


# ============================================================
# 查看（弹窗）
# ============================================================
func open_view(p: Dictionary):
	var id = str(p.get("id", ""))
	var m = Modal.open(ui, str(p.get("title", "")), ui.C_ACCENT_2, Vector2(1100, 0))
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 14)
	m.body.add_child(top)
	top.add_child(_thumb_rect(p, 128))
	var col = VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(col)
	var id_row = HBoxContainer.new()
	id_row.add_constant_override("separation", 10)
	col.add_child(id_row)
	id_row.add_child(ui._label("ID  " + id, ui.FONT_SMALL, ui.C_TEXT))
	var copy = ui._button(ui.tr("BE_CLOUD_COPY_ID"), ui.FONT_DESC)
	ui._apply_action_style(copy, ui.C_ACCENT_2)
	copy.connect("pressed", self, "_on_copy_id", [id])
	id_row.add_child(copy)
	col.add_child(ui._label(_info(p) + ("  ·  v" + str(p.mod_ver) if str(p.get("mod_ver", "")) != "" else ""), ui.FONT_DESC, ui.C_ACCENT_2))
	if str(p.get("desc", "")) != "":
		var d = ui._desc(str(p.desc))
		d.add_color_override("font_color", ui.C_TEXT)
		col.add_child(d)
	var sc = ui._scroll()
	sc.rect_min_size = Vector2(0, 460)
	m.body.add_child(sc)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_constant_override("separation", 6)
	sc.add_child(list)
	if _mod.packs.has(id):
		_fill_contents(list, _mod.packs[id].data)
		m.add_button(ui.tr("BE_CLOUD_MANAGE"), ui.C_ACCENT, self, "_view_action", [m, "open_manage", id])
		m.add_button(ui.tr("BE_CLOUD_UNINSTALL"), ui.C_DANGER, self, "_view_action", [m, "_on_uninstall_ask", id])
	else:
		list.add_child(ui._desc(ui.tr("BE_CLOUD_LOADING")))
		_request("/packs/" + id + "?peek", HTTPClient.METHOD_GET, "", [], "_on_peek", [list])
		m.add_button(ui.tr("BE_CLOUD_DOWNLOAD"), ui.C_ACCENT_3, self, "_view_action", [m, "download", p])
	m.add_button(ui.tr("MENU_BACK"), ui.C_TEXT_DIM, m, "close")
	return m


func _view_action(m, method: String, arg) -> void:
	m.close()
	call(method, arg)


func _on_copy_id(id: String) -> void:
	ui._clipboard_set(id)
	set_status(ui.tr("BE_CLOUD_ID_COPIED"))


func _on_peek(code: int, body: PoolByteArray, list: Control) -> void:
	if not is_instance_valid(list):
		return
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var raw = _mod.pack_code_data(body.get_string_from_utf8()) if code == 200 else null
	if raw == null:
		list.add_child(ui._desc(ui.tr("BE_CLOUD_IMPORT_FAILED") if code == 200 else ui.tr("BE_CLOUD_NET_ERROR").replace("{0}", str(code))))
		return
	_fill_contents(list, BEMain.normalize_layer(raw))


# 包内对象：按种类列出图标与名称，再列套装 / 标签
func _fill_contents(list: Control, l: Dictionary) -> void:
	for kind in BEMain.KINDS:
		var units = _mod.layer_units(l, [kind])
		if units.empty():
			continue
		list.add_child(ui._label(ui.tr("BE_KIND_" + kind.to_upper()) + "  " + str(units.size()), ui.FONT_SMALL, ui.C_ACCENT_2))
		var g = GridContainer.new()
		g.columns = 3
		g.add_constant_override("hseparation", 16)
		list.add_child(g)
		for u in units:
			var v = _mod.unit_value(l, u[0], u[1])
			var cell = HBoxContainer.new()
			cell.rect_min_size = Vector2(320, 0)
			cell.add_constant_override("separation", 6)
			g.add_child(cell)
			cell.add_child(ui._icon_tile(_mod.unit_icon(u[0], u[1], v), ui.C_BORDER, 40))
			var name = ui._label(_mod.unit_name(u[0], u[1], v), ui.FONT_DESC, ui.C_CUSTOM if _mod._unit_look(u[0], v).custom else ui.C_TEXT)
			name.size_flags_horizontal = SIZE_EXPAND_FILL
			name.clip_text = true
			cell.add_child(name)
	var extra = [["BE_SEC_WEAPON_SETS", l.sets], ["BE_SEC_ITEM_TAGS", l.tags]]
	for e in extra:
		if e[1].empty():
			continue
		var names = []
		for k in e[1]:
			names.push_back(e[1][k].name if e[1][k] is Dictionary and e[1][k].name != "" else (str(e[1][k]) if e[1][k] is String else k))
		list.add_child(ui._label(ui.tr(e[0]) + "：" + PoolStringArray(names).join("、"), ui.FONT_DESC, ui.C_TEXT_DIM))


# ============================================================
# 左栏（上传 / 管理）：种类筛选 + 搜索 + 图标格
# ============================================================
func _left_panel(parent: Control, units: Array) -> void:
	var card = ui._card(parent)
	card.size_flags_horizontal = 0
	card.rect_min_size = Vector2(ui.LEFT_WIDTH, 0)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	card.add_child(box)
	_left_units = units
	var chips = GridContainer.new()
	chips.columns = 3
	chips.add_constant_override("hseparation", 6)
	box.add_child(chips)
	for k in BEMain.KINDS:
		var n = 0
		for u in units:
			n += int(u[0] == k)
		var b = ui._button(ui.tr("BE_KIND_" + k.to_upper()) + " " + str(n), ui.FONT_DESC)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		ui._apply_chip_style(b, _left.kind == k, ui._kind_tabs[k][2])
		b.connect("pressed", self, "_on_left_kind", [k])
		chips.add_child(b)
	var le = ui._line_edit(ui.tr("BE_SEARCH"))
	le.text = _left.q
	le.connect("text_changed", self, "_on_left_search")
	box.add_child(le)
	var sc = ui._scroll()
	box.add_child(sc)
	_left_grid = GridContainer.new()
	_left_grid.columns = LEFT_COLUMNS
	_left_grid.add_constant_override("hseparation", 6)
	_left_grid.add_constant_override("vseparation", 6)
	sc.add_child(_left_grid)
	if _page == "upload":
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 8)
		box.add_child(row)
		for q in ["all", "none"]:
			var b = ui._button(ui.tr("BE_CLOUD_PICK_" + q.to_upper()), ui.FONT_SMALL)
			b.size_flags_horizontal = SIZE_EXPAND_FILL
			ui._apply_action_style(b, ui.C_ACCENT)
			b.connect("pressed", self, "pick", [q])
			row.add_child(b)
	_fill_left_grid()


func _left_layer() -> Dictionary:
	return _mod.packs[_pid].data if _page == "manage" else _mod.own


# 左栏当前种类、匹配搜索的对象
func _left_shown() -> Array:
	var out = []
	var q = _left.q.strip_edges().to_lower()
	for u in _left_units:
		if u[0] != _left.kind:
			continue
		if q != "" and u[1].find(q) < 0 and _mod.unit_name(u[0], u[1], _mod.unit_value(_left_layer(), u[0], u[1])).to_lower().find(q) < 0:
			continue
		out.push_back(u)
	return out


func _fill_left_grid() -> void:
	if not is_instance_valid(_left_grid):
		return
	for c in _left_grid.get_children():
		_left_grid.remove_child(c)
		c.queue_free()
	var l = _left_layer()
	for u in _left_shown():
		var v = _mod.unit_value(l, u[0], u[1])
		var b = ui._icon_button(_mod.unit_icon(u[0], u[1], v), ui.CHAR_ICON)
		b.connect("pressed", self, "_on_left_pressed", [u])
		b.connect("mouse_entered", self, "_on_left_hover", [b, u])
		b.connect("mouse_exited", ui, "_hide_preview")
		b.connect("tree_exiting", ui, "_hide_preview")
		_left_grid.add_child(b)
		var color = ui.C_CUSTOM if _mod._unit_look(u[0], v).custom else ui.C_BORDER
		var w = 1
		if _page == "manage":
			if _mod.unit_source(u[0], u[1]) == _pid:
				color = ui.C_ACCENT_3
				w = 2
			else:
				b.modulate = Color(1, 1, 1, 0.4)
			if u == _unit:
				color = ui.C_ACCENT
				w = 3
		elif u in _sel:
			color = ui.C_ACCENT_3
			w = 3
		ui._set_icon_style(b, color, w)


# 悬停预览：原版物品框，显示左栏这一版（管理 = 数据包版本，上传 = 自修改版）
func _on_left_hover(b: Control, u: Array) -> void:
	ui._show_preview(b, _mod.preview_res(u[0], u[1], _mod.unit_value(_left_layer(), u[0], u[1])))


func _on_left_kind(k: String) -> void:
	_left.kind = k
	refresh()


func _on_left_search(text: String) -> void:
	_left.q = text
	_fill_left_grid()


func _on_left_pressed(u: Array) -> void:
	if _page == "manage":
		select_unit(u)
		return
	if u in _sel:
		_sel.erase(u)
	else:
		_sel.push_back(u)
	_fill_left_grid()
	_refresh_deps()
	_refresh_preview()


# ============================================================
# 管理
# ============================================================
func open_manage(pid: String) -> void:
	if not _mod.packs.has(pid):
		return
	_pid = pid
	_unit = []
	# 包里没有左栏当前种类的对象：换到第一个对象的种类
	var units = _mod.layer_units(_mod.packs[pid].data)
	var has = false
	for u in units:
		has = has or u[0] == _left.kind
	if not has and not units.empty():
		_left.kind = units[0][0]
	set_page("manage")


func _build_manage() -> void:
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	_content.add_child(head)
	var back = ui._button(ui.tr("MENU_BACK"), ui.FONT_SMALL)
	ui._apply_action_style(back, ui.C_TEXT_DIM)
	back.connect("pressed", self, "set_page", ["installed"])
	head.add_child(back)
	var title = ui._label(_pack_title(_pid), ui.FONT_NORMAL, ui.C_ACCENT)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	for d in [["BE_CLOUD_ENABLE_ALL", ui.C_ACCENT_3, true], ["BE_CLOUD_DISABLE_ALL", ui.C_TEXT_DIM, false]]:
		var b = ui._button(ui.tr(d[0]), ui.FONT_SMALL)
		ui._apply_action_style(b, d[1])
		b.connect("pressed", self, "set_all", [d[2]])
		head.add_child(b)
	# 左栏当前种类的全部对象
	var kind_name = ui.tr("BE_KIND_" + _left.kind.to_upper())
	for d in [["BE_CLOUD_ENABLE_KIND", ui.C_ACCENT_3, true], ["BE_CLOUD_DISABLE_KIND", ui.C_TEXT_DIM, false]]:
		var b = ui._button(ui.tr(d[0]).replace("{0}", kind_name), ui.FONT_SMALL)
		ui._apply_action_style(b, d[1])
		b.connect("pressed", self, "set_kind_enabled", [d[2]])
		head.add_child(b)
	var un = ui._button(ui.tr("BE_CLOUD_UNINSTALL"), ui.FONT_SMALL)
	ui._apply_action_style(un, ui.C_DANGER)
	un.connect("pressed", self, "_on_uninstall_ask", [_pid])
	head.add_child(un)
	var body = HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_constant_override("separation", 12)
	_content.add_child(body)
	var units = _mod.layer_units(_mod.packs[_pid].data)
	# 选中对象：保留之前的（须是左栏当前种类），否则本种类第一个
	if not (_unit in units and _unit[0] == _left.kind):
		_unit = []
		for u in units:
			if u[0] == _left.kind:
				_unit = u
				break
	_preview_src = _mod.unit_source(_unit[0], _unit[1]) if not _unit.empty() else ""
	_left_panel(body, units)
	var card = ui._card(body)
	card.size_flags_vertical = SIZE_EXPAND_FILL
	_right = VBoxContainer.new()
	_right.add_constant_override("separation", 10)
	card.add_child(_right)
	_fill_manage_right()


func select_unit(u: Array) -> void:
	_unit = u
	_preview_src = _mod.unit_source(u[0], u[1])
	_fill_left_grid()
	_fill_manage_right()


func set_all(on: bool) -> void:
	_mod.set_pack_enabled(_pid, on)
	refresh()


func set_kind_enabled(on: bool) -> void:
	_mod.set_pack_enabled(_pid, on, _left.kind)
	refresh()


func _fill_manage_right() -> void:
	for c in _right.get_children():
		_right.remove_child(c)
		c.queue_free()
	if _unit.empty():
		return
	var kind = _unit[0]
	var id = _unit[1]
	var cur = _mod.unit_source(kind, id)
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 14)
	_right.add_child(head)
	var pv = _mod.unit_value(_mod.packs[_pid].data, kind, id)
	var icon = TextureRect.new()
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(72, 72)
	icon.texture = _mod.unit_icon(kind, id, pv)
	head.add_child(icon)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGN_CENTER
	head.add_child(col)
	col.add_child(ui._label(_mod.unit_name(kind, id, pv), ui.FONT_NORMAL, ui.C_TEXT))
	col.add_child(ui._key_label(id))
	var sw = ui._switch(ui.tr("BE_CLOUD_ENABLED"), cur == _pid)
	sw.connect("toggled", self, "_on_unit_toggled")
	head.add_child(sw)
	# 版本：点击预览，"使用此版本"切换
	var vrow = HBoxContainer.new()
	vrow.add_constant_override("separation", 6)
	_right.add_child(vrow)
	vrow.add_child(ui._label(ui.tr("BE_CLOUD_VERSIONS"), ui.FONT_SMALL, ui.C_ACCENT))
	for v in _mod.unit_versions(kind, id):
		var b = ui._button(("✓ " if v == cur else "") + _ver_name(v), ui.FONT_DESC)
		ui._apply_chip_style(b, v == _preview_src, ui.C_ACCENT_2)
		b.connect("pressed", self, "_on_preview_version", [v])
		vrow.add_child(b)
	var spacer = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	vrow.add_child(spacer)
	var use = ui._button(ui.tr("BE_CLOUD_USE_VERSION"), ui.FONT_SMALL)
	ui._apply_action_style(use, ui.C_ACCENT_3)
	use.disabled = _preview_src == cur
	use.connect("pressed", self, "use_version")
	vrow.add_child(use)
	var sc = ui._scroll()
	_right.add_child(sc)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 4)
	sc.add_child(box)
	_version_preview(box, kind, id, _preview_src)


func _ver_name(v: String) -> String:
	match v:
		"vanilla":
			return ui.tr("BE_SRC_VANILLA")
		"self":
			return ui.tr("BE_CLOUD_VER_SELF")
	return _pack_title(v)


func _on_preview_version(v: String) -> void:
	_preview_src = v
	_fill_manage_right()


func use_version() -> void:
	_mod.set_source(_unit[0], _unit[1], _preview_src)
	_fill_left_grid()
	_fill_manage_right()


func _on_unit_toggled(on: bool) -> void:
	_mod.set_pack_enabled(_pid, on, _unit[0], _unit[1])
	_preview_src = _mod.unit_source(_unit[0], _unit[1])
	_fill_left_grid()
	_fill_manage_right()


# 某个版本的预览：名称 + 效果行（武器按等级）；自定义对象的"原版"= 不存在
func _version_preview(box: Control, kind: String, id: String, src: String) -> void:
	var v = _mod.version_value(kind, id, src)
	if v == null and _mod._unit_res(kind, id) == null:
		box.add_child(ui._desc(ui.tr("BE_CLOUD_VER_NONE")))
		return
	box.add_child(ui._label(_mod.unit_name(kind, id, v), ui.FONT_SMALL, ui.C_TEXT))
	if kind != "weapon":
		ui._effect_lines(_mod.build_effects(id, BEMain.normalize_profile(v)), box)
		return
	var tiers = {}
	if v == null:
		for w in _mod._vanilla_members(id):
			tiers[w.my_id] = {}
	else:
		tiers = v.tiers
	var ids = tiers.keys()
	ids.sort()
	for tid in ids:
		box.add_child(ui._label(tid, ui.FONT_DESC, ui.C_ACCENT_2))
		ui._effect_lines(_mod.build_effects(tid, BEMain.normalize_profile(tiers[tid])), box)


# ============================================================
# 上传
# ============================================================
func _build_upload() -> void:
	_mod.capture()
	var units = _mod.layer_units(_mod.own)
	var keep = []
	for u in _sel:
		if u in units:
			keep.push_back(u)
	_sel = keep
	var cols = HBoxContainer.new()
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 12)
	_content.add_child(cols)
	_left_panel(cols, units)
	var card = ui._card(cols)
	card.size_flags_vertical = SIZE_EXPAND_FILL
	var right = VBoxContainer.new()
	right.add_constant_override("separation", 6)
	card.add_child(right)
	right.add_child(ui._label(ui.tr("BE_CLOUD_PACK_TITLE"), ui.FONT_SMALL, ui.C_TEXT))
	var title = ui._line_edit("")
	title.max_length = MAX_TITLE
	title.text = _title
	title.connect("text_changed", self, "_on_title")
	right.add_child(title)
	right.add_child(ui._label(ui.tr("BE_CLOUD_AUTHOR"), ui.FONT_SMALL, ui.C_TEXT))
	var author = ui._line_edit("")
	author.max_length = MAX_AUTHOR
	author.text = str(_uploads.author)
	author.connect("text_changed", self, "_on_author")
	right.add_child(author)
	right.add_child(ui._label(ui.tr("BE_CLOUD_DESC"), ui.FONT_SMALL, ui.C_TEXT))
	var desc = TextEdit.new()
	desc.rect_min_size = Vector2(0, 160)
	desc.wrap_enabled = true
	desc.add_font_override("font", ui.FONT_SMALL)
	desc.add_color_override("font_color", ui.C_TEXT)
	desc.add_stylebox_override("normal", ui._style(ui.C_BG_CHIP, ui.C_BORDER, 6, 1, 10, 6))
	desc.add_stylebox_override("focus", ui._style(ui.C_BG_CHIP, ui.C_ACCENT, 6, 1, 10, 6))
	desc.text = _desc
	desc.connect("text_changed", self, "_on_desc", [desc])
	right.add_child(desc)
	var img_row = HBoxContainer.new()
	img_row.add_constant_override("separation", 10)
	right.add_child(img_row)
	_preview = TextureRect.new()
	_preview.rect_min_size = Vector2(128, 128)
	_preview.expand = true
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_row.add_child(_preview)
	var img_col = VBoxContainer.new()
	img_col.add_constant_override("separation", 6)
	img_row.add_child(img_col)
	_card_button(img_col, "BE_CLOUD_IMAGE", ui.C_ACCENT_2, "_on_pick_image", [])
	_card_button(img_col, "BE_CLOUD_IMAGE_CLEAR", ui.C_TEXT_DIM, "set_thumb", [null])
	_refresh_preview()
	_deps = ui._label("", ui.FONT_DESC, ui.C_TEXT_DIM)
	right.add_child(_deps)
	_refresh_deps()
	var up = ui._button(ui.tr("BE_CLOUD_UPLOAD"), ui.FONT_NORMAL)
	ui._apply_action_style(up, ui.C_ACCENT_3)
	up.connect("pressed", self, "upload")
	right.add_child(up)


func pick(what: String) -> void:
	if what == "none":
		_sel = []
	else:
		for u in _left_shown():
			if not u in _sel:
				_sel.push_back(u)
	_fill_left_grid()
	_refresh_deps()
	_refresh_preview()


func _on_title(text: String) -> void:
	_title = text


func _on_author(text: String) -> void:
	_uploads.author = text
	_save_uploads()


func _on_desc(edit: TextEdit) -> void:
	_desc = edit.text


# 自动附带的依赖：套装、标签、未勾选但被引用到的自定义对象
func _refresh_deps() -> void:
	if not is_instance_valid(_deps):
		return
	var data = _mod.bundle_data(_sel, _mod.own)
	var extra = 0
	for pair in [["character", "profiles"], ["item", "items"], ["weapon", "families"]]:
		for id in data.get(pair[1], {}):
			if not [pair[0], id] in _sel:
				extra += 1
	_deps.text = ui.tr("BE_CLOUD_DEPS").replace("{0}", str(data.get("sets", {}).size())).replace("{1}", str(data.get("tags", {}).size())).replace("{2}", str(extra))


func _on_pick_image() -> void:
	var fd = FileDialog.new()
	fd.mode = FileDialog.MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PoolStringArray(["*.png ; PNG", "*.jpg, *.jpeg ; JPG", "*.webp ; WEBP"])
	fd.window_title = ui.tr("BE_CLOUD_IMAGE")
	fd.connect("file_selected", self, "_on_image_file")
	fd.connect("popup_hide", fd, "queue_free")
	ui.add_child(fd)
	fd.popup_centered(Vector2(1100, 720))


func _on_image_file(path: String) -> void:
	var img = Image.new()
	if img.load(path) != OK:
		set_status(ui.tr("BE_IMPORT_ICON_FAILED"))
		return
	set_thumb(img)


# 缩略图：等比缩小到 THUMB_SIZE 以内；null = 用默认（第一个选中对象的图标）
func set_thumb(img) -> void:
	_thumb = _fit(img) if img != null else null
	_refresh_preview()


static func _fit(img: Image) -> Image:
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var s = min(1.0, float(THUMB_SIZE) / max(img.get_width(), img.get_height()))
	if s < 1.0:
		img.resize(int(max(1, img.get_width() * s)), int(max(1, img.get_height() * s)), Image.INTERPOLATE_BILINEAR)
	return img


func thumb_image():
	if _thumb != null:
		return _thumb
	for u in _sel:
		var tex = _mod.unit_icon(u[0], u[1], _mod.unit_value(_mod.own, u[0], u[1]))
		if tex != null and tex.get_data() != null:
			return _fit(tex.get_data())
	return null


func _refresh_preview() -> void:
	if not is_instance_valid(_preview):
		return
	var img = thumb_image()
	_preview.texture = _texture(img) if img != null else null


# 上传的请求正文；无法上传时返回错误提示的 key
func upload_body():
	if _sel.empty():
		return "BE_CLOUD_NEED_PICK"
	if _title.strip_edges() == "":
		return "BE_CLOUD_NEED_TITLE"
	var data = _mod.bundle_data(_sel, _mod.own)
	var code = BEMain.ALL_PREFIX + BEMain.pack(data)
	if code.length() > MAX_CODE:
		return "BE_CLOUD_TOO_LARGE"
	var kinds = []
	for k in BEMain.KINDS:
		if data.has(BEMain.BUNDLE_KEYS[k]) or k == "weapon" and data.has("families"):
			kinds.push_back(k)
	var names = []
	for u in _sel:
		names.push_back(_mod.unit_name(u[0], u[1], _mod.unit_value(_mod.own, u[0], u[1])))
	var body = {
		"title": _title.strip_edges(), "author": str(_uploads.author).strip_edges(), "desc": _desc.strip_edges().substr(0, MAX_DESC),
		"kinds": kinds, "contents": PoolStringArray(names).join(", "), "n": _sel.size(), "mod_ver": _mod_version(), "code": code,
	}
	var img = thumb_image()
	if img != null:
		body.thumb = Marshalls.raw_to_base64(img.save_png_to_buffer())
	return body


func upload() -> void:
	_mod.capture()
	var body = upload_body()
	if body is String:
		set_status(ui.tr(body))
		return
	set_status(ui.tr("BE_CLOUD_UPLOADING"))
	_request("/packs", HTTPClient.METHOD_POST, JSON.print(body), ["Content-Type: application/json"], "_on_uploaded", [body.title])


func _on_uploaded(code: int, body: PoolByteArray, title: String) -> void:
	if code == 429:
		set_status(ui.tr("BE_CLOUD_RATE_LIMITED"))
		return
	var r = _json(body)
	if code != 200 or not r.has("id"):
		_net_error(code)
		return
	_uploads.packs.push_front({"id": str(r.id), "token": str(r.get("token", "")), "title": title, "created": OS.get_unix_time()})
	_save_uploads()
	_packs = []
	set_status(ui.tr("BE_CLOUD_UPLOADED").replace("{0}", title))


# ============================================================
# 我的上传
# ============================================================
func _build_mine() -> void:
	var sc = ui._scroll()
	_content.add_child(sc)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_constant_override("separation", 6)
	sc.add_child(list)
	if _uploads.packs.empty():
		list.add_child(ui._desc(ui.tr("BE_CLOUD_MINE_EMPTY")))
	for p in _uploads.packs:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		ui._card(list).add_child(row)
		var t = ui._label(str(p.title), ui.FONT_SMALL, ui.C_TEXT)
		t.size_flags_horizontal = SIZE_EXPAND_FILL
		t.clip_text = true
		row.add_child(t)
		row.add_child(ui._label(_date(float(p.get("created", 0)) * 1000) + "  ·  " + str(p.id), ui.FONT_DESC, ui.C_TEXT_DIM))
		_card_button(row, "BE_CLOUD_COPY_ID", ui.C_ACCENT_2, "_on_copy_id", [str(p.id)])
		_card_button(row, "BE_DELETE", ui.C_DANGER, "_on_delete_ask", [p])


func _on_delete_ask(p: Dictionary) -> void:
	Modal.confirm(ui, [ui.tr("BE_CLOUD_DELETE_CONFIRM").replace("{0}", str(p.title))], ui.C_DANGER, self, "delete_pack", [p])


func delete_pack(p: Dictionary) -> void:
	_request("/packs/" + str(p.id), HTTPClient.METHOD_DELETE, "", ["X-Token: " + str(p.token)], "_on_deleted", [p])


func _on_deleted(code: int, _body: PoolByteArray, p: Dictionary) -> void:
	# 404 = 已被删除（如被管理员下架）：同样从本地记录移除
	if code != 200 and code != 404:
		_net_error(code)
		return
	_uploads.packs.erase(p)
	_save_uploads()
	_packs = []
	set_status(ui.tr("BE_CLOUD_DELETED"))
	if _page == "mine":
		refresh()


func _load_uploads() -> void:
	var file = File.new()
	if file.open(UPLOADS_PATH, File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error == OK and parsed.result is Dictionary:
		_uploads.author = str(parsed.result.get("author", ""))
		for p in parsed.result.get("packs", []):
			if p is Dictionary and p.has("id") and p.has("token"):
				_uploads.packs.push_back({"id": str(p.id), "token": str(p.token), "title": str(p.get("title", "")), "created": int(p.get("created", 0))})


func _save_uploads() -> void:
	var file = File.new()
	if file.open(UPLOADS_PATH, File.WRITE) == OK:
		file.store_string(JSON.print(_uploads, "\t"))
		file.close()
