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
	m.profiles[ch] = p
	m.apply_all()
	for target in [ch, custom]:
		var ui = load("res://mods-unpacked/Mojimoon-BroEditor/ui/editor_ui.tscn").instance()
		ui.initial_id = target
		root.add_child(ui)
		for t in ["overview", "stats", "effects", "gear", "bans"]:
			ui._on_tab_pressed(t)
			if t == "effects":
				ui._on_effect_edit(1)
			for i in 6:
				yield(self, "idle_frame")
			var img = root.get_texture().get_data()
			img.flip_y()
			img.save_png(out + "/" + target + "_" + t + ".png")
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
