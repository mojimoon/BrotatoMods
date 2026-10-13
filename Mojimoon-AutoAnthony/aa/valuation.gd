extends Reference

# 触发条款估值：value = 单位价值 × 每波有效触发次数（或叠层 / 在场率）× 持续倍率。
# 生成器和测试共用同一套公式，保证"生成时预算"与"审计时估值"不会漂移。

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")
const WeaponValue = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/weapon_value.gd")


# 扳机事件数 × 机制条件满足率（未计入数值条件）
static func base_rate(c: Dictionary) -> float:
	return Catalog.events_per_wave(c.trigger, int(c.get("param", 1))) * Catalog.cond_factor(str(c.get("cond", "")), int(c.get("cond_arg", 0)))


# 每波"原始"触发次数（已计入机制条件、每 N 次、几率与冷却，未计入每波上限）
static func raw_rate(c: Dictionary) -> float:
	var e = base_rate(c)
	if Catalog.TRIGGERS[c.trigger].gate == "every":
		e /= max(1, int(c.get("param", 1)))
	# 冷却：事件近似均匀到达，每次触发后等待冷却，有效频率 = r / (1 + r × 冷却)
	var cd = float(c.get("cooldown", 0))
	if cd > 0:
		e /= 1.0 + e * cd / Catalog.WAVE_SECONDS
	return e * clamp(int(c.get("chance", 100)), 1, 100) / 100.0


static func _cap(c: Dictionary) -> int:
	return Catalog.effective_cap(c.trigger, int(c.get("param", 1)), int(c.get("cap", 0)))


# 每波有效触发次数（计入上限）
static func fires_per_wave(c: Dictionary) -> float:
	var cap = _cap(c)
	var f = raw_rate(c)
	if cap > 0:
		f = min(f, float(cap))
	return f


# 本波临时属性的平均叠层（线性累积；有上限时在达到上限后保持）
static func avg_stack(c: Dictionary) -> float:
	var cap = _cap(c)
	var t = Catalog.TRIGGERS[c.trigger]
	if bool(c.get("reset", false)) and t.kind == "event" and t.timing > 0.0 and t.timing < 1.0:
		# 受击清空：受击间隔近似指数分布（实际约每波 7 次），平均叠层 = 触发频率 × 平均受击间隔
		var c2 = c.duplicate()
		c2.reset = false
		return min(avg_stack(c2), raw_rate(c) / Catalog.REAL_HITS_PER_WAVE)
	if t.kind == "state":
		return t.e
	var e = raw_rate(c)
	if t.timing >= 1.0:
		return fires_per_wave(c)
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
	var payload: String = c.payload
	var cap: int = int(c.get("cap", 0))
	var stat: String = c.get("stat", "")
	var v: float = float(c.value)
	var v2: float = float(c.get("value2", 0))

	match payload:
		"temp_stat":
			return _stat_sign(stat) * Catalog.stat_w(stat) * v * avg_stack(c)
		"perm_stat":
			return _stat_sign(stat) * Catalog.stat_w(stat) * v * fires_per_wave(c) * perm_mult * _capped_perm(cap)
		"timed_stat":
			var f = fires_per_wave(c)
			return _stat_sign(stat) * Catalog.stat_w(stat) * v * f * v2 / Catalog.WAVE_SECONDS
		"heal":
			return Catalog.HEAL_W * v * fires_per_wave(c)
		"gold":
			return Catalog.GOLD_W * v * fires_per_wave(c)
		"xp":
			return Catalog.XP_W * v * fires_per_wave(c)
		"damage":
			return Catalog.DMG_W * damage_per_proc(stat, int(v)) * fires_per_wave(c)
		"grant":
			# 被获得效果的价值（作为整局持有的道具行）× 数量 × 叠层 / 在场率 或 永久累积
			var unit = float(c.get("grant_unit", 0.0)) * v
			if c.get("grant_mode", "temp") == "perm":
				return unit * fires_per_wave(c) * perm_mult * _capped_perm(cap)
			return unit * avg_stack(c)
		"explode":
			return Catalog.DMG_W * Catalog.EXPLOSION_TARGETS * damage_per_proc(stat, int(v)) * fires_per_wave(c)
		"ignite":
			# 每跳 X + 100% 元素伤害（元素参考值），共 3 跳
			var tick = v + Catalog.STATS["stat_elemental_damage"].ref
			return Catalog.DMG_W * Catalog.IGNITE_TICKS * tick * fires_per_wave(c)
		"slow":
			return Catalog.SLOW_W * v * fires_per_wave(c)
		"fruit":
			return Catalog.FRUIT_W * v * fires_per_wave(c)
		"hp_dmg":
			return Catalog.HP_DMG_W * v * fires_per_wave(c)
		"rand_stats":
			return Catalog.RAND_STAT_W * v * fires_per_wave(c) * perm_mult * _capped_perm(cap)
		"vuln":
			# 使该敌人受到的伤害 +X%，持续 N 秒 ≈ 对"被覆盖的那部分敌人"+X% 伤害；覆盖率 = 触发次数 × 有效持续 / (波长 × 同时受伤敌人数)
			var cover = clamp(fires_per_wave(c) * min(v2, Catalog.VULN_MAX_USEFUL_SECONDS) \
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
static func scaling_value(stat: String, value: int, counter: String, nb: int, growth_tier: int = -1) -> float:
	var ref = growth_counter_ref(counter, growth_tier) if growth_tier >= 0 else Catalog.counter_ref(counter)
	return Catalog.stat_w(stat) * value * ref / max(1, nb)


# 成长型道具的计数期望 = 买家持有的 A：专精玩家在 A 上投入的"价值"大致相同（而不是点数相同），
# 所以持有点数 = 白给的基础持有量 + 投入价值 V × 持有期阶段 / A 的单价。转化率因此正比于 A 的单价（近战约为远程的一半）。
#   持有期阶段 = (购买时属性阶段 + 1) / 2（越早买、持有越久的 A 越少）
#   次要属性与非属性计数（材料、敌人、道具……）沿用 counter_ref × 倍率；V 与倍率由原版转化道具拟合（suite_core test_164）
static func growth_counter_ref(counter: String, tier: int) -> float:
	# 只对构筑属性（武器参考表里的属性）按单价换算；击退、拾取范围、经验等是顺带获得的，沿用 counter_ref
	var w = Catalog.stat_w(counter) if Catalog.STATS.has(counter) and WeaponValue.REF_STATS.has(counter) else 0.0
	if w <= 0:
		return Catalog.counter_ref(counter) * float(Catalog.GROWTH_REF["mult"])
	var f = float(WeaponValue.TIER_STAT_FRAC[clamp(tier, 0, 3)])
	return float(Catalog.GROWTH_BASELINE.get(counter, 0.0)) + float(Catalog.GROWTH_REF["v"]) * (f + 1.0) / 2.0 / w


# 计数型效果的价值（成长型道具的计数效果带 aa_growth_tier 标记）
static func scaling_effect_value(e) -> float:
	var gt = int(e.get_meta("aa_growth_tier")) if e.has_meta("aa_growth_tier") else -1
	return scaling_value(e.key, e.value, e.stat_scaled, e.nb_stat_scaled, gt)


# 属性修改 ±pct%
static func gain_mod_value(stat: String, pct: int) -> float:
	return Catalog.stat_w(stat) * Catalog.counter_ref(stat) * pct / 100.0


# 敌人属性（生命 / 伤害 / 速度）提高对玩家不利
static func _stat_sign(stat: String) -> float:
	return -1.0 if Catalog.ENEMY_STATS.has(stat) else 1.0
