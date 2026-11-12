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
	# 压缩格式：正文以 PACK 开头，只含非默认字段；旧的未压缩码仍可导入
	_check(code2.begins_with(m.SHARE_PREFIX + m.PACK), "compressed body")
	var body = m.unpack(code2.substr(m.SHARE_PREFIX.length()))
	_check(body.profile.has("custom") and not body.profile.has("wstats") and not body.profile.has("price"), "defaults stripped: " + str(body.profile.keys()))
	var old = m.SHARE_PREFIX + "eyJraW5kIjoiY2hhcmFjdGVyIiwiaWQiOiJjaGFyYWN0ZXJfd2VsbF9yb3VuZGVkXzc1MTYiLCJwcm9maWxlIjp7ImVuYWJsZWQiOnRydWUsImN1c3RvbSI6dHJ1ZSwibmFtZSI6IueZvemprOmTg+iWryIsImRlc2MiOiIiLCJiYXNlIjoiY2hhcmFjdGVyX3dpbGRsaW5nIiwiaWNvbiI6IiIsImVmZmVjdHMiOlt7ImZyb20iOiJjaGFyYWN0ZXJfZmlzaGVybWFuIiwiaSI6Miwic2V0Ijp7ImtleSI6Iml0ZW1fcmljb2NoZXQifX0seyJmcm9tIjoiY2hhcmFjdGVyX2Zpc2hlcm1hbiIsImkiOjMsInNldCI6eyJrZXkiOiJpdGVtX3JpY29jaGV0IiwidmFsdWUiOi05MH19LHsiZnJvbSI6ImNoYXJhY3Rlcl9nbHV0dG9uIiwiaSI6M30seyJncm91cCI6InN0YXRzIiwia2V5IjoiYm91bmNlX2RhbWFnZSJ9LHsiZ3JvdXAiOiJzdGF0cyIsImtleSI6InBpZXJjaW5nX2RhbWFnZSJ9LHsiZnJvbSI6ImNoYXJhY3Rlcl9yYW5nZXIiLCJpIjozfV0sInN0YXRzIjp7ImJvdW5jZV9kYW1hZ2UiOjEwMCwicGllcmNpbmdfZGFtYWdlIjotMTAwLCJnYWluX3N0YXRfcGVyY2VudF9kYW1hZ2UiOi0xMjV9LCJ3ZWFwb25zIjpbIndlYXBvbl9rbmlmZV8xIiwid2VhcG9uX3N0aWNrXzEiLCJ3ZWFwb25fZmlzdF8xIiwid2VhcG9uX2Nob3BwZXJfMSIsIndlYXBvbl9maWdodGluZ19zdGlja18xIiwid2VhcG9uX2NhY3RpX2NsdWJfMSIsIndlYXBvbl9oYXRjaGV0XzEiLCJ3ZWFwb25fc3Bpa3lfc2hpZWxkXzEiLCJ3ZWFwb25fZ2hvc3RfZmxpbnRfMSIsIndlYXBvbl93cmVuY2hfMSIsIndlYXBvbl9waXN0b2xfMSIsIndlYXBvbl9zbWdfMSIsIndlYXBvbl9kb3VibGVfYmFycmVsX3Nob3RndW5fMSIsIndlYXBvbl9zbGluZ3Nob3RfMSIsIndlYXBvbl90YXNlcl8xIiwid2VhcG9uX3dhbmRfMSIsIndlYXBvbl9pY2ljbGVfMSIsIndlYXBvbl9yYWlsX2d1bl8xIiwid2VhcG9uX2x1dGVfMSJdLCJzdGFydF9pdGVtcyI6W3siaWQiOiJpdGVtX3JpY29jaGV0IiwibiI6MSwiY3Vyc2VkIjpmYWxzZX1dLCJiYW5faXRlbXMiOlsiaXRlbV9zaGFycF9idWxsZXQiLCJpdGVtX2JhbmRhbmEiLCJpdGVtX2V5ZXBhdGNoIiwiaXRlbV9wdW1wa2luIl0sImJhbl93ZWFwb25zIjpbXSwid2FudGVkX3RhZ3MiOltdLCJncmFwaCI6bnVsbCwic3RhcnQiOnt9LCJwcmljZSI6LTEsInRpZXIiOi0xLCJtYXhfbmIiOi0yLCJ0YWdzIjpudWxsLCJ3c3RhdHMiOnt9LCJzY2FsaW5nIjpudWxsLCJudW0iOjJ9fQ=="
	var id3 = m.import_code(old, CH)
	_check(id3 != "" and m.profiles[id3].weapons.size() == 19 and m.profiles[id3].stats.get("bounce_damage") == 100, "old uncompressed code imports")
	_eq(m.profiles[id3].wanted_tags, [], "explicit empty list kept")
	_eq(m.compact({"wanted_tags": [], "tags": null, "price": -1}, m.new_profile()), {"wanted_tags": []}, "[] differs from null")
	var g = {"nodes": [{"id": 1, "kind": "kill", "params": {}, "pos": [0, 0]}], "links": [], "next": 2}
	var gc = m.export_graph(g)
	_check(gc.begins_with(m.GRAPH_PREFIX + m.PACK) and m.import_graph(gc).nodes.size() == 1, "blueprint code compressed and round-trips")


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


# 新节点：目标敌人条件、伤害类型、非临时属性表的属性、持续 N 秒获得效果、文本
func test_75_graph_more_nodes() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var hit = GE.add_node(g, "enemy_hit", Vector2.ZERO)
	var above = GE.add_node(g, "enemy_hp_above", Vector2.ZERO, {"pct": 50})
	var below = GE.add_node(g, "enemy_hp_below", Vector2.ZERO, {"pct": 50})
	var melee = GE.add_node(g, "dmg_type", Vector2.ZERO, {"stat": "stat_melee_damage"})
	GE.add_link(g, hit, above)
	GE.add_link(g, above, GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 1}))
	GE.add_link(g, hit, below)
	GE.add_link(g, below, GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 10}))
	GE.add_link(g, hit, melee)
	GE.add_link(g, melee, GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 100}))
	GE.add_link(g, hit, GE.add_node(g, "vuln", Vector2.ZERO, {"pct": 20, "secs": 3}))
	# 不在原版临时属性表里的属性（箱子几率）：本波 / 永久都直接改效果表
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), GE.add_node(g, "temp_stat", Vector2.ZERO, {"stat": "crate_chance", "value": 5}))
	GE.add_link(g, GE.add_node(g, "level_up", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "crate_chance", "value": 3}))
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), GE.add_node(g, "grant", Vector2.ZERO, {"ref": {"set": {"key": "stat_armor", "value": 2}}, "n": 1, "mode": "timed", "secs": 60}))
	_graph_char(g)
	var gold0 = rd.players_data[0].gold
	m.runtime.fire("enemy_hit", 0, null, null, {"hp_pct": 80.0, "stats": ["stat_ranged_damage"]})
	_eq(rd.players_data[0].gold - gold0, 1, "enemy HP above passes, below / melee blocked")
	gold0 = rd.players_data[0].gold
	m.runtime.fire("enemy_hit", 0, null, null, {"hp_pct": 30.0, "stats": ["stat_melee_damage"]})
	_eq(rd.players_data[0].gold - gold0, 110, "enemy HP below + melee damage type pass")
	var hc = Keys.generate_hash("crate_chance")
	var c0 = rd.get_player_effect(hc, 0)
	m.runtime.fire("wave_start", 0)
	m.runtime.fire("level_up", 0)
	_eq(rd.get_player_effect(hc, 0), c0 + 8, "non-temp stat: wave + permanent")
	var a0 = _armor()
	m.runtime.fire("kill", 0)
	_eq(_armor(), a0 + 2, "timed grant applied")
	m.runtime.end_wave()
	_eq(rd.get_player_effect(hc, 0), c0 + 3, "wave stat reverted at wave end, permanent kept")
	_eq(_armor(), a0, "timed grant reverted at wave end")
	var text = GE.graph_text(g, false)
	_check(text.find("60") >= 0 and text.find("20%") >= 0, "timed grant / vuln text: " + text)
	_check(not "no_melee_weapons" in m.Catalog.graph_stat_keys() and "enemy_damage" in m.Catalog.graph_stat_keys(), "blueprint stats exclude rules")


# 条件"仅一次"：每获得一次持有者只通过一次（同原版"下一波"）；令牌随存档保存；拆解原版"下一波"效果
func test_76_graph_once() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var once = GE.add_node(g, "once", Vector2.ZERO)
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), once)
	GE.add_link(g, once, GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 2}))
	_graph_char(g)
	var h = Keys.generate_hash(GE.ONCE_KEY)
	_eq(rd.get_player_effects(0).get(h, []).size(), 1, "one token when the character is added")
	# 存档往返：令牌保留
	var pd = rd.players_data[0]
	var saved = JSON.parse(JSON.print(pd._serialize_effects(pd.effects))).result
	var loaded = Utils.convert_dictionary_to_hash(pd._deserialize_effects(saved, {}), true)
	_eq(loaded.get(h, []).size(), 1, "token survives save / load")
	_check(int(loaded[h][0]) == int(pd.effects[h][0]), "same token after load")
	var a0 = _armor()
	m.runtime.fire("wave_start", 0)
	m.runtime.fire("wave_start", 0)
	_eq(_armor(), a0 + 2, "fires once")
	m.runtime.end_wave()
	m.runtime.start_wave(null)
	m.runtime.fire("wave_start", 0)
	_eq(_armor(), a0 + 2, "not again next wave")
	m.runtime.end_wave()
	_check(GE.graph_text(g, false).find(tr("BE_CX_ONCE").strip_edges()) >= 0, "once text")
	# 拆解原版"下一波"效果：波次开始 → 仅一次 → 本波属性
	var nw = m.trigger_template("stats_next_wave")
	if nw != null:
		var g2 = GE.new_graph()
		_check(GE.split_native(g2, m.make_effect({"from": nw.from, "i": nw.i}), Vector2.ZERO), "next-wave effect splits")
		var kinds = []
		for n in g2.nodes:
			kinds.push_back(n.kind)
		_eq(kinds, ["wave_start", "once", "temp_stat"], "split path")


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


# 属性页效果的好坏（颜色 / 诅咒方向）、文本 / 好坏 / 计算方式 / 实际修改属性可编辑
func test_77_effect_signs_and_fields() -> void:
	_eq(m.stat_effect("stat_armor", 3).effect_sign, 0, "armor +3 good")
	_eq(m.stat_effect("stat_armor", -3).effect_sign, 1, "armor -3 bad")
	_eq(m.stat_effect("items_price", -10).effect_sign, 0, "price -10 good")
	_eq(m.stat_effect("items_price", 10).effect_sign, 1, "price +10 bad")
	var dlc = load("res://dlcs/dlc_1/dlc_1_data.gd").new() if ResourceLoader.exists("res://dlcs/dlc_1/dlc_1_data.gd") else null
	if dlc != null:
		_eq(dlc._boost_effect_value_positively(m.stat_effect("items_price", -10), 0.5), -15, "cursed price cut grows")
		_eq(dlc._boost_effect_value_positively(m.stat_effect("stat_armor", -4), 1.0), -2, "cursed armor loss shrinks")
	var names = []
	for f in m.Catalog.editable_fields(m.stat_effect("stat_armor", 3)):
		names.push_back(f.name)
	_eq(names.slice(names.size() - 3, names.size() - 1), ["text_key", "effect_sign", "storage_method"], "advanced fields last")
	var hidden = m.make_effect({"set": {"key": "stat_armor", "value": 3, "text_key": "[EMPTY]"}})
	_eq(hidden.get_text(0, false), "", "[EMPTY] hides the text")
	var rep = m.make_effect({"set": {"key": "dodge_cap", "value": 1, "storage_method": 0}})
	_eq(rep.storage_method, 0, "storage method set")
	var gain = null
	for entry in m.library(true):
		if "stats_modified" in entry.effect and entry.effect.stats_modified.size() > 1:
			gain = entry
			break
	_check(gain != null, "multi-stat gain effect found")
	if gain != null:
		var e = m.make_effect({"from": gain.from, "i": gain.i, "set": {"stats_modified": ["stat_luck"]}})
		_eq(Array(e.stats_modified), ["stat_luck"], "stats_modified edited")
		var fn = []
		for f in m.Catalog.editable_fields(e):
			fn.push_back(f.name)
		_check("stats_modified" in fn, "stats_modified editable")


func test_78_graph_low_hp_and_difficulty() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "wave_start", Vector2.ZERO)
	var d = GE.add_node(g, "diff_min", Vector2.ZERO, {"n": 99})
	GE.add_link(g, t, d)
	GE.add_link(g, d, GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 1}))
	var d2 = GE.add_node(g, "diff_max", Vector2.ZERO, {"n": 99})
	GE.add_link(g, t, d2)
	GE.add_link(g, d2, GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_luck", "value": 1}))
	_graph_char(g)
	var a0 = _armor()
	var l0 = rd.get_player_effect(Keys.generate_hash("stat_luck"), 0)
	m.runtime.fire("wave_start", 0)
	_eq(_armor(), a0, "danger 99+ blocks")
	_eq(rd.get_player_effect(Keys.generate_hash("stat_luck"), 0), l0 + 1, "danger <= 99 passes")
	m.runtime.end_wave()
	TranslationServer.set_locale("zh")
	_eq(_path_line([["low_hp", {"pct": 30}], ["temp_stat", {"stat": "stat_armor", "value": 2}]]).find("30%") >= 0, true, "low hp threshold in text")
	_check(_path_line([["wave_start", {}], ["diff_min", {"n": 3}], ["xp", {"value": 1}]]).find("危险等级不低于3") >= 0, "danger text")
	TranslationServer.set_locale("en")


# 状态扳机"始终"：路径上的状态条件持续检查，满足时进入、不满足时撤销
func test_79_always_state_paths() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "always", Vector2.ZERO)
	var c = GE.add_node(g, "stat_min", Vector2.ZERO, {"stat": "stat_armor", "n": 500})
	GE.add_link(g, t, c)
	GE.add_link(g, c, GE.add_node(g, "temp_stat", Vector2.ZERO, {"stat": "stat_luck", "value": 5}))
	GE.add_link(g, t, GE.add_node(g, "temp_stat", Vector2.ZERO, {"stat": "stat_speed", "value": 3}))
	_graph_char(g)
	var en = m.runtime.entries[0][0]
	var trig = en.by_id[t]
	var luck = Keys.generate_hash("stat_luck")
	var speed = Keys.generate_hash("stat_speed")
	var l0 = TempStats.get_stat(luck, 0)
	var s0 = TempStats.get_stat(speed, 0)
	m.runtime.poll_state(en, trig, 0, null)
	m.runtime.poll_state(en, trig, 0, null)
	_eq(TempStats.get_stat(speed, 0), s0 + 3, "always: unconditional path once")
	_eq(TempStats.get_stat(luck, 0), l0, "armor too low: not entered")
	RunData.add_stat(Keys.stat_armor_hash, 1000, 0)
	Utils.reset_stat_cache(0)
	m.runtime.poll_state(en, trig, 0, null)
	_eq(TempStats.get_stat(luck, 0), l0 + 5, "armor reached: entered")
	RunData.add_stat(Keys.stat_armor_hash, -1000, 0)
	Utils.reset_stat_cache(0)
	m.runtime.poll_state(en, trig, 0, null)
	_eq(TempStats.get_stat(luck, 0), l0, "armor lost: reverted")
	m.runtime.end_wave()
	_eq(TempStats.get_stat(speed, 0), s0, "wave end reverts")
	TranslationServer.set_locale("zh")
	var at = _path_line([["always", {}], ["stat_min", {"stat": "stat_armor", "n": 10}], ["temp_stat", {"stat": "stat_luck", "value": 5}]])
	_check(at.find("+5") >= 0 and not at.begins_with(",") and not at.begins_with("，"), "always has no trigger text: " + at)
	TranslationServer.set_locale("en")


# 道具变为：敌袭中触发，敌袭结束时替换；移除后变成（replaced_by）；金鱼效果复制到别的道具上指向该道具
func test_80_item_transform() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), GE.add_node(g, "transform", Vector2.ZERO, {"items": ["item_coupon"]}))
	_graph_char(GE.new_graph())
	var p = m.new_profile()
	p.graph = g
	m.item_profiles["item_alien_eyes"] = p
	m.apply_all()
	var it = m.find_target("item", "item_alien_eyes")
	rd.add_item(it, 0)
	m.runtime.start_wave(null)
	m.runtime.fire("kill", 0)
	m.runtime.fire("kill", 0)
	_check(it in rd.get_player_items_ref(0), "kept during the wave")
	m.runtime.end_wave()
	var ids = []
	for x in rd.get_player_items_ref(0):
		ids.push_back(x.my_id)
	_check(not "item_alien_eyes" in ids and ids.count("item_coupon") == 1, "replaced once at wave end: " + str(ids))
	_check(GE.graph_text(g, false).find(tr(m.find_target("item", "item_coupon").name)) >= 0, "transform text")
	m.item_profiles.erase("item_alien_eyes")
	m.apply_all()
	# 列表为空：移除并换成"移除后变成"；指定了道具：不再额外加入"移除后变成"
	var p3 = m.new_profile()
	p3.graph = GE.new_graph()
	GE.add_link(p3.graph, GE.add_node(p3.graph, "kill", Vector2.ZERO), GE.add_node(p3.graph, "transform", Vector2.ZERO))
	p3.replaced_by = "item_bandana"
	m.item_profiles["item_alien_eyes"] = p3
	m.apply_all()
	rd.add_item(it, 0)
	m.runtime.start_wave(null)
	m.runtime.fire("kill", 0)
	m.runtime.end_wave()
	ids = []
	for x in rd.get_player_items_ref(0):
		ids.push_back(x.my_id)
	_check(not "item_alien_eyes" in ids and "item_bandana" in ids, "empty list uses replaced_by: " + str(ids))
	_check(GE.graph_text(p3.graph, false) == tr("BE_PX_TRANSFORM_REPLACED") or GE.graph_text(p3.graph, false).find(tr("BE_PX_TRANSFORM_REPLACED")) >= 0, "replaced text")
	m.item_profiles.erase("item_alien_eyes")
	# 移除后变成
	var p2 = m.new_profile()
	p2.replaced_by = "item_coupon"
	m.item_profiles["item_alien_eyes"] = p2
	m.apply_all()
	_eq(it.replaced_by, m.find_target("item", "item_coupon"), "replaced_by applied")
	m.item_profiles.erase("item_alien_eyes")
	m.apply_all()
	_eq(it.replaced_by, null, "replaced_by restored")
	var fish = m.find_target("item", "item_goldfish")
	if fish != null:
		var cid = m.create_custom_item("item_goldfish")
		var ci = m.find_target("item", cid)
		m.apply_all()
		_eq(ci.replaced_by, fish.replaced_by, "custom copy keeps replaced_by")
		var keyed = false
		for e in ci.effects:
			keyed = keyed or (e.custom_key == "increase_tier_on_reroll" and e.key == cid)
		_check(keyed, "copied goldfish effect points at the copy")
		m.delete_custom_item(cid)


func test_110_path_text() -> void:
	TranslationServer.set_locale("zh")
	_eq(_path_line([["level_up", {}], ["perm_stat", {"stat": "stat_melee_damage", "value": 2}]]), "升级时，+2近战伤害", "zh level up")
	_eq(_path_line([["kill", {}], ["chance", {"pct": 20}], ["add_gold", {"value": 3}]]), "杀死敌人时，有20%几率获得3个材料", "zh chance")
	_eq(_path_line([["kill", {}], ["every", {"n": 5}], ["cap", {"n": 3}], ["temp_stat", {"stat": "stat_armor", "value": 1}]]), "每杀死5个敌人，+1护甲，直至敌袭结束（每波最多3次）", "zh every + cap")
	_eq(_path_line([["still", {}], ["temp_stat", {"stat": "stat_percent_damage", "value": 10}]]), "站立不动时，+10%伤害", "zh state")
	_eq(_path_line([["level_up", {}], ["every", {"n": 2}], ["hp_below", {"pct": 50}], ["heal_hp", {"value": 5}]]), "升级时，生命值低于50%，恢复5点生命值（每2次）", "zh conds inline")
	_eq(_path_line([["hit", {}], ["timed_stat", {"stat": "stat_dodge", "value": 20, "secs": 3}]]), "受到伤害时，+20%闪避，持续3秒", "zh timed")
	TranslationServer.set_locale("en")
	_eq(_path_line([["kill", {}], ["chance", {"pct": 20}], ["add_gold", {"value": 3}]]), "+3 materials when you kill an enemy (20% chance)", "en chance")
	_eq(_path_line([["interval", {"secs": 5}], ["xp", {"value": 2}]]), "+2 XP every 5 seconds", "en interval")
	_eq(_path_line([["enemy_hit", {}], ["hp_below", {"pct": 50}], ["enemy_hp_below", {"pct": 30}], ["chance", {"pct": 10}], ["xp", {"value": 2}]]), "+2 XP when you hit an enemy, if you are below 50% HP and the enemy is below 30% HP (10% chance)", "en conds inline")
	TranslationServer.set_locale("zh")
	_eq(_path_line([["enemy_hit", {}], ["hp_below", {"pct": 50}], ["enemy_hp_below", {"pct": 30}], ["chance", {"pct": 10}], ["xp", {"value": 2}]]), "命中敌人时，生命值低于50%且该敌人生命值低于30%，有10%几率获得2经验", "zh conds joined")
	TranslationServer.set_locale("en")


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
	_eq(m.stat_name("torture"), "每秒固定回复（无法其他治疗）", "torture label")
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
	m.profiles[CH].stats = {"stat_armor": 1}
	var single = m.export_code(it.my_id, "item")
	_check(single.begins_with(m.SHARE_PREFIX), "single prefix")
	_eq(m.import_code(single, CH, "character"), "", "item code rejected for characters")
	var kind_code = m.export_bundle("item")
	_check(kind_code.begins_with(m.BUNDLE_PREFIX.item), "item bundle prefix")
	_eq(m.export_bundle("weapon"), "", "empty bundle exports nothing")
	var all_code = m.export_bundle("")
	_check(all_code.begins_with(m.ALL_PREFIX), "all prefix")
	_check(kind_code.begins_with(m.BUNDLE_PREFIX.item + m.PACK) and all_code.begins_with(m.ALL_PREFIX + m.PACK), "bundles compressed")
	_eq(m.unpack(kind_code.substr(m.BUNDLE_PREFIX.item.length())).items[it.my_id], {"price": 3}, "bundle keeps only edited fields")
	_eq(m.import_bundle(m.BUNDLE_PREFIX.item + Marshalls.utf8_to_base64(JSON.print({"items": {it.my_id: {"price": 5}}}))), 1, "old uncompressed bundle imports")
	_eq(m.item_profiles[it.my_id].price, 5, "old bundle content")
	m.item_profiles[it.my_id].price = 3
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
	var dlc = _dlc("abyssal_terrors")
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
	var dlc = _dlc("abyssal_terrors")
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
	var st = GE.add_node(g, "steps", Vector2.ZERO, {"n": 80})
	ids["steps"] = st
	ids["steps:perm_stat"] = GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_max_hp", "value": 1})
	GE.add_link(g, st, ids["steps:perm_stat"])
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
		["steps", "n", _bad(80), "every X steps -> +hp: X shrinks (as the hiker's value2)"],
		["steps:perm_stat", "value", 1, "  and the hp is unchanged"],
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


# 没有 DLC（未拥有或停用）时：诅咒相关的代码不报错、不改变数值；诅咒的初始装备改为普通的
func test_192_without_dlc() -> void:
	var saved = _drop_dlc("abyssal_terrors")
	_check(_dlc("abyssal_terrors") == null and not m.set_active("abyssal_terrors"), "DLC unavailable")
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var ev = GE.add_node(g, "every", Vector2.ZERO, {"n": 6})
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), ev)
	var gold = GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 2})
	GE.add_link(g, ev, gold)
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 3}))
	_eq(JSON.print(m.curse_graph(g, 0.5)), JSON.print(g), "curse_graph without DLC leaves the graph unchanged")
	# 带诅咒的蓝图（例如有 DLC 时存的档，之后停用 DLC 再读档）：按原数值运行，不报错
	var ge = GE.make(g)
	ge.value = 1500
	_eq(JSON.print(ge.live_graph()), JSON.print(g), "cursed blueprint without DLC uses its own values")
	_check(ge.get_text(0, false) != "", "text still renders")
	var iid = m.create_custom_item(_plain_item().my_id, "nodlc")
	m.item_profiles[iid].effects = []
	m.item_profiles[iid].graph = g
	m.apply_all()
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_item(m.find_target("item", iid), 0)
	var h = Keys.generate_hash("stat_armor")
	var a0 = rd.get_player_effect(h, 0)
	m.graph_dirty = true
	m.runtime.start_wave(null)
	m.runtime.fire("wave_start", 0)
	_eq(rd.get_player_effect(h, 0), a0 + 3, "blueprint fires with its own values")
	var g0 = rd.players_data[0].gold
	for i in 6:
		m.runtime.fire("kill", 0)
	_eq(rd.players_data[0].gold - g0, 2, "every 6 kills unchanged")
	m.runtime.end_wave()
	# 诅咒的初始道具：没有 DLC 时作为普通初始道具
	var e = m.start_item_effect({"id": _plain_item().my_id, "n": 1, "cursed": true})
	_eq(e.custom_key, "starting_item", "cursed starting item falls back to a normal one")
	# 编辑器各页
	var p = m.new_profile()
	p.start_items = [{"id": _plain_item().my_id, "n": 1, "cursed": true}]
	p.graph = g
	m.profiles[CH] = p
	var ui = yield(_open_ui(CH), "completed")
	for t in ui._tab_defs():
		ui._on_tab_pressed(t[0])
		yield(tree, "idle_frame")
		_check(ui._page.get_child_count() > 0, "tab " + t[0] + " without DLC")
	ui._on_tab_pressed("gear")
	var has_cursed_box = false
	for n in _all_nodes(ui._page):
		if n is CheckBox and n.text == tr("BE_CURSED"):
			has_cursed_box = true
	_check(not has_cursed_box, "no cursed checkbox without DLC")
	ui.queue_free()
	yield(tree, "idle_frame")
	m.delete_custom_item(iid)
	_restore_dlcs(saved)
	_check(_dlc("abyssal_terrors") != null, "DLC restored")


func _all_nodes(n: Node) -> Array:
	var out = []
	for c in n.get_children():
		out.push_back(c)
		out += _all_nodes(c)
	return out


# 反馈 2：效果库合并属性联动、收录未启用 DLC 的角色；自定义道具名称用于"初始拥有"文本
func test_200_library_dlc_and_names() -> void:
	var dedup0 = m.library_dedup
	m.set_library_dedup(true)
	var seen = {}
	var dup = false
	for entry in m.library():
		if entry.cat != "scaling":
			continue
		var e = entry.effect
		var tk = str(e.text_key).to_lower()
		var k = e.get_script().resource_path + "|" + (tk if tk != "" else "#" + e.key)
		dup = dup or seen.has(k)
		seen[k] = true
	_check(not dup, "scaling effects merged by text_key")
	if _dlc("abyssal_terrors") != null:
		var saved = _drop_dlc("abyssal_terrors")
		m.set_library_dedup(m.library_dedup)
		var from_dlc = false
		for entry in m.library():
			from_dlc = from_dlc or entry.from == "character_romantic"
		_check(from_dlc, "inactive DLC characters in the library")
		var t = null
		for entry in m.library():
			if entry.from == "character_romantic":
				t = entry
				break
		_check(t != null and m.make_effect({"from": t.from, "i": t.i}) != null, "inactive DLC effect usable as template")
		_restore_dlcs(saved)
	m.set_library_dedup(dedup0)
	var iid = m.create_custom_item(_plain_item().my_id, "knife")
	m.item_profiles[iid].name = "Blade X"
	m.apply_all()
	_eq(tr(iid.to_upper()), "Blade X", "custom item name registered for vanilla text")
	_check(m.effect_text(m.start_item_effect({"id": iid, "n": 1}), false).find("Blade X") >= 0, "starting item text shows the name")
	m.delete_custom_item(iid)


# 每走 N 步、徒步旅行者拆解、隐藏蓝图描述
func test_201_steps_and_hidden_text() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "steps", Vector2.ZERO, {"n": 3}), GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 1}))
	_graph_char(g)
	var g0 = rd.players_data[0].gold
	for i in 7:
		m.runtime.fire("steps", 0)
	_eq(rd.players_data[0].gold - g0, 2, "every 3 steps")
	m.runtime.end_wave()
	_check(GE.graph_text(g, false).find("3") >= 0, "steps text shows N")
	var ge = GE.make(g)
	_check(ge.get_text(0, false) != "", "text shown by default")
	g.hide_text = true
	ge = GE.make(g)
	_eq(ge.get_text(0, false), "", "hidden text")
	var hiker = null
	for e in m.orig_effects("character_hiker"):
		if e.custom_key == "gain_stat_for_every_step_after_equip":
			hiker = e
	if hiker != null:
		var g2 = GE.new_graph()
		_check(GE.split_native(g2, hiker, Vector2.ZERO), "hiker effect splits")
		_eq(int(g2.nodes[0].params.n), int(hiker.value2), "steps count from value2")


# 获得 / 失去道具（敌袭结束时执行）、本局商店加入 / 移出（随存档保存）
func test_202_item_and_shop_effects() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var k = GE.add_node(g, "kill", Vector2.ZERO)
	GE.add_link(g, k, GE.add_node(g, "gain_item", Vector2.ZERO, {"items": ["item_coupon"]}))
	GE.add_link(g, GE.add_node(g, "level_up", Vector2.ZERO), GE.add_node(g, "lose_item", Vector2.ZERO, {"items": ["item_coupon"]}))
	var sa = GE.add_node(g, "shop_add", Vector2.ZERO, {"items": ["item_coupon"]})
	GE.add_link(g, GE.add_node(g, "crate", Vector2.ZERO), sa)
	GE.add_link(g, GE.add_node(g, "heal", Vector2.ZERO), GE.add_node(g, "shop_remove", Vector2.ZERO, {"items": ["item_coupon"]}))
	_graph_char(g)
	var coupon = m.find_target("item", "item_coupon")
	m.runtime.fire("kill", 0)
	_check(not coupon in rd.get_player_items_ref(0), "gain waits for wave end")
	m.runtime.end_wave()
	_check(coupon in rd.get_player_items_ref(0), "gained at wave end")
	m.runtime.start_wave(null)
	m.runtime.fire("level_up", 0)
	m.runtime.end_wave()
	_check(not coupon in rd.get_player_items_ref(0), "lost at wave end")
	TranslationServer.set_locale("zh")
	_check(GE.graph_text(g, false).find(tr("BE_CX_AT_WAVE_END")) >= 0, "wave end note in text")
	TranslationServer.set_locale("en")
	m.set_disabled("item", "item_coupon", true)
	var h = Keys.generate_hash("item_coupon")
	_check(h in m.ban_hashes(0), "disabled")
	m.runtime.start_wave(null)
	m.runtime.fire("crate", 0)
	_check(not h in m.ban_hashes(0), "shop_add lifts the disable for this run")
	var state = rd.get_state()
	_eq(state.broeditor_shop[0].add, ["item_coupon"], "saved with the run")
	m.runtime.fire("heal", 0)
	_check(h in m.ban_hashes(0), "shop_remove bans again")
	m.load_run_shop(state.broeditor_shop)
	_check(not h in m.ban_hashes(0), "restored from the run state")
	m.runtime.end_wave()
	rd.reset()
	_eq(m.run_shop[0].add.size() + m.run_shop[0].remove.size(), 0, "new run clears the changes")
	m.set_disabled("item", "item_coupon", false)
	_check(not m.enemy_list().empty(), "enemy list")
	_check(m.enemy_scene("baby_alien") != null, "enemy scene")


# 融合角色：被融合角色的效果接在后面（不含它的融合与介绍）；取消后还原
func test_203_fusion() -> void:
	var other = isvc.characters[1]
	var n0 = m.find_character(CH).effects.size()
	var own = other.effects.size()
	var p = m.new_profile()
	p.fuse = [other.my_id]
	m.profiles[CH] = p
	var po = m.new_profile()
	po.desc = "hello"
	po.fuse = [CH]
	m.profiles[other.my_id] = po
	m.apply_all()
	var c = m.find_character(CH)
	_eq(c.effects.size(), n0 + own, "fused effects appended (without the other's description and fusion)")
	_eq(m.find_character(other.my_id).effects.size(), own + 1 + n0, "two-way fusion uses each side's own effects")
	_eq(m.normalize_profile({"fuse": ["a", "a", 3]}).fuse, ["a", "3"], "normalized")
	m.profiles.erase(CH)
	m.profiles.erase(other.my_id)
	m.apply_all()
	_eq(m.find_character(CH).effects.size(), n0, "restored")
	var cid = m.create_custom(CH)
	m.apply_all()
	var cn = m.find_character(cid).effects.size()
	m.profiles[cid].fuse = [other.my_id]
	m.apply_all()
	_eq(m.find_character(cid).effects.size(), cn + own, "custom character fusion")
	var ui = yield(_open_ui(cid), "completed")
	ui._on_tab_pressed("gear")
	yield(tree, "idle_frame")
	var found = false
	for nd in _all_nodes(ui._page):
		found = found or (nd is Label and nd.text == tr(other.name))
	_check(found, "fused character listed on the gear tab")
	ui._open_picker("fuse")
	_eq(ui._picker.sel, [other.my_id], "picker preselects")
	ui._picker.sel = []
	ui._picker.confirm()
	_eq(m.profiles[cid].fuse, [], "picker clears")
	ui.queue_free()
	yield(tree, "idle_frame")


# 浪漫之人 / 长笛的魅惑可拆解；按属性缩放的几率；武器上的命中扳机只响应这把武器
func test_204_charm_split_and_weapon_hits() -> void:
	var GE = load(GraphEffectScript)
	var Catalog = load(MOD_DIR + "catalog.gd")
	var rom = null
	for e in m.orig_effects("character_romantic"):
		if e.custom_key == "charm_on_hit":
			rom = e
	if rom != null:
		_check(Catalog.can_split(rom), "romantic charm splittable")
		var g = GE.new_graph()
		GE.split_native(g, rom, Vector2.ZERO)
		var kinds = []
		for n in g.nodes:
			kinds.push_back(n.kind)
		_eq(kinds, ["enemy_hit", "enemy_hp_below", "stat_chance", "charm"], "split nodes")
		_eq(int(g.nodes[1].params.pct), int(rom.value2), "hp threshold")
		_eq([g.nodes[2].params.stat, int(g.nodes[2].params.pct)], [rom.key, int(rom.value)], "scaled chance")
		TranslationServer.set_locale("zh")
		var t = GE.graph_text(g, false)
		_check(t.find("8") >= 0 and t.find("魅惑") >= 0, "charm text: " + t)
		TranslationServer.set_locale("en")
	var fl = m.find_target("weapon", "weapon_flute_1")
	if fl != null:
		_check(Catalog.can_split(fl.effects[0]), "flute charm splittable")
	var hiker = null
	for e in m.orig_effects("character_hiker"):
		if e.custom_key == "gain_stat_for_every_step_after_equip":
			hiker = e
	if hiker != null:
		_check(Catalog.can_split(hiker), "hiker splittable in the effect list")
	var g2 = GE.new_graph()
	var sc = GE.add_node(g2, "stat_chance", Vector2.ZERO, {"stat": "stat_max_hp", "pct": 1000})
	GE.add_link(g2, GE.add_node(g2, "enemy_hit", Vector2.ZERO), sc)
	GE.add_link(g2, sc, GE.add_node(g2, "add_gold", Vector2.ZERO, {"value": 1}))
	var wid = m.create_custom_weapon(_family_from(0, 0)[0].weapon_id)
	m.weapon_profiles[wid].graph = g2
	m.apply_all()
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_weapon(_family_from(0, 0)[0], 0)
	rd.add_weapon(m.find_target("weapon", wid), 0)
	m.graph_dirty = true
	m.runtime.start_wave(null)
	var g0 = rd.players_data[0].gold
	m.runtime.fire("enemy_hit", 0, null, null, {"weapon_pos": 0})
	_eq(rd.players_data[0].gold, g0, "another weapon's hit ignored")
	m.runtime.fire("enemy_hit", 0, null, null, {"weapon_pos": 1})
	_eq(rd.players_data[0].gold, g0 + 1, "own hit fires (max hp x 1000% chance)")
	m.runtime.fire("enemy_hit", 0, null, null, {})
	_eq(rd.players_data[0].gold, g0 + 2, "hits without a weapon fire")
	m.runtime.end_wave()
	m.delete_custom_weapon(m.find_target("weapon", wid).weapon_id)


# 更多可拆解的原版效果；拆解后数值一致
func test_205_more_splits() -> void:
	var GE = load(GraphEffectScript)
	var Catalog = load(MOD_DIR + "catalog.gd")
	var cases = [
		["item_hunting_trophy", "gold_on_crit_kill", ["crit_kill", "chance", "add_gold"]],
		["item_adrenaline", "heal_on_dodge", ["dodge", "chance", "heal_hp"]],
		["item_riposte", "dmg_on_dodge", ["dodge", "damage"]],
		["character_lich", "dmg_when_heal", ["heal", "damage"]],
		["item_cyberball", "dmg_when_death", ["kill", "chance", "damage"]],
		["item_baby_elephant", "dmg_when_pickup_gold", ["gold", "chance", "damage"]],
		["item_medikit", "temp_stats_per_interval", ["interval", "temp_stat"]],
	]
	for c in cases:
		var e = null
		for x in m.orig_effects(c[0]):
			if x.custom_key == c[1]:
				e = x
		if e == null:
			continue
		_check(Catalog.can_split(e), c[0] + " splittable")
		var g = GE.new_graph()
		GE.split_native(g, e, Vector2.ZERO)
		var kinds = []
		for n in g.nodes:
			kinds.push_back(n.kind)
		_eq(kinds, c[2], c[0] + " nodes")
		_eq(g.links.size(), c[2].size() - 1, c[0] + " linked")
		if c[2][-1] == "damage":
			_eq([g.nodes[-1].params.stat, int(g.nodes[-1].params.pct)], [e.key, int(e.value)], c[0] + " damage")
	# 隐藏描述：编辑器预览也不显示
	var g2 = GE.new_graph()
	GE.add_link(g2, GE.add_node(g2, "wave_start", Vector2.ZERO), GE.add_node(g2, "add_gold", Vector2.ZERO, {"value": 1}))
	g2.hide_text = true
	var p = m.new_profile()
	p.graph = g2
	m.profiles[CH] = p
	var ui = yield(_open_ui(CH), "completed")
	var holder = VBoxContainer.new()
	ui.add_child(holder)
	ui._effect_lines([GE.make(g2)], holder)
	_eq(holder.get_child_count(), 0, "hidden blueprint not in the preview")
	ui._on_tab_pressed("blueprint")
	yield(tree, "idle_frame")
	_check(ui.blueprint._hide_desc.visible, "hint shown while checked")
	ui.blueprint._on_hide_text(false)
	_check(not ui.blueprint._hide_desc.visible, "hint hidden when unchecked")
	ui.queue_free()
	yield(tree, "idle_frame")





# 效果库在 DLC 加入前就被建好（本 mod 早于 ProgressData 就绪）时，apply_all 要重建；纯属性效果同名只留一个
func test_175_library_dlc_and_stat_dedup() -> void:
	var Catalog = load(MOD_DIR + "catalog.gd")
	m._library = []
	m._weapon_library = []
	m.apply_all()
	var froms = {}
	var stat_keys = {}
	var dup = false
	for e in m.library(false):
		froms[e.from] = true
		var ef = e.effect
		if Catalog.is_plain_effect(ef) and ef.custom_key == "" and str(ef.key).begins_with("stat_"):
			dup = dup or stat_keys.has(ef.key)
			stat_keys[ef.key] = true
	_check(froms.has("character_dwarf") and froms.has("character_romantic"), "dlc characters rebuilt into the library")
	_check(stat_keys.has("stat_max_hp") and not dup, "plain stat effects deduped by key")
	if not m._dlcs().empty():
		var dlc = m._dlcs()[0]
		dlc.remove_resources()
		m._weapon_library = null
		var wf = {}
		for e in m.library(true):
			wf[e.from] = true
		var dlc_w = null
		for w in dlc.weapons:
			if not w.effects.empty():
				dlc_w = w.my_id
				break
		_check(dlc_w == null or wf.has(dlc_w), "inactive dlc weapons in the weapon library")
		dlc.add_resources()
		m.apply_all()


# BroEditor+ 移植：拥有标签道具 / 类别武器条件、商店必定出现、内容分组锁定 / 解锁
func test_176_own_conds_shop_force_groups() -> void:
	var GE = load(MOD_DIR + "graph/graph_effect.gd")
	var isvc = tree.root.get_node("ItemService")
	var rd = tree.root.get_node("RunData")
	var ctx = {"pos": null, "target": null, "hold": null, "info": {}}
	var tagged = null
	for it in isvc.items:
		if not it.tags.empty():
			tagged = it
			break
	var tag = tagged.tags[0]
	var c0 = 0
	for it in rd.get_player_items(0):
		if tag in it.tags:
			c0 += 1
	rd.add_item(tagged, 0)
	var n = {"id": 1, "kind": "own_tag", "params": {"tag": tag, "cmp": "exactly", "n": c0 + 1}}
	_check(m.runtime._pass({"st": {}}, n, 0, ctx), "own_tag exactly")
	n.params.cmp = "at_most"
	n.params.n = c0
	_check(not m.runtime._pass({"st": {}}, n, 0, ctx), "own_tag at most")
	_check(GE._cond_text(n).find(m.tag_name(tag)) >= 0, "own_tag text names the tag")
	rd.remove_item(tagged, 0)
	var knife = isvc.get_element_safe(isvc.weapons, "weapon_knife_1")
	var w0 = 0
	for w in rd.get_player_weapons(0):
		for st in w.sets:
			if st.my_id == "set_precise":
				w0 += 1
	rd.add_weapon(knife, 0)
	rd.add_weapon(knife, 0)
	var ns = {"id": 2, "kind": "own_set", "params": {"set": "set_precise", "cmp": "at_least", "n": w0 + 2}}
	_check(m.runtime._pass({"st": {}}, ns, 0, ctx), "own_set at least")
	ns.params.cmp = "exactly"
	ns.params.n = w0 + 3
	_check(not m.runtime._pass({"st": {}}, ns, 0, ctx), "own_set exactly")
	var no = {"id": 4, "kind": "own_item", "params": {"id": knife.weapon_id, "cmp": "at_least", "n": 2}}
	_check(m.runtime._pass({"st": {}}, no, 0, ctx), "own_item counts the weapon family")
	no.params.cmp = "exactly"
	no.params.n = 3
	_check(not m.runtime._pass({"st": {}}, no, 0, ctx), "own_item exactly")
	_check(GE._cond_text(no).find(tr(knife.name)) >= 0, "own_item text names the weapon")
	for w in rd.get_player_weapons(0).duplicate():
		if w.my_id == "weapon_knife_1":
			rd.remove_weapon(w, 0)
	# 商店必定出现：从最后一格往前替换
	m.queue_shop_force(0, ["weapon_knife_1", "item_coupon"])
	var shop = [[null, 1], [null, 1], [null, 1], [null, 1]]
	m.inject_shop_force(shop, 0, 1)
	_eq(shop[3][0].my_id, "weapon_knife_1", "forced weapon in the last slot")
	_eq(shop[2][0].my_id, "item_coupon", "forced item")
	_check(m.run_shop[0].force.empty(), "queue consumed")
	# 分组：锁定移出原版解锁记录与商店池，apply_all 后保持，蓝图效果解锁
	var gid = m.create_group("T")
	m.toggle_group_member(gid, "item", "item_coupon")
	m.toggle_group_member(gid, "weapon", knife.weapon_id)
	_check(m.is_unlocked("item", "item_coupon") and m.is_unlocked("weapon", knife.weapon_id), "unlocked before")
	m.set_group_locked(gid, true)
	_check(not m.is_unlocked("item", "item_coupon") and not m.is_unlocked("weapon", knife.weapon_id), "locked")
	var coupon = isvc.get_element_safe(isvc.items, "item_coupon")
	_check(not coupon in isvc.get_pool(coupon.tier, isvc.TierData.ITEMS), "locked item left the pool")
	m.apply_all()
	_check(not m.is_unlocked("item", "item_coupon"), "still locked after apply_all")
	m.runtime._execute({"st": {}}, {"id": 3, "kind": "group_unlock", "params": {"group": gid}}, 0, ctx)
	_check(m.is_unlocked("item", "item_coupon") and not m.groups[gid].locked, "blueprint unlocks the group")
	_check(coupon in isvc.get_pool(coupon.tier, isvc.TierData.ITEMS), "back in the pool")
	m.set_group_locked(gid, true)
	m.delete_group(gid)
	_check(m.is_unlocked("weapon", knife.weapon_id) and m.groups.empty(), "deleting a locked group unlocks it")



# 按属性几率的初始值
func test_177_stat_chance_base() -> void:
	var GE = load(MOD_DIR + "graph/graph_effect.gd")
	var ctx = {"pos": null, "target": null, "hold": null, "info": {}}
	var n = {"id": 1, "kind": "stat_chance", "params": {"base": 100, "stat": "stat_max_hp", "pct": 0}}
	_check(m.runtime._pass({"st": {}}, n, 0, ctx), "base 100 always passes")
	n.params.base = -1000
	_check(not m.runtime._pass({"st": {}}, n, 0, ctx), "negative base never passes")
	var g = GE.new_graph()
	var t = GE.add_node(g, "kill", Vector2.ZERO)
	var c = GE.add_node(g, "stat_chance", Vector2.ZERO, {"base": 10, "stat": "stat_max_hp", "pct": 50})
	GE.add_link(g, t, c)
	GE.add_link(g, c, GE.add_node(g, "heal_hp", Vector2.ZERO, {"value": 1}))
	_check(GE.graph_text(g, false).find("10%") >= 0, "text shows the base chance")


# 燃烧几率效果改了属性加成：全局燃烧按改后的属性加成（原版合并时丢掉加成）；伤害类型条件可选所有主要属性
func test_178_burn_chance_scaling_and_dmg_types() -> void:
	var i = 0
	while not m.template("item_scared_sausage", i) is BurnChanceEffect:
		i += 1
	var e = m.make_effect({"from": "item_scared_sausage", "i": i, "sub": {"burning_data": {"scaling_stats": [["stat_max_hp", 0.5]]}}})
	_check(e is BurnChanceEffect and e.burning_data.chance > 0, "edited burn chance keeps its fields")
	var g = RunData.get_player_effects(0)[Keys.burn_chance_hash]
	var old = JSON.print(g.scaling_stats)
	e.apply(0)
	_eq(JSON.print(g.scaling_stats), JSON.print([[Keys.stat_max_hp_hash, 0.5]]), "global burn scales with the edited stat")
	var vanilla = m.template("item_scared_sausage", i)
	vanilla.apply(0)
	var bd = WeaponService.init_burning_data(BurningData.new(), 0)
	_eq(bd.scaling_stats.size(), 2, "a vanilla burn source gained later keeps elemental scaling")
	vanilla.unapply(0)
	e.unapply(0)
	_eq(JSON.print(g.scaling_stats), old, "removing the effect restores the scaling")
	var Catalog = load(MOD_DIR + "catalog.gd")
	_check("stat_max_hp" in Catalog.graph_stat_keys() and "xp_gain" in Catalog.graph_stat_keys() and Catalog.node_def("dmg_type")[2][0][1] == "stat", "damage type lists every stat")
	var eyes = load("res://items/all/00_base_game/alien_eyes/alien_eyes_stats.tres")
	_check("stat_max_hp" in load(MOD_DIR + "graph/enemy_behavior.gd").stat_names(eyes.scaling_stats), "alien eyes hit counts as max HP damage")



# 武器种类数；"拥有指定道具 / 武器"可指定等级；随机主要属性可为负；减速 / 受伤加成为负时的文本
func test_179_weapon_kinds_tiers_negatives() -> void:
	var GE = load(MOD_DIR + "graph/graph_effect.gd")
	var isvc = tree.root.get_node("ItemService")
	var rd = tree.root.get_node("RunData")
	var ctx = {"pos": null, "target": null, "hold": null, "info": {}}
	var kinds = {}
	for w in rd.get_player_weapons(0):
		kinds[w.weapon_id] = true
	var knife1 = isvc.get_element_safe(isvc.weapons, "weapon_knife_1")
	var knife2 = isvc.get_element_safe(isvc.weapons, "weapon_knife_2")
	var added = [rd.add_weapon(knife1, 0), rd.add_weapon(knife2, 0)]
	var want = kinds.size() + (0 if kinds.has(knife1.weapon_id) else 1)
	var nk = {"id": 1, "kind": "weapon_kinds", "params": {"cmp": "exactly", "n": want}}
	_check(m.runtime._pass({"st": {}}, nk, 0, ctx), "weapon kinds: tiers of one weapon count once")
	_check(GE._cond_text(nk).find(str(want)) >= 0, "weapon kinds text")
	var no = {"id": 2, "kind": "own_item", "params": {"id": "weapon_knife_2", "cmp": "exactly", "n": 1}}
	_check(m.runtime._pass({"st": {}}, no, 0, ctx), "own_item counts a specific tier")
	_check(GE._cond_text(no).find("II") >= 0, "own_item text shows the tier")
	for w in added:
		rd.remove_weapon(w, 0)
	var before = 0
	for k in Catalog_primary():
		before += rd.get_stat(Keys.generate_hash(k), 0)
	m.runtime._execute({"st": {}, "g": {}}, {"id": 3, "kind": "rand_stats", "params": {"value": -2}}, 0, ctx)
	var after = 0
	for k in Catalog_primary():
		after += rd.get_stat(Keys.generate_hash(k), 0)
	_eq(int(before - after), 2, "negative random stats removes points")
	m.runtime._execute({"st": {}, "g": {}}, {"id": 4, "kind": "rand_stats", "params": {"value": 2}}, 0, ctx)
	_check(GE._payload_text({"kind": "slow", "params": {"pct": -10, "secs": 3}}, "enemy_hit", false) == tr("BE_PX_HASTE").replace("{0}", "10%").replace("{1}", "40%") + tr("BE_PX_FOR_SECS").replace("{0}", "3"), "haste text")
	_check(GE._payload_text({"kind": "vuln", "params": {"pct": -20, "secs": 3}}, "enemy_hit", false).find("20%") >= 0, "less damage text")


func Catalog_primary() -> Array:
	return load(MOD_DIR + "catalog.gd").STAT_GROUPS[0][1]


# 分享包的依赖：武器带上套装（自定义 + 改过的原版），角色 / 道具带上自定义标签；引用到的自定义对象与自定义图标一并打包
func test_135_bundle_dependencies() -> void:
	var dir = Directory.new()
	dir.make_dir_recursive(m.ICON_DIR)
	var png = Image.new()
	png.create(2, 2, false, Image.FORMAT_RGBA8)
	png.save_png(m.ICON_DIR + "be_dep_icon.png")
	var wt = m.create_custom_weapon("weapon_knife", "dep")
	var wid = m.weapon_family_of(wt)
	var vs = m.family_members("weapon_knife")[0].sets[0].my_id
	var cs = m.create_set(vs)
	m.weapon_sets[vs] = m.normalize_set({"bonuses": m.set_specs(vs).duplicate(true)})
	m.weapon_families[wid].sets = [vs, cs]
	m.custom_tags["be_dep_tag"] = "Dep Tag"
	var iid = m.create_custom_item(_plain_item().my_id, "dep")
	m.item_profiles[iid].tags = ["be_dep_tag"]
	m.item_profiles[iid].icon = "file:be_dep_icon.png"
	var p = m.new_profile()
	p.wanted_tags = ["be_dep_tag"]
	p.effects = [{"from": iid, "i": 0}]
	p.weapons = [wt]
	m.profiles[CH] = p
	var d = m.bundle_data([["character", CH]])
	_check(d.profiles.has(CH), "selected character packed")
	_check(d.get("items", {}).has(iid), "referenced custom item packed")
	_check(d.get("families", {}).has(wid) and d.get("weapons", {}).has(wt), "referenced custom weapon packed")
	_check(d.get("sets", {}).has(cs) and d.sets.has(vs), "weapon sets packed (custom + edited vanilla)")
	_eq(d.get("tags"), {"be_dep_tag": "Dep Tag"}, "custom tag packed")
	_check(d.get("icons", {}).has("be_dep_icon.png"), "custom icon packed")
	var dw = m.bundle_data([["weapon", wid]])
	_check(dw.get("sets", {}).has(cs) and not dw.has("profiles") and not dw.has("tags"), "weapon pack: its sets only")
	_check(m.export_bundle("character").begins_with(m.ALL_PREFIX), "cross-kind deps use the all prefix")
	_check(m.share_entries().has(["weapon", wid]) and m.share_entries(["item"]) == [["item", iid]], "share entries")
	var code = m.ALL_PREFIX + m.pack(d)
	_reset()
	m.weapon_sets = {}
	m.custom_tags = {}
	dir.remove(m.ICON_DIR + "be_dep_icon.png")
	m.disabled.item = ["item_keep"]
	_check(m.import_bundle(code) > 0, "pack imported")
	m.apply_all()
	_check(m.find_target("item", iid) != null and m.find_target("weapon", wt) != null, "custom item / weapon restored")
	_check(m.weapon_sets.has(cs) and m.weapon_sets.has(vs) and m.custom_tags.has("be_dep_tag"), "sets / tags restored")
	_check(dir.file_exists(m.ICON_DIR + "be_dep_icon.png"), "icon file restored")
	_eq(m.disabled.item, ["item_keep"], "pack without disabled lists keeps them")
	_check(m.import_bundle(m.ALL_PREFIX + m.pack({"icons": {"../be_evil.png": "AAAA"}})) >= 0 and not dir.file_exists("user://Mojimoon-BroEditor/be_evil.png"), "icon names with paths ignored")
	m.weapon_sets = {}
	m.custom_tags = {}
	dir.remove(m.ICON_DIR + "be_dep_icon.png")


# 数据包：单独存储、下载即启用、切换版本、编辑包版本成为自修改版、停用 / 卸载、保存读取；冲突的自定义套装改 id
func test_136_pack_versions() -> void:
	var it = _plain_item().my_id
	var vs = m.family_members("weapon_knife")[0].sets[0].my_id
	var p = m.new_profile()
	p.price = 3
	m.item_profiles[it] = p
	m.weapon_sets["set_custom_1"] = m.normalize_set({"custom": true, "base": vs, "name": "Mine"})
	m.save_profiles()
	_eq(m.own.items[it].price, 3, "own captured")
	var data = {
		"items": {it: {"price": 9}},
		"profiles": {"character_be_pack_1": {"custom": true, "base": CH, "name": "Pack Guy", "effects": [{"from": "set_custom_1#0", "i": 0}]}},
		"sets": {"set_custom_1": {"custom": true, "base": vs, "name": "Theirs"}},
	}
	_eq(m.install_pack({"id": "testpack01", "title": "T"}, m.ALL_PREFIX + m.pack(data)), 2, "pack installed")
	_eq(m.install_pack({"id": "../bad"}, m.ALL_PREFIX + m.pack(data)), -1, "bad pack id rejected")
	_eq(m.item_profiles[it].price, 9, "pack version active")
	_eq(m.own.items[it].price, 3, "own edits kept")
	_check(m.find_character("character_be_pack_1") != null, "pack custom character registered")
	_check(m.weapon_sets.has("set_custom_1_testpack01") and m.weapon_sets["set_custom_1"].name == "Mine", "clashing custom set rekeyed")
	_eq(m.profiles["character_be_pack_1"].effects[0].from, "set_custom_1_testpack01#0", "set refs renamed")
	_eq(m.unit_versions("item", it), ["vanilla", "self", "testpack01"], "versions")
	m.set_source("item", it, "self")
	_eq(m.item_profiles[it].price, 3, "switched to own")
	m.set_source("item", it, "vanilla")
	_check(not m.item_profiles.has(it), "switched to vanilla")
	_eq(m.own.items[it].price, 3, "own kept while vanilla")
	m.set_pack_enabled("testpack01", true)
	_eq(m.item_profiles[it].price, 9, "enable all")
	m.item_profiles[it].price = 12
	m.capture()
	_eq(m.own.items[it].price, 12, "edited pack version becomes own")
	_eq(m.unit_source("item", it), "self", "now uses own")
	_eq(m.packs.testpack01.data.items[it].price, 9, "pack data untouched")
	m.set_pack_enabled("testpack01", false)
	_check(m.find_character("character_be_pack_1") == null, "disable all unregisters pack custom")
	_check(not m.weapon_sets.has("set_custom_1_testpack01"), "pack set dropped with its users")
	_eq(m.item_profiles[it].price, 12, "own still active")
	m.set_pack_enabled("testpack01", true, "character", "character_be_pack_1")
	_check(not File.new().file_exists(m.CUSTOM_DIR + "character/character_be_pack_1.json"), "pack custom not saved as own")
	m.load_profiles()
	m.apply_all()
	_check(m.packs.has("testpack01") and m.find_character("character_be_pack_1") != null, "pack reloaded, entry still enabled")
	_eq(m.item_profiles[it].price, 12, "own reloaded")
	m.set_pack_enabled("testpack01", true, "item")
	_eq(m.item_profiles[it].price, 9, "enable one kind")
	m.set_pack_enabled("testpack01", false, "character")
	_check(m.find_character("character_be_pack_1") == null and m.item_profiles[it].price == 9, "disable one kind leaves the others")
	m.uninstall_pack("testpack01")
	_check(m.find_character("character_be_pack_1") == null and not m.packs.has("testpack01"), "uninstalled")
	_check(not File.new().file_exists(m.PACK_DIR + "testpack01.json"), "pack file removed")
	_eq(m.item_profiles[it].price, 12, "own kept after uninstall")
	m.weapon_sets = {}
	m.custom_tags = {}


# 变量：修改 / 比较；效果之后继续连接；多条出线按纵坐标执行；跨波保留、随存档保存；不受诅咒
func test_206_variables_and_order() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	# 敌袭结束 → x 加 1 → x 至少 2 → 获得优惠券（上）/ x 设为 0（下）：每 2 波一次
	var we = GE.add_node(g, "wave_end", Vector2(0, 0))
	var inc = GE.add_node(g, "var_set", Vector2(300, 0), {"var": "x", "op": "add", "value": 1})
	var cmp = GE.add_node(g, "var_cmp", Vector2(600, 0), {"var": "x", "cmp": "at_least", "n": 2})
	var reset = GE.add_node(g, "var_set", Vector2(900, 100), {"var": "x", "op": "set", "value": 0})
	var gain = GE.add_node(g, "gain_item", Vector2(900, 0), {"items": ["item_coupon"]})
	GE.add_link(g, we, inc)
	GE.add_link(g, inc, cmp)
	GE.add_link(g, cmp, reset)
	GE.add_link(g, cmp, gain)
	# 击杀 → 乘以 2（上）/ 设为 5（下）
	var k = GE.add_node(g, "kill", Vector2(0, 400))
	var mul = GE.add_node(g, "var_set", Vector2(300, 400), {"var": "o", "op": "mul", "value": 2})
	var set5 = GE.add_node(g, "var_set", Vector2(300, 500), {"var": "o", "op": "set", "value": 5})
	GE.add_link(g, k, set5)
	GE.add_link(g, k, mul)
	_eq(GE.outgoing(g, cmp), [gain, reset], "outgoing ordered by y")
	_eq(GE.paths(g).size(), 5, "effects in the middle end their own path too")
	var text = GE.graph_text(g, false)
	_check(text.find("BE_") < 0 and text.find("x") >= 0, "variable text: " + text)
	_eq(text.split("\n")[0], GE.path_text(GE.nodes_by_id(g), [we, inc], false), "first effect first")
	_graph_char(g)
	var coupon = m.find_target("item", "item_coupon")
	var n0 = rd.get_player_items_ref(0).count(coupon)
	m.runtime.fire("wave_end", 0)
	m.runtime.end_wave()
	_eq(GE.get_var(0, "x"), 1, "x counted across the wave end")
	_eq(rd.get_player_items_ref(0).count(coupon), n0, "no item after 1 wave")
	m.runtime.start_wave(null)
	m.runtime.fire("wave_end", 0)
	m.runtime.end_wave()
	_eq(rd.get_player_items_ref(0).count(coupon), n0 + 1, "item after 2 waves")
	_eq(GE.get_var(0, "x"), 0, "reset after the item")
	m.runtime.start_wave(null)
	m.runtime.fire("kill", 0)
	_eq(GE.get_var(0, "o"), 5, "upper branch first: 0 x 2, then set 5")
	m.runtime.fire("kill", 0)
	_eq(GE.get_var(0, "o"), 5, "10 then set 5")
	# 存档往返
	GE.set_var(0, "x", 7)
	var pd = rd.players_data[0]
	var saved = JSON.parse(JSON.print(pd._serialize_effects(pd.effects))).result
	var loaded = Utils.convert_dictionary_to_hash(pd._deserialize_effects(saved, {}), true)
	var vt = loaded.get(Keys.generate_hash(GE.VARS_KEY), {})
	_eq(int(vt.get(GE.var_hash("x"), -1)), 7, "variable survives save / load")
	m.runtime.end_wave()
	# 除以 0 不变；比较可以作为状态条件
	var g2 = GE.new_graph()
	var lv = GE.add_node(g2, "level_up", Vector2.ZERO)
	GE.add_link(g2, lv, GE.add_node(g2, "var_set", Vector2.ZERO, {"var": "d", "op": "div", "value": 0}))
	_graph_char(g2)
	GE.set_var(0, "d", 9)
	m.runtime.fire("level_up", 0)
	_eq(GE.get_var(0, "d"), 9, "divide by zero ignored")
	m.runtime.end_wave()
	_check("var_cmp" in m.Catalog.STATE_CONDS, "var_cmp is a state condition")
	# 不受诅咒：数值与路径上的"每 N 次"都不变
	var g3 = GE.new_graph()
	var kl = GE.add_node(g3, "kill", Vector2.ZERO)
	var ev = GE.add_node(g3, "every", Vector2.ZERO, {"n": 6})
	var vs = GE.add_node(g3, "var_set", Vector2.ZERO, {"var": "c", "op": "add", "value": 3})
	var vc = GE.add_node(g3, "var_cmp", Vector2.ZERO, {"var": "c", "n": 4})
	GE.add_link(g3, kl, ev)
	GE.add_link(g3, ev, vs)
	GE.add_link(g3, vs, vc)
	GE.add_link(g3, vc, GE.add_node(g3, "heal_hp", Vector2.ZERO, {"value": 3}))
	var heal = vc + 1
	var by = GE.nodes_by_id(m.curse_graph(g3, CURSE_M))
	_eq(int(by[vs].params.value), 3, "variable value not cursed")
	_eq(int(by[vc].params.n), 4, "variable compare not cursed")
	_eq(int(by[ev].params.n), 6, "every before a variable not cursed")
	var has_dlc = _dlc("abyssal_terrors") != null
	_eq(int(by[heal].params.value), _good(3) if has_dlc else 3, "effect after a variable cursed as usual")


# 节点详细信息：基础伤害与额外属性加成进入伤害计算、路径文本，并随诅咒放大；没有详细信息的旧节点不变
func test_197_node_details() -> void:
	var GE = load(GraphEffectScript)
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	var fx = rd.get_player_effects(0)
	fx[Keys.stat_armor_hash] = 10
	fx[Keys.stat_luck_hash] = 20
	fx[Keys.stat_percent_damage_hash] = 0
	m.runtime._refresh(0)
	var old = {"params": {"stat": "stat_armor", "pct": 50}}
	_eq(m.runtime._scaled_damage(old, 0), 5, "no details: same as before")
	var n = {"kind": "explode", "params": {"stat": "stat_armor", "pct": 50, "damage": 7, "scaling_stats": [["stat_luck", 0.5]]}}
	_eq(m.runtime._scaled_damage(n, 0), 22, "percent + flat + extra scaling")
	var neg = {"params": {"stat": "stat_armor", "pct": 50, "damage": -500}}
	_eq(m.runtime._scaled_damage(neg, 0), 1, "at least 1 damage")
	var text = GE._payload_text(n, "", false)
	_check(text.find(" + 50% ") >= 0 and text.find(" + 7") >= 0, "details in the path text: " + text)
	_eq(GE._payload_text({"kind": "explode", "params": {"stat": "stat_armor", "pct": 50}}, "", false).find(" + "), -1, "no details: text unchanged")
	var ig = {"kind": "ignite", "params": {"value": 5, "secs": 3, "stat": "stat_armor", "pct": 100, "damage": 9, "scaling_stats": [["stat_luck", 1.0]]}}
	var ig_text = GE._payload_text(ig, "", false)
	_check(ig_text.find(" + 100% ") >= 0 and ig_text.find(" + 9") < 0, "ignite text: extra scaling only: " + ig_text)
	var g = GE.new_graph()
	var ex = GE.add_node(g, "explode", Vector2.ZERO, {"stat": "stat_armor", "pct": 100, "damage": 10, "scaling_stats": [["stat_luck", 0.5]]})
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), ex)
	var cursed = GE.nodes_by_id(m.curse_graph(g, CURSE_M))[ex].params
	var has_dlc = _dlc("abyssal_terrors") != null
	_eq(int(cursed.damage), _good(10) if has_dlc else 10, "flat damage cursed")
	_check(abs(cursed.scaling_stats[0][1] - (0.5 * (1.0 + CURSE_M) if has_dlc else 0.5)) < 0.001, "extra scaling cursed: %s" % cursed.scaling_stats[0][1])
	_eq(g.nodes[0].params.scaling_stats[0][1], 0.5, "curse keeps the source graph")


# ============================================================
# 3.0.0：土豆兄弟 1.2（物品套组、史前惧兽）
# ============================================================
# 原版列表是按套组重建的缓存：自定义对象在重建后仍在列表与商店池里；DLC 角色没有被提前缓存掉
func test_300_lists_and_pool() -> void:
	for id in ["character_veteran", "character_variant", "character_romantic"]:
		_check(m.find_character(id) != null, "DLC character listed: " + id)
	var iid = m.create_custom_item(_plain_item().my_id, "pooltest")
	var fam = _family_from(1, WeaponType.MELEE)
	_check(fam != null, "vanilla family starting at tier 2")
	var low = m.add_weapon_tier(fam[0].weapon_id, 0) if fam != null else ""
	m.apply_all()
	_unlock_everything()
	isvc.invalidate_items_cache()
	isvc.invalidate_weapons_cache()
	var it = m.find_target("item", iid)
	_check(it != null and it in isvc.items, "custom item survives a list rebuild")
	_check(low != "" and m.find_target("weapon", low) in isvc.weapons, "lower tier survives a list rebuild")
	isvc.init_unlocked_pool()
	_check(it in isvc.get_pool(it.tier, isvc.TierData.ITEMS), "custom item in the shop pool")
	var w = m.find_target("weapon", low) if low != "" else null
	_check(w != null and w in isvc.get_pool(0, isvc.TierData.WEAPONS), "lower tier in the shop pool")
	# 原版商店池重建（重开一局 / 选难度）后仍在
	rd.reset()
	_check(it in isvc.get_pool(it.tier, isvc.TierData.ITEMS), "custom item in the pool after RunData.reset")
	m.delete_custom_item(iid)
	if low != "":
		m.delete_weapon_tier(low)
	m.apply_all()
	_check(m.find_target("item", iid) == null and not it in isvc.items, "deleted custom item leaves the list")


# 来源：DLC2 的内容不在 res://dlcs/ 下，按物品套组判断
func test_301_sources() -> void:
	var BE = load(MOD_DIR + "mod_main.gd")
	_eq(BE.source_of(m.find_character("character_veteran")), "dlc2", "DLC2 character")
	_eq(BE.source_of(m.find_target("item", "item_fossil_skull")), "dlc2", "DLC2 item")
	_eq(BE.source_of(m.find_target("item", "item_cybernetic_arm")), "dlc2", "DLC2 mecha item")
	_eq(BE.source_of(m.find_target("weapon", "weapon_whip_1")), "dlc2", "DLC2 weapon")
	_eq(BE.source_of(m.find_character("character_romantic")), "dlc1", "DLC1 character")
	_eq(BE.source_of(m.find_target("item", "item_evil_hat")), "vanilla", "free update item")
	_eq(BE.source_of(m.find_character("character_well_rounded")), "vanilla", "base character")
	var ui = yield(_open_ui(CH), "completed")
	_check(ui._stat_icon("loot_alien_chance") != null and ui._stat_icon("xp_gain") != null and ui._stat_icon("bonus_crit_damage") != null, "stat icons resolve through object ids")
	ui.queue_free()
	yield(tree, "idle_frame")


# 禁用页：升级 / 机械化禁用的属性；自定义角色沿用基底（含需要的物品套组）
func test_302_stat_bans() -> void:
	var c = m.find_character(CH)
	var orig = c.banned_upgrades.duplicate()
	var p = m.new_profile()
	p.ban_upgrades = ["upgrade_speed", "upgrade_luck"]
	p.ban_meca = ["stat_luck"]
	m.profiles[CH] = p
	m.apply_all()
	_eq(c.banned_upgrades, ["upgrade_speed", "upgrade_luck"], "upgrade bans applied")
	_eq(c.banned_meca_stats, ["stat_luck"], "mecha bans applied")
	_check(not m.upgrade_ban_options().empty() and "stat_luck" in m.meca_ban_options(), "ban options listed")
	m.profiles.erase(CH)
	m.apply_all()
	_eq(c.banned_upgrades, orig, "upgrade bans restored")
	var wid = m.create_custom("character_wounded", "bantest")
	_eq(m.find_character(wid).banned_upgrades, m.find_character("character_wounded").banned_upgrades, "custom character keeps the base upgrade bans")
	var vid = m.create_custom("character_variant", "settest")
	_eq(m.find_character(vid).required_item_set, "primal_dread", "custom character needs the base item set")
	var did = m.create_custom("character_droid", "mecatest")
	_check("stat_max_hp" in m.find_character(did).banned_meca_stats, "custom character keeps the base mecha bans")
	# 编辑器禁用页
	var ui = yield(_open_ui(wid), "completed")
	ui._on_tab_pressed("bans")
	yield(tree, "idle_frame")
	_check(_tree_has_text(ui._page, tr("BE_BAN_UPGRADES").replace("{0}", str(m.find_character(wid).banned_upgrades.size()))), "upgrade ban card shown")
	ui._on_stat_ban_toggle("ban_upgrades", "banned_upgrades", "upgrade_speed")
	_check("upgrade_speed" in m.profiles[wid].ban_upgrades, "toggle adds a ban")
	ui.queue_free()
	yield(tree, "idle_frame")
	for id in [wid, vid, did]:
		m.delete_custom(id)


# 异变：蓝图被复制到肿瘤上时按异变强度缩放，合并时相加；不当作诅咒；异变不重新发放"仅一次"令牌
func test_303_mutation_and_blueprints() -> void:
	var GE = load(GraphEffectScript)
	var dlc = isvc.get_dlc_data_by_id("primal_dread")
	var g = GE.new_graph()
	var once = GE.add_node(g, "once", Vector2.ZERO)
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), once)
	var ps = GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 4})
	GE.add_link(g, once, ps)
	var ge = GE.make(g)
	_check(dlc.can_effect_be_copied_by_mutation(ge, -1), "blueprint can be copied by a mutation")
	var copy = ge.duplicate()
	copy.added_by_mutation = true
	copy.value = 500
	_eq(copy.curse_modifier(), 0.0, "mutated copy is not cursed")
	_eq(int(GE.nodes_by_id(copy.live_graph())[ps].params.value), 2, "half-strength copy halves the value")
	var tumor = []
	dlc.add_effect_to_tumor_effects(tumor, copy)
	var copy2 = copy.duplicate()
	dlc.add_effect_to_tumor_effects(tumor, copy2)
	_eq(tumor.size(), 1, "identical blueprints merge on the tumor")
	_eq(int(tumor[0].value), 1000, "merged strength adds up")
	_eq(int(GE.nodes_by_id(tumor[0].live_graph())[ps].params.value), 4, "merged copies at full strength")
	var tiny = ge.duplicate()
	tiny.added_by_mutation = true
	tiny.value = 100
	_eq(int(GE.nodes_by_id(tiny.live_graph())[ps].params.value), 1, "weak copy keeps at least 1")
	# 真实异变：道具上的蓝图跟着异变后的副本走，令牌数不变
	var iid = m.create_custom_item(_plain_item().my_id, "mutgraph")
	m.item_profiles[iid].effects = []
	m.item_profiles[iid].graph = g
	m.apply_all()
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_item(m.find_target("item", iid), 0)
	rd.get_player_effects(0)[Keys.stat_evolution_hash] = -20
	var n0 = GE.once_list(0).size() - _graph_count(rd.players_data[0].items, GE)
	var mutated = rd.mutate_random_item(0)
	_check(mutated != null and mutated.is_mutant, "item mutated")
	_check(_graph_count(rd.players_data[0].items, GE) >= 1, "blueprint still owned after the mutation")
	_eq(GE.once_list(0).size() - n0, _graph_count(rd.players_data[0].items, GE), "one once token per owned blueprint after the mutation")
	m.delete_custom_item(iid)


func _graph_count(items: Array, GE) -> int:
	var c = 0
	for it in items:
		for e in it.effects:
			if e is GE:
				c += 1
	return c


# 史前惧兽的蓝图节点：进化敌人扳机、道具异变扳机、进化方向 / 目标条件、机械部件 / 异变 / 减缓时间效果
func test_304_dlc2_nodes() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "evolved_kill", Vector2.ZERO), GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 1}))
	GE.add_link(g, GE.add_node(g, "meca_kill", Vector2.ZERO), GE.add_node(g, "meca_parts", Vector2.ZERO, {"value": 2}))
	var camp = GE.add_node(g, "evo_camp", Vector2.ZERO, {"camp": "mutant"})
	GE.add_link(g, GE.add_node(g, "mutant_kill", Vector2.ZERO), camp)
	GE.add_link(g, camp, GE.add_node(g, "mutate", Vector2.ZERO, {"n": 1}))
	var tev = GE.add_node(g, "target_evolved", Vector2.ZERO, {"camp": "meca"})
	GE.add_link(g, GE.add_node(g, "enemy_hit", Vector2.ZERO), tev)
	GE.add_link(g, tev, GE.add_node(g, "slow_time", Vector2.ZERO, {"pct": 60, "secs": 2}))
	GE.add_link(g, GE.add_node(g, "mutated", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_luck", "value": 1}))
	_graph_char(g)
	var g0 = rd.players_data[0].gold
	m.runtime.fire("evolved_kill", 0)
	_eq(rd.players_data[0].gold - g0, 1, "evolved kill")
	var parts0 = rd.get_player_meca_parts(0)
	m.runtime.fire("meca_kill", 0)
	_eq(rd.get_player_meca_parts(0) - parts0, 2, "mecha parts gained")
	rd.get_player_effects(0)[Keys.stat_evolution_hash] = 5
	var pend0 = rd.players_data[0].pending_mutations
	m.runtime.fire("mutant_kill", 0)
	_eq(rd.players_data[0].pending_mutations, pend0, "evolution side: not mutant")
	rd.get_player_effects(0)[Keys.stat_evolution_hash] = -5
	m.runtime.fire("mutant_kill", 0)
	_eq(rd.players_data[0].pending_mutations, pend0 + 1, "mutate queued on the mutant side")
	rd.players_data[0].pending_mutations = pend0
	var holder = Node.new()
	holder.set_script(_flag_script())
	holder._is_meca = true
	tree.root.add_child(holder)
	EntityService.stop_enemy_time_slow()
	m.runtime.fire("enemy_hit", 0, null, holder)
	_check(abs(EntityService.enemy_time_factor - 0.4) < 0.01, "slow time on an evolved target: %s" % EntityService.enemy_time_factor)
	EntityService.stop_enemy_time_slow()
	holder._is_meca = false
	m.runtime.fire("enemy_hit", 0, null, holder)
	_eq(EntityService.enemy_time_factor, 1.0, "not a mecha target")
	holder.queue_free()
	m.runtime.end_wave()
	# 波次之外的扳机
	var luck0 = rd.get_player_effect(Keys.stat_luck_hash, 0)
	m.runtime.fire("mutated", 0)
	_eq(rd.get_player_effect(Keys.stat_luck_hash, 0) - luck0, 1, "mutated fires outside a wave")
	# 文本：没有未翻译的 key
	for loc in ["zh", "en", "ja", "de"]:
		TranslationServer.set_locale(loc)
		var t = GE.graph_text(g, false)
		_check(t.find("BE_") < 0 and t.find("{") < 0, loc + ": " + t)
	TranslationServer.set_locale("en")
	for k in ["stat_evolution", "bonus_crit_damage", "meca_only", "time_shift_on_hit", "weapon_set_bonus", "more_horde"]:
		_check(m.stat_name(k).find("BE_") < 0 and m.stat_name(k).find("{") < 0 and m.stat_name(k) != k, "stat name: " + k + " = " + m.stat_name(k))


func _flag_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = "extends Node\nvar _is_meca = false\nvar _is_mutant = false\n"
	s.reload()
	return s


# 其他 mod 的内容：add_mod_item（原版 1.2.0.1 重建时会丢）、直接加进列表的对象在重建后保留；套组里被移除的不补回
func test_305_other_mods_content() -> void:
	var a = _plain_item().duplicate()
	a.my_id = "item_be_test_modapi"
	a._generate_hashes()
	isvc.add_mod_item(a)
	var b = _plain_item().duplicate()
	b.my_id = "item_be_test_direct"
	b._generate_hashes()
	isvc.items.push_back(b)
	var c = _plain_item().duplicate()
	c.my_id = "item_be_test_inset"
	c._generate_hashes()
	isvc.base_game_item_set.items.push_back(c)
	isvc.invalidate_items_cache()
	var items = isvc.items
	_check(a in items, "add_mod_item content kept after a rebuild")
	_check(b in items, "directly added content kept after a rebuild")
	_check(c in items, "set content listed")
	m._lists_changed()
	_check(a in isvc.items and b in isvc.items, "kept after BroEditor invalidates the lists")
	isvc.base_game_item_set.items.erase(c)
	isvc.remove_mod_item(a)
	isvc.invalidate_items_cache()
	_check(not c in isvc.items, "content removed from its set not restored")
	_check(not a in isvc.items, "remove_mod_item content not restored")
	isvc.items.erase(b)
	isvc.invalidate_items_cache()
	_check(not b in isvc.items, "directly removed content stays removed")


# 属性分组：特殊规则单独分组，进化相关规则在进化分组；蓝图不可用规则；次要属性与规则的来源图标
func test_306_stat_groups_and_icons() -> void:
	var Catalog = load(MOD_DIR + "catalog.gd")
	var groups = {}
	for g in Catalog.STAT_GROUPS:
		groups[g[0]] = g[1]
	for k in ["min_weapon_tier", "max_weapon_tier", "max_melee_weapons", "max_ranged_weapons", "can_attack_while_moving", "weapon_set_bonus"]:
		_check(k in groups.BE_GRP_SPECIAL_RULES and not k in groups.BE_GRP_RULES, k + " is a special rule")
		_check(not k in Catalog.graph_stat_keys(), k + " not a blueprint stat")
	for k in Catalog.EVOLUTION_RULES:
		_check(k in groups.BE_GRP_EVOLUTION and not k in groups.BE_GRP_RULES, k + " in evolution")
		_check(not k in Catalog.graph_stat_keys(), k + " not a blueprint stat")
	_check("stat_evolution" in Catalog.graph_stat_keys(), "evolution still a blueprint stat")
	var seen = {}
	for k in Catalog.stat_keys():
		_check(not seen.has(k), k + " listed once")
		seen[k] = true
	_eq(Catalog.STAT_ICON_PATHS.structure_range, ["item_rusty_antenna", "character_builder"], "structure range icon")
	_eq(Catalog.STAT_ICON_PATHS.structure_percent_damage, ["character_builder"], "structure damage icon")
	var ui = yield(_open_ui(CH), "completed")
	for k in ["time_shift_on_hit", "min_weapon_tier", "max_weapon_tier", "harvesting_growth", "weapons_price", "no_heal", "torture", "fire_puddle_size", "can_attack_while_moving"]:
		_check(ui._stat_icon(k) != null, k + " has an icon")
	_eq(ui._stat_icon("structure_range"), m._find_any("item_rusty_antenna").icon, "rusty antenna icon")
	# 过长的原版名称换成本模组的短名称
	for k in ["fog_of_war_permanent", "effect_mixing_up_wave"]:
		_check(m.stat_name(k) == tr("BE_K_" + k.to_upper()) and m.stat_name(k).length() < 30, k + " short name")
	# 每10个波次+2敌群：开关（固定 +2），保留原版名称
	_check("more_horde" in groups.BE_GRP_RULES and m.stat_name("more_horde") == tr("MORE_HORDE"), "more horde is a rule toggle")
	# 禁用页：只显示已禁用的；编辑用选择器（词条 / 类别筛选）
	ui._on_tab_pressed("bans")
	yield(tree, "idle_frame")
	_eq(ui._ban_grids["items"][0].get_child_count(), 0, "nothing banned: empty grid")
	ui._open_picker("ban_weapons")
	var tag = ""
	for r in ui._picker.res:
		if not r.sets.empty():
			tag = r.sets[0].my_id
			break
	ui._picker.on_chip(tag, "tag")
	var shown = []
	for r in ui._picker.res:
		if ui._picker.shown(r):
			shown.push_back(r)
			_check(ui._tags_of(r).size() > 0, "shown weapon has the class")
	_check(not shown.empty() and shown.size() < ui._picker.res.size(), "class filter narrows")
	ui._picker.on_shown(true)
	ui._picker.confirm()
	_eq(m.profiles[CH].ban_weapons.size(), shown.size(), "banned the shown families")
	_eq(ui._ban_grids["weapons"][0].get_child_count(), shown.size(), "page lists the banned")
	ui._open_picker("start_items")
	var itag = ""
	for r in ui._picker.res:
		if not r.tags.empty():
			itag = r.tags[0]
			break
	ui._picker.on_chip(itag, "tag")
	var ok = true
	for r in ui._picker.res:
		if ui._picker.shown(r):
			ok = ok and itag in r.tags
	_check(ok, "item tag filter")
	ui._close_picker()
	ui.queue_free()
	yield(tree, "idle_frame")


# 火焰池（莫洛托夫鸡尾酒）：缩放按一个数编辑；火焰池持续时间与燃烧持续时间分开
func test_307_fire_puddle_fields() -> void:
	var Catalog = load(MOD_DIR + "catalog.gd")
	var idx = -1
	var effects = m.orig_effects("weapon_molotov_1")
	for i in effects.size():
		if "puddle_scale" in effects[i]:
			idx = i
	if idx < 0:
		return
	var names = []
	for f in Catalog.editable_fields(effects[idx]):
		names.push_back(f.name)
	_check("puddle_scale" in names and "puddle_lifetime" in names, "puddle fields editable")
	_check(abs(Catalog.field_value(effects[idx], "puddle_scale") - 1.4) < 0.001, "scale read as a number")
	var e = m.make_effect({"from": "weapon_molotov_1", "i": idx, "set": {"puddle_scale": 2.0, "puddle_lifetime": 6.0}, "sub": {"burning_data": {"duration": 7}}})
	_eq(e.puddle_scale, Vector2(2, 2), "scale written as Vector2")
	_eq([e.puddle_lifetime, e.burning_data.duration], [6.0, 7], "puddle and burning durations separate")
	_eq(effects[idx].burning_data.duration, 4, "template untouched")
	_check("burning_data" in Catalog.sub_fields(e), "burning data in details")


# 撬棍：生成的炮塔的数值（嵌套在子效果里）可以在详细信息里修改
func test_308_nested_structure_details() -> void:
	var Catalog = load(MOD_DIR + "catalog.gd")
	var effects = m.orig_effects("weapon_crowbar_1")
	if effects.empty():
		return
	_check("structure_effect.stats" in Catalog.sub_fields(effects[0]), "crowbar turret stats listed")
	var orig_dmg = effects[0].structure_effect.stats.damage
	var e = m.make_effect({"from": "weapon_crowbar_1", "i": 0, "sub": {"structure_effect.stats": {"damage": 99, "scaling_stats": [["stat_engineering", 2.0]]}}})
	_eq(e.structure_effect.stats.damage, 99, "nested damage applied")
	_eq(e.structure_effect.stats.scaling_stats.size(), 1, "nested scaling applied")
	_eq(effects[0].structure_effect.stats.damage, orig_dmg, "template untouched")
	_check(m.effect_text(e).find("99") >= 0, "text shows new damage")
	var spec = m._effect_to_spec({"from": "weapon_crowbar_1", "i": 0}, e)
	_eq(int(spec.sub["structure_effect.stats"].damage), 99, "spec round trip")
	# 炮塔附带的易伤效果（5 秒 +10%，最多 3 层）
	var vf = "structure_effect.effects.0"
	_check(vf in Catalog.sub_fields(effects[0]), "crowbar turret vulnerability listed")
	var v = m.make_effect({"from": "weapon_crowbar_1", "i": 0, "sub": {vf: {"value": 20, "duration_secs": 8, "max_stacks": 4}}})
	var ve = v.structure_effect.effects[0]
	_eq([ve.value, ve.duration_secs, ve.max_stacks], [20, 8, 4], "vulnerability applied")
	_eq(effects[0].structure_effect.effects[0].value, 10, "vulnerability template untouched")
	_check(m.effect_text(v).find("80") >= 0, "text shows new max vulnerability")
	_eq(int(m._effect_to_spec({"from": "weapon_crowbar_1", "i": 0}, v).sub[vf].duration_secs), 8, "vulnerability round trip")
	# 流血炮塔（道具）同样可改
	var bt = m.orig_effects("item_bleeding_turret")
	if not bt.empty():
		_check("effects.0" in Catalog.sub_fields(bt[0]), "bleeding turret vulnerability listed")


# 史前惧兽效果拆解：病毒、干扰背包、怀表、臭臭大王花、泥潭爱好者（新状态扳机）
func test_309_dlc2_splits() -> void:
	var GE = load(GraphEffectScript)
	var Catalog = load(MOD_DIR + "catalog.gd")
	var cases = [
		["item_virus", "charm_evolved_on_hit", ["enemy_hit", "target_evolved", "enemy_hp_below", "chance", "charm"]],
		["item_jamming_backpack", "slow_meca_on_hit", ["enemy_hit", "target_evolved", "slow"]],
		["item_pocket_watch", "slow_time_when_below_hp", ["hit", "hp_below", "cap", "slow_time"]],
		["item_smelly_rafflesia", "enemy_percent_damage_taken", ["enemy_hit", "chance", "vuln"]],
		["item_mud_lover", "temp_stats_while_being_in_puddle", ["in_puddle", "temp_stat"]],
	]
	for c in cases:
		var e = null
		for x in m.orig_effects(c[0]):
			if x.custom_key == c[1] or (x.custom_key == "" and x.key == c[1]):
				e = x
		if e == null:
			continue
		_check(Catalog.can_split(e), c[0] + " splittable")
		var g = GE.new_graph()
		GE.split_native(g, e, Vector2.ZERO)
		var kinds = []
		for n in g.nodes:
			kinds.push_back(n.kind)
		_eq(kinds, c[2], c[0] + " nodes")
		_eq(g.links.size(), c[2].size() - 1, c[0] + " linked")
		_check(GE.graph_text(g, false) != "", c[0] + " has text")
	_check("in_puddle" in Catalog.STATE_TRIGGERS, "puddle is a state trigger")
	var s = GDScript.new()
	s.source_code = "extends Reference\nvar petrol_in_puddle = false\nvar acid_in_puddle = true\n"
	s.reload()
	var pl = s.new()
	_check(m.runtime._state_holds({"kind": "in_puddle", "params": {}}, pl), "in puddle holds")
	pl.acid_in_puddle = false
	_check(not m.runtime._state_holds({"kind": "in_puddle", "params": {}}, pl), "out of puddle")


# 进化值的颜色同原版：属性行按数值正负（机械蓝 / 异变黄），蓝图属性效果同色
func test_310_evolution_colors() -> void:
	var meca = Utils.get_evolution_color(1).to_html()
	var mutant = Utils.get_evolution_color(-1).to_html()
	_eq(m.stat_effect("stat_evolution", 3).effect_sign, 3, "evolution from value")
	_check(m.effect_text(m.stat_effect("stat_evolution", 3)).find(meca) >= 0, "+evolution meca color")
	_check(m.effect_text(m.stat_effect("stat_evolution", -3)).find(mutant) >= 0, "-evolution mutant color")
	var GE = load(GraphEffectScript)
	for v in [3, -3]:
		var g = GE.new_graph()
		var t = GE.add_node(g, "level_up", Vector2.ZERO)
		GE.add_link(g, t, GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_evolution", "value": v}))
		var txt = GE.graph_text(g, true)
		_check(txt.find(meca if v > 0 else mutant) >= 0, "graph evolution color: " + txt)


# ---------------- 反馈 1：蓝图扳机"获得时"、去重原版优先、诅咒 / 异变选项、单个对象的锁定 ----------------
func test_320_gain_trigger() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "gain", Vector2.ZERO)
	GE.add_link(g, t, GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 3}))
	GE.add_link(g, t, GE.add_node(g, "gain_item", Vector2.ZERO, {"items": ["item_coupon"]}))
	_graph_char(GE.new_graph())
	m.runtime.end_wave()
	var p = m.new_profile()
	p.graph = g
	m.item_profiles["item_alien_eyes"] = p
	m.apply_all()
	var a0 = _armor()
	rd.add_item(m.find_target("item", "item_alien_eyes"), 0)
	yield(_frames(2), "completed")
	_eq(_armor(), a0 + 3, "gain fires once when the item is obtained")
	var ids = []
	for x in rd.get_player_items_ref(0):
		ids.push_back(x.my_id)
	_eq(ids.count("item_coupon"), 1, "gain -> gain item right away (shop phase): " + str(ids))
	m.runtime.start_wave(null)
	m.runtime.fire("wave_start", 0)
	m.runtime.end_wave()
	_eq(_armor(), a0 + 3, "not again on later events")
	_check(GE.graph_text(g, false).find(tr("BE_TX_GAIN").strip_edges()) >= 0, "gain text: " + GE.graph_text(g, false))
	# 互相获得的蓝图不会卡死
	var g2 = GE.new_graph()
	GE.add_link(g2, GE.add_node(g2, "gain", Vector2.ZERO), GE.add_node(g2, "gain_item", Vector2.ZERO, {"items": ["item_alien_eyes"]}))
	p.graph = g2
	m.apply_all()
	rd.add_item(m.find_target("item", "item_alien_eyes"), 0)
	yield(_frames(2), "completed")
	_check(rd.get_player_items_ref(0).size() < 2 * m.runtime.MAX_GAIN + 20, "self-gain loop is capped: %d items" % rd.get_player_items_ref(0).size())


func test_321_library_vanilla_first() -> void:
	var out = m._vanilla_first([["mod_a", "", [], true], ["van_a", "", [], false], ["mod_b", "", [], true], ["van_b", "", [], false]])
	var ids = []
	for s in out:
		ids.push_back(s[0])
	_eq(ids, ["van_a", "van_b", "mod_a", "mod_b"], "vanilla sources first, order kept")
	for s in m._library_sources():
		_check(not s[3], "vanilla source is not a mod: " + str(s[0]))


func test_322_no_curse_no_evolve() -> void:
	var it = _plain_item()
	_check(isvc.can_item_be_cursed(it) and isvc.can_item_be_mutated(it), "allowed by default")
	var p = m.new_profile()
	p.no_curse = true
	p.no_evolve = true
	m.item_profiles[it.my_id] = p
	m.apply_all()
	_check(not isvc.can_item_be_cursed(it) and not isvc.can_item_be_mutated(it), "item flags block curse / mutation")
	var dlc = isvc.get_dlc_data_by_id("abyssal_terrors")
	if dlc != null:
		_check(dlc.curse_item(it, 0, true, 0.5) == it, "curse_item leaves the item alone")
	p.enabled = false
	_check(isvc.can_item_be_cursed(it) and isvc.can_item_be_mutated(it), "disabled profile: flags off")
	var w = isvc.weapons[0]
	_check(isvc.can_weapon_be_mechanized(w) and isvc.can_item_be_cursed(w), "weapon allowed by default")
	var f = m.new_family()
	f.no_curse = true
	f.no_evolve = true
	m.weapon_families[w.weapon_id] = f
	_check(not isvc.can_weapon_be_mechanized(w) and not isvc.can_item_be_cursed(w), "family flags block curse / mechanizing")
	_eq(m.normalize_family(JSON.parse(JSON.print(f)).result).no_evolve, true, "family flags survive save / load")
	# 蓝图：不受诅咒
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 2}))
	var ge = GE.make(g)
	ge.value = int(GE.CURSE_PROBE * 1.5)
	_check(ge.curse_modifier() > 0.4, "cursed blueprint")
	g["no_curse"] = true
	ge = GE.make(g)
	ge.value = int(GE.CURSE_PROBE * 1.5)
	_eq(ge.curse_modifier(), 0.0, "no_curse blueprint ignores the curse")


func test_323_mutation_options() -> void:
	var dlc = isvc.get_dlc_data_by_id("primal_dread")
	if dlc == null:
		return
	var iid = m.create_custom_item(_plain_item().my_id, "muttest")
	var p = m.item_profiles[iid]
	p.effects = [{"set": {"key": "stat_armor", "value": 5}}, {"set": {"key": "stat_speed", "value": -3}}]
	m.apply_all()
	var it = m.find_target("item", iid)
	rd.add_item(it, 0)
	var armor = _find_effect(it.effects, "stat_armor")
	_check(armor in dlc._get_copy_candidates(it, 0), "positive effect is a copy candidate")
	_check(it.effects.find(_find_effect(it.effects, "stat_speed")) in dlc._get_removable_negative_effect_indexes(it), "negative effect is removable")
	p.effects[0]["mut_copy"] = 2
	p.effects[1]["mut_keep"] = true
	m.apply_all()
	armor = _find_effect(it.effects, "stat_armor")
	_check(armor != null and not armor in dlc._get_copy_candidates(it, 0), "mut_copy = never: not copied")
	_check(not it.effects.find(_find_effect(it.effects, "stat_speed")) in dlc._get_removable_negative_effect_indexes(it), "mut_keep: not removed")
	# 读档后的实例（新建的效果）同样生效
	_eq(m.mutation_flags(it, armor.duplicate()), [2, false], "flags found by signature")
	p.effects[0]["mut_copy"] = 1
	m.apply_all()
	armor = _find_effect(it.effects, "stat_armor")
	_eq(m.mutation_flags(it, armor)[0], 1, "min-scale mode")
	_eq(armor in dlc._get_copy_candidates(it, 0), dlc.get_mutation_scale(0) >= m.MUT_MIN_SCALE, "mut_copy = min scale follows the mutation strength")
	# 蓝图
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_armor", "value": 2}))
	_eq(m.mutation_flags(it, GE.make(g))[0], 0, "blueprint copyable by default")
	g["no_copy"] = true
	_eq(m.mutation_flags(it, GE.make(g))[0], 2, "no_copy blueprint")
	m.delete_custom_item(iid)


func test_324_object_lock() -> void:
	var it = _plain_item()
	var id = it.my_id
	_check(m.is_unlocked("item", id), "unlocked at start")
	var p = m.new_profile()
	p.lock = true
	p.lock_note = "hello"
	p.unlock = {"type": "gold", "stat": "", "n": 50}
	m.item_profiles[id] = m.normalize_profile(JSON.parse(JSON.print(p)).result)
	m.apply_all()
	_check(m.is_obj_locked("item", id) and not m.is_unlocked("item", id), "profile lock uses the unlock records")
	var text = m.lock_text("item", id)
	_check(text.find("hello") >= 0 and text.find("50") >= 0, "lock text has the condition and the note: " + text)
	rd.players_data[0].gold = 10
	m.check_unlocks()
	_check(not m.is_unlocked("item", id), "condition not met")
	rd.players_data[0].gold = 60
	m.check_unlocks()
	_check(m.is_unlocked("item", id) and not m.is_obj_locked("item", id), "unlocked by the condition")
	_eq(m.lock_text("item", id), "", "no lock text once unlocked")
	m.apply_all()
	_check(m.is_unlocked("item", id), "stays unlocked after re-applying")
	# 蓝图：锁定 / 解锁对象
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "kill", Vector2.ZERO), GE.add_node(g, "obj_lock", Vector2.ZERO, {"target": "item:" + id}))
	GE.add_link(g, GE.add_node(g, "crit", Vector2.ZERO), GE.add_node(g, "obj_unlock", Vector2.ZERO, {"target": "item:" + id}))
	rd.players_data[0].gold = 0
	_graph_char(g)
	m.runtime.fire("kill", 0)
	_check(not m.is_unlocked("item", id), "blueprint locks one object")
	m.runtime.fire("crit", 0)
	_check(m.is_unlocked("item", id), "blueprint unlocks one object")
	_check(GE.graph_text(g, false).find(tr(it.name)) >= 0, "lock text names the object")
	m.runtime.end_wave()
	# 档案没了：加回解锁记录
	m.set_obj_locked("item", id, true)
	m.item_profiles.erase(id)
	m.obj_locks = {}
	m.apply_all()
	_check(m.is_unlocked("item", id) and m.lock_applied.empty(), "removing the lock unlocks again")
	# 本来就没解锁的对象不接管（之后也不会被"加回"）
	m._set_unlocked("item", id, false)
	m.set_obj_locked("item", id, true)
	_check(m.lock_applied.empty(), "never takes over an object the player has not unlocked")
	m.obj_locks = {}
	m.apply_all()
	_check(not m.is_unlocked("item", id), "left locked")
	m._set_unlocked("item", id, true)
	# 武器按家族
	var w = isvc.weapons[0]
	var f = m.new_family()
	f.lock = true
	m.weapon_families[w.weapon_id] = f
	m.apply_all()
	_check(not m.is_unlocked("weapon", w.weapon_id), "weapon family locked")
	m.kind_enabled.weapon = false
	m.apply_all()
	_check(m.is_unlocked("weapon", w.weapon_id), "tab switch off lifts the lock")
