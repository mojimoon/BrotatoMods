extends SceneTree

# 截图检查界面布局（非测试；需要窗口）：godot --path . -s res://mods/tests/BroEditor/shot.gd
# 输出到环境变量 BE_SHOT_DIR

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var out = OS.get_environment("BE_SHOT_DIR")
	var m = root.get_node("ModLoader/Mojimoon-BroEditor")
	var isvc = root.get_node("ItemService")
	var ch = isvc.characters[2].my_id
	var custom = m.create_custom(ch)
	var p = m.new_profile()
	p.stats = {"stat_armor": 5, "items_price": -10}
	p.ban_items = [isvc.items[0].my_id, isvc.items[3].my_id]
	p.desc = "测试介绍：一个会编辑的土豆"
	p.start = {"materials": 30, "levels": 2}
	var GE = load("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
	var g = GE.new_graph()
	var tk = GE.add_node(g, "kill", Vector2(20, 40))
	var c1 = GE.add_node(g, "chance", Vector2(320, 40), {"pct": 20})
	var e1 = GE.add_node(g, "explode", Vector2(620, 40))
	var t2 = GE.add_node(g, "still", Vector2(20, 300))
	var e2 = GE.add_node(g, "temp_stat", Vector2(620, 300))
	GE.add_link(g, tk, c1)
	GE.add_link(g, c1, e1)
	GE.add_link(g, t2, e2)
	p.graph = g
	m.profiles[ch] = p
	m.apply_all()
	for target in [ch, custom]:
		var ui = load("res://mods-unpacked/Mojimoon-BroEditor/ui/editor_ui.tscn").instance()
		ui.initial_id = target
		root.add_child(ui)
		for t in ["overview", "stats", "effects", "blueprint", "gear", "bans"]:
			ui._on_tab_pressed(t)
			if t == "effects":
				ui._on_effect_edit(1)
			for i in 6:
				yield(self, "idle_frame")
			var img = root.get_texture().get_data()
			img.flip_y()
			img.save_png(out + "/" + target + "_" + t + ".png")
			if t == "stats" and target != "":
				var sc = ui._page.get_child(1)
				for off in [560, 1100]:
					sc.scroll_vertical = off
					for i in 4:
						yield(self, "idle_frame")
					var im = root.get_texture().get_data()
					im.flip_y()
					im.save_png(out + "/" + target + "_stats_" + str(off) + ".png")
			if t == "blueprint":
				var gn = null
				for c in ui.blueprint.ge.get_children():
					if c is GraphNode and c.title.find("属性") >= 0:
						gn = c
				var sel = ui.blueprint.ge.get_parent().get_parent().get_child(0).get_child(2)
				for c in ui.find_node("*", true, false).get_children() if false else []:
					pass
				sel.open()
				sel._on_search("")
				for i in 4:
					yield(self, "idle_frame")
				var img3 = root.get_texture().get_data()
				img3.flip_y()
				img3.save_png(out + "/" + target + "_select.png")
				sel.close()
		if target == ch:
			ui._open_picker("start_weapons")
			for i in 6:
				yield(self, "idle_frame")
			var img2 = root.get_texture().get_data()
			img2.flip_y()
			img2.save_png(out + "/picker.png")
			ui._close_picker()
		ui.queue_free()
		yield(self, "idle_frame")
	quit()
