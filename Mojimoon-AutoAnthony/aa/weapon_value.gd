extends Reference

# 武器价值模型：把武器折算成"参考状态下的等效 DPS"（power），再按原版价格标定成材料价值。
#
# 冷却按 codex 攻速计算器（AttackSpeedCalculator / codexStore.js）移植：攻速 0、6 把武器、范围 0，
#   取实际攻击间隔的平均帧数（含后坐 / 近战出招收招的补间帧、6 武器的随机冷却抖动、换弹折算到每发）。
# 每次攻击的伤害 = 基础伤害 + Σ 加成系数 × 参考属性（catalog.STATS.ref，例如 15 近战伤害、40 最大生命）；
#   负系数（狼牙棒的 -攻速加成）不计入。
# power = 每次伤害 × 暴击期望 × 射程系数 × 多发 × (1 + 贯穿 / 弹跳的额外命中) / 冷却 + 吸血折算
#   + 可建模的效果（爆炸、点燃、命中时射出投射物）。
# 其余效果按原版残差标定：同稀有度同类型的纯属性武器给出 价格 / power 的比例 k，
#   带效果武器的 (价格 − k × power) 按效果 key 取中位数，得到每单位效果数值的材料价值。
# 玩家属性类效果（+收获、-攻速、+护甲……）直接用 catalog 的属性权重。

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")

const FPS = 60.0
const MIN_CD_FRAMES = 2
const MELEE_ATTACK_DURATION = 0.2
const WEAPON_COUNT = 6
# 贯穿 / 弹跳 / 爆炸命中其他敌人的概率（敌人密度），额外命中最多计 3 次
const CROWD = 0.5
const MAX_EXTRA_HITS = 3
# 多发投射物（散射）每多一发的有效命中
const PROJ_EXTRA = 0.5
# 爆炸平均命中数（含主目标）
const EXPLOSION_TARGETS = 2.0
# 点燃：同一目标重复点燃只刷新持续时间。攻击间隔短于持续时间时，燃烧约等于每秒一跳的持续伤害；
# 否则每次攻击烧满整段。再乘以效率（目标常在烧完前死亡）
const BURN_EFF = 0.7
# 同时燃烧的目标数上限 = 每次攻击命中数 × 此值
const BURN_TARGETS = 1.5
# 溢出伤害：单次伤害超过参考敌人生命时，超出部分按幂次折算（慢速重击常打出溢出伤害）
const OVERKILL_HP = 40.0
const OVERKILL_EXP = 0.6
# 效果的残差单位价值不为正时（模型高估了来源武器），按"至少值来源武器价格的这一比例"兜底
const EFFECT_VALUE_FLOOR = 0.15
# 命中时射出的投射物 / 闪电：命中率
const SUB_PROJ_EFF = 0.7
# 吸血：每秒 1 点回复折算的 DPS
const HEAL_DPS = 8.0
# catalog.STATS 里没有参考值的加成属性
const REF_EXTRA = {"stat_curse": 20.0, "stat_levels": 10.0}

# 可建模（计入 power）的效果脚本 id
const MODELED_EFFECTS = ["weapon_exploding", "weapon_burning", "weapon_projectiles_on_hit"]


static func _tween(d: float) -> int:
	if abs(d - 0.05) < 0.0001:
		return 4
	return int(floor(d * 60.0)) + 2


static func _avg_attack(min_cd: float, max_cd: float) -> float:
	if max_cd <= min_cd:
		return max_cd
	var c_min = ceil(min_cd)
	var f_max = floor(max_cd)
	var tri_a = f_max * (f_max + 1.0) / 2.0
	var tri_b = c_min * (c_min + 1.0) / 2.0
	return ((c_min - min_cd) * c_min + tri_a - tri_b + (max_cd - f_max) * ceil(max_cd)) / (max_cd - min_cd)


static func is_melee(st) -> bool:
	return "attack_type" in st


# 每次攻击的平均间隔（秒），换弹折算到每发
static func cooldown_seconds(st) -> float:
	var wcf = max(MIN_CD_FRAMES, int(st.cooldown))
	var recoil = float(st.recoil_duration)
	var add_cd = 0.0
	var alt_bonus = 0.0
	if is_melee(st):
		var eff_range = max(25.0, float(st.max_range))
		var attack_dur = MELEE_ATTACK_DURATION + max(0.0, eff_range / 70.0) * 0.15
		add_cd = _tween(recoil) + _tween(MELEE_ATTACK_DURATION) - 1
		var half = _tween(attack_dur / 2.0)
		var quarter = _tween(attack_dur / 4.0)
		add_cd += half if int(st.attack_type) == 0 else 2 * quarter
		if st.alternate_attack_type and half > 2 * quarter:
			alt_bonus = 1.0
	else:
		add_cd = 2 * _tween(recoil) - 1
	var max_rand = min(WEAPON_COUNT * wcf / 5.0, WEAPON_COUNT * 5.0)
	var avg = add_cd + _avg_attack(max(1.0, wcf - max_rand), wcf + max_rand) - alt_bonus
	var cd = avg / FPS
	var shots = int(st.additional_cooldown_every_x_shots)
	var mult = float(st.additional_cooldown_multiplier)
	if shots > 0 and mult > 0:
		var actual = (add_cd + wcf * mult) / FPS
		cd += (actual - cd) / shots
	return cd


static func stat_name(s) -> String:
	if s is String:
		return s
	return Keys.hash_to_string.get(s, "")


static func stat_ref(stat: String) -> float:
	if Catalog.STATS.has(stat) and float(Catalog.STATS[stat].get("ref", 0.0)) > 0.0:
		return float(Catalog.STATS[stat].ref)
	return float(REF_EXTRA.get(stat, 10.0))


# 每次命中的伤害（参考属性下）
static func hit_damage(damage: float, scaling_stats: Array) -> float:
	var d = damage
	for sc in scaling_stats:
		d += max(0.0, float(sc[1])) * stat_ref(stat_name(sc[0]))
	return d


static func overkill(d: float) -> float:
	if d <= OVERKILL_HP:
		return d
	return OVERKILL_HP * pow(d / OVERKILL_HP, OVERKILL_EXP)


static func crit_factor(st) -> float:
	return 1.0 + float(st.crit_chance) * max(0.0, float(st.crit_damage) - 1.0)


static func _extra_hits(n: int, reduction: float) -> float:
	var s = 0.0
	var f = 1.0
	for _k in min(n, MAX_EXTRA_HITS):
		f *= (1.0 - reduction)
		s += f
	return s * CROWD


# 每次攻击的命中数（多发、贯穿、弹跳）
static func hits_per_attack(st) -> float:
	if is_melee(st):
		return 1.0
	var proj = 1.0 + (max(1, int(st.nb_projectiles)) - 1) * PROJ_EXTRA
	var extra = _extra_hits(int(st.piercing), float(st.piercing_dmg_reduction))
	if st.can_bounce:
		extra += _extra_hits(int(st.bounce), float(st.bounce_dmg_reduction))
	return proj * (1.0 + extra)


static func range_factor(st) -> float:
	var ref = 150.0 if is_melee(st) else 350.0
	return pow(max(50.0, float(st.max_range)) / ref, 0.25)


static func effect_id(e) -> String:
	return e.get_id() if e.has_method("get_id") else ""


# 等效 DPS（参考状态）；effects 中可建模的效果计入
static func power(st, effects: Array) -> float:
	var cd = max(0.05, cooldown_seconds(st))
	var hit = hit_damage(float(st.damage), st.scaling_stats)
	var per_hit = overkill(hit * crit_factor(st)) * range_factor(st)
	var hits = hits_per_attack(st)
	var mult = 1.0
	var extra = 0.0
	for e in effects:
		match effect_id(e):
			"weapon_exploding":
				var area = EXPLOSION_TARGETS * pow(max(0.25, float(e.scale)), 0.5)
				if is_melee(st):
					mult += float(e.chance) * area
				else:
					mult += float(e.chance) * (area - 1.0)
			"weapon_burning":
				var bd = e.burning_data
				if bd != null:
					var targets = min(hits * float(bd.duration) / cd, BURN_TARGETS * hits)
					extra += float(bd.chance) * hit_damage(float(bd.damage), bd.scaling_stats) * targets * BURN_EFF
			"weapon_projectiles_on_hit":
				var ws = e.weapon_stats
				if ws != null:
					var sub = hit_damage(float(ws.damage), ws.scaling_stats) * crit_factor(ws)
					if ws.can_bounce:
						sub *= 1.0 + _extra_hits(int(ws.bounce), float(ws.bounce_dmg_reduction))
					extra += float(e.value) * sub * SUB_PROJ_EFF * hits / cd
	var p = per_hit * hits * mult / cd + extra
	p += HEAL_DPS * float(st.lifesteal) * hits / cd
	return p


# ------------------------------------------------------------
# 残差效果：key 与数值大小（单位价值 × 大小 = 材料价值）
# ------------------------------------------------------------
static func effect_key(e) -> String:
	var id = effect_id(e)
	if id == "turret" or id == "structure":
		return "structure:" + (str(e.tracking_key) if "tracking_key" in e and str(e.tracking_key) != "" else id)
	if e.custom_key != "":
		return e.custom_key
	if e.key != "":
		return e.key
	return id


static func is_plain_player_stat(e) -> bool:
	return effect_id(e) == "effect" and e.custom_key == "" and Catalog.STATS.has(e.key)


static func magnitude(e) -> float:
	var k = effect_key(e)
	var v = float(e.value)
	match k:
		"effect_gain_stat_every_killed_enemies":
			return Catalog.stat_w(e.stat) / max(1.0, v)
		"modify_every_x_projectile":
			return 1.0 / max(1.0, v)
		"gain_stat_for_every_step_after_equip":
			return 1.0 / max(1.0, float(e.value2))
		"break_on_hit":
			return float(e.value2)
		"enemy_percent_damage_taken":
			return v * float(e.max_stacks)
		"temp_stats_per_interval":
			return v * Catalog.stat_w(e.key) / max(1.0, float(e.interval))
		"temp_stats_while_not_moving", "temp_stats_on_hit":
			return v * Catalog.stat_w(e.key)
		"additional_weapon_effects":
			return v * Catalog.stat_w(e.key) * WEAPON_COUNT
		"lose_hp_per_second":
			return -v
		"stat_lifesteal":
			if effect_id(e) == "gain_stat_for_every_stat":
				return 1.0 / max(1.0, float(e.nb_stat_scaled))
	if k.begins_with("structure:"):
		if "spawn_cooldown" in e and int(e.spawn_cooldown) > 0:
			return 1.0 / float(e.spawn_cooldown)
		return 1.0
	if v == 0:
		return 1.0
	return v


# 效果是否计入 power（其余按残差 / 属性权重估值）
static func is_modeled(e) -> bool:
	return effect_id(e) in MODELED_EFFECTS


# ------------------------------------------------------------
# 标定
# ------------------------------------------------------------
var k_by: Dictionary = {}		# "M0" -> 价格 / power
var unit_by_key: Dictionary = {}	# 效果 key -> 每单位大小的材料价值
var fit_rows: Array = []		# [weapon, price, value]


static func _tk(st, tier: int) -> String:
	return ("M" if is_melee(st) else "R") + str(tier)


static func _median(a: Array) -> float:
	if a.empty():
		return 0.0
	var b = a.duplicate()
	b.sort()
	return b[b.size() / 2]


func calibrate(weapons: Array) -> void:
	var ratios = {}
	for w in weapons:
		if w.stats == null or int(w.value) <= 0:
			continue
		var pure = true
		for e in w.effects:
			if not is_modeled(e) and not is_plain_player_stat(e):
				pure = false
		if not pure:
			continue
		var p = power(w.stats, w.effects)
		var stat_v = _player_stat_value(w.effects)
		var key = _tk(w.stats, w.tier)
		if not ratios.has(key):
			ratios[key] = []
		ratios[key].push_back(max(1.0, float(w.value) - stat_v) / max(0.1, p))
	for key in ratios:
		k_by[key] = _median(ratios[key])
	# 缺数据的档：用同类型相邻档按 2 倍价格外推
	for ty in ["M", "R"]:
		for t in 4:
			var key = ty + str(t)
			if not k_by.has(key):
				for d in [1, -1, 2, -2, 3, -3]:
					if k_by.has(ty + str(t + d)):
						k_by[key] = k_by[ty + str(t + d)]
						break
	var resid = {}
	var prices = {}
	var mags = {}
	for w in weapons:
		if w.stats == null or int(w.value) <= 0:
			continue
		var others = []
		for e in w.effects:
			if not is_modeled(e) and not is_plain_player_stat(e):
				others.push_back(e)
		if others.empty():
			continue
		var r = float(w.value) - k(w.stats, w.tier) * power(w.stats, w.effects) - _player_stat_value(w.effects)
		for e in others:
			var mg = magnitude(e)
			if abs(mg) < 0.0001:
				continue
			var key = effect_key(e)
			if not resid.has(key):
				resid[key] = []
				prices[key] = []
				mags[key] = []
			resid[key].push_back(r / others.size() / mg)
			prices[key].push_back(float(w.value))
			mags[key].push_back(abs(mg))
	# 单位价值不为正：模型高估了来源武器（或效果本是代价但大小记为正），按来源价格的一定比例兜底
	for key in resid:
		var u = _median(resid[key])
		if u <= 0.0:
			u = EFFECT_VALUE_FLOOR * _median(prices[key]) / max(0.0001, _median(mags[key]))
		unit_by_key[key] = u
	fit_rows = []
	for w in weapons:
		if w.stats != null and int(w.value) > 0:
			fit_rows.push_back([w, float(w.value), value(w.stats, w.effects, w.tier)])


func k(st, tier: int) -> float:
	return float(k_by.get(_tk(st, tier), 1.0))


static func _player_stat_value(effects: Array) -> float:
	var v = 0.0
	for e in effects:
		if is_plain_player_stat(e):
			v += Catalog.stat_w(e.key) * float(e.value)
	return v


# 效果的材料价值（不含计入 power 的部分）
func effect_value(e) -> float:
	if is_modeled(e):
		return 0.0
	if is_plain_player_stat(e):
		return Catalog.stat_w(e.key) * float(e.value)
	return float(unit_by_key.get(effect_key(e), 0.0)) * magnitude(e)


# 武器的材料价值
func value(st, effects: Array, tier: int) -> float:
	var v = k(st, tier) * power(st, effects)
	for e in effects:
		v += effect_value(e)
	return v
