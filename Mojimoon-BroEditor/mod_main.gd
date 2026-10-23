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
# 蓝图分享码（只含节点图）
const GRAPH_PREFIX = "BEB:"
# 分享码正文：PACK + base64(deflate(JSON))；不以 PACK 开头的是旧格式 base64(JSON)（JSON 的 base64 总以 "ey" 开头）
const PACK = "z"
const BUNDLE_KEYS = {"character": "profiles", "item": "items", "weapon": "weapons"}
const MAX_DESC = 300

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const GraphEffect = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
const Runtime = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/runtime.gd")
const BurnChance = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/burn_chance_effect.gd")
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
	["projectile_speed", "int", ""], ["attack_type", "int", ""], ["alternate_attack_type", "bool", ""],
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
var groups: Dictionary = {}	# 内容分组：分组 id -> {"name", "members": [[种类, id]...], "locked"}
var weapon_sets: Dictionary = {}	# 武器套装：套装 id -> 档案（见 new_set）
var custom_tags: Dictionary = {}	# 自定义标签：键名 -> 名称（所有道具 / 角色可用；随 profiles.json 保存）
# 效果库去重（同脚本、同 key 的效果只保留一条）；默认关：保留全部，包括同一武器各等级的效果
var library_dedup := false
# 更详细的键名（只在显示键名时生效）：效果显示全部键名、编辑时显示字段名
var debug_detail := false
# 编辑器字体大小 80–125%（标题行与设置弹窗不缩放）
var font_scale: int = 100

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
# 本局商店的变化（蓝图效果"本局商店中出现 / 不再出现"）：每名玩家 {"add": [道具 id], "remove": [道具 id]}，随一局存档保存
var run_shop: Array = new_run_shop()
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
	ModLoaderMod.install_script_extension(dir + "singletons/weapon_service.gd")
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
	_register_enemy_behavior()
	# 自定义角色必须在 ProgressData 读档之前注册（存档里的本局可能就是自定义角色）
	_register_customs()
	# DLC 角色在 ProgressData 就绪后才加入：本帧结束后再应用档案
	call_deferred("apply_all")


# 挂在敌人身上的效果行为（蓝图的命中 / 首次命中 / 点燃扳机与"受到伤害提高"效果）：注册到原版 EffectBehaviorService
var _behavior_data = null


func _register_enemy_behavior() -> void:
	var svc = _autoload("EffectBehaviorService")
	if svc == null:
		return
	if _behavior_data == null:
		_behavior_data = load("res://items/global/effect_behavior_data.gd").new()
		_behavior_data.scene = load("res://mods-unpacked/Mojimoon-BroEditor/graph/enemy_behavior.tscn")
	if not _behavior_data in svc.enemy_effect_behaviors:
		svc.enemy_effect_behaviors.push_back(_behavior_data)


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
		"fuse": [],	# 角色：融合的角色 id（开局获得它们的全部效果，同 GMO / cave-modtools）
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
		"replaced_by": null,	# 道具：移除后变成的道具 id（"" = 无；null = 不修改）
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
	for k in ["start_items", "ban_items", "ban_weapons", "fuse"]:
		if not out[k] is Array:
			out[k] = []
	var fuse = []
	for id in out.fuse:
		if not str(id) in fuse:
			fuse.push_back(str(id))
	out.fuse = fuse
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
	if out.replaced_by != null:
		out.replaced_by = str(out.replaced_by)
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
# 武器套装档案：bonuses 为 null 时用原版（自定义套装：基底）的效果，否则为每一级的 spec 列表
static func new_set() -> Dictionary:
	return {"custom": false, "base": "", "name": "", "bonuses": null}


static func normalize_set(s) -> Dictionary:
	var out = new_set()
	if not s is Dictionary:
		return out
	out.custom = bool(s.get("custom", false))
	out.base = str(s.get("base", ""))
	out.name = str(s.get("name", ""))
	if s.get("bonuses") is Array:
		out.bonuses = []
		for lv in s.bonuses:
			out.bonuses.push_back(lv.duplicate(true) if lv is Array else [])
	return out


static func new_family() -> Dictionary:
	return {"custom": false, "base": "", "name": "", "icon": "", "sets": null, "tiers": [], "num": 0}


# 保存 / 分享时去掉与默认值相同的字段（读取时 normalize_* 会补齐）
static func compact(d: Dictionary, defaults: Dictionary) -> Dictionary:
	var out = {}
	for k in d:
		if not defaults.has(k) or JSON.print(d[k]) != JSON.print(defaults[k]):
			out[k] = d[k]
	return out


static func compact_all(ps: Dictionary, defaults: Dictionary) -> Dictionary:
	var out = {}
	for id in ps:
		out[id] = compact(ps[id], defaults) if ps[id] is Dictionary else ps[id]
	return out


static func pack(data) -> String:
	return PACK + Marshalls.raw_to_base64(JSON.print(data).to_utf8().compress(File.COMPRESSION_DEFLATE))


# 分享码正文 -> 解析结果（无法解析返回 null）；兼容旧的未压缩格式
static func unpack(body: String):
	var text = ""
	if body.begins_with(PACK):
		var raw = Marshalls.base64_to_raw(body.substr(PACK.length()))
		if raw.empty():
			return null
		text = raw.decompress_dynamic(16 * 1024 * 1024, File.COMPRESSION_DEFLATE).get_string_from_utf8()
	else:
		text = Marshalls.base64_to_utf8(body)
	var parsed = JSON.parse(text)
	return parsed.result if parsed.error == OK else null


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


# 重置一整栏。parts：disabled = 禁用状态，edits = 对原版对象的修改（武器含补的低级版本、家族名称 / 类别），
# custom = 自定义对象（并重置编号：从剩余的其他栏自定义对象之后重新开始）。
# 存档中进行中的一局正在使用的自定义角色保留；返回保留的个数
func reset_kind(kind: String, parts: Array) -> int:
	var kept = 0
	var ps = profiles_of(kind)
	if "custom" in parts:
		match kind:
			"character":
				for id in ps.keys():
					if ps[id].custom and not delete_custom(id):
						kept += 1
			"item":
				for id in ps.keys():
					if ps[id].custom:
						var _ok = delete_custom_item(id)
			"weapon":
				for wid in weapon_families.keys():
					if weapon_families[wid].custom:
						var _ok = delete_custom_weapon(wid)
		next_id = 1
		for e in custom_entries():
			var num = weapon_families[e[1]].num if e[0] == "weapon" else profiles_of(e[0])[e[1]].num
			next_id = int(max(next_id, num + 1))
	if "edits" in parts:
		if kind == "weapon":
			for wid in weapon_families.keys():
				var f = weapon_families[wid]
				if f.custom:
					continue
				for t in f.tiers:
					_unregister_weapon(tier_id(wid, t, false))
				weapon_families.erase(wid)
				_link_family(wid)
		for id in ps.keys():
			if not ps[id].custom:
				ps.erase(id)
	if "disabled" in parts:
		disabled[kind] = []
	_library = null
	_weapon_library = null
	return kept


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
	custom_tags = {}
	weapon_sets = {}
	groups = {}
	sources = {}
	_load_main_file()
	_load_custom_files()
	# 读到的是自修改层；再叠加数据包得出生效层（注册与应用在 _ready / apply_all 里）
	own = new_layer()
	for k in LAYER_KEYS:
		own[k] = eff()[k].duplicate(true)
	_load_packs()
	compose(false)


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
	library_dedup = bool(settings.get("library_dedup", false)) if settings is Dictionary else false
	debug_detail = bool(settings.get("debug_detail", false)) if settings is Dictionary else false
	font_scale = int(clamp(int(settings.get("font_scale", 100)), 80, 125)) if settings is Dictionary else 100
	var kinds = settings.get("kinds", {}) if settings is Dictionary else {}
	for k in KINDS:
		kind_enabled[k] = bool(kinds.get(k, true)) if kinds is Dictionary else true
	var src = parsed.result.get("sources", {})
	if src is Dictionary:
		for k in src:
			sources[str(k)] = str(src[k])
	var gs = parsed.result.get("groups", {})
	if gs is Dictionary:
		for k in gs:
			groups[str(k)] = normalize_group(gs[k])
	var sets = parsed.result.get("sets", {})
	if sets is Dictionary:
		for k in sets:
			weapon_sets[str(k)] = normalize_set(sets[k])
	var tags = parsed.result.get("tags", {})
	if tags is Dictionary:
		for k in tags:
			custom_tags[str(k)] = str(tags[k])
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
		return {"kind": kind, "id": id, "family": compact(weapon_families[id], new_family()), "tiers": compact_all(tiers, new_profile())}
	return {"kind": kind, "id": id, "profile": compact(profiles_of(kind)[id], new_profile())}


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
# 保存自修改层（先把生效层上的编辑写回）
func save_profiles() -> void:
	capture()
	var e = eff()
	profiles = own.profiles
	item_profiles = own.items
	weapon_profiles = own.weapons
	weapon_families = own.families
	weapon_sets = own.sets
	custom_tags = own.tags
	_write_profiles()
	profiles = e.profiles
	item_profiles = e.items
	weapon_profiles = e.weapons
	weapon_families = e.families
	weapon_sets = e.sets
	custom_tags = e.tags


func _write_profiles() -> void:
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
				main[pair[0]][id] = compact(pair[1][id], new_profile())
	for id in weapon_profiles:
		if not custom_tiers.has(id):
			main.weapons[id] = compact(weapon_profiles[id], new_profile())
	for wid in weapon_families:
		if not weapon_families[wid].custom:
			main.families[wid] = compact(weapon_families[wid], new_family())
	main["version"] = 1
	main["next_id"] = next_id
	main["settings"] = {"debug": debug, "debug_detail": debug_detail, "font_scale": font_scale, "hide_numbers": hide_numbers, "library_dedup": library_dedup, "kinds": kind_enabled}
	main["disabled"] = disabled
	main["tags"] = custom_tags
	main["sets"] = compact_all(weapon_sets, new_set())
	main["groups"] = groups
	main["sources"] = sources
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
	return SHARE_PREFIX + pack({"kind": kind, "id": id, "profile": compact(ps[id], new_profile())})


# 蓝图分享码：空图返回 ""
static func export_graph(g) -> String:
	if not g is Dictionary or g.get("nodes", []).empty():
		return ""
	return GRAPH_PREFIX + pack(g)


# 读取蓝图分享码；无法识别返回 null
static func import_graph(code: String):
	code = code.strip_edges()
	if not code.begins_with(GRAPH_PREFIX):
		return null
	var g = unpack(code.substr(GRAPH_PREFIX.length()))
	if g == null:
		return null
	return normalize_profile({"graph": g}).graph


# 批量导出：kind = "" 时导出三栏全部（含禁用列表与依赖，见 bundle_data）
func export_bundle(kind: String) -> String:
	var kinds = KINDS if kind == "" else [kind]
	var dis = {}
	for k in kinds:
		dis[k] = disabled[k]
	var data = bundle_data(share_entries(kinds))
	if data.empty() and not _any_disabled(dis):
		return ""
	var prefix = ALL_PREFIX if kind == "" else BUNDLE_PREFIX[kind]
	# 依赖了其他栏的自定义对象（如角色的初始武器是自定义武器）时用三栏格式，导入时才会一并读取
	for k in KINDS:
		if not k in kinds and (data.has(BUNDLE_KEYS[k]) or (k == "weapon" and data.has("families"))):
			prefix = ALL_PREFIX
	data["disabled"] = dis
	return prefix + pack(data)


# 可分享的对象（默认取生效层）：[[种类, id]...]，武器按家族 weapon_id
func share_entries(kinds: Array = KINDS, l = null) -> Array:
	return layer_units(l if l != null else eff(), kinds)


# 等级 id -> 家族 weapon_id（未登记的等级按 id 推断：去掉 _broeditor 与末尾等级号）
func weapon_family_of(tid: String) -> String:
	var r = find_target("weapon", tid)
	if r != null:
		return r.weapon_id
	tid = tid.trim_suffix(TIER_SUFFIX)
	return tid.substr(0, tid.find_last("_"))


# 选中对象的批量码数据（BEA 格式，导入用 import_bundle / install_pack），l = 取数据的层（默认生效层），并带上依赖：
#   武器所属的已修改 / 自定义套装，角色 / 道具用到的自定义标签，
#   档案里引用到的其他自定义对象（效果来源、初始武器 / 道具、融合角色等）与自定义图标（icons：文件名 -> base64 PNG）
func bundle_data(sel: Array, l = null) -> Dictionary:
	if l == null:
		l = eff()
	var data = {"profiles": {}, "items": {}, "weapons": {}, "families": {}, "sets": {}, "tags": {}, "icons": {}}
	var queue = sel.duplicate()
	var seen = {}
	while not queue.empty():
		var e = queue.pop_front()
		var kind = str(e[0])
		var id = str(e[1])
		if seen.has(kind + ":" + id):
			continue
		seen[kind + ":" + id] = true
		var refs = []
		match kind:
			"set":
				if l.sets.has(id):
					data.sets[id] = compact(l.sets[id], new_set())
					refs.push_back(l.sets[id])
			"weapon":
				var f = l.families.get(id)
				if f != null:
					data.families[id] = compact(f, new_family())
					refs.push_back(f)
				for tid in l.weapons:
					if weapon_family_of(tid) == id:
						data.weapons[tid] = compact(l.weapons[tid], new_profile())
						refs.push_back(l.weapons[tid])
				for sid in _family_set_ids(id, l):
					queue.push_back(["set", sid])
			_:
				var ps = l[BUNDLE_KEYS[kind]]
				if ps.has(id):
					data[BUNDLE_KEYS[kind]][id] = compact(ps[id], new_profile())
					refs.push_back(ps[id])
		var strs = []
		for r in refs:
			_strings_in(r, strs)
		for s in strs:
			queue += _ref_entries(s, data, l)
	for k in data.keys():
		if data[k].empty():
			data.erase(k)
	return data


# 武器家族的套装：家族档案指定的，否则原版（自定义武器：基底家族）的
func _family_set_ids(wid: String, l: Dictionary) -> Array:
	var f = l.families.get(wid)
	if f != null and f.sets is Array:
		return f.sets
	var vm = _vanilla_members(f.base if f != null and f.custom else wid)
	var out = []
	if not vm.empty():
		for s in vm[0].sets:
			if s != null:
				out.push_back(s.my_id)
	return out


static func _strings_in(v, out: Array) -> void:
	if v is String:
		out.push_back(v)
	elif v is Array:
		for x in v:
			_strings_in(x, out)
	elif v is Dictionary:
		for k in v:
			_strings_in(v[k], out)


# 档案里的一个字符串指向的依赖：标签 / 图标直接写入 data，对象与套装返回待处理的 [种类, id]
func _ref_entries(s: String, data: Dictionary, l: Dictionary) -> Array:
	if l.tags.has(s):
		data.tags[s] = l.tags[s]
	elif s.begins_with("file:"):
		var name = s.substr(5)
		var file = File.new()
		if not data.icons.has(name) and file.open(ICON_DIR + name, File.READ) == OK:
			data.icons[name] = Marshalls.raw_to_base64(file.get_buffer(file.get_len()))
			file.close()
	elif l.sets.has(s.get_slice(SET_LEVEL_SEP, 0)):
		return [["set", s.get_slice(SET_LEVEL_SEP, 0)]]
	elif l.profiles.has(s) and l.profiles[s].custom:
		return [["character", s]]
	elif l.items.has(s) and l.items[s].custom:
		return [["item", s]]
	elif l.families.has(s) and l.families[s].custom:
		return [["weapon", s]]
	elif l.weapons.has(s) and l.families.has(weapon_family_of(s)) and l.families[weapon_family_of(s)].custom:
		return [["weapon", weapon_family_of(s)]]
	return []


# ============================================================
# 数据包与版本
# ============================================================
# 三层：自修改层 own（编辑器里的修改，存 profiles.json 与 custom/）、下载的数据包 packs（各存 packs/<id>.json）、
# 生效层（profiles / item_profiles / weapon_profiles / weapon_families / weapon_sets / custom_tags，游戏与编辑器使用）。
# 对象（角色 / 道具 / 武器家族）按 sources 选用版本："self" / "vanilla" / 包 id；没有记录时有自修改版用自修改版，否则原版。
# compose() 由 own + packs + sources 生成生效层；capture() 把生效层上的编辑写回 own：
#   数据包版本被编辑后，编辑结果成为自修改版（覆盖原有的），并改用自修改版。
# 套装：自修改层优先，其次是启用中的数据包对象引用到的包内套装（新下载的包优先）；标签同理。
const PACK_DIR = "user://Mojimoon-BroEditor/packs/"
const LAYER_KEYS = ["profiles", "items", "weapons", "families", "sets", "tags"]
var own: Dictionary = new_layer()
var packs: Dictionary = {}	# 包 id -> {"meta": {id, title, author, desc, kinds, contents, created, installed...}, "data": 层}
var sources: Dictionary = {}	# "种类:id" -> "self" / "vanilla" / 包 id
var _set_src: Dictionary = {}	# 生效的包内套装 id -> 包 id（compose 得出）
var _tag_src: Dictionary = {}	# 生效的包内标签 -> 包 id


static func new_layer() -> Dictionary:
	return {"profiles": {}, "items": {}, "weapons": {}, "families": {}, "sets": {}, "tags": {}}


# 生效层（引用当前的字典，不是副本）
func eff() -> Dictionary:
	return {"profiles": profiles, "items": item_profiles, "weapons": weapon_profiles, "families": weapon_families, "sets": weapon_sets, "tags": custom_tags}


# 分享码 / 包文件里的数据 -> 层（补齐字段）
static func normalize_layer(d) -> Dictionary:
	var out = new_layer()
	if not d is Dictionary:
		return out
	for k in ["profiles", "items", "weapons"]:
		if d.get(k) is Dictionary:
			for id in d[k]:
				out[k][str(id)] = normalize_profile(d[k][id])
	if d.get("families") is Dictionary:
		for id in d.families:
			out.families[str(id)] = normalize_family(d.families[id])
	if d.get("sets") is Dictionary:
		for id in d.sets:
			out.sets[str(id)] = normalize_set(d.sets[id])
	if d.get("tags") is Dictionary:
		for id in d.tags:
			out.tags[str(id)] = str(d.tags[id])
	return out


# 层 -> 存储格式（去掉默认字段）
static func compact_layer(l: Dictionary) -> Dictionary:
	return {
		"profiles": compact_all(l.profiles, new_profile()), "items": compact_all(l.items, new_profile()),
		"weapons": compact_all(l.weapons, new_profile()), "families": compact_all(l.families, new_family()),
		"sets": compact_all(l.sets, new_set()), "tags": l.tags.duplicate(),
	}


# 层里的对象（有修改的）
func layer_units(l: Dictionary, kinds: Array = KINDS) -> Array:
	var out = []
	var seen = {}
	for k in kinds:
		var ids = []
		if k == "weapon":
			ids = l.families.keys()
			for tid in l.weapons:
				ids.push_back(weapon_family_of(tid))
		else:
			ids = l[BUNDLE_KEYS[k]].keys()
		for id in ids:
			if not seen.has(k + ":" + id) and unit_value(l, k, id) != null:
				seen[k + ":" + id] = true
				out.push_back([k, id])
	return out


# 对象在层里的值（去掉默认字段；没有修改返回 null）。武器：{"family": 家族档案, "tiers": {等级 id: 档案}}
func unit_value(l: Dictionary, kind: String, id: String):
	if kind != "weapon":
		var p = l[BUNDLE_KEYS[kind]].get(id)
		var c = compact(p, new_profile()) if p is Dictionary else {}
		return c if not c.empty() else null
	var f = l.families.get(id)
	var fc = compact(f, new_family()) if f is Dictionary else {}
	var tiers = {}
	for tid in l.weapons:
		if weapon_family_of(tid) == id:
			var c = compact(l.weapons[tid], new_profile())
			# 自定义等级注册时自动建的空档案不算修改
			if not c.empty() and c.keys() != ["custom"]:
				tiers[tid] = c
	if fc.empty() and tiers.empty():
		return null
	return {"family": fc, "tiers": tiers}


func _set_unit(l: Dictionary, kind: String, id: String, v) -> void:
	if kind != "weapon":
		l[BUNDLE_KEYS[kind]].erase(id)
		if v != null:
			l[BUNDLE_KEYS[kind]][id] = normalize_profile(v.duplicate(true))
		return
	l.families.erase(id)
	for tid in l.weapons.keys():
		if weapon_family_of(tid) == id:
			l.weapons.erase(tid)
	if v == null:
		return
	if not v.family.empty():
		l.families[id] = normalize_family(v.family.duplicate(true))
	for tid in v.tiers:
		l.weapons[tid] = normalize_profile(v.tiers[tid].duplicate(true))


static func _same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)


# 对象选用的版本："self" / "vanilla" / 包 id
func unit_source(kind: String, id: String) -> String:
	var s = str(sources.get(kind + ":" + id, ""))
	if s == "vanilla" or packs.has(s) and unit_value(packs[s].data, kind, id) != null:
		return s
	return "self" if unit_value(own, kind, id) != null else "vanilla"


# 对象的全部版本：原版、自修改版（有时）、含有它的数据包（按下载顺序）
func unit_versions(kind: String, id: String) -> Array:
	var out = ["vanilla"]
	if unit_value(own, kind, id) != null:
		out.push_back("self")
	for pid in pack_ids():
		if unit_value(packs[pid].data, kind, id) != null:
			out.push_back(pid)
	return out


func version_value(kind: String, id: String, src: String):
	if src == "self":
		return unit_value(own, kind, id)
	return unit_value(packs[src].data, kind, id) if packs.has(src) else null


# 已下载的包，按下载顺序
func pack_ids() -> Array:
	var ids = packs.keys()
	ids.sort_custom(self, "_by_installed")
	return ids


func _by_installed(a, b) -> bool:
	return int(packs[a].meta.get("installed", 0)) < int(packs[b].meta.get("installed", 0))


func _all_unit_keys() -> Array:
	var out = []
	var seen = {}
	var layers = [eff(), own]
	for pid in packs:
		layers.push_back(packs[pid].data)
	for l in layers:
		for u in layer_units(l):
			if not seen.has(u[0] + ":" + u[1]):
				seen[u[0] + ":" + u[1]] = true
				out.push_back(u)
	return out


# 生效层上的编辑写回自修改层（切换版本、保存之前调用）
func capture() -> void:
	var e = eff()
	for u in _all_unit_keys():
		var key = u[0] + ":" + u[1]
		var src = unit_source(u[0], u[1])
		var cur = unit_value(e, u[0], u[1])
		if packs.has(src):
			if _same(cur, unit_value(packs[src].data, u[0], u[1])):
				continue
			_set_unit(own, u[0], u[1], cur)
			sources[key] = "self" if cur != null else "vanilla"
		elif src == "self":
			_set_unit(own, u[0], u[1], cur)
			if cur == null:
				sources.erase(key)
		elif cur != null:
			_set_unit(own, u[0], u[1], cur)
			sources.erase(key)
	for sid in own.sets.keys():
		if not e.sets.has(sid):
			own.sets.erase(sid)
	for sid in e.sets:
		var pid = _set_src.get(sid, "")
		if packs.has(pid) and packs[pid].data.sets.has(sid) and _same(compact(e.sets[sid], new_set()), compact(packs[pid].data.sets[sid], new_set())):
			continue
		own.sets[sid] = normalize_set(e.sets[sid])
	for t in own.tags.keys():
		if not e.tags.has(t):
			own.tags.erase(t)
	for t in e.tags:
		var pid = _tag_src.get(t, "")
		if own.tags.has(t) or not packs.has(pid) or packs[pid].data.tags.get(t) != e.tags[t]:
			own.tags[t] = e.tags[t]


# 由 own + packs + sources 生成生效层；apply：同时更新游戏资源（注册 / 注销自定义对象、应用档案）
func compose(apply: bool = true) -> void:
	var e = eff()
	var changed = []
	for u in _all_unit_keys():
		var v = version_value(u[0], u[1], unit_source(u[0], u[1]))
		var old = unit_value(e, u[0], u[1])
		if _same(v, old):
			continue
		# 存档中进行中的一局正在使用的自定义角色保留（同 delete_custom）
		if v == null and u[0] == "character" and profiles[u[1]].custom and is_in_saved_run(u[1]):
			continue
		changed.push_back([u[0], u[1], v])
	var new_chars = false
	for c in changed:
		if apply:
			_unregister_unit(c[0], c[1])
		_set_unit(e, c[0], c[1], c[2])
		new_chars = new_chars or c[0] == "character" and c[2] != null and c[2].get("custom", false)
	weapon_sets = {}
	for sid in own.sets:
		weapon_sets[sid] = normalize_set(own.sets[sid])
	custom_tags = own.tags.duplicate()
	_set_src = {}
	_tag_src = {}
	var order = pack_ids()
	order.invert()
	for pid in order:
		var d = packs[pid].data
		for u in layer_units(d):
			if unit_source(u[0], u[1]) != pid:
				continue
			var strs = []
			_strings_in(unit_value(d, u[0], u[1]), strs)
			for s in strs:
				var sid = s.get_slice(SET_LEVEL_SEP, 0)
				if d.sets.has(sid) and not weapon_sets.has(sid):
					weapon_sets[sid] = normalize_set(d.sets[sid])
					_set_src[sid] = pid
				if d.tags.has(s) and not custom_tags.has(s):
					custom_tags[s] = d.tags[s]
					_tag_src[s] = pid
	if not apply:
		return
	_repool = true
	apply_all()
	if new_chars:
		_unlock_new_characters()


# 注销对象的游戏资源（自定义角色 / 道具 / 武器等级），之后由 apply_all 按新的档案重新注册
func _unregister_unit(kind: String, id: String) -> void:
	var isvc = _isvc()
	match kind:
		"character":
			var c = _customs.get(id)
			_customs.erase(id)
			if c != null:
				isvc.characters.erase(c)
		"item":
			var it = _custom_items.get(id)
			_custom_items.erase(id)
			if it != null:
				isvc.items.erase(it)
				_repool = true
		"weapon":
			for w in family_members(id):
				if _custom_weapons.has(w.my_id):
					_unregister_weapon(w.my_id)
			_link_family(id)


# 切换对象的版本
func set_source(kind: String, id: String, src: String) -> void:
	capture()
	sources[kind + ":" + id] = src
	compose()
	save_profiles()


# 把某个来源（数据包）的版本复制为自修改版并改用它；包内被引用的套装 / 标签一并复制（自修改层已有的不改）
func adopt_version(kind: String, id: String, src: String) -> void:
	capture()
	var v = version_value(kind, id, src)
	_set_unit(own, kind, id, v)
	if packs.has(src):
		var d = packs[src].data
		var strs = []
		_strings_in(v, strs)
		for s in strs:
			var sid = s.get_slice(SET_LEVEL_SEP, 0)
			if d.sets.has(sid) and not own.sets.has(sid):
				own.sets[sid] = normalize_set(d.sets[sid])
			if d.tags.has(s) and not own.tags.has(s):
				own.tags[s] = d.tags[s]
	sources[kind + ":" + id] = "self" if v != null else "vanilla"
	compose()
	save_profiles()


# 启用 / 停用数据包里的对象（停用：改回自修改版或原版）：kind / id 为空时不限种类 / 对象
func set_pack_enabled(pid: String, on: bool, kind: String = "", id: String = "") -> void:
	if not packs.has(pid):
		return
	capture()
	for u in layer_units(packs[pid].data):
		if kind != "" and u[0] != kind or id != "" and u[1] != id:
			continue
		var key = u[0] + ":" + u[1]
		if on:
			sources[key] = pid
		elif unit_source(u[0], u[1]) == pid:
			sources.erase(key)
	compose()
	save_profiles()


# 安装下载的数据包：code = 分享码，meta = 列表里的信息（含 id）。包内对象全部启用；返回对象数，-1 = 无法识别
# 已安装时 = 更新：保留下载顺序与各对象的启用状态，只启用新增的对象
func install_pack(meta: Dictionary, code: String) -> int:
	var raw = pack_code_data(code)
	var pid = str(meta.get("id", ""))
	if not raw is Dictionary or pid == "" or clean_suffix(pid) != pid:
		return -1
	var d = normalize_layer(raw)
	_rekey_sets(d, pid)
	_write_icons(raw.get("icons"))
	capture()
	var old = packs[pid].data if packs.has(pid) else null
	var m = meta.duplicate()
	m.installed = OS.get_unix_time()
	for other in packs:
		if other != pid:
			m.installed = max(m.installed, int(packs[other].meta.get("installed", 0)) + 1)
	if old != null:
		m.installed = packs[pid].meta.get("installed", m.installed)
	packs[pid] = {"meta": m, "data": d}
	var units = layer_units(d)
	for u in units:
		if old == null or unit_value(old, u[0], u[1]) == null:
			sources[u[0] + ":" + u[1]] = pid
	_save_pack(pid)
	compose()
	save_profiles()
	return units.size()


# 批量码的数据（字典）；不是批量码返回 null
static func pack_code_data(code: String):
	code = code.strip_edges()
	for pre in [ALL_PREFIX] + BUNDLE_PREFIX.values():
		if code.begins_with(pre):
			var raw = unpack(code.substr(pre.length()))
			return raw if raw is Dictionary else null
	return null


func uninstall_pack(pid: String) -> void:
	if not packs.has(pid):
		return
	capture()
	for key in sources.keys():
		if sources[key] == pid:
			sources.erase(key)
	packs.erase(pid)
	Directory.new().remove(PACK_DIR + pid + ".json")
	compose()
	save_profiles()


# 包内自定义套装与本地（自修改层 / 其他包）的同 id 套装内容不同时改 id（<id>_<包 id>），引用一并改
func _rekey_sets(d: Dictionary, pid: String) -> void:
	for sid in d.sets.keys():
		if not d.sets[sid].custom:
			continue
		var mine = compact(d.sets[sid], new_set())
		var clash = own.sets.has(sid) and not _same(compact(own.sets[sid], new_set()), mine)
		for other in packs:
			if other != pid and packs[other].data.sets.has(sid) and not _same(compact(packs[other].data.sets[sid], new_set()), mine):
				clash = true
		if not clash:
			continue
		var nid = sid + "_" + pid
		for k in ["profiles", "items", "weapons", "families"]:
			d[k] = _rename_refs(d[k], sid, nid)
		d.sets[nid] = d.sets[sid]
		d.sets.erase(sid)


static func _rename_refs(v, old: String, new: String):
	if v is String:
		if v == old:
			return new
		return new + v.substr(old.length()) if v.begins_with(old + SET_LEVEL_SEP) else v
	if v is Array:
		var out = []
		for x in v:
			out.push_back(_rename_refs(x, old, new))
		return out
	if v is Dictionary:
		var out = {}
		for k in v:
			out[k] = _rename_refs(v[k], old, new)
		return out
	return v


# 分享码里的自定义图标写入图标目录（文件名只接受 import_icon 生成的那种；已存在则不改）
func _write_icons(icons) -> void:
	if not icons is Dictionary:
		return
	var dir = Directory.new()
	if not dir.dir_exists(ICON_DIR):
		dir.make_dir_recursive(ICON_DIR)
	for name in icons:
		if str(name) != clean_suffix(str(name).get_basename()) + ".png" or dir.file_exists(ICON_DIR + str(name)):
			continue
		var file = File.new()
		if file.open(ICON_DIR + str(name), File.WRITE) == OK:
			file.store_buffer(Marshalls.base64_to_raw(str(icons[name])))
			file.close()


func _save_pack(pid: String) -> void:
	var dir = Directory.new()
	if not dir.dir_exists(PACK_DIR):
		dir.make_dir_recursive(PACK_DIR)
	var file = File.new()
	if file.open(PACK_DIR + pid + ".json", File.WRITE) == OK:
		file.store_string(JSON.print({"meta": packs[pid].meta, "data": compact_layer(packs[pid].data)}))
		file.close()


func _load_packs() -> void:
	packs = {}
	for name in _list_json(PACK_DIR):
		var file = File.new()
		if file.open(PACK_DIR + name, File.READ) != OK:
			continue
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		var r = parsed.result if parsed.error == OK else null
		if r is Dictionary and r.get("meta") is Dictionary and str(r.meta.get("id", "")) == name.get_basename():
			packs[name.get_basename()] = {"meta": r.meta, "data": normalize_layer(r.get("data"))}


# 对象在某个版本下的名称 / 图标（列表与预览用；不要求对象已注册）
func unit_name(kind: String, id: String, v = null) -> String:
	var p = _unit_look(kind, v)
	if p.name != "":
		return p.name
	var r = _unit_res(kind, id)
	if r != null:
		return tr(orig_name(r))
	return tr({"character": "BE_NEW_CHARACTER", "item": "BE_NEW_ITEM", "weapon": "BE_NEW_WEAPON"}[kind]) if p.custom else id


func unit_icon(kind: String, id: String, v = null) -> Texture:
	var p = _unit_look(kind, v)
	if p.custom:
		return custom_icon(id, p, kind)
	var r = _unit_res(kind, id)
	return r.icon if r != null else null


func _unit_look(kind: String, v) -> Dictionary:
	if kind == "weapon":
		return normalize_family(v.family if v != null else {})
	return normalize_profile(v)


# 悬停预览用的临时资源（原版物品框显示）：复制已注册的对象或基底，换上该版本的名称、图标、效果等
func preview_res(kind: String, id: String, v):
	# 自定义对象的"原版"= 不存在
	if v == null and _unit_res(kind, id) == null:
		return null
	var look = _unit_look(kind, v)
	if kind == "weapon":
		var tid = ""
		if v != null and not v.tiers.empty():
			var ids = v.tiers.keys()
			ids.sort()
			tid = ids[0]
		var t = find_target("weapon", tid) if tid != "" else null
		if t == null:
			var ms = family_members(id)
			if ms.empty():
				ms = _vanilla_members(look.base)
			t = ms[0] if not ms.empty() else null
		if t == null:
			return null
		if tid == "":
			tid = t.my_id
		var tp = normalize_profile(v.tiers.get(tid, {}) if v != null else {})
		var w = t.duplicate()
		w.name = unit_name(kind, id, v)
		w.icon = unit_icon(kind, id, v)
		var stats = weapon_stats_for(t, tp)
		if stats != null:
			w.stats = stats
		w.effects = build_effects(tid, tp)
		return w
	var p = normalize_profile(v)
	var r = find_target(kind, id)
	if r == null:
		r = find_target(kind, p.base)
	if r == null:
		return null
	r = r.duplicate()
	r.name = unit_name(kind, id, v)
	r.icon = unit_icon(kind, id, v)
	r.effects = build_effects(id, p)
	if kind == "character" and p.weapons is Array:
		r.starting_weapons = _weapons_by_ids(p.weapons)
	if kind == "item":
		if p.price >= 0:
			r.value = p.price
		if p.tier >= 0:
			r.tier = p.tier
	return r


func _unit_res(kind: String, id: String):
	if kind == "weapon":
		var vm = _vanilla_members(id)
		return vm[0] if not vm.empty() else null
	return find_target(kind, id) if not (_customs.has(id) or _custom_items.has(id)) else null


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
	var parsed = {"result": unpack(code)}
	if not parsed.result is Dictionary:
		return -1
	var n = 0
	# 依赖：自定义标签、套装、图标（同名覆盖；图标文件已存在则不改）
	var tags = parsed.result.get("tags", {})
	if tags is Dictionary:
		for k in tags:
			custom_tags[str(k)] = str(tags[k])
	var sets = parsed.result.get("sets", {})
	if sets is Dictionary:
		for k in sets:
			weapon_sets[str(k)] = normalize_set(sets[k])
	_write_icons(parsed.result.get("icons"))
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
			keep[k] = [] if k in kinds and parsed.result.disabled.has(k) else disabled[k]
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
	var parsed = {"result": unpack(code.substr(SHARE_PREFIX.length()))}
	if not parsed.result is Dictionary or not parsed.result.get("profile") is Dictionary:
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
	if id.find(SET_LEVEL_SEP) > 0:
		var s = find_set(id.get_slice(SET_LEVEL_SEP, 0))
		var lv = int(id.get_slice(SET_LEVEL_SEP, 1))
		var bonuses = backup_value(s, "set_bonuses") if s != null else []
		return bonuses[lv] if lv < bonuses.size() else []
	var r = _find_any(id)
	if r == null:
		r = _find_dlc(id)
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
		# 燃烧几率：换成会带上属性加成的子类（见 graph/burn_chance_effect.gd）
		if e is BurnChanceEffect:
			var be = BurnChance.new()
			for pr in e.get_property_list():
				if pr.usage & PROPERTY_USAGE_STORAGE and pr.name != "script":
					be.set(pr.name, e.get(pr.name))
			e = be
	else:
		e = load(EFFECT_SCRIPT).new()
		e.effect_sign = 3	# FROM_VALUE
	_set_typed(e, spec.get("set", {}))
	# 子资源（燃烧数据、武器属性…）：复制后改写，不影响模板
	var subs = spec.get("sub", {})
	if subs is Dictionary:
		for f in subs:
			var r = e.get(f) if f in e else null
			if not r is Resource or not subs[f] is Dictionary:
				continue
			r = r.duplicate()
			var vals = subs[f].duplicate()
			if vals.get("scaling_stats") is Array and "scaling_stats" in r:
				var sc = []
				for row in vals.scaling_stats:
					if row is Array and row.size() >= 2:
						sc.push_back([str(row[0]), float(row[1])])
				r.scaling_stats = Utils.convert_to_hash_array(sc)
			vals.erase("scaling_stats")
			_set_typed(r, vals)
			e.set(f, r)
	e._generate_hashes()
	return e


# 按目标字段的类型写入（JSON 读回的数字是浮点）
static func _set_typed(obj, sets) -> void:
	if not sets is Dictionary:
		return
	for k in sets:
		if not k in obj:
			continue
		var cur = obj.get(k)
		match typeof(cur):
			TYPE_INT:
				obj.set(k, int(sets[k]))
			TYPE_REAL:
				obj.set(k, float(sets[k]))
			TYPE_BOOL:
				obj.set(k, bool(sets[k]))
			TYPE_STRING:
				obj.set(k, str(sets[k]))
			TYPE_ARRAY:
				if sets[k] is Array:
					var arr = []
					for x in sets[k]:
						arr.push_back(str(x))
					obj.set(k, arr)


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
		_dyn_tr().add_message(tk, stat_name(key))
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
	# 好坏按该属性在原版效果里的方向（如价格越低越好、敌人数量中立）：决定文本颜色与诅咒方向（有利放大、不利缩小、中立不变）
	var dir = _good_dir(key) * (1 if value > 0 else -1)
	sets.effect_sign = 0 if dir > 0 else (1 if dir < 0 else 2)
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
			_rekey_self(e, spec, id)
			out.push_back(e)
	for en in entries:
		if not used.has(entry_sig(en.marker)):
			out.push_back(en.effect)
	return out


# 删除自定义标签：同时从所有道具 / 角色的档案里移除
func delete_custom_tag(tag: String) -> void:
	custom_tags.erase(tag)
	for pair in [[profiles, "wanted_tags"], [item_profiles, "tags"]]:
		for id in pair[0]:
			var arr = pair[0][id][pair[1]]
			if arr is Array:
				arr.erase(tag)


# 以所在道具 id 为 key 的原版效果（金鱼"刷新时升级"、镜子"复制下一件"：原版按 key 找到并移除这件道具）
# 复制到别的道具上时改指向该道具，否则会去找原来那件
const SELF_KEYED = ["increase_tier_on_reroll", "duplicate_item"]


func _rekey_self(e, spec: Dictionary, id: String) -> void:
	var from = str(spec.get("from", ""))
	if from == "" or from == id or e.key != from or not e.custom_key in SELF_KEYED or find_target("item", id) == null:
		return
	e.key = id
	e._generate_hashes()


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
	# 没有 DLC 时原版会丢掉诅咒的初始装备：改为普通初始装备
	var pd = _autoload("ProgressData")
	var cursed = bool(s.get("cursed", false)) and pd != null and pd.is_dlc_available_and_active("abyssal_terrors")
	var ck = ("cursed_" if cursed else "") + ("starting_weapon" if weapon else "starting_item")
	return make_effect({"set": {
		"key": id, "value": max(1, int(s.get("n", 1))), "custom_key": ck, "storage_method": 1, "effect_sign": 3,
		"text_key": "effect_cursed_starting_item" if cursed else "effect_starting_item",
	}})


# 描述：一条不生效的效果（key 为空，apply 直接返回），文本是动态注册的翻译
func _desc_effect(id: String, text: String):
	var key = "BE_DESC_" + id.to_upper()
	_set_message(key, "[color=#" + Color(0.75, 0.8, 0.9).to_html(false) + "]" + text + "[/color]")
	return make_effect({"set": {"key": "", "value": 0, "text_key": key, "effect_sign": 2}})


# 动态注册的翻译（描述、属性名、自定义对象名）：每个语言都显示同一段文字
func _dyn_tr() -> Translation:
	if _desc_translation == null:
		_desc_translation = Translation.new()
		TranslationServer.add_translation(_desc_translation)
	_desc_translation.locale = TranslationServer.get_locale()
	return _desc_translation


func _set_message(key: String, text: String) -> void:
	var t = _dyn_tr()
	t.erase_message(key)
	t.add_message(key, text)


const BACKUP_FIELDS = {
	"character": ["effects", "name", "starting_weapons", "wanted_tags"],
	"item": ["effects", "name", "value", "tier", "max_nb", "tags", "replaced_by"],
	"weapon": ["effects", "name", "value", "stats", "sets"],
	"set": ["set_bonuses"],
}


static func kind_of(res) -> String:
	if res is CharacterData:
		return "character"
	if res is WeaponData:
		return "weapon"
	if res is SetData:
		return "set"
	return "item"


func _backup(c) -> void:
	if _backups.has(c.my_id):
		return
	var fields = {}
	for f in BACKUP_FIELDS[kind_of(c)]:
		fields[f] = c.get(f)
	_backups[c.my_id] = {"res": c, "fields": fields}


# 备份里的原值；该种类不备份的字段（如武器的 tier）取当前值
func backup_value(c, field: String):
	if _backups.has(c.my_id) and _backups[c.my_id].fields.has(field):
		return _backups[c.my_id].fields[field]
	return c.get(field)


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
	# 本 mod 的 _ready 早于 ProgressData（DLC 在那之后才加入）：此前建好的效果库缓存不含 DLC，这里重建
	_library = null
	_weapon_library = null
	_stat_text_keys = null
	_good_dirs = null
	_ban_cache.clear()
	_global_ban = null
	_register_customs()
	_register_custom_items()
	_register_weapon_families()
	apply_sets()
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
	_apply_fusion()
	if apply_group_locks():
		isvc.init_unlocked_pool()


# 融合角色：把被融合角色自身的效果（含本编辑器的修改，不含它们的融合与介绍）复制一份接在后面
func _apply_fusion() -> void:
	var targets = []
	var own = {}
	for id in profiles:
		var p = profiles[id]
		if p.fuse.empty() or not (p.custom or (p.enabled and kind_enabled.character)):
			continue
		var c = find_character(id)
		if c == null:
			continue
		targets.push_back([c, p])
		for fid in p.fuse:
			var f = find_character(fid)
			if f != null and not own.has(fid):
				own[fid] = f.effects.duplicate()
	for t in targets:
		var c = t[0]
		_backup(c)
		var add = []
		for fid in t[1].fuse:
			if fid == c.my_id or not own.has(fid):
				continue
			for e in own[fid]:
				if e != null and not str(e.text_key).begins_with("BE_DESC_"):
					add.push_back(e.duplicate())
		c.effects = c.effects + add


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
		# 未知的道具（导入不完全 / mod 未启用）：保持原版
		if p.replaced_by is String and (p.replaced_by == "" or find_target("item", p.replaced_by) != null):
			it.replaced_by = find_target("item", p.replaced_by) if p.replaced_by != "" else null


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


# ============================================================
# 武器套装
# ============================================================
const SET_LEVEL_SEP = "#"
var _set_res: Dictionary = {}	# 自定义套装 id -> SetData（同一 id 一直用同一个资源，武器上的引用不会失效）


func find_set(id: String):
	for s in _isvc().sets:
		if s != null and s.my_id == id:
			return s
	return null


# 每一级的 spec 列表（没有修改时引用原版 / 基底套装的效果）
func set_specs(id: String) -> Array:
	var p = weapon_sets.get(id)
	if p != null and p.bonuses is Array:
		return p.bonuses
	var base = p.base if p != null and p.custom else id
	var s = find_set(base)
	var out = []
	if s != null:
		var bonuses = backup_value(s, "set_bonuses")
		for lv in bonuses.size():
			var specs = []
			for i in bonuses[lv].size():
				specs.push_back({"from": base + SET_LEVEL_SEP + str(lv), "i": i})
			out.push_back(specs)
	return out


func is_set_modified(id: String) -> bool:
	return weapon_sets.has(id) and (weapon_sets[id].custom or weapon_sets[id].bonuses is Array)


# 注册自定义套装、改写原版套装的效果（编辑器里每次修改后也调用）
func apply_sets() -> void:
	var isvc = _isvc()
	for id in _set_res:
		if not weapon_sets.has(id) or not weapon_sets[id].custom:
			isvc.sets.erase(_set_res[id])
	for s in isvc.sets:
		if s != null and _backups.has(s.my_id) and s is SetData:
			s.set_bonuses = _backups[s.my_id].fields.set_bonuses
	for id in weapon_sets:
		var p = weapon_sets[id]
		var s = null
		if p.custom:
			# 基底缺失（导入不完全 / mod 未启用）且没有自己的效果：不注册（原版按件数取档位，空档位会出错）
			if set_specs(id).empty():
				if _set_res.has(id):
					isvc.sets.erase(_set_res[id])
				continue
			s = _set_res.get(id)
			if s == null:
				s = SetData.new()
				_set_res[id] = s
			s.my_id = id
			s.my_id_hash = Keys.generate_hash(id)
			s.name = p.name if p.name != "" else id
			if not s in isvc.sets:
				isvc.sets.push_back(s)
		else:
			s = find_set(id)
			if s == null or not p.bonuses is Array or not kind_enabled.weapon:
				continue
			_backup(s)
		var bonuses = []
		for lv in set_specs(id):
			var effects = []
			for spec in lv:
				var e = make_effect(spec) if spec is Dictionary else null
				if e != null:
					effects.push_back(e)
			bonuses.push_back(effects)
		s.set_bonuses = bonuses


# 以 base 为基底新建自定义套装（复制其当前效果）
func create_set(base: String) -> String:
	var n = 1
	while weapon_sets.has("set_custom_" + str(n)) or find_set("set_custom_" + str(n)) != null:
		n += 1
	var id = "set_custom_" + str(n)
	var src = weapon_sets.get(base, new_set())
	var s = find_set(base)
	weapon_sets[id] = {"custom": true, "base": src.base if src.custom else base,
		"name": tr(s.name) if s != null else id, "bonuses": set_specs(base).duplicate(true)}
	apply_sets()
	return id


# 改 id：武器家族里的引用一并改
func rename_set(old_id: String, new_id: String) -> bool:
	if new_id == "" or new_id == old_id or weapon_sets.has(new_id) or find_set(new_id) != null or not weapon_sets.has(old_id):
		return false
	weapon_sets[new_id] = weapon_sets[old_id]
	weapon_sets.erase(old_id)
	if _set_res.has(old_id):
		_set_res[new_id] = _set_res[old_id]
		_set_res.erase(old_id)
	for wid in weapon_families:
		var f = weapon_families[wid]
		if f.sets is Array and old_id in f.sets:
			f.sets[f.sets.find(old_id)] = new_id
	apply_sets()
	return true


func delete_set(id: String) -> void:
	weapon_sets.erase(id)
	for wid in weapon_families:
		var f = weapon_families[wid]
		if f.sets is Array:
			f.sets.erase(id)
	apply_sets()


# 原版套装恢复原版效果；自定义套装恢复为基底的效果
func reset_set(id: String) -> void:
	if weapon_sets.has(id) and weapon_sets[id].custom:
		weapon_sets[id].bonuses = null
	else:
		weapon_sets.erase(id)
	apply_sets()


# ============================================================
# 内容分组：角色 / 道具 / 武器（家族）归为一组，可改名；整组锁定 / 解锁用原版的解锁记录
# （ProgressData.characters_unlocked / items_unlocked / weapons_unlocked，记的是 id 的哈希；武器按 weapon_id）
# 锁定 = 移出解锁记录并把 unlocked_by_default 设为 false（否则启动时又被原版加回）；解锁 = 加回
# ============================================================
const UNLOCK_LISTS = {"character": "characters_unlocked", "item": "items_unlocked", "weapon": "weapons_unlocked"}


static func normalize_group(g) -> Dictionary:
	var out = {"name": "", "members": [], "locked": false}
	if not g is Dictionary:
		return out
	out.name = str(g.get("name", ""))
	out.locked = bool(g.get("locked", false))
	if g.get("members") is Array:
		for m in g.members:
			if m is Array and m.size() == 2 and str(m[0]) in KINDS:
				out.members.push_back([str(m[0]), str(m[1])])
	return out


func tag_name(tag: String) -> String:
	return custom_tags[tag] if custom_tags.has(tag) else stat_name(tag)


# "拥有指定道具 / 武器"的名称：道具 my_id 或武器家族 weapon_id
func owned_name(id: String) -> String:
	var r = find_target("item", id)
	if r != null:
		return tr(r.name)
	r = find_target("weapon", id)
	if r != null:
		return tr(r.name) + ["", " II", " III", " IV"][int(clamp(r.tier, 0, 3))]
	var ms = family_members(id)
	return tr(ms[0].name) if not ms.empty() else id


func weapon_set_name(id: String) -> String:
	var s = find_set(id)
	return tr(s.name) if s != null else id


func create_group(name: String) -> String:
	var n = 1
	while groups.has("group_" + str(n)):
		n += 1
	var gid = "group_" + str(n)
	groups[gid] = {"name": name, "members": [], "locked": false}
	return gid


func group_name(gid: String) -> String:
	var g = groups.get(gid)
	return gid if g == null or g.name == "" else g.name


static func group_has(g: Dictionary, kind: String, id: String) -> bool:
	for m in g.members:
		if m[0] == kind and m[1] == id:
			return true
	return false


func toggle_group_member(gid: String, kind: String, id: String) -> void:
	var g = groups.get(gid)
	if g == null:
		return
	if group_has(g, kind, id):
		for i in g.members.size():
			if g.members[i][0] == kind and g.members[i][1] == id:
				g.members.remove(i)
				break
		if g.locked:
			_set_unlocked(kind, id, true)
	else:
		g.members.push_back([kind, id])
	_after_lock_change()


func delete_group(gid: String) -> void:
	if groups.has(gid) and groups[gid].locked:
		set_group_locked(gid, false)
	groups.erase(gid)


func set_group_locked(gid: String, locked: bool) -> void:
	var g = groups.get(gid)
	if g == null:
		return
	g.locked = locked
	if not locked:
		for m in g.members:
			_set_unlocked(m[0], m[1], true)
	_after_lock_change()


# 解锁后仍在其他锁定分组里的对象保持锁定；写入存档并重建商店池
func _after_lock_change() -> void:
	var _any = apply_group_locks()
	_isvc().init_unlocked_pool()
	var pd = _autoload("ProgressData")
	if pd != null and pd.SAVE_DIR != "":
		pd.save()
	save_profiles()


# 锁定所有锁定分组的成员；返回是否有锁定分组
func apply_group_locks() -> bool:
	var any = false
	for gid in groups:
		if groups[gid].locked:
			any = true
			for m in groups[gid].members:
				_set_unlocked(m[0], m[1], false)
	return any


func is_unlocked(kind: String, id: String) -> bool:
	var pd = _autoload("ProgressData")
	return pd != null and Keys.generate_hash(id) in pd.get(UNLOCK_LISTS[kind])


func _set_unlocked(kind: String, id: String, on: bool) -> void:
	var pd = _autoload("ProgressData")
	if pd == null or not UNLOCK_LISTS.has(kind):
		return
	var list: Array = pd.get(UNLOCK_LISTS[kind])
	var h = Keys.generate_hash(id)
	var res = []
	if kind == "weapon":
		for w in _isvc().weapons:
			if w != null and w.weapon_id == id:
				res.push_back(w)
	else:
		var r = find_target(kind, id)
		if r != null:
			res.push_back(r)
	for r in res:
		r.unlocked_by_default = on
	if on and not h in list:
		list.push_back(h)
	while not on and h in list:
		list.erase(h)


# ============================================================
# 武器的使用者：哪些角色以该武器家族为初始武器（改写的是角色档案的 weapons）
# ============================================================
# 角色的初始武器 id：档案改过时取档案，否则取原版
func char_weapon_ids(cid: String) -> Array:
	var p = profiles.get(cid)
	if p != null and p.weapons is Array:
		return p.weapons.duplicate()
	var c = find_character(cid)
	var out = []
	if c != null:
		for w in backup_value(c, "starting_weapons"):
			if w != null and not w.my_id in out:
				out.push_back(w.my_id)
	return out


func _in_family(ids: Array, wid: String) -> bool:
	for id in ids:
		var w = find_target("weapon", str(id))
		if w != null and w.weapon_id == wid:
			return true
	return false


func weapon_users(wid: String) -> Array:
	var out = []
	for c in _isvc().characters:
		if c != null and _in_family(char_weapon_ids(c.my_id), wid):
			out.push_back(c.my_id)
	return out


# 角色在该家族里的初始武器等级（没有为 -1）
func char_weapon_tier(cid: String, wid: String) -> int:
	for id in char_weapon_ids(cid):
		var w = find_target("weapon", str(id))
		if w != null and w.weapon_id == wid:
			return w.tier
	return -1


# 设为 cids 这些角色的初始武器（其余角色移除该家族）；tiers：角色 -> 想要的等级（套用已有武器时沿用原武器的等级）
func set_weapon_users(wid: String, cids: Array, tiers: Dictionary = {}) -> void:
	for c in _isvc().characters:
		if c == null:
			continue
		var ids = char_weapon_ids(c.my_id)
		var want = c.my_id in cids
		if _in_family(ids, wid) == want:
			continue
		if want:
			var w = weapon_for_character(wid, c.my_id, int(tiers.get(c.my_id, -1)))
			if w == null:
				continue
			ids.push_back(w.my_id)
		else:
			for id in ids.duplicate():
				var w = find_target("weapon", str(id))
				if w != null and w.weapon_id == wid:
					ids.erase(id)
		if not profiles.has(c.my_id):
			profiles[c.my_id] = new_profile()
		profiles[c.my_id].weapons = ids


# 角色可用的等级：优先 prefer（可用时），否则取家族中最低的可用等级。
# 可用 = 满足角色"最低 / 最高武器等级"效果，且不低于角色原本初始武器的最低等级（如国王只有 T2 以上）
func weapon_for_character(wid: String, cid: String, prefer: int = -1):
	var ms = family_members(wid)
	if ms.empty():
		return null
	var lo = 0
	var hi = 99
	var c = find_character(cid)
	if c != null:
		var orig = backup_value(c, "starting_weapons")
		if not orig.empty():
			var t0 = 99
			for w in orig:
				if w != null:
					t0 = min(t0, w.tier)
			lo = max(lo, t0 if t0 < 99 else 0)
	var effects = build_effects(cid, profiles[cid]) if profiles.has(cid) else (c.effects if c != null else [])
	for e in effects:
		if e != null and "key" in e:
			if e.key == "min_weapon_tier":
				lo = max(lo, int(e.value))
			elif e.key == "max_weapon_tier":
				hi = min(hi, int(e.value))
	for w in ms:
		if w.tier == prefer and w.tier >= lo and w.tier <= hi:
			return w
	for w in ms:
		if w.tier >= lo and w.tier <= hi:
			return w
	return ms[-1] if ms[-1].tier < lo else ms[0]


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
			for k in ["effects", "stats", "weapons", "start_items", "fuse", "ban_items", "ban_weapons", "wanted_tags", "desc"]:
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
		var rep = backup_value(base, "replaced_by")
		p.replaced_by = rep.my_id if rep != null else ""
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
	# 原版"初始拥有"等效果文本按 tr(ID 大写) 显示名称
	_set_message(id.to_upper(), it.name)
	it.icon = custom_icon(id, p, "item")
	it.item_appearances = base.item_appearances if base != null else []
	it.value = max(0, p.price)
	if it.tier != max(0, p.tier):
		_repool = true
	it.tier = int(clamp(p.tier, 0, 3))
	it.max_nb = p.max_nb if p.max_nb != -2 else -1
	it.tags = p.tags.duplicate() if p.tags is Array else []
	# 效果由 _apply_items 按档案生成；编辑器里改名等重新注册时保留已生成的效果
	if it.effects == null:
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
	for w in bm:
		var p = new_profile()
		p.custom = true
		_copy_tier_effects(p, w.my_id)
		weapon_profiles[tier_id(wid, w.tier, true)] = p
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
	for w in family_members(weapon_id):
		if abs(w.tier - t) == 1:
			_copy_tier_effects(p, w.my_id)
			break
	weapon_profiles[id] = p
	_register_weapon_families()
	_unlock_new_characters()
	return id


# 新等级 / 新武器的效果：复制 src 等级的效果（有档案时连同档案里的效果与蓝图，否则引用其原版效果）
func _copy_tier_effects(p: Dictionary, src_id: String) -> void:
	var sp = weapon_profiles.get(src_id)
	var use = sp != null and (sp.custom or sp.enabled)
	if use and sp.graph is Dictionary:
		p.graph = sp.graph.duplicate(true)
	if use and (sp.effects is Array or sp.custom):
		p.effects = sp.effects.duplicate(true) if sp.effects is Array else []
		return
	p.effects = []
	for i in orig_effects(src_id).size():
		p.effects.push_back({"from": src_id, "i": i})


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


# 编辑器里修改自定义武器后重新注册：注册会按基底重置属性 / 效果，再按档案写回
func reregister_weapons() -> void:
	_register_weapon_families()
	_apply_weapons()
	_apply_families()


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
		_set_message(weapon_id.to_upper(), w.name)
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
	var _locked = apply_group_locks()
	pd.set_max_selectable_difficulty()
	pd.save()


# ============================================================
# 效果库
# ============================================================
func library(with_weapons: bool = false) -> Array:
	if with_weapons:
		if _weapon_library == null:
			var sources = _library_sources()
			var dlc_weapons = []
			for d in _dlcs():
				dlc_weapons += d.weapons
			var seen = {}
			for w in _isvc().weapons + dlc_weapons:
				if w == null or seen.has(w.my_id):
					continue
				seen[w.my_id] = true
				if w != null and not w.effects.empty() and not _custom_weapons.has(w.my_id):
					sources.push_back([w.my_id, orig_name(w), orig_effects(w.my_id)])
			_weapon_library = Catalog.build_library(sources, library_dedup)
		return _weapon_library
	if _library == null:
		_library = Catalog.build_library(_library_sources(), library_dedup)
	return _library


# ============================================================
# 诅咒蓝图：节点数值做成代理效果交给原版 curse_item（同一系数），按 effect key 走原版的规则与特判，再写回
# ============================================================
const CURSE_TAG = "be_curse:"
var _good_dirs = null


# 属性在原版效果里的好方向：+1 = 越大越好，-1 = 越小越好（如价格），0 = 中立（如敌人数量）
func _good_dir(key: String) -> int:
	if _good_dirs == null:
		_good_dirs = {}
		for entry in library(true):
			var e = entry.effect
			if e.custom_key != "" or e.key == "" or _good_dirs.has(e.key) or e.value == 0 or not "effect_sign" in e:
				continue
			var s = e.get_sign(e.effect_sign, e.value)
			var v = 1 if e.value > 0 else -1
			_good_dirs[e.key] = v if s in [0, 5] else (-v if s == 1 else 0)
	return _good_dirs.get(key, 1)


# 效果节点对玩家的好坏（路径符号）：+1 / -1 / 0
func _effect_goodness(n: Dictionary) -> int:
	var kind = str(n.get("kind", ""))
	var params = n.get("params", {})
	if kind == "grant":
		var ge = make_effect(params.ref) if params.get("ref") is Dictionary else null
		if ge == null:
			return 0
		var s = ge.get_sign(ge.effect_sign, ge.value)
		return 1 if s in [0, 5] else (-1 if s == 1 else 0)
	var v = int(params.get("value", params.get("pct", _node_default(kind, "value"))))
	if v == 0:
		return 0
	var sv = 1 if v > 0 else -1
	if kind in ["temp_stat", "perm_stat", "timed_stat"]:
		return _good_dir(str(params.get("stat", ""))) * sv
	return sv


# 每条路径：路径符号 E = 效果的好坏；有 CURSE_TARGETS 里的条件时诅咒该条件（方向 = E × 条件符号），
# 否则诅咒效果的数值（方向 = E）。E = 0（中立）的路径不变。方向交给原版：+1 按正面放大、-1 按负面缩小
func curse_graph(g: Dictionary, modifier: float) -> Dictionary:
	var out = g.duplicate(true)
	var pd = _autoload("ProgressData")
	var dlc = pd.get_dlc_data("abyssal_terrors") if pd != null else null
	if dlc == null or modifier <= 0.0:
		return out
	var by_id = GraphEffect.nodes_by_id(out)
	var dirs = {}	# "节点 id:参数" -> 方向（同一节点在多条路径上取第一条的）
	for path in GraphEffect.paths(out):
		var eff = by_id[path[-1]]
		var e_sign = _effect_goodness(eff)
		if e_sign == 0:
			continue
		var target = null
		for id in path.slice(0, path.size() - 2):
			if Catalog.CURSE_TARGETS.has(by_id[id].kind):
				target = by_id[id]
				break
		if target != null:
			var tp = Catalog.CURSE_TARGETS[target.kind]
			var k = str(target.id) + ":" + tp
			if not dirs.has(k):
				dirs[k] = e_sign * Catalog.curse_sign(target.kind, tp)
			continue
		if eff.kind == "grant":
			var k = str(eff.id) + ":ref"
			if not dirs.has(k):
				dirs[k] = e_sign
			continue
		for pname in Catalog.CURSE_EFFECT_PARAMS.get(eff.kind, []):
			var k = str(eff.id) + ":" + pname
			if not dirs.has(k):
				dirs[k] = e_sign * Catalog.curse_sign(eff.kind, pname)
	var proxies = []
	for k in dirs:
		var parts = k.split(":")
		var n = by_id.get(int(parts[0]), by_id.get(parts[0]))
		if n == null:
			continue
		var pname = parts[1]
		if pname == "ref":
			var ge = make_effect(n.params.ref)
			if ge != null:
				ge.resource_name = CURSE_TAG + k
				proxies.push_back(ge)
			continue
		var v = int(n.params.get(pname, _node_default(n.kind, pname)))
		if v == 0:
			continue
		var e = load(EFFECT_SCRIPT).new()
		e.value = v
		# 属性类效果的数值用属性 key（原版按 key 的特判同样生效，如闪避上限）；其余用占位 key
		e.key = str(n.params.get("stat", "")) if n.kind in ["temp_stat", "perm_stat", "timed_stat"] and pname == "value" else "broeditor_param"
		# 方向 +1：|值| 放大（原版正面）；-1：|值| 缩小（原版负面）——与数值本身的正负无关
		e.effect_sign = 0 if dirs[k] > 0 else 1
		e.resource_name = CURSE_TAG + k
		e._generate_hashes()
		proxies.push_back(e)
	if proxies.empty():
		return out
	var item = load("res://items/global/item_data.gd").new()
	item.my_id = "broeditor_graph_curse"
	item.effects = proxies
	# 用给定系数：关掉随机，并临时压低基础系数，使 max(最低系数, 基础系数) = 给定系数
	var base = dlc.cursed_item_base_percent_modifier
	dlc.cursed_item_base_percent_modifier = -100000
	var cursed = dlc.curse_item(item, 0, true, modifier)
	dlc.cursed_item_base_percent_modifier = base
	for ce in cursed.effects:
		var tag = str(ce.resource_name)
		if not tag.begins_with(CURSE_TAG):
			continue
		var parts = tag.substr(CURSE_TAG.length()).split(":")
		var n = by_id.get(int(parts[0]), by_id.get(parts[0]))
		if n == null:
			continue
		if parts[1] == "ref":
			n.params.ref = _effect_to_spec(n.params.ref, ce)
			continue
		var v = int(ce.value)
		var mx = Catalog.CURSE_MAX.get(n.kind, {}).get(parts[1])
		if mx != null:
			v = int(min(v, mx))
		n.params[parts[1]] = v
	return out


static func _node_default(kind: String, pname: String):
	var d = Catalog.node_def(kind)
	if d != null:
		for p in d[2]:
			if p[0] == pname:
				return p[2]
	return 0


# 诅咒后的效果写回 spec：数值与子资源（燃烧、武器属性）
func _effect_to_spec(spec: Dictionary, e) -> Dictionary:
	var out = spec.duplicate(true)
	if not out.get("set") is Dictionary:
		out["set"] = {}
	for f in Catalog.editable_fields(e):
		if f.type in [TYPE_INT, TYPE_REAL]:
			out.set[f.name] = e.get(f.name)
	for f in Catalog.sub_fields(e):
		var r = e.get(f)
		var vals = {}
		for cf in Catalog.sub_child_fields(r):
			vals[cf.name] = r.get(cf.name)
		if "scaling_stats" in r:
			vals["scaling_stats"] = scaling_names(r.scaling_stats)
		if not out.get("sub") is Dictionary:
			out["sub"] = {}
		out.sub[f] = vals
	return out


func set_library_dedup(on: bool) -> void:
	library_dedup = on
	_library = null
	_weapon_library = null


# 角色与道具；DLC 当前未启用（未拥有或在选择界面关闭）时也收录它的角色与道具
func _library_sources() -> Array:
	var isvc = _isvc()
	var sources = []
	var seen = {}
	var dlc_chars = []
	var dlc_items = []
	for d in _dlcs():
		dlc_chars += d.characters
		dlc_items += d.items
	for arr in [isvc.characters + dlc_chars, isvc.items + dlc_items]:
		for r in arr:
			if r == null or seen.has(r.my_id) or is_custom(r.my_id):
				continue
			seen[r.my_id] = true
			sources.push_back([r.my_id, orig_name(r), orig_effects(r.my_id)])
	return sources


func _dlcs() -> Array:
	var pd = _autoload("ProgressData")
	return pd.available_dlcs if pd != null and "available_dlcs" in pd else []


# 未启用的 DLC 里的角色 / 道具（效果库引用它们的效果）
func _find_dlc(id: String):
	for d in _dlcs():
		for arr in [d.characters, d.items, d.weapons]:
			for r in arr:
				if r != null and r.my_id == id:
					return r
	return null


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
		return _with_run_shop(_ban_cache[c.my_id], player_index)
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
	return _with_run_shop(out, player_index)


static func new_run_shop() -> Array:
	var out = []
	for _i in 4:
		out.push_back({"add": [], "remove": [], "force": []})
	return out


# 读档：存档里没有或格式不对时为空
func load_run_shop(state) -> void:
	run_shop = new_run_shop()
	if not state is Array:
		return
	for i in min(4, state.size()):
		if state[i] is Dictionary:
			for k in ["add", "remove", "force"]:
				if state[i].get(k) is Array:
					for id in state[i][k]:
						run_shop[i][k].push_back(str(id))


# 加入 / 移出本局商店（同一件道具后执行的为准）
func run_shop_change(p: int, ids, add: bool) -> void:
	if not ids is Array or p < 0 or p >= run_shop.size():
		return
	for id in ids:
		id = str(id)
		run_shop[p].add.erase(id)
		run_shop[p].remove.erase(id)
		run_shop[p]["add" if add else "remove"].push_back(id)


# 商店必定出现：下次刷新商店时放进商店（从最后一格往前替换）
func queue_shop_force(p: int, ids) -> void:
	if ids is Array and p >= 0 and p < run_shop.size():
		for id in ids:
			run_shop[p].force.push_back(str(id))


func inject_shop_force(shop_items: Array, p: int, wave: int) -> void:
	if p < 0 or p >= run_shop.size():
		return
	var q = run_shop[p].force
	var k = 0
	while not q.empty() and k < shop_items.size():
		var r = _find_any(str(q.pop_front()))
		if r == null or r is CharacterData:
			continue
		if r is ItemData:
			r = _isvc().apply_item_effect_modifications(r, p)
		shop_items[shop_items.size() - 1 - k] = [r, wave]
		k += 1


func _with_run_shop(bans: Array, p: int) -> Array:
	if p >= run_shop.size() or (run_shop[p].add.empty() and run_shop[p].remove.empty()):
		return bans
	var out = bans.duplicate()
	for id in run_shop[p].add:
		out.erase(Keys.generate_hash(id))
	for id in run_shop[p].remove:
		out.push_back(Keys.generate_hash(id))
	return out


# ============================================================
# 敌人（蓝图效果"生成敌人"）：原版图鉴里的普通敌人（不含精英 / 首领）
# ============================================================
var _enemies = null


func enemy_list() -> Array:
	if _enemies == null:
		_enemies = []
		var isvc = _isvc()
		for e in isvc.entities if isvc != null else []:
			if e is ItemEnemy and not e.is_boss and not e.is_elite and e.icon != null:
				var path = e.icon.resource_path.get_base_dir() + "/" + e.my_id + ".tscn"
				if ResourceLoader.exists(path):
					_enemies.push_back({"id": e.my_id, "name": e.name, "icon": e.icon, "scene": path})
	return _enemies


func enemy_scene(id: String):
	for e in enemy_list():
		if e.id == id:
			return load(e.scene)
	return null


func enemy_name(id: String) -> String:
	for e in enemy_list():
		if e.id == id:
			return tr(e.name)
	return id


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
	if not File.new().file_exists(ICON_DIR + name) or img.load(ICON_DIR + name) != OK:
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
