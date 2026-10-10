extends "res://mods/tests/BroEditor/test_base.gd"

# compat_off：紧接 compat 运行，BroLab、Modtools 已卸下，沿用 compat 的 user://（含 test_90 保存的档案）。
# 对 mod 内容的修改、基于 mod 内容新建的对象都不应显示，档案保留；编辑器、选择界面、战斗不应出错。

const BROLAB_CHAR_ID = "character_brolab_compat"
const MOD_ITEM_ID = "item_brolab_compat"
const MOD_WEAPON_ID = "weapon_modcompat"
const CUSTOM_IDS = ["character_frommod", "item_frommod", "weapon_frommod"]


func _load_saved() -> void:
	m.load_profiles()
	m.apply_all()
	_setup_player(CH)


func test_01_mods_gone() -> void:
	_check(tree.root.get_node_or_null("ModLoader/QianMo-BroLab") == null, "BroLab not loaded")
	_check(tree.root.get_node_or_null("ModLoader/cave-modtools") == null, "Modtools not loaded")
	_load_saved()
	_check(m.profiles.has(BROLAB_CHAR_ID) and m.item_profiles.has(MOD_ITEM_ID), "saved profiles read")


func test_10_hidden() -> void:
	_load_saved()
	_check(m.find_character(BROLAB_CHAR_ID) == null, "mod character absent")
	_check(m.find_character("character_frommod") == null, "custom character based on it hidden")
	_check(m.find_target("item", "item_frommod") == null, "custom item based on the mod item hidden")
	_check(m.family_members("weapon_frommod").empty(), "custom weapon based on the mod weapon hidden")
	_check(m.family_members(MOD_WEAPON_ID).empty(), "mod weapon absent")
	var c = m.find_character(CH)
	var ok = true
	for e in c.effects:
		ok = ok and e != null and (e.get_script() == null or e.get_script().resource_path.find("QianMo-BroLab") < 0)
	_check(ok, "BroLab effect dropped from the vanilla character")
	_check(not c.starting_weapons.empty(), "vanilla character keeps a starting weapon")
	for entry in m.library(true):
		ok = ok and entry.effect != null
	_check(ok, "effect library builds")


func test_11_profiles_kept() -> void:
	_load_saved()
	m.save_profiles()
	var main = JSON.parse(_read(m.SAVE_PATH)).result
	_check(main.profiles.has(BROLAB_CHAR_ID) and main.items.has(MOD_ITEM_ID) and main.weapons.has(MOD_WEAPON_ID + "_1"), "edits to mod content kept for when it comes back")
	_check(MOD_ITEM_ID in main.disabled.item, "disabled mod item kept")
	var files = m.custom_files()
	for id in CUSTOM_IDS:
		var kind = id.split("_")[0]
		_check(kind + "/" + id + ".json" in files, "custom file kept: " + id)


func test_20_editor() -> void:
	_load_saved()
	var ui = yield(_open_ui(CH), "completed")
	for kind in m.KINDS:
		ui.set_kind(kind)
		yield(tree, "idle_frame")
		var listed = []
		for n in ui._char_grid.get_children():
			listed.push_back(n.get_meta("id"))
		var bad = []
		for id in [BROLAB_CHAR_ID, MOD_ITEM_ID, MOD_WEAPON_ID + "_1"] + CUSTOM_IDS + ["weapon_frommod_1"]:
			if id in listed:
				bad.push_back(id)
		_eq(bad, [], kind + " list hides mod-related objects")
		for t in ui._tab_defs():
			ui._on_tab_pressed(t[0])
			yield(tree, "idle_frame")
			_check(ui._page.get_child_count() > 0, kind + " tab " + t[0])
	ui.set_kind("character")
	ui._select(CH)
	ui._on_tab_pressed("effects")
	yield(tree, "idle_frame")
	_eq(ui._effect_list.get_child_count(), ui._specs().size() - 1, "missing BroLab effect not listed")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_30_selection_and_battle() -> void:
	_load_saved()
	print("COMPAT watch begin")
	for path in [MenuData.character_selection_scene, MenuData.weapon_selection_scene]:
		_setup_player(CH)
		var _e = tree.change_scene(path)
		yield(_frames(8), "completed")
		_check(tree.current_scene != null, "opens " + path)
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_starting_items_and_weapons()
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(10), "completed")
	var main = tree.current_scene
	_check(main != null and main.name == "Main", "battle starts")
	if main != null and main.name == "Main":
		main._players[0].disable_hurtbox()
		yield(_frames(30), "completed")
		main._on_WaveTimer_timeout()
		yield(_frames(4), "completed")
	print("COMPAT watch end")
	_setup_player(CH)
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")
