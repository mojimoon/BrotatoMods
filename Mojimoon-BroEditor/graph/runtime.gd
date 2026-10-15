extends Node

# 蓝图运行时：常驻在 mod 节点下。战斗开始时 start_wave(main)，波次结束时 end_wave()。
# 原版事件（击杀 / 受击 / 升级 / 拾取 / 商店刷新……）经脚本扩展转发到 fire()，
# 从对应扳机节点出发沿路径走：条件节点决定是否继续，效果节点执行。
# 状态扳机（静止 / 移动 / 低血 / 满血）每 0.2 秒轮询：进入状态时执行，离开时撤销本次加的本波属性与本波获得的效果。
# 载荷实现参考 AutoAnthony 的 aa/runtime.gd。

const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const GraphEffect = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd")
const EnemyBehavior = preload("res://mods-unpacked/Mojimoon-BroEditor/graph/enemy_behavior.gd")
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
var _timed_list: Array = []	# 持续 N 秒的效果：[{p, u: 撤销列表}]
var _transforms: Array = []	# 待执行的道具变化：[{p, src: 移除的道具或 null, id: 加入的道具 id 或 "", self: 是否为道具变为}]（敌袭结束 / 商店中执行）


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
				for ps in st.get("paths", {}).values():
					if ps.active:
						_revert(p, ps.hold)
				st.paths = {}
				st.active = false
				st.hold = []
				st.fired = 0
				st.count = 0
				st.acc = 0.0
			_revert(p, en.granted)
			en.granted = []
	for rec in _timed_list:
		_revert(rec.p, rec.u)
		rec.u = []
	_timed_list = []
	_flush_transforms()
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
							var g = e.live_graph()
							en = {"effect": e, "g": g, "by_id": GraphEffect.nodes_by_id(g), "st": {}, "granted": [], "src": src, "sp": {}}
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
# target：有目标敌人的事件（命中、暴击、点燃）；info：{hp_pct：目标的生命百分比, stats：伤害类型（缩放属性 key）}
func fire(event: String, player_index: int, pos = null, target = null, info = null) -> void:
	if player_index < 0 or player_index >= RunData.get_player_count():
		return
	if wave_over and not event in Catalog.SHOP_TRIGGERS:
		return
	_check_dirty()
	if entries[player_index].empty():
		return
	var ctx = {"pos": pos, "target": target, "hold": null, "info": info if info is Dictionary else {}}
	for en in entries[player_index]:
		if ctx.info.has("weapon_pos") and en.src is WeaponData and RunData.get_player_weapons_ref(player_index).find(en.src) != int(ctx.info.weapon_pos):
			continue
		for n in en.g.get("nodes", []):
			if n.kind == event and (event != "steps" or _every_n_steps(en, n)):
				_walk(en, int(n.id), player_index, ctx, 0)


# 扳机"每走 N 步"：每个扳机节点单独计数
func _every_n_steps(en: Dictionary, n: Dictionary) -> bool:
	var st = _state(en, int(n.id))
	st.count += 1
	if st.count < max(1, int(_param(n, "n", 1))):
		return false
	st.count = 0
	return true


func _walk(en: Dictionary, from_id: int, p: int, ctx: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	for to in GraphEffect.outgoing(en.g, from_id):
		var n = en.by_id.get(to)
		if n == null:
			continue
		match Catalog.node_type(n.kind):
			"cond":
				if _pass(en, n, p, ctx):
					_walk(en, to, p, ctx, depth + 1)
			"effect":
				_execute(en, n, p, ctx)


func _param(n: Dictionary, k: String, default = 0):
	return n.get("params", {}).get(k, default)


func _pass(en: Dictionary, n: Dictionary, p: int, ctx: Dictionary) -> bool:
	# 不认识的条件（来自更新的版本）不放行
	if Catalog.node_def(n.kind) == null:
		return false
	var st = _state(en, int(n.id))
	match n.kind:
		"chance":
			return randf() * 100.0 < float(_param(n, "pct", 100))
		"stat_chance":
			# 同原版浪漫之人：几率 = max(1, 属性 × pct%)%
			var stat_v = Utils.get_stat(Keys.generate_hash(str(_param(n, "stat", ""))), p)
			return randf() * 100.0 < max(1.0, float(_param(n, "pct", 100)) / 100.0 * stat_v)
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
		"diff_min":
			return RunData.current_difficulty >= int(_param(n, "n", 0))
		"diff_max":
			return RunData.current_difficulty <= int(_param(n, "n", 0))
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
		"enemy_hp_above":
			var hp = _target_hp(ctx)
			return hp != null and hp >= float(_param(n, "pct", 50))
		"enemy_hp_below":
			var hp = _target_hp(ctx)
			return hp != null and hp < float(_param(n, "pct", 50))
		"dmg_type":
			return str(_param(n, "stat", "")) in ctx.info.get("stats", [])
		"own_tag":
			var tag = str(_param(n, "tag", ""))
			var c = 0
			for it in RunData.get_player_items(p):
				if tag in it.tags:
					c += 1
			return _cmp(n, c)
		"own_item":
			# 道具按 my_id；武器按家族（weapon_id，任意等级）
			var oid = str(_param(n, "id", ""))
			var c = 0
			for it in RunData.get_player_items(p):
				if it.my_id == oid:
					c += 1
			for w in RunData.get_player_weapons(p):
				if w.weapon_id == oid:
					c += 1
			return _cmp(n, c)
		"own_set":
			var sid = str(_param(n, "set", ""))
			var c = 0
			for w in RunData.get_player_weapons(p):
				for s in w.sets:
					if s.my_id == sid:
						c += 1
			return _cmp(n, c)
		"once":
			var tokens = GraphEffect.once_list(p)
			return tokens != null and GraphEffect.take_once(tokens, en.effect.once_token(int(n.id)))
	return true


# 数量比较：至少 / 至多 / 恰好 n
func _cmp(n: Dictionary, c: int) -> bool:
	var want = int(_param(n, "n", 1))
	match str(_param(n, "cmp", "at_least")):
		"at_most":
			return c <= want
		"exactly":
			return c == want
	return c >= want


# 目标敌人的生命百分比：命中事件为命中前，其余为当前；没有目标敌人为 null
func _target_hp(ctx: Dictionary):
	if ctx.info.has("hp_pct"):
		return float(ctx.info.hp_pct)
	var t = ctx.target
	if t != null and is_instance_valid(t) and "current_stats" in t:
		return 100.0 * t.current_stats.health / max(1.0, float(t.max_stats.health))
	return null


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
			var u = _add_temp(h, v, p)
			if ctx.hold != null:
				ctx.hold.push_back(u)
			elif u[0] == "eff":
				en.granted.push_back(u)
		"perm_stat":
			if Utils.is_stat_key(h):
				RunData.add_stat(h, v, p)
			else:
				_add_effect(h, v, p)
			_refresh(p)
		"timed_stat":
			_timed(p, [_add_temp(h, v, p)], _param(n, "secs", 1))
		"vuln":
			_vuln(n, ctx.target)
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
		"transform":
			_transform(en, n, p)
		"gain_item":
			_gain_item(n, p)
		"lose_item":
			_lose_item(n, p)
		"charm":
			_charm(p, ctx.target)
		"spawn":
			_spawn(n, p)
		"break":
			_break(en, v, p)
		"shop_add", "shop_remove":
			if mod != null:
				mod.run_shop_change(p, _param(n, "items", []), n.kind == "shop_add")
		"grant":
			_grant(en, n, p, ctx)
		"shop_force":
			if mod != null:
				mod.queue_shop_force(p, _param(n, "items", []))
		"group_unlock", "group_lock":
			if mod != null:
				mod.set_group_locked(str(_param(n, "group", "")), n.kind == "group_lock")
	_sync_lost_max_hp(p, hp_before)


# 道具变为：持有者是道具时，换成列表中随机一件；列表为空时移除它（原版 remove_item 换成"移除后变成"的道具）
func _transform(en: Dictionary, n: Dictionary, p: int) -> void:
	var ids = _param(n, "items", [])
	var src = en.get("src")
	if not ids is Array or not src is ItemData or src is CharacterData:
		return
	for t in _transforms:
		if t.src == src and t.p == p and t.self:
			return
	_queue_item_change(p, src, _pick_id(ids), true)


# 获得道具：列表中随机一件；列表为空时为本波商店里可能出现的随机道具
func _gain_item(n: Dictionary, p: int) -> void:
	var ids = _param(n, "items", [])
	var id = _pick_id(ids)
	if id == "":
		var it = ItemService.get_rand_item_for_wave(RunData.current_wave, p)
		if it == null or not it is ItemData:
			return
		id = it.my_id
	_queue_item_change(p, null, id, false)


# 失去道具：已拥有的、列表中的道具里随机一件（列表为空时为任意已拥有的道具）；原版照常换成"移除后变成"
func _lose_item(n: Dictionary, p: int) -> void:
	var ids = _param(n, "items", [])
	ids = ids if ids is Array else []
	var owned = []
	var queued = []
	for t in _transforms:
		queued.push_back(t.src)
	for it in RunData.get_player_items_ref(p):
		if (ids.empty() or it.my_id in ids) and not it in queued and not it is CharacterData:
			owned.push_back(it)
	if not owned.empty():
		_queue_item_change(p, owned[randi() % owned.size()], "", false)


func _pick_id(ids) -> String:
	return str(ids[randi() % ids.size()]) if ids is Array and not ids.empty() else ""


func _queue_item_change(p: int, src, id: String, is_self: bool) -> void:
	_transforms.push_back({"p": p, "src": src, "id": id, "self": is_self})
	if wave_over:
		_flush_transforms()


func _flush_transforms() -> void:
	var list = _transforms
	_transforms = []
	for t in list:
		var target = mod.find_target("item", t.id) if mod != null and t.id != "" else null
		if (t.id != "" and target == null) or t.p >= RunData.get_player_count():
			continue
		if t.src != null:
			if not t.src in RunData.get_player_items_ref(t.p):
				continue
			# 道具变为：没有指定道具时由原版换成"移除后变成"；指定了道具时只换成该道具
			var rep = t.src.replaced_by
			if target != null and t.self:
				t.src.replaced_by = null
			RunData.remove_item(t.src, t.p)
			t.src.replaced_by = rep
		if target != null:
			RunData.add_item(target, t.p)
		# 商店中：刷新装备栏
		var scene = get_tree().current_scene if is_inside_tree() else null
		if scene != null and scene.has_method("_get_gear_container"):
			var gear = scene._get_gear_container(t.p)
			if gear != null:
				gear.set_items_data(RunData.get_player_items(t.p))


# 魅惑（同浪漫之人：原版魅惑行为，每名玩家最多同时 5 个）；敌人身上没有魅惑行为时补上
const CHARM_SCENE = "res://dlcs/dlc_1/effect_behaviors/enemy/charm_enemy_effect_behavior.tscn"


func _charm(p: int, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead or not "effect_behaviors" in target:
		return
	if target is Boss or target.is_loot or not target.can_be_charmed:
		return
	var b = null
	for c in target.effect_behaviors.get_children():
		if "charmed" in c:
			b = c
	if b == null:
		if not ResourceLoader.exists(CHARM_SCENE):
			return
		b = load(CHARM_SCENE).instance().init(target)
		target.effect_behaviors.add_child(b)
	if b.charmed or RunData.current_charmed_enemies[p] >= b.max_charm_count:
		return
	b.charm(p)


# 生成敌人：地图上随机位置（原版出生标记）
func _spawn(n: Dictionary, p: int) -> void:
	if main == null or not is_instance_valid(main) or mod == null:
		return
	var scene = mod.enemy_scene(str(_param(n, "enemy", "")))
	if scene == null:
		return
	for _i in clamp(int(_param(n, "n", 1)), 0, 50):
		main._entity_spawner.spawn_entity_birth(EntityType.ENEMY, scene, ZoneService.get_rand_pos(), null, p)


# 损坏：持有者是武器时，这把武器损坏并掉落材料（同原版砖块）
func _break(en: Dictionary, gold: int, p: int) -> void:
	var src = en.get("src")
	var pl = _player(p)
	if not src is WeaponData or pl == null:
		return
	var pos = RunData.get_player_weapons_ref(p).find(src)
	for w in pl.current_weapons:
		if w.weapon_pos == pos:
			pl.call_deferred("on_weapon_wanted_to_break", w, max(0, gold))
			return


func _grant(en: Dictionary, n: Dictionary, p: int, ctx: Dictionary) -> void:
	var ref = _param(n, "ref", null)
	if mod == null or not ref is Dictionary:
		return
	var g = mod.make_effect(ref)
	if g == null:
		return
	g.value = g.value * int(_param(n, "n", 1))
	g.apply(p)
	match str(_param(n, "mode", "temp")):
		"perm":
			pass
		"timed":
			_timed(p, [["grant", g]], _param(n, "secs", 5))
		_:
			if ctx.hold != null:
				ctx.hold.push_back(["grant", g])
			else:
				en.granted.push_back(["grant", g])
	_refresh(p)


# 本波属性：原版临时属性表里有的 key 走 TempStats（原版波末清空）；其余（敌人数量、价格…）直接改玩家效果表，由本运行时撤销
func _add_temp(h: int, v: int, p: int) -> Array:
	if TempStats.player_stats[p].has(h):
		TempStats.add_stat(h, v, p)
		return ["temp", h, v]
	_add_effect(h, v, p)
	return ["eff", h, v]


func _add_effect(h: int, v: int, p: int) -> void:
	var effects = RunData.get_player_effects(p)
	if typeof(effects.get(h)) in [TYPE_INT, TYPE_REAL]:
		effects[h] += v
	_refresh(p)


# 持续 N 秒：到时撤销；波次提前结束时由 end_wave 撤销
func _timed(p: int, undo: Array, secs) -> void:
	var rec = {"p": p, "u": undo}
	_timed_list.push_back(rec)
	var timer = get_tree().create_timer(max(0.1, float(secs)), false)
	timer.connect("timeout", self, "_on_timed_out", [rec])


func _on_timed_out(rec: Dictionary) -> void:
	_revert(rec.p, rec.u)
	rec.u = []


# 撤销：["temp", hash, 数值] / ["eff", hash, 数值] / ["grant", 效果]
func _revert(p: int, undo: Array) -> void:
	if undo.empty() or p >= RunData.get_player_count():
		return
	var hp_before = RunData.get_player_max_health(p)
	for u in undo:
		match u[0]:
			"temp":
				TempStats.remove_stat(u[1], u[2], p)
			"eff":
				_add_effect(u[1], -u[2], p)
			_:
				u[1].unapply(p)
	_refresh(p)
	_sync_lost_max_hp(p, hp_before)


func _refresh(p: int) -> void:
	Utils.reset_stat_cache(p)
	RunData._are_player_stats_dirty[p] = true
	LinkedStats.reset_player(p)
	EntityService.reset_cache()


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
	args.set_meta("be_bp", true)
	WeaponService.call_deferred("explode", _explosion_effect, args)


# 使目标敌人受到的伤害提高 X%，持续 N 秒（敌人身上的效果行为；同一节点不叠层，取较大值并刷新时间）
func _vuln(n: Dictionary, target) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var b = EnemyBehavior.find_on(target)
	if b != null:
		b.add_vuln(int(_param(n, "pct", 10)), max(0.1, float(_param(n, "secs", 3))), str(n.id) + JSON.print(n.params))


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
					poll_state(en, n, p, pl)


# 状态扳机：每条路径单独记录是否已进入。扳机状态与路径上的状态条件都满足时进入：检查其余条件（只此一次），
# 通过则执行效果；任一状态不再满足时撤销本次的本波属性与本波获得
func poll_state(en: Dictionary, trig: Dictionary, p: int, pl) -> void:
	var st = _state(en, int(trig.id))
	if not st.has("paths"):
		st.paths = {}
	var on = _state_holds(trig, pl)
	for path in _state_paths(en, int(trig.id)):
		var key = str(path)
		if not st.paths.has(key):
			st.paths[key] = {"active": false, "hold": []}
		var ps = st.paths[key]
		var want = on and _state_conds_hold(en, path, p)
		if want == ps.active:
			continue
		ps.active = want
		if not want:
			_revert(p, ps.hold)
			ps.hold = []
			continue
		var ctx = {"pos": null, "target": null, "hold": [], "info": {}}
		var ok = true
		for i in range(1, path.size() - 1):
			var c = en.by_id[path[i]]
			if not c.kind in Catalog.STATE_CONDS and not _pass(en, c, p, ctx):
				ok = false
				break
		if ok:
			_execute(en, en.by_id[path[-1]], p, ctx)
		ps.hold = ctx.hold


func _state_paths(en: Dictionary, trig_id: int) -> Array:
	if not en.has("sp"):
		en.sp = {}
	if not en.sp.has(trig_id):
		var out = []
		for path in GraphEffect.paths(en.g):
			if path[0] == trig_id:
				out.push_back(path)
		en.sp[trig_id] = out
	return en.sp[trig_id]


func _state_conds_hold(en: Dictionary, path: Array, p: int) -> bool:
	var ctx = {"pos": null, "target": null, "hold": null, "info": {}}
	for i in range(1, path.size() - 1):
		var c = en.by_id[path[i]]
		if c.kind in Catalog.STATE_CONDS and not _pass(en, c, p, ctx):
			return false
	return true


func _state_holds(n: Dictionary, pl) -> bool:
	match n.kind:
		"still":
			return pl._current_movement == Vector2.ZERO
		"moving":
			return pl._current_movement != Vector2.ZERO
		"low_hp":
			return pl.current_stats.health < pl.max_stats.health * float(_param(n, "pct", 50)) / 100.0
		"full_hp":
			return pl.current_stats.health >= pl.max_stats.health
		"always":
			return true
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
