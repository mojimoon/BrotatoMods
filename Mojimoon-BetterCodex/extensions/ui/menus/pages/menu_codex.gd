extends "res://ui/menus/pages/menu_codex.gd"

# 图鉴：道具 / 武器列表上方加搜索与筛选、元素上加角标；详情下方加附加区块（ui/extras.gd）；武器属性里的冷却改为实际冷却。
# 筛选掉的元素从 Inventory 中移出（保留实例），排序 / 手柄焦点只作用于显示的元素。
# 本脚本在 mod _init 时安装：不在类级别 preload，不对 autoload 表达式用 := 推断。

const BC_DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"
const BC_SET_ABBR = {"new_dawn": "ND", "paws_n_claws": "PC", "abyssal_terrors": "DLC1", "primal_dread": "DLC2"}
const BC_SET_COLORS = {"new_dawn": "#c99a2e", "paws_n_claws": "#c4505f", "abyssal_terrors": "#b75cff", "primal_dread": "#6f9a12"}
const BC_EVO_ICONS = {"meca": "res://items/consumables/meca_parts/meca_parts.png", "mutant": "res://items/consumables/mutation_fruit/mutation_fruit.png"}
const BC_SPECIALS = ["fossil", "meca", "mutant"]

var _bc_tabs = {}	# "items" / "weapons" -> {inv, desc, all, current, extras, f（筛选值）, ui（控件）}
var _bc_origin = {}	# my_id_hash -> [物品套组 id, DLC2 进化路线 "" / meca / mutant / both]
var _bc_temp = null	# 临时筛选 {"title", "ids"}
var _bc_badge_font = null


func _bc_mod():
	return get_node_or_null("/root/ModLoader/Mojimoon-BetterCodex")


func _pop():
	_bc_free_detached()
	_bc_temp = null
	._pop()
	_bc_setup()


func _exit_tree():
	_bc_free_detached()


func _bc_free_detached() -> void:
	for t in _bc_tabs.values():
		for e in t.all:
			if is_instance_valid(e) and e.get_parent() == null:
				e.free()
		t.all = []


func _bc_setup() -> void:
	if _bc_tabs.empty():
		_bc_badge_font = load("res://resources/fonts/actual/base/font_26_outline.tres").duplicate()
		_bc_badge_font.size = 18
		_bc_build_tab("items", inventory_items, $"%codex_item_description")
		_bc_build_tab("weapons", inventory_weapons, $"%codex_weapon_description")
	_bc_build_origin()
	for tab in _bc_tabs:
		var t = _bc_tabs[tab]
		t.all = t.inv.get_children()
		t.current = null
		t.extras.reset_defaults()
		t.extras.show_item(null)
		for e in t.all:
			_bc_add_badges(e, tab)
		_bc_reset_filters(tab)
		_bc_fill_options(tab)
	_bc_apply_all()


func _bc_build_origin() -> void:
	_bc_origin = {}
	for ud in ItemService.update_data_list:
		if ud == null or ud.item_set == null:
			continue
		for x in ud.item_set.items + ud.item_set.weapons:
			_bc_origin[x.my_id_hash] = [ud.id, ""]
		var evo = {"meca_items": "meca", "mutant_items": "mutant", "evolution_items": "both"}
		for field in evo:
			if field in ud.item_set:
				for x in ud.item_set.get(field):
					_bc_origin[x.my_id_hash] = [ud.id, evo[field]]


func _bc_set_of(it) -> String:
	return _bc_origin[it.my_id_hash][0] if _bc_origin.has(it.my_id_hash) else "base"


func _bc_evo_of(it) -> String:
	return _bc_origin[it.my_id_hash][1] if _bc_origin.has(it.my_id_hash) else ""


static func _bc_set_name(id: String) -> String:
	if id == "base":
		return TranslationServer.translate("BC_BASE_GAME")
	return TranslationServer.translate("ITEM_SET_" + id.to_upper())


# ---- 筛选栏 ----

func _bc_build_tab(tab: String, inv, desc) -> void:
	var extras = load(BC_DIR + "ui/extras.gd").new()
	desc.get_effects().get_parent().add_child(extras)	# 紧接在效果列表后面
	extras.connect("tag_pressed", self, "bc_filter_tag")
	extras.connect("set_pressed", self, "_bc_filter_set")
	extras.connect("item_pressed", self, "bc_focus_item", ["items"])
	extras.connect("display_changed", self, "_bc_redisplay", [tab])
	var t = {"inv": inv, "desc": desc, "all": [], "current": null, "extras": extras, "f": {}, "ui": {}}
	_bc_tabs[tab] = t

	var column = inv.get_parent().get_parent()	# VBoxContainer2：排序行 / 分隔线 / 列表
	var bar = VBoxContainer.new()
	bar.name = "BCFilterBar"
	bar.theme = load("res://resources/themes/verysmall_option_button_theme.tres")
	bar.add_constant_override("separation", 6)
	var row1 = HBoxContainer.new()
	var search = LineEdit.new()
	search.placeholder_text = tr("BC_SEARCH")
	search.clear_button_enabled = true
	search.size_flags_horizontal = SIZE_EXPAND_FILL
	search.connect("text_changed", self, "_bc_on_search", [tab])
	row1.add_child(search)
	var clear = Button.new()
	clear.text = tr("BC_CLEAR")
	clear.connect("pressed", self, "_bc_on_clear", [tab])
	row1.add_child(clear)
	var badges = Button.new()
	badges.text = tr("BC_BADGES")
	badges.toggle_mode = true
	badges.pressed = _bc_badges_on()
	badges.connect("toggled", self, "_bc_on_badges")
	row1.add_child(badges)
	bar.add_child(row1)

	var row2 = HBoxContainer.new()
	var keys = ["tier", "tag", "source", "special"] if tab == "items" else ["tier", "type", "class", "source"]
	for key in keys:
		var ob = OptionButton.new()
		ob.size_flags_horizontal = SIZE_EXPAND_FILL
		ob.clip_text = true
		ob.connect("item_selected", self, "_bc_on_option", [tab, key])
		row2.add_child(ob)
		t.ui[key] = ob
	bar.add_child(row2)

	var row3 = HBoxContainer.new()
	row3.visible = false
	var temp_label = Label.new()
	temp_label.size_flags_horizontal = SIZE_EXPAND_FILL
	temp_label.clip_text = true
	temp_label.add_color_override("font_color", Color("#facc15"))
	row3.add_child(temp_label)
	var temp_clear = Button.new()
	temp_clear.text = "X"
	temp_clear.connect("pressed", self, "_bc_clear_temp")
	row3.add_child(temp_clear)
	bar.add_child(row3)

	t.ui.search = search
	t.ui.badges = badges
	t.ui.temp_row = row3
	t.ui.temp_label = temp_label
	var font = load("res://resources/fonts/actual/base/font_22.tres")
	temp_label.add_font_override("font", font)
	for b in [clear, badges, temp_clear]:
		b.add_font_override("font", font)
	column.add_child(bar)
	column.move_child(bar, 1)


func _bc_reset_filters(tab: String) -> void:
	var t = _bc_tabs[tab]
	t.f = {"text": "", "tier": -1, "tag": "", "source": "", "special": "", "type": -1, "class": ""}
	t.ui.search.text = ""


func _bc_fill_options(tab: String) -> void:
	var t = _bc_tabs[tab]
	var opts = {"tier": [[-1, tr("BC_TIER")]]}
	for i in 4:
		opts.tier.push_back([i, ["T1", "T2", "T3", "T4"][i]])
	var sources = []
	var tags = []
	var classes = {}
	for e in t.all:
		var it = e.item
		if it == null:
			continue
		var s = _bc_set_of(it)
		if not sources.has(s):
			sources.push_back(s)
		if tab == "items":
			for tag in it.tags:
				if not tags.has(tag):
					tags.push_back(tag)
		else:
			for set in it.sets:
				classes[set.my_id] = tr(set.name)
	opts.source = [["", tr("BC_SOURCE")]]
	for s in ["base"] + BC_SET_ABBR.keys():
		if sources.has(s):
			opts.source.push_back([s, _bc_set_name(s)])
	if tab == "items":
		var Extras = load(BC_DIR + "ui/extras.gd")
		var named = []
		for tag in tags:
			named.push_back([tag, Extras.tag_name(tag)])
		named.sort_custom(self, "_bc_by_label")
		opts.tag = [["", tr("BC_TAG")]] + named
		opts.special = [["", tr("BC_SPECIAL")], ["fossil", tr("BC_FOSSIL")], ["meca", tr("MECA_ITEMS")], ["mutant", tr("MUTANT_ITEMS")]]
	else:
		opts.type = [[-1, tr("BC_TYPE")], [WeaponData.Type.MELEE, tr("BC_MELEE")], [WeaponData.Type.RANGED, tr("BC_RANGED")]]
		var named = []
		for id in classes:
			named.push_back([id, classes[id]])
		named.sort_custom(self, "_bc_by_label")
		opts["class"] = [["", tr("BC_CLASS")]] + named
	for key in t.ui:
		if not t.ui[key] is OptionButton:
			continue
		var ob = t.ui[key]
		ob.clear()
		for o in opts[key]:
			ob.add_item(o[1])
			ob.set_item_metadata(ob.get_item_count() - 1, o[0])
		_bc_select_option(ob, t.f[key])


func _bc_by_label(a, b) -> bool:
	return a[1] < b[1]


func _bc_select_option(ob: OptionButton, value) -> void:
	for i in ob.get_item_count():
		if typeof(ob.get_item_metadata(i)) == typeof(value) and ob.get_item_metadata(i) == value:
			ob.select(i)
			return
	ob.select(0)


func _bc_on_search(text: String, tab: String) -> void:
	_bc_tabs[tab].f.text = text.strip_edges().to_lower()
	_bc_apply(tab)


func _bc_on_option(index: int, tab: String, key: String) -> void:
	_bc_tabs[tab].f[key] = _bc_tabs[tab].ui[key].get_item_metadata(index)
	_bc_apply(tab)


func _bc_on_clear(tab: String) -> void:
	if tab == "items":
		_bc_temp = null
	_bc_reset_filters(tab)
	for key in _bc_tabs[tab].ui:
		if _bc_tabs[tab].ui[key] is OptionButton:
			_bc_select_option(_bc_tabs[tab].ui[key], _bc_tabs[tab].f[key])
	_bc_apply(tab)


func _bc_clear_temp() -> void:
	_bc_temp = null
	_bc_apply("items")


func _bc_match(tab: String, it) -> bool:
	if it == null:
		return true
	var f = _bc_tabs[tab].f
	if tab == "items" and _bc_temp != null and not _bc_temp.ids.has(it.my_id_hash):
		return false
	if f.text != "" and tr(it.name).to_lower().find(f.text) < 0 and it.my_id.find(f.text) < 0:
		return false
	if f.tier >= 0 and it.tier != f.tier:
		return false
	if f.source != "" and _bc_set_of(it) != f.source:
		return false
	if tab == "items":
		if f.tag != "" and not it.tags.has(f.tag):
			return false
		if f.special == "fossil" and not it.my_id.begins_with("item_fossil_"):
			return false
		if f.special in ["meca", "mutant"] and not _bc_evo_of(it) in [f.special, "both"]:
			return false
	else:
		if f.type >= 0 and it.type != f.type:
			return false
		if f["class"] != "":
			var found = false
			for s in it.sets:
				found = found or s.my_id == f["class"]
			if not found:
				return false
	return true


func _bc_apply_all() -> void:
	for tab in _bc_tabs:
		_bc_apply(tab)


func _bc_apply(tab: String) -> void:
	var t = _bc_tabs[tab]
	var inv = t.inv
	for c in inv.get_children():
		inv.remove_child(c)
	for e in t.all:
		if is_instance_valid(e) and _bc_match(tab, e.item):
			inv.add_child(e)
	inv.emit_signal("need_to_sort_inventory")
	inv.queue_set_focus_neighbours()
	if tab == "items":
		t.ui.temp_row.visible = _bc_temp != null
		if _bc_temp != null:
			t.ui.temp_label.text = "%s: %s" % [tr("BC_TEMP_FILTER"), _bc_temp.title]


# ---- 角标 ----

func _bc_badges_on() -> bool:
	var m = _bc_mod()
	return m == null or m.settings.get("badges", true)


func _bc_on_badges(on: bool) -> void:
	var m = _bc_mod()
	if m != null:
		m.settings.badges = on
		m.save_settings()
	for t in _bc_tabs.values():
		if t.ui.badges.pressed != on:
			t.ui.badges.pressed = on
		for e in t.all:
			if is_instance_valid(e) and e.has_node("BCBadges"):
				e.get_node("BCBadges").visible = on


func _bc_badge_label(text: String, color: Color, align: int, valign: int) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", _bc_badge_font)
	l.add_color_override("font_color", color)
	l.align = align
	l.valign = valign
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.set_anchors_and_margins_preset(PRESET_WIDE)
	l.margin_left = 5
	l.margin_right = -5
	l.margin_top = 2
	l.margin_bottom = -2
	return l


func _bc_add_badges(e, tab: String) -> void:
	var it = e.item
	if it == null or it.is_locked or it._is_silhouette_in_codex() or e.has_node("BCBadges"):
		return
	var root = Control.new()
	root.name = "BCBadges"
	root.mouse_filter = MOUSE_FILTER_IGNORE
	root.set_anchors_and_margins_preset(PRESET_WIDE)
	var Extras = load(BC_DIR + "ui/extras.gd")
	if Extras.has_price(it):
		root.add_child(_bc_badge_label(str(it.value), Color("#ffd75e"), Label.ALIGN_LEFT, Label.VALIGN_TOP))
	if tab == "items" and it.max_nb > 0:
		root.add_child(_bc_badge_label(str(it.max_nb), Color("#ff6b6b") if it.max_nb == 1 else Color("#ffa94d"), Label.ALIGN_RIGHT, Label.VALIGN_TOP))
	var evo = _bc_evo_of(it)
	if evo != "":
		var box = HBoxContainer.new()
		box.mouse_filter = MOUSE_FILTER_IGNORE
		box.add_constant_override("separation", 0)
		box.set_anchors_and_margins_preset(PRESET_BOTTOM_LEFT)
		box.margin_top = -24
		box.margin_left = 3
		for k in (["mutant", "meca"] if evo == "both" else [evo]):
			if ResourceLoader.exists(BC_EVO_ICONS[k]):
				var icon = TextureRect.new()
				icon.texture = load(BC_EVO_ICONS[k])
				icon.expand = true
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.rect_min_size = Vector2(22, 22)
				icon.mouse_filter = MOUSE_FILTER_IGNORE
				box.add_child(icon)
		root.add_child(box)
	else:
		var s = _bc_set_of(it)
		if BC_SET_ABBR.has(s):
			root.add_child(_bc_badge_label(BC_SET_ABBR[s], Color(BC_SET_COLORS[s]).lightened(0.25), Label.ALIGN_LEFT, Label.VALIGN_BOTTOM))
	root.visible = _bc_badges_on()
	e.add_child(root)


# ---- 详情 ----

func _on_InventoryItems_element_pressed(element: InventoryElement):
	._on_InventoryItems_element_pressed(element)
	_bc_select("items", _bc_visible_item(element.item))


func _on_InventoryWeapons_element_pressed(element: InventoryElement):
	._on_InventoryWeapons_element_pressed(element)
	# 等级按钮原本直接连到描述的 set_item：改连到这里，才能套用诅咒 / 机械化与附加区块
	var desc = $"%codex_weapon_description"
	for b in [but_tier0, but_tier1, but_tier2, but_tier3]:
		if b.is_connected("pressed", self, "_bc_select_tier"):
			b.disconnect("pressed", self, "_bc_select_tier")
		for c in b.get_signal_connection_list("pressed"):
			if c.target == desc and c.method == "set_item":
				b.disconnect("pressed", desc, "set_item")
				b.connect("pressed", self, "_bc_select_tier", [c.binds[0]])
	_bc_select("weapons", _bc_visible_item(element.item))


# 未解锁或图鉴描述未解锁（买得不够多）的物品不显示附加区块，与原版图鉴一致
static func _bc_visible_item(it):
	return null if it == null or it.is_locked or it._is_locked_in_codex() else it


func _bc_select_tier(w) -> void:
	$"%codex_weapon_description".set_item(w, 0)
	_bc_select("weapons", _bc_visible_item(w))


func _bc_select(tab: String, it) -> void:
	if not _bc_tabs.has(tab):
		return
	var t = _bc_tabs[tab]
	t.current = it
	t.extras.show_item(it)
	_bc_redisplay(tab, false)


# 诅咒 / 机械化后的描述 + 实际冷却
func _bc_redisplay(tab: String, reset: bool = true) -> void:
	var t = _bc_tabs[tab]
	if t.current == null:
		return
	var shown = t.extras.display_item(t.current)
	if reset or shown != t.current:
		t.desc.set_item(shown, 0)
	if shown is WeaponData:
		_bc_fix_cooldown(t.desc, shown)


# 武器属性里的冷却（游戏 tooltip 算法）替换为实际平均冷却；ImprovedTooltips 已替换过时找不到原文，保持不动
func _bc_fix_cooldown(desc, w) -> void:
	var label = desc.get_weapon_stats()
	if label == null or not label.visible:
		return
	var Calc = load(BC_DIR + "calc.gd")
	var args = WeaponServiceInitStatsArgs.new()
	args.sets = w.sets
	args.effects = w.effects
	var cur
	if w.type == WeaponData.Type.MELEE:
		cur = WeaponService.init_melee_stats(w.stats, 0, args)
	else:
		cur = WeaponService.init_ranged_stats(w.stats, 0, false, args)
	var in_run = load(BC_DIR + "ui/extras.gd").scene_in_run(get_tree())
	var count = int(clamp(RunData.get_player_weapons_ref(0).size(), 1, 6)) if in_run else Calc.DEFAULT_WEAPON_COUNT
	var atk = (Utils.get_stat(Keys.stat_attack_speed_hash, 0) + cur.attack_speed_mod) / 100.0
	var timing = Calc.timing(w.stats, atk, Utils.get_stat(Keys.stat_range_hash, 0), count)
	var text = label.bbcode_text
	var from = max(0, text.find(tr("COOLDOWN")))
	var at = text.find(Calc.cooldown_str(cur.get_cooldown_value(0, 1.0)), from)
	if at >= 0:
		var old = Calc.cooldown_str(cur.get_cooldown_value(0, 1.0))
		text = text.substr(0, at) + Calc.actual_str(timing.avg) + text.substr(at + old.length())
		from = at + 1
	if timing.shots > 0:
		var old_r = Calc.cooldown_str(cur.get_cooldown_value(0, cur.additional_cooldown_multiplier))
		var at_r = text.find(old_r, from)
		if at_r >= 0:
			text = text.substr(0, at_r) + Calc.actual_str(timing.reload) + text.substr(at_r + old_r.length())
	label.bbcode_text = text


# 进度条按全部元素计算（筛选会改变 Inventory 的子节点数）
func _on_but_tab_items_pressed():
	if _bc_tabs.has("items") and _bc_tabs.items.all.size() > 0:
		_update_progress_bar(float(unlocked_items) / _bc_tabs.items.all.size())
	else:
		._on_but_tab_items_pressed()


func _on_but_tab_weapons_pressed():
	if _bc_tabs.has("weapons") and _bc_tabs.weapons.all.size() > 0:
		_update_progress_bar(float(unlocked_weapons) / _bc_tabs.weapons.all.size())
	else:
		._on_but_tab_weapons_pressed()


# ---- 外部入口（标签 / 关联 / 禁用道具）----

func bc_show_tab(tab: String) -> void:
	$"root/BetterTabContainer"._change_tab(1 if tab == "items" else 2)


func bc_filter_tag(tag: String) -> void:
	bc_show_tab("items")
	_bc_temp = null
	_bc_reset_filters("items")
	_bc_tabs.items.f.tag = tag
	_bc_fill_options("items")
	_bc_apply("items")
	_bc_focus_first("items")


func _bc_filter_set(set_id: String) -> void:
	_bc_reset_filters("weapons")
	_bc_tabs.weapons.f["class"] = set_id
	_bc_fill_options("weapons")
	_bc_apply("weapons")
	_bc_focus_first("weapons")


# 临时筛选：只显示 items（如角色的禁用道具），select = 要选中的道具
func bc_temp_filter(title: String, items: Array, select = null) -> void:
	bc_show_tab("items")
	_bc_reset_filters("items")
	_bc_fill_options("items")
	var ids = []
	for it in items:
		ids.push_back(it.my_id_hash)
	_bc_temp = {"title": title, "ids": ids}
	_bc_apply("items")
	if select != null:
		bc_focus_item(select, "items")
	else:
		_bc_focus_first("items")


func bc_focus_item(it, tab: String) -> void:
	bc_show_tab(tab)
	var e = _bc_find(tab, it)
	if e == null:
		_bc_on_clear(tab)
		e = _bc_find(tab, it)
	if e != null:
		_bc_tabs[tab].inv.on_element_focused(e)
		e.call_deferred("grab_focus")


# 武器按家族（weapon_id）找，列表里只有最低等级
func _bc_find(tab: String, it):
	for e in _bc_tabs[tab].inv.get_children():
		if e.item == null:
			continue
		if e.item.my_id_hash == it.my_id_hash or (it is WeaponData and e.item.weapon_id_hash == it.weapon_id_hash):
			return e
	return null


# 商店里打开：定位到该物品（武器定位到对应等级）；已有的诅咒 / 机械化物品预设为其实际强度
func bc_open_item(it) -> void:
	var tab = "weapons" if it is WeaponData else "items"
	var x = _bc_tabs[tab].extras
	if it.is_cursed:
		x.curse_on = true
		x.curse_pct = int(clamp(round(it.curse_factor * 100.0), 10, 110))
	if it is WeaponData and it.is_meca:
		x.meca_on = true
		x.meca_power = int(clamp(it.meca_power, 1, x.MECA_MAX))
	bc_focus_item(it, tab)
	if it is WeaponData:
		var w = ItemService.get_base_weapon(it.my_id_hash)
		if w != null and w.previous_upgrade != null:
			call_deferred("_bc_select_tier", w)


func _bc_focus_first(tab: String) -> void:
	var inv = _bc_tabs[tab].inv
	if inv.get_child_count() > 0:
		inv.on_element_focused(inv.get_child(0))
