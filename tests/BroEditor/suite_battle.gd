extends "res://mods/tests/BroEditor/test_base.gd"

# battle：真实场景（战斗中的蓝图、读档继续）


func test_85_battle_graph() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var pairs = [
		["interval", {"secs": 1}, "add_gold", {"value": 1}],
		["still", {}, "temp_stat", {"stat": "stat_luck", "value": 50}],
		["hit", {}, "add_gold", {"value": 100}],
		["level_up", {}, "perm_stat", {"stat": "stat_armor", "value": 7}],
		["kill", {}, "add_gold", {"value": 1000}],
		["wave_start", {}, "perm_stat", {"stat": "stat_engineering", "value": 3}],
	]
	for pr in pairs:
		GE.add_link(g, GE.add_node(g, pr[0], Vector2.ZERO, pr[1]), GE.add_node(g, pr[2], Vector2.ZERO, pr[3]))
	var p = m.new_profile()
	p.graph = g
	m.profiles[CH] = p
	m.apply_all()
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_weapon(isvc.get_element_safe(isvc.weapons, "weapon_fist_1"), 0)
	rd.current_wave = 1
	TempStats.reset()
	var eng0 = rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0)
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(10), "completed")
	var main = tree.current_scene
	_check(not m.runtime.wave_over, "runtime started")
	_eq(rd.get_player_effect(Keys.generate_hash("stat_engineering"), 0), eng0 + 3, "wave_start fired")
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	var gold0 = rd.players_data[0].gold
	yield(tree.create_timer(1.5), "timeout")
	_check(rd.players_data[0].gold - gold0 >= 1, "interval fired")
	_eq(TempStats.get_stat(Keys.generate_hash("stat_luck"), 0), 50, "still state holds temp stat")
	player._move_locked = true
	player._current_movement = Vector2(1, 0)
	yield(tree.create_timer(0.6), "timeout")
	_eq(TempStats.get_stat(Keys.generate_hash("stat_luck"), 0), 0, "leaving state reverts")
	player._current_movement = Vector2.ZERO
	player._move_locked = false
	gold0 = rd.players_data[0].gold
	var hit_args = TakeDamageArgs.new(-1)
	hit_args.bypass_invincibility = true
	hit_args.dodgeable = false
	var _r = player.take_damage(1, hit_args)
	yield(tree, "physics_frame")
	yield(tree, "idle_frame")
	_check(rd.players_data[0].gold - gold0 >= 100, "hit fired")
	player._invincibility_timer.stop()
	player.disable_hurtbox()
	var armor0 = _armor()
	rd.add_xp(int(rd.get_next_level_xp_needed(0)) + 1, 0)
	yield(_frames(2), "completed")
	_eq(_armor(), armor0 + 7, "level_up fired")
	var enemy = null
	for i in 300:
		var es = main._entity_spawner.get_all_enemies(false)
		if not es.empty():
			enemy = es[0]
			break
		yield(tree, "idle_frame")
	_check(enemy != null, "enemy spawned")
	if enemy != null:
		gold0 = rd.players_data[0].gold
		var _k = enemy.take_damage(999999, TakeDamageArgs.new(0))
		yield(_frames(3), "completed")
		_check(rd.players_data[0].gold - gold0 >= 1000, "kill fired")
	main._on_WaveTimer_timeout()
	yield(_frames(2), "completed")
	_check(m.runtime.wave_over, "wave end stops runtime")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")


# 一局进行中删除自定义道具 / 武器后读档继续：不应报错（找不到的对象被原版读档逻辑跳过）
func test_150_resume_after_delete() -> void:
	var pd = tree.root.get_node("ProgressData")
	var cid = m.create_custom(CH)
	var iid = m.create_custom_item(_plain_item().my_id)
	var base = _family_from(0, 0)
	var wtier = m.create_custom_weapon(base[0].weapon_id)
	var wid = m.find_target("weapon", wtier).weapon_id
	while not m.family_complete(wid):
		var add = m.addable_tiers(wid)
		m.add_weapon_tier(wid, add[-1])
	m.apply_all()
	_setup_player(cid)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(cid), 0)
	rd.add_weapon(m.find_target("weapon", wtier), 0)
	rd.add_item(m.find_target("item", iid), 0)
	rd.current_wave = 3
	pd.save_run_state()
	_check(pd.saved_run_state.has_run_state, "run state saved")
	_check(not m.delete_custom(cid), "character in a saved run cannot be deleted")
	_eq(m.rename_custom("character", cid, "renamed_mid_run"), "", "nor renamed")
	_check(m.delete_custom_item(iid), "item deleted mid-run")
	_check(m.delete_custom_weapon(wid), "weapon deleted mid-run")
	m.apply_all()
	pd.load_game_file()
	rd.resume_from_state(pd.saved_run_state)
	_check(rd.players_data[0].current_character != null, "character kept")
	_eq(rd.players_data[0].weapons.size(), 0, "deleted weapon dropped from the run")
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(60), "completed")
	_check(tree.current_scene != null, "battle scene running after resume")
	var _s = tree.change_scene(MenuData.shop_scene if "shop_scene" in MenuData else "res://ui/menus/shop/shop.tscn")
	yield(_frames(30), "completed")
	_check(tree.current_scene != null, "shop scene running after resume")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")
	pd.reset_and_save_new_run_state()
