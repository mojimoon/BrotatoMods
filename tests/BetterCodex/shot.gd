extends SceneTree

# 截图检查布局（需要窗口）：godot --path 1.2 -s res://mods/tests/BetterCodex/shot.gd，输出到 BC_SHOT_DIR

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var out = OS.get_environment("BC_SHOT_DIR")
	var cases = load("res://mods/tests/BetterCodex/test_cases.gd").new()
	cases.tree = self
	if OS.get_environment("BC_SHOT_FONT") != "":
		root.get_node("ProgressData").set_font_size(float(OS.get_environment("BC_SHOT_FONT")))
	cases._unlock_everything()
	cases._setup_player()
	var codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
	codex.name = "MenuCodex"
	root.add_child(codex)
	yield(_wait(3), "completed")
	codex._pop()
	codex.bc_show_tab("items")
	yield(_wait(3), "completed")
	var it = null
	for x in root.get_node("ItemService").items:
		if x.replaced_by != null and x.tags.size() > 0:
			it = x
			break
	codex.bc_focus_item(it, "items")
	yield(_wait(5), "completed")
	codex._bc_tabs.items.extras.curse_band = [30, 60, 90]
	codex._bc_tabs.items.extras.show_item(codex._bc_tabs.items.current)
	yield(_wait(2), "completed")
	codex._bc_tabs.items.extras._curse_btn.pressed = true
	codex._bc_tabs.items.extras._on_mut_toggled(true)
	yield(_shot(out + "/items.png"), "completed")
	codex._bc_tabs.items.ui.tag._open()
	yield(_shot(out + "/tag_grid.png"), "completed")
	codex._bc_tabs.items.ui.tag._popup.hide()
	codex.bc_show_tab("weapons")
	for e in codex._bc_tabs.weapons.all:
		if e.item.my_id == "weapon_smg_1":
			codex._on_InventoryWeapons_element_pressed(e)
	yield(_wait(5), "completed")
	yield(_shot(out + "/weapons.png"), "completed")
	codex._bc_open_settings()
	yield(_shot(out + "/settings.png"), "completed")
	codex._bc_settings_popup.hide()
	var sc = codex.get_node("root/BetterTabContainer/TabContainer/tab_weapons/HBoxContainer/VBoxContainer/scroll_right_weapons")
	sc.scroll_vertical = 2000
	yield(_shot(out + "/weapons2.png"), "completed")
	codex.hide()
	codex.queue_free()
	var c = null
	for x in root.get_node("ItemService").characters:
		if x.wanted_tags.size() > 0 and x.banned_item_groups.size() > 0:
			c = x
			break
	cases._setup_player(c.my_id)
	var scene = load("res://ui/menus/run/weapon_selection.tscn").instance()
	root.add_child(scene)
	current_scene = scene
	yield(_shot(out + "/weapon_selection.png"), "completed")
	scene.queue_free()
	var diff = load("res://ui/menus/run/difficulty_selection/difficulty_selection.tscn").instance()
	root.add_child(diff)
	current_scene = diff
	yield(_shot(out + "/difficulty.png"), "completed")
	diff.queue_free()
	root.get_node("ItemService").init_unlocked_pool()
	root.get_node("RunData").current_wave = 4
	for id in ["item_alien_eyes", "item_baby_elephant", "item_coffee"]:
		root.get_node("RunData").add_item(cases._item(id), 0)
	var shop = load("res://ui/menus/shop/shop.tscn").instance()
	root.add_child(shop)
	current_scene = shop
	yield(_shot(out + "/shop.png"), "completed")
	for n in cases._all(shop):
		if n.get("item") != null and n.item.get("my_id") == "item_alien_eyes" and n.has_method("silouhette_if_hidden_in_codex"):
			shop._get_item_popup(0).display_item_data(n.item, n, true)
	yield(_shot(out + "/shop_popup.png"), "completed")
	quit()


func _wait(n):
	for i in n:
		yield(self, "idle_frame")


func _shot(path: String):
	for i in 8:
		yield(self, "idle_frame")
	var img = root.get_texture().get_data()
	img.flip_y()
	img.save_png(path)
