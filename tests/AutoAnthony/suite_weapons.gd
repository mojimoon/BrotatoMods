extends "res://mods/tests/AutoAnthony/test_base.gd"

# weapons：武器重组的全部测试（价值模型、仅重组效果、深度重组、道具效果、低级武器、混沌、名称、真实战斗与选择武器界面）


func _keys_of(effects: Array) -> Array:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var ks = []
	for e in effects:
		ks.push_back(WV.effect_key(e))
	return ks


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
	var lifted = 0
	var over = 0
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
				_check(WV.effect_key(e) in _keys_of(w.effects), "%s keeps only its own family-bound effect %s" % [id, WV.effect_key(e)])
		# 绑定效果按 key 比较（参数按家族随机）
		for e in w.effects:
			if WG.bound_key(e):
				_check(WV.effect_key(e) in _keys_of(p.effects), "%s keeps its family-bound effect" % id)
		# 价值守恒：新武器价值 = 原价值 × 家族浮动（伤害取整误差内）
		var want = wg._want(w) * wg._family_mult(WG.family_of(w))
		var got = wg.wv.value(p.stats, p.effects, w.tier)
		# 为不倒挂而抬高伤害的武器会超出目标，单独计数
		# 负面效果抵扣封顶的武器价值低于目标，不计
		if p.get("capped", false):
			continue
		if p.get("lifted", false):
			lifted += 1
			if got > want * 1.3:
				over += 1
				print("AUDIT lifted over target %s: want %.1f got %.1f" % [id, want, got])
		elif abs(got - want) > max(3.0, want * 0.15):
			off += 1
			print("AUDIT weapon value off %s: want %.1f got %.1f (scale %.2f)" % [id, want, got, p.scale])
	_check(changed > out.size() / 2, "most weapons got another family's effects (%d)" % changed)
	_check(cross > 0, "effects cross melee / ranged (%d)" % cross)
	_check(off <= out.size() / 20, "weapon values match the target (%d off)" % off)
	print("AUDIT lifted %d, of which > 1.3x target %d" % [lifted, over])
	_check(over <= out.size() / 10, "few lifted weapons far above target (%d)" % over)
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
				if e.key in WG.VALUE2_TENTH_KEYS and "value2" in e:
					_eq(float(e.value2), float(e.value) / 10.0, id + " boss / elite percent follows the value")
			# 最低一级按抽到的价格定目标价值；更高一级按实际价值重新定价，价值 / 价格同样落在同档原版的比例上
			var fm = wg._family_mult(WG.family_of(w))
			var want = wg._want(w, true) * fm
			# 更高一级：成长受限时价值可以低于价格对应的目标（不降价），只检查不超出
			var upper = w.tier > wg.families[WG.family_of(w)].tiers.keys().min()
			if upper:
				want = float(p.price) * float(wg._vp.get(str(w.type) + "/" + str(w.tier), 1.0)) * fm
			var got = wg.wv.value(p.stats, p.effects, w.tier)
			for sc in p.stats.scaling_stats:
				if float(sc[1]) > 0:
					_check(float(sc[1]) >= WG.SCALING_FLOOR.get(WV.stat_name(sc[0]), 0.0) - 0.001, "%s coef %s %.2f >= floor" % [id, WV.stat_name(sc[0]), float(sc[1])])
			# 为不倒挂而抬高伤害的武器会超出目标，不计
			if not p.get("lifted", false) and not p.get("capped", false) and (got - want if upper else abs(got - want)) > max(3.0, want * 0.15):
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
# 两种模式各测一半 T4 武器（按 6 把一组交替），合起来每把都上场一次；主要检查原版代码在重组武器下不报错
func test_140_reassembled_weapons_in_battle() -> void:
	var i = 0
	for mode in ["effects", "deep"]:
		yield(_weapons_battle(mode, i), "completed")
		i += 1


func _weapons_battle(mode: String, parity: int) -> void:
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
	for g in range(parity * 6, t4.size(), 12):
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
		yield(tree.create_timer(5.0), "timeout")
		for w in rd.get_player_weapons(0):
			total += 1
			if w.dmg_dealt_last_wave > 0:
				dealt += 1
		main._cleaning_up = true
	print("AUDIT watch end")
	print("AUDIT %s: reassembled T4 weapons dealing damage: %d / %d" % [mode, dealt, total])
	# 5 秒内敌人未必进入射程（构筑物、治疗枪等也不直接造成伤害）：主要检查的是原版代码不报错
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
	_check(r * r > 0.78, "weapon value model explains native prices (r^2 %.3f)" % (r * r))


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
func test_147_deep_value_audit_row() -> void:
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
			_audit_row(wg, WV, "NATIVE " + id, w.stats, w.effects, w.tier, float(w.value), wg.wv.value(w.stats, w.effects, w.tier))
			var p = out[id]
			_audit_row(wg, WV, "DEEP   " + id, p.stats, p.effects, w.tier, float(w.value), wg._want(w, true) * wg._family_mult(WG.family_of(w)))


func _audit_row(wg, WV, label: String, st, effects: Array, tier: int, price: float, want: float) -> void:
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
			var high_crit = WG.is_high_crit(p.stats)
			for sc in p.stats.scaling_stats:
				if WV.stat_name(sc[0]) == "stat_crit_chance" and float(sc[1]) > 0:
					high_crit = true
			_eq("stat_crit_chance" in tags, high_crit, f + " crit tag only from the stat panel or crit scaling")
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


# 玩家设置（深度重组 + 道具效果）在固定种子下走设置界面逐页预览武器。
# 曾因 Array.sort() 比较数组在正式版闪退（调试版只报 "bad comparison function"，run_tests.sh 会把它算作失败）
func test_155_weapon_preview_player_seed() -> void:
	m.cfg_items = true
	m.cfg_weapons = true
	m.cfg_weapon_mode = "deep"
	m.cfg_w_item_effects = true
	m.cfg_w_any_start = true
	m.cfg_w_low_tiers = false
	m.cfg_fixed_seed = true
	m.cfg_seed = 33772723
	var ui = load(MOD_DIR + "ui/settings_ui.tscn").instance()
	tree.root.add_child(ui)
	ui._on_page_pressed("weapons")
	ui._on_preview_pressed("weapons")
	for t in 4:
		ui._on_tier_pressed(t, "weapons")
		yield(tree, "idle_frame")
		_check(ui._pv.weapons.grid.get_child_count() > 5, "tier %d rendered" % t)
	ui.queue_free()


# 审计：某个种子的 T4 预览武器与同家族原版 T4 的模型拆解（AA_ONLY=test_156 单独运行）
func test_156_audit_t4_vs_native() -> void:
	# 纯审计（只打印）：AA_AUDIT=1 时才运行
	if OS.get_environment("AA_AUDIT") == "":
		return
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.items = false
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	cfg.w_item_effects = true
	cfg.w_any_start = true
	var sd = 333729899
	var g = Generator.new(cfg, sd)
	g.generate(m.native_only(isvc.items), m.native_only(isvc.characters), [], weapons)
	var wg = WG.new(cfg, sd, g)
	var out = wg.generate(weapons)
	var rows = []
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		if w.tier == 3:
			rows.push_back([id, w])
	rows.sort_custom(self, "_audit_by_id")
	var want_ids = ["icicle", "javelin", "jousting_lance", "knife", "laser_gun", "lightning_shiv", "lute", "mace", "medical_gun", "minigun", "nuclear_launcher", "obliterator", "spiky", "spear", "lance", "ice"]
	for r in rows:
		var hit = false
		for x in want_ids:
			if r[0].find(x) >= 0:
				hit = true
		if not hit:
			continue
		var w = r[1]
		var p = out[r[0]]
		print("AUDIT T4 %s %s" % [r[0], tr(p.get("adj", ""))])
		print("AUDIT    gen  " + _t4_row(wg, p.stats, p.effects, w, p))
		print("AUDIT    nat  " + _t4_row(wg, w.stats, w.effects, w, null))


func _audit_by_id(a, b) -> bool:
	return a[0] < b[0]


func _t4_row(wg, st, effects: Array, w, p) -> String:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var cd = WV.cooldown_seconds(st)
	var hit = WV.hit_damage(float(st.damage), st.scaling_stats, 3)
	var crit = WV.crit_factor(st)
	var hits = WV.hits_per_attack(st)
	var raw = hit * crit * hits / cd
	var pw = WV.power(st, effects, 3)
	var fx = 0.0
	for e in effects:
		fx += wg.wv.effect_value(e)
	var val = wg.wv.value(st, effects, 3)
	var want = wg._want(w, p != null) * wg._family_mult(load(MOD_DIR + "aa/weapon_gen.gd").family_of(w)) if p != null else wg._want(w)
	return "price %d dmg %d sc %s cd %.2f hit %.1f crit %.2f hits %.2f rawDPS %.1f power %.1f k %.2f fxVal %.1f value %.1f want %.1f" % [
		int(p.get("price", w.value)) if p != null else int(w.value), int(st.damage), str(st.scaling_stats), cd, hit, crit, hits, raw, pw, wg.wv.k(st, 3), fx, val, want]


# 审计：原版武器按特性分组的"模型价值 / 价格"相对同档中位数的偏差（<1 = 模型低估了这类特性）
func test_157_audit_feature_residuals() -> void:
	# 纯审计（只打印）：AA_AUDIT=1 时才运行
	if OS.get_environment("AA_AUDIT") == "":
		return
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	var wg = WG.new(cfg, 1)
	wg.generate(weapons)
	var groups = {}
	for w in weapons:
		if wg.wv.legendary_families.has(WG.family_of(w)):
			continue
		var r = wg.wv.value(w.stats, w.effects, w.tier) / float(w.value) / float(wg._vp.get(str(w.type) + "/" + str(w.tier), 1.0))
		var feats = ["all"]
		if w.type == 1 and int(w.stats.nb_projectiles) > 1:
			feats.push_back("multi_proj")
		if w.type == 1 and int(w.stats.piercing) > 0:
			feats.push_back("pierce")
		if w.type == 1 and w.stats.can_bounce and int(w.stats.bounce) > 0:
			feats.push_back("bounce")
		if float(w.stats.crit_chance) >= 0.15:
			feats.push_back("high_crit")
		if WV.cooldown_seconds(w.stats) >= 1.4:
			feats.push_back("slow")
		if WV.cooldown_seconds(w.stats) <= 0.5:
			feats.push_back("fast")
		var hit = WV.hit_damage(float(w.stats.damage), w.stats.scaling_stats, w.tier)
		if hit > 0 and float(w.stats.damage) / hit > 0.6:
			feats.push_back("base_heavy")
		elif hit > 0 and float(w.stats.damage) / hit < 0.3:
			feats.push_back("scaling_heavy")
		for e in w.effects:
			var id = WV.effect_id(e)
			if id in ["weapon_burning", "weapon_exploding", "weapon_projectiles_on_hit"]:
				feats.push_back(id)
			elif not WV.is_modeled(e) and not WV.is_plain_player_stat(e):
				feats.push_back("unmodeled_fx")
			elif WV.is_plain_player_stat(e):
				feats.push_back("stat_line")
		if "fast" in feats or "multi_proj" in feats or "bounce" in feats:
			print("AUDIT   %s %s r %.2f cd %.2f proj %d pierce %d bounce %d hit %.1f" % [w.my_id, str(feats.slice(1, feats.size() - 1)), r, WV.cooldown_seconds(w.stats), int(w.stats.nb_projectiles), int(w.stats.piercing), int(w.stats.bounce), WV.hit_damage(float(w.stats.damage), w.stats.scaling_stats, w.tier)])
		for f in feats:
			if not groups.has(f):
				groups[f] = []
			groups[f].push_back(log(max(0.01, r)))
	for f in groups:
		var a: Array = groups[f]
		var s = 0.0
		for x in a:
			s += x
		var mean = exp(s / a.size())
		a.sort()
		print("AUDIT feature %-26s n %3d  geo-mean value/price vs tier median %.2f  median %.2f" % [f, a.size(), mean, exp(a[a.size() / 2])])


# 深度重组的价格重新抽样：同为 T4，最低 T1 < 最低 T2 < 最低 T3 < 传奇（均价）；砖头价格固定；多数价格有变化
func test_158_deep_price_resample() -> void:
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	var wg = WG.new(cfg, 5)
	var out = wg.generate(weapons)
	var lows = {}
	for w in weapons:
		var f = WG.family_of(w)
		lows[f] = min(lows.get(f, 3), w.tier)
	var sums = [0.0, 0.0, 0.0, 0.0]
	var ns = [0, 0, 0, 0]
	var changed = 0
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		var price = int(out[id].get("price", -1))
		_check(price > 0, id + " has a price")
		if price != int(w.value):
			changed += 1
		if WG._is_brick(wg.families[WG.family_of(w)]):
			_eq(price, int(w.value), id + " brick keeps its price")
		if w.tier == 3:
			var lo = lows[WG.family_of(w)]
			sums[lo] += price
			ns[lo] += 1
	var means = []
	for i in 4:
		means.push_back(sums[i] / max(1, ns[i]))
	print("AUDIT T4 mean price by lowest tier %s (n %s)" % [str(means), str(ns)])
	# 更高一级按实际价值重新定价：相对抽到的价格阶梯（各稀有度的中位数）
	var rel = [[], [], [], []]
	for id in out:
		var w = isvc.get_element_safe(isvc.weapons, id)
		rel[w.tier].push_back(float(out[id].price) / max(1.0, wg._price_of(w)))
	for t in 4:
		rel[t].sort()
		if not rel[t].empty():
			print("AUDIT T%d repriced / ladder: p10 %.2f median %.2f p90 %.2f" % [t + 1, rel[t][rel[t].size() / 10], rel[t][rel[t].size() / 2], rel[t][rel[t].size() * 9 / 10]])
	for i in 3:
		if ns[i] > 0 and ns[i + 1] > 0:
			_check(means[i] < means[i + 1], "T4 lowest T%d cheaper than lowest T%d" % [i + 1, i + 2])
	_check(changed > out.size() / 2, "most prices resampled (%d / %d)" % [changed, out.size()])


# 估值参数随机搜索（AA_SEARCH=<次数> 时才运行）：各稀有度的参考属性阶段 TIER_STAT_FRAC[0..2]、武器属性行倍率。
# 目标 = 原版"价值 / 价格"（相对同档中位数）的对数方差 + 2 × 各特性组偏差平方的加权和（多发 / 贯穿 / 弹跳除外）；不含传奇与 99 贯穿的火焰类
func test_160_search_value_params() -> void:
	var n_try = int(OS.get_environment("AA_SEARCH")) if OS.get_environment("AA_SEARCH").is_valid_integer() else 0
	if n_try <= 0:
		return
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var all = m.native_only(isvc.weapons)
	var base_frac = WV.TIER_STAT_FRAC.duplicate()
	var base_on_hit = WV.ON_HIT_DPS[0]
	var wv0 = WV.new()
	wv0.calibrate(all)
	var rows = []
	for w in all:
		if w.stats == null or int(w.value) <= 0 or wv0.legendary_families.has(WV._family(w)) or (w.type == 1 and int(w.stats.piercing) >= 50):
			continue
		var groups = []
		var hit = WV.hit_damage(float(w.stats.damage), w.stats.scaling_stats, w.tier)
		var share = float(w.stats.damage) / max(0.01, hit)
		groups.push_back("T%d %s" % [w.tier + 1, "base" if share > 0.6 else ("scal" if share < 0.3 else "mid")])
		if WV.cooldown_seconds(w.stats) <= 0.5:
			groups.push_back("fast")
		if WV.cooldown_seconds(w.stats) >= 1.4:
			groups.push_back("slow")
		if w.type == 1 and int(w.stats.nb_projectiles) > 1:
			groups.push_back("multi_proj")
		if w.type == 1 and int(w.stats.piercing) > 0:
			groups.push_back("pierce")
		if w.type == 1 and w.stats.can_bounce and int(w.stats.bounce) > 0:
			groups.push_back("bounce")
		if float(w.stats.crit_chance) >= 0.15:
			groups.push_back("high_crit")
		for e in w.effects:
			if WV.is_plain_player_stat(e):
				groups.push_back("stat_line")
				break
		rows.push_back([w, groups])
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var results = []
	for i in n_try + 1:
		var c = [base_frac[0], base_frac[1], base_frac[2], WV.STAT_LINE_MULT, WV.ON_HIT_DPS[0]]
		if i > 0:
			c[0] = rng.randf_range(0.05, 0.45)
			c[1] = rng.randf_range(max(c[0], 0.2), 0.7)
			c[2] = rng.randf_range(max(c[1], 0.45), 0.95)
			c[3] = rng.randf_range(0.8, 4.0)
			c[4] = rng.randf_range(0.0, 20.0)
		results.push_back([_eval_value_params(WV, all, rows, c), c])
		_set_frac(WV, [base_frac[0], base_frac[1], base_frac[2], 0, base_on_hit])
	print("AUDIT search baseline obj %.4f var %.4f bias %.4f %s %s" % [results[0][0][0], results[0][0][1], results[0][0][2], str(results[0][1]), str(results[0][0][3])])
	results.sort_custom(self, "_sort_first_asc")
	for r in results.slice(0, 7):
		print("AUDIT search obj %.4f var %.4f bias %.4f frac %.2f %.2f %.2f statmult %.2f onhit %.1f %s" % [r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[1][3], r[1][4], str(r[0][3])])


# 常量数组只能取出引用后修改（Godot 3 的常量数组本身可变）
func _set_frac(WV, c: Array) -> void:
	var fr: Array = WV.TIER_STAT_FRAC
	for i in 3:
		fr[i] = c[i]
	var oh: Array = WV.ON_HIT_DPS
	oh[0] = c[4]


func _sort_first_asc(a, b) -> bool:
	return a[0][0] < b[0][0]


func _eval_value_params(WV, all: Array, rows: Array, c: Array) -> Array:
	_set_frac(WV, c)
	var wv = WV.new()
	wv.stat_line_mult = c[3]
	wv.calibrate(all)
	var by = {}
	var lr = []
	for r in rows:
		var w = r[0]
		var key = str(w.type) + "/" + str(w.tier)
		var x = wv.value(w.stats, w.effects, w.tier) / float(w.value)
		lr.push_back(x)
		if not by.has(key):
			by[key] = []
		by[key].push_back(x)
	var med = {}
	for key in by:
		var a: Array = by[key]
		a.sort()
		med[key] = a[a.size() / 2]
	var sums = {}
	var tot = 0.0
	var tot2 = 0.0
	for i in rows.size():
		var w = rows[i][0]
		var l = log(max(0.01, lr[i] / med[str(w.type) + "/" + str(w.tier)]))
		tot += l
		tot2 += l * l
		for g in rows[i][1]:
			if not sums.has(g):
				sums[g] = [0.0, 0]
			sums[g][0] += l
			sums[g][1] += 1
	var n = float(rows.size())
	var var_ = tot2 / n - pow(tot / n, 2)
	var bias = 0.0
	var gm = {}
	for g in sums:
		var mean = sums[g][0] / sums[g][1]
		# 多发 / 贯穿 / 弹跳按打满计是定下的规则，不参与目标
		if not g in ["multi_proj", "pierce", "bounce"]:
			bias += float(sums[g][1]) / n * mean * mean
		gm[g] = stepify(exp(mean), 0.01)
	return [var_ + 2.0 * bias, var_, bias, gm]


# 伤害不倒挂（两种模式）：同一家族高一级的基础伤害与每项加成系数不低于低一级；
# effects 模式特效逐级强化，deep 模式允许持平但不倒挂；固定参数的效果按家族随机（砖头碎裂几率保持 1%、自伤 1–3）；有最小范围的武器范围足够大；原版砖头按寿命折扣估值后与按价格的估值相近
func _stronger(WV, e, q) -> bool:
	match WV.effect_id(e):
		"weapon_exploding":
			return float(e.chance) > float(q.chance) or float(q.chance) >= 1.0
		"weapon_burning":
			return e.burning_data == null or int(e.burning_data.damage) > int(q.burning_data.damage)
		"weapon_projectiles_on_hit":
			return int(e.value) > int(q.value) or int(e.weapon_stats.damage) > int(q.weapon_stats.damage)
	if not "value" in e or WV.magnitude(q) < 0 or float(q.value) < 0 or (float(e.value) == 0 and float(q.value) == 0):
		return true
	return WV.magnitude(e) > WV.magnitude(q) or int(q.value) >= 100


func _effect_non_decreasing(WV, e, q) -> bool:
	match WV.effect_id(e):
		"weapon_exploding":
			return float(e.chance) + 0.000001 >= float(q.chance)
		"weapon_burning":
			return q.burning_data == null or (e.burning_data != null and int(e.burning_data.damage) >= int(q.burning_data.damage))
		"weapon_projectiles_on_hit":
			return int(e.value) >= int(q.value) and (q.weapon_stats == null or (e.weapon_stats != null and int(e.weapon_stats.damage) >= int(q.weapon_stats.damage)))
	return WV.magnitude(e) + 0.000001 >= WV.magnitude(q)


func _has_key(WV, effects: Array, key: String) -> bool:
	for e in effects:
		if WV.effect_key(e) == key:
			return true
	return false


func _crit_scaling(WV, st) -> bool:
	for sc in st.scaling_stats:
		if WV.stat_name(sc[0]) == "stat_crit_chance" and float(sc[1]) > 0:
			return true
	return false


func test_162_no_inversion_and_fixed_params() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	for mode in ["effects", "deep"]:
		var cfg = _cfg()
		cfg.weapons = true
		cfg.weapon_mode = mode
		for sd in [3, 11]:
			var wg = WG.new(cfg, sd)
			var out = wg.generate(weapons)
			var bad = 0
			var weak = 0
			for f in wg.fam_names:
				var tiers = wg.families[f].tiers.keys()
				tiers.sort()
				var prev = null
				var chance = -1
				for t in tiers:
					var p = out.get(wg.families[f].tiers[t].my_id)
					if p == null:
						continue
					if prev != null:
						if p.stats.damage < prev.stats.damage:
							bad += 1
							print("AUDIT inversion %s T%d damage %d < %d" % [f, t + 1, p.stats.damage, prev.stats.damage])
						for x in p.stats.scaling_stats:
							for y in prev.stats.scaling_stats:
								if x[0] == y[0] and float(y[1]) >= 0 and float(x[1]) < float(y[1]):
									bad += 1
									print("AUDIT inversion %s T%d coef %s < %s" % [f, t + 1, str(x[1]), str(y[1])])
					for e in p.effects:
						if WV.effect_key(e) == "break_on_hit":
							_eq(int(e.value), 1, f + " break chance stays 1%")
						if WV.effect_key(e) == "lose_hp_per_second":
							_check(int(e.value) >= 1 and int(e.value) <= 3, f + " self damage 1-3")
						# 同 key：effects 严格增强（已到上限的除外），deep 允许原版 no-op。
						if prev != null:
							for q in prev.effects:
								if WV.effect_key(q) == WV.effect_key(e) and not WV.effect_key(e) in WG.NO_STRENGTHEN_KEYS and not WV.effect_key(e).begins_with("structure:"):
									if not (_stronger(WV, e, q) if mode == "effects" else _effect_non_decreasing(WV, e, q)):
										weak += 1
										print("AUDIT not strengthened %s T%d %s %s vs %s mag %s vs %s" % [f, t + 1, WV.effect_key(e), str(e.value), str(q.value), str(WV.magnitude(e)), str(WV.magnitude(q))])
									break
					# 标枪效果绑定 0% 暴击 + 高暴伤；没有标枪效果的武器不用这个模板（深度重组）；0% 暴击不算精准
					var has_jav = _has_key(WV, p.effects, WG.JAVELIN_KEY)
					if has_jav:
						_check(float(p.stats.crit_chance) == 0 and float(p.stats.crit_damage) >= WG.HIGH_CRIT_DAMAGE, "%s javelin effect binds 0%% crit x%.2f" % [f, float(p.stats.crit_damage)])
					elif mode == "deep":
						_check(not WG.is_javelin_template(p.stats), "%s has no javelin crit template without the javelin effect" % f)
					if float(p.stats.crit_chance) == 0:
						_check(not "stat_crit_chance" in wg.weapon_tags(wg.families[f].type, p.stats, p.effects) or _crit_scaling(WV, p.stats), "%s 0%% crit has no crit tag" % f)
					if int(p.stats.min_range) > 0:
						_check(int(p.stats.max_range) >= int(p.stats.min_range) + 100, "%s range %d-%d is wide" % [f, int(p.stats.min_range), int(p.stats.max_range)])
					prev = p
			_eq(bad, 0, "%s seed %d: no tier has lower damage / scaling than the tier below" % [mode, sd])
			_eq(weak, 0, "%s seed %d: effects %s" % [mode, sd, "get stronger every tier" if mode == "effects" else "never decrease (ties allowed)"])
	var wv = WV.new()
	wv.calibrate(weapons)
	var wg2 = WG.new(_cfg(), 1)
	wg2.generate(weapons)
	for w in weapons:
		if WG.family_of(w) == "weapon_brick":
			var by_price = float(w.value) * float(wg2._vp.get(str(w.type) + "/" + str(w.tier), 1.0))
			var r = wv.value(w.stats, w.effects, w.tier) / by_price
			print("AUDIT brick %s value / by-price %.2f (brick_k %.2f)" % [w.my_id, r, wv.brick_k])
			_check(r > 0.4 and r < 2.5, w.my_id + " valued near its price after the life discount (%.2f)" % r)


# 审计：模型之外的强度指标——参考属性下不含效果的原始 DPS / 价格（相对原版同类型同稀有度的中位数）。
# 比较生成武器与原版的离散度，列出最强 / 最弱的生成武器（默认设置：深度重组 + 道具效果）
func test_163_audit_raw_dps_spread() -> void:
	# 纯审计（只打印）：AA_AUDIT=1 时才运行
	if OS.get_environment("AA_AUDIT") == "":
		return
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var weapons = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	cfg.w_item_effects = true
	var med = {}
	var nat = []
	for w in weapons:
		var key = str(w.type) + "/" + str(w.tier)
		var r = _raw_dps(WV, w.stats, w.tier) / float(w.value)
		if not med.has(key):
			med[key] = []
		med[key].push_back(r)
	for key in med:
		med[key].sort()
		med[key] = med[key][med[key].size() / 2]
	for w in weapons:
		nat.push_back(log(_raw_dps(WV, w.stats, w.tier) / float(w.value) / med[str(w.type) + "/" + str(w.tier)]))
	var rows = []
	var gen = []
	var fxs = []
	for sd in [3, 23, 333729899]:
		var g = Generator.new(cfg, sd)
		g.generate(m.native_only(isvc.items), m.native_only(isvc.characters), [], [])
		var wg = WG.new(cfg, sd, g)
		var out = wg.generate(weapons)
		for id in out:
			var w = isvc.get_element_safe(isvc.weapons, id)
			var p = out[id]
			var price = float(p.get("price", w.value))
			var r = _raw_dps(WV, p.stats, w.tier) / price / med[str(w.type) + "/" + str(w.tier)]
			gen.push_back(log(r))
			var val = wg.wv.value(p.stats, p.effects, w.tier)
			var fx = val - wg.wv.value(p.stats, [], w.tier)
			fxs.push_back(fx / max(1.0, val))
			var keys = []
			for e in p.effects:
				keys.push_back("%s(%.0f)" % [WV.effect_key(e), wg.wv.effect_value(e)])
			rows.push_back([r, "%s T%d price %d raw x%.2f value/want %.2f fx %.0f%% %s%s cd %.2f crit %.2f hits %.2f %s" % [id, w.tier + 1, int(price), r, val / max(1.0, float(p.get("want", val))), fx / max(1.0, val) * 100, "lifted " if p.get("lifted", false) else "", str(p.stats.scaling_stats), WV.cooldown_seconds(p.stats), WV.crit_factor(p.stats), WV.hits_per_attack(p.stats), str(keys)]])
	print("AUDIT raw DPS / price log-sd: native %.3f  generated %.3f (n %d / %d)" % [_sd(nat), _sd(gen), nat.size(), gen.size()])
	rows.sort_custom(self, "_sort_first_num")
	print("AUDIT weakest:")
	for r in rows.slice(0, 9):
		print("AUDIT   " + r[1])
	print("AUDIT strongest:")
	for i in range(rows.size() - 1, rows.size() - 11, -1):
		print("AUDIT   " + rows[i][1])


func _median(a: Array) -> float:
	var b = a.duplicate()
	b.sort()
	return b[b.size() / 2] if not b.empty() else 0.0


func _sort_first_num(a, b) -> bool:
	return a[0] < b[0]


func _sd(a: Array) -> float:
	var s = 0.0
	var s2 = 0.0
	for x in a:
		s += x
		s2 += x * x
	var n = float(a.size())
	return sqrt(max(0.0, s2 / n - pow(s / n, 2)))


func _raw_dps(WV, st, tier: int) -> float:
	return max(0.01, WV.hit_damage(float(st.damage), st.scaling_stats, tier) * WV.crit_factor(st) * WV.hits_per_attack(st) / max(0.05, WV.cooldown_seconds(st)))


# 审计（AA_AUDIT=1）：深度重组的武器表（各级插值），
# 以及最低一级"随机多组取最高"（24 组）与只抽 1 组的分布对比
func test_167_audit_upgrade_schemes() -> void:
	if OS.get_environment("AA_AUDIT") == "":
		return
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var natives = m.native_only(isvc.weapons)
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	var sd0 = int(OS.get_environment("AA_SEED")) if OS.get_environment("AA_SEED") != "" else 3
	var g = Generator.new(cfg, sd0)
	g.generate(isvc.items, isvc.characters, [], [])
	cfg.w_item_effects = true
	for mode in ["interp"]:
		var wg = WG.new(cfg, sd0, g)
		var out = wg.generate(natives)
		print("AUDIT ===== scheme %s (native adjacent sampling) =====" % mode)
		for ty in wg._upgrade_priors:
			for t in wg._upgrade_priors[ty]:
				var txt = ""
				for field in ["damage", "cooldown", "main", "secondary"]:
					var a = wg._upgrade_priors[ty][t].get(field, [])
					if not a.empty():
						txt += "%s n%d p10 %.2f med %.2f p90 %.2f max %.2f  " % [field, a.size(), a[a.size() / 10], a[a.size() / 2], a[a.size() * 9 / 10], a[-1]]
				print("AUDIT native step type %d T%d->T%d %s" % [ty, t + 1, t + 2, txt])
		var smooth = []
		var t4r = []
		var vw_top = []
		var vw_tier = {}
		var ks_top = []
		var cd_top = []
		var fx_top = []
		for f in wg.fam_names:
			var tiers = wg.families[f].tiers.keys()
			tiers.sort()
			var prev = null
			for t in tiers:
				var w = wg.families[f].tiers[t]
				var p = out[w.my_id]
				var st = p.stats
				var sc = ""
				for x in st.scaling_stats:
					sc += "%s%d%% " % [WV.stat_name(x[0]).replace("stat_", "").replace("_damage", ""), int(round(float(x[1]) * 100))]
				var fx = ""
				for e in p.effects:
					fx += "%s=%s " % [WV.effect_key(e).replace("effect_", ""), str(e.chance) if WV.effect_id(e) == "weapon_exploding" else (str(e.burning_data.damage) if WV.effect_id(e) == "weapon_burning" and e.burning_data != null else str(e.value))]
				var val = wg.wv.value(st, p.effects, t)
				var extra = ""
				if not WV.is_melee(st):
					extra = " x%d p%d b%d" % [int(st.nb_projectiles), int(st.piercing), int(st.bounce)]
				print("AUDIT %s %-26s T%d $%-4d v%-6.0f dmg %-4d %scd %.2f crit %d%%x%.2f rng %d ls %d%%%s | %s" % [mode, f.replace("weapon_", ""), t + 1, int(p.price), val, int(st.damage), sc, WV.cooldown_seconds(st), int(round(float(st.crit_chance) * 100)), float(st.crit_damage), int(st.max_range), int(round(float(st.lifesteal) * 100)), extra, fx])
				if prev != null:
					smooth.push_back(float(st.damage) / max(1.0, float(prev.stats.damage)))
					var vk = "%d/%d" % [int(wg.families[f].type), t]
					if not vw_tier.has(vk):
						vw_tier[vk] = []
					vw_tier[vk].push_back(val / (wg._want(w, true) * wg._family_mult(f)))
				prev = p
			var top = tiers[-1]
			if tiers.size() > 1:
				var wt = wg.families[f].tiers[top]
				t4r.push_back(float(out[wt.my_id].price) / max(1.0, wg._price_of(wt)))
				var pt = out[wt.my_id]
				vw_top.push_back(wg.wv.value(pt.stats, pt.effects, top) / (wg._want(wt, true) * wg._family_mult(f)))
				ks_top.push_back(float(pt.scale))
				var a0 = out[wg.families[f].tiers[tiers[0]].my_id]
				cd_top.push_back(WV.cooldown_seconds(pt.stats) / WV.cooldown_seconds(a0.stats))
				var v_fx0 = wg.wv.value(a0.stats, a0.effects, tiers[0]) - wg.wv.value(a0.stats, [], tiers[0])
				if v_fx0 > 0.01:
					fx_top.push_back((wg.wv.value(pt.stats, pt.effects, top) - wg.wv.value(pt.stats, [], top)) / v_fx0)
		# 原版同类型同档"参考属性下原始 DPS / 价格"的中位数为 1：生成武器相对它的中位数（各档）；T4 / 最低一级的伤害与主加成倍数
		var med = {}
		for w in natives:
			var key = str(w.type) + "/" + str(w.tier)
			if not med.has(key):
				med[key] = []
			med[key].push_back(_raw_dps(WV, w.stats, w.tier) / float(w.value))
		var rel = {}
		var dmg_g = []
		var coef_g = []
		var nat_dmg_g = []
		var nat_coef_g = []
		for f in wg.fam_names:
			var tiers = wg.families[f].tiers.keys()
			tiers.sort()
			for t in tiers:
				var w = wg.families[f].tiers[t]
				var key = str(w.type) + "/" + str(t)
				if not rel.has(key):
					rel[key] = []
				rel[key].push_back(_raw_dps(WV, out[w.my_id].stats, t) / float(out[w.my_id].price) / _median(med[key]))
			if tiers.size() == 4:
				var a = out[wg.families[f].tiers[0].my_id].stats
				var b = out[wg.families[f].tiers[3].my_id].stats
				dmg_g.push_back(float(b.damage) / max(1.0, float(a.damage)))
				coef_g.push_back(float(b.scaling_stats[0][1]) / max(0.01, float(a.scaling_stats[0][1])))
				var na = wg.families[f].tiers[0]
				var nb = wg.families[f].tiers[3]
				if not na.has_meta("aa_low_of") and float(na.stats.damage) > 0 and not na.stats.scaling_stats.empty():
					nat_dmg_g.push_back(float(nb.stats.damage) / float(na.stats.damage))
					nat_coef_g.push_back(float(nb.stats.scaling_stats[0][1]) / max(0.01, float(na.stats.scaling_stats[0][1])))
		var ks = rel.keys()
		ks.sort()
		var txt = ""
		for key in ks:
			txt += "%s %.2f  " % [key, _median(rel[key])]
		print("AUDIT %s raw DPS / price vs native median: %s" % [mode, txt])
		print("AUDIT %s T4/T1 damage median %.2f (native %.2f), main coef median %.2f (native %.2f)" % [mode, _median(dmg_g), _median(nat_dmg_g), _median(coef_g), _median(nat_coef_g)])
		smooth.sort()
		t4r.sort()
		for arr in [vw_top, ks_top, cd_top, fx_top]:
			arr.sort()
		var vt = ""
		var vks = vw_tier.keys()
		vks.sort()
		for vk in vks:
			vt += "%s %.2f  " % [vk, _median(vw_tier[vk])]
		print("AUDIT %s upper tiers value / ladder want median: %s" % [mode, vt])
		print("AUDIT %s top value / want p10 %.2f median %.2f p90 %.2f (<0.9: %d / %d); k p10 %.2f median %.2f p90 %.2f; top/lowest attack interval median %.2f; effect value top/lowest p10 %.2f median %.2f p90 %.2f" % [mode, vw_top[vw_top.size() / 10], _median(vw_top), vw_top[vw_top.size() * 9 / 10], _count_below(vw_top, 0.9), vw_top.size(), ks_top[ks_top.size() / 10], _median(ks_top), ks_top[ks_top.size() * 9 / 10], _median(cd_top), fx_top[fx_top.size() / 10], _median(fx_top), fx_top[fx_top.size() * 9 / 10]])
		print("AUDIT %s damage step ratio p10 %.2f median %.2f p90 %.2f max %.2f; top price / ladder p10 %.2f median %.2f p90 %.2f" % [mode, smooth[smooth.size() / 10], smooth[smooth.size() / 2], smooth[smooth.size() * 9 / 10], smooth[-1], t4r[t4r.size() / 10], t4r[t4r.size() / 2], t4r[t4r.size() * 9 / 10]])
	# 最低一级择优的偏向：24 组取最高 vs 1 组（5 个种子合计）
	for tries in [24, 1]:
		var n = 0
		var acc = {"fx1": 0, "fx2": 0, "item": 0, "hicrit": 0, "ls": 0, "pierce": 0, "bounce": 0, "over": 0, "unnatural_dmg": 0}
		var cds = []
		var coef = []
		var share = []
		var vw = []
		var keys = {}
		var mains = {}
		for sd in [1, 2, 3, 4, 5]:
			var wg = WG.new(cfg, sd, g)
			wg.deep_tries = tries
			var out = wg.generate(natives)
			for f in wg.fam_names:
				var tiers = wg.families[f].tiers.keys()
				tiers.sort()
				var w = wg.families[f].tiers[tiers[0]]
				var p = out[w.my_id]
				var st = p.stats
				n += 1
				var nfx = 0
				for e in p.effects:
					if WG.bound_key(e):
						continue
					nfx += 1
					if e.has_meta("aa_value"):
						acc.item += 1
					else:
						var k = WV.effect_key(e)
						keys[k] = keys.get(k, 0) + 1
				acc.fx1 += 1 if nfx >= 1 else 0
				acc.fx2 += 1 if nfx >= 2 else 0
				acc.hicrit += 1 if WG.is_high_crit(st) else 0
				acc.ls += 1 if float(st.lifesteal) > 0 else 0
				if not WV.is_melee(st):
					acc.pierce += 1 if int(st.piercing) > 0 else 0
					acc.bounce += 1 if int(st.bounce) > 0 else 0
				var val = wg.wv.value(st, p.effects, tiers[0])
				acc.over += 1 if val > float(p.want) else 0
				vw.push_back(val / max(1.0, float(p.want)))
				cds.push_back(WV.cooldown_seconds(st))
				var hit = WV.hit_damage(float(st.damage), st.scaling_stats, tiers[0])
				share.push_back(WV.hit_damage(0.0, st.scaling_stats, tiers[0]) / max(1.0, hit))
				var m0 = WV.stat_name(st.scaling_stats[0][0])
				mains[m0] = mains.get(m0, 0) + 1
				coef.push_back(float(st.scaling_stats[0][1]))
		for a in [cds, coef, share, vw]:
			a.sort()
		var top = []
		for k in keys:
			top.push_back([keys[k], k])
		top.sort_custom(self, "_sort_first_desc")
		print("AUDIT tries %d: n %d effects>=1 %.2f >=2 %.2f item %.2f hicrit %.2f lifesteal %.2f pierce %d bounce %d over-want %d" % [tries, n, float(acc.fx1) / n, float(acc.fx2) / n, float(acc.item) / n, float(acc.hicrit) / n, float(acc.ls) / n, acc.pierce, acc.bounce, acc.over])
		print("AUDIT tries %d: cd median %.2f p90 %.2f; main coef median %.2f p90 %.2f; scaling share median %.2f; value/want p10 %.2f median %.2f" % [tries, cds[cds.size() / 2], cds[cds.size() * 9 / 10], coef[coef.size() / 2], coef[coef.size() * 9 / 10], share[share.size() / 2], vw[vw.size() / 10], vw[vw.size() / 2]])
		print("AUDIT tries %d: mains %s" % [tries, str(mains)])
		print("AUDIT tries %d: top effects %s" % [tries, str(top.slice(0, min(11, top.size() - 1)))])


const UPGRADE_FIELDS = ["damage", "cooldown", "main", "secondary", "crit_chance", "crit_damage", "range", "knockback", "nb_projectiles", "piercing", "bounce", "lifesteal"]
const UPGRADE_AUDIT_SEEDS = [1, 2, 3, 11, 42]


func _upgrade_cfg() -> Dictionary:
	var cfg = _cfg()
	cfg.weapons = true
	cfg.weapon_mode = "deep"
	cfg.w_item_effects = false
	return cfg


func _upgrade_api(wg) -> bool:
	for method in ["_collect_upgrade_priors", "_upgrade_stats", "_upgrade_effects", "_upgrade_plan"]:
		if not wg.has_method(method):
			_check(false, "generator API missing: " + method)
			return false
	return true


# 所有档位放同一分布，避免把测试绑死在 prior 的 source/target tier 索引约定上。
func _controlled_upgrade_priors(damage_ratio: float) -> Dictionary:
	var priors = {0: {}, 1: {}}
	for ty in [0, 1]:
		for tier in range(4):
			var row = {}
			for field in UPGRADE_FIELDS:
				row[field] = [1.0] if field in ["damage", "cooldown", "main", "secondary"] else [0.0]
			row.damage = [damage_ratio]
			priors[ty][tier] = row
	return priors


func _upgrade_full_family(wg):
	for f in wg.fam_names:
		var fam = wg.families[f]
		if fam.tiers.has(0) and fam.tiers.has(1) and fam.tiers.has(2) and fam.tiers.has(3) and fam.type == 0 and fam.tiers[0].stats.scaling_stats.size() > 0:
			return fam
	return null


func test_168_native_upgrade_priors_include_noops() -> void:
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var natives = m.native_only(isvc.weapons)
	var wg = WG.new(_upgrade_cfg(), 11)
	if not _upgrade_api(wg):
		return
	wg.generate(natives)
	var noops = 0
	var positive = 0
	var samples = 0
	for ty in wg._upgrade_priors:
		for tier in wg._upgrade_priors[ty]:
			for field in wg._upgrade_priors[ty][tier]:
				_check(field in UPGRADE_FIELDS, "known native upgrade field " + str(field))
				for raw in wg._upgrade_priors[ty][tier][field]:
					var x = float(raw)
					var neutral = 1.0 if field in ["damage", "cooldown", "main", "secondary"] else 0.0
					_check(x > 0 and x <= 1.000001 if field == "cooldown" else x >= neutral - 0.000001, "%s native sample in improvement domain: %s" % [field, str(raw)])
					samples += 1
					noops += 1 if abs(x - neutral) < 0.000001 else 0
					positive += 1 if abs(x - neutral) > 0.000001 else 0
	_check(samples > 0, "collected real native adjacent samples")
	_check(noops > 0, "native priors retain no-op samples")
	_check(positive > 0, "native priors retain positive samples (not required for every field)")
	var fx_samples = 0
	var fx_noops = 0
	var fx_positive = 0
	for key in wg._effect_upgrades:
		for tier in wg._effect_upgrades[key]:
			for x in wg._effect_upgrades[key][tier]:
				_check(float(x) >= 1.0, "%s effect prior never weakens" % str(key))
				fx_samples += 1
				fx_noops += 1 if abs(float(x) - 1.0) < 0.000001 else 0
				fx_positive += 1 if float(x) > 1.000001 else 0
	_check(fx_samples > 0, "collected same-key native effect ratios")
	_check(fx_noops > 0, "same-key native effect priors retain no-ops")
	_check(fx_positive > 0, "same-key native effect priors retain positive upgrades (not every key)")
		# aa_low_of 伪造完整家族：必须不污染任何原版升级分布（含 effect）。
	var fam = _upgrade_full_family(wg)
	_check(fam != null, "native four-tier melee fixture available")
	if fam == null:
		return
	var before = _upgrade_snapshot([wg._upgrade_priors, wg._effect_upgrades])
	var augmented = natives.duplicate()
	for tier in range(4):
		var w = fam.tiers[tier].duplicate()
		w.stats = fam.tiers[tier].stats.duplicate()
		w.my_id = "aa_upgrade_prior_fixture_" + str(tier)
		w.weapon_id = "aa_upgrade_prior_fixture"
		w.set_meta("aa_low_of", fam.tiers[tier])
		w.stats.damage = 1000 * (tier + 1)
		augmented.push_back(w)
	wg.generate(augmented)
	_eq(_upgrade_snapshot([wg._upgrade_priors, wg._effect_upgrades]), before, "aa_low_of adjacent pairs excluded from native priors")


func test_169_upgrade_noops_and_uncapped_damage() -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var wg = WG.new(_upgrade_cfg(), 3)
	if not _upgrade_api(wg):
		return
	wg.generate(m.native_only(isvc.weapons))
	var fam = _upgrade_full_family(wg)
	_check(fam != null, "four-tier fixture available")
	if fam == null:
		return
	var st = fam.tiers[0].stats.duplicate(true)
	st.damage = 100
	st.cooldown = 90
	st.additional_cooldown_every_x_shots = 3
	st.additional_cooldown_multiplier = 2.0
	var main_key = st.scaling_stats[0][0]
	var secondary_key = null
	for w in m.native_only(isvc.weapons):
		for sc in w.stats.scaling_stats:
			if sc[0] != main_key:
				secondary_key = sc[0]
	_check(secondary_key != null, "distinct secondary scaling fixture available")
	if secondary_key == null:
		return
	st.scaling_stats = [[main_key, 0.5], [secondary_key, 0.25]]
	var cd0 = WV.cooldown_seconds(st)
	var scaling0 = _upgrade_snapshot(st.scaling_stats)
	wg._upgrade_priors = _controlled_upgrade_priors(1.0)
	wg._effect_upgrades = {}
	var plan = wg._upgrade_plan(fam.type, [0, 1, 2, 3], st, [])
	for tier in range(4):
		_check(plan.has(tier), "plan contains T%d" % (tier + 1))
		if not plan.has(tier):
			return
		_eq(float(plan[tier].damage_weight), 0.0, "no damage draw has zero cumulative weight")
		_check(not plan[tier].damage_up, "no damage draw marks damage_up false")
		_check(abs(WV.cooldown_seconds(plan[tier].stats) - cd0) < 0.000001, "cooldown no-op preserves real average attack interval including reload")
		_eq(_upgrade_snapshot(plan[tier].stats.cooldown), _upgrade_snapshot(st.cooldown), "cooldown no-op preserves raw cooldown frames")
		_eq(_upgrade_snapshot(plan[tier].stats.scaling_stats), scaling0, "main/secondary no-ops preserve coefficients")
	var base = {"stats": st, "effects": [], "donor": fam.tiers[0].my_id, "price": int(fam.tiers[0].value), "want": wg.wv.value(st, [], 0)}
	var flat = wg._deep_interp(fam, base, [0, 1, 2, 3], 100.0)
	_eq(flat.size(), 4, "deep interpolation returns all tiers")
	for p in flat:
		_eq(int(p.stats.damage), int(st.damage), "damage no-op stays flat even with huge value budget")
		_check(abs(WV.cooldown_seconds(p.stats) - cd0) < 0.000001, "deep solve does not force faster cooldown")
		_eq(_upgrade_snapshot(p.stats.scaling_stats), scaling0, "deep solve does not force main/secondary growth")
	wg._upgrade_priors = _controlled_upgrade_priors(1.5)
	wg.rng.seed = 3
	var growing = wg._deep_interp(fam, base, [0, 1, 2, 3], 100.0)
	_eq(growing.size(), 4, "uncapped solve returns all tiers")
	if growing.size() != 4:
		return
	var ratio = float(growing[-1].stats.damage) / float(st.damage)
	_check(ratio > 2.55, "high value budget allows damage beyond old 2.55 cap (x%.3f)" % ratio)
	for p in growing:
		_check(abs(WV.cooldown_seconds(p.stats) - cd0) < 0.000001, "damage budget cannot force cooldown growth")
		_eq(_upgrade_snapshot(p.stats.scaling_stats), scaling0, "damage budget cannot force coefficient growth")
	# 单个 no-op 插在 positive steps 中，不能被累计预算或取整强制 +1。
	wg._upgrade_priors[fam.type][1].damage = [1.0]
	wg.rng.seed = 3
	plan = wg._upgrade_plan(fam.type, [0, 1, 2, 3], st, [])
	var mixed = wg._deep_interp(fam, base, [0, 1, 2, 3], 100.0)
	_eq(mixed.size(), 4, "mixed solve returns all tiers")
	if mixed.size() != 4:
		return
	var held = 0
	for i in range(1, 4):
		if not plan[i].damage_up:
			_eq(int(mixed[i].stats.damage), int(mixed[i - 1].stats.damage), "unsampled damage step stays flat among positive steps")
			held += 1
	_check(held > 0, "mixed upgrade plan actually includes a damage no-op")


# Resource 身份 / instance_id 不能用于确定性比较；递归比较存储属性及 metadata。
func _upgrade_snapshot(value) -> String:
	if value is Array:
		var parts = []
		for x in value:
			parts.push_back(_upgrade_snapshot(x))
		return "[" + PoolStringArray(parts).join(",") + "]"
	if value is Dictionary:
		var keys = value.keys()
		keys.sort()
		var parts = []
		for key in keys:
			parts.push_back(var2str(key) + ":" + _upgrade_snapshot(value[key]))
		return "{" + PoolStringArray(parts).join(",") + "}"
	if value is Resource:
		if value is Texture or value is Script:
			return value.resource_path
		var stored = {}
		for prop in value.get_property_list():
			if int(prop.usage) & PROPERTY_USAGE_STORAGE and not prop.name in ["resource_path", "resource_name", "resource_local_to_scene"]:
				stored[prop.name] = value.get(prop.name)
		var metadata = {}
		for key in value.get_meta_list():
			metadata[key] = value.get_meta(key)
		stored["_metadata"] = metadata
		return _upgrade_snapshot(stored)
	return var2str(value)


func test_170_upgrade_seed_determinism_and_distribution() -> void:
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var natives = m.native_only(isvc.weapons)
	var cfg = _upgrade_cfg()
	var wg = WG.new(cfg, 11)
	if not _upgrade_api(wg):
		return
	var first = wg.generate(natives)
	var snapshot = _upgrade_snapshot(first)
	_eq(_upgrade_snapshot(wg.generate(natives)), snapshot, "same instance / seed regenerates identical complete output")
	var same = WG.new(cfg, 11)
	_eq(_upgrade_snapshot(same.generate(natives)), snapshot, "fresh instance / same seed has identical stats, effects, prices and metadata")
	var distributions = {}
	var flat_damage = 0
	var raised_damage = 0
	for sd in UPGRADE_AUDIT_SEEDS:
		var other = WG.new(cfg, sd)
		var out = other.generate(natives)
		var acc = {}
		for f in other.fam_names:
			var fam = other.families[f]
			for tier in range(3):
				if not fam.tiers.has(tier) or not fam.tiers.has(tier + 1):
					continue
				var a = out.get(fam.tiers[tier].my_id)
				var b = out.get(fam.tiers[tier + 1].my_id)
				if a == null or b == null:
					continue
				_upgrade_record_stats(acc, fam.type, tier, a.stats, b.stats)
				flat_damage += 1 if int(a.stats.damage) == int(b.stats.damage) else 0
				raised_damage += 1 if int(b.stats.damage) > int(a.stats.damage) else 0
		distributions[_upgrade_snapshot(acc)] = true
	_check(distributions.size() > 1, "different seeds yield different adjacent improvement distributions, not just different bases")
	_check(flat_damage > 0, "real generation has a chance of flat adjacent damage")
	_check(raised_damage > 0, "real generation also has positive adjacent damage upgrades")


func _upgrade_record(acc: Dictionary, key: String, before: float, after: float, lower_better := false) -> void:
	if not acc.has(key):
		acc[key] = {"n": 0, "up": 0, "flat": 0, "down": 0}
	var row = acc[key]
	row.n += 1
	var delta = (before - after) if lower_better else (after - before)
	if delta > 0.000001:
		row.up += 1
	elif delta < -0.000001:
		row.down += 1
	else:
		row.flat += 1


func _upgrade_stat_sample(acc: Dictionary, ty: int, tier: int, field: String, before: float, after: float) -> void:
	_upgrade_record(acc, field, before, after, field == "cooldown")
	_upgrade_record(acc, "%d/%d/%s" % [ty, tier, field], before, after, field == "cooldown")


func _upgrade_record_stats(acc: Dictionary, ty: int, tier: int, a, b) -> void:
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	if float(a.damage) > 0:
		_upgrade_stat_sample(acc, ty, tier, "damage", float(a.damage), float(b.damage))
	_upgrade_stat_sample(acc, ty, tier, "cooldown", WV.cooldown_seconds(a), WV.cooldown_seconds(b))
	for i in a.scaling_stats.size():
		var sc = a.scaling_stats[i]
		if float(sc[1]) <= 0:
			continue
		for next in b.scaling_stats:
			if next[0] == sc[0]:
				_upgrade_stat_sample(acc, ty, tier, "main" if i == 0 else "secondary", float(sc[1]), float(next[1]))
				break
	for field in ["crit_chance", "crit_damage", "knockback"]:
		_upgrade_stat_sample(acc, ty, tier, field, float(a.get(field)), float(b.get(field)))
	_upgrade_stat_sample(acc, ty, tier, "range", float(a.max_range), float(b.max_range))
	if float(a.lifesteal) > 0:
		_upgrade_stat_sample(acc, ty, tier, "lifesteal", float(a.lifesteal), float(b.lifesteal))
	if ty == 1:
		_upgrade_stat_sample(acc, ty, tier, "nb_projectiles", float(a.nb_projectiles), float(b.nb_projectiles))
		for field in ["piercing", "bounce"]:
			if int(a.get(field)) > 0:
				_upgrade_stat_sample(acc, ty, tier, field, float(a.get(field)), float(b.get(field)))


func _upgrade_rate(acc: Dictionary, field: String) -> String:
	if not acc.has(field) or int(acc[field].n) == 0:
		return "n=0"
	var row = acc[field]
	return "n=%d up=%.2f%% flat=%.2f%% down=%.2f%%" % [row.n, 100.0 * row.up / row.n, 100.0 * row.flat / row.n, 100.0 * row.down / row.n]


func _upgrade_merge(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if not target.has(key):
			target[key] = {"n": 0, "up": 0, "flat": 0, "down": 0}
		for field in ["n", "up", "flat", "down"]:
			target[key][field] += source[key][field]


# 效果价值是边际 value(st,[effect],tier)-value(st,[],tier)，覆盖 power 建模的效果。
# fixed 两边都用低档面板与低档 tier；actual 两边各用真实升级的面板和 tier，单列而不混入 prior ratio。
func _upgrade_record_effects(wg, WV, WG, ratios: Dictionary, tier: int, a, b) -> void:
	var used = []
	for e in a.effects:
		var key = WV.effect_key(e)
		if key in WG.NO_STRENGTHEN_KEYS or key.begins_with("structure:"):
			continue
		for i in b.effects.size():
			var q = b.effects[i]
			if i in used or WV.effect_key(q) != key:
				continue
			used.push_back(i)
			var label = "%s/T%d" % [key, tier + 1]
			if not ratios.has(label):
				ratios[label] = {"fixed": [], "actual": [], "skipped": 0}
			var row = ratios[label]
			var v0 = wg.wv.value(a.stats, [e], tier) - wg.wv.value(a.stats, [], tier)
			var fixed = wg.wv.value(a.stats, [q], tier) - wg.wv.value(a.stats, [], tier)
			var actual = wg.wv.value(b.stats, [q], tier + 1) - wg.wv.value(b.stats, [], tier + 1)
			if v0 > 0.000001 and fixed > 0 and actual > 0:
				row.fixed.push_back(fixed / v0)
				row.actual.push_back(actual / v0)
			else:
				row.skipped += 1
			break


func _upgrade_ratio_summary(values: Array) -> String:
	if values.empty():
		return "n=0"
	var sorted = values.duplicate()
	sorted.sort()
	var sum_value = 0.0
	var up = 0
	for x in sorted:
		sum_value += x
		up += 1 if float(x) > 1.000001 else 0
	return "n=%d up=%.2f%% mean=%.4f p10=%.4f median=%.4f p90=%.4f" % [sorted.size(), 100.0 * up / sorted.size(), sum_value / sorted.size(), sorted[sorted.size() / 10], _median(sorted), sorted[sorted.size() * 9 / 10]]


# 精确独立入口：AA_AUDIT=1 AA_ONLY=test_171_audit_native_adjacent_upgrades
# 不打印全武器表；原版只计一次，生成计五种子，缺档家族不跨级比较，aa_low_of 不参与。
func test_171_audit_native_adjacent_upgrades() -> void:
	if OS.get_environment("AA_AUDIT") == "":
		return
	var WV = load(MOD_DIR + "aa/weapon_value.gd")
	var WG = load(MOD_DIR + "aa/weapon_gen.gd")
	var natives = m.native_only(isvc.weapons)
	var cfg = _upgrade_cfg()
	cfg.w_item_effects = true
	var native_rates = {}
	var generated_rates = {}
	var native_fx = {}
	var generated_fx = {}
	for sd in UPGRADE_AUDIT_SEEDS:
		var g = Generator.new(cfg, sd)
		g.generate(m.native_only(isvc.items), m.native_only(isvc.characters), [], [])
		var wg = WG.new(cfg, sd, g)
		if sd == UPGRADE_AUDIT_SEEDS[0]:
			print("AUDIT adjacent generator=%s" % ("native-adjacent API" if wg.has_method("_upgrade_plan") else "legacy API (baseline only)"))
		var out = wg.generate(natives)
		var seed_rates = {}
		for f in wg.fam_names:
			var fam = wg.families[f]
			for tier in range(3):
				if not fam.tiers.has(tier) or not fam.tiers.has(tier + 1):
					continue
				var lo = fam.tiers[tier]
				var hi = fam.tiers[tier + 1]
				if lo.has_meta("aa_low_of") or hi.has_meta("aa_low_of"):
					continue
				if sd == UPGRADE_AUDIT_SEEDS[0]:
					_upgrade_record_stats(native_rates, fam.type, tier, lo.stats, hi.stats)
					_upgrade_record_effects(wg, WV, WG, native_fx, tier, lo, hi)
				var a = out.get(lo.my_id)
				var b = out.get(hi.my_id)
				if a != null and b != null:
					_upgrade_record_stats(seed_rates, fam.type, tier, a.stats, b.stats)
					_upgrade_record_effects(wg, WV, WG, generated_fx, tier, a, b)
		_upgrade_merge(generated_rates, seed_rates)
		var summary = []
		for field in UPGRADE_FIELDS:
			summary.push_back(field + "{" + _upgrade_rate(seed_rates, field) + "}")
		print("AUDIT adjacent seed=%d %s" % [sd, PoolStringArray(summary).join("; ")])
	print("AUDIT adjacent pooled seeds=%s; conditional samples: positive same-key scaling, existing lifesteal, ranged projectiles/existing pierce/bounce; cooldown=average attack interval" % str(UPGRADE_AUDIT_SEEDS))
	for field in UPGRADE_FIELDS:
		print("AUDIT adjacent %s NATIVE{%s} GENERATED{%s}" % [field, _upgrade_rate(native_rates, field), _upgrade_rate(generated_rates, field)])
	# 分层报告避免类型/档位的样本量变化把 pooled rate 伪装成 prior 不匹配。
	for ty in [0, 1]:
		for tier in range(3):
			var summary = []
			for field in UPGRADE_FIELDS:
				var key = "%d/%d/%s" % [ty, tier, field]
				summary.push_back("%s N{%s} G{%s}" % [field, _upgrade_rate(native_rates, key), _upgrade_rate(generated_rates, key)])
			print("AUDIT adjacent type=%d T%d->T%d %s" % [ty, tier + 1, tier + 2, PoolStringArray(summary).join("; ")])
	print("AUDIT effects fixed=identical lower panel + lower tier; actual=each native/generated upgrade's own panel + tier; nonpositive marginal values excluded, skips reported")
	for pair in [["NATIVE", native_fx], ["GENERATED", generated_fx]]:
		var fixed_all = []
		var actual_all = []
		var skipped = 0
		var keys = pair[1].keys()
		keys.sort()
		for key in keys:
			var row = pair[1][key]
			fixed_all += row.fixed
			actual_all += row.actual
			skipped += row.skipped
			print("AUDIT effects %s %s fixed{%s} actual{%s} skipped=%d" % [pair[0], key, _upgrade_ratio_summary(row.fixed), _upgrade_ratio_summary(row.actual), row.skipped])
		print("AUDIT effects %s TOTAL fixed{%s} actual{%s} skipped=%d" % [pair[0], _upgrade_ratio_summary(fixed_all), _upgrade_ratio_summary(actual_all), skipped])


func _count_below(a: Array, x: float) -> int:
	var n = 0
	for v in a:
		n += 1 if v < x else 0
	return n
