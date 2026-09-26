extends Reference

# 东尼算法生成器：把原版道具 / 角色 / 武器拆成组件，再按价值预算重新组装。
#
# 组件分三类：
#   属性行   纯属性加减（可缩放数值），占原版效果行的约 70%
#   机制行   固定机制（炮台、宠物、受击爆炸、每波额外敌人……），价值 = 来源道具价格 − 截距 − 其属性行价值
#   触发条款 通用 (扳机 × 载荷 × 门控)，由 trigger_effect.gd 表达；原版的触发型效果被拆解为先验
#
# 出现频率不手写表格：属性、负面、行数、机制、触发组合的分布都在运行时从原版数据统计（经验先验），
# 再与目录中的基础权重相加，保证原版没有出现过的组合也有非零概率。
#
# 输出 plan：
#   items:      { my_id: {effects, name, tags} }
#   characters: { my_id: {effects, name} }
#   weapons:    { my_id: {effects} }

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")
const Valuation = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/valuation.gd")
const TriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")

enum Mode { BALANCED, AGGRESSIVE, CHAOS }

const MODE_BUDGET = [1.0, 1.25, 1.0]
const TRIGGER_RATE = [0.5, 1.0, 1.8]
# 各稀有度获得触发条款 / 搬运机制的基础概率
const P_TRIGGER = [0.30, 0.40, 0.50, 0.60]
const P_MECHANIC = [0.10, 0.14, 0.16, 0.18]

var cfg: Dictionary
var seed_value: int
var rng: RandomNumberGenerator

# ---- 先验（从原版数据统计） ----
var stat_pos_w: Dictionary = {}
var stat_neg_w: Dictionary = {}
var stat_max_pos: Dictionary = {}	# 原版单行最大正值（限制单行数值，超出部分溢出到别的属性）
var stat_max_neg: Dictionary = {}
var lines_by_tier: Array = [[], [], [], []]		# 每个原版道具的正面属性行数
var neg_prob_by_tier: Array = [0.0, 0.0, 0.0, 0.0]
var trigger_prior: Dictionary = {}
var payload_prior: Dictionary = {}
var trigger_stat_prior: Dictionary = {}
var mechanics_by_tier: Array = [[], [], [], []]	# {effect, value, down, source}
var effect_script: Script
# 条款约束（角色重组时使用）：禁用的扳机 / 载荷（反协同，如"无法回血"的角色不出现回血相关条款）
var banned_triggers: Array = []
var banned_payloads: Array = []


func _init(p_cfg: Dictionary, p_seed: int) -> void:
	cfg = p_cfg
	seed_value = p_seed
	rng = RandomNumberGenerator.new()
	effect_script = load("res://items/global/effect.gd")


# ============================================================
# 入口
# ============================================================
func generate(items: Array, characters: Array, weapons: Array) -> Dictionary:
	_collect_priors(items, characters, weapons)
	var plan = {"items": {}, "characters": {}, "weapons": {}, "seed": seed_value}
	if cfg.get("items", true):
		for item in items:
			if _is_reassemblable_item(item):
				var r = generate_item(item)
				if not r.empty():
					plan.items[item.my_id] = r
	if cfg.get("characters", false):
		for ch in characters:
			plan.characters[ch.my_id] = generate_character(ch)
	if cfg.get("weapons", false):
		plan.weapons = generate_weapons(weapons)
	return plan


func _seed_for(id: String) -> void:
	rng.seed = hash(str(seed_value) + "/" + id)


func _is_reassemblable_item(item) -> bool:
	if item is CharacterData or item is WeaponData:
		return false
	if item.my_id in Catalog.ANCHORED_ITEMS:
		return false
	if item.tier < 0 or item.tier > 3:
		return false
	if item.is_pet_item() or item.is_structure_item():
		# 宠物 / 建筑道具的外观、计数与其效果绑定：保留原样，但其机制行可以被其他道具借用
		return false
	return true


# ============================================================
# 分类
# ============================================================
func is_plain_stat(e) -> bool:
	return e.get_script() == effect_script and e.custom_key == "" and e.storage_method == 0 \
		and Catalog.STATS.has(e.key) and (e.text_key == "" or e.text_key.to_lower() == "effect_" + e.key)


func native_trigger_of(e):
	var k = e.custom_key if e.custom_key != "" else e.key
	if Catalog.NATIVE_TRIGGER_MAP.has(k):
		return Catalog.NATIVE_TRIGGER_MAP[k]
	var id = e.get_id() if e.has_method("get_id") else ""
	if id == "weapon_gain_stat_every_killed_enemies":
		return Catalog.NATIVE_TRIGGER_MAP["effect_gain_stat_every_killed_enemies"]
	return null


func is_mechanic(e) -> bool:
	if is_plain_stat(e) or native_trigger_of(e) != null:
		return false
	if e.get_script() == effect_script and e.key == "":
		return false	# 纯描述行（由道具 ID 实现）
	if e.key in Catalog.MECHANIC_BANNED_KEYS or e.custom_key in Catalog.MECHANIC_BANNED_KEYS:
		return false
	return true


func _collect_priors(items: Array, characters: Array, weapons: Array) -> void:
	for s in Catalog.STATS:
		stat_pos_w[s] = 0.5
		stat_neg_w[s] = 0.3
	for t in Catalog.TRIGGERS:
		trigger_prior[t] = 0.0
	for p in Catalog.PAYLOADS:
		payload_prior[p] = 0.0

	# 机制行必须能写入玩家 effects 字典（例如未启用 DLC 时没有诅咒等 DLC 属性）
	var effect_keys = PlayerRunData.init_effects()
	var sources = items + characters + weapons
	for src in sources:
		var pos_lines = 0
		var has_neg = false
		var stat_value = 0.0
		var mechs = []
		for e in src.effects:
			if is_plain_stat(e):
				if e.value > 0:
					stat_pos_w[e.key] += 1.0
					stat_max_pos[e.key] = max(stat_max_pos.get(e.key, 0), e.value)
					pos_lines += 1
					stat_value += Valuation.stat_line_value(e.key, e.value)
				elif e.value < 0:
					stat_neg_w[e.key] += 1.0
					stat_max_neg[e.key] = max(stat_max_neg.get(e.key, 0), -e.value)
					has_neg = true
					stat_value += Valuation.stat_line_value(e.key, e.value) * (1.0 - Catalog.DOWNSIDE_COMPENSATION)
				continue
			var nt = native_trigger_of(e)
			if nt != null:
				trigger_prior[nt[0]] += 1.0
				payload_prior[nt[1]] += 1.0
				var sk = e.key if Catalog.STATS.has(e.key) else ""
				if sk == "" and "stat" in e and Catalog.STATS.has(e.stat):
					sk = e.stat
				if sk != "":
					trigger_stat_prior[sk] = trigger_stat_prior.get(sk, 0.0) + 1.0
				continue
			if src is ItemData and not src is CharacterData and not src is WeaponData and is_mechanic(e) \
					and not src.my_id in Catalog.ANCHORED_ITEMS and src.tier >= 0 and src.tier <= 3 \
					and e.get_text(0, false) != "" and _mechanic_keys_exist(e, effect_keys):
				mechs.push_back(e)
		if src is ItemData and not src is CharacterData and not src is WeaponData and src.tier >= 0 and src.tier <= 3:
			if not src.my_id in Catalog.ANCHORED_ITEMS and src.can_be_looted:
				lines_by_tier[src.tier].push_back(pos_lines)
				if has_neg:
					neg_prob_by_tier[src.tier] += 1.0
			if not mechs.empty():
				var ups = 0
				for e in mechs:
					if not Catalog.is_downside_mechanic(e):
						ups += 1
				var budget = max(0.0, src.value - Catalog.TIER_INTERCEPT[src.tier] - stat_value)
				var each = budget / max(1, ups)
				for e in mechs:
					var down = Catalog.is_downside_mechanic(e)
					mechanics_by_tier[src.tier].push_back({
						"effect": e, "value": max(5.0, each) if not down else -max(5.0, src.value * 0.3),
						"down": down, "source": src.my_id,
					})
	for t in 4:
		var n = max(1, lines_by_tier[t].size())
		neg_prob_by_tier[t] = neg_prob_by_tier[t] / n
		if lines_by_tier[t].empty():
			lines_by_tier[t] = [1, 2]


func _mechanic_keys_exist(e, effect_keys: Dictionary) -> bool:
	if e.custom_key != "":
		return effect_keys.has(Keys.generate_hash(e.custom_key))
	if e.key != "" and e.get_script() == effect_script:
		return effect_keys.has(Keys.generate_hash(e.key))
	return true


# ============================================================
# 随机工具
# ============================================================
func _pick_weighted(weights: Dictionary, allowed = null):
	var total = 0.0
	for k in weights:
		if allowed != null and not k in allowed:
			continue
		total += max(0.0, weights[k])
	if total <= 0.0:
		return null
	var r = rng.randf() * total
	for k in weights:
		if allowed != null and not k in allowed:
			continue
		r -= max(0.0, weights[k])
		if r <= 0.0:
			return k
	for k in weights:
		if allowed == null or k in allowed:
			return k
	return null


func _pick_stat(neg: bool, exclude: Array = [], allowed = null) -> String:
	var weights = {}
	var src = stat_neg_w if neg else stat_pos_w
	for s in src:
		if s in exclude:
			continue
		if allowed != null and not s in allowed:
			continue
		weights[s] = src[s] + trigger_stat_prior.get(s, 0.0) * 0.5
	var s = _pick_weighted(weights)
	return s if s != null else "stat_max_hp"


func _budget_mult() -> float:
	var mode = int(cfg.get("mode", Mode.BALANCED))
	if mode == Mode.CHAOS:
		return rng.randf_range(0.6, 1.8)
	return MODE_BUDGET[mode]


func _trigger_rate() -> float:
	return TRIGGER_RATE[int(clamp(cfg.get("trigger_rate", 1), 0, 2))]


# ============================================================
# 道具
# ============================================================
func generate_item(item) -> Dictionary:
	_seed_for(item.my_id)
	if rng.randf() < float(cfg.get("native_ratio", 0)) / 100.0:
		return {}

	var tier: int = item.tier
	var perm_mult: float = Catalog.PERM_MULT[tier]
	var budget: float = max(3.0, item.value - Catalog.TIER_INTERCEPT[tier]) * _budget_mult()
	var budget_total = budget
	var effects = []
	var used_stats = []
	var main_line = {"value": 0.0, "adj": ""}

	# 1) 代价（负面属性 / 负面触发 / 负面机制）
	var downsides = []
	var p_neg = neg_prob_by_tier[tier]
	if int(cfg.get("mode", 0)) == Mode.CHAOS:
		p_neg = min(0.8, p_neg * 1.5)
	if rng.randf() < p_neg:
		var d = budget * rng.randf_range(0.2, 0.5)
		var r = rng.randf()
		var down_value = 0.0
		if r < 0.15:
			var c = gen_clause(-d, perm_mult, true)
			if not c.empty():
				downsides.push_back(TriggerEffect.make(c))
				down_value = Valuation.clause_value(c, perm_mult)
		elif r < 0.25:
			var m = _pick_mechanic(tier, true, d * 2.0)
			if m != null:
				downsides.push_back(_mechanic_copy(m))
				down_value = m.value
		if down_value == 0.0:
			var s = _pick_stat(true)
			var v = int(min(_round_to_unit(d / Catalog.stat_w(s), s), _line_cap(s, true)))
			downsides.push_back(_stat_effect(s, -v))
			used_stats.push_back(s)
			down_value = -v * Catalog.stat_w(s)
		budget += abs(down_value) * Catalog.DOWNSIDE_COMPENSATION

	# 2) 固定机制
	if rng.randf() < P_MECHANIC[tier] and budget > 8.0:
		var m = _pick_mechanic(tier, false, budget * 1.1)
		if m != null:
			effects.push_back(_mechanic_copy(m))
			budget -= m.value
			if m.value > main_line.value:
				main_line = {"value": m.value, "adj": "AA_ADJ_ODD"}

	# 3) 触发条款
	if rng.randf() < min(0.95, P_TRIGGER[tier] * _trigger_rate()) and budget > 4.0:
		var share = rng.randf_range(0.5, 0.95)
		var c = gen_clause(budget * share, perm_mult, false)
		if not c.empty():
			var cv = Valuation.clause_value(c, perm_mult)
			effects.push_front(TriggerEffect.make(c))
			budget -= cv
			if cv > main_line.value:
				main_line = {"value": cv, "adj": Catalog.ADJ_BY_TRIGGER[c.trigger]}
			if c.get("stat", "") != "":
				used_stats.push_back(c.stat)

	# 4) 属性行：行数取自原版同稀有度道具的分布；剩余预算较多时至少补一行
	var n = int(lines_by_tier[tier][rng.randi() % lines_by_tier[tier].size()])
	if effects.empty() or budget > max(6.0, budget_total * 0.2):
		n = max(n, 1)
	if budget < 2.0:
		n = 0 if not effects.empty() else 1
	elif n > 0:
		n = int(clamp(n, 1, max(1, floor(budget / 4.0))))
	var shares = []
	var total_share = 0.0
	for i in n:
		var w = rng.randf_range(0.5, 1.5)
		shares.push_back(w)
		total_share += w
	var stat_lines = []
	var carry = 0.0
	var i = 0
	while i < n or (carry > 2.0 and i < n + 2):
		var s = _pick_stat(false, used_stats)
		used_stats.push_back(s)
		var b = carry
		if i < n:
			b += max(budget, 2.0) * shares[i] / total_share
		var v = _round_to_unit(b / Catalog.stat_w(s), s)
		var cap = _line_cap(s, false)
		if v > cap:
			v = cap
		carry = max(0.0, b - v * Catalog.stat_w(s))
		stat_lines.push_back(_stat_effect(s, v))
		if v * Catalog.stat_w(s) > main_line.value:
			main_line = {"value": v * Catalog.stat_w(s), "adj": Catalog.ADJ_BY_STAT.get(s, "AA_ADJ_ODD")}
		i += 1

	# 原版的书写顺序：正面属性在前，触发 / 机制随后，负面在最后
	var ordered = stat_lines + effects + downsides

	return {
		"effects": ordered,
		"adj": main_line.adj if main_line.adj != "" else "AA_ADJ_ODD",
		"tags": _tags_for(ordered),
	}


# 单行数值上限：原版该属性单行最大值的 1.25 倍（至少 5 个单位）
func _line_cap(stat: String, neg: bool) -> int:
	var src = stat_max_neg if neg else stat_max_pos
	var unit = Catalog.stat_unit(stat)
	var raw = max(5 * unit, src.get(stat, 10 * unit) * 1.25)
	return int(ceil(raw / unit) * unit)


func _round_to_unit(raw: float, stat: String) -> int:
	var unit = Catalog.stat_unit(stat)
	return int(max(unit, round(raw / unit) * unit))


func _stat_effect(stat: String, value: int) -> Effect:
	var e = effect_script.new()
	e.key = stat
	e.text_key = Catalog.STAT_TEXT_KEYS.get(stat, "")
	e.key_hash = Keys.generate_hash(stat)
	e.custom_key_hash = Keys.generate_hash("")
	e.value = value
	e.effect_sign = Effect.Sign.FROM_VALUE
	return e


# 机制行复制时记下其估值，便于审计
func _mechanic_copy(m: Dictionary):
	var e = m.effect.duplicate()
	e.set_meta("aa_value", m.value)
	return e


func _pick_mechanic(tier: int, downside: bool, max_abs_value: float):
	var pool = []
	for t in [tier, tier - 1, tier + 1]:
		if t < 0 or t > 3:
			continue
		for m in mechanics_by_tier[t]:
			if m.down == downside and abs(m.value) <= max_abs_value:
				pool.push_back(m)
		if not pool.empty():
			break
	if pool.empty():
		return null
	return pool[rng.randi() % pool.size()]


func _tags_for(effects: Array) -> Array:
	var tags = []
	for e in effects:
		var s = ""
		if e.get_script() == effect_script and Catalog.STATS.has(e.key):
			s = e.key
		elif e.has_method("to_clause"):
			s = e.stat
		if s != "" and e.value > 0 and not s in tags:
			tags.push_back(s)
	return tags


# ============================================================
# 触发条款
# ============================================================
# target：目标价值（负数表示代价条款）。返回 clause 字典，失败返回 {}。
# fixed_trigger / fixed_payload：固定条款的一半，只重组另一半
func gen_clause(target: float, perm_mult: float, negative: bool, fixed_trigger: String = "", fixed_payload: String = "") -> Dictionary:
	for _attempt in 8:
		var c = _try_clause(abs(target), perm_mult, negative, fixed_trigger, fixed_payload)
		if c.empty():
			continue
		var v = abs(Valuation.clause_value(c, perm_mult))
		# 允许 ±35% 的偏差；超出则换一个组合
		if v > 0.0 and v <= abs(target) * 1.35 and v >= abs(target) * 0.4:
			return c
	return {}


const NEGATIVE_TRIGGERS = ["hit", "dodge", "kill", "interval", "still", "moving", "wave_start", "consumable"]


func _legal_payloads(trigger: String, negative: bool) -> Array:
	if negative:
		return ["temp_stat"] if trigger in NEGATIVE_TRIGGERS else []
	var out = []
	for p in Catalog.LEGAL[trigger]:
		if not p in banned_payloads:
			out.push_back(p)
	return out


func _try_clause(budget: float, perm_mult: float, negative: bool, fixed_trigger: String = "", fixed_payload: String = "") -> Dictionary:
	var trigger = fixed_trigger if fixed_trigger != "" else null
	if trigger == null:
		var tw = {}
		for t in Catalog.TRIGGERS:
			if t in banned_triggers:
				continue
			var legal_t = _legal_payloads(t, negative)
			if legal_t.empty() or (fixed_payload != "" and not fixed_payload in legal_t):
				continue
			tw[t] = Catalog.TRIGGERS[t].w + Catalog.NATIVE_PRIOR_STRENGTH * trigger_prior[t] / 3.0
		trigger = _pick_weighted(tw)
	if trigger == null:
		return {}
	var legal: Array = _legal_payloads(trigger, negative)
	if fixed_payload != "":
		legal = [fixed_payload] if fixed_payload in legal else []
	var pw = {}
	for p in legal:
		pw[p] = Catalog.PAYLOADS[p].w + Catalog.NATIVE_PRIOR_STRENGTH * payload_prior[p] / 3.0
	var payload = _pick_weighted(pw)
	if payload == null:
		return {}

	var c = {"trigger": trigger, "payload": payload, "param": 1, "chance": 100, "cap": 0, "stat": "", "value": 1, "value2": 0}
	var t = Catalog.TRIGGERS[trigger]
	if trigger == "interval":
		c.param = Catalog.INTERVAL_CHOICES[rng.randi() % Catalog.INTERVAL_CHOICES.size()]

	match payload:
		"temp_stat", "timed_stat":
			c.stat = _pick_stat(negative, Catalog.TEMP_STAT_BANNED)
			c.value = Catalog.stat_unit(c.stat)
			if payload == "timed_stat":
				c.value2 = [3, 4, 5, 6, 8][rng.randi() % 5]
			if payload == "temp_stat" and t.kind == "event" and Valuation.raw_rate(trigger, 1, 100) > 6.0 and rng.randf() < 0.5:
				c.cap = [10, 15, 20, 30][rng.randi() % 4]
		"perm_stat":
			c.stat = _pick_stat(false)
			c.value = Catalog.stat_unit(c.stat)
			if Valuation.raw_rate(trigger, 1, 100) > 1.5:
				c.cap = 1 + rng.randi() % 3
		"heal", "gold":
			c.value = 1
		"xp":
			c.value = 3
		"damage":
			c.stat = _pick_stat(false, [], Catalog.DAMAGE_SCALING_STATS)
			c.value = [50, 75, 100, 150, 200][rng.randi() % 5]
		"explode":
			c.stat = _pick_stat(false, [], Catalog.DAMAGE_SCALING_STATS)
			c.value = [50, 75, 100, 150][rng.randi() % 4]

	var unit_v = abs(Valuation.clause_value(c, perm_mult))
	if unit_v <= 0.0:
		return {}

	if unit_v <= budget:
		# 预算有余：先提高数值（有合理上限），再用"每 N 次"之外的门控不变
		var k = floor(budget / unit_v)
		var k_max = _amount_cap(c, trigger)
		k = clamp(k, 1, k_max)
		if payload in ["damage", "explode"]:
			c.value = int(min(c.value * k, 400))
		elif payload == "xp":
			c.value = int(c.value * k)
		else:
			c.value = int(c.value * k)
	else:
		# 预算不足：按扳机的门控方式降低频率
		var ratio = budget / unit_v
		if t.gate == "every":
			c.param = int(max(1, ceil(1.0 / ratio)))
		elif t.gate == "chance" or t.kind == "shop":
			c.chance = int(clamp(round(ratio * 20.0) * 5, 5, 100))
			if c.chance == 5 and ratio < 0.05:
				return {}
		elif trigger == "interval":
			var fitted = int(ceil(c.param / ratio))
			if fitted > 30:
				return {}
			c.param = fitted
		else:
			return {}
		# 永久属性在高频扳机上再用每波上限收口
		if payload == "perm_stat" and c.cap > 1:
			var per_fire = abs(Valuation.clause_value(c, perm_mult)) / max(0.01, Valuation.fires_per_wave(trigger, c.param, c.chance, c.cap))
			c.cap = int(clamp(floor(budget / max(0.01, per_fire)), 1, c.cap))

	# 单次触发的属性数值同样受原版单行上限约束
	if c.payload in ["temp_stat", "perm_stat", "timed_stat"]:
		c.value = int(min(c.value, _line_cap(c.stat, negative)))
	if negative:
		c.value = -abs(c.value)
	return c


func _amount_cap(c: Dictionary, trigger: String) -> int:
	var rate = Valuation.raw_rate(trigger, c.param, c.chance)
	var kind = Catalog.TRIGGERS[trigger].kind
	match c.payload:
		"temp_stat":
			if kind == "state" or rate <= 1.5:
				return 40
			return 5 if rate <= 10 else 2
		"perm_stat":
			return 6 if rate <= 1.5 else 2
		"timed_stat":
			return 20 if rate <= 2.0 else 8
		"heal":
			return 6
		"gold":
			return 10 if rate <= 3 else 3
		"xp":
			return 20
		"damage", "explode":
			return 8
	return 5


# ============================================================
# 角色：保留身份行（初始物品、武器限制、属性成长修正、特殊机制），重掷普通属性行；
# 原版触发行只重组一半——要么保留扳机换效果，要么保留效果换扳机——让角色仍然"像自己"
# ============================================================
func generate_character(ch) -> Dictionary:
	_seed_for(ch.my_id)
	var perm_mult = Catalog.PERM_MULT_CHARACTER
	banned_triggers = []
	banned_payloads = []
	for e in ch.effects:
		if e.key == "no_heal" and e.value > 0:
			banned_triggers.push_back("heal")
			banned_payloads.push_back("heal")
	var out = []
	var rerollable_pos = []
	var main_adj = ""
	var main_v = 0.0
	var used = []
	for e in ch.effects:
		if is_plain_stat(e) and ((e.value > 0 and e.value <= 20) or (e.value < 0 and e.value >= -10)):
			var neg = e.value < 0
			var s = _pick_stat(neg, used + [e.key])
			used.push_back(s)
			var v = _round_to_unit(abs(e.value) * Catalog.stat_w(e.key) / Catalog.stat_w(s), s)
			var ne = _stat_effect(s, -v if neg else v)
			out.push_back(ne)
			if not neg:
				rerollable_pos.push_back(ne)
			continue
		var nt = native_trigger_of(e)
		if nt != null and Catalog.STATS.has(e.key) and e.value != 0:
			var native = {"trigger": nt[0], "payload": nt[1], "stat": e.key, "value": e.value, "param": 5 if nt[0] == "interval" else 1}
			var nv = Valuation.clause_value(native, perm_mult)
			var c = {}
			if rng.randf() < 0.5:
				c = gen_clause(nv, perm_mult, nv < 0, nt[0], "")
			else:
				c = gen_clause(nv, perm_mult, nv < 0, "", nt[1])
			if c.empty():
				c = gen_clause(nv, perm_mult, nv < 0)
			if not c.empty():
				out.push_back(TriggerEffect.make(c))
				if abs(nv) > main_v and nv > 0:
					main_v = abs(nv)
					main_adj = Catalog.ADJ_BY_TRIGGER[c.trigger]
				continue
		out.push_back(e)
	# 额外把一条正面属性行换成等价触发条款
	if not rerollable_pos.empty() and rng.randf() < 0.6 * _trigger_rate():
		var victim = rerollable_pos[rng.randi() % rerollable_pos.size()]
		var bv = Valuation.stat_line_value(victim.key, victim.value) * _budget_mult()
		var c = gen_clause(bv, perm_mult, false)
		if not c.empty():
			out[out.find(victim)] = TriggerEffect.make(c)
			if main_adj == "":
				main_adj = Catalog.ADJ_BY_TRIGGER[c.trigger]
	if main_adj == "":
		main_adj = "AA_ADJ_ODD"
	banned_triggers = []
	banned_payloads = []
	return {"effects": out, "adj": main_adj}


# ============================================================
# 武器（实验）：同类型（近战 / 远程）武器家族之间交换整套特效，按等级对齐
# ============================================================
static func family_of(weapon_my_id: String) -> String:
	var idx = weapon_my_id.find_last("_")
	if idx > 0 and weapon_my_id.substr(idx + 1).is_valid_integer():
		return weapon_my_id.substr(0, idx)
	return weapon_my_id


func generate_weapons(weapons: Array) -> Dictionary:
	_seed_for("__weapons__")
	var families = {}	# family -> {type, tiers: {tier: weapon}}
	for w in weapons:
		var f = w.weapon_id if w.weapon_id != "" else family_of(w.my_id)
		if not families.has(f):
			families[f] = {"type": w.type, "tiers": {}}
		families[f].tiers[w.tier] = w
	var by_type = {}
	var fam_names = families.keys()
	fam_names.sort()
	for f in fam_names:
		var ty = families[f].type
		if not by_type.has(ty):
			by_type[ty] = []
		by_type[ty].push_back(f)
	var out = {}
	for ty in by_type:
		var names: Array = by_type[ty]
		var donors = names.duplicate()
		# Fisher-Yates
		for i in range(donors.size() - 1, 0, -1):
			var j = rng.randi() % (i + 1)
			var tmp = donors[i]
			donors[i] = donors[j]
			donors[j] = tmp
		for i in names.size():
			var target = families[names[i]]
			var donor = families[donors[i]]
			for tier in target.tiers:
				var tw = target.tiers[tier]
				var dw = _closest_tier(donor.tiers, tier)
				var new_effects = []
				for e in dw.effects:
					var ne = e.duplicate()
					if ne is WeaponStackEffect:
						ne.weapon_stacked_id = tw.weapon_id
						ne.weapon_stacked_id_hash = Keys.generate_hash(tw.weapon_id)
						ne.weapon_stacked_name = tw.name
					new_effects.push_back(ne)
				out[tw.my_id] = {"effects": new_effects, "donor": dw.my_id}
	return out


func _closest_tier(tiers: Dictionary, tier: int):
	if tiers.has(tier):
		return tiers[tier]
	var best = null
	var best_d = 99
	for t in tiers:
		if abs(t - tier) < best_d:
			best_d = abs(t - tier)
			best = tiers[t]
	return best
