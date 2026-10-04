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
			effects.push_back(_adapt(_convert_explosion(e.duplicate(), target.type), tw))
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
const SECOND_EFFECT_CHANCE = 0.2
# 第二个武器类别的概率（原版约 60% 的武器有两个类别）
const SECOND_SET_CHANCE = 0.6
# 每个类别至少这么多个武器家族（不超过原版数量）
const MIN_SET_FAMILIES = 3
const DEEP_TRIES = 24
# 慢速武器（平均攻击间隔 ≥ 此值，秒）：手感差、通常不会选用，作为攻击节奏的权重低；可以有更高的加成系数（激光枪、歼灭者）
const SLOW_COOLDOWN = 1.4
const SLOW_PROFILE_W = 0.25
# 原版家族没有附加加成时，附加加成每升一级的相对倍率（原版约 1.2–1.4：镰刀收获 10%->25%、尖刺盾护甲 100%->200%）
const SEC_GROWTH_DEFAULT = 1.3
# 从最低一级到最高一级，加成系数的总增长上限（相对倍率）：主加成 ×1.5（原版左轮 100%->200% 为最高），附加 ×2.5（镰刀收获 10%->25%）
const MAIN_GROWTH_CAP = 1.5
const SEC_GROWTH_CAP = 2.5
# 系数上限（折算成近战伤害的系数）：附加加成 1.25（镰刀收获 25% 约 1.25）；正常节奏武器的主加成 2.0（锤子 T4）；慢速武器不限
const SEC_COEF_CAP = 1.25
const MAIN_COEF_CAP = 2.0
# 高暴击：暴击率 / 暴击伤害达到此值的武器带"暴击"词条（必定精准类）
const HIGH_CRIT_CHANCE = 0.15
const HIGH_CRIT_DAMAGE = 2.5

# 词条 -> 武器类别：must = 必定、may = 可能（重复出现 = 权重更高）。词条包括原版角色的偏好词条（含全部主要属性）与武器自身特性；
# 宠物词条没有对应类别（驯兽师没有武器）
const TAG_SETS = {
	"stat_melee_damage": {"may": ["set_blade", "set_blade", "set_primitive", "set_primitive", "set_blunt", "set_medieval", "set_unarmed"]},
	"stat_ranged_damage": {"may": ["set_gun", "set_gun", "set_gun", "set_gun", "set_precise", "set_heavy"]},
	"stat_elemental_damage": {"must": ["set_elemental"]},
	"stat_engineering": {"must": ["set_tool"], "may": ["set_support"]},
	"stat_lifesteal": {"must": ["set_medical"], "may": ["set_blade"]},
	"stat_hp_regeneration": {"must": ["set_medical"]},
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
	"burning": {"must": ["set_elemental"]},
	"structure": {"must": ["set_tool"], "may": ["set_support"]},
	"ethereal": {"must": ["set_ethereal"]},
	"musical": {"must": ["set_musical"]},
	"economy": {"may": ["set_support", "set_precise"]},
	"xp_gain": {"may": ["set_support", "set_primitive"]},
	"consumable": {"may": ["set_medical", "set_support"]},
	"pickup": {"may": ["set_support"]},
	"exploration": {"may": ["set_support"]},
	"stand_still": {"may": ["set_heavy"]},
	"less_enemy_speed": {"may": ["set_naval", "set_support"]},
	"heavy": {"must": ["set_heavy"]},
}
# 只属于某一类型武器的类别
const MELEE_ONLY_SETS = ["set_blade", "set_blunt", "set_unarmed"]
const RANGED_ONLY_SETS = ["set_gun"]
# 词条之外的随机类别权重（"可能"类别为 1）
const RANDOM_SET_W = 0.15

var _bases: Dictionary = {}		# 类型 -> 各家族最低稀有度的原版武器
var _second_w: Dictionary = {}	# 属性 -> 权重（第二条 / 非伤害主加成）
var _main_coefs: Dictionary = {}	# "slow"/"normal" -> {属性: [原版主加成系数（最低一级）]}
var _sec_coefs: Dictionary = {}	# 属性 -> [原版附加加成系数（最低一级）]
var _shapes: Dictionary = {}	# 类型 -> [{cd, dmg, main, sec}]：原版家族每升一级的相对倍率
var _sets: Dictionary = {}		# set my_id -> SetData
var _set_native_count: Dictionary = {}


static func is_slow(st) -> bool:
	return WeaponValue.cooldown_seconds(st) >= SLOW_COOLDOWN


func _collect_deep_priors() -> void:
	_bases = {0: [], 1: []}
	_second_w = {}
	_main_coefs = {"slow": {}, "normal": {}}
	_sec_coefs = {}
	_shapes = {0: [], 1: []}
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
		var pace = "slow" if is_slow(lo.stats) else "normal"
		# 只有 T4 的传奇武器（王者之剑 +200% 最大生命……）的系数不进系数池
		if lo.tier == 3:
			sc = []
		for i in sc.size():
			var st = WeaponValue.stat_name(sc[i][0])
			var c = float(sc[i][1])
			if c <= 0:
				continue
			if i == 0:
				if not _main_coefs[pace].has(st):
					_main_coefs[pace][st] = []
				_main_coefs[pace][st].push_back(c)
			if i > 0 or not st in DAMAGE_STATS:
				if not _sec_coefs.has(st):
					_sec_coefs[st] = []
				_sec_coefs[st].push_back(c)
				counts[st] = counts.get(st, 0) + 1
		# 升级形状：冷却、伤害、主加成、附加加成每级的相对倍率
		var d = natives[-1] - natives[0]
		if d > 0:
			var shape = {
				"cd": pow(float(hi.stats.cooldown) / max(1.0, float(lo.stats.cooldown)), 1.0 / d),
				"dmg": pow(max(1.0, float(hi.stats.damage)) / max(1.0, float(lo.stats.damage)), 1.0 / d),
				"main": 1.0, "sec": SEC_GROWTH_DEFAULT,
			}
			var hsc = hi.stats.scaling_stats
			if sc.size() > 0 and hsc.size() > 0 and float(sc[0][1]) > 0 and float(hsc[0][1]) > 0:
				shape.main = pow(float(hsc[0][1]) / float(sc[0][1]), 1.0 / d)
			if sc.size() > 1 and hsc.size() > 1 and float(sc[1][1]) > 0 and float(hsc[1][1]) > 0:
				shape.sec = pow(float(hsc[1][1]) / float(sc[1][1]), 1.0 / d)
			_shapes[fam.type].push_back(shape)
		for set in lo.sets:
			_sets[set.my_id] = set
			_set_native_count[set.my_id] = _set_native_count.get(set.my_id, 0) + 1
	for st in SCALING_STATS:
		_second_w[st] = float(counts.get(st, 0)) + SCALING_BASE_W


func _pick_base(ty: int):
	var arr: Array = _bases[ty]
	return arr[rng.randi() % arr.size()]


# 攻击节奏（冷却、伤害、多发、换弹）来自同一把原版武器：同类型、价格最接近（最低一级的价格）的 PROFILE_POOL 把，
# 慢速武器（手感差，通常不会选用）的权重只有 SLOW_PROFILE_W
const PROFILE_POOL = 8


func _pick_profile(ty: int, price: float):
	var arr = []
	for b in _bases[ty]:
		arr.push_back([abs(log(max(1.0, float(b.value)) / max(1.0, price))), b])
	arr.sort_custom(self, "_sort_first")
	var w = {}
	for i in min(PROFILE_POOL, arr.size()):
		w[i] = SLOW_PROFILE_W if is_slow(arr[i][1].stats) else 1.0
	return arr[int(_pick_w(w))][1]


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


# 加成属性（每个家族先定）与最低一级的系数。主加成大多是本类型的伤害；系数来自原版同节奏（慢速 / 正常）武器的同属性主加成，
# 慢速武器可以抽到激光枪 / 歼灭者那样的高系数，正常武器不会
func _pick_scaling_stats(ty: int) -> Array:
	var main = _pick_w(MAIN_SCALING[ty])
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


func _pick_scaling(stats: Array, slow: bool) -> Array:
	var main = stats[0]
	var pool = _main_coefs["slow" if slow else "normal"].get(main, [])
	if pool.empty():
		pool = _main_coefs["normal"].get(main, [])
	if pool.empty() and not main in DAMAGE_STATS:
		pool = _sec_coefs.get(main, [])
	var sc = [[Keys.generate_hash(main), _coef_from(pool, main, 0.5)]]
	if stats.size() > 1:
		sc.push_back([Keys.generate_hash(stats[1]), _coef_from(_sec_coefs.get(stats[1], []), stats[1], 0.3)])
	return sc


func generate_deep() -> Dictionary:
	_collect_deep_priors()
	var out = {}
	var fam_sets = {}
	for f in fam_names:
		var fam = families[f]
		var mult = _family_mult(f)
		rng.seed = hash(str(seed_value) + "/wdeep/" + f)
		# 加成属性先定（避免下面择优时偏向系数小的属性），再多次抽取数值，
		# 取伤害最自然的一组（最低一级的伤害缩放最接近 1、逐级增长最接近所抽的原版形状）
		var stats = _pick_scaling_stats(fam.type)
		var res = {}
		var best = INF
		for _k in DEEP_TRIES:
			var cand = _deep_family(fam, mult, stats)
			if cand.score < best:
				best = cand.score
				res = cand.out
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


# 一个家族：最低一级的属性按原版分布抽取，更高级按一个原版家族的升级形状（冷却、主 / 附加加成系数的相对倍率）变化，
# 各级的伤害按价值解出；效果取来源家族对应稀有度
func _deep_family(fam: Dictionary, mult: float, stats: Array) -> Dictionary:
	var ty: int = fam.type
	var lo = _closest_tier(fam.tiers, 0)
	var bp = lo.stats.duplicate()
	var prof = _pick_profile(ty, float(lo.value)).stats
	bp.cooldown = prof.cooldown
	bp.recoil_duration = prof.recoil_duration
	bp.damage = prof.damage
	var b
	# 暴击直接套用原版武器的模板（低暴击 / 标准 3% ×2 / 高暴击）
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
	bp.scaling_stats = _pick_scaling(stats, is_slow(bp))
	var shape = {"cd": 0.9, "dmg": 1.6, "main": 1.0, "sec": SEC_GROWTH_DEFAULT}
	if not _shapes[ty].empty():
		shape = _shapes[ty][rng.randi() % _shapes[ty].size()]
	# 效果：随机来源家族（可跨类型），少数武器再加一个
	var donors = [families[fam_names[rng.randi() % fam_names.size()]]]
	if rng.randf() < SECOND_EFFECT_CHANCE:
		donors.push_back(families[fam_names[rng.randi() % fam_names.size()]])
	var out = {}
	var spec = _item_spec(family_of(lo), bp.scaling_stats)
	var tiers = fam.tiers.keys()
	tiers.sort()
	var score = 0.0
	var dmg0 = 1.0
	for tier in tiers:
		var tw = fam.tiers[tier]
		var d = tier - tiers[0]
		var effects = []
		var keys = []
		for e in tw.effects:
			if bound_key(e):
				effects.push_back(e)
		for dn in donors:
			var dw = _closest_tier(dn.tiers, tier)
			for e in dw.effects:
				var key = WeaponValue.effect_key(e)
				if bound_key(e) or key in keys or (ranged_only(e) and ty == 0):
					continue
				keys.push_back(key)
				effects.push_back(_adapt(_convert_explosion(e.duplicate(), ty), tw))
		var st = bp.duplicate()
		st.cooldown = int(max(2, round(bp.cooldown * pow(shape.cd, d))))
		var sc = []
		for i in bp.scaling_stats.size():
			var x = bp.scaling_stats[i]
			var g = min(pow(shape.main, d), MAIN_GROWTH_CAP) if i == 0 else min(pow(shape.sec, d), SEC_GROWTH_CAP)
			var c = float(x[1]) * g
			var equiv_cap = SEC_COEF_CAP if i > 0 else (INF if is_slow(st) else MAIN_COEF_CAP)
			var per = WeaponValue.stat_ref("stat_melee_damage") / WeaponValue.stat_ref(WeaponValue.stat_name(x[0]))
			c = min(c, equiv_cap * per)
			sc.push_back([x[0], max(0.01, stepify(c, 0.01))])
		st.scaling_stats = sc
		var want = _want(tw, true) * mult
		var line = _item_effect(spec, tier, want)
		if line != null:
			effects.push_back(line)
		var r = _solve_damage(st, effects, tier, want)
		st.damage = int(max(1, round(bp.damage * r)))
		if d == 0:
			dmg0 = float(st.damage)
			score += abs(log(max(0.02, r)))
		else:
			score += abs(log(max(1.0, float(st.damage)) / (dmg0 * pow(shape.dmg, d))))
		# 加成部分已超过目标（伤害解到 1 也嫌多）或伤害解到上限（代价过大）：这组不合适
		if r <= 0.03 or r >= 49.0:
			score += 10.0
		var dwf = _closest_tier(donors[0].tiers, tier)
		out[tw.my_id] = {"effects": effects, "stats": st, "donor": dwf.my_id, "scale": r}
	return {"out": out, "score": score}


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


# 武器的词条：加成属性、暴击 / 吸血 / 慢速重击等特性、效果的词条、道具效果的属性
func weapon_tags(ty: int, st, effects: Array) -> Array:
	var tags = []
	for sc in st.scaling_stats:
		if float(sc[1]) > 0:
			tags.push_back(WeaponValue.stat_name(sc[0]))
	if float(st.crit_chance) >= HIGH_CRIT_CHANCE or float(st.crit_damage) >= HIGH_CRIT_DAMAGE:
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
			"pierce_on_crit", "bounce_on_crit", "crit_on_hitting_burning_target":
				tags.push_back("stat_crit_chance")
			"temp_stats_while_not_moving":
				tags.push_back("stand_still")
		if e.has_meta("aa_value") and not e is TriggerEffect and Catalog.STATS.has(e.key) and e.value > 0:
			tags.push_back(e.key)
		elif Catalog.STATS.has(e.key) and WeaponValue.is_plain_player_stat(e) and e.value > 0:
			tags.push_back(e.key)
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
	if lo.tier == 3 and _sets.has("set_legendary"):
		out.push_back("set_legendary")
	var tags = weapon_tags(ty, p.stats, p.effects)
	var may = {}
	for t in tags:
		var m = TAG_SETS.get(t, {})
		for id in m.get("must", []):
			if _set_ok(id, ty) and not id in out:
				out.push_back(id)
		for id in m.get("may", []):
			if _set_ok(id, ty):
				may[id] = may.get(id, 0.0) + 1.0
	n = max(n, min(out.size(), 2))
	while out.size() > n:
		out.pop_back()
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


# 武器的目标价值（未乘浮动）：仅重组效果时按原武器的模型估值（属性不变，模型误差相互抵消）；
# 深度重组与补出的低级武器 = 价格 × 同档原版武器"模型价值 / 价格"的中位数（属性全部重抽，不沿用原武器的模型误差）
var _vp: Dictionary = {}


func _want(w, by_price := false) -> float:
	if by_price or w.has_meta("aa_low_of"):
		return float(w.value) * float(_vp.get(str(w.type) + "/" + str(w.tier), 1.0))
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

