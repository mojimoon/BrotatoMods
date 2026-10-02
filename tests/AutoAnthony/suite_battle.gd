extends "res://mods/tests/AutoAnthony/test_base.gd"

# battle：在真实战斗场景（main.tscn）/ 商店里运行的集成测试（较慢；改动运行时 / 战斗逻辑时跑）


func test_91_menu_buttons_and_shop_hook() -> void:
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	for path in [MenuData.character_selection_scene, MenuData.weapon_selection_scene, MenuData.difficulty_selection_scene]:
		_setup_player("character_well_rounded")
		var _e = tree.change_scene(path)
		for i in 6:
			yield(tree, "idle_frame")
		var sc = tree.current_scene
		var back = sc.get_node_or_null("%BackButton") if sc != null else null
		_check(back != null and back.has_node("AutoAnthonyBtn"), "config button on " + path)
		if back != null and back.has_node("AutoAnthonyBtn"):
			back.get_node("AutoAnthonyBtn").emit_signal("pressed")
			yield(tree, "idle_frame")
			var opened = false
			for c in sc.get_children():
				if c is CanvasLayer and c.get_child_count() > 0 and c.get_child(0).name == "AutoAnthonySettings":
					opened = true
					c.get_child(0)._on_close_pressed()
			_check(opened, "settings popup opens on " + path)
	_setup_player("character_well_rounded")
	var _w = rd.add_weapon(fist, 0)
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [TriggerEffect.make({"trigger": "reroll", "payload": "gold", "value": 50})]
	rd.add_item(holder, 0)
	rd.current_wave = 3
	rd.add_gold(100, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	var g = rd.get_player_gold(0)
	shop._on_RerollButton_pressed(0)
	_check(rd.get_player_gold(0) > g + 40, "reroll trigger fired through the shop hook (%d -> %d)" % [g, rd.get_player_gold(0)])
	# 购买改变武器栏的道具后，"武器 (n/上限)"标签立即刷新
	var slot_item = _item("item_potato").duplicate()
	slot_item.effects = [_plain("weapon_slot", 1)]
	var slots0 = rd.get_player_effect(Keys.weapon_slot_hash, 0)
	shop.buy_item(slot_item, 0)
	var label = shop._get_gear_container(0).weapons_container._label.text
	_eq(rd.get_player_effect(Keys.weapon_slot_hash, 0), slots0 + 1, "weapon slot item applied")
	_check(label.ends_with("/" + str(slots0 + 1) + ")"), "weapon label refreshed right after buying: " + label)
	m.on_menu_reset()


func test_87_hourglass_and_goldfish_in_shop() -> void:
	_setup_player("character_well_rounded")
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	# 先从原版道具收集机制（开局后金鱼 / 沙漏本身也被重组）
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	m.start_new_run()
	# 金鱼：刷新后持有者消失
	var fish_holder = _item("item_cake").duplicate()
	fish_holder.effects = [gen._mechanic_copy(_find_mech(gen, "increase_tier_on_reroll"), -1.0, "item_cake")]
	rd.add_item(fish_holder, 0)
	# 沙漏：进入下一波时倒退一波并移除持有者
	var glass_holder = _item("item_potato").duplicate()
	glass_holder.effects = [gen._mechanic_copy(_find_mech(gen, "item_hourglass"), -1.0, "item_potato")]
	rd.add_item(glass_holder, 0)
	rd.current_wave = 5
	rd.add_gold(200, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	shop._on_RerollButton_pressed(0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_cake"), 0, false), 1, "goldfish-like holder kept after reroll")
	var cake = rd.get_player_item(Keys.generate_hash("item_cake"), 0)
	_check(cake != null and cake.effects.empty(), "only the consumed effect disappeared")
	# 镜子：购买时复制，持有者只失去这条效果
	var mirror_holder = _item("item_helmet").duplicate()
	mirror_holder.effects = [gen._mechanic_copy(_find_mech(gen, "duplicate_item"), -1.0, "item_helmet")]
	rd.add_item(mirror_holder, 0)
	var bought = _item("item_bat")
	shop.buy_item(bought, 0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_bat"), 0, false), 2, "mirror-like holder duplicated the bought item")
	_eq(rd.get_nb_item(Keys.generate_hash("item_helmet"), 0, false), 1, "mirror-like holder kept")
	var helmet = rd.get_player_item(Keys.generate_hash("item_helmet"), 0)
	_check(helmet != null and helmet.effects.empty(), "mirror effect removed from the holder")
	shop._on_GoButton_pressed(0)
	_eq(rd.current_wave, 5, "hourglass-like holder rewinds the wave (5 -> 6 -> 5)")
	_eq(rd.get_nb_item(Keys.generate_hash("item_potato"), 0, false), 1, "hourglass-like holder kept")
	var pot = rd.get_player_item(Keys.generate_hash("item_potato"), 0)
	_check(pot != null and pot.effects.empty(), "hourglass effect removed from the holder")
	_eq(int(rd.get_player_effects(0)[Keys.item_hourglass_hash]), 0, "hourglass counter back to 0")
	for i in 6:
		yield(tree, "idle_frame")
	m.on_menu_reset()


func test_102_triggers_and_payloads_in_battle() -> void:
	m.start_new_run()
	var pistol = isvc.get_element_safe(isvc.weapons, "weapon_pistol_1")
	var _w = rd.add_weapon(pistol, 0)
	var gain_armor = load("res://effects/items/stat_gains_modification_effect.gd").new()
	gain_armor.key = "effect_increase_stat_gains"
	gain_armor.key_hash = Keys.generate_hash(gain_armor.key)
	gain_armor.custom_key_hash = Keys.generate_hash("")
	gain_armor.value = 50
	gain_armor.stat_displayed = "stat_armor"
	gain_armor.stats_modified = ["stat_armor"]
	# (A) 每种扳机一条（状态扳机挂临时属性，其余挂 +1 材料），只看是否触发
	var trig_holder = _item("item_potato").duplicate()
	var trig_effects = []
	for t in Catalog.TRIGGERS:
		if Catalog.TRIGGERS[t].kind == "shop":
			continue
		var payload = "temp_stat" if Catalog.TRIGGERS[t].kind == "state" else "gold"
		var c = {"trigger": t, "payload": payload, "value": 1, "stat": "stat_luck", "dmg_type": "stat_elemental_damage"}
		if t == "interval":
			c.param = 1
		trig_effects.push_back(TriggerEffect.make(c))
	trig_holder.effects = trig_effects
	rd.add_item(trig_holder, 0)
	# 树木属性至少 3：原版每次刷树 (randi(1, 2) + 树木属性) × 33%，整数部分必定生成（"砍倒树木时"）
	rd.get_player_effects(0)[Keys.trees_hash] = max(3, rd.get_player_effects(0)[Keys.trees_hash])
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_wait_frames(10), "completed")
	var main = tree.current_scene
	var rt = main.get_node_or_null("AutoAnthonyRuntime") if main != null else null
	_check(rt != null, "runtime in battle")
	if rt == null:
		return
	var player = main._players[0]
	# 测试期间玩家不被敌人打到（直接调用 take_damage 不受影响）
	player.disable_hurtbox()
	# 延长本波，保证整个测试期间都有敌人
	main._wave_timer.start(600)
	var seen_state = {}

	# 满血、静止在开局即成立；等待间隔
	yield(tree.create_timer(1.3), "timeout")
	for en in rt.entries[0]:
		if en.active:
			seen_state[en.effect.trigger] = true
	# 移动与计步：锁定移动方向，让原版移动逻辑走起来
	player._move_locked = true
	player._current_movement = Vector2(1, 0)
	yield(tree.create_timer(2.0), "timeout")
	for en in rt.entries[0]:
		if en.active:
			seen_state[en.effect.trigger] = true
	player._current_movement = Vector2.ZERO
	player._move_locked = false
	# 受击
	var hit_args = TakeDamageArgs.new(-1)
	hit_args.bypass_invincibility = true
	hit_args.dodgeable = false
	var _r = player.take_damage(3, hit_args)
	yield(_wait_physics(6), "completed")
	# 闪避：闪避率 100%
	player.current_stats.dodge = 1.0
	var dodge_args = TakeDamageArgs.new(-1)
	dodge_args.bypass_invincibility = true
	var _d = player.take_damage(3, dodge_args)
	yield(_wait_frames(2), "completed")
	# 受击后的无敌计时结束时原版会重新启用受击判定：停掉计时器，否则低血时会被敌人打死（偶发）
	player._invincibility_timer.stop()
	player.disable_hurtbox()
	# 低血
	player.current_stats.health = 1
	yield(tree.create_timer(0.5), "timeout")
	for en in rt.entries[0]:
		if en.active:
			seen_state[en.effect.trigger] = true
	# 回血（原版的回血信号）
	RunData.emit_signal("healing_effect", 3, 0, Keys.empty_hash)
	yield(_wait_frames(2), "completed")
	player.current_stats.health = player.max_stats.health
	# 升级
	rd.add_xp(int(rd.get_next_level_xp_needed(0)) + 1, 0)
	yield(_wait_frames(2), "completed")
	# 击杀 / 燃烧击杀 / 暴击击杀（原版受伤信号带暴击标记）
	var en1 = yield(_wait_enemy(main), "completed")
	_check(en1 != null, "enemy spawned for kill triggers")
	if en1 != null:
		en1._is_burning = true
		var _k = en1.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_frames(2), "completed")
		if is_instance_valid(en1):
			main._on_enemy_took_damage(en1, 999999, Vector2.ZERO, true, false, false, false, TakeDamageArgs.new(0), 0, false)
	# 击杀被诅咒的敌人：挂上原版 DLC 的诅咒效果行为
	var en_cursed = yield(_wait_enemy(main), "completed")
	if en_cursed != null:
		var cb = load("res://dlcs/dlc_1/effect_behaviors/enemy/curse_enemy_effect_behavior.gd").new()
		en_cursed.effect_behaviors.add_child(cb)
		var _cbi = cb.init(en_cursed)
		var _kcur = en_cursed.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_frames(2), "completed")
	# 砍倒树木：按原版刷树队列生成一棵树并击倒
	main._entity_spawner.queue_to_spawn_trees.push_back([EntityType.NEUTRAL, load("res://entities/units/neutral/tree.tscn"), player.global_position + Vector2(150, 0)])
	for i in 100:
		if not main._entity_spawner.neutrals.empty():
			break
		yield(tree.create_timer(0.1), "timeout")
	_check(not main._entity_spawner.neutrals.empty(), "a tree spawned")
	if not main._entity_spawner.neutrals.empty():
		var tr0 = main._entity_spawner.neutrals[0]
		var _kt = tr0.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_frames(3), "completed")
	# 拾取材料（原版生成的材料节点）
	main.spawn_gold(1.0, player.global_position, 0)
	yield(_wait_frames(2), "completed")
	if not main._active_golds.empty():
		main.on_gold_picked_up(main._active_golds.back(), 0)
	# 拾取消耗品
	# 与原版 spawn_consumables 相同：先从对象池取（同时建立对象池），没有再实例化
	var cons = main.get_node_from_pool(main._consumable_pool_id, main._consumables_container)
	if cons == null:
		cons = main.consumable_scene.instance()
		main._consumables_container.add_child(cons)
	cons.consumable_data = isvc.consumables[0]
	cons.global_position = player.global_position
	main._consumables.push_back(cons)
	main.on_consumable_picked_up(cons, 0)
	# 半波
	main._on_HalfWaveTimer_timeout()
	yield(_wait_frames(2), "completed")
	# ---- 实验性扳机 ----
	var AAEnemyBehavior = load("res://mods-unpacked/Mojimoon-AutoAnthony/aa/enemy_behavior.gd")
	# 拾取箱子（原版箱子消耗品）
	var crate = main.get_node_from_pool(main._consumable_pool_id, main._consumables_container)
	if crate == null:
		crate = main.consumable_scene.instance()
		main._consumables_container.add_child(crate)
	crate.consumable_data = isvc.get_element_safe(isvc.consumables, "consumable_item_box")
	crate.already_picked_up = false
	crate.global_position = player.global_position
	main._consumables.push_back(crate)
	main.on_consumable_picked_up(crate, 0)
	# 引发爆炸（经原版 WeaponService.explode，延迟生成）
	var en_x = yield(_wait_enemy(main), "completed")
	if en_x != null:
		rt._explode(TriggerEffect.make({"trigger": "kill", "payload": "explode", "stat": "stat_max_hp", "value": 50}), 0, en_x.global_position)
	yield(_wait_physics(8), "completed")
	# 点燃敌人（原版燃烧，燃烧结算时触发）
	var en_b = yield(_wait_enemy(main), "completed")
	if en_b != null:
		var bd = BurningData.new()
		bd.chance = 1.0
		bd.damage = 1
		bd.duration = 3
		bd.from = player
		# 目标要活到燃烧结算（手枪会一直射击）
		en_b.max_stats.health = max(en_b.max_stats.health, 5000)
		en_b.current_stats.health = en_b.max_stats.health
		en_b.apply_burning(bd)
	yield(tree.create_timer(1.6), "timeout")
	# 首次命中 / 命中高低血：手枪的真实命中触发远程与高血部分；其余伤害类型与低血敌人用原版 on_hurt 入口模拟
	var en_h = yield(_wait_enemy(main), "completed")
	var beh = AAEnemyBehavior.find_on(en_h) if en_h != null else null
	_check(beh != null, "enemies carry the mod's effect behavior")
	if beh != null:
		var hb = Hitbox.new()
		hb.from = player
		hb.scaling_stats = [[Keys.stat_ranged_damage_hash, 1.0]]
		beh.on_hurt(hb)
		hb.scaling_stats = [[Keys.stat_melee_damage_hash, 1.0], [Keys.stat_elemental_damage_hash, 1.0], [Keys.stat_engineering_hash, 1.0]]
		# 第 1 波敌人生命只有个位数：放大上限后设为 5%
		en_h.max_stats.health = max(en_h.max_stats.health, 40)
		en_h.current_stats.health = 2
		beh.on_hurt(hb)
		hb.free()
		# 用某类伤害击杀：致命一击取最后一次命中的伤害类型
		var _kh = en_h.take_damage(999999, TakeDamageArgs.new(0))
	yield(_wait_frames(2), "completed")
	var fired = {}
	for en in rt.entries[0]:
		if en.effect in trig_effects:
			fired[en.effect.trigger] = en.fired > 0 or en.active or seen_state.has(en.effect.trigger)
	for t in Catalog.TRIGGERS:
		if Catalog.TRIGGERS[t].kind == "shop" or t == "wave_end":
			continue
		_check(fired.get(t, false), "trigger fires from real game events: " + t)

	# (B) 载荷：直接执行，检查真实的玩家 / 敌人 / 武器状态
	player.current_stats.health = player.max_stats.health
	var weapon = player.current_weapons[0] if not player.current_weapons.empty() else null
	var base_armor = player.max_stats.armor
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "temp_stat", "stat": "stat_armor", "value": 4}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_eq(player.max_stats.armor, base_armor + 4, "temp stat reaches the player's real armor")
	var base_hp = player.max_stats.health
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "perm_stat", "stat": "stat_max_hp", "value": 5}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_eq(player.max_stats.health, base_hp + 5, "perm stat reaches the player's real max HP")
	var base_speed = player.max_stats.speed
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "timed_stat", "stat": "stat_speed", "value": 20, "value2": 1}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_check(player.max_stats.speed > base_speed, "timed stat raises real speed")
	yield(tree.create_timer(1.4), "timeout")
	_check(abs(player.max_stats.speed - base_speed) < 0.01, "timed stat expires")
	player.current_stats.health = max(1, player.max_stats.health - 10)
	var h0 = player.current_stats.health
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "heal", "value": 3}), 0, null, false)
	yield(_wait_frames(2), "completed")
	_check(player.current_stats.health > h0, "heal payload heals the player (%d -> %d)" % [h0, player.current_stats.health])
	var g0 = rd.get_player_gold(0)
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "gold", "value": 7}), 0, null, false)
	_eq(rd.get_player_gold(0), g0 + 7, "gold payload")
	var x0 = rd.get_player_xp(0)
	var l0 = rd.get_player_level(0)
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "xp", "value": 3}), 0, null, false)
	_check(rd.get_player_xp(0) > x0 or rd.get_player_level(0) > l0, "xp payload")
	var en2 = yield(_wait_enemy(main), "completed")
	if en2 != null:
		var hp0 = _enemies_hp(main)
		rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "damage", "stat": "stat_max_hp", "value": 100}), 0, null, false)
		yield(_wait_frames(2), "completed")
		_check(_enemies_hp(main) < hp0, "damage payload hurts an enemy")
	var en3 = yield(_wait_enemy(main), "completed")
	if en3 != null:
		var e_hp = en3.current_stats.health
		rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "explode", "stat": "stat_max_hp", "value": 100}), 0, en3.global_position, false)
		yield(_wait_physics(12), "completed")
		_check(not is_instance_valid(en3) or en3.dead or en3.current_stats.health < e_hp, "explode payload hurts the enemy at the position")
	# 获得效果：机制（穿透 → 武器的真实穿透数）、属性修改（护甲 +50% → 真实护甲）
	if weapon != null:
		var p0 = weapon.current_stats.piercing
		rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "grant", "value": 2, "grant": _plain("piercing", 1), "grant_mode": "temp", "grant_unit": 10.0}), 0, null, false)
		yield(_wait_physics(12), "completed")
		_eq(weapon.current_stats.piercing, p0 + 2, "granted piercing reaches the weapon")
	rd.add_stat(Keys.stat_armor_hash, 10, 0)
	yield(_wait_physics(12), "completed")
	var a0 = player.max_stats.armor
	rt.execute(TriggerEffect.make({"trigger": "kill", "payload": "grant", "value": 1, "grant": gain_armor, "grant_mode": "temp", "grant_unit": 5.0}), 0, null, false)
	yield(_wait_physics(12), "completed")
	_check(player.max_stats.armor > a0, "granted stat-gain modification raises real armor (%d -> %d)" % [a0, player.max_stats.armor])

	# 使该敌人受到的伤害提高：原版伤害计算（get_damage_value）实际变化，到时恢复
	var AAEB = load("res://mods-unpacked/Mojimoon-AutoAnthony/aa/enemy_behavior.gd")
	var en_v = yield(_wait_enemy(main), "completed")
	if en_v != null:
		var d0 = en_v.get_damage_value(100, 0, false).value
		rt.execute(TriggerEffect.make({"trigger": "crit", "payload": "vuln", "value": 30, "value2": 1}), 0, en_v.global_position, false, null, en_v)
		var d1 = en_v.get_damage_value(100, 0, false).value
		_eq(d1, int(round(d0 * 1.3)), "vuln payload raises the damage that enemy takes (%d -> %d)" % [d0, d1])
		yield(tree.create_timer(1.3), "timeout")
		if is_instance_valid(en_v) and not en_v.dead:
			_eq(en_v.get_damage_value(100, 0, false).value, d0, "vuln expires")
	# 连锁：击杀 -> 爆炸（延迟生成）-> "引发爆炸时" -> 材料；并且超过连锁深度上限的事件不再触发
	var chain_holder = _item("item_potato").duplicate()
	chain_holder.effects = [
		TriggerEffect.make({"trigger": "kill", "payload": "explode", "stat": "stat_max_hp", "value": 50}),
		TriggerEffect.make({"trigger": "explode", "payload": "gold", "value": 9}),
	]
	rd.add_item(chain_holder, 0)
	m.triggers_dirty = true
	rt._check_dirty()
	var en_c = yield(_wait_enemy(main), "completed")
	if en_c != null:
		var gc = rd.get_player_gold(0)
		var _kc = en_c.take_damage(999999, TakeDamageArgs.new(0))
		yield(_wait_physics(10), "completed")
		_check(rd.get_player_gold(0) >= gc + 9, "chain kill -> explosion -> 'when you cause an explosion' gave materials (%d -> %d)" % [gc, rd.get_player_gold(0)])
	var gd = rd.get_player_gold(0)
	rt.fire("explode", 0, null, Catalog.MAX_CHAIN_DEPTH)
	_eq(rd.get_player_gold(0), gd, "events beyond the chain depth limit do not fire")
	rd.remove_item(chain_holder, 0)
	m.triggers_dirty = true
	rt._check_dirty()

	# (C) 生成池中每种效果在战斗中都有效果。先移除 (A) 的测试条款（静止 / 移动等状态加成会同时切换，干扰前后比较）
	for en in rt.entries[0].duplicate():
		if en.effect in trig_effects:
			if en.active:
				rt._set_state(0, en, false)
			rt.entries[0].erase(en)
	rd.remove_item(trig_holder, 0)
	var shapes = {}
	for sd in SEEDS:
		var gen = Generator.new(_cfg(), sd)
		var plan = gen.generate(isvc.items, isvc.characters, [], [])
		for id in plan.items:
			for e in plan.items[id].effects:
				if not e is TriggerEffect:
					continue
				var gk = ""
				if e.grant != null:
					gk = e.grant.custom_key if e.grant.custom_key != "" else e.grant.key
				# 执行与扳机无关（扳机由 (A) 逐个核对）：每种载荷 × 获得效果 × 属性只测一个代表，扳机只区分类型
				var k = "%s/%s/%s/%s/%s" % [Catalog.TRIGGERS[e.trigger].kind, e.payload, e.grant_mode if e.payload == "grant" else "", gk, e.stat]
				if not shapes.has(k):
					shapes[k] = e
	var bad = []
	for k in shapes:
		var e = shapes[k]
		# 受伤加成需要目标敌人且不立即改变生命值：由实验性扳机测试单独核对
		if e.payload == "vuln":
			continue
		if player.dead or not is_instance_valid(main):
			_check(false, "player alive during shape checks")
			break
		player.disable_hurtbox()
		player.current_stats.health = max(1, player.max_stats.health / 2)
		# 伤害 / 爆炸看敌人总生命，敌人同时生成 / 死亡会干扰比较：最多重试 3 次
		var changed = false
		for attempt in (3 if e.payload in ["damage", "explode", "hp_dmg", "ignite", "slow"] else 1):
			var tgt = yield(_wait_enemy(main), "completed")
			var before = _battle_snapshot(main)
			var hp_before = _enemy_hp_map(main)
			var tb = AAEB.find_on(tgt) if tgt != null and is_instance_valid(tgt) else null
			var vuln_before = tb._vuln_total if tb != null else 0
			var speed_before = tgt.current_stats.speed if tgt != null and is_instance_valid(tgt) else 0
			rt.execute(e, 0, tgt.global_position if tgt != null and is_instance_valid(tgt) else null, false, null, tgt if tgt != null and is_instance_valid(tgt) else null)
			# 爆炸由 WeaponService 延迟生成，命中需要几帧
			# 爆炸由 WeaponService 延迟生成，命中需要几帧；燃烧第一跳约 1 秒
			var waits = {"explode": 12, "ignite": 75}
			yield(_wait_physics(waits.get(e.payload, 4)), "completed")
			if e.payload == "vuln":
				if tb != null and is_instance_valid(tb) and tb._vuln_total > vuln_before:
					changed = true
					break
			elif e.payload == "slow":
				if tgt != null and is_instance_valid(tgt) and (tgt.dead or tgt.current_stats.speed < speed_before):
					changed = true
					break
			elif e.payload in ["damage", "explode", "hp_dmg", "ignite"]:
				if _any_enemy_hurt(main, hp_before):
					changed = true
					break
			elif _battle_snapshot(main) != before:
				changed = true
				break
		if not changed:
			bad.push_back(k + " : " + e.get_text(0, false))
		player.current_stats.health = player.max_stats.health
	print("AUDIT battle-executed %d distinct (trigger kind, payload, grant, stat) shapes, %d without effect" % [shapes.size(), bad.size()])
	for b in bad:
		print("AUDIT   no effect: " + b)
	_check(bad.empty(), "every generated trigger shape changes the battle state")
	main._cleaning_up = true
	rt.revert_all_grants()
	m.on_menu_reset()


# 反馈的 bug（真实战斗模拟）：
# (1) "每暴击击杀 N 个敌人：永久 +1% 暴击率"——原版在敌人死亡（延迟调用）之前发出受伤信号，暴击击杀要按"本次伤害致死"判断
# (2) "移动时：-2 最大生命值"——原版降低最大生命不压低当前生命、升高时补上差值：反复走停会让当前生命不断上涨
func test_122_feedback_crit_kill_and_state_max_hp() -> void:
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [
		TriggerEffect.make({"trigger": "crit_kill", "param": 2, "payload": "perm_stat", "stat": "stat_crit_chance", "value": 1, "cap": 3}),
		TriggerEffect.make({"trigger": "moving", "payload": "temp_stat", "stat": "stat_max_hp", "value": -2}),
		TriggerEffect.make({"trigger": "still", "payload": "temp_stat", "stat": "stat_max_hp", "value": 5}),
	]
	rd.add_item(holder, 0)
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_wait_frames(10), "completed")
	var main = tree.current_scene
	var rt = main.get_node_or_null("AutoAnthonyRuntime") if main != null else null
	_check(rt != null, "runtime in battle")
	if rt == null:
		return
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	# (1) 原版受伤路径的暴击击杀：命中盒暴击率 100%，一击致死
	var crit0 = rd.get_player_effects(0)[Keys.stat_crit_chance_hash]
	var kills = 0
	for i in 8:
		var en = yield(_wait_enemy(main), "completed")
		if en == null:
			break
		var hb = Hitbox.new()
		hb.from = player
		hb.crit_chance = 1.0
		hb.crit_damage = 2.0
		var args = TakeDamageArgs.new(0, hb)
		var _r = en.take_damage(999999, args)
		kills += 1
		yield(_wait_frames(2), "completed")
		hb.free()
	var crit1 = rd.get_player_effects(0)[Keys.stat_crit_chance_hash]
	print("AUDIT crit kills %d: crit chance %d -> %d" % [kills, crit0, crit1])
	_check(kills >= 6, "enough crit kills simulated (%d)" % kills)
	_eq(crit1 - crit0, 3, "every 2 crit kills: +1% crit chance permanently, max 3 per wave")
	# (2) 走停循环：当前生命不应上涨（满血时保持满血，受伤时不白回血）
	yield(_wait_physics(12), "completed")
	player.current_stats.health = player.max_stats.health
	var trace = []
	for half in [true, false]:
		if not half:
			player.current_stats.health = max(1, player.max_stats.health - 10)
		var start_hp = player.current_stats.health
		var start_gap = player.max_stats.health - player.current_stats.health
		for cycle in 4:
			player._move_locked = true
			player._current_movement = Vector2(1, 0)
			yield(tree.create_timer(0.5), "timeout")
			yield(_wait_physics(4), "completed")
			trace.push_back("%d/%d" % [player.current_stats.health, player.max_stats.health])
			_check(player.current_stats.health <= player.max_stats.health, "moving: health within max (%d/%d)" % [player.current_stats.health, player.max_stats.health])
			player._current_movement = Vector2.ZERO
			player._move_locked = false
			yield(tree.create_timer(0.5), "timeout")
			yield(_wait_physics(4), "completed")
			trace.push_back("%d/%d" % [player.current_stats.health, player.max_stats.health])
			_check(player.current_stats.health <= player.max_stats.health, "still: health within max (%d/%d)" % [player.current_stats.health, player.max_stats.health])
		var gap = player.max_stats.health - player.current_stats.health
		# 满血：走停后仍是满血、不超上限；受伤：降低时只截到上限（升高时原版补差值）
		if start_gap == 0:
			_eq(gap, 0, "full health stays exactly full after walk/stop cycles")
	print("AUDIT walk/stop health trace: " + str(trace))
	main._cleaning_up = true
	rt.revert_all_grants()
	m.on_menu_reset()


# 反馈：持有"复制购买的道具"（镜子效果）的重组道具时购买道具闪退
func test_123_mirror_like_holders_in_shop() -> void:
	# 生成池里的复制效果数值
	var vals = {}
	for sd in range(1, 31):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.custom_key == "duplicate_item":
					vals[e.value] = vals.get(e.value, 0) + 1
					_eq(e.key, id, "duplicate_item keyed to its holder " + id)
	print("AUDIT duplicate_item values in generated pools: %s" % str(vals))
	_setup_player("character_well_rounded")
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	m.start_new_run()
	rd.add_gold(500, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	# (a) 复制 2 份的持有者：购买一件，得到 1 + 2 件，持有者保留但失去该效果
	var holder = _item("item_helmet").duplicate()
	var dup = gen._mechanic_copy(_find_mech(gen, "duplicate_item"), -1.0, "item_helmet")
	dup.value = 2
	holder.effects = [dup]
	rd.add_item(holder, 0)
	shop.buy_item(_item("item_bat"), 0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_bat"), 0, false), 3, "x2 holder: bought 1 + duplicated 2")
	_eq(rd.get_nb_item(Keys.generate_hash("item_helmet"), 0, false), 1, "x2 holder kept")
	shop.buy_item(_item("item_bat"), 0)
	_eq(rd.get_nb_item(Keys.generate_hash("item_bat"), 0, false), 4, "next purchase is a normal purchase")
	# (b) 购买与持有者同 ID 的道具（重组道具本身带复制效果，例如重组后的镜子）
	var mirror = _item("item_mirror")
	var own = null
	for e in mirror.effects:
		if e.custom_key == "duplicate_item":
			own = e
	var holder2 = _item("item_cake").duplicate()
	var dup2 = gen._mechanic_copy(_find_mech(gen, "duplicate_item"), -1.0, "item_cake")
	holder2.effects = [dup2]
	rd.add_item(holder2, 0)
	var cake_shop = _item("item_cake").duplicate()
	cake_shop.effects = [dup2.duplicate()]
	shop.buy_item(cake_shop, 0)
	var cakes = rd.get_nb_item(Keys.generate_hash("item_cake"), 0, false)
	var dup_left = rd.get_player_effect(Keys.duplicate_item_hash, 0).size()
	print("AUDIT buying the holder's own id: %d cakes, %d duplicate effects left" % [cakes, dup_left])
	_eq(cakes, 3, "own-id purchase: holder + bought + 1 copy")
	shop.buy_item(_item("item_bat"), 0)
	for i in 4:
		yield(tree, "idle_frame")
	_check(true, "no crash after buying again")
	m.on_menu_reset()


# 金鱼（刷新时升档）/ 沙漏（倒流）效果在重组道具上：数值分布、两件同 ID 持有者
func test_124_goldfish_hourglass_holders() -> void:
	var vals = {}
	for sd in range(1, 31):
		var plan = _gen(sd)
		for id in plan.items:
			for e in plan.items[id].effects:
				if e.custom_key == "increase_tier_on_reroll" or e.key == "item_hourglass":
					var k = (e.custom_key if e.custom_key != "" else e.key) + "=" + str(e.value)
					vals[k] = vals.get(k, 0) + 1
	print("AUDIT goldfish / hourglass values in generated pools: %s" % str(vals))
	_setup_player("character_well_rounded")
	var fist = isvc.get_element_safe(isvc.weapons, "weapon_fist_1")
	var _w = rd.add_weapon(fist, 0)
	var gen = Generator.new(_cfg(), 1)
	gen._collect_priors(isvc.items, isvc.characters, isvc.weapons)
	m.start_new_run()
	for i in 2:
		var fish = _item("item_cake").duplicate()
		fish.effects = [gen._mechanic_copy(_find_mech(gen, "increase_tier_on_reroll"), -1.0, "item_cake")]
		rd.add_item(fish, 0)
	for i in 2:
		var glass = _item("item_potato").duplicate()
		glass.effects = [gen._mechanic_copy(_find_mech(gen, "item_hourglass"), -1.0, "item_potato")]
		rd.add_item(glass, 0)
	rd.current_wave = 6
	rd.add_gold(500, 0)
	var _e = tree.change_scene("res://ui/menus/shop/shop.tscn")
	for i in 6:
		yield(tree, "idle_frame")
	var shop = tree.current_scene
	var fish_fx = []
	for r in 3:
		shop._on_RerollButton_pressed(0)
		var n = 0
		for it in rd.get_player_items(0):
			if it.my_id == "item_cake" and not it.effects.empty():
				n += 1
		fish_fx.push_back(n)
	print("AUDIT two goldfish-like holders, holders with the effect after each reroll: %s" % str(fish_fx))
	_eq(fish_fx, [1, 0, 0], "each reroll consumes one goldfish-like holder")
	_eq(rd.get_player_effect(Keys.increase_tier_on_reroll_hash, 0).size(), 0, "no goldfish effect left")
	shop._on_GoButton_pressed(0)
	_eq(rd.current_wave, 5, "two hourglass-like holders rewind two waves (6 -> 7 -> 5)")
	for i in 6:
		yield(tree, "idle_frame")
	m.on_menu_reset()


# 掉落水果：真实战斗中大量掉落、全部可拾取（拾取触发"捡起消耗品时"）、对象池复用、清场后不再掉落
func test_131_fruit_drops_in_battle() -> void:
	m.start_new_run()
	var holder = _item("item_potato").duplicate()
	holder.effects = [TriggerEffect.make({"trigger": "consumable", "payload": "gold", "value": 1})]
	rd.add_item(holder, 0)
	rd.current_wave = 1
	TempStats.reset()
	var _e = tree.change_scene("res://main.tscn")
	yield(_wait_frames(10), "completed")
	var main = tree.current_scene
	var rt = main.get_node_or_null("AutoAnthonyRuntime") if main != null else null
	_check(rt != null, "runtime in battle")
	if rt == null:
		return
	var player = main._players[0]
	player.disable_hurtbox()
	main._wave_timer.start(600)
	var fruit = TriggerEffect.make({"trigger": "kill", "payload": "fruit", "value": 3})
	# 掉在玩家附近的水果可能被直接吸取：场上新增 + 已拾取（每个 +1 材料）= 掉落总数
	for round_i in 2:
		var n0 = main._consumables.size()
		var g0 = rd.get_player_gold(0)
		for i in 10:
			rt.execute(fruit, 0, player.global_position + Vector2(30 * i, 0), false)
		yield(_wait_physics(4), "completed")
		var dropped = main._consumables.slice(n0, main._consumables.size() - 1) if main._consumables.size() > n0 else []
		_eq(dropped.size() + rd.get_player_gold(0) - g0, 30, "round %d: 10 fires x 3 fruits dropped" % round_i)
		var ok = true
		for c in dropped:
			ok = ok and is_instance_valid(c) and c.consumable_data != null and not c.already_picked_up and c.is_inside_tree()
		_check(ok, "dropped fruits are live consumables")
		for c in dropped:
			main.on_consumable_picked_up(c, 0)
		yield(_wait_frames(2), "completed")
		_eq(rd.get_player_gold(0), g0 + 30, "round %d: picking each fruit fires the consumable trigger" % round_i)
		_eq(main._consumables.size(), n0, "round %d: picked fruits leave the field (back to the pool)" % round_i)
	main._cleaning_up = true
	var n1 = main._consumables.size()
	rt.execute(fruit, 0, player.global_position, false)
	yield(_wait_frames(3), "completed")
	_eq(main._consumables.size(), n1, "no fruit dropped while the wave is being cleaned up")
	rt.revert_all_grants()
	rd.remove_item(holder, 0)
	m.on_menu_reset()
