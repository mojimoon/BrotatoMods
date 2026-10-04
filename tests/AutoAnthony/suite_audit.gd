extends "res://mods/tests/AutoAnthony/test_base.gd"

# audit：价值 / 分布的统计审计（输出 AUDIT 行；调参或发版前跑）。README 与 catalog 引用的 test_12 / 60 / 70 / 115 在这里


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
	# 点燃 / 减速 / 按生命值伤害只挂在少数有目标敌人的扳机上，单个种子里可能不出现：由 test_127 / 128 在多个种子上检查
	for p in Catalog.PAYLOADS:
		_check(pay_count.has(p) or p in ["ignite", "slow", "hp_dmg"], "payload occurs: " + p)
	# 实验性扳机出现但保持少数（原 test_107）
	var n_exp = 0
	var n_all = 0
	for t in trig_count:
		n_all += trig_count[t]
		if t in Catalog.EXPERIMENTAL_TRIGGERS:
			n_exp += trig_count[t]
	_check(n_exp > 0 and n_exp < n_all * 0.25, "experimental triggers appear but stay a minority (%d of %d)" % [n_exp, n_all])


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
	_check_reassembled_characters()


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


# 角色重组：禁止回血的角色不出现回血条款；原版触发行全部重新表达（原 test_53）
func _check_reassembled_characters() -> void:
	var cfg = _cfg()
	cfg.characters = true
	var gen = Generator.new(cfg, 20260927)
	var chars = []
	for cid in ["character_apprentice", "character_masochist", "character_golem", "character_well_rounded", "character_lucky"]:
		chars.push_back(isvc.get_element_safe(isvc.characters, cid))
	var plan = gen.generate([], isvc.characters, chars, [])
	for cid in plan.characters:
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


# 次要正面属性（击退 / 范围 / 拾取范围）：生成道具与原版道具的数值对比（按稀有度，主属性与附属行分开）
func test_133_minor_stats_audit() -> void:
	var keys = ["knockback", "stat_range", "pickup_range"]
	var native = {}
	for it in isvc.items:
		if not m.is_native_resource(it) or not it.can_be_looted:
			continue
		for e in it.effects:
			if e.key in keys and e.custom_key == "" and e.value > 0 and e.get_script() == load("res://items/global/effect.gd"):
				var k = "%s T%d" % [e.key, it.tier + 1]
				if not native.has(k):
					native[k] = []
				native[k].push_back(e.value)
	var gen_main = {}
	var gen_side = {}
	var trig = {}
	var n_items = 0
	for sd in SEEDS:
		var plan = _gen(sd)
		for id in plan.items:
			n_items += 1
			var p = plan.items[id]
			var tier = _item(id).tier
			for e in p.effects:
				if e is TriggerEffect:
					if e.stat in keys and e.value > 0:
						var tk = "%s %s" % [e.stat, e.payload]
						trig[tk] = trig.get(tk, 0) + 1
					continue
				if e.key in keys and e.custom_key == "" and e.value > 0:
					var k = "%s T%d" % [e.key, tier + 1]
					var d = gen_main if e.key in p.get("main_stats", []) else gen_side
					if not d.has(k):
						d[k] = []
					d[k].push_back(e.value)
	print("AUDIT minor stats over %d seeds (%d items); values as median [min-max] (count)" % [SEEDS.size(), n_items])
	for key in keys:
		for t in 4:
			var k = "%s T%d" % [key, t + 1]
			print("AUDIT   %-18s native %-18s generated main %-18s side %s" % [k, _dist(native.get(k, [])), _dist(gen_main.get(k, [])), _dist(gen_side.get(k, []))])
	print("AUDIT   trigger clauses: %s" % str(trig))
	_check(true, "audit printed")


func _dist(a: Array) -> String:
	if a.empty():
		return "-"
	var s = a.duplicate()
	s.sort()
	return "%d [%d-%d] (%d)" % [s[s.size() / 2], s[0], s.back(), s.size()]


# 武器价值模型：原版武器的 模型价值 / 价格 拟合（按类型、稀有度），以及各效果 key 的单位价值
func test_139_weapon_value_model() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var wv = WV.new()
	var weapons = m.native_only(isvc.weapons)
	wv.calibrate(weapons)
	print("AUDIT weapon k (price / power): " + str(wv.k_by))
	var keys = wv.unit_by_key.keys()
	keys.sort()
	for key in keys:
		print("AUDIT   unit %s = %.2f" % [key, wv.unit_by_key[key]])
	var sx = 0.0
	var sy = 0.0
	var sxx = 0.0
	var syy = 0.0
	var sxy = 0.0
	var n = 0
	var worst = []
	for row in wv.fit_rows:
		var x = log(max(1.0, row[2]))
		var y = log(max(1.0, row[1]))
		sx += x
		sy += y
		sxx += x * x
		syy += y * y
		sxy += x * y
		n += 1
		worst.push_back([abs(x - y), row[0].my_id, row[1], row[2], WV.cooldown_seconds(row[0].stats), WV.power(row[0].stats, row[0].effects)])
	var r = (n * sxy - sx * sy) / sqrt(max(0.0001, (n * sxx - sx * sx) * (n * syy - sy * sy)))
	print("AUDIT weapon value fit: n %d, r^2 %.3f (log value vs log price)" % [n, r * r])
	worst.sort_custom(self, "_sort_first_desc")
	for i in min(15, worst.size()):
		var w = worst[i]
		print("AUDIT   off %s: price %d, model %.0f, cd %.2fs, power %.1f" % [w[1], w[2], w[3], w[4], w[5]])
	_check(r * r > 0.8, "weapon value model explains native prices (r^2 %.3f)" % (r * r))


func _sort_first_desc(a, b) -> bool:
	return a[0] > b[0]
