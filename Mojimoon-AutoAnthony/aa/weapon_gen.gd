extends Reference

# 武器重组。以武器家族（同 weapon_id 的各稀有度）为单位：
#   仅重组效果（effects）：每个家族换用另一个随机家族的效果（可跨近战 / 远程），
#     再按价值模型（weapon_value.gd）缩放伤害与属性加成，使新武器的价值 = 原武器价值 × 平均数值 × 浮动
#   深度重组（deep）：冷却、暴击、射程、击退、吸血、投射物 / 贯穿 / 弹跳 / 换弹、属性加成、效果、武器类别全部重新生成
#     （各属性从同类型原版武器的分布中抽取），再按价值模型解出伤害与加成系数；近战 / 远程、武器场景不变
# 输出 { my_id: {effects, stats, sets, donor} }

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")
const WeaponValue = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/weapon_value.gd")
const TriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")
const Valuation = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/valuation.gd")

# 绑定在武器场景 / 家族上的效果：只留在原家族（不给别的武器，也不从原家族拿走）
#   电击枪 / 鱼叉枪的区域减速由投射物场景实现（效果只是说明文字）；磁轨炮的未受伤加成只在它的场景脚本里生效；
#   砖头的"命中后碎裂并替换为新武器"只适合砖头这种消耗型武器
const FAMILY_BOUND_KEYS = ["weapon_slow_in_zone", "effect_no_hit_boost", "break_on_hit"]
# 只对远程武器有效的效果（暴击时贯穿 / 弹跳、每 X 发投射物、捡材料时换弹）
const RANGED_ONLY_KEYS = ["pierce_on_crit", "bounce_on_crit", "modify_every_x_projectile", "reload_when_pickup_gold"]
# 原版武器价值 / 价格的对数离散度（浮动范围 100% 的参考）
const NATIVE_SIGMA = 0.2
# 伤害缩放的可接受范围：超出则换下一个候选家族
const MIN_SCALE = 0.3
const MAX_SCALE = 3.5
const DONOR_TRIES = 12

var cfg: Dictionary
var seed_value: int
var rng := RandomNumberGenerator.new()
var wv = WeaponValue.new()
var families: Dictionary = {}	# weapon_id -> {type, tiers: {tier: WeaponData}}
var fam_names: Array = []
# 道具生成器（引入道具效果时用它的属性 / 条款生成；为 null 时不引入）
var gen = null


func _init(p_cfg: Dictionary, p_seed: int, p_gen = null) -> void:
	cfg = p_cfg
	seed_value = p_seed
	gen = p_gen


static func family_of(w) -> String:
	if w.weapon_id != "":
		return w.weapon_id
	var id: String = w.my_id
	var idx = id.find_last("_")
	if idx > 0 and id.substr(idx + 1).is_valid_integer():
		return id.substr(0, idx)
	return id


static func bound_key(e) -> bool:
	return WeaponValue.effect_key(e) in FAMILY_BOUND_KEYS or WeaponValue.effect_id(e) in FAMILY_BOUND_KEYS


static func ranged_only(e) -> bool:
	return WeaponValue.effect_key(e) in RANGED_ONLY_KEYS


func generate(weapons: Array) -> Dictionary:
	var natives = []
	for w in weapons:
		if not w.has_meta("aa_low_of"):
			natives.push_back(w)
	wv.calibrate(natives)
	families = {}
	for w in weapons:
		if w.stats == null:
			continue
		var f = family_of(w)
		if not families.has(f):
			families[f] = {"type": w.type, "tiers": {}}
		families[f].tiers[w.tier] = w
	fam_names = families.keys()
	fam_names.sort()
	if str(cfg.get("weapon_mode", "effects")) == "deep":
		return generate_deep()
	return generate_effects_only()


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


# 家族的浮动（各稀有度共用一次抽取，保持同一家族逐级成长）
func _family_mult(f: String) -> float:
	rng.seed = hash(str(seed_value) + "/wmult/" + f)
	var sigma = NATIVE_SIGMA * float(cfg.get("w_variance", 100)) / 100.0
	var z = clamp(rng.randfn(0.0, 1.0), -2.5, 2.5)
	return float(cfg.get("w_avg", 100)) / 100.0 * exp(z * sigma)


# ============================================================
# 仅重组效果
# ============================================================
func generate_effects_only() -> Dictionary:
	rng.seed = hash(str(seed_value) + "/weapons")
	var order = fam_names.duplicate()
	var pool = fam_names.duplicate()
	_shuffle(pool)
	var out = {}
	for f in order:
		var target = families[f]
		var mult = _family_mult(f)
		# 候选来源家族：打乱后的顺序，从与自身位置对应的那个开始轮换
		var start = pool.find(f)
		var done = false
		for k in DONOR_TRIES:
			var donor_f = pool[(start + 1 + k) % pool.size()]
			var res = _apply_donor(f, target, families[donor_f], mult)
			if not res.empty():
				for id in res:
					out[id] = res[id]
				done = true
				break
		if not done:
			var res = _apply_donor(f, target, target, mult, true)
			for id in res:
				out[id] = res[id]
	return out


# 把来源家族的效果放到目标家族各稀有度上，缩放伤害使价值达标；任一稀有度无法达标返回 {}
func _apply_donor(f: String, target: Dictionary, donor: Dictionary, mult: float, force := false) -> Dictionary:
	var out = {}
	var spec = _item_spec(f, _closest_tier(target.tiers, 0).stats.scaling_stats)
	for tier in target.tiers:
		var tw = target.tiers[tier]
		var dw = _closest_tier(donor.tiers, tier)
		var effects = []
		# 目标家族自身绑定的效果保留
		for e in tw.effects:
			if bound_key(e):
				effects.push_back(e)
		for e in dw.effects:
			if bound_key(e):
				continue
			if ranged_only(e) and target.type == 0:
				if force:
					continue
				return {}
			effects.push_back(_adapt(e.duplicate(), tw))
		var want = _want(tw) * mult
		var line = _item_effect(spec, tier, want)
		if line != null:
			effects.push_back(line)
		var r = _solve_scale(tw.stats, effects, tier, want)
		if not force and (r < MIN_SCALE or r > MAX_SCALE):
			return {}
		var st = scaled_stats(tw.stats, r)
		out[tw.my_id] = {"effects": effects, "stats": st, "donor": dw.my_id, "scale": r}
	return out


# 效果搬到新武器上的改写：棍子的"每有 1 把同名武器"指向新武器
static func _adapt(e, tw):
	if e is WeaponStackEffect:
		e.weapon_stacked_id = tw.weapon_id
		e.weapon_stacked_id_hash = Keys.generate_hash(tw.weapon_id)
		e.weapon_stacked_name = tw.name
	return e


# 伤害与属性加成的缩放倍率 r，使 value(缩放后属性, effects) = want（二分；价值随 r 单调）
func _solve_scale(st, effects: Array, tier: int, want: float) -> float:
	var lo = 0.05
	var hi = 20.0
	if wv.value(scaled_stats(st, hi), effects, tier) < want:
		return hi
	if wv.value(scaled_stats(st, lo), effects, tier) > want:
		return lo
	for _i in 30:
		var mid = sqrt(lo * hi)
		if wv.value(scaled_stats(st, mid), effects, tier) < want:
			lo = mid
		else:
			hi = mid
	return sqrt(lo * hi)


# 伤害 × r（至少 1），每条属性加成 × r（按 5% 取整，正系数至少 5%）
static func scaled_stats(st, r: float):
	var s = st.duplicate()
	s.damage = int(max(1, round(st.damage * r)))
	var sc = []
	for x in st.scaling_stats:
		var c = float(x[1])
		var nc = stepify(c * r, 0.05)
		if c > 0:
			nc = max(0.05, nc)
		sc.push_back([x[0], nc])
	s.scaling_stats = sc
	return s


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ============================================================
# 深度重组
# ============================================================
# 加成属性：16 种主要属性 + 诅咒
const SCALING_STATS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage",
	"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
	"stat_range", "stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting", "stat_curse",
]
# 第二条加成属性的概率（大部分武器只有主属性）
const SECOND_SCALING_CHANCE = 0.3
# 主属性权重 = 原版同类型武器家族中作为主属性的次数 + 此值（原版没出现过的属性也能出现）
const SCALING_BASE_W = 1.5
# 第二个效果的概率
const SECOND_EFFECT_CHANCE = 0.2
# 第二个武器类别的概率（原版约 60% 的武器有两个类别）
const SECOND_SET_CHANCE = 0.6
# 每个类别至少这么多个武器家族（不超过原版数量）
const MIN_SET_FAMILIES = 3
# 每升一级冷却 × 此值
const TIER_COOLDOWN_MULT = 0.95
const DEEP_TRIES = 8

var _bases: Dictionary = {}		# 类型 -> 各家族最低稀有度的原版武器
var _primary_w: Dictionary = {}	# 类型 -> {属性: 权重}
var _second_coefs: Array = []
var _sets: Dictionary = {}		# set my_id -> SetData
var _set_native_count: Dictionary = {}


func _collect_deep_priors() -> void:
	_bases = {0: [], 1: []}
	_primary_w = {0: {}, 1: {}}
	var counts = {0: {}, 1: {}}
	for f in fam_names:
		var fam = families[f]
		var lo = _closest_tier(fam.tiers, 0)
		_bases[fam.type].push_back(lo)
		var sc = lo.stats.scaling_stats
		if sc.size() > 0:
			var st = WeaponValue.stat_name(sc[0][0])
			counts[fam.type][st] = counts[fam.type].get(st, 0) + 1
			for i in range(1, sc.size()):
				if float(sc[i][1]) > 0:
					_second_coefs.push_back(float(sc[i][1]))
		for set in lo.sets:
			_sets[set.my_id] = set
			_set_native_count[set.my_id] = _set_native_count.get(set.my_id, 0) + 1
	for ty in [0, 1]:
		for st in SCALING_STATS:
			_primary_w[ty][st] = float(counts[ty].get(st, 0)) + SCALING_BASE_W
	if _second_coefs.empty():
		_second_coefs = [0.5]


func _pick_base(ty: int):
	var arr: Array = _bases[ty]
	return arr[rng.randi() % arr.size()]


func _pick_w(weights: Dictionary) -> String:
	var total = 0.0
	for k in weights:
		total += weights[k]
	var x = rng.randf() * total
	for k in weights:
		x -= weights[k]
		if x <= 0:
			return k
	return weights.keys()[0]


func generate_deep() -> Dictionary:
	_collect_deep_priors()
	var out = {}
	var fam_sets = {}
	for f in fam_names:
		rng.seed = hash(str(seed_value) + "/wdeep/" + f)
		var fam = families[f]
		var mult = _family_mult(f)
		rng.seed = hash(str(seed_value) + "/wdeep/" + f)
		var res = {}
		for _k in DEEP_TRIES:
			res = _deep_family(fam, mult)
			if not res.empty():
				break
		if res.empty():
			res = _deep_family(fam, mult, true)
		for id in res:
			out[id] = res[id]
		fam_sets[f] = _pick_sets(fam, res)
	_ensure_set_minimum(fam_sets)
	for f in fam_names:
		for tier in families[f].tiers:
			var id = families[f].tiers[tier].my_id
			if out.has(id):
				out[id]["sets"] = fam_sets[f]
	return out


# 一个家族的蓝图：属性在各稀有度共用（冷却逐级略降），效果取来源家族对应稀有度，伤害与加成系数按价值解出
func _deep_family(fam: Dictionary, mult: float, force := false) -> Dictionary:
	var ty: int = fam.type
	var lo = _closest_tier(fam.tiers, 0)
	var bp = lo.stats.duplicate()
	var b = _pick_base(ty).stats
	bp.cooldown = b.cooldown
	bp.recoil_duration = b.recoil_duration
	b = _pick_base(ty).stats
	bp.crit_chance = b.crit_chance
	bp.crit_damage = b.crit_damage
	b = _pick_base(ty).stats
	bp.max_range = b.max_range
	bp.knockback = b.knockback
	bp.lifesteal = _pick_base(ty).stats.lifesteal
	if ty == 0:
		b = _pick_base(ty).stats
		bp.attack_type = b.attack_type
		bp.alternate_attack_type = b.alternate_attack_type
	else:
		b = _pick_base(ty).stats
		bp.nb_projectiles = b.nb_projectiles
		bp.projectile_spread = b.projectile_spread
		b = _pick_base(ty).stats
		bp.piercing = b.piercing
		bp.piercing_dmg_reduction = b.piercing_dmg_reduction
		b = _pick_base(ty).stats
		bp.bounce = b.bounce
		bp.bounce_dmg_reduction = b.bounce_dmg_reduction
		b = _pick_base(ty).stats
		bp.additional_cooldown_every_x_shots = b.additional_cooldown_every_x_shots
		bp.additional_cooldown_multiplier = b.additional_cooldown_multiplier
	# 属性加成：主属性 + 少数武器有第二属性；系数先取原版的值，后面随伤害一起缩放
	var primary = _pick_w(_primary_w[ty])
	var coef = 1.0
	var bsc = _pick_base(ty).stats.scaling_stats
	if bsc.size() > 0 and float(bsc[0][1]) > 0:
		coef = float(bsc[0][1])
	var sc = [[Keys.generate_hash(primary), coef]]
	if rng.randf() < SECOND_SCALING_CHANCE:
		var w2 = _primary_w[ty].duplicate()
		w2.erase(primary)
		sc.push_back([Keys.generate_hash(_pick_w(w2)), _second_coefs[rng.randi() % _second_coefs.size()]])
	bp.scaling_stats = sc
	bp.damage = _pick_base(ty).stats.damage
	# 效果：随机来源家族（可跨类型），少数武器再加一个
	var donors = [families[fam_names[rng.randi() % fam_names.size()]]]
	if rng.randf() < SECOND_EFFECT_CHANCE:
		donors.push_back(families[fam_names[rng.randi() % fam_names.size()]])
	var out = {}
	var spec = _item_spec(family_of(lo), bp.scaling_stats)
	var tiers = fam.tiers.keys()
	tiers.sort()
	for tier in tiers:
		var tw = fam.tiers[tier]
		var effects = []
		var keys = []
		for e in tw.effects:
			if bound_key(e):
				effects.push_back(e)
		for d in donors:
			var dw = _closest_tier(d.tiers, tier)
			for e in dw.effects:
				var key = WeaponValue.effect_key(e)
				if bound_key(e) or key in keys or (ranged_only(e) and ty == 0):
					continue
				keys.push_back(key)
				effects.push_back(_adapt(e.duplicate(), tw))
		var st = bp.duplicate()
		st.scaling_stats = bp.scaling_stats.duplicate(true)
		st.cooldown = int(max(2, round(bp.cooldown * pow(TIER_COOLDOWN_MULT, tier - lo.tier))))
		var want = _want(tw) * mult
		var line = _item_effect(spec, tier, want)
		if line != null:
			effects.push_back(line)
		var r = _solve_scale(st, effects, tier, want)
		if not force and (r < MIN_SCALE or r > MAX_SCALE):
			return {}
		var dwf = _closest_tier(donors[0].tiers, tier)
		out[tw.my_id] = {"effects": effects, "stats": scaled_stats(st, r), "donor": dwf.my_id, "scale": r}
	return out


# 武器类别：按新武器的特性加权（爆炸 -> 爆炸类，点燃 / 元素加成 -> 元素类……），再加少量随机；1–2 个
func _pick_sets(fam: Dictionary, res: Dictionary) -> Array:
	var lo = _closest_tier(fam.tiers, 0)
	var p = res.get(lo.my_id)
	if p == null:
		return lo.sets
	var w = _set_weights(fam, lo, p.stats, p.effects)
	var first = _pick_w(w)
	var out = [_sets[first]]
	if rng.randf() < SECOND_SET_CHANCE:
		w.erase(first)
		if not w.empty():
			out.push_back(_sets[_pick_w(w)])
	return out


func _set_weights(fam: Dictionary, lo, st, effects: Array) -> Dictionary:
	var w = {}
	for id in _sets:
		w[id] = 0.5
	var melee = fam.type == 0
	var primary = WeaponValue.stat_name(st.scaling_stats[0][0]) if st.scaling_stats.size() > 0 else ""
	var ids = []
	for e in effects:
		ids.push_back(WeaponValue.effect_id(e))
		ids.push_back(WeaponValue.effect_key(e))
	var add = {}
	if "weapon_exploding" in ids:
		add["set_explosive"] = 8.0
	if "weapon_burning" in ids or primary == "stat_elemental_damage":
		add["set_elemental"] = 8.0
	if float(st.crit_chance) >= 0.1 or float(st.crit_damage) >= 2.5 or "pierce_on_crit" in ids or "bounce_on_crit" in ids or "gold_on_crit_kill" in ids:
		add["set_precise"] = 5.0
	if float(st.lifesteal) > 0 or primary in ["stat_hp_regeneration", "stat_lifesteal", "stat_max_hp"]:
		add["set_medical"] = 5.0
	if WeaponValue.cooldown_seconds(st) >= 1.4:
		add["set_heavy"] = 5.0
	if primary == "stat_engineering" or "turret" in ids or "structure" in ids or "reload_turrets_on_shoot" in ids:
		add["set_tool"] = 5.0
		add["set_support"] = 3.0
	if primary in ["stat_harvesting", "stat_luck"]:
		add["set_support"] = 5.0
	if "weapon_gain_stat_every_killed_enemies" in ids:
		add["set_ethereal"] = 8.0
	if "null_charm" in ids or "weapon_percent_damage_effect" in ids:
		add["set_musical"] = 8.0
	if not melee and primary == "stat_ranged_damage":
		add["set_gun"] = 5.0
	if melee:
		if int(st.knockback) >= 8:
			add["set_blunt"] = 4.0
		if int(st.max_range) <= 150:
			add["set_unarmed"] = 3.0
		if int(st.attack_type) == 0:
			add["set_blade"] = 3.0
		if st.alternate_attack_type or int(st.max_range) >= 175:
			add["set_medieval"] = 3.0
	if int(st.knockback) < 0 or int(st.min_range) > 0:
		add["set_naval"] = 4.0
	if lo.tier == 0:
		add["set_primitive"] = 2.0
	for id in add:
		if w.has(id):
			w[id] += add[id]
	# 传奇类别只属于原本只有 T4 的武器
	w.erase("set_legendary")
	if lo.tier == 3 and _sets.has("set_legendary"):
		w = {"set_legendary": 1.0}
	return w


# 每个类别至少 MIN_SET_FAMILIES 个家族（不超过原版数量）：不足时随机补给只有一个类别的家族
func _ensure_set_minimum(fam_sets: Dictionary) -> void:
	for id in _sets:
		if id == "set_legendary":
			continue
		var need = min(MIN_SET_FAMILIES, int(_set_native_count.get(id, 0)))
		var have = 0
		for f in fam_sets:
			for s in fam_sets[f]:
				if s.my_id == id:
					have += 1
		if have >= need:
			continue
		var cands = []
		for f in fam_names:
			var cur: Array = fam_sets[f]
			if cur.size() >= 2 or _sets[id] in cur or _closest_tier(families[f].tiers, 0).tier == 3:
				continue
			cands.push_back([rng.randf(), f])
		cands.sort()
		for c in cands:
			if have >= need:
				break
			fam_sets[c[1]] = fam_sets[c[1]] + [_sets[id]]
			have += 1


# ============================================================
# 引入道具效果：每个家族至多一条道具的属性行或触发条款（各稀有度相同，数值随稀有度的价值增长）
# ============================================================
# 拿到道具效果的家族比例
const ITEM_LINE_CHANCE = 0.6
# 道具效果与武器本身相关的概率：武器加成属性的属性行（狼牙棒吃 -攻速 加成 -> -攻速）
const ITEM_RELATED_CHANCE = 0.4
# 道具效果占武器价值的比例
const ITEM_LINE_SHARE = 0.25
# 不相关时属性行 / 触发条款各半
const ITEM_CLAUSE_CHANCE = 0.5


# 家族的道具效果规格：{kind: stat / clause, stat, neg, clause}；不加时为 {}
func _item_spec(f: String, scaling: Array) -> Dictionary:
	if gen == null or not cfg.get("w_item_effects", false):
		return {}
	rng.seed = hash(str(seed_value) + "/witem/" + f)
	if rng.randf() >= ITEM_LINE_CHANCE:
		return {}
	if rng.randf() < ITEM_RELATED_CHANCE and scaling.size() > 0:
		var x = scaling[rng.randi() % scaling.size()]
		var st = WeaponValue.stat_name(x[0])
		if Catalog.STATS.has(st):
			return {"kind": "stat", "stat": st, "neg": float(x[1]) < 0, "related": true}
	gen.rng.seed = hash(str(seed_value) + "/witemgen/" + f)
	gen.cur_tier = 0
	if rng.randf() < ITEM_CLAUSE_CHANCE:
		var c = gen.gen_clause(6.0, Catalog.PERM_MULT[0], false)
		gen.cur_tier = -1
		if not c.empty():
			return {"kind": "clause", "clause": c, "base": abs(Valuation.clause_value(c, Catalog.PERM_MULT[0]))}
	var st = gen._pick_stat(false, Catalog.SIDE_ONLY_STATS)
	gen.cur_tier = -1
	return {"kind": "stat", "stat": st, "neg": false, "related": false}


# 规格在某稀有度上的效果：价值 = 武器价值 × ITEM_LINE_SHARE
func _item_effect(spec: Dictionary, tier: int, weapon_value: float):
	if spec.empty():
		return null
	var budget = max(1.0, weapon_value * ITEM_LINE_SHARE)
	if spec.kind == "stat":
		var st: String = spec.stat
		var v = gen._round_to_unit(budget / Catalog.stat_w(st), st)
		v = int(min(v, gen._line_cap(st, false)))
		var e = gen._stat_effect(st, -v if spec.neg else v)
		# 负系数相关的属性行（狼牙棒的 -攻速）：对这把武器是好处、对其他武器是代价，不计价值
		e.set_meta("aa_value", 0.0 if spec.neg else v * Catalog.stat_w(st))
		return e
	var c: Dictionary = spec.clause.duplicate(true)
	var perm = Catalog.PERM_MULT[tier]
	c.value = int(max(1, round(float(c.value) * budget / max(0.1, float(spec.base)))))
	var te = TriggerEffect.make(c)
	te.set_meta("aa_value", abs(Valuation.clause_value(c, perm)))
	return te


# 武器的目标价值（未乘浮动）：原版武器按模型估值；补出的低级武器 = 原最低级的价值 × 价格比例
func _want(w) -> float:
	if w.has_meta("aa_low_of"):
		var base = w.get_meta("aa_low_of")
		return wv.value(base.stats, base.effects, base.tier) * float(w.value) / max(1.0, float(base.value))
	return wv.value(w.stats, w.effects, w.tier)


# ============================================================
# 允许低级武器：没有低级版本的武器家族补到 T1。新武器复制最低级的原版武器（图标、场景、类别），
# 价格按原版同类型武器相邻稀有度的价格比例（中位数）递减，合成后升级为上一级；属性由重组按价值重新解出
# ============================================================
static func make_low_tiers(weapons: Array) -> Array:
	var fams = {}
	for w in weapons:
		if w.stats == null or w.has_meta("aa_low_of"):
			continue
		var f = family_of(w)
		if not fams.has(f):
			fams[f] = {}
		fams[f][w.tier] = w
	# 相邻稀有度价格比例（低 / 高），按类型取中位数
	var ratios = {0: [[], [], []], 1: [[], [], []]}
	for f in fams:
		for t in 3:
			if fams[f].has(t) and fams[f].has(t + 1):
				var lo = fams[f][t]
				ratios[lo.type][t].push_back(float(lo.value) / max(1.0, float(fams[f][t + 1].value)))
	var out = []
	var names = fams.keys()
	names.sort()
	for f in names:
		var tiers: Dictionary = fams[f]
		var t0 = 3
		for t in tiers:
			t0 = min(t0, t)
		var base = tiers[t0]
		var next = base
		var price = float(base.value)
		for t in range(t0 - 1, -1, -1):
			var arr: Array = ratios[base.type][t]
			arr.sort()
			price *= arr[arr.size() / 2] if not arr.empty() else 0.5
			var w = base.duplicate()
			w.my_id = base.weapon_id + "_" + str(t + 1)
			w.my_id_hash = Keys.generate_hash(w.my_id)
			w.weapon_id_hash = Keys.generate_hash(base.weapon_id)
			w.tier = t
			w.value = int(max(1, round(price)))
			w.stats = base.stats.duplicate()
			w.effects = base.effects.duplicate()
			w.upgrades_into = next
			w.set_meta("aa_low_of", base)
			out.push_back(w)
			next = w
	return out
