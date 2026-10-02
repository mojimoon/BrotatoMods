extends EnemyEffectBehavior

# 挂在每个敌人身上的效果行为（原版 EffectBehaviorService 框架，与冰块的"受伤加成"、DLC 的魅惑 / 诅咒相同）：
#   on_hurt：被玩家命中 -> "首次命中 / 首次某类伤害命中"、"命中高 / 低血敌人"
#   on_burned：燃烧结算 -> 每段燃烧的第一次结算视为"点燃敌人"
#   get_bonus_damage：本 mod"使该敌人受到的伤害提高"载荷

const NODE_NAME = "AutoAnthonyEnemyBehavior"

var _first_done: Dictionary = {}		# player_index -> true
var _first_stats: Dictionary = {}		# player_index -> {stat_hash: true}
var _burn_seen := false
var _vulns: Dictionary = {}		# 来源 -> [百分比, 剩余秒数]
var _vuln_total := 0


static func find_on(enemy):
	if enemy == null or not is_instance_valid(enemy) or not "effect_behaviors" in enemy or enemy.effect_behaviors == null:
		return null
	for c in enemy.effect_behaviors.get_children():
		if c.name == NODE_NAME:
			return c
	return null


func init(parent: Enemy) -> EnemyEffectBehavior:
	.init(parent)
	name = NODE_NAME
	return self


func should_add_on_spawn() -> bool:
	var m = Engine.get_main_loop().root.get_node_or_null("/root/ModLoader/Mojimoon-AutoAnthony")
	return m != null and m.enabled and m.active_state != null


func _rt():
	var main = Utils.get_scene_node()
	if main != null and main.has_method("_aa_rt"):
		return main._aa_rt()
	return null


func on_hurt(hitbox: Hitbox) -> void:
	if hitbox == null or _parent == null or _parent.dead:
		return
	var from = hitbox.from
	if not is_instance_valid(from) or not "player_index" in from or from.player_index < 0:
		return
	var rt = _rt()
	if rt == null:
		return
	var p: int = from.player_index
	var info = {
		"hp_pct": 100.0 * _parent.current_stats.health / max(1.0, float(_parent.max_stats.health)),
		"first_any": false, "first_stats": [], "stats": [],
	}
	if not _first_done.has(p):
		_first_done[p] = true
		info.first_any = true
	var seen = _first_stats.get(p, {})
	for s in hitbox.scaling_stats:
		var h = s[0]
		info.stats.push_back(Keys.hash_to_string.get(h, ""))
		if not seen.has(h):
			seen[h] = true
			info.first_stats.push_back(Keys.hash_to_string.get(h, ""))
	_first_stats[p] = seen
	var pos = _parent.global_position
	if info.first_any or not info.first_stats.empty():
		rt.fire("first_hit", p, pos, -1, _parent, info)
	rt.fire("hit_enemy", p, pos, -1, _parent, info)


func on_burned(_burning_data: BurningData, from_player_index: int) -> void:
	if _burn_seen or from_player_index < 0 or _parent == null or _parent.dead:
		return
	_burn_seen = true
	var rt = _rt()
	if rt != null:
		rt.fire("ignite", from_player_index, _parent.global_position, -1, _parent, null)


func _process(delta: float) -> void:
	if _burn_seen and _parent != null and not _parent._is_burning:
		_burn_seen = false
	if _vulns.empty():
		return
	for src in _vulns.keys():
		var v = _vulns[src]
		v[1] -= delta
		if v[1] <= 0.0:
			_vuln_total -= v[0]
			_vulns.erase(src)


# 与原版受伤加成（冰块、鲁特琴）相同的规则：同一来源不叠层，取较大数值并刷新持续时间；不同来源相加
func add_vuln(pct: int, seconds: float, source: int = 0) -> void:
	if _vulns.has(source):
		var v = _vulns[source]
		if pct > v[0]:
			_vuln_total += pct - v[0]
			v[0] = pct
		v[1] = max(v[1], seconds)
		return
	_vulns[source] = [pct, seconds]
	_vuln_total += pct


func get_bonus_damage(_hitbox: Hitbox, _from_player_index: int) -> int:
	return _vuln_total
