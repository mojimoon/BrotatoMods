extends "res://effects/items/burn_chance_effect.gd"

# 原版"燃烧几率"效果合并进全局燃烧时只加几率 / 伤害 / 持续时间 / 扩散，不带属性加成（全局燃烧固定按元素伤害）。
# 本模组生成的此类效果记下各自的属性加成，全局燃烧按各属性的最大系数加成；仍有原版来源时保留元素伤害 100%。
# 结算燃烧前（WeaponService.init_burning_data）再重算一次，原版来源后获得也不会冲掉。
# 读档后没有记录，不再改写（读档恢复的全局燃烧已带存档时的加成）


func apply(player_index: int) -> void:
	.apply(player_index)
	var g = RunData.get_player_effects(player_index)[Keys.burn_chance_hash]
	var srcs = g.get_meta("be_srcs") if g.has_meta("be_srcs") else []
	srcs.push_back(burning_data)
	g.set_meta("be_srcs", srcs)
	_rescale(g, srcs)


func unapply(player_index: int) -> void:
	.unapply(player_index)
	var g = RunData.get_player_effects(player_index)[Keys.burn_chance_hash]
	if not g.has_meta("be_srcs"):
		return
	var srcs = g.get_meta("be_srcs")
	srcs.erase(burning_data)
	_rescale(g, srcs)


static func _rescale(g, srcs: Array) -> void:
	var by = {}
	var own = 0.0
	for bd in srcs:
		own += bd.chance
		for row in bd.scaling_stats:
			by[row[0]] = max(by.get(row[0], 0.0), row[1])
	if srcs.empty() or g.chance > own + 0.0001:
		by[Keys.stat_elemental_damage_hash] = max(by.get(Keys.stat_elemental_damage_hash, 0.0), 1.0)
	var sc = []
	for k in by:
		sc.push_back([k, by[k]])
	g.scaling_stats = sc
