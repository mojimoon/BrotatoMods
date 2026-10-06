extends Node

# 不受伤加成（"每 X 秒未受伤 +Y 伤害，受伤后重置"）：原版只在磁轨炮的场景脚本里实现。
# 其他武器带这个效果时，由挂在武器下的这个节点按同样的规则改基础伤害（武器的 stats 是每个实例单独复制的）。
# 不更新武器的统计值显示

var weapon = null
var effect = null
var base_damage := 0
var seconds := 0


func setup(w, e) -> void:
	weapon = w
	effect = e
	base_damage = int(w.stats.damage)
	var _c = w._parent.connect("took_damage", self, "_on_took_damage")
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	add_child(timer)
	var _t = timer.connect("timeout", self, "_on_second")


func _on_second() -> void:
	seconds += 1
	var interval = int(max(1, int(effect.interval)))
	if seconds % interval == 0:
		_apply(int(effect.value) * (seconds / interval))


func _on_took_damage(_unit, _value, _kb, _is_crit, is_dodge, is_protected, _armor, _args, _hit_type, _one_shot) -> void:
	if is_protected or is_dodge:
		return
	seconds = 0
	_apply(0)


func _apply(bonus: int) -> void:
	if not is_instance_valid(weapon):
		return
	weapon.stats.damage = base_damage + bonus
	weapon.init_stats(false)
