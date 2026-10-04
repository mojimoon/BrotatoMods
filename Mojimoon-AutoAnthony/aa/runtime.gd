extends Node

# 战斗内的通用触发总线。挂在 main 场景下（每波创建、随场景释放）。
# 原版的钩子（击杀 / 受击 / 闪避 / 拾取 / 升级 / 回血 / 波次开始与结束）通过脚本扩展转发到 fire()，
# 由这里统一处理门控（每 N 次 / 几率 / 每波上限）并执行载荷。状态扳机（静止 / 移动 / 低血 / 满血）
# 每 0.2 秒轮询一次，进入状态时加临时属性、离开时移除。

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")
const TriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")
const Valuation = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/valuation.gd")
const AAEnemyBehavior = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/enemy_behavior.gd")
# 每波期望触发次数不超过该值时才显示浮动图标（避免高频扳机刷屏）
const FEEDBACK_MAX_RATE = 12.0
const EXPLOSION_EFFECT_PATH = "res://items/all/rip_and_tear/rip_and_tear_effect_1.tres"

# 本波已结束（运行时每波重建）
var _wave_over := false
var main: Node = null
var mod: Node = null
# 每个玩家的触发条款列表：[{effect, count, fired, active}]
var entries: Array = [[], [], [], []]
var _poll_time := 0.0
var _elapsed := 0.0
var _wave_serial := 0
var _depth := 0
var _explosion_effect = null
var _explode_args = null
var _damage_args = null
# 计步（与原版徒步旅行者一致：移动时长 × 2 / 移动动画时长）
var _steps: Array = [0.0, 0.0, 0.0, 0.0]


func setup(p_main: Node, p_mod: Node) -> void:
	main = p_main
	mod = p_mod
	name = "AutoAnthonyRuntime"
	_wave_serial = randi()
	_explosion_effect = load(EXPLOSION_EFFECT_PATH)
	rebuild_all()


func rebuild_all() -> void:
	for p in RunData.get_player_count():
		rebuild(p)
	if mod != null:
		mod.triggers_dirty = false


# 收集玩家角色、道具、武器上的所有触发条款
func rebuild(player_index: int) -> void:
	var old = {}
	for en in entries[player_index]:
		old[en.effect.get_instance_id()] = en
	var list = []
	var sources = []
	sources += RunData.get_player_items_ref(player_index)
	sources += RunData.get_player_weapons_ref(player_index)
	for src in sources:
		for e in src.effects:
			if e is TriggerEffect:
				var id = e.get_instance_id()
				if old.has(id):
					list.push_back(old[id])
				else:
					var show = Valuation.raw_rate(e.trigger, e.param, e.chance) <= FEEDBACK_MAX_RATE and not e.trigger in ["still", "moving"] and Catalog.STATS.has(e.stat)
					list.push_back({"effect": e, "count": 0, "fired": 0, "active": false, "show": show, "stack": 0, "granted": []})
	# 被移除的状态加成要撤销
	var reverted = false
	for id in old:
		var still_there = false
		for en in list:
			if en.effect.get_instance_id() == id:
				still_there = true
				break
		if not still_there:
			if old[id].active:
				_set_state(player_index, old[id], false)
			if not old[id].granted.empty():
				_revert_grants(player_index, old[id])
				reverted = true
	entries[player_index] = list
	# 撤销的"获得效果"可能是计数型（LinkedStats）：立即重算，不等下一次刷新
	if reverted:
		_refresh(player_index)


func _check_dirty() -> void:
	if mod != null and mod.triggers_dirty:
		rebuild_all()


# ============================================================
# 事件入口
# ============================================================
# chain_depth：延迟发生的事件（爆炸）携带的连锁深度；target：有目标敌人的事件（命中、暴击、点燃）；
# info：命中事件的附加信息（hp_pct：命中前的生命百分比；first_any / first_stats：对该敌人的首次命中 / 首次某类伤害命中）
func fire(event: String, player_index: int, pos = null, chain_depth: int = -1, target = null, info = null) -> void:
	if _wave_over or player_index < 0 or player_index >= RunData.get_player_count():
		return
	_check_dirty()
	var saved_depth = _depth
	if chain_depth >= 0:
		_depth = max(_depth, chain_depth)
	if _depth >= Catalog.MAX_CHAIN_DEPTH:
		_depth = saved_depth
		return	# 连锁（"A 触发 B、B 触发 C"）最多 MAX_CHAIN_DEPTH 层，防止无限递归
	# 连锁中的触发（由另一条条款或本 mod 的爆炸引起）才受每秒次数上限约束
	var chained = _depth > 0
	_depth += 1
	for en in entries[player_index]:
		var e = en.effect
		if not _matches(e.trigger, event, info, e.dmg_type):
			continue
		if e.cap > 0 and en.fired >= e.cap:
			continue
		# 每秒触发次数上限（连锁保护）
		var sec = int(_elapsed)
		if en.get("rate_sec", -1) != sec:
			en["rate_sec"] = sec
			en["rate_n"] = 0
		if chained and en.rate_n >= Catalog.MAX_FIRES_PER_SECOND:
			continue
		if Catalog.TRIGGERS[e.trigger].gate == "every" and e.param > 1:
			en.count += 1
			if en.count < e.param:
				continue
			en.count = 0
		if e.chance < 100 and randf() * 100.0 >= e.chance:
			continue
		en.fired += 1
		en.rate_n += 1
		execute(e, player_index, pos, en.show, en, target)
		if e.reset and e.payload == "temp_stat":
			en.stack = en.get("stack", 0) + e.value
	if event == "hit":
		_reset_on_hit(player_index)
	_depth = saved_depth


# 事件与扳机的对应：命中事件（hit_enemy）按命中前的生命百分比分发到"命中高 / 低血敌人"；
# 首次命中事件按"对该敌人首次命中 / 首次某类伤害命中"分发
static func _matches(trigger: String, event: String, info, dmg_type: String = "") -> bool:
	if event == "hit_enemy":
		if info == null:
			return false
		if trigger.begins_with("hit_above_"):
			return info.hp_pct >= float(trigger.get_slice("_", 2))
		if trigger.begins_with("hit_below_"):
			return info.hp_pct <= float(trigger.get_slice("_", 2))
		if trigger == "hit_typed":
			return dmg_type in info.get("stats", [])
		return false
	if event == "first_hit":
		if info == null:
			return false
		if trigger == "first_hit":
			return info.get("first_any", false)
		if trigger == "first_hit_typed":
			return dmg_type in info.get("first_stats", [])
		return false
	if event == "kill_typed":
		return trigger == event and info != null and dmg_type in info.get("stats", [])
	return trigger == event


# "受伤时清空"：撤销该条款本波累积的临时属性
func _reset_on_hit(player_index: int) -> void:
	var hp_before = _max_hp(player_index)
	for en in entries[player_index]:
		var e = en.effect
		if e.reset and en.get("stack", 0) != 0:
			TempStats.remove_stat(Keys.generate_hash(e.stat), en.stack, player_index)
			en.stack = 0
	_sync_lost_max_hp(player_index, hp_before)


# 玩家的原版 took_damage 信号：闪避或实际受到伤害时转发
func on_player_took_damage(unit, value: int, _knockback, _is_crit: bool, is_dodge: bool, _is_protected: bool, _armor_did_something: bool, _args, _hit_type: int, _is_one_shot: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if is_dodge:
		fire("dodge", unit.player_index, unit.global_position)
	elif value > 0:
		fire("hit", unit.player_index, unit.global_position)


func _physics_process(delta: float) -> void:
	if _wave_over:
		return
	_elapsed += delta
	_count_steps(delta)
	_poll_time += delta
	if _poll_time < 0.2:
		return
	var step = _poll_time
	_poll_time = 0.0
	_check_dirty()
	for p in RunData.get_player_count():
		var player = _get_player(p)
		if player == null or player.dead:
			continue
		for en in entries[p]:
			var e = en.effect
			if e.trigger == "interval":
				en.count += 1
				# count 以 0.2 秒为单位累积
				if en.count * 0.2 + 0.001 >= e.param:
					en.count = 0
					if (e.cap <= 0 or en.fired < e.cap) and (e.chance >= 100 or randf() * 100.0 < e.chance):
						en.fired += 1
						execute(e, p, null, en.show, en)
						if e.reset and e.payload == "temp_stat":
							en.stack = en.get("stack", 0) + e.value
			elif Catalog.TRIGGERS[e.trigger].kind == "state":
				var want = _state_holds(e.trigger, player)
				if want != en.active:
					_set_state(p, en, want)
	var _unused = step


func _count_steps(delta: float) -> void:
	for p in RunData.get_player_count():
		var player = _get_player(p)
		if player == null or player.dead or player._current_movement == Vector2.ZERO:
			continue
		var anim_len = 0.5
		if "_animation_player" in player and player._animation_player != null and player._animation_player.has_animation(player.animation_move):
			anim_len = player._animation_player.get_animation(player.animation_move).length / max(0.01, player._animation_player.playback_speed)
		var before = _steps[p]
		_steps[p] += 2.0 * delta / max(0.05, anim_len)
		for _i in range(int(before), int(_steps[p])):
			fire("steps", p)


func _state_holds(trigger: String, player) -> bool:
	match trigger:
		"still":
			return player._current_movement == Vector2.ZERO
		"moving":
			return player._current_movement != Vector2.ZERO
		"low_hp":
			return player.current_stats.health < player.max_stats.health / 2.0
		"full_hp":
			return player.current_stats.health >= player.max_stats.health
	return false


func _set_state(player_index: int, en: Dictionary, on: bool) -> void:
	var hp_before = _max_hp(player_index)
	_set_state_inner(player_index, en, on)
	_sync_lost_max_hp(player_index, hp_before)


func _set_state_inner(player_index: int, en: Dictionary, on: bool) -> void:
	en.active = on
	var e = en.effect
	if e.payload == "grant":
		if on and e.grant != null:
			var g = e.scaled_grant()
			g.apply(player_index)
			en.granted.push_back(g)
		elif not on:
			_revert_grants(player_index, en)
		_refresh(player_index)
		return
	var h = Keys.generate_hash(e.stat)
	if on:
		TempStats.add_stat(h, e.value, player_index)
		if en.get("show", false):
			RunData.emit_signal("stat_added", h, e.value, 0.0, player_index)
	else:
		TempStats.remove_stat(h, e.value, player_index)
		if en.get("show", false):
			RunData.emit_signal("stat_removed", h, e.value, 0.0, player_index)


# ============================================================
# 载荷
# ============================================================
func execute(e, player_index: int, pos, show: bool = true, en = null, target = null) -> void:
	var hp_before = _max_hp(player_index)
	_execute_inner(e, player_index, pos, show, en, target)
	_sync_lost_max_hp(player_index, hp_before)


func _execute_inner(e, player_index: int, pos, show: bool, en, target) -> void:
	var h = Keys.generate_hash(e.stat) if e.stat != "" else Keys.empty_hash
	match e.payload:
		"grant":
			if e.grant == null:
				return
			var g = e.scaled_grant()
			g.apply(player_index)
			if e.grant_mode != "perm" and en != null:
				en.granted.push_back(g)
			_refresh(player_index)
		"temp_stat":
			TempStats.add_stat(h, e.value, player_index)
			if show:
				RunData.emit_signal("stat_added", h, e.value, 0.0, player_index)

		"perm_stat":
			RunData.add_stat(h, e.value, player_index)

			LinkedStats.reset_player(player_index)
		"timed_stat":
			TempStats.add_stat(h, e.value, player_index)
			if show:
				RunData.emit_signal("stat_added", h, e.value, 0.0, player_index)
			var serial = _wave_serial
			var timer = get_tree().create_timer(max(0.1, e.value2), false)
			timer.connect("timeout", self, "_on_timed_stat_timeout", [serial, h, e.value, player_index])

		"heal":
			RunData.emit_signal("healing_effect", e.value, player_index, Keys.empty_hash)
		"gold":
			# 负值（更多双面效果的代价）：失去材料，不低于 0
			if e.value < 0:
				RunData.remove_gold(-e.value, player_index)
			else:
				RunData.add_gold(e.value, player_index)
		"xp":
			RunData.add_xp(e.value, player_index)
		"damage":
			_deal_damage(e, player_index)
		"explode":
			_explode(e, player_index, pos)
		"vuln":
			_vuln(e, target)
		"hp_dmg":
			_hp_damage(e, player_index, target)
		"ignite":
			_ignite(e, player_index, target)
		"slow":
			_slow(e, target)
		"fruit":
			call_deferred("_drop_fruit", e.value, pos if pos != null else _player_pos(player_index))
		"rand_stats":
			# 糖果袋：每点随机分配到一项主要属性
			for _i in max(0, e.value):
				RunData.add_stat(RunData.get_random_primary_stats(), 1, player_index)
			LinkedStats.reset_player(player_index)


func _on_timed_stat_timeout(serial: int, h: int, value: int, player_index: int) -> void:
	# 波次结束时 TempStats 已整体清空，旧波的计时器不能再扣减
	if serial != _wave_serial or not is_inside_tree():
		return
	var hp_before = _max_hp(player_index)
	TempStats.remove_stat(h, value, player_index)
	_sync_lost_max_hp(player_index, hp_before)


# 最大生命的临时变化：原版降低最大生命时不压低当前生命、升高时把差值加到当前生命（player.update_player_stats），
# 状态型 / 限时 / 本波效果反复开关时当前生命会不断上涨（"移动时 -2 最大生命"走停一次回 2 点，满血时超出上限）。
# 本 mod 的效果降低最大生命时，当前生命 = min(当前生命, 降低后的最大生命)
func _max_hp(player_index: int) -> int:
	return RunData.get_player_max_health(player_index)


func _sync_lost_max_hp(player_index: int, before: int) -> void:
	var now = _max_hp(player_index)
	if now >= before:
		return
	var player = _get_player(player_index)
	if player == null or player.dead or player.current_stats.health <= now:
		return
	player.current_stats.health = now
	player.emit_signal("health_updated", player, player.current_stats.health, player.max_stats.health)


func _scaled_damage(e, player_index: int) -> int:
	var stat_val = Utils.get_stat(Keys.generate_hash(e.stat), player_index)
	var base = max(1.0, floor(e.value / 100.0 * stat_val))
	# 与原版一致：%伤害再低，伤害也至少为 1
	return int(max(1.0, round(base * (1.0 + Utils.get_stat(Keys.stat_percent_damage_hash, player_index) / 100.0))))


func _deal_damage(e, player_index: int) -> void:
	if main == null or not is_instance_valid(main):
		return
	var enemies: Array = main._entity_spawner.get_all_enemies(false)
	if enemies.empty():
		return
	var target = enemies[randi() % enemies.size()]
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var dmg = _scaled_damage(e, player_index)
	if dmg <= 0:
		return
	if _damage_args == null:
		_damage_args = TakeDamageArgs.new(player_index)
	_damage_args._init(player_index)
	var _r = target.take_damage(dmg, _damage_args)


func _explode(e, player_index: int, pos) -> void:
	if _explosion_effect == null or main == null or not is_instance_valid(main):
		return
	var player = _get_player(player_index)
	if pos == null:
		if player == null:
			return
		pos = player.global_position
	var dmg = _scaled_damage(e, player_index)
	var exploding_bonus = Utils.get_stat(Keys.explosion_damage_hash, player_index) / 100.0
	dmg = int(max(1, round(dmg * (1.0 + exploding_bonus))))
	var args = WeaponServiceExplodeArgs.new()
	args.pos = pos
	args.damage = dmg
	args.accuracy = 1.0
	args.crit_chance = Utils.get_capped_stat(Keys.stat_crit_chance_hash, player_index) / 100.0
	args.crit_damage = 1.5
	args.burning_data = BurningData.new()
	args.scaling_stats = []
	args.from_player_index = player_index
	args.damage_tracking_key_hash = Keys.empty_hash
	# 爆炸延迟生成：记下当前连锁深度，"引发爆炸时"扳机从这里继续计数
	args.set_meta("aa_depth", _depth)
	WeaponService.call_deferred("explode", _explosion_effect, args)


func _player_pos(player_index: int):
	var p = _get_player(player_index)
	return p.global_position if p != null else null


# 点燃目标（害怕的香肠）：3 跳 × X（+100% 元素伤害）
func _ignite(e, player_index: int, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var player = _get_player(player_index)
	var bd = BurningData.new()
	bd.chance = 1.0
	bd.damage = int(max(1, e.value))
	bd.duration = Catalog.IGNITE_TICKS
	bd.scaling_stats = [[Keys.stat_elemental_damage_hash, 1.0]]
	bd.from = player
	target.apply_burning(bd)


# 减速目标（丑牙）：每次降低最大速度的 X%，最多降到 (1 - 4X%)
func _slow(e, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead or not "current_stats" in target:
		return
	var floor_speed = target.max_stats.speed * (1.0 - min(0.9, 4.0 * e.value / 100.0))
	if target.current_stats.speed > floor_speed:
		target.current_stats.speed = max(floor_speed, target.current_stats.speed - target.max_stats.speed * e.value / 100.0)


# 掉落水果（果篮）：与原版敌人掉落消耗品相同的对象池与拾取信号
func _drop_fruit(count: int, pos) -> void:
	# 清场（波次结束）后掉落的消耗品不会被吸取，跳过
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


# 按目标敌人当前生命值的 X% 造成伤害（同巨型带 / 希腊火：头目和精英按原版的 1/10，无尽模式同样折减）
func _hp_damage(e, player_index: int, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead or target.current_stats.health <= 0:
		return
	var factor = target._get_health_effect_percent_factor() if target.has_method("_get_health_effect_percent_factor") else 100.0
	var endless = max(1.0, RunData.get_endless_factor() * 0.2)
	var dmg = int(max(1, target.current_stats.health * (e.value / factor) / endless))
	var args = TakeDamageArgs.new(player_index)
	args.armor_applied = false
	args.dodgeable = false
	var _r = target.take_damage(dmg, args)


# 使目标敌人受到的伤害提高（挂在敌人身上的本 mod 效果行为节点）
func _vuln(e, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var b = AAEnemyBehavior.find_on(target)
	if b != null:
		# 来源 = 条款内容：同一道具（同 ID 的多件）的同一条款不叠层，不同道具 / 不同条款相加
		b.add_vuln(e.value, float(clamp(e.value2, 1, Catalog.VULN_SECONDS)), hash(JSON.print(e.to_clause())))


func _get_player(player_index: int):
	if main == null or not is_instance_valid(main):
		return null
	if player_index >= main._players.size():
		return null
	var p = main._players[player_index]
	if p == null or not is_instance_valid(p):
		return null
	return p


# "本波获得"的效果：撤销
func _revert_grants(player_index: int, en: Dictionary) -> void:
	var hp_before = _max_hp(player_index)
	for g in en.granted:
		g.unapply(player_index)
	en.granted = []
	_sync_lost_max_hp(player_index, hp_before)


func _refresh(player_index: int) -> void:
	Utils.reset_stat_cache(player_index)
	RunData._are_player_stats_dirty[player_index] = true
	LinkedStats.reset_player(player_index)


func revert_all_grants() -> void:
	for p in entries.size():
		var any = false
		for en in entries[p]:
			if not en.granted.empty():
				_revert_grants(p, en)
				any = true
		if any and p < RunData.get_player_count():
			_refresh(p)


# 场景提前结束（死亡 / 退出 / 重开）时也要撤销，避免"本波获得"的效果残留到之后
func _exit_tree() -> void:
	revert_all_grants()


# 波次结束：清空状态（TempStats 由原版在波末整体重置）；撤销"本波获得"的效果
func on_wave_end() -> void:
	_wave_serial += 1
	# 波次结束后（回收箱子道具、清场期间）不再触发任何条款：每 N 秒、状态、事件
	_wave_over = true
	revert_all_grants()
	for p in entries.size():
		for en in entries[p]:
			en.active = false
			en.fired = 0
			en.count = 0
			en.stack = 0
