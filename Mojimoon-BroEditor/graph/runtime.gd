extends Node

# 蓝图运行时：常驻在 mod 节点下。战斗开始时 start_wave(main)，波次结束时 end_wave()。
# 原版事件（击杀 / 受击 / 升级 / 拾取 / 商店刷新……）经脚本扩展转发到 fire()，
# 从对应扳机节点出发沿路径走：条件节点决定是否继续，效果节点执行。
# 状态扳机（静止 / 移动 / 低血 / 满血）每 0.2 秒轮询：进入状态时执行，离开时撤销本次加的本波属性与本波获得的效果。
# 载荷实现参考 AutoAnthony 的 aa/runtime.gd。

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const GraphEffect = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
const EXPLOSION_EFFECT_PATH = "res://items/all/rip_and_tear/rip_and_tear_effect_1.tres"
const MAX_DEPTH = 24

var mod = null
var main = null
var wave_over := true
# 每个玩家：[{effect, g, by_id, st: {节点 id: 状态}, granted: [本波获得的效果]}]
var entries: Array = [[], [], [], []]
var _elapsed := 0.0
var _poll := 0.0
var _steps: Array = [0.0, 0.0, 0.0, 0.0]
var _wave_serial := 0
var _explosion_effect = null


func _ready() -> void:
	name = "BroEditorRuntime"


func start_wave(p_main: Node) -> void:
	main = p_main
	wave_over = false
	_elapsed = 0.0
	_wave_serial += 1
	rebuild_all()


func end_wave() -> void:
	_wave_serial += 1
	wave_over = true
	for p in entries.size():
		for en in entries[p]:
			for id in en.st:
				var st = en.st[id]
				if st.get("active", false):
					_revert(p, st.get("hold", []))
				st.active = false
				st.hold = []
				st.fired = 0
				st.count = 0
				st.acc = 0.0
			_revert(p, en.granted)
			en.granted = []
	main = null


func _exit_tree() -> void:
	if not wave_over:
		end_wave()


# 收集玩家角色、道具、武器上的全部蓝图效果（保留已有节点状态）
func rebuild_all() -> void:
	if mod != null:
		mod.graph_dirty = false
	var rd = RunData
	for p in entries.size():
		var old = {}
		for en in entries[p]:
			old[en.effect.get_instance_id()] = en
		var list = []
		if p < rd.get_player_count():
			for src in rd.get_player_items_ref(p) + rd.get_player_weapons_ref(p):
				for e in src.effects:
					if e is GraphEffect:
						var en = old.get(e.get_instance_id())
						if en == null:
							en = {"effect": e, "g": e.graph, "by_id": GraphEffect.nodes_by_id(e.graph), "st": {}, "granted": []}
						list.push_back(en)
		entries[p] = list


func _check_dirty() -> void:
	if mod != null and mod.graph_dirty:
		rebuild_all()


func _state(en: Dictionary, id: int) -> Dictionary:
	if not en.st.has(id):
		en.st[id] = {"count": 0, "fired": 0, "last": -9999.0, "acc": 0.0, "active": false, "hold": []}
	return en.st[id]


func has_any(player_index: int) -> bool:
	return player_index < entries.size() and not entries[player_index].empty()


# ============================================================
# 事件
# ============================================================
func fire(event: String, player_index: int, pos = null, target = null) -> void:
	if player_index < 0 or player_index >= RunData.get_player_count():
		return
	if wave_over and not event in Catalog.SHOP_TRIGGERS:
		return
	_check_dirty()
	if entries[player_index].empty():
		return
	var ctx = {"pos": pos, "target": target, "hold": null}
	for en in entries[player_index]:
		for n in en.g.get("nodes", []):
			if n.kind == event:
				_walk(en, int(n.id), player_index, ctx, 0)


func _walk(en: Dictionary, from_id: int, p: int, ctx: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	for to in GraphEffect.outgoing(en.g, from_id):
		var n = en.by_id.get(to)
		if n == null:
			continue
		match Catalog.node_type(n.kind):
			"cond":
				if _pass(en, n, p):
					_walk(en, to, p, ctx, depth + 1)
			"effect":
				_execute(en, n, p, ctx)


func _param(n: Dictionary, k: String, default = 0):
	return n.get("params", {}).get(k, default)


func _pass(en: Dictionary, n: Dictionary, p: int) -> bool:
	var st = _state(en, int(n.id))
	match n.kind:
		"chance":
			return randf() * 100.0 < float(_param(n, "pct", 100))
		"every":
			st.count += 1
			if st.count >= max(1, int(_param(n, "n", 1))):
				st.count = 0
				return true
			return false
		"cap":
			if st.fired < int(_param(n, "n", 1)):
				st.fired += 1
				return true
			return false
		"cooldown":
			if _elapsed - st.last >= float(_param(n, "secs", 1)):
				st.last = _elapsed
				return true
			return false
		"hp_below":
			return _hp_pct(p) < float(_param(n, "pct", 50))
		"hp_above":
			return _hp_pct(p) >= float(_param(n, "pct", 50))
		"wave_min":
			return RunData.current_wave >= int(_param(n, "n", 1))
		"wave_max":
			return RunData.current_wave <= int(_param(n, "n", 1))
		"stat_min":
			return Utils.get_stat(Keys.generate_hash(str(_param(n, "stat", ""))), p) >= float(_param(n, "n", 0))
		"stat_max":
			return Utils.get_stat(Keys.generate_hash(str(_param(n, "stat", ""))), p) <= float(_param(n, "n", 0))
		"if_moving":
			var pl = _player(p)
			return pl != null and pl._current_movement != Vector2.ZERO
		"if_still":
			var pl = _player(p)
			return pl != null and pl._current_movement == Vector2.ZERO
	return true


func _hp_pct(p: int) -> float:
	var pl = _player(p)
	if pl != null:
		return 100.0 * pl.current_stats.health / max(1.0, pl.max_stats.health)
	return 100.0 * RunData.get_player_current_health(p) / max(1.0, RunData.get_player_max_health(p))


# ============================================================
# 效果
# ============================================================
func _execute(en: Dictionary, n: Dictionary, p: int, ctx: Dictionary) -> void:
	var hp_before = RunData.get_player_max_health(p)
	var stat = str(_param(n, "stat", ""))
	var h = Keys.generate_hash(stat) if stat != "" else Keys.empty_hash
	var v = int(_param(n, "value", 0))
	match n.kind:
		"temp_stat":
			TempStats.add_stat(h, v, p)
			if ctx.hold != null:
				ctx.hold.push_back(["temp", h, v])
		"perm_stat":
			RunData.add_stat(h, v, p)
			LinkedStats.reset_player(p)
		"timed_stat":
			TempStats.add_stat(h, v, p)
			var timer = get_tree().create_timer(max(0.1, float(_param(n, "secs", 1))), false)
			timer.connect("timeout", self, "_on_timed_out", [_wave_serial, h, v, p])
		"heal_hp":
			RunData.emit_signal("healing_effect", v, p, Keys.empty_hash)
		"add_gold":
			if v < 0:
				RunData.remove_gold(-v, p)
			else:
				RunData.add_gold(v, p)
		"xp":
			RunData.add_xp(v, p)
		"rand_stats":
			for _i in max(0, v):
				RunData.add_stat(RunData.get_random_primary_stats(), 1, p)
			LinkedStats.reset_player(p)
		"damage":
			_deal_damage(n, p)
		"explode":
			_explode(n, p, ctx.pos)
		"hp_dmg":
			_hp_damage(n, p, ctx.target)
		"ignite":
			_ignite(n, p, ctx.target)
		"slow":
			_slow(n, ctx.target)
		"fruit":
			call_deferred("_drop_fruit", v, ctx.pos if ctx.pos != null else _player_pos(p))
		"grant":
			_grant(en, n, p, ctx)
	_sync_lost_max_hp(p, hp_before)


func _grant(en: Dictionary, n: Dictionary, p: int, ctx: Dictionary) -> void:
	var ref = _param(n, "ref", null)
	if mod == null or not ref is Dictionary:
		return
	var g = mod.make_effect(ref)
	if g == null:
		return
	g.value = g.value * int(_param(n, "n", 1))
	g.apply(p)
	if str(_param(n, "mode", "temp")) != "perm":
		if ctx.hold != null:
			ctx.hold.push_back(["grant", g])
		else:
			en.granted.push_back(["grant", g])
	_refresh(p)


# 撤销：["temp", hash, 数值] / ["grant", 效果]
func _revert(p: int, undo: Array) -> void:
	if undo.empty() or p >= RunData.get_player_count():
		return
	var hp_before = RunData.get_player_max_health(p)
	for u in undo:
		if u[0] == "temp":
			TempStats.remove_stat(u[1], u[2], p)
		else:
			u[1].unapply(p)
	_refresh(p)
	_sync_lost_max_hp(p, hp_before)


func _on_timed_out(serial: int, h: int, v: int, p: int) -> void:
	if serial != _wave_serial or not is_inside_tree():
		return
	var hp_before = RunData.get_player_max_health(p)
	TempStats.remove_stat(h, v, p)
	_sync_lost_max_hp(p, hp_before)


func _refresh(p: int) -> void:
	Utils.reset_stat_cache(p)
	RunData._are_player_stats_dirty[p] = true
	LinkedStats.reset_player(p)


# 最大生命被临时降低时，当前生命不超过新上限（同 AutoAnthony）
func _sync_lost_max_hp(p: int, before: int) -> void:
	var now = RunData.get_player_max_health(p)
	if now >= before:
		return
	var pl = _player(p)
	if pl == null or pl.dead or pl.current_stats.health <= now:
		return
	pl.current_stats.health = now
	pl.emit_signal("health_updated", pl, pl.current_stats.health, pl.max_stats.health)


func _scaled_damage(n: Dictionary, p: int) -> int:
	var stat_val = Utils.get_stat(Keys.generate_hash(str(_param(n, "stat", ""))), p)
	var base = max(1.0, floor(float(_param(n, "pct", 100)) / 100.0 * stat_val))
	return int(max(1.0, round(base * (1.0 + Utils.get_stat(Keys.stat_percent_damage_hash, p) / 100.0))))


func _deal_damage(n: Dictionary, p: int) -> void:
	if main == null or not is_instance_valid(main):
		return
	var enemies: Array = main._entity_spawner.get_all_enemies(false)
	if enemies.empty():
		return
	var target = enemies[randi() % enemies.size()]
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var _r = target.take_damage(_scaled_damage(n, p), TakeDamageArgs.new(p))


func _explode(n: Dictionary, p: int, pos) -> void:
	if main == null or not is_instance_valid(main):
		return
	if _explosion_effect == null:
		_explosion_effect = load(EXPLOSION_EFFECT_PATH)
	if pos == null:
		pos = _player_pos(p)
		if pos == null:
			return
	var dmg = _scaled_damage(n, p)
	dmg = int(max(1, round(dmg * (1.0 + Utils.get_stat(Keys.explosion_damage_hash, p) / 100.0))))
	var args = WeaponServiceExplodeArgs.new()
	args.pos = pos
	args.damage = dmg
	args.accuracy = 1.0
	args.crit_chance = Utils.get_capped_stat(Keys.stat_crit_chance_hash, p) / 100.0
	args.crit_damage = 1.5
	args.burning_data = BurningData.new()
	args.scaling_stats = []
	args.from_player_index = p
	args.damage_tracking_key_hash = Keys.empty_hash
	WeaponService.call_deferred("explode", _explosion_effect, args)


func _hp_damage(n: Dictionary, p: int, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead or target.current_stats.health <= 0:
		return
	var factor = target._get_health_effect_percent_factor() if target.has_method("_get_health_effect_percent_factor") else 100.0
	var dmg = int(max(1, target.current_stats.health * (float(_param(n, "pct", 1)) / factor)))
	var args = TakeDamageArgs.new(p)
	args.armor_applied = false
	args.dodgeable = false
	var _r = target.take_damage(dmg, args)


func _ignite(n: Dictionary, p: int, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var bd = BurningData.new()
	bd.chance = 1.0
	bd.damage = int(max(1, int(_param(n, "value", 1))))
	bd.duration = 3
	bd.scaling_stats = [[Keys.stat_elemental_damage_hash, 1.0]]
	bd.from = _player(p)
	target.apply_burning(bd)


func _slow(n: Dictionary, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead or not "current_stats" in target:
		return
	var pct = float(_param(n, "pct", 10))
	var floor_speed = target.max_stats.speed * (1.0 - min(0.9, 4.0 * pct / 100.0))
	if target.current_stats.speed > floor_speed:
		target.current_stats.speed = max(floor_speed, target.current_stats.speed - target.max_stats.speed * pct / 100.0)


func _drop_fruit(count: int, pos) -> void:
	if main == null or not is_instance_valid(main) or pos == null or main._cleaning_up:
		return
	for _i in max(0, count):
		var data = ItemService.get_consumable_for_tier(Tier.COMMON)
		if data == null:
			return
		var consumable = main.get_node_from_pool(main._consumable_pool_id, main._consumables_container)
		if consumable == null:
			consumable = main.consumable_scene.instance()
			main._consumables_container.add_child(consumable)
			var _err = consumable.connect("picked_up", main, "on_consumable_picked_up")
		consumable.already_picked_up = false
		consumable.consumable_data = data
		consumable.set_texture(data.icon)
		consumable.drop(pos, 0, ZoneService.get_rand_pos_in_area(pos, rand_range(50, 100), 0))
		main._consumables.push_back(consumable)


func _player(p: int):
	if main == null or not is_instance_valid(main) or p >= main._players.size():
		return null
	var pl = main._players[p]
	return pl if pl != null and is_instance_valid(pl) else null


func _player_pos(p: int):
	var pl = _player(p)
	return pl.global_position if pl != null else null


# ============================================================
# 轮询：状态扳机、每隔 N 秒、计步
# ============================================================
func _physics_process(delta: float) -> void:
	if wave_over or main == null or not is_instance_valid(main):
		return
	_elapsed += delta
	_count_steps(delta)
	_poll += delta
	if _poll < 0.2:
		return
	var step = _poll
	_poll = 0.0
	_check_dirty()
	for p in min(entries.size(), RunData.get_player_count()):
		var pl = _player(p)
		if pl == null or pl.dead:
			continue
		for en in entries[p]:
			for n in en.g.get("nodes", []):
				if n.kind == "interval":
					var st = _state(en, int(n.id))
					st.acc += step
					if st.acc + 0.001 >= max(0.2, float(_param(n, "secs", 1))):
						st.acc = 0.0
						_walk(en, int(n.id), p, {"pos": null, "target": null, "hold": null}, 0)
				elif n.kind in Catalog.STATE_TRIGGERS:
					var st = _state(en, int(n.id))
					var want = _state_holds(n.kind, pl)
					if want == st.active:
						continue
					st.active = want
					if want:
						var ctx = {"pos": null, "target": null, "hold": []}
						_walk(en, int(n.id), p, ctx, 0)
						st.hold = ctx.hold
					else:
						_revert(p, st.hold)
						st.hold = []


func _state_holds(kind: String, pl) -> bool:
	match kind:
		"still":
			return pl._current_movement == Vector2.ZERO
		"moving":
			return pl._current_movement != Vector2.ZERO
		"low_hp":
			return pl.current_stats.health < pl.max_stats.health / 2.0
		"full_hp":
			return pl.current_stats.health >= pl.max_stats.health
	return false


# 计步（同原版徒步旅行者：移动时长 × 2 / 移动动画时长）
func _count_steps(delta: float) -> void:
	for p in min(entries.size(), RunData.get_player_count()):
		if entries[p].empty():
			continue
		var pl = _player(p)
		if pl == null or pl.dead or pl._current_movement == Vector2.ZERO:
			continue
		var anim_len = 0.5
		if "_animation_player" in pl and pl._animation_player != null and pl._animation_player.has_animation(pl.animation_move):
			anim_len = pl._animation_player.get_animation(pl.animation_move).length / max(0.01, pl._animation_player.playback_speed)
		var before = _steps[p]
		_steps[p] += 2.0 * delta / max(0.05, anim_len)
		for _i in range(int(before), int(_steps[p])):
			fire("steps", p)
