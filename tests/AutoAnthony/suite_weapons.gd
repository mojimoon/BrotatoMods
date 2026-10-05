extends "res://mods/tests/AutoAnthony/test_base.gd"

# weapons：武器重组的全部测试（价值模型、仅重组效果、深度重组、道具效果、低级武器、混沌、名称、真实战斗与选择武器界面）


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
		var want = wg._want(w) * wg._family_mult(WG.family_of(w))
		var got = wg.wv.value(p.stats, p.effects, w.tier)
		if abs(got - want) > max(3.0, want * 0.15):
			off += 1
			print("AUDIT weapon value off %s: want %.1f got %.1f (scale %.2f)" % [id, want, got, p.scale])
	_check(changed > out.size() / 2, "most weapons got another family's effects (%d)" % changed)
	_check(cross > 0, "effects cross melee / ranged (%d)" % cross)
	_check(off <= out.size() / 20, "weapon values match the target (%d off)" % off)
	print("AUDIT weapons: %d, other family %d, cross-type %d" % [out.size(), changed, cross])


# 深度重组：属性从原版分布抽取、价值按模型守恒；主加成大多是本类型的伤害；类别按词条（必定 / 可能）选取
func test_141_weapon_deep_reassembly() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	for sd in [3, 17]:
		var wg = WG.new(cfg, sd)
		var out = wg.generate(weapons)
		_check(out.size() > 200, "deep: weapons generated (%d)" % out.size())
		var off = 0
		var cd_changed = 0
		var mains = {0: {}, 1: {}}
		var n_type = {0: 0, 1: 0}
		var set_count = {}
		var must_ok = 0
		var must_all = 0
		var fams = {}
		for id in out:
			var w = isvc.get_element_safe(isvc.weapons, id)
			var p = out[id]
			_check(p.stats.damage >= 1, id + " damage >= 1")
			_eq(WV.is_melee(p.stats), w.type == 0, id + " keeps melee / ranged")
			if p.stats.cooldown != w.stats.cooldown:
				cd_changed += 1
			for e in p.effects:
				if w.type == 0:
					_check(not WG.ranged_only(e), id + " melee has no ranged-only effect")
			var want = wg._want(w, true) * wg._family_mult(WG.family_of(w))
			var got = wg.wv.value(p.stats, p.effects, w.tier)
			if abs(got - want) > max(3.0, want * 0.15):
				off += 1
			var f = WG.family_of(w)
			if fams.has(f):
				continue
			fams[f] = true
			n_type[w.type] += 1
			var main = WV.stat_name(p.stats.scaling_stats[0][0])
			if not main in WG.DAMAGE_STATS:
				main = "other"
			mains[w.type][main] = mains[w.type].get(main, 0) + 1
			var ids = []
			for x in p.sets:
				ids.push_back(x.my_id)
				set_count[x.my_id] = set_count.get(x.my_id, 0) + 1
				if w.type == 0:
					_check(not x.my_id in WG.RANGED_ONLY_SETS, f + " melee is not " + x.my_id)
				else:
					_check(not x.my_id in WG.MELEE_ONLY_SETS, f + " ranged is not " + x.my_id)
			_check(ids.size() >= 1 and ids.size() <= 3, f + " has 1-2 sets (+1 for the minimum rule)")
			var lowest = 3
			for x in weapons:
				if WG.family_of(x) == f:
					lowest = min(lowest, x.tier)
			_eq("set_legendary" in ids, lowest == 3, f + " legendary iff only tier IV")
			# 第一个"必定"类别一定在
			for t in wg.weapon_tags(w.type, p.stats, p.effects):
				var must = WG.TAG_SETS.get(t, {}).get("must", [])
				if not must.empty() and wg._set_ok(must[0], w.type) and lowest < 3:
					must_all += 1
					if must[0] in ids:
						must_ok += 1
					break
		_check(off <= out.size() / 20, "deep: values match (%d off)" % off)
		_check(cd_changed > out.size() / 2, "deep: cooldowns rerolled (%d)" % cd_changed)
		_check(mains[0].get("stat_melee_damage", 0) >= n_type[0] * 0.7, "deep: melee weapons mostly scale with melee damage %s" % str(mains[0]))
		_check(mains[1].get("stat_ranged_damage", 0) >= n_type[1] * 0.5, "deep: ranged weapons mostly scale with ranged damage %s" % str(mains[1]))
		_check(mains[0].get("other", 0) + mains[1].get("other", 0) <= (n_type[0] + n_type[1]) * 0.2, "deep: few weapons without a damage main scaling")
		_check(must_ok == must_all, "deep: the first required class is always present (%d / %d)" % [must_ok, must_all])
		for x in wg._sets:
			if x != "set_legendary":
				_check(set_count.get(x, 0) >= min(3, wg._set_native_count.get(x, 0)), "deep: set %s has enough families (%d)" % [x, set_count.get(x, 0)])
		if sd == 3:
			print("AUDIT deep main scaling melee %s ranged %s" % [str(mains[0]), str(mains[1])])
			print("AUDIT deep sets %s" % str(set_count))


# 引入道具效果：约六成武器家族多一条道具属性行 / 触发条款，各稀有度相同、数值随稀有度增长；相关时是武器的加成属性
func test_142_weapon_item_effects() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	for mode in ["effects", "deep"]:
		var cfg = _cfg()
		cfg.weapons = true
		cfg.weapon_mode = mode
		cfg.w_item_effects = true
		var g = Generator.new(cfg, 23)
		g.generate(isvc.items, isvc.characters, [], [])
		var out = g.generate_weapons(weapons)
		var fam_lines = {}
		var related = 0
		var clauses = 0
		for id in out:
			var w = isvc.get_element_safe(isvc.weapons, id)
			var f = WG.family_of(w)
			var line = null
			for e in out[id].effects:
				if e.has_meta("aa_value"):
					_check(line == null, id + " at most one item line")
					line = e
			if line == null:
				_check(not fam_lines.has(f) or fam_lines[f] == null, f + " item line on every tier or none")
				fam_lines[f] = null
				continue
			var txt = line.get_text(0, false)
			_check(txt != "" and txt.find("AA_") == -1, id + " item line text: " + txt)
			var key = line.trigger + "/" + line.payload if line is TriggerEffect else line.key
			if fam_lines.has(f):
				_check(fam_lines[f] != null and fam_lines[f][0] == key, f + " same item line on every tier")
			if line is TriggerEffect:
				clauses += 1
			else:
				for sc in out[id].stats.scaling_stats:
					if WV.stat_name(sc[0]) == line.key:
						related += 1
						if float(sc[1]) < 0:
							_check(line.value < 0, id + " negative scaling -> negative related line")
			fam_lines[f] = [key]
		var with_line = 0
		for f in fam_lines:
			if fam_lines[f] != null:
				with_line += 1
		print("AUDIT %s item lines: %d / %d families, related %d, clauses %d" % [mode, with_line, fam_lines.size(), related, clauses])
		# 仅重组效果：约六成家族有道具效果；深度重组：道具效果是"额外效果"中的一部分
		var lo_share = 0.4 if mode == "effects" else 0.1
		var hi_share = 0.8 if mode == "effects" else 0.5
		_check(with_line > fam_lines.size() * lo_share and with_line < fam_lines.size() * hi_share, mode + ": share of families with an item line (%d)" % with_line)
		_check(related > 0 and clauses > 0, mode + ": related stat lines and clauses both appear")


# 允许低级武器：没有低级版本的家族补到 T1（价格递减、合成升级为上一级）；开局注册进商店池，回到菜单移除；读档能找回
func test_143_low_tier_weapons() -> void:
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var natives = m.native_only(isvc.weapons)
	var low = WG.make_low_tiers(natives)
	var lowest = {}
	for w in natives:
		var f = WG.family_of(w)
		lowest[f] = min(lowest.get(f, 3), w.tier)
	var expect = 0
	for f in lowest:
		expect += lowest[f]
	_eq(low.size(), expect, "one new weapon per missing lower tier")
	for w in low:
		_eq(w.my_id, w.weapon_id + "_" + str(w.tier + 1), "id pattern " + w.my_id)
		_check(w.upgrades_into != null and w.upgrades_into.tier == w.tier + 1, w.my_id + " upgrades into the next tier")
		_check(w.value < w.upgrades_into.value, w.my_id + " cheaper than its upgrade (%d < %d)" % [w.value, w.upgrades_into.value])
	m.cfg_weapons = true
	m.cfg_w_low_tiers = true
	for mode in ["effects", "deep"]:
		m.cfg_weapon_mode = mode
		_setup_player("character_well_rounded")
		m.start_new_run()
		var sword1 = isvc.get_element_safe(isvc.weapons, "weapon_sword_1")
		_check(sword1 != null, mode + ": weapon_sword_1 registered")
		if sword1 == null:
			continue
		_check(m.plan.weapons.has("weapon_sword_1"), mode + ": low weapon reassembled")
		_check(sword1 in isvc._tiers_data[0][0], mode + ": low weapon in the tier I shop pool")
		var s2 = isvc.get_element_safe(isvc.weapons, "weapon_sword_2")
		var WV = load(MOD_DIR + "aa/weapon_value.gd")
		# 各自稀有度下含效果的总价值（低级版本的效果更弱、伤害可能更高）
		var wv = WV.new()
		wv.calibrate(m.native_only(isvc.weapons))
		var p1 = wv.value(sword1.stats, sword1.effects, 0)
		var p2 = wv.value(s2.stats, s2.effects, 1)
		_check(p1 < p2, mode + ": tier I weaker than tier II (value %.1f < %.1f)" % [p1, p2])
		# 存档 / 读档：持有补出的低级武器
		var _nw = rd.add_weapon(sword1, 0)
		var saved = JSON.parse(JSON.print(rd.get_state())).result
		m.on_menu_reset()
		_check(isvc.get_element_safe(isvc.weapons, "weapon_sword_1") == null, mode + ": removed on menu reset")
		rd.resume_from_state(saved)
		var found = false
		for w in rd.get_player_weapons(0):
			if w.my_id == "weapon_sword_1":
				found = true
		_check(found, mode + ": low weapon survives save / load")
		m.on_menu_reset()
	m.cfg_weapons = false
	m.cfg_w_low_tiers = false
	m.cfg_weapon_mode = "effects"


# 仅重组效果：所有 T4 武器（效果可跨近战 / 远程）分组装备后在真实战斗中运行，原版代码不报错、武器造成伤害
func test_140_reassembled_weapons_in_battle() -> void:
	for mode in ["effects", "deep"]:
		yield(_weapons_battle(mode), "completed")


func _weapons_battle(mode: String) -> void:
	m.cfg_weapons = true
	m.cfg_weapon_mode = mode
	m.cfg_w_item_effects = mode == "deep"
	m.start_new_run()
	var t4 = []
	for w in isvc.weapons:
		if w.tier == 3 and m.plan.weapons.has(w.my_id) and w.can_be_looted:
			t4.push_back(w)
	_check(t4.size() > 40, "T4 weapons reassembled (%d)" % t4.size())
	var dealt = 0
	var total = 0
	print("AUDIT watch begin")
	for g in range(0, t4.size(), 6):
		for w in rd.get_player_weapons(0).duplicate():
			rd.remove_weapon(w, 0)
		var group = t4.slice(g, min(g + 5, t4.size() - 1))
		for w in group:
			var _nw = rd.add_weapon(w, 0)
		rd.current_wave = 8
		TempStats.reset()
		var _e = tree.change_scene("res://main.tscn")
		yield(_wait_frames(10), "completed")
		var main = tree.current_scene
		main._players[0].disable_hurtbox()
		main._wave_timer.start(600)
		yield(tree.create_timer(7.0), "timeout")
		for w in rd.get_player_weapons(0):
			total += 1
			if w.dmg_dealt_last_wave > 0:
				dealt += 1
		main._cleaning_up = true
	print("AUDIT watch end")
	print("AUDIT %s: reassembled T4 weapons dealing damage: %d / %d" % [mode, dealt, total])
	# 7 秒内敌人未必进入射程（构筑物、治疗枪等也不直接造成伤害）：主要检查的是原版代码不报错
	_check(dealt >= total * 0.5, "most reassembled weapons deal damage (%d / %d)" % [dealt, total])
	for w in rd.get_player_weapons(0).duplicate():
		rd.remove_weapon(w, 0)
	m.on_menu_reset()
	m.cfg_weapons = false
	m.cfg_weapon_mode = "effects"
	m.cfg_w_item_effects = false


# 选择武器界面：进入时提前生成，显示重组后的武器；任意初始武器列出 T1 全部武器（含补出的低级武器）；
# 难度确认沿用同一种子；返回角色选择时撤销
func test_144_weapon_selection_shows_reassembled() -> void:
	m.cfg_weapons = true
	m.cfg_weapon_mode = "deep"
	m.cfg_w_low_tiers = true
	m.cfg_w_any_start = true
	m.cfg_fixed_seed = false
	_setup_player("character_well_rounded")
	var _e = tree.change_scene(MenuData.weapon_selection_scene)
	for i in 6:
		yield(tree, "idle_frame")
	var sc = tree.current_scene
	_check(m.active_state != null, "run prepared on the weapon selection screen")
	var shown = []
	for el in sc.displayed_elements[0]:
		if el is WeaponData:
			shown.push_back(el)
	_check(shown.size() > 30, "any starting weapon: many weapons listed (%d)" % shown.size())
	var sword1 = null
	var all_t1 = true
	for w in shown:
		if w.tier != 0:
			all_t1 = false
		if w.my_id == "weapon_sword_1":
			sword1 = w
	_check(all_t1, "listed weapons are tier I (the character starts with tier I)")
	_check(sword1 != null, "lower-tier sword listed")
	if sword1 == null:
		return
	_check(m.plan.weapons.has("weapon_sword_1") and sword1.stats == m.plan.weapons["weapon_sword_1"].stats, "listed weapon shows the reassembled stats")
	var seed0 = int(m.active_state.seed)
	sc._player_weapons[0] = sword1
	sc._on_selections_completed()
	for i in 6:
		yield(tree, "idle_frame")
	m.start_new_run()
	_eq(int(m.active_state.seed), seed0, "difficulty confirmation keeps the prepared run")
	var owned = rd.get_player_weapons(0)
	_check(owned.size() > 0 and owned[0].my_id == "weapon_sword_1" and owned[0].stats == m.plan.weapons["weapon_sword_1"].stats, "selected weapon is the reassembled one")
	m.on_menu_reset()
	# 返回角色选择：撤销
	_setup_player("character_well_rounded")
	_e = tree.change_scene(MenuData.weapon_selection_scene)
	for i in 6:
		yield(tree, "idle_frame")
	_check(m.active_state != null, "prepared again")
	_e = tree.change_scene(MenuData.character_selection_scene)
	for i in 6:
		yield(tree, "idle_frame")
	_eq(m.active_state, null, "back to character selection cancels the prepared run")
	_check(isvc.get_element_safe(isvc.weapons, "weapon_sword_1") == null, "lower-tier weapons unregistered")
	m.cfg_weapons = false
	m.cfg_weapon_mode = "effects"
	m.cfg_w_low_tiers = false
	m.cfg_w_any_start = false


# 究极混沌开、允许低级武器开 -> 关：在选择武器界面打开设置切换后，界面重新载入、不再列出已注销的补出武器，选武器开局正常
func test_145_toggle_low_tiers_with_chaos() -> void:
	m.cfg_chaos = true
	m.cfg_weapons = true
	m.cfg_w_low_tiers = true
	m.cfg_w_any_start = true
	_setup_player("character_well_rounded")
	var _e = tree.change_scene(MenuData.weapon_selection_scene)
	for i in 6:
		yield(tree, "idle_frame")
	var sc = tree.current_scene
	sc.get_node("%BackButton").get_node("AutoAnthonyBtn").emit_signal("pressed")
	yield(tree, "idle_frame")
	var ui = null
	for c in sc.get_children():
		if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0).name == "AutoAnthonySettings":
			ui = c.get_child(0)
	ui._on_page_pressed("weapons")
	ui._on_preview_pressed("weapons")
	ui._on_switch_toggled(false, "cfg_w_low_tiers")
	ui._on_close_pressed()
	for i in 10:
		yield(tree, "idle_frame")
	sc = tree.current_scene
	_check(sc is WeaponSelection and sc != null, "weapon selection reloaded")
	var stale = 0
	var pick = null
	for el in sc.displayed_elements[0]:
		if el is WeaponData:
			if isvc.get_element_safe(isvc.weapons, el.my_id) == null:
				stale += 1
			elif pick == null:
				pick = el
	_eq(stale, 0, "no unregistered weapons listed after turning lower tiers off")
	sc._player_weapons[0] = pick
	sc._on_selections_completed()
	for i in 6:
		yield(tree, "idle_frame")
	m.start_new_run()
	_check(rd.get_player_weapons(0).size() > 0, "run starts with the picked weapon")
	m.on_menu_reset()
	m.cfg_chaos = false
	m.cfg_weapons = false
	m.cfg_w_any_start = false


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
		worst.push_back([abs(x - y), row[0].my_id, row[1], row[2], WV.cooldown_seconds(row[0].stats), WV.power(row[0].stats, row[0].effects, row[0].tier)])
	var r = (n * sxy - sx * sy) / sqrt(max(0.0001, (n * sxx - sx * sx) * (n * syy - sy * sy)))
	print("AUDIT weapon value fit: n %d, r^2 %.3f (log value vs log price)" % [n, r * r])
	worst.sort_custom(self, "_sort_first_desc")
	for i in min(15, worst.size()):
		var w = worst[i]
		print("AUDIT   off %s: price %d, model %.0f, cd %.2fs, power %.1f" % [w[1], w[2], w[3], w[4], w[5]])
	_check(r * r > 0.8, "weapon value model explains native prices (r^2 %.3f)" % (r * r))


# 深度重组的极端值：系数 / 伤害最大的武器（用户种子 102116457，引入道具效果 + 低级武器）
# 正常节奏的武器主加成不超过原版正常武器的水平；高系数只出现在慢速武器上；%伤害不作为加成属性
func test_146_deep_weapon_extremes() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	cfg.w_item_effects = true
	cfg.w_low_tiers = true
	var g = Generator.new(cfg, 102116457)
	g.generate(isvc.items, isvc.characters, [], [])
	var natives = m.native_only(isvc.weapons)
	var wg = WG.new(cfg, 102116457, g)
	var out = wg.generate(natives + WG.make_low_tiers(natives))
	var rows = []
	var bad = 0
	var slow = 0
	for id in out:
		var p = out[id]
		var mx = 0.0
		var txt = ""
		for sc in p.stats.scaling_stats:
			_check(WV.stat_name(sc[0]) != "stat_percent_damage", id + " does not scale with % damage")
			mx = max(mx, float(sc[1]) * WV.stat_ref(WV.stat_name(sc[0])) / WV.stat_ref("stat_melee_damage"))
			txt += "%s %.2f " % [WV.stat_name(sc[0]).replace("stat_", ""), float(sc[1])]
		var cd = WV.cooldown_seconds(p.stats)
		if WG.is_slow(p.stats):
			slow += 1
		elif mx > 2.5:
			bad += 1
			print("AUDIT strong scaling %s: %s cd %.2fs" % [id, txt, cd])
		rows.push_back([p.stats.damage / max(0.05, cd), id, p.stats.damage, txt, cd, mx])
	rows.sort_custom(self, "_sort_first_desc")
	for i in 10:
		var r = rows[i]
		print("AUDIT damage/s %s: dmg %d, %s cd %.2fs" % [r[1], r[2], r[3], r[4]])
		if i < 3:
			var pw = out[r[1]]
			var w0 = isvc.get_element_safe(isvc.weapons, r[1])
			for e in pw.effects:
				print("AUDIT     effect %s value %.1f" % [e.get_text(0, false), wg.wv.effect_value(e)])
			print("AUDIT     want %.1f, power %.1f, k %.2f, value %.1f" % [wg._want(w0 if w0 != null else pw, true) if w0 != null else -1.0, WV.power(pw.stats, pw.effects, 0), wg.wv.k(pw.stats, 0), wg.wv.value(pw.stats, pw.effects, 0)])
	print("AUDIT slow weapons %d / %d, normal weapons with melee-equivalent coef > 2.5: %d" % [slow, rows.size(), bad])
	# 基础伤害：除点燃 / 收获武器外，不低于该稀有度的下限
	var low = 0
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		var tier = w.tier if w != null else 0
		var p = out[id]
		var exempt = false
		for e in p.effects:
			if WV.effect_id(e) == "weapon_burning":
				exempt = true
		for sc in p.stats.scaling_stats:
			if WV.stat_name(sc[0]) == "stat_harvesting":
				exempt = true
		var n = 1 if WV.is_melee(p.stats) else max(1, int(p.stats.nb_projectiles))
		if not exempt and float(p.stats.damage) < floor(WG.BASE_DMG_MIN[tier] / sqrt(float(n))):
			low += 1
			print("AUDIT low base damage %s: %d (%s)" % [id, p.stats.damage, str(p.stats.scaling_stats)])
	_check(low <= rows.size() / 50, "few weapons below the base damage floor (%d)" % low)
	_check(bad == 0, "normal-pace weapons keep native-like scaling (%d)" % bad)
	_check(slow < rows.size() / 5, "slow weapons are uncommon (%d)" % slow)


# 深度重组价值拆解：截图中的典型武器（种子 66622907 的 T1、812597668 的 T4），以及原版参照
func test_147_deep_value_breakdown() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var natives = m.native_only(isvc.weapons)
	var cases = {
		66622907: ["weapon_dagger_1", "weapon_double_barrel_shotgun_1", "weapon_fist_1", "weapon_crossbow_1", "weapon_ghost_scepter_1", "weapon_hand_1"],
		812597668: ["weapon_chain_gun_4", "weapon_chainsaw_4", "weapon_blunderbuss_4", "weapon_anchor_4", "weapon_captains_sword_4", "weapon_brick_4"],
		867169211: ["weapon_brick_4", "weapon_knife_4", "weapon_bloody_vorpal_4", "weapon_sword_4"],
	}
	for sd in cases:
		var cfg = _cfg()
		cfg.weapons = true
		cfg.weapon_mode = "deep"
		cfg.w_item_effects = true
		var g = Generator.new(cfg, sd)
		g.generate(isvc.items, isvc.characters, [], [])
		var wg = WG.new(cfg, sd, g)
		var out = wg.generate(natives)
		for id in cases[sd]:
			var w = isvc.get_element_safe(isvc.weapons, id)
			# 角色选择界面的测试会按无头配置卸下 DLC 资源（原版行为）：DLC 武器不在时跳过
			if w == null or not out.has(id):
				print("AUDIT (skipped %s: not loaded)" % id)
				continue
			_breakdown(wg, WV, "NATIVE " + id, w.stats, w.effects, w.tier, float(w.value), wg.wv.value(w.stats, w.effects, w.tier))
			var p = out[id]
			_breakdown(wg, WV, "DEEP   " + id, p.stats, p.effects, w.tier, float(w.value), wg._want(w, true) * wg._family_mult(WG.family_of(w)))


func _breakdown(wg, WV, label: String, st, effects: Array, tier: int, price: float, want: float) -> void:
	var cd = WV.cooldown_seconds(st)
	var base = float(st.damage)
	var scal = WV.hit_damage(0.0, st.scaling_stats, tier)
	var hit = base + scal
	var crit = WV.crit_factor(st)
	var ok = WV.overkill(hit * crit, tier) / max(0.01, hit * crit)
	var hits = WV.hits_per_attack(st)
	var p = WV.power(st, effects, tier)
	var p_plain = WV.power(st, [], tier)
	var k = wg.wv.k(st, tier)
	var txt = ""
	var fx = 0.0
	for e in effects:
		var v = wg.wv.effect_value(e)
		fx += v
		txt += "[%s = %.0f] " % [e.get_text(0, false).left(28), v]
	print("AUDIT %s T%d price %d want %.0f | dmg %d + scaling %.0f (cd %.2fs, crit x%.2f, overkill x%.2f, hits %.2f) | power %.0f (%.0f w/o modeled fx) x k %.2f = %.0f | effects %.0f | total %.0f" % [
		label, tier + 1, price, want, base, scal, cd, crit, ok, hits, p, p_plain, k, k * p, fx, k * p + fx])
	if txt != "":
		print("AUDIT        " + txt)


func test_148_legendary_values() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var wv = WV.new()
	var natives = m.native_only(isvc.weapons)
	wv.calibrate(natives)
	for id in ["weapon_chain_gun_4", "weapon_gatling_laser_4", "weapon_dextroyer_4", "weapon_drill_4", "weapon_excalibur_4", "weapon_scythe_4", "weapon_minigun_4", "weapon_obliterator_4", "weapon_sword_4", "weapon_smg_4"]:
		var w = isvc.get_element_safe(isvc.weapons, id)
		var fx = ""
		for e in w.effects:
			fx += "[%s %.0f] " % [WV.effect_key(e), wv.effect_value(e)]
		print("AUDIT legendary %s price %d model %.0f power %.0f %s" % [id, w.value, wv.value(w.stats, w.effects, 3), WV.power(w.stats, w.effects, 3), fx])


# 武器名称：每个家族一个特性形容词（各稀有度相同、形容词多样），回到菜单还原；"保留原名"时不改名
func test_150_weapon_names() -> void:
	m.cfg_weapons = true
	for mode in ["effects", "deep"]:
		m.cfg_weapon_mode = mode
		var before = {}
		for w in isvc.weapons:
			before[w.my_id] = w.name
		_setup_player("character_well_rounded")
		m.start_new_run()
		var adjs = {}
		for w in isvc.weapons:
			if not m.plan.weapons.has(w.my_id):
				continue
			var p = m.plan.weapons[w.my_id]
			_check(p.has("adj") and w.name != before[w.my_id], w.my_id + " renamed")
			adjs[p.adj] = adjs.get(p.adj, 0) + 1
		_check(adjs.size() >= 15, mode + ": varied weapon adjectives (%d)" % adjs.size())
		print("AUDIT %s weapon adjectives %s" % [mode, str(adjs)])
		m.on_menu_reset()
		var restored = true
		for w in isvc.weapons:
			if before.has(w.my_id) and w.name != before[w.my_id]:
				restored = false
		_check(restored, mode + ": names restored")
	m.cfg_w_rename = false
	var sword = isvc.get_element_safe(isvc.weapons, "weapon_sword_2")
	var native_name = sword.name
	m.start_new_run()
	_eq(sword.name, native_name, "keep original weapon names")
	m.on_menu_reset()
	m.cfg_w_rename = true
	m.cfg_weapons = false
	m.cfg_weapon_mode = "effects"


# 加成属性只用当前可用的属性：未启用 DLC（玩家属性表里没有诅咒）时不生成诅咒加成
func test_151_scaling_stats_available() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var keys = PlayerRunData.init_effects()
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	var natives = m.native_only(isvc.weapons)
	var used = {}
	for w in natives:
		for x in w.stats.scaling_stats:
			used[WV.stat_name(x[0])] = true
	for sd in [1, 2, 3]:
		var out = Generator.new(cfg, sd).generate_weapons(natives)
		for id in out:
			for x in out[id].stats.scaling_stats:
				var st = WV.stat_name(x[0])
				_check(keys.has(Keys.generate_hash(st)) or used.has(st), "%s scales with an available stat: %s" % [id, st])


func test_152_tier_value_ratio() -> void:
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	var wg = WG.new(cfg, 1)
	var out = wg.generate(m.native_only(isvc.weapons))
	print("AUDIT value / price by type/tier: " + str(wg._vp))
	var sums = {}
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		var key = str(w.type) + "/" + str(w.tier)
		if not sums.has(key):
			sums[key] = [0.0, 0.0, 0]
		sums[key][0] += load(MOD_DIR + "aa/weapon_value.gd").power(out[id].stats, out[id].effects, w.tier)
		sums[key][1] += load(MOD_DIR + "aa/weapon_value.gd").power(w.stats, w.effects, w.tier)
		sums[key][2] += 1
	for key in sums:
		print("AUDIT %s mean power deep %.0f native %.0f" % [key, sums[key][0] / sums[key][2], sums[key][1] / sums[key][2]])


# "+X 伤害"类效果（船长之剑、棍子）按 X / 面板伤害估值：同一效果放在低伤害武器上增幅更大
func test_153_flat_damage_effects_relative() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var stick = isvc.get_element_safe(isvc.weapons, "weapon_stick_1")
	var fx = stick.effects
	var lo = stick.stats.duplicate()
	lo.damage = 5
	var hi = stick.stats.duplicate()
	hi.damage = 60
	var gain_lo = WV.power(lo, fx, 0) / WV.power(lo, [], 0)
	var gain_hi = WV.power(hi, fx, 0) / WV.power(hi, [], 0)
	print("AUDIT stick +X damage: relative gain at 5 dmg %.2f, at 60 dmg %.2f" % [gain_lo, gain_hi])
	_check(gain_lo > 1.0 and gain_hi > 1.0, "flat damage effect adds power")
	_check(gain_lo - 1.0 > (gain_hi - 1.0) * 2.0, "worth relatively more on a low-damage weapon")


# 效果里的暴击 / 元素属性不给词条：精准类别只来自高暴击面板，元素类别只来自元素加成与燃烧（默认设置：深度重组 + 道具效果）
func test_154_effect_crit_elemental_no_tag() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	cfg.w_item_effects = true
	for sd in [3, 23]:
		var g = Generator.new(cfg, sd)
		g.generate(isvc.items, isvc.characters, [], [])
		var wg = WG.new(cfg, sd, g)
		var out = wg.generate(weapons)
		var set_count = {}
		var fams = {}
		var burning = 0
		var elem = 0
		for id in out:
			var w = isvc.get_element_safe(isvc.weapons, id)
			var f = WG.family_of(w)
			if fams.has(f):
				continue
			fams[f] = true
			var p = out[id]
			var tags = wg.weapon_tags(w.type, p.stats, p.effects)
			var high_crit = float(p.stats.crit_chance) >= WG.HIGH_CRIT_CHANCE or float(p.stats.crit_damage) >= WG.HIGH_CRIT_DAMAGE
			_eq("stat_crit_chance" in tags, high_crit, f + " crit tag only from the stat panel")
			var elem_scaling = false
			for sc in p.stats.scaling_stats:
				if WV.stat_name(sc[0]) == "stat_elemental_damage" and float(sc[1]) > 0:
					elem_scaling = true
			_eq("stat_elemental_damage" in tags, elem_scaling, f + " elemental tag only from scaling")
			for x in p.sets:
				set_count[x.my_id] = set_count.get(x.my_id, 0) + 1
			if "burning" in tags or "burning_main" in tags:
				burning += 1
			if elem_scaling:
				elem += 1
		print("AUDIT default sets seed %d %s; burning %d, elemental scaling %d" % [sd, str(set_count), burning, elem])
		print("AUDIT native sets %s" % str(wg._set_native_count))
