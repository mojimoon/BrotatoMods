extends "res://mods/tests/BroEditor/test_base.gd"

# ui：编辑器界面与选择界面入口


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
	ui._on_export_selected(m.SHARE_PREFIX)
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
	_check(m.is_custom(id) and ui._modals.size() == 1, "delete asks first")
	ui._modals[-1].ok_button.emit_signal("pressed")
	_check(not m.is_custom(id) and ui._modals.empty(), "deleted after confirming")
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


func test_104_tier_weapons_and_reset_button() -> void:
	var ui = yield(_open_ui(CH), "completed")
	_check(ui._reset_btn.visible and ui._reset_btn.disabled, "reset visible, disabled without changes")
	ui._on_tab_pressed("gear")
	# 武器弹窗：筛选 T1 后"选中当前全部"，再"取消当前全部"
	var t1 = []
	for w in isvc.weapons:
		if w.tier == 0:
			t1.push_back(w.my_id)
	ui._open_picker("start_weapons")
	ui._on_picker_chip("tier", 0)
	ui._on_picker_shown(true)
	ui._on_picker_confirm()
	for id in t1:
		_check(id in m.profiles[CH].weapons, "T1 added " + id)
	_check(not ui._reset_btn.disabled, "reset enabled after change")
	ui._open_picker("start_weapons")
	ui._on_picker_chip("tier", 0)
	ui._on_picker_shown(false)
	ui._on_picker_confirm()
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
	ui._on_tab_pressed("stats")
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
	ui._on_tab_pressed("stats")
	var it = m.find_target("item", ui._id)
	ui._on_attr_changed((it.tier + 1) % 4, "tier", it.tier)
	_eq(ui._p().tier, (it.tier + 1) % 4, "tier edit")
	# 导出：本栏全部
	ui._on_export_selected(m.BUNDLE_PREFIX.item)
	_check(ui.test_clipboard.begins_with(m.BUNDLE_PREFIX.item), "export item bundle from ui")
	ui._on_export_selected(m.ALL_PREFIX)
	_check(ui.test_clipboard.begins_with(m.ALL_PREFIX), "export all from ui")
	# 键名：非调试 = 只有主键名
	ui.set_kind("character")
	_eq(ui._kind, "character", "back to characters")
	var e = m.make_effect({"set": {"key": "stat_luck", "custom_key": "ck", "text_key": "tk"}})
	_eq(ui._key_info(e), "stat_luck  ·  ck  ·  tk", "all keys, no file")
	ui.queue_free()
	yield(tree, "idle_frame")


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
	ui._on_tab_pressed("stats")
	ui._on_attr_changed(2, "tier", -999)
	_eq(m.find_target("item", iid).tier, 2, "custom item tier live")
	ui._on_delete_custom()
	ui._modals[-1].ok_button.emit_signal("pressed")
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
	ui._on_tab_pressed("stats")
	_check(ui._aspd_label != null and ui._aspd_label.text != "", "attack speed shown")
	ui._on_delete_custom()
	ui._modals[-1].ok_button.emit_signal("pressed")
	_check(not m.weapon_families.has(wid), "custom weapon deleted from ui")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_153_weapon_attack_type() -> void:
	var ui = yield(_open_ui(CH), "completed")
	ui.set_kind("weapon")
	var fam = _family_from(0, 0)
	ui._select(fam[0].my_id)
	ui._on_tab_pressed("stats")
	var sweep = 1 - int(fam[0].stats.attack_type)
	ui._on_wstat_changed(sweep, ["attack_type", "int", ""])
	_eq(ui._p().wstats.get("attack_type"), sweep, "attack type toggled")
	ui._on_wstat_changed(-30.0, ["speed_percent_modifier", "int", ""])
	_eq(ui._p().wstats.get("speed_percent_modifier"), -30, "enemy speed on hit keeps the vanilla sign")
	m.apply_all()
	_eq(fam[0].stats.attack_type, sweep, "applied")
	ui.queue_free()
	yield(tree, "idle_frame")


func _find_label(n: Node, t: String):
	if n is Label and n.text == t:
		return n
	for c in n.get_children():
		var f = _find_label(c, t)
		if f != null:
			return f
	return null


func test_154_key_names() -> void:
	m.debug = true
	var ui = yield(_open_ui("character_brawler"), "completed")
	ui._on_tab_pressed("effects")
	var l = null
	for e in m.find_character("character_brawler").effects:
		if e.key == "EFFECT_WEAPON_CLASS_BONUS":
			l = _find_label(ui._effect_list, ui._key_info(e))
	_check(l != null and not l.can_translate_messages(), "upper-case key label is not auto-translated")
	ui._on_effect_edit(0)
	_check(_find_label(ui._effect_list, ui._key_info(m.make_effect(ui._specs()[0]))) != null, "key shown on the expanded row in key mode")
	ui._on_tab_pressed("overview")
	_check(_tree_has_text(ui._page, "stat_max_hp") or _tree_has_text(ui._page, m.find_character("character_brawler").wanted_tags[0] if not m.find_character("character_brawler").wanted_tags.empty() else "stat_"), "tag keys shown in key mode")
	ui._on_tab_pressed("stats")
	_check(_tree_has_text(ui._page, "materials"), "start state keys shown in key mode")
	m.debug = false
	ui._on_tab_pressed("effects")
	ui._on_effect_edit(0)
	_check(not _tree_has_text(ui._effect_list, "stat_"), "no keys when key mode is off, even expanded")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_155_short_dropdown_fits() -> void:
	var ui = yield(_open_ui(CH), "completed")
	var sel = ui._search_select([["A", "a"], ["B", "b"], ["C", "c"], ["D", "d"], ["E", "e"]], "a")
	ui.add_child(sel)
	sel.open()
	yield(tree, "idle_frame")
	yield(tree, "idle_frame")
	_check(sel._scroll.rect_size.y + 1 >= sel._list.get_combined_minimum_size().y, "short menu shows every row without scrolling")
	_check(not sel._scroll.get_v_scrollbar().visible, "no scrollbar for a short menu")
	sel.close()
	ui.queue_free()
	yield(tree, "idle_frame")


func test_156_name_colors_and_shared_layout() -> void:
	var ui = yield(_open_ui(CH), "completed")
	ui._on_tab_pressed("stats")
	var lbl = ui._name_labels.get("stat_armor")
	_check(lbl != null, "stat name label registered")
	_eq(lbl.get_color("font_color"), ui.C_TEXT, "unchanged stat is white")
	ui._on_stat_changed(4.0, "stat_armor")
	_eq(lbl.get_color("font_color"), ui.C_ACCENT_3, "raised stat is green")
	ui._on_stat_changed(-2.0, "stat_armor")
	_eq(lbl.get_color("font_color"), ui.C_DANGER, "lowered stat is red")
	ui._on_stat_changed(0.0, "stat_armor")
	_eq(lbl.get_color("font_color"), ui.C_TEXT, "back to white")
	# 概览：三栏用同一套组件，预览栏宽度一致
	# 比较排版后的实际宽度（内容可能把最小宽度撑大）；角色选初始武器最多的全能者
	var widths = []
	for kind in ["character", "item", "weapon"]:
		ui.set_kind(kind)
		if kind == "character":
			ui._select("character_well_rounded")
		ui._on_tab_pressed("overview")
		yield(_frames(3), "completed")
		var card = ui._preview_text.get_parent().get_parent().get_parent()
		widths.push_back(card.rect_size.x)
	_check(widths[0] == widths[1] and widths[1] == widths[2], "same preview column width on every tab: " + str(widths))
	_eq(widths[0], float(ui.PREVIEW_WIDTH), "preview column keeps its fixed width")
	ui.set_kind("weapon")
	ui._on_tab_pressed("stats")
	ui._on_wstat_changed(999.0, ["damage", "int", ""])
	_eq(ui._name_labels["damage"].get_color("font_color"), ui.C_ACCENT_3, "weapon stat raised is green")
	ui.queue_free()
	yield(tree, "idle_frame")


# 每栏按自己的页签列表打开属性页 / 效果页：三栏各用各的属性页，效果库只有武器栏多出武器效果
func test_157_stats_and_effects_per_kind() -> void:
	var ui = yield(_open_ui(CH), "completed")
	var lib_sizes = {}
	for kind in m.KINDS:
		ui.set_kind(kind)
		yield(tree, "idle_frame")
		var ids = []
		for t in ui._tab_defs():
			ids.push_back(t[0])
		_check("stats" in ids and "effects" in ids, kind + " has stats and effects tabs")
		ui._on_tab_pressed("stats")
		yield(tree, "idle_frame")
		var names = ui._name_labels
		match kind:
			"character":
				_check(names.has("materials") and names.has("stat_max_hp") and not names.has("value"), "character stats: start state + stat tables")
			"item":
				_check(names.has("value") and names.has("max_nb") and names.has("stat_max_hp") and not names.has("materials"), "item stats: numbers + stat tables, no start state")
			"weapon":
				_check(names.has("value") and names.has("damage") and not names.has("stat_max_hp") and not names.has("materials"), "weapon stats: numbers + weapon stats only")
		ui._on_tab_pressed("effects")
		ui._on_lib_search("")
		yield(tree, "idle_frame")
		lib_sizes[kind] = ui._lib_list.get_child_count()
	_eq(m.library(false).size() < m.library(true).size(), true, "weapon library has weapon effects")
	_check(lib_sizes.character == lib_sizes.item, "characters and items share one library (%d / %d)" % [lib_sizes.character, lib_sizes.item])
	ui.queue_free()
	yield(tree, "idle_frame")


# 弹窗类、确认、全部重置、蓝图分享码、从角色导入初始武器、武器弹窗筛选、预览中的蓝图效果
const NL = "\n"


func test_158_modals_reset_and_blueprint_codes() -> void:
	var ui = yield(_open_ui(CH), "completed")
	ui.test_clipboard = ""
	# 重置单个：确认后才重置；Esc 关闭弹窗
	m.profiles[CH] = m.new_profile()
	m.profiles[CH].stats = {"stat_luck": 4}
	ui._select(CH)
	ui._on_reset_pressed()
	_check(m.profiles.has(CH), "reset asks first")
	var ev = InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	ui._unhandled_input(ev)
	_check(ui._modals.empty() and m.profiles.has(CH) and ui.is_inside_tree(), "Esc closes only the dialog")
	ui._on_reset_pressed()
	ui._modals[-1].ok_button.emit_signal("pressed")
	_check(not m.profiles.has(CH), "reset after confirming")
	# 蓝图：导出 / 导入 / 清空（确认）
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	GE.add_link(g, GE.add_node(g, "wave_start", Vector2.ZERO), GE.add_node(g, "perm_stat", Vector2.ZERO, {"stat": "stat_engineering", "value": 3}))
	GE.add_link(g, GE.add_node(g, "interval", Vector2.ZERO, {"secs": 1}), GE.add_node(g, "add_gold", Vector2.ZERO, {"value": 1}))
	ui._p().graph = g
	ui._on_tab_pressed("blueprint")
	yield(tree, "idle_frame")
	ui.blueprint._on_export()
	_check(ui.test_clipboard.begins_with(m.GRAPH_PREFIX), "blueprint exported as BEB:")
	var code = ui.test_clipboard
	ui.blueprint._on_clear()
	_check(m.profiles[CH].graph != null, "clear asks first")
	ui._modals[-1].ok_button.emit_signal("pressed")
	_eq(m.profiles[CH].graph, null, "cleared after confirming")
	ui.test_clipboard = m.SHARE_PREFIX + "x"
	ui.blueprint._on_import()
	_eq(m.profiles[CH].graph, null, "other codes are not blueprints")
	ui.test_clipboard = code
	ui.blueprint._on_import()
	_eq(GE.paths(m.profiles[CH].graph).size(), 2, "blueprint imported")
	# 预览：蓝图每条路径一行，和其他效果一样（带属性图标）
	ui._on_tab_pressed("overview")
	yield(tree, "idle_frame")
	var lines = []
	for c in ui._preview_text.get_children():
		if c.get("text_descr") != null:
			lines.push_back(c)
	var eng = null
	for l in lines:
		if l.text_descr.bbcode_text.find(NL) < 0 and l.text_descr.bbcode_text.find("3") >= 0 and l.effect_icon.texture != null:
			eng = l
	_check(eng != null, "blueprint path rendered as its own effect line with an icon")
	var multi = false
	for l in lines:
		multi = multi or l.text_descr.bbcode_text.find(NL) >= 0
	_check(not multi, "no multi-line effect block")
	# 从角色导入初始武器
	var other = null
	for c in isvc.characters:
		if c.my_id != CH and c.starting_weapons.size() >= 2:
			other = c
			break
	ui._on_tab_pressed("gear")
	ui._open_char_weapons()
	_eq(ui._modals.size(), 1, "character table opened")
	ui._on_char_weapons_picked(other.my_id, ui._modals[-1])
	var want = []
	for w in other.starting_weapons:
		if not w.my_id in want:
			want.push_back(w.my_id)
	_eq(m.profiles[CH].weapons, want, "starting weapons copied from " + other.my_id)
	_check(ui._modals.empty(), "table closed")
	# 武器弹窗：近 / 远战与来源筛选、重置全部
	ui._open_picker("start_weapons")
	ui._on_picker_chip("type", 1)
	ui._on_picker_chip("src", "vanilla")
	var ok = ui._picker_grid.get_child_count() > 0
	for r in ui._picker_res:
		if ui._picker_shown(r):
			ok = ok and r.type == 1 and ui._source(r) == "vanilla"
	_check(ok, "ranged + vanilla filter")
	ui._on_picker_reset()
	var orig = []
	for w in m.backup_value(m.find_character(CH), "starting_weapons"):
		if not w.my_id in orig:
			orig.push_back(w.my_id)
	_eq(ui._picker_sel, orig, "reset all = original starting weapons")
	ui._close_picker()
	# 全部重置：先勾选内容，再最终确认；只重置自定义内容时保留修改与禁用，编号重新开始
	ui.set_kind("item")
	var it = _plain_item()
	m.item_profiles[it.my_id] = m.new_profile()
	m.item_profiles[it.my_id].price = 99
	m.set_disabled("item", it.my_id, true)
	var iid = m.create_custom_item(it.my_id)
	_check(m.next_id > 1, "numbering advanced")
	ui._fill_left()
	ui._on_reset_kind()
	_check(not ui._reset_parts.disabled.pressed and not ui._reset_parts.edits.pressed and not ui._reset_parts.custom.pressed, "nothing ticked by default")
	ui._modals[-1].ok_button.emit_signal("pressed")
	_eq(ui._modals.size(), 1, "nothing ticked: stays on the first dialog")
	ui._reset_parts.custom.pressed = true
	ui._modals[-1].ok_button.emit_signal("pressed")
	_check(m.find_target("item", iid) != null and ui._modals.size() == 1, "second dialog before anything is reset")
	ui._modals[-1].ok_button.emit_signal("pressed")
	_check(m.find_target("item", iid) == null, "custom items removed")
	_eq(m.next_id, 1, "numbering reset")
	_check(m.item_profiles.has(it.my_id) and m.is_disabled("item", it.my_id), "edits and disabled kept")
	ui._on_reset_kind()
	for k in ui._reset_parts:
		ui._reset_parts[k].pressed = true
	ui._modals[-1].ok_button.emit_signal("pressed")
	ui._modals[-1].ok_button.emit_signal("pressed")
	_check(not m.item_profiles.has(it.my_id) and not m.is_disabled("item", it.my_id), "edits and disabled reset")
	ui.queue_free()
	yield(tree, "idle_frame")


# 修改过的原版武器（有备份但不备份 tier）列表正常；点标签不回到顶部；勾选框各状态同一样式；道具预览的独特 / 限制
func test_159_regressions_090() -> void:
	var fam = _family_from(0, 0)
	m.weapon_families[fam[0].weapon_id] = m.new_family()
	m.weapon_families[fam[0].weapon_id].name = "Renamed family"
	m.apply_all()
	_eq(m.backup_value(fam[1], "tier"), fam[1].tier, "weapon tier read from the resource")
	var ui = yield(_open_ui(CH), "completed")
	ui.set_kind("weapon")
	yield(tree, "idle_frame")
	var ok = ui._char_grid.get_child_count() > 0
	for b in ui._char_grid.get_children():
		ok = ok and b.has_meta("tier") and typeof(b.get_meta("tier")) == TYPE_INT
	_check(ok, "weapon list built with a modified vanilla family")
	# 页面重建（点标签 / 改稀有度等）后滚动位置保持：道具属性页足够长
	ui.set_kind("item")
	var it = _plain_item()
	ui._select(it.my_id)
	ui._on_tab_pressed("stats")
	yield(_frames(3), "completed")
	var sc = null
	var scrolls = []
	_collect_scrolls(ui._page, scrolls)
	for s in scrolls:
		if sc == null and s.get_v_scrollbar().max_value > s.rect_size.y + 300:
			sc = s
	_check(sc != null, "stats page scrolls")
	if sc != null:
		sc.scroll_vertical = 250
		yield(tree, "idle_frame")
		var before = sc.scroll_vertical
		ui._on_attr_changed(2, "tier", it.tier)
		yield(_frames(3), "completed")
		var after = []
		_collect_scrolls(ui._page, after)
		var kept = false
		for s in after:
			kept = kept or (s.scroll_vertical == before and s != sc)
		_check(before > 0 and kept, "scroll position kept after the page is rebuilt (%d)" % before)
	# 换到别的页 / 对象时从顶部开始
	ui._on_tab_pressed("overview")
	ui._on_tab_pressed("stats")
	yield(_frames(3), "completed")
	var fresh = []
	_collect_scrolls(ui._page, fresh)
	var top = true
	for s in fresh:
		top = top and s.scroll_vertical == 0
	_check(top, "another page starts at the top")
	# 独特 / 限制
	_eq(ui._limit_text(1), tr("UNIQUE"), "unique")
	_check(ui._limit_text(3).find("3") >= 0 and ui._limit_text(3).find("{") < 0, "limited (3): " + ui._limit_text(3))
	_eq(ui._limit_text(-1), "", "no limit")
	# 勾选框
	var cb = ui._checkbox("x", ui.FONT_SMALL)
	_check(cb.get_stylebox("hover") == cb.get_stylebox("normal"), "checkbox hover keeps the same margins")
	_eq(cb.get_color("font_color"), ui.C_TEXT, "checkbox text white")
	var red = ui._checkbox("x", ui.FONT_SMALL, ui.C_DANGER)
	_eq([red.get_color("font_color_hover"), red.get_color("font_color_hover_pressed")], [ui.C_DANGER, ui.C_DANGER], "reset options turn red on hover")
	red.free()
	cb.free()
	ui.queue_free()
	yield(tree, "idle_frame")


func _collect_scrolls(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.push_back(c)
		_collect_scrolls(c, out)


# 列表排序：本模组新增的在最前；道具按稀有度再按英文名，不随语言变化；从角色导入的弹窗不超宽、有返回
func test_160_sort_and_char_weapons_popup() -> void:
	var iid = m.create_custom_item(_plain_item().my_id, "sorttest")
	var ui = yield(_open_ui(CH), "completed")
	ui.set_kind("item")
	var orders = []
	for loc in ["en", "zh"]:
		TranslationServer.set_locale(loc)
		ui._refresh_char_list()
		var ids = []
		for b in ui._char_grid.get_children():
			ids.push_back(b.get_meta("id"))
		orders.push_back(ids)
	TranslationServer.set_locale("en")
	_eq(orders[0][0], iid, "custom item first")
	_check(orders[0] == orders[1], "order does not depend on the language")
	var ok = true
	for i in range(2, orders[0].size()):
		var a = m.find_target("item", orders[0][i - 1])
		var b = m.find_target("item", orders[0][i])
		ok = ok and (a.tier < b.tier or (a.tier == b.tier and ui._en_name(a) <= ui._en_name(b)))
	_check(ok, "tier, then English name")
	# 角色列表：原版顺序
	ui.set_kind("character")
	var cids = []
	for b in ui._char_grid.get_children():
		cids.push_back(b.get_meta("id"))
	var natives = []
	for c in isvc.characters:
		if not m.is_custom(c.my_id):
			natives.push_back(c.my_id)
	_eq(cids, natives, "characters in vanilla order")
	# 从角色导入：不超宽，右上角返回
	ui._on_tab_pressed("gear")
	ui._open_char_weapons()
	yield(_frames(3), "completed")
	var md = ui._modals[-1]
	var panel = md.get_child(1).get_child(0)
	_check(panel.rect_size.x <= 1240 + 1, "popup keeps its width (%d)" % panel.rect_size.x)
	var back = md.head.get_child(md.head.get_child_count() - 1)
	back.emit_signal("pressed")
	_check(ui._modals.empty(), "back closes the popup")
	ui.queue_free()
	yield(tree, "idle_frame")
