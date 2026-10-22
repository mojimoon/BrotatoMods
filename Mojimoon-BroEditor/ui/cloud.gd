extends Node

# 分享站（编辑器右上角"上传 / 下载"）：服务端是 mods/tools/broeditor-cloud 的 Cloudflare Worker。挂在一个 Modal 上：
#   浏览：搜索 / 种类 / 排序，下载后用 import_bundle 导入
#   上传：勾选对象（依赖由 bundle_data 自动带上），填标题 / 作者 / 简介，选缩略图（默认第一个对象的图标）
#   我的上传：上传时返回的删除令牌存在 UPLOADS_PATH（只在本机），可删除自己的包
# test_responses：测试用，"方法 路径" -> [状态码, 正文]，有值时不发网络请求

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")
const Modal = preload("res://mods-unpacked/Mojimoon-BroEditor/ui/modal.gd")
const API = "https://broeditor-6myuzuteg3xe5jtk.mojimoon.top"
const UPLOADS_PATH = "user://Mojimoon-BroEditor/uploads.json"
const THUMB_SIZE = 256
const THUMB_SHOW = 112
# 与 worker.js 的 MAX 一致
const MAX_TITLE = 60
const MAX_AUTHOR = 40
const MAX_DESC = 500
const MAX_CODE = 512 * 1024
const TABS = ["browse", "upload", "mine"]

var ui = null
var modal = null
var test_responses = null
var _mod = null
var _tab := "browse"
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
var _list: VBoxContainer
var _thumbs := {}	# 包 id -> 纹理
# 上传
var _sel := []	# [[种类, id]...]
var _with_disabled := false
var _thumb: Image = null
var _title := ""
var _desc := ""
var _deps: Label
var _preview: TextureRect
var _uploads := {"author": "", "packs": []}


static func open(p_ui):
	var c = load("res://mods-unpacked/Mojimoon-BroEditor/ui/cloud.gd").new()
	c._build(p_ui)
	return c


func _build(p_ui) -> void:
	ui = p_ui
	_mod = ui._mod
	test_responses = ui.test_cloud
	_load_uploads()
	modal = Modal.open(ui, ui.tr("BE_CLOUD_TITLE"), ui.C_ACCENT_2, Vector2(1500, 900))
	modal.add_child(self)
	for t in TABS:
		var b = ui._button(ui.tr("BE_CLOUD_TAB_" + t), ui.FONT_SMALL)
		b.connect("pressed", self, "set_tab", [t])
		modal.head.add_child(b)
		_tab_btns[t] = b
	_status = ui._label("", ui.FONT_DESC, ui.C_TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.align = Label.ALIGN_RIGHT
	_status.clip_text = true
	modal.head.add_child(_status)
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_constant_override("separation", 8)
	modal.body.add_child(_content)
	modal.add_button(ui.tr("MENU_BACK"), ui.C_TEXT_DIM, modal, "close")
	# 默认勾选编辑器当前对象（有修改时）
	var cur = [ui._kind, ui._obj_key()]
	if cur in _mod.share_entries([ui._kind]):
		_sel.push_back(cur)
	set_tab("browse")


func set_tab(t: String) -> void:
	_tab = t
	for k in _tab_btns:
		ui._apply_chip_style(_tab_btns[k], k == t, ui.C_ACCENT_2)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	call("_build_" + t)


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
# 浏览
# ============================================================
func _build_browse() -> void:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	_content.add_child(row)
	var le = ui._line_edit(ui.tr("BE_SEARCH"))
	le.text = _q
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var sc = ui._scroll()
	_content.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_constant_override("separation", 8)
	sc.add_child(_list)
	_fill_list()
	if _packs.empty():
		fetch(0)


func _on_search(text: String) -> void:
	_q = text.strip_edges()
	fetch(0)


func _on_browse_filter(key: String, value: String) -> void:
	set(("_" + key), value)
	set_tab("browse")
	fetch(0)


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
	if _tab == "browse":
		_fill_list()


func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _packs.empty() and not _busy:
		_list.add_child(ui._desc(ui.tr("BE_CLOUD_EMPTY")))
	for p in _packs:
		_pack_card(p)
	if _more:
		var b = ui._button(ui.tr("BE_CLOUD_MORE"), ui.FONT_SMALL)
		ui._apply_action_style(b, ui.C_ACCENT_2)
		b.connect("pressed", self, "fetch", [_packs.size()])
		_list.add_child(b)


func _pack_card(p: Dictionary) -> void:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	ui._card(_list).add_child(row)
	var img = TextureRect.new()
	img.rect_min_size = Vector2(THUMB_SHOW, THUMB_SHOW)
	img.expand = true
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(img)
	if int(p.get("thumb", 0)):
		_load_thumb(str(p.id), img)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_constant_override("separation", 2)
	row.add_child(col)
	var title = ui._label(str(p.get("title", "")), ui.FONT_NORMAL, ui.C_TEXT)
	title.clip_text = true
	col.add_child(title)
	var info = [_date(p.get("created", 0)), ui.tr("BE_CLOUD_DOWNLOADS").replace("{0}", str(int(p.get("downloads", 0))))]
	if str(p.get("author", "")) != "":
		info.push_front(str(p.author))
	var kinds = []
	for k in str(p.get("kinds", "")).split(",", false):
		kinds.push_back(ui.tr("BE_KIND_" + k.to_upper()))
	if not kinds.empty():
		info.push_back(PoolStringArray(kinds).join(" / "))
	col.add_child(ui._label(PoolStringArray(info).join("  ·  "), ui.FONT_DESC, ui.C_ACCENT_2))
	if str(p.get("contents", "")) != "":
		var contents = ui._label(str(p.contents), ui.FONT_DESC, ui.C_CUSTOM)
		contents.clip_text = true
		col.add_child(contents)
	if str(p.get("desc", "")) != "":
		var d = ui._desc(str(p.desc))
		d.add_color_override("font_color", ui.C_TEXT)
		col.add_child(d)
	var dl = ui._button(ui.tr("BE_CLOUD_DOWNLOAD"), ui.FONT_SMALL)
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui._apply_action_style(dl, ui.C_ACCENT_3)
	dl.connect("pressed", self, "_on_download_ask", [p])
	row.add_child(dl)


static func _date(ms) -> String:
	var d = OS.get_datetime_from_unix_time(int(float(ms) / 1000))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _load_thumb(id: String, img: TextureRect) -> void:
	if _thumbs.has(id):
		img.texture = _thumbs[id]
		return
	_request("/packs/" + id + "/thumb", HTTPClient.METHOD_GET, "", [], "_on_thumb", [id, img])


func _on_thumb(code: int, body: PoolByteArray, id: String, img: TextureRect) -> void:
	var image = Image.new()
	if code != 200 or image.load_png_from_buffer(body) != OK:
		return
	var tex = ImageTexture.new()
	tex.create_from_image(image)
	_thumbs[id] = tex
	if is_instance_valid(img):
		img.texture = tex


# 导入会覆盖同 id 的档案，先确认
func _on_download_ask(p: Dictionary) -> void:
	Modal.confirm(ui, [ui.tr("BE_CLOUD_IMPORT_CONFIRM").replace("{0}", str(p.get("title", "")))], ui.C_ACCENT_3, self, "download", [str(p.id)])


func download(id: String) -> void:
	set_status(ui.tr("BE_CLOUD_LOADING"))
	_request("/packs/" + id, HTTPClient.METHOD_GET, "", [], "_on_code")


func _on_code(code: int, body: PoolByteArray) -> void:
	if code != 200:
		_net_error(code)
		return
	var n = _mod.import_bundle(body.get_string_from_utf8())
	if n < 0:
		set_status(ui.tr("BE_CLOUD_IMPORT_FAILED"))
		return
	ui._refresh_char_list()
	ui._select(ui._id)
	set_status(ui.tr("BE_IMPORTED_N").replace("{0}", str(n)))


# ============================================================
# 上传
# ============================================================
func _build_upload() -> void:
	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_constant_override("separation", 12)
	_content.add_child(cols)
	# 左：勾选内容
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_constant_override("separation", 6)
	cols.add_child(left)
	var quick = HBoxContainer.new()
	quick.add_constant_override("separation", 8)
	left.add_child(quick)
	quick.add_child(ui._label(ui.tr("BE_CLOUD_PICK"), ui.FONT_NORMAL, ui.C_ACCENT))
	for q in ["current", "all", "none"]:
		var b = ui._button(ui.tr("BE_CLOUD_PICK_" + q.to_upper()), ui.FONT_DESC)
		ui._apply_action_style(b, ui.C_ACCENT)
		b.connect("pressed", self, "pick", [q])
		quick.add_child(b)
	var sc = ui._scroll()
	left.add_child(sc)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var any = false
	for kind in BEMain.KINDS:
		var entries = _entries([kind])
		if entries.empty():
			continue
		any = true
		var head = HBoxContainer.new()
		list.add_child(head)
		var hl = ui._label(ui.tr("BE_KIND_" + kind.to_upper()), ui.FONT_SMALL, ui.C_ACCENT_2)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl)
		var kb = ui._button(ui.tr("BE_CLOUD_PICK_KIND"), ui.FONT_DESC)
		ui._apply_action_style(kb, ui.C_ACCENT_2)
		kb.connect("pressed", self, "pick", [kind])
		head.add_child(kb)
		for e in entries:
			var cb = ui._checkbox(_entry_name(e), ui.FONT_DESC)
			cb.pressed = e in _sel
			if _is_custom_entry(e):
				for k in ["font_color", "font_color_pressed", "font_color_focus"]:
					cb.add_color_override(k, ui.C_CUSTOM)
			cb.connect("toggled", self, "_on_pick_toggled", [e])
			list.add_child(cb)
	if not any:
		list.add_child(ui._desc(ui.tr("BE_CLOUD_NO_ENTRIES")))
	var dis = ui._checkbox(ui.tr("BE_CLOUD_WITH_DISABLED"), ui.FONT_DESC)
	dis.pressed = _with_disabled
	dis.connect("toggled", self, "_on_with_disabled")
	left.add_child(dis)
	_deps = ui._desc("")
	left.add_child(_deps)
	_refresh_deps()
	# 右：标题 / 作者 / 简介 / 图片
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(ui._label(ui.tr("BE_CLOUD_PACK_TITLE"), ui.FONT_SMALL, ui.C_TEXT))
	var title = ui._line_edit(ui.tr("BE_CLOUD_PACK_TITLE"))
	title.max_length = MAX_TITLE
	title.text = _title
	title.connect("text_changed", self, "_on_title")
	right.add_child(title)
	right.add_child(ui._label(ui.tr("BE_CLOUD_AUTHOR"), ui.FONT_SMALL, ui.C_TEXT))
	var author = ui._line_edit(ui.tr("BE_CLOUD_AUTHOR"))
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
	_preview.rect_min_size = Vector2(THUMB_SHOW, THUMB_SHOW)
	_preview.expand = true
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_row.add_child(_preview)
	var img_col = VBoxContainer.new()
	img_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	img_row.add_child(img_col)
	var pick_img = ui._button(ui.tr("BE_CLOUD_IMAGE"), ui.FONT_DESC)
	ui._apply_action_style(pick_img, ui.C_ACCENT_2)
	pick_img.connect("pressed", self, "_on_pick_image")
	img_col.add_child(pick_img)
	var clear_img = ui._button(ui.tr("BE_CLOUD_IMAGE_CLEAR"), ui.FONT_DESC)
	ui._apply_action_style(clear_img, ui.C_TEXT_DIM)
	clear_img.connect("pressed", self, "set_thumb", [null])
	img_col.add_child(clear_img)
	img_col.add_child(ui._desc(ui.tr("BE_CLOUD_IMAGE_HINT")))
	_refresh_preview()
	var up = ui._button(ui.tr("BE_CLOUD_UPLOAD"), ui.FONT_NORMAL)
	ui._apply_action_style(up, ui.C_ACCENT_3)
	up.connect("pressed", self, "upload")
	right.add_child(up)


func _entry_name(e: Array) -> String:
	if e[0] == "weapon":
		var ms = _mod.family_members(e[1])
		return ui.tr(ms[0].name) if not ms.empty() else e[1]
	var r = _mod.find_target(e[0], e[1])
	return ui.tr(r.name) if r != null else e[1]


# 可分享的对象，自定义对象在前（列表、全选顺序；默认缩略图取第一个）
func _entries(kinds: Array = BEMain.KINDS) -> Array:
	var out = []
	for e in _mod.share_entries(kinds):
		if _is_custom_entry(e):
			out.push_back(e)
	for e in _mod.share_entries(kinds):
		if not e in out:
			out.push_back(e)
	return out


func _is_custom_entry(e: Array) -> bool:
	return _mod.is_custom_family(e[1]) if e[0] == "weapon" else _mod.is_custom(e[1])


func pick(what: String) -> void:
	match what:
		"current":
			var cur = [ui._kind, ui._obj_key()]
			_sel = [cur] if cur in _mod.share_entries([ui._kind]) else []
		"all":
			_sel = _entries()
		"none":
			_sel = []
		_:
			for e in _entries([what]):
				if not e in _sel:
					_sel.push_back(e)
	set_tab("upload")


func _on_pick_toggled(on: bool, e: Array) -> void:
	if on and not e in _sel:
		_sel.push_back(e)
	elif not on:
		_sel.erase(e)
	_refresh_deps()
	_refresh_preview()


func _on_with_disabled(on: bool) -> void:
	_with_disabled = on


func _on_title(text: String) -> void:
	_title = text


func _on_author(text: String) -> void:
	_uploads.author = text
	_save_uploads()


func _on_desc(edit: TextEdit) -> void:
	_desc = edit.text


# 附带的依赖：套装、标签、未勾选但被引用到的对象
func _refresh_deps() -> void:
	var data = _mod.bundle_data(_sel)
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


# 缩略图：等比缩小到 THUMB_SIZE 以内；null = 用默认（第一个勾选对象的图标）
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
	for e in _sel:
		var r = _mod.family_members(e[1])[0] if e[0] == "weapon" and not _mod.family_members(e[1]).empty() else _mod.find_target(e[0], e[1])
		if r != null and r.icon != null and r.icon.get_data() != null:
			return _fit(r.icon.get_data())
	return null


func _refresh_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	var img = thumb_image()
	var tex = null
	if img != null:
		tex = ImageTexture.new()
		tex.create_from_image(img)
	_preview.texture = tex


# 上传的请求正文；无法上传时返回错误提示的 key
func upload_body():
	if _sel.empty() and not _with_disabled:
		return "BE_CLOUD_NEED_PICK"
	if _title.strip_edges() == "":
		return "BE_CLOUD_NEED_TITLE"
	var data = _mod.bundle_data(_sel)
	if _with_disabled:
		data.disabled = _mod.disabled.duplicate(true)
	var code = BEMain.ALL_PREFIX + BEMain.pack(data)
	if code.length() > MAX_CODE:
		return "BE_CLOUD_TOO_LARGE"
	var kinds = []
	for k in BEMain.KINDS:
		if data.has(BEMain.BUNDLE_KEYS[k]) or k == "weapon" and data.has("families"):
			kinds.push_back(k)
	var names = []
	for e in _sel:
		names.push_back(_entry_name(e))
	var body = {
		"title": _title.strip_edges(), "author": str(_uploads.author).strip_edges(), "desc": _desc.strip_edges().substr(0, MAX_DESC),
		"kinds": kinds, "contents": PoolStringArray(names).join(", "), "n": _sel.size(), "mod_ver": _mod_version(), "code": code,
	}
	var img = thumb_image()
	if img != null:
		body.thumb = Marshalls.raw_to_base64(img.save_png_to_buffer())
	return body


func upload() -> void:
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
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_constant_override("separation", 6)
	sc.add_child(list)
	if _uploads.packs.empty():
		list.add_child(ui._desc(ui.tr("BE_CLOUD_MINE_EMPTY")))
	for p in _uploads.packs:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		ui._card(list).add_child(row)
		var t = ui._label(str(p.title), ui.FONT_SMALL, ui.C_TEXT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		row.add_child(t)
		row.add_child(ui._label(_date(float(p.get("created", 0)) * 1000) + "  ·  " + str(p.id), ui.FONT_DESC, ui.C_TEXT_DIM))
		var del = ui._button(ui.tr("BE_DELETE"), ui.FONT_DESC)
		ui._apply_action_style(del, ui.C_DANGER)
		del.connect("pressed", self, "_on_delete_ask", [p])
		row.add_child(del)


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
	if _tab == "mine":
		set_tab("mine")


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
