extends "res://mods/tests/BroEditor/test_base.gd"

# compat：与 QianMo-BroLab、cave-modtools 同时加载（run_tests.sh compat 会临时装上这两个 mod）。
# 关注兼容性：能正常显示、编辑、使用 BroLab 新增的效果；与 Modtools 共存时入口、禁用、开局状态、战斗不受影响。
# 不追求完备性：Modtools 额外加的属性等是否在 BroEditor 中显示不做检查。

const BROLAB = "QianMo-BroLab"
const MODTOOLS = "cave-modtools"
const BROLAB_CHAR = "res://mods-unpacked/QianMo-BroLab/contents/characters/1/brolab_virtual_character_data.tres"
const BROLAB_CHAR_ID = "character_brolab_compat"

var _brolab_char = null


func _brolab():
	return tree.root.get_node_or_null("ModLoader/" + BROLAB)


# BroLab 自带的示例角色（效果全是 BroLab 新增的效果脚本），按 BroLab 自己的方式加入 ItemService
func _brolab_character():
	if _brolab_char == null:
		var c = load(BROLAB_CHAR).duplicate()
		c.my_id = BROLAB_CHAR_ID
		c.unlocked_by_default = true
		c._generate_hashes()
		_brolab().BrolabManager.add_items([c], "character", false, true)
		_brolab_char = c
		# 效果库按需重建（新角色加入后）
		m._library = null
		m._weapon_library = null
	return _brolab_char


static func _is_brolab_effect(e) -> bool:
	return e != null and e.get_script() != null and e.get_script().resource_path.find(BROLAB) >= 0


func _brolab_entries() -> Array:
	var out = []
	for entry in m.library():
		if _is_brolab_effect(entry.effect):
			out.push_back(entry)
	return out


func _entry_with_key(key: String):
	for entry in _brolab_entries():
		if entry.effect.key == key:
			return entry
	return null


func test_01_mods_loaded() -> void:
	_check(_brolab() != null, "BroLab loaded")
	_check(tree.root.get_node_or_null("ModLoader/" + MODTOOLS) != null, "Modtools loaded")
	_check(m != null, "BroEditor loaded")


# ============================================================
# BroLab：新增效果的显示、编辑、使用
# ============================================================
func test_10_brolab_effects_in_library() -> void:
	var c = _brolab_character()
	_check(m.find_character(c.my_id) != null, "BroLab character listed in BroEditor")
	_eq(m.source_of(c), "mod", "BroLab character is a mod character")
	var entries = _brolab_entries()
	_check(entries.size() >= 3, "BroLab effects in the effect library (%d)" % entries.size())
	for entry in entries:
		var e = entry.effect
		_check(m.effect_text(e) != "", "text for " + e.key)
		var made = m.make_effect({"from": entry.from, "i": entry.i})
		_check(made != null and made.get_script() == e.get_script(), "clone keeps the BroLab script: " + e.key)
		_check(made != e, "clone is a copy: " + e.key)
	var rs = _entry_with_key("brolab_effect_receive_stat_at_wave")
	_check(rs != null, "receive-stat-at-wave effect found")
	if rs != null:
		var names = []
		for f in m.Catalog.editable_fields(rs.effect):
			names.push_back(f.name)
		_check("brolab_receive_stat_wave" in names and "brolab_receive_stat_key" in names, "BroLab fields are editable: " + str(names))
		var e2 = m.make_effect({"from": rs.from, "i": rs.i, "set": {"value": 9, "brolab_receive_stat_wave": 3, "brolab_receive_stat_key": "stat_luck"}})
		_eq([e2.value, e2.brolab_receive_stat_wave, e2.brolab_receive_stat_key], [9, 3, "stat_luck"], "edited BroLab fields")
		_check(m.effect_text(e2).find("9") >= 0, "edited text shows the value: " + m.effect_text(e2))


func test_11_brolab_effect_used_in_run() -> void:
	var _c = _brolab_character()
	var rs = _entry_with_key("brolab_effect_receive_stat_at_wave")
	if rs == null:
		_check(false, "receive-stat-at-wave effect found")
		return
	var p = m.new_profile()
	p.effects = [{"from": rs.from, "i": rs.i, "set": {"value": 7, "brolab_receive_stat_wave": 2}}]
	m.profiles[CH] = p
	m.apply_all()
	var ch = m.find_character(CH)
	var e = _find_effect(ch.effects, "brolab_effect_receive_stat_at_wave")
	_check(e != null and _is_brolab_effect(e), "BroLab effect on a vanilla character")
	_check(e != null and e.value == 7 and e.brolab_receive_stat_wave == 2, "with edited values")
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(ch, 0)
	var arr = rd.get_player_effect(Keys.generate_hash("brolab_effect_receive_stat_at_wave"), 0)
	_check(arr is Array and not arr.empty() and int(arr[-1][0]) == 7, "BroLab effect applied to the run: " + str(arr))
	# 分享码往返
	var code = m.export_code(CH)
	m.profiles = {}
	_eq(m.import_code(code, CH), CH, "share code with a BroLab effect")
	m.apply_all()
	_check(_find_effect(m.find_character(CH).effects, "brolab_effect_receive_stat_at_wave") != null, "BroLab effect survives the share code")


func test_12_brolab_character_in_editor() -> void:
	var c = _brolab_character()
	var cid = m.create_custom(c.my_id)
	m.apply_all()
	_eq(m.find_character(cid).effects.size(), m.orig_effects(c.my_id).size(), "custom character copies BroLab effects")
	var p = m.new_profile()
	p.stats = {"stat_armor": 3}
	m.profiles[c.my_id] = p
	m.apply_all()
	_check(_find_effect(c.effects, "stat_armor") != null, "BroLab character can be edited")
	var ui = yield(_open_ui(c.my_id), "completed")
	_eq(ui._id, c.my_id, "editor opens on the BroLab character")
	for t in ui.TABS:
		ui._on_tab_pressed(t[0])
		yield(tree, "idle_frame")
		_check(ui._page.get_child_count() > 0, "tab " + t[0])
	ui._on_tab_pressed("effects")
	var specs = ui._specs()
	for i in specs.size():
		ui._on_effect_edit(i)
		yield(tree, "idle_frame")
	_check(ui._effect_list.get_child_count() == specs.size(), "every BroLab effect row expands")
	ui._on_lib_search("brolab_effect")
	_check(ui._lib_list.get_child_count() > 0, "BroLab effects searchable in the library")
	ui._on_tab_pressed("overview")
	_check(_tree_has_rich(ui._preview_text), "preview renders")
	ui.queue_free()
	yield(tree, "idle_frame")
	m.profiles.erase(c.my_id)


func _tree_has_rich(n: Node) -> bool:
	if n == null:
		return false
	for ch in n.get_children():
		if ch.get_child_count() > 0 or ch is RichTextLabel:
			return true
	return false


# ============================================================
# Modtools：同时扩展了选择界面、ItemService、RunData、main、商店
# ============================================================
func test_20_selection_buttons() -> void:
	for path in [MenuData.character_selection_scene, MenuData.weapon_selection_scene, MenuData.difficulty_selection_scene]:
		_setup_player(CH)
		var _e = tree.change_scene(path)
		yield(_frames(12), "completed")
		var sc = tree.current_scene
		var back = sc.get_node_or_null("%BackButton") if sc != null else null
		_check(back != null and back.has_node("BroEditorBtn"), "BroEditor button on " + path)
		if back == null or not back.has_node("BroEditorBtn"):
			continue
		var btns = []
		for ch in back.get_children():
			if ch is Button and ch.visible:
				btns.push_back(ch)
		var overlap = false
		for i in btns.size():
			for j in range(i + 1, btns.size()):
				overlap = overlap or btns[i].get_global_rect().grow(-1).intersects(btns[j].get_global_rect().grow(-1))
		_check(not overlap, "buttons do not overlap on %s (%d buttons)" % [path, btns.size()])
		back.get_node("BroEditorBtn").emit_signal("pressed")
		yield(tree, "idle_frame")
		var opened = false
		for c in sc.get_children():
			if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0).name == "BroEditor":
				opened = true
				c.get_child(0)._on_close_pressed()
		_check(opened, "editor opens on " + path)
		yield(tree, "idle_frame")
	_setup_player(CH)


func test_21_bans_with_modtools() -> void:
	var banned_items = []
	for it in isvc.items:
		if it.tier == 0 and banned_items.size() < 40:
			banned_items.push_back(it.my_id)
	var p = m.new_profile()
	p.ban_items = banned_items
	m.profiles[CH] = p
	var disabled_item = null
	for it in isvc.items:
		if it.tier == 0 and not it.my_id in banned_items:
			disabled_item = it.my_id
			break
	m.set_disabled("item", disabled_item, true)
	m.apply_all()
	_setup_player(CH)
	var ok = true
	for i in 200:
		seed(i)
		var it = isvc.get_rand_item_for_wave(1, 0)
		ok = ok and not it.my_id in banned_items and it.my_id != disabled_item
	_check(ok, "banned / disabled items never rolled with Modtools loaded")


func test_22_start_state_with_modtools() -> void:
	var p = m.new_profile()
	p.start = {"materials": 50, "levels": 3}
	p.stats = {"stat_luck": 11}
	m.profiles[CH] = p
	m.apply_all()
	rd.set_player_count(1, true)
	rd.add_character(m.find_character(CH), 0)
	var g0 = rd.players_data[0].gold
	var l0 = rd.players_data[0].current_level
	rd.add_starting_items_and_weapons()
	_eq(rd.players_data[0].gold, g0 + 50, "materials")
	_eq(rd.players_data[0].current_level, l0 + 3, "levels")
	_check(rd.get_player_effect(Keys.generate_hash("stat_luck"), 0) >= 11, "starting stats")
	m._pending_start = {}


func test_30_battle_with_both() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_engineering", "value": 3}))
	GE.add_link(g, GE.add_node(g, "interval", Vector2.ZERO, {"secs": 1}), GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 1}))
	var _c = _brolab_character()
	var rs = _entry_with_key("brolab_effect_receive_stat_at_wave")
	var p = m.new_profile()
	p.graph = g
	if rs != null:
		p.effects = [{"from": rs.from, "i": rs.i, "set": {"value": 5, "brolab_receive_stat_wave": 1}}]
	m.profiles[CH] = p
	m.apply_all()
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_weapon(isvc.get_element_safe(isvc.weapons, "weapon_fist_1"), 0)
	rd.current_wave = 1
	TempStats.reset()
	var eng0 = rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0)
	print("COMPAT watch begin")
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(10), "completed")
	var main = tree.current_scene
	_check(main != null and main.name == "Main", "battle starts with both mods")
	_eq(rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0), eng0 + 3, "blueprint wave_start fires")
	main._players[0].disable_hurtbox()
	main._wave_timer.start(600)
	var gold0 = rd.players_data[0].gold
	yield(tree.create_timer(1.5), "timeout")
	_check(rd.players_data[0].gold - gold0 >= 1, "blueprint interval fires")
	main._on_WaveTimer_timeout()
	yield(_frames(4), "completed")
	print("COMPAT watch end")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")
