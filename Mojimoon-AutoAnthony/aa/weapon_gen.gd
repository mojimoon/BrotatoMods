extends Reference

# 武器重组。以武器家族（同 weapon_id 的各稀有度）为单位：
#   仅重组效果（effects）：每个家族换用另一个随机家族的效果（可跨近战 / 远程），
#     再按价值模型（weapon_value.gd）缩放伤害与属性加成，使新武器的价值 = 原武器价值 × 平均数值 × 浮动
#   深度重组（deep）：冷却、暴击、射程、击退、吸血、投射物 / 贯穿 / 弹跳 / 换弹、属性加成、效果、武器类别全部重新生成
#     （各属性从同类型原版武器的分布中抽取）；最低一级随机多组、取价值不超过价格对应目标的最好一组，
#     更高一级在低一级基础上逐项随机提升、按实际价值重新定价；近战 / 远程、武器场景不变
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
# 浮动范围 100% 时家族强度倍率的对数标准差（原版"价值 / 价格"的离散度约 0.36，但大部分是模型误差，不照搬）
const NATIVE_SIGMA = 0.1
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
	# 同类型同稀有度原版武器的 模型价值 / 价格 中位数（补出的低级武器按价格换算目标价值）
	var vp = {}
	for w in natives:
		if w.stats == null or int(w.value) <= 0:
			continue
		var key = str(w.type) + "/" + str(w.tier)
		if not vp.has(key):
			vp[key] = []
		vp[key].push_back(wv.value(w.stats, w.effects, w.tier) / float(w.value))
	_vp = {}
	for key in vp:
		vp[key].sort()
		_vp[key] = vp[key][vp[key].size() / 2]
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
	var out = generate_deep() if str(cfg.get("weapon_mode", "effects")) == "deep" else generate_effects_only()
	_no_inversion(out)
	_name_families(out)
	return out


# 相邻稀有度价格比例（低 / 高），按类型取中位数：{类型: [T1/T2, T2/T3, T3/T4]}
static func price_ratios(weapons: Array) -> Dictionary:
	var fams = {}
	for w in weapons:
		if w.stats == null or w.has_meta("aa_low_of"):
			continue
		var f = family_of(w)
		if not fams.has(f):
			fams[f] = {}
		fams[f][w.tier] = w
	var raw = {0: [[], [], []], 1: [[], [], []]}
	for f in fams:
		for t in 3:
			if fams[f].has(t) and fams[f].has(t + 1):
				var lo = fams[f][t]
				raw[lo.type][t].push_back(float(lo.value) / max(1.0, float(fams[f][t + 1].value)))
	var out = {0: [0.5, 0.5, 0.5], 1: [0.5, 0.5, 0.5]}
	for ty in raw:
		for t in 3:
			var arr: Array = raw[ty][t]
			if not arr.empty():
				arr.sort()
				out[ty][t] = arr[arr.size() / 2]
	return out


# 武器名称：每个家族按它最显著的特性（效果、节奏、暴击 / 吸血、主加成属性）选一个形容词，各稀有度相同
func _name_families(out: Dictionary) -> void:
	for f in fam_names:
		var fam = families[f]
		var lo = _closest_tier(fam.tiers, 0)
		if not out.has(lo.my_id):
			continue
		rng.seed = hash(str(seed_value) + "/wname/" + f)
		var adj = _weapon_adj(out[lo.my_id])
		for t in fam.tiers:
			var id = fam.tiers[t].my_id
			if out.has(id):
				out[id]["adj"] = adj


func _weapon_adj(p: Dictionary) -> String:
	var st = p.stats
	var cats = []
	for e in p.effects:
		match WeaponValue.effect_id(e):
			"weapon_exploding":
				cats.push_back("explosive")
			"weapon_burning":
				cats.push_back("burning")
			"weapon_projectiles_on_hit":
				cats.push_back("splinter")
	if float(st.lifesteal) > 0:
		cats.push_back("stat_lifesteal")
	if is_high_crit(st):
		cats.push_back("crit")
	var cd = WeaponValue.cooldown_seconds(st)
	if cd < 0.55:
		cats.push_back("fast")
	elif cd >= SLOW_COOLDOWN:
		cats.push_back("heavy")
	if not WeaponValue.is_melee(st):
		if int(st.nb_projectiles) > 1:
			cats.push_back("splinter")
		if int(st.piercing) >= 2:
			cats.push_back("piercing")
	if st.scaling_stats.size() > 0:
		cats.push_back(WeaponValue.stat_name(st.scaling_stats[0][0]))
	var opts = []
	if not cats.empty():
		var c = cats[rng.randi() % cats.size()]
		opts = Catalog.WEAPON_ADJ.get(c, Catalog.ADJ_BY_STAT.get(c, []))
	if opts.empty():
		opts = Catalog.ADJ_MECHANIC
	return opts[rng.randi() % opts.size()]


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
	# 向上至多 +1.5σ（原版的离散度有不少是模型误差，不全是真实强度差）
	var z = clamp(rng.randfn(0.0, 1.0), -2.5, 1.5)
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
				effects.push_back(_vary_fixed(e, f))
		for e in dw.effects:
			if bound_key(e):
				continue
			if ranged_only(e) and target.type == 0:
				if force:
					continue
				return {}
			effects.push_back(_vary_fixed(_adapt(_convert_explosion(e.duplicate(), target.type), tw), f))
		var base_st = _bind_javelin(tw.stats, effects, float(dw.stats.crit_damage))
		var want = _want(tw) * mult
		var line = _item_effect(spec, tier, want)
		if line != null:
			effects.push_back(line)
		var excess = _downside_excess(want, effects)
		want -= excess
		var r = _solve_scale(base_st, effects, tier, want)
		if not force and (r < MIN_SCALE or r > MAX_SCALE):
			return {}
		var st = scaled_stats(base_st, r)
		out[tw.my_id] = {"effects": effects, "stats": st, "donor": dw.my_id, "scale": r, "want": want, "capped": excess > 0}
	return out


# 效果搬到新武器上的改写：棍子的"每有 1 把同名武器"指向新武器
# 固定参数的效果按家族随机（各稀有度共用一次抽取）：砖头碎裂掉落的材料、磁轨炮的加成、自伤（至多原版的 3）
func _vary_fixed(e, f: String):
	var key = WeaponValue.effect_key(e)
	if not key in ["break_on_hit", "effect_no_hit_boost", "lose_hp_per_second"]:
		return e
	var r = RandomNumberGenerator.new()
	r.seed = hash(str(seed_value) + "/wfix/" + f + "/" + key)
	var ne = e.duplicate()
	match key:
		"break_on_hit":
			# 碎裂几率不变，掉落材料随机
			if "value2" in ne:
				ne.value2 = int(max(1, round(float(ne.value2) * r.randf_range(0.5, 1.5))))
		"effect_no_hit_boost":
			ne.value = int(max(1, round(float(ne.value) * r.randf_range(0.5, 1.5))))
		"lose_hp_per_second":
			ne.value = r.randi_range(1, 3)
	return ne


# 逐级强化（同一家族，从低到高）：
#   1. 特效数值必须强于低一级（至少一步；已到上限的除外；代价与固定参数的效果不动）
#   2. 基础伤害与正加成系数不低于低一级
#   3. 因此超出目标价值时，先放慢攻速（不慢于低一级）、再降暴击（不低于低一级）；仍超出则不管
const TIER_FIT_TOL = 1.05
const NO_STRENGTHEN_KEYS = ["break_on_hit", "lose_hp_per_second", "effect_slow_in_zone"]


func _no_inversion(out: Dictionary) -> void:
	for f in fam_names:
		var tiers = families[f].tiers.keys()
		tiers.sort()
		var prev = null
		for t in tiers:
			var id = families[f].tiers[t].my_id
			if not out.has(id) or not out[id].has("stats"):
				continue
			var p = out[id]
			if prev != null:
				var before = wv.value(p.stats, p.effects, t)
				p.effects = _strengthen_effects(p.effects, prev.effects)
				var st = p.stats
				st.damage = int(max(st.damage, prev.stats.damage))
				var sc = []
				for x in st.scaling_stats:
					var c = float(x[1])
					for y in prev.stats.scaling_stats:
						if y[0] == x[0] and c >= 0 and float(y[1]) > c:
							c = float(y[1])
					sc.push_back([x[0], c])
				st.scaling_stats = sc
				if wv.value(st, p.effects, t) > before + 0.01:
					p["lifted"] = true
					if p.has("want"):
						_slow_down(p, prev.stats, t)
			prev = p


func _strengthen_effects(effects: Array, prev_effects: Array) -> Array:
	var used = []
	var res = []
	for e in effects:
		var key = WeaponValue.effect_key(e)
		var pe = null
		for q in prev_effects:
			if WeaponValue.effect_key(q) == key and not q in used:
				pe = q
				break
		if pe == null:
			res.push_back(e)
			continue
		used.push_back(pe)
		res.push_back(_stronger_than(e, pe))
	return res


static func _dup(e):
	var ne = e.duplicate()
	for m in e.get_meta_list():
		ne.set_meta(m, e.get_meta(m))
	return ne


# 返回不弱于 pe 一步的 e（必要时复制后修改）
static func _stronger_than(e, pe):
	var key = WeaponValue.effect_key(e)
	if key in NO_STRENGTHEN_KEYS or key.begins_with("structure:"):
		return e
	match WeaponValue.effect_id(e):
		"weapon_exploding":
			if float(pe.chance) >= 1.0 or float(e.chance) > float(pe.chance):
				return e
			var ne = _dup(e)
			ne.chance = min(1.0, float(pe.chance) + 0.05)
			return ne
		"weapon_burning":
			if e.burning_data == null or pe.burning_data == null or int(e.burning_data.damage) > int(pe.burning_data.damage):
				return e
			var ne = _dup(e)
			ne.burning_data = e.burning_data.duplicate()
			ne.burning_data.damage = int(pe.burning_data.damage) + 1
			return ne
		"weapon_projectiles_on_hit":
			if e.weapon_stats == null or pe.weapon_stats == null:
				return e
			if int(e.value) > int(pe.value) or (int(e.value) == int(pe.value) and int(e.weapon_stats.damage) > int(pe.weapon_stats.damage)):
				return e
			var ne = _dup(e)
			ne.value = int(max(int(e.value), int(pe.value)))
			ne.weapon_stats = e.weapon_stats.duplicate()
			ne.weapon_stats.damage = int(pe.weapon_stats.damage) + 1
			return ne
	# 没有数值的开关型效果（对燃烧目标必定暴击：value = 0）不强化
	if not "value" in e or (float(e.value) == 0 and float(pe.value) == 0):
		return e
	var m0 = WeaponValue.magnitude(pe)
	# 代价（负值）不强化；已强于低一级的不动
	if m0 < 0 or float(pe.value) < 0 or WeaponValue.magnitude(e) > m0:
		return e
	var ne = _dup(e)
	for v in [int(pe.value) + 1, int(pe.value) - 1]:
		if v < 1 or (v > int(pe.value) and int(pe.value) >= 100):
			continue
		ne.value = v
		if WeaponValue.magnitude(ne) > m0:
			if e.has_meta("aa_value") and float(e.value) > 0:
				ne.set_meta("aa_value", float(e.get_meta("aa_value")) * float(v) / float(e.value))
			return ne
	return e


# 价值超出目标：冷却最多放慢到低一级的冷却，暴击最多降到低一级的暴击
func _slow_down(p: Dictionary, prev_st, tier: int) -> void:
	var want = float(p.want) * TIER_FIT_TOL
	var st = p.stats
	if wv.value(st, p.effects, tier) <= want:
		return
	var cd0 = int(st.cooldown)
	var cd1 = int(max(cd0, int(prev_st.cooldown)))
	var lo = cd0
	var hi = cd1
	st.cooldown = cd1
	if wv.value(st, p.effects, tier) <= want:
		while hi - lo > 1:
			var mid = (lo + hi) / 2
			st.cooldown = mid
			if wv.value(st, p.effects, tier) <= want:
				hi = mid
			else:
				lo = mid
		st.cooldown = hi
		return
	var c0 = float(st.crit_chance)
	var c1 = min(c0, float(prev_st.crit_chance))
	var d0 = float(st.crit_damage)
	var d1 = min(d0, float(prev_st.crit_damage))
	var a_lo = 0.0
	var a_hi = 1.0
	st.crit_chance = c1
	st.crit_damage = d1
	if wv.value(st, p.effects, tier) > want:
		return
	for _i in 12:
		var a = (a_lo + a_hi) / 2.0
		st.crit_chance = c0 + (c1 - c0) * a
		st.crit_damage = d0 + (d1 - d0) * a
		if wv.value(st, p.effects, tier) <= want:
			a_hi = a
		else:
			a_lo = a
	st.crit_chance = max(c1, stepify(c0 + (c1 - c0) * a_hi, 0.01))
	st.crit_damage = max(d1, stepify(d0 + (d1 - d0) * a_hi, 0.05))


# 负面效果（自伤、-属性、每把武器 -属性……）抵扣的价值至多为目标价值的 DOWNSIDE_CAP：
# 代价按绝对量估值，放在便宜武器上可能远超武器本身，全部换成伤害会补出离谱的面板。返回超出的部分（从目标价值中扣除）
const DOWNSIDE_CAP = 0.25


func _downside_excess(want: float, effects: Array) -> float:
	var neg = 0.0
	for e in effects:
		var v = wv.effect_value(e)
		if v < 0:
			neg -= v
	return max(0.0, neg - DOWNSIDE_CAP * want)


static func _adapt(e, tw):
	if e is WeaponStackEffect:
		e.weapon_stacked_id = tw.weapon_id
		e.weapon_stacked_id_hash = Keys.generate_hash(tw.weapon_id)
		e.weapon_stacked_name = tw.name
	return e


# 伤害与属性加成的缩放倍率 r，使 value(缩放后属性, effects) = want（二分；价值随 r 单调）
func _solve_scale(st, effects: Array, tier: int, want: float, coef_exp := 1.0) -> float:
	var lo = 0.05
	var hi = 20.0
	if wv.value(scaled_stats(st, hi, coef_exp), effects, tier) < want:
		return hi
	if wv.value(scaled_stats(st, lo, coef_exp), effects, tier) > want:
		return lo
	for _i in 30:
		var mid = sqrt(lo * hi)
		if wv.value(scaled_stats(st, mid, coef_exp), effects, tier) < want:
			lo = mid
		else:
			hi = mid
	return sqrt(lo * hi)


# 伤害 × r（至少 1），每条属性加成 × r^coef_exp（按 5% 取整，正系数至少 5%）
static func scaled_stats(st, r: float, coef_exp := 1.0):
	var s = st.duplicate()
	s.damage = int(max(1, round(st.damage * r)))
	var sc = []
	var rc = pow(r, coef_exp)
	for x in st.scaling_stats:
		var c = float(x[1])
		var nc = stepify(c * rc, 0.05)
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
# 加成属性：主要属性（%伤害除外）+ 诅咒 + 等级（短木棍）
const SCALING_STATS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_melee_damage",
	"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
	"stat_range", "stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting", "stat_curse", "stat_levels",
]
const DAMAGE_STATS = ["stat_melee_damage", "stat_ranged_damage", "stat_elemental_damage"]
# 主加成（第一条加成属性）的伤害类型分布，按武器类型。原版：近战武器 46/47 以近战伤害为主（元素伤害只作为附加），
# 远程武器 23/31 远程、6/31 元素、3/31 近战；没有伤害类主加成的只有尖刺盾（护甲）。
# 这里没有伤害类主加成的比例比原版略高（none -> 主加成从其他属性中抽）
const MAIN_SCALING = {
	0: {"stat_melee_damage": 0.84, "stat_elemental_damage": 0.07, "stat_ranged_damage": 0.02, "none": 0.07},
	1: {"stat_ranged_damage": 0.70, "stat_elemental_damage": 0.17, "stat_melee_damage": 0.06, "none": 0.07},
}
# 第二条加成属性的概率（原版近战约一半、远程约三成）
const SECOND_SCALING_CHANCE = {0: 0.45, 1: 0.3}
# 第二条 / 非伤害主加成的属性权重 = 原版作为附加加成的次数 + 此值
const SCALING_BASE_W = 1.0
# 第二个效果的概率
# 额外效果中道具效果所占的比例（引入道具效果开启时）
const ITEM_SLOT_SHARE = 0.4
# 第二个武器类别的概率（原版约 60% 的武器有两个类别）
const SECOND_SET_CHANCE = 0.6
# 每个类别至少这么多个武器家族（不超过原版数量）
const MIN_SET_FAMILIES = 3
# 最低一级随机组合的个数上限；价值落在目标的 [1 - PICK_BAND, 1] 内即可采用
const DEEP_TRIES = 24
const PICK_BAND = 0.1
const DEEP_TEMPLATES = 2
# 慢速武器（平均攻击间隔 ≥ 此值，秒）：手感差、通常不会选用，作为攻击节奏的权重低；可以有更高的加成系数（激光枪、歼灭者）
const SLOW_COOLDOWN = 1.4
const SLOW_PROFILE_W = 0.25
# 系数上限（折算成近战伤害的系数）：附加加成 1.25（镰刀收获 25% 约 1.25）；正常节奏武器的主加成 2.0（锤子 T4）；慢速武器不限
const SEC_COEF_CAP = 1.25
const MAIN_COEF_CAP = 2.0
# 慢速武器的主加成系数上限（折算成近战伤害）：原版激光枪等慢速武器的系数较高，但不能无限制（否则传奇慢速武器会解出 2000%+）
const SLOW_COEF_CAP = 4.0
# 效果（来源家族 + 道具效果）至多占武器目标价值的比例
const FX_SHARE_CAP = 0.4
# 更高一级：冷却、贯穿 / 弹跳 / 吸血 / 射程 / 击退各自提升的概率；加成系数提升的概率；基础伤害提升的概率
const UP_CHANCE = 0.5
const COEF_UP_CHANCE = 0.75
const DMG_UP_CHANCE = 0.5
# 基础伤害没抽中提升、但效果补完后仍比目标价值低这么多：基础伤害仍然提升
const DMG_FORCE_GAP = 0.15
# 效果每升一级至多放大的倍数
const FX_GROWTH_CAP = 2.0
# 加成系数下限（不分稀有度、不分第几条加成；参考原版，约为终局属性 15 点时加成出的伤害）
const SCALING_FLOOR = {
	"stat_max_hp": 0.15, "stat_hp_regeneration": 0.35, "stat_lifesteal": 0.5, "stat_melee_damage": 0.25,
	"stat_ranged_damage": 0.5, "stat_elemental_damage": 0.4, "stat_attack_speed": 0.15, "stat_crit_chance": 0.2,
	"stat_engineering": 0.35, "stat_range": 0.1, "stat_armor": 0.95, "stat_dodge": 0.25, "stat_speed": 0.25,
	"stat_luck": 0.1, "stat_harvesting": 0.1, "stat_levels": 0.75, "stat_curse": 0.15,
}
# 单次伤害（含暴击）不宜超过该阶段参考敌人生命的倍数
const HIT_CAP = 3.0
const KB_CAP = {0: 15, 1: 8}
# 基础伤害下限（按稀有度；多发武器按发数开方折算）：1 点基础伤害前期没有战斗力，宁可降低加成与攻速也要保证。
# 点燃敌人的武器、以收获为加成的武器（原版掌、火炬、魔杖）不受限
const BASE_DMG_MIN = [3.0, 5.0, 7.0, 10.0]
# 高暴击：暴击率 / 暴击伤害达到此值的武器带"暴击"词条（必定精准类）
const HIGH_CRIT_CHANCE = 0.15
# 标枪效果（每 X 发投射物 +100% 暴击率）：绑定 0% 暴击率 + 高暴伤（标枪自己的暴击模板），这样的武器不算高暴击
const JAVELIN_KEY = "modify_every_x_projectile"


# 高暴击：暴击率高，或暴伤高且有暴击率（0% 暴击率的高暴伤是标枪模板，靠效果暴击）
static func is_high_crit(st) -> bool:
	return float(st.crit_chance) >= HIGH_CRIT_CHANCE or (float(st.crit_damage) >= HIGH_CRIT_DAMAGE and float(st.crit_chance) > 0)


static func is_javelin_template(st) -> bool:
	return float(st.crit_chance) <= 0 and float(st.crit_damage) >= HIGH_CRIT_DAMAGE


# 带标枪效果：暴击改为 0% + 来源标枪的暴伤
static func _bind_javelin(st, effects: Array, crit_damage: float):
	for e in effects:
		if WeaponValue.effect_key(e) == JAVELIN_KEY:
			var s = st.duplicate()
			s.crit_chance = 0.0
			s.crit_damage = crit_damage
			return s
	return st
const HIGH_CRIT_DAMAGE = 2.5

# 词条 -> 武器类别：must = 必定、high = 优先（必定之后、名额未满时先取）、may = 可能（重复出现 = 权重更高）。词条包括原版角色的偏好词条（含全部主要属性）与武器自身特性；
# 宠物词条没有对应类别（驯兽师没有武器）
const TAG_SETS = {
	"stat_melee_damage": {"may": ["set_blade", "set_blade", "set_primitive", "set_primitive", "set_blunt", "set_medieval", "set_unarmed"]},
	"stat_ranged_damage": {"high": ["set_gun"], "may": ["set_precise", "set_heavy"]},
	"stat_elemental_damage": {"must": ["set_elemental"]},
	"stat_engineering": {"must": ["set_tool"], "may": ["set_support"]},
	"stat_lifesteal": {"may": ["set_medical", "set_blade"]},
	"stat_hp_regeneration": {"may": ["set_medical"]},
	"stat_max_hp": {"may": ["set_blunt", "set_heavy", "set_medical"]},
	"stat_armor": {"may": ["set_blunt", "set_medieval", "set_heavy"]},
	"stat_dodge": {"may": ["set_ethereal", "set_unarmed"]},
	"stat_curse": {"must": ["set_naval"]},
	"stat_luck": {"may": ["set_support", "set_musical"]},
	"stat_harvesting": {"must": ["set_support"]},
	"stat_speed": {"may": ["set_medieval", "set_unarmed"]},
	"stat_range": {"may": ["set_precise", "set_medieval"]},
	"stat_crit_chance": {"must": ["set_precise"], "may": ["set_blade"]},
	"stat_attack_speed": {"may": ["set_primitive", "set_unarmed"]},
	"stat_levels": {"may": ["set_primitive", "set_medieval"]},
	"explosive": {"must": ["set_explosive"]},
	"burning": {"may": ["set_elemental"]},
	"burning_main": {"high": ["set_elemental"]},
	"structure": {"must": ["set_tool"], "may": ["set_support"]},
	"ethereal": {"must": ["set_ethereal"]},
	"musical": {"must": ["set_musical"]},
	"economy": {"may": ["set_support", "set_precise"]},
	"xp_gain": {"may": ["set_support", "set_primitive"]},
	"consumable": {"may": ["set_musical", "set_support"]},
	"pickup": {"may": ["set_support"]},
	"exploration": {"may": ["set_support"]},
	"stand_still": {"may": ["set_heavy"]},
	"less_enemy_speed": {"may": ["set_support"]},
	"heavy": {"must": ["set_heavy"]},
}
# 只属于某一类型武器的类别
const MELEE_ONLY_SETS = ["set_blade", "set_blunt", "set_unarmed"]
const RANGED_ONLY_SETS = ["set_gun"]
# 词条之外的随机类别权重（"可能"类别为 1）
const RANDOM_SET_W = 0.15

var _bases: Dictionary = {}		# 类型 -> 各家族最低稀有度的原版武器
var _second_w: Dictionary = {}	# 属性 -> 权重（第二条 / 非伤害主加成）
var _common: Dictionary = {}	# 类型 -> 非传奇原版武器（暴击、射程、吸血等独立抽取的来源）
var _shares: Dictionary = {}	# 类型 -> {稀有度: [加成部分 / 每次命中伤害]}（原版非传奇武器，已排序）
var _sec_coefs: Dictionary = {}	# 属性 -> [原版附加加成系数（最低一级）]
var _crit_pool: Dictionary = {}	# 类型 -> {是否高暴击: [[暴击率, 暴伤]]}（原版非传奇武器，不含标枪模板）
var _hi_crit_share: Dictionary = {}	# 类型 -> 原版高暴击武器的比例
var _up_r: Array = [1.0, 1.25, 1.5, 2.0]	# 原版 4 级家族逐级基础伤害相对最低一级的倍率（中位数）
# 更高稀有度的生成方式：step = 逐级随机提升，interp = 由最高一级插值；最低一级随机组合的个数（实验用）
var upgrade_mode := "interp"
var deep_tries := DEEP_TRIES
var _sets: Dictionary = {}		# set my_id -> SetData
var _set_native_count: Dictionary = {}
var _fx_share: Array = [1.0, 0.6, 0.1]	# 原版（非传奇）武器家族：[-, 至少 1 条效果的比例, 2 条以上的比例]
var _effectful: Array = []		# 有（可搬运的）效果的家族


# 原版只有 T4 的传奇武器家族（补出低级版本时不算）
func _is_legendary(lo) -> bool:
	return not lo.has_meta("aa_low_of") and wv.legendary_families.has(family_of(lo))


static func is_slow(st) -> bool:
	return WeaponValue.cooldown_seconds(st) >= SLOW_COOLDOWN


func _collect_deep_priors() -> void:
	_bases = {0: [], 1: []}
	_second_w = {}
	_common = {0: [], 1: []}
	_shares = {0: {}, 1: {}}
	_sec_coefs = {}
	_crit_pool = {0: {true: [], false: []}, 1: {true: [], false: []}}
	var counts = {}
	for f in fam_names:
		var fam = families[f]
		var natives = []
		for t in fam.tiers:
			if not fam.tiers[t].has_meta("aa_low_of"):
				natives.push_back(t)
		if natives.empty():
			continue
		natives.sort()
		var lo = fam.tiers[natives[0]]
		var hi = fam.tiers[natives[-1]]
		_bases[fam.type].push_back(lo)
		var sc = lo.stats.scaling_stats
		# 只有 T4 的传奇武器（王者之剑 +200% 最大生命……）不进系数 / 占比 / 独立抽取的来源
		if _is_legendary(lo):
			sc = []
		else:
			_common[fam.type].push_back(lo)
			if not is_javelin_template(lo.stats):
				_crit_pool[fam.type][is_high_crit(lo.stats)].push_back([float(lo.stats.crit_chance), float(lo.stats.crit_damage)])
			for t in natives:
				var w = fam.tiers[t]
				var hit = WeaponValue.hit_damage(float(w.stats.damage), w.stats.scaling_stats, t)
				if hit > 0:
					if not _shares[fam.type].has(t):
						_shares[fam.type][t] = []
					_shares[fam.type][t].push_back(WeaponValue.hit_damage(0.0, w.stats.scaling_stats, t) / hit)
		for i in sc.size():
			var st = WeaponValue.stat_name(sc[i][0])
			var c = float(sc[i][1])
			if c <= 0:
				continue
			if i > 0 or not st in DAMAGE_STATS:
				if not _sec_coefs.has(st):
					_sec_coefs[st] = []
				_sec_coefs[st].push_back(c)
				counts[st] = counts.get(st, 0) + 1
		for set in lo.sets:
			_sets[set.my_id] = set
			_set_native_count[set.my_id] = _set_native_count.get(set.my_id, 0) + 1
	# 只用当前可用的属性（未启用 DLC 时没有诅咒：原版计算伤害时会读到空值）：
	# 玩家属性表里有的，或当前加载的原版武器用过的
	var keys = PlayerRunData.init_effects()
	var used = {}
	for f in fam_names:
		for t in families[f].tiers:
			for x in families[f].tiers[t].stats.scaling_stats:
				used[WeaponValue.stat_name(x[0])] = true
	for st in SCALING_STATS:
		if keys.has(Keys.generate_hash(st)) or used.has(st):
			_second_w[st] = float(counts.get(st, 0)) + SCALING_BASE_W
	for ty in _shares:
		for t in _shares[ty]:
			_shares[ty][t].sort()
	for ty in _crit_pool:
		var n = _crit_pool[ty][true].size() + _crit_pool[ty][false].size()
		_hi_crit_share[ty] = float(_crit_pool[ty][true].size()) / max(1, n)
	var rs = [[], [], [], []]
	for f in fam_names:
		var tw = families[f].tiers
		if tw.size() == 4 and not tw[0].has_meta("aa_low_of") and int(tw[0].stats.damage) > 0:
			for t in 4:
				rs[t].push_back(float(tw[t].stats.damage) / float(tw[0].stats.damage))
	if not rs[3].empty():
		for t in 4:
			_up_r[t] = _median_of(rs[t])
	_effectful = []
	var n_all = 0
	var n1 = 0
	var n2 = 0
	for f in fam_names:
		var lo2 = _closest_tier(families[f].tiers, 0)
		if lo2.has_meta("aa_low_of"):
			lo2 = lo2.get_meta("aa_low_of")
		var n = 0
		for e in lo2.effects:
			if not bound_key(e):
				n += 1
		if n > 0:
			_effectful.push_back(f)
		if not _is_legendary(lo2):
			n_all += 1
			if n >= 1:
				n1 += 1
			if n >= 2:
				n2 += 1
	if n_all > 0:
		_fx_share = [1.0, float(n1) / n_all, float(n2) / n_all]


func _pick_base(ty: int):
	var arr: Array = _common[ty]
	return arr[rng.randi() % arr.size()]


# 攻击节奏（冷却、伤害、多发、换弹）来自同一把原版武器：同类型、价格最接近（最低一级的价格）的 PROFILE_POOL 把，
# 慢速武器（手感差，通常不会选用）的权重只有 SLOW_PROFILE_W
const PROFILE_POOL = 8


func _pick_profile(ty: int, price: float, tier: int):
	var arr = []
	for b in _bases[ty]:
		# 按同一稀有度的价格比较（传奇武器的 T4 价格不能和别的家族的最低一级价格比，否则总是挑到最贵的慢速重武器）
		var bp = float(_closest_tier(families[family_of(b)].tiers, tier).value)
		arr.push_back([abs(log(max(1.0, bp) / max(1.0, price))), b])
	arr.sort_custom(self, "_sort_first")
	var w = {}
	for i in min(PROFILE_POOL, arr.size()):
		w[i] = SLOW_PROFILE_W if is_slow(arr[i][1].stats) else 1.0
	return arr[int(_pick_w(w))][1]


static func _median_of(a: Array) -> float:
	var b = a.duplicate()
	b.sort()
	return b[b.size() / 2]


static func _sort_first(a, b) -> bool:
	return a[0] < b[0]


func _pick_w(weights: Dictionary):
	var total = 0.0
	for k in weights:
		total += weights[k]
	var x = rng.randf() * total
	for k in weights:
		x -= weights[k]
		if x <= 0:
			return k
	return weights.keys()[0]


# 原版系数池里抽一个；没有原版数据的属性按与近战伤害的参考属性之比折算（主加成约 0.5 近战、附加约 0.3）
func _coef_from(pool: Array, st: String, melee_equiv: float) -> float:
	if pool.size() > 0:
		return pool[rng.randi() % pool.size()]
	var c = melee_equiv * WeaponValue.stat_ref("stat_melee_damage") / WeaponValue.stat_ref(st)
	return max(0.01, stepify(c * rng.randf_range(0.7, 1.3), 0.01))


# 加成属性（每个家族先定，避免择优时偏向系数小的属性）：主加成大多是本类型的伤害，少数武器有附加加成
func _pick_scaling_stats(ty: int) -> Array:
	var main = _pick_w(MAIN_SCALING[ty])
	if main != "none" and not _second_w.has(main):
		main = "stat_melee_damage" if ty == 0 else "stat_ranged_damage"
	if main == "none":
		var w = _second_w.duplicate()
		for d in DAMAGE_STATS:
			w.erase(d)
		main = _pick_w(w)
	var out = [main]
	if rng.randf() < SECOND_SCALING_CHANCE[ty]:
		var w2 = _second_w.duplicate()
		w2.erase(main)
		out.push_back(_pick_w(w2))
	return out


func generate_deep() -> Dictionary:
	_collect_deep_priors()
	_sample_prices()
	var out = {}
	var fam_sets = {}
	for f in fam_names:
		var fam = families[f]
		var mult = _family_mult(f)
		rng.seed = hash(str(seed_value) + "/wdeep/" + f)
		# 加成属性先定（避免择优时偏向系数小的属性）
		var stats = _pick_scaling_stats(fam.type)
		var tiers = fam.tiers.keys()
		tiers.sort()
		var prev = _deep_base(fam, mult, stats, tiers[0])
		out[fam.tiers[tiers[0]].my_id] = prev
		if upgrade_mode == "interp":
			var res = _deep_interp(fam, prev, tiers, mult)
			for i in tiers.size():
				out[fam.tiers[tiers[i]].my_id] = res[i]
		else:
			for i in range(1, tiers.size()):
				prev = _deep_up(fam, prev, tiers[i], mult)
				out[fam.tiers[tiers[i]].my_id] = prev
		fam_sets[f] = _pick_sets(fam, out)
	_ensure_set_minimum(fam_sets)
	for f in fam_names:
		for tier in families[f].tiers:
			var id = families[f].tiers[tier].my_id
			if out.has(id):
				out[id]["sets"] = fam_sets[f]
	return out


# 深度重组的价格重新抽样：整个家族沿用一个原版家族的价格阶梯（同类型、最低稀有度相同的原版家族中随机一个；
# 不足 2 个时不限类型），所以同为 T4，最低 T1 < 最低 T2 < 最低 T3 < 传奇。砖头（会碎裂）价格固定。
# 补出的低级武器按相邻稀有度的价格比例从上一级递减。目标价值按新价格估计
var _price: Dictionary = {}


func _price_of(w) -> float:
	return float(_price.get(w.my_id, w.value))


static func _native_ladder(fam: Dictionary) -> Dictionary:
	var lad = {}
	for t in fam.tiers:
		if not fam.tiers[t].has_meta("aa_low_of"):
			lad[t] = float(fam.tiers[t].value)
	return lad


static func _is_brick(fam: Dictionary) -> bool:
	for t in fam.tiers:
		for e in fam.tiers[t].effects:
			if WeaponValue.effect_key(e) == "break_on_hit":
				return true
	return false


func _sample_prices() -> void:
	_price = {}
	var ladders = []
	for f in fam_names:
		var lad = _native_ladder(families[f])
		if not lad.empty() and not _is_brick(families[f]):
			ladders.push_back({"type": families[f].type, "min": lad.keys().min(), "lad": lad})
	var natives = []
	for f in fam_names:
		for t in families[f].tiers:
			natives.push_back(families[f].tiers[t])
	var ratios = price_ratios(natives)
	for f in fam_names:
		var fam = families[f]
		var own = _native_ladder(fam)
		if own.empty() or _is_brick(fam):
			continue
		var lo: int = own.keys().min()
		var same = []
		var any = []
		for l in ladders:
			if l.min != lo:
				continue
			var covers = true
			for t in own:
				if not l.lad.has(t):
					covers = false
			if not covers:
				continue
			any.push_back(l)
			if l.type == fam.type:
				same.push_back(l)
		var pool = same if same.size() >= 2 else any
		if pool.empty():
			continue
		rng.seed = hash(str(seed_value) + "/wprice/" + f)
		var lad: Dictionary = pool[rng.randi() % pool.size()].lad
		for t in own:
			_price[fam.tiers[t].my_id] = lad[t]
		# 补出的低级武器：从最低的原版稀有度往下按比例递减
		for t in range(lo - 1, -1, -1):
			if fam.tiers.has(t) and fam.tiers.has(t + 1):
				_price[fam.tiers[t].my_id] = max(1.0, _price_of(fam.tiers[t + 1]) * float(ratios[fam.type][t]))


# 最低一级：价格已定（_sample_prices），先定攻击节奏（价格相近的原版武器）与高 / 低暴击，
# 再随机 DEEP_TRIES 组其余数值（基础伤害与加成的比例、加成系数、暴击、射程 / 贯穿 / 弹跳 / 吸血、效果），
# 每组按价值解出每次命中伤害（攻速越慢、每次伤害越高）；取第一组面板自然、价值不超过目标且接近目标的，
# 没有时取价值不超过目标中最高的一组（面板自然的优先），都超过时取价值最低的
func _deep_base(fam: Dictionary, mult: float, stats: Array, tier: int) -> Dictionary:
	var tw = fam.tiers[tier]
	var want = _want(tw, true) * mult
	# 不取"最接近目标"的一组：价值步长越细（加成占比高、没有贯穿 / 效果……）越容易贴近目标，择优会让分布偏向这类组合；
	# 同理，构成（攻击节奏、射程 / 贯穿 / 弹跳 / 吸血、效果条数）在模板里先定，否则"先满足条件"会偏向效果少、没有贯穿的组合。
	# 依次抽取，取第一组面板自然、价值在目标的 [1 - PICK_BAND, 1] 内的；构成实在不合适（一组都不满足）时换一次构成，仍不满足再择优
	var cands = []
	for _t in DEEP_TEMPLATES:
		var tpl = _deep_template(fam, tw, tier)
		for _k in deep_tries:
			var c = _deep_candidate(fam, tw, tier, want, stats, tpl)
			if c.natural and c.value <= c.out.want and c.value >= c.out.want * (1.0 - PICK_BAND):
				c.out["price"] = int(round(_price_of(tw)))
				return c.out
			cands.push_back(c)
	var pick = null
	for natural_only in [true, false]:
		for c in cands:
			if (natural_only and not c.natural) or c.value > c.out.want:
				continue
			if pick == null or c.value > pick.value:
				pick = c
		if pick != null:
			break
	if pick == null:
		for c in cands:
			if pick == null or c.value < pick.value:
				pick = c
	pick.out["price"] = int(round(_price_of(tw)))
	return pick.out


# 最低一级的构成（各组共用）：攻击节奏、高 / 低暴击、射程 / 击退 / 吸血 / 出招方式 / 投射物 / 贯穿 / 弹跳、效果条数（是否含道具效果）
func _deep_template(fam: Dictionary, tw, tier: int) -> Dictionary:
	var ty: int = fam.type
	var prof_w = _pick_profile(ty, _price_of(tw), tier)
	var prof = prof_w.stats
	var bp = tw.stats.duplicate()
	bp.cooldown = prof.cooldown
	bp.recoil_duration = prof.recoil_duration
	var b = _pick_base(ty).stats
	bp.max_range = b.max_range
	# 有最小攻击范围的武器（鱼叉枪）：最大范围再加上最小范围
	if int(bp.min_range) > 0:
		bp.max_range = int(b.max_range) + int(bp.min_range)
	# 击退：原版大多很小（中位数 2），远程常为 0；截到近战 15 / 远程 8（原版拳、双管霰弹枪）（太高把怪打飞往往是负面作用），不计入价值
	bp.knockback = int(min(b.knockback, KB_CAP[ty]))
	bp.lifesteal = _pick_base(ty).stats.lifesteal
	if ty == 0:
		b = _pick_base(ty).stats
		bp.attack_type = b.attack_type
		bp.alternate_attack_type = b.alternate_attack_type
	else:
		bp.nb_projectiles = prof.nb_projectiles
		bp.projectile_spread = prof.projectile_spread
		bp.additional_cooldown_every_x_shots = prof.additional_cooldown_every_x_shots
		bp.additional_cooldown_multiplier = prof.additional_cooldown_multiplier
		b = _pick_base(ty).stats
		# 火焰喷射器 / 歼灭者 / 粒子加速器的 99 贯穿属于它们的投射物，不单独抽取
		if int(b.piercing) < 50:
			bp.piercing = b.piercing
			bp.piercing_dmg_reduction = b.piercing_dmg_reduction
		else:
			bp.piercing = 0
		b = _pick_base(ty).stats
		bp.bounce = b.bounce
		bp.bounce_dmg_reduction = b.bounce_dmg_reduction
	# 额外效果的条数：按原版有效果的武器比例 × "额外效果"滑条（100% ≈ 原版）抽取；
	# 攻击节奏有定义性效果时它占一条；其余每条是一个有效果的随机家族（可跨类型）或一条道具效果
	var fx_mult = float(cfg.get("w_effects", 125)) / 100.0
	var n_fx = 0
	var u = rng.randf()
	if u < min(0.95, _fx_share[1] * fx_mult):
		n_fx = 1
		if u < min(0.5, _fx_share[2] * fx_mult):
			n_fx = 2
	var prof_fam = families.get(family_of(prof_w))
	var defining = prof_fam != null and _has_defining_effect(prof_w)
	if defining:
		n_fx = max(1, n_fx)
	var n_donor = 1 if defining else 0
	var want_item = false
	while n_donor + (1 if want_item else 0) < n_fx:
		if not want_item and gen != null and cfg.get("w_item_effects", false) and rng.randf() < ITEM_SLOT_SHARE:
			want_item = true
		elif not _effectful.empty():
			n_donor += 1
		else:
			break
	return {"bp": bp, "prof_fam": prof_fam if defining else null, "n_donor": n_donor, "want_item": want_item, "hi_crit": rng.randf() < float(_hi_crit_share[ty])}


func _deep_candidate(fam: Dictionary, tw, tier: int, want: float, stats: Array, tpl: Dictionary) -> Dictionary:
	var ty: int = fam.type
	var f = family_of(tw)
	var bp = tpl.bp.duplicate()
	var hi_crit: bool = tpl.hi_crit
	# 暴击：同类型原版武器的高 / 低暴击模板（标枪的 0% 暴击 + 高暴伤模板只随标枪效果出现）
	var pool: Array = _crit_pool[ty][hi_crit]
	if pool.empty():
		pool = _crit_pool[ty][not hi_crit]
	var cr = pool[rng.randi() % pool.size()] if not pool.empty() else [0.03, 2.0]
	bp.crit_chance = cr[0]
	bp.crit_damage = cr[1]
	var sec_base = 0.0
	if stats.size() > 1:
		sec_base = _coef_from(_sec_coefs.get(stats[1], []), stats[1], 0.3)
	var donors = []
	if tpl.prof_fam != null:
		donors.push_back(tpl.prof_fam)
	while donors.size() < tpl.n_donor:
		donors.push_back(families[_effectful[rng.randi() % _effectful.size()]])
	var want_item: bool = tpl.want_item
	var effects = []
	var keys = []
	for e in tw.effects:
		if bound_key(e):
			effects.push_back(_vary_fixed(e, f))
	var jav_cd = 0.0
	for dn in donors:
		var dw = _closest_tier(dn.tiers, tier)
		for e in dw.effects:
			var key = WeaponValue.effect_key(e)
			if bound_key(e) or key in keys or (ranged_only(e) and ty == 0):
				continue
			keys.push_back(key)
			if key == JAVELIN_KEY:
				jav_cd = float(dw.stats.crit_damage)
			effects.push_back(_vary_fixed(_adapt(_convert_explosion(e.duplicate(), ty), tw), f))
	var st = _bind_javelin(bp, effects, jav_cd)
	if want_item:
		var line = _item_effect(_item_spec(f, _spec_scaling(stats), true), tier, want)
		if line != null:
			effects.push_back(line)
	var excess = _downside_excess(want, effects)
	want -= excess
	var plan = {
		"stats": stats, "s": _share_at(ty, tier, rng.randf()), "sec": sec_base,
		"slow": is_slow(st), "base_min": _base_min(st, stats, effects, tier),
	}
	var natural = true
	# 效果占比超出上限：缩小效果数值（一次）
	var h = _solve_hit(st, plan, effects, tier, want)
	var final = _build(st, plan, tier, h)
	var fx = wv.value(final, effects, tier) - wv.value(final, [], tier)
	if fx > FX_SHARE_CAP * want:
		effects = _scale_effects(effects, FX_SHARE_CAP * want / fx)
		h = _solve_hit(st, plan, effects, tier, want)
		final = _build(st, plan, tier, h)
		fx = wv.value(final, effects, tier) - wv.value(final, [], tier)
		natural = fx <= FX_SHARE_CAP * want * 1.2
	# 基础伤害仍不到下限：再缩小一次效果
	if float(final.damage) < plan.base_min and fx > 0:
		effects = _scale_effects(effects, 0.5)
		h = _solve_hit(st, plan, effects, tier, want)
		final = _build(st, plan, tier, h)
	# 基础伤害不到下限、单次伤害远超该阶段敌人生命：面板不自然
	if float(final.damage) < plan.base_min:
		natural = false
	if WeaponValue.hit_damage(float(final.damage), final.scaling_stats, tier) * WeaponValue.crit_factor(final) > HIT_CAP * WeaponValue.OVERKILL_HP[clamp(tier, 0, 3)]:
		natural = false
	var donor_id = _closest_tier(donors[0].tiers, tier).my_id if not donors.empty() else ""
	return {
		"value": wv.value(final, effects, tier), "natural": natural,
		"out": {"effects": effects, "stats": final, "donor": donor_id, "scale": h, "want": want, "capped": excess > 0},
	}


# 更高一级：在低一级的基础上随机提升——各加成系数以 COEF_UP_CHANCE、冷却与贯穿 / 弹跳 / 吸血 / 射程 / 击退各以 UP_CHANCE 的概率提升（否则不变），
# 高暴击武器的暴击必定提升（否则不变）；效果按剩余的价值差额必定提升（每条至少强一步），
# 基础伤害（DMG_UP_CHANCE，或效果补完后仍差得多时）补足其余；最后按实际价值重新定价（砖头价格固定）
func _deep_up(fam: Dictionary, prev: Dictionary, tier: int, mult: float) -> Dictionary:
	var tw = fam.tiers[tier]
	var st = prev.stats.duplicate()
	var ty: int = fam.type
	if rng.randf() < UP_CHANCE:
		st.cooldown = int(max(WeaponValue.MIN_CD_FRAMES, min(int(st.cooldown) - 1, round(float(st.cooldown) * rng.randf_range(0.85, 0.95)))))
	var sc = []
	for i in st.scaling_stats.size():
		var x = st.scaling_stats[i]
		var c = float(x[1])
		if c > 0 and rng.randf() < COEF_UP_CHANCE:
			var cap = INF
			if i > 0:
				cap = SEC_COEF_CAP
			else:
				cap = SLOW_COEF_CAP if is_slow(st) else MAIN_COEF_CAP
			cap *= WeaponValue.stat_ref("stat_melee_damage") / WeaponValue.stat_ref(WeaponValue.stat_name(x[0]))
			c = max(c, min(cap, max(c + 0.05, stepify(c * rng.randf_range(1.1, 1.3), 0.05))))
		sc.push_back([x[0], c])
	st.scaling_stats = sc
	if not WeaponValue.is_melee(st):
		if int(st.piercing) > 0 and int(st.piercing) < 50 and rng.randf() < UP_CHANCE:
			st.piercing = int(st.piercing) + 1
		if int(st.bounce) > 0 and rng.randf() < UP_CHANCE:
			st.bounce = int(st.bounce) + 1
	if float(st.lifesteal) > 0 and rng.randf() < UP_CHANCE:
		st.lifesteal = stepify(float(st.lifesteal) + rng.randf_range(0.01, 0.03), 0.01)
	if rng.randf() < UP_CHANCE:
		st.max_range = int(stepify(float(st.max_range) * rng.randf_range(1.05, 1.12), 5.0))
	if int(st.knockback) > 0 and rng.randf() < UP_CHANCE:
		st.knockback = int(min(int(st.knockback) + 1, KB_CAP[ty]))
	if is_high_crit(st):
		st.crit_chance = min(1.0, stepify(float(st.crit_chance) + rng.randf_range(0.02, 0.05), 0.01))
		if rng.randf() < 0.5:
			st.crit_damage = stepify(float(st.crit_damage) + 0.25, 0.05)
	var dmg_up = rng.randf() < DMG_UP_CHANCE
	var effects: Array = prev.effects
	var want = _want(tw, true) * mult
	var excess = _downside_excess(want, effects)
	want -= excess
	if not effects.empty():
		var cur = wv.value(st, effects, tier)
		var fx0 = cur - wv.value(st, [], tier)
		# 基础伤害也提升时，效果按它占当前价值的比例分摊差额；否则效果承担全部差额
		var share = clamp(fx0 / max(1.0, cur), 0.0, 1.0) if dmg_up else 1.0
		effects = _grow_effects(st, effects, tier, fx0 + max(0.0, want - cur) * share)
	# 基础伤害低于该稀有度的下限时也必定提升
	var names = []
	for x in st.scaling_stats:
		names.push_back(WeaponValue.stat_name(x[0]))
	var bmin = _base_min(st, names, effects, tier)
	if dmg_up or float(st.damage) < bmin or wv.value(st, effects, tier) < want * (1.0 - DMG_FORCE_GAP):
		st.damage = _fill_damage(st, effects, tier, want, int(max(int(st.damage) + 1, ceil(bmin))))
	var got = wv.value(st, effects, tier)
	var price = _price_of(tw)
	if not _is_brick(fam):
		var vp = float(_vp.get(str(ty) + "/" + str(tier), 1.0))
		price = max(float(prev.price) + 1.0, (got + excess) / max(0.01, vp * mult))
	return {"effects": effects, "stats": st, "donor": prev.donor, "scale": 1.0, "want": got, "capped": excess > 0, "price": int(round(price))}


# 方案 B（插值）：由最低一级估出最高一级——价格按价格阶梯、效果价值按它在最低一级总价值中的占比（至多放大 FX_TOP_CAP 倍，不低于逐级各强一步），
# 伤害、加成系数、（高暴击武器的）暴击按同一个增长量 g 放大，使最高一级价值达标；
# 中间各级按原版逐级的伤害比例（_up_r）插值。攻速每级略快；射程：远程每级 +50，射程大的近战每级 +25；
# 吸血每级 +5%；弹跳每级 +1、贯穿到最高一级共 +1（原本有的才加），投射物数不变。各级按实际价值重新定价
func _deep_interp(fam: Dictionary, base: Dictionary, tiers: Array, mult: float) -> Array:
	var lo: int = tiers[0]
	var top: int = tiers[-1]
	var st0 = base.stats
	var e0: Array = base.effects
	var v0 = wv.value(st0, e0, lo)
	var share = clamp((v0 - wv.value(st0, [], lo)) / max(1.0, v0), 0.0, 1.0)
	var want_top = _want(fam.tiers[top], true) * mult
	var P = {}
	for t in tiers:
		P[t] = (float(_up_r[t]) - float(_up_r[lo])) / max(0.01, float(_up_r[top]) - float(_up_r[lo]))
	var cd_step = rng.randf_range(0.93, 0.97)
	var g = 0.0
	var f = 1.0
	var chain = _fx_chain(e0, tiers, P, f)
	for _round in 2:
		g = _solve_g(st0, lo, top, P[top], cd_step, chain[top], want_top)
		if e0.empty():
			break
		var st_top = _interp_stats(st0, lo, top, P[top], g, cd_step)
		var base_v = wv.value(st_top, [], top)
		var target = share * want_top
		var f_lo = 1.0
		var f_hi = FX_TOP_CAP
		for _i in 10:
			var mid = (f_lo + f_hi) / 2.0
			if wv.value(st_top, _fx_chain(e0, tiers, P, mid)[top], top) - base_v <= target:
				f_lo = mid
			else:
				f_hi = mid
		f = f_lo
		chain = _fx_chain(e0, tiers, P, f)
	g = _solve_g(st0, lo, top, P[top], cd_step, chain[top], want_top)
	var res = [base]
	var prev = base
	for i in range(1, tiers.size()):
		var t: int = tiers[i]
		var st = _interp_stats(st0, lo, t, P[t], g, cd_step)
		var effects: Array = chain[t]
		var names = []
		for x in st.scaling_stats:
			names.push_back(WeaponValue.stat_name(x[0]))
		st.damage = int(max(max(int(st.damage), int(prev.stats.damage) + 1), ceil(_base_min(st, names, effects, t))))
		var got = wv.value(st, effects, t)
		var excess = _downside_excess(_want(fam.tiers[t], true) * mult, effects)
		var price = _price_of(fam.tiers[t])
		if not _is_brick(fam):
			var vp = float(_vp.get(str(fam.type) + "/" + str(t), 1.0))
			price = max(float(prev.price) + 1.0, (got + excess) / max(0.01, vp * mult))
		prev = {"effects": effects, "stats": st, "donor": base.donor, "scale": g, "want": got, "capped": excess > 0, "price": int(round(price))}
		res.push_back(prev)
	return res


# 加成系数、暴击率的相对增长 = 伤害相对增长 × 此值（原版升级主要加伤害，系数与暴击涨得慢）
const COEF_G = 0.5
const CRIT_G = 0.5
# 效果从最低一级到最高一级至多放大的倍数（原版效果逐级增长不多：爆炸 25%→40%、点燃 3→8）；暴击率每级至多 +10%
const FX_TOP_CAP = 3.0
# 加成系数从最低一级到最高一级至多放大的倍数（原版主加成最多约 ×1.5（左轮）、附加加成 ×2.5（镰刀收获））
const MAIN_TOP_GROWTH = 1.5
const SEC_TOP_GROWTH = 2.5
const CRIT_STEP_CAP = 0.1


func _interp_stats(st0, lo: int, t: int, p: float, g: float, cd_step: float):
	var st = st0.duplicate()
	var d = t - lo
	st.damage = int(max(1, round(float(st0.damage) * (1.0 + g * p))))
	var sc = []
	for i in st0.scaling_stats.size():
		var x = st0.scaling_stats[i]
		var c = float(x[1])
		if c > 0:
			var cap = INF
			if i > 0:
				cap = SEC_COEF_CAP
			else:
				cap = SLOW_COEF_CAP if is_slow(st0) else MAIN_COEF_CAP
			cap *= WeaponValue.stat_ref("stat_melee_damage") / WeaponValue.stat_ref(WeaponValue.stat_name(x[0]))
			cap = min(cap, float(x[1]) * (SEC_TOP_GROWTH if i > 0 else MAIN_TOP_GROWTH))
			c = max(c, min(cap, stepify(c * (1.0 + COEF_G * g * p), 0.05)))
		sc.push_back([x[0], c])
	st.scaling_stats = sc
	if is_high_crit(st0):
		st.crit_chance = min(min(1.0, float(st0.crit_chance) + CRIT_STEP_CAP * d), stepify(float(st0.crit_chance) * (1.0 + CRIT_G * g * p), 0.01))
	st.cooldown = int(max(WeaponValue.MIN_CD_FRAMES, round(float(st0.cooldown) * pow(cd_step, d))))
	if WeaponValue.is_melee(st0):
		if int(st0.max_range) >= 200:
			st.max_range = int(st0.max_range) + 25 * d
	else:
		st.max_range = int(st0.max_range) + 50 * d
		if int(st0.bounce) > 0:
			st.bounce = int(st0.bounce) + d
		if int(st0.piercing) > 0 and int(st0.piercing) < 50:
			st.piercing = int(st0.piercing) + int(round(p))
	if float(st0.lifesteal) > 0:
		st.lifesteal = float(st0.lifesteal) + 0.05 * d
	return st


func _solve_g(st0, lo: int, top: int, p: float, cd_step: float, effects: Array, want: float) -> float:
	if wv.value(_interp_stats(st0, lo, top, p, 0.0, cd_step), effects, top) >= want:
		return 0.0
	var g_lo = 0.0
	var g_hi = 50.0
	for _i in 20:
		var mid = (g_lo + g_hi) / 2.0
		if wv.value(_interp_stats(st0, lo, top, p, mid, cd_step), effects, top) <= want:
			g_lo = mid
		else:
			g_hi = mid
	return g_lo


# 各级效果：最低一级的效果按 1 + (f - 1) × P 放大，且比低一级强一步以上
func _fx_chain(e0: Array, tiers: Array, P: Dictionary, f: float) -> Dictionary:
	var out = {tiers[0]: e0}
	var prev = e0
	for i in range(1, tiers.size()):
		var t = tiers[i]
		prev = _strengthen_effects(_scale_effects(e0, 1.0 + (f - 1.0) * P[t]), prev)
		out[t] = prev
	return out


# 基础伤害：至少 dmin，取价值不超过 want 的最大值
func _fill_damage(st, effects: Array, tier: int, want: float, dmin: int) -> int:
	var probe = st.duplicate()
	probe.damage = dmin
	if wv.value(probe, effects, tier) >= want:
		return dmin
	var lo = dmin
	var hi = dmin * 2 + 10
	probe.damage = hi
	while wv.value(probe, effects, tier) < want and hi < 100000:
		lo = hi
		hi *= 2
		probe.damage = hi
	while hi - lo > 1:
		var mid = (lo + hi) / 2
		probe.damage = mid
		if wv.value(probe, effects, tier) <= want:
			lo = mid
		else:
			hi = mid
	return lo


# 效果放大到效果价值约为 target（至多 FX_GROWTH_CAP 倍），且每条都比低一级强一步以上
func _grow_effects(st, effects: Array, tier: int, target: float) -> Array:
	var base = wv.value(st, [], tier)
	var best = _strengthen_effects(effects, effects)
	if wv.value(st, best, tier) - base >= target:
		return best
	var lo = 1.0
	var hi = FX_GROWTH_CAP
	for _i in 10:
		var mid = (lo + hi) / 2.0
		var cand = _strengthen_effects(_scale_effects(effects, mid), effects)
		if wv.value(st, cand, tier) - base <= target:
			lo = mid
			best = cand
		else:
			hi = mid
	return best


func _base_min(st, stats: Array, effects: Array, tier: int) -> float:
	if "stat_harvesting" in stats:
		return 1.0
	for e in effects:
		if WeaponValue.effect_id(e) == "weapon_burning":
			return 1.0
	var n = 1
	if not WeaponValue.is_melee(st):
		n = max(1, int(st.nb_projectiles))
	return BASE_DMG_MIN[clamp(tier, 0, 3)] / sqrt(float(n))


func _spec_scaling(stats: Array) -> Array:
	var out = []
	for x in stats:
		out.push_back([Keys.generate_hash(x), 1.0])
	return out


# 攻击节奏的定义性效果：没有它们，原版武器的冷却 / 伤害就说不通（喇叭枪的慢冷却靠捡材料换弹、榴弹炮的低伤害靠爆炸）
const DEFINING_IDS = ["weapon_exploding", "weapon_burning", "weapon_projectiles_on_hit"]
const DEFINING_KEYS = ["reload_when_pickup_gold"]


static func _has_defining_effect(w) -> bool:
	for e in w.effects:
		if WeaponValue.effect_id(e) in DEFINING_IDS or WeaponValue.effect_key(e) in DEFINING_KEYS:
			return true
	return false


# 原版同类型同稀有度武器的"加成部分 / 每次命中伤害"在分位数 q 处的值（缺档用相邻档）
func _share_at(ty: int, tier: int, q: float) -> float:
	for dt in [0, -1, 1, -2, 2, -3, 3]:
		var arr: Array = _shares[ty].get(tier + dt, [])
		if not arr.empty():
			return arr[int(clamp(floor(q * arr.size()), 0, arr.size() - 1))]
	return 0.5


# 每次命中伤害 H 拆成基础伤害 + 加成：加成部分 = s × H；附加加成至多占一半；系数受上限与下限（SCALING_FLOOR）约束
func _build(st, plan: Dictionary, tier: int, h: float, into = null):
	var s = into if into != null else st.duplicate()
	var stats: Array = plan.stats
	var scal = plan.s * h
	var ref1 = WeaponValue.stat_ref(stats[0], tier)
	var c2 = 0.0
	var sec_val = 0.0
	if stats.size() > 1:
		var ref2 = WeaponValue.stat_ref(stats[1], tier)
		c2 = min(plan.sec, SEC_COEF_CAP * WeaponValue.stat_ref("stat_melee_damage", tier) / ref2)
		c2 = min(c2, 0.5 * scal / ref2)
		c2 = min(c2, max(0.0, h - plan.base_min) / ref2)
		c2 = max(SCALING_FLOOR.get(stats[1], 0.05), stepify(c2, 0.01))
		sec_val = c2 * ref2
	var c1 = max(0.0, scal - sec_val) / ref1
	c1 = min(c1, (SLOW_COEF_CAP if plan.slow else MAIN_COEF_CAP) * WeaponValue.stat_ref("stat_melee_damage", tier) / ref1)
	# 保证基础伤害下限：加成只能占下限之外的部分（逐级增长约束让位于此）
	c1 = min(c1, max(0.0, h - plan.base_min - sec_val) / ref1)
	c1 = max(SCALING_FLOOR.get(stats[0], 0.05), stepify(c1, 0.01))
	var sc = [[Keys.generate_hash(stats[0]), c1]]
	if stats.size() > 1:
		sc.push_back([Keys.generate_hash(stats[1]), c2])
	s.scaling_stats = sc
	s.damage = int(max(1, round(h - c1 * ref1 - sec_val)))
	return s


# 解出每次命中伤害 H，使价值不超过 want 且尽量接近（价值随 H 单调）
func _solve_hit(st, plan: Dictionary, effects: Array, tier: int, want: float) -> float:
	var lo = 1.0
	var hi = 3000.0
	# 求解时复用同一个属性对象（复制 WeaponStats 会排队延迟调用，大量复制很慢）
	var probe = st.duplicate()
	if wv.value(_build(st, plan, tier, hi, probe), effects, tier) < want:
		return hi
	if wv.value(_build(st, plan, tier, lo, probe), effects, tier) > want:
		return lo
	for _i in 20:
		var mid = sqrt(lo * hi)
		if wv.value(_build(st, plan, tier, mid, probe), effects, tier) < want:
			lo = mid
		else:
			hi = mid
	return lo


# 按比例缩放效果的数值（属性 / 几率 / 次数等线性数值；爆炸几率、点燃伤害、命中射出投射物的数量）
#   道具效果一起缩放（记下的价值按比例）；放大时代价（负值）不动；碎裂、自伤、区域减速、开关、建筑不动
static func _scale_effects(effects: Array, f: float) -> Array:
	var out = []
	for e in effects:
		var key = WeaponValue.effect_key(e)
		if key in NO_STRENGTHEN_KEYS or key.begins_with("structure:") or not "value" in e:
			out.push_back(e)
			continue
		if f > 1.0 and int(e.value) < 0:
			out.push_back(e)
			continue
		var ne = _dup(e)
		var id = WeaponValue.effect_id(ne)
		if id == "weapon_exploding":
			ne.chance = clamp(stepify(float(ne.chance) * f, 0.05), 0.05, max(1.0, float(e.chance)))
		elif id == "weapon_burning" and ne.burning_data != null:
			ne.burning_data = ne.burning_data.duplicate()
			ne.burning_data.damage = int(max(1, round(ne.burning_data.damage * f)))
		elif id == "weapon_projectiles_on_hit":
			ne.value = int(max(1, round(ne.value * f)))
		elif WeaponValue.effect_key(ne) in ["effect_gain_stat_every_killed_enemies", "modify_every_x_projectile"]:
			# "每 X 次"：X 越大越弱
			ne.value = int(max(1, round(ne.value / max(0.05, f))))
		elif abs(int(ne.value)) >= 2 or (f > 1.0 and int(ne.value) != 0):
			ne.value = int(sign(ne.value) * max(1, round(abs(ne.value) * f)))
		if e.has_meta("aa_value") and int(e.value) != 0:
			ne.set_meta("aa_value", float(e.get_meta("aa_value")) * float(ne.value) / float(e.value))
		out.push_back(ne)
	return out


# 爆炸效果按武器类型的写法：近战为"命中时 X% 几率爆炸"（伤害之外再炸一次），远程为"投射物 X% 几率爆炸"（爆炸代替直接伤害）
static func _convert_explosion(e, ty: int):
	if not e is ExplodingEffect:
		return e
	if ty == 0 and e.key != "effect_explode_melee":
		e.key = "effect_explode_melee"
		e.text_key = ""
		e.value = 1
		# 远程武器的必定爆炸到近战上按原版近战爆炸的几率上限
		e.chance = min(float(e.chance), 0.5)
	elif ty == 1 and e.key == "effect_explode_melee":
		e.key = "effect_explode" if float(e.chance) >= 1.0 else "effect_explode_custom"
		e.text_key = ""
	return e


# 只缩放伤害（加成系数不变）
func _solve_damage(st, effects: Array, tier: int, want: float) -> float:
	var lo = 0.02
	var hi = 50.0
	var probe = st.duplicate()
	probe.damage = int(max(1, round(st.damage * hi)))
	if wv.value(probe, effects, tier) < want:
		return hi
	probe.damage = int(max(1, round(st.damage * lo)))
	if wv.value(probe, effects, tier) > want:
		return lo
	for _i in 30:
		var mid = sqrt(lo * hi)
		probe.damage = int(max(1, round(st.damage * mid)))
		if wv.value(probe, effects, tier) < want:
			lo = mid
		else:
			hi = mid
	return sqrt(lo * hi)


# 效果里的暴击 / 元素属性不给词条（不决定精准 / 元素类别）；暴击词条只看武器面板，元素只看加成属性与燃烧
const EFFECT_NO_TAG_STATS = ["stat_crit_chance", "stat_elemental_damage"]


# 武器的词条：加成属性、暴击 / 吸血 / 慢速重击等特性、效果的词条、道具效果的属性
func weapon_tags(ty: int, st, effects: Array) -> Array:
	var tags = []
	for sc in st.scaling_stats:
		if float(sc[1]) > 0:
			tags.push_back(WeaponValue.stat_name(sc[0]))
	if is_high_crit(st):
		tags.push_back("stat_crit_chance")
	if float(st.lifesteal) > 0:
		tags.push_back("stat_lifesteal")
	if WeaponValue.cooldown_seconds(st) >= 1.6:
		tags.push_back("heavy")
	for e in effects:
		var id = WeaponValue.effect_id(e)
		var key = WeaponValue.effect_key(e)
		match id:
			"weapon_exploding":
				tags.push_back("explosive")
			"weapon_burning":
				tags.push_back("burning")
			"turret", "structure":
				tags.push_back("structure")
			"weapon_gain_stat_every_killed_enemies":
				tags.push_back("ethereal")
			"null_charm", "weapon_percent_damage_effect":
				tags.push_back("musical")
			"weapon_slow_on_hit", "weapon_slow_in_zone":
				tags.push_back("less_enemy_speed")
		match key:
			"gold_on_crit_kill":
				tags.push_back("economy")
			"reload_turrets_on_shoot":
				tags.push_back("structure")
			"burning_spread":
				tags.push_back("burning")
			"temp_stats_while_not_moving":
				tags.push_back("stand_still")
		if e.key in EFFECT_NO_TAG_STATS:
			continue
		if e.has_meta("aa_value") and not e is TriggerEffect and Catalog.STATS.has(e.key) and e.value > 0:
			tags.push_back(e.key)
		elif Catalog.STATS.has(e.key) and WeaponValue.is_plain_player_stat(e) and e.value > 0:
			tags.push_back(e.key)
	# 燃烧武器的主加成是元素伤害：优先元素类别；否则只是"可能"
	if not st.scaling_stats.empty() and WeaponValue.stat_name(st.scaling_stats[0][0]) == "stat_elemental_damage":
		for i in tags.size():
			if tags[i] == "burning":
				tags[i] = "burning_main"
	return tags


func _set_ok(id: String, ty: int) -> bool:
	if not _sets.has(id) or id == "set_legendary":
		return false
	if ty == 0 and id in RANGED_ONLY_SETS:
		return false
	if ty == 1 and id in MELEE_ONLY_SETS:
		return false
	return true


# 武器类别（1–2 个）：词条的"必定"类别优先（按词条顺序，主加成在前），其余按"可能"类别加权、再加少量随机。
# 传奇只属于原本只有 T4 的武器（补全低级武器时不出现）
func _pick_sets(fam: Dictionary, res: Dictionary) -> Array:
	var lo = _closest_tier(fam.tiers, 0)
	var p = res.get(lo.my_id)
	if p == null:
		return lo.sets
	var ty: int = fam.type
	var n = 2 if rng.randf() < SECOND_SET_CHANCE else 1
	var out = []
	if _is_legendary(lo) and _sets.has("set_legendary"):
		out.push_back("set_legendary")
	var tags = weapon_tags(ty, p.stats, p.effects)
	var may = {}
	var high = {}
	for t in tags:
		var m = TAG_SETS.get(t, {})
		for id in m.get("must", []):
			if _set_ok(id, ty) and not id in out:
				out.push_back(id)
		for id in m.get("high", []):
			if _set_ok(id, ty):
				high[id] = high.get(id, 0.0) + 1.0
		for id in m.get("may", []):
			if _set_ok(id, ty):
				may[id] = may.get(id, 0.0) + 1.0
	n = max(n, min(out.size(), 2))
	while out.size() > n:
		out.pop_back()
	for id in out:
		high.erase(id)
	while out.size() < n and not high.empty():
		var id = _pick_w(high)
		high.erase(id)
		out.push_back(id)
	while out.size() < n:
		var w = {}
		for id in _sets:
			if _set_ok(id, ty) and not id in out:
				w[id] = may.get(id, 0.0) + RANDOM_SET_W
		if w.empty():
			break
		out.push_back(_pick_w(w))
	var sets = []
	for id in out:
		sets.push_back(_sets[id])
	return sets


# 每个类别至少 MIN_SET_FAMILIES 个家族（不超过原版数量）：不足时补给只有一个类别、类型相符的家族
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
			if cur.size() >= 2 or _sets[id] in cur or not _set_ok(id, families[f].type):
				continue
			if cur.size() == 1 and cur[0].my_id == "set_legendary":
				continue
			cands.push_back([rng.randf(), f])
		# 元素是数组：Array.sort() 不能比较数组（正式版游戏会因排序越界闪退），按第一项排序
		cands.sort_custom(self, "_sort_first")
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
func _item_spec(f: String, scaling: Array, forced := false) -> Dictionary:
	if gen == null or not cfg.get("w_item_effects", false):
		return {}
	if not forced:
		rng.seed = hash(str(seed_value) + "/witem/" + f)
		if rng.randf() >= min(0.9, ITEM_LINE_CHANCE * float(cfg.get("w_effects", 125)) / 125.0):
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
		# 武器上的属性行按武器的属性行倍率估值（与原版武器一致）
		var sw = Catalog.stat_w(st) * wv.stat_line_mult
		var v = gen._round_to_unit(budget / sw, st)
		v = int(min(v, gen._line_cap(st, false)))
		var e = gen._stat_effect(st, -v if spec.neg else v)
		# 负系数相关的属性行（狼牙棒的 -攻速）：对这把武器是好处、对其他武器是代价，不计价值
		e.set_meta("aa_value", 0.0 if spec.neg else v * sw)
		return e
	var c: Dictionary = spec.clause.duplicate(true)
	var perm = Catalog.PERM_MULT[tier]
	c.value = int(max(1, round(float(c.value) * budget / max(0.1, float(spec.base)))))
	var te = TriggerEffect.make(c)
	te.set_meta("aa_value", abs(Valuation.clause_value(c, perm)))
	return te


# 武器的目标价值（未乘浮动）：仅重组效果时按原武器的模型估值（属性不变，模型误差相互抵消）；
# 深度重组与补出的低级武器 = 价格 × 同档原版武器"模型价值 / 价格"的中位数（属性全部重抽，不沿用原武器的模型误差）
var _vp: Dictionary = {}


func _want(w, by_price := false) -> float:
	# 砖头也按价格：碎裂在估值里按寿命折扣计（WeaponValue.life_mult）
	if by_price or w.has_meta("aa_low_of"):
		var v = _price_of(w) * float(_vp.get(str(w.type) + "/" + str(w.tier), 1.0))
		# 传奇武器（只有 T4 的原版武器）普遍超模、程度不等：取模型价值与按价格换算值的几何平均（链枪约 ×2）
		if not w.has_meta("aa_low_of") and wv.legendary_families.has(family_of(w)):
			v = sqrt(v * max(1.0, wv.value(w.stats, w.effects, w.tier)))
		return v
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
	var ratios = price_ratios(weapons)
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
			price *= ratios[base.type][t]
			var w = base.duplicate()
			w.my_id = base.weapon_id + "_" + str(t + 1)
			w.my_id_hash = Keys.generate_hash(w.my_id)
			w.weapon_id_hash = Keys.generate_hash(base.weapon_id)
			w.tier = t
			w.value = int(max(1, round(price)))
			w.stats = base.stats.duplicate()
			w.effects = _scaled_effects(base.effects, w.value / max(1.0, float(base.value)))
			w.upgrades_into = next
			w.set_meta("aa_low_of", base)
			out.push_back(w)
			next = w
	return out


# 补出低级版本时的效果：数值线性的效果（属性、几率、每 X 次……的 value ≥ 2）按价格比例缩小；
# 其余（开关、value 为 1 的效果、计入 power 的爆炸 / 点燃 / 投射物）保持原样，估值时按比例折算
static func _scaled_effects(effects: Array, ratio: float) -> Array:
	var out = []
	for e in effects:
		var ne = e.duplicate()
		var v = int(ne.value)
		if WeaponValue.is_modeled(ne):
			pass
		elif abs(v) >= 2 and WeaponValue.effect_key(ne) != "effect_gain_stat_every_killed_enemies" and WeaponValue.effect_key(ne) != "modify_every_x_projectile":
			ne.value = int(sign(v) * max(1, round(abs(v) * ratio)))
		else:
			ne.set_meta("aa_eff_scale", ratio)
		out.push_back(ne)
	return out
