extends EnemyEffectBehavior

# 挂在每个敌人身上的效果行为（原版 EffectBehaviorService 框架，同 AutoAnthony 的 aa/enemy_behavior.gd）：
#   on_hurt：被玩家命中 -> 蓝图扳机"命中敌人时 / 首次命中敌人时"（附命中前生命百分比、伤害类型）
#   on_burned：每段燃烧的第一次结算 -> "点燃敌人时"
#   get_bonus_damage：蓝图效果"使其受到的伤害提高"

const NODE_NAME = "BroEditorEnemyBehavior"
const MOD_PATH = "/root/ModLoader/Mojimoon-BroEditor"

var _first_done: Dictionary = {}	# player_index -> true
var last_stats: Array = []	# 最近一次命中的伤害缩放属性（击杀的伤害类型取致命一击）
var _burn_seen := false
var _vulns: Dictionary = {}	# 来源 -> [百分比, 剩余秒数]
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
	return Engine.get_main_loop().root.get_node_or_null(MOD_PATH) != null


func _rt():
	var m = Engine.get_main_loop().root.get_node_or_null(MOD_PATH)
	return m.runtime if m != null and m.runtime != null and not m.runtime.wave_over else null


func hp_pct() -> float:
	return 100.0 * _parent.current_stats.health / max(1.0, float(_parent.max_stats.health))


func on_hurt(hitbox: Hitbox) -> void:
	if hitbox == null or _parent == null or _parent.dead:
		return
	var from = hitbox.from
	if not is_instance_valid(from) or not "player_index" in from or from.player_index < 0:
		return
	var stats = stat_names(hitbox.scaling_stats)
	last_stats = stats
	# 蓝图自己的爆炸不再触发命中扳机（防止"命中 -> 爆炸 -> 命中"无限连锁）
	if from.has_meta("be_bp") and from.get_meta("be_bp"):
		return
	var rt = _rt()
	if rt == null:
		return
	var p: int = from.player_index
	var info = {"hp_pct": hp_pct(), "stats": stats}
	# 武器的命中：武器上的蓝图只响应自己的命中
	if "weapon_pos" in from and int(from.weapon_pos) >= 0:
		info.weapon_pos = int(from.weapon_pos)
	var pos = _parent.global_position
	if not _first_done.has(p):
		_first_done[p] = true
		rt.fire("first_hit", p, pos, _parent, info)
	rt.fire("enemy_hit", p, pos, _parent, info)


static func stat_names(scaling: Array) -> Array:
	var out = []
	for s in scaling:
		out.push_back(Keys.hash_to_string.get(s[0], "") if s[0] is int else str(s[0]))
	return out


func on_burned(burning_data: BurningData, from_player_index: int) -> void:
	if _burn_seen or from_player_index < 0 or _parent == null or _parent.dead:
		return
	_burn_seen = true
	var rt = _rt()
	if rt != null:
		rt.fire("on_ignite", from_player_index, _parent.global_position, _parent, {"hp_pct": hp_pct(), "stats": stat_names(burning_data.scaling_stats)})


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


# 同原版受伤加成（冰块）：同一来源不叠层，取较大数值并刷新持续时间；不同来源相加
func add_vuln(pct: int, seconds: float, source) -> void:
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
