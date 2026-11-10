extends Reference

# BetterCodex 无头测试（run_tests.sh 调用；BC_MODE = normal / compat，compat 同时加载 ImprovedTooltips）

const MOD_ID = "Mojimoon-BetterCodex"
const DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"

var tree: SceneTree
var m
var Calc
var Preview
var Extras
var _current = ""
var _failures = []
var _checks = 0


func run(p_tree: SceneTree):
	tree = p_tree
	if OS.get_environment("BC_TEST") != "1":
		printerr("Refusing to run: use run_tests.sh")
		return 2
	m = tree.root.get_node_or_null("ModLoader/" + MOD_ID)
	if m == null:
		printerr("Mod node not found")
		return 2
	if OS.get_environment("BC_MODE") == "compat":
		print("IT loaded: ", tree.root.get_node_or_null("ModLoader/_wl-ImprovedTooltips") != null)
	Calc = load(DIR + "calc.gd")
	Preview = load(DIR + "preview.gd")
	Extras = load(DIR + "ui/extras.gd")
	_unlock_everything()
	var only = OS.get_environment("BC_ONLY")
	var tests = []
	for method in get_method_list():
		if method.name.begins_with("test_") and (only == "" or method.name.find(only) >= 0):
			tests.push_back(method.name)
	tests.sort()
	for t in tests:
		_current = t
		_setup_player()
		var c0 = _checks
		var state = call(t)
		if state is GDScriptFunctionState:
			yield(state, "completed")
		print("  ran %s (%d checks)" % [t, _checks - c0])
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		printerr("FAIL ", f)
	if _failures.empty():
		print("ALL TESTS PASSED")
	return 0 if _failures.empty() else 1


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures.push_back(_current + ": " + msg)


func _eq(a, b, msg: String) -> void:
	_check(a == b, "%s (expected %s, got %s)" % [msg, str(b), str(a)])


func _unlock_everything() -> void:
	ProgressData.items_unlocked = []
	for it in ItemService.items:
		ProgressData.items_unlocked.push_back(it.my_id_hash)
	ProgressData.items_bought = {}
	for x in ItemService.items + ItemService.weapons:
		ProgressData.items_bought[x.my_id_hash] = 10
	ProgressData.weapons_unlocked = []
	for w in ItemService.weapons:
		if not ProgressData.weapons_unlocked.has(w.weapon_id_hash):
			ProgressData.weapons_unlocked.push_back(w.weapon_id_hash)


func _setup_player(char_id: String = "") -> void:
	RunData.set_player_count(1, true)
	var c = ItemService.characters[0]
	for x in ItemService.characters:
		if x.my_id == char_id:
			c = x
	RunData.players_data[0].current_character = c
	RunData.players_data[0].items = [c]
	RunData.current_wave = 1
	RunData.current_difficulty = 0
	Utils.reset_stat_caches()
	RunData.bc_reset_mutable_counts()


func _set_stat(key: int, v) -> void:
	RunData.players_data[0].effects[key] = v
	Utils.reset_stat_caches()


func _item(id: String):
	for it in ItemService.items:
		if it.my_id == id:
			return it
	return null


func _weapon(id: String):
	for w in ItemService.weapons:
		if w.my_id == id:
			return w
	return null


func _wait(n: int = 3):
	for i in n:
		yield(tree, "idle_frame")


# ---- 计算 ----

# 移植的 tooltip 冷却与游戏 get_cooldown_value 完全一致（全部武器，攻速 -50 / 0 / 50 / 200）
func test_calc_tooltip_matches_game() -> void:
	for atk in [-50, 0, 50, 200]:
		_set_stat(Keys.stat_attack_speed_hash, atk)
		var rng = Utils.get_stat(Keys.stat_range_hash, 0)
		var bad = []
		for w in ItemService.weapons:
			var args = WeaponServiceInitStatsArgs.new()
			args.sets = w.sets
			args.effects = w.effects
			var cur = WeaponService.init_melee_stats(w.stats, 0, args) if w.type == WeaponData.Type.MELEE else WeaponService.init_ranged_stats(w.stats, 0, false, args)
			var t = Calc.timing(w.stats, (Utils.get_stat(Keys.stat_attack_speed_hash, 0) + cur.attack_speed_mod) / 100.0, rng, 6)
			if abs(t.tooltip - cur.get_cooldown_value(0, 1.0)) > 0.0005:
				bad.push_back("%s %s vs %s" % [w.my_id, t.tooltip, cur.get_cooldown_value(0, 1.0)])
			if t.shots > 0 and abs(t.reload_tooltip - cur.get_cooldown_value(0, cur.additional_cooldown_multiplier)) > 0.02:
				bad.push_back("%s reload %s" % [w.my_id, t.reload_tooltip])
		_check(bad.empty(), "atk %d: %s" % [atk, str(bad.slice(0, 4))])
	_set_stat(Keys.stat_attack_speed_hash, 0)


func test_calc_frames() -> void:
	_eq(Calc.cd_frames(60, 0.5), 40, "60f +50%")
	_eq(Calc.cd_frames(60, -0.5), 90, "60f -50%")
	_eq(Calc.cd_frames(3, 5.0), 2, "min cooldown")
	_eq(Calc.tween(0.05), 4, "0.05s tween")
	_eq(Calc.tween(0.1), 8, "0.1s tween")
	_check(abs(Calc.avg_duration(10, 10) - 10) < 1e-6, "degenerate avg")
	var pistol = _weapon("weapon_pistol_1")
	if pistol != null:
		var t = Calc.timing(pistol.stats, 0, 0, 6)
		_check(t.min <= t.avg and t.avg <= t.max, "avg within range")
		_check(Calc.dps_change(pistol.stats, 0.5, 0, 6) > 0, "attack speed raises dps")
		_eq(Calc.dps_change(pistol.stats, 0, 0, 6), 0.0, "zero change at 0")


# 价格：去掉玩家价格效果后与原始公式一致（噩梦通胀取自难度数据），且不改动玩家效果
func test_price_preview() -> void:
	var effects = RunData.players_data[0].effects
	effects[Keys.items_price_hash] = -30
	_eq(Preview.nightmare_inflation(), 10, "nightmare inflation from difficulty data")
	for nm in [false, true]:
		var infl = 0.11 if nm else 0.1
		for base in [10, 37, 90]:
			for wave in [0, 1, 7, 19]:
				_eq(Preview.price(base, wave, nm, false), int(max(1.0, base + wave + base * wave * infl)), "price %d w%d nm%s" % [base, wave, nm])
	_check(Preview.price(30, 25, false, false) > int(30 + 25 + 30 * 25 * 0.1), "endless factor applied")
	_eq(effects[Keys.items_price_hash], -30, "player effect restored")
	effects[Keys.items_price_hash] = 0
	_check(abs(Preview.price_increment(20, false, false) - 3.0) < 0.06, "increment ~ base*0.1+1")


func test_curse_range() -> void:
	var d = Preview.dlc(Preview.DLC1)
	if d == null:
		return
	_eq(Calc.curse_range(d, 1), [10, 40, 70], "wave 1")
	_eq(Calc.curse_range(d, 21), [50, 80, 110], "wave 21")
	_eq(Calc.curse_range(d, 40), [50, 80, 110], "capped at wave 21")


func test_curse_preview() -> void:
	var it = _item("item_alien_eyes")
	if Preview.dlc(Preview.DLC1) == null or it == null:
		return
	var c = Preview.cursed(it, 80)
	_check(c.is_cursed, "cursed")
	_check(abs(c.curse_factor - 0.8) < 1e-6, "factor 0.8, got %s" % c.curse_factor)
	_eq(Preview.dlc(Preview.DLC1).cursed_item_base_percent_modifier, 40, "modifier restored")
	var w = _weapon("weapon_pistol_1")
	_eq(Preview.cursed(w, 100).stats.damage, int(ceil(w.stats.damage * 2.0)), "weapon damage x2")


func test_meca_preview() -> void:
	var w = _weapon("weapon_pistol_1")
	if not Preview.can_meca(w):
		return
	var mw = Preview.meca(w, 10)
	_check(mw.is_meca, "is meca")
	_eq(mw.stats.damage, int(ceil(w.stats.damage * 1.5)), "damage +50%")
	_check(not w.is_meca, "original untouched")


func test_mutation_preview() -> void:
	if not Preview.can_mutate():
		return
	var it = _item("item_alien_eyes")
	var key = Keys.stat_evolution_hash
	RunData.players_data[0].effects[key] = 7
	var hi = Preview.mutation(it, 150)
	var lo = Preview.mutation(it, 1)
	_eq(RunData.players_data[0].effects[key], 7, "evolution restored")
	_check(hi.copy.size() + hi.later.size() + hi.remove.size() > 0, "something to show")
	_check(lo.copy.size() <= hi.copy.size(), "less copyable at low evolution")
	for e in hi.copy:
		_check(e.added_by_mutation, "copy marked as mutation")
	# 化石等带 mut_min 的效果：低异变时出现在 later
	var any_later = false
	for x in ItemService.items:
		if Preview.mutation(x, 1).later.size() > 0:
			any_later = true
			break
	_check(any_later, "some effect needs higher mutation")


func test_banned_and_related() -> void:
	var with_ban = null
	for c in ItemService.characters:
		if c.banned_item_groups.size() > 0 or c.banned_items.size() > 0:
			with_ban = c
			break
	_check(with_ban != null, "a character bans items")
	if with_ban != null:
		_check(Extras.banned_items(with_ban).size() > 0, "banned list resolved")
	var chained = 0
	for it in ItemService.items:
		if it.replaced_by != null:
			chained += 1
			var chain = Extras.related_chain(it)
			_check(chain.size() >= 2 and chain.has(it), "chain contains " + it.my_id)
	_check(chained > 0, "replaced_by items exist")


# ---- 图鉴界面 ----

func _open_codex():
	var codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
	codex.name = "MenuCodex"
	tree.root.add_child(codex)
	yield(_wait(), "completed")
	codex._pop()
	yield(_wait(), "completed")
	return codex


func _close(codex) -> void:
	codex.hide()
	tree.root.remove_child(codex)
	codex.free()


func test_codex_filters_and_badges():
	var codex = yield(_open_codex(), "completed")
	var t = codex._bc_tabs.items
	var total = t.inv.get_child_count()
	_check(total > 100, "items listed: %d" % total)
	_check(codex.find_node("BCFilterBar", true, false) != null, "filter bar")
	var badged = 0
	for e in t.all:
		if e.has_node("BCBadges"):
			badged += 1
	_check(badged > 100, "badges added: %d" % badged)
	codex.bc_filter_tag("stat_luck")
	yield(_wait(), "completed")
	var shown = t.inv.get_children()
	_check(shown.size() > 0 and shown.size() < total, "tag filter narrows: %d" % shown.size())
	for e in shown:
		_check(e.item.tags.has("stat_luck"), "tag kept " + e.item.my_id)
	_check(t.ui.tag.get_selected_metadata() == "stat_luck", "tag option selected")
	# 标签多：网格弹窗不超出屏幕，点选即筛选
	t.ui.tag._open()
	yield(_wait(2), "completed")
	var view = t.ui.tag.get_viewport_rect()
	_check(view.encloses(t.ui.tag._popup.get_global_rect()), "tag grid fits on screen: %s" % t.ui.tag._popup.get_global_rect())
	_eq(t.ui.tag._grid.columns, 3, "long list uses 3 columns")
	var pick = 2
	t.ui.tag._grid.get_child(pick).emit_signal("pressed")
	yield(_wait(), "completed")
	_eq(t.f.tag, t.ui.tag.get_item_metadata(pick), "picked tag filters")
	_check(not t.ui.tag._popup.visible, "grid closed after pick")
	codex._bc_on_clear("items")
	_eq(t.inv.get_child_count(), total, "clear restores")
	t.ui.search.text = "item_fossil"
	codex._bc_on_search("item_fossil", "items")
	for e in t.inv.get_children():
		_check(e.item.my_id.find("item_fossil") >= 0, "search " + e.item.my_id)
	codex._bc_on_clear("items")
	var picks = [ItemService.items[0], ItemService.items[3]]
	codex.bc_temp_filter("test", picks, picks[1])
	yield(_wait(), "completed")
	_eq(t.inv.get_child_count(), 2, "temp filter")
	_check(t.ui.temp_row.visible, "temp row visible")
	_check(t.current != null and t.current.my_id_hash == picks[1].my_id_hash, "temp select")
	codex._bc_clear_temp()
	_eq(t.inv.get_child_count(), total, "temp cleared")
	# 重新打开：旧元素释放，不重复加角标
	codex._pop()
	yield(_wait(), "completed")
	_eq(codex._bc_tabs.items.inv.get_child_count(), total, "reopen")
	var w = codex._bc_tabs.weapons
	var wt = w.inv.get_child_count()
	w.f.type = WeaponData.Type.MELEE
	codex._bc_apply("weapons")
	for e in w.inv.get_children():
		_eq(e.item.type, WeaponData.Type.MELEE, "melee filter " + e.item.my_id)
	_check(w.inv.get_child_count() < wt, "melee subset")
	_close(codex)


func _select_weapon(codex, id: String):
	var w = codex._bc_tabs.weapons
	for e in w.all:
		if e.item.my_id == id:
			codex._on_InventoryWeapons_element_pressed(e)
	yield(_wait(), "completed")


func test_codex_weapon_detail():
	var codex = yield(_open_codex(), "completed")
	codex.bc_show_tab("weapons")
	yield(_select_weapon(codex, "weapon_pistol_1"), "completed")
	var w = codex._bc_tabs.weapons
	_check(w.current != null and w.current.my_id == "weapon_pistol_1", "pistol selected")
	var text = w.desc.get_weapon_stats().bbcode_text
	var pistol = w.current
	var t = Calc.timing(pistol.stats, Utils.get_stat(Keys.stat_attack_speed_hash, 0) / 100.0, Utils.get_stat(Keys.stat_range_hash, 0), 6)
	var cur = WeaponService.init_ranged_stats(pistol.stats, 0, false)
	var vanilla = Calc.cooldown_str(cur.get_cooldown_value(0, 1.0))
	if Calc.actual_str(t.avg) != vanilla:
		_check(text.find(vanilla) < 0, "tooltip cooldown %s replaced: %s" % [vanilla, text])
	if OS.get_environment("BC_MODE") != "compat":
		_check(text.find(Calc.actual_str(t.avg)) >= 0, "actual cooldown %s shown: %s (vanilla %s)" % [Calc.actual_str(t.avg), text, vanilla])
	_check(w.extras._calc_text != null and w.extras._calc_text.bbcode_text.find("DPS") >= 0, "calculator")
	_check(w.extras._price_text != null, "price section")
	var header = w.desc._category.get_parent().get_node_or_null("BCCategory")
	_check(header != null and header.visible and not w.desc._category.visible, "type / class header")
	if header != null:
		_eq(header.bbcode_text.count("[url="), w.current.sets.size(), "header links (classes only)")
		_check(header.bbcode_text.find(tr("BC_RANGED")) < 0, "no melee / ranged in header")
		header.emit_signal("meta_clicked", "type:%d" % WeaponData.Type.RANGED)
		yield(_wait(), "completed")
		for e in w.inv.get_children():
			_eq(e.item.type, WeaponData.Type.RANGED, "type filter from header")
		yield(_select_weapon(codex, "weapon_pistol_1"), "completed")
	# 诅咒：描述显示被诅咒的武器
	if w.extras._curse_btn != null:
		w.extras._curse_btn.pressed = true
		yield(_wait(), "completed")
		_check(w.desc.item.is_cursed, "description cursed")
		_check(w.desc.get_weapon_stats().bbcode_text.find(vanilla) < 0 or Calc.actual_str(t.avg) == vanilla, "cursed still actual cd")
		if w.extras._meca_btn != null:
			w.extras._meca_btn.pressed = true
			yield(_wait(), "completed")
			_check(w.desc.item.is_meca and not w.desc.item.is_cursed, "meca replaces curse")
			_check(not w.extras._curse_btn.pressed, "curse toggle off")
	# 等级按钮仍然可用（改连到扩展）
	codex.but_tier1.emit_signal("pressed")
	yield(_wait(), "completed")
	_eq(w.current.tier, 1, "tier 2 via button")
	# 带换弹的武器
	for id in ["weapon_minigun_1", "weapon_shotgun_1", "weapon_smg_1"]:
		yield(_select_weapon(codex, id), "completed")
	codex._bc_filter_set(w.current.sets[0].my_id if w.current.sets.size() > 0 else "")
	_close(codex)


func test_codex_item_detail():
	var codex = yield(_open_codex(), "completed")
	codex.bc_show_tab("items")
	var it = null
	for x in ItemService.items:
		if x.replaced_by != null and x.tags.size() > 0:
			it = x
			break
	codex.bc_focus_item(it, "items")
	yield(_wait(), "completed")
	var t = codex._bc_tabs.items
	_check(t.current == it, "focused related root")
	var header = t.desc._category.get_parent().get_node_or_null("BCCategory")
	_check(header != null and header.visible and not t.desc._category.visible, "item header")
	if header != null and it.tags.size() > 0:
		_eq(header.bbcode_text.count("[url="), it.tags.size(), "tag links in header")
		if it.max_nb == 1:
			_check(header.bbcode_text.find(tr("UNIQUE")) >= 0, "unique shown: " + header.bbcode_text)
		_check(header.bbcode_text.find(t.desc._category.text) < 0 or t.desc._category.text == "", "original category replaced")
		header.emit_signal("meta_clicked", "tag:" + it.tags[0])
		yield(_wait(), "completed")
		_eq(t.f.tag, it.tags[0], "header tag filter")
		codex.bc_focus_item(it, "items")
		yield(_wait(), "completed")
	var icons = 0
	var evo_icons = 0
	for e in t.all:
		if e.has_node("BCBadges"):
			for c in e.get_node("BCBadges").get_children():
				if c is HBoxContainer and c.anchor_left == 1.0:
					icons += 1
					if c.get_child(0).texture.resource_path.find("consumables") >= 0:
						evo_icons += 1
	_check(icons > 50, "source icons bottom-right: %d" % icons)
	_check(evo_icons > 5, "meca / mutant icons bottom-right: %d" % evo_icons)
	# 关联里当前道具（disabled）的图标与其他一样大
	for b in _all(t.extras):
		if b is Button and b.disabled and b.icon != null:
			_check(b.get_stylebox("disabled") == b.get_stylebox("normal"), "disabled style same as normal")
	# 边框涂鸦：内容区内的边框贴图像素被清掉
	var img = codex.get_node("root/shelf").texture.get_data()
	img.lock()
	_eq(img.get_pixel(260, 500).a, 0.0, "frame cleared inside content")
	img.unlock()
	t.extras._on_mut_toggled(true)
	t.extras._on_mut_slid(30)
	_check(t.extras._mut_box.get_child_count() > 0, "mutation lines")
	var nxt = Extras.related_chain(it)[1]
	t.extras._on_related(nxt)
	yield(_wait(), "completed")
	_eq(t.current.my_id, nxt.my_id, "related jump")
	if nxt.tags.size() > 0:
		t.extras._on_tag(nxt.tags[0])
		yield(_wait(), "completed")
		_eq(t.f.tag, nxt.tags[0], "tag jump")
	_close(codex)


# 局内：默认值取当前值
func test_codex_in_run_defaults():
	var e = Extras.new()
	tree.root.add_child(e)
	var main = Node.new()
	main.name = "Main"
	tree.root.add_child(main)
	var prev = tree.current_scene
	tree.current_scene = main
	RunData.current_wave = 11
	RunData.current_difficulty = 5
	_set_stat(Keys.stat_attack_speed_hash, 35)
	RunData.players_data[0].effects[Keys.inflation_modifier_hash] = 10
	e.reset_defaults()
	_check(e.in_run, "in run")
	_eq(e.wave, 11, "wave")
	_check(e.nightmare, "nightmare")
	_eq(e.atk, 35, "attack speed")
	if Preview.dlc(Preview.DLC1) != null:
		_eq(e.curse_pct, 60, "curse median at wave 11")
	tree.current_scene = prev
	main.free()
	e.free()
	RunData.players_data[0].effects[Keys.inflation_modifier_hash] = 0
	_set_stat(Keys.stat_attack_speed_hash, 0)


func test_selection_panel():
	var c = null
	for x in ItemService.characters:
		if x.wanted_tags.size() > 0 and (x.banned_item_groups.size() > 0 or x.banned_items.size() > 0):
			c = x
			break
	if c == null:
		c = ItemService.characters[0]
	_setup_player(c.my_id)
	RunData.current_zone = 0
	var scene = load("res://ui/menus/run/weapon_selection.tscn").instance()
	tree.root.add_child(scene)
	var prev = tree.current_scene
	tree.current_scene = scene
	yield(_wait(5), "completed")
	var info = scene.find_node("BCCharacterInfo", true, false)
	_check(info != null, "character info panel")
	if info != null:
		_check(info.extras.item == c, "shows character")
		if c.wanted_tags.size() > 0:
			info._on_tag(c.wanted_tags[0])
			yield(_wait(), "completed")
			_check(info.codex != null and info.codex.visible, "codex opened")
			var want = 0
			for it in ItemService.items:
				for t in it.tags:
					if c.wanted_tags.has(t):
						want += 1
						break
			_eq(info.codex._bc_tabs.items.inv.get_child_count(), want, "wanted tags temp filter (all tags)")
		info._on_banned(c, null)
		yield(_wait(), "completed")
		_check(info.codex._bc_temp != null, "banned temp filter")
		_eq(info.codex._bc_tabs.items.inv.get_child_count(), Extras.banned_items(c).size(), "banned count")
	tree.current_scene = prev
	tree.root.remove_child(scene)
	scene.free()


# 商店：右键 / C 定位到商品与已有物品；ItemRefund（compat）同时加载时也正常
func test_shop_open_codex():
	var w = _weapon("weapon_pistol_2")
	var owned = Preview.cursed(w, 70) if Preview.dlc(Preview.DLC1) != null else w
	RunData.players_data[0].weapons = [owned]
	RunData.players_data[0].items.push_back(_item("item_alien_eyes"))
	RunData.current_wave = 3
	ItemService.init_unlocked_pool()
	var shop = load("res://ui/menus/shop/shop.tscn").instance()
	var prev = tree.current_scene
	tree.root.add_child(shop)
	tree.current_scene = shop
	yield(_wait(10), "completed")
	var hook = shop.get_node_or_null("BCShopHook")
	_check(hook != null, "hook attached")
	if OS.get_environment("BC_MODE") == "compat":
		_check(shop.get_node_or_null("ItemRefundController") != null, "ItemRefund attached")
	if hook != null:
		# 已有武器元素：命中测试 → 打开图鉴，定位到 T2，诅咒预设为 70%
		var el = null
		for n in _all(shop):
			if n is InventoryElement and n.item == owned and n.is_visible_in_tree():
				el = n
		_check(el != null, "owned weapon element")
		if el != null:
			_eq(hook._item_at(shop, el.get_global_rect().get_center()), owned, "hit test")
			hook.open(owned)
			yield(_wait(5), "completed")
			var t = hook.codex._bc_tabs.weapons
			_check(hook.codex.visible, "codex visible")
			_check(t.current != null and t.current.my_id == "weapon_pistol_2", "tier 2 selected: %s" % (t.current.my_id if t.current else "null"))
			if owned.is_cursed:
				_check(t.extras.curse_on and t.extras.curse_pct == 70, "curse preset")
				_check(t.desc.item.is_cursed, "cursed description")
			_check(t.extras.in_run, "in-run defaults in shop")
			hook.codex.hide()
		var card = null
		for n in _all(shop):
			if n is ShopItem and n.item_data != null and n.is_visible_in_tree():
				card = n
				break
		_check(card != null, "shop item card")
		if card != null:
			_eq(hook._item_of(card), card.item_data, "card item")
			hook.open(card.item_data)
			yield(_wait(5), "completed")
			var tab = "weapons" if card.item_data is WeaponData else "items"
			var cur = hook.codex._bc_tabs[tab].current
			_check(cur != null and cur.my_id_hash == card.item_data.my_id_hash, "shop item selected")
			hook.codex.hide()
	tree.current_scene = prev
	tree.root.remove_child(shop)
	shop.queue_free()
	yield(_wait(3), "completed")
	RunData.players_data[0].weapons = []


func _all(node: Node) -> Array:
	var out = [node]
	for c in node.get_children():
		out += _all(c)
	return out



func test_translations_loaded() -> void:
	_check(tr("BC_SETTINGS") != "BC_SETTINGS", "csv loaded")
	_eq(tr("BC_FRAMES"), "f", "frames unit")


func test_settings_unlock_quick():
	var real_items = ProgressData.items_unlocked
	var real_bought = ProgressData.items_bought
	ProgressData.items_unlocked = []
	ProgressData.items_bought = {}
	m.settings.unlock_all = true
	m.settings.badge_price = false
	var codex = yield(_open_codex(), "completed")
	var t = codex._bc_tabs.items
	_check(not codex.animation_tree.active and codex.get_node("root").rect_position == Vector2.ZERO, "quick open")
	_eq(ProgressData.items_unlocked.size(), 0, "save list untouched")
	codex._bc_unlock_begin()
	var it0 = ItemService.items[0]
	_eq(ProgressData.items_bought[it0.my_id_hash], it0.unlock_codex_descr_after_get_it, "fake purchases = just enough to unlock")
	codex._bc_unlock_end()
	var locked = 0
	var priced = 0
	for e in t.all:
		if e.item.is_locked:
			locked += 1
		if e.has_node("BCBadges"):
			for l in e.get_node("BCBadges").get_children():
				if l is Label and l.align == Label.ALIGN_LEFT and l.valign == Label.VALIGN_TOP:
					priced += 1
	_eq(locked, 0, "everything unlocked in codex")
	_eq(priced, 0, "price badges off")
	codex._on_InventoryItems_element_pressed(t.all[0])
	yield(_wait(), "completed")
	_check(t.current != null, "description unlocked")
	codex._bc_open_settings()
	_check(codex.get_node("root/BCSettings").visible, "settings popup")
	codex._on_BackButton_pressed()
	_check(not codex.visible, "quick close")
	_check(ItemService.items[0].is_locked, "is_locked restored")
	m.settings.unlock_all = false
	m.settings.badge_price = true
	ProgressData.items_unlocked = real_items
	ProgressData.items_bought = real_bought
	_close(codex)


func test_banned_grey_in_run():
	var c = null
	for x in ItemService.characters:
		if x.banned_item_groups.size() > 0 or x.banned_items.size() > 0:
			c = x
			break
	_setup_player(c.my_id)
	RunData.current_wave = 5
	var token = ItemService.items[0]
	RunData.players_data[0].banned_items = [token.my_id_hash]
	var main = Node.new()
	main.name = "Main"
	tree.root.add_child(main)
	var prev = tree.current_scene
	tree.current_scene = main
	var codex = yield(_open_codex(), "completed")
	var grey = {}
	for e in codex._bc_tabs.items.all:
		if e.modulate.r < 0.5:
			grey[e.item.my_id_hash] = true
	_check(grey.has(token.my_id_hash), "ban token greyed")
	for it in Extras.banned_items(c):
		_check(grey.has(it.my_id_hash), "character ban greyed " + it.my_id)
	_eq(grey.size(), Extras.banned_items(c).size() + (0 if Extras.banned_items(c).has(token) else 1), "only banned greyed")
	tree.current_scene = prev
	main.free()
	RunData.players_data[0].banned_items = []
	_close(codex)


func test_fruit_hint() -> void:
	var Hook = load(DIR + "ui/shop_hook.gd")
	if not "primal_dread" in ProgressData.active_update_data:
		_eq(Hook.fruit_text(), "", "no dlc2")
		return
	RunData.players_data[0].items = [RunData.players_data[0].current_character]
	RunData.bc_reset_mutable_counts()
	_check(Hook.fruit_text().find("0/3") >= 0, "not enough items: " + Hook.fruit_text())
	for id in ["item_alien_eyes", "item_baby_elephant", "item_coffee"]:
		RunData.add_item(_item(id), 0)
	_check(Hook.fruit_text() != "" and Hook.fruit_text().find("/3") < 0, "can drop: " + Hook.fruit_text())
	_set_stat(Keys.stat_evolution_hash, 10)
	_eq(Hook.fruit_text(), "", "meca route hides")
	_set_stat(Keys.stat_evolution_hash, 0)


# 真实切换场景进商店（与升级后进入商店相同的路径），检查期间的任何脚本错误（watch begin/end）
func test_shop_scene_change():
	var w = _weapon("weapon_pistol_1")
	RunData.players_data[0].weapons = [w]
	RunData.current_wave = 2
	ItemService.init_unlocked_pool()
	print("watch begin")
	tree.change_scene("res://ui/menus/shop/shop.tscn")
	yield(_wait(30), "completed")
	var shop = tree.current_scene
	_check(shop != null and shop.name == "Shop", "in shop")
	if shop != null:
		_check(shop.get_node_or_null("BCShopHook") != null, "hook")
		_check(shop.get_node_or_null("BCShopHint") != null, "hint")
	yield(_wait(40), "completed")
	print("watch end")
	RunData.players_data[0].weapons = []


# 商店：可掉落异变果时，悬停已有道具 / 角色显示异变预览；道具不足时不显示
func test_shop_mutation_preview():
	if not "primal_dread" in ProgressData.active_update_data:
		return
	var c = RunData.players_data[0].current_character
	RunData.players_data[0].items = [c]
	for id in ["item_alien_eyes", "item_baby_elephant", "item_coffee"]:
		RunData.players_data[0].items.push_back(_item(id))
	RunData.bc_reset_mutable_counts()
	RunData.current_wave = 3
	ItemService.init_unlocked_pool()
	var shop = load("res://ui/menus/shop/shop.tscn").instance()
	var prev = tree.current_scene
	tree.root.add_child(shop)
	tree.current_scene = shop
	yield(_wait(10), "completed")
	var hook = shop.get_node("BCShopHook")
	var popup = shop._get_item_popup(0)
	var el = null
	for n in _all(shop):
		if n is InventoryElement and n.item != null and n.item.my_id == "item_alien_eyes" and n.is_visible_in_tree():
			el = n
	_check(el != null, "item element")
	# 商品卡片（道具）：描述末尾有分割线 + 异变预览
	var card = null
	for n in _all(shop):
		if n is ShopItem and n.item_data is ItemData and n.is_visible_in_tree():
			card = n
			break
	if card != null:
		_check(_has_mut_preview(card._item_description), "shop card description has mutation preview")
	if el != null:
		popup.display_item_data(el.item, el, true)
		yield(_wait(3), "completed")
		var desc = _desc_in(popup)
		_check(desc != null and _has_mut_preview(desc), "popup description has mutation preview")
		popup.hide()
		# 道具不足 3 个：不可掉落 → 没有预览；商品卡片也随之刷新
		RunData.remove_item(_item("item_coffee"), 0)
		RunData.remove_item(_item("item_baby_elephant"), 0)
		RunData.emit_signal("gold_changed", 0, 0)	# 买卖道具时会触发：提示随之刷新
		yield(_wait(2), "completed")
		_check(hook.hint.text.find("/3") >= 0, "hint refreshed on gold change: " + hook.hint.text)
		_check(hook.hint.visible, "hint shown when fruit can't drop")
		if card != null:
			_check(not _has_mut_preview(card._item_description), "card refreshed without preview")
		popup.display_item_data(el.item, el, true)
		yield(_wait(3), "completed")
		_check(not _has_mut_preview(_desc_in(popup)), "no preview when fruit can't drop")
	tree.current_scene = prev
	tree.root.remove_child(shop)
	shop.queue_free()
	yield(_wait(3), "completed")


func _desc_in(node):
	for n in _all(node):
		if n is ItemDescription and n.is_visible_in_tree():
			return n
	return null


func _has_mut_preview(desc) -> bool:
	for n in desc.get_effects().get_children():
		if n is HSeparator and n.get_stylebox("separator") is StyleBoxLine and not n.is_queued_for_deletion():
			return true
	return false


# 可异变道具计数：增量更新与重新数的结果一致（替换品、没找到、诅咒道具、角色）
func test_mutable_count_incremental() -> void:
	var c = RunData.players_data[0].current_character
	RunData.players_data[0].items = [c]
	RunData.bc_reset_mutable_counts()
	_eq(RunData.bc_mutable_count(0), 0, "character not counted")
	var a = _item("item_alien_eyes")
	var b = _item("item_coffee")
	RunData.add_item(a, 0)
	RunData.add_item(b, 0)
	RunData.add_item(a, 0)
	_eq(RunData.bc_mutable_count(0), 3, "after adds")
	if Preview.dlc(Preview.DLC1) != null:
		RunData.add_item(Preview.cursed(b, 50), 0)
		_eq(RunData.bc_mutable_count(0), 3, "cursed item not mutable")
	RunData.remove_item(a, 0)
	_eq(RunData.bc_mutable_count(0), 2, "after remove")
	RunData.remove_item(_item("item_baby_elephant"), 0)
	_eq(RunData.bc_mutable_count(0), 2, "removing a missing item")
	var chained = null
	for x in ItemService.items:
		if x.replaced_by != null and ItemService.can_item_be_mutated(x):
			chained = x
			break
	RunData.add_item(chained, 0)
	RunData.remove_item(chained, 0)	# 加入替换品
	var counted = RunData.bc_mutable_count(0)
	RunData.bc_reset_mutable_counts()
	_eq(counted, RunData.bc_mutable_count(0), "incremental == recount (replacement)")
	RunData.players_data[0].items = [c]
	RunData.bc_reset_mutable_counts()


# 图鉴：开诅咒时异变复制的基础值取诅咒后的；诅咒道具不能被异变，没有可清除
func test_codex_mutation_cursed():
	if not Preview.can_mutate() or Preview.dlc(Preview.DLC1) == null:
		return
	var it = _item("item_alien_eyes")
	var plain = Preview.mutation(it, 100)
	var cursed = Preview.mutation(Preview.cursed(it, 100), 100)
	_check(plain.copy.size() > 0 and cursed.copy.size() > 0, "copyable both ways")
	_check(abs(cursed.copy[0].value) >= abs(plain.copy[0].value), "copied from cursed value: %s vs %s" % [cursed.copy[0].value, plain.copy[0].value])
	var codex = yield(_open_codex(), "completed")
	var t = codex._bc_tabs.items
	codex.bc_focus_item(it, "items")
	yield(_wait(), "completed")
	t.extras._on_mut_toggled(true)
	var before = t.extras._mut_box.get_child_count()
	t.extras._curse_btn.pressed = true
	yield(_wait(), "completed")
	var has_remove = false
	for n in t.extras._mut_box.get_children():
		if n is Label and n.text == tr("BC_MUT_REMOVE"):
			has_remove = true
	_check(not has_remove, "no removable when cursed")
	_check(t.extras._mut_box.get_child_count() > 0 and before > 0, "mutation preview present")
	codex._bc_open_settings()
	var cb = codex.get_node("root/BCSettings").find_node("unlock_all", true, false)
	_check(cb.get_stylebox("hover") == cb.get_stylebox("normal"), "checkbox hover style same as normal")
	_close(codex)


# 预先构建 + 快速重开：内容不变时不重建元素；获得次数变了就重建
func test_codex_prewarm_and_reuse():
	var codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
	codex.name = "MenuCodex"
	tree.root.add_child(codex)
	yield(_wait(3), "completed")
	codex.bc_prewarm()
	_check(not codex.visible, "prewarm leaves the codex hidden")
	_check(codex._bc_tabs.items.all.size() > 100, "prewarm built the lists")
	var first = codex._bc_tabs.items.all[0]
	var t0 = OS.get_ticks_usec()
	codex._pop()
	var reopen_ms = (OS.get_ticks_usec() - t0) / 1000
	_check(codex.visible, "opened")
	_check(is_instance_valid(first) and codex._bc_tabs.items.all[0] == first, "elements reused")
	_check(reopen_ms < 100, "reopen fast: %d ms" % reopen_ms)
	codex._on_BackButton_pressed()
	var it = ItemService.items[5]
	ProgressData.items_bought[it.my_id_hash] = ProgressData.items_bought.get(it.my_id_hash, 0) + 1
	codex._pop()
	yield(_wait(2), "completed")
	_check(not is_instance_valid(first) or codex._bc_tabs.items.all[0] != first, "rebuilt after a purchase")
	_close(codex)


# 商店里（局内）的图鉴：描述末尾不再加异变预览（图鉴有自己的异变区块，局内可掉落时默认打开）；提示在暂停菜单下面
func test_shop_codex_single_mutation_view():
	if not "primal_dread" in ProgressData.active_update_data:
		return
	var c = RunData.players_data[0].current_character
	RunData.players_data[0].items = [c]
	for id in ["item_alien_eyes", "item_baby_elephant", "item_coffee"]:
		RunData.add_item(_item(id), 0)
	RunData.bc_reset_mutable_counts()
	RunData.current_wave = 3
	ItemService.init_unlocked_pool()
	var shop = load("res://ui/menus/shop/shop.tscn").instance()
	var prev = tree.current_scene
	tree.root.add_child(shop)
	tree.current_scene = shop
	yield(_wait(10), "completed")
	var hook = shop.get_node("BCShopHook")
	_check(shop.get_node("BCShopHint").get_index() < shop.get_node("PauseMenu").get_index(), "hint below the pause menu")
	var hint = shop.get_node("BCShopHint")
	_check(hint.text.begins_with(tr("BC_SHOP_HINT").format(["C"])), "hint starts with the codex hotkey: " + hint.text)
	hook._ensure_codex()
	hook.codex._bc_on_setting(false, "shop_hint")
	_check(not hint.visible, "hint hidden by the setting")
	hook.update_hint()
	_check(not hint.visible, "stays hidden after refresh")
	hook.codex._bc_on_setting(true, "shop_hint")
	_check(hint.visible, "shown again")
	hook.open(_item("item_alien_eyes"))
	yield(_wait(5), "completed")
	var t = hook.codex._bc_tabs.items
	_check(t.extras.mut_on, "mutation on by default (fruit can drop)")
	_check(not _has_mut_preview(t.desc), "no second preview in the codex description")
	var seps = 0
	for n in _all(t.extras._mut_box):
		if n is HSeparator:
			seps += 1
	_eq(seps, 1, "one mutation view with its separator")
	var label_ok = false
	for n in _all(t.extras._mut_box):
		if n is Label and (n.text.begins_with(tr("BC_MUT_COPY") + " x") or n.text == tr("BC_NO_MUT_COPY") or n.text.begins_with(tr("BC_MUT_LOW").split("(")[0])):
			label_ok = true
	_check(label_ok, "merged header '%s x…'" % tr("BC_MUT_COPY"))
	hook.codex.hide()
	tree.current_scene = prev
	tree.root.remove_child(shop)
	shop.queue_free()
	yield(_wait(3), "completed")


# 商店：快捷键 C（真实输入事件，图鉴预先构建之后）打开图鉴
func test_shop_hotkey_after_prewarm():
	RunData.players_data[0].weapons = [_weapon("weapon_pistol_1")]
	RunData.current_wave = 3
	ItemService.init_unlocked_pool()
	var shop = load("res://ui/menus/shop/shop.tscn").instance()
	var prev = tree.current_scene
	tree.root.add_child(shop)
	tree.current_scene = shop
	yield(_wait(10), "completed")
	var hook = shop.get_node("BCShopHook")
	yield(tree.create_timer(2.5), "timeout")	# 预先构建（1–2 秒）
	_check(hook.codex != null and not hook.codex._bc_tabs.empty(), "shop codex prewarmed")
	var el = null
	for n in _all(shop):
		if n is InventoryElement and n.item is WeaponData and n.is_visible_in_tree():
			el = n
	el.grab_focus()
	yield(_wait(2), "completed")
	print("focus owner: ", shop.get_focus_owner())
	var ev = InputEventKey.new()
	ev.scancode = KEY_C
	ev.pressed = true
	tree.input_event(ev)
	yield(_wait(3), "completed")
	_check(hook.codex.visible, "C opens the codex (focus %s)" % shop.get_focus_owner())
	hook.codex.hide()
	# 关掉右键：右键事件完全不处理（不打开、不标记已处理），快捷键照常；提示只写快捷键
	m.settings.right_click = false
	hook.update_hint()
	_eq(hook.hint.text.begins_with(tr("BC_SHOP_HINT_KEY").format(["C"])), true, "hint without right-click: " + hook.hint.text)
	var rc = InputEventMouseButton.new()
	rc.button_index = BUTTON_RIGHT
	rc.pressed = true
	rc.position = el.get_global_rect().get_center()
	rc.global_position = rc.position
	var calls = [0]
	hook._input(rc)
	yield(_wait(2), "completed")
	_check(not hook.codex.visible, "right-click ignored when disabled")
	tree.input_event(ev)
	yield(_wait(3), "completed")
	_check(hook.codex.visible, "hotkey still works")
	hook.codex.hide()
	m.settings.right_click = true
	tree.current_scene = prev
	tree.root.remove_child(shop)
	shop.queue_free()
	yield(_wait(3), "completed")
	RunData.players_data[0].weapons = []



# 异变阈值：缩放达到生成实体所需最小缩放的最小异变值（150 → 67，100 → 40）；不足时显示“异变不足 (X/阈值)”，无法复制时不显示倍率
func test_mutation_threshold_view():
	if not Preview.can_mutate():
		return
	var t = Preview.mut_threshold()
	var d = Preview.dlc(Preview.DLC2)
	var min_scale = d.get_script().get_script_constant_map()["MUTATION_ENTITY_MIN_SCALE"]
	_check(Preview.mut_scale(t) >= min_scale and Preview.mut_scale(t - 1) < min_scale, "threshold %d" % t)
	_eq(t, {150: 67, 100: 40}.get(Preview.mut_max(), t), "known thresholds")
	var pet = null
	for x in ItemService.items:
		if Preview.mutation(x, 1).later.size() > 0:
			pet = x
			break
	var box = VBoxContainer.new()
	tree.root.add_child(box)
	load(DIR + "ui/mutation_view.gd").build(box, pet, 1, 0)
	var texts = []
	for n in box.get_children():
		if n is Label:
			texts.push_back(n.text)
	_check(texts.has(tr("BC_MUT_LOW").format([1, t])), "low line: %s" % str(texts))
	box.free()
	var none = null
	for x in ItemService.items:
		var m = Preview.mutation(x, 1)
		if m.copy.empty() and m.later.empty():
			none = x
			break
	box = VBoxContainer.new()
	tree.root.add_child(box)
	load(DIR + "ui/mutation_view.gd").build(box, none, 1, 0)
	var found = false
	for n in box.get_children():
		if n is Label and n.text == tr("BC_NO_MUT_COPY"):
			found = true
	_check(found, "no scale after 'can't copy'")
	box.free()



# 启用异变预览：默认 = 可掉落异变果；进化 <= 0 = 不看道具数；关 = 不显示
func test_mutation_preview_modes() -> void:
	if not "primal_dread" in ProgressData.active_update_data:
		return
	var Hook = load(DIR + "ui/shop_hook.gd")
	var c = RunData.players_data[0].current_character
	RunData.players_data[0].items = [c]
	RunData.bc_reset_mutable_counts()
	m.settings.mut_preview = "default"
	_check(not Hook.mutation_preview_on(), "default: off when the fruit can't drop")
	m.settings.mut_preview = "evo"
	_check(Hook.mutation_preview_on(), "evo <= 0: on without enough items")
	_set_stat(Keys.stat_evolution_hash, 5)
	_check(not Hook.mutation_preview_on(), "evo > 0: off")
	_set_stat(Keys.stat_evolution_hash, 0)
	for id in ["item_alien_eyes", "item_baby_elephant", "item_coffee"]:
		RunData.add_item(_item(id), 0)
	m.settings.mut_preview = "off"
	_check(not Hook.mutation_preview_on(), "off")
	m.settings.mut_preview = "default"
	_check(Hook.mutation_preview_on(), "default: on when the fruit can drop")
	RunData.players_data[0].items = [c]
	RunData.bc_reset_mutable_counts()
