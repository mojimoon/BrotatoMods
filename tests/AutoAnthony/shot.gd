extends SceneTree

# 截图检查设置界面布局（非测试；需要窗口）：godot --path . -s res://mods/tests/AutoAnthony/shot.gd
# 输出到环境变量 AA_SHOT_DIR；每种字体大小（80 / 100 / 125%）各截三个页签

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var out = OS.get_environment("AA_SHOT_DIR")
	if OS.get_environment("AA_LOCALE") != "":
		TranslationServer.set_locale(OS.get_environment("AA_LOCALE"))
	var m = root.get_node("ModLoader/Mojimoon-AutoAnthony")
	m.cfg_weapons = true
	var ui = load("res://mods-unpacked/Mojimoon-AutoAnthony/ui/settings_ui.tscn").instance()
	root.add_child(ui)
	ui._on_preview_pressed("items")
	ui._on_preview_pressed("weapons")
	for scale in [80, 100, 125]:
		ui._on_slider_changed(float(scale), "cfg_font_scale")
		for page in ["items", "weapons", "characters"]:
			ui._on_page_pressed(page)
			for i in 6:
				yield(self, "idle_frame")
			print("panel ", scale, " ", page, " ", ui.get_child(1).get_child(0).rect_size)
			var img = root.get_texture().get_data()
			img.flip_y()
			img.save_png(out + "/" + str(scale) + "_" + page + ".png")
	m.cfg_weapons = false
	quit()
