extends Reference

# 触发条款估值：value = 单位价值 × 每波有效触发次数（或叠层 / 在场率）× 持续倍率。
# 生成器和测试共用同一套公式，保证"生成时预算"与"审计时估值"不会漂移。

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")


# 每波"原始"事件数（已计入每 N 次与几率，未计入每波上限）
static func raw_rate(trigger: String, param: int, chance: int) -> float:
	var t = Catalog.TRIGGERS[trigger]
	var e: float = Catalog.events_per_wave(trigger, param)
	if t.gate == "every":
		e /= max(1, param)
	return e * clamp(chance, 1, 100) / 100.0


# 每波有效触发次数（计入上限）
static func fires_per_wave(trigger: String, param: int, chance: int, cap: int) -> float:
	var f = raw_rate(trigger, param, chance)
	if cap > 0:
		f = min(f, float(cap))
	return f


# 本波临时属性的平均叠层（线性累积；有上限时在达到上限后保持）
static func avg_stack(trigger: String, param: int, chance: int, cap: int, reset: bool = false) -> float:
	var t = Catalog.TRIGGERS[trigger]
	if reset and t.kind == "event" and t.timing > 0.0 and t.timing < 1.0:
		# 受击清空：受击间隔近似指数分布（实际约每波 7 次），平均叠层 = 触发频率 × 平均受击间隔
		var normal = avg_stack(trigger, param, chance, cap, false)
		var rate = raw_rate(trigger, param, chance) / Catalog.WAVE_SECONDS
		return min(normal, rate * Catalog.WAVE_SECONDS / Catalog.REAL_HITS_PER_WAVE)
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


# 条款价值（带符号，负面未折算）。敌人属性提高为负价值
static func clause_value(c: Dictionary, perm_mult: float) -> float:
	return main_value(c, perm_mult)


# 下一波：一波的价值
static func next_wave_value(stat: String, value: int, perm_mult: float) -> float:
	return Catalog.stat_w(stat) * value / Catalog.remaining_waves(perm_mult)


static func main_value(c: Dictionary, perm_mult: float) -> float:
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
			return _stat_sign(stat) * Catalog.stat_w(stat) * v * avg_stack(trigger, param, chance, cap, bool(c.get("reset", false)))
		"perm_stat":
			return _stat_sign(stat) * Catalog.stat_w(stat) * v * fires_per_wave(trigger, param, chance, cap) * perm_mult * _capped_perm(cap)
		"timed_stat":
			var f = fires_per_wave(trigger, param, chance, cap)
			return _stat_sign(stat) * Catalog.stat_w(stat) * v * f * v2 / Catalog.WAVE_SECONDS
		"heal":
			return Catalog.HEAL_W * v * fires_per_wave(trigger, param, chance, cap)
		"gold":
			return Catalog.GOLD_W * v * fires_per_wave(trigger, param, chance, cap)
		"xp":
			return Catalog.XP_W * v * fires_per_wave(trigger, param, chance, cap)
		"damage":
			return Catalog.DMG_W * damage_per_proc(stat, int(v)) * fires_per_wave(trigger, param, chance, cap)
		"grant":
			# 被获得效果的价值（作为整局持有的道具行）× 数量 × 叠层 / 在场率 或 永久累积
			var unit = float(c.get("grant_unit", 0.0)) * v
			if c.get("grant_mode", "temp") == "perm":
				return unit * fires_per_wave(trigger, param, chance, cap) * perm_mult * _capped_perm(cap)
			return unit * avg_stack(trigger, param, chance, cap, bool(c.get("reset", false)))
		"explode":
			return Catalog.DMG_W * Catalog.EXPLOSION_TARGETS * damage_per_proc(stat, int(v)) * fires_per_wave(trigger, param, chance, cap)
		"hp_dmg":
			return Catalog.HP_DMG_W * v * fires_per_wave(trigger, param, chance, cap)
		"rand_stats":
			return Catalog.RAND_STAT_W * v * fires_per_wave(trigger, param, chance, cap) * perm_mult * _capped_perm(cap)
		"vuln":
			# 使该敌人受到的伤害 +X%，持续 N 秒 ≈ 对"被覆盖的那部分敌人"+X% 伤害；覆盖率 = 触发次数 × 有效持续 / (波长 × 同时受伤敌人数)
			var cover = clamp(fires_per_wave(trigger, param, chance, cap) * min(v2, Catalog.VULN_MAX_USEFUL_SECONDS) \
				/ (Catalog.WAVE_SECONDS * Catalog.VULN_CONCURRENT_TARGETS), 0.0, 1.0)
			return Catalog.stat_w("stat_percent_damage") * v * cover
	return 0.0


# 带每波上限的永久效果：每次触发的期望价值折算（catalog.PERM_CAPPED_FIRE_VALUE）
static func _capped_perm(cap: int) -> float:
	return Catalog.PERM_CAPPED_FIRE_VALUE if cap > 0 else 1.0


# 普通属性行价值（负面行按补偿比例折算为负价值）
static func stat_line_value(stat: String, value: int) -> float:
	return Catalog.stat_w(stat) * value


# 计数型："每有 nb 个 counter 获得 value 个 stat"
static func scaling_value(stat: String, value: int, counter: String, nb: int) -> float:
	return Catalog.stat_w(stat) * value * Catalog.counter_ref(counter) / max(1, nb)


# 属性修改 ±pct%
static func gain_mod_value(stat: String, pct: int) -> float:
	return Catalog.stat_w(stat) * Catalog.counter_ref(stat) * pct / 100.0


# 敌人属性（生命 / 伤害 / 速度）提高对玩家不利
static func _stat_sign(stat: String) -> float:
	return -1.0 if Catalog.ENEMY_STATS.has(stat) else 1.0
