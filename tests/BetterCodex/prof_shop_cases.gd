extends Reference

var tree: SceneTree
var cases
var _prev = [0, 0, 0]


func _ms(t0) -> String:
	return "%.2f ms" % ((OS.get_ticks_usec() - t0) / 1000.0)


func _frames(n: int, label: String):
	var times = []
	var last = OS.get_ticks_usec()
	for i in n:
		yield(tree, "idle_frame")
		var now = OS.get_ticks_usec()
		times.push_back((now - last) / 1000.0)
		if (now - last) > 30000 and OS.get_environment("BC_MON") != "":
			print("  spike f%d %.0fms: process %.1fms physics %.1fms nodes %d objects %d resources %d mem %.1fMB" % [Engine.get_idle_frames(), (now - last) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
			print("  prev     : nodes %d objects %d resources %d" % _prev)
		_prev = [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)]
		last = now
	var sorted = times.duplicate()
	sorted.sort()
	var spikes = []
	for i in times.size():
		if times[i] > 30:
			spikes.push_back("#%d(f%d)=%.0f" % [i, Engine.get_idle_frames() - n + i, times[i]])
	print("%s: median %.2f ms, p95 %.2f, max %.2f, spikes>30ms %s" % [label, sorted[n / 2], sorted[int(n * 0.95)], sorted[n - 1], str(spikes)])


func run(t):
	tree = t
	cases = load("res://mods/tests/BetterCodex/test_cases.gd").new()
	cases.tree = tree
	cases._unlock_everything()
	var m = tree.root.get_node_or_null("ModLoader/Mojimoon-BetterCodex")
	if m == null:	# 不加载 mod：只看原版商店的帧时间
		RunData.set_player_count(1, true)
		RunData.players_data[0].current_character = ItemService.characters[0]
		RunData.players_data[0].items = [ItemService.characters[0]]
		RunData.current_wave = 5
		ItemService.init_unlocked_pool()
		var s = load("res://ui/menus/shop/shop.tscn").instance()
		tree.current_scene = s
		tree.root.add_child(s)
		yield(_frames(240, "VANILLA shop idle 240 frames"), "completed")
		yield(_rerolls(s, 40, "VANILLA"), "completed")
		return
	cases._setup_player()
	m.settings.mut_preview = OS.get_environment("BC_MUT") if OS.get_environment("BC_MUT") != "" else "default"
	for id in ["item_alien_eyes", "item_baby_elephant", "item_coffee", "item_cyberball", "item_lens"]:
		var it = cases._item(id)
		if it != null:
			RunData.players_data[0].items.push_back(it)
	RunData.bc_reset_mutable_counts()
	RunData.current_wave = 5
	ItemService.init_unlocked_pool()
	print("mut_preview=%s preview_on=%s" % [m.settings.mut_preview, load("res://mods-unpacked/Mojimoon-BetterCodex/ui/shop_hook.gd").mutation_preview_on()])

	# node_added 开销：统计商店加载时的调用次数
	if OS.get_environment("BC_NOHOOK") != "":
		tree.disconnect("node_added", m, "_on_node_added")
	var t0 = OS.get_ticks_usec()
	var shop = load("res://ui/menus/shop/shop.tscn").instance()
	print("shop instance: " + _ms(t0))
	t0 = OS.get_ticks_usec()
	tree.current_scene = shop	# 与 change_scene 相同：先设 current_scene 再进树
	tree.root.add_child(shop)
	print("shop add_child (incl. _ready, node_added): " + _ms(t0))
	var n_nodes = cases._all(shop).size()
	t0 = OS.get_ticks_usec()
	for i in n_nodes:
		m._on_node_added(shop.get_child(0))
	print("node_added x%d direct cost: %s" % [n_nodes, _ms(t0)])

	yield(_frames(240, "shop idle 240 frames (prewarm inside)"), "completed")
	yield(_frames(120, "shop idle after prewarm"), "completed")
	yield(_rerolls(shop, 40, "MOD mut=" + m.settings.mut_preview), "completed")
	if OS.get_environment("BC_REROLL_ONLY") != "":
		# 下一波：买过的道具次数增加，再进一个新商店（图鉴应保留，不重建）
		tree.root.remove_child(shop)
		shop.free()
		yield(tree, "idle_frame")
		var it = cases._item("item_coffee")
		ProgressData.items_bought[it.my_id_hash] = ProgressData.items_bought.get(it.my_id_hash, 0) + 1
		var shop2 = load("res://ui/menus/shop/shop.tscn").instance()
		tree.current_scene = shop2
		tree.root.add_child(shop2)
		yield(_frames(120, "second shop"), "completed")
		var h2 = shop2.get_node("BCShopHook")
		t0 = OS.get_ticks_usec()
		h2.open(it)
		print("second shop: open codex " + _ms(t0))
		return

	var hook = shop.get_node("BCShopHook")
	var codex = hook.codex
	if OS.get_environment("BC_STEADY") != "":
		hook.hint.visible = false
		yield(_frames(120, "hint hidden"), "completed")
		hook.hint.visible = true
		var pc = shop.get_node("PauseMenu/Menus/MenuCodex")
		pc.set_process(false)
		codex.set_process(false)
		yield(_frames(120, "both codex _process off"), "completed")
		pc.set_process(true)
		codex.set_process(true)
		shop.remove_child(codex)
		yield(_frames(120, "hook codex removed from tree"), "completed")
		shop.add_child(codex)
		var pm = shop.get_node("PauseMenu/Menus")
		pm.remove_child(pc)
		yield(_frames(120, "pause codex removed too"), "completed")
		shop.remove_child(codex)
		yield(_frames(120, "both removed"), "completed")
		shop.remove_child(hook)
		yield(_frames(120, "hook removed"), "completed")
		return
	t0 = OS.get_ticks_usec()
	codex._bc_last_signature = null
	codex.bc_prewarm()
	print("prewarm (forced rebuild): " + _ms(t0))

	# 商品卡片描述：原版 set_item vs 加异变预览
	var cards = []
	for n in cases._all(shop):
		if n is ShopItem and n.item_data != null and n.is_visible_in_tree():
			cards.push_back(n)
	var desc_script = load("res://ui/menus/shop/item_description.gd")
	for card in cards:
		var d = card._item_description
		t0 = OS.get_ticks_usec()
		for i in 10:
			d.set_item(card.item_data, 0)
		var full = (OS.get_ticks_usec() - t0) / 10000.0
		t0 = OS.get_ticks_usec()
		for i in 10:
			d._bc_add_mutation_preview(card.item_data, 0)
		var ours = (OS.get_ticks_usec() - t0) / 10000.0
		print("card %s: set_item %.2f ms, of which mutation preview %.2f ms" % [card.item_data.my_id, full, ours])

	# 悬停弹窗
	var popup = shop._get_item_popup(0)
	var els = []
	for n in cases._all(shop):
		if n is InventoryElement and n.item != null and n.is_visible_in_tree():
			els.push_back(n)
	t0 = OS.get_ticks_usec()
	for e in els:
		popup.display_item_data(e.item, e, true)
	print("popup x%d: %s" % [els.size(), _ms(t0)])

	# 买卖：gold_changed → update_hint
	t0 = OS.get_ticks_usec()
	for i in 20:
		hook.update_hint()
	print("update_hint x20: " + _ms(t0))
	hook._can_drop = "x"
	t0 = OS.get_ticks_usec()
	hook.update_hint()
	print("update_hint with card refresh: " + _ms(t0))
	t0 = OS.get_ticks_usec()
	for i in 20:
		RunData.add_item(cases._item("item_coffee"), 0)
		RunData.remove_item(cases._item("item_coffee"), 0)
	print("add+remove item x20: " + _ms(t0))

	# 输入：鼠标移动（不处理）、右键命中测试
	var ev = InputEventMouseMotion.new()
	t0 = OS.get_ticks_usec()
	for i in 1000:
		hook._input(ev)
	print("_input mouse motion x1000: " + _ms(t0))
	t0 = OS.get_ticks_usec()
	for i in 20:
		hook._node_at(shop, Vector2(500, 500))
	print("right-click hit test x20: " + _ms(t0))



# 刷新商店 n 次（每次之间等 2 帧），统计刷新那一帧的耗时
func _rerolls(shop, n: int, label: String):
	var times = []
	for i in n:
		RunData.players_data[0].gold = 100000
		var t0 = OS.get_ticks_usec()
		shop._on_RerollButton_pressed(0)
		yield(tree, "idle_frame")
		times.push_back((OS.get_ticks_usec() - t0) / 1000.0)
		yield(tree, "idle_frame")
	var sorted = times.duplicate()
	sorted.sort()
	print("%s reroll x%d: median %.1f ms, p90 %.1f, max %.1f" % [label, n, sorted[n / 2], sorted[int(n * 0.9)], sorted[n - 1]])
