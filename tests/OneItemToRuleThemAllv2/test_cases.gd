extends Reference

# OneItemToRuleThemAllv2 的无头测试：在反编译的游戏工程里运行，使用真实的
# ItemService / RunData / ModLoader（编辑器模式只加载 res://mods-unpacked 下的 mod）。
# 由 run_oitrta.gd 在 autoload 就绪后加载（本文件引用游戏的 class_name，不能作为 -s 入口）。
# 不要直接运行，使用同目录的 run_tests.sh（会同步 mod、隔离 user:// 目录）。

const MOD_ID = "Mojimoon-OneItemToRuleThemAllv2"
const MOD_DIR = "res://mods-unpacked/" + MOD_ID + "/"
const ITEM_BOX = "res://items/consumables/item_box/item_box_data.tres"
const LEGENDARY_BOX = "res://items/consumables/legendary_item_box/legendary_item_box_data.tres"
const WAVE = 8
const SEEDS = [11, 222, 3333, 44444, 555555]

var m	# mod 节点
var isvc
var rd
var utils
var box
var legendary_box
# 测试用目标物品 id
var A: String
var B: String
var L1: String
var L2: String
var C1: String

var tree: SceneTree
var _current_test = ""
var _failures: Array = []
var _checks = 0


# 返回退出码
func run(p_tree: SceneTree):
	tree = p_tree
	if OS.get_environment("OITRTA_TEST") != "1":
		printerr("Refusing to run: use run_tests.sh (it isolates user:// from your real saves).")
		return 2

	m = tree.root.get_node_or_null("ModLoader/" + MOD_ID)
	isvc = tree.root.get_node("ItemService")
	rd = tree.root.get_node("RunData")
	utils = tree.root.get_node("Utils")
	if m == null:
		printerr("Mod node not found: is the mod in res://mods-unpacked?")
		return 2
	_unlock_everything()
	box = load(ITEM_BOX)
	legendary_box = load(LEGENDARY_BOX)
	A = isvc.items[0].my_id
	B = isvc.items[1].my_id
	L1 = isvc.items[2].my_id
	L2 = isvc.items[3].my_id
	C1 = isvc.items[4].my_id
	print("user dir: ", OS.get_user_data_dir())

	var tests: Array = []
	for method in get_method_list():
		if method.name.begins_with("test_"):
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


# ============================================================
# 工具
# ============================================================
func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures.push_back(_current_test + ": " + msg)


func _eq(actual, expected, msg: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func _reset() -> void:
	m.enabled = true
	m.target_item_ids = []
	m.legendary_item_ids = []
	m.legendary_mode = m.Mode.NONE
	m.crate_item_ids = []
	m.crate_mode = m.Mode.SHOP
	m.force_cursed = false
	m.cfg_replace_starting = false
	m.cfg_replace_shop = true
	m.cfg_replace_shop_first = false
	m.cfg_replace_shop_once = false
	m.reset_counter()
	_setup_player()
	rd.current_wave = WAVE


# 单人局：角色 + 空物品栏（游戏的随机物品逻辑需要角色）
func _setup_player() -> void:
	rd.set_player_count(1, true)
	rd.enabled_dlcs = []
	var pd = rd.players_data[0]
	pd.current_character = isvc.characters[0]
	pd.items = [isvc.characters[0]]


# 沙盒存档是全新的，只解锁了少量物品；全部解锁并初始化掉落池（开局时游戏会做同样的事）
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


func _seed(n: int) -> void:
	seed(n)
	utils._rng.seed = n


func _item(id: String):
	return isvc.get_element_safe(isvc.items, id)


func _id(item) -> String:
	return item.my_id if item != null else "<null>"


func _crate(seed_n: int, legendary: bool) -> String:
	_seed(seed_n)
	return _id(isvc.process_item_box(legendary_box if legendary else box, WAVE, 0))


func _rand_item(seed_n: int) -> String:
	_seed(seed_n)
	return _id(isvc.get_rand_item_for_wave(WAVE, 0))


func _shop(seed_n: int, wave: int = WAVE) -> Array:
	_seed(seed_n)
	var args = ItemServiceGetShopItemsArgs.new([[]], 0)
	var ids: Array = []
	for entry in isvc.get_player_shop_items(wave, 0, args):
		ids.push_back(_id(entry[0]))
	return ids


# 在总开关关闭的状态下跑一遍，作为"没有 mod 影响"的基准
func _baseline(method: String, args: Array):
	var was = m.enabled
	var c1 = m.replace_counter
	var c2 = m.legendary_counter
	var c3 = m.crate_counter
	m.enabled = false
	var result = callv(method, args)
	# 基准必须是真实的随机结果，否则"与基准一致"的比较毫无意义
	_check(str(result).find("<null>") == -1, "baseline %s%s returned null: %s" % [method, str(args), str(result)])
	m.enabled = was
	m.replace_counter = c1
	m.legendary_counter = c2
	m.crate_counter = c3
	return result


# 断言当前配置下，所有物品来源的结果都与基准一致，且计数器不动
func _assert_no_effect(label: String) -> void:
	for s in SEEDS:
		_eq(_crate(s, false), _baseline("_crate", [s, false]), label + ": crate seed %d" % s)
		_eq(_crate(s, true), _baseline("_crate", [s, true]), label + ": T4 crate seed %d" % s)
		_eq(_rand_item(s), _baseline("_rand_item", [s]), label + ": treasure map seed %d" % s)
		_eq(_shop(s), _baseline("_shop", [s]), label + ": shop seed %d" % s)
	_eq(m.replace_counter, 0, label + ": general counter untouched")
	_eq(m.legendary_counter, 0, label + ": T4 counter untouched")
	_eq(m.crate_counter, 0, label + ": crate counter untouched")


# ============================================================
# 0. 环境自检：基准必须可复现，否则后面的比较没有意义
# ============================================================
func test_00_baseline_is_deterministic() -> void:
	for s in SEEDS:
		_eq(_baseline("_crate", [s, false]), _baseline("_crate", [s, false]), "crate seed %d" % s)
		_eq(_baseline("_crate", [s, true]), _baseline("_crate", [s, true]), "T4 crate seed %d" % s)
		_eq(_baseline("_rand_item", [s]), _baseline("_rand_item", [s]), "rand item seed %d" % s)
		_eq(_baseline("_shop", [s]), _baseline("_shop", [s]), "shop seed %d" % s)
	var t4 = _item(_baseline("_crate", [SEEDS[0], true]))
	_check(t4 != null and t4.tier == Tier.LEGENDARY, "T4 crate yields a tier-4 item")


# ============================================================
# 1. 替换对象全不选 / 通用替换池为空 => 与禁用一致
# ============================================================
func test_01_disabled_has_no_effect() -> void:
	m.target_item_ids = [A, B]
	m.legendary_item_ids = [L1]
	m.cfg_replace_starting = true
	m.legendary_mode = m.Mode.SEQUENTIAL
	m.enabled = false
	# _assert_no_effect 的基准本身就是 enabled=false，这里额外确认 get_* 直接返回原物品
	var orig = _item(L2)
	_check(m.get_replacement(orig, 0) == orig, "get_replacement returns original")
	_check(m.get_legendary_replacement(orig, 0) == orig, "get_legendary_replacement returns original")
	_eq(m.replace_counter, 0, "counter untouched")


func test_02_no_sources_selected_equals_disabled() -> void:
	m.target_item_ids = [A, B]
	m.cfg_replace_starting = false
	m.cfg_replace_shop = false
	m.cfg_replace_shop_first = false
	m.cfg_replace_shop_once = false
	m.crate_mode = m.Mode.NONE
	m.legendary_mode = m.Mode.NONE
	_assert_no_effect("no sources")
	_eq(_starting_items_after_run_start(), _starting_items_baseline(), "starting items untouched")


func test_03_empty_general_pool_equals_disabled() -> void:
	m.target_item_ids = []
	m.cfg_replace_starting = true
	m.cfg_replace_shop = true
	# "同商店" 使用商店池，商店池为空时箱子 / T4 箱子也不受影响
	m.crate_mode = m.Mode.SHOP
	m.legendary_mode = m.Mode.SHOP
	_assert_no_effect("empty general pool")
	m.cfg_replace_shop = false
	m.cfg_replace_shop_first = true
	_assert_no_effect("empty general pool, shops always sell")
	m.cfg_replace_shop_first = false
	m.cfg_replace_shop_once = true
	_assert_no_effect("empty general pool, sold once per wave")
	_eq(_starting_items_after_run_start(), _starting_items_baseline(), "starting items untouched")


# 说明：箱子 / T4 箱子是独立设置，不受商店"替换对象"影响。
# 商店替换对象全不选时，若模式为 同商店 / 独立 / 单次 且对应池非空，箱子仍会被替换。
func test_04_t4_pool_is_independent_of_sources() -> void:
	m.target_item_ids = [A]
	m.legendary_item_ids = [L1]
	m.cfg_replace_shop = false
	m.crate_mode = m.Mode.NONE
	m.legendary_mode = m.Mode.SHOP
	_eq(_crate(SEEDS[0], true), A, "same as shop still replaces T4 crates")
	m.legendary_mode = m.Mode.SEQUENTIAL
	_eq(_crate(SEEDS[0], true), L1, "independent still replaces T4 crates")
	_eq(_crate(SEEDS[0], false), _baseline("_crate", [SEEDS[0], false]), "normal crate untouched")


# ============================================================
# 2. T4 独立 / 单次 且池为空 => 与禁用一致
# ============================================================
func test_05_t4_independent_empty_equals_off() -> void:
	m.target_item_ids = [A]
	m.legendary_mode = m.Mode.SEQUENTIAL
	for s in SEEDS:
		_eq(_crate(s, true), _baseline("_crate", [s, true]), "T4 crate seed %d" % s)
	_eq(m.legendary_counter, 0, "T4 counter untouched")
	_eq(m.replace_counter, 0, "general pool not used")


func test_06_t4_once_empty_equals_off() -> void:
	m.target_item_ids = [A]
	m.legendary_mode = m.Mode.ONCE
	for s in SEEDS:
		_eq(_crate(s, true), _baseline("_crate", [s, true]), "T4 crate seed %d" % s)
	_eq(m.legendary_counter, 0, "T4 counter untouched")
	_eq(m.replace_counter, 0, "general pool not used")


func test_07_t4_off_ignores_pools() -> void:
	m.target_item_ids = [A]
	m.legendary_item_ids = [L1]
	m.legendary_mode = m.Mode.NONE
	for s in SEEDS:
		_eq(_crate(s, true), _baseline("_crate", [s, true]), "T4 crate seed %d" % s)


# ============================================================
# T4 模式行为
# ============================================================
func test_08_t4_same_as_shop_shares_shop_rotation() -> void:
	m.target_item_ids = [A, B]
	m.legendary_mode = m.Mode.SHOP
	_eq(_crate(1, false), A, "normal crate 1")
	_eq(_crate(2, true), B, "T4 crate continues the A-B rotation")
	_eq(_crate(3, false), A, "normal crate 2")
	_eq(m.legendary_counter, 0, "T4 counter unused")


func test_09_t4_independent_rotates_own_pool() -> void:
	m.target_item_ids = [A]
	m.legendary_item_ids = [L1, L2]
	m.legendary_mode = m.Mode.SEQUENTIAL
	var got: Array = []
	for i in 5:
		got.push_back(_crate(i, true))
	_eq(got, [L1, L2, L1, L2, L1], "A-B-A-B over the T4 pool")
	_eq(m.replace_counter, 0, "general counter untouched")
	_eq(_crate(9, false), A, "normal crates still use the general pool")


func test_10_t4_once_replaces_first_n_only() -> void:
	m.legendary_item_ids = [L1, L2]
	m.legendary_mode = m.Mode.ONCE
	_eq(_crate(SEEDS[0], true), L1, "1st T4 crate")
	_eq(_crate(SEEDS[1], true), L2, "2nd T4 crate")
	for s in SEEDS:
		_eq(_crate(s, true), _baseline("_crate", [s, true]), "later T4 crates are random (seed %d)" % s)
	_eq(m.legendary_counter, 2, "counter stops at N")
	# 新一局重新计数
	m.reset_counter()
	_eq(_crate(SEEDS[0], true), L1, "resets on new run")


# ============================================================
# 通用池各来源
# ============================================================
func test_11_general_rotation_across_sources() -> void:
	m.target_item_ids = [A, B]
	_eq(_crate(1, false), A, "crate")
	_eq(_rand_item(2), B, "treasure map extra")
	_eq(_crate(3, false), A, "crate again")


func test_12_crate_option_off() -> void:
	m.target_item_ids = [A]
	m.crate_mode = m.Mode.NONE
	for s in SEEDS:
		_eq(_crate(s, false), _baseline("_crate", [s, false]), "crate seed %d" % s)
		_eq(_rand_item(s), _baseline("_rand_item", [s]), "treasure map seed %d" % s)


func test_13_shop_all_items() -> void:
	m.target_item_ids = [A]
	for s in SEEDS:
		var base: Array = _baseline("_shop", [s])
		var got: Array = _shop(s)
		_eq(got.size(), base.size(), "shop size seed %d" % s)
		for i in got.size():
			var orig = _item(base[i])
			if orig != null:	# 物品位：替换
				_eq(got[i], A, "item slot %d seed %d" % [i, s])
			else:	# 武器位：不动
				_eq(got[i], base[i], "weapon slot %d seed %d" % [i, s])


func test_14_shop_always_sells_replaces_one_slot() -> void:
	m.target_item_ids = [A]
	m.cfg_replace_shop = false
	m.cfg_replace_shop_first = true
	for s in SEEDS:
		var base: Array = _baseline("_shop", [s])
		var got: Array = _shop(s)
		var diff = 0
		for i in got.size():
			if got[i] != base[i]:
				diff += 1
		_check(got.has(A), "target present seed %d" % s)
		_check(diff <= 1, "at most one slot changed seed %d (changed %d)" % [s, diff])


func _starting_items_baseline() -> Array:
	var was = m.enabled
	m.enabled = false
	var ids = _starting_items_after_run_start()
	m.enabled = was
	return ids


func _starting_items_after_run_start() -> Array:
	_setup_player()
	var pd = rd.players_data[0]
	pd.items = [isvc.characters[0], _item(L1), _item(L2)]
	rd.add_starting_items_and_weapons()
	var ids: Array = []
	for it in pd.items:
		ids.push_back(_id(it))
	return ids


func test_15_starting_items() -> void:
	m.target_item_ids = [A]
	m.cfg_replace_starting = true
	var ids = _starting_items_after_run_start()
	_eq(ids, [isvc.characters[0].my_id, A, A], "items replaced, character kept")
	m.cfg_replace_starting = false
	_eq(_starting_items_after_run_start(), _starting_items_baseline(), "option off")


# ============================================================
# 3. 额外物品：藏宝图 / 珍珠（记录行为）
# ============================================================
# 藏宝图额外物品走 ItemService.get_rand_item_for_wave => 受箱子模式控制。
# 珍珠额外物品走 ItemService.get_item_from_id(珍珠) => 固定物品，不被替换。
func test_16_extra_items_in_crate() -> void:
	m.target_item_ids = [A]
	_eq(_rand_item(SEEDS[0]), A, "treasure map extra replaced (crates on)")
	m.crate_mode = m.Mode.NONE
	_eq(_rand_item(SEEDS[0]), _baseline("_rand_item", [SEEDS[0]]), "treasure map extra untouched (crates off)")
	m.crate_mode = m.Mode.SHOP
	# 珍珠：upgrades_ui._get_extra_crate_item 对非 random 的 extra_item_in_crate
	# 调用 get_item_from_id(effect_key)，这个函数 mod 没有扩展
	var f = File.new()
	f.open(MOD_DIR + "extensions/singletons/item_service.gd", File.READ)
	var src = f.get_as_text()
	f.close()
	_check(src.find("func get_rand_item_for_wave(") != -1, "treasure map path is hooked")
	_check(src.find("func get_item_from_id(") == -1, "pearl path is not hooked")
	if _item("item_pearl") != null:
		var pearl = isvc.get_item_from_id(tree.root.get_node("Keys").generate_hash("item_pearl"))
		_eq(_id(pearl), "item_pearl", "pearl extra stays a pearl")


# ============================================================
# 诅咒 / 异常数据
# ============================================================
func test_17_curse() -> void:
	m.target_item_ids = [A]
	var orig = _item(L1)
	var plain = m.get_replacement(orig, 0)
	_check(not plain.is_cursed, "not cursed by default")
	m.force_cursed = true
	var cursed = m.get_replacement(orig, 0)
	_check(cursed.is_cursed, "force_cursed curses the replacement")
	_check(not _item(A).is_cursed, "source item data not modified")
	m.force_cursed = false
	var cursed_orig = orig.duplicate()
	cursed_orig.is_cursed = true
	_check(m.get_replacement(cursed_orig, 0).is_cursed, "curse inherited from original")


func test_18_unknown_item_id() -> void:
	m.target_item_ids = ["item_does_not_exist"]
	var orig = _item(L1)
	_check(m.get_replacement(orig, 0) == orig, "unknown id keeps the original")


# ============================================================
# 设置读写
# ============================================================
func _write_json(path: String, data: Dictionary) -> void:
	var dir = Directory.new()
	dir.make_dir_recursive(path.get_base_dir())
	var f = File.new()
	f.open(path, File.WRITE)
	f.store_string(JSON.print(data))
	f.close()


func _remove(path: String) -> void:
	var dir = Directory.new()
	if dir.file_exists(path):
		dir.remove(path)


func test_19_settings_roundtrip() -> void:
	m.enabled = false
	m.target_item_ids = [A, B]
	m.legendary_item_ids = [L1]
	m.legendary_mode = m.Mode.ONCE
	m.crate_item_ids = [L2, C1]
	m.crate_mode = m.Mode.SEQUENTIAL
	m.cfg_replace_starting = true
	m.cfg_replace_shop = false
	m.cfg_replace_shop_once = true
	m._save_settings()
	_reset()
	m._load_settings()
	_eq(m.enabled, false, "enabled")
	_eq(m.target_item_ids, [A, B], "general pool")
	_eq(m.legendary_item_ids, [L1], "T4 pool")
	_eq(m.legendary_mode, m.Mode.ONCE, "mode")
	_eq(m.crate_item_ids, [L2, C1], "crate pool")
	_eq(m.crate_mode, m.Mode.SEQUENTIAL, "crate mode")
	_eq(m.cfg_replace_starting, true, "starting")
	_eq(m.cfg_replace_shop, false, "all items in shop")
	_eq(m.cfg_replace_shop_once, true, "sold once per wave")
	_remove(m.SETTINGS_PATH)


func test_20_settings_defaults_and_clamp() -> void:
	_write_json(m.SETTINGS_PATH, {"target_item_ids": [A]})
	m.enabled = false
	m.legendary_mode = m.Mode.ONCE
	m._load_settings()
	_eq(m.target_item_ids, [A], "pool loaded")
	_eq(m.enabled, true, "missing enabled defaults to true")
	_eq(m.legendary_mode, m.Mode.NONE, "missing T4 mode defaults to off")
	_eq(m.crate_mode, m.Mode.SHOP, "missing crate mode defaults to same as shop")
	_eq(m.crate_item_ids, [], "missing crate pool defaults to empty")
	_write_json(m.SETTINGS_PATH, {"legendary_mode": 99, "crate_mode": -3})
	m._load_settings()
	_eq(m.legendary_mode, m.Mode.ONCE, "out-of-range mode clamped")
	_eq(m.crate_mode, m.Mode.NONE, "negative mode clamped")
	_remove(m.SETTINGS_PATH)


# ============================================================
# 本地化
# ============================================================
func _csv_rows() -> Array:
	var f = File.new()
	f.open(m.CSV_PATH, File.READ)
	var rows: Array = []
	for line in f.get_as_text().split("\n", false):
		rows.push_back(m._parse_csv_line(line))
	f.close()
	return rows


func test_21_csv_shape() -> void:
	var rows = _csv_rows()
	var width = rows[0].size()
	_eq(width, 14, "header columns")
	for r in rows:
		_eq(r.size(), width, "columns in row " + r[0])
		for v in r:
			_check(v.strip_edges() != "", "empty cell in row " + r[0])


func _keys_used_in(path: String, out: Dictionary) -> void:
	var f = File.new()
	f.open(path, File.READ)
	var re = RegEx.new()
	re.compile("MOJI_[A-Z_]+")
	for match_ in re.search_all(f.get_as_text()):
		out[match_.get_string()] = path
	f.close()


func test_22_all_used_keys_exist() -> void:
	var used = {}
	for p in ["ui/item_picker_ui.gd", "extensions/ui/menus/run/weapon_selection.gd", "extensions/ui/menus/run/difficulty_selection/difficulty_selection.gd"]:
		_keys_used_in(MOD_DIR + p, used)
	var defined = {}
	for r in _csv_rows():
		defined[r[0]] = true
	for k in used:
		_check(defined.has(k), "key %s used in %s is missing from the CSV" % [k, used[k]])


func _tr_in(locale: String, key: String) -> String:
	TranslationServer.set_locale(locale)
	return TranslationServer.translate(key)


func test_23_translations_placeholders() -> void:
	var locales = Array(_csv_rows()[0]).slice(1, 13)
	for loc in locales:
		_eq(_tr_in(loc, "MOJI_DESC_REPLACED").count("%s"), 1, loc + " MOJI_DESC_REPLACED")
		_eq(_tr_in(loc, "MOJI_ADD_TO").count("%s"), 1, loc + " MOJI_ADD_TO")
		_eq(_tr_in(loc, "MOJI_SELECTED").count("%d"), 1, loc + " MOJI_SELECTED")
		_eq(_tr_in(loc, "MOJI_LEG_ONCE_DESC").count("%d"), 1, loc + " MOJI_LEG_ONCE_DESC")
		_eq(_tr_in(loc, "MOJI_CRATE_ONCE_DESC").count("%d"), 1, loc + " MOJI_CRATE_ONCE_DESC")
		_eq(_tr_in(loc, "MOJI_HINT").count("\n"), 1, loc + " MOJI_HINT has one line break")
		var dlc = _tr_in(loc, "MOJI_CURSE_DLC_REQUIRED")
		if loc == "zh":
			_check(dlc.find("深海魔怪") != -1, "zh uses the Chinese DLC name")
		else:
			_check(dlc.find("Abyssal Terrors") != -1, loc + " uses the English DLC name")
		_check(_tr_in(loc, "MOJI_LEGENDARY").find("T4") != -1, loc + " says T4")
	TranslationServer.set_locale("en")


# ============================================================
# UI 冒烟测试（真实场景 + 游戏主题/字体）
# ============================================================
func _open_ui():
	var ui = load(MOD_DIR + "ui/item_picker_ui.tscn").instance()
	tree.root.add_child(ui)
	yield(tree, "idle_frame")
	yield(tree, "idle_frame")
	return ui


func _center(c: Control) -> Vector2:
	var r = c.get_global_rect()
	return r.position + r.size / 2


# ============================================================
# 每波销售一次
# ============================================================
# 连续刷新商店，收集与基准不同的槽位里出现的物品
func _shop_once_appearances(wave: int, rerolls: int) -> Array:
	var appeared: Array = []
	for r in rerolls:
		var s = 1000 * wave + r
		var base: Array = _baseline("_shop", [s, wave])
		var got: Array = _shop(s, wave)
		_eq(got.size(), base.size(), "shop size wave %d reroll %d" % [wave, r])
		for i in got.size():
			if got[i] != base[i]:
				appeared.push_back(got[i])
	return appeared


func test_23a_shop_once_per_wave() -> void:
	m.target_item_ids = [A, B, L1, L2, C1]
	m.cfg_replace_shop = false
	m.cfg_replace_shop_once = true
	# 5 件物品超过一次商店的物品槽位数，需要刷新才能全部出现；每件恰好一次，按选择顺序
	_eq(_shop_once_appearances(WAVE, 6), [A, B, L1, L2, C1], "each item once per wave, in order")
	_eq(m.replace_counter, 0, "general rotation counter untouched")
	# 同一波后续刷新：恢复随机
	_eq(_shop_once_appearances(WAVE, 3), [], "back to random after all items appeared")
	# 下一波重新开始
	_eq(_shop_once_appearances(WAVE + 1, 6), [A, B, L1, L2, C1], "refills next wave")
	# 新一局重置
	_shop_once_appearances(WAVE + 2, 1)
	m.reset_counter()
	var first = _shop_once_appearances(WAVE + 2, 1)
	_check(not first.empty() and first[0] == A, "reset on new run starts from the first item")


func test_23b_shop_once_first_shop_fills_item_slots() -> void:
	m.target_item_ids = [A, B]
	m.cfg_replace_shop = false
	m.cfg_replace_shop_once = true
	for s in SEEDS:
		m.reset_counter()
		var base: Array = _baseline("_shop", [s])
		var got: Array = _shop(s)
		var item_slots = 0
		for id in base:
			if _item(id) != null:
				item_slots += 1
		var expected: Array = [A, B].slice(0, min(2, max(1, item_slots)) - 1)
		var appeared: Array = []
		for i in got.size():
			if got[i] != base[i]:
				appeared.push_back(got[i])
		_eq(appeared, expected, "first shop shows as many items as fit (seed %d, %d item slots)" % [s, item_slots])
		# 武器槽位不被占用（除非根本没有物品槽位）
		if item_slots > 0:
			for i in got.size():
				if _item(base[i]) == null:
					_eq(got[i], base[i], "weapon slot %d kept (seed %d)" % [i, s])


func test_23c_shop_once_disabled_or_off() -> void:
	m.target_item_ids = [A, B]
	m.cfg_replace_shop = false
	m.cfg_replace_shop_once = true
	m.enabled = false
	_eq(_shop_once_appearances(WAVE, 2), [], "master switch off")
	m.enabled = true
	# 关闭期间不应消耗本波队列
	_eq(_shop_once_appearances(WAVE, 3), [A, B], "queue not consumed while disabled")
	m.cfg_replace_shop_once = false
	m.reset_counter()
	_eq(_shop_once_appearances(WAVE, 3), [], "option off")


func test_24_ui_descriptions() -> void:
	TranslationServer.set_locale("en")
	var ui = yield(_open_ui(), "completed")
	_eq(ui._descs[ui.POOL_SHOP].text, "All items in shop will be replaced with the following items.", "default desc")

	ui._option_chips["cfg_replace_starting"].pressed = true
	_eq(ui._descs[ui.POOL_SHOP].text, "Starting items, all items in shop will be replaced with the following items.", "starting on")

	ui._option_chips["cfg_replace_shop_first"].pressed = true
	_eq(m.cfg_replace_shop, false, "shops always sell turns off all-shop")
	_eq(ui._option_chips["cfg_replace_shop"].pressed, false, "all-shop chip unpressed")
	_eq(ui._descs[ui.POOL_SHOP].text, "Starting items will be replaced with the following items. Upon each shop reroll, one of the slots is guaranteed to be one of the following items.", "shops always sell")

	ui._option_chips["cfg_replace_shop_once"].pressed = true
	_eq(m.cfg_replace_shop_first, false, "sold once per wave turns off shops always sell")
	_eq(ui._option_chips["cfg_replace_shop_first"].pressed, false, "shops always sell chip unpressed")
	_eq(ui._descs[ui.POOL_SHOP].text, "Starting items will be replaced with the following items. Each wave, the shop sells each of the following items once, then goes back to random.", "sold once per wave")

	ui._option_chips["cfg_replace_shop"].pressed = true
	_eq(m.cfg_replace_shop_once, false, "all items in shop turns off sold once per wave")
	_eq(m.cfg_replace_shop_first, false, "still off")
	_eq(ui._option_chips["cfg_replace_shop_once"].pressed, false, "sold once chip unpressed")

	_eq(ui._option_chips.size(), 4, "shop card holds the four non-crate options")
	_check(not ui._option_chips.has("cfg_replace_crate"), "no crate option chip")

	for key in ui._option_chips:
		ui._option_chips[key].pressed = false
	_eq(ui._descs[ui.POOL_SHOP].text, TranslationServer.translate("MOJI_DESC_NOTHING"), "nothing selected")

	TranslationServer.set_locale("zh")
	ui._option_chips["cfg_replace_starting"].pressed = true
	ui._option_chips["cfg_replace_shop_first"].pressed = true
	_eq(ui._descs[ui.POOL_SHOP].text, "起始物品被替换为以下物品。每次商店刷新时，固定有一个槽位是以下物品之一。", "zh joins without spaces")
	TranslationServer.set_locale("en")

	ui._enable_switch.pressed = false
	_eq(m.enabled, false, "enable switch off")
	_check(ui._pool_cards[0].modulate.a < 1.0, "content dimmed when disabled")
	ui._enable_switch.pressed = true
	_eq(ui._pool_cards[0].modulate.a, 1.0, "content restored")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_25_ui_pools_and_modes() -> void:
	TranslationServer.set_locale("en")
	var ui = yield(_open_ui(), "completed")
	_eq(m.crate_mode, m.Mode.SHOP, "crate defaults to same as shop")
	_eq(m.legendary_mode, m.Mode.NONE, "T4 crate defaults to off")
	_eq(ui._pool_scrolls[ui.POOL_CRATE].visible, false, "crate pool hidden when same as shop")
	_eq(ui._pool_scrolls[ui.POOL_LEGENDARY].visible, false, "T4 pool hidden when off")
	_eq(ui._active_pool, ui.POOL_SHOP, "shop pool active")
	_eq(ui._mode_buttons[ui.POOL_CRATE].size(), 4, "crate has four modes")
	_eq(ui._mode_buttons[ui.POOL_LEGENDARY].size(), 4, "T4 crate has four modes")

	ui._on_available_pressed(null, A)
	ui._on_available_pressed(null, B)
	_eq(m.target_item_ids, [A, B], "added to shop pool")
	ui._on_available_pressed(null, A)
	_eq(m.target_item_ids, [B], "clicking again removes")

	# 箱子：独立
	ui._mode_buttons[ui.POOL_CRATE][m.Mode.SEQUENTIAL].emit_signal("pressed")
	_eq(m.crate_mode, m.Mode.SEQUENTIAL, "crate mode set")
	_eq(ui._active_pool, ui.POOL_CRATE, "switching to a pool mode activates the crate pool")
	ui._on_available_pressed(null, C1)
	yield(tree, "idle_frame")
	_eq(m.crate_item_ids, [C1], "added to crate pool")
	_eq(m.target_item_ids, [B], "shop pool unchanged")
	_eq(ui._pool_scrolls[ui.POOL_CRATE].visible, true, "crate pool shown")

	# T4 箱子：单次
	ui._mode_buttons[ui.POOL_LEGENDARY][m.Mode.ONCE].emit_signal("pressed")
	_eq(m.legendary_mode, m.Mode.ONCE, "T4 mode set")
	_eq(ui._active_pool, ui.POOL_LEGENDARY, "switching to a pool mode activates the T4 pool")
	ui._on_available_pressed(null, L1)
	ui._on_available_pressed(null, L2)
	yield(tree, "idle_frame")
	_eq(m.legendary_item_ids, [L1, L2], "added to T4 pool")
	_eq(m.crate_item_ids, [C1], "crate pool unchanged")
	_eq(ui._descs[ui.POOL_LEGENDARY].text, "The first 2 T4 crates will be replaced with the following items.", "once desc shows N")

	ui._on_pool_item_pressed(null, ui.POOL_LEGENDARY, L1)
	yield(tree, "idle_frame")
	_eq(m.legendary_item_ids, [L2], "removed from T4 pool")
	_eq(ui._descs[ui.POOL_LEGENDARY].text, "The first 1 T4 crates will be replaced with the following items.", "desc updates N")

	ui._on_clear_pressed(ui.POOL_LEGENDARY)
	_eq(m.legendary_item_ids, [], "clear T4 pool")

	# 同商店 / 禁用：专用池隐藏，当前池回到商店
	ui._mode_buttons[ui.POOL_LEGENDARY][m.Mode.SHOP].emit_signal("pressed")
	_eq(ui._pool_scrolls[ui.POOL_LEGENDARY].visible, false, "T4 pool hidden for same as shop")
	_eq(ui._pool_empty[ui.POOL_LEGENDARY].visible, false, "T4 empty label hidden too")
	_eq(ui._active_pool, ui.POOL_SHOP, "falls back to the shop pool")
	ui._mode_buttons[ui.POOL_CRATE][m.Mode.NONE].emit_signal("pressed")
	_eq(m.crate_mode, m.Mode.NONE, "crate off")
	_eq(ui._descs[ui.POOL_CRATE].text, "Crates are still generated randomly.", "crate off desc")
	ui._mode_buttons[ui.POOL_CRATE][m.Mode.SHOP].emit_signal("pressed")
	_eq(ui._descs[ui.POOL_CRATE].text, "Crates use the shop pool.", "crate same-as-shop desc")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_26_ui_card_click_switches_pool() -> void:
	m.crate_mode = m.Mode.SEQUENTIAL
	m.legendary_mode = m.Mode.SEQUENTIAL
	var ui = yield(_open_ui(), "completed")
	yield(tree, "idle_frame")

	# 三张卡片并排，横向不重叠
	var rects = []
	for pool in ui.POOLS:
		rects.push_back(ui._pool_cards[pool].get_global_rect())
	for i in 2:
		_check(rects[i].end.x <= rects[i + 1].position.x + 0.5, "cards %d and %d do not overlap" % [i, i + 1])
		_check(abs(rects[i].position.y - rects[i + 1].position.y) < 1.0, "cards %d and %d share a row" % [i, i + 1])
	var panel = ui._pool_cards[0].get_parent().get_parent().get_parent()
	_eq(panel.rect_size.x, ui.PANEL_SIZE.x, "content does not widen the panel")
	_check(rects[2].end.x <= panel.get_global_rect().end.x, "cards stay inside the panel")

	# 卡片内任意位置：中心、说明文字、四个角附近
	for pool in ui.POOLS:
		var card = ui._pool_cards[pool]
		var r = card.get_global_rect()
		var points = [_center(card), _center(ui._descs[pool]), r.position + Vector2(3, 3), r.end - Vector2(3, 3)]
		for p in points:
			ui._active_pool = (pool + 1) % 3
			ui._select_pool_at(p)
			_eq(ui._active_pool, pool, "click card %d at %s" % [pool, str(p)])

	# 卡片外：不切换
	ui._active_pool = ui.POOL_LEGENDARY
	ui._select_pool_at(Vector2(1, 1))
	_eq(ui._active_pool, ui.POOL_LEGENDARY, "click outside keeps the pool")

	# 非独立 / 单次模式下箱子卡片不可选
	ui._active_pool = ui.POOL_SHOP
	ui._mode_buttons[ui.POOL_CRATE][m.Mode.NONE].emit_signal("pressed")
	ui._active_pool = ui.POOL_SHOP
	ui._select_pool_at(_center(ui._pool_cards[ui.POOL_CRATE]))
	_eq(ui._active_pool, ui.POOL_SHOP, "crate card not selectable when off")
	ui._mode_buttons[ui.POOL_LEGENDARY][m.Mode.SHOP].emit_signal("pressed")
	ui._active_pool = ui.POOL_SHOP
	ui._select_pool_at(_center(ui._pool_cards[ui.POOL_LEGENDARY]))
	_eq(ui._active_pool, ui.POOL_SHOP, "T4 card not selectable when same as shop")
	ui.queue_free()
	yield(tree, "idle_frame")


func test_27_ui_no_tooltips() -> void:
	var ui = yield(_open_ui(), "completed")
	var stack = [ui]
	var with_tooltip = 0
	while not stack.empty():
		var n = stack.pop_back()
		if n is Control and n.hint_tooltip != "":
			with_tooltip += 1
		for c in n.get_children():
			stack.push_back(c)
	_eq(with_tooltip, 0, "no control has a tooltip")
	ui.queue_free()
	yield(tree, "idle_frame")


# ============================================================
# 箱子模式（独立于 T4 箱子）
# ============================================================
func test_28_crate_modes() -> void:
	m.target_item_ids = [A]
	m.crate_item_ids = [L1, L2]
	# 同商店
	m.crate_mode = m.Mode.SHOP
	_eq(_crate(1, false), A, "same as shop uses the shop pool")
	_eq(_rand_item(2), A, "treasure map uses the shop pool")
	# 独立：A-B-A-B，不动商店计数器
	m.reset_counter()
	m.crate_mode = m.Mode.SEQUENTIAL
	var got: Array = []
	for i in 5:
		got.push_back(_crate(i, false))
	_eq(got, [L1, L2, L1, L2, L1], "A-B-A-B over the crate pool")
	_eq(_rand_item(7), L2, "treasure map continues the crate rotation")
	_eq(m.replace_counter, 0, "shop counter untouched")
	_eq(m.legendary_counter, 0, "T4 counter untouched")
	_eq(_crate(9, true), _baseline("_crate", [9, true]), "T4 crate unaffected by crate mode")
	# 单次：只替换前 N 个
	m.reset_counter()
	m.crate_mode = m.Mode.ONCE
	_eq(_crate(SEEDS[0], false), L1, "1st crate")
	_eq(_crate(SEEDS[1], false), L2, "2nd crate")
	for s in SEEDS:
		_eq(_crate(s, false), _baseline("_crate", [s, false]), "later crates are random (seed %d)" % s)
	_eq(m.crate_counter, 2, "counter stops at N")
	m.reset_counter()
	_eq(m.crate_counter, 0, "reset on new run")
	_eq(_crate(SEEDS[0], false), L1, "restarts after reset")
	# 禁用 / 独立池为空
	m.crate_mode = m.Mode.NONE
	_assert_no_effect_crate_only("crate off")
	m.crate_mode = m.Mode.SEQUENTIAL
	m.crate_item_ids = []
	_assert_no_effect_crate_only("independent with empty pool")
	m.crate_mode = m.Mode.ONCE
	_assert_no_effect_crate_only("one-time with empty pool")


func _assert_no_effect_crate_only(label: String) -> void:
	m.target_item_ids = []
	m.reset_counter()
	for s in SEEDS:
		_eq(_crate(s, false), _baseline("_crate", [s, false]), label + ": crate seed %d" % s)
		_eq(_rand_item(s), _baseline("_rand_item", [s]), label + ": treasure map seed %d" % s)
	_eq(m.crate_counter, 0, label + ": counter untouched")


func test_29_crate_and_t4_pools_are_independent() -> void:
	m.target_item_ids = [A]
	m.crate_item_ids = [B]
	m.legendary_item_ids = [L1]
	m.crate_mode = m.Mode.SEQUENTIAL
	m.legendary_mode = m.Mode.SEQUENTIAL
	_eq(_crate(1, false), B, "crate pool")
	_eq(_crate(2, true), L1, "T4 pool")
	m.crate_mode = m.Mode.SHOP
	_eq(_crate(3, false), A, "crate switches to the shop pool")
	_eq(_crate(4, true), L1, "T4 unchanged")
	m.legendary_mode = m.Mode.SHOP
	_eq(_crate(5, true), A, "T4 same as shop")


func test_30_master_switch_covers_crates() -> void:
	m.target_item_ids = [A]
	m.crate_item_ids = [B]
	m.crate_mode = m.Mode.SEQUENTIAL
	m.enabled = false
	var orig = _item(L2)
	_check(m.get_crate_replacement(orig, 0) == orig, "disabled returns the original")
	_eq(m.crate_counter, 0, "counter untouched while disabled")


# ============================================================
# 导入 / 导出
# ============================================================
func test_31_share_code_roundtrip() -> void:
	m.enabled = false
	m.force_cursed = true
	m.target_item_ids = [A, B]
	m.crate_item_ids = [C1]
	m.crate_mode = m.Mode.ONCE
	m.legendary_item_ids = [L1, L2]
	m.legendary_mode = m.Mode.SEQUENTIAL
	m.cfg_replace_starting = true
	m.cfg_replace_shop = false
	m.cfg_replace_shop_first = true
	var code: String = m.export_settings_code()
	_check(code.begins_with(m.SHARE_PREFIX), "code has the prefix")
	_reset()
	_eq(m.target_item_ids, [], "reset cleared the pool")
	_check(m.import_settings_code("  " + code + "\n"), "import succeeds (whitespace tolerated)")
	_eq(m.enabled, false, "enabled")
	_eq(m.force_cursed, true, "force_cursed")
	_eq(m.target_item_ids, [A, B], "shop pool")
	_eq(m.crate_item_ids, [C1], "crate pool")
	_eq(m.crate_mode, m.Mode.ONCE, "crate mode")
	_eq(m.legendary_item_ids, [L1, L2], "T4 pool")
	_eq(m.legendary_mode, m.Mode.SEQUENTIAL, "T4 mode")
	_eq(m.cfg_replace_starting, true, "starting")
	_eq(m.cfg_replace_shop, false, "all items in shop")
	_eq(m.cfg_replace_shop_first, true, "shops always sell")
	# 导入后写入本地设置
	_reset()
	m._load_settings()
	_eq(m.target_item_ids, [A, B], "import persisted to the settings file")
	_remove(m.SETTINGS_PATH)


func test_32_share_code_rejects_garbage() -> void:
	m.target_item_ids = [A]
	m.crate_mode = m.Mode.ONCE
	for bad in ["", "hello", "OITRTA1:", "OITRTA1:!!!", "OITRTA1:" + Marshalls.utf8_to_base64("[1,2]"), "OITRTA1:" + Marshalls.utf8_to_base64("{\"x\":1}"), "AA1:" + Marshalls.utf8_to_base64("{}")]:
		_check(not m.import_settings_code(bad), "rejects %s" % bad)
	_eq(m.target_item_ids, [A], "settings untouched after failures")
	_eq(m.crate_mode, m.Mode.ONCE, "mode untouched after failures")


func test_33_ui_import_export() -> void:
	TranslationServer.set_locale("en")
	m.target_item_ids = [A]
	m.crate_item_ids = [B]
	m.crate_mode = m.Mode.SEQUENTIAL
	m.legendary_mode = m.Mode.ONCE
	m.legendary_item_ids = [L1]
	var ui = yield(_open_ui(), "completed")
	ui.test_clipboard = ""
	ui._on_export_pressed()
	_check(ui.test_clipboard.begins_with(m.SHARE_PREFIX), "export puts a code on the clipboard")
	_eq(ui._status.text, "Settings copied to the clipboard as a share code.", "export status")
	var code = ui.test_clipboard

	# 改乱设置后导入，UI 同步刷新
	ui._mode_buttons[ui.POOL_CRATE][m.Mode.NONE].emit_signal("pressed")
	ui._mode_buttons[ui.POOL_LEGENDARY][m.Mode.NONE].emit_signal("pressed")
	ui._on_clear_pressed(ui.POOL_SHOP)
	ui._option_chips["cfg_replace_starting"].pressed = true
	ui._enable_switch.pressed = false
	ui.test_clipboard = code
	ui._on_import_pressed()
	_eq(ui._status.text, "Settings imported from the clipboard.", "import status")
	_eq(m.target_item_ids, [A], "shop pool restored")
	_eq(m.crate_mode, m.Mode.SEQUENTIAL, "crate mode restored")
	_eq(m.legendary_mode, m.Mode.ONCE, "T4 mode restored")
	_eq(ui._enable_switch.pressed, true, "enable switch synced")
	_eq(ui._option_chips["cfg_replace_starting"].pressed, false, "chip synced")
	_eq(ui._mode_buttons[ui.POOL_CRATE][m.Mode.SEQUENTIAL].pressed, true, "crate mode button synced")
	_eq(ui._pool_scrolls[ui.POOL_CRATE].visible, true, "crate pool shown")
	_eq(ui._pool_rows[ui.POOL_SHOP].get_child_count(), 1, "shop pool contents rebuilt")

	ui.test_clipboard = "nonsense"
	ui._on_import_pressed()
	_eq(ui._status.text, "The clipboard does not contain a valid share code; nothing was changed.", "failure status")
	_eq(m.target_item_ids, [A], "nothing changed after a failed import")
	ui.queue_free()
	yield(tree, "idle_frame")
	_remove(m.SETTINGS_PATH)
