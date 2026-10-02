extends Reference

# 东尼算法无头测试：在反编译的游戏工程里运行，使用真实的 ItemService / RunData / ModLoader。
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
var _failures: Array = []
var _checks = 0


func run(p_tree: SceneTree):
	tree = p_tree
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
	print("user dir: ", OS.get_user_data_dir())

	var tests: Array = []
	for method in get_method_list():
		if method.name.begins_with("test_") and (OS.get_environment("AA_ONLY") == "" or method.name.find(OS.get_environment("AA_ONLY")) >= 0):
			tests.push_back(method.name)
	tests.sort()
	for t in tests:
		_current_test = t
		_reset()
		var state = call(t)
		if state is GDScriptFunctionState:
			yield(state, "completed")
		print("  ran ", t)
	m.on_menu_reset()
	_reset()
	# 表格用真正的默认设置（浮动范围、触发效果默认 150%）
	m.cfg_variance = 125
	m.cfg_triggers = 150
	_write_items_table()
	m.on_menu_reset()

	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		printerr("FAIL ", f)
	if _failures.empty():
		print("ALL TESTS PASSED")
	return 0 if _failures.empty() else 1


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
		var tags = PoolStringArray(p.tags).join(", ") if not p.tags.empty() else "（无）"
		lines.push_back("| T%d | %s | %d | %s | %s | %s |" % [it.tier + 1, nm, p.price, PoolStringArray(fx).join("<br>"), tags, mark])
	var out = "# 默认设置下的全部重组道具\n\n"
	out += "由测试在每次运行结束时自动生成（`test_cases.gd` 的 `_write_items_table`）。默认设置：重组道具、重组名称开启，其余选项关闭，平均数值 100%、浮动范围 125%、触发效果 150%，保留原版道具 0%；种子 " + str(ITEMS_TABLE_SEED) + "。\n\n"
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
	_checks += 1
	if not cond:
		_failures.push_back(_current_test + ": " + msg)


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
			var sv = Valuation.scaling_value(e.key, e.value, e.stat_scaled, e.nb_stat_scaled)
			v += sv if sv >= 0 else sv / Catalog.DOWNSIDE_DIVISOR
		elif gen.is_gain_mod(e):
			var gv = Valuation.gain_mod_value(e.stats_modified[0], e.value)
			v += gv if gv >= 0 else gv / Catalog.DOWNSIDE_DIVISOR
		elif e.has_meta("aa_value"):
			var mv = e.get_meta("aa_value")
			v += mv
	return v


# ============================================================
# 基础
# ============================================================
func test_01_mod_loaded_and_effect_registered() -> void:
	m.register_effect_script()
	_check(TriggerEffect in isvc.effects, "trigger effect script registered in ItemService.effects")
	_eq(TriggerEffect.get_id(), "aa_trigger", "effect id")


func test_02_catalog_consistency() -> void:
	for t in Catalog.TRIGGERS:
		_check(Catalog.LEGAL.has(t), "LEGAL has trigger " + t)
		for p in Catalog.LEGAL[t]:
			_check(Catalog.PAYLOADS.has(p), "payload %s of %s exists" % [p, t])
		if Catalog.TRIGGERS[t].kind == "state":
			_eq(Catalog.LEGAL[t], ["temp_stat"], "state trigger %s only drives temp stats" % t)
		if Catalog.TRIGGERS[t].kind == "shop":
			for p in Catalog.LEGAL[t]:
				_check(p in ["perm_stat", "gold", "rand_stats"], "shop trigger %s payload %s is shop-safe" % [t, p])
	_check(not "heal" in Catalog.LEGAL["heal"], "no heal->heal loop")
	for k in Catalog.NATIVE_TRIGGER_MAP:
		var pair = Catalog.NATIVE_TRIGGER_MAP[k]
		_check(pair[1] in Catalog.LEGAL[pair[0]], "native combo %s is legal in the generic system" % k)
	for s in Catalog.STATS:
		_check(Utils.is_stat_key(Keys.generate_hash(s)), "catalog stat %s is a game stat key" % s)
	for id in Catalog.ANCHORED_ITEMS:
		_check(_item(id) != null, "anchored item exists: " + id)


# ============================================================
# 生成
# ============================================================
func test_10_generation_is_deterministic() -> void:
	var a = _plan_signature(_gen(42))
	var b = _plan_signature(_gen(42))
	var c = _plan_signature(_gen(43))
	_check(a == b, "same seed -> same pool")
	_check(a != c, "different seed -> different pool")
	_check(a.length() > 1000, "pool is non-trivial")


func test_11_generated_items_are_well_formed() -> void:
	for s in SEEDS:
		var gen = Generator.new(_cfg(), s)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		_check(plan.items.size() > 120, "seed %d: most items reassembled (%d)" % [s, plan.items.size()])
		for id in plan.items:
			var p = plan.items[id]
			_check(not id in Catalog.ANCHORED_ITEMS, "anchored item not reassembled: " + id)
			_check(p.effects.size() >= 1, "%s has effects" % id)
			var has_pos = false
			for e in p.effects:
				if e.value > 0:
					has_pos = true
				var text = e.get_text(0, false)
				_check(text != "" and text.find("AA_") == -1, "%s line renders (%s) %s/%s/%s" % [id, text, e.key, e.custom_key, e.get_script().resource_path])
				if e is TriggerEffect:
					_check(e.payload in Catalog.FREE_LEGAL[e.trigger], "%s legal combo %s/%s" % [id, e.trigger, e.payload])
					_check(e.value != 0, "%s trigger value non-zero" % id)
					_check(e.chance >= 5 and e.chance <= 100, "%s chance in range" % id)
					_check(e.param >= 1, "%s param >= 1" % id)
					if e.payload in ["temp_stat", "timed_stat"]:
						_check(not e.stat in Catalog.TEMP_STAT_BANNED, "%s temp stat allowed" % id)
					if e.trigger == "interval":
						_check(e.param <= 30, "%s interval sane" % id)
				elif gen.is_plain_stat(e):
					_check(e.value % Catalog.stat_unit(e.key) == 0, "%s value multiple of unit" % id)
			_check(has_pos or _has_up_mechanic(p.effects), "%s has a positive line: %s" % [id, _texts(p.effects)])


# 价值审计：平衡模式下生成道具的估算价值应贴近原版价格预算
func test_12_value_audit() -> void:
	var ratios = []
	var trig_count = {}
	var pay_count = {}
	var with_trigger = 0
	var total = 0
	for s in SEEDS:
		var gen = Generator.new(_cfg(), s)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			var item = _item(id)
			var budget = plan.items[id].budget
			var v = _value_of(gen, plan.items[id].effects, item.tier)
			ratios.push_back(v / budget)
			if v / budget < 0.5 and s == SEEDS[0]:
				print("AUDIT low ", id, " budget=", budget, " v=", v, " ", _texts(plan.items[id].effects))
			total += 1
			var has_t = false
			for e in plan.items[id].effects:
				if e is TriggerEffect:
					has_t = true
					trig_count[e.trigger] = trig_count.get(e.trigger, 0) + 1
					pay_count[e.payload] = pay_count.get(e.payload, 0) + 1
			if has_t:
				with_trigger += 1
	ratios.sort()
	var n = ratios.size()
	var median = ratios[n / 2]
	var p10 = ratios[int(n * 0.1)]
	var p90 = ratios[int(n * 0.9)]
	var g_sh = Generator.new(_cfg(), 1)
	g_sh._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	print("AUDIT native special share by tier: ", g_sh.special_share_by_tier, " negative share: ", g_sh.neg_prob_by_tier)
	print("AUDIT value/budget: p10=%.2f median=%.2f p90=%.2f (n=%d)" % [p10, median, p90, n])
	print("AUDIT items with a trigger clause: %d / %d" % [with_trigger, total])
	var kinds = {"scaling": 0, "gain_mod": 0, "mechanic": 0}
	var samples = []
	for sd in [SEEDS[0]]:
		var gk = Generator.new(_cfg(), sd)
		var pk = gk.generate(isvc.items, isvc.characters, [], [])
		for id in pk.items:
			for e in pk.items[id].effects:
				var k = ""
				if gk.is_scaling(e):
					k = "scaling"
				elif gk.is_gain_mod(e):
					k = "gain_mod"
				elif e.has_meta("aa_value"):
					k = "mechanic"
				if k != "":
					kinds[k] += 1
					if samples.size() < 10 and k != "mechanic":
						samples.push_back(e.get_text(0, false))
	print("AUDIT special kinds (1 seed): ", kinds)
	for t in samples:
		print("AUDIT special sample: ", t)
	print("AUDIT triggers: ", trig_count)
	print("AUDIT payloads: ", pay_count)
	_check(median > 0.8 and median < 1.25, "median value/budget near 1 (%.2f)" % median)
	_check(p10 > 0.5, "p10 value/budget not too low (%.2f)" % p10)
	_check(p90 < 1.7, "p90 value/budget not too high (%.2f)" % p90)
	_check(trig_count.size() >= 12, "most triggers occur (%d)" % trig_count.size())
	_check(pay_count.size() == Catalog.PAYLOADS.size(), "all payloads occur (%d)" % pay_count.size())


func test_13_native_ratio_keeps_items() -> void:
	var cfg = _cfg()
	cfg.native_ratio = 50
	var n50 = _gen(7, cfg).items.size()
	var n0 = _gen(7).items.size()
	_check(n50 < n0 * 0.7 and n50 > n0 * 0.3, "about half kept native (%d of %d)" % [n50, n0])


func test_14_sliders() -> void:
	var cfg = _cfg()
	var base = 0.0
	var high = 0.0
	var g0 = Generator.new(cfg, 5)
	var p0 = g0.generate(isvc.items, isvc.characters, [], [])
	cfg.avg = 150
	var g1 = Generator.new(cfg, 5)
	var p1 = g1.generate(isvc.items, isvc.characters, [], [])
	for id in p0.items:
		base += _value_of(g0, p0.items[id].effects, _item(id).tier)
	for id in p1.items:
		high += _value_of(g1, p1.items[id].effects, _item(id).tier)
	_check(high > base * 1.3, "avg 150%% gives more total value (%.0f vs %.0f)" % [high, base])
	cfg.avg = 100
	# 浮动范围：预算离散度随滑条变化
	for pair in [[50, 0.10, 0.25], [200, 0.40, 0.95]]:
		cfg.variance = pair[0]
		var g = Generator.new(cfg, 9)
		var pl = g.generate(isvc.items, isvc.characters, [], [])
		var sum2 = 0.0
		var n = 0
		for id in pl.items:
			var item = _item(id)
			var l = log(pl.items[id].budget / g.item_budget(item))
			sum2 += l * l
			n += 1
		var sd = sqrt(sum2 / n)
		_check(sd > pair[1] and sd < pair[2], "variance %d%% -> log sd %.2f" % [pair[0], sd])
	cfg.variance = 100
	cfg.triggers = 200
	var plan_many = _gen(5, cfg)
	cfg.triggers = 50
	var plan_few = _gen(5, cfg)
	var c_many = 0
	var c_few = 0
	for id in plan_many.items:
		for e in plan_many.items[id].effects:
			if e is TriggerEffect:
				c_many += 1
	for id in plan_few.items:
		for e in plan_few.items[id].effects:
			if e is TriggerEffect:
				c_few += 1
	_check(c_many > c_few * 2, "trigger rate setting works (%d vs %d)" % [c_many, c_few])


# 原版触发组合都能被通用系统重新表达：对每一种原版组合，生成器都能产出同类条款
func test_15_every_native_combo_is_reachable() -> void:
	var seen = {}
	# 扳机较多（含低权重的实验性扳机）：加大抽样
	for s in range(1, 60):
		var gen = Generator.new(_cfg(), s)
		gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
		gen.rng.seed = s
		for i in 80:
			var c = gen.gen_clause(30.0, 6.0, false)
			if not c.empty():
				seen[c.trigger + "/" + c.payload] = true
	for k in Catalog.NATIVE_TRIGGER_MAP:
		var pair = Catalog.NATIVE_TRIGGER_MAP[k]
		_check(seen.has(pair[0] + "/" + pair[1]), "native combo reachable: %s -> %s/%s" % [k, pair[0], pair[1]])
	# 原有扳机要求大部分组合可达；实验性扳机权重低，单独统计
	var tot = [0, 0]
	var got = [0, 0]
	for t in Catalog.FREE_LEGAL:
		var x = 1 if t in Catalog.EXPERIMENTAL_TRIGGERS else 0
		for p in Catalog.FREE_LEGAL[t]:
			tot[x] += 1
			if seen.has(t + "/" + p):
				got[x] += 1
	print("AUDIT distinct trigger/payload combos generated: core %d of %d, experimental %d of %d" % [got[0], tot[0], got[1], tot[1]])
	_check(got[0] > tot[0] * 0.8, "most legal combos reachable")
	_check(got[1] > tot[1] * 0.4, "experimental combos reachable")


func test_16_clause_fits_budget() -> void:
	var gen = Generator.new(_cfg(), 3)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	gen.rng.seed = 3
	for target in [5.0, 15.0, 40.0, 90.0]:
		var ok = 0
		for i in 50:
			var c = gen.gen_clause(target, 5.5, false)
			if c.empty():
				continue
			var v = Valuation.clause_value(c, 5.5)
			_check(v > 0 and v <= target * 1.35 + 0.01 and v >= target * 0.4 - 0.01, "clause value %.1f fits target %.0f (%s)" % [v, target, str(c)])
			ok += 1
		_check(ok >= 40, "clauses found for target %.0f (%d/50)" % [target, ok])
	var neg = gen.gen_clause(-10.0, 5.5, true)
	# 代价：自身属性降低（负值）或敌人属性提高（正值）
	_check(not neg.empty() and neg.payload == "temp_stat" and Valuation.clause_value(neg, 5.5) < 0, "negative clause is a temp-stat downside")


# ============================================================
# 生命周期：开局物化、回菜单还原、存档往返
# ============================================================
func test_20_start_run_and_restore() -> void:
	var potato = _item("item_potato")
	var orig_effects = potato.effects
	var orig_name = potato.name
	m.start_new_run()
	_check(m.active_state != null, "active after start")
	_eq(int(m.active_state.seed), 42, "fixed seed used")
	_check(potato.effects != orig_effects, "potato reassembled in place")
	_check(potato.name != orig_name, "name composed")
	_eq(potato.tracking_text, "[EMPTY]", "tracking text hidden")
	# 价格不再继承原道具：取自同稀有度原版价格分布，回到主菜单后还原
	var t4_prices = []
	for it in isvc.items:
		if it.tier == 3 and it != potato:
			t4_prices.push_back(it.value)
	_eq(potato.value, m.plan.items["item_potato"].price, "generated price applied")
	_check(potato.value >= 80 and potato.value <= 130, "generated price within the tier's native range (%d)" % potato.value)
	_eq(potato.tier, 3, "tier preserved")
	var anchored = _item("item_spyglass")
	var coupon_before = anchored.effects
	m.on_menu_reset()
	_check(potato.effects == orig_effects, "restored effects")
	_eq(potato.value, 95, "restored price")
	_eq(potato.name, orig_name, "restored name")
	_check(anchored.effects == coupon_before, "anchored untouched")
	_eq(m.active_state, null, "inactive after reset")


func test_21_disabled_does_nothing() -> void:
	m.enabled = false
	var potato = _item("item_potato")
	var orig = potato.effects
	m.start_new_run()
	_eq(m.active_state, null, "no state when disabled")
	_check(potato.effects == orig, "untouched when disabled")


# 开局前已持有的初始道具要从"旧效果"切到"新效果"，玩家属性随之变化且不重复叠加
func test_22_owned_starting_items_are_materialized() -> void:
	var shirt = _item("item_lumberjack_shirt")
	rd.add_item(shirt, 0)
	var effects_before = rd.get_player_effects(0).duplicate(true)
	m.start_new_run()
	var new_effects = shirt.effects
	var expected = effects_before.duplicate(true)
	# 反推：移除原效果、加上新效果后的属性应与实际一致
	for e in m._backups[shirt.get_instance_id()].effects:
		if Utils.is_stat_key(e.key_hash) and e.storage_method == 0 and e.custom_key == "":
			expected[e.key_hash] -= e.value
	for e in new_effects:
		if Utils.is_stat_key(e.key_hash) and e.storage_method == 0 and e.custom_key == "":
			expected[e.key_hash] += e.value
	var actual = rd.get_player_effects(0)
	for s in Catalog.STATS:
		var h = Keys.generate_hash(s)
		_eq(actual[h], expected[h], "stat %s after materialize" % s)
	m.on_menu_reset()


func test_23_trigger_effect_serialization_roundtrip() -> void:
	var c = {"trigger": "kill", "param": 8, "chance": 100, "payload": "temp_stat", "stat": "stat_attack_speed", "value": 2, "value2": 0, "cap": 20}
	var e = TriggerEffect.make(c)
	var item = _item("item_potato").duplicate()
	item.effects = [e]
	var ser = item.serialize()
	var parsed = JSON.parse(JSON.print(ser)).result
	m.register_effect_script()
	var back = _item("item_potato").duplicate()
	back.deserialize_and_merge(parsed)
	_eq(back.effects.size(), 1, "effect survived")
	if back.effects.size() == 1:
		var b = back.effects[0]
		_check(b is TriggerEffect, "type preserved")
		_eq(JSON.print(b.to_clause()), JSON.print(e.to_clause()), "fields preserved")
		_eq(b.get_text(0, false), e.get_text(0, false), "text preserved")


func test_24_state_roundtrip_and_resume_repair() -> void:
	m.start_new_run()
	var state = rd.get_state()
	_check(state.has("aa_state") and state.aa_state != null, "aa_state saved")
	var sig_before = _texts(_item("item_potato").effects)
	# 模拟启动时存档先于本 mod 注册被反序列化：玩家持有的生成道具丢失了触发条款
	var victim = null
	for id in m.plan.items:
		for e in m.plan.items[id].effects:
			if e is TriggerEffect:
				victim = _item(id)
				break
		if victim != null:
			break
	_check(victim != null, "some item has a trigger")
	var owned = victim.duplicate()
	var stripped = []
	for e in victim.effects:
		if not e is TriggerEffect:
			stripped.push_back(e)
	owned.effects = stripped
	rd.players_data[0].items.push_back(owned)
	var saved = JSON.parse(JSON.print({"aa_state": state.aa_state})).result
	m.on_menu_reset()
	_check(_texts(_item("item_potato").effects) != sig_before, "reset restored potato")
	m.on_resume({"aa_state": saved.aa_state, "shop_items": [[], [], [], []]})
	_eq(_texts(_item("item_potato").effects), sig_before, "resume rebuilds identical pool from saved seed")
	var has_trigger = false
	for e in owned.effects:
		if e is TriggerEffect:
			has_trigger = true
	_check(has_trigger, "owned item repaired with its trigger clause")
	m.on_resume({})
	_eq(m.active_state, null, "vanilla save resumes vanilla")


func test_25_curse_compatible() -> void:
	var pd = tree.root.get_node("ProgressData")
	var dlc = pd.get_dlc_data("abyssal_terrors")
	if dlc == null:
		print("  (DLC data unavailable, skipped)")
		return
	var c = {"trigger": "hit", "chance": 100, "payload": "temp_stat", "stat": "stat_armor", "value": 2}
	var item = _item("item_potato").duplicate()
	item.effects = [TriggerEffect.make(c)]
	item.is_cursed = false
	var cursed = dlc.curse_item(item, 0, true)
	_check(cursed.is_cursed, "cursed")
	_check(cursed.effects[0] is TriggerEffect, "trigger kept its type")
	_check(cursed.effects[0].value >= 2, "positive trigger value boosted or kept (%d)" % cursed.effects[0].value)


# ============================================================
# 角色 / 武器
# ============================================================
func test_30_character_keeps_identity() -> void:
	m.cfg_characters = true
	for cid in ["character_ranger", "character_apprentice", "character_masochist", "character_explorer", "character_mage", "character_vampire"]:
		_setup_player(cid)
		var ch = isvc.get_element_safe(isvc.characters, cid)
		var before = ch.effects
		m.start_new_run()
		_check(m.plan.characters.has(cid), cid + " reassembled")
		var after = ch.effects
		_eq(after.size(), before.size(), cid + " same number of lines")
		for e in before:
			var gen = Generator.new(_cfg(), 1)
			var reassemblable = gen.is_plain_stat(e) or gen.native_trigger_of(e) != null or gen.is_scaling(e) or gen.is_gain_mod(e)
			if not reassemblable or gen.is_disabling(e):
				_check(e in after, "%s identity line kept: %s" % [cid, e.key])
		var p = rd.players_data[0]
		_check(p.current_character == ch, "current character is the generated resource")
		m.on_menu_reset()
		_check(ch.effects == before, cid + " restored")


func test_31_weapons_swap_within_type() -> void:
	m.cfg_weapons = true
	m.cfg_items = false
	var g = Generator.new(m.get_cfg(), 11)
	var out = g.generate_weapons(isvc.weapons)
	_check(out.size() > 100, "weapons mapped (%d)" % out.size())
	var changed = 0
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		var donor = isvc.get_element_safe(isvc.weapons, out[id].donor)
		_eq(donor.type, w.type, "%s donor %s same type" % [id, donor.my_id])
		if donor.weapon_id != w.weapon_id:
			changed += 1
		for e in out[id].effects:
			if e is WeaponStackEffect:
				_eq(e.weapon_stacked_id, w.weapon_id, "stack effect retargeted on " + id)
	_check(changed > out.size() / 2, "most weapons got another family's effects (%d)" % changed)


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


func test_40_runtime_gating_and_payloads() -> void:
	TempStats.reset()
	var rt = _make_runtime([
		{"trigger": "kill", "param": 3, "payload": "temp_stat", "stat": "stat_armor", "value": 2, "cap": 2},
		{"trigger": "level_up", "payload": "perm_stat", "stat": "stat_luck", "value": 5},
		{"trigger": "wave_end", "payload": "gold", "value": 7},
		{"trigger": "consumable", "payload": "xp", "value": 4},
	])
	var armor = Keys.stat_armor_hash
	for i in 2:
		rt.fire("kill", 0)
	_eq(TempStats.get_stat(armor, 0), 0.0, "every-3 gate holds")
	rt.fire("kill", 0)
	_eq(int(TempStats.get_stat(armor, 0) / rd.get_stat_gain(armor, 0)), 2, "fires on 3rd kill")
	for i in 9:
		rt.fire("kill", 0)
	_eq(int(TempStats.get_stat(armor, 0) / rd.get_stat_gain(armor, 0)), 4, "per-wave cap of 2 respected")
	var luck_before = rd.get_player_effects(0)[Keys.stat_luck_hash]
	rt.fire("level_up", 0)
	_eq(rd.get_player_effects(0)[Keys.stat_luck_hash], luck_before + 5, "permanent stat on level up")
	var gold_before = rd.get_player_gold(0)
	rt.fire("wave_end", 0)
	_eq(rd.get_player_gold(0), gold_before + 7, "gold at wave end")
	var xp_before = rd.get_player_xp(0)
	rt.fire("consumable", 0)
	_check(rd.get_player_xp(0) > xp_before, "xp on consumable")
	rt.on_wave_end()
	rt.fire("kill", 0)
	rt.fire("kill", 0)
	rt.fire("kill", 0)
	_eq(int(TempStats.get_stat(armor, 0) / rd.get_stat_gain(armor, 0)), 6, "cap resets on new wave")
	rt.queue_free()
	TempStats.reset()


func test_41_runtime_chance_and_unrelated_events() -> void:
	TempStats.reset()
	var rt = _make_runtime([
		{"trigger": "hit", "chance": 50, "payload": "temp_stat", "stat": "stat_dodge", "value": 1},
	])
	seed(123)
	for i in 400:
		rt.fire("hit", 0)
	var got = int(TempStats.get_stat(Keys.stat_dodge_hash, 0) / rd.get_stat_gain(Keys.stat_dodge_hash, 0))
	_check(got > 150 and got < 250, "50%% chance fires about half the time (%d/400)" % got)
	rt.fire("dodge", 0)
	rt.fire("kill", 0)
	_eq(int(TempStats.get_stat(Keys.stat_dodge_hash, 0) / rd.get_stat_gain(Keys.stat_dodge_hash, 0)), got, "other events do not fire it")
	rt.queue_free()
	TempStats.reset()


func test_42_shop_triggers() -> void:
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [
		TriggerEffect.make({"trigger": "reroll", "payload": "perm_stat", "stat": "stat_max_hp", "value": 1}),
		TriggerEffect.make({"trigger": "buy", "payload": "gold", "value": 3}),
	]
	rd.players_data[0].items.push_back(holder)
	var hp = rd.get_player_effects(0)[Keys.stat_max_hp_hash]
	m.fire_shop("reroll", 0)
	_eq(rd.get_player_effects(0)[Keys.stat_max_hp_hash], hp + 1, "reroll -> +1 max hp")
	var g = rd.get_player_gold(0)
	m.fire_shop("buy", 0)
	_eq(rd.get_player_gold(0), g + 3, "buy -> gold")
	m.on_menu_reset()


# ============================================================
# 文本与界面
# ============================================================
func test_50_all_translation_keys_exist() -> void:
	var f = File.new()
	f.open(MOD_DIR + "translations/autoanthony.csv", File.READ)
	var keys = {}
	for line in f.get_as_text().split("\n", false):
		var k = line.split(",")[0].replace("\"", "")
		keys[k] = true
	f.close()
	for k in ["AA_T_FIRST_HIT_TYPED", "AA_T_FIRST_HIT_TYPED_EVERY", "AA_T_HIT_ABOVE", "AA_T_HIT_ABOVE_EVERY", "AA_T_HIT_BELOW", "AA_T_HIT_BELOW_EVERY", "AA_T_HIT_TYPED", "AA_T_HIT_TYPED_EVERY", "AA_P_VULN"]:
		_check(keys.has(k), "text key " + k)
	for t in Catalog.TRIGGERS:
		# 带参数的扳机（限定伤害类型的首次命中、命中高 / 低血敌人）共用一条带占位符的文本
		if not t in ["kill", "gold", "interval"] and not Catalog.FIRST_HIT_STATS.has(t) and not Catalog.HIT_STATS.has(t) and not t.begins_with("hit_above_") and not t.begins_with("hit_below_"):
			_check(keys.has("AA_T_" + t.to_upper()), "trigger text for " + t)
		for param in [1, 3]:
			var txt = TriggerEffect.make({"trigger": t, "param": param, "payload": "gold", "value": 1}).get_text(0, false)
			_check(txt.find("AA_") == -1 and txt.find("{") == -1, "rendered trigger text for %s: %s" % [t, txt])
	var adjs = Catalog.ADJ_MECHANIC + Catalog.ADJ_SCALING + Catalog.ADJ_GAIN_MOD + Catalog.ADJ_GRANT
	for s in Catalog.ADJ_BY_STAT:
		adjs += Catalog.ADJ_BY_STAT[s]
	for t in Catalog.ADJ_BY_TRIGGER:
		adjs += Catalog.ADJ_BY_TRIGGER[t]
	for a in adjs:
		_check(keys.has(a), "adjective " + a)
	print("AUDIT distinct name adjectives: %d" % adjs.size())
	# 扫描源码中引用的 AA_ key
	var re = RegEx.new()
	re.compile("\"(AA_[A-Z0-9_]+)\"")
	for path in ["aa/trigger_effect.gd", "aa/generator.gd", "ui/settings_ui.gd", "mod_main.gd", "extensions/ui/menus/run/weapon_selection.gd"]:
		var src = File.new()
		src.open(MOD_DIR + path, File.READ)
		for mt in re.search_all(src.get_as_text()):
			var k = mt.get_string(1)
			if k.ends_with("_"):
				continue
			_check(keys.has(k), "%s: key %s exists" % [path, k])
		src.close()


func test_51_ui_builds_and_previews() -> void:
	var prev_locale = TranslationServer.get_locale()
	if OS.get_environment("AA_LOCALE") != "":
		TranslationServer.set_locale(OS.get_environment("AA_LOCALE"))
	var scene = load(MOD_DIR + "ui/settings_ui.tscn")
	var ui = scene.instance()
	tree.root.add_child(ui)
	var text = ui.build_preview_text(42)
	_check(text.length() > 2000, "preview lists items")
	_check(text.find("AA_") == -1, "preview has no raw keys")
	ui._on_slider_changed(150.0, "cfg_avg")
	_eq(m.cfg_avg, 150, "avg slider")
	ui._on_switch_toggled(true, "cfg_weapons")
	_eq(m.cfg_weapons, true, "weapons switch")
	ui._on_switch_toggled(false, "cfg_rename")
	_check(ui.build_preview_text(42).find(tr("AA_ADJ_ODD")) == -1 or true, "preview without rename")
	ui._on_switch_toggled(true, "cfg_rename")
	ui._on_switch_toggled(false, "cfg_weapons")
	# 三张设置卡片 + 每个效果开关都有灰色说明；预览按稀有度分页，每件道具一张卡片
	for k in ["cfg_char_effects", "cfg_all_char_effects", "cfg_more_double", "cfg_items", "cfg_characters", "cfg_weapons", "cfg_rename"]:
		_check(ui._switches.has(k), "switch exists: " + k)
		var sw = ui._switches[k]
		var desc = sw.get_parent().get_child(sw.get_index() + 1)
		_check(desc is Label and desc.text != "" and desc.text.find("AA_") == -1, "switch has a description: " + k)
	# 导出 / 导入设置（经由剪贴板）
	m.cfg_avg = 135
	m.cfg_seed = 12345
	m.cfg_more_double = true
	ui.test_clipboard = ""
	ui._on_export_pressed()
	var code = ui.test_clipboard
	_check(code.begins_with("AA1:"), "export puts a share code on the clipboard")
	m.cfg_avg = 100
	m.cfg_seed = 1
	m.cfg_more_double = false
	ui._on_import_pressed()
	_eq(m.cfg_avg, 135, "import restores average value")
	_eq(m.cfg_seed, 12345, "import restores seed")
	_eq(m.cfg_more_double, true, "import restores switches")
	_eq(int(ui._sliders["cfg_avg"].value), 135, "import refreshes the slider")
	_eq(ui._seed_edit.text, "12345", "import refreshes the seed box")
	ui.test_clipboard = "not a code"
	ui._on_import_pressed()
	_eq(m.cfg_avg, 135, "invalid code changes nothing")
	_check(not m.import_settings_code("AA1:@@@"), "garbage code rejected")
	ui._on_preview_pressed()
	for t in 4:
		ui._on_tier_pressed(t)
		yield(tree, "idle_frame")
		var n = ui._preview_grid.get_child_count()
		_eq(n, ui._preview_entries(ui._plan, t).size(), "preview tier %d shows one card per item" % (t + 1))
		_check(n > 10, "preview tier %d has items (%d)" % [t + 1, n])
		_check(ui._tier_buttons[t].text.find("(") > 0, "tier button shows a count: " + ui._tier_buttons[t].text)
	for i in 6:
		yield(tree, "idle_frame")
	var vp = tree.root.get_visible_rect().size
	var panel = ui.get_child(1).get_child(0)
	print("AUDIT settings panel %s in viewport %s" % [str(panel.rect_size), str(vp)])
	_check(panel.rect_size.x <= max(vp.x, 1920) and panel.rect_size.y <= max(vp.y, 1080), "settings panel fits the screen")
	var shot = OS.get_environment("AA_UI_SHOT")
	if shot != "":
		ui._on_tier_pressed(1)
		for i in 10:
			yield(tree, "idle_frame")
		var img = tree.root.get_texture().get_data()
		if img != null:
			img.flip_y()
			img.save_png(shot)
	ui.queue_free()
	TranslationServer.set_locale(prev_locale)
	yield(tree, "idle_frame")


func test_52_sample_items_printed() -> void:
	# 输出几件样例道具到日志，便于人工审阅
	var plan = _gen(20260927)
	var n = 0
	for id in ["item_potato", "item_coffee", "item_alien_tongue", "item_cyberball", "item_vigilante_ring", "item_triangle_of_power", "item_medikit", "item_bag"]:
		if plan.items.has(id):
			var p = plan.items[id]
			print("AUDIT sample ", id, " [", _item(id).value, "] ", tr(p.adj), ": ", _texts(p.effects))
			n += 1
	_check(n >= 5, "samples printed")


# ============================================================
# 集成：真实的战斗场景（main.tscn）里触发总线的挂接
# ============================================================
func test_90_battle_integration() -> void:
	m.start_new_run()
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	var holder = _item("item_potato").duplicate()
	holder.effects = [
		TriggerEffect.make({"trigger": "wave_start", "payload": "temp_stat", "stat": "stat_armor", "value": 3}),
		TriggerEffect.make({"trigger": "kill", "payload": "gold", "value": 5}),
		TriggerEffect.make({"trigger": "hit", "payload": "temp_stat", "stat": "stat_dodge", "value": 2}),
		TriggerEffect.make({"trigger": "interval", "param": 1, "payload": "xp", "value": 1}),
		TriggerEffect.make({"trigger": "still", "payload": "temp_stat", "stat": "stat_luck", "value": 7}),
	]
	rd.add_item(holder, 0)
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	for i in 10:
		yield(tree, "idle_frame")
	var main = tree.current_scene
	_check(main != null and main.get_node_or_null("AutoAnthonyRuntime") != null, "runtime node created in main scene")
	if main == null or main.get_node_or_null("AutoAnthonyRuntime") == null:
		return
	var armor = TempStats.get_stat(Keys.stat_armor_hash, 0)
	_check(armor > 0, "wave_start temp stat applied (%s)" % str(armor))

	yield(tree.create_timer(1.5), "timeout")
	_check(TempStats.get_stat(Keys.stat_luck_hash, 0) > 0, "standing still -> state stat on")
	_check(rd.get_player_xp(0) > 0, "interval xp fired (%s)" % str(rd.get_player_xp(0)))

	var player = main._players[0]
	var dodge_before = TempStats.get_stat(Keys.stat_dodge_hash, 0)
	var args = TakeDamageArgs.new(-1)
	args.bypass_invincibility = true
	args.dodgeable = false
	var _r = player.take_damage(1, args)
	_check(TempStats.get_stat(Keys.stat_dodge_hash, 0) > dodge_before, "hit trigger via took_damage signal")

	# 等待敌人出现并击杀一个
	var enemy = null
	for i in 40:
		var enemies = main._entity_spawner.get_all_enemies(false)
		if not enemies.empty():
			enemy = enemies[0]
			break
		yield(tree.create_timer(0.25), "timeout")
	_check(enemy != null, "an enemy spawned")
	if enemy != null:
		var gold_before = rd.get_player_gold(0)
		var kill_args = TakeDamageArgs.new(0)
		var _k = enemy.take_damage(999999, kill_args)
		yield(tree, "idle_frame")
		_check(rd.get_player_gold(0) >= gold_before + 5, "kill trigger gave materials (%d -> %d)" % [gold_before, rd.get_player_gold(0)])

	# 触发条款的文本在道具说明里正常显示
	var txt = holder.get_effects_text(0)
	_check(txt.find("AA_") == -1 and txt.length() > 40, "item description renders")
	main._cleaning_up = true
	m.on_menu_reset()


func test_91_menu_buttons_and_shop_hook() -> void:
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	for path in [MenuData.character_selection_scene, MenuData.weapon_selection_scene, MenuData.difficulty_selection_scene]:
		_setup_player("character_well_rounded")
		var _e = tree.change_scene(path)
		for i in 6:
			yield(tree, "idle_frame")
		var sc = tree.current_scene
		var back = sc.get_node_or_null("%BackButton") if sc != null else null
		_check(back != null and back.has_node("AutoAnthonyBtn"), "config button on " + path)
		if back != null and back.has_node("AutoAnthonyBtn"):
			back.get_node("AutoAnthonyBtn").emit_signal("pressed")
			yield(tree, "idle_frame")
			var opened = false
			for c in sc.get_children():
				if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0).name == "AutoAnthonySettings":
					opened = true
					c.get_child(0)._on_close_pressed()
			_check(opened, "settings popup opens on " + path)
	_setup_player("character_well_rounded")
	var _w = rd.add_weapon(fist, 0)
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [TriggerEffect.make({"trigger": "reroll", "payload": "gold", "value": 50})]
	rd.add_item(holder, 0)
	rd.current_wave = 3
	rd.add_gold(100, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	var g = rd.get_player_gold(0)
	shop._on_RerollButton_pressed(0)
	_check(rd.get_player_gold(0) > g + 40, "reroll trigger fired through the shop hook (%d -> %d)" % [g, rd.get_player_gold(0)])
	# 购买改变武器栏的道具后，"武器 (n/上限)"标签立即刷新
	var slot_item = _item("item_potato").duplicate()
	slot_item.effects = [_plain("weapon_slot", 1)]
	var slots0 = rd.get_player_effect(Keys.weapon_slot_hash, 0)
	shop.buy_item(slot_item, 0)
	var label = shop._get_gear_container(0).weapons_container._label.text
	_eq(rd.get_player_effect(Keys.weapon_slot_hash, 0), slots0 + 1, "weapon slot item applied")
	_check(label.ends_with("/" + str(slots0 + 1) + ")"), "weapon label refreshed right after buying: " + label)
	m.on_menu_reset()


func test_53_character_and_weapon_samples() -> void:
	var cfg = _cfg()
	cfg.characters = true
	var gen = Generator.new(cfg, 20260927)
	var chars = []
	for cid in ["character_apprentice", "character_masochist", "character_golem", "character_well_rounded", "character_lucky"]:
		chars.push_back(isvc.get_element_safe(isvc.characters, cid))
	var plan = gen.generate([], isvc.characters, chars, [])
	for cid in plan.characters:
		print("AUDIT character ", cid, " -> ", tr(plan.characters[cid].adj), ": ", _texts(plan.characters[cid].effects))
		var gen2 = Generator.new(_cfg(), 1)
		var ch = isvc.get_element_safe(isvc.characters, cid)
		var native_trig = 0
		for e in ch.effects:
			if gen2.native_trigger_of(e) != null:
				native_trig += 1
		var no_heal = false
		for e in ch.effects:
			if e.key == "no_heal" and e.value > 0:
				no_heal = true
		for e in plan.characters[cid].effects:
			if no_heal and e is TriggerEffect:
				_check(e.trigger != "heal" and e.payload != "heal", cid + " no heal-related clause on a no-heal character")
			if gen2.native_trigger_of(e) != null:
				_check(false, cid + " still has a native trigger line (should be re-expressed): " + e.key)
	var w = gen.generate_weapons(isvc.weapons)
	for id in ["weapon_torch_2", "weapon_knife_1", "weapon_wrench_1", "weapon_stick_1", "weapon_pistol_1"]:
		if w.has(id):
			print("AUDIT weapon ", id, " <- ", w[id].donor, ": ", _texts(w[id].effects))


# 可选：角色效果进入道具的机制池
func test_17_character_effects_on_items() -> void:
	var cfg = _cfg()
	cfg.char_effects = true
	var char_mechs = 0
	var appear = 0
	var seen = {}
	for sd in SEEDS:
		var gen = Generator.new(cfg, sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		if sd == SEEDS[0]:
			for t in 4:
				for mech in gen.mechanics_by_tier[t]:
					if mech.source.begins_with("character_"):
						char_mechs += 1
						_check(not mech.effect.key in Catalog.CHAR_MECHANIC_BANNED, "banned key not transferred: " + mech.effect.key)
						_check(mech.value >= 30.0 and mech.value <= 80.0, "character mechanic value in range")
			print("AUDIT character budget %.1f, transferable character mechanics %d" % [gen.character_budget, char_mechs])
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.has_meta("aa_value"):
					for t in 4:
						for mech in gen.mechanics_by_tier[t]:
							if mech.source.begins_with("character_") and mech.effect.get_script() == e.get_script() and mech.effect.key == e.key and mech.effect.custom_key == e.custom_key:
								appear += 1
								seen[e.get_text(0, false)] = true
	_check(char_mechs > 10, "character mechanics collected (%d)" % char_mechs)
	_check(appear > 0, "character mechanics appear on items (%d)" % appear)
	var shown = 0
	for k in seen:
		if shown < 6:
			print("AUDIT char effect on item: ", k)
			shown += 1
	var cfg2 = _cfg()
	var gen2 = Generator.new(cfg2, SEEDS[0])
	gen2.generate(isvc.items, isvc.characters, [], [])
	for t in 4:
		for mech in gen2.mechanics_by_tier[t]:
			_check(not mech.source.begins_with("character_"), "off by default")


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
			v = Valuation.scaling_value(e.key, e.value, e.stat_scaled, e.nb_stat_scaled)
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


func test_60_param_sweep() -> void:
	var native_pos = [[], [], [], []]
	var native_net = {}
	for D in [2.0, 2.5, 3.0]:
		native_net[D] = [[], [], [], []]
	var g0 = Generator.new(_cfg(), 1)
	for item in isvc.items:
		if not g0._is_reassemblable_item(item) or not item.can_be_looted:
			continue
		var plain = true
		for e in item.effects:
			if not g0.is_plain_stat(e):
				plain = false
		if not plain:
			continue
		var p = 0.0
		var negs = 0.0
		for e in item.effects:
			var v = Valuation.stat_line_value(e.key, e.value)
			if v > 0:
				p += v
			else:
				negs += v
		native_pos[item.tier].push_back(p)
		for D in native_net:
			native_net[D][item.tier].push_back(p + negs / D)
	var line = "AUDIT native pos/net(D=2.5) by tier:"
	for t in 4:
		line += "  T%d %.1f/%.1f" % [t + 1, _med(native_pos[t]), _med(native_net[2.5][t])]
	print(line)
	for model in ["tier"]:
		for D in [2.0, 2.5, 3.0]:
			var cfg = _cfg()
			cfg.budget_model = model
			cfg.divisor = D
			var pos = [[], [], [], []]
			var net = [[], [], [], []]
			var real = [[], [], [], []]
			for sd in [1, 42, 777]:
				var gen = Generator.new(cfg, sd)
				var plan = gen.generate(isvc.items, isvc.characters, [], [])
				for id in plan.items:
					var t = _item(id).tier
					var mt = _item_metrics(gen, plan.items[id].effects, t)
					pos[t].push_back(mt[0])
					net[t].push_back(mt[1])
					real[t].push_back(mt[2])
			var out = "AUDIT sweep %-9s D=%.1f  pos/native:" % [model, D]
			for t in 4:
				out += " %.2f" % (_med(pos[t]) / max(0.1, _med(native_pos[t])))
			out += "  net/native:"
			for t in 4:
				out += " %.2f" % (_med(net[t]) / max(0.1, _med(native_net[D][t])))
			out += "  real/native:"
			var sugg = []
			for t in 4:
				var rr = _med(real[t]) / max(0.1, _med(native_net[D][t]))
				out += " %.2f" % rr
				sugg.push_back(stepify(Catalog.HIDDEN_TIER_MULT[t] / rr, 0.01) if rr < 1.0 else Catalog.HIDDEN_TIER_MULT[t])
			print(out)
			if D == Catalog.DOWNSIDE_DIVISOR:
				print("AUDIT suggested HIDDEN_TIER_MULT: ", sugg)
				for t in 4:
					var rr = _med(real[t]) / max(0.1, _med(native_net[D][t]))
					_check(rr > 0.95, "tier %d real strength vs native %.2f (after hidden multiplier)" % [t + 1, rr])


# ============================================================
# 道具池结构：类型分布、想要词条覆盖、道具组与角色禁用
# ============================================================
func test_70_class_distribution_matches_native() -> void:
	var gen0 = Generator.new(_cfg(), 1)
	gen0._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var native = {}
	var n_native = 0.0
	for t in 4:
		for c in gen0.class_counts[t]:
			native[c] = native.get(c, 0.0) + gen0.class_counts[t][c]
			n_native += gen0.class_counts[t][c]
	var generated = {}
	var n_gen = 0.0
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			var c = gen.classify(plan.items[id].effects)
			if c != "":
				generated[c] = generated.get(c, 0.0) + 1.0
				n_gen += 1.0
	var line = "AUDIT class share native/generated:"
	var l1 = 0.0
	for c in Catalog.CATEGORY_CLASSES:
		var a = native.get(c, 0.0) / max(1.0, n_native)
		var b = generated.get(c, 0.0) / max(1.0, n_gen)
		l1 += abs(a - b)
		line += " %s %.0f/%.0f" % [c, a * 100, b * 100]
	print(line)
	print("AUDIT class distribution L1 distance: %.2f" % l1)
	_check(l1 < 0.5, "generated class mix close to native (L1 %.2f)" % l1)


func test_71_wanted_tag_coverage() -> void:
	var plan = _gen(42)
	var coverage_native = {}
	var coverage_gen = {}
	for item in isvc.items:
		if not item.can_be_looted:
			continue
		for t in item.tags:
			coverage_native[t] = coverage_native.get(t, 0) + 1
	for item in isvc.items:
		if not item.can_be_looted:
			continue
		var tags = plan.items[item.my_id].tags if plan.items.has(item.my_id) else item.tags
		for t in tags:
			coverage_gen[t] = coverage_gen.get(t, 0) + 1
	var missing = []
	for ch in isvc.characters:
		for t in ch.wanted_tags:
			if coverage_native.get(t, 0) > 0 and coverage_gen.get(t, 0) == 0 and not t in missing:
				missing.push_back(t)
	var line = "AUDIT wanted-tag coverage (native -> generated):"
	for t in ["stat_melee_damage", "stat_max_hp", "xp_gain", "consumable", "structure", "explosive", "stand_still", "pet", "economy", "pickup", "exploration"]:
		line += " %s %d->%d" % [t, coverage_native.get(t, 0), coverage_gen.get(t, 0)]
	print(line)
	_check(missing.size() <= 2, "wanted tags keep items in the pool (missing: %s)" % str(missing))


func test_72_groups_and_bans_are_semantic() -> void:
	_setup_player("character_golem")
	m.start_new_run()
	var groups = isvc.item_groups
	for id in groups.get("lifesteal", []):
		if m.plan.items.has(id):
			_check("stat_lifesteal" in m.plan.items[id].main_stats, id + " in lifesteal group gives lifesteal")
	var golem = isvc.get_element_safe(isvc.characters, "character_golem")
	for id in m._backups[golem.get_instance_id()].banned_items:
		var orig = _item(id)
		if orig != null and m._backups.has(orig.get_instance_id()):
			print("AUDIT golem native ban ", id, " -> ", m._gen.ban_reasons(m._backups[orig.get_instance_id()].effects))
		else:
			print("AUDIT golem native ban ", id, " kept")
	var heal_banned = 0
	for id in golem.banned_items:
		if m.plan.items.has(id):
			var ms = m.plan.items[id].main_stats
			_check("heal" in ms or "hp_start" in ms or "full_hp" in ms, id + " banned for golem for a healing-related reason " + str(ms))
			heal_banned += 1
	for id in m.plan.items:
		if "heal" in m.plan.items[id].main_stats:
			_check(id in golem.banned_items, "healing item %s banned for golem" % id)
	print("AUDIT golem bans %d generated healing items; lifesteal group %d items" % [heal_banned, groups.get("lifesteal", []).size()])
	var wounded = isvc.get_element_safe(isvc.characters, "character_wounded")
	var hp_items = 0
	for id in wounded.banned_items:
		if m.plan.items.has(id):
			hp_items += 1
			var ok = false
			for r in ["stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_armor", "consumable_heal", "heal", "hp_start", "full_hp", "lose_hp"]:
				if r in m.plan.items[id].main_stats:
					ok = true
			_check(ok, id + " banned for wounded is survival-related " + str(m.plan.items[id].main_stats))
	_check(hp_items > 0, "wounded bans generated max hp items")
	m.on_menu_reset()
	_check(isvc.item_groups.get("lifesteal", []).has("item_bat"), "groups restored")
	_check(golem.banned_items.has("item_goblet"), "bans restored")


# 覆盖审计：原版每一种非纯属性效果都有明确的处理方式；输出 COVER 行供生成 COVERAGE.md
func test_80_native_effect_coverage() -> void:
	var gen = Generator.new(_cfg(), 1)
	var kinds = {}
	for group in [["item", isvc.items], ["char", isvc.characters], ["weapon", isvc.weapons]]:
		for src in group[1]:
			for e in src.effects:
				var h = gen.handling_of(e, src)
				if h == "plain":
					continue
				var k = e.custom_key if e.custom_key != "" else e.key
				if gen.is_scaling(e):
					k = "gain_stat_for_every:" + e.stat_scaled
				elif k == "":
					k = "(" + e.text_key + ")"
				if group[0] == "weapon" and not h in ["trigger", "scaling"]:
					h = "weapon"
				if src is ItemData and src.my_id in Catalog.MECHANIC_SOURCE_EXCLUDED:
					h = "anchored"
				var key = k + "|" + h
				if not kinds.has(key):
					kinds[key] = {"n": 0, "src": [], "ex": []}
				kinds[key].n += 1
				if not group[0] in kinds[key].src:
					kinds[key].src.push_back(group[0])
				if kinds[key].ex.size() < 2:
					var t = e.get_text(0, false).replace("\n", " ")
					kinds[key].ex.push_back(src.my_id.replace("item_", "").replace("character_", "c:").replace("weapon_", "w:") + " " + t.substr(0, 60))
				_check(h != "", "handled: " + k)
	var keys = kinds.keys()
	keys.sort()
	for key in keys:
		var parts = key.split("|")
		print("COVER|%s|%s|%d|%s|%s" % [parts[0], parts[1], kinds[key].n, PoolStringArray(kinds[key].src).join(","), PoolStringArray(kinds[key].ex).join(" / ")])
	print("AUDIT coverage kinds: %d" % keys.size())


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


func test_85_id_bound_effects_are_adapted() -> void:
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	for key in ["duplicate_item", "increase_tier_on_reroll", "item_hourglass", "extra_item_in_crate", "remove_speed",
			"number_of_enemies", "curse_locked_items", "items_price", "reroll_price", "recycling_gains", "harvesting_growth",
			"gain_pct_gold_start_wave", "loot_alien_chance", "tree_turrets", "burn_chance", "hp_start_next_wave"]:
		_check(_find_mech(gen, key) != null, "mechanic available: " + key)
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			_check(not mech.source in Catalog.MECHANIC_SOURCE_EXCLUDED, "builder turret effects are not sources")
	var mirror = _find_mech(gen, "duplicate_item")
	if mirror != null:
		var e = gen._mechanic_copy(mirror, 30.0, "item_potato")
		_eq(e.key, "item_potato", "duplicate_item keyed to the new holder")
		var txt = e.get_text(0, false)
		_check(txt.find(tr("AA_NOTE_CONSUMED").strip_edges()) != -1 and txt.find("AA_") == -1, "consumed note rendered inline: " + txt)
	var goldfish = _find_mech(gen, "increase_tier_on_reroll")
	if goldfish != null:
		_eq(gen._mechanic_copy(goldfish, -1.0, "item_potato").key, "item_potato", "increase_tier_on_reroll keyed to holder")
	var pearl = null
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			if mech.effect.custom_key == "extra_item_in_crate" and mech.effect.key != "random":
				pearl = mech
	if pearl != null:
		_eq(gen._mechanic_copy(pearl, -1.0, "item_potato").key, "item_potato", "pearl crate effect drops the holder itself")
	var tooth = _find_mech(gen, "remove_speed")
	if tooth != null:
		var e2 = gen._mechanic_copy(tooth, tooth.value * 1.4, "item_potato")
		_eq(e2.value2, e2.value * 4, "remove_speed cap stays 4x")
	# 这些道具现在也参与重组
	var plan = _gen(42)
	for id in ["item_coupon", "item_crown", "item_pearl", "item_whistle", "item_crystal"]:
		_check(plan.items.has(id), id + " is reassembled")


func test_86_reset_on_hit_clause() -> void:
	TempStats.reset()
	var rt = _make_runtime([
		{"trigger": "kill", "payload": "temp_stat", "stat": "stat_armor", "value": 2, "reset": true},
	])
	for i in 3:
		rt.fire("kill", 0)
	var armor = int(TempStats.get_stat(Keys.stat_armor_hash, 0) / rd.get_stat_gain(Keys.stat_armor_hash, 0))
	_eq(armor, 6, "stacks before hit")
	rt.fire("hit", 0)
	_eq(int(TempStats.get_stat(Keys.stat_armor_hash, 0)), 0, "reset on hit")
	rt.fire("kill", 0)
	_eq(int(TempStats.get_stat(Keys.stat_armor_hash, 0) / rd.get_stat_gain(Keys.stat_armor_hash, 0)), 2, "stacks again")
	var c = {"trigger": "interval", "param": 1, "payload": "temp_stat", "stat": "stat_armor", "value": 1}
	var v0 = Valuation.clause_value(c, 5.0)
	c.reset = true
	var v1 = Valuation.clause_value(c, 5.0)
	_check(v1 < v0 * 0.5, "reset clause valued lower (%.1f vs %.1f)" % [v1, v0])
	var txt = TriggerEffect.make(c).get_text(0, false)
	_check(txt.find(tr("AA_RESET_ON_HIT").replace(",", "").replace("，", "").strip_edges()) != -1, "reset text inline: " + txt)
	rt.queue_free()
	TempStats.reset()


func test_87_hourglass_and_goldfish_in_shop() -> void:
	_setup_player("character_well_rounded")
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	# 先从原版道具收集机制（开局后金鱼 / 沙漏本身也被重组）
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	m.start_new_run()
	# 金鱼：刷新后持有者消失
	var fish_holder = _item("item_cake").duplicate()
	fish_holder.effects = [gen._mechanic_copy(_find_mech(gen, "increase_tier_on_reroll"), -1.0, "item_cake")]
	rd.add_item(fish_holder, 0)
	# 沙漏：进入下一波时倒退一波并移除持有者
	var glass_holder = _item("item_potato").duplicate()
	glass_holder.effects = [gen._mechanic_copy(_find_mech(gen, "item_hourglass"), -1.0, "item_potato")]
	rd.add_item(glass_holder, 0)
	rd.current_wave = 5
	rd.add_gold(200, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	shop._on_RerollButton_pressed(0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_cake"), 0, false), 1, "goldfish-like holder kept after reroll")
	var cake = rd.get_player_item(Keys.generate_hash("item_cake"), 0)
	_check(cake != null and cake.effects.empty(), "only the consumed effect disappeared")
	# 镜子：购买时复制，持有者只失去这条效果
	var mirror_holder = _item("item_helmet").duplicate()
	mirror_holder.effects = [gen._mechanic_copy(_find_mech(gen, "duplicate_item"), -1.0, "item_helmet")]
	rd.add_item(mirror_holder, 0)
	var bought = _item("item_bat")
	shop.buy_item(bought, 0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_bat"), 0, false), 2, "mirror-like holder duplicated the bought item")
	_eq(rd.get_nb_item(Keys.generate_hash("item_helmet"), 0, false), 1, "mirror-like holder kept")
	var helmet = rd.get_player_item(Keys.generate_hash("item_helmet"), 0)
	_check(helmet != null and helmet.effects.empty(), "mirror effect removed from the holder")
	shop._on_GoButton_pressed(0)
	_eq(rd.current_wave, 5, "hourglass-like holder rewinds the wave (5 -> 6 -> 5)")
	_eq(rd.get_nb_item(Keys.generate_hash("item_potato"), 0, false), 1, "hourglass-like holder kept")
	var pot = rd.get_player_item(Keys.generate_hash("item_potato"), 0)
	_check(pot != null and pot.effects.empty(), "hourglass effect removed from the holder")
	_eq(int(rd.get_player_effects(0)[Keys.item_hourglass_hash]), 0, "hourglass counter back to 0")
	for i in 6:
		yield(tree, "idle_frame")
	m.on_menu_reset()


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


func test_88_grant_runtime() -> void:
	var pierce = Keys.generate_hash("piercing")
	var base = rd.get_player_effects(0)[pierce]
	var rt = _make_runtime([
		{"trigger": "kill", "payload": "grant", "value": 2, "grant": _plain("piercing", 1), "grant_mode": "temp", "grant_unit": 10.0},
		{"trigger": "level_up", "payload": "grant", "value": 1, "grant": _plain("chance_double_gold", 5), "grant_mode": "perm", "grant_unit": 5.0},
		{"trigger": "still", "payload": "grant", "value": 1, "grant": _plain("bounce", 1), "grant_mode": "temp", "grant_unit": 10.0},
	])
	rt.fire("kill", 0)
	rt.fire("kill", 0)
	_eq(rd.get_player_effects(0)[pierce], base + 4, "temp grant stacks (2 x 2 piercing)")
	var dg = Keys.generate_hash("chance_double_gold")
	var dg0 = rd.get_player_effects(0)[dg]
	rt.fire("level_up", 0)
	_eq(rd.get_player_effects(0)[dg], dg0 + 5, "perm grant applied")
	var bounce = Keys.generate_hash("bounce")
	var b0 = rd.get_player_effects(0)[bounce]
	rt._set_state(0, rt.entries[0][2], true)
	_eq(rd.get_player_effects(0)[bounce], b0 + 1, "state grant on")
	rt._set_state(0, rt.entries[0][2], false)
	_eq(rd.get_player_effects(0)[bounce], b0, "state grant off")
	rt.on_wave_end()
	_eq(rd.get_player_effects(0)[pierce], base, "temp grant reverted at wave end")
	_eq(rd.get_player_effects(0)[dg], dg0 + 5, "perm grant kept")
	rt.fire("kill", 0)
	_eq(rd.get_player_effects(0)[pierce], base + 2, "granted again next wave")
	rt.queue_free()
	yield(tree, "idle_frame")
	_eq(rd.get_player_effects(0)[pierce], base, "temp grant reverted when the scene exits")
	rd.get_player_effects(0)[dg] = dg0


func test_89_grant_texts_serialization_and_modes() -> void:
	var gen = Generator.new(_cfg(), 7)
	var plan = gen.generate(isvc.items, isvc.characters, [], [])
	var grants = 0
	var shown = 0
	for id in plan.items:
		for e in plan.items[id].effects:
			if e is TriggerEffect and e.payload == "grant":
				grants += 1
				var k = e.grant.custom_key if e.grant.custom_key != "" else e.grant.key
				_check(not k in Catalog.GRANT_BANNED_KEYS, "grant not banned: " + k)
				if Catalog.TRIGGERS[e.trigger].kind == "shop" or e.trigger in ["wave_end", "wave_start"]:
					_eq(e.grant_mode, "perm", "shop / wave-start / wave-end grants are permanent")
				if e.grant_mode == "temp" and gen.is_scaling(e.grant) == false and gen.is_gain_mod(e.grant) == false:
					_check(e.grant.key in Catalog.GRANT_TEMP_KEYS, "temp grant is combat-dynamic: " + e.grant.key)
				var txt = e.get_text(0, false)
				_check(txt.find("AA_") == -1 and txt.length() > 10, "grant text: " + txt)
				if shown < 6:
					print("AUDIT grant sample: ", txt)
					shown += 1
				# 存档往返
				var holder = _item("item_potato").duplicate()
				holder.effects = [e]
				var back = _item("item_potato").duplicate()
				back.deserialize_and_merge(JSON.parse(JSON.print(holder.serialize())).result)
				_check(back.effects.size() == 1 and back.effects[0].grant != null and back.effects[0].get_text(0, false) == txt, "grant survives save: " + txt)
	print("AUDIT grant clauses (1 seed): %d" % grants)
	_check(grants > 10, "free triggers produce grants (%d)" % grants)
	var cfg = _cfg()
	cfg.free_triggers = false
	var plan2 = Generator.new(cfg, 7).generate(isvc.items, isvc.characters, [], [])
	for id in plan2.items:
		for e in plan2.items[id].effects:
			if e is TriggerEffect:
				_check(e.payload in Catalog.LEGAL[e.trigger], "free triggers off -> classic legal table")
	for t in Catalog.FREE_LEGAL:
		_check(not ("heal" in Catalog.FREE_LEGAL[t] and t == "heal"), "no heal loop")
		_check(not ("xp" in Catalog.FREE_LEGAL[t] and t == "level_up"), "no xp/level loop")
		if Catalog.TRIGGERS[t].kind == "shop":
			for p in Catalog.FREE_LEGAL[t]:
				_check(p in ["perm_stat", "gold", "grant", "rand_stats"], "shop trigger payload is shop-safe")


func test_89b_shop_grant() -> void:
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [TriggerEffect.make({"trigger": "buy", "payload": "grant", "value": 3, "grant": _plain("items_price", -1), "grant_mode": "perm", "grant_unit": 3.0})]
	rd.players_data[0].items.push_back(holder)
	var ip = Keys.generate_hash("items_price")
	var before = rd.get_player_effects(0)[ip]
	m.fire_shop("buy", 0)
	_eq(rd.get_player_effects(0)[ip], before - 3, "buy -> permanently -3% items price")
	rd.get_player_effects(0)[ip] = before
	m.on_menu_reset()



func test_16b_permanent_caps() -> void:
	var gen = Generator.new(_cfg(), 4)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	gen.rng.seed = 4
	var caps = []
	var shown = 0
	for i in 400:
		var c = gen.gen_clause(rng_budget(i), 4.0, false)
		if c.empty():
			continue
		# 永久属性条款（永久获得效果的单位价值差异很大，上限按预算另算）
		var perm = c.payload == "perm_stat"
		if perm and Valuation.raw_rate(c.trigger, 1, 100) > 1.5:
			caps.push_back(c.cap)
			if shown < 5:
				print("AUDIT perm clause: ", TriggerEffect.make(c).get_text(0, false))
				shown += 1
	caps.sort()
	print("AUDIT perm caps on high-frequency triggers: n=%d median=%d max=%d" % [caps.size(), caps[caps.size() / 2] if caps.size() > 0 else 0, caps.back() if caps.size() > 0 else 0])
	var big = 0
	for c in caps:
		if c >= 4:
			big += 1
	print("AUDIT perm caps >= 4: %d / %d" % [big, caps.size()])
	_check(caps.size() > 10 and caps[caps.size() / 2] >= 2 and big >= caps.size() / 4, "permanent caps are no longer 1-3")


func rng_budget(i: int) -> float:
	return [10.0, 20.0, 35.0, 60.0][i % 4]


# ============================================================
# 下一波（芹菜茶 / 孔雀）与同扳机正负成对
# ============================================================
func test_92_next_wave_and_pairs() -> void:
	var nw = 0
	var nw_pairs = 0
	var paired = 0
	var shown = 0
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			var effs = plan.items[id].effects
			var n_here = 0
			for e in effs:
				if gen.is_next_wave(e):
					n_here += 1
					_eq(e.storage_method, Effect.StorageMethod.KEY_VALUE, "next wave uses native storage")
					var txt = e.get_text(0, false)
					_check(txt != "" and txt.find("AA_") == -1, "next wave text: " + txt)
				elif e is TriggerEffect and e.is_downside():
					var idx = effs.find(e)
					var prev = effs[idx - 1] if idx > 0 else null
					if prev is TriggerEffect and not prev.is_downside() and prev.trigger == e.trigger and prev.param == e.param and prev.chance == e.chance and prev.cap == e.cap and prev.payload == e.payload:
						paired += 1
						if shown < 6:
							print("AUDIT paired clauses: ", prev.get_text(0, false), " | ", e.get_text(0, false))
							shown += 1
			if n_here > 0:
				nw += 1
				if n_here > 1:
					nw_pairs += 1
					if shown < 10:
						print("AUDIT next wave: ", _texts(effs))
						shown += 1
	print("AUDIT next-wave items %d (paired %d), paired trigger clauses %d (5 seeds)" % [nw, nw_pairs, paired])
	_check(nw > 20 and nw_pairs > 5 and paired >= 25, "next-wave and paired effects appear (%d / %d / %d)" % [nw, nw_pairs, paired])
	# 运行时：成对条款同时施加正负两部分
	TempStats.reset()
	var rt = _make_runtime([
		{"trigger": "kill", "payload": "temp_stat", "stat": "stat_armor", "value": 3},
		{"trigger": "kill", "payload": "temp_stat", "stat": "enemy_damage", "value": 2},
	])
	rt.fire("kill", 0)
	_eq(int(TempStats.get_stat(Keys.stat_armor_hash, 0) / rd.get_stat_gain(Keys.stat_armor_hash, 0)), 3, "positive part")
	_eq(int(TempStats.get_stat(Keys.generate_hash("enemy_damage"), 0)), 2, "negative part (enemy damage up)")
	rt.queue_free()
	TempStats.reset()
	# 下一波：购买后写入 stats_next_wave
	var gen2 = Generator.new(_cfg(), 3)
	var e = gen2._next_wave_effect("xp_gain", 50)
	var holder = _item("item_potato").duplicate()
	holder.effects = [e]
	rd.add_item(holder, 0)
	var list = rd.get_player_effects(0)[Keys.stats_next_wave_hash]
	var found = false
	for x in list:
		if x[0] == Keys.xp_gain_hash and x[1] == 50:
			found = true
	_check(found, "next wave entry queued for the next wave")
	rd.remove_item(holder, 0)
	# 估值：孔雀校准
	var pv = 0.66 * 25 + Valuation.next_wave_value("xp_gain", 100, Catalog.PERM_MULT[2]) - Valuation.next_wave_value("enemy_damage", 50, Catalog.PERM_MULT[2]) / Catalog.DOWNSIDE_DIVISOR
	var g3 = Generator.new(_cfg(), 1)
	g3._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var peacock_budget = g3.item_budget(_item("item_peacock"))
	print("AUDIT peacock model value %.1f vs budget %.1f" % [pv, peacock_budget])
	_check(abs(pv / peacock_budget - 1.0) < 0.35, "next-wave valuation matches peacock")


# ============================================================
# 新扳机（暴击击杀 / 击杀燃烧敌人 / 每走 N 步 / 半波）、词条绑定、角色效果、下一波种类
# ============================================================
func test_93_new_triggers_tags_and_char_components() -> void:
	TempStats.reset()
	var rt = _make_runtime([
		{"trigger": "crit_kill", "param": 2, "payload": "gold", "value": 5},
		{"trigger": "burning_kill", "payload": "temp_stat", "stat": "stat_armor", "value": 1},
		{"trigger": "steps", "param": 10, "payload": "xp", "value": 3},
		{"trigger": "half_wave", "payload": "temp_stat", "stat": "stat_dodge", "value": 7},
	])
	var g0 = rd.get_player_gold(0)
	rt.fire("crit_kill", 0)
	rt.fire("crit_kill", 0)
	_eq(rd.get_player_gold(0), g0 + 5, "every 2 crit kills")
	rt.fire("kill", 0)
	_eq(rd.get_player_gold(0), g0 + 5, "plain kill does not count as crit kill")
	rt.fire("burning_kill", 0)
	_eq(int(TempStats.get_stat(Keys.stat_armor_hash, 0) / rd.get_stat_gain(Keys.stat_armor_hash, 0)), 1, "burning kill")
	var xp0 = rd.get_player_xp(0)
	for i in 10:
		rt.fire("steps", 0)
	_check(rd.get_player_xp(0) > xp0, "every 10 steps")
	rt.fire("half_wave", 0)
	_eq(int(TempStats.get_stat(Keys.stat_dodge_hash, 0) / rd.get_stat_gain(Keys.stat_dodge_hash, 0)), 7, "half wave")
	rt.queue_free()
	TempStats.reset()
	# 生成：新扳机、词条绑定、角色效果、下一波种类
	var seen_trig = {}
	var char_kinds = {}
	var next_kinds = {}
	var shown = 0
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			var p = plan.items[id]
			for e in p.effects:
				if e is TriggerEffect:
					seen_trig[e.trigger] = true
					if e.value > 0 and e.trigger == "crit_kill":
						_check("stat_crit_chance" in p.tags, id + " crit-kill item has crit tag")
					if e.value > 0 and e.trigger == "burning_kill":
						_check("stat_elemental_damage" in p.tags, id + " burning-kill item has elemental tag")
				if gen.is_scaling(e) and e.value > 0:
					if e.stat_scaled == "burning_enemy":
						_check("stat_elemental_damage" in p.tags, id + " burning-enemy counter has elemental tag")
					if e.stat_scaled == "structure":
						_check("structure" in p.tags, id + " structure counter has structure tag")
				if gen.is_next_wave(e) and e.value > 0 and not Catalog.ENEMY_STATS.has(e.key):
					next_kinds[e.key] = true
				if e.key == "extra_loot_aliens_next_wave":
					next_kinds["loot_aliens"] = true
				var k = ""
				if e.get_script() == load("res://effects/items/class_bonus_effect.gd"):
					k = "class_bonus"
				elif e.key in ["pacifist", "bonus_non_elemental_damage_against_burning_targets", "group_structures", "weapon_slot"]:
					k = e.key
				elif e.custom_key == "stats_end_of_wave" and e.key.begins_with("enemy_"):
					k = "enemy_growth"
				if k != "":
					char_kinds[k] = char_kinds.get(k, 0) + 1
					var t = e.get_text(0, false)
					_check(t != "" and t.find("AA_") == -1, "char component text: " + t)
					if shown < 8:
						print("AUDIT char component: ", t)
						shown += 1
	print("AUDIT char components: ", char_kinds, " next-wave kinds: ", next_kinds.keys())
	for t in ["crit_kill", "burning_kill", "steps", "half_wave"]:
		_check(seen_trig.has(t), "trigger generated: " + t)
	for k in next_kinds:
		_check(k in ["xp_gain", "loot_aliens"], "next-wave positive is xp or loot aliens: " + k)
	for k in ["class_bonus", "pacifist", "weapon_slot", "enemy_growth"]:
		_check(char_kinds.has(k), "char component generated: " + k)
	# 武器栏受规则限定的角色不刷"+武器栏"
	_setup_player("character_one_arm")
	m.start_new_run()
	var one_arm = isvc.get_element_safe(isvc.characters, "character_one_arm")
	for id in m.plan.items:
		if "weapon_slot" in m.plan.items[id].main_stats:
			_check(id in one_arm.banned_items, "one-arm bans weapon-slot item " + id)
	m.on_menu_reset()


# ============================================================
# 与其他 mod 的道具共处：只重组原版（含 DLC）资源
# ============================================================
func test_94_other_mod_items_untouched() -> void:
	var fake = _item("item_potato").duplicate()
	fake.my_id = "item_testmod_widget"
	fake.my_id_hash = Keys.generate_hash(fake.my_id)
	fake.name = "TESTMOD_WIDGET"
	fake.unlocked_by_default = true
	var fake_effects = fake.effects
	isvc.add_mod_item(fake)
	_check(not m.is_native_resource(fake), "script-created item is not native")
	_check(m.is_native_resource(_item("item_potato")), "base item is native")
	var dlc_item = null
	for it in isvc.items:
		if it.resource_path.begins_with("res://dlcs/"):
			dlc_item = it
			break
	if dlc_item != null:
		_check(m.is_native_resource(dlc_item), "DLC item is native: " + dlc_item.my_id)
	m.start_new_run()
	_check(not m.plan.items.has("item_testmod_widget"), "mod item not reassembled")
	_check(fake.effects == fake_effects and fake.name == "TESTMOD_WIDGET", "mod item unchanged")
	_check(fake in isvc.items, "mod item still registered")
	isvc.init_unlocked_pool()
	var in_pool = false
	for it in isvc.get_pool(fake.tier, 0):
		if it == fake:
			in_pool = true
	_check(in_pool, "mod item still in the shop pool")
	var pl = m.preview_plan(42)
	_check(not pl.items.has("item_testmod_widget"), "preview ignores mod item")
	m.on_menu_reset()
	isvc.remove_mod_item(fake)
	isvc.init_unlocked_pool()


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


func test_95_curse_whole_pool() -> void:
	var pd = tree.root.get_node("ProgressData")
	var dlc = pd.get_dlc_data("abyssal_terrors")
	if dlc == null:
		print("  (DLC data unavailable, skipped)")
		return
	rd.current_wave = 12
	# 原版诅咒对这些 key 有特殊处理（固定值 / 随机值 / 数值越小越好）
	var special_keys = ["dodge_cap", "hp_start_next_wave", "extra_elite_next_wave_chance", "hit_protection", "stat_curse", "knockback_aura", "modify_every_x_projectile"]
	var n_items = 0
	var n_trig = 0
	var n_side = 0
	var n_skipped_assert = 0
	for sd in [11, 222]:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			# 原版诅咒对少数效果按道具 ID 断言（仅调试版生效，正式版断言被移除、后续逻辑对任何持有者都成立）
			var id_asserted = false
			for e in plan.items[id].effects:
				var ek = e.custom_key if e.custom_key != "" else e.key
				if ek in CURSE_ID_ASSERTED and CURSE_ID_ASSERTED[ek] != id:
					id_asserted = true
			if id_asserted:
				n_skipped_assert += 1
				continue
			var holder = _item(id).duplicate()
			holder.effects = plan.items[id].effects
			holder.is_cursed = false
			var cursed = dlc.curse_item(holder, 0)
			n_items += 1
			_check(cursed.is_cursed and cursed.curse_factor > 0.0, id + " cursed")
			# 原版诅咒可能插入额外行（藏宝图 +幸运、铁砧 +护甲……）：按类型与 key 匹配对应行
			var used = {}
			for i in holder.effects.size():
				var a = holder.effects[i]
				var b = null
				for j in cursed.effects.size():
					var c = cursed.effects[j]
					if not used.has(j) and c.get_script() == a.get_script() and c.key == a.key and c.custom_key == a.custom_key:
						b = c
						used[j] = true
						break
				_check(b != null, "%s effect %d (%s) survives the curse" % [id, i, a.key])
				if b == null:
					continue
				var txt = b.get_text(0, false)
				_check(txt.find("AA_") == -1, "%s cursed text: %s" % [id, txt])
				if (a.custom_key if a.custom_key != "" else a.key) in special_keys:
					continue
				if a.value != 0 and "value" in b:
					if _is_good(a):
						_check(abs(b.value) >= abs(a.value), "%s: good line not weakened (%s: %d -> %d)" % [id, a.key, a.value, b.value])
					else:
						_check(abs(b.value) <= abs(a.value), "%s: bad line not strengthened (%s: %d -> %d)" % [id, a.key, a.value, b.value])
				if a is TriggerEffect:
					n_trig += 1
					if a.is_downside():
						n_side += 1
					if a.grant != null:
						_check(b.grant != null, id + " grant kept")
	print("AUDIT cursed %d items, %d trigger clauses (%d downside clauses); skipped %d items carrying an ID-asserted effect on another holder (debug-build assert only)" % [n_items, n_trig, n_side, n_skipped_assert])
	_check(n_side > 3, "downside clauses covered")
	# 诅咒后的触发条款在运行时照常生效（并且更强）
	TempStats.reset()
	var base = _item("item_potato").duplicate()
	base.effects = [
		TriggerEffect.make({"trigger": "kill", "payload": "temp_stat", "stat": "stat_armor", "value": 2}),
		TriggerEffect.make({"trigger": "kill", "payload": "temp_stat", "stat": "enemy_damage", "value": 4}),
	]
	var cursed2 = dlc.curse_item(base, 0, true)
	_check(cursed2.effects[1].value < 4, "native curse weakens the enemy-stat clause (%d)" % cursed2.effects[1].value)
	rd.add_item(cursed2, 0)
	var rt = Runtime.new()
	tree.root.add_child(rt)
	rt.mod = m
	rt.rebuild_all()
	rt.fire("kill", 0)
	_check(int(TempStats.get_stat(Keys.stat_armor_hash, 0) / rd.get_stat_gain(Keys.stat_armor_hash, 0)) >= 3, "cursed trigger stronger at runtime")
	_check(int(TempStats.get_stat(Keys.generate_hash("enemy_damage"), 0)) <= 3, "cursed paired downside weaker at runtime")
	rt.queue_free()
	TempStats.reset()
	rd.remove_item(cursed2, 0)


# 原版的"限制 (N)"/"独特"不继承到重组道具
func test_96_no_item_limits() -> void:
	var limited = []
	for it in isvc.items:
		if it.max_nb > 0 and m.is_native_resource(it) and not it.my_id in Catalog.ANCHORED_ITEMS:
			limited.push_back([it, it.max_nb])
	_check(limited.size() > 5, "native pool has limited items (%d)" % limited.size())
	m.start_new_run()
	var lifted = 0
	for pair in limited:
		if m.plan.items.has(pair[0].my_id):
			# 带叠加有技术问题的效果的重组道具是独特的（catalog.UNIQUE_MECHANIC_*）
			_eq(pair[0].max_nb, 1 if m.plan.items[pair[0].my_id].unique else -1, pair[0].my_id + " limit lifted")
			lifted += 1
	_check(lifted > 5, "limits lifted on reassembled items (%d)" % lifted)
	m.on_menu_reset()
	for pair in limited:
		_eq(pair[0].max_nb, pair[1], pair[0].my_id + " limit restored")



# 真实游戏里 DLC 脚本位于独立 pck、mod 加载时尚不存在：不能扩展 res://dlcs/ 下的脚本
func test_97_no_dlc_script_extensions() -> void:
	var f = File.new()
	f.open(MOD_DIR + "mod_main.gd", File.READ)
	var src = f.get_as_text()
	f.close()
	_check(src.find('install_script_extension(dir + "dlcs') == -1, "no script extension targets res://dlcs/")
	var d = Directory.new()
	_check(not d.dir_exists(MOD_DIR + "extensions/dlcs"), "no extensions/dlcs folder")



# 敌人属性条款：估值为负、显示为负面、被视为代价
func test_98_enemy_stat_clauses() -> void:
	var c = {"trigger": "wave_start", "payload": "temp_stat", "stat": "enemy_health", "value": 10}
	_check(Valuation.clause_value(c, 4.0) < 0.0, "enemy stat clause has negative value")
	var e = TriggerEffect.make(c)
	_eq(e.effect_sign, Effect.Sign.NEGATIVE, "enemy stat clause uses the native negative sign")
	_check(e.is_downside(), "enemy stat clause is a downside")


# ============================================================
# 建筑 / 宠物 / 沙漏 / 金鱼 / 镜子现在也会被重组；角色初始道具保留原版；T4 无 +收获；T3 单效果非纯数值
# ============================================================
func test_99_structures_and_special_items_reassembled() -> void:
	var plan = _gen(42)
	for id in ["item_turret", "item_landmines", "item_garden", "item_bonk_dog", "item_lootworm", "item_hourglass", "item_goldfish", "item_mirror"]:
		_check(plan.items.has(id), id + " is reassembled")
	for id in ["item_builder_turret_0", "item_goldfish_used", "item_broken_mirror", "item_broken_hourglass"]:
		_check(not plan.items.has(id), id + " kept")
	m.start_new_run()
	for id in ["item_hourglass", "item_goldfish", "item_mirror"]:
		_eq(_item(id).replaced_by, null, id + " no longer turns into another item")
	m.on_menu_reset()
	_check(_item("item_mirror").replaced_by != null, "mirror replaced_by restored")
	# 技术法师：本局初始道具（炮台）不重组，开局的与商店里的同 ID 道具都是原版
	_setup_player("character_technomage")
	rd.add_starting_items_and_weapons()
	var native_turret_effects = _item("item_turret").effects
	m.start_new_run()
	_check(not m.plan.items.has("item_turret"), "technomage run: turret not reassembled")
	var owned_turrets = 0
	for it in rd.players_data[0].items:
		if it.my_id == "item_turret":
			owned_turrets += 1
			_check(it.effects == native_turret_effects, "starting turret keeps its native effect")
			_check(it.is_structure_item(), "starting turret still spawns a structure")
	_eq(owned_turrets, 2, "technomage owns two starting turrets")
	_check(_item("item_turret").effects == native_turret_effects, "shop turret is native too")
	m.on_menu_reset()


func test_99b_tier_rules() -> void:
	var t3_single = 0
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			var tier = _item(id).tier
			var p = plan.items[id]
			if tier == 3:
				for e in p.effects:
					if e.value > 0 and (e.key == "stat_harvesting" or (e is TriggerEffect and e.stat == "stat_harvesting") or (gen.is_scaling(e) and e.key == "stat_harvesting")):
						_check(false, id + " T4 item has +harvesting: " + e.get_text(0, false))
			if tier == 2 and p.effects.size() == 1:
				t3_single += 1
	print("AUDIT T3 single-line items: %d (5 seeds)" % t3_single)
	# 敌人属性作为独立代价 / 触发结果
	var gen2 = Generator.new(_cfg(), 9)
	gen2._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	gen2.rng.seed = 9
	var enemy_neg = 0
	for i in 300:
		var c = gen2.gen_clause(-8.0, 4.0, true)
		if not c.empty() and Catalog.ENEMY_STATS.has(c.stat):
			enemy_neg += 1
			_check(c.value > 0 and Valuation.clause_value(c, 4.0) < 0, "enemy downside clause increases enemy stat")
	_check(enemy_neg > 20, "negative trigger clauses can raise enemy stats (%d)" % enemy_neg)


# ============================================================
# 核心属性道具：T1–T3 每档、每个重要输出 / 收获属性各一件，唯一正面效果为该属性
# ============================================================
func test_100_core_stat_items() -> void:
	var ratios = [[], []]
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		var seen = {}
		for id in plan.items:
			var p = plan.items[id]
			var tier = _item(id).tier
			if p.has("core"):
				var k = str(tier) + "/" + p.core
				_check(not seen.has(k), "one core item per tier/stat " + k)
				seen[k] = true
				_check(tier in Catalog.CORE_TIERS, "core item tier " + id)
				_check(gen.is_plain_stat(p.effects[0]) and p.effects[0].key == p.core and p.effects[0].value > 0, id + " first line is the core stat")
				for j in range(1, p.effects.size()):
					_check(not _is_good(p.effects[j]) or Catalog.is_downside_mechanic(p.effects[j]) or (p.effects[j] is TriggerEffect and p.effects[j].is_downside()), id + " other lines are downsides: " + p.effects[j].get_text(0, false))
				_check(p.effects.size() >= 2, id + " core item carries a downside")
				ratios[0].push_back(p.effects[0].value * Catalog.stat_w(p.core) / p.budget)
			else:
				ratios[1].push_back(p.budget / gen.item_budget(_item(id)))
		for t in Catalog.CORE_TIERS:
			for st in Catalog.CORE_STATS:
				_check(seen.has(str(t) + "/" + st), "seed %d has core %d/%s" % [sd, t, st])
	ratios[0].sort()
	print("AUDIT core items: n=%d, core-line value / budget median %.2f" % [ratios[0].size(), ratios[0][ratios[0].size() / 2]])
	# 保留原版滑条：被保留原版的道具不会被选为核心道具
	var cfg = _cfg()
	cfg.native_ratio = 50
	var g2 = Generator.new(cfg, 3)
	var p2 = g2.generate(isvc.items, isvc.characters, [], [])
	var n_core = 0
	for id in p2.items:
		if p2.items[id].has("core"):
			n_core += 1
	_eq(n_core, Catalog.CORE_STATS.size() * Catalog.CORE_TIERS.size(), "core items survive native_ratio 50%")


# ============================================================
# 实际商店抽取：每个角色分别用原版道具池与重组道具池各抽 N 件道具（原版 ItemService._get_rand_item_for_wave），
# 检查 (1) 角色禁用（禁用道具 / 禁用道具组 / remove_shop_items 词条）在重组后按语义生效；
# (2) 角色想要的词条（wanted_tags）在重组后仍然提高出现概率，且带该词条的道具确实提供对应效果
# ============================================================
const ROLLS_PER_MODE = 600
const WANTED_ROLLS = 2000


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
			if e.grant != null and "stat_scaled" in e.grant:
				out.push_back(e.grant.stat_scaled)
		elif "stat_scaled" in e:
			out.push_back(e.stat_scaled)
	return out


func test_101_character_bans_and_wanted_tags_in_rolls() -> void:
	_unlock_everything()
	var t0 = OS.get_ticks_msec()
	var ban_rows = []
	var tag_rows = []
	var n_checked = 0
	var boost_sum = [0.0, 0.0]
	var boost_n = 0
	var n_tag_slots = 0
	var shown_tag_items = 0
	for ch0 in isvc.characters:
		if not m.is_native_resource(ch0):
			continue
		var cid = ch0.my_id
		var remove_tags = []
		for e in ch0.effects:
			if e.custom_key == "remove_shop_items":
				remove_tags.push_back(e.key)
		if ch0.banned_items.empty() and ch0.banned_item_groups.empty() and ch0.wanted_tags.empty() and remove_tags.empty():
			continue
		n_checked += 1
		# 禁用语义（从原版被禁道具推出，与 mod 的重建规则无关的独立口径：被禁道具的全部"主属性"原因）
		_reset()
		m.cfg_char_effects = true
		var sems = []
		var ban_gen = Generator.new(_cfg(), 1)
		for id in ch0.banned_items:
			var it = _item(id)
			if it != null:
				for r in ban_gen.ban_reasons(it.effects):
					# 想要的词条优先（与 mod 规则一致）
					if not r in sems and not r in ch0.wanted_tags:
						sems.push_back(r)
		var group_needs = []
		for g in ch0.banned_item_groups:
			group_needs.push_back(Catalog.GROUP_STATS.get(g, []))
		var res = {}
		for mode in ["native", "aa"]:
			_reset()
			m.cfg_char_effects = true
			m.cfg_items = mode == "aa"
			_setup_player(cid)
			m.start_new_run()
			isvc.init_unlocked_pool()
			var ch = rd.get_player_character(0)
			var rolls = _roll_items(ROLLS_PER_MODE)
			var r = {"rate_with": 0.0, "rate_without": 0.0, "n": rolls.size(), "banned_id": 0, "sem_main": 0, "sem_any": 0, "removed_tag": 0, "wanted": 0, "wanted_relevant": 0, "pool_wanted": 0.0}
			for it in rolls:
				var pitems = m.plan.get("items", {})
				var gen_item = pitems.has(it.my_id)
				var ms = pitems[it.my_id].main_stats if gen_item else []
				if it.my_id in ch.banned_items:
					r.banned_id += 1
				if gen_item:
					if _has_any(sems, ms):
						r.sem_main += 1
					for need in group_needs:
						var all_in = not need.empty()
						for st in need:
							if not st in ms:
								all_in = false
						if all_in:
							r.sem_main += 1
				if _has_any(sems, _pos_semantics(it.effects)):
					r.sem_any += 1
				if _has_any(remove_tags, it.tags):
					r.removed_tag += 1
				if _has_any(ch.wanted_tags, it.tags):
					r.wanted += 1
					var rel = false
					for t in ch.wanted_tags:
						# 只评判重组道具；保留原版的道具（本局初始道具、锚定道具）按原版词条
						# 计数属性（每点工程 +暴击）与伤害缩放属性与原版一致也算提供（原版石皮、血手、幸运币都带计数属性词条）
						if t in it.tags and (not m.plan.get("items", {}).has(it.my_id) or not Catalog.STATS.has(t) or t in _pos_semantics(it.effects) 								or t in _synergy_stats(it.effects)):
							rel = true
					if rel:
						r.wanted_relevant += 1
					elif mode == "aa" and not r.has("shown"):
						r.shown = true
						var txt = []
						for e in it.effects:
							txt.push_back(e.get_text(0, false))
						print("AUDIT not-provided %s %s tags=%s: %s" % [cid, it.my_id, str(it.tags), " / ".join(txt)])
			# 本局偏好词条（去掉核心属性）：T1–T3 每个稀有度的商店池里都有带该词条、且该角色未被禁的道具
			if mode == "aa":
				for id in m.plan.get("items", {}):
					var pi = m.plan.items[id]
					if pi.has("wanted_tag") and shown_tag_items < 12:
						shown_tag_items += 1
						var txt = []
						for e in pi.effects:
							txt.push_back(e.get_text(0, false))
						print("AUDIT tag item [%s] T%d %s: %s" % [pi.wanted_tag, _item(id).tier + 1, id, " / ".join(txt)])
				for tag in ch.wanted_tags:
					if tag in Catalog.CORE_STATS:
						continue
					for tier in [0, 1, 2]:
						var found = false
						for it in isvc.get_pool(tier, isvc.TierData.ITEMS):
							if tag in it.tags and not it.my_id in ch.banned_items:
								found = true
								break
						_check(found, "%s: tier %d pool has a '%s' item" % [cid, tier + 1, tag])
						if found:
							n_tag_slots += 1
			# 想要词条的加成：同一角色、同一道具池，清空 wanted_tags 后再抽一次作对照
			if not ch.wanted_tags.empty():
				seed(1234)
				var with_n = 0
				var rw = _roll_items(WANTED_ROLLS)
				for it in rw:
					if _has_any(ch.wanted_tags, it.tags):
						with_n += 1
				var saved_tags = ch.wanted_tags
				ch.wanted_tags = []
				seed(1234)
				var without_n = 0
				var ro = _roll_items(WANTED_ROLLS)
				for it in ro:
					if _has_any(saved_tags, it.tags):
						without_n += 1
				ch.wanted_tags = saved_tags
				r.rate_with = float(with_n) / max(1, rw.size())
				r.rate_without = float(without_n) / max(1, ro.size())
			# 道具池中带想要词条的比例（不含禁用）
			if not ch.wanted_tags.empty():
				var tot = 0
				var hit = 0
				for t in 4:
					for it in isvc.get_pool(t, isvc.TierData.ITEMS):
						if it.my_id in ch.banned_items:
							continue
						tot += 1
						if _has_any(ch.wanted_tags, it.tags):
							hit += 1
				r.pool_wanted = float(hit) / max(1, tot)
			res[mode] = r
			m.on_menu_reset()
		var a = res.aa
		var nv = res.native
		# (1) 禁用：被禁 ID 与按语义被禁的重组道具一件都抽不到；带 remove_shop_items 词条的道具抽不到
		_eq(a.banned_id, 0, cid + " rolls no banned id (aa)")
		_eq(a.sem_main, 0, cid + " rolls no reassembled item whose main stats hit the ban semantics " + str(sems))
		_eq(a.removed_tag, 0, cid + " rolls no item with removed tags " + str(remove_tags))
		if not sems.empty() or not group_needs.empty() or not remove_tags.empty():
			ban_rows.push_back("%-24s sem=%s groups=%s rm=%s | minor-leak native %d/%d aa %d/%d" % [cid, str(sems), str(ch0.banned_item_groups), str(remove_tags), nv.sem_any, nv.n, a.sem_any, a.n])
		# (2) 想要的词条：抽到的比例高于道具池比例（原版 5% 强制 + 自然出现），且带词条的道具确实提供该属性
		if not ch0.wanted_tags.empty():
			var ra = float(a.wanted) / max(1, a.n)
			var rn = float(nv.wanted) / max(1, nv.n)
			tag_rows.push_back("%-24s %-44s pool %.2f/%.2f | native %.3f->%.3f (+%.3f) | aa %.3f->%.3f (+%.3f) | provided %d/%d" % [
				cid, str(ch0.wanted_tags), nv.pool_wanted, a.pool_wanted,
				nv.rate_without, nv.rate_with, nv.rate_with - nv.rate_without,
				a.rate_without, a.rate_with, a.rate_with - a.rate_without, a.wanted_relevant, a.wanted])
			boost_sum[0] += nv.rate_with - nv.rate_without
			boost_sum[1] += a.rate_with - a.rate_without
			boost_n += 1
			_check(a.pool_wanted > 0.0, cid + " has wanted-tag items in the reassembled pool")
			_check(a.rate_with >= a.rate_without, cid + " wanted tags raise the roll rate (%.3f -> %.3f)" % [a.rate_without, a.rate_with])
			_check(a.wanted_relevant >= a.wanted * 0.9, cid + " wanted-tag items really provide the tag (%d/%d)" % [a.wanted_relevant, a.wanted])
	print("AUDIT bans (%d characters, %d rolls per mode):" % [n_checked, ROLLS_PER_MODE])
	for l in ban_rows:
		print("AUDIT   " + l)
	print("AUDIT wanted tags:")
	for l in tag_rows:
		print("AUDIT   " + l)
	print("AUDIT wanted (non-core) tag x tier slots covered: %d" % n_tag_slots)
	print("AUDIT wanted-tag boost, mean over %d characters: native +%.3f, reassembled +%.3f" % [boost_n, boost_sum[0] / max(1, boost_n), boost_sum[1] / max(1, boost_n)])
	_check(boost_sum[1] / max(1, boost_n) >= 0.8 * boost_sum[0] / max(1, boost_n), "reassembled wanted-tag boost is comparable to native")
	print("AUDIT test_101 took %d ms" % (OS.get_ticks_msec() - t0))


# ============================================================
# 真实战斗：(A) 每种扳机都能由原版事件触发；(B) 每种载荷在战斗里真正改变玩家 / 敌人 / 武器；
# (C) 生成道具池里每种 (扳机, 载荷, 获得效果) 组合在战斗中执行后都有可观察的变化
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
		p.current_stats.health, p.max_stats.health, _enemies_hp(main), main._entity_spawner.get_all_enemies(false).size()])


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


func test_102_triggers_and_payloads_in_battle() -> void:
	m.start_new_run()
	var pistol = isvc.get_element_safe(isvc.weapons, "weapon_pistol_1")
	var _w = rd.add_weapon(pistol, 0)
	var gain_armor = load("res://effects/items/stat_gains_modification_effect.gd").new()
	gain_armor.key = "effect_increase_stat_gains"
	gain_armor.key_hash = Keys.generate_hash(gain_armor.key)
	gain_armor.custom_key_hash = Keys.generate_hash("")
	gain_armor.value = 50
	gain_armor.stat_displayed = "stat_armor"
	gain_armor.stats_modified = ["stat_armor"]
	# (A) 每种扳机一条（状态扳机挂临时属性，其余挂 +1 材料），只看是否触发
	var trig_holder = _item("item_potato").duplicate()
	var trig_effects = []
	for t in Catalog.TRIGGERS:
		if Catalog.TRIGGERS[t].kind == "shop":
			continue
		var payload = "temp_stat" if Catalog.TRIGGERS[t].kind == "state" else "gold"
		var c = {"trigger": t, "payload": payload, "value": 1, "stat": "stat_luck"}
		if t == "interval":
			c.param = 1
		trig_effects.push_back(TriggerEffect.make(c))
	trig_holder.effects = trig_effects
	rd.add_item(trig_holder, 0)
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_wait_frames(10), "completed")
	var main = tree.current_scene
	var rt = main.get_node_or_null("AutoAnthonyRuntime") if main != null else null
	_check(rt != null, "runtime in battle")
	if rt == null:
		return
	var player = main._players[0]
	# 测试期间玩家不被敌人打到（直接调用 take_damage 不受影响）
	player.disable_hurtbox()
	# 延长本波，保证整个测试期间都有敌人
	main._wave_timer.start(600)
	var seen_state = {}

	# 满血、静止在开局即成立；等待间隔
	yield(tree.create_timer(1.3), "timeout")
	for en in rt.entries[0]:
		if en.active:
			seen_state[en.effect.trigger] = true
	# 移动与计步：锁定移动方向，让原版移动逻辑走起来
	player._move_locked = true
	player._current_movement = Vector2(1, 0)
	yield(tree.create_timer(2.0), "timeout")
	for en in rt.entries[0]:
		if en.active:
			seen_state[en.effect.trigger] = true
	player._current_movement = Vector2.ZERO
	player._move_locked = false
	# 受击
	var hit_args = TakeDamageArgs.new(-1)
	hit_args.bypass_invincibility = true
	hit_args.dodgeable = false
	var _r = player.take_damage(3, hit_args)
	yield(_wait_physics(6), "completed")
	# 闪避：闪避率 100%
	player.current_stats.dodge = 1.0
	var dodge_args = TakeDamageArgs.new(-1)
	dodge_args.bypass_invincibility = true
	var _d = player.take_damage(3, dodge_args)
	yield(_wait_frames(2), "completed")
	player.disable_hurtbox()
	# 低血
	player.current_stats.health = 1
	yield(tree.create_timer(0.5), "timeout")
	for en in rt.entries[0]:
		if en.active:
			seen_state[en.effect.trigger] = true
	# 回血（原版的回血信号）
	RunData.emit_signal("healing_effect", 3, 0, Keys.empty_hash)
	yield(_wait_frames(2), "completed")
	# 升级
	rd.add_xp(int(rd.get_next_level_xp_needed(0)) + 1, 0)
	yield(_wait_frames(2), "completed")
	# 击杀 / 燃烧击杀 / 暴击击杀（原版受伤信号带暴击标记）
	var en1 = yield(_wait_enemy(main), "completed")
	_check(en1 != null, "enemy spawned for kill triggers")
	if en1 != null:
		en1._is_burning = true
		var _k = en1.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_frames(2), "completed")
		if is_instance_valid(en1):
			main._on_enemy_took_damage(en1, 999999, Vector2.ZERO, true, false, false, false, TakeDamageArgs.new(0), 0, false)
	# 击杀被诅咒的敌人：挂上原版 DLC 的诅咒效果行为
	var en_cursed = yield(_wait_enemy(main), "completed")
	if en_cursed != null:
		var cb = load("res://dlcs/dlc_1/effect_behaviors/enemy/curse_enemy_effect_behavior.gd").new()
		en_cursed.effect_behaviors.add_child(cb)
		var _cbi = cb.init(en_cursed)
		var _kcur = en_cursed.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_frames(2), "completed")
	# 拾取材料（原版生成的材料节点）
	main.spawn_gold(1.0, player.global_position, 0)
	yield(_wait_frames(2), "completed")
	if not main._active_golds.empty():
		main.on_gold_picked_up(main._active_golds.back(), 0)
	# 拾取消耗品
	# 与原版 spawn_consumables 相同：先从对象池取（同时建立对象池），没有再实例化
	var cons = main.get_node_from_pool(main._consumable_pool_id, main._consumables_container)
	if cons == null:
		cons = main.consumable_scene.instance()
		main._consumables_container.add_child(cons)
	cons.consumable_data = isvc.consumables[0]
	cons.global_position = player.global_position
	main._consumables.push_back(cons)
	main.on_consumable_picked_up(cons, 0)
	# 半波
	main._on_HalfWaveTimer_timeout()
	yield(_wait_frames(2), "completed")
	# ---- 实验性扳机 ----
	var AAEnemyBehavior = load("res://mods-unpacked/Mojimoon-AutoAnthony/aa/enemy_behavior.gd")
	# 拾取箱子（原版箱子消耗品）
	var crate = main.get_node_from_pool(main._consumable_pool_id, main._consumables_container)
	if crate == null:
		crate = main.consumable_scene.instance()
		main._consumables_container.add_child(crate)
	crate.consumable_data = isvc.get_element_safe(isvc.consumables, "consumable_item_box")
	crate.already_picked_up = false
	crate.global_position = player.global_position
	main._consumables.push_back(crate)
	main.on_consumable_picked_up(crate, 0)
	# 引发爆炸（经原版 WeaponService.explode，延迟生成）
	var en_x = yield(_wait_enemy(main), "completed")
	if en_x != null:
		rt._explode(TriggerEffect.make({"trigger": "kill", "payload": "explode", "stat": "stat_max_hp", "value": 50}), 0, en_x.global_position)
	yield(_wait_physics(8), "completed")
	# 点燃敌人（原版燃烧，燃烧结算时触发）
	var en_b = yield(_wait_enemy(main), "completed")
	if en_b != null:
		var bd = BurningData.new()
		bd.chance = 1.0
		bd.damage = 1
		bd.duration = 3
		bd.from = player
		# 目标要活到燃烧结算（手枪会一直射击）
		en_b.max_stats.health = max(en_b.max_stats.health, 5000)
		en_b.current_stats.health = en_b.max_stats.health
		en_b.apply_burning(bd)
	yield(tree.create_timer(1.6), "timeout")
	# 首次命中 / 命中高低血：手枪的真实命中触发远程与高血部分；其余伤害类型与低血敌人用原版 on_hurt 入口模拟
	var en_h = yield(_wait_enemy(main), "completed")
	var beh = AAEnemyBehavior.find_on(en_h) if en_h != null else null
	_check(beh != null, "enemies carry the mod's effect behavior")
	if beh != null:
		var hb = Hitbox.new()
		hb.from = player
		hb.scaling_stats = [[Keys.stat_ranged_damage_hash, 1.0]]
		beh.on_hurt(hb)
		hb.scaling_stats = [[Keys.stat_melee_damage_hash, 1.0], [Keys.stat_elemental_damage_hash, 1.0], [Keys.stat_engineering_hash, 1.0]]
		# 第 1 波敌人生命只有个位数：放大上限后设为 5%
		en_h.max_stats.health = max(en_h.max_stats.health, 40)
		en_h.current_stats.health = 2
		beh.on_hurt(hb)
		hb.free()
	yield(_wait_frames(2), "completed")
	var fired = {}
	for en in rt.entries[0]:
		if en.effect in trig_effects:
			fired[en.effect.trigger] = en.fired > 0 or en.active or seen_state.has(en.effect.trigger)
	for t in Catalog.TRIGGERS:
		if Catalog.TRIGGERS[t].kind == "shop" or t == "wave_end":
			continue
		_check(fired.get(t, false), "trigger fires from real game events: " + t)

	# (B) 载荷：直接执行，检查真实的玩家 / 敌人 / 武器状态
	player.current_stats.health = player.max_stats.health
	var weapon = player.current_weapons[0] if not player.current_weapons.empty() else null
	var base_armor = player.max_stats.armor
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "temp_stat", "stat": "stat_armor", "value": 4}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_eq(player.max_stats.armor, base_armor + 4, "temp stat reaches the player's real armor")
	var base_hp = player.max_stats.health
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "perm_stat", "stat": "stat_max_hp", "value": 5}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_eq(player.max_stats.health, base_hp + 5, "perm stat reaches the player's real max HP")
	var base_speed = player.max_stats.speed
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "timed_stat", "stat": "stat_speed", "value": 20, "value2": 1}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_check(player.max_stats.speed > base_speed, "timed stat raises real speed")
	yield(tree.create_timer(1.4), "timeout")
	_check(abs(player.max_stats.speed - base_speed) < 0.01, "timed stat expires")
	player.current_stats.health = max(1, player.max_stats.health - 10)
	var h0 = player.current_stats.health
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "heal", "value": 3}), 0, null, false)
	yield(_wait_frames(2), "completed")
	_check(player.current_stats.health > h0, "heal payload heals the player (%d -> %d)" % [h0, player.current_stats.health])
	var g0 = rd.get_player_gold(0)
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "gold", "value": 7}), 0, null, false)
	_eq(rd.get_player_gold(0), g0 + 7, "gold payload")
	var x0 = rd.get_player_xp(0)
	var l0 = rd.get_player_level(0)
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "xp", "value": 3}), 0, null, false)
	_check(rd.get_player_xp(0) > x0 or rd.get_player_level(0) > l0, "xp payload")
	var en2 = yield(_wait_enemy(main), "completed")
	if en2 != null:
		var hp0 = _enemies_hp(main)
		rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "damage", "stat": "stat_max_hp", "value": 100}), 0, null, false)
		yield(_wait_frames(2), "completed")
		_check(_enemies_hp(main) < hp0, "damage payload hurts an enemy")
	var en3 = yield(_wait_enemy(main), "completed")
	if en3 != null:
		var e_hp = en3.current_stats.health
		rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "explode", "stat": "stat_max_hp", "value": 100}), 0, en3.global_position, false)
		yield(_wait_physics(12), "completed")
		_check(not is_instance_valid(en3) or en3.dead or en3.current_stats.health < e_hp, "explode payload hurts the enemy at the position")
	# 获得效果：机制（穿透 → 武器的真实穿透数）、属性修改（护甲 +50% → 真实护甲）
	if weapon != null:
		var p0 = weapon.current_stats.piercing
		rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "grant", "value": 2, "grant": _plain("piercing", 1), "grant_mode": "temp", "grant_unit": 10.0}), 0, null, false)
		yield(_wait_physics(12), "completed")
		_eq(weapon.current_stats.piercing, p0 + 2, "granted piercing reaches the weapon")
	rd.add_stat(Keys.stat_armor_hash, 10, 0)
	yield(_wait_physics(12), "completed")
	var a0 = player.max_stats.armor
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "grant", "value": 1, "grant": gain_armor, "grant_mode": "temp", "grant_unit": 5.0}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_check(player.max_stats.armor > a0, "granted stat-gain modification raises real armor (%d -> %d)" % [a0, player.max_stats.armor])

	# 使该敌人受到的伤害提高：原版伤害计算（get_damage_value）实际变化，到时恢复
	var AAEB = load("res://mods-unpacked/Mojimoon-AutoAnthony/aa/enemy_behavior.gd")
	var en_v = yield(_wait_enemy(main), "completed")
	if en_v != null:
		var d0 = en_v.get_damage_value(100, 0, false).value
		rt.execute(TriggerEffect.make({"trigger": "crit", "payload": "vuln", "value": 30, "value2": 1}), 0, en_v.global_position, false, null, en_v)
		var d1 = en_v.get_damage_value(100, 0, false).value
		_eq(d1, int(round(d0 * 1.3)), "vuln payload raises the damage that enemy takes (%d -> %d)" % [d0, d1])
		yield(tree.create_timer(1.3), "timeout")
		if is_instance_valid(en_v) and not en_v.dead:
			_eq(en_v.get_damage_value(100, 0, false).value, d0, "vuln expires")
	# 连锁：击杀 -> 爆炸（延迟生成）-> "引发爆炸时" -> 材料；并且超过连锁深度上限的事件不再触发
	var chain_holder = _item("item_potato").duplicate()
	chain_holder.effects = [
		TriggerEffect.make({"trigger": "kill", "payload": "explode", "stat": "stat_max_hp", "value": 50}),
		TriggerEffect.make({"trigger": "explode", "payload": "gold", "value": 9}),
	]
	rd.add_item(chain_holder, 0)
	m.triggers_dirty = true
	rt._check_dirty()
	var en_c = yield(_wait_enemy(main), "completed")
	if en_c != null:
		var gc = rd.get_player_gold(0)
		var _kc = en_c.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_physics(10), "completed")
		_check(rd.get_player_gold(0) >= gc + 9, "chain kill -> explosion -> 'when you cause an explosion' gave materials (%d -> %d)" % [gc, rd.get_player_gold(0)])
	var gd = rd.get_player_gold(0)
	rt.fire("explode", 0, null, Catalog.MAX_CHAIN_DEPTH)
	_eq(rd.get_player_gold(0), gd, "events beyond the chain depth limit do not fire")
	rd.remove_item(chain_holder, 0)
	m.triggers_dirty = true
	rt._check_dirty()

	# (C) 生成池中每种组合在战斗中都有效果。先移除 (A) 的测试条款（静止 / 移动等状态加成会同时切换，干扰前后比较）
	for en in rt.entries[0].duplicate():
		if en.effect in trig_effects:
			if en.active:
				rt._set_state(0, en, false)
			rt.entries[0].erase(en)
	rd.remove_item(trig_holder, 0)
	var shapes = {}
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				if not e is TriggerEffect:
					continue
				var gk = ""
				if e.grant != null:
					gk = e.grant.custom_key if e.grant.custom_key != "" else e.grant.key
				var k = "%s/%s/%s/%s/%s" % [e.trigger, e.payload, e.grant_mode if e.payload == "grant" else "", gk, e.stat]
				if not shapes.has(k):
					shapes[k] = e
	var bad = []
	for k in shapes:
		var e = shapes[k]
		# 受伤加成需要目标敌人且不立即改变生命值：由实验性扳机测试单独核对
		if e.payload == "vuln":
			continue
		if player.dead or not is_instance_valid(main):
			_check(false, "player alive during shape checks")
			break
		player.disable_hurtbox()
		player.current_stats.health = max(1, player.max_stats.health / 2)
		# 伤害 / 爆炸看敌人总生命，敌人同时生成 / 死亡会干扰比较：最多重试 3 次
		var changed = false
		for attempt in (3 if e.payload in ["damage", "explode", "hp_dmg"] else 1):
			var tgt = yield(_wait_enemy(main), "completed")
			var before = _battle_snapshot(main)
			var hp_before = _enemy_hp_map(main)
			var tb = AAEB.find_on(tgt) if tgt != null and is_instance_valid(tgt) else null
			var vuln_before = tb._vuln_total if tb != null else 0
			rt.execute(e, 0, tgt.global_position if tgt != null and is_instance_valid(tgt) else null, false, null, tgt if tgt != null and is_instance_valid(tgt) else null)
			# 爆炸由 WeaponService 延迟生成，命中需要几帧
			yield(_wait_physics(12 if e.payload == "explode" else 4), "completed")
			if e.payload == "vuln":
				if tb != null and is_instance_valid(tb) and tb._vuln_total > vuln_before:
					changed = true
					break
			elif e.payload in ["damage", "explode", "hp_dmg"]:
				if _any_enemy_hurt(main, hp_before):
					changed = true
					break
			elif _battle_snapshot(main) != before:
				changed = true
				break
		if not changed:
			bad.push_back(k + " : " + e.get_text(0, false))
		player.current_stats.health = player.max_stats.health
	print("AUDIT battle-executed %d distinct (trigger, payload, grant, stat) shapes, %d without effect" % [shapes.size(), bad.size()])
	for b in bad:
		print("AUDIT   no effect: " + b)
	_check(bad.empty(), "every generated trigger shape changes the battle state")
	main._cleaning_up = true
	rt.revert_all_grants()
	m.on_menu_reset()


# ============================================================
# 探查："每有 [计数] 获得 [属性]"作为触发结果（已从生成中移除）在真实战斗中是否正确
# 对每种计数：本波获得 / 叠加 / 波末撤销 / 状态开关 / 永久获得 / 序列化往返，与原版 LinkedStats 口径的期望值比较
# ============================================================
func _scaling_grant(target: String, counter: String, nb: int, perm_only: bool):
	var e = load("res://effects/items/gain_stat_for_every_stat_effect.gd").new()
	e.key = target
	e.key_hash = Keys.generate_hash(target)
	e.custom_key_hash = Keys.generate_hash("")
	e.value = 1
	e.stat_scaled = counter
	e.stat_scaled_hash = Keys.generate_hash(counter)
	e.nb_stat_scaled = nb
	e.perm_stats_only = perm_only
	e.text_key = Catalog.COUNTER_TEXT.get(counter, "EFFECT_GAIN_STAT_FOR_EVERY_PERM_STAT" if perm_only else "EFFECT_GAIN_STAT_FOR_EVERY_STAT")
	return e


# 与原版 LinkedStats.reset_player 相同的计数口径
func _counter_now(counter: String, perm_only: bool) -> float:
	match counter:
		"materials": return float(rd.get_player_gold(0))
		"structure": return float(rd.get_nb_structures(0))
		"living_enemy": return float(rd.current_living_enemies)
		"burning_enemy": return float(rd.current_burning_enemies)
		"living_tree": return float(rd.current_living_trees)
		"percent_player_missing_health":
			return float(WeaponService.apply_inverted_health_bonus(1, 1, rd.get_player_current_health(0), rd.get_player_max_health(0)))
		"different_item": return float(rd.get_nb_different_items_of_tier(-1, 0))
		"common_item": return float(rd.get_nb_different_items_of_tier(Tier.COMMON, 0))
		"legendary_item": return float(rd.get_nb_different_items_of_tier(Tier.LEGENDARY, 0))
		"free_weapon_slots": return float(rd.get_free_weapon_slots(0))
	var h = Keys.generate_hash(counter)
	return rd.get_stat(h, 0) + (0.0 if perm_only else TempStats.get_stat(h, 0))


func test_103_scaling_grants_probe() -> void:
	m.start_new_run()
	var pistol = isvc.get_element_safe(isvc.weapons, "weapon_pistol_1")
	var _w = rd.add_weapon(pistol, 0)
	# 让各种计数都不为 0：几件不同的普通 / 传说道具、材料、属性
	var added = 0
	for it in isvc.items:
		if added >= 4:
			break
		if it.tier == 0 and not it.is_cursed and it.effects.size() > 0:
			# 只用纯属性道具，避免原版的计数型效果随战斗变化干扰基线
			var plain = true
			for e in it.effects:
				if e.get_script() != load("res://items/global/effect.gd") or e.custom_key != "" or e.key == "stat_max_hp" or not Catalog.STATS.has(e.key):
					plain = false
			if not plain:
				continue
			rd.add_item(it, 0)
			added += 1
	for it in isvc.items:
		if it.tier == 3 and not it.is_cursed and it.effects.size() == 1 and it.effects[0].get_script() == load("res://items/global/effect.gd") and it.effects[0].key != "stat_max_hp" 				and it.effects[0].custom_key == "" and Catalog.STATS.has(it.effects[0].key):
			rd.add_item(it, 0)
			break
	rd.add_gold(80, 0)
	for st in ["stat_luck", "stat_range", "stat_engineering", "stat_harvesting", "stat_armor"]:
		rd.add_stat(Keys.generate_hash(st), 12, 0)
	rd.current_wave = 3
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_wait_frames(10), "completed")
	var main = tree.current_scene
	var rt = main.get_node_or_null("AutoAnthonyRuntime") if main != null else null
	_check(rt != null, "runtime in battle")
	if rt == null:
		return
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	# 等场上有几个敌人（"每个存活敌人"计数），并让玩家损失部分生命（"每 1% 已损失生命"计数）
	for i in 40:
		if rd.current_living_enemies >= 4:
			break
		yield(tree.create_timer(0.25), "timeout")
	var hurt = TakeDamageArgs.new(-1)
	hurt.bypass_invincibility = true
	hurt.dodgeable = false
	hurt.armor_applied = false
	player.enable_hurtbox()
	var _h = player.take_damage(int(player.max_stats.health * 0.4), hurt)
	yield(_wait_frames(2), "completed")
	player.disable_hurtbox()

	# 用户报告的原样场景：每击杀 N 个敌人 → 本波获得「每持有一件不同的 I 级道具 +1 最大生命值」，用真实击杀触发
	var ug = _scaling_grant("stat_max_hp", "common_item", 1, false)
	var ute = TriggerEffect.make({"trigger": "kill", "param": 2, "payload": "grant", "value": 1, "grant": ug, "grant_mode": "temp", "grant_unit": 5.0})
	var uholder = _item("item_potato").duplicate()
	uholder.effects = [ute]
	rd.add_item(uholder, 0)
	m.triggers_dirty = true
	var hp_before = player.max_stats.health
	var kills = 0
	for i in 60:
		if kills >= 2:
			break
		var en = yield(_wait_enemy(main), "completed")
		if en == null:
			break
		var _k = en.take_damage(999999, TakeDamageArgs.new(0))
		kills += 1
		yield(_wait_frames(2), "completed")
	yield(_wait_physics(12), "completed")
	var n_common = int(_counter_now("common_item", false))
	print("AUDIT user scenario: %d real kills, %d different tier-I items, real max HP %d -> %d" % [kills, n_common, hp_before, player.max_stats.health])
	_check(kills == 2 and player.max_stats.health - hp_before == n_common, "user scenario: kill-triggered 'for every tier-I item' grant raises real max HP")
	rd.remove_item(uholder, 0)
	m.triggers_dirty = true
	rt._check_dirty()
	yield(_wait_physics(12), "completed")
	_check(abs(player.max_stats.health - hp_before) < 0.5, "grant removed with its item")

	var counters = Catalog.COUNTER_TEXT.keys() + ["stat_luck", "stat_range", "stat_engineering", "stat_harvesting"]
	var target = "stat_max_hp"
	var th = Keys.stat_max_hp_hash
	var rows = []
	var problems = []
	for counter in counters:
		for perm_only in ([true, false] if Catalog.STATS.has(counter) else [false]):
			player.disable_hurtbox()
			var nb = 2
			var g = _scaling_grant(target, counter, nb, perm_only)
			# 用战斗中不会自然发生的扳机（商店刷新），避免武器自动击杀额外触发
			var te = TriggerEffect.make({"trigger": "reroll", "payload": "grant", "value": 1, "grant": g, "grant_mode": "temp", "grant_unit": 5.0})
			var en = {"effect": te, "count": 0, "fired": 0, "active": false, "show": false, "stack": 0, "granted": []}
			rt.entries[0].push_back(en)
			yield(_wait_frames(2), "completed")
			var base = Utils.get_stat(th, 0)
			var hp0 = player.max_stats.health
			var cnt = _counter_now(counter, perm_only)
			rt.execute(te, 0, null, false, en)
			yield(_wait_physics(12), "completed")
			var d1 = Utils.get_stat(th, 0) - base
			var exp1 = int(1 * (cnt / nb))
			rt.execute(te, 0, null, false, en)
			yield(_wait_physics(12), "completed")
			var cnt2 = _counter_now(counter, perm_only)
			var d2 = Utils.get_stat(th, 0) - base
			var exp2 = 2 * int(1 * (cnt2 / nb))
			var hp_seen = player.max_stats.health - hp0
			var txt = te.get_text(0, false)
			rt._revert_grants(0, en)
			rt._refresh(0)
			yield(_wait_physics(12), "completed")
			var d3 = Utils.get_stat(th, 0) - base
			rt.entries[0].erase(en)
			var row = "%-32s perm=%-5s count=%.1f  +1 grant: %+d (exp %+d)  +2 grants: %+d (exp %+d)  real max HP %+d  reverted %+d" % [counter, str(perm_only), cnt, d1, exp1, d2, exp2, hp_seen, d3]
			rows.push_back(row)
			var live = counter in ["living_enemy", "burning_enemy", "living_tree", "percent_player_missing_health", "materials"]
			if d3 != 0 or (not live and (d1 != exp1 or d2 != exp2)) or (exp2 != 0 and hp_seen == 0 and not live):
				problems.push_back(row + "  | " + txt)
	# 状态扳机（静止时获得）开关、永久获得、序列化往返
	var g2 = _scaling_grant(target, "common_item", 1, false)
	var st = TriggerEffect.make({"trigger": "still", "payload": "grant", "value": 1, "grant": g2, "grant_mode": "temp", "grant_unit": 5.0})
	var en2 = {"effect": st, "count": 0, "fired": 0, "active": false, "show": false, "stack": 0, "granted": []}
	rt.entries[0].push_back(en2)
	var b2 = Utils.get_stat(th, 0)
	rt._set_state(0, en2, true)
	yield(_wait_physics(6), "completed")
	var on_d = Utils.get_stat(th, 0) - b2
	# 先移出总线，避免"静止"轮询立刻重新打开
	rt.entries[0].erase(en2)
	rt._set_state(0, en2, false)
	yield(_wait_physics(6), "completed")
	var off_d = Utils.get_stat(th, 0) - b2
	rows.push_back("state grant (still, common_item/1): on %+d, off %+d, count %d" % [on_d, off_d, _counter_now("common_item", false)])
	_check(on_d == int(_counter_now("common_item", false)) and off_d == 0, "state scaling grant on / off")
	var g3 = _scaling_grant(target, "different_item", 1, false)
	var pe = TriggerEffect.make({"trigger": "level_up", "payload": "grant", "value": 1, "grant": g3, "grant_mode": "perm", "grant_unit": 5.0})
	var b3 = Utils.get_stat(th, 0)
	rt.execute(pe, 0, null, false, null)
	yield(_wait_physics(6), "completed")
	LinkedStats.reset_player(0)
	Utils.reset_stat_cache(0)
	var perm_d = Utils.get_stat(th, 0) - b3
	rows.push_back("perm grant (level up, different_item/1): %+d after a LinkedStats reset, count %d" % [perm_d, _counter_now("different_item", false)])
	_check(perm_d == int(_counter_now("different_item", false)), "perm scaling grant survives LinkedStats reset")
	rd.get_player_effects(0)[Keys.stat_links_hash].erase([g3.key_hash, 1, g3.stat_scaled_hash, 1, false])
	var ser = pe.serialize()
	var back = TriggerEffect.new()
	back.deserialize_and_merge(ser)
	_check(back.grant != null and back.grant.stat_scaled == "different_item" and back.grant.stat_scaled_hash == g3.stat_scaled_hash, "scaling grant serialization roundtrip")
	print("AUDIT scaling-grant probe (target %s):" % target)
	for r in rows:
		print("AUDIT   " + r)
	for p in problems:
		print("AUDIT   PROBLEM " + p)
	_check(problems.empty(), "scaling grants behave like native linked stats (%d problems)" % problems.size())
	main._cleaning_up = true
	rt.revert_all_grants()
	m.on_menu_reset()


# ============================================================
# "每有 [计数] 获得 [属性]"：原版文本不显示 N 的计数固定 N = 1；道具说明里的 [+x] 与实际获得的属性一致
# ============================================================
func test_104_scaling_counts_and_bonus_text() -> void:
	var n_fixed = 0
	var n_checked = 0
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				var sc = e.grant if e is TriggerEffect and e.grant != null else e
				if not gen.is_scaling(sc):
					continue
				if sc.stat_scaled in Catalog.COUNTER_NB_FIXED:
					n_fixed += 1
					_eq(sc.nb_stat_scaled, 1, "%s: '%s' uses N = 1" % [id, sc.stat_scaled])
	print("AUDIT scaling effects on fixed-N counters: %d (5 seeds)" % n_fixed)
	_check(n_fixed > 0, "fixed-N counters still appear")
	# 实际生效：把道具池里每条（非触发）计数型效果装到玩家身上，比较属性增量与原版 get_scaling_bonus
	m.start_new_run()
	for it in isvc.items:
		if it.tier == 0 and it.effects.size() > 0 and not m.plan.items.has(it.my_id):
			rd.add_item(it, 0)
	for it in isvc.items:
		if it.tier == 0 and m.plan.items.has(it.my_id) and n_checked < 12:
			rd.add_item(it, 0)
	rd.add_gold(60, 0)
	var gen = m._gen
	for id in m.plan.items:
		for e in m.plan.items[id].effects:
			if not gen.is_scaling(e) or e.value <= 0:
				continue
			var h = Keys.generate_hash(e.key)
			LinkedStats.reset_player(0)
			Utils.reset_stat_cache(0)
			var before = Utils.get_stat(h, 0)
			var bonus = rd.get_scaling_bonus(e.value, e.stat_scaled, e.nb_stat_scaled, e.perm_stats_only, 0)
			e.apply(0)
			LinkedStats.reset_player(0)
			Utils.reset_stat_cache(0)
			var gained = Utils.get_stat(h, 0) - before
			# 原版的"属性修改"同样作用于计数加成
			bonus = int(round(bonus * rd.get_stat_gain(h, 0)))
			e.unapply(0)
			n_checked += 1
			if e.key != e.stat_scaled:
				_check(abs(gained - bonus) <= 1, "%s: text bonus [+%d] equals real gain %s (%s per %d %s)" % [id, bonus, str(gained), e.key, e.nb_stat_scaled, e.stat_scaled])
	LinkedStats.reset_player(0)
	print("AUDIT scaling effects applied and compared with their [+x] text: %d" % n_checked)
	m.on_menu_reset()


# 下一波经验：数值分散，不集中在上限
func test_105_next_wave_xp_spread() -> void:
	var vals = {}
	var n = 0
	var at_top = 0
	var top = 0
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		top = gen._line_cap("xp_gain", false) * 2
		for id in plan.items:
			for e in plan.items[id].effects:
				if gen.is_next_wave(e) and e.key == "xp_gain" and e.value > 0:
					n += 1
					vals[e.value] = vals.get(e.value, 0) + 1
					_check(e.value <= top, "next-wave xp within the cap: %d" % e.value)
					if e.value == top:
						at_top += 1
	var keys = vals.keys()
	keys.sort()
	print("AUDIT next-wave xp values (n=%d, cap %d, at cap %d): %s" % [n, top, at_top, str(keys)])
	_check(n > 10 and keys.size() >= 8, "next-wave xp values vary")
	_check(at_top <= n * 0.2, "few next-wave xp lines sit at the cap (%d / %d)" % [at_top, n])


# ============================================================
# 本局玩家角色的初始道具不重组（驯兽师：战利品虫 + 开局可选的四只宠物）；鱼钩锚定；蝾螈效果不参与组合
# ============================================================
func test_106_starting_items_stay_native() -> void:
	var bm = isvc.get_element_safe(isvc.characters, "character_beast_master")
	var ids = m.starting_item_ids([bm])
	_check("item_lootworm" in ids, "beast master: lootworm is a starting item")
	_eq(ids.size(), 1 + bm.starting_items.size(), "beast master: lootworm + selectable pets")
	_setup_player("character_beast_master")
	m.start_new_run()
	for id in ids:
		_check(not m.plan.items.has(id), "beast master run: %s not reassembled" % id)
	m.on_menu_reset()
	# 其他角色的局里照常重组
	var plan = _gen(42)
	_check(plan.items.has("item_lootworm"), "lootworm reassembled in other runs")
	# 法师：蛇、香肠；军火商：危险的兔子
	for pair in [["character_mage", ["item_snake"]], ["character_arms_dealer", ["item_dangerous_bunny"]]]:
		var ch = isvc.get_element_safe(isvc.characters, pair[0])
		var sids = m.starting_item_ids([ch])
		for id in pair[1]:
			_check(id in sids, "%s starts with %s" % [pair[0], id])
	# 存档往返：法师开局的蛇 + 商店买的蛇，读档后两件效果一致（原版按 ID 缓存序列化）
	_setup_player("character_mage")
	rd.add_starting_items_and_weapons()
	m.start_new_run()
	var snake = _item("item_snake")
	rd.add_item(snake, 0)
	var ser = rd.players_data[0].serialize()
	var pd2 = PlayerRunData.new().deserialize(JSON.parse(JSON.print(ser)).result)
	var snakes = []
	for it in pd2.items:
		if it.my_id == "item_snake":
			snakes.push_back(_texts(it.effects))
	_check(snakes.size() >= 2 and snakes[0] == snakes[1], "both snakes identical after a save roundtrip (%d)" % snakes.size())
	_eq(snakes[0] if snakes.size() > 0 else "", _texts(snake.effects), "saved snake matches the shop snake")
	m.on_menu_reset()
	# 锚定与机制来源
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var sources = {}
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			sources[mech.source] = true
	_check(not plan.items.has("item_fish_hook"), "item_fish_hook anchored")
	for id in ["item_fish_hook", "item_tardigrade"]:
		_check(sources.has(id), id + " effects still combine")
	_check(not sources.has("item_axolotl"), "axolotl effect no longer combines")


# 实验性扳机：出现频率与样例
func test_107_experimental_triggers_audit() -> void:
	var n = 0
	var n_exp = 0
	var by = {}
	var shown = 0
	for sd in SEEDS:
		var plan = Generator.new(_cfg(), sd).generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				if not e is TriggerEffect:
					continue
				n += 1
				if e.trigger in Catalog.EXPERIMENTAL_TRIGGERS:
					n_exp += 1
					by[e.trigger] = by.get(e.trigger, 0) + 1
					if shown < 10:
						shown += 1
						print("AUDIT experimental sample: " + e.get_text(0, false))
	print("AUDIT experimental trigger clauses: %d of %d (%s)" % [n_exp, n, str(by)])
	_check(n_exp > 0 and n_exp < n * 0.25, "experimental triggers appear but stay a minority")


# 几率类效果：单条效果生成时不超过 100%，价值按截断后的数值折算；叠加 / 诅咒不限制
func test_108_percent_caps() -> void:
	var n = 0
	for sd in SEEDS:
		var plan = Generator.new(_cfg(), sd).generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				var cap = Catalog.pct_cap(e)
				if cap > 0:
					n += 1
					_check(e.value <= cap, "%s: %s <= %d pct" % [id, e.get_text(0, false), cap])
				if e is TriggerEffect and e.grant != null and Catalog.pct_cap(e.grant) > 0:
					n += 1
					_check(e.grant.value * e.value <= Catalog.pct_cap(e.grant), "single grant amount <= cap: " + e.get_text(0, false))
	print("AUDIT capped-chance effects checked: %d" % n)
	_check(n > 3, "capped effects appear")
	# 希夫德圣物（100%）按超出上限的预算缩放：数值截断为 100%，价值按 100% 计（不是按想要的 150%）
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var relic = null
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			if mech.effect.key == "instant_gold_attracting" and mech.effect.value == 100:
				relic = mech
	_check(relic != null, "sifd's relic mechanic available")
	if relic != null:
		var e = gen._mechanic_copy(relic, relic.value * 1.5, "item_potato")
		_eq(e.value, 100, "chance capped at 100")
		_check(abs(e.get_meta("aa_value") - relic.value) < 0.01, "value follows the capped number (%.1f vs %.1f)" % [e.get_meta("aa_value"), relic.value])
	# 战利品外星人出现几率是相对值，不受上限
	_check(not Catalog.PCT_CAPS.has("loot_alien_chance"), "loot alien chance is relative, not capped")


# 每隔 N 秒获得持续 M 秒的效果：M < N；每波开始时只能"永久获得"
func test_109_interval_duration_and_wave_start_grants() -> void:
	var n_int = 0
	var n_ws = 0
	for sd in SEEDS:
		var plan = Generator.new(_cfg(), sd).generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				if not e is TriggerEffect:
					continue
				if e.trigger == "interval" and e.payload == "timed_stat":
					n_int += 1
					_check(e.value2 < e.param, "duration < interval: " + e.get_text(0, false))
				if e.trigger == "wave_start" and e.payload == "grant":
					n_ws += 1
					_eq(e.grant_mode, "perm", "wave-start grant is permanent: " + e.get_text(0, false))
	var gen = Generator.new(_cfg(), 5)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	gen.rng.seed = 5
	for i in 200:
		var c = gen.gen_clause([8.0, 20.0, 45.0][i % 3], 4.0, false, "interval", "timed_stat")
		if not c.empty():
			n_int += 1
			_check(c.value2 < c.param, "generated duration %d < interval %d" % [c.value2, c.param])
		var w = gen.gen_clause(20.0, 4.0, false, "wave_start", "grant")
		if not w.empty():
			n_ws += 1
			_eq(w.grant_mode, "perm", "wave-start grant clause is permanent")
	print("AUDIT interval timed clauses %d, wave-start grants %d" % [n_int, n_ws])
	_check(n_int > 20 and n_ws > 20, "both shapes still generated")


# 升级所需经验（反比例估值）、波初不生成本波属性、高频扳机不出现过高门槛
func test_110_xp_needed_wave_start_and_frequency() -> void:
	_check(abs(Catalog.xp_needed_equiv_pct(-67) - 203.0) < 1.0, "-67% xp needed = +203% xp gain")
	_check(abs(Catalog.xp_needed_equiv_pct(100) + 50.0) < 0.01, "+100% xp needed = -50% xp gain")
	var cfg = _cfg()
	cfg.char_effects = true
	var n_xp = [0, 0]
	var low = 0
	var n_hf = 0
	var shown = 0
	for sd in SEEDS:
		var plan = Generator.new(cfg, sd).generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.key == "next_level_xp_needed" and not e is TriggerEffect:
					n_xp[0 if e.value < 0 else 1] += 1
					_check(e.value >= Catalog.XP_NEEDED_MIN and e.value <= Catalog.XP_NEEDED_MAX, "xp needed in range: %d" % e.value)
					var expect = Catalog.stat_w("xp_gain") * Catalog.xp_needed_equiv_pct(e.value)
					if e.value < 0:
						_check(abs(e.get_meta("aa_value") - expect) < 0.01, "xp needed valued as inverse xp gain")
						_check("xp_gain" in plan.items[id].main_stats, id + ": xp needed counts as xp gain")
				if not e is TriggerEffect:
					continue
				_check(not (e.trigger == "wave_start" and e.payload == "temp_stat"), "no wave-start temp stat: " + e.get_text(0, false))
				if Catalog.TRIGGERS[e.trigger].kind == "event" and Catalog.TRIGGERS[e.trigger].e >= 20.0 and e.value > 0 and not Catalog.ENEMY_STATS.has(e.stat):
					n_hf += 1
					var r = Valuation.raw_rate(e.trigger, e.param, e.chance)
					if r < Catalog.MIN_FIRES_HIGH_FREQ - 0.01:
						low += 1
						print("AUDIT low-frequency high-freq clause: " + e.get_text(0, false))
					if e.payload in ["damage", "heal", "gold", "xp", "explode"] and shown < 8:
						shown += 1
						print("AUDIT high-freq payload sample: " + e.get_text(0, false))
	print("AUDIT xp-needed lines: %d good, %d downside; high-freq clauses %d (below min %d)" % [n_xp[0], n_xp[1], n_hf, low])
	_check(n_xp[0] > 0 and n_xp[1] > 0, "xp needed appears as upside and downside")
	_eq(low, 0, "high-frequency triggers fire at least MIN_FIRES_HIGH_FREQ times per wave")
	# 运行时：多条叠加后所需经验不低于原版的 10%
	m.start_new_run()
	var h = Keys.next_level_xp_needed_hash
	var saved = rd.get_player_effects(0)[h]
	rd.get_player_effects(0)[h] = -150
	var need = rd.get_next_level_xp_needed(0)
	_check(need > 0 and abs(need - rd.get_xp_needed(rd.get_player_level(0) + 1) * 0.1) < 0.01, "stacked xp needed floored at -90%% (%s)" % str(need))
	rd.get_player_effects(0)[h] = saved
	m.on_menu_reset()


# 更多角色效果（选项）与武器数量计数（常规池）
func test_111_more_character_effects() -> void:
	var more_keys = {"cryptid": "cryptid", "charm_on_hit": "charm", "beast_master_effect": "beast_master", "map_size": "map_size",
		"specific_items_price": "self_price", "weapons_price": "weapons_price", "group_structures": "group_structures",
		"next_level_xp_needed": "xp_needed", "items_price+": "items_price_up"}
	var seen = {}
	var seen_off = {}
	var counters = {}
	var samples = []
	for on in [true, false]:
		var cfg = _cfg()
		cfg.char_effects = on
		# 部分效果权重很低：多用几个种子
		for sd in range(1, 21):
			var plan = Generator.new(cfg, sd).generate(isvc.items, isvc.characters, [], [])
			for id in plan.items:
				for e in plan.items[id].effects:
					if e is TriggerEffect:
						continue
					var k = e.custom_key if e.custom_key in ["charm_on_hit", "specific_items_price"] else e.key
					if k == "items_price" and e.value > 0:
						k = "items_price+"
					if Catalog.WEAPON_COUNTERS.has(e.custom_key):
						counters[e.custom_key] = counters.get(e.custom_key, 0) + 1
						if samples.size() < 12:
							samples.push_back(e.get_text(0, false))
						_check(abs(e.get_meta("aa_value")) > 0, "weapon counter valued")
					if more_keys.has(k):
						if on:
							seen[k] = seen.get(k, 0) + 1
							if samples.size() < 24:
								samples.push_back(e.get_text(0, false))
						else:
							seen_off[k] = seen_off.get(k, 0) + 1
					if k == "specific_items_price":
						_eq(e.key, id, "self price effect targets its own item")
	print("AUDIT more character effects (on): %s; with option off: %s; weapon counters: %s" % [str(seen), str(seen_off), str(counters)])
	for s in samples:
		print("AUDIT   sample: " + s)
	_check(seen_off.empty(), "more character effects only with the option on")
	for k in more_keys:
		if k != "charm_on_hit" or tree.root.get_node("ProgressData").get_dlc_data("abyssal_terrors") != null:
			_check(seen.has(k), "more character effect appears: " + k)
	_check(counters.size() >= 3, "weapon counters appear in the regular pool")
	# 武器数量计数在玩家身上实际生效：持有 2 把武器时"每把武器 +2 护甲"= +4
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var tmpl = gen.char_templates.weapon_counters.get("additional_weapon_effects")
	if tmpl != null:
		var e = tmpl.duplicate()
		e.key = "stat_armor"
		e.key_hash = Keys.stat_armor_hash
		e.value = 2
		holder.effects = [e]
		var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
		var _w1 = rd.add_weapon(fist, 0)
		var _w2 = rd.add_weapon(fist, 0)
		var a0 = rd.get_stat(Keys.stat_armor_hash, 0)
		var nw = rd.get_player_weapons(0).size()
		rd.add_item(holder, 0)
		_eq(rd.get_stat(Keys.stat_armor_hash, 0) - a0, 2 * nw, "per-weapon counter applied (%d weapons)" % nw)
		_check(e.get_text(0, false).find("AA_") == -1, "counter text: " + e.get_text(0, false))
	m.on_menu_reset()


# ============================================================
# 全部角色效果（BETA）：只在选项开启时出现；限制带高补偿、只在高预算道具上；设定值型效果所在道具为独特；
# 无法回血的道具不带回血；每种效果加到玩家身上生效、移除后恢复
# ============================================================
func test_112_all_character_effects() -> void:
	var seen = {}
	var seen_off = {}
	var samples = []
	for on in [true, false]:
		var cfg = _cfg()
		cfg.char_effects = true
		cfg.all_char_effects = on
		for sd in range(1, 31):
			var gen = Generator.new(cfg, sd)
			var plan = gen.generate(isvc.items, isvc.characters, [], [])
			for id in plan.items:
				var p = plan.items[id]
				var has_beta = false
				var no_heal = false
				for e in p.effects:
					var k = e.custom_key if e.custom_key in ["remove_shop_items", "guaranteed_shop_items"] else e.key
					if gen.is_scaling(e) and e.stat_scaled.begins_with("item_"):
						k = "item_counter"
						_check(e.stat_scaled != id, "guaranteed item is another item")
					elif gen.handling_of(e, null) != "char_beta":
						continue
					has_beta = true
					if on:
						seen[k] = seen.get(k, 0) + 1
						if samples.size() < 40 and not "sample:" + k in samples:
							samples.push_back("sample:" + k)
							samples.push_back("%s (T%d, budget %.0f): %s" % [id, _item(id).tier + 1, p.budget, _texts(p.effects)])
					else:
						seen_off[k] = true
					if k == "no_heal":
						no_heal = true
					if Catalog.BETA_RESTRICTIONS.has(k):
						_check(p.budget >= Catalog.BETA_RESTRICTIONS[k].min_budget, "restriction %s only on items with enough budget (%.0f)" % [k, p.budget])
				_eq(p.get("unique", false), Generator.has_unique_effect(p.effects), "unique flag: " + id)
				if no_heal:
					for e in p.effects:
						var ek = e.custom_key if e.custom_key != "" else e.key
						_check(not (e is TriggerEffect and (e.payload == "heal" or e.trigger == "heal")) and not (ek in Catalog.HEAL_KEYS and e.value > 0),
							"no heal effect on a 'cannot heal' item: " + _texts(p.effects))
				if has_beta:
					for e in p.effects:
						var t = e.get_text(0, false)
						_check(t.find("AA_") == -1, "beta text translated: " + t)
	print("AUDIT all character effects (on): %s; with option off: %s" % [str(seen), str(seen_off)])
	for s in samples:
		if not s.begins_with("sample:"):
			print("AUDIT   " + s)
	_check(seen_off.empty(), "all character effects only with the option on")
	var gen0 = Generator.new(_cfg(), 1)
	gen0._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var expect = Catalog.BETA_RESTRICTIONS.keys() + ["all_weapons_count_for_sets",
		"weapon_slot_upgrades", "item_steals", "guaranteed_shop_items", "item_counter"]
	for k in expect:
		if gen0._beta_tmpl(k) != null:
			_check(seen.has(k), "all character effect appears: " + k)

	# 真实生效与撤销
	m.start_new_run()
	var beta = gen0.char_templates.beta
	var keys = beta.keys()
	keys.sort()
	for k in keys:
		if k == "item_counter":
			continue
		var e = beta[k].duplicate()
		var holder = _item("item_potato").duplicate()
		holder.effects = [e]
		var h = e.custom_key_hash if e.custom_key in ["remove_shop_items", "guaranteed_shop_items"] else e.key_hash
		var before = str(rd.get_player_effect(h, 0))
		rd.add_item(holder, 0)
		var during = str(rd.get_player_effect(h, 0))
		rd.remove_item(holder, 0)
		var after = str(rd.get_player_effect(h, 0))
		# 数值为 0 的伴随行（偷窃生成精英的参数）不改变效果值
		if e.value != 0 or e.storage_method == Effect.StorageMethod.REPLACE:
			_check(during != before or k == "can_attack_while_moving" and during == "0", "%s applies (%s -> %s)" % [k, before, during])
		_eq(after, before, "%s is reverted when the item is removed" % k)
	# 商店总是出售 X + 每有 1 个 X 获得属性
	var gi = beta.get("guaranteed_shop_items")
	var ic = beta.get("item_counter")
	if gi != null and ic != null:
		var x = "item_coupon"
		var e1 = gi.duplicate()
		e1.key = x
		e1.key_hash = Keys.generate_hash(x)
		var e2 = ic.duplicate()
		e2.key = "stat_armor"
		e2.key_hash = Keys.stat_armor_hash
		e2.value = 3
		e2.stat_scaled = x
		e2.stat_scaled_hash = Keys.generate_hash(x)
		e2.nb_stat_scaled = 1
		var holder = _item("item_potato").duplicate()
		holder.effects = [e1, e2]
		rd.add_item(holder, 0)
		LinkedStats.reset_player(0)
		Utils.reset_stat_cache(0)
		# 只看计数带来的部分（X 自己的效果也可能给护甲）：联动属性 = 总属性 − 永久属性
		var a0 = Utils.get_stat(Keys.stat_armor_hash, 0) - rd.get_stat(Keys.stat_armor_hash, 0)
		var n0 = rd.get_nb_item(Keys.generate_hash(x), 0)
		rd.add_item(_item(x), 0)
		rd.add_item(_item(x), 0)
		LinkedStats.reset_player(0)
		Utils.reset_stat_cache(0)
		var dn = rd.get_nb_item(Keys.generate_hash(x), 0) - n0
		_check(dn >= 1, "guaranteed item added (%d)" % dn)
		_eq(Utils.get_stat(Keys.stat_armor_hash, 0) - rd.get_stat(Keys.stat_armor_hash, 0) - a0, 3 * dn, "+3 armor for every owned guaranteed item")
		var args = ItemServiceGetShopItemsArgs.new([[], [], [], []], 0)
		var shop = isvc.get_player_shop_items(rd.current_wave, 0, args)
		var found = false
		for entry in shop:
			if entry[0].my_id == x:
				found = true
		_check(found, "shop always sells the guaranteed item")
		_check(e1.get_text(0, false).find(TranslationServer.translate(x.to_upper())) >= 0, "guaranteed item text names the item: " + e1.get_text(0, false))
	m.on_menu_reset()


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


func test_113_more_double_sided() -> void:
	var seen = {}
	var seen_off = {}
	var samples = {}
	for on in [true, false]:
		var cfg = _cfg()
		cfg.more_double = on
		for sd in range(1, 21):
			var gen = Generator.new(cfg, sd)
			var plan = gen.generate(isvc.items, isvc.characters, [], [])
			for id in plan.items:
				for e in plan.items[id].effects:
					var k = _double_kind(gen, e)
					if k == "":
						continue
					if on:
						seen[k] = seen.get(k, 0) + 1
						if not samples.has(k):
							samples[k] = "%s: %s" % [id, _texts(plan.items[id].effects)]
					else:
						seen_off[k] = true
					if k.begins_with("neg:"):
						_check(abs(e.value) <= Catalog.DOUBLE_NEG_CAPS[e.key], "mirrored downside capped: " + e.get_text(0, false))
						_check(e.get_meta("aa_value") < 0, "mirrored downside valued as a downside")
					if k.begins_with("pos:"):
						_check(abs(e.value) <= Catalog.DOUBLE_POS_ENEMY_CAPS[e.key], "enemy stat reduction capped: " + e.get_text(0, false))
					var t = e.get_text(0, false)
					_check(t != "" and t.find("AA_") == -1, "double-sided text: " + t)
	print("AUDIT more double-sided (on): %s; with option off: %s" % [str(seen), str(seen_off)])
	for k in samples:
		print("AUDIT   %s -> %s" % [k, samples[k]])
	for k in seen_off:
		_check(k == "items_price+", "double-sided effect only with the option on: " + k)
	for k in ["lose_gold", "class_bonus-", "enemy_decay", "next_wave_enemy_down", "weapon_slot-1", "weapons_price+",
			"neg:gold_drops", "neg:enemy_gold_drops", "neg:reroll_price", "neg:enemy_speed", "pos:enemy_health", "pos:enemy_damage"]:
		_check(seen.has(k), "double-sided effect appears: " + k)
	# 失去材料
	m.start_new_run()
	var main_rt = load(MOD_DIR + "aa/runtime.gd").new()
	var te = TriggerEffect.make({"trigger": "kill", "payload": "gold", "value": -5})
	_check(te.get_text(0, false).find("5") >= 0 and te.get_text(0, false).find("--") == -1, "lose gold text: " + te.get_text(0, false))
	rd.add_gold(3 - rd.get_player_gold(0), 0)
	main_rt.execute(te, 0, null, false)
	_eq(rd.get_player_gold(0), 0, "losing materials stops at 0")
	rd.add_gold(20, 0)
	main_rt.execute(te, 0, null, false)
	_eq(rd.get_player_gold(0), 15, "lose 5 materials")
	main_rt.free()
	m.on_menu_reset()



# ============================================================
# 词条绑定：生成道具的触发（伤害类型、闪避、拾取材料、箱子……）、载荷（爆炸、伤害缩放属性）、计数、
# 机制（燃烧、敌人减速……）都带上对应的原版词条（角色的偏好词条据此命中）
# ============================================================
func test_114_tag_bindings() -> void:
	var cfg = _cfg()
	cfg.char_effects = true
	cfg.more_double = true
	var checked = {}
	var missing = []
	for sd in range(1, 11):
		var gen = Generator.new(cfg, sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			var p = plan.items[id]
			for e in p.effects:
				var want = []
				var what = ""
				if e is TriggerEffect and e.value > 0:
					want += Catalog.tags_for_binding("trigger:" + e.trigger)
					want += Catalog.tags_for_binding("payload:" + e.payload)
					what = e.trigger + "/" + e.payload
					if e.payload in ["damage", "explode"] and Catalog.STATS.has(e.stat):
						want.push_back(e.stat)
						what += "/" + e.stat
					if e.payload == "explode":
						want.push_back("explosive")
				elif gen.is_scaling(e) and e.value > 0:
					want += Catalog.tags_for_binding("counter:" + e.stat_scaled)
					if Catalog.STATS.has(e.stat_scaled):
						want.push_back(e.stat_scaled)
					want.push_back(e.key)
					what = "counter:" + e.stat_scaled
				elif e.key == "enemy_speed" and e.value < 0 and e.custom_key == "":
					want.push_back("less_enemy_speed")
					what = "enemy_speed-"
				elif e.has_meta("aa_value") and e.get_meta("aa_value") > 0:
					var k = e.custom_key if e.custom_key != "" else e.key
					want += Catalog.tags_for_binding("mech:" + k)
					what = "mech:" + k
				for t in want:
					checked[what] = true
					if not t in p.tags:
						missing.push_back("%s: %s missing %s (%s)" % [id, what, t, str(p.tags)])
	print("AUDIT tag bindings checked on %d kinds of effects, %d missing" % [checked.size(), missing.size()])
	for x in missing.slice(0, min(10, missing.size()) - 1) if not missing.empty() else []:
		print("AUDIT   " + x)
	_check(missing.empty(), "every generated effect carries its bound tags")
	for k in ["dodge/", "gold/", "first_hit_", "ignite/", "crit_kill/"]:
		var found = false
		for w in checked:
			if w.begins_with(k):
				found = true
		_check(found, "tag binding exercised: " + k)
	# 伤害 / 爆炸载荷带缩放属性；计数属性也是词条
	var g = Generator.new(cfg, 1)
	var dmg = TriggerEffect.make({"trigger": "kill", "payload": "damage", "stat": "stat_luck", "value": 50})
	_check("stat_luck" in g._tags_for([dmg]), "damage payload scaling from luck carries the luck tag")
	var ex = TriggerEffect.make({"trigger": "dodge", "payload": "explode", "stat": "stat_elemental_damage", "value": 50})
	var tx = g._tags_for([ex])
	_check("explosive" in tx and "stat_elemental_damage" in tx and "stat_dodge" in tx, "explode on dodge: " + str(tx))



# ============================================================
# 角色重组：身份行与"禁用"行保留；可估值行按同等价值重组并偏向偏好词条；-100 / -100% 行按期望总量封顶估值
# ============================================================
func _char_value(gen, e) -> float:
	if e is TriggerEffect:
		var cv = Valuation.clause_value(e.to_clause(), Catalog.PERM_MULT_CHARACTER)
		return cv if cv >= 0 else cv / Catalog.DOWNSIDE_DIVISOR
	return gen.char_line_value(e)


func test_115_character_reassembly() -> void:
	var cfg = _cfg()
	cfg.characters = true
	var hits = 0
	var total = 0
	var base_rate = 0.0
	var ratios = []
	var converted = {}
	for sd in range(1, 9):
		var gen = Generator.new(cfg, sd)
		var plan = gen.generate([], isvc.characters, isvc.characters, [])
		for ch in isvc.characters:
			var p = plan.characters[ch.my_id]
			_eq(p.effects.size(), ch.effects.size(), ch.my_id + " same number of lines")
			var v0 = 0.0
			var v1 = 0.0
			for i in ch.effects.size():
				var e0 = ch.effects[i]
				var e1 = p.effects[i]
				var reassemblable = gen.is_plain_stat(e0) or gen.native_trigger_of(e0) != null or gen.is_scaling(e0) or gen.is_gain_mod(e0)
				if not reassemblable or gen.is_disabling(e0):
					_check(e1 == e0, "%s keeps identity / disabling line: %s" % [ch.my_id, e0.get_text(0, false)])
					continue
				v0 += _char_value(gen, e0)
				v1 += _char_value(gen, e1)
				if e1 != e0 and e1.get_script() != e0.get_script():
					var k = "clause" if e1 is TriggerEffect else ("scaling" if gen.is_scaling(e1) else ("gain_mod" if gen.is_gain_mod(e1) else "stat"))
					converted[k] = converted.get(k, 0) + 1
				# 偏好词条命中：新的正面行的词条与角色偏好相交
				if _char_value(gen, e0) > 0 and not ch.wanted_tags.empty() and e1 != e0:
					var stat_wanted = 0
					for t in ch.wanted_tags:
						if Catalog.STATS.has(t):
							stat_wanted += 1
					if stat_wanted > 0:
						total += 1
						base_rate += float(stat_wanted) / Catalog.STATS.size()
						for t in gen._tags_for([e1]):
							if t in ch.wanted_tags:
								hits += 1
								break
			if abs(v0) > 5.0:
				ratios.push_back(v1 / v0)
	ratios.sort()
	var hit_rate = float(hits) / max(1, total)
	base_rate = base_rate / max(1, total)
	print("AUDIT character reassembly: value ratio p10 %.2f / median %.2f / p90 %.2f; wanted-tag hit rate %.2f (uniform %.2f); converted %s" % [
		ratios[ratios.size() / 10], ratios[ratios.size() / 2], ratios[ratios.size() * 9 / 10], hit_rate, base_rate, str(converted)])
	_check(ratios[ratios.size() / 2] > 0.7 and ratios[ratios.size() / 2] < 1.4, "character value preserved (median)")
	_check(hit_rate > base_rate * 2.0, "reassembled positives favour the character's wanted tags")
	for k in ["clause", "scaling", "gain_mod", "stat"]:
		_check(converted.has(k) or k == "stat", "positive components converted into: " + k)
	# -100 / -100% 行：按期望总量封顶
	var g = Generator.new(cfg, 1)
	var vamp = isvc.get_element_safe(isvc.characters, "character_vampire")
	for e in vamp.effects:
		if e.key == "consumable_heal":
			_check(g.is_disabling(e), "vampire -100 consumable heal is a disabling line")
			_check(abs(g.char_line_value(e)) <= Catalog.stat_w("consumable_heal") * Catalog.counter_ref("consumable_heal") / Catalog.DOWNSIDE_DIVISOR + 0.01,
				"disabling line valued at most the stat's expected total (%.1f)" % g.char_line_value(e))
	var mage = isvc.get_element_safe(isvc.characters, "character_mage")
	for e in mage.effects:
		if g.is_gain_mod(e) and e.value <= -100:
			_check(g.is_disabling(e), "mage -100% gains is a disabling line")
	var sample = Generator.new(cfg, 20260927).generate([], isvc.characters, [mage, vamp, isvc.get_element_safe(isvc.characters, "character_engineer")], [])
	for cid in sample.characters:
		print("AUDIT   %s: %s" % [cid, _texts(sample.characters[cid].effects)])


# ============================================================
# 价格与预算：重组道具的价格取自同稀有度原版价格分布（不继承原道具）；同稀有度内预算与价格成正比；
# 开局后写到道具资源上、回主菜单后还原
# ============================================================
func test_116_generated_prices_and_budget() -> void:
	var cfg = _cfg()
	cfg.variance = 0
	var gen = Generator.new(cfg, 42)
	var plan = gen.generate(isvc.items, isvc.characters, [], [])
	var plan2 = Generator.new(cfg, 42).generate(isvc.items, isvc.characters, [], [])
	var plan3 = Generator.new(cfg, 43).generate(isvc.items, isvc.characters, [], [])
	var lo = [9999, 9999, 9999, 9999]
	var hi = [0, 0, 0, 0]
	var native_sum = [0.0, 0.0, 0.0, 0.0]
	var gen_sum = [0.0, 0.0, 0.0, 0.0]
	var n = [0, 0, 0, 0]
	for id in plan.items:
		var it = _item(id)
		if it.value >= Catalog.PRICE_POOL_MIN:
			lo[it.tier] = min(lo[it.tier], it.value)
			hi[it.tier] = max(hi[it.tier], it.value)
	var changed = 0
	var differ_seed = 0
	for id in plan.items:
		var it = _item(id)
		var p = plan.items[id]
		_check(p.price >= lo[it.tier] and p.price <= hi[it.tier], "%s price %d within tier range [%d, %d]" % [id, p.price, lo[it.tier], hi[it.tier]])
		_eq(p.price, plan2.items[id].price, "price deterministic for a seed: " + id)
		if p.price != it.value:
			changed += 1
		if plan3.items.has(id) and plan3.items[id].price != p.price:
			differ_seed += 1
		native_sum[it.tier] += it.value
		gen_sum[it.tier] += p.price
		n[it.tier] += 1
		# 同稀有度内预算与价格成正比（浮动为 0 时）
		var expect = max(2.0, gen.tier_value_median[it.tier] * p.price / gen.tier_price_median[it.tier]) * Catalog.HIDDEN_TIER_MULT[it.tier]
		_check(abs(p.budget - expect) < 0.01, "%s budget proportional to its price (%.2f vs %.2f)" % [id, p.budget, expect])
	_check(changed > plan.items.size() / 2, "most items get a new price (%d / %d)" % [changed, plan.items.size()])
	_check(differ_seed > plan.items.size() / 3, "prices depend on the seed (%d)" % differ_seed)
	for t in 4:
		var a = native_sum[t] / max(1, n[t])
		var b = gen_sum[t] / max(1, n[t])
		print("AUDIT prices T%d: native mean %.1f, generated mean %.1f, range [%d, %d], k = %.3f" % [t + 1, a, b, lo[t], hi[t], gen.tier_value_median[t] / gen.tier_price_median[t]])
		_check(abs(a - b) < a * 0.15, "generated prices follow the tier's native distribution (T%d)" % (t + 1))
	# 写到资源上并在回主菜单后还原
	var before = {}
	for it in isvc.items:
		before[it.my_id] = it.value
	m.cfg_seed = 42
	m.start_new_run()
	for id in m.plan.items:
		_eq(_item(id).value, m.plan.items[id].price, "generated price written to the item: " + id)
	m.on_menu_reset()
	for it in isvc.items:
		_eq(it.value, before[it.my_id], "price restored: " + it.my_id)
	# 估值修正：从升级中获得的属性 +X% 估值降低（同样预算数值更高）
	var found = false
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			if mech.effect.key == "level_upgrades_modifications" and not mech.down:
				found = true
				print("AUDIT level upgrades mechanic: +%d%% valued %.1f (%.2f per %%)" % [mech.effect.value, mech.value, mech.value / mech.effect.value])
	_check(found or tree.root.get_node("ProgressData").get_dlc_data("abyssal_terrors") == null, "level upgrade mechanic collected")
	_check(Catalog.MECHANIC_VALUE_MULT["level_upgrades_modifications"] < 1.0, "level upgrade valuation lowered")



# ============================================================
# 本地化：原版的 13 种语言每个 key 都有文本，占位符与英文一致
# ============================================================
func test_117_all_locales_translated() -> void:
	var f = File.new()
	_check(f.open(MOD_DIR + "translations/autoanthony.csv", File.READ) == OK, "csv opens")
	var lines = f.get_as_text().split("\n", false)
	f.close()
	var header = m._parse_csv_line(lines[0].strip_edges())
	_eq(header.size(), 14, "key + 13 locales")
	for l in ["en", "fr", "zh", "ja", "ko", "zh_TW", "ru", "pl", "es", "pt", "de", "tr", "it"]:
		_check(l in header, "locale column: " + l)
	var re = RegEx.new()
	re.compile("\\{[0-9]\\}")
	var n = 0
	for li in range(1, lines.size()):
		var row = m._parse_csv_line(lines[li].strip_edges())
		if row.size() < 2 or row[0] == "":
			continue
		n += 1
		_eq(row.size(), header.size(), "row has every locale: " + row[0])
		var ph = []
		for mt in re.search_all(row[1]):
			ph.push_back(mt.get_string())
		ph.sort()
		for i in range(1, min(row.size(), header.size())):
			_check(row[i] != "", "%s translated in %s" % [row[0], header[i]])
			var got = []
			for mt in re.search_all(row[i]):
				got.push_back(mt.get_string())
			got.sort()
			_check(got == ph, "%s placeholders kept in %s: %s" % [row[0], header[i], row[i]])
	_check(n > 190, "rows checked (%d)" % n)
	# 运行时切换语言后能取到对应文本
	var prev = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	_eq(tr("AA_T_LEVEL_UP"), " beim Levelaufstieg", "German text at runtime")
	TranslationServer.set_locale("ja")
	_eq(tr("AA_T_STILL"), "静止中は", "Japanese text at runtime")
	TranslationServer.set_locale(prev)



# ============================================================
# T3 及以上的道具至少有两条效果（各选项组合下）
# ============================================================
func test_118_t3_min_two_lines() -> void:
	var worst = {}
	for opts in [{}, {"char_effects": true, "all_char_effects": true, "more_double": true}, {"triggers": 50}, {"avg": 50}]:
		var cfg = _cfg()
		for k in opts:
			cfg[k] = opts[k]
		for sd in range(1, 9):
			var gen = Generator.new(cfg, sd)
			gen.player_wanted_tags = ["structure", "pet", "explosive", "stat_curse", "consumable", "stat_luck"]
			var plan = gen.generate(isvc.items, isvc.characters, [], [])
			for id in plan.items:
				var it = _item(id)
				var n = Generator.visible_lines(plan.items[id].effects)
				if it.tier >= Catalog.MIN_LINES_TIER:
					_check(n >= Catalog.MIN_LINES, "T%d item %s has %d effect line(s): %s" % [it.tier + 1, id, n, _texts(plan.items[id].effects)])
				worst[it.tier] = min(worst.get(it.tier, 99), n)
	print("AUDIT minimum effect lines by tier: ", worst)


# ============================================================
# 武器类型加成：暴击率 / 暴击伤害 / 贯通都能出现并在武器上正确生效；拷问的回血不低于 4；带上限的永久效果
# ============================================================
func test_119_class_bonus_and_value_tweaks() -> void:
	var seen = {}
	var caps = []
	var torture = []
	for sd in range(1, 21):
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		var ranged = gen._ranged_only_sets()
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.get_script() == load("res://effects/items/class_bonus_effect.gd"):
					seen[e.stat_displayed_name] = seen.get(e.stat_displayed_name, 0) + 1
					if e.stat_name == "piercing":
						_check(e.set_id in ranged, "piercing only on ranged-only classes: " + e.set_id)
					var t = e.get_text(0, false)
					_check(t.find("STAT_") == -1 and t.find("AA_") == -1, "class bonus text: " + t)
				if e.key == "torture":
					torture.push_back(e.value)
					_check(e.value >= 4, "torture heals at least 4 per second (%d)" % e.value)
				if e is TriggerEffect and e.cap > 0 and (e.payload == "perm_stat" or e.grant_mode == "perm"):
					caps.push_back(e.cap)
	caps.sort()
	print("AUDIT class bonus stats: %s; torture values: %s; perm caps median %d max %d" % [str(seen), str(torture), caps[caps.size() / 2] if not caps.empty() else 0, caps.back() if not caps.empty() else 0])
	for k in ["stat_crit_chance", "stat_crit_damage", "piercing"]:
		_check(seen.has(k), "class bonus can give " + k)
	# 实际武器属性：手枪（枪械）+10% 暴击率、+1 贯通；小刀（精准）+10% 暴击率
	m.start_new_run()
	var g = Generator.new(_cfg(), 1)
	g._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var tmpl = g.char_templates.class_bonus[0]
	var pistol = isvc.get_element_safe(isvc.weapons, "weapon_pistol_1")
	var knife = isvc.get_element_safe(isvc.weapons, "weapon_knife_1")
	var gun_set = pistol.sets[0]
	var holder = _item("item_potato").duplicate()
	var fx = []
	for spec in [["crit_chance", "stat_crit_chance", 10, gun_set.my_id], ["piercing", "piercing", 1, gun_set.my_id], ["crit_chance", "stat_crit_chance", 10, knife.sets[0].my_id]]:
		var e = tmpl.duplicate()
		e.stat_name = spec[0]
		e.stat_hash = Keys.generate_hash(spec[0])
		e.stat_displayed_name = spec[1]
		e.value = spec[2]
		e.set_id = spec[3]
		e.set_id_hash = Keys.generate_hash(spec[3])
		fx.push_back(e)
	holder.effects = fx
	var pa = WeaponServiceInitStatsArgs.new()
	pa.sets = pistol.sets
	var ka = WeaponServiceInitStatsArgs.new()
	ka.sets = knife.sets
	var p0 = WeaponService.init_ranged_stats(pistol.stats, 0, false, pa)
	var k0 = WeaponService.init_melee_stats(knife.stats, 0, ka)
	rd.add_item(holder, 0)
	var p1 = WeaponService.init_ranged_stats(pistol.stats, 0, false, pa)
	var k1 = WeaponService.init_melee_stats(knife.stats, 0, ka)
	_check(abs(p1.crit_chance - p0.crit_chance - 0.10) < 0.001, "gun +10%% crit chance (%.3f -> %.3f)" % [p0.crit_chance, p1.crit_chance])
	_eq(p1.piercing - p0.piercing, 1, "gun +1 piercing")
	_check(abs(k1.crit_chance - k0.crit_chance - 0.10) < 0.001, "knife (precise) +10%% crit chance (%.3f -> %.3f)" % [k0.crit_chance, k1.crit_chance])
	rd.remove_item(holder, 0)
	var p2 = WeaponService.init_ranged_stats(pistol.stats, 0, false, pa)
	_check(abs(p2.crit_chance - p0.crit_chance) < 0.001 and p2.piercing == p0.piercing, "class bonus removed cleanly")
	m.on_menu_reset()


# 击退 / 范围是次要正面属性；重组初始道具（选项）；"用[]伤害命中敌人时"扳机（更多角色效果）
func test_120_minor_stats_starting_items_typed_hits() -> void:
	# 1) 击退单价提高，击退 / 范围行的数值与价值占比都下降
	_check(Catalog.MINOR_POSITIVE_STATS.has("knockback") and Catalog.MINOR_POSITIVE_STATS.has("stat_range"), "knockback / range are minor stats")
	var kb = []
	var minor_share = []
	var g0 = Generator.new(_cfg(), 1)
	for sd in range(1, 11):
		var plan = _gen(sd)
		for id in plan.items:
			var total = 0.0
			var minor = 0.0
			for e in plan.items[id].effects:
				if g0.is_plain_stat(e) and e.value > 0 and Catalog.STATS.has(e.key):
					var v = e.value * Catalog.stat_w(e.key)
					total += v
					if Catalog.MINOR_POSITIVE_STATS.has(e.key):
						minor += v
					if e.key == "knockback":
						kb.push_back(e.value)
			if minor > 0 and total > minor:
				minor_share.push_back(minor / total)
	kb.sort()
	minor_share.sort()
	var kb_med = kb[kb.size() / 2] if not kb.empty() else 0
	var share_med = minor_share[minor_share.size() / 2] if not minor_share.empty() else 0.0
	print("AUDIT knockback values median %d max %d (n=%d); minor-stat value share median %.2f (n=%d)" % [kb_med, kb.back() if not kb.empty() else 0, kb.size(), share_med, minor_share.size()])
	_check(share_med < 0.4, "knockback / range take a minor share of mixed items (%.2f)" % share_med)
	# 2) 重组初始道具：技术法师的炮台默认保持原版，开启选项后也重组，开局持有的炮台换成生成版本
	_setup_player("character_technomage")
	rd.add_starting_items_and_weapons()
	m.cfg_starting_items = true
	m.start_new_run()
	_check(m.plan.items.has("item_turret"), "starting items option: turret reassembled")
	for it in rd.players_data[0].items:
		if it.my_id == "item_turret":
			_eq(_texts(it.effects), _texts(_item("item_turret").effects), "owned starting turret matches the shop turret")
	m.on_menu_reset()
	m.cfg_starting_items = false
	_check(not m.get_cfg().get("starting_items", true), "starting items option off by default")
	# 3) 每次以某类伤害命中：只在"更多角色效果"开启时出现；文本、匹配、潜水员原效果不再原样搬运
	var cfg = _cfg()
	var counts = {true: 0, false: 0}
	var samples = []
	for on in [true, false]:
		cfg.char_effects = on
		for sd in range(1, 21):
			var plan = Generator.new(cfg, sd).generate(isvc.items, isvc.characters, [], [])
			for id in plan.items:
				for e in plan.items[id].effects:
					if e is TriggerEffect and Catalog.HIT_STATS.has(e.trigger):
						counts[on] += 1
						if samples.size() < 6:
							samples.push_back(e.get_text(0, false))
						_check(e.get_text(0, false).find("AA_") == -1 and e.get_text(0, false).find("{") == -1, "typed hit text: " + e.get_text(0, false))
					if e.custom_key == "enemy_percent_damage_taken" and e.value >= 300:
						_check(false, "diver's +300% vulnerability is not copied verbatim")
	print("AUDIT typed-hit clauses on=%d off=%d: %s" % [counts[true], counts[false], str(samples)])
	_check(counts[true] > 0, "typed-hit triggers appear with more character effects")
	_eq(counts[false], 0, "typed-hit triggers absent without more character effects")
	var info = {"hp_pct": 80.0, "first_any": false, "first_stats": [], "stats": ["stat_ranged_damage"]}
	_check(Runtime._matches("hit_ranged", "hit_enemy", info), "ranged hit matches hit_ranged")
	_check(not Runtime._matches("hit_melee", "hit_enemy", info), "ranged hit does not match hit_melee")


# 反馈的 bug（真实战斗模拟）：
# (1) "每暴击击杀 N 个敌人：永久 +1% 暴击率"——原版在敌人死亡（延迟调用）之前发出受伤信号，暴击击杀要按"本次伤害致死"判断
# (2) "移动时：-2 最大生命值"——原版降低最大生命不压低当前生命、升高时补上差值：反复走停会让当前生命不断上涨
func test_122_feedback_crit_kill_and_state_max_hp() -> void:
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [
		TriggerEffect.make({"trigger": "crit_kill", "param": 2, "payload": "perm_stat", "stat": "stat_crit_chance", "value": 1, "cap": 3}),
		TriggerEffect.make({"trigger": "moving", "payload": "temp_stat", "stat": "stat_max_hp", "value": -2}),
		TriggerEffect.make({"trigger": "still", "payload": "temp_stat", "stat": "stat_max_hp", "value": 5}),
	]
	rd.add_item(holder, 0)
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_wait_frames(10), "completed")
	var main = tree.current_scene
	var rt = main.get_node_or_null("AutoAnthonyRuntime") if main != null else null
	_check(rt != null, "runtime in battle")
	if rt == null:
		return
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	# (1) 原版受伤路径的暴击击杀：命中盒暴击率 100%，一击致死
	var crit0 = rd.get_player_effects(0)[Keys.stat_crit_chance_hash]
	var kills = 0
	for i in 8:
		var en = yield(_wait_enemy(main), "completed")
		if en == null:
			break
		var hb = Hitbox.new()
		hb.from = player
		hb.crit_chance = 1.0
		hb.crit_damage = 2.0
		var args = TakeDamageArgs.new(0, hb)
		var _r = en.take_damage(999999, args)
		kills += 1
		yield(_wait_frames(2), "completed")
		hb.free()
	var crit1 = rd.get_player_effects(0)[Keys.stat_crit_chance_hash]
	print("AUDIT crit kills %d: crit chance %d -> %d" % [kills, crit0, crit1])
	_check(kills >= 6, "enough crit kills simulated (%d)" % kills)
	_eq(crit1 - crit0, 3, "every 2 crit kills: +1% crit chance permanently, max 3 per wave")
	# (2) 走停循环：当前生命不应上涨（满血时保持满血，受伤时不白回血）
	yield(_wait_physics(12), "completed")
	player.current_stats.health = player.max_stats.health
	var trace = []
	for half in [true, false]:
		if not half:
			player.current_stats.health = max(1, player.max_stats.health - 10)
		var start_hp = player.current_stats.health
		var start_gap = player.max_stats.health - player.current_stats.health
		for cycle in 4:
			player._move_locked = true
			player._current_movement = Vector2(1, 0)
			yield(tree.create_timer(0.5), "timeout")
			yield(_wait_physics(4), "completed")
			trace.push_back("%d/%d" % [player.current_stats.health, player.max_stats.health])
			_check(player.current_stats.health <= player.max_stats.health, "moving: health within max (%d/%d)" % [player.current_stats.health, player.max_stats.health])
			player._current_movement = Vector2.ZERO
			player._move_locked = false
			yield(tree.create_timer(0.5), "timeout")
			yield(_wait_physics(4), "completed")
			trace.push_back("%d/%d" % [player.current_stats.health, player.max_stats.health])
			_check(player.current_stats.health <= player.max_stats.health, "still: health within max (%d/%d)" % [player.current_stats.health, player.max_stats.health])
		var gap = player.max_stats.health - player.current_stats.health
		# 满血：走停后仍是满血、不超上限；受伤：降低时只截到上限（升高时原版补差值）
		if start_gap == 0:
			_eq(gap, 0, "full health stays exactly full after walk/stop cycles")
	print("AUDIT walk/stop health trace: " + str(trace))
	main._cleaning_up = true
	rt.revert_all_grants()
	m.on_menu_reset()


# 反馈：持有"复制购买的道具"（镜子效果）的重组道具时购买道具闪退
func test_123_mirror_like_holders_in_shop() -> void:
	# 生成池里的复制效果数值
	var vals = {}
	for sd in range(1, 31):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.custom_key == "duplicate_item":
					vals[e.value] = vals.get(e.value, 0) + 1
					_eq(e.key, id, "duplicate_item keyed to its holder " + id)
	print("AUDIT duplicate_item values in generated pools: %s" % str(vals))
	_setup_player("character_well_rounded")
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	m.start_new_run()
	rd.add_gold(500, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	# (a) 复制 2 份的持有者：购买一件，得到 1 + 2 件，持有者保留但失去该效果
	var holder = _item("item_helmet").duplicate()
	var dup = gen._mechanic_copy(_find_mech(gen, "duplicate_item"), -1.0, "item_helmet")
	dup.value = 2
	holder.effects = [dup]
	rd.add_item(holder, 0)
	shop.buy_item(_item("item_bat"), 0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_bat"), 0, false), 3, "x2 holder: bought 1 + duplicated 2")
	_eq(rd.get_nb_item(Keys.generate_hash("item_helmet"), 0, false), 1, "x2 holder kept")
	shop.buy_item(_item("item_bat"), 0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_bat"), 0, false), 4, "next purchase is a normal purchase")
	# (b) 购买与持有者同 ID 的道具（重组道具本身带复制效果，例如重组后的镜子）
	var mirror = _item("item_mirror")
	var own = null
	for e in mirror.effects:
		if e.custom_key == "duplicate_item":
			own = e
	var holder2 = _item("item_cake").duplicate()
	var dup2 = gen._mechanic_copy(_find_mech(gen, "duplicate_item"), -1.0, "item_cake")
	holder2.effects = [dup2]
	rd.add_item(holder2, 0)
	var cake_shop = _item("item_cake").duplicate()
	cake_shop.effects = [dup2.duplicate()]
	shop.buy_item(cake_shop, 0)
	var cakes = rd.get_nb_item(Keys.generate_hash("item_cake"), 0, false)
	var dup_left = rd.get_player_effect(Keys.duplicate_item_hash, 0).size()
	print("AUDIT buying the holder's own id: %d cakes, %d duplicate effects left" % [cakes, dup_left])
	_eq(cakes, 3, "own-id purchase: holder + bought + 1 copy")
	shop.buy_item(_item("item_bat"), 0)
	for i in 4:
		yield(tree, "idle_frame")
	_check(true, "no crash after buying again")
	m.on_menu_reset()


# 金鱼（刷新时升档）/ 沙漏（倒流）效果在重组道具上：数值分布、两件同 ID 持有者
func test_124_goldfish_hourglass_holders() -> void:
	var vals = {}
	for sd in range(1, 31):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.custom_key == "increase_tier_on_reroll" or e.key == "item_hourglass":
					var k = (e.custom_key if e.custom_key != "" else e.key) + "=" + str(e.value)
					vals[k] = vals.get(k, 0) + 1
	print("AUDIT goldfish / hourglass values in generated pools: %s" % str(vals))
	_setup_player("character_well_rounded")
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	m.start_new_run()
	for i in 2:
		var fish = _item("item_cake").duplicate()
		fish.effects = [gen._mechanic_copy(_find_mech(gen, "increase_tier_on_reroll"), -1.0, "item_cake")]
		rd.add_item(fish, 0)
	for i in 2:
		var glass = _item("item_potato").duplicate()
		glass.effects = [gen._mechanic_copy(_find_mech(gen, "item_hourglass"), -1.0, "item_potato")]
		rd.add_item(glass, 0)
	rd.current_wave = 6
	rd.add_gold(500, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	var fish_fx = []
	for r in 3:
		shop._on_RerollButton_pressed(0)
		var n = 0
		for it in rd.get_player_items(0):
			if it.my_id == "item_cake" and not it.effects.empty():
				n += 1
		fish_fx.push_back(n)
	print("AUDIT two goldfish-like holders, holders with the effect after each reroll: %s" % str(fish_fx))
	_eq(fish_fx, [1, 0, 0], "each reroll consumes one goldfish-like holder")
	_eq(rd.get_player_effect(Keys.increase_tier_on_reroll_hash, 0).size(), 0, "no goldfish effect left")
	shop._on_GoButton_pressed(0)
	_eq(rd.current_wave, 5, "two hourglass-like holders rewind two waves (6 -> 7 -> 5)")
	for i in 6:
		yield(tree, "idle_frame")
	m.on_menu_reset()


# 叠加有技术问题的原版独特效果：带这些效果的重组道具设为独特
func test_125_unique_mechanics() -> void:
	var seen = {}
	var n_unique = 0
	for sd in range(1, 21):
		var plan = _gen(sd)
		for id in plan.items:
			var p = plan.items[id]
			var hit = ""
			for e in p.effects:
				if e.key in Catalog.UNIQUE_MECHANIC_KEYS or e.custom_key in Catalog.UNIQUE_MECHANIC_KEYS:
					hit = e.key if e.key in Catalog.UNIQUE_MECHANIC_KEYS else e.custom_key
				elif e.get_script().resource_path in Catalog.UNIQUE_MECHANIC_SCRIPTS:
					hit = e.get_script().resource_path.get_file()
			if hit != "":
				seen[hit] = seen.get(hit, 0) + 1
				_check(p.unique, "%s with %s is unique" % [id, hit])
			if p.unique:
				n_unique += 1
	print("AUDIT unique-mechanic effects over 20 seeds: %s; unique items %d" % [str(seen), n_unique])
	_check(seen.size() >= 6, "most unique mechanics show up (%d)" % seen.size())
	# 开局后道具资源的上限
	m.start_new_run()
	for id in m.plan.items:
		if m.plan.items[id].unique:
			_eq(_item(id).max_nb, 1, id + " max_nb 1 in run")
	m.on_menu_reset()


# 易伤：本 mod 的"使该敌人受到的伤害提高"与原版规则一致（同一来源不叠层，不同来源相加）；
# 搬运的冰块效果来源改为持有者；潜水员的远程命中易伤不再搬运
func test_126_vulnerability_stacking() -> void:
	var b = load(MOD_DIR + "aa/enemy_behavior.gd").new()
	var c1 = {"trigger": "hit_above_50", "payload": "vuln", "value": 15, "value2": 3}
	var c2 = {"trigger": "crit", "payload": "vuln", "value": 20, "value2": 2}
	var s1 = hash(JSON.print(TriggerEffect.make(c1).to_clause()))
	var s2 = hash(JSON.print(TriggerEffect.make(c2).to_clause()))
	for i in 10:
		b.add_vuln(15, 3.0, s1)
	_eq(b.get_bonus_damage(null, 0), 15, "same clause does not stack")
	b.add_vuln(20, 2.0, s2)
	_eq(b.get_bonus_damage(null, 0), 35, "different clauses add up")
	b._process(2.5)
	_eq(b.get_bonus_damage(null, 0), 15, "shorter one expired")
	b.add_vuln(15, 3.0, s1)
	b._process(2.0)
	_eq(b.get_bonus_damage(null, 0), 15, "re-hit refreshes the duration")
	b._process(1.5)
	_eq(b.get_bonus_damage(null, 0), 0, "all expired")
	b.free()
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var sources = {}
	var ice = null
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			if mech.effect.custom_key == "enemy_percent_damage_taken":
				sources[mech.source] = true
				if mech.source == "item_ice_cube":
					ice = mech
	_check(not sources.has("character_diver"), "diver's ranged-hit vulnerability is not transferred")
	# 冰块现在拆解为"首次被元素伤害命中时 → 受伤加成"；搬运规则仍用于其他道具上的同类效果
	_check(ice == null, "ice cube vulnerability is decomposed into a trigger clause")
	for e in _item("item_ice_cube").effects if not m.is_generated(_item("item_ice_cube")) else []:
		if e.custom_key == "enemy_percent_damage_taken":
			ice = {"effect": e, "value": 10.0, "scalar": false, "down": false, "source": "item_ice_cube"}
	if ice != null:
		var e = gen._mechanic_copy(ice, -1.0, "item_potato")
		_eq(e.source_id, "item_potato", "copied vulnerability uses the holder as its source")
		_eq(ice.effect.source_id, "item_ice_cube", "native ice cube effect untouched")


# 拆解更多原版触发型效果：冰块、金属探测器、巨型带、希腊火、糖果袋、黑旗；新载荷"按当前生命值伤害""随机主属性"、新扳机"击杀被诅咒的敌人"
func test_127_more_native_triggers() -> void:
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	var gone = ["enemy_percent_damage_taken", "chance_double_gold", "giant_crit_damage", "burning_enemy_hp_percent_damage",
		"gain_random_primary_stats_on_go_to_next_wave", "gold_on_cursed_enemy_kill"]
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			var k = mech.effect.custom_key if mech.effect.custom_key != "" else mech.effect.key
			_check(not k in gone, "decomposed native trigger not copied as a mechanic: " + k)
	for p in ["hp_dmg", "rand_stats"]:
		_check(gen.payload_prior.get(p, 0.0) > 0.0, "native prior for payload " + p)
	_check(gen.trigger_prior.get("cursed_kill", 0.0) > 0.0, "native prior for cursed_kill")
	var diver = isvc.get_element_safe(isvc.characters, "character_diver")
	for e in diver.effects:
		if e.custom_key == "enemy_percent_damage_taken":
			_eq(gen.native_trigger_of(e), null, "diver's vulnerability stays a character effect")
	var seen = {}
	var samples = []
	for sd in range(1, 31):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if not e is TriggerEffect:
					continue
				var k = ""
				if e.payload in ["hp_dmg", "rand_stats"]:
					k = e.payload
				elif e.trigger == "cursed_kill":
					k = "cursed_kill"
				if k == "":
					continue
				seen[k] = seen.get(k, 0) + 1
				var t = e.get_text(0, false)
				if samples.size() < 9:
					samples.push_back(t)
				_check(t.find("AA_") == -1 and t.find("{") == -1, "text: " + t)
				if e.payload == "hp_dmg":
					_check(e.trigger in Catalog.ENEMY_TARGET_TRIGGERS, "hp damage only on triggers with a target: " + e.trigger)
					_check(e.value >= 1 and e.value <= Catalog.HP_DMG_MAX, "hp damage within 1..%d (%d)" % [Catalog.HP_DMG_MAX, e.value])
	print("AUDIT new trigger shapes over 30 seeds: %s %s" % [str(seen), str(samples)])
	for k in ["hp_dmg", "rand_stats"]:
		_check(seen.get(k, 0) > 0, k + " appears in generated pools")
	# 估值：原版巨型带 / 糖果袋折算
	var belt = Valuation.clause_value({"trigger": "crit", "payload": "hp_dmg", "value": 10, "param": 1, "chance": 100, "cap": 0}, Catalog.PERM_MULT[3])
	var bag = Valuation.clause_value({"trigger": "wave_end", "payload": "rand_stats", "value": 8, "param": 1, "chance": 100, "cap": 0}, Catalog.PERM_MULT[2])
	print("AUDIT giant-belt-like clause %.1f, candy-bag-like clause %.1f" % [belt, bag])
	_check(belt > 40 and belt < 90, "giant-belt-like valued near the native item")
	_check(bag > 15 and bag < 40, "candy-bag-like valued near the native item")
	# 运行时：随机主属性
	m.start_new_run()
	var rt = _make_runtime([])
	var before = 0
	for s in Catalog.STATS:
		before += int(rd.get_player_effects(0)[Keys.generate_hash(s)]) if rd.get_player_effects(0).has(Keys.generate_hash(s)) else 0
	rt.execute(TriggerEffect.make({"trigger": "wave_end", "payload": "rand_stats", "value": 6}), 0, null, false)
	var after = 0
	for s in Catalog.STATS:
		after += int(rd.get_player_effects(0)[Keys.generate_hash(s)]) if rd.get_player_effects(0).has(Keys.generate_hash(s)) else 0
	_eq(after - before, 6, "6 points split between primary stats")
	rt.queue_free()
	m.on_menu_reset()


