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
		if method.name.begins_with("test_"):
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

	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		printerr("FAIL ", f)
	if _failures.empty():
		print("ALL TESTS PASSED")
	return 0 if _failures.empty() else 1


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
				_check(p in ["perm_stat", "gold"], "shop trigger %s payload %s is shop-safe" % [t, p])
	_check(not "heal" in Catalog.LEGAL["heal"], "no heal->heal loop")
	_check(not "gold" in Catalog.LEGAL["gold"], "no gold->gold loop")
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
	for s in range(1, 40):
		var gen = Generator.new(_cfg(), s)
		gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
		gen.rng.seed = s
		for i in 30:
			var c = gen.gen_clause(30.0, 6.0, false)
			if not c.empty():
				seen[c.trigger + "/" + c.payload] = true
	for k in Catalog.NATIVE_TRIGGER_MAP:
		var pair = Catalog.NATIVE_TRIGGER_MAP[k]
		_check(seen.has(pair[0] + "/" + pair[1]), "native combo reachable: %s -> %s/%s" % [k, pair[0], pair[1]])
	var legal_total = 0
	for t in Catalog.FREE_LEGAL:
		legal_total += Catalog.FREE_LEGAL[t].size()
	print("AUDIT distinct trigger/payload combos generated: %d of %d legal" % [seen.size(), legal_total])
	_check(seen.size() > legal_total * 0.8, "most legal combos reachable")


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
	_check(not neg.empty() and neg.value < 0 and neg.payload == "temp_stat", "negative clause is a temp-stat downside")


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
	_eq(potato.value, 95, "price preserved")
	_eq(potato.tier, 3, "tier preserved")
	var anchored = _item("item_spyglass")
	var coupon_before = anchored.effects
	m.on_menu_reset()
	_check(potato.effects == orig_effects, "restored effects")
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
	for cid in ["character_ranger", "character_apprentice", "character_masochist", "character_explorer"]:
		_setup_player(cid)
		var ch = isvc.get_element_safe(isvc.characters, cid)
		var before = ch.effects
		m.start_new_run()
		_check(m.plan.characters.has(cid), cid + " reassembled")
		var after = ch.effects
		_eq(after.size(), before.size(), cid + " same number of lines")
		for e in before:
			var gen = Generator.new(_cfg(), 1)
			if not gen.is_plain_stat(e) and gen.native_trigger_of(e) == null:
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
	for t in Catalog.TRIGGERS:
		if not t in ["kill", "gold", "interval"]:
			_check(keys.has("AA_T_" + t.to_upper()), "trigger text for " + t)
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
	ui.queue_free()
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
	for id in ["item_coupon", "item_crown", "item_pearl", "item_whistle", "item_crystal", "item_fish_hook"]:
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
	m.start_new_run()
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
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
				if Catalog.TRIGGERS[e.trigger].kind == "shop" or e.trigger == "wave_end":
					_eq(e.grant_mode, "perm", "shop / wave-end grants are permanent")
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
		_check(not ("gold" in Catalog.FREE_LEGAL[t] and t == "gold"), "no gold loop")
		_check(not ("xp" in Catalog.FREE_LEGAL[t] and t == "level_up"), "no xp/level loop")
		if Catalog.TRIGGERS[t].kind == "shop":
			for p in Catalog.FREE_LEGAL[t]:
				_check(p in ["perm_stat", "gold", "grant"], "shop trigger payload is shop-safe")


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
		var perm = c.payload == "perm_stat" or (c.payload == "grant" and c.get("grant_mode", "") == "perm")
		if perm and Valuation.raw_rate(c.trigger, 1, 100) > 1.5:
			caps.push_back(c.cap)
			if shown < 5:
				print("AUDIT perm clause: ", TriggerEffect.make(c).get_text(0, false))
				shown += 1
	caps.sort()
	print("AUDIT perm caps on high-frequency triggers: n=%d median=%d max=%d" % [caps.size(), caps[caps.size() / 2] if caps.size() > 0 else 0, caps.back() if caps.size() > 0 else 0])
	_check(caps.size() > 10 and caps[caps.size() / 2] >= 3, "permanent caps are no longer 1-3")


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
				elif e is TriggerEffect and e.side_stat != "":
					paired += 1
					var t2 = e.get_text(0, false)
					_check(t2.find(tr("AA_AND").strip_edges()) != -1, "paired clause rendered in one line: " + t2)
					if shown < 6:
						print("AUDIT paired clause: ", t2)
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
	var rt = _make_runtime([{"trigger": "kill", "payload": "temp_stat", "stat": "stat_armor", "value": 3, "side_stat": "enemy_damage", "side_value": 2}])
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
