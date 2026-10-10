extends Reference

# BroEditor 的无头测试：在反编译的游戏工程里运行，使用真实的 ItemService / RunData / ModLoader。
# 由 run_be.gd 在 autoload 就绪后加载；不要直接运行，使用同目录的 run_tests.sh（会同步 mod、隔离 user:// 目录）。

const MOD_ID = "Mojimoon-BroEditor"
const MOD_DIR = "res://mods-unpacked/" + MOD_ID + "/"
const WAVE = 8

var m
var isvc
var rd
var tree: SceneTree
var _current_test = ""
var _failures: Array = []
var _checks = 0
# 测试用角色（第一个原版角色）
var CH: String


func run(p_tree: SceneTree):
	tree = p_tree
	if OS.get_environment("BE_TEST") != "1":
		printerr("Refusing to run: use run_tests.sh (it isolates user:// from your real saves).")
		return 2
	m = tree.root.get_node_or_null("ModLoader/" + MOD_ID)
	isvc = tree.root.get_node("ItemService")
	rd = tree.root.get_node("RunData")
	if m == null:
		printerr("Mod node not found: is the mod in res://mods-unpacked?")
		return 2
	_unlock_everything()
	CH = isvc.characters[0].my_id
	print("user dir: ", OS.get_user_data_dir())
	var tests: Array = []
	for method in get_method_list():
		var only = OS.get_environment("BE_ONLY")
		if method.name.begins_with("test_") and (only == "" or method.name.find(only) >= 0):
			tests.push_back(method.name)
	tests.sort()
	for t in tests:
		_current_test = t
		_reset()
		var state = call(t)
		if state is GDScriptFunctionState:
			yield(state, "completed")
		print("  ran ", t)
	print("")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		printerr("FAIL ", f)
	if _failures.empty():
		print("ALL TESTS PASSED")
	return 0 if _failures.empty() else 1


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures.push_back(_current_test + ": " + msg)


# Godot 3 的字典 == 比较引用：字典按 JSON 比较
func _eq(actual, expected, msg: String) -> void:
	if actual is Dictionary or expected is Dictionary:
		_check(JSON.print(actual) == JSON.print(expected), "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])
		return
	_check(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func _reset() -> void:
	for id in m.custom_ids():
		m.delete_custom(id)
	for id in m.item_profiles.keys():
		if m.item_profiles[id].custom:
			m.delete_custom_item(id)
	for wid in m.weapon_families.keys():
		var f = m.weapon_families[wid]
		if f.custom:
			m.delete_custom_weapon(wid)
		else:
			for t in f.tiers:
				m._unregister_weapon(m.tier_id(wid, t, false))
			m.weapon_families.erase(wid)
			m._link_family(wid)
	m.weapon_families = {}
	m.disabled = {"character": [], "item": [], "weapon": []}
	m.profiles = {}
	m.item_profiles = {}
	m.weapon_profiles = {}
	for k in m.KINDS:
		m.kind_enabled[k] = true
	m.apply_all()
	_setup_player(CH if CH != "" else isvc.characters[0].my_id)
	rd.current_wave = WAVE


func _setup_player(id: String) -> void:
	rd.set_player_count(1, true)
	rd.enabled_dlcs = []
	var c = m.find_character(id)
	rd.players_data[0].current_character = c
	rd.players_data[0].items = [c]


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


func _find_effect(effects: Array, key: String, custom_key: String = ""):
	for e in effects:
		if e.key == key and e.custom_key == custom_key:
			return e
	return null


func _open_ui(id: String):
	var ui = load(MOD_DIR + "ui/editor_ui.tscn").instance()
	ui.initial_id = id
	tree.root.add_child(ui)
	yield(tree, "idle_frame")
	yield(tree, "idle_frame")
	return ui


# ============================================================
# 效果库与蓝图
# ============================================================
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


# ============================================================
# 原版角色档案
# ============================================================
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


# ============================================================
# 自定义角色
# ============================================================
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


# ============================================================
# 禁用
# ============================================================
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


# ============================================================
# 分享码 / 存档
# ============================================================
func test_40_share_code() -> void:
	var p = m.new_profile()
	p.stats = {"stat_luck": 12}
	m.profiles[CH] = p
	var code = m.export_code(CH)
	_check(code.begins_with(m.SHARE_PREFIX), "prefix")
	m.profiles = {}
	_eq(m.import_code(code, CH), CH, "imported into native")
	_eq(m.profiles[CH].stats, {"stat_luck": 12}, "content")
	for bad in ["", "x", "BE1:", "BE1:!!", "AA1:" + Marshalls.utf8_to_base64("{}")]:
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


# ============================================================
# 编辑器界面
# ============================================================
func test_50_ui_all_tabs_native_and_custom() -> void:
	var id = m.create_custom(CH)
	for target in [CH, id]:
		var ui = yield(_open_ui(target), "completed")
		_eq(ui._id, target, "opened on " + target)
		for t in ui.TABS:
			ui._on_tab_pressed(t[0])
			yield(tree, "idle_frame")
			_check(ui._page.get_child_count() > 0, "tab %s built for %s" % [t[0], target])
		ui.queue_free()
		yield(tree, "idle_frame")


func test_51_ui_edits() -> void:
	var ui = yield(_open_ui(CH), "completed")
	# 初始属性
	ui._on_tab_pressed("stats")
	ui._on_stat_changed(4.0, "stat_armor", Label.new())
	_eq(m.profiles[CH].stats, {"stat_armor": 4}, "stat edit")
	# 效果：升级时 +3 幸运（原版扳机模板）
	ui._on_tab_pressed("effects")
	var n = _real(m.effect_specs(CH, m.profiles[CH])).size()
	var t = m.trigger_template("stats_on_level_up")
	ui._add_spec({"from": t.from, "i": t.i, "set": {"key": "stat_luck", "value": 3}})
	var specs = m.profiles[CH].effects
	_eq(_real(specs).size(), n + 1, "effect added")
	var e = m.make_effect(specs[-1])
	_eq([e.key, e.value, e.custom_key], ["stat_luck", 3, "stats_on_level_up"], "trigger effect")
	_eq(ui._expanded, specs.size() - 1, "new effect expanded")
	# 编辑字段
	ui._on_field_changed(6.0, specs.size() - 1, "value")
	_eq(m.make_effect(specs[-1]).value, 6, "field edit")
	# 换扳机：保留属性和数值
	ui._on_effect_trigger("", specs.size() - 1)
	e = m.make_effect(m.profiles[CH].effects[-1])
	_eq([e.key, e.value, e.custom_key], ["stat_luck", 6, ""], "trigger switched to permanent")
	# 效果库
	ui._on_lib_search("")
	_check(ui._lib_list.get_child_count() > 0, "library rows")
	var entry = m.library()[0]
	ui._add_spec({"from": entry.from, "i": entry.i})
	_eq(_real(m.profiles[CH].effects).size(), n + 2, "library add")
	ui._on_effect_move(m.profiles[CH].effects.size() - 1, -1)
	ui._on_effect_delete(0)
	_eq(_real(m.profiles[CH].effects).size(), n + 1, "delete")
	# 禁用
	ui._on_tab_pressed("bans")
	ui._on_ban_toggle("items", isvc.items[0].my_id)
	ui._on_ban_toggle("weapons", isvc.weapons[0].weapon_id)
	_eq(m.profiles[CH].ban_items, [isvc.items[0].my_id], "ban item")
	_eq(m.profiles[CH].ban_weapons, [isvc.weapons[0].weapon_id], "ban weapon family")
	# 初始装备：选择器
	ui._on_tab_pressed("gear")
	ui._open_picker("start_items")
	ui._on_picker_toggle(isvc.items[1].my_id)
	ui._on_picker_confirm()
	_eq(m.profiles[CH].start_items.size(), 1, "start item added via picker")
	ui._open_picker("start_weapons")
	ui._on_picker_clear()
	ui._on_picker_toggle(isvc.weapons[0].my_id)
	ui._on_picker_confirm()
	_eq(m.profiles[CH].weapons, [isvc.weapons[0].my_id], "starting weapons via picker")
	# 概览
	ui._on_tab_pressed("overview")
	ui._on_name_changed("  Renamed  ")
	_eq(m.profiles[CH].name, "Renamed", "name trimmed")
	_check(ui._preview_text.get_child_count() > 2, "preview filled")
	# 导出 / 导入
	ui.test_clipboard = ""
	ui._on_export_selected("BE1:")
	_check(ui.test_clipboard.begins_with(m.SHARE_PREFIX), "export to clipboard")
	# 关闭：保存
	ui._on_close_pressed()
	yield(tree, "idle_frame")
	m.load_profiles()
	_eq(m.profiles[CH].name, "Renamed", "saved on close")


func test_52_ui_custom_create_delete() -> void:
	var ui = yield(_open_ui(CH), "completed")
	var n = isvc.characters.size()
	ui._on_new_custom()
	_eq(isvc.characters.size(), n + 1, "created from UI")
	var id = ui._id
	_check(m.is_custom(id), "selected the new custom")
	ui._open_picker("icon")
	ui._on_picker_toggle(isvc.items[2].my_id)
	_eq(m.profiles[id].icon, isvc.items[2].my_id, "single picker applies immediately")
	_eq(ui._picker, null, "single picker closed")
	ui._on_delete_custom()
	_check(m.is_custom(id), "first click only arms")
	ui._on_delete_custom()
	_check(not m.is_custom(id), "second click deletes")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_60_entry_button() -> void:
	var screen = Control.new()
	var back = Button.new()
	back.name = "BackButton"
	back.unique_name_in_owner = true
	screen.add_child(back)
	back.owner = screen
	tree.root.add_child(screen)
	m.add_editor_button(screen)
	m.add_editor_button(screen)
	var n = 0
	for c in back.get_children():
		if c.name.begins_with("BroEditorBtn"):
			n += 1
	_eq(n, 1, "button added exactly once")
	screen.queue_free()


# ============================================================
# 蓝图
# ============================================================
const GraphEffectScript = "res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd"


func _graph_char(g: Dictionary):
	var p = m.new_profile()
	p.graph = g
	m.profiles[CH] = p
	m.apply_all()
	var c = m.find_character(CH)
	rd.set_player_count(1, true)
	rd.add_character(c, 0)
	m.runtime.start_wave(null)
	return c


func _armor() -> int:
	return int(rd.get_player_effect(Keys.generate_hash("stat_armor"), 0))


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


# ============================================================
# 开局状态 / 属性获取修改
# ============================================================
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
	var e = m.stat_effect("gain_stat_max_hp", 20)
	var t = e.get_text(0, false)
	_check(t.find("GAIN_STAT") < 0 and t.find("20") >= 0, "gain stat text: " + t)
	_check(t.find("+20") >= 0, "signed: " + t)
	_eq(m.stat_effect("hp_cap", 30).storage_method, 2, "cap replaces")


# ============================================================
# 真实场景：选择界面入口、战斗中的蓝图（较慢）
# ============================================================
func _frames(n: int):
	for i in n:
		yield(tree, "idle_frame")


func test_90_menu_buttons() -> void:
	for path in [MenuData.character_selection_scene, MenuData.weapon_selection_scene, MenuData.difficulty_selection_scene]:
		_setup_player(CH)
		var _e = tree.change_scene(path)
		yield(_frames(6), "completed")
		var sc = tree.current_scene
		var back = sc.get_node_or_null("%BackButton") if sc != null else null
		_check(back != null and back.has_node("BroEditorBtn"), "button on " + path)
		if back == null or not back.has_node("BroEditorBtn"):
			continue
		back.get_node("BroEditorBtn").emit_signal("pressed")
		yield(tree, "idle_frame")
		var opened = false
		for c in sc.get_children():
			if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0).name == "BroEditor":
				opened = true
				c.get_child(0)._on_close_pressed()
		_check(opened, "editor opens on " + path)
	_setup_player(CH)


func test_85_battle_graph() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var pairs = [
		["interval", {"secs": 1}, "add_gold", {"value": 1}],
		["still", {}, "temp_stat", {"stat": "stat_luck", "value": 50}],
		["hit", {}, "add_gold", {"value": 100}],
		["level_up", {}, "perm_stat", {"stat": "stat_armor", "value": 7}],
		["kill", {}, "add_gold", {"value": 1000}],
		["wave_start", {}, "perm_stat", {"stat": "stat_engineering", "value": 3}],
	]
	for pr in pairs:
		GE.add_link(g, GE.add_node(g, pr[0], Vector2.ZERO, pr[1]), GE.add_node(g, pr[2], Vector2.ZERO, pr[3]))
	var p = m.new_profile()
	p.graph = g
	m.profiles[CH] = p
	m.apply_all()
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_weapon(isvc.get_element_safe(isvc.weapons, "weapon_fist_1"), 0)
	rd.current_wave = 1
	TempStats.reset()
	var eng0 = rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0)
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(10), "completed")
	var main = tree.current_scene
	_check(not m.runtime.wave_over, "runtime started")
	_eq(rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0), eng0 + 3, "wave_start fired")
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	var gold0 = rd.players_data[0].gold
	yield(tree.create_timer(1.5), "timeout")
	_check(rd.players_data[0].gold - gold0 >= 1, "interval fired")
	_eq(TempStats.get_stat(Keys.generate_hash("stat_luck"), 0), 50, "still state holds temp stat")
	player._move_locked = true
	player._current_movement = Vector2(1, 0)
	yield(tree.create_timer(0.6), "timeout")
	_eq(TempStats.get_stat(Keys.generate_hash("stat_luck"), 0), 0, "leaving state reverts")
	player._current_movement = Vector2.ZERO
	player._move_locked = false
	gold0 = rd.players_data[0].gold
	var hit_args = TakeDamageArgs.new(-1)
	hit_args.bypass_invincibility = true
	hit_args.dodgeable = false
	var _r = player.take_damage(1, hit_args)
	yield(tree, "physics_frame")
	yield(tree, "idle_frame")
	_check(rd.players_data[0].gold - gold0 >= 100, "hit fired")
	player._invincibility_timer.stop()
	player.disable_hurtbox()
	var armor0 = _armor()
	rd.add_xp(int(rd.get_next_level_xp_needed(0)) + 1, 0)
	yield(_frames(2), "completed")
	_eq(_armor(), armor0 + 7, "level_up fired")
	var enemy = null
	for i in 300:
		var es = main._entity_spawner.get_all_enemies(false)
		if not es.empty():
			enemy = es[0]
			break
		yield(tree, "idle_frame")
	_check(enemy != null, "enemy spawned")
	if enemy != null:
		gold0 = rd.players_data[0].gold
		var _k = enemy.take_damage(999999, TakeDamageArgs.new(0))
		yield(_frames(3), "completed")
		_check(rd.players_data[0].gold - gold0 >= 1000, "kill fired")
	main._on_WaveTimer_timeout()
	yield(_frames(2), "completed")
	_check(m.runtime.wave_over, "wave end stops runtime")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")


# ============================================================
# 0.3.0：图标、分类、文本兼容、下拉框、输入、武器稀有度
# ============================================================
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


func test_103_search_select() -> void:
	var ui = yield(_open_ui(CH), "completed")
	var sel = ui._stat_option("stat_luck")
	ui.add_child(sel)
	_eq(sel.key, "stat_luck", "current key")
	_check(sel.text != "stat_luck", "shows localized name")
	var got = []
	sel.connect("selected", self, "_on_sel", [got])
	sel.open()
	_eq(ui.active_popup, sel, "popup open")
	sel._on_search("stat_armor")
	_eq(sel._list.get_child_count(), 2, "search by key (stat + its gain modifier)")
	sel._on_enter("")
	_eq(got, ["stat_armor"], "enter picks first match")
	_eq(sel.key, "stat_armor", "key updated")
	_eq(ui.active_popup, null, "popup closed")
	ui.queue_free()
	yield(tree, "idle_frame")


func _on_sel(k, got: Array) -> void:
	got.push_back(k)


func test_104_tier_weapons_and_reset_button() -> void:
	var ui = yield(_open_ui(CH), "completed")
	_check(ui._reset_btn.visible and ui._reset_btn.disabled, "reset visible, disabled without changes")
	ui._on_tab_pressed("gear")
	var t1 = ui._tier_weapon_ids(0)
	ui._on_tier_weapons(0)
	for id in t1:
		_check(id in m.profiles[CH].weapons, "T1 added " + id)
	_check(not ui._reset_btn.disabled, "reset enabled after change")
	ui._on_tier_weapons(0)
	for id in t1:
		_check(not id in m.profiles[CH].weapons, "T1 removed " + id)
	ui.queue_free()
	yield(tree, "idle_frame")


func test_105_input_blocked_while_open() -> void:
	_setup_player(CH)
	var _e = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(6), "completed")
	var sc = tree.current_scene
	_check(sc.is_processing_input(), "screen handles input normally")
	sc.get_node("%BackButton").get_node("BroEditorBtn").emit_signal("pressed")
	yield(tree, "idle_frame")
	_check(not sc.is_processing_input(), "screen input off while editor open")
	var fe_blocked = true
	for n in m._input_blocked:
		if n is FocusEmulator:
			fe_blocked = fe_blocked and not n.is_processing_input()
	_check(fe_blocked, "focus emulators off")
	_check(not _action_has_key("ui_up", KEY_W) and not _action_has_key("ui_down", KEY_S), "W/S removed from ui_up/ui_down while open")
	_check(_action_has_key("ui_up", KEY_UP), "arrow keys kept")
	for c in sc.get_children():
		if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0).name == "BroEditor":
			c.get_child(0)._on_close_pressed()
	yield(_frames(3), "completed")
	_check(sc.is_processing_input(), "input restored after close")
	_check(_action_has_key("ui_up", KEY_W) and _action_has_key("ui_down", KEY_S), "W/S restored after close")


func _action_has_key(action: String, sc: int) -> bool:
	for ev in InputMap.get_action_list(action):
		if ev is InputEventKey and (ev.scancode == sc or ev.physical_scancode == sc):
			return true
	return false


# ============================================================
# 路径文本（中文 / 英文句式）与原版用语
# ============================================================
func _path_line(nodes: Array) -> String:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var prev = -1
	for nd in nodes:
		var id = GE.add_node(g, nd[0], Vector2.ZERO, nd[1])
		if prev >= 0:
			GE.add_link(g, prev, id)
		prev = id
	return GE.graph_text(g, false)


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


# 效果列表里的真实效果（去掉初始属性 / 初始装备 / 蓝图的分组占位）
func _real(specs: Array) -> Array:
	var out = []
	for s in specs:
		if not (s is Dictionary and s.has("group")):
			out.push_back(s)
	return out


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


func test_122_entry_rows_and_drag() -> void:
	var p = m.new_profile()
	p.stats = {"stat_armor": 3, "stat_luck": 5}
	p.start_items = [{"id": isvc.items[3].my_id, "n": 1}, {"id": isvc.items[3].my_id, "n": 1}]
	p.effects = [{"set": {"key": "stat_dodge", "value": 7}}, {"group": "stats"}]
	m.profiles[CH] = m.normalize_profile(p)
	var c = m.find_character(CH)
	m.apply_all()
	var keys = []
	for e in c.effects:
		keys.push_back(e.key)
	_eq(keys.slice(0, 1), ["stat_dodge", "stat_armor"], "legacy group marker expands in place")
	var ui = yield(_open_ui(CH), "completed")
	ui._on_tab_pressed("effects")
	var specs = ui._specs()
	_eq(specs.size(), 5, "own effect + 2 stats + 2 start items, one row each")
	var rows = ui._effect_list.get_children()
	_eq(rows.size(), 5, "five rows")
	# 把幸运拖到最前面
	var li = -1
	for i in specs.size():
		if specs[i].get("key") == "stat_luck":
			li = i
	rows[0].drop_data(Vector2(0, 0), rows[li].get_drag_data(Vector2.ZERO))
	m.apply_all()
	_eq(c.effects[0].key, "stat_luck", "dragged stat entry to the top")
	_eq(c.effects[1].key, "stat_dodge", "own effect follows")
	# 拖到某行的下半部分 = 插到它后面
	rows = ui._effect_list.get_children()
	rows[1].drop_data(Vector2(0, rows[1].rect_size.y), rows[0].get_drag_data(Vector2.ZERO))
	m.apply_all()
	_eq([c.effects[0].key, c.effects[1].key], ["stat_dodge", "stat_luck"], "drop on lower half inserts after")
	# 删除一项属性后，它的占位被丢弃
	ui._p().stats.erase("stat_armor")
	_eq(ui._specs().size(), 4, "stale marker dropped")
	# 调试模式：键名显示
	m.debug = true
	ui._build_page()
	_check(_tree_has_text(ui._effect_list, "stat_dodge"), "debug shows keys in effect rows")
	ui._on_tab_pressed("stats")
	_check(_tree_has_text(ui._page, "stat_max_hp"), "debug shows keys on stats page")
	m.debug = false
	ui.queue_free()
	yield(tree, "idle_frame")


func _tree_has_text(n: Node, t: String) -> bool:
	if n is Label and n.text.find(t) >= 0:
		return true
	for c in n.get_children():
		if _tree_has_text(c, t):
			return true
	return false


# ============================================================
# 道具 / 武器
# ============================================================
func _plain_item():
	for it in isvc.items:
		if it.tier == 0 and it.max_nb == -1 and not it.effects.empty():
			return it
	return isvc.items[0]


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
	_check(kind_code.begins_with("BEI1:"), "item bundle prefix")
	_eq(m.export_bundle("weapon"), "", "empty bundle exports nothing")
	var all_code = m.export_bundle("")
	_check(all_code.begins_with("BEA1:"), "all prefix")
	m.item_profiles = {}
	m.profiles = {}
	_eq(m.import_bundle(kind_code), 1, "item bundle imported")
	_eq(m.item_profiles[it.my_id].price, 3, "bundle content")
	_eq(m.profiles.size(), 0, "item bundle leaves characters")
	m.item_profiles = {}
	_eq(m.import_bundle(all_code), 2, "all bundle imported")
	_eq(m.import_bundle(single), -1, "single code is not a bundle")
	_eq(m.import_bundle("BEA1:!!"), -1, "bad bundle rejected")


func test_133_ui_items_and_weapons() -> void:
	var ui = yield(_open_ui(CH), "completed")
	ui.test_clipboard = ""
	for kind in ["item", "weapon"]:
		ui.set_kind(kind)
		yield(tree, "idle_frame")
		_eq(ui._kind, kind, "switched to " + kind)
		_check(ui._char_grid.get_child_count() > 0, kind + " list filled")
		_check(m.find_target(kind, ui._id) != null, kind + " selected")
		for t in ui.OBJECT_TABS:
			ui._on_tab_pressed(t[0])
			yield(tree, "idle_frame")
			_check(ui._page.get_child_count() > 0, "%s tab %s built" % [kind, t[0]])
		# 筛选：稀有度
		ui._on_filter(3, "tier")
		var ok = true
		for b in ui._char_grid.get_children():
			var r = m.find_target(kind, b.get_meta("id"))
			var has3 = false
			for x in (m.family_members(r.weapon_id) if kind == "weapon" else [r]):
				has3 = has3 or x.tier == 3
			ok = ok and has3
		_check(ok, kind + " tier filter")
		ui._on_filter("vanilla", "src")
		for b in ui._char_grid.get_children():
			ok = ok and ui._source(m.find_target(kind, b.get_meta("id"))) == "vanilla"
		_check(ok, kind + " source filter")
		ui._on_filter(-1, "tier")
		ui._on_filter("all", "src")
		ui._on_filter("price", "sort")
		_check(ui._char_grid.get_child_count() > 0, kind + " sorted by price")
	# 武器属性页编辑
	ui._on_tab_pressed("attrs")
	var w = m.find_target("weapon", ui._id)
	ui._on_wstat_changed(42.0, ["damage", "int", ""])
	_eq(ui._p().wstats.get("damage"), 42 if w.stats.damage != 42 else null, "weapon damage edit")
	ui._on_wstat_changed(float(w.stats.damage), ["damage", "int", ""])
	_check(not ui._p().wstats.has("damage"), "back to original clears override")
	ui._on_scaling_add()
	_eq(ui._p().scaling.size(), w.stats.scaling_stats.size() + 1, "scaling row added")
	ui._on_attr_changed(9.0, "price", w.value)
	_eq(ui._p().price, 9 if w.value != 9 else -1, "price edit")
	# 道具：稀有度
	ui.set_kind("item")
	ui._on_tab_pressed("attrs")
	var it = m.find_target("item", ui._id)
	ui._on_attr_changed((it.tier + 1) % 4, "tier", it.tier)
	_eq(ui._p().tier, (it.tier + 1) % 4, "tier edit")
	# 导出：本栏全部
	ui._on_export_selected("BEI1:")
	_check(ui.test_clipboard.begins_with("BEI1:"), "export item bundle from ui")
	ui._on_export_selected("BEA1:")
	_check(ui.test_clipboard.begins_with("BEA1:"), "export all from ui")
	# 键名：非调试 = 只有主键名
	ui.set_kind("character")
	_eq(ui._kind, "character", "back to characters")
	var e = m.make_effect({"set": {"key": "stat_luck", "custom_key": "ck", "text_key": "tk"}})
	_eq(ui._key_info(e), "stat_luck", "main key only")
	m.debug = true
	_eq(ui._key_info(e), "stat_luck  ·  ck  ·  tk", "debug: all keys, no file")
	m.debug = false
	ui.queue_free()
	yield(tree, "idle_frame")



# ============================================================
# 自定义道具 / 武器、禁用
# ============================================================
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


func _family_from(min_tier: int, type: int):
	var seen = {}
	for w in isvc.weapons:
		if seen.has(w.weapon_id):
			continue
		seen[w.weapon_id] = true
		var ms = m.family_members(w.weapon_id)
		if ms[0].tier == min_tier and ms[0].type == type and ms[-1].tier == 3:
			return ms
	return null


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


func test_145_ui_custom_and_disable() -> void:
	var ui = yield(_open_ui(CH), "completed")
	# 角色：来源筛选与禁用
	ui._on_filter("mod", "src")
	_eq(ui._char_grid.get_child_count(), 0, "no mod characters yet")
	ui._on_filter("all", "src")
	ui._on_disable_toggled(true)
	_check(CH in m.disabled.character, "character disabled from ui")
	var greyed = false
	for b in ui._char_grid.get_children():
		if b.get_meta("id") == CH:
			greyed = b.modulate.a < 1.0
	_check(greyed, "disabled character greyed in list")
	ui._on_disable_toggled(false)
	# 道具：新建、改名、属性、删除
	ui.set_kind("item")
	var base = ui._id
	ui._on_new_custom()
	var iid = ui._id
	_check(iid.begins_with(m.ITEM_PREFIX) and iid != base, "custom item created from ui")
	for t in ui.OBJECT_TABS:
		ui._on_tab_pressed(t[0])
		yield(tree, "idle_frame")
		_check(ui._page.get_child_count() > 0, "custom item tab " + t[0])
	ui._on_name_changed("My Item")
	_eq(m.find_target("item", iid).name, "My Item", "custom item renamed live")
	ui._on_tab_pressed("attrs")
	ui._on_attr_changed(2, "tier", -999)
	_eq(m.find_target("item", iid).tier, 2, "custom item tier live")
	ui._on_delete_custom()
	ui._on_delete_custom()
	_check(m.find_target("item", iid) == null, "custom item deleted from ui")
	# 武器：每个家族一格
	ui.set_kind("weapon")
	var fams = {}
	for b in ui._char_grid.get_children():
		fams[b.get_meta("key")] = fams.get(b.get_meta("key"), 0) + 1
	var one_each = true
	for k in fams:
		one_each = one_each and fams[k] == 1
	_check(one_each and fams.size() > 10, "one entry per weapon family")
	# 给最低 T2 的原版武器补 T1
	var fam = _family_from(1, 0)
	ui._select(fam[0].my_id)
	_check(ui._tier_box.get_child_count() >= 4, "tier buttons shown")
	ui._on_add_tier(0)
	_eq(m.find_target("weapon", ui._id).tier, 0, "lower tier added from ui")
	_eq(m.find_target("weapon", ui._id).weapon_id, fam[0].weapon_id, "same family")
	ui._on_delete_tier()
	_eq(m.family_members(fam[0].weapon_id).size(), fam.size(), "lower tier deleted from ui")
	# 自定义武器：新建（未完成 -> 禁用）、补等级、改远程、类别
	ui._on_new_custom()
	var w = m.find_target("weapon", ui._id)
	var wid = w.weapon_id
	_check(m.is_custom_family(wid), "custom weapon created from ui")
	_check(m.family_complete(wid), "custom weapon copies the whole family")
	var top = m.family_members(wid)[-1]
	ui._select(top.my_id)
	ui._on_delete_tier()
	_check(ui._disable_switch.pressed and ui._disable_switch.disabled, "incomplete weapon: disable switch locked on")
	for t in ui.OBJECT_TABS:
		ui._on_tab_pressed(t[0])
		yield(tree, "idle_frame")
		_check(ui._page.get_child_count() > 0, "custom weapon tab " + t[0])
	while not m.family_complete(wid):
		var add = m.addable_tiers(wid)
		ui._on_add_tier(add[-1])
	_check(not m.is_disabled("weapon", wid), "complete after adding tiers")
	ui._refresh_header()
	_check(not ui._disable_switch.disabled, "switch unlocked when complete")
	ui._on_set_pressed(isvc.sets[0].my_id)
	_check(m.weapon_families[wid].sets is Array, "sets recorded on family")
	ui._on_tab_pressed("attrs")
	_check(ui._aspd_label != null and ui._aspd_label.text != "", "attack speed shown")
	ui._on_delete_custom()
	ui._on_delete_custom()
	_check(not m.weapon_families.has(wid), "custom weapon deleted from ui")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_146_attack_interval() -> void:
	for w in isvc.weapons:
		var cd = m.Catalog.attack_interval(w.stats)
		if cd <= 0.0 or cd > 10.0:
			_check(false, "attack interval sane for " + w.my_id)
			return
	_check(true, "attack intervals sane")



# 一局进行中删除自定义道具 / 武器后读档继续：不应报错（找不到的对象被原版读档逻辑跳过）
func test_150_resume_after_delete() -> void:
	var pd = tree.root.get_node("ProgressData")
	var cid = m.create_custom(CH)
	var iid = m.create_custom_item(_plain_item().my_id)
	var base = _family_from(0, 0)
	var wtier = m.create_custom_weapon(base[0].weapon_id)
	var wid = m.find_target("weapon", wtier).weapon_id
	while not m.family_complete(wid):
		var add = m.addable_tiers(wid)
		m.add_weapon_tier(wid, add[-1])
	m.apply_all()
	_setup_player(cid)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(cid), 0)
	rd.add_weapon(m.find_target("weapon", wtier), 0)
	rd.add_item(m.find_target("item", iid), 0)
	rd.current_wave = 3
	pd.save_run_state()
	_check(pd.saved_run_state.has_run_state, "run state saved")
	_check(m.delete_custom_item(iid), "item deleted mid-run")
	_check(m.delete_custom_weapon(wid), "weapon deleted mid-run")
	m.apply_all()
	pd.load_game_file()
	rd.resume_from_state(pd.saved_run_state)
	_check(rd.players_data[0].current_character != null, "character kept")
	_eq(rd.players_data[0].weapons.size(), 0, "deleted weapon dropped from the run")
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(60), "completed")
	_check(tree.current_scene != null, "battle scene running after resume")
	var _s = tree.change_scene(MenuData.shop_scene if "shop_scene" in MenuData else "res://ui/menus/shop/shop.tscn")
	yield(_frames(30), "completed")
	_check(tree.current_scene != null, "shop scene running after resume")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")
	pd.reset_and_save_new_run_state()



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


func test_153_weapon_attack_type() -> void:
	var ui = yield(_open_ui(CH), "completed")
	ui.set_kind("weapon")
	var fam = _family_from(0, 0)
	ui._select(fam[0].my_id)
	ui._on_tab_pressed("attrs")
	var sweep = 1 - int(fam[0].stats.attack_type)
	ui._on_wstat_changed(sweep, ["attack_type", "int", ""])
	_eq(ui._p().wstats.get("attack_type"), sweep, "attack type toggled")
	ui._on_wstat_changed(30.0, ["speed_percent_modifier", "int", "neg"])
	_eq(ui._p().wstats.get("speed_percent_modifier"), -30, "slow shown as positive, stored negative")
	m.apply_all()
	_eq(fam[0].stats.attack_type, sweep, "applied")
	ui.queue_free()
	yield(tree, "idle_frame")
