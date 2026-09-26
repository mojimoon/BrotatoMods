extends Reference

# 触发条款估值：value = 单位价值 × 每波有效触发次数（或叠层 / 在场率）× 持续倍率。
# 生成器和测试共用同一套公式，保证"生成时预算"与"审计时估值"不会漂移。

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")


# 每波"原始"事件数（已计入每 N 次与几率，未计入每波上限）
static func raw_rate(trigger: String, param: int, chance: int) -> float:
	var t = Catalog.TRIGGERS[trigger]
	var e: float = Catalog.events_per_wave(trigger, param)
	if t.gate == "every" and trigger != "interval":
		e /= max(1, param)
	return e * clamp(chance, 1, 100) / 100.0


# 每波有效触发次数（计入上限）
static func fires_per_wave(trigger: String, param: int, chance: int, cap: int) -> float:
	var f = raw_rate(trigger, param, chance)
	if cap > 0:
		f = min(f, float(cap))
	return f


# 本波临时属性的平均叠层（线性累积；有上限时在达到上限后保持）
static func avg_stack(trigger: String, param: int, chance: int, cap: int) -> float:
	var t = Catalog.TRIGGERS[trigger]
	if t.kind == "state":
		return t.e
	var e = raw_rate(trigger, param, chance)
	if t.timing >= 1.0:
		return fires_per_wave(trigger, param, chance, cap)
	if t.timing <= 0.0:
		return 0.0
	if cap > 0 and cap < e:
		return cap - cap * cap / (2.0 * e)
	return e * 0.5


static func damage_per_proc(stat: String, pct: int) -> float:
	var ref = 10.0
	if Catalog.STATS.has(stat) and Catalog.STATS[stat].ref > 0:
		ref = Catalog.STATS[stat].ref
	return max(1.0, pct / 100.0 * ref)


# 条款价值（带符号）。perm_mult：永久累积倍率（由道具稀有度或角色决定）
static func clause_value(c: Dictionary, perm_mult: float) -> float:
	var trigger: String = c.trigger
	var payload: String = c.payload
	var param: int = int(c.get("param", 1))
	var chance: int = int(c.get("chance", 100))
	var cap: int = int(c.get("cap", 0))
	var stat: String = c.get("stat", "")
	var v: float = float(c.value)
	var v2: float = float(c.get("value2", 0))

	match payload:
		"temp_stat":
			return Catalog.stat_w(stat) * v * avg_stack(trigger, param, chance, cap)
		"perm_stat":
			return Catalog.stat_w(stat) * v * fires_per_wave(trigger, param, chance, cap) * perm_mult
		"timed_stat":
			var f = fires_per_wave(trigger, param, chance, cap)
			return Catalog.stat_w(stat) * v * f * v2 / Catalog.WAVE_SECONDS
		"heal":
			return Catalog.HEAL_W * v * fires_per_wave(trigger, param, chance, cap)
		"gold":
			return Catalog.GOLD_W * v * fires_per_wave(trigger, param, chance, cap)
		"xp":
			return Catalog.XP_W * v * fires_per_wave(trigger, param, chance, cap)
		"damage":
			return Catalog.DMG_W * damage_per_proc(stat, int(v)) * fires_per_wave(trigger, param, chance, cap)
		"explode":
			return Catalog.DMG_W * Catalog.EXPLOSION_TARGETS * damage_per_proc(stat, int(v)) * fires_per_wave(trigger, param, chance, cap)
	return 0.0


# 普通属性行价值（负面行按补偿比例折算为负价值）
static func stat_line_value(stat: String, value: int) -> float:
	return Catalog.stat_w(stat) * value
