extends "res://ui/menus/pages/menu_codex.gd"

# 图鉴：道具 / 武器列表上方加搜索与筛选、元素上加角标；详情下方加附加区块（ui/extras.gd）；武器属性里的冷却改为实际冷却。
# 筛选掉的元素从 Inventory 中移出（保留实例），排序 / 手柄焦点只作用于显示的元素。
# 本脚本在 mod _init 时安装：不在类级别 preload，不对 autoload 表达式用 := 推断。

const BC_DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"
const BC_SET_ORDER = ["base", "new_dawn", "paws_n_claws", "abyssal_terrors", "primal_dread"]
const BC_EVO_ICONS = {"meca": "res://items/consumables/meca_parts/meca_parts.png", "mutant": "res://items/consumables/mutation_fruit/mutation_fruit.png"}
const BC_SPECIALS = ["fossil", "meca", "mutant"]

var _bc_tabs = {}	# "items" / "weapons" -> {inv, desc, all, current, extras, f（筛选值）, ui（控件）}
var _bc_origin = {}	# my_id_hash -> [物品套组 id, DLC2 进化路线 "" / meca / mutant / both]
var _bc_temp = null	# 临时筛选 {"title", "ids"}
var _bc_extras_script = null
var _bc_icon_script = null
var _bc_updates = {}	# 物品套组 id -> UpdateData（图标 + 颜色）
var bc_player := 0	# 局内显示哪个玩家的数值：商店里由 shop_hook 设为操作的玩家，暂停菜单里取菜单当前显示的玩家


func _bc_mod():
	return get_node_or_null("/root/ModLoader/Mojimoon-BetterCodex")


func _bc_setting(key: String, default = true):
	var m = _bc_mod()
	return m.settings.get(key, default) if m != null else default


func _pop():
	_bc_temp = null
	var pause = find_parent("PauseMenu")
	if pause != null and "_main_menu" in pause:
		bc_player = pause._main_menu.player_index
	if bc_player >= RunData.players_data.size():
		bc_player = 0
	for tab in _bc_tabs:
		_bc_tabs[tab].extras.player = bc_player
	var sig = _bc_signature()
	if not _bc_tabs.empty() and sig == _bc_last_signature:
		_bc_unlock_begin()
		_bc_reopen()
		_bc_unlock_end()
	else:
		_bc_free_detached()
		_bc_unlock_begin()
		._pop()
		_bc_setup()
		_bc_unlock_end()
		_bc_last_signature = sig
		for tab in _bc_tabs:
			_bc_apply_bar_font(_bc_tabs[tab])
		if _bc_settings_popup != null:	# 设置弹窗按新的字体大小重建
			_bc_settings_popup.queue_free()
			_bc_settings_popup = null
		_bc_challenge_signature = _bc_csig()
		_bc_enemy_signature = _bc_esig()
	_bc_count_progress()
	_bc_skip_animation()	# 总是快速打开（跳过开场动画）


# ---- 快速重开：道具 / 武器列表的内容没变时不重建（原版每次打开都重建全部元素，再加上角标、筛选，是打开慢的主要原因）----

var _bc_last_signature = null
const BC_PREWARM_DELAY = 1.0


# 预先构建：图鉴进树约 1 秒后在后台做一次完整构建（同一帧里打开再隐藏：不绘制、不播放动画与音效，焦点还原），
# 之后第一次打开就走快速重开。战斗中（Main 场景）不做，避免卡顿。
func _ready() -> void:
	var scene = get_tree().current_scene
	if scene != null and scene.name == "Main":
		return
	get_tree().create_timer(BC_PREWARM_DELAY + randf()).connect("timeout", self, "bc_prewarm")	# 错开同一场景里的多个图鉴


func bc_prewarm() -> void:
	if not is_inside_tree() or visible or (not _bc_tabs.empty() and _bc_signature() == _bc_last_signature):
		return
	var focus = get_focus_owner()
	var popup_before = Utils._popup if RunData.is_coop_run else null
	_pop()
	animation_tree.active = false
	hide()
	if RunData.is_coop_run:
		Utils._popup = popup_before
	elif is_instance_valid(focus):
		focus.grab_focus()
	_bc_restore_locks()
var _bc_challenge_signature = null
var _bc_enemy_signature = null


func _bc_csig() -> Array:
	return [ChallengeService.challenges.size(), ProgressData.challenges_completed.size(), TranslationServer.get_locale()]


func _bc_esig() -> Array:
	return [ItemService.entities.size(), _bc_sum(ProgressData.killed_enemies), _bc_sum(ProgressData.killed_by_enemies), TranslationServer.get_locale()]


static func _bc_sum(d: Dictionary) -> int:
	var n = 0
	for v in d.values():
		n += v
	return n


# 决定列表内容的状态：物品集合、解锁、获得次数（图鉴描述是否解锁）、解锁全部、语言
func _bc_signature() -> Array:
	var bought = 0
	for v in ProgressData.items_bought.values():
		bought += v
	return [ItemService.items.size(), ItemService.weapons.size(), ProgressData.items_unlocked.size(), ProgressData.weapons_unlocked.size(),
		ProgressData.items_bought.size(), bought, _bc_setting("unlock_all", false), TranslationServer.get_locale(), str(ProgressData.active_update_data), ProgressData.settings.get("font_size", 1.0)]


# 原版 _pop 去掉道具 / 武器列表的重建（敌人列表的击杀数会变，照原版重建）
func _bc_reopen() -> void:
	unlocked_entities = 0
	focus_before_created = get_focus_owner()
	popup()
	if RunData.is_coop_run:
		Utils._popup = self
	animation_tree.set("parameters/conditions/finish", false)
	animation_tree.active = true
	var csig = _bc_csig()
	if csig != _bc_challenge_signature:	# 挑战列表也很慢：没有新完成的挑战就不重建
		tab_challenge.set_elements(true)
		_bc_challenge_signature = csig
	lb_texture.player_index = player_index
	rb_texture.player_index = player_index
	_focus_control($"%but_tab_challenger")
	for item in ItemService.items:
		item.is_locked = not ProgressData.items_unlocked.has(item.my_id_hash)
	for weapon in ItemService.weapons:
		weapon.is_locked = not ProgressData.weapons_unlocked.has(weapon.weapon_id_hash)
	var list_of_entities: Array = ItemService.entities.duplicate()
	var list_of_entities_id: Array = []
	for entity in list_of_entities:
		if entity._get_how_many_killed() > 0:
			unlocked_entities += 1
		if list_of_entities_id.has(entity.my_id_hash):
			list_of_entities.erase(entity)
		else:
			list_of_entities_id.append(entity.my_id_hash)
	var esig = _bc_esig()
	if esig != _bc_enemy_signature:	# 击杀数没变就不重建敌人列表
		inventory_enemies.set_elements(list_of_entities)
		_bc_enemy_signature = esig
	inventory_enemies.on_element_focused(inventory_enemies.get_child(0))
	_unlockall_icon.visible = ProgressData.is_unlock_all_save()
	for tab in _bc_tabs:
		var t = _bc_tabs[tab]
		t.current = null
		t.extras.reset_defaults()
		t.extras.show_item(null)
		_bc_grey_banned(tab)
		_bc_reset_filters(tab)
		_bc_fill_options(tab)
	_bc_apply_all()
	for tab in _bc_tabs:
		if _bc_tabs[tab].inv.get_child_count() > 0:
			_bc_tabs[tab].inv.on_element_focused(_bc_tabs[tab].inv.get_child(0))


# 进度按真实存档计算（解锁全部时图鉴里看到的是临时数据）
func _bc_count_progress() -> void:
	unlocked_items = 0
	unlocked_weapons = 0
	for e in _bc_tabs.items.all:
		if e.item != null and ProgressData.items_bought.has(e.item.my_id_hash):
			unlocked_items += 1
	for e in _bc_tabs.weapons.all:
		if e.item != null and ProgressData.items_bought.has(e.item.my_id_hash):
			unlocked_weapons += 1


# 边框贴图（画在内容上面）上的涂鸦有一部分伸进内容区：把贴图里内容区范围内的像素清掉
const BC_CONTENT_RECT = Rect2(247, 201, 1426, 750)	# BetterTabContainer 在 1920×1080 贴图中的位置
var _bc_frame_cleaned := false


func _bc_clean_frame() -> void:
	if _bc_frame_cleaned:
		return
	_bc_frame_cleaned = true
	var shelf = $root/shelf
	if shelf.texture == null:
		return
	var img = shelf.texture.get_data()
	if img == null or img.get_size() != Vector2(1920, 1080):
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var clear = Image.new()
	clear.create(int(BC_CONTENT_RECT.size.x), int(BC_CONTENT_RECT.size.y), false, Image.FORMAT_RGBA8)
	img.blit_rect(clear, Rect2(Vector2.ZERO, BC_CONTENT_RECT.size), BC_CONTENT_RECT.position)
	var tex = ImageTexture.new()
	tex.create_from_image(img, shelf.texture.flags)
	shelf.texture = tex


func _exit_tree():
	_bc_free_detached()
	_bc_restore_locks()


# 快速打开：跳过开场动画，直接设为动画结束时的状态
func _bc_skip_animation() -> void:
	animation_tree.active = false
	$root.rect_position = Vector2.ZERO
	$root.rect_scale = Vector2.ONE
	$Cache.self_modulate = Color.white
	$root/shelf/cable.rect_scale = Vector2.ONE
	$root/shelf/cable.rect_rotation = 0.0
	$root/BetterTabContainer.modulate = Color.white


func _on_BackButton_pressed() -> void:
	_bc_restore_locks()
	emit_signal("codex_closed")
	animation_tree.active = false
	if is_instance_valid(focus_before_created):
		_focus_control(focus_before_created)
	hide()
	if RunData.is_coop_run:
		Utils._popup = null


# ---- 解锁全部图鉴（不修改存档）：只在图鉴读取解锁状态的调用期间临时替换 ProgressData 的列表 ----

var _bc_saved_progress = null
var _bc_unlock_depth := 0	# 可嵌套：只在最外层替换 / 恢复


func _bc_unlock_begin() -> void:
	_bc_unlock_depth += 1
	if _bc_unlock_depth > 1 or not _bc_setting("unlock_all", false):
		return
	_bc_saved_progress = [ProgressData.items_unlocked, ProgressData.weapons_unlocked, ProgressData.items_bought]
	var items = []
	var weapons = []
	var bought = ProgressData.items_bought.duplicate()
	for it in ItemService.items:
		items.push_back(it.my_id_hash)
		bought[it.my_id_hash] = max(bought.get(it.my_id_hash, 0), it.unlock_codex_descr_after_get_it)
	for w in ItemService.weapons:
		if not weapons.has(w.weapon_id_hash):
			weapons.push_back(w.weapon_id_hash)
		bought[w.my_id_hash] = max(bought.get(w.my_id_hash, 0), w.unlock_codex_descr_after_get_it)
	ProgressData.items_unlocked = items
	ProgressData.weapons_unlocked = weapons
	ProgressData.items_bought = bought


func _bc_unlock_end() -> void:
	_bc_unlock_depth = max(0, _bc_unlock_depth - 1)
	if _bc_unlock_depth > 0 or _bc_saved_progress == null:
		return
	ProgressData.items_unlocked = _bc_saved_progress[0]
	ProgressData.weapons_unlocked = _bc_saved_progress[1]
	ProgressData.items_bought = _bc_saved_progress[2]
	_bc_saved_progress = null


# 图鉴会改资源上的 is_locked（原版每次打开都重算）；解锁全部时关闭后恢复真实值
func _bc_restore_locks() -> void:
	if not _bc_setting("unlock_all", false):
		return
	for it in ItemService.items:
		it.is_locked = not ProgressData.items_unlocked.has(it.my_id_hash)
	for w in ItemService.weapons:
		w.is_locked = not ProgressData.weapons_unlocked.has(w.weapon_id_hash)


func _bc_free_detached() -> void:
	for t in _bc_tabs.values():
		for e in t.all:
			if is_instance_valid(e) and e.get_parent() == null:
				e.free()
		t.all = []


func _bc_setup() -> void:
	_bc_clean_frame()
	if _bc_tabs.empty():
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
		_bc_grey_banned(tab)
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
		_bc_updates[ud.id] = ud
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
	extras.player = bc_player
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
	clear.text = "X"	# 游戏字体没有 × 字形
	clear.rect_min_size.x = 40
	clear.connect("pressed", self, "_bc_on_clear", [tab])
	row1.add_child(clear)
	var badges = Button.new()
	badges.text = tr("BC_SETTINGS")
	badges.connect("pressed", self, "_bc_open_settings")
	row1.add_child(badges)
	bar.add_child(row1)

	var row2 = HBoxContainer.new()
	var keys = ["tier", "tag", "source", "special"] if tab == "items" else ["tier", "type", "class", "source"]
	for key in keys:
		var ob = load(BC_DIR + "ui/grid_select.gd").new()	# 多列网格弹窗：道具标签等长列表不会超出屏幕
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
	_bc_apply_bar_font(t)
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
	opts.source = [["", tr("MENU_ITEMSET")]]
	for s in BC_SET_ORDER:
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
		if not t.ui[key].has_method("get_item_metadata"):
			continue
		var ob = t.ui[key]
		ob.clear()
		for o in opts[key]:
			ob.add_item(o[1])
			ob.set_item_metadata(ob.get_item_count() - 1, o[0])
		_bc_select_option(ob, t.f[key])


func _bc_by_label(a, b) -> bool:
	return a[1] < b[1]


func _bc_select_option(ob, value) -> void:
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
		if _bc_tabs[tab].ui[key].has_method("get_item_metadata"):
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
	var wanted = []
	for e in t.all:
		if is_instance_valid(e) and _bc_match(tab, e.item):
			wanted.push_back(e)
	var same = wanted.size() == inv.get_child_count()
	if same:
		for e in wanted:
			if e.get_parent() != inv:
				same = false
				break
	if not same:	# 显示的元素不变时什么都不做（没有筛选时打开图鉴不必重排）
		for c in inv.get_children():
			inv.remove_child(c)
		for e in wanted:
			inv.add_child(e)
		inv.emit_signal("need_to_sort_inventory")
		inv.queue_set_focus_neighbours()
	if tab == "items":
		t.ui.temp_row.visible = _bc_temp != null
		if _bc_temp != null:
			t.ui.temp_label.text = "%s: %s" % [tr("BC_TEMP_FILTER"), _bc_temp.title]


# 筛选栏的字体（跟随设置里的字体大小）
func _bc_apply_bar_font(t) -> void:
	var font = load("res://mods-unpacked/Mojimoon-BetterCodex/ui/fonts.gd").font(22)
	for c in [t.ui.search, t.ui.badges, t.ui.temp_label] + t.ui.temp_row.get_children() + t.ui.search.get_parent().get_children():
		c.add_font_override("font", font)
	for key in t.ui:
		if t.ui[key].has_method("set_list_font"):
			t.ui[key].set_list_font(font)


# ---- 角标 ----

# ---- 设置 ----

# 设置分两组：图鉴 / 商店（组名用游戏自己的词）
const BC_TOGGLES_CODEX = [["badge_price", "BC_BADGE_PRICE", true], ["badge_limit", "BC_BADGE_LIMIT", true], ["badge_source", "BC_BADGE_SOURCE", true], ["unlock_all", "BC_UNLOCK_ALL", false]]
const BC_TOGGLES_SHOP = [["shop_hint", "BC_SHOW_SHOP_HINT", true], ["right_click", "BC_RIGHT_CLICK", true]]
const BC_MUT_MODES = ["default", "evo", "off"]	# 启用异变预览：默认（可掉落异变果）/ 进化 <= 0 / 关

var _bc_settings_popup: PopupPanel
var _bc_hotkey_btn: Button
var _bc_mut_btn: Button
var _bc_capturing := false


func _bc_open_settings() -> void:
	if _bc_settings_popup == null:
		var font = load("res://mods-unpacked/Mojimoon-BetterCodex/ui/fonts.gd").font(22)
		_bc_settings_popup = PopupPanel.new()
		_bc_settings_popup.name = "BCSettings"
		var box = VBoxContainer.new()
		box.add_constant_override("separation", 8)
		# 各状态用同一个样式：游戏主题的悬停样式边距不同，文字会左移、压到勾上（同 BroEditor 的 _checkbox）
		var sb = StyleBoxEmpty.new()
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		for group in [["MENU_CODEX", BC_TOGGLES_CODEX], ["MENU_SHOP", BC_TOGGLES_SHOP]]:
			var head = Label.new()
			head.text = tr(group[0])
			head.add_font_override("font", font)
			head.add_color_override("font_color", Color(0.92, 0.89, 0.69))
			box.add_child(head)
			for t in group[1]:
				box.add_child(_bc_setting_checkbox(t, font, sb))
			if group[0] == "MENU_SHOP":
				_bc_hotkey_btn = Button.new()
				_bc_hotkey_btn.add_font_override("font", font)
				_bc_hotkey_btn.connect("pressed", self, "_bc_on_hotkey_pressed")
				_bc_hotkey_btn.connect("gui_input", self, "_bc_on_hotkey_input")
				box.add_child(_bc_hotkey_btn)
				_bc_mut_btn = Button.new()
				_bc_mut_btn.add_font_override("font", font)
				_bc_mut_btn.connect("pressed", self, "_bc_on_mut_mode")
				box.add_child(_bc_mut_btn)
		_bc_settings_popup.add_child(box)
		$root.add_child(_bc_settings_popup)
	_bc_capturing = false
	_bc_update_hotkey_text()
	_bc_update_mut_text()
	_bc_settings_popup.popup_centered()


func _bc_setting_checkbox(t: Array, font, sb) -> CheckBox:
	var cb = CheckBox.new()
	cb.name = t[0]
	cb.text = tr(t[1])
	cb.add_font_override("font", font)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		cb.add_stylebox_override(st, sb)
	for k in ["font_color", "font_color_pressed", "font_color_focus"]:
		cb.add_color_override(k, Color.white)
	for k in ["font_color_hover", "font_color_hover_pressed"]:
		cb.add_color_override(k, Color("#8fd3ff"))
	cb.pressed = _bc_setting(t[0], t[2])
	cb.connect("toggled", self, "_bc_on_setting", [t[0]])
	return cb


func _bc_update_mut_text() -> void:
	var mode = str(_bc_setting("mut_preview", "default"))
	var value = tr("BC_DEFAULT") if mode == "default" else ("%s <= 0" % tr("STAT_EVOLUTION")) if mode == "evo" else tr("BC_OFF")
	_bc_mut_btn.text = "%s: %s" % [tr("BC_MUT_PREVIEW"), value]


# 三项循环：默认 → 进化 <= 0 → 关
func _bc_on_mut_mode() -> void:
	var i = BC_MUT_MODES.find(str(_bc_setting("mut_preview", "default")))
	_bc_set_setting("mut_preview", BC_MUT_MODES[(i + 1) % BC_MUT_MODES.size()])
	_bc_update_mut_text()
	var scene = get_tree().current_scene
	var hook = scene.get_node_or_null("BCShopHook") if scene != null else null
	if hook != null:
		hook.update_hint()	# 商品卡片的描述随之刷新


func _bc_update_hotkey_text() -> void:
	var key = OS.get_scancode_string(_bc_setting("hotkey", KEY_C))
	_bc_hotkey_btn.text = "%s: %s" % [tr("BC_HOTKEY"), tr("BC_PRESS_KEY") if _bc_capturing else key]


func _bc_on_hotkey_pressed() -> void:
	_bc_capturing = true
	_bc_update_hotkey_text()


func _bc_on_hotkey_input(event: InputEvent) -> void:
	if not _bc_capturing or not event is InputEventKey or not event.pressed or event.scancode == KEY_ESCAPE:
		return
	_bc_capturing = false
	_bc_set_setting("hotkey", event.scancode)
	_bc_update_hotkey_text()
	_bc_hotkey_btn.accept_event()


func _bc_set_setting(key: String, value) -> void:
	var m = _bc_mod()
	if m != null:
		m.settings[key] = value
		m.save_settings()


func _bc_on_setting(on: bool, key: String) -> void:
	_bc_set_setting(key, on)
	if key == "unlock_all":
		if not on:
			for it in ItemService.items:
				it.is_locked = not ProgressData.items_unlocked.has(it.my_id_hash)
			for w in ItemService.weapons:
				w.is_locked = not ProgressData.weapons_unlocked.has(w.weapon_id_hash)
		_pop()	# 重新生成列表
	elif key in ["shop_hint", "right_click"]:
		var scene = get_tree().current_scene	# 暂停菜单里的图鉴不是商店的直接子节点
		var hook = scene.get_node_or_null("BCShopHook") if scene != null else null
		if hook != null:
			hook.update_hint()
	elif key.begins_with("badge_"):
		for t in _bc_tabs.values():
			for e in t.all:
				if is_instance_valid(e) and e.has_node("BCBadges"):
					var b = e.get_node("BCBadges")
					e.remove_child(b)
					b.free()
		for tab in _bc_tabs:
			for e in _bc_tabs[tab].all:
				_bc_add_badges(e, tab)


# 局内：当前玩家的禁用道具变灰（角色禁用只在非无尽波次生效，与商店一致；加上消耗禁用次数禁掉的）
func _bc_grey_banned(tab: String) -> void:
	for e in _bc_tabs[tab].all:
		if not e.has_meta("bc_modulate"):
			e.set_meta("bc_modulate", e.modulate)
		e.modulate = e.get_meta("bc_modulate")
	if not load(BC_DIR + "ui/extras.gd").scene_in_run(get_tree()) or RunData.players_data.empty():
		return
	var banned = RunData.players_data[bc_player].banned_items
	var char_banned = []
	if RunData.current_wave < RunData.nb_of_waves:
		for it in load(BC_DIR + "ui/extras.gd").banned_items(RunData.get_player_character(bc_player)):
			char_banned.push_back(it.my_id_hash)
	for e in _bc_tabs[tab].all:
		var it = e.item
		if it == null:
			continue
		if char_banned.has(it.my_id_hash) or banned.has(it.my_id_hash) or (it is WeaponData and banned.has(it.weapon_id_hash)):
			e.modulate = Color(0.35, 0.35, 0.35, e.get_meta("bc_modulate").a)


func _bc_badge_label(text: String, color: Color, align: int, valign: int) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", load("res://mods-unpacked/Mojimoon-BetterCodex/ui/fonts.gd").font(18, true, true))	# 角标不随字体大小缩放：列表元素大小固定
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
	if _bc_extras_script == null:
		_bc_extras_script = load(BC_DIR + "ui/extras.gd")
		_bc_icon_script = load(BC_DIR + "ui/outlined_icon.gd")
	var Extras = _bc_extras_script
	if Extras.has_price(it) and _bc_setting("badge_price"):
		root.add_child(_bc_badge_label(str(it.value), Color("#ffd75e"), Label.ALIGN_LEFT, Label.VALIGN_TOP))
	if tab == "items" and it.max_nb > 0 and _bc_setting("badge_limit"):
		root.add_child(_bc_badge_label(str(it.max_nb), Color("#ff6b6b") if it.max_nb == 1 else Color("#ffa94d"), Label.ALIGN_RIGHT, Label.VALIGN_TOP))
	# 右下角来源图标（带描边）：机械 / 异变道具用机械部件 / 异变果图标，其他用物品套组图标（按物品套组栏的颜色着色）
	if _bc_setting("badge_source"):
		var Icon = _bc_icon_script
		var icons = []
		var evo = _bc_evo_of(it)
		if evo != "":
			for k in (["mutant", "meca"] if evo == "both" else [evo]):
				if ResourceLoader.exists(BC_EVO_ICONS[k]):
					icons.push_back(Icon.new(load(BC_EVO_ICONS[k])))
		else:
			var s = _bc_set_of(it)
			if _bc_updates.has(s) and _bc_updates[s].icon != null:
				icons.push_back(Icon.new(_bc_updates[s].icon, _bc_updates[s].color))
		if not icons.empty():
			var box = HBoxContainer.new()
			box.mouse_filter = MOUSE_FILTER_IGNORE
			box.add_constant_override("separation", 0)
			box.set_anchors_and_margins_preset(PRESET_BOTTOM_RIGHT)
			box.grow_horizontal = GROW_DIRECTION_BEGIN
			box.grow_vertical = GROW_DIRECTION_BEGIN
			box.margin_right = -3
			box.margin_bottom = -3
			for icon in icons:
				box.add_child(icon)
			root.add_child(box)
	e.add_child(root)


# ---- 详情 ----

func _on_InventoryItems_element_pressed(element: InventoryElement):
	_bc_unlock_begin()
	._on_InventoryItems_element_pressed(element)
	_bc_select("items", _bc_visible_item(element.item))
	_bc_unlock_end()


func _on_InventoryWeapons_element_pressed(element: InventoryElement):
	_bc_unlock_begin()
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
	_bc_unlock_end()


# 未解锁或图鉴描述未解锁（买得不够多）的物品不显示附加区块，与原版图鉴一致
# 局外（标题界面）总是 0；局内为当前玩家
func _bc_p() -> int:
	return bc_player if load(BC_DIR + "ui/extras.gd").scene_in_run(get_tree()) else 0


static func _bc_visible_item(it):
	return null if it == null or it.is_locked or it._is_locked_in_codex() else it


func _bc_select_tier(w) -> void:
	_bc_unlock_begin()
	$"%codex_weapon_description".set_item(w, _bc_p())
	_bc_select("weapons", _bc_visible_item(w))
	_bc_unlock_end()


func _bc_select(tab: String, it) -> void:
	if not _bc_tabs.has(tab):
		return
	var t = _bc_tabs[tab]
	t.current = it
	_bc_unlock_begin()
	t.extras.show_item(it)
	_bc_redisplay(tab, false)
	_bc_unlock_end()
	_bc_header(tab, t.desc, it)


# 诅咒 / 机械化后的描述 + 实际冷却
func _bc_redisplay(tab: String, reset: bool = true) -> void:
	var t = _bc_tabs[tab]
	if t.current == null:
		return
	var shown = t.extras.display_item(t.current)
	if reset or shown != t.current or _bc_p() != 0:	# 原版聚焦时按玩家 0 生成描述：多人时按当前玩家重新生成
		_bc_unlock_begin()
		t.desc.set_item(shown, _bc_p())
		_bc_unlock_end()
		_bc_header(tab, t.desc, t.current)
	if shown is WeaponData:
		_bc_fix_cooldown(t.desc, shown)


# 图鉴标题下原来的类别行（只在图鉴里）：武器 = 类型 + 类别按钮（代替原文字）；道具 = 原文字（限制 (X)、构筑物……）+ 标签按钮。点击筛选
func _bc_header(tab: String, desc, it) -> void:
	var cat = desc._category
	var box = cat.get_parent().get_node_or_null("BCCategory")
	if box == null:
		# 居中、可换行的一行文字，类型 / 类别 / 标签是可点击的链接
		box = RichTextLabel.new()
		box.bbcode_enabled = true
		box.fit_content_height = true
		box.scroll_active = false
		box.add_font_override("normal_font", load("res://mods-unpacked/Mojimoon-BetterCodex/ui/fonts.gd").font(26))
		box.connect("meta_clicked", self, "_bc_on_header_link", [], CONNECT_DEFERRED)	# 处理点击时不能改自己的文本（会崩溃）
		box.name = "BCCategory"
		cat.get_parent().add_child_below_node(cat, box)
	box.visible = it != null
	cat.visible = it == null
	if it == null:
		return
	var parts = []
	if tab == "weapons":	# 近战 / 远程已在属性的范围一行里
		for set in it.sets:
			parts.push_back(_bc_link("set:" + set.my_id, tr(set.name)))
	else:
		# 代替原来的类别文字：独特的 / 限制 (X) / 构筑物（同样式、不是链接；宠物由同名标签显示）+ 标签链接
		var Extras = load(BC_DIR + "ui/extras.gd")
		var tags = it.tags.duplicate()
		var font_color = cat.get_color("font_color").to_html(false)
		tags.sort()
		var tag_texts = []
		for tag in tags:
			tag_texts.push_back(Extras.tag_name(tag))
		var plain = []
		if it.max_nb == 1:
			plain.push_back(tr("UNIQUE"))
		elif it.max_nb > 1:
			plain.push_back("%s (%d)" % [tr("BC_LIMITED"), it.max_nb])
		if it.is_structure_item():
			plain.push_back(tr("STRUCTURE"))
		for t in plain:
			if not tag_texts.has(t):
				parts.push_back("[color=#%s]%s[/color]" % [font_color, t])
		for i in tags.size():
			parts.push_back(_bc_link("tag:" + tags[i], tag_texts[i]))
		if parts.empty():
			parts.push_back("[color=#%s]%s[/color]" % [font_color, cat.text])
	box.bbcode_text = "[center]" + "  ·  ".join(parts) + "[/center]"


static func _bc_link(meta: String, text: String) -> String:
	return "[url=%s][color=#8fd3ff]%s[/color][/url]" % [meta, text]


func _bc_on_header_link(meta) -> void:
	var m = str(meta)
	if m.begins_with("type:"):
		_bc_filter_type(int(m.substr(5)))
	elif m.begins_with("set:"):
		_bc_filter_set(m.substr(4))
	elif m.begins_with("tag:"):
		bc_filter_tag(m.substr(4))


func _bc_filter_type(type: int) -> void:
	_bc_reset_filters("weapons")
	_bc_tabs.weapons.f.type = type
	_bc_fill_options("weapons")
	_bc_apply("weapons")
	_bc_focus_first("weapons")


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
	var p = _bc_p()
	if w.type == WeaponData.Type.MELEE:
		cur = WeaponService.init_melee_stats(w.stats, p, args)
	else:
		cur = WeaponService.init_ranged_stats(w.stats, p, false, args)
	var in_run = load(BC_DIR + "ui/extras.gd").scene_in_run(get_tree())
	var count = int(clamp(RunData.get_player_weapons_ref(p).size(), 1, 6)) if in_run else Calc.DEFAULT_WEAPON_COUNT
	var atk = (Utils.get_stat(Keys.stat_attack_speed_hash, p) + cur.attack_speed_mod) / 100.0
	var timing = Calc.timing(w.stats, atk, Utils.get_stat(Keys.stat_range_hash, p), count)
	var text = label.bbcode_text
	var from = max(0, text.find(tr("COOLDOWN")))
	var at = text.find(Calc.cooldown_str(cur.get_cooldown_value(p, 1.0)), from)
	if at >= 0:
		var old = Calc.cooldown_str(cur.get_cooldown_value(p, 1.0))
		text = text.substr(0, at) + Calc.actual_str(timing.avg) + text.substr(at + old.length())
		from = at + 1
	if timing.shots > 0:
		var old_r = Calc.cooldown_str(cur.get_cooldown_value(p, cur.additional_cooldown_multiplier))
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
