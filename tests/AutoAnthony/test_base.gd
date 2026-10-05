extends Reference

# 东尼算法无头测试：在反编译的游戏工程里运行，使用真实的 ItemService / RunData / ModLoader。
# 公共基类：状态、工具函数、运行流程；测试分在 suite_core / suite_audit / suite_battle.gd。
# 由 run_aa.gd 在 autoload 就绪后加载；请使用同目录的 run_tests.sh（会同步 mod、隔离 user://）。

const MOD_ID = "Mojimoon-AutoAnthony"
const MOD_DIR = "res://mods-unpacked/" + MOD_ID + "/"
const SEEDS = [1, 42, 777, 20260927, 99999]

var Catalog
var Valuation
var Generator
var TriggerEffect
var Runtime

var m
var isvc
var rd
var tree: SceneTree
var _current_test = ""
# 各组共用的计数（run_aa.gd 依次运行选中的测试组）
var ctx: Dictionary = {"checks": 0, "failures": []}


func setup(p_tree: SceneTree, p_ctx: Dictionary) -> int:
	tree = p_tree
	ctx = p_ctx
	if OS.get_environment("AA_TEST") != "1":
		printerr("Refusing to run: use run_tests.sh (it isolates user:// from your real saves).")
		return 2
	m = tree.root.get_node_or_null("ModLoader/" + MOD_ID)
	isvc = tree.root.get_node("ItemService")
	rd = tree.root.get_node("RunData")
	if m == null:
		printerr("Mod node not found: is the mod in res://mods-unpacked?")
		return 2
	Catalog = load(MOD_DIR + "aa/catalog.gd")
	Valuation = load(MOD_DIR + "aa/valuation.gd")
	Generator = load(MOD_DIR + "aa/generator.gd")
	TriggerEffect = load(MOD_DIR + "aa/trigger_effect.gd")
	Runtime = load(MOD_DIR + "aa/runtime.gd")
	_unlock_everything()
	return 0


# 运行本组的 test_ 方法（AA_ONLY 按名字过滤）
func run_suite():
	var tests: Array = []
	for method in get_method_list():
		if method.name.begins_with("test_") and (OS.get_environment("AA_ONLY") == "" or method.name.find(OS.get_environment("AA_ONLY")) >= 0):
			tests.push_back(method.name)
	tests.sort()
	for t in tests:
		_current_test = t
		_reset()
		var t0 = OS.get_ticks_msec()
		var c0 = ctx.checks
		var state = call(t)
		if state is GDScriptFunctionState:
			yield(state, "completed")
		print("  ran %s (%.1fs, %d checks)" % [t, (OS.get_ticks_msec() - t0) / 1000.0, ctx.checks - c0])
	m.on_menu_reset()


# 全部组跑完：输出 ITEMS.md 与汇总
func finish() -> int:
	_reset()
	# 表格用真正的默认设置（浮动范围、触发效果默认 150%）
	m.cfg_variance = 125
	m.cfg_triggers = 150
	_write_items_table()
	m.on_menu_reset()
	print("")
	print("%d checks, %d failures" % [ctx.checks, ctx.failures.size()])
	for f in ctx.failures:
		printerr("FAIL ", f)
	if ctx.failures.empty():
		print("ALL TESTS PASSED")
	return 0 if ctx.failures.empty() else 1


# 每次测试都输出：默认设置（固定种子 42）下全部重组道具的 markdown 表格 -> mods/tests/AutoAnthony/ITEMS.md
const ITEMS_TABLE_SEED = 42
const ITEMS_TABLE_PATH = "res://mods/tests/AutoAnthony/ITEMS.md"


func _write_items_table() -> void:
	var prev = TranslationServer.get_locale()
	# 默认输出简体中文；AA_ITEMS_LOCALE / AA_ITEMS_OUT 可输出其他语言到指定路径（核对文本用）
	var loc = OS.get_environment("AA_ITEMS_LOCALE")
	TranslationServer.set_locale(loc if loc != "" else "zh")
	var gen = Generator.new(_cfg(), ITEMS_TABLE_SEED)
	var plan = gen.generate(m.native_only(isvc.items), m.native_only(isvc.characters), [], [])
	var strip = RegEx.new()
	strip.compile("\\[img[^\\]]*\\][^\\[]*\\[/img\\]|\\[/?color\\]|\\[color=[^\\]]*\\]")
	var entries = []
	for it in isvc.items:
		if plan.items.has(it.my_id):
			entries.push_back(it)
	entries.sort_custom(self, "_sort_tier_price")
	var count = [0, 0, 0, 0]
	var lines = []
	for it in entries:
		var p = plan.items[it.my_id]
		count[it.tier] += 1
		var nm = tr("AA_NAME_FMT").replace("{0}", tr(p.adj)).replace("{1}", tr(it.name))
		var fx = []
		for e in p.effects:
			var t = strip.sub(e.get_text(0, false), "", true).strip_edges()
			if t != "":
				fx.push_back(t.replace("|", "/").replace("\n", " "))
		var mark = ""
		if p.get("core", "") != "":
			mark = "核心"
		elif p.get("wanted_tag", "") != "":
			mark = "词条保底"
		if p.get("unique", false):
			mark += ("，" if mark != "" else "") + "独特"
		elif int(p.get("limit", 0)) > 1:
			mark += ("，" if mark != "" else "") + "限制 (%d)" % p.limit
		if p.get("growth", false):
			mark += ("，" if mark != "" else "") + "成长型"
		var tags = PoolStringArray(p.tags).join(", ") if not p.tags.empty() else "（无）"
		lines.push_back("| T%d | %s | %d | %s | %s | %s |" % [it.tier + 1, nm, p.price, PoolStringArray(fx).join("<br>"), tags, mark])
	var out = "# 默认设置下的全部重组道具\n\n"
	out += "由测试在每次运行结束时自动生成（`test_base.gd` 的 `_write_items_table`）。默认设置：重组道具、重组名称开启，其余选项关闭，平均数值 100%、浮动范围 125%、触发效果 150%，保留原版道具 0%；种子 " + str(ITEMS_TABLE_SEED) + "。\n\n"
	out += "共 %d 件：T1 %d、T2 %d、T3 %d、T4 %d。锚定道具（望远镜、诱饵、口袋工厂、美西螈、鱼钩等）保持原版，不在表内。\n\n" % [entries.size(), count[0], count[1], count[2], count[3]]
	out += "词条为道具资源的 tags（角色的偏好词条、商店按词条加权抽取都用它），使用原版的词条 ID。\n\n"
	out += "| 稀有度 | 道具 | 价格 | 效果 | 词条 | 备注 |\n| --- | --- | --- | --- | --- | --- |\n"
	out += PoolStringArray(lines).join("\n") + "\n"
	var f = File.new()
	var out_path = OS.get_environment("AA_ITEMS_OUT") if loc != "" and OS.get_environment("AA_ITEMS_OUT") != "" else ITEMS_TABLE_PATH
	if f.open(out_path, File.WRITE) == OK:
		f.store_string(out)
		f.close()
		print("items table: ", ProjectSettings.globalize_path(out_path), " (", entries.size(), " items)")
	else:
		printerr("FAIL could not write ", ITEMS_TABLE_PATH)
	TranslationServer.set_locale(prev)


func _sort_tier_price(a, b) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.my_id < b.my_id


# ============================================================
# 工具
# ============================================================
func _check(cond: bool, msg: String) -> void:
	ctx.checks += 1
	if not cond:
		ctx.failures.push_back(_current_test + ": " + msg)


func _eq(actual, expected, msg: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func _reset() -> void:
	m.on_menu_reset()
	m.enabled = true
	m.cfg_items = true
	m.cfg_characters = false
	m.cfg_weapons = false
	m.cfg_avg = 100
	m.cfg_variance = 100
	m.cfg_triggers = 100
	m.cfg_char_effects = false
	m.cfg_all_char_effects = false
	m.cfg_more_double = false
	m.cfg_rename = true
	m.cfg_force_items = false
	m.cfg_chaos = false
	m.cfg_weapon_mode = "effects"
	m.cfg_w_item_effects = false
	m.cfg_w_low_tiers = false
	m.cfg_w_any_start = false
	m.cfg_w_avg = 100
	m.cfg_w_variance = 100
	m.cfg_w_effects = 125
	m.cfg_tier_chaos = false
	m.cfg_w_rename = true
	m.cfg_native_ratio = 0
	m.cfg_fixed_seed = true
	m.cfg_seed = 42
	_setup_player("character_well_rounded")
	rd.current_wave = 5


func _setup_player(char_id: String) -> void:
	rd.set_player_count(1, true)
	rd.enabled_dlcs = []
	var ch = isvc.get_element_safe(isvc.characters, char_id)
	rd.add_character(ch, 0)


func _unlock_everything() -> void:
	var pd = tree.root.get_node("ProgressData")
	pd.items_unlocked = []
	for it in isvc.items:
		pd.items_unlocked.push_back(it.my_id_hash)
	pd.weapons_unlocked = []
	for w in isvc.weapons:
		if not pd.weapons_unlocked.has(w.weapon_id_hash):
			pd.weapons_unlocked.push_back(w.weapon_id_hash)
	isvc.init_unlocked_pool()


func _cfg() -> Dictionary:
	return m.get_cfg()


func _gen(p_seed: int, cfg = null) -> Dictionary:
	var g = Generator.new(cfg if cfg != null else _cfg(), p_seed)
	return g.generate(isvc.items, isvc.characters, [], [])


func _texts(effects: Array) -> String:
	var s = ""
	for e in effects:
		s += e.get_text(0, false) + "|"
	return s


func _plan_signature(plan: Dictionary) -> String:
	var ids = plan.items.keys()
	ids.sort()
	var s = ""
	for id in ids:
		s += id + ":" + _texts(plan.items[id].effects) + "\n"
	return s


func _item(id: String):
	return isvc.get_element_safe(isvc.items, id)


func _has_up_mechanic(effects: Array) -> bool:
	for e in effects:
		if e.has_meta("aa_value") and e.get_meta("aa_value") > 0:
			return true
	return false


# 生成结果的估算价值（属性行 + 触发条款；机制行按来源估值；负面按补偿比例）
func _value_of(gen, effects: Array, tier: int) -> float:
	var v = 0.0
	for e in effects:
		if e is TriggerEffect:
			var cv = Valuation.clause_value(e.to_clause(), Catalog.PERM_MULT[tier])
			v += cv if cv >= 0 else cv / Catalog.DOWNSIDE_DIVISOR
		elif gen.is_plain_stat(e):
			v += gen.line_value(e.key, e.value)
		elif gen.is_scaling(e):
			var sv = Valuation.scaling_effect_value(e)
			v += sv if sv >= 0 else sv / Catalog.DOWNSIDE_DIVISOR
		elif gen.is_gain_mod(e):
			var gv = Valuation.gain_mod_value(e.stats_modified[0], e.value)
			v += gv if gv >= 0 else gv / Catalog.DOWNSIDE_DIVISOR
		elif e.has_meta("aa_value"):
			var mv = e.get_meta("aa_value")
			v += mv
	return v


# ============================================================
# 运行时触发总线
# ============================================================
func _make_runtime(clauses: Array):
	var holder = _item("item_potato").duplicate()
	var effects = []
	for c in clauses:
		effects.push_back(TriggerEffect.make(c))
	holder.effects = effects
	rd.players_data[0].items.push_back(holder)
	var rt = Runtime.new()
	tree.root.add_child(rt)
	rt.mod = m
	rt.rebuild_all()
	return rt


# ============================================================
# 参数实验：预算模型 × 负面除数。每档对比生成道具与原版纯属性道具的正面数值 / 净值中位数。
# "真实"一列按实际频率（击杀 / 材料 110、受击 7、回血 12）重估触发条款，即玩家体感。
# ============================================================
const REAL_RATE = {"kill": 110.0 / 120.0, "gold": 110.0 / 120.0, "hit": 7.0 / 10.0, "heal": 12.0 / 20.0}


func _med(a: Array) -> float:
	if a.empty():
		return 0.0
	var b = a.duplicate()
	b.sort()
	return b[b.size() / 2]


func _item_metrics(gen, effects: Array, tier: int) -> Array:
	var pos = 0.0
	var net = 0.0
	var real = 0.0
	for e in effects:
		var v = 0.0
		var rv = 0.0
		if e is TriggerEffect:
			v = Valuation.clause_value(e.to_clause(), Catalog.PERM_MULT[tier])
			rv = v * REAL_RATE.get(e.trigger, 1.0)
		elif gen.is_plain_stat(e):
			v = Valuation.stat_line_value(e.key, e.value)
			rv = v
		elif gen.is_scaling(e):
			v = Valuation.scaling_effect_value(e)
			rv = v
		elif gen.is_gain_mod(e):
			v = Valuation.gain_mod_value(e.stats_modified[0], e.value)
			rv = v
		elif e.has_meta("aa_value"):
			v = e.get_meta("aa_value")
			rv = v
		if v > 0:
			pos += v
			net += v
			real += rv
		else:
			net += v / gen.divisor if not e.has_meta("aa_value") else v
			real += rv / gen.divisor if not e.has_meta("aa_value") else rv
	return [pos, net, real]


# ============================================================
# 原版按道具 ID 实现的效果：搬运到其他道具后仍然可用
# ============================================================
func _find_mech(gen, key: String):
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			var k = mech.effect.custom_key if mech.effect.custom_key != "" else mech.effect.key
			if k == key:
				return mech
	return null


# ============================================================
# 自由触发：任何扳机 -> "获得效果"
# ============================================================
func _plain(key: String, value: int) -> Effect:
	var e = load("res://items/global/effect.gd").new()
	e.key = key
	e.key_hash = Keys.generate_hash(key)
	e.custom_key_hash = Keys.generate_hash("")
	e.value = value
	return e


func rng_budget(i: int) -> float:
	return [10.0, 20.0, 35.0, 60.0][i % 4]


# ============================================================
# 诅咒：把整个生成道具池逐件诅咒（原版 DLC 代码），检查方向与可用性
# ============================================================
func _is_good(e) -> bool:
	var s = e.get_sign(e.effect_sign, e.value)
	return s == Effect.Sign.POSITIVE or s == Effect.Sign.OVERRIDE


const CURSE_ID_ASSERTED = {
	"hit_protection": "item_tardigrade", "hp_regen_bonus": "item_potion", "upgrade_random_weapon": "item_anvil",
	"wandering_bot": "item_wandering_bot", "instant_gold_attracting": "item_sifds_relic",
}


# ============================================================
# 实际商店抽取：每个角色分别用原版道具池与重组道具池各抽 N 件道具（原版 ItemService._get_rand_item_for_wave），
# 检查 (1) 角色禁用（禁用道具 / 禁用道具组 / remove_shop_items 词条）在重组后按语义生效；
# (2) 角色想要的词条（wanted_tags）在重组后仍然提高出现概率，且带该词条的道具确实提供对应效果
# ============================================================
const ROLLS_PER_MODE = 200
const WANTED_ROLLS = 800


# 道具的所有正面语义（不只主属性）：属性、回血、规则性语义
var _sem_gen = null


func _pos_semantics(effects: Array) -> Array:
	if _sem_gen == null:
		_sem_gen = Generator.new(_cfg(), 1)
	var gen = _sem_gen
	var out = []
	for e in effects:
		var k = e.custom_key if e.custom_key != "" else e.key
		var add = []
		if e is TriggerEffect:
			if e.value > 0 and not Catalog.ENEMY_STATS.has(e.stat):
				if e.payload == "heal":
					add.push_back("heal")
				elif e.payload == "xp":
					add.push_back("xp_gain")
				elif e.stat != "":
					add.push_back(e.stat)
				# 扳机绑定的词条（暴击击杀 → 暴击、每走 N 步 → 速度……）
				add += Catalog.tags_for_binding("trigger:" + e.trigger)
				if e.grant != null:
					if gen.is_scaling(e.grant):
						add.push_back(e.grant.key)
					elif gen.is_gain_mod(e.grant):
						add.push_back(e.grant.stat_displayed)
					elif e.grant.has_meta("aa_tags"):
						add += e.grant.get_meta("aa_tags")
						add += Catalog.tags_for_binding("mech:" + (e.grant.custom_key if e.grant.custom_key != "" else e.grant.key))
		elif gen.is_next_wave(e) and e.value > 0:
			add.push_back(e.key)
		elif e.has_meta("aa_tags") and e.get_meta("aa_value", 0) > 0:
			add += e.get_meta("aa_tags")
			add += Catalog.tags_for_binding("mech:" + k)
		elif e.value > 0 and gen.is_plain_stat(e):
			add.push_back(e.key)
		elif e.value > 0 and gen.is_scaling(e):
			add.push_back(e.key)
			add += Catalog.tags_for_binding("counter:" + e.stat_scaled)
		elif e.value > 0 and gen.is_gain_mod(e) and e.stats_modified.size() > 0:
			add.push_back(e.stats_modified[0])
		if k in Catalog.HEAL_KEYS and e.value > 0:
			add.push_back("heal")
		for x in add:
			if not x in out:
				out.push_back(x)
	return out


func _roll_items(n: int) -> Array:
	var out = []
	for i in n:
		rd.current_wave = 1 + (i % 19)
		var it = isvc.get_rand_item_for_wave(rd.current_wave, 0)
		if it != null:
			out.push_back(it)
	return out


func _has_any(a: Array, b: Array) -> bool:
	for x in a:
		if x in b:
			return true
	return false


func _synergy_stats(effects: Array) -> Array:
	var out = []
	for e in effects:
		if e.value <= 0:
			continue
		if e is TriggerEffect:
			if e.payload in ["damage", "explode"]:
				out.push_back(e.stat)
			# 限定伤害类型的扳机（首次被 / 用 [类型] 伤害命中、击杀）与该伤害属性配合
			if e.dmg_type != "":
				out.push_back(e.dmg_type)
			if e.grant != null and "stat_scaled" in e.grant:
				out.push_back(e.grant.stat_scaled)
		elif "stat_scaled" in e:
			out.push_back(e.stat_scaled)
	return out


# ============================================================
# 真实战斗：(A) 每种扳机都能由原版事件触发；(B) 每种载荷在战斗里真正改变玩家 / 敌人 / 武器；
# (C) 生成道具池里每种 (扳机类型, 载荷, 获得效果, 属性) 在战斗中执行后都有可观察的变化
# ============================================================
func _wait_frames(n: int):
	for i in n:
		yield(tree, "idle_frame")


# 原版的属性重载按物理帧排队处理（stats_manager），等待要按物理帧计
func _wait_physics(n: int):
	for i in n:
		yield(tree, "physics_frame")


# 按敌人记录生命：新敌人同时生成会掩盖总生命的下降
func _enemy_hp_map(main) -> Dictionary:
	var d = {}
	for en in main._entity_spawner.get_all_enemies(false):
		if is_instance_valid(en) and not en.dead:
			d[en.get_instance_id()] = [en, en.current_stats.health]
	return d


func _any_enemy_hurt(main, before: Dictionary) -> bool:
	for id in before:
		var en = before[id][0]
		if not is_instance_valid(en) or en.dead or en.current_stats.health < before[id][1]:
			return true
	return false


func _enemies_hp(main) -> int:
	var s = 0
	for en in main._entity_spawner.get_all_enemies(false):
		if is_instance_valid(en) and not en.dead:
			s += en.current_stats.health
	return s


func _battle_snapshot(main) -> String:
	var p = main._players[0]
	return JSON.print([rd.get_player_effects(0), TempStats.player_stats[0], rd.get_player_gold(0), rd.get_player_xp(0), rd.get_player_level(0),
		p.current_stats.health, p.max_stats.health, _enemies_hp(main), main._entity_spawner.get_all_enemies(false).size(), main._consumables.size()])


func _wait_enemy(main):
	yield(tree, "idle_frame")
	for i in 24:
		if not is_instance_valid(main):
			return null
		var enemies = main._entity_spawner.get_all_enemies(false)
		for en in enemies:
			if is_instance_valid(en) and not en.dead:
				return en
		yield(tree.create_timer(0.25), "timeout")
	return null


# ============================================================
# 更多双面效果：常规池效果的对立面只在选项开启时出现，数值不超过上限；"失去材料"不会让材料低于 0
# ============================================================
func _double_kind(gen, e) -> String:
	var class_script = load("res://effects/items/class_bonus_effect.gd")
	if e is TriggerEffect:
		return "lose_gold" if e.payload == "gold" and e.value < 0 else ""
	if e.get_script() == class_script:
		return "class_bonus-" if e.value < 0 else ""
	if e.custom_key == "stats_end_of_wave" and Catalog.ENEMY_STATS.has(e.key) and e.value < 0:
		return "enemy_decay"
	if e.custom_key == "stats_next_wave" and Catalog.ENEMY_STATS.has(e.key) and e.value < 0:
		return "next_wave_enemy_down"
	if e.custom_key != "" or gen.is_plain_stat(e) and e.key != "weapon_slot":
		return ""
	if e.key == "weapon_slot" and e.value < 0:
		return "weapon_slot-1"
	if e.key == "weapons_price" and e.value > 0:
		return "weapons_price+"
	if e.key == "items_price" and e.value > 0:
		return "items_price+"
	if Catalog.DOUBLE_NEG_CAPS.has(e.key) and Catalog.is_downside_mechanic(e):
		return "neg:" + e.key
	if Catalog.DOUBLE_POS_ENEMY_CAPS.has(e.key) and e.value < 0:
		return "pos:" + e.key
	return ""


# ============================================================
# 角色重组：身份行与"禁用"行保留；可估值行按同等价值重组并偏向偏好词条；-100 / -100% 行按期望总量封顶估值
# ============================================================
func _char_value(gen, e) -> float:
	if e is TriggerEffect:
		var cv = Valuation.clause_value(e.to_clause(), Catalog.PERM_MULT_CHARACTER)
		return cv if cv >= 0 else cv / Catalog.DOWNSIDE_DIVISOR
	return gen.char_line_value(e)


func _sort_first_desc(a, b) -> bool:
	return a[0] > b[0]
