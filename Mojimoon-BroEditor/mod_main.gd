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
# 新增的角色 / 道具 / 武器：每个一个单行 JSON（custom/<种类>/<id>.json），可直接复制给别人
const CUSTOM_DIR = "user://Mojimoon-BroEditor/custom/"
const CSV_PATH = MOD_DIR + "translations/broeditor.csv"
const UI_SCENE = MOD_DIR + "ui/editor_ui.tscn"
const FONT_26_PATH = "res://resources/fonts/actual/base/font_26.tres"
# 新建对象的 id = 前缀 + 玩家输入的后缀（默认 <基底>_<随机数>）
const CHAR_PREFIX = "character_"
const ITEM_PREFIX = "item_"
const WEAPON_PREFIX = "weapon_"
const ID_PREFIX = {"character": CHAR_PREFIX, "item": ITEM_PREFIX, "weapon": WEAPON_PREFIX}
# 给原版武器家族补的低级版本：<weapon_id>_<等级>_broeditor
const TIER_SUFFIX = "_broeditor"
const EFFECT_SCRIPT = "res://items/global/effect.gd"
const SHARE_PREFIX = "BE0:"
# 批量导出：一栏全部（角色 / 道具 / 武器）与三栏全部，前缀不同
const BUNDLE_PREFIX = {"character": "BEC:", "item": "BEI:", "weapon": "BEW:"}
const ALL_PREFIX = "BEA:"
const BUNDLE_KEYS = {"character": "profiles", "item": "items", "weapon": "weapons"}
const MAX_DESC = 300

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const GraphEffect = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
const Runtime = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/runtime.gd")
# 上限类属性：角色效果直接设定上限值（原版 REPLACE 存储），而不是加减
const CAP_KEYS = ["hp_cap", "speed_cap", "dodge_cap", "crit_chance_cap"]
# 设定值型规则：直接设定数值（原版士兵的"移动时不能攻击"就是 REPLACE 为 0）；界面默认显示角色自身的值，0 也是有效值
const SET_KEYS = ["can_attack_while_moving"]
# 效果列表中的分组占位：初始属性 / 额外初始装备 / 蓝图生成的效果插在占位处（没有占位时接在最后）
const GROUPS = ["stats", "start", "graph"]
# 三栏：角色 / 道具 / 武器（各自一份档案字典与一个总开关）
const KINDS = ["character", "item", "weapon"]
# 武器属性页可编辑的 WeaponStats 字段：[字段, 类型, 显示方式]；pct = 内部 0–1，界面按百分比整数编辑
const WSTAT_FIELDS = [
	["damage", "int", ""], ["cooldown", "int", ""], ["recoil", "int", ""], ["recoil_duration", "float", ""],
	["additional_cooldown_every_x_shots", "int", ""], ["additional_cooldown_multiplier", "float", ""], ["crit_chance", "float", "pct"], ["crit_damage", "float", ""],
	["accuracy", "float", "pct"], ["min_range", "int", ""], ["max_range", "int", ""], ["knockback", "int", ""],
	["lifesteal", "float", "pct"], ["speed_percent_modifier", "int", ""], ["effect_scale", "float", "pct"],
	["nb_projectiles", "int", ""], ["projectile_spread", "float", ""], ["piercing", "int", ""],
	["piercing_dmg_reduction", "float", "pct"], ["bounce", "int", ""], ["bounce_dmg_reduction", "float", "pct"],
	["projectile_speed", "int", ""], ["attack_type", "int", ""],
]
# 开局状态的默认值
const START_DEFAULT = {
	"materials": 0, "levels": 0, "level_settle": false, "crates": 0, "legendary_crates": 0,
	"ban_tokens": 0, "start_wave": 1, "wave_delta": 0, "wave_lock": 0,
}

# id -> 档案
var profiles: Dictionary = {}
var item_profiles: Dictionary = {}
var weapon_profiles: Dictionary = {}
var kind_enabled := {"character": true, "item": true, "weapon": true}
# 武器家族（weapon_id）层面的修改：名称 / 词条对全部等级生效；自定义武器与补的低级版本也记在这里
var weapon_families: Dictionary = {}
# 禁用的对象（武器按家族 weapon_id）：角色不可选，道具 / 武器不出现
var disabled := {"character": [], "item": [], "weapon": []}
var next_id: int = 1
# 调试模式：编辑器里在效果与属性旁显示键名
var debug := false
# 隐藏自定义对象图标右下角的编号（使用原版图标时才有编号）
var hide_numbers := false

# 原版角色 id -> 原始字段（还原用）
var _backups: Dictionary = {}
# 原始效果数组缓存：来源 id -> 效果数组（第一次读取时的版本，此后不受本 mod / 其他 mod 改写影响）
var _orig_effects: Dictionary = {}
# 自定义角色 id -> CharacterData
var _customs: Dictionary = {}
var _custom_items: Dictionary = {}
var _custom_weapons: Dictionary = {}
var _global_ban = null
# 角色 id -> 禁用的道具 / 武器 hash（商店过滤用）
var _ban_cache: Dictionary = {}
var _library = null
var _weapon_library = null
# 道具 / 武器稀有度被改过：还原或重新应用后要重建商店分档池
var _repool := false
var _desc_translation: Translation = null
# 蓝图运行时（常驻）与"需要重建触发索引"标记
var runtime = null
var graph_dirty := true
# 结算升级 / 开局箱子：开局时记下，第一波开始时执行
var _pending_start: Dictionary = {}
var _wave_duration_set := false
var _start_wave_set := false


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/extensions/"
	ModLoaderMod.install_script_extension(dir + "singletons/item_service.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/run_data.gd")
	ModLoaderMod.install_script_extension(dir + "main.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/shop/shop.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/shop/coop_shop.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/character_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")


func _ready() -> void:
	_register_translations()
	load_profiles()
	runtime = Runtime.new()
	runtime.mod = self
	add_child(runtime)
	# 存档反序列化按 get_id() 在 ItemService.effects 中查找效果脚本：要在 ProgressData 读档之前注册
	var isvc = _isvc()
	if isvc != null and not GraphEffect in isvc.effects:
		isvc.effects.push_back(GraphEffect)
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
		"graph": null,
		"start": {},
		# 道具 / 武器：-1 / -2 / null = 不修改
		"price": -1,
		"tier": -1,
		"max_nb": -2,
		"tags": null,
		"wstats": {},
		"scaling": null,
		# 自定义对象的图标编号
		"num": 0,
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
		if v != 0 or str(k) in SET_KEYS:
			stats[str(k)] = v
	out.stats = stats
	for k in ["effects", "weapons", "wanted_tags"]:
		if out[k] != null and not out[k] is Array:
			out[k] = null
	for k in ["start_items", "ban_items", "ban_weapons"]:
		if not out[k] is Array:
			out[k] = []
	if out.graph != null and not (out.graph is Dictionary and out.graph.get("nodes") is Array and out.graph.get("links") is Array):
		out.graph = null
	if out.graph != null:
		_int_ids(out.graph)
	out.num = int(out.num)
	out.price = int(out.price)
	out.tier = int(out.tier)
	out.max_nb = int(out.max_nb)
	if out.tags != null and not out.tags is Array:
		out.tags = null
	var ws = {}
	if out.wstats is Dictionary:
		for k in out.wstats:
			if typeof(out.wstats[k]) in [TYPE_INT, TYPE_REAL, TYPE_BOOL]:
				ws[str(k)] = out.wstats[k]
	out.wstats = ws
	if out.scaling is Array:
		var sc = []
		for e in out.scaling:
			if e is Array and e.size() >= 2:
				sc.push_back([str(e[0]), float(e[1])])
		out.scaling = sc
	else:
		out.scaling = null
	var start = {}
	if out.start is Dictionary:
		for k in START_DEFAULT:
			if out.start.has(k) and typeof(out.start[k]) in [TYPE_INT, TYPE_REAL, TYPE_BOOL]:
				var v = bool(out.start[k]) if typeof(START_DEFAULT[k]) == TYPE_BOOL else int(out.start[k])
				if v != START_DEFAULT[k]:
					start[k] = v
	out.start = start
	return out


# JSON 读回的数字是浮点：节点 id / 连线统一转为整数
# 武器家族档案：custom = 自定义武器（base = 外观与近 / 远战来源的原版家族）；tiers = 本模组新增的等级
static func new_family() -> Dictionary:
	return {"custom": false, "base": "", "name": "", "icon": "", "sets": null, "tiers": [], "num": 0}


static func normalize_family(f) -> Dictionary:
	var out = new_family()
	if not f is Dictionary:
		return out
	for k in out:
		if f.has(k) and typeof(f[k]) == typeof(out[k]):
			out[k] = f[k]
	out.custom = bool(f.get("custom", false))
	out.num = int(f.get("num", 0))
	out.sets = null
	if f.get("sets") is Array:
		out.sets = []
		for s in f.sets:
			out.sets.push_back(str(s))
	var tiers = []
	for t in out.tiers:
		if int(t) >= 0 and int(t) <= 3 and not int(t) in tiers:
			tiers.push_back(int(t))
	tiers.sort()
	out.tiers = tiers
	return out


static func _int_ids(g: Dictionary) -> void:
	for n in g.nodes:
		n.id = int(n.get("id", 0))
		if not n.get("params") is Dictionary:
			n.params = {}
	var links = []
	for l in g.links:
		if l is Array and l.size() >= 2:
			links.push_back([int(l[0]), int(l[1])])
	g.links = links
	g.next = int(g.get("next", 1))


static func start_value(p: Dictionary, k: String):
	return p.get("start", {}).get(k, START_DEFAULT[k])


static func clean_desc(text: String) -> String:
	# 描述作为一行效果文本显示：花括号会被当成参数占位符，换成全角
	text = text.strip_edges().replace("{", "｛").replace("}", "｝")
	return text.substr(0, MAX_DESC)


func profiles_of(kind: String) -> Dictionary:
	match kind:
		"item":
			return item_profiles
		"weapon":
			return weapon_profiles
	return profiles


func get_profile(id: String) -> Dictionary:
	return profiles.get(id, {})


func set_profile(id: String, p: Dictionary) -> void:
	profiles[id] = normalize_profile(p)


func reset_profile(id: String, kind: String = "character") -> void:
	var ps = profiles_of(kind)
	if ps.has(id) and not ps[id].custom:
		ps.erase(id)


func is_custom(id: String) -> bool:
	for ps in [profiles, item_profiles, weapon_profiles]:
		if ps.has(id) and ps[id].custom:
			return true
	return false


func is_custom_family(weapon_id: String) -> bool:
	return weapon_families.has(weapon_id) and weapon_families[weapon_id].custom


func load_profiles() -> void:
	profiles = {}
	item_profiles = {}
	weapon_profiles = {}
	weapon_families = {}
	disabled = {"character": [], "item": [], "weapon": []}
	_load_main_file()
	_load_custom_files()


func _load_main_file() -> void:
	var file = File.new()
	if not file.file_exists(SAVE_PATH) or file.open(SAVE_PATH, File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		ModLoaderLog.error("profiles.json is invalid; ignored", MOD_ID)
		return
	next_id = max(1, int(parsed.result.get("next_id", 1)))
	var settings = parsed.result.get("settings", {})
	debug = bool(settings.get("debug", false)) if settings is Dictionary else false
	hide_numbers = bool(settings.get("hide_numbers", false)) if settings is Dictionary else false
	var kinds = settings.get("kinds", {}) if settings is Dictionary else {}
	for k in KINDS:
		kind_enabled[k] = bool(kinds.get(k, true)) if kinds is Dictionary else true
	for pair in [["profiles", profiles], ["items", item_profiles], ["weapons", weapon_profiles]]:
		var ps = parsed.result.get(pair[0], {})
		if ps is Dictionary:
			for id in ps:
				pair[1][str(id)] = normalize_profile(ps[id])
	_load_extra(parsed.result)


# 家族档案与禁用列表（存档与批量码共用）
func _load_extra(data: Dictionary) -> void:
	var fs = data.get("families", {})
	if fs is Dictionary:
		for wid in fs:
			weapon_families[str(wid)] = normalize_family(fs[wid])
	var dis = data.get("disabled", {})
	if dis is Dictionary:
		for k in KINDS:
			if dis.get(k) is Array:
				for id in dis[k]:
					if not str(id) in disabled[k]:
						disabled[k].push_back(str(id))


# 一个自定义对象的数据：角色 / 道具 = 档案；武器 = 家族档案 + 各等级的档案
func custom_file_data(kind: String, id: String) -> Dictionary:
	if kind == "weapon":
		var tiers = {}
		for t in weapon_families[id].tiers:
			var tid = tier_id(id, t, true)
			if weapon_profiles.has(tid):
				tiers[tid] = weapon_profiles[tid]
		return {"kind": kind, "id": id, "family": weapon_families[id], "tiers": tiers}
	return {"kind": kind, "id": id, "profile": profiles_of(kind)[id]}


# 全部自定义对象：[[种类, id]]
func custom_entries() -> Array:
	var out = []
	for id in profiles:
		if profiles[id].custom:
			out.push_back(["character", id])
	for id in item_profiles:
		if item_profiles[id].custom:
			out.push_back(["item", id])
	for wid in weapon_families:
		if weapon_families[wid].custom:
			out.push_back(["weapon", wid])
	return out


# profiles.json 只存原版对象的修改与设置；自定义对象各存一个文件（删掉的对象的文件一并删除）
func save_profiles() -> void:
	var dir = Directory.new()
	for kind in KINDS:
		if not dir.dir_exists(CUSTOM_DIR + kind):
			dir.make_dir_recursive(CUSTOM_DIR + kind)
	var main = {"profiles": {}, "items": {}, "weapons": {}, "families": {}}
	var custom_tiers = {}
	var files = {}
	for e in custom_entries():
		var data = custom_file_data(e[0], e[1])
		files[e[0] + "/" + e[1] + ".json"] = data
		if e[0] == "weapon":
			for tid in data.tiers:
				custom_tiers[tid] = true
	for pair in [["profiles", profiles], ["items", item_profiles]]:
		for id in pair[1]:
			if not pair[1][id].custom:
				main[pair[0]][id] = pair[1][id]
	for id in weapon_profiles:
		if not custom_tiers.has(id):
			main.weapons[id] = weapon_profiles[id]
	for wid in weapon_families:
		if not weapon_families[wid].custom:
			main.families[wid] = weapon_families[wid]
	main["version"] = 1
	main["next_id"] = next_id
	main["settings"] = {"debug": debug, "hide_numbers": hide_numbers, "kinds": kind_enabled}
	main["disabled"] = disabled
	var file = File.new()
	if file.open(SAVE_PATH, File.WRITE) != OK:
		ModLoaderLog.error("Failed to save profiles", MOD_ID)
		return
	file.store_string(JSON.print(main, "\t"))
	file.close()
	for name in files:
		if file.open(CUSTOM_DIR + name, File.WRITE) == OK:
			file.store_string(JSON.print(files[name]))
			file.close()
	for name in custom_files():
		if not files.has(name):
			dir.remove(CUSTOM_DIR + name)


static func _list_json(path: String) -> Array:
	var out = []
	var dir = Directory.new()
	if dir.open(path) != OK:
		return out
	dir.list_dir_begin(true, true)
	var name = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "json":
			out.push_back(name)
		name = dir.get_next()
	dir.list_dir_end()
	return out


# custom/ 下的全部文件（相对路径：<种类>/<id>.json）
static func custom_files() -> Array:
	var out = []
	for kind in KINDS:
		for name in _list_json(CUSTOM_DIR + kind):
			out.push_back(kind + "/" + name)
	return out


# 读取 custom/ 下的文件（包括别人分享的）
func _load_custom_files() -> void:
	for name in custom_files():
		var file = File.new()
		if file.open(CUSTOM_DIR + name, File.READ) != OK:
			continue
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if not (parsed.error == OK and parsed.result is Dictionary and load_custom_data(parsed.result) != ""):
			ModLoaderLog.error("custom file is invalid or clashes with an existing id; ignored: " + name, MOD_ID)


# 载入一个自定义对象的数据；与原版对象重 id 的跳过。返回其 id（无效返回 ""）
func load_custom_data(data: Dictionary) -> String:
	var kind = str(data.get("kind", ""))
	var id = str(data.get("id", ""))
	if not kind in KINDS or clean_suffix(id) != id or not id.begins_with(ID_PREFIX[kind]):
		return ""
	if kind == "weapon":
		var f = normalize_family(data.get("family", {}))
		if not _vanilla_members(id).empty() or f.tiers.empty():
			return ""
		f.custom = true
		weapon_families[id] = f
		var tiers = data.get("tiers", {})
		for t in f.tiers:
			var tid = tier_id(id, t, true)
			var p = normalize_profile(tiers.get(tid, {}) if tiers is Dictionary else {})
			p.custom = true
			weapon_profiles[tid] = p
		next_id = max(next_id, f.num + 1)
		return id
	# 已登记的自定义对象（重新读取时）不算重 id
	var ours = _customs.has(id) if kind == "character" else _custom_items.has(id)
	if find_target(kind, id) != null and not ours:
		return ""
	var p = normalize_profile(data.get("profile", {}))
	p.custom = true
	profiles_of(kind)[id] = p
	next_id = max(next_id, p.num + 1)
	return id


# 分享码：一个角色的档案（自定义角色导入后成为新的自定义角色）
func export_code(id: String, kind: String = "character") -> String:
	var ps = profiles_of(kind)
	if not ps.has(id):
		return ""
	return SHARE_PREFIX + Marshalls.utf8_to_base64(JSON.print({"kind": kind, "id": id, "profile": ps[id]}))


# 返回导入后的角色 id；无法识别返回 ""
# 批量导出：kind = "" 时导出三栏全部
func export_bundle(kind: String) -> String:
	var data = {}
	var prefix = ALL_PREFIX
	var kinds = KINDS
	if kind != "":
		prefix = BUNDLE_PREFIX[kind]
		kinds = [kind]
	var dis = {}
	for k in kinds:
		data[BUNDLE_KEYS[k]] = profiles_of(k)
		dis[k] = disabled[k]
	if "weapon" in kinds:
		data["families"] = weapon_families
	data["disabled"] = dis
	var has = _any_disabled(dis)
	for k in data:
		has = has or (k != "disabled" and not data[k].empty())
	return prefix + Marshalls.utf8_to_base64(JSON.print(data)) if has else ""


static func _any_disabled(dis: Dictionary) -> bool:
	for k in dis:
		if not dis[k].empty():
			return true
	return false


# 导入批量码：同 id 的档案被覆盖（自定义角色保留 id）；返回导入条数，-1 = 不是有效的批量码
func import_bundle(code: String) -> int:
	code = code.strip_edges()
	var kinds = []
	if code.begins_with(ALL_PREFIX):
		kinds = KINDS
		code = code.substr(ALL_PREFIX.length())
	else:
		for k in BUNDLE_PREFIX:
			if code.begins_with(BUNDLE_PREFIX[k]):
				kinds = [k]
				code = code.substr(BUNDLE_PREFIX[k].length())
	if kinds.empty():
		return -1
	var parsed = JSON.parse(Marshalls.base64_to_utf8(code))
	if parsed.error != OK or not parsed.result is Dictionary:
		return -1
	var n = 0
	# 先建好自定义武器 / 补的等级，后面的武器档案才找得到目标
	if "weapon" in kinds:
		var fs = parsed.result.get("families", {})
		if fs is Dictionary:
			for wid in fs:
				var f = normalize_family(fs[wid])
				# 自定义武器不能占用原版武器的 id
				if f.custom and not _vanilla_members(str(wid)).empty():
					continue
				weapon_families[str(wid)] = f
				next_id = max(next_id, f.num + 1)
				n += 1
			_register_weapon_families()
	if parsed.result.get("disabled") is Dictionary:
		var keep = {}
		for k in KINDS:
			keep[k] = disabled[k] if not k in kinds else []
		disabled = keep
		_load_extra({"disabled": parsed.result.disabled})
	for k in kinds:
		var src = parsed.result.get(BUNDLE_KEYS[k], {})
		if not src is Dictionary:
			continue
		for id in src:
			if not src[id] is Dictionary:
				continue
			var p = normalize_profile(src[id])
			id = str(id)
			# 自定义对象不能占用原版对象的 id；原版对象的档案要有对应的对象
			var existing = find_target(k, id)
			if p.custom and existing != null and not is_custom(id):
				continue
			if not p.custom and k != "weapon" and existing == null:
				continue
			if k == "item" and p.custom:
				item_profiles[id] = p
				_register_custom_item(id)
			if k != "character" and find_target(k, id) == null:
				continue
			if k == "character" and not p.custom and find_character(id) == null:
				continue
			profiles_of(k)[id] = p
			if p.custom and k == "character":
				_register_custom(id)
			if p.custom:
				next_id = max(next_id, p.num + 1)
			n += 1
	return n


# 自定义对象 id 末尾的编号
static func _id_number(id: String) -> int:
	return int(id.get_slice("_", id.count("_")))


func import_code(code: String, target_id: String, kind: String = "character") -> String:
	code = code.strip_edges()
	if not code.begins_with(SHARE_PREFIX):
		return ""
	var parsed = JSON.parse(Marshalls.base64_to_utf8(code.substr(SHARE_PREFIX.length())))
	if parsed.error != OK or not parsed.result is Dictionary or not parsed.result.get("profile") is Dictionary:
		return ""
	var p = normalize_profile(parsed.result.profile)
	# 道具 / 武器的档案只能导入到同种类的对象上
	if str(parsed.result.get("kind", "character")) != kind:
		return ""
	if kind == "item" and p.custom:
		var nid = create_custom_item(p.base)
		item_profiles[nid] = p
		_register_custom_item(nid)
		return nid
	if kind != "character":
		if target_id == "":
			return ""
		# 自定义武器的等级档案保持自定义
		p.custom = is_custom(target_id)
		profiles_of(kind)[target_id] = p
		return target_id
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


func find_target(kind: String, id: String):
	var isvc = _isvc()
	if isvc == null:
		return null
	var arr = isvc.characters if kind == "character" else (isvc.items if kind == "item" else isvc.weapons)
	for r in arr:
		if r != null and r.my_id == id:
			return r
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
	if _backups.has(id):
		effects = _backups[id].fields.effects
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


# 属性显示名：原版 STAT_X；属性获取修改（gain_stat_x / gain_x）= "<属性> 获取 %"；其余用本 mod 的 BE_K_X
# 原版标签含义不清（NUMBER_OF_ENEMIES = "敌人"）的 key：用本 mod 的标签
# item_box_gold：原版标签"箱子里的材料"不如袋子的说法清楚，用本 mod 的标签
const OWN_LABEL_KEYS = ["number_of_enemies", "item_box_gold"]
# 原版效果文本不含数值（"同时仅能装备1种武器"）的 key：不借用该文本
const NO_LIBRARY_TEXT = ["weapon_slot"]
const TEXT_FORMAT_LIKE = {"effect_bounce_damage": "effect_piercing_damage"}


func stat_name(key: String) -> String:
	if key.begins_with("gain_") and key != "gain_pct_gold_start_wave":
		var base = stat_name(key.substr(5)).strip_edges()
		for pfx in ["%", "％"]:
			base = base.trim_prefix(pfx).trim_suffix(pfx).strip_edges()
		return tr("BE_GAIN_FMT").replace("{0}", base)
	var native = key.to_upper()
	if key.begins_with("stat_") or (not key in OWN_LABEL_KEYS and tr(native) != native and tr(native).find("{") < 0):
		return tr(native).strip_edges()
	var k = "BE_K_" + native
	var t = tr(k)
	return t if t != k else key


# 属性页数值的效果文本：原版效果用过的 text_key > 原版 EFFECT_<KEY> > 原版 <KEY>（"+X 名称"）；
# 都没有时注册本 mod 的 BE_FX_<KEY>（有翻译行用翻译行，否则 "+X 名称"）
func _plain_text_key(key: String) -> String:
	var tk = "" if key in NO_LIBRARY_TEXT else stat_text_key(key)
	if tk != "":
		return tk
	if tr("EFFECT_" + key.to_upper()) != "EFFECT_" + key.to_upper():
		tk = "effect_" + key
		# 原版没有用过、因而没登记 +/- 号与 % 的文本：照同类文本登记（反弹伤害同贯通伤害）
		var like = TEXT_FORMAT_LIKE.get(tk, "")
		var text = _autoload("Text")
		if like != "" and text != null:
			for table in [text.keys_needing_operator, text.keys_needing_percent]:
				if table.has(like) and not table.has(tk):
					table[tk] = table[like]
		return tk
	if tr(key.to_upper()) != key.to_upper():
		return ""
	tk = "BE_FX_" + key.to_upper()
	if tr(tk) == tk:
		if _desc_translation == null:
			_desc_translation = Translation.new()
			_desc_translation.locale = TranslationServer.get_locale()
			TranslationServer.add_translation(_desc_translation)
		_desc_translation.add_message(tk, stat_name(key))
		var text = _autoload("Text")
		if text != null:
			text.keys_needing_operator[tk.to_lower()] = [0]
	return tk


const STAT_GAINS_SCRIPT = "res://effects/items/stat_gains_modification_effect.gd"


func stat_effect(key: String, value: int):
	# 属性获取修改：用原版的效果（"{0}的修改增加 / 减少{1}"），效果与 gain_<属性> += value 相同
	if key.begins_with("gain_") and key != "gain_pct_gold_start_wave" and ResourceLoader.exists(STAT_GAINS_SCRIPT):
		var g = load(STAT_GAINS_SCRIPT).new()
		g.key = "effect_increase_stat_gains" if value >= 0 else "effect_reduce_stat_gains"
		g.value = value
		g.effect_sign = 3	# FROM_VALUE
		g.stat_displayed = key.substr(5)
		g.stats_modified = [key.substr(5)]
		g._generate_hashes()
		return g
	var sets = {"key": key, "value": value, "text_key": _plain_text_key(key)}
	if key in CAP_KEYS or key in SET_KEYS:
		sets.storage_method = 2
	return make_effect({"set": sets})


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
# 效果列表中每条"生成的效果"（初始属性的每一项、每件额外初始装备、蓝图）用一个占位标记它的位置：
#   {"group": "stats", "key": 属性} / {"group": "start", "id": 道具 id, "n": 同 id 的第几件} / {"group": "graph"}
# 只有 group 的旧占位 = 该分组中其余全部条目；列表里没有占位的条目接在最后。
func build_effects(id: String, p: Dictionary) -> Array:
	var out = []
	if p.desc != "":
		out.push_back(_desc_effect(id, p.desc))
	var entries = group_entries(p)
	var used = {}
	for spec in effect_specs(id, p):
		if not spec is Dictionary:
			continue
		if spec.has("group"):
			for en in entries_for_marker(entries, spec):
				var s = entry_sig(en.marker)
				if not used.has(s):
					used[s] = true
					out.push_back(en.effect)
			continue
		var e = make_effect(spec)
		if e != null:
			out.push_back(e)
	for en in entries:
		if not used.has(entry_sig(en.marker)):
			out.push_back(en.effect)
	return out


# 生成的效果条目（默认顺序）：[{marker, effect}]
func group_entries(p: Dictionary) -> Array:
	var out = []
	var keys = p.stats.keys()
	keys.sort()
	for k in keys:
		if int(p.stats[k]) != 0 or k in SET_KEYS:
			out.push_back({"marker": {"group": "stats", "key": k}, "effect": stat_effect(k, int(p.stats[k]))})
	var seen = {}
	for s in p.start_items:
		var e = start_item_effect(s)
		if e == null:
			continue
		var sid = str(s.get("id", ""))
		seen[sid] = seen.get(sid, 0) + 1
		out.push_back({"marker": {"group": "start", "id": sid, "n": seen[sid]}, "effect": e})
	if p.graph is Dictionary and not p.graph.get("nodes", []).empty():
		out.push_back({"marker": {"group": "graph"}, "effect": GraphEffect.make(p.graph)})
	return out


static func entry_sig(m: Dictionary) -> String:
	return str(m.get("group", "")) + "|" + str(m.get("key", m.get("id", ""))) + "|" + str(int(m.get("n", 1)))


# 是否是只有分组名的旧占位（graph 本身只有一条，按条目处理）
static func is_group_marker(m: Dictionary) -> bool:
	return m.has("group") and m.group != "graph" and not m.has("key") and not m.has("id")


func entries_for_marker(entries: Array, m: Dictionary) -> Array:
	var out = []
	for en in entries:
		if is_group_marker(m):
			if en.marker.group == m.group:
				out.push_back(en)
		elif entry_sig(en.marker) == entry_sig(m):
			out.push_back(en)
	return out


func group_effects(p: Dictionary, g: String) -> Array:
	var out = []
	for en in group_entries(p):
		if en.marker.group == g:
			out.push_back(en.effect)
	return out


# 设定值型规则在角色身上的原有值（原版效果里的 REPLACE；没有则为玩家效果表的默认值）
func native_set_value(id: String, key: String) -> int:
	var v = 1
	var probe = load("res://singletons/player_run_data.gd").init_effects()
	var h = Keys.generate_hash(key)
	if probe.has(h) and typeof(probe[h]) in [TYPE_INT, TYPE_REAL]:
		v = int(probe[h])
	for e in orig_effects(id):
		if e != null and "key" in e and e.key == key and e.custom_key == "" and e.storage_method == 2:
			v = int(e.value)
	return v


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


const BACKUP_FIELDS = {
	"character": ["effects", "name", "starting_weapons", "wanted_tags"],
	"item": ["effects", "name", "value", "tier", "max_nb", "tags"],
	"weapon": ["effects", "name", "value", "stats", "sets"],
}


static func kind_of(res) -> String:
	if res is CharacterData:
		return "character"
	if res is WeaponData:
		return "weapon"
	return "item"


func _backup(c) -> void:
	if _backups.has(c.my_id):
		return
	var fields = {}
	for f in BACKUP_FIELDS[kind_of(c)]:
		fields[f] = c.get(f)
	_backups[c.my_id] = {"res": c, "fields": fields}


func backup_value(c, field: String):
	return _backups[c.my_id].fields[field] if _backups.has(c.my_id) else c.get(field)


func restore() -> void:
	for id in _backups:
		var b = _backups[id]
		var c = b.res
		if c == null or not is_instance_valid(c):
			continue
		for f in b.fields:
			if f == "tier" and c.tier != b.fields.tier:
				_repool = true
			c.set(f, b.fields[f])
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
	_global_ban = null
	_register_customs()
	_register_custom_items()
	_register_weapon_families()
	_apply_items()
	_apply_weapons()
	_apply_families()
	if _repool and isvc.has_method("init_unlocked_pool"):
		isvc.init_unlocked_pool()
	_repool = false
	# 原版按 id 查找道具 / 武器的缓存（新增或删除对象后会过期）
	isvc._item_id_lookup = {}
	isvc._weapon_id_lookup = {}
	for id in profiles:
		var p = profiles[id]
		var c = find_character(id)
		if c == null:
			continue
		if p.custom:
			_fill_custom(c, id, p)
			continue
		if not p.enabled or not kind_enabled.character:
			continue
		# 先缓存原始效果（_backup 之后 orig_effects 也会读备份）
		var _orig = orig_effects(id)
		_backup(c)
		c.effects = build_effects(id, p)
		if p.name != "":
			c.name = p.name
		if p.weapons is Array:
			# 档案里的武器全都不存在（来自已停用的 mod）时保留原版初始武器
			var ws = _weapons_by_ids(p.weapons)
			if not ws.empty() or p.weapons.empty():
				c.starting_weapons = ws
		if p.wanted_tags is Array:
			c.wanted_tags = p.wanted_tags.duplicate()


# 道具：效果、名称、价格、稀有度、数量限制、词条
func _apply_items() -> void:
	for id in item_profiles:
		var p = item_profiles[id]
		var it = find_target("item", id)
		# 自定义道具总是生效（同自定义角色）
		if it == null or not (p.custom or (p.enabled and kind_enabled.item)):
			continue
		var _orig = orig_effects(id)
		_backup(it)
		it.effects = build_effects(id, p)
		if p.name != "":
			it.name = p.name
		if p.price >= 0:
			it.value = p.price
		if p.tier >= 0 and p.tier != it.tier:
			it.tier = p.tier
			_repool = true
		if p.max_nb != -2:
			it.max_nb = p.max_nb
		if p.tags is Array:
			it.tags = p.tags.duplicate()


# 武器：效果、名称、价格、武器属性（在原属性的副本上改写）
func _apply_weapons() -> void:
	for id in weapon_profiles:
		var p = weapon_profiles[id]
		var w = find_target("weapon", id)
		if w == null or not (p.custom or (p.enabled and kind_enabled.weapon)):
			continue
		var _orig = orig_effects(id)
		_backup(w)
		w.effects = build_effects(id, p)
		if p.name != "":
			w.name = p.name
		if p.price >= 0:
			w.value = p.price
		if not p.wstats.empty() or p.scaling is Array:
			w.stats = weapon_stats_for(w, p)


# 家族层面的名称、词条（全部等级）
func _apply_families() -> void:
	for wid in weapon_families:
		var f = weapon_families[wid]
		if not f.custom and not kind_enabled.weapon:
			continue
		var sets = null
		if f.sets is Array:
			sets = []
			for s in _isvc().sets:
				if s != null and s.my_id in f.sets:
					sets.push_back(s)
		for w in family_members(wid):
			if f.name == "" and sets == null:
				continue
			_backup(w)
			if f.name != "":
				w.name = f.name
			if sets != null:
				w.sets = sets.duplicate()


# 同一家族的全部等级（按等级排序）
func family_members(weapon_id: String) -> Array:
	var out = []
	for w in _isvc().weapons:
		if w != null and w.weapon_id == weapon_id:
			out.push_back(w)
	out.sort_custom(self, "_by_tier")
	return out


static func _by_tier(a, b) -> bool:
	return a.tier < b.tier


# 家族是否完整：等级连续且最高到 T4（未完成的武器自动禁用，但仍可编辑）
func family_complete(weapon_id: String) -> bool:
	var ms = family_members(weapon_id)
	if ms.empty() or ms[-1].tier != 3:
		return false
	for i in ms.size():
		if ms[i].tier != ms[0].tier + i:
			return false
	return true


# 禁用（受本栏总开关控制；未完成的武器总是禁用）
func is_disabled(kind: String, id: String) -> bool:
	if kind == "weapon" and not family_complete(id):
		return true
	return kind_enabled[kind] and id in disabled[kind]


func set_disabled(kind: String, id: String, on: bool) -> void:
	disabled[kind].erase(id)
	if on:
		disabled[kind].push_back(id)
	_global_ban = null
	_ban_cache.clear()


func disabled_character_hashes() -> Array:
	var out = []
	if kind_enabled.character:
		for id in disabled.character:
			out.push_back(Keys.generate_hash(id))
	return out


static func without(arr: Array, remove: Array) -> Array:
	if remove.empty():
		return arr
	var out = []
	for x in arr:
		if not x in remove:
			out.push_back(x)
	return out


# 被禁用的道具 / 武器哈希（所有角色）
func global_ban_hashes() -> Array:
	if _global_ban != null:
		return _global_ban
	var out = []
	var isvc = _isvc()
	for it in isvc.items:
		if it != null and is_disabled("item", it.my_id):
			out.push_back(Keys.generate_hash(it.my_id))
	var seen = {}
	for w in isvc.weapons:
		if w == null:
			continue
		if not seen.has(w.weapon_id):
			seen[w.weapon_id] = is_disabled("weapon", w.weapon_id)
		if seen[w.weapon_id]:
			out.push_back(w.my_id_hash)
	_global_ban = out
	return out


# 按档案改写后的武器属性（不修改原资源）
func weapon_stats_for(w, p: Dictionary):
	var base = backup_value(w, "stats")
	if base == null:
		return null
	var s = base.duplicate()
	for f in WSTAT_FIELDS:
		if p.wstats.has(f[0]) and f[0] in s:
			match f[1]:
				"int":
					s.set(f[0], int(p.wstats[f[0]]))
				"float":
					s.set(f[0], float(p.wstats[f[0]]))
				"bool":
					s.set(f[0], bool(p.wstats[f[0]]))
	if p.scaling is Array:
		var sc = []
		for e in p.scaling:
			sc.push_back([Keys.generate_hash(e[0]), e[1]])
		s.scaling_stats = sc
	return s


# 原版运行时的属性加成用属性哈希：[[hash, 系数]] -> [[属性名, 系数]]
static func scaling_names(scaling: Array) -> Array:
	var out = []
	for e in scaling:
		out.push_back([Keys.hash_to_string.get(e[0], str(e[0])) if e[0] is int else str(e[0]), float(e[1])])
	return out


# 对象来源：原版 / dlc1、dlc2… / 模组（按资源路径；本模组新增的对象没有路径，属于模组）
static func source_of(res) -> String:
	var path = res.resource_path if res != null else ""
	if path.begins_with("res://dlcs/dlc_"):
		return "dlc" + path.get_slice("/", 3).trim_prefix("dlc_")
	if path.begins_with("res://items/") or path.begins_with("res://weapons/"):
		return "vanilla"
	return "mod"


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
func create_custom(base_id: String, suffix: String = "") -> String:
	var id = new_custom_id("character", base_id, suffix)
	if id == "":
		return ""
	var p = new_profile()
	p.custom = true
	p.num = _take_num()
	p.base = base_id
	var base = find_character(base_id)
	if base != null:
		p.name = tr(orig_name(base)) + " +"
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
			for w in backup_value(base, "starting_weapons"):
				ws.push_back(w.my_id)
			p.weapons = ws
		if p.wanted_tags == null:
			p.wanted_tags = backup_value(base, "wanted_tags").duplicate()
	else:
		p.name = tr("BE_NEW_CHARACTER")
		p.effects = []
		p.weapons = []
		p.wanted_tags = []
	profiles[id] = p
	_register_custom(id)
	_unlock_new_characters()
	return id


# 删除自定义角色；存档中进行中的一局正在使用该角色时拒绝（读档时找不到角色，那一局无法继续）
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


# 只看存档里各玩家的当前角色（不序列化整个存档：其中有循环引用）
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


# 基底不存在（来自已停用的 mod）：自定义对象不注册、不显示，档案保留，重新启用该 mod 后恢复
func base_missing(kind: String, id: String) -> bool:
	var p = profiles_of(kind).get(id)
	if p == null or p.base == "":
		return false
	var bp = profiles_of(kind).get(p.base)
	if bp != null and bp.custom:
		return p.base != id and base_missing(kind, p.base)
	return find_target(kind, p.base) == null


func _register_custom(id: String) -> void:
	var isvc = _isvc()
	if isvc == null or base_missing("character", id):
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
	c.icon = custom_icon(id, p)
	if base != null:
		c.item_appearances = base.item_appearances
	c.effects = build_effects(id, p)
	c.starting_weapons = _weapons_by_ids(p.weapons if p.weapons is Array else [])
	if c.starting_weapons.empty():
		c.starting_weapons = [load("res://weapons/melee/fist/1/fist_data.tres")]
	c.wanted_tags = p.wanted_tags.duplicate() if p.wanted_tags is Array else []


# ============================================================
# 自定义道具（同 BroLab：基底提供外观，图标可选 / 可导入）
# ============================================================
func create_custom_item(base_id: String, suffix: String = "") -> String:
	var id = new_custom_id("item", base_id, suffix)
	if id == "":
		return ""
	var p = new_profile()
	p.custom = true
	p.num = _take_num()
	p.base = base_id
	var base = find_target("item", base_id)
	if base != null:
		p.name = tr(orig_name(base)) + " +"
		p.price = int(backup_value(base, "value"))
		p.tier = int(backup_value(base, "tier"))
		p.max_nb = int(backup_value(base, "max_nb"))
		p.tags = backup_value(base, "tags").duplicate()
		p.effects = []
		for i in orig_effects(base_id).size():
			p.effects.push_back({"from": base_id, "i": i})
	else:
		p.name = tr("BE_NEW_ITEM")
		p.price = 10
		p.tier = 0
		p.effects = []
	item_profiles[id] = p
	_register_custom_item(id)
	_repool = true
	_unlock_new_characters()
	return id


func delete_custom_item(id: String) -> bool:
	if not item_profiles.has(id) or not item_profiles[id].custom:
		return false
	item_profiles.erase(id)
	disabled.item.erase(id)
	var it = _custom_items.get(id)
	_custom_items.erase(id)
	_isvc().items.erase(it)
	_repool = true
	return true


func _register_custom_items() -> void:
	for id in item_profiles:
		if item_profiles[id].custom:
			_register_custom_item(id)


func _register_custom_item(id: String) -> void:
	var isvc = _isvc()
	var p = item_profiles[id]
	if base_missing("item", id):
		return
	var it = _custom_items.get(id)
	if it == null:
		it = load("res://items/global/item_data.gd").new()
		it.my_id = id
		it.unlocked_by_default = true
		_custom_items[id] = it
	# 基础字段直接取档案（自定义道具的档案总是完整的）
	var base = find_target("item", p.base)
	it.name = p.name if p.name != "" else tr("BE_NEW_ITEM")
	it.icon = custom_icon(id, p, "item")
	it.item_appearances = base.item_appearances if base != null else []
	it.value = max(0, p.price)
	if it.tier != max(0, p.tier):
		_repool = true
	it.tier = int(clamp(p.tier, 0, 3))
	it.max_nb = p.max_nb if p.max_nb != -2 else -1
	it.tags = p.tags.duplicate() if p.tags is Array else []
	it.effects = []
	it._generate_hashes()
	if not it in isvc.items:
		isvc.items.push_back(it)
		_repool = true


# ============================================================
# 自定义武器 / 补低级版本
# ============================================================
static func tier_id(weapon_id: String, t: int, custom_family: bool) -> String:
	return weapon_id + "_" + str(t + 1) + ("" if custom_family else TIER_SUFFIX)


# 以 base_wid 家族为基底新建自定义武器（先只有基底最低的等级），返回该等级的 my_id
# 以 base_wid 家族为基底新建自定义武器：复制基底的全部等级，返回最低等级的 my_id
func create_custom_weapon(base_wid: String, suffix: String = "") -> String:
	var wid = new_custom_id("weapon", base_wid, suffix)
	var bm = _vanilla_members(base_wid)
	if wid == "" or bm.empty():
		return ""
	var f = new_family()
	f.custom = true
	f.num = _take_num()
	f.base = base_wid
	f.name = tr(orig_name(bm[0])) + " +"
	for w in bm:
		f.tiers.push_back(w.tier)
	weapon_families[wid] = f
	for t in f.tiers:
		var p = new_profile()
		p.custom = true
		weapon_profiles[tier_id(wid, t, true)] = p
	_register_weapon_families()
	_unlock_new_characters()
	return tier_id(wid, f.tiers[0], true)


# ============================================================
# 自定义对象的 id
# ============================================================
# 后缀只保留字母、数字、_（空格转为 _）
static func clean_suffix(text: String) -> String:
	var out = ""
	for ch in text.strip_edges().replace(" ", "_"):
		var c = ord(ch)
		if ch == "_" or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			out += ch
	return out


func id_taken(kind: String, id: String) -> bool:
	if kind == "weapon":
		return weapon_families.has(id) or not family_members(id).empty()
	return find_target(kind, id) != null or profiles_of(kind).has(id)


# 新对象的 id：给了后缀就用它（重复返回 ""），否则用 <基底>_<随机数>（导入时不易重复）
func new_custom_id(kind: String, base_id: String, suffix: String) -> String:
	var prefix = ID_PREFIX[kind]
	suffix = clean_suffix(suffix)
	if suffix != "":
		return "" if id_taken(kind, prefix + suffix) else prefix + suffix
	var body = base_id.trim_prefix(prefix)
	if body == "":
		body = "custom"
	var id = ""
	while id == "" or id_taken(kind, id):
		id = prefix + body + "_" + str(1000 + randi() % 9000)
	return id


func _take_num() -> int:
	next_id += 1
	return next_id - 1


# 修改自定义对象的 id 后缀；返回新 id（角色 / 道具为 my_id，武器为 weapon_id），失败返回 ""
func rename_custom(kind: String, old_id: String, suffix: String) -> String:
	suffix = clean_suffix(suffix)
	if suffix == "":
		return ""
	var new_id = ID_PREFIX[kind] + suffix
	if new_id == old_id:
		return old_id
	if id_taken(kind, new_id):
		return ""
	match kind:
		"character":
			if not (profiles.has(old_id) and profiles[old_id].custom) or is_in_saved_run(old_id):
				return ""
			_move_key(profiles, old_id, new_id)
			_rename_res(_customs, old_id, new_id)
		"item":
			if not (item_profiles.has(old_id) and item_profiles[old_id].custom):
				return ""
			_move_key(item_profiles, old_id, new_id)
			_rename_res(_custom_items, old_id, new_id)
		"weapon":
			if not is_custom_family(old_id):
				return ""
			_move_key(weapon_families, old_id, new_id)
			for t in weapon_families[new_id].tiers:
				var oid = tier_id(old_id, t, true)
				var nid = tier_id(new_id, t, true)
				_move_key(weapon_profiles, oid, nid)
				var w = _rename_res(_custom_weapons, oid, nid)
				if w != null:
					w.weapon_id = new_id
					w._generate_hashes()
				_replace_refs(oid, nid)
	_replace_refs(old_id, new_id)
	var i = disabled[kind].find(old_id)
	if i >= 0:
		disabled[kind][i] = new_id
	_global_ban = null
	_ban_cache.clear()
	_unlock_new_characters()
	return new_id


static func _move_key(d: Dictionary, old, new) -> void:
	if d.has(old):
		d[new] = d[old]
		d.erase(old)


func _rename_res(d: Dictionary, old: String, new: String):
	var r = d.get(old)
	_move_key(d, old, new)
	_orig_effects.erase(old)
	if r != null:
		r.my_id = new
		r._generate_hashes()
	return r


# 角色档案里对改名对象的引用（初始武器 / 道具、禁用列表）
func _replace_refs(old: String, new: String) -> void:
	for id in profiles:
		var p = profiles[id]
		for k in ["weapons", "ban_items", "ban_weapons"]:
			if p[k] is Array:
				for i in p[k].size():
					if str(p[k][i]) == old:
						p[k][i] = new
		for st in p.start_items:
			if st is Dictionary and str(st.get("id", "")) == old:
				st.id = new


# 可新增的等级：家族最低等级之下一级；自定义武器还可以加最高等级之上一级
func addable_tiers(weapon_id: String) -> Array:
	var ms = family_members(weapon_id)
	if ms.empty():
		return []
	var out = []
	if ms[0].tier > 0:
		out.push_back(ms[0].tier - 1)
	if is_custom_family(weapon_id) and ms[-1].tier < 3:
		out.push_back(ms[-1].tier + 1)
	return out


func add_weapon_tier(weapon_id: String, t: int) -> String:
	if not t in addable_tiers(weapon_id):
		return ""
	if not weapon_families.has(weapon_id):
		weapon_families[weapon_id] = new_family()
	var f = weapon_families[weapon_id]
	if not t in f.tiers:
		f.tiers.push_back(t)
		f.tiers.sort()
	var id = tier_id(weapon_id, t, f.custom)
	var p = new_profile()
	p.custom = true
	weapon_profiles[id] = p
	_register_weapon_families()
	_unlock_new_characters()
	return id


# 删除自定义等级（只能删两端，保持连续）；自定义武器删到最后一级时整把删除
func delete_weapon_tier(id: String) -> bool:
	var w = find_target("weapon", id)
	if w == null or not _custom_weapons.has(id):
		return false
	var ms = family_members(w.weapon_id)
	if w != ms[0] and w != ms[-1]:
		return false
	var f = weapon_families[w.weapon_id]
	f.tiers.erase(w.tier)
	_unregister_weapon(id)
	if f.custom and f.tiers.empty():
		weapon_families.erase(w.weapon_id)
		disabled.weapon.erase(w.weapon_id)
	_link_family(w.weapon_id)
	return true


func delete_custom_weapon(weapon_id: String) -> bool:
	if not is_custom_family(weapon_id):
		return false
	for w in family_members(weapon_id):
		_unregister_weapon(w.my_id)
	weapon_families.erase(weapon_id)
	disabled.weapon.erase(weapon_id)
	return true


func _unregister_weapon(id: String) -> void:
	var w = _custom_weapons.get(id)
	_custom_weapons.erase(id)
	weapon_profiles.erase(id)
	_orig_effects.erase(id)
	if w != null:
		_isvc().weapons.erase(w)
	_repool = true


func _vanilla_members(weapon_id: String) -> Array:
	var out = []
	for w in family_members(weapon_id):
		if not _custom_weapons.has(w.my_id):
			out.push_back(w)
	return out


# 新等级的模板：自定义武器取基底家族同级（没有则最近一级），补的低级版本取原家族最低一级
func _weapon_template(weapon_id: String, t: int):
	var f = weapon_families[weapon_id]
	var ms = _vanilla_members(f.base if f.custom else weapon_id)
	var best = null
	for w in ms:
		if best == null or abs(w.tier - t) < abs(best.tier - t):
			best = w
	return best


func _register_weapon_families() -> void:
	for wid in weapon_families:
		var f = weapon_families[wid]
		for t in f.tiers:
			_register_custom_weapon(wid, t)
		_link_family(wid)


func _register_custom_weapon(weapon_id: String, t: int) -> void:
	var f = weapon_families[weapon_id]
	var tpl = _weapon_template(weapon_id, t)
	if tpl == null:
		return
	var id = tier_id(weapon_id, t, f.custom)
	var w = _custom_weapons.get(id)
	if w == null:
		w = load("res://items/global/weapon_data.gd").new()
		_custom_weapons[id] = w
	w.my_id = id
	w.weapon_id = weapon_id
	w.tier = t
	w.unlocked_by_default = true
	w.type = tpl.type
	w.scene = tpl.scene
	w.stats = backup_value(tpl, "stats").duplicate()
	w.sets = backup_value(tpl, "sets").duplicate()
	w.effects = backup_value(tpl, "effects").duplicate()
	w.value = int(round(backup_value(tpl, "value") * pow(2, t - tpl.tier)))
	w.name = backup_value(tpl, "name")
	w.icon = tpl.icon
	if f.custom:
		w.icon = custom_icon(weapon_id, f, "weapon")
		w.name = f.name if f.name != "" else tr("BE_NEW_WEAPON")
	w.add_to_chars_as_starting = []
	w.upgrades_into = null
	w._generate_hashes()
	_orig_effects.erase(id)
	if not weapon_profiles.has(id):
		var p = new_profile()
		p.custom = true
		weapon_profiles[id] = p
	if not w in _isvc().weapons:
		_isvc().weapons.push_back(w)
		_repool = true


# 升级链：自定义等级指向下一级；原版成员只改 previous_upgrade（无需备份）
func _link_family(weapon_id: String) -> void:
	var ms = family_members(weapon_id)
	for i in ms.size():
		var w = ms[i]
		if i == 0:
			w.previous_upgrade = null
		if _custom_weapons.has(w.my_id):
			w.upgrades_into = ms[i + 1] if i + 1 < ms.size() else null
		if i + 1 < ms.size():
			ms[i + 1].previous_upgrade = w


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
func library(with_weapons: bool = false) -> Array:
	if with_weapons:
		if _weapon_library == null:
			var sources = _library_sources()
			for w in _isvc().weapons:
				if w != null and not w.effects.empty() and not _custom_weapons.has(w.my_id):
					sources.push_back([w.my_id, orig_name(w), orig_effects(w.my_id)])
			_weapon_library = Catalog.build_library(sources)
		return _weapon_library
	if _library == null:
		_library = Catalog.build_library(_library_sources())
	return _library


func _library_sources() -> Array:
	var isvc = _isvc()
	var sources = []
	for c in isvc.characters:
		if c != null and not is_custom(c.my_id):
			sources.push_back([c.my_id, orig_name(c), orig_effects(c.my_id)])
	for it in isvc.items:
		if it != null and not is_custom(it.my_id):
			sources.push_back([it.my_id, orig_name(it), orig_effects(it.my_id)])
	return sources


# 蓝图扳机的模板：custom_key -> spec（找不到返回 null）
func trigger_template(custom_key: String):
	for entry in library():
		var e = entry.effect
		if e.custom_key == custom_key and Catalog.is_plain_effect(e) and e.storage_method == 1 and Catalog.is_stat_key(e.key):
			return {"from": entry.from, "i": entry.i}
	return null


# 角色的原始名称（不受档案改名影响）
func orig_name(c) -> String:
	return backup_value(c, "name")


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
	var out = global_ban_hashes().duplicate()
	var p = profiles.get(c.my_id)
	if p != null and ((p.enabled and kind_enabled.character) or p.custom):
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
	var en_col = locales.find("en") + 1 if "en" in locales else -1
	for li in range(1, lines.size()):
		var row = _parse_csv_line(lines[li].strip_edges())
		if row.size() < 2 or row[0].strip_edges() == "":
			continue
		for i in range(1, header.size()):
			var value = row[i].c_unescape() if i < row.size() else ""
			# 缺少翻译：中文系回退到中文，其他语言回退到英文（没有英文时用第一列）
			if value == "":
				var locale = locales[i - 1]
				var fb = 1 if locale.begins_with("zh") or en_col < 0 or en_col >= row.size() or row[en_col] == "" else en_col
				value = row[fb].c_unescape()
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
	ui.connect("tree_exited", self, "_on_editor_exited")
	_block_input(true)


# 编辑器打开期间：原版的焦点模拟器（把 WASD / 方向键当作界面导航并吞掉按键）与选择界面本身
# （松开 Esc 返回上一页）都不处理输入，文字输入框才能正常输入字母
var _input_blocked: Array = []
var _unblock_pending := false
# [动作, 事件]：编辑器打开期间从 ui_* 动作中移除的字母 / 数字按键
var _removed_keys: Array = []


func _block_input(on: bool) -> void:
	if on:
		_unblock_pending = false
		for n in _input_blocked:
			if is_instance_valid(n):
				n.set_process_input(true)
		_input_blocked = []
		var stack = [get_tree().root]
		var scene = get_tree().current_scene
		while not stack.empty():
			var n = stack.pop_back()
			if (n is FocusEmulator or n == scene) and n.is_processing_input():
				n.set_process_input(false)
				_input_blocked.push_back(n)
			for c in n.get_children():
				stack.push_back(c)
		for action in InputMap.get_actions():
			if not str(action).begins_with("ui_") or action == "ui_cancel":
				continue
			for ev in InputMap.get_action_list(action):
				if ev is InputEventKey and _is_text_key(ev):
					InputMap.action_erase_event(action, ev)
					_removed_keys.push_back([action, ev])
	else:
		for r in _removed_keys:
			if InputMap.has_action(r[0]) and not InputMap.action_has_event(r[0], r[1]):
				InputMap.action_add_event(r[0], r[1])
		_removed_keys = []
		for n in _input_blocked:
			if is_instance_valid(n):
				n.set_process_input(true)
		_input_blocked = []


static func _is_text_key(ev: InputEventKey) -> bool:
	var sc = ev.physical_scancode if ev.scancode == 0 else ev.scancode
	return (sc >= KEY_A and sc <= KEY_Z) or (sc >= KEY_0 and sc <= KEY_9) or sc == KEY_SPACE


# 编辑器关闭：等 Esc 松开后再恢复（否则松开 Esc 会被选择界面当作"返回"）
func _on_editor_exited() -> void:
	_unblock_pending = true


func _process(_delta: float) -> void:
	if _unblock_pending and not Input.is_action_pressed("ui_cancel"):
		_unblock_pending = false
		_block_input(false)


# ============================================================
# 自定义角色图标：导入的图片，或原版贴图 + 右下角编号（与原角色区分）
# ============================================================
const ICON_DIR = "user://Mojimoon-BroEditor/icons/"
const ICON_SIZE = 96
# 3×5 点阵数字
const DIGITS = ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]
var _icon_cache: Dictionary = {}


# 自定义对象的图标：导入的图片 / 选的图标 / 基底的图标（后两者加编号）
func custom_icon(id: String, p: Dictionary, kind: String = "character") -> Texture:
	if p.icon.begins_with("file:"):
		var t = _load_icon_file(p.icon.substr(5))
		if t != null:
			return t
	var src = _find_any(p.icon) if p.icon != "" and not p.icon.begins_with("file:") else null
	if src == null and kind == "weapon":
		var bm = _vanilla_members(p.base)
		src = bm[0] if not bm.empty() else null
	elif src == null:
		src = find_target(kind, p.base)
	var tex = src.icon if src != null else load("res://items/characters/well_rounded/well_rounded_icon.png")
	return numbered_icon(tex, p.num if p.num > 0 else _id_number(id))


func _load_icon_file(name: String):
	var key = "file:" + name
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img = Image.new()
	if img.load(ICON_DIR + name) != OK:
		return null
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	_icon_cache[key] = tex
	return tex


# 导入图片：缩放到 96×96（保持比例、居中）存入 user://，返回档案 icon 字段的值；失败返回 ""
func import_icon(path: String, id: String) -> String:
	var img = Image.new()
	if img.load(path) != OK:
		return ""
	img.convert(Image.FORMAT_RGBA8)
	var s = float(ICON_SIZE) / max(img.get_width(), img.get_height())
	img.resize(int(max(1, img.get_width() * s)), int(max(1, img.get_height() * s)), Image.INTERPOLATE_BILINEAR)
	var out = Image.new()
	out.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2(Vector2.ZERO, img.get_size()), (Vector2(ICON_SIZE, ICON_SIZE) - img.get_size()) / 2)
	var dir = Directory.new()
	if not dir.dir_exists(ICON_DIR):
		dir.make_dir_recursive(ICON_DIR)
	var name = id + "_" + str(OS.get_unix_time()) + ".png"
	if out.save_png(ICON_DIR + name) != OK:
		return ""
	return "file:" + name


func numbered_icon(tex: Texture, n: int) -> Texture:
	if tex == null or n <= 0 or hide_numbers:
		return tex
	var key = str(tex.get_rid().get_id()) + "#" + str(n)
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img: Image = tex.get_data()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var digits = str(n)
	var scale = max(2, int(img.get_width() / 24))
	var w = digits.length() * 4 * scale - scale
	var x0 = img.get_width() - w - scale * 2
	var y0 = img.get_height() - 5 * scale - scale * 2
	img.lock()
	# 先画黑色描边，再画白色数字
	for pass_i in 2:
		var col = Color(0, 0, 0, 1) if pass_i == 0 else Color(1, 0.85, 0.3, 1)
		var grow = scale if pass_i == 0 else 0
		for di in digits.length():
			var pat = DIGITS[int(digits[di])]
			for py in 5:
				for px in 3:
					if pat[py * 3 + px] != "1":
						continue
					var rx = x0 + (di * 4 + px) * scale
					var ry = y0 + py * scale
					for yy in range(ry - grow, ry + scale + grow):
						for xx in range(rx - grow, rx + scale + grow):
							if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
								img.set_pixel(xx, yy, col)
	img.unlock()
	var out = ImageTexture.new()
	out.create_from_image(img, Texture.FLAG_FILTER)
	_icon_cache[key] = out
	return out


# ============================================================
# 效果文本：原版（及本 mod）的效果脚本用自身的 get_text；其他 mod 的效果脚本按原版默认规则渲染，
# 避免它们的自定义文本在编辑器里（没有本局数据时）出错
# ============================================================
const TEXT_SAFE_DIRS = ["res://items/", "res://dlcs/", "res://effects/", "res://weapons/", "res://mods-unpacked/Mojimoon-BroEditor/"]


func effect_text(e, colored: bool = true) -> String:
	if e == null:
		return ""
	var path = e.get_script().resource_path if e.get_script() != null else ""
	for d in TEXT_SAFE_DIRS:
		if path.begins_with(d):
			return e.get_text(0, colored)
	var key_text = str(e.key).to_upper() if str(e.text_key) == "" else str(e.text_key).to_upper()
	return _autoload("Text").text(key_text, [str(e.value), tr(str(e.key).to_upper())])


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


# ============================================================
# 蓝图：商店阶段事件
# ============================================================
func fire_shop(event: String, player_index: int) -> void:
	if runtime == null:
		return
	if runtime.wave_over:
		runtime.rebuild_all()
	runtime.fire(event, player_index)


# ============================================================
# 开局状态（同 cave-modtools）：材料、等级（直接 / 结算）、箱子、额外禁用次数、起始波次、波次时长
# ============================================================
func _player_profile(rd, player_index: int):
	if player_index < 0 or player_index >= rd.players_data.size():
		return null
	var c = rd.players_data[player_index].current_character
	if c == null:
		return null
	var p = profiles.get(c.my_id)
	if p == null or not ((p.enabled and kind_enabled.character) or p.custom):
		return null
	return p


# RunData.add_starting_items_and_weapons 之后（选完武器 / 重新开始）
func apply_start_state() -> void:
	var rd = _autoload("RunData")
	_pending_start = {}
	for i in rd.get_player_count():
		var p = _player_profile(rd, i)
		if p == null:
			continue
		rd.players_data[i].gold += max(0, start_value(p, "materials"))
		var levels = max(0, start_value(p, "levels"))
		if levels > 0 and not start_value(p, "level_settle"):
			rd.players_data[i].current_level += levels
			levels = 0
		var pend = {"levels": levels, "crates": max(0, start_value(p, "crates")), "legendary": max(0, start_value(p, "legendary_crates"))}
		if pend.levels + pend.crates + pend.legendary > 0:
			_pending_start[i] = pend


# 第一波开始：结算升级（波末选择升级）、开局箱子（波末开箱）
func apply_pending_start(main: Node) -> void:
	if _pending_start.empty():
		return
	var rd = _autoload("RunData")
	var isvc = _isvc()
	for i in _pending_start:
		if i >= rd.get_player_count():
			continue
		var pend = _pending_start[i]
		for _l in pend.levels:
			rd.level_up(i)
		for k in [["crates", Keys.consumable_item_box_hash], ["legendary", Keys.consumable_legendary_item_box_hash]]:
			var data = isvc.get_element(isvc.consumables, k[1])
			if data == null:
				continue
			for _c in pend[k[0]]:
				var ctp = UpgradesUI.ConsumableToProcess.new()
				ctp.consumable_data = data
				ctp.player_index = i
				main._consumables_to_process[i].push_back(ctp)
				main._things_to_process_player_containers[i].consumables.add_element(data)
	_pending_start = {}


# 选定难度后（原版在此时发放禁用次数）/ 重新开始本局
func apply_start_bans() -> void:
	var rd = _autoload("RunData")
	if not rd.is_ban_active_in_current_run():
		return
	for i in rd.get_player_count():
		var p = _player_profile(rd, i)
		if p != null:
			rd.players_data[i].remaining_ban_token += max(0, start_value(p, "ban_tokens"))


# 选定难度后：起始波次（取玩家 1 的角色；超过最后一波即为无尽）
func apply_start_wave() -> void:
	var rd = _autoload("RunData")
	var dbg = _autoload("DebugService")
	var p = _player_profile(rd, 0)
	var w = int(start_value(p, "start_wave")) if p != null else 1
	if w > 1:
		dbg.starting_wave = w
		rd.current_wave = w
		rd.is_endless_run = w > rd.nb_of_waves
		_start_wave_set = true
	else:
		clear_start_wave()


# 新一局（回到选角界面）：撤销上一局设置的起始波次
func clear_start_wave() -> void:
	if _start_wave_set:
		_autoload("DebugService").starting_wave = 1
		_start_wave_set = false


# 每波开始前（main._ready 之前）：波次时长 = 固定值，或原版时长 + 增减
func apply_wave_duration() -> void:
	var rd = _autoload("RunData")
	var dbg = _autoload("DebugService")
	var p = _player_profile(rd, 0)
	var lock = int(start_value(p, "wave_lock")) if p != null else 0
	var delta = int(start_value(p, "wave_delta")) if p != null else 0
	if lock > 0:
		dbg.custom_wave_duration = lock
		_wave_duration_set = true
	elif delta != 0:
		var base = 60
		var wd = _autoload("ZoneService").get_wave_data(rd.current_zone, rd.current_wave)
		if wd != null and "wave_duration" in wd:
			base = int(wd.wave_duration)
		dbg.custom_wave_duration = max(1, base + delta)
		_wave_duration_set = true
	elif _wave_duration_set:
		dbg.custom_wave_duration = -1
		_wave_duration_set = false
