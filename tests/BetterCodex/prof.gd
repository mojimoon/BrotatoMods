extends SceneTree

# 图鉴打开耗时（非测试）：godot --no-window --path 1.2 -s res://mods/tests/BetterCodex/prof.gd

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var cases = load("res://mods/tests/BetterCodex/test_cases.gd").new()
	cases.tree = self
	cases._unlock_everything()
	cases._setup_player()
	var codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
	codex.name = "MenuCodex"
	root.add_child(codex)
	yield(self, "idle_frame")
	var tf = OS.get_ticks_usec()
	codex._bc_clean_frame()
	print("frame clean: %d ms" % ((OS.get_ticks_usec() - tf) / 1000))
	for i in 4:
		var t0 = OS.get_ticks_usec()
		codex._bc_free_detached()
		var t1 = OS.get_ticks_usec()
		codex.get_script().get_base_script()	# noop
		codex._bc_unlock_begin()
		var vanilla = load("res://ui/menus/pages/menu_codex.gd")
		var t2 = OS.get_ticks_usec()
		codex._pop()
		var t3 = OS.get_ticks_usec()
		print("open %d: total %d ms" % [i, (t3 - t0) / 1000])
		codex._bc_unlock_end()
		yield(self, "idle_frame")
		yield(self, "idle_frame")
		codex._on_BackButton_pressed()
		yield(self, "idle_frame")
	var t9 = OS.get_ticks_usec()
	codex.tab_challenge.set_elements(true)
	print("challenges: %d ms" % ((OS.get_ticks_usec() - t9) / 1000))
	t9 = OS.get_ticks_usec()
	codex.inventory_enemies.set_elements(root.get_node("ItemService").entities.duplicate())
	print("enemies: %d ms" % ((OS.get_ticks_usec() - t9) / 1000))
	t9 = OS.get_ticks_usec()
	for tab in codex._bc_tabs:
		codex._bc_tabs[tab].extras.reset_defaults()
		codex._bc_fill_options(tab)
		codex._bc_grey_banned(tab)
	print("extras+options+grey: %d ms" % ((OS.get_ticks_usec() - t9) / 1000))
	t9 = OS.get_ticks_usec()
	codex._bc_signature()
	print("signature: %d ms" % ((OS.get_ticks_usec() - t9) / 1000))
	# 分段：原版 _pop 与各个扩展步骤
	var t = OS.get_ticks_usec()
	codex._bc_free_detached()
	codex._bc_temp = null
	var Vanilla = load("res://ui/menus/pages/menu_codex.gd")
	t = OS.get_ticks_usec()
	codex.call("_bc_setup")
	print("bc_setup only: %d ms" % ((OS.get_ticks_usec() - t) / 1000))
	for tab in codex._bc_tabs:
		var tt = codex._bc_tabs[tab]
		t = OS.get_ticks_usec()
		for e in tt.all:
			if e.has_node("BCBadges"):
				var b = e.get_node("BCBadges")
				e.remove_child(b)
				b.free()
		for e in tt.all:
			codex._bc_add_badges(e, tab)
		print("%s badges: %d ms" % [tab, (OS.get_ticks_usec() - t) / 1000])
		t = OS.get_ticks_usec()
		codex._bc_fill_options(tab)
		print("%s options: %d ms" % [tab, (OS.get_ticks_usec() - t) / 1000])
		t = OS.get_ticks_usec()
		codex._bc_apply(tab)
		print("%s apply: %d ms" % [tab, (OS.get_ticks_usec() - t) / 1000])
	t = OS.get_ticks_usec()
	codex.inventory_items.set_elements(root.get_node("ItemService").items.duplicate())
	print("vanilla set_elements items: %d ms" % ((OS.get_ticks_usec() - t) / 1000))
	quit()
