extends "res://mods/tests/BroEditor/test_base.gd"

# core：数据层（档案、应用 / 还原、效果、蓝图、开局状态、道具 / 武器、自定义对象、分享码、文本与本地化）


func test_01_library_and_triggers() -> void:
	var lib = m.library()
	_check(lib.size() > 100, "library has many effects (%d)" % lib.size())
	var cats = {}
	for e in lib:
		cats[e.cat] = true
	for c in ["stat", "trigger", "scaling", "start"]:
		_check(cats.has(c), "category %s present" % c)
	for ck in ["stats_on_level_up", "stats_end_of_wave", "temp_stats_while_not_moving"]:
		_check(m.trigger_template(ck) != null, "trigger template " + ck)
	_eq(m.stat_text_key("knockback"), "effect_knockback", "non-stat key borrows a native text key")


func test_02_make_effect_copies_template() -> void:
	var t = m.trigger_template("stats_on_level_up")
	var tmpl = m.template(t.from, t.i)
	var orig_value = tmpl.value
	var e = m.make_effect({"from": t.from, "i": t.i, "set": {"key": "stat_armor", "value": 7.0}})
	_eq(e.key, "stat_armor", "key set")
	_eq(e.value, 7, "value coerced to int")
	_eq(typeof(e.value), TYPE_INT, "value type int")
	_eq(e.custom_key, "stats_on_level_up", "trigger kept")
	_eq(tmpl.value, orig_value, "template untouched")
	_check(e.get_text(0) != "", "effect has text")
	_eq(m.make_effect({"from": "nope", "i": 0}), null, "missing source -> null")


func test_10_native_profile_applies_and_restores() -> void:
	var c = m.find_character(CH)
	var orig_effects = c.effects
	var orig_name = c.name
	var item = isvc.items[5].my_id
	var p = m.new_profile()
	p.name = "Test Potato"
	p.stats = {"stat_armor": 5}
	p.start_items = [{"id": item, "n": 2}]
	p.desc = "hello {0}"
	m.profiles[CH] = p
	m.apply_all()
	_eq(c.name, "Test Potato", "renamed")
	_eq(c.effects.size(), orig_effects.size() + 3, "desc + original + stat + start item")
	var st = _find_effect(c.effects, "stat_armor")
	_check(st != null and st.value == 5, "stat effect added")
	var si = _find_effect(c.effects, item, "starting_item")
	_check(si != null and si.value == 2 and si.storage_method == 1, "starting item effect")
	_eq(c.effects[0].key, "", "description first, inert")
	_check(c.effects[0].get_text(0).find("hello") >= 0, "description text shown")
	_check(c.effects[0].get_text(0).find("{") < 0, "braces sanitized")
	# 停用 -> 原版
	m.profiles[CH].enabled = false
	m.apply_all()
	_eq(c.effects, orig_effects, "disabled restores effects")
	_eq(c.name, orig_name, "disabled restores name")
	m.profiles[CH].enabled = true
	m.apply_all()
	m.reset_profile(CH)
	m.apply_all()
	_eq(c.effects, orig_effects, "reset restores effects")


func test_11_run_gets_profile_stats_and_items() -> void:
	var item = isvc.items[5]
	var p = m.new_profile()
	p.stats = {"stat_armor": 9}
	p.start_items = [{"id": item.my_id, "n": 1}]
	m.profiles[CH] = p
	m.apply_all()
	var c = m.find_character(CH)
	var base_armor = 0
	for e in m.orig_effects(CH):
		if e.key == "stat_armor" and e.custom_key == "" and e.storage_method == 0:
			base_armor += e.value
	rd.set_player_count(1, true)
	rd.add_character(c, 0)
	rd.add_starting_items_and_weapons()
	_eq(int(rd.get_player_effect(Keys.generate_hash("stat_armor"), 0)), base_armor + 9, "armor from profile")
	var has_item = false
	for it in rd.players_data[0].items:
		if it.my_id == item.my_id:
			has_item = true
	_check(has_item, "starting item granted")


func test_12_effects_edit_and_starting_weapons() -> void:
	var c = m.find_character(CH)
	var w = isvc.weapons[3]
	var orig_sw = c.starting_weapons
	var p = m.new_profile()
	p.effects = [{"set": {"key": "stat_luck", "value": 30}}]
	p.weapons = [w.my_id]
	p.wanted_tags = ["stat_luck"]
	m.profiles[CH] = p
	m.apply_all()
	_eq(c.effects.size(), 1, "effects replaced")
	_eq(c.effects[0].key, "stat_luck", "plain stat effect")
	_eq(c.starting_weapons, [w], "starting weapons replaced")
	_eq(c.wanted_tags, ["stat_luck"], "wanted tags replaced")
	m.reset_profile(CH)
	m.apply_all()
	_eq(c.starting_weapons, orig_sw, "starting weapons restored")


func test_20_custom_character_lifecycle() -> void:
	var n = isvc.characters.size()
	var id = m.create_custom(CH)
	_check(id.begins_with(m.CHAR_PREFIX), "custom id prefix")
	_eq(isvc.characters.size(), n + 1, "registered")
	var c = m.find_character(id)
	_eq(c.effects.size(), m.orig_effects(CH).size(), "copies base effects")
	_check(c.icon is ImageTexture and c.icon.get_size() == m.find_character(CH).icon.get_size(), "base icon, numbered copy")
	_check(not c.starting_weapons.empty(), "has starting weapons")
	_check(tree.root.get_node("ProgressData").characters_unlocked.has(c.my_id_hash), "unlocked")
	# 改图标
	m.profiles[id].icon = isvc.items[0].my_id
	m.apply_all()
	_check(c.icon is ImageTexture and c.icon.get_size() == isvc.items[0].icon.get_size(), "icon from item, numbered copy")
	# 存档往返
	m.save_profiles()
	m.load_profiles()
	_check(m.is_custom(id), "custom survives save/load")
	_check(m.delete_custom(id), "deleted")
	_eq(isvc.characters.size(), n, "unregistered")
	_eq(m.find_character(id), null, "gone")


func test_21_custom_from_modified_base_copies_profile() -> void:
	var p = m.new_profile()
	p.stats = {"stat_dodge": 3}
	p.ban_items = [isvc.items[0].my_id]
	m.profiles[CH] = p
	m.apply_all()
	var id = m.create_custom(CH)
	_eq(m.profiles[id].stats, {"stat_dodge": 3}, "stats copied")
	_eq(m.profiles[id].ban_items, [isvc.items[0].my_id], "bans copied")
	m.profiles[id].stats["stat_dodge"] = 4
	_eq(m.profiles[CH].stats["stat_dodge"], 3, "deep copy")


func test_30_bans_filter_shop() -> void:
	var banned_items = []
	for it in isvc.items:
		if it.tier == 0 and banned_items.size() < 40:
			banned_items.push_back(it.my_id)
	var families = []
	for w in isvc.weapons:
		if w.tier == 0 and not w.weapon_id in families and families.size() < 20:
			families.push_back(w.weapon_id)
	var p = m.new_profile()
	p.ban_items = banned_items
	p.ban_weapons = families
	m.profiles[CH] = p
	m.apply_all()
	_setup_player(CH)
	var before = rd.players_data[0].banned_items.size()
	for i in 300:
		seed(i)
		var it = isvc.get_rand_item_for_wave(1, 0)
		_check(not it.my_id in banned_items, "banned item rolled: " + it.my_id)
		var args = isvc.GetRandItemForWaveArgs.new()
		args.owned_and_shop_items = []
		var w = isvc._get_rand_item_for_wave(1, 0, isvc.TierData.WEAPONS, args)
		_check(not w.weapon_id in families, "banned weapon rolled: " + w.my_id)
	_eq(rd.players_data[0].banned_items.size(), before, "player ban list restored")
	# 停用档案 -> 不过滤
	m.profiles[CH].enabled = false
	m.apply_all()
	_eq(m.ban_hashes(0), [], "no bans when disabled")


func test_40_share_code() -> void:
	var p = m.new_profile()
	p.stats = {"stat_luck": 12}
	m.profiles[CH] = p
	var code = m.export_code(CH)
	_check(code.begins_with(m.SHARE_PREFIX), "prefix")
	m.profiles = {}
	_eq(m.import_code(code, CH), CH, "imported into native")
	_eq(m.profiles[CH].stats, {"stat_luck": 12}, "content")
	for bad in ["", "x", m.SHARE_PREFIX, m.SHARE_PREFIX + "!!", "AA1:" + Marshalls.utf8_to_base64("{}")]:
		_eq(m.import_code(bad, CH), "", "rejects " + bad)
	# 自定义角色 -> 导入为新的自定义角色
	var id = m.create_custom(CH)
	var code2 = m.export_code(id)
	var id2 = m.import_code(code2, CH)
	_check(id2 != "" and id2 != id and m.is_custom(id2), "custom imported as new custom")


func test_41_normalize_profile() -> void:
	var p = m.normalize_profile({"stats": {"stat_armor": 2.0, "stat_luck": 0}, "effects": "bad", "ban_items": null, "desc": "{x}"})
	_eq(p.stats, {"stat_armor": 2}, "zero stats dropped, ints")
	_eq(p.effects, null, "bad effects -> null")
	_eq(p.ban_items, [], "null list -> []")
	_eq(p.desc, "｛x｝", "braces replaced")


func test_70_graph_text_and_runtime() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "level_up", Vector2.ZERO)
	var every = GE.add_node(g, "every", Vector2.ZERO, {"n": 2})
	var eff = GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 3})
	var gold = GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 7})
	GE.add_link(g, t, every)
	GE.add_link(g, every, eff)
	GE.add_link(g, t, gold)
	GE.add_link(g, t, every)
	_eq(g.links.size(), 3, "duplicate link ignored")
	_eq(GE.paths(g).size(), 2, "two paths")
	var c = _graph_char(g)
	var ge = null
	for e in c.effects:
		if e is GE:
			ge = e
	_check(ge != null, "graph effect on character")
	var text = ge.get_text(0, false)
	_check(text.find("2") >= 0 and text.split("\n").size() == 2, "path text: " + text)
	var a0 = _armor()
	var g0 = rd.players_data[0].gold
	m.runtime.fire("level_up", 0)
	_eq(_armor(), a0, "every 2: first fire blocked")
	_eq(rd.players_data[0].gold, g0 + 7, "parallel path fired")
	m.runtime.fire("level_up", 0)
	_eq(_armor(), a0 + 3, "every 2: second fire passes")
	m.runtime.fire("kill", 0)
	_eq(_armor(), a0 + 3, "other events ignored")
	m.runtime.end_wave()
	m.runtime.fire("level_up", 0)
	m.runtime.fire("level_up", 0)
	_eq(_armor(), a0 + 3, "no firing after wave end")


func test_71_graph_conditions_and_cycles() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "kill", Vector2.ZERO)
	var cap = GE.add_node(g, "cap", Vector2.ZERO, {"n": 2})
	var wave = GE.add_node(g, "wave_min", Vector2.ZERO, {"n": 99})
	var eff = GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 1})
	var eff2 = GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_luck", "value": 1})
	GE.add_link(g, t, cap)
	GE.add_link(g, cap, eff)
	GE.add_link(g, cap, cap)	# 环：不应死循环
	GE.add_link(g, t, wave)
	GE.add_link(g, wave, eff2)
	_graph_char(g)
	var a0 = _armor()
	var l0 = rd.get_player_effect(Keys.generate_hash("stat_luck"), 0)
	for i in 5:
		m.runtime.fire("kill", 0)
	_check(_armor() - a0 >= 2, "cap passes (cycle re-enters cap)")
	_check(_armor() - a0 <= 6, "cap/cycle bounded")
	_eq(rd.get_player_effect(Keys.generate_hash("stat_luck"), 0), l0, "wave_min blocks")
	m.runtime.end_wave()


func test_72_graph_grant_and_shop() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "reroll", Vector2.ZERO)
	var gr = GE.add_node(g, "grant", Vector2.ZERO, {"ref": {"set": {"key": "stat_armor", "value": 2}}, "n": 3, "mode": "perm"})
	GE.add_link(g, t, gr)
	_graph_char(g)
	m.runtime.end_wave()
	var a0 = _armor()
	m.fire_shop("reroll", 0)
	_eq(_armor(), a0 + 6, "shop trigger + permanent grant x3")
	_check(GE.graph_text(g, false).find("6") >= 0, "grant text scaled")


func test_73_graph_serialize() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "dodge", Vector2(1, 2)), GE.add_node(g, "heal_hp", Vector2.ZERO, {"value": 4}))
	var e = GE.make(g)
	var s = e.serialize()
	_eq(s.effect_id, "broeditor_graph", "effect id")
	var e2 = GE.new()
	e2.deserialize_and_merge(JSON.parse(JSON.print(s)).result)
	var p = m.normalize_profile({"graph": e2.graph})
	_eq(GE.paths(p.graph).size(), 1, "ids normalized")
	_check(isvc.effects.has(GE), "registered for save loading")


func test_74_split_native() -> void:
	var t = m.trigger_template("stats_on_level_up")
	var p = m.new_profile()
	p.effects = [{"from": t.from, "i": t.i, "set": {"key": "stat_luck", "value": 4}}]
	m.profiles[CH] = p
	var ui = yield(_open_ui(CH), "completed")
	ui._on_tab_pressed("effects")
	ui._on_effect_split(0)
	_eq(_real(m.profiles[CH].effects).size(), 0, "removed from effect list")
	var g = m.profiles[CH].graph
	_eq(g.nodes.size(), 2, "trigger + effect nodes")
	_eq(g.nodes[0].kind, "level_up", "trigger")
	_eq([g.nodes[1].kind, g.nodes[1].params.stat, g.nodes[1].params.value], ["perm_stat", "stat_luck", 4], "effect node")
	# 蓝图页
	ui._on_tab_pressed("blueprint")
	yield(tree, "idle_frame")
	_eq(ui.blueprint.ge.get_child_count() >= 2, true, "graph nodes shown")
	_check(ui.blueprint.preview.bbcode_text.find("4") >= 0, "path preview")
	ui.blueprint.add_node_kind("chance")
	_eq(g.nodes.size(), 3, "node added from menu")
	var cid = g.nodes[2].id
	ui.blueprint._on_connect("n" + str(g.nodes[0].id), 0, "n" + str(cid), 0)
	ui.blueprint._on_connect("n" + str(cid), 0, "n" + str(g.nodes[1].id), 0)
	_eq(g.links.size(), 3, "links added")
	ui.blueprint._on_param(50.0, cid, "pct")
	_eq(g.nodes[2].params.pct, 50, "param edit")
	ui.blueprint._on_close_node(cid)
	_eq(g.links.size(), 1, "node removal drops links")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_80_start_state() -> void:
	var p = m.new_profile()
	p.start = {"materials": 50, "levels": 3, "crates": 2}
	m.profiles[CH] = p
	m.apply_all()
	rd.set_player_count(1, true)
	rd.add_character(m.find_character(CH), 0)
	var g0 = rd.players_data[0].gold
	var l0 = rd.players_data[0].current_level
	rd.add_starting_items_and_weapons()
	_eq(rd.players_data[0].gold, g0 + 50, "materials")
	_eq(rd.players_data[0].current_level, l0 + 3, "levels direct")
	_eq(m._pending_start[0].crates, 2, "crates pending for first wave")
	p.start = {"levels": 2, "level_settle": true}
	m.profiles[CH] = m.normalize_profile(p)
	rd.add_starting_items_and_weapons()
	_eq(m._pending_start[0].levels, 2, "settle levels pending")
	m._pending_start = {}
	_eq(m.normalize_profile({"start": {"materials": 0, "start_wave": 1.0, "levels": 2.0}}).start, {"levels": 2}, "defaults dropped")


func test_81_gain_and_cap_stats() -> void:
	_eq(m.stat_effect("hp_cap", 30).storage_method, 2, "cap replaces")
	TranslationServer.set_locale("zh")
	# 属性页的效果文本全部用原版字符串
	var cases = [
		["gain_stat_hp_regeneration", -100, "生命再生的修改减少100%"],
		["gain_stat_max_hp", 20, "最大生命值的修改增加20%"],
		["dodge_cap", 90, "闪避上限为90%"],
		["hp_cap", 50, "最大生命值上限为50"],
		["speed_cap", 30, "速度上限为30%"],
		["item_box_gold", 5, "拾取箱子时+5材料"],
		["bounce_damage", 20, "+20%反弹伤害，不会高于基础伤害"],
		["neutral_gold_drops", 10, "+10%树木掉落的材料"],
		["stat_armor", 3, "+3 护甲"],
	]
	for c in cases:
		_eq(m.effect_text(m.stat_effect(c[0], c[1]), false), c[2], c[0])
	_eq(m.stat_name("item_box_gold"), "拾取箱子时获得材料", "item box gold label")
	# 属性获取修改与原版的效果相同：gain_<属性> += value
	var e = m.stat_effect("gain_stat_max_hp", -30)
	_setup_player(CH)
	var h = Keys.generate_hash("gain_stat_max_hp")
	var before = rd.get_player_effect(h, 0)
	e.apply(0)
	_eq(rd.get_player_effect(h, 0), before - 30, "gain modification applied")
	e.unapply(0)
	TranslationServer.set_locale("en")


func test_100_icons() -> void:
	var id = m.create_custom(CH)
	var c = m.find_character(id)
	var base_img = m.find_character(CH).icon.get_data()
	base_img.decompress()
	var img = c.icon.get_data()
	var w = img.get_width()
	var h = img.get_height()
	img.lock()
	base_img.lock()
	_check(img.get_pixel(w - 6, h - 6) != base_img.get_pixel(w - 6, h - 6) or img.get_pixel(w - 10, h - 10) != base_img.get_pixel(w - 10, h - 10), "badge drawn bottom-right")
	_eq(img.get_pixel(2, 2), base_img.get_pixel(2, 2), "rest of icon untouched")
	img.unlock()
	base_img.unlock()
	# 导入图片
	var src = Image.new()
	src.create(200, 100, false, Image.FORMAT_RGBA8)
	src.fill(Color(1, 0, 0, 1))
	var path = OS.get_user_data_dir() + "/be_test_icon.png"
	src.save_png(path)
	var v = m.import_icon(path, id)
	_check(v.begins_with("file:"), "imported")
	m.profiles[id].icon = v
	m.apply_all()
	_eq(c.icon.get_size(), Vector2(96, 96), "imported icon 96x96")
	var im = c.icon.get_data()
	im.lock()
	_eq(im.get_pixel(48, 48), Color(1, 0, 0, 1), "imported content")
	_eq(im.get_pixel(48, 5).a, 0.0, "aspect kept (letterbox transparent)")
	im.unlock()
	_eq(m.import_icon("C:/nope/none.png", id), "", "bad path")


func test_101_categories() -> void:
	var cats = {}
	for e in m.library():
		if not cats.has(e.cat):
			cats[e.cat] = []
		cats[e.cat].push_back(str(e.effect.key) + "|" + str(e.effect.custom_key) + "|" + str(e.effect.text_key))
	for c in ["stat", "stat_mod", "trigger", "scaling", "combat", "economy", "weapon", "structure", "pet", "start"]:
		_check(cats.has(c), "category " + c)
	for s in cats.get("economy", []):
		_check(s.find("dmg_") < 0 and s.find("explo") < 0, "economy has no damage effect: " + s)
	var pets = PoolStringArray(cats.get("pet", [])).join(" ").to_lower()
	_check(pets.find("pet") >= 0, "pets grouped")
	_check(PoolStringArray(cats.get("structure", [])).join(" ").find("turret") >= 0, "turrets in structure")


func test_102_mod_effect_text_fallback() -> void:
	var script = GDScript.new()
	script.source_code = PoolStringArray(["extends \"res://items/global/effect.gd\"", "func get_text(_p, _c = true):", "	return \"CUSTOM\"", ""]).join("\n")
	script.reload()
	var e = script.new()
	e.key = "stat_armor"
	e.value = 3
	var t = m.effect_text(e, false)
	_check(t.find("CUSTOM") < 0 and t.find("3") >= 0, "non-vanilla script uses default text: " + t)
	_eq(m.effect_text(m.stat_effect("stat_armor", 3), false), m.stat_effect("stat_armor", 3).get_text(0, false), "vanilla uses own text")


func test_110_path_text() -> void:
	TranslationServer.set_locale("zh")
	_eq(_path_line([["level_up", {}], ["perm_stat", {"stat": "stat_melee_damage", "value": 2}]]), "升级时+2近战伤害", "zh level up")
	_eq(_path_line([["kill", {}], ["chance", {"pct": 20}], ["add_gold", {"value": 3}]]), "杀死敌人时有20%概率获得3个材料", "zh chance")
	_eq(_path_line([["kill", {}], ["every", {"n": 5}], ["cap", {"n": 3}], ["temp_stat", {"stat": "stat_armor", "value": 1}]]), "每杀死5个敌人，+1护甲，直至敌袭结束（每波最多3次）", "zh every + cap")
	_eq(_path_line([["still", {}], ["temp_stat", {"stat": "stat_percent_damage", "value": 10}]]), "站立不动时+10%伤害", "zh state")
	_eq(_path_line([["level_up", {}], ["every", {"n": 2}], ["hp_below", {"pct": 50}], ["heal_hp", {"value": 5}]]), "升级时恢复5点生命值（每2次）（生命值低于50%时）", "zh conds as suffix")
	_eq(_path_line([["hit", {}], ["timed_stat", {"stat": "stat_dodge", "value": 20, "secs": 3}]]), "受到伤害时+20%闪避，持续3秒", "zh timed")
	TranslationServer.set_locale("en")
	_eq(_path_line([["kill", {}], ["chance", {"pct": 20}], ["add_gold", {"value": 3}]]), "+3 materials when you kill an enemy (20% chance)", "en chance")
	_eq(_path_line([["interval", {"secs": 5}], ["xp", {"value": 2}]]), "+2 XP every 5 seconds", "en interval")


func test_111_stat_names() -> void:
	TranslationServer.set_locale("zh")
	_eq(m.stat_name("piercing"), "贯通", "vanilla label")
	_eq(m.stat_name("bounce_damage"), "%反弹伤害", "vanilla label with %")
	_eq(m.stat_name("number_of_enemies"), "%敌人数量", "own label overrides vague vanilla one")
	_eq(m.stat_name("gain_stat_max_hp"), "%最大生命值修改", "gain modifier")
	_eq(m.stat_name("gain_stat_lifesteal"), "%生命窃取修改", "gain modifier strips %")
	_eq(m.stat_name("loot_alien_speed"), "%战利品外星人速度", "loot alien term")
	TranslationServer.set_locale("en")


func test_112_all_locales() -> void:
	var f = File.new()
	f.open(MOD_DIR + "translations/broeditor.csv", File.READ)
	var keys = []
	var first = true
	while not f.eof_reached():
		var line = f.get_line()
		if first:
			_eq(line.split(",").size(), 14, "13 languages + key")
			first = false
			continue
		if line != "":
			keys.push_back(line.split(",")[0])
	f.close()
	for loc in ["en", "fr", "zh", "ja", "ko", "zh_TW", "ru", "pl", "es", "pt", "de", "tr", "it"]:
		TranslationServer.set_locale(loc)
		var raw = []
		for k in keys:
			if TranslationServer.translate(k) == k:
				raw.push_back(k)
		_eq(raw, [], loc + ": every key translated")
		var t = _path_line([["kill", {}], ["chance", {"pct": 20}], ["every", {"n": 3}], ["cap", {"n": 2}], ["hp_below", {"pct": 50}], ["temp_stat", {"stat": "stat_armor", "value": 1}]])
		_check(t.find("BE_") < 0 and t.find("{") < 0 and t.find("20%") >= 0, loc + ": path text " + t)
		_check(m.stat_name("gain_stat_max_hp").find("BE_") < 0, loc + ": gain stat name")
	TranslationServer.set_locale("en")


func test_120_effect_groups_order() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 1}))
	var p = m.new_profile()
	p.stats = {"stat_armor": 3}
	p.graph = g
	m.profiles[CH] = p
	var c = m.find_character(CH)
	m.apply_all()
	var n0 = m.orig_effects(CH).size()
	_eq(c.effects[n0].key, "stat_armor", "groups after own effects by default")
	_check(c.effects[-1] is GE, "blueprint last by default")
	var ui = yield(_open_ui(CH), "completed")
	ui._on_tab_pressed("effects")
	var specs = ui._edit_specs()
	var gi = -1
	for i in specs.size():
		if specs[i] is Dictionary and specs[i].get("group") == "graph":
			gi = i
	_check(gi > 0, "blueprint row present")
	# 蓝图行上移两次（跳过空的初始装备占位）
	ui._on_effect_move(gi, -1)
	m.apply_all()
	_check(c.effects[n0] is GE, "blueprint moved before the stats group")
	_eq(c.effects[n0 + 1].key, "stat_armor", "stats after blueprint")
	# 生成的效果各占一行（只读）
	var group_rows = 0
	for row in ui._effect_list.get_children():
		if row.has_meta("be_group"):
			group_rows += 1
	_eq(group_rows, 2, "two read-only rows (stat + blueprint)")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_121_attack_while_moving_rule() -> void:
	TranslationServer.set_locale("zh")
	_eq(m.native_set_value(CH, "can_attack_while_moving"), 1, "default 1")
	_eq(m.native_set_value("character_soldier", "can_attack_while_moving"), 0, "soldier 0")
	var p = m.new_profile()
	p.stats = {"can_attack_while_moving": 1}
	m.profiles["character_soldier"] = m.normalize_profile(p)
	m.apply_all()
	rd.set_player_count(1, true)
	rd.add_character(m.find_character("character_soldier"), 0)
	_eq(int(rd.get_player_effect(Keys.can_attack_while_moving_hash, 0)), 1, "soldier can attack while moving after override")
	m.profiles.erase("character_soldier")
	var p2 = m.new_profile()
	p2.stats = {"can_attack_while_moving": 0}
	m.profiles[CH] = m.normalize_profile(p2)
	_eq(m.profiles[CH].stats, {"can_attack_while_moving": 0}, "0 kept for set-value rule")
	m.apply_all()
	rd.set_player_count(1, true)
	rd.add_character(m.find_character(CH), 0)
	_eq(int(rd.get_player_effect(Keys.can_attack_while_moving_hash, 0)), 0, "can be disabled")
	_eq(m.stat_name("next_level_xp_needed"), "%升级需要经验值", "label without placeholder")
	_eq(m.stat_name("torture"), "拷问", "torture label")
	TranslationServer.set_locale("en")


func test_130_item_profile_apply_restore() -> void:
	var it = _plain_item()
	var orig = [it.name, it.value, it.tier, it.max_nb, it.tags, it.effects]
	var p = m.new_profile()
	p.name = "Test Item"
	p.price = 77
	p.tier = 2
	p.max_nb = 1
	p.tags = ["stat_luck"]
	p.stats = {"stat_armor": 3}
	m.item_profiles[it.my_id] = p
	m.apply_all()
	_eq([it.name, it.value, it.tier, it.max_nb, it.tags], ["Test Item", 77, 2, 1, ["stat_luck"]], "item fields applied")
	_eq(it.effects.size(), orig[5].size() + 1, "stat effect appended")
	_check(_find_effect(it.effects, "stat_armor") != null, "stat effect present")
	var in_t3 = false
	for x in isvc._tiers_data[2][isvc.TierData.ITEMS]:
		in_t3 = in_t3 or x == it
	_check(in_t3, "pool rebuilt with new tier")
	# 道具栏总开关关闭 -> 原版
	m.kind_enabled.item = false
	m.apply_all()
	_eq([it.name, it.value, it.tier, it.max_nb, it.tags, it.effects], orig, "kind switch off restores")
	m.kind_enabled.item = true
	m.apply_all()
	m.reset_profile(it.my_id, "item")
	m.apply_all()
	_eq([it.name, it.value, it.tier, it.max_nb, it.tags, it.effects], orig, "reset restores")


func test_131_weapon_stats_apply_restore() -> void:
	var w = isvc.weapons[0]
	var orig_stats = w.stats
	var orig_damage = orig_stats.damage
	var p = m.new_profile()
	p.price = 5
	p.wstats = {"damage": orig_damage + 90, "crit_chance": 0.5}
	p.scaling = [["stat_luck", 2.0]]
	m.weapon_profiles[w.my_id] = p
	m.apply_all()
	_check(w.stats != orig_stats, "stats replaced by a copy")
	_eq([w.stats.damage, w.stats.crit_chance, w.value], [orig_damage + 90, 0.5, 5], "weapon stats applied")
	_eq(JSON.print(w.stats.scaling_stats), JSON.print([[Keys.generate_hash("stat_luck"), 2.0]]), "scaling applied as hashes")
	_eq(JSON.print(m.scaling_names(w.stats.scaling_stats)), JSON.print([["stat_luck", 2.0]]), "scaling names round trip")
	_eq(orig_stats.damage, orig_damage, "original stats untouched")
	_check(w.get_weapon_stats_text(0) != "", "stats text renders")
	m.kind_enabled.weapon = false
	m.apply_all()
	_check(w.stats == orig_stats, "kind switch off restores stats")
	# 武器效果库包含武器自带效果
	var from_weapon = false
	for e in m.library(true):
		from_weapon = from_weapon or m.find_target("weapon", e.from) != null
	_check(from_weapon, "weapon library has weapon effects")
	_check(m.library(true).size() > m.library().size(), "weapon library is larger")


func test_132_bundle_codes() -> void:
	var it = _plain_item()
	var p = m.new_profile()
	p.price = 3
	m.item_profiles[it.my_id] = p
	m.profiles[CH] = m.new_profile()
	var single = m.export_code(it.my_id, "item")
	_check(single.begins_with(m.SHARE_PREFIX), "single prefix")
	_eq(m.import_code(single, CH, "character"), "", "item code rejected for characters")
	var kind_code = m.export_bundle("item")
	_check(kind_code.begins_with(m.BUNDLE_PREFIX.item), "item bundle prefix")
	_eq(m.export_bundle("weapon"), "", "empty bundle exports nothing")
	var all_code = m.export_bundle("")
	_check(all_code.begins_with(m.ALL_PREFIX), "all prefix")
	m.item_profiles = {}
	m.profiles = {}
	_eq(m.import_bundle(kind_code), 1, "item bundle imported")
	_eq(m.item_profiles[it.my_id].price, 3, "bundle content")
	_eq(m.profiles.size(), 0, "item bundle leaves characters")
	m.item_profiles = {}
	_eq(m.import_bundle(all_code), 2, "all bundle imported")
	_eq(m.import_bundle(single), -1, "single code is not a bundle")
	_eq(m.import_bundle("BEA1:!!"), -1, "bad bundle rejected")


func test_140_custom_item() -> void:
	var base = _plain_item()
	var id = m.create_custom_item(base.my_id)
	_check(id.begins_with(m.ITEM_PREFIX), "custom item id")
	var it = m.find_target("item", id)
	_check(it != null and it in isvc.items, "registered in ItemService")
	m.apply_all()
	_eq([it.value, it.tier, it.max_nb], [base.value, base.tier, base.max_nb], "fields from base")
	_eq(it.effects.size(), base.effects.size(), "effects copied from base")
	_eq(m.source_of(it), "mod", "custom item is a mod item")
	_check(it.icon != null, "has icon")
	m.item_profiles[id].tier = 2
	m.item_profiles[id].price = 3
	m._register_custom_item(id)
	m.apply_all()
	_eq([it.tier, it.value], [2, 3], "tier / price edits")
	m.kind_enabled.item = false
	m.apply_all()
	_eq(it.tier, 2, "custom item ignores the item tab switch")
	m.kind_enabled.item = true
	var id2 = m.import_code(m.export_code(id, "item"), "", "item")
	_check(id2 != "" and id2 != id and m.is_custom(id2), "custom item code imports as new custom item")
	_check(m.delete_custom_item(id), "deleted")
	_check(m.find_target("item", id) == null and not it in isvc.items, "unregistered")


func test_141_disable() -> void:
	var it = _plain_item()
	var w = isvc.weapons[0]
	m.set_disabled("item", it.my_id, true)
	m.set_disabled("weapon", w.weapon_id, true)
	m.set_disabled("character", CH, true)
	m.apply_all()
	var bans = m.ban_hashes(0)
	_check(Keys.generate_hash(it.my_id) in bans, "disabled item banned")
	var all = true
	for x in m.family_members(w.weapon_id):
		all = all and x.my_id_hash in bans
	_check(all, "every tier of a disabled weapon banned")
	_check(Keys.generate_hash(CH) in m.disabled_character_hashes(), "disabled character hidden from unlocked")
	_eq(m.without([1, 2, 3], [2]), [1, 3], "without helper")
	m.kind_enabled.item = false
	m.kind_enabled.character = false
	m.apply_all()
	_check(not Keys.generate_hash(it.my_id) in m.ban_hashes(0), "item tab switch off lifts item disable")
	_check(m.disabled_character_hashes().empty(), "character tab switch off lifts character disable")
	m.set_disabled("weapon", w.weapon_id, false)
	_check(not w.my_id_hash in m.ban_hashes(0), "re-enabled weapon")


func test_142_custom_weapon() -> void:
	var base = _family_from(0, 0)
	var ranged = _family_from(0, 1)
	var id = m.create_custom_weapon(base[0].weapon_id)
	m.apply_all()
	var w = m.find_target("weapon", id)
	_check(w != null and w in isvc.weapons, "custom weapon registered")
	var wid = w.weapon_id
	_check(wid.begins_with(m.WEAPON_PREFIX), "custom weapon family id")
	_eq(w.type, base[0].type, "type from base")
	_eq(m.family_members(wid).size(), base.size(), "whole base family copied")
	_check(m.family_complete(wid), "copied family is complete")
	_check(m.delete_weapon_tier(m.family_members(wid)[-1].my_id), "top tier deleted")
	m.apply_all()
	_check(not m.family_complete(wid) and m.is_disabled("weapon", wid), "incomplete weapon is disabled")
	_check(w.my_id_hash in m.global_ban_hashes(), "incomplete weapon banned")
	_eq(m.addable_tiers(wid), [3], "can add next tier")
	_check(m.add_weapon_tier(wid, 3) != "", "added tier back")
	_eq(m.add_weapon_tier(wid, 3), "", "no duplicate tier")
	m.apply_all()
	_check(m.family_complete(wid) and not m.is_disabled("weapon", wid), "complete weapon enabled")
	var ms = m.family_members(wid)
	_eq(ms.size(), 4, "four tiers")
	var linked = true
	for i in 3:
		linked = linked and ms[i].upgrades_into == ms[i + 1] and ms[i + 1].previous_upgrade == ms[i]
	_check(linked and ms[3].upgrades_into == null, "upgrade chain")
	_check(ms[3].value > ms[0].value, "higher tiers cost more")
	m.weapon_profiles[ms[1].my_id].wstats = {"damage": 77}
	m.apply_all()
	_eq(ms[1].stats.damage, 77, "custom tier stats edit")
	# 改为远程：基底换成远程武器家族
	m.weapon_families[wid].base = ranged[0].weapon_id
	m.apply_all()
	_eq(ms[0].type, ranged[0].type, "switched to ranged")
	_check("nb_projectiles" in ms[0].stats, "ranged stats")
	m.weapon_families[wid].sets = [isvc.sets[0].my_id]
	m.apply_all()
	var sets_ok = true
	for x in ms:
		sets_ok = sets_ok and x.sets.size() == 1 and x.sets[0].my_id == isvc.sets[0].my_id
	_check(sets_ok, "sets for all tiers")
	_check(not m.delete_weapon_tier(ms[1].my_id), "middle tier cannot be deleted")
	_check(m.delete_weapon_tier(ms[3].my_id), "top tier deleted")
	m.apply_all()
	_check(not m.family_complete(wid), "incomplete again")
	_check(m.delete_custom_weapon(wid), "custom weapon deleted")
	_check(m.family_members(wid).empty(), "all tiers removed")


func test_143_lower_tier_for_vanilla() -> void:
	var ms = _family_from(1, 0)
	if ms == null:
		ms = _family_from(1, 1)
	var wid = ms[0].weapon_id
	var lo = ms[0]
	_eq(m.addable_tiers(wid), [0], "vanilla family: only a lower tier")
	var id = m.add_weapon_tier(wid, 0)
	m.apply_all()
	var nw = m.find_target("weapon", id)
	_check(nw != null and nw.tier == 0, "lower tier registered")
	_check(nw.upgrades_into == lo and lo.previous_upgrade == nw, "links into vanilla tier")
	_check(nw.value < lo.value, "cheaper")
	_eq(m.source_of(nw), "mod", "added tier is a mod weapon")
	_check(m.family_complete(wid), "still complete")
	m.weapon_families[wid].name = "Test Weapon"
	m.apply_all()
	var named = true
	for x in m.family_members(wid):
		named = named and x.name == "Test Weapon"
	_check(named, "family name for all tiers")
	m.kind_enabled.weapon = false
	m.apply_all()
	_check(lo.name != "Test Weapon", "weapon tab switch off restores vanilla name")
	m.kind_enabled.weapon = true
	var code = m.export_bundle("weapon")
	_check(m.delete_weapon_tier(id), "lower tier deleted")
	_check(lo.previous_upgrade == null, "unlinked")
	_check(m.import_bundle(code) > 0, "bundle imported")
	m.apply_all()
	_check(m.find_target("weapon", id) != null, "bundle restores added tier")


func test_144_sources() -> void:
	for c in isvc.characters:
		if c.resource_path.begins_with("res://dlcs/dlc_1/"):
			_eq(m.source_of(c), "dlc1", "dlc character source")
			break
	_eq(m.source_of(m.find_character(CH)), "vanilla" if m.find_character(CH).resource_path.begins_with("res://items/") else m.source_of(m.find_character(CH)), "vanilla character")
	var id = m.create_custom(CH)
	_eq(m.source_of(m.find_character(id)), "mod", "custom character is mod")


func test_146_attack_interval() -> void:
	for w in isvc.weapons:
		var cd = m.Catalog.attack_interval(w.stats)
		if cd <= 0.0 or cd > 10.0:
			_check(false, "attack interval sane for " + w.my_id)
			return
	_check(true, "attack intervals sane")


func test_151_ids_and_rename() -> void:
	_eq(m.clean_suffix(" my item-2! "), "my_item2", "suffix cleaned")
	var base = _plain_item()
	var iid = m.create_custom_item(base.my_id)
	var body = base.my_id.trim_prefix("item_")
	_check(iid.begins_with("item_" + body + "_"), "default id = item_<base>_<random>")
	_eq(m.create_custom_item(base.my_id, base.my_id.trim_prefix("item_")), "", "taken suffix rejected")
	var named = m.create_custom_item(base.my_id, "solution")
	_eq(named, "item_solution", "custom suffix")
	m.profiles[CH] = m.new_profile()
	m.profiles[CH].ban_items = [named]
	_eq(m.rename_custom("item", named, "new solution"), "item_new_solution", "item renamed")
	_check(m.find_target("item", "item_new_solution") != null and m.find_target("item", named) == null, "item resource renamed")
	_eq(m.profiles[CH].ban_items, ["item_new_solution"], "references follow")
	_eq(m.rename_custom("item", "item_new_solution", base.my_id.trim_prefix("item_")), "", "rename to vanilla id rejected")
	var cid = m.create_custom(CH, "hero")
	_eq(cid, "character_hero", "character id")
	_eq(m.rename_custom("character", cid, "hero2"), "character_hero2", "character renamed")
	_check(m.find_character("character_hero2") != null, "character resource renamed")
	var fam = _family_from(0, 0)
	var wt = m.create_custom_weapon(fam[0].weapon_id, "blade")
	_eq(wt, "weapon_blade_1", "weapon tier id")
	_eq(m.rename_custom("weapon", "weapon_blade", "sword x"), "weapon_sword_x", "weapon renamed")
	var ms = m.family_members("weapon_sword_x")
	_eq(ms.size(), fam.size(), "all tiers moved")
	_eq(ms[0].my_id, "weapon_sword_x_1", "tier ids follow")
	_check(m.weapon_profiles.has("weapon_sword_x_1") and not m.weapon_profiles.has("weapon_blade_1"), "tier profiles moved")
	m.apply_all()
	_check(m.family_complete("weapon_sword_x"), "renamed weapon still complete")
	# 隐藏编号
	var p = m.item_profiles["item_new_solution"]
	var numbered = m.custom_icon("item_new_solution", p, "item")
	m.hide_numbers = true
	var plain = m.custom_icon("item_new_solution", p, "item")
	m.hide_numbers = false
	_check(plain == base.icon and numbered != base.icon, "hide numbers uses the vanilla icon")


func test_152_weapon_effect_categories() -> void:
	for path in ["res://dlcs/dlc_1/weapons/melee/lute/1/lute_effect_0.tres",
			"res://weapons/ranged/particle_accelerator/3/particle_accelerator_3_effect_2.tres",
			"res://weapons/ranged/crossbow/1/crossbow_effect.tres"]:
		if ResourceLoader.exists(path):
			_eq(m.Catalog.category_of(load(path)), "combat", path.get_file() + " is combat")



func test_160_custom_files() -> void:
	var cid = m.create_custom(CH, "filetest")
	var iid = m.create_custom_item(_plain_item().my_id, "filetest")
	var fam = _family_from(0, 0)
	var wt = m.create_custom_weapon(fam[0].weapon_id, "filetest")
	m.weapon_profiles[wt].wstats = {"damage": 55}
	m.profiles[CH] = m.new_profile()
	m.profiles[CH].stats = {"stat_luck": 2}
	m.save_profiles()
	for name in ["character/character_filetest", "item/item_filetest", "weapon/weapon_filetest"]:
		var t = _read(m.CUSTOM_DIR + name + ".json")
		_check(t != "" and t.find("\n") < 0, name + " saved as one-line json")
	var main = JSON.parse(_read(m.SAVE_PATH)).result
	_check(not main.profiles.has(cid) and main.profiles.has(CH), "profiles.json keeps only vanilla changes")
	_check(not main.items.has(iid) and not main.weapons.has(wt) and not main.families.has("weapon_filetest"), "no custom objects in profiles.json")
	# 重新读取
	m.load_profiles()
	m.apply_all()
	_check(m.find_character(cid) != null and m.find_target("item", iid) != null, "custom character / item reloaded")
	_eq(m.family_members("weapon_filetest").size(), fam.size(), "custom weapon tiers reloaded")
	_eq(m.weapon_profiles[wt].wstats.get("damage"), 55, "weapon tier profile reloaded")
	_eq(m.profiles[CH].stats, {"stat_luck": 2}, "vanilla change reloaded")
	# 删除后文件也删除
	_check(m.delete_custom_item(iid), "deleted")
	m.save_profiles()
	_check(not File.new().file_exists(m.CUSTOM_DIR + "item/" + iid + ".json"), "file removed with the item")
	# 别人分享的文件：复制进对应种类的文件夹即可
	var shared = m.custom_file_data("character", cid)
	shared.id = "character_shared_one"
	var f = File.new()
	f.open(m.CUSTOM_DIR + "character/character_shared_one.json", File.WRITE)
	f.store_string(JSON.print(shared))
	f.close()
	m.load_profiles()
	m.apply_all()
	_check(m.find_character("character_shared_one") != null, "shared file loaded as a custom character")
	_eq(m.load_custom_data({"kind": "item", "id": _plain_item().my_id, "profile": {}}), "", "file clashing with a vanilla id ignored")
	_eq(m.load_custom_data({"kind": "item", "id": "character_bad", "profile": {}}), "", "id must match its kind")
	m.delete_custom("character_shared_one")
	m.delete_custom(cid)
	m.delete_custom_weapon("weapon_filetest")
	m.profiles = {}
	m.save_profiles()
	_eq(m.custom_files(), [], "all custom files removed")


# 新建自定义武器、补等级时复制效果；效果库去重开关
func test_170_weapon_effects_copied_and_library_dedup() -> void:
	var fam = null
	var seen = {}
	for w in isvc.weapons:
		if seen.has(w.weapon_id):
			continue
		seen[w.weapon_id] = true
		var ms = m.family_members(w.weapon_id)
		if ms[0].tier == 1 and not ms[0].effects.empty():
			fam = ms
			break
	_check(fam != null, "a vanilla family starting at T2 with effects")
	if fam == null:
		return
	var wid = fam[0].weapon_id
	# 补低级版本：复制相邻（较高）等级的效果
	var low = m.add_weapon_tier(wid, 0)
	m.apply_all()
	_eq(m.find_target("weapon", low).effects.size(), fam[0].effects.size(), "lower tier copies the next tier's effects")
	# 新建自定义武器：每级复制基底同级的效果
	var top = m.create_custom_weapon(wid)
	m.apply_all()
	var cwid = m.find_target("weapon", top).weapon_id
	var cms = m.family_members(cwid)
	var ok = cms.size() >= 1
	for w in cms:
		var vm = null
		for v in fam:
			if v.tier == w.tier:
				vm = v
		ok = ok and vm != null and w.effects.size() == vm.effects.size()
	_check(ok, "custom weapon tiers copy the base tiers' effects")
	# 自定义武器补高级 / 低级：复制相邻等级（含档案里的修改）
	m.weapon_profiles[cms[0].my_id].effects = [{"from": fam[0].my_id, "i": 0}]
	var cl = m.add_weapon_tier(cwid, cms[0].tier - 1)
	_eq(JSON.print(m.weapon_profiles[cl].effects), JSON.print([{"from": fam[0].my_id, "i": 0}]), "custom lower tier copies the edited neighbour")
	# 去重开关
	m.set_library_dedup(false)
	var full = m.library(true).size()
	var keys = {}
	var dup = false
	for e in m.library(true):
		var k = str(e.effect.get_script()) + e.effect.text_key + e.effect.custom_key + e.effect.key
		dup = dup or keys.has(k)
		keys[k] = true
	_check(dup, "dedup off keeps duplicates")
	m.set_library_dedup(true)
	_check(m.library(true).size() < full, "dedup on is smaller (%d < %d)" % [m.library(true).size(), full])
	m.set_library_dedup(false)
	m.delete_custom_weapon(cwid)


# 效果库里第一个带指定子资源字段的效果
func _lib_with_sub(field: String, script_part: String = ""):
	for entry in m.library(true):
		var e = entry.effect
		if field in m.Catalog.sub_fields(e) and (script_part == "" or e.get_script().resource_path.find(script_part) >= 0):
			return entry
	return null


# 子资源（燃烧 / 投射物 / 爆炸的武器属性）的详细信息：写入 spec.sub，复制后改写，不影响模板
func test_180_effect_sub_resources() -> void:
	var burn = _lib_with_sub("burning_data", "burn_chance")
	_check(burn != null, "burn chance effect in the library")
	if burn != null:
		var e = m.make_effect({"from": burn.from, "i": burn.i, "sub": {"burning_data": {"damage": 99, "duration": 7, "scaling_stats": [["stat_max_hp", 0.5]]}}})
		_eq([e.burning_data.damage, e.burning_data.duration], [99, 7], "burning damage / duration")
		_eq(m.scaling_names(e.burning_data.scaling_stats), [["stat_max_hp", 0.5]], "burning scaling: +50% max HP")
		_check(burn.effect.burning_data.damage != 99 and e.burning_data != burn.effect.burning_data, "template untouched")
		_check(m.effect_text(e, false).find("7x") >= 0, "text shows the new duration: " + m.effect_text(e, false))
	var proj = _lib_with_sub("weapon_stats", "projectile")
	_check(proj != null, "projectile effect in the library")
	if proj != null:
		var e = m.make_effect({"from": proj.from, "i": proj.i, "sub": {"weapon_stats": {"damage": 42, "nb_projectiles": 3}}})
		_eq([e.weapon_stats.damage, e.weapon_stats.nb_projectiles], [42, 3], "projectile damage / count")
		_check(proj.effect.weapon_stats.damage != 42, "template untouched")
	var boom = _lib_with_sub("stats", "exploding")
	_check(boom != null, "explosion effect in the library")
	if boom != null:
		var e = m.make_effect({"from": boom.from, "i": boom.i, "sub": {"stats": {"scaling_stats": [["stat_max_hp", 0.5], ["stat_elemental_damage", 1.0]]}}})
		_eq(m.scaling_names(e.stats.scaling_stats), [["stat_max_hp", 0.5], ["stat_elemental_damage", 1.0]], "explosion scaling")
	# 存档往返（JSON）
	var spec = JSON.parse(JSON.print({"from": burn.from, "i": burn.i, "sub": {"burning_data": {"damage": 12}}})).result
	_eq(m.make_effect(spec).burning_data.damage, 12, "JSON round trip")
	_eq(m.Catalog.category_of(_beast_effect()), "pet", "beast master effect is a pet effect")


func _beast_effect():
	for e in m.orig_effects("character_beast_master"):
		if e.key == "beast_master_effect":
			return e
	return null


# 诅咒（DLC）后的效果：属性、子资源、蓝图都照常生效
func test_181_cursed_effects() -> void:
	var dlc = tree.root.get_node("ProgressData").get_dlc_data("abyssal_terrors")
	_check(dlc != null, "DLC data available")
	if dlc == null:
		return
	var burn = _lib_with_sub("burning_data", "burn_chance")
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_engineering", "value": 3}))
	var iid = m.create_custom_item(_plain_item().my_id, "cursetest")
	var p = m.item_profiles[iid]
	p.stats = {"stat_armor": 4}
	p.effects = [{"from": burn.from, "i": burn.i, "sub": {"burning_data": {"damage": 20}}}]
	p.graph = g
	m.apply_all()
	var it = m.find_target("item", iid)
	var cursed = dlc.curse_item(it, 0, true, 0.5)
	_check(cursed.is_cursed and cursed != it, "item cursed")
	var ge = null
	var armor = null
	var b = null
	for e in cursed.effects:
		if e.get_script() == GE:
			ge = e
		elif e.key == "stat_armor":
			armor = e
		elif "burning_data" in e:
			b = e
	_check(ge != null and GE.paths(ge.graph).size() == 1, "blueprint survives the curse")
	_check(armor != null and armor.value >= 4, "stat effect kept (boosted: %s)" % (armor.value if armor != null else -1))
	_check(b != null and b.burning_data.damage >= 20, "edited burning kept (boosted: %s)" % (b.burning_data.damage if b != null else -1))
	# 加入一局：属性生效，蓝图在波次开始时触发
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	var a0 = rd.get_player_effect(Keys.generate_hash("stat_armor"), 0)
	rd.add_item(cursed, 0)
	_eq(rd.get_player_effect(Keys.generate_hash("stat_armor"), 0), a0 + armor.value, "cursed stat applied")
	var eng0 = rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0)
	m.graph_dirty = true
	m.runtime.start_wave(null)
	m.runtime.fire("wave_start", 0)
	_eq(rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0), eng0 + _good(3), "blueprint on the cursed item fires (cursed value)")
	m.runtime.end_wave()
	# 自定义武器诅咒：伤害提高，效果保留（原版另加一条诅咒属性）
	var base_w = null
	for v in isvc.weapons:
		if v.tier == 0 and not v.effects.empty() and not m.is_custom(v.my_id):
			base_w = v
			break
	var wt = m.create_custom_weapon(base_w.weapon_id, "cursetest")
	m.apply_all()
	var w = m.find_target("weapon", wt)
	var cw = dlc.curse_item(w, 0, true, 0.5)
	_check(cw.is_cursed and cw.stats.damage >= w.stats.damage, "custom weapon cursed: damage %d -> %d" % [w.stats.damage, cw.stats.damage])
	var keys = []
	for e in w.effects:
		keys.push_back(e.key)
	var ckeys = []
	for e in cw.effects:
		if e.key != "stat_curse":
			ckeys.push_back(e.key)
	_check(not keys.empty(), "weapon has effects: " + str(keys))
	_eq(ckeys, keys, "custom weapon effects kept through the curse")
	m.delete_custom_item(iid)
	m.delete_custom_weapon(m.find_target("weapon", wt).weapon_id)


# ---------------- 蓝图诅咒 ----------------
const CURSE_M = 0.5


static func _good(v: int) -> int:
	return int(sign(v)) * int(ceil(abs(v) * (1.0 + CURSE_M)))


static func _bad(v: int) -> int:
	return int(sign(v)) * int(max(1.0, floor(abs(v) / (1.0 + CURSE_M))))


# 自定义道具挂上蓝图后诅咒（系数固定 0.5），返回 [诅咒后的道具, 蓝图效果, 道具 id]
func _cursed_graph_item(g: Dictionary, suffix: String) -> Array:
	var dlc = tree.root.get_node("ProgressData").get_dlc_data("abyssal_terrors")
	var iid = m.create_custom_item(_plain_item().my_id, suffix)
	m.item_profiles[iid].effects = []
	m.item_profiles[iid].graph = g
	m.apply_all()
	var cursed = dlc.curse_item(m.find_target("item", iid), 0, true, CURSE_M)
	var ge = null
	for e in cursed.effects:
		if e.get_script() == load(GraphEffectScript):
			ge = e
	return [cursed, ge, iid]


func _burn_ref(dmg: int) -> Dictionary:
	for entry in m.library(true):
		if "burning_data" in m.Catalog.sub_fields(entry.effect) and entry.effect.get_script().resource_path.find("burn_chance") >= 0:
			return {"from": entry.from, "i": entry.i, "sub": {"burning_data": {"damage": dmg, "duration": 3}}}
	return {}


# 各种节点与组合在诅咒后的数值。路径符号 = 效果的好坏；默认诅咒效果的数值，路径上有"每 X 次"时改诅咒 X（方向 = 效果符号 × -1）
func test_190_cursed_blueprint_values() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var ids = {}
	var rows = {
		"armor": ["wave_start", ["perm_stat", {"stat": "stat_armor", "value": 3}]],
		"armor_neg": ["wave_start", ["perm_stat", {"stat": "stat_armor", "value": -4}]],
		"price_good": ["wave_start", ["perm_stat", {"stat": "items_price", "value": -5}]],
		"price_bad": ["wave_start", ["perm_stat", {"stat": "items_price", "value": 5}]],
		"enemies": ["wave_start", ["temp_stat", {"stat": "number_of_enemies", "value": 10}]],
		"dodge_cap": ["wave_start", ["temp_stat", {"stat": "dodge_cap", "value": 60}]],
		"timed": ["wave_start", ["timed_stat", {"stat": "stat_attack_speed", "value": 20, "secs": 3}]],
		"timed_bad": ["hit", ["timed_stat", {"stat": "stat_armor", "value": -6, "secs": 4}]],
		"every_gold": ["kill", ["every", {"n": 6}], ["add_gold", {"value": 2}]],
		"every_bad": ["kill", ["every", {"n": 6}], ["perm_stat", {"stat": "stat_armor", "value": -2}]],
		"every_neutral": ["kill", ["every", {"n": 6}], ["temp_stat", {"stat": "number_of_enemies", "value": 10}]],
		"every_price": ["kill", ["every", {"n": 6}], ["perm_stat", {"stat": "items_price", "value": -5}]],
		"every1": ["crit", ["every", {"n": 1}], ["heal_hp", {"value": 3}]],
		"wave_every": ["kill", ["wave_min", {"n": 5}], ["every", {"n": 6}], ["add_gold", {"value": 2}]],
		"chance": ["level_up", ["chance", {"pct": 40}], ["xp", {"value": 5}]],
		"chance80": ["wave_start", ["chance", {"pct": 80}], ["damage", {"stat": "stat_ranged_damage", "pct": 100}]],
		"waves": ["wave_start", ["wave_min", {"n": 10}], ["wave_max", {"n": 10}], ["explode", {"stat": "stat_elemental_damage", "pct": 100}]],
		"cap": ["hit", ["cap", {"n": 4}], ["cooldown", {"secs": 3}], ["hp_dmg", {"pct": 5}]],
		"hp": ["hit", ["hp_below", {"pct": 50}], ["hp_above", {"pct": 50}], ["ignite", {"value": 5}]],
		"stats": ["kill", ["stat_min", {"stat": "stat_armor", "n": 10}], ["stat_max", {"stat": "stat_luck", "n": 10}], ["slow", {"pct": 10}]],
		"misc": ["wave_start", ["rand_stats", {"value": 1}]],
		"fruit": ["wave_start", ["fruit", {"value": 1}]],
	}
	for r in rows:
		var prev = GE.add_node(g, rows[r][0], Vector2.ZERO)
		for k in range(1, rows[r].size()):
			var step = rows[r][k]
			var id = GE.add_node(g, step[0], Vector2.ZERO, step[1].duplicate())
			ids[r + ":" + step[0]] = id
			GE.add_link(g, prev, id)
			prev = id
	var it = GE.add_node(g, "interval", Vector2.ZERO, {"secs": 5})
	ids["interval"] = it
	var gr = GE.add_node(g, "grant", Vector2.ZERO, {"ref": _burn_ref(20), "n": 1, "mode": "temp"})
	ids["grant"] = gr
	GE.add_link(g, it, gr)
	var res = _cursed_graph_item(g, "cursegraph")
	var ge = res[1]
	_check(ge != null, "blueprint on the cursed item")
	if ge == null:
		return
	_check(abs(ge.curse_modifier() - CURSE_M) < 0.002, "curse modifier recovered: %s" % ge.curse_modifier())
	var by = GE.nodes_by_id(ge.live_graph())
	var cases = [
		["armor:perm_stat", "value", _good(3), "+3 armor grows"],
		["armor_neg:perm_stat", "value", _bad(-4), "-4 armor shrinks"],
		["price_good:perm_stat", "value", _good(-5), "-X% price: X grows"],
		["price_bad:perm_stat", "value", _bad(5), "+X% price: X shrinks"],
		["enemies:temp_stat", "value", 10, "+X% enemies: neutral, unchanged"],
		["timed:timed_stat", "value", _good(20), "timed +attack speed grows"],
		["timed:timed_stat", "secs", _good(3), "its duration grows"],
		["timed_bad:timed_stat", "value", _bad(-6), "timed -armor shrinks"],
		["timed_bad:timed_stat", "secs", _bad(4), "its duration shrinks"],
		["every_gold:every", "n", _bad(6), "every X kills -> +gold: X shrinks"],
		["every_gold:add_gold", "value", 2, "  and the gold is unchanged"],
		["every_bad:every", "n", _good(6), "every X kills -> -armor: X grows (-1 x -1)"],
		["every_bad:perm_stat", "value", -2, "  and the armor is unchanged"],
		["every_neutral:every", "n", 6, "every X kills -> +enemies (neutral): unchanged"],
		["every_price:every", "n", _bad(6), "every X kills -> -price: X shrinks"],
		["every_price:perm_stat", "value", -5, "  and the price is unchanged"],
		["every1:every", "n", 1, "every 1 stays 1"],
		["every1:heal_hp", "value", 3, "  heal unchanged"],
		["wave_every:every", "n", _bad(6), "other conditions do not flip every X"],
		["wave_every:wave_min", "n", 5, "  from-wave unchanged"],
		["chance:chance", "pct", 40, "chance unchanged"],
		["chance:xp", "value", _good(5), "  xp grows"],
		["chance80:chance", "pct", 80, "chance 80 unchanged"],
		["chance80:damage", "pct", _good(100), "  damage % grows"],
		["waves:wave_min", "n", 10, "wave conditions unchanged"],
		["waves:wave_max", "n", 10, "wave conditions unchanged"],
		["waves:explode", "pct", _good(100), "  explosion % grows"],
		["cap:cap", "n", 4, "cap unchanged"],
		["cap:cooldown", "secs", 3, "cooldown unchanged"],
		["cap:hp_dmg", "pct", _good(5), "  hp damage grows"],
		["hp:hp_below", "pct", 50, "hp conditions unchanged"],
		["hp:ignite", "value", _good(5), "  ignite grows"],
		["stats:stat_min", "n", 10, "stat conditions unchanged"],
		["stats:slow", "pct", _good(10), "  slow grows"],
		["misc:rand_stats", "value", _good(1), "random stats grow"],
		["fruit:fruit", "value", _good(1), "fruit grows"],
		["interval", "secs", 5, "interval unchanged"],
		["grant", "n", 1, "grant count unchanged"],
	]
	for c in cases:
		_eq(int(by[ids[c[0]]].params[c[1]]), c[2], c[3])
	var dc = int(by[ids["dodge_cap:temp_stat"]].params.value)
	_check(dc >= 72 and dc <= 76, "dodge cap uses the vanilla special case (72-76): %d" % dc)
	var be = m.make_effect(by[ids["grant"]].params.ref)
	_check(be.burning_data.damage == _good(20) and be.burning_data.duration == _good(3), "granted burning cursed like vanilla: %d dmg / %d s" % [be.burning_data.damage, be.burning_data.duration])
	_eq(int(GE.nodes_by_id(ge.graph)[ids["armor:perm_stat"]].params.value), 3, "original graph untouched")
	_check(ge.get_text(0, false).find(str(_good(3))) >= 0, "text shows cursed values")
	m.delete_custom_item(res[2])


# 诅咒后的蓝图在一局中按诅咒后的数值触发；存档往返保留诅咒
func test_191_cursed_blueprint_runtime() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 3}))
	var ev = GE.add_node(g, "every", Vector2.ZERO, {"n": 6})
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), ev)
	GE.add_link(g, ev, GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 2}))
	GE.add_link(g, GE.add_node(g, "level_up", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "items_price", "value": -5}))
	var res = _cursed_graph_item(g, "curserun")
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_item(res[0], 0)
	var h_armor = Keys.generate_hash("stat_armor")
	var h_price = Keys.generate_hash("items_price")
	var a0 = rd.get_player_effect(h_armor, 0)
	var p0 = rd.get_player_effect(h_price, 0)
	m.graph_dirty = true
	m.runtime.start_wave(null)
	m.runtime.fire("wave_start", 0)
	_eq(rd.get_player_effect(h_armor, 0), a0 + _good(3), "wave start: cursed armor")
	m.runtime.fire("level_up", 0)
	_eq(rd.get_player_effect(h_price, 0), p0 + _good(-5), "level up: cursed price reduction")
	var g0 = rd.players_data[0].gold
	for i in _bad(6):
		m.runtime.fire("kill", 0)
	_eq(rd.players_data[0].gold - g0, 2, "every %d kills (cursed from 6): +2 materials" % _bad(6))
	m.runtime.end_wave()
	var ge = res[1]
	var copy = GE.new()
	copy.deserialize_and_merge(ge.serialize())
	_check(abs(copy.curse_modifier() - CURSE_M) < 0.002, "curse survives save / load")
	var uncursed = GE.make(g)
	_check(uncursed.curse_modifier() == 0.0 and uncursed.live_graph() == uncursed.graph, "uncursed blueprint uses its own values")
	m.delete_custom_item(res[2])
