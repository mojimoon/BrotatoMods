extends Node

# 战斗内的通用触发总线。挂在 main 场景下（每波创建、随场景释放）。
# 原版的钩子（击杀 / 受击 / 闪避 / 拾取 / 升级 / 回血 / 波次开始与结束）通过脚本扩展转发到 fire()，
# 由这里统一处理门控（每 N 次 / 几率 / 每波上限）并执行载荷。状态扳机（静止 / 移动 / 低血 / 满血）
# 每 0.2 秒轮询一次，进入状态时加临时属性、离开时移除。

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")
const TriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")
const Valuation = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/valuation.gd")
# 每波期望触发次数不超过该值时才显示浮动图标（避免高频扳机刷屏）
const FEEDBACK_MAX_RATE = 12.0
const EXPLOSION_EFFECT_PATH = "res://items/all/rip_and_tear/rip_and_tear_effect_1.tres"

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
	entries[player_index] = list


func _check_dirty() -> void:
	if mod != null and mod.triggers_dirty:
		rebuild_all()


# ============================================================
# 事件入口
# ============================================================
func fire(event: String, player_index: int, pos = null) -> void:
	if player_index < 0 or player_index >= RunData.get_player_count():
		return
	_check_dirty()
	if _depth > 2:
		return	# 防止 "回血 -> 伤害 -> 击杀 -> 回血 ..." 之类的连锁无限递归
	_depth += 1
	for en in entries[player_index]:
		var e = en.effect
		if e.trigger != event:
			continue
		if e.cap > 0 and en.fired >= e.cap:
			continue
		if Catalog.TRIGGERS[e.trigger].gate == "every" and e.param > 1:
			en.count += 1
			if en.count < e.param:
				continue
			en.count = 0
		if e.chance < 100 and randf() * 100.0 >= e.chance:
			continue
		en.fired += 1
		execute(e, player_index, pos, en.show, en)
		if e.reset and e.payload == "temp_stat":
			en.stack = en.get("stack", 0) + e.value
	if event == "hit":
		_reset_on_hit(player_index)
	_depth -= 1


# "受伤时清空"：撤销该条款本波累积的临时属性
func _reset_on_hit(player_index: int) -> void:
	for en in entries[player_index]:
		var e = en.effect
		if e.reset and en.get("stack", 0) != 0:
			TempStats.remove_stat(Keys.generate_hash(e.stat), en.stack, player_index)
			en.stack = 0


# 玩家的原版 took_damage 信号：闪避或实际受到伤害时转发
func on_player_took_damage(unit, value: int, _knockback, _is_crit: bool, is_dodge: bool, _is_protected: bool, _armor_did_something: bool, _args, _hit_type: int, _is_one_shot: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if is_dodge:
		fire("dodge", unit.player_index, unit.global_position)
	elif value > 0:
		fire("hit", unit.player_index, unit.global_position)


func _physics_process(delta: float) -> void:
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
func execute(e, player_index: int, pos, show: bool = true, en = null) -> void:
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
			RunData.add_gold(e.value, player_index)
		"xp":
			RunData.add_xp(e.value, player_index)
		"damage":
			_deal_damage(e, player_index)
		"explode":
			_explode(e, player_index, pos)


func _on_timed_stat_timeout(serial: int, h: int, value: int, player_index: int) -> void:
	# 波次结束时 TempStats 已整体清空，旧波的计时器不能再扣减
	if serial != _wave_serial or not is_inside_tree():
		return
	TempStats.remove_stat(h, value, player_index)


func _scaled_damage(e, player_index: int) -> int:
	var stat_val = Utils.get_stat(Keys.generate_hash(e.stat), player_index)
	var base = max(1.0, floor(e.value / 100.0 * stat_val))
	return int(round(base * (1.0 + Utils.get_stat(Keys.stat_percent_damage_hash, player_index) / 100.0)))


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
	WeaponService.call_deferred("explode", _explosion_effect, args)


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
	for g in en.granted:
		g.unapply(player_index)
	en.granted = []


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
	revert_all_grants()
	for p in entries.size():
		for en in entries[p]:
			en.active = false
			en.fired = 0
			en.count = 0
			en.stack = 0
