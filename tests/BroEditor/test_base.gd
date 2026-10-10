extends Reference

# BroEditor 无头测试的公共基类：状态、工具函数、运行流程；测试分在 suite_core / suite_ui / suite_battle / suite_compat.gd。
# 由 run_be.gd 在 autoload 就绪后加载；请使用同目录的 run_tests.sh（会同步 mod、隔离 user://）。

const MOD_ID = "Mojimoon-BroEditor"
const MOD_DIR = "res://mods-unpacked/" + MOD_ID + "/"

var m
var isvc
var rd
var tree: SceneTree
var _current_test = ""
# 各组共用的计数（run_be.gd 依次运行选中的测试组）
var ctx: Dictionary = {"checks": 0, "failures": []}
# 测试用角色（第一个原版角色）
var CH: String


func setup(p_tree: SceneTree, p_ctx: Dictionary) -> int:
	tree = p_tree
	ctx = p_ctx
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
	return 0


# 运行本组的 test_ 方法（BE_ONLY 按名字过滤）
func run_suite():
	var only = OS.get_environment("BE_ONLY")
	var tests: Array = []
	for method in get_method_list():
		if method.name.begins_with("test_") and (only == "" or method.name.find(only) >= 0):
			tests.push_back(method.name)
	tests.sort()
	for t in tests:
		_current_test = t
		_reset()
		var c0 = ctx.checks
		var state = call(t)
		if state is GDScriptFunctionState:
			yield(state, "completed")
		print("  ran %s (%d checks)" % [t, ctx.checks - c0])
	_reset()


func finish() -> int:
	print("")
	print("%d checks, %d failures" % [ctx.checks, ctx.failures.size()])
	for f in ctx.failures:
		printerr("FAIL ", f)
	if ctx.failures.empty():
		print("ALL TESTS PASSED")
	return 0 if ctx.failures.empty() else 1


func _check(cond: bool, msg: String) -> void:
	ctx.checks += 1
	if not cond:
		ctx.failures.push_back(_current_test + ": " + msg)


# Godot 3 的字典 == 比较引用：字典按 JSON 比较
func _eq(actual, expected, msg: String) -> void:
	if actual is Dictionary or expected is Dictionary:
		_check(JSON.print(actual) == JSON.print(expected), "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])
		return
	_check(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


const WAVE = 8


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


func _frames(n: int):
	for i in n:
		yield(tree, "idle_frame")


func _on_sel(k, got: Array) -> void:
	got.push_back(k)


func _action_has_key(action: String, sc: int) -> bool:
	for ev in InputMap.get_action_list(action):
		if ev is InputEventKey and (ev.scancode == sc or ev.physical_scancode == sc):
			return true
	return false


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


# 效果列表里的真实效果（去掉初始属性 / 初始装备 / 蓝图的分组占位）
func _real(specs: Array) -> Array:
	var out = []
	for s in specs:
		if not (s is Dictionary and s.has("group")):
			out.push_back(s)
	return out


func _tree_has_text(n: Node, t: String) -> bool:
	if n is Label and n.text.find(t) >= 0:
		return true
	for c in n.get_children():
		if _tree_has_text(c, t):
			return true
	return false


func _plain_item():
	for it in isvc.items:
		if it.tier == 0 and it.max_nb == -1 and not it.effects.empty():
			return it
	return isvc.items[0]


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
