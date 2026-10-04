extends "res://mods/tests/AutoAnthony/test_base.gd"

# core：每次改动都跑的逻辑测试（目录、生成、估值、生命周期、文本、触发与载荷的单元测试、选项、原版效果拆解、词条）


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
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var g = Generator.new(m.get_cfg(), 11)
	var out = g.generate_weapons(weapons)
	var wg = WG.new(m.get_cfg(), 11)
	wg.generate(weapons)
	_check(out.size() > 200, "weapons mapped (%d)" % out.size())
	var changed = 0
	var cross = 0
	var off = 0
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		var p = out[id]
		var donor = isvc.get_element_safe(isvc.weapons, p.donor)
		if WG.family_of(donor) != WG.family_of(w):
			changed += 1
		if donor.type != w.type:
			cross += 1
		_check(p.stats.damage >= 1, id + " damage >= 1")
		for e in p.effects:
			if e is WeaponStackEffect:
				_eq(e.weapon_stacked_id, w.weapon_id, "stack effect retargeted on " + id)
			if w.type == 0:
				_check(not WG.ranged_only(e), "%s (melee) has no ranged-only effect %s" % [id, WV.effect_key(e)])
			if WG.bound_key(e):
				_check(e in w.effects, "%s keeps only its own family-bound effect %s" % [id, WV.effect_key(e)])
		for e in w.effects:
			if WG.bound_key(e):
				_check(e in p.effects, "%s keeps its family-bound effect" % id)
		# 价值守恒：新武器价值 = 原价值 × 家族浮动（伤害取整误差内）
		var want = wg.wv.value(w.stats, w.effects, w.tier) * wg._family_mult(WG.family_of(w))
		var got = wg.wv.value(p.stats, p.effects, w.tier)
		if abs(got - want) > max(3.0, want * 0.15):
			off += 1
			print("AUDIT weapon value off %s: want %.1f got %.1f (scale %.2f)" % [id, want, got, p.scale])
	_check(changed > out.size() / 2, "most weapons got another family's effects (%d)" % changed)
	_check(cross > 0, "effects cross melee / ranged (%d)" % cross)
	_check(off <= out.size() / 20, "weapon values match the target (%d off)" % off)
	print("AUDIT weapons: %d, other family %d, cross-type %d" % [out.size(), changed, cross])


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
	# 实际游戏每波重建运行时：模拟下一波
	rt._wave_over = false
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
		if not t in ["kill", "gold", "interval"] and not t.begins_with("hit_above_") and not t.begins_with("hit_below_"):
			_check(keys.has("AA_T_" + t.to_upper()), "trigger text for " + t)
		for param in [1, 3]:
			var txt = TriggerEffect.make({"trigger": t, "param": param, "payload": "gold", "value": 1, "dmg_type": "stat_melee_damage", "stat": "stat_armor"}).get_text(0, false)
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
	# "保留原名"是"重组名称"的反向显示
	ui._on_switch_toggled(true, "cfg_rename")
	_eq(m.cfg_rename, false, "keep names on = no rename")
	_eq(ui._switches["cfg_rename"].pressed, true, "keep names switch shows on")
	ui._on_switch_toggled(false, "cfg_rename")
	_eq(m.cfg_rename, true, "keep names off = rename")
	# 重组方式二选一
	ui._on_mode_toggled(true, "deep")
	_eq(m.cfg_weapon_mode, "deep", "deep mode")
	_check(not ui._mode_switches["effects"].pressed, "modes are exclusive")
	ui._on_mode_toggled(true, "effects")
	_eq(m.cfg_weapon_mode, "effects", "effects mode")
	# 页签：只显示当前页；页签右边的开关就是本页总开关
	ui._on_page_pressed("weapons")
	_check(ui._pages["weapons"].visible and not ui._pages["items"].visible, "weapons page shown")
	ui._on_page_pressed("items")
	for pg in ["items", "weapons", "characters"]:
		_check(ui._page_switches.has(pg), "page switch: " + pg)
	_eq(ui._page_switches["weapons"].pressed, true, "weapons page switch follows cfg")
	# 每个开关都有灰色说明
	for k in ["cfg_char_effects", "cfg_all_char_effects", "cfg_more_double", "cfg_starting_items", "cfg_rename", "cfg_force_items", "cfg_chaos", "cfg_w_item_effects", "cfg_w_low_tiers", "cfg_w_any_start"]:
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
		var n = ui._pv.items.grid.get_child_count()
		_eq(n, ui._preview_entries(ui._plan, t).size(), "preview tier %d shows one card per item" % (t + 1))
		_check(n > 10, "preview tier %d has items (%d)" % [t + 1, n])
		_check(ui._pv.items.buttons[t].text.find("(") > 0, "tier button shows a count: " + ui._pv.items.buttons[t].text)
	# 武器预览：每把武器一张卡片，带原版的属性文本
	ui._on_page_pressed("weapons")
	for t in 4:
		ui._on_tier_pressed(t, "weapons")
		yield(tree, "idle_frame")
		var n = ui._pv.weapons.grid.get_child_count()
		_eq(n, ui._preview_entries(ui._plan, t, "weapons").size(), "weapon preview tier %d shows one card per weapon" % (t + 1))
		_check(n > 5, "weapon preview tier %d has weapons (%d)" % [t + 1, n])
	var wt = ui.weapon_preview_text(ui._preview_entries(ui._plan, 0, "weapons")[0], ui._plan.weapons[ui._preview_entries(ui._plan, 0, "weapons")[0].my_id])
	_check(wt.find(tr("STAT_DAMAGE")) >= 0 and wt.find("AA_") == -1, "weapon card text: " + wt.left(80))
	ui._on_page_pressed("items")
	ui._on_switch_toggled(false, "cfg_weapons")
	for i in 6:
		yield(tree, "idle_frame")
	var vp = tree.root.get_visible_rect().size
	var panel = ui.get_child(1).get_child(0)
	print("AUDIT settings panel %s in viewport %s" % [str(panel.rect_size), str(vp)])
	_check(panel.rect_size.x <= max(vp.x, 1920) and panel.rect_size.y <= max(vp.y, 1080), "settings panel fits the screen")
	var shot = OS.get_environment("AA_UI_SHOT")
	if shot != "":
		# AA_UI_PAGE=weapons / characters：截取对应分页
		var page = OS.get_environment("AA_UI_PAGE")
		if page != "":
			m.cfg_weapons = true
			ui._on_page_pressed(page)
			ui._on_preview_pressed()
			ui._on_tier_pressed(1, "weapons")
		else:
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


func test_85_id_bound_effects_are_adapted() -> void:
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	# 丑牙（减速）与害怕的香肠（点燃）已拆解为触发条款，不再作为机制
	for key in ["duplicate_item", "increase_tier_on_reroll", "item_hourglass", "extra_item_in_crate",
			"number_of_enemies", "curse_locked_items", "items_price", "reroll_price", "recycling_gains", "harvesting_growth",
			"gain_pct_gold_start_wave", "loot_alien_chance", "tree_turrets", "hp_start_next_wave"]:
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
	# 实际游戏每波重建运行时：模拟下一波
	rt._wave_over = false
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
			# 成长型道具带自己的限制 (X)
			var pp = m.plan.items[pair[0].my_id]
			_eq(pair[0].max_nb, 1 if pp.unique else int(pp.get("limit", -1)), pair[0].my_id + " limit lifted")
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
# 建筑 / 宠物 / 沙漏 / 镜子现在也会被重组（金鱼锚定）；角色初始道具保留原版；T4 无 +收获；T3 单效果非纯数值
# ============================================================
func test_99_structures_and_special_items_reassembled() -> void:
	var plan = _gen(42)
	for id in ["item_turret", "item_landmines", "item_garden", "item_bonk_dog", "item_lootworm", "item_hourglass", "item_mirror"]:
		_check(plan.items.has(id), id + " is reassembled")
	# 金鱼锚定（低价是为了允许大量获取），效果仍参与组合
	for id in ["item_builder_turret_0", "item_goldfish", "item_goldfish_used", "item_broken_mirror", "item_broken_hourglass"]:
		_check(not plan.items.has(id), id + " kept")
	m.start_new_run()
	for id in ["item_hourglass", "item_mirror"]:
		_eq(_item(id).replaced_by, null, id + " no longer turns into another item")
	_check(_item("item_goldfish").replaced_by != null, "anchored goldfish still turns into the used goldfish")
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
					var k = e.stat if e is TriggerEffect else e.key
					if e.value > 0 and k in Catalog.T4_BANNED_POSITIVE_STATS and (e is TriggerEffect or gen.is_plain_stat(e) or gen.is_scaling(e)):
						_check(false, id + " T4 item has +" + k + ": " + e.get_text(0, false))
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
				# 成长型道具的限制 (1) 也是独特
				_eq(p.get("unique", false), Generator.has_unique_effect(p.effects) or int(p.get("limit", 0)) == 1, "unique flag: " + id)
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
						want.push_back(Catalog.STAT_EXTRA_TAGS.get(e.stat_scaled, e.stat_scaled))
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
					if e is TriggerEffect and e.trigger == "hit_typed":
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
	_check(Runtime._matches("hit_typed", "hit_enemy", info, "stat_ranged_damage"), "ranged hit matches ranged hit_typed")
	_check(not Runtime._matches("hit_typed", "hit_enemy", info, "stat_melee_damage"), "ranged hit does not match melee hit_typed")


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
	_check(belt > 40 and belt < 120, "giant-belt-like valued near the native item")
	# 1.2.5：糖果袋实测偏强，估值为原版折算的约 2 倍（同样预算下数值减半）
	_check(bag > 30 and bag < 80, "candy-bag-like valued at about twice the native item")
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


# 剩余拆解（发射投射物已删除，婴儿胡子 / 外星之眼仍作为机制搬运）：点燃（害怕的香肠）、减速（丑牙）、掉落水果（果篮）；
# 新扳机：砍倒树木（口袋工厂）、获得提升 [属性] 的道具（雪球）；击杀被诅咒的敌人附带 +5 诅咒
func test_128_remaining_native_triggers() -> void:
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	for t in 4:
		for mech in gen.mechanics_by_tier[t]:
			var k = mech.effect.custom_key if mech.effect.custom_key != "" else mech.effect.key
			_check(not k in ["burn_chance", "remove_speed", "gain_stat_for_equipped_item_with_stat"],
				"decomposed native trigger not copied: " + k)
	_eq(Catalog.TRIGGERS["cursed_kill"].e, 25.0, "cursed kills estimated at 1/4 of kills")
	var seen = {}
	var samples = []
	var curse_ok = 0
	for sd in range(1, 31):
		var plan = _gen(sd)
		for id in plan.items:
			var has_ck = false
			var curse = 0
			for e in plan.items[id].effects:
				if e.key == "stat_curse" and not e is TriggerEffect:
					curse += e.value
				if not e is TriggerEffect:
					continue
				var k = ""
				if e.payload in ["ignite", "slow", "fruit"]:
					k = e.payload
				elif e.trigger in ["tree_kill", "buy_stat"]:
					k = e.trigger
				if e.trigger == "cursed_kill" and e.value > 0:
					has_ck = true
				if k == "":
					continue
				seen[k] = seen.get(k, 0) + 1
				var txt = e.get_text(0, false)
				if samples.size() < 12:
					samples.push_back(txt)
				_check(txt.find("AA_") == -1 and txt.find("{") == -1, "text: " + txt)
				if e.payload in ["ignite", "slow"]:
					_check(e.trigger in Catalog.ENEMY_TARGET_TRIGGERS, e.payload + " only on triggers with a target: " + e.trigger)
				if e.trigger == "buy_stat":
					_eq(e.payload, "perm_stat", "item-with-stat trigger grants the same stat")
			if has_ck:
				_check(curse >= Catalog.CURSED_KILL_CURSE, "cursed-kill item carries +%d curse (%s)" % [Catalog.CURSED_KILL_CURSE, id])
				if curse >= Catalog.CURSED_KILL_CURSE:
					curse_ok += 1
	print("AUDIT remaining native shapes over 30 seeds: %s, cursed-kill items with curse %d; %s" % [str(seen), curse_ok, str(samples)])
	for k in ["ignite", "slow", "fruit", "tree_kill", "buy_stat"]:
		_check(seen.get(k, 0) > 0, k + " appears in generated pools")
	# 商店：获得提升该属性的道具时
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [TriggerEffect.make({"trigger": "buy_stat", "payload": "perm_stat", "stat": "stat_elemental_damage", "value": 2}),
		TriggerEffect.make({"trigger": "buy", "payload": "rand_stats", "value": 3})]
	rd.add_item(holder, 0)
	var h = Keys.stat_elemental_damage_hash
	var before = rd.get_player_effects(0)[h]
	var elem_item = _item("item_potato").duplicate()
	elem_item.effects = [gen._stat_effect("stat_elemental_damage", 1)]
	var other = _item("item_potato").duplicate()
	other.effects = [gen._stat_effect("stat_armor", 1)]
	m.fire_shop("buy_stat", 0, other)
	_eq(rd.get_player_effects(0)[h], before, "item without the stat does not trigger")
	m.fire_shop("buy_stat", 0, elem_item)
	_eq(rd.get_player_effects(0)[h], before + 2, "item with the stat triggers")
	var tot0 = 0
	for s in Catalog.STATS:
		tot0 += int(rd.get_player_effects(0).get(Keys.generate_hash(s), 0))
	m.fire_shop("buy", 0)
	var tot1 = 0
	for s in Catalog.STATS:
		tot1 += int(rd.get_player_effects(0).get(Keys.generate_hash(s), 0))
	_eq(tot1 - tot0, 3, "random primary stats work in the shop")
	rd.remove_item(holder, 0)
	m.on_menu_reset()


# 脚本加载阶段不预载游戏本体资源（preload 原版 .tres / 场景会在实际游戏启动时崩溃：mod 脚本先于部分资源加载）
func test_129_no_preload_of_game_resources() -> void:
	var dirs = [MOD_DIR]
	var bad = []
	var n = 0
	while not dirs.empty():
		var d = dirs.pop_back()
		var da = Directory.new()
		if da.open(d) != OK:
			continue
		da.list_dir_begin(true, true)
		var f = da.get_next()
		while f != "":
			var path = d + f
			if da.current_is_dir():
				dirs.push_back(path + "/")
			# 设置界面在菜单中按需加载（字体预载没有问题），只检查随 mod 初始化 / 脚本扩展加载的脚本
			elif f.ends_with(".gd") and f != "settings_ui.gd":
				n += 1
				var fh = File.new()
				fh.open(path, File.READ)
				var text = fh.get_as_text()
				fh.close()
				var re = RegEx.new()
				re.compile("preload\\(\"(res://[^\"]+)\"\\)")
				for mt in re.search_all(text):
					if not mt.get_string(1).begins_with("res://mods-unpacked/"):
						bad.push_back(path.get_file() + ": " + mt.get_string(1))
			f = da.get_next()
	_check(n > 10, "scanned mod scripts (%d)" % n)
	_check(bad.empty(), "no preload of game resources: " + str(bad))


# 通用门控：gate = every 的扳机都能单次 / 几率 / 每 N 次；作用于目标敌人的载荷不计次；
# 限定伤害类型的扳机统一为一个 id + dmg_type 字段（近战 : 远程 : 元素 : 工程 = 2 : 2 : 2 : 1）；
# 商店扳机计次；"用某类伤害击杀"；水果不会在波末掉落
func test_130_trigger_templates() -> void:
	var counted = {}
	var typed = {}
	var dmg_stats = {}
	for sd in range(1, 41):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if not e is TriggerEffect:
					continue
				if e.param > 1 and e.trigger != "interval":
					counted[e.trigger] = true
					_check(Catalog.TRIGGERS[e.trigger].gate == "every", "counted only on gate-every triggers: " + e.trigger)
					_check(not e.payload in Catalog.TARGET_PAYLOADS, "target payload not counted: " + e.get_text(0, false))
				if e.trigger in Catalog.TYPED_TRIGGERS:
					_check(Catalog.DMG_TYPES.has(e.dmg_type), "typed trigger has a damage type: " + e.trigger)
					typed[e.dmg_type] = typed.get(e.dmg_type, 0) + 1
				else:
					_eq(e.dmg_type, "", "untyped trigger has no damage type")
				if e.payload in ["damage", "explode"] and Catalog.DMG_TYPES.has(e.stat):
					dmg_stats[e.stat] = dmg_stats.get(e.stat, 0) + 1
				var txt = e.get_text(0, false)
				_check(txt.find("AA_") == -1 and txt.find("{") == -1, "text: " + txt)
				if e.payload == "fruit":
					_check(not e.trigger in ["wave_end", "wave_start", "half_wave", "interval"], "no fruit outside of combat events: " + e.trigger)
				if e.payload == "vuln":
					_eq(e.value2, Catalog.VULN_SECONDS, "vulnerability lasts 3 seconds like the ice cube")
	print("AUDIT counted triggers %s; typed damage types %s; damage/explode types %s" % [str(counted.keys()), str(typed), str(dmg_stats)])
	# 商店扳机（刷新 / 购买）出现得少：至少一个用上计次
	for t in ["dodge", "consumable", "hit"]:
		_check(counted.has(t), "count gate now used on " + t)
	_check(counted.has("reroll") or counted.has("buy"), "count gate used on a shop trigger")
	_check(typed.get("stat_engineering", 0) > 0 and typed.get("stat_engineering", 0) < typed.get("stat_melee_damage", 0), "engineering rarer than melee")
	for tbl in [Catalog.LEGAL, Catalog.FREE_LEGAL]:
		_check(not "fruit" in tbl.wave_end and not "fruit" in tbl.wave_start, "no fruit at wave start / end")
	# 用某类伤害击杀
	_check(Runtime._matches("kill_typed", "kill_typed", {"stats": ["stat_melee_damage"]}, "stat_melee_damage"), "melee kill matches")
	_check(not Runtime._matches("kill_typed", "kill_typed", {"stats": ["stat_ranged_damage"]}, "stat_melee_damage"), "ranged kill does not match melee")
	# 商店计次：每刷新 3 次商店
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [TriggerEffect.make({"trigger": "reroll", "param": 3, "payload": "perm_stat", "stat": "stat_armor", "value": 1})]
	rd.add_item(holder, 0)
	var a0 = rd.get_player_effects(0)[Keys.stat_armor_hash]
	for i in 7:
		m.fire_shop("reroll", 0)
	_eq(rd.get_player_effects(0)[Keys.stat_armor_hash], a0 + 2, "every 3 rerolls: 7 rerolls give +2")
	rd.remove_item(holder, 0)
	m.on_menu_reset()


# 消耗品持续治疗（干肉条）：绿色文本但实际是代价，带消耗品词条
func test_132_consumable_heal_over_time_is_downside() -> void:
	var jerky = _item("item_jerky")
	var hot = null
	for e in jerky.effects:
		if e.key == "consumable_heal_over_time":
			hot = e
	_check(hot != null, "jerky has heal over time")
	if hot == null:
		return
	_check(Catalog.is_downside_mechanic(hot), "heal over time is a downside")
	var gen = Generator.new(_cfg(), 1)
	_check("consumable" in gen._tags_for([hot]), "heal over time carries the consumable tag")
	var n = 0
	for sd in range(1, 41):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.key == "consumable_heal_over_time":
					n += 1
					_check("consumable" in plan.items[id].tags, id + " with heal over time has the consumable tag")
	print("AUDIT heal-over-time lines over 40 seeds: %d" % n)


# 成长型道具：小概率；"每有 [A] 获得 [B]"，B 只取 %伤害 / 攻速 / 最大生命，转化率约为常规估值的 2 倍；带限制 (X)
func test_134_growth_items() -> void:
	var n = 0
	var n_items = 0
	var targets = {}
	var counters = {}
	var samples = []
	for sd in range(1, 21):
		var plan = _gen(sd)
		for id in plan.items:
			n_items += 1
			var p = plan.items[id]
			if not p.get("growth", false):
				continue
			n += 1
			_check(_item(id).tier >= 1, id + " growth items are T2+")
			var lim = int(p.get("limit", 0))
			_check(lim >= 1 and lim <= 3, id + " has a limit (%d)" % lim)
			# 限制 1 = 独特（代价是独特型机制时也会独特）
			_check(lim != 1 or p.unique, id + " limit 1 is unique")
			var sc = null
			for e in p.effects:
				if e.get_script() != null and e.get_script().resource_path.ends_with("gain_stat_for_every_stat_effect.gd") and e.value > 0:
					sc = e
			_check(sc != null, id + " has a scaling line")
			if sc == null:
				continue
			_check(Catalog.GROWTH_TARGETS.has(sc.key), id + " target stat is %damage / attack speed / max hp: " + sc.key)
			_check(sc.stat_scaled in Catalog.GROWTH_COUNTERS and sc.stat_scaled != sc.key, id + " counter: " + sc.stat_scaled)
			targets[sc.key] = targets.get(sc.key, 0) + 1
			counters[sc.stat_scaled] = counters.get(sc.stat_scaled, 0) + 1
			# +属性行只能是计数属性 A 本身（诅咒道具原有的 +诅咒行除外）
			for e in p.effects:
				if e.get_script() == load("res://items/global/effect.gd") and Catalog.STATS.has(e.key) and e.custom_key == "" and e.value > 0:
					_eq(e.key, sc.stat_scaled, id + " plus line is the counted stat")
			var txt = _texts(p.effects)
			_check(txt.find("AA_") == -1 and txt.find("{") == -1, "text: " + txt)
			if samples.size() < 8:
				samples.push_back("T%d limit %d: %s" % [_item(id).tier + 1, lim, txt])
	print("AUDIT growth items %d of %d (targets %s; counters %s)" % [n, n_items, str(targets), str(counters)])
	for t in samples:
		print("AUDIT   " + t)
	_check(n > 0 and n < n_items * 0.08, "growth items are rare but present")
	# 属性 A 按普通属性行的权重：主要属性占多数
	var minor = 0
	for c in counters:
		if not c in ["stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage", "stat_ranged_damage",
				"stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering", "stat_range", "stat_armor", "stat_dodge",
				"stat_speed", "stat_luck", "stat_harvesting"]:
			minor += counters[c]
	_check(minor < n * 0.2, "secondary stats / curse are a minority of counters (%d of %d)" % [minor, n])
	# 限制写到道具上，回菜单后还原
	m.start_new_run()
	for id in m.plan.items:
		var p = m.plan.items[id]
		if int(p.get("limit", 0)) > 1 and not p.unique:
			_eq(_item(id).max_nb, p.limit, id + " limit written to the item")
	m.on_menu_reset()


# 珍珠（箱子里额外出现这件道具自己）必须同时带有其他正面行
func test_136_pearl_needs_positive_lines() -> void:
	var n = 0
	var pct = []
	for sd in range(1, 41):
		var plan = _gen(sd)
		for id in plan.items:
			var p = plan.items[id]
			var pearl = null
			for e in p.effects:
				if e.custom_key == "extra_item_in_crate" and e.key != "random":
					pearl = e
			if pearl == null:
				continue
			n += 1
			pct.push_back(pearl.value)
			var pos = 0
			for e in p.effects:
				if e != pearl and e.value > 0 and e.key != "stat_curse" and not Catalog.is_downside_mechanic(e):
					pos += 1
			_check(pos > 0, id + " pearl has another positive line: " + _texts(p.effects))
	_check(n > 0, "pearl lines appear (%d)" % n)
	print("AUDIT pearl lines %d, values %s" % [n, str(pct)])


# 强制重组 (BETA)：商店里买得到的锚定道具也参与重组；望远镜补足按下标读取的效果行
func test_137_force_reassembly() -> void:
	var plan = _gen(5)
	for id in Catalog.ANCHORED_ITEMS:
		_check(not plan.items.has(id), "anchored by default: " + id)
	var cfg = _cfg()
	cfg.force_items = true
	plan = _gen(5, cfg)
	for id in Catalog.ANCHORED_ITEMS:
		var it = _item(id)
		if it == null:
			continue
		_eq(plan.items.has(id), it.can_be_looted, "forced iff lootable: " + id)
	for sd in range(1, 21):
		plan = _gen(sd, cfg)
		var sp = plan.items.get("item_spyglass")
		_check(sp != null and sp.effects.size() >= 2, "spyglass has effects[1] (seed %d)" % sd)
		if sp != null:
			_check(_texts(sp.effects).find("AA_") == -1, "spyglass text: " + _texts(sp.effects))
	# 实际开局：望远镜的 effects[1] 可读（商店刷新时按它统计折扣）
	m.cfg_force_items = true
	_setup_player("character_well_rounded")
	m.start_new_run()
	var spy = _item("item_spyglass")
	_check(spy.effects.size() >= 2 and spy.effects[1].value is int, "live spyglass effects[1].value readable")
	m.on_menu_reset()
	m.cfg_force_items = false


# 究极混沌：被重组道具之间交换稀有度（每档数量不变）与图标；预览不改动资源；开局写入、回到菜单还原
func test_138_ultimate_chaos() -> void:
	var cfg = _cfg()
	cfg.chaos = true
	var before = {}
	for it in isvc.items:
		before[it.my_id] = [it.tier, it.icon]
	var plan = _gen(9, cfg)
	var moved = 0
	var icons = 0
	var count_old = [0, 0, 0, 0]
	var count_new = [0, 0, 0, 0]
	var budget_by_tier = [[], [], [], []]
	for id in plan.items:
		var p = plan.items[id]
		_check(p.has("tier") and p.has("icon"), id + " has chaos tier / icon")
		count_old[before[id][0]] += 1
		count_new[int(p.tier)] += 1
		budget_by_tier[int(p.tier)].push_back(float(p.budget))
		if int(p.tier) != before[id][0]:
			moved += 1
		if p.icon != before[id][1]:
			icons += 1
	_eq(str(count_new), str(count_old), "tier counts unchanged")
	_check(moved > plan.items.size() / 2, "most items change tier (%d)" % moved)
	_check(icons > plan.items.size() / 2, "most items change icon (%d)" % icons)
	var med = []
	for t in 4:
		budget_by_tier[t].sort()
		med.push_back(budget_by_tier[t][budget_by_tier[t].size() / 2])
	_check(med[0] < med[1] and med[1] < med[2] and med[2] < med[3], "budget follows the new tier %s" % str(med))
	var untouched = true
	for it in isvc.items:
		if it.tier != before[it.my_id][0] or it.icon != before[it.my_id][1]:
			untouched = false
	_check(untouched, "preview leaves resources unchanged")
	# 开局：资源与商店分档池使用新稀有度；回到菜单还原
	m.cfg_chaos = true
	_setup_player("character_well_rounded")
	m.start_new_run()
	var id0 = ""
	for id in m.plan.items:
		if int(m.plan.items[id].tier) != before[id][0]:
			id0 = id
			break
	var res = _item(id0)
	_eq(res.tier, int(m.plan.items[id0].tier), "live tier applied: " + id0)
	_check(res in isvc._tiers_data[res.tier][0] or not res.can_be_looted or not ProgressData.items_unlocked.has(res.my_id_hash), "shop pool rebuilt with the new tier")
	m.on_menu_reset()
	_eq(res.tier, before[id0][0], "tier restored")
	_check(res.icon == before[id0][1], "icon restored")
	m.cfg_chaos = false
