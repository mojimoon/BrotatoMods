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


# 价格与 ItemService.get_value 一致（玩家无价格效果；难度 5 = 通胀 +10%）
func test_price_matches_game() -> void:
	var effects = RunData.players_data[0].effects
	for diff in [0, 5]:
		effects[Keys.inflation_modifier_hash] = 10 if diff == 5 else 0
		for base in [10, 37, 90]:
			for wave in [0, 1, 7, 19, 25]:
				_eq(Calc.price(base, wave, diff), ItemService.get_value(wave, base, 0, true, false), "price %d w%d d%d" % [base, wave, diff])
	effects[Keys.inflation_modifier_hash] = 0


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
		if x.replaced_by != null:
			it = x
			break
	codex.bc_focus_item(it, "items")
	yield(_wait(), "completed")
	var t = codex._bc_tabs.items
	_check(t.current == it, "focused related root")
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
	e.reset_defaults()
	_check(e.in_run, "in run")
	_eq(e.wave, 11, "wave")
	_eq(e.difficulty, 5, "difficulty")
	_eq(e.atk, 35, "attack speed")
	if Preview.dlc(Preview.DLC1) != null:
		_eq(e.curse_pct, 60, "curse median at wave 11")
	tree.current_scene = prev
	main.free()
	e.free()
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
			_eq(info.codex._bc_tabs.items.f.tag, c.wanted_tags[0], "tag filter")
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
