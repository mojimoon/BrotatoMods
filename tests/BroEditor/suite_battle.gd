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
		["enemy_hit", {}, "vuln", {"pct": 25, "secs": 30}],
		["on_explode", {}, "add_gold", {"value": 500}],
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
		var beb = load("res://mods-unpacked/Mojimoon-BroEditor/graph/enemy_behavior.gd").find_on(enemy)
		_check(beb != null, "enemy behavior attached")
		if beb != null:
			m.runtime.fire("enemy_hit", 0, enemy.global_position, enemy, {"hp_pct": 100.0, "stats": []})
			_eq(beb.get_bonus_damage(null, 0), 25, "vuln on the hit enemy")
		var ex = load("res://items/all/rip_and_tear/rip_and_tear_effect_1.tres")
		var args = WeaponServiceExplodeArgs.new()
		args.pos = player.global_position
		args.damage = 1
		args.from_player_index = 0
		args.ignored_objects = [enemy]
		gold0 = rd.players_data[0].gold
		WeaponService.explode(ex, args)
		_eq(rd.players_data[0].gold - gold0, 500, "explosion trigger")
		args.set_meta("be_bp", true)
		gold0 = rd.players_data[0].gold
		WeaponService.explode(ex, args)
		_eq(rd.players_data[0].gold - gold0, 0, "blueprint explosions do not re-trigger")
		yield(_frames(2), "completed")
		gold0 = rd.players_data[0].gold
		var _k = enemy.take_damage(999999, TakeDamageArgs.new(0))
		yield(_frames(3), "completed")
		_check(rd.players_data[0].gold - gold0 >= 1000, "kill fired")
	main._on_WaveTimer_timeout()
	yield(_frames(2), "completed")
	_check(m.runtime.wave_over, "wave end stops runtime")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")


# 魅惑、生成敌人、武器损坏（战斗中）
func test_86_battle_new_effects() -> void:
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_weapon(isvc.get_element_safe(isvc.weapons, "weapon_fist_1"), 0)
	rd.add_weapon(isvc.get_element_safe(isvc.weapons, "weapon_fist_1"), 0)
	rd.current_wave = 1
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(10), "completed")
	var main = tree.current_scene
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	var sp = main._entity_spawner
	var births = sp.active_births
	m.runtime._spawn({"params": {"enemy": "baby_alien", "n": 2}}, 0)
	_eq(sp.active_births - births, 2, "two enemies spawning")
	var enemy = null
	for i in 300:
		var es = sp.get_all_enemies(false)
		if not es.empty():
			enemy = es[0]
			break
		yield(tree, "idle_frame")
	_check(enemy != null, "enemy spawned")
	if enemy != null and ResourceLoader.exists(m.runtime.CHARM_SCENE):
		m.runtime._charm(0, enemy)
		_check(enemy.get_charmed_by_player_index() == 0, "charmed")
	var ws = rd.get_player_weapons_ref(0)
	var n = ws.size()
	var gold0 = rd.players_data[0].gold
	m.runtime._break({"src": ws[1]}, 3, 0)
	yield(_frames(3), "completed")
	_eq(rd.get_player_weapons_ref(0).size(), n - 1, "weapon broke")
	_eq(player.current_weapons.size(), n - 1, "weapon node removed")
	main._on_WaveTimer_timeout()
	yield(_frames(2), "completed")
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


# "每帧检查"：对每个敌人持续检查（敌人生命低于 X% → 按属性几率 → 魅惑 N 秒）；燃烧的持续时间 / 扩散 / 伤害类型
func test_87_tick_trigger_charm_ignite() -> void:
	var GE = load(GraphEffectScript)
	var g = GE.new_graph()
	var t = GE.add_node(g, "tick", Vector2.ZERO)
	var hp = GE.add_node(g, "enemy_hp_below", Vector2.ZERO, {"pct": 101})
	var ch = GE.add_node(g, "stat_chance", Vector2.ZERO, {"base": 100, "stat": "stat_max_hp", "pct": 0})
	GE.add_link(g, t, hp)
	GE.add_link(g, hp, ch)
	GE.add_link(g, ch, GE.add_node(g, "charm", Vector2.ZERO, {"secs": 2}))
	GE.add_link(g, hp, GE.add_node(g, "ignite", Vector2.ZERO, {"value": 3, "secs": 5, "spread": 1, "stat": "stat_max_hp", "pct": 50}))
	var p = m.new_profile()
	p.graph = g
	m.profiles[CH] = p
	m.apply_all()
	var text = GE.graph_text(g, false)
	_check(text.find("2") >= 0 and text.find("5") >= 0, "charm / ignite text shows the new fields")
	_setup_player(CH)
	rd.players_data[0].items = []
	rd.add_character(m.find_character(CH), 0)
	rd.add_weapon(isvc.get_element_safe(isvc.weapons, "weapon_fist_1"), 0)
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_frames(10), "completed")
	var main = tree.current_scene
	main._players[0].disable_hurtbox()
	main._wave_timer.start(600)
	var enemy = null
	for i in 300:
		var es = main._entity_spawner.get_all_enemies(false)
		if not es.empty():
			enemy = es[0]
			break
		yield(tree, "idle_frame")
	_check(enemy != null, "enemy spawned")
	if enemy != null:
		yield(_frames(3), "completed")
		_check(enemy.get_charmed_by_player_index() == 0, "tick trigger charmed the enemy without a hit")
		var timer = null
		for c in enemy.effect_behaviors.get_children():
			if "charmed" in c:
				timer = c.get_node("CharmTimer")
		_check(timer != null and timer.time_left <= 2.0 and timer.wait_time == 8, "charm lasts the node's duration; vanilla duration restored")
		_check(enemy._burning != null and enemy._burning.duration == 5 and enemy._burning.spread >= 1, "ignite duration and spread")
		var want = WeaponService.apply_damage_bonus(3 + int(Utils.get_stat(Keys.stat_max_hp_hash, 0) * 0.5), 0)
		_check(enemy._burning != null and enemy._burning.damage == want and want > 3, "ignite scales with the chosen stat (50% max HP)")
		var sp = enemy.current_stats.speed
		m.runtime._slow({"id": 99, "kind": "slow", "params": {"pct": -10, "secs": 1}}, enemy)
		_check(enemy.current_stats.speed > sp, "negative slow speeds the enemy up")
		yield(tree.create_timer(1.3), "timeout")
		_check(is_instance_valid(enemy) and abs(enemy.current_stats.speed - sp) < 0.5, "slow with a duration is restored")
	main._on_WaveTimer_timeout()
	yield(_frames(2), "completed")
	var _b = tree.change_scene(MenuData.character_selection_scene)
	yield(_frames(4), "completed")
	m.profiles.erase(CH)
	m.apply_all()
