extends Node

# Mojimoon-BroEditor：土豆兄弟角色编辑器
# 每个角色一份"档案"（profile），保存在 user://Mojimoon-BroEditor/profiles.json：
#   原版角色：档案启用时改写 CharacterData 资源（名称、效果、初始属性、可选初始武器、额外初始装备、偏好词条），
#             关闭档案或重置时还原；禁用道具 / 武器在商店抽取时过滤（ItemService 扩展）。
#   自定义角色：以某个角色为基底（外观 / 图标）新建的 CharacterData，游戏启动时注册，可在选角界面直接选择。
# 效果描述统一为 spec：{"from": 来源 id, "i": 效果下标, "set": {字段: 值}}，或 {"set": {...}}（普通属性效果）；
# 来源是原版角色 / 道具上的效果，复制后改字段，因此任何原版机制都能搬到角色上。

const MOD_ID = "Mojimoon-BroEditor"
const MOD_DIR = "res://mods-unpacked/Mojimoon-BroEditor/"
const SAVE_PATH = "user://Mojimoon-BroEditor/profiles.json"
const CSV_PATH = MOD_DIR + "translations/broeditor.csv"
const UI_SCENE = MOD_DIR + "ui/editor_ui.tscn"
const FONT_26_PATH = "res://resources/fonts/actual/base/font_26.tres"
const CUSTOM_PREFIX = "character_broeditor_"
const EFFECT_SCRIPT = "res://items/global/effect.gd"
const SHARE_PREFIX = "BE1:"
const MAX_DESC = 300

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")

# id -> 档案
var profiles: Dictionary = {}
var next_id: int = 1

# 原版角色 id -> 原始字段（还原用）
var _backups: Dictionary = {}
# 原始效果数组缓存：来源 id -> 效果数组（第一次读取时的版本，此后不受本 mod / 其他 mod 改写影响）
var _orig_effects: Dictionary = {}
# 自定义角色 id -> CharacterData
var _customs: Dictionary = {}
# 角色 id -> 禁用的道具 / 武器 hash（商店过滤用）
var _ban_cache: Dictionary = {}
var _library = null
var _desc_translation: Translation = null


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/extensions/"
	ModLoaderMod.install_script_extension(dir + "singletons/item_service.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/character_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")


func _ready() -> void:
	_register_translations()
	load_profiles()
	# 自定义角色必须在 ProgressData 读档之前注册（存档里的本局可能就是自定义角色）
	_register_customs()
	# DLC 角色在 ProgressData 就绪后才加入：本帧结束后再应用档案
	call_deferred("apply_all")


static func get_mod() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/ModLoader/" + MOD_ID)


static func _autoload(name_: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/" + name_)


# ============================================================
# 档案
# ============================================================
static func new_profile() -> Dictionary:
	return {
		"enabled": true,
		"custom": false,
		"name": "",
		"desc": "",
		"base": "",
		"icon": "",
		"effects": null,
		"stats": {},
		"weapons": null,
		"start_items": [],
		"ban_items": [],
		"ban_weapons": [],
		"wanted_tags": null,
	}


# 补齐缺少的字段并修正类型（读取存档、导入分享码共用）
static func normalize_profile(p) -> Dictionary:
	var out = new_profile()
	if not p is Dictionary:
		return out
	for k in out:
		if p.has(k) and p[k] != null:
			out[k] = p[k]
	out.enabled = bool(out.enabled)
	out.custom = bool(out.custom)
	out.name = str(out.name)
	out.desc = clean_desc(str(out.desc))
	out.base = str(out.base)
	out.icon = str(out.icon)
	if not out.stats is Dictionary:
		out.stats = {}
	var stats = {}
	for k in out.stats:
		var v = int(out.stats[k])
		if v != 0:
			stats[str(k)] = v
	out.stats = stats
	for k in ["effects", "weapons", "wanted_tags"]:
		if out[k] != null and not out[k] is Array:
			out[k] = null
	for k in ["start_items", "ban_items", "ban_weapons"]:
		if not out[k] is Array:
			out[k] = []
	return out


static func clean_desc(text: String) -> String:
	# 描述作为一行效果文本显示：花括号会被当成参数占位符，换成全角
	text = text.strip_edges().replace("{", "｛").replace("}", "｝")
	return text.substr(0, MAX_DESC)


func get_profile(id: String) -> Dictionary:
	return profiles.get(id, {})


func set_profile(id: String, p: Dictionary) -> void:
	profiles[id] = normalize_profile(p)


func reset_profile(id: String) -> void:
	if profiles.has(id) and not profiles[id].custom:
		profiles.erase(id)


func is_custom(id: String) -> bool:
	return profiles.has(id) and profiles[id].custom


func load_profiles() -> void:
	profiles = {}
	var file = File.new()
	if not file.file_exists(SAVE_PATH) or file.open(SAVE_PATH, File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		ModLoaderLog.error("profiles.json is invalid; ignored", MOD_ID)
		return
	next_id = max(1, int(parsed.result.get("next_id", 1)))
	var ps = parsed.result.get("profiles", {})
	if ps is Dictionary:
		for id in ps:
			profiles[str(id)] = normalize_profile(ps[id])


func save_profiles() -> void:
	var dir = Directory.new()
	if not dir.dir_exists(SAVE_PATH.get_base_dir()):
		dir.make_dir_recursive(SAVE_PATH.get_base_dir())
	var file = File.new()
	if file.open(SAVE_PATH, File.WRITE) != OK:
		ModLoaderLog.error("Failed to save profiles", MOD_ID)
		return
	file.store_string(JSON.print({"version": 1, "next_id": next_id, "profiles": profiles}, "\t"))
	file.close()


# 分享码：一个角色的档案（自定义角色导入后成为新的自定义角色）
func export_code(id: String) -> String:
	if not profiles.has(id):
		return ""
	return SHARE_PREFIX + Marshalls.utf8_to_base64(JSON.print({"id": id, "profile": profiles[id]}))


# 返回导入后的角色 id；无法识别返回 ""
func import_code(code: String, target_id: String) -> String:
	code = code.strip_edges()
	if not code.begins_with(SHARE_PREFIX):
		return ""
	var parsed = JSON.parse(Marshalls.base64_to_utf8(code.substr(SHARE_PREFIX.length())))
	if parsed.error != OK or not parsed.result is Dictionary or not parsed.result.get("profile") is Dictionary:
		return ""
	var p = normalize_profile(parsed.result.profile)
	if p.custom:
		var id = create_custom(p.base if p.base != "" else target_id)
		p.custom = true
		profiles[id] = p
		_register_custom(id)
		return id
	# 原版角色的档案导入到当前选中的原版角色上
	if target_id == "" or is_custom(target_id):
		return ""
	profiles[target_id] = p
	return target_id


# ============================================================
# 应用档案
# ============================================================
func _isvc():
	return _autoload("ItemService")


func find_character(id: String):
	var isvc = _isvc()
	if isvc == null:
		return null
	for c in isvc.characters:
		if c != null and c.my_id == id:
			return c
	return null


func _find_any(id: String):
	var isvc = _isvc()
	for arr in [isvc.characters, isvc.items, isvc.weapons]:
		for r in arr:
			if r != null and r.my_id == id:
				return r
	return null


# 来源的原始效果数组（第一次读取时缓存；原版角色若已被本 mod 改写，取备份）
func orig_effects(id: String) -> Array:
	if _orig_effects.has(id):
		return _orig_effects[id]
	var r = _find_any(id)
	if r == null:
		return []
	var effects: Array = r.effects
	if r is CharacterData and _backups.has(id):
		effects = _backups[id].effects
	_orig_effects[id] = effects.duplicate()
	return _orig_effects[id]


func template(from_id: String, i: int):
	var effects = orig_effects(from_id)
	if i < 0 or i >= effects.size():
		return null
	return effects[i]


# spec -> 效果资源（模板不存在返回 null）
func make_effect(spec: Dictionary):
	var e
	var from = str(spec.get("from", ""))
	if from != "":
		var t = template(from, int(spec.get("i", 0)))
		if t == null:
			return null
		e = t.duplicate()
	else:
		e = load(EFFECT_SCRIPT).new()
		e.effect_sign = 3	# FROM_VALUE
	var sets = spec.get("set", {})
	if sets is Dictionary:
		for k in sets:
			if not k in e:
				continue
			var cur = e.get(k)
			match typeof(cur):
				TYPE_INT:
					e.set(k, int(sets[k]))
				TYPE_REAL:
					e.set(k, float(sets[k]))
				TYPE_BOOL:
					e.set(k, bool(sets[k]))
				TYPE_STRING:
					e.set(k, str(sets[k]))
	e._generate_hashes()
	return e


# 普通属性效果的原版描述 key（stat_ 以外的 key 没有同名文本，借用原版同 key 效果的 text_key）
var _stat_text_keys = null


func stat_text_key(key: String) -> String:
	if _stat_text_keys == null:
		_stat_text_keys = {}
		for entry in library():
			var e = entry.effect
			if e.custom_key == "" and e.storage_method == 0 and Catalog.is_plain_effect(e) and not _stat_text_keys.has(e.key):
				_stat_text_keys[e.key] = e.text_key
	return _stat_text_keys.get(key, "")


func stat_effect(key: String, value: int):
	return make_effect({"set": {"key": key, "value": value, "text_key": stat_text_key(key)}})


# 档案的效果 spec 列表（null = 原版效果）展开为 spec
func effect_specs(id: String, p: Dictionary) -> Array:
	if p.effects is Array:
		return p.effects
	var out = []
	if p.custom:
		return out
	for i in orig_effects(id).size():
		out.push_back({"from": id, "i": i})
	return out


# 档案 -> 角色的完整效果列表
func build_effects(id: String, p: Dictionary) -> Array:
	var out = []
	if p.desc != "":
		out.push_back(_desc_effect(id, p.desc))
	for spec in effect_specs(id, p):
		if spec is Dictionary:
			var e = make_effect(spec)
			if e != null:
				out.push_back(e)
	var keys = p.stats.keys()
	keys.sort()
	for k in keys:
		if int(p.stats[k]) != 0:
			out.push_back(stat_effect(k, int(p.stats[k])))
	for s in p.start_items:
		var e = start_item_effect(s)
		if e != null:
			out.push_back(e)
	return out


# 额外初始装备：原版 starting_item / starting_weapon / cursed_* 效果（KEY_VALUE 存 [id_hash, 数量]）
func start_item_effect(s):
	if not s is Dictionary:
		return null
	var id = str(s.get("id", ""))
	var r = _find_any(id)
	if r == null or r is CharacterData:
		return null
	var weapon = r is WeaponData
	var cursed = bool(s.get("cursed", false))
	var ck = ("cursed_" if cursed else "") + ("starting_weapon" if weapon else "starting_item")
	return make_effect({"set": {
		"key": id, "value": max(1, int(s.get("n", 1))), "custom_key": ck, "storage_method": 1, "effect_sign": 3,
		"text_key": "effect_cursed_starting_item" if cursed else "effect_starting_item",
	}})


# 描述：一条不生效的效果（key 为空，apply 直接返回），文本是动态注册的翻译
func _desc_effect(id: String, text: String):
	if _desc_translation == null:
		_desc_translation = Translation.new()
		_desc_translation.locale = TranslationServer.get_locale()
		TranslationServer.add_translation(_desc_translation)
	var key = "BE_DESC_" + id.to_upper()
	# 每个语言都显示同一段描述
	_desc_translation.locale = TranslationServer.get_locale()
	_desc_translation.erase_message(key)
	_desc_translation.add_message(key, "[color=#" + Color(0.75, 0.8, 0.9).to_html(false) + "]" + text + "[/color]")
	return make_effect({"set": {"key": "", "value": 0, "text_key": key, "effect_sign": 2}})


func _backup(c) -> void:
	if _backups.has(c.my_id):
		return
	_backups[c.my_id] = {
		"res": c, "effects": c.effects, "name": c.name, "starting_weapons": c.starting_weapons,
		"wanted_tags": c.wanted_tags,
	}


func restore() -> void:
	for id in _backups:
		var b = _backups[id]
		var c = b.res
		if c == null or not is_instance_valid(c):
			continue
		c.effects = b.effects
		c.name = b.name
		c.starting_weapons = b.starting_weapons
		c.wanted_tags = b.wanted_tags
	_backups.clear()


func _weapons_by_ids(ids: Array) -> Array:
	var out = []
	var isvc = _isvc()
	for id in ids:
		for w in isvc.weapons:
			if w.my_id == str(id) and not w in out:
				out.push_back(w)
	return out


# 把全部档案写入角色资源（先还原，再按当前档案改写）
func apply_all() -> void:
	var isvc = _isvc()
	if isvc == null:
		return
	restore()
	_ban_cache.clear()
	_register_customs()
	for id in profiles:
		var p = profiles[id]
		var c = find_character(id)
		if c == null:
			continue
		if p.custom:
			_fill_custom(c, id, p)
			continue
		if not p.enabled:
			continue
		# 先缓存原始效果（_backup 之后 orig_effects 也会读备份）
		var _orig = orig_effects(id)
		_backup(c)
		c.effects = build_effects(id, p)
		if p.name != "":
			c.name = p.name
		if p.weapons is Array:
			c.starting_weapons = _weapons_by_ids(p.weapons)
		if p.wanted_tags is Array:
			c.wanted_tags = p.wanted_tags.duplicate()


# ============================================================
# 自定义角色
# ============================================================
func custom_ids() -> Array:
	var out = []
	for id in profiles:
		if profiles[id].custom:
			out.push_back(id)
	out.sort()
	return out


# 以 base_id 为基底新建自定义角色（复制基底的效果、初始武器、偏好词条），返回新 id
func create_custom(base_id: String) -> String:
	var id = CUSTOM_PREFIX + str(next_id)
	while find_character(id) != null or profiles.has(id):
		next_id += 1
		id = CUSTOM_PREFIX + str(next_id)
	next_id += 1
	var p = new_profile()
	p.custom = true
	p.base = base_id
	var base = find_character(base_id)
	if base != null:
		p.name = tr(_backups[base_id].name if _backups.has(base_id) else base.name) + " +"
		var bp = profiles.get(base_id)
		if bp != null and bp.enabled:
			# 基底已有档案：连同档案内容一起复制
			for k in ["effects", "stats", "weapons", "start_items", "ban_items", "ban_weapons", "wanted_tags", "desc"]:
				p[k] = bp[k].duplicate(true) if bp[k] is Array or bp[k] is Dictionary else bp[k]
		if p.effects == null:
			p.effects = []
			for i in orig_effects(base_id).size():
				p.effects.push_back({"from": base_id, "i": i})
		if p.weapons == null:
			var ws = []
			for w in (_backups[base_id].starting_weapons if _backups.has(base_id) else base.starting_weapons):
				ws.push_back(w.my_id)
			p.weapons = ws
		if p.wanted_tags == null:
			p.wanted_tags = (_backups[base_id].wanted_tags if _backups.has(base_id) else base.wanted_tags).duplicate()
	else:
		p.name = tr("BE_NEW_CHARACTER")
		p.effects = []
		p.weapons = []
		p.wanted_tags = []
	profiles[id] = p
	_register_custom(id)
	_unlock_new_characters()
	return id


# 删除自定义角色；存档中进行中的一局正在使用该角色时拒绝（读档会找不到角色）
func delete_custom(id: String) -> bool:
	if not is_custom(id) or is_in_saved_run(id):
		return false
	profiles.erase(id)
	var c = _customs.get(id)
	_customs.erase(id)
	var isvc = _isvc()
	if c != null and isvc != null:
		isvc.characters.erase(c)
	return true


func is_in_saved_run(id: String) -> bool:
	var pd = _autoload("ProgressData")
	if pd == null or not pd.saved_run_state is Dictionary or not pd.saved_run_state.get("has_run_state", false):
		return false
	var players = pd.saved_run_state.get("players_data", [])
	if not players is Array:
		return false
	for pl in players:
		var ch = pl.get("current_character") if pl is Dictionary else (pl.current_character if pl is Object and "current_character" in pl else null)
		if ch is Object and "my_id" in ch and ch.my_id == id:
			return true
		if ch is Dictionary and str(ch.get("my_id", "")) == id:
			return true
		if ch is String and ch == id:
			return true
	return false


func _register_customs() -> void:
	for id in custom_ids():
		_register_custom(id)


func _register_custom(id: String) -> void:
	var isvc = _isvc()
	if isvc == null:
		return
	var c = _customs.get(id)
	if c == null:
		c = load("res://items/characters/character_data.gd").new()
		c.my_id = id
		c.unlocked_by_default = true
		c.tier = 0
		c.value = 1
		c.max_nb = -1
		c.effects = []
		c.tags = []
		c.wanted_tags = []
		c.banned_item_groups = []
		c.banned_items = []
		c.banned_upgrades = []
		c.starting_weapons = []
		c.starting_items = []
		c.item_appearances = []
		_customs[id] = c
	c._generate_hashes()
	if not c in isvc.characters:
		isvc.characters.push_back(c)
	_fill_custom(c, id, profiles[id])


func _fill_custom(c, id: String, p: Dictionary) -> void:
	var base = find_character(p.base)
	c.name = p.name if p.name != "" else tr("BE_NEW_CHARACTER")
	var icon_src = _find_any(p.icon) if p.icon != "" else null
	if icon_src == null:
		icon_src = base
	c.icon = icon_src.icon if icon_src != null else load("res://items/characters/well_rounded/well_rounded_icon.png")
	if base != null:
		c.item_appearances = base.item_appearances
	c.effects = build_effects(id, p)
	c.starting_weapons = _weapons_by_ids(p.weapons if p.weapons is Array else [])
	if c.starting_weapons.empty():
		c.starting_weapons = [load("res://weapons/melee/fist/1/fist_data.tres")]
	c.wanted_tags = p.wanted_tags.duplicate() if p.wanted_tags is Array else []


# 新建的自定义角色：解锁并补上难度记录（游戏启动时由 ProgressData 读档自动完成）
func _unlock_new_characters() -> void:
	var pd = _autoload("ProgressData")
	if pd == null or pd.SAVE_DIR == "":
		return
	pd.add_unlocked_by_default()
	pd.set_max_selectable_difficulty()
	pd.save()


# ============================================================
# 效果库
# ============================================================
func library() -> Array:
	if _library != null:
		return _library
	var isvc = _isvc()
	var sources = []
	for c in isvc.characters:
		if c != null and not c.my_id.begins_with(CUSTOM_PREFIX):
			sources.push_back([c.my_id, _backups[c.my_id].name if _backups.has(c.my_id) else c.name, orig_effects(c.my_id)])
	for it in isvc.items:
		if it != null:
			sources.push_back([it.my_id, it.name, orig_effects(it.my_id)])
	_library = Catalog.build_library(sources)
	return _library


# 蓝图扳机的模板：custom_key -> spec（找不到返回 null）
func trigger_template(custom_key: String):
	for entry in library():
		var e = entry.effect
		if e.custom_key == custom_key and Catalog.is_plain_effect(e) and e.storage_method == 1 and Catalog.is_stat_key(e.key):
			return {"from": entry.from, "i": entry.i}
	return null


# 角色的原始名称（不受档案改名影响）
func orig_name(c) -> String:
	return _backups[c.my_id].name if _backups.has(c.my_id) else c.name


# ============================================================
# 禁用道具 / 武器（商店与箱子）
# ============================================================
func ban_hashes(player_index: int) -> Array:
	var rd = _autoload("RunData")
	if rd == null or player_index < 0 or player_index >= rd.players_data.size():
		return []
	var c = rd.players_data[player_index].current_character
	if c == null:
		return []
	if _ban_cache.has(c.my_id):
		return _ban_cache[c.my_id]
	var out = []
	var p = profiles.get(c.my_id)
	if p != null and (p.enabled or p.custom):
		for id in p.ban_items:
			out.push_back(Keys.generate_hash(str(id)))
		if not p.ban_weapons.empty():
			for w in _isvc().weapons:
				if w.weapon_id in p.ban_weapons:
					out.push_back(w.my_id_hash)
	_ban_cache[c.my_id] = out
	return out


# ============================================================
# 本地化（运行时解析 CSV；与 AutoAnthony 相同）
# ============================================================
func _register_translations() -> void:
	var file = File.new()
	if not file.file_exists(CSV_PATH) or file.open(CSV_PATH, File.READ) != OK:
		ModLoaderLog.error("i18n csv not found: " + CSV_PATH, MOD_ID)
		return
	var lines: PoolStringArray = file.get_as_text().split("\n", false)
	file.close()
	if lines.size() < 2:
		return
	var header = _parse_csv_line(lines[0].strip_edges())
	var locales = []
	var translations = {}
	for i in range(1, header.size()):
		var locale = header[i].strip_edges()
		locales.push_back(locale)
		var t = Translation.new()
		t.locale = locale
		translations[locale] = t
	for li in range(1, lines.size()):
		var row = _parse_csv_line(lines[li].strip_edges())
		if row.size() < 2 or row[0].strip_edges() == "":
			continue
		for i in range(1, header.size()):
			var value = row[i].c_unescape() if i < row.size() else ""
			if value == "":
				value = row[1].c_unescape()
			translations[locales[i - 1]].add_message(row[0].strip_edges(), value)
	for locale in locales:
		TranslationServer.add_translation(translations[locale])


static func _parse_csv_line(line: String) -> PoolStringArray:
	var result = PoolStringArray()
	var current = ""
	var in_quotes = false
	var i = 0
	while i < line.length():
		var ch = line[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					current += "\""
					i += 1
				else:
					in_quotes = false
			else:
				current += ch
		else:
			if ch == "\"":
				in_quotes = true
			elif ch == ",":
				result.append(current)
				current = ""
			else:
				current += ch
		i += 1
	result.append(current)
	return result


# ============================================================
# 入口按钮：角色 / 武器 / 难度选择界面左上角（返回按钮旁）
# ============================================================
static func add_editor_button(screen: Node) -> void:
	if screen == null or not screen.is_inside_tree():
		return
	var back_button = screen.get_node_or_null("%BackButton")
	if back_button == null or back_button.has_node("BroEditorBtn"):
		return
	var btn = Button.new()
	btn.name = "BroEditorBtn"
	btn.text = TranslationServer.translate("BE_BTN_OPEN")
	btn.rect_min_size = Vector2(200, 50)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_font_override("font", load(FONT_26_PATH))
	place_button(back_button, btn)
	btn.connect("pressed", get_mod(), "open_editor", [screen])


# 当前界面里玩家 0 的角色（武器 / 难度选择界面）或选角界面中聚焦的角色
func open_editor(screen: Node) -> void:
	var scene = load(UI_SCENE)
	if scene == null or screen == null:
		return
	var ui = scene.instance()
	ui.initial_id = _screen_character_id(screen)
	var layer = CanvasLayer.new()
	layer.layer = 100
	screen.get_tree().current_scene.add_child(layer)
	layer.add_child(ui)
	ui.connect("tree_exited", layer, "queue_free")


func _screen_character_id(screen: Node) -> String:
	var rd = _autoload("RunData")
	if not screen is CharacterSelection and rd != null and rd.players_data.size() > 0 and rd.players_data[0].current_character != null:
		return rd.players_data[0].current_character.my_id
	if screen is CharacterSelection and "_info_panel" in screen and screen._info_panel != null:
		var id = str(screen._info_panel.character_currently_displayed) if "character_currently_displayed" in screen._info_panel else ""
		if id != "":
			return id
	return ""


# 编辑器关闭：保存并应用；本局已选的角色在武器 / 难度选择界面里按新档案重新加入
func on_editor_closed(changed: bool) -> void:
	save_profiles()
	if not changed:
		return
	apply_all()
	var tree = get_tree()
	var scene = tree.current_scene
	var rd = _autoload("RunData")
	if scene is CharacterSelection:
		tree.call_deferred("reload_current_scene")
	elif scene is WeaponSelection:
		var chars = []
		for pd in rd.players_data:
			chars.push_back(pd.current_character)
		rd.revert_all_selections()
		for i in chars.size():
			rd.add_character(chars[i], i)
		tree.call_deferred("reload_current_scene")
	elif scene is DifficultySelection:
		rd.reset(true)


static func place_button(back_button: Node, btn: Button) -> void:
	back_button.add_child(btn)
	var left_neighbour: Button = null
	var max_right: float = -1.0
	for child in back_button.get_children():
		if child is Button and child != btn and child.is_inside_tree():
			var right: float = child.rect_position.x + child.rect_size.x
			if right > max_right:
				max_right = right
				left_neighbour = child
	var base_x: float = back_button.rect_size.x
	if left_neighbour != null:
		base_x = left_neighbour.rect_position.x + left_neighbour.rect_size.x
	btn.rect_position = Vector2(base_x + 18.0, 0.0)
	btn.focus_neighbour_left = btn.get_path_to(left_neighbour if left_neighbour != null else back_button)
