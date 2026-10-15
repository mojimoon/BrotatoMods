extends SceneTree

# 截图检查界面布局（非测试；需要窗口）：godot --path . -s res://mods/tests/BroEditor/shot.gd
# 输出到环境变量 BE_SHOT_DIR

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var out = OS.get_environment("BE_SHOT_DIR")
	var m = root.get_node("ModLoader/Mojimoon-BroEditor")
	var isvc = root.get_node("ItemService")
	if OS.get_environment("BE_SHOT_HOVER") != "":
		yield(_hover(m, out), "completed")
		quit()
		return
	if OS.get_environment("BE_SHOT_GROUPS") != "":
		yield(_groups(m, out), "completed")
		quit()
		return
	if OS.get_environment("BE_SHOT_SETS") != "":
		yield(_sets(m, out), "completed")
		quit()
		return
	if OS.get_environment("BE_SHOT_KINDS") != "":
		yield(_kinds(m, out), "completed")
		quit()
		return
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
		m.debug = target == custom
		if target == custom:
			m.profiles[custom].stats = {"stat_armor": 2}
			m.profiles[custom].graph = p.graph.duplicate(true)
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



# 道具 / 武器栏的截图
func _kinds(m, out: String):
	var ui = load("res://mods-unpacked/Mojimoon-BroEditor/ui/editor_ui.tscn").instance()
	root.add_child(ui)
	yield(self, "idle_frame")
	ui._on_filter("dlc1", "src")
	yield(_shot(ui, out + "/char_dlc1.png"), "completed")
	ui._on_filter("all", "src")
	for kind in ["item", "weapon"]:
		ui.set_kind(kind)
		ui._on_filter(2, "tier")
		ui._select(ui._first_listed())
		if kind == "weapon":
			ui._on_wstat_changed(99.0, ["damage", "int", ""])
		ui._on_disable_toggled(true)
		for t in ["overview", "stats", "effects"]:
			ui._on_tab_pressed(t)
			yield(_shot(ui, out + "/" + kind + "_" + t + ".png"), "completed")
		ui._on_filter(-1, "tier")
		ui._on_new_custom()
		ui._on_tab_pressed("overview")
		yield(_shot(ui, out + "/" + kind + "_custom.png"), "completed")
	ui.queue_free()
	yield(self, "idle_frame")


func _shot(ui, path: String):
	for i in 6:
		yield(self, "idle_frame")
	var img = root.get_texture().get_data()
	img.flip_y()
	img.save_png(path)


# 悬停预览：左侧列表、初始装备页（含融合角色）
func _hover(m, out: String):
	var isvc = root.get_node("ItemService")
	var ch = isvc.characters[0].my_id
	var p = m.new_profile()
	p.fuse = [isvc.characters[3].my_id]
	p.start_items = [{"id": isvc.items[5].my_id, "n": 1}]
	m.profiles[ch] = p
	m.apply_all()
	var ui = load("res://mods-unpacked/Mojimoon-BroEditor/ui/editor_ui.tscn").instance()
	ui.initial_id = ch
	root.add_child(ui)
	yield(self, "idle_frame")
	var b = ui._char_grid.get_child(4)
	ui._show_preview(b, isvc.characters[4])
	yield(_shot(ui, out + "/hover_list.png"), "completed")
	ui._on_tab_pressed("gear")
	yield(self, "idle_frame")
	var btns = []
	for n in _nodes(ui._page):
		if n is Button and n.icon != null:
			btns.push_back(n)
	ui._show_preview(btns[-1], isvc.characters[3])
	yield(_shot(ui, out + "/hover_fuse.png"), "completed")
	ui.set_kind("weapon")
	yield(self, "idle_frame")
	ui._show_preview(ui._char_grid.get_child(2), m.find_target("weapon", ui._char_grid.get_child(2).get_meta("id")))
	yield(_shot(ui, out + "/hover_weapon.png"), "completed")
	ui.queue_free()
	yield(self, "idle_frame")


# 武器类别管理弹窗：原版类别（展开一条效果）、自定义类别、效果库
func _sets(m, out: String):
	var ui = load("res://mods-unpacked/Mojimoon-BroEditor/ui/editor_ui.tscn").instance()
	root.add_child(ui)
	yield(self, "idle_frame")
	ui.set_kind("weapon")
	ui._select("weapon_knife_1")
	ui.open_set_manager()
	ui._on_set_select("set_blade")
	ui._on_set_effect_edit("0:0")
	yield(_shot(ui, out + "/sets_vanilla.png"), "completed")
	ui._on_set_new()
	yield(_shot(ui, out + "/sets_custom.png"), "completed")
	ui._open_set_library(1)
	yield(_shot(ui, out + "/sets_library.png"), "completed")
	m.weapon_sets.clear()
	ui.queue_free()
	yield(self, "idle_frame")


# 内容分组：概览页的分组、管理弹窗；蓝图新节点
func _groups(m, out: String):
	var isvc = root.get_node("ItemService")
	var ch = isvc.characters[0].my_id
	var gid = m.create_group("Test Series")
	m.toggle_group_member(gid, "character", ch)
	m.toggle_group_member(gid, "item", isvc.items[3].my_id)
	m.create_group("Other")
	var ui = load("res://mods-unpacked/Mojimoon-BroEditor/ui/editor_ui.tscn").instance()
	ui.initial_id = ch
	root.add_child(ui)
	yield(self, "idle_frame")
	ui._on_tab_pressed("overview")
	yield(_shot(ui, out + "/groups_overview.png"), "completed")
	ui.open_group_manager()
	yield(_shot(ui, out + "/groups_manager.png"), "completed")
	ui._modals[-1].close()
	ui._on_tab_pressed("blueprint")
	yield(self, "idle_frame")
	for k in ["own_tag", "own_set", "shop_force", "group_unlock"]:
		ui.blueprint.add_node_kind(k)
	yield(_shot(ui, out + "/groups_blueprint.png"), "completed")
	for g in m.groups.keys():
		m.delete_group(g)
	m.profiles.erase(ch)
	ui.queue_free()
	yield(self, "idle_frame")


func _nodes(n: Node) -> Array:
	var out = []
	for c in n.get_children():
		out.push_back(c)
		out += _nodes(c)
	return out
