extends Node

# Mojimoon-AutoAnthony：东尼算法（Brotato 版）
# 每局开始时把原版道具（可选：角色、武器）拆成组件，再按价值预算重新组装；
# 触发型效果由通用的 (扳机 × 载荷 × 门控) 条款表达，任意扳机都能驱动任意合法载荷。
#
# 生成结果直接写回原版 ItemData / CharacterData / WeaponData 资源（保留 ID、图标、稀有度和价格），
# 商店、箱子、存档都自动沿用；回到主菜单时还原。本局种子与设置写入存档，读档时按种子重建。

const MOD_ID = "Mojimoon-AutoAnthony"
const MOD_DIR = "res://mods-unpacked/Mojimoon-AutoAnthony/"
const VERSION = "1.0.0"
const SETTINGS_PATH = "user://Mojimoon-AutoAnthony/settings.json"
const CSV_PATH = MOD_DIR + "translations/autoanthony.csv"

const Generator = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/generator.gd")
const TriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")
const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")

# ------------------------------------------------------------
# 设置（弹窗配置，持久化到 JSON）
# ------------------------------------------------------------
var enabled: bool = true
var cfg_items: bool = true
var cfg_characters: bool = false
var cfg_weapons: bool = false
var cfg_char_effects: bool = false	# 道具可含角色效果
var cfg_rename: bool = true			# 重组名称
var cfg_avg: int = 100				# 平均数值 50–200%
var cfg_variance: int = 100			# 浮动范围 50–200%（100% = 原版离散度）
var cfg_triggers: int = 100			# 触发效果 50–200%（100% = 原版特殊行比例）
var cfg_native_ratio: int = 0		# 保留原版道具 0–100%
var cfg_fixed_seed: bool = false
var cfg_seed: int = 0

# ------------------------------------------------------------
# 运行时状态
# ------------------------------------------------------------
# 本局生成状态（写入存档）：{ "version", "seed", "cfg" }；null = 本局未启用
var active_state = null
var plan: Dictionary = {}
# 资源 instance_id -> 原始字段
var _backups: Dictionary = {}
# 运行时触发索引需要重建
var triggers_dirty: bool = true
# 原版"道具组"备份（按道具 ID 写死，重组后按语义重建）
var _groups_backup = null
var _gen = null
var _effect_registered := false


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/extensions/"
	ModLoaderMod.install_script_extension(dir + "singletons/run_data.gd")
	ModLoaderMod.install_script_extension(dir + "main.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/character_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/shop/shop.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/shop/coop_shop.gd")


func _ready() -> void:
	_register_translations()
	_load_settings()
	call_deferred("register_effect_script")


# 存档反序列化按 get_id() 在 ItemService.effects 中查找效果脚本
func register_effect_script() -> void:
	if _effect_registered:
		return
	var isvc = _autoload("ItemService")
	if isvc == null:
		return
	if not TriggerEffect in isvc.effects:
		isvc.effects.push_back(TriggerEffect)
	_effect_registered = true


# 效果原文 + 说明（例如"……（生效后此道具消失）"）：按当前语言生成组合描述并注册
var _note_translations: Dictionary = {}


func register_note(new_key: String, native_key: String, note_key: String) -> void:
	var locale = TranslationServer.get_locale()
	var t = _note_translations.get(locale)
	if t == null:
		t = Translation.new()
		t.locale = locale
		TranslationServer.add_translation(t)
		_note_translations[locale] = t
	if t.get_message(new_key) == "":
		t.add_message(new_key, tr(native_key) + tr(note_key))


static func _autoload(name_: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/" + name_)


static func get_mod() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/ModLoader/" + MOD_ID)


# ============================================================
# 设置持久化
# ============================================================
func get_cfg() -> Dictionary:
	return {
		"items": cfg_items,
		"characters": cfg_characters,
		"weapons": cfg_weapons,
		"char_effects": cfg_char_effects,
		"rename": cfg_rename,
		"avg": cfg_avg,
		"variance": cfg_variance,
		"triggers": cfg_triggers,
		"native_ratio": cfg_native_ratio,
	}


func save_settings() -> void:
	var data = get_cfg()
	data["version"] = VERSION
	data["enabled"] = enabled
	data["fixed_seed"] = cfg_fixed_seed
	data["seed"] = cfg_seed
	var dir = Directory.new()
	var dir_path = SETTINGS_PATH.get_base_dir()
	if not dir.dir_exists(dir_path):
		dir.make_dir_recursive(dir_path)
	var file = File.new()
	if file.open(SETTINGS_PATH, File.WRITE) != OK:
		ModLoaderLog.error("Failed to save settings", MOD_ID)
		return
	file.store_string(JSON.print(data, "\t"))
	file.close()


func _load_settings() -> void:
	var file = File.new()
	if not file.file_exists(SETTINGS_PATH):
		return
	if file.open(SETTINGS_PATH, File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		return
	var d: Dictionary = parsed.result
	enabled = bool(d.get("enabled", true))
	cfg_items = bool(d.get("items", true))
	cfg_characters = bool(d.get("characters", false))
	cfg_weapons = bool(d.get("weapons", false))
	cfg_char_effects = bool(d.get("char_effects", false))
	cfg_rename = bool(d.get("rename", true))
	cfg_avg = int(clamp(int(d.get("avg", 100)), 50, 200))
	cfg_variance = int(clamp(int(d.get("variance", 100)), 50, 200))
	cfg_triggers = int(clamp(int(d.get("triggers", 100)), 50, 200))
	cfg_native_ratio = int(clamp(int(d.get("native_ratio", 0)), 0, 100))
	cfg_fixed_seed = bool(d.get("fixed_seed", false))
	cfg_seed = int(d.get("seed", 0))


# ============================================================
# 本地化（运行时解析 CSV）
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
		for i in range(1, min(row.size(), header.size())):
			var value = row[i].c_unescape()
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
# 本局生命周期
# ============================================================

# 难度确认、进入战斗前调用：生成并把已持有的角色 / 初始道具 / 初始武器换成生成版本
func start_new_run() -> void:
	register_effect_script()
	if not enabled or not (cfg_items or cfg_characters or cfg_weapons):
		restore()
		active_state = null
		return
	var s = cfg_seed if cfg_fixed_seed else (randi() % 999999999)
	var state = {"version": VERSION, "seed": s, "cfg": get_cfg()}
	var owned = _collect_owned()
	_activate(state)
	_materialize_owned(owned)


# 回到主菜单 / 新开一局前
func on_menu_reset() -> void:
	restore()
	active_state = null


# 读档：按存档中的种子重建，并修复读档时丢失的触发条款
func on_resume(state: Dictionary) -> void:
	register_effect_script()
	var aa = state.get("aa_state", null)
	if aa == null or not aa is Dictionary:
		restore()
		active_state = null
		return
	_activate(aa)
	_repair_loaded(state)


func preview_plan(p_seed: int) -> Dictionary:
	var gen = Generator.new(get_cfg(), p_seed)
	var isvc = _autoload("ItemService")
	return gen.generate(native_only(isvc.items), native_only(isvc.characters), [], [])


func _activate(state: Dictionary) -> void:
	restore()
	active_state = state.duplicate(true)
	var isvc = _autoload("ItemService")
	var rd = _autoload("RunData")
	var chars = []
	for pd in rd.players_data:
		if pd.current_character != null:
			var native = _find(isvc.characters, pd.current_character.my_id)
			if native != null and not native in chars:
				chars.push_back(native)
	var gen = Generator.new(state.cfg, int(state.seed))
	# 本局玩家角色的初始道具（角色效果里的初始 / 诅咒初始道具，以及开局可选的道具，例如驯兽师的四只宠物）
	# 本局不重组：初始道具与商店里的同 ID 道具一致，背包合并显示、存档（原版按 ID 缓存序列化）、独特限制都保持正确
	gen.run_excluded_ids = starting_item_ids(chars)
	# 本局所有玩家角色的偏好词条：重组后 T1–T3 每个稀有度都保证有带这些词条的道具
	for ch in chars:
		for t in ch.wanted_tags:
			if not t in gen.player_wanted_tags:
				gen.player_wanted_tags.push_back(t)
	plan = gen.generate(native_only(isvc.items), native_only(isvc.characters), native_only(chars), native_only(isvc.weapons))
	_gen = gen
	var rename = bool(state.cfg.get("rename", true))
	for id in plan.items:
		var res = _find(isvc.items, id)
		if res != null:
			var p = plan.items[id]
			_backup(res)
			res.effects = p.effects
			res.tags = p.tags
			res.tracking_text = "[EMPTY]"
			# 原版的"限制 (N)"/"独特"属于原道具，不继承到重组后的道具上
			res.max_nb = -1
			# 金鱼 / 沙漏 / 镜子在原版"用后 / 移除时变成另一件道具"：重组后不再继承
			res.replaced_by = null
			if rename:
				res.name = _compose_name(p.adj, _backups[res.get_instance_id()].name)
	for id in plan.characters:
		var res = _find(isvc.characters, id)
		if res != null:
			var p = plan.characters[id]
			_backup(res)
			res.effects = p.effects
			if rename:
				res.name = _compose_name(p.adj, _backups[res.get_instance_id()].name)
	for id in plan.weapons:
		var res = _find(isvc.weapons, id)
		if res != null:
			_backup(res)
			res.effects = plan.weapons[id].effects
	_rebuild_groups_and_bans(isvc)
	triggers_dirty = true
	ModLoaderLog.info("Activated seed %d: %d items, %d characters, %d weapons" % [int(state.seed), plan.items.size(), plan.characters.size(), plan.weapons.size()], MOD_ID)


# 原版的"道具组"（角色整组禁用）与角色的禁用道具都按道具 ID 写死。重组后：
#   道具组 = 未重组的原成员 + 主属性满足该组属性的生成道具
#   角色禁用 = 未重组的原禁用道具 + 与"被禁用原版道具的语义主属性"相同的生成道具
#   （例如魔像禁用了触手、圣杯等回血道具 -> 禁用主效果为回血的生成道具）
func _rebuild_groups_and_bans(isvc) -> void:
	if plan.items.empty() or _gen == null:
		return
	_groups_backup = isvc.item_groups
	var groups = {}
	for g in _groups_backup:
		var members = []
		for id in _groups_backup[g]:
			if not plan.items.has(id):
				members.push_back(id)
		var need = Catalog.GROUP_STATS.get(g, [])
		if not need.empty():
			for id in plan.items:
				var ok = true
				for st in need:
					if not st in plan.items[id].main_stats:
						ok = false
				if ok:
					members.push_back(id)
		groups[g] = members
	isvc.item_groups = groups
	for ch in isvc.characters:
		var orig_banned: Array = ch.banned_items
		# 武器栏被规则限定的角色（独臂、野兽大师、公牛、多面手、宝宝……）：不出现"+武器栏"道具
		var slot_rule = false
		for e in ch.effects:
			if e.key == "weapon_slot" or e.key == "weapon_slot_upgrades":
				slot_rule = true
		var extra = []
		if slot_rule:
			for id in plan.items:
				if "weapon_slot" in plan.items[id].main_stats:
					extra.push_back(id)
		if orig_banned.empty() and extra.empty():
			continue
		var semantics = []
		var kept = []
		for id in orig_banned:
			if plan.items.has(id):
				var orig = _find(isvc.items, id)
				var b = _backups.get(orig.get_instance_id()) if orig != null else null
				if b != null:
					for sem in _gen.ban_reasons(b.effects):
						# 角色想要的词条优先：不会因为某件被禁道具恰好以它为主属性而禁掉整类（例如幽灵想要闪避）
						if not sem in semantics and not sem in ch.wanted_tags:
							semantics.push_back(sem)
			else:
				kept.push_back(id)
		for id in plan.items:
			for sem in semantics:
				if sem in plan.items[id].main_stats and not id in kept:
					kept.push_back(id)
		for id in extra:
			if not id in kept:
				kept.push_back(id)
		_backup(ch)
		if not _backups[ch.get_instance_id()].has("banned_items"):
			_backups[ch.get_instance_id()]["banned_items"] = orig_banned
		ch.banned_items = kept


# 只重组原版（含 DLC）的道具 / 角色 / 武器：其他 mod 加入的内容不重组、不参与先验统计、也不作为机制来源，
# 照常留在道具池里。判断依据是资源来源目录（mod 的资源来自 mods-unpacked 或由脚本创建，没有原版路径）。
const NATIVE_RESOURCE_DIRS = ["res://items/", "res://dlcs/", "res://weapons/"]


static func is_native_resource(res) -> bool:
	if res == null:
		return false
	var path: String = res.resource_path
	for d in NATIVE_RESOURCE_DIRS:
		if path.begins_with(d):
			return true
	return false


static func native_only(arr: Array) -> Array:
	var out = []
	for r in arr:
		if is_native_resource(r):
			out.push_back(r)
	return out


func _compose_name(adj_key: String, native_name_key: String) -> String:
	return tr("AA_NAME_FMT").replace("{0}", tr(adj_key)).replace("{1}", tr(native_name_key))


static func _find(arr: Array, id: String):
	for r in arr:
		if r.my_id == id:
			return r
	return null


func _backup(res) -> void:
	var id = res.get_instance_id()
	if _backups.has(id):
		return
	var b = {"res": res, "effects": res.effects, "name": res.name}
	if res is ItemData:
		b.tags = res.tags
		b.tracking_text = res.tracking_text
		b.max_nb = res.max_nb
		b.replaced_by = res.replaced_by
	_backups[id] = b


func restore() -> void:
	for id in _backups:
		var b = _backups[id]
		var res = b.res
		if res == null or not is_instance_valid(res):
			continue
		res.effects = b.effects
		res.name = b.name
		if b.has("banned_items"):
			res.banned_items = b.banned_items
		if b.has("tags"):
			res.tags = b.tags
			res.tracking_text = b.tracking_text
			res.max_nb = b.max_nb
			res.replaced_by = b.replaced_by
	_backups.clear()
	if _groups_backup != null:
		var isvc = _autoload("ItemService")
		if isvc != null:
			isvc.item_groups = _groups_backup
		_groups_backup = null
	_gen = null
	plan = {}
	triggers_dirty = true


func is_generated(res) -> bool:
	if plan.empty() or res == null:
		return false
	if res is WeaponData:
		return plan.weapons.has(res.my_id)
	if res is CharacterData:
		return plan.characters.has(res.my_id)
	return plan.items.has(res.my_id)


# 记录生成前已持有的对象和它们当前生效的效果数组
func _collect_owned() -> Array:
	var rd = _autoload("RunData")
	var owned = []
	for p in rd.get_player_count():
		var pd = rd.players_data[p]
		for it in pd.items:
			owned.push_back([p, it, it.effects])
		for w in pd.weapons:
			owned.push_back([p, w, w.effects])
	return owned


func _template_for(res):
	var isvc = _autoload("ItemService")
	if res is WeaponData:
		return _find(isvc.weapons, res.my_id) if plan.weapons.has(res.my_id) else null
	if res is CharacterData:
		return _find(isvc.characters, res.my_id) if plan.characters.has(res.my_id) else null
	return _find(isvc.items, res.my_id) if plan.items.has(res.my_id) else null


func _materialize_owned(owned: Array) -> void:
	var rd = _autoload("RunData")
	var touched = {}
	for o in owned:
		var p: int = o[0]
		var res = o[1]
		var old: Array = o[2]
		if res.is_cursed:
			continue
		var tmpl = _template_for(res)
		if tmpl == null:
			continue
		rd.unapply_effects_array(old, p)
		if res != tmpl:
			res.effects = tmpl.effects if res is WeaponData else _dup_effects(tmpl.effects)
			res.name = tmpl.name
			if res is ItemData and not res is CharacterData:
				res.tags = tmpl.tags
				res.tracking_text = tmpl.tracking_text
				res.max_nb = tmpl.max_nb
				res.replaced_by = tmpl.replaced_by
		rd.apply_item_effects(res, p)
		touched[p] = true
	for p in touched:
		rd.update_sets(p)
		rd.update_item_related_effects(p)
		LinkedStats.reset_player(p)
	triggers_dirty = true


static func starting_item_ids(chars: Array) -> Array:
	var ids = []
	for ch in chars:
		for e in ch.effects:
			if e.custom_key in ["starting_item", "cursed_starting_item"] and not e.key in ids:
				ids.push_back(e.key)
		for it in ch.starting_items:
			if it != null and not it.my_id in ids:
				ids.push_back(it.my_id)
	return ids


static func _dup_effects(effects: Array) -> Array:
	var out = []
	for e in effects:
		out.push_back(e.duplicate())
	return out


# 读档后的修复：启动时存档可能在本 mod 注册效果脚本之前就被反序列化，触发条款会丢失。
# 只补回缺失的触发条款（诅咒物品按诅咒系数增强），其余效果保持存档原样（例如已消失的一次性效果不会被补回）。
func _repair_loaded(state: Dictionary) -> void:
	var rd = _autoload("RunData")
	for pd in rd.players_data:
		for it in pd.items:
			_repair_item(it)
	for list in rd.locked_shop_items:
		for entry in list:
			if entry[0] is ItemData:
				_repair_item(entry[0])
	if state.has("shop_items") and state.shop_items is Array:
		for list in state.shop_items:
			for entry in list:
				if entry is Array and entry.size() > 0 and entry[0] is ItemData:
					_repair_item(entry[0])
	triggers_dirty = true


func _repair_item(it) -> void:
	var tmpl = _template_for(it)
	if tmpl == null or tmpl == it:
		return
	it.name = tmpl.name
	if not it is CharacterData:
		it.tags = tmpl.tags
		it.tracking_text = tmpl.tracking_text
		it.max_nb = tmpl.max_nb
		it.replaced_by = tmpl.replaced_by
	var has_trigger = false
	for e in it.effects:
		if e is TriggerEffect:
			has_trigger = true
	if has_trigger:
		return
	var dlc = null
	var pd = _autoload("ProgressData")
	if pd != null:
		dlc = pd.get_dlc_data("abyssal_terrors")
	var new_effects = it.effects.duplicate()
	for e in tmpl.effects:
		if e is TriggerEffect:
			var ne = e.duplicate()
			if it.is_cursed and dlc != null and dlc.has_method("_boost_effect_value_positively"):
				ne.value = dlc._boost_effect_value_positively(ne, it.curse_factor)
			new_effects.push_back(ne)
	it.effects = new_effects
	it.name = tmpl.name


# ============================================================
# 商店阶段扳机（刷新 / 购买）：只允许永久属性与材料
# ============================================================
func fire_shop(event: String, player_index: int) -> void:
	if active_state == null:
		return
	var rd = _autoload("RunData")
	var sources = []
	sources += rd.get_player_items_ref(player_index)
	sources += rd.get_player_weapons_ref(player_index)
	for src in sources:
		for e in src.effects:
			if not e is TriggerEffect or e.trigger != event:
				continue
			if e.chance < 100 and randf() * 100.0 >= e.chance:
				continue
			match e.payload:
				"perm_stat":
					rd.add_stat(Keys.generate_hash(e.stat), e.value, player_index)
					LinkedStats.reset_player(player_index)
				"grant":
					if e.grant != null:
						e.scaled_grant().apply(player_index)
						Utils.reset_stat_cache(player_index)
						rd._are_player_stats_dirty[player_index] = true
						LinkedStats.reset_player(player_index)
				"gold":
					rd.add_gold(e.value, player_index)


# ============================================================
# 设置按钮：挂在角色 / 武器 / 难度选择界面的返回按钮旁
# ============================================================
const UI_SCENE = MOD_DIR + "ui/settings_ui.tscn"
const FONT_26_PATH = "res://resources/fonts/actual/base/font_26.tres"


static func add_config_button(screen: Node) -> void:
	if screen == null or not screen.is_inside_tree():
		return
	var back_button = screen.get_node_or_null("%BackButton")
	if back_button == null or back_button.has_node("AutoAnthonyBtn"):
		return
	var btn = Button.new()
	btn.name = "AutoAnthonyBtn"
	btn.text = TranslationServer.translate("AA_BTN_OPEN")
	btn.rect_min_size = Vector2(200, 50)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_font_override("font", load(FONT_26_PATH))
	place_config_button(back_button, btn)
	btn.connect("pressed", get_mod(), "open_settings", [screen])


func open_settings(screen: Node) -> void:
	var scene = load(UI_SCENE)
	if scene == null or screen == null:
		return
	var ui = scene.instance()
	var layer = CanvasLayer.new()
	layer.layer = 100
	screen.get_tree().current_scene.add_child(layer)
	layer.add_child(ui)
	ui.connect("tree_exited", layer, "queue_free")


# ============================================================
# 按钮定位（兼容 cave-modtools、OneItemToRuleThemAll 等挂在返回按钮旁的 mod 按钮）
# ============================================================
static func place_config_button(back_button: Node, btn: Button) -> void:
	if back_button == null or btn == null:
		return
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
	if left_neighbour != null:
		btn.focus_neighbour_left = btn.get_path_to(left_neighbour)
	else:
		btn.focus_neighbour_left = btn.get_path_to(back_button)
