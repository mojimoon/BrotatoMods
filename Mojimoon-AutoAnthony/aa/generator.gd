extends Reference

# 东尼算法生成器：把原版道具 / 角色 / 武器拆成组件，再按价值预算重新组装。
#
# 组件分三类：
#   属性行   纯属性加减（可缩放数值），占原版效果行的约 70%
#   机制行   固定机制（炮台、宠物、受击爆炸、每波额外敌人……），价值 = 来源道具价格 − 截距 − 其属性行价值；
#            可选：角色身上的机制（如"某类武器伤害 +X%"）也进入机制池，价值由"角色总价值"反推
#   触发条款 通用 (扳机 × 载荷 × 门控)，由 trigger_effect.gd 表达；原版的触发型效果被拆解为先验
#
# 出现频率不手写表格：属性、负面、行数、机制、特殊行比例、触发组合的分布都在运行时从原版数据统计，
# 再与目录中的基础权重相加，保证原版没有出现过的组合也有非零概率。
#
# cfg（百分比都是整数）：
#   avg          平均数值：预算倍率（100 = 原版价格）
#   variance     浮动范围：预算的对数正态离散度，100 = 原版"价值 / 价格"的离散度（σ = 0.35，四分位约 0.8–1.27）
#   triggers     触发效果：100 = 原版同稀有度道具带特殊行（触发 / 机制）的比例
#   native_ratio 保留原版道具的比例
#   char_effects 角色效果可出现在道具上
#
# 输出 plan：
#   items:      { my_id: {effects, adj, tags, budget} }
#   characters: { my_id: {effects, adj} }
#   weapons:    { my_id: {effects, donor} }

const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")
const Valuation = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/valuation.gd")
const TriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")

# 原版价值 / 价格的对数离散度（浮动范围 100% 的参考）
const NATIVE_VALUE_SIGMA = 0.35
# 特殊行中生成触发条款（其余为搬运机制）的比例
const TRIGGER_SHARE_OF_SPECIAL = 0.7

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
var special_share_by_tier: Array = [0.0, 0.0, 0.0, 0.0]	# 原版带特殊行（触发 / 机制）的道具比例
var trigger_prior: Dictionary = {}
var payload_prior: Dictionary = {}
var trigger_stat_prior: Dictionary = {}
var mechanics_by_tier: Array = [[], [], [], []]	# {effect, value, down, source}
var character_budget: float = Catalog.CHARACTER_BUDGET_DEFAULT
# 本次生成的道具价格 {道具 ID: 价格}（重组道具不再继承原版价格）
var gen_prices: Dictionary = {}
# 预算模型：原版纯属性道具每档的净价值中位数与价格中位数（同稀有度内预算与价格成正比）
var tier_value_median: Array = [8.0, 18.0, 29.0, 55.0]
var tier_price_median: Array = [20.0, 48.0, 72.0, 100.0]
var divisor: float = Catalog.DOWNSIDE_DIVISOR
# 道具池结构先验：每档 (正面类, 负面类) 计数；正面属性共现；正面属性 -> 负面属性
var class_counts: Array = [{}, {}, {}, {}]
var cooc: Dictionary = {}
var posneg: Dictionary = {}
# 当前正在生成的道具的类型与主属性（影响属性、载荷选择）
var pos_cat := ""
var neg_cat := ""
var anchor_stat := ""
# 当前生成道具的稀有度（T4 不出现 +收获）
var cur_tier := -1
# 当前道具不能生成的普通属性行（catalog.ITEM_STAT_BANS）
var cur_stat_bans: Array = []
# 本局玩家角色的偏好词条（开局时由 mod_main 填入）
var player_wanted_tags: Array = []
# 本局玩家角色的初始道具 ID（开局时由 mod_main 填入）：本局不重组，商店里的同 ID 道具也保持原版
var run_excluded_ids: Array = []
# 计数型 / 属性修改的原版先验
var counter_prior: Dictionary = {}
var gain_mod_prior := 0.0
# 重复惩罚：本次生成中已出现的扳机 / 载荷 / 组合计数
var used_combo: Dictionary = {}
var used_trigger: Dictionary = {}
var used_payload: Dictionary = {}
var scaling_script: Script
var gain_mod_script: Script
var effect_script: Script
# 条款约束（角色重组时使用）：禁用的扳机 / 载荷（反协同，如"无法回血"的角色不出现回血相关条款）
var banned_triggers: Array = []
var banned_payloads: Array = []
# 角色重组时的偏好词条：偏好属性更常作为正面、很少作为代价；绑定了偏好词条的扳机 / 载荷 / 计数更常出现
var wanted_bias: Array = []
# 当前道具的代价是"无法回血"（全部角色效果）：生成完后撤销上面的临时禁用
var item_banned_heal := false


func _init(p_cfg: Dictionary, p_seed: int) -> void:
	cfg = p_cfg
	seed_value = p_seed
	divisor = float(cfg.get("divisor", Catalog.DOWNSIDE_DIVISOR))
	rng = RandomNumberGenerator.new()
	effect_script = load("res://items/global/effect.gd")
	scaling_script = load("res://effects/items/gain_stat_for_every_stat_effect.gd")
	gain_mod_script = load("res://effects/items/stat_gains_modification_effect.gd")


# ============================================================
# 入口
# all_characters：全部角色（用于先验与角色效果池）；selected：本局需要重组的角色
# ============================================================
func generate(items: Array, all_characters: Array, selected: Array, weapons: Array) -> Dictionary:
	_collect_priors(items, all_characters, weapons)
	var plan = {"items": {}, "characters": {}, "weapons": {}, "seed": seed_value}
	if cfg.get("items", true):
		var gen_items = []
		for item in items:
			if _is_reassemblable_item(item) and not _keeps_native(item):
				gen_items.push_back(item)
		assign_prices(gen_items)
		var core = pick_core_items(gen_items)
		for item in gen_items:
			var r = generate_item(item, core.get(item.my_id, ""))
			if not r.empty():
				plan.items[item.my_id] = r
		cur_stat_bans = []
		_ensure_player_wanted_tags(plan, items, gen_items, core)
		for item in gen_items:
			if plan.items.has(item.my_id):
				_ensure_min_lines(item, plan.items[item.my_id])
		cur_stat_bans = []
		cur_tier = -1
		for id in plan.items:
			plan.items[id]["unique"] = has_unique_effect(plan.items[id].effects)
			plan.items[id]["price"] = int(gen_prices.get(id, 0))
	if cfg.get("characters", false):
		for ch in selected:
			plan.characters[ch.my_id] = generate_character(ch)
	if cfg.get("weapons", false):
		plan.weapons = generate_weapons(weapons)
	return plan


# T3 及以上的道具至少有两条效果（catalog.MIN_LINES_TIER / MIN_LINES），价值不变：
#   有可拆的正面属性行 -> 拆出一半换成另一条等价的属性行
#   否则（唯一的效果是触发条款 / 机制）-> 加一条代价和它换来的一条正面属性
static func visible_lines(effects: Array) -> int:
	var n = 0
	for e in effects:
		if e.get_text(0, false) != "":
			n += 1
	return n


func _ensure_min_lines(item, r: Dictionary) -> void:
	if item.tier < Catalog.MIN_LINES_TIER or visible_lines(r.effects) >= Catalog.MIN_LINES:
		return
	rng.seed = hash(str(seed_value) + "/minlines/" + item.my_id)
	cur_tier = item.tier
	cur_stat_bans = Catalog.ITEM_STAT_BANS.get(item.my_id, [])
	var effects: Array = r.effects.duplicate()
	var used = []
	var split = null
	for e in effects:
		if Catalog.STATS.has(e.key):
			used.push_back(e.key)
		if is_plain_stat(e) and e.value >= 2 * Catalog.stat_unit(e.key) and (split == null or line_value(e.key, e.value) > line_value(split.key, split.value)):
			split = e
	if split != null:
		var unit = Catalog.stat_unit(split.key)
		var half = int(floor(split.value / 2.0 / unit) * unit)
		var s2 = _pick_stat(false, used)
		var v2 = _round_to_unit(half * Catalog.stat_w(split.key) / Catalog.stat_w(s2), s2)
		var idx = effects.find(split)
		effects[idx] = _stat_effect(split.key, split.value - half)
		effects.insert(idx + 1, _stat_effect(s2, v2))
	else:
		var ns = _pick_stat(true, used)
		var nv = int(min(_round_to_unit(float(r.budget) * 0.15 * divisor / Catalog.stat_w(ns), ns), _line_cap(ns, true)))
		var ps = _pick_stat(false, used + [ns])
		var pv = _round_to_unit(neg_value(nv * Catalog.stat_w(ns)) / Catalog.stat_w(ps), ps)
		effects.push_front(_stat_effect(ps, pv))
		effects.push_back(_stat_effect(ns, -nv))
	r.effects = effects
	r.tags = _tags_for(effects)
	r.main_stats = main_stats(effects)


# 带"设定值 / 列表"型角色效果（catalog.BETA_UNIQUE_KEYS）或叠加有技术问题的原版独特效果（UNIQUE_MECHANIC_*）的道具：设为独特
static func has_unique_effect(effects: Array) -> bool:
	for e in effects:
		if e.key in Catalog.BETA_UNIQUE_KEYS or e.custom_key in Catalog.BETA_UNIQUE_KEYS:
			return true
		if e.key in Catalog.UNIQUE_MECHANIC_KEYS or e.custom_key in Catalog.UNIQUE_MECHANIC_KEYS:
			return true
		if e.get_script() != null and e.get_script().resource_path in Catalog.UNIQUE_MECHANIC_SCRIPTS:
			return true
	return false


# "保留原版道具"滑条：按道具 ID 的种子决定是否保留原版
func _keeps_native(item) -> bool:
	_seed_for(item.my_id)
	return rng.randf() < float(cfg.get("native_ratio", 0)) / 100.0


# 核心属性道具的分配：T1–T3 每档为每个核心属性各挑一件道具（种子确定；优先挑价格接近该档中位数的道具）
# 返回 {道具 ID: 属性}
func pick_core_items(gen_items: Array) -> Dictionary:
	var res = {}
	for t in Catalog.CORE_TIERS:
		var pool = []
		for it in gen_items:
			if it.tier == t and not Catalog.ITEM_STAT_BANS.has(it.my_id) and _preserved_lines(it).empty():
				pool.push_back(it)
		pool.sort_custom(self, "_sort_by_id")
		rng.seed = hash(str(seed_value) + "/core/" + str(t))
		var stats = Catalog.CORE_STATS.duplicate()
		for st in stats:
			if pool.empty():
				break
			var weights = {}
			for k in pool.size():
				var d = abs(log(max(1.0, price_of(pool[k])) / tier_price_median[t]))
				weights[k] = 1.0 / (0.25 + d)
			var k = _pick_weighted(weights)
			res[pool[k].my_id] = st
			pool.remove(k)
	return res


# 本局玩家角色的偏好词条（去掉八种核心属性，核心属性道具已保证）：T1–T3 每个稀有度如果没有带该词条的道具，
# 就把该稀有度的一件重组道具（优先选原版就带该词条的，图标一致）重新生成为带该词条的道具，只在本局有效。
# 原版的偏好词条有 5% 几率只从带该词条的道具中抽，某稀有度一件都没有时会退回到不检查角色禁用的备用池。
func _ensure_player_wanted_tags(plan: Dictionary, items: Array, gen_items: Array, core: Dictionary) -> void:
	var tags = []
	for t in player_wanted_tags:
		if not t in tags and not t in Catalog.CORE_STATS:
			tags.push_back(t)
	if tags.empty():
		return
	var sorted_items = gen_items.duplicate()
	sorted_items.sort_custom(self, "_sort_by_id")
	var used = {}
	for tag in tags:
		for tier in [0, 1, 2]:
			if _tier_has_tag(plan, items, tier, tag):
				continue
			var with_tag = []
			var others = []
			for it in sorted_items:
				if it.tier != tier or not plan.items.has(it.my_id) or core.has(it.my_id) or used.has(it.my_id):
					continue
				if tag in it.tags:
					with_tag.push_back(it)
				else:
					others.push_back(it)
			rng.seed = hash(str(seed_value) + "/wanted/" + tag + "/" + str(tier))
			var cands = with_tag if not with_tag.empty() else others
			if cands.empty():
				continue
			var item = cands[rng.randi() % cands.size()]
			var r = _generate_tag_item(item, tag, items)
			if r.empty():
				# 生成不出来：该稀有度有原版带此词条的道具就保留原版
				if not with_tag.empty():
					plan.items.erase(item.my_id)
					used[item.my_id] = true
				continue
			r["wanted_tag"] = tag
			plan.items[item.my_id] = r
			used[item.my_id] = true


func _tier_has_tag(plan: Dictionary, items: Array, tier: int, tag: String) -> bool:
	for it in items:
		if it.tier != tier or it is CharacterData or it is WeaponData or not it.can_be_looted:
			continue
		var tags = plan.items[it.my_id].tags if plan.items.has(it.my_id) else it.tags
		if tag in tags:
			return true
	return false


# 为偏好词条生成道具：属性词条 = 单属性道具（同核心属性道具）；诅咒 = 普通道具 + 原版的"+1 诅咒"行；
# 其余功能性词条（消耗品、建筑、宠物、爆炸、静止、经济、拾取……）= 反复重新生成直到带上该词条
func _generate_tag_item(item, tag: String, items: Array) -> Dictionary:
	cur_stat_bans = Catalog.ITEM_STAT_BANS.get(item.my_id, [])
	var r = {}
	if Catalog.STATS.has(tag) and not tag in cur_stat_bans:
		rng.seed = hash(str(seed_value) + "/tagitem/" + item.my_id)
		r = _generate_core_item(item, tag)
		r.erase("core")
	elif tag == "stat_curse":
		var curse = null
		for it in items:
			for e in it.effects:
				if e.key == "stat_curse" and e.custom_key == "" and e.value == 1:
					curse = e
		if curse != null:
			rng.seed = hash(str(seed_value) + "/tagitem/" + item.my_id)
			r = _generate_item_once(item, false)
			var effects = r.effects + [curse.duplicate()]
			r.effects = effects
			r.tags = _tags_for(effects)
	else:
		for attempt in 20:
			rng.seed = hash(str(seed_value) + "/tagitem/" + item.my_id + "/" + tag + "/" + str(attempt))
			var c = _generate_item_once(item, true)
			if tag in c.tags:
				r = c
				break
		if r.empty():
			r = _generate_clause_tag_item(item, tag)
		if r.empty():
			r = _generate_mechanic_tag_item(item, tag)
	cur_stat_bans = []
	return r


# 围绕一条带该词条的触发条款生成道具（扳机 / 载荷绑定了该词条，例如 静止 -> stand_still、爆炸 -> explosive）：条款 + 一行属性补足预算
func _generate_clause_tag_item(item, tag: String) -> Dictionary:
	var trig = []
	for t in Catalog.TRIGGERS:
		if Catalog.TRIGGER_TAGS.get(t, "") == tag or tag in Catalog.tags_for_binding("trigger:" + t):
			trig.push_back(t)
	var pay = []
	for p in Catalog.PAYLOADS:
		if Catalog.PAYLOAD_TAGS.get(p, "") == tag or tag in Catalog.tags_for_binding("payload:" + p):
			pay.push_back(p)
	if trig.empty() and pay.empty():
		return {}
	rng.seed = hash(str(seed_value) + "/tagclause/" + item.my_id + "/" + tag)
	cur_tier = item.tier
	var perm_mult: float = Catalog.PERM_MULT[item.tier]
	var budget: float = item_budget(item) * Catalog.HIDDEN_TIER_MULT[item.tier] * _avg_mult() * _variance_mult()
	var budget_total = budget
	var c = {}
	for attempt in 8:
		var ft = trig[rng.randi() % trig.size()] if not trig.empty() else ""
		var fp = pay[rng.randi() % pay.size()] if trig.empty() else ""
		c = gen_clause(budget * 0.6, perm_mult, false, ft, fp)
		if not c.empty():
			break
	if c.empty():
		cur_tier = -1
		return {}
	_note_clause(c)
	var ce = TriggerEffect.make(c)
	budget -= Valuation.clause_value(c, perm_mult)
	var effects = []
	if budget > 1.0:
		var stat = _pick_stat(false, [c.get("stat", "")])
		var v = int(min(_round_to_unit(budget / Catalog.stat_w(stat), stat), _line_cap(stat, false)))
		effects.push_back(_stat_effect(stat, v))
	effects.push_back(ce)
	cur_tier = -1
	return {
		"effects": effects,
		"adj": _adj(Catalog.ADJ_BY_TRIGGER.get(c.trigger, Catalog.ADJ_MECHANIC)),
		"tags": _tags_for(effects),
		"main_stats": main_stats(effects),
		"budget": budget_total,
		"class": ["A", "-"],
	}


# 围绕一条带该词条的机制生成道具（敌人数量增减、更多树木……）：机制 + 一行属性补足预算；
# 机制本身是代价时（敌人数量增加），换来的预算加到属性行上
func _generate_mechanic_tag_item(item, tag: String) -> Dictionary:
	var cands = []
	for t in 4:
		for m in mechanics_by_tier[t]:
			if Catalog.MECHANIC_BANNED_KEYS.has(m.effect.key):
				continue
			var probe = _mechanic_copy(m, -1.0, item.my_id)
			if tag in _tags_for([probe]):
				cands.push_back(m)
	if cands.empty():
		return {}
	rng.seed = hash(str(seed_value) + "/tagmech/" + item.my_id + "/" + tag)
	cur_tier = item.tier
	var budget: float = item_budget(item) * Catalog.HIDDEN_TIER_MULT[item.tier] * _avg_mult() * _variance_mult()
	var budget_total = budget
	var m = cands[rng.randi() % cands.size()]
	var me = _mechanic_copy(m, budget * 0.5 if not m.down else -1.0, item.my_id)
	var mv: float = me.get_meta("aa_value")
	budget -= mv
	var effects = []
	var stat = _pick_stat(false)
	if budget > 1.0:
		var cap = _line_cap(stat, false)
		var v = int(min(_round_to_unit(budget / Catalog.stat_w(stat), stat), cap))
		effects.push_back(_stat_effect(stat, v))
	if m.down:
		effects.push_back(me)
	else:
		effects.push_front(me)
	cur_tier = -1
	return {
		"effects": effects,
		"adj": _adj(Catalog.ADJ_MECHANIC),
		"tags": _tags_for(effects),
		"main_stats": main_stats(effects),
		"budget": budget_total,
		"class": [Catalog.STAT_CATEGORY.get(stat, "A"), "*" if m.down else "-"],
	}


static func _sort_by_id(a, b) -> bool:
	return a.my_id < b.my_id


func _seed_for(id: String) -> void:
	rng.seed = hash(str(seed_value) + "/" + id)


func _is_reassemblable_item(item) -> bool:
	if item is CharacterData or item is WeaponData:
		return false
	if item.my_id in Catalog.ANCHORED_ITEMS or item.my_id in run_excluded_ids:
		return false
	if item.tier < 0 or item.tier > 3:
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
		# 受伤加成只拆解道具上的（冰块）；潜水员的同类效果是角色身份
		if k == "enemy_percent_damage_taken" and not ("source_id" in e and e.source_id.begins_with("item_")):
			return null
		return Catalog.NATIVE_TRIGGER_MAP[k]
	var id = e.get_id() if e.has_method("get_id") else ""
	if id == "weapon_gain_stat_every_killed_enemies":
		return Catalog.NATIVE_TRIGGER_MAP["effect_gain_stat_every_killed_enemies"]
	return null


func is_scaling(e) -> bool:
	return e.get_script() == scaling_script


func is_gain_mod(e) -> bool:
	return e.get_script() == gain_mod_script


func is_next_wave(e) -> bool:
	return e.custom_key == "stats_next_wave"


func is_mechanic(e) -> bool:
	if is_plain_stat(e) or native_trigger_of(e) != null or is_scaling(e) or is_gain_mod(e) or is_next_wave(e):
		return false
	if e.get_script() == effect_script and e.key == "":
		return false	# 纯描述行（由道具 ID 实现）
	if e.key in Catalog.MECHANIC_BANNED_KEYS or e.custom_key in Catalog.MECHANIC_BANNED_KEYS:
		return false
	return true


func neg_value(v: float) -> float:
	return v / divisor


# 属性行价值：负面行按除数折算
func line_value(stat: String, value: int) -> float:
	var v = Valuation.stat_line_value(stat, value)
	return v if value >= 0 else neg_value(v)


func _collect_priors(items: Array, characters: Array, weapons: Array) -> void:
	for s in Catalog.STATS:
		stat_pos_w[s] = 0.5
		stat_neg_w[s] = 0.3
	for t in Catalog.TRIGGERS:
		trigger_prior[t] = 0.0
	for p in Catalog.PAYLOADS:
		payload_prior[p] = 0.0
	var tier_count = [0, 0, 0, 0]

	# 机制行必须能写入玩家 effects 字典（例如未启用 DLC 时没有诅咒等 DLC 属性）
	var effect_keys = PlayerRunData.init_effects()
	var plain_values = [[], [], [], []]
	var plain_prices = [[], [], [], []]
	var pending_mechs = []
	var sources = items + characters + weapons
	for src in sources:
		var pos_lines = 0
		var has_neg = false
		var has_special = false
		var stat_value = 0.0
		var pos_value = 0.0
		var mechs = []
		for e in src.effects:
			if is_plain_stat(e):
				if e.value > 0:
					stat_pos_w[e.key] += 1.0
					if src is ItemData and not src is CharacterData:
						stat_max_pos[e.key] = max(stat_max_pos.get(e.key, 0), e.value)
					pos_lines += 1
					pos_value += line_value(e.key, e.value)
				elif e.value < 0:
					stat_neg_w[e.key] += 1.0
					if src is ItemData and not src is CharacterData:
						stat_max_neg[e.key] = max(stat_max_neg.get(e.key, 0), -e.value)
					has_neg = true
				stat_value += line_value(e.key, e.value)
				continue
			has_special = true
			if is_scaling(e):
				counter_prior[e.stat_scaled] = counter_prior.get(e.stat_scaled, 0.0) + 1.0
				continue
			if is_gain_mod(e):
				gain_mod_prior += 1.0
				continue
			if is_next_wave(e):
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
					and not src.my_id in Catalog.MECHANIC_SOURCE_EXCLUDED and src.tier >= 0 and src.tier <= 3 \
					and e.get_text(0, false) != "" and _mechanic_keys_exist(e, effect_keys):
				mechs.push_back(e)
		if src is ItemData and not src is CharacterData and not src is WeaponData and src.tier >= 0 and src.tier <= 3:
			_record_structure(src)
			if not src.my_id in Catalog.ANCHORED_ITEMS and src.can_be_looted:
				lines_by_tier[src.tier].push_back(pos_lines)
				tier_count[src.tier] += 1
				if has_neg:
					neg_prob_by_tier[src.tier] += 1.0
				if has_special:
					special_share_by_tier[src.tier] += 1.0
				elif pos_lines > 0:
					plain_values[src.tier].push_back(max(1.0, stat_value))
					plain_prices[src.tier].push_back(float(src.value))
			if not mechs.empty():
				pending_mechs.push_back([src, mechs, stat_value, pos_value])
	for t in 4:
		if plain_values[t].size() >= 5:
			tier_value_median[t] = _median(plain_values[t])
			tier_price_median[t] = _median(plain_prices[t])
	for pm in pending_mechs:
		_add_item_mechanics(pm[0], pm[1], pm[2], pm[3])
	for t in 4:
		var n = max(1, tier_count[t])
		neg_prob_by_tier[t] = neg_prob_by_tier[t] / n
		special_share_by_tier[t] = special_share_by_tier[t] / n
		if lines_by_tier[t].empty():
			lines_by_tier[t] = [1, 2]
	_collect_char_templates(characters, items)
	if cfg.get("char_effects", false):
		_collect_character_mechanics(characters, effect_keys)


# 道具类型：正面主类 + 负面主类（"-" 表示无负面），例如 "AS" = 攻击为主、以生存为代价
func classify(effects: Array) -> String:
	var pos = {"A": 0.0, "S": 0.0, "E": 0.0}
	var neg = {"A": 0.0, "S": 0.0, "E": 0.0}
	for e in effects:
		var cat = ""
		var v = 0.0
		if is_plain_stat(e):
			cat = Catalog.STAT_CATEGORY.get(e.key, "")
			v = Catalog.stat_w(e.key) * e.value
		elif e is TriggerEffect:
			cat = Catalog.PAYLOAD_CATEGORY.get(e.payload, Catalog.STAT_CATEGORY.get(e.stat, ""))
			v = 10.0 * sign(e.value)
		elif is_scaling(e):
			cat = Catalog.STAT_CATEGORY.get(e.key, "")
			v = 10.0 * sign(e.value)
		elif is_gain_mod(e) and e.stats_modified.size() > 0:
			cat = Catalog.STAT_CATEGORY.get(e.stats_modified[0], "A")
			v = 10.0 * sign(e.value)
		else:
			var nt = native_trigger_of(e)
			if nt != null:
				cat = Catalog.PAYLOAD_CATEGORY.get(nt[1], Catalog.STAT_CATEGORY.get(e.key, ""))
				v = 10.0 * sign(e.value)
		if cat == "":
			continue
		if v > 0:
			pos[cat] += v
		elif v < 0:
			neg[cat] -= v
	var pc = ""
	var best = 0.0
	for k in pos:
		if pos[k] > best:
			best = pos[k]
			pc = k
	if pc == "":
		return ""
	var nc = "-"
	best = 0.0
	for k in neg:
		if neg[k] > best:
			best = neg[k]
			nc = k
	return pc + nc


func _record_structure(src) -> void:
	var cls = classify(src.effects)
	if cls != "":
		class_counts[src.tier][cls] = class_counts[src.tier].get(cls, 0.0) + 1.0
	var P = []
	var N = []
	for e in src.effects:
		if is_plain_stat(e):
			if e.value > 0:
				P.push_back(e.key)
			elif e.value < 0:
				N.push_back(e.key)
	for a in P:
		if not cooc.has(a):
			cooc[a] = {}
		for b in P:
			if a != b:
				cooc[a][b] = cooc[a].get(b, 0.0) + 1.0
		if not posneg.has(a):
			posneg[a] = {}
		for n in N:
			posneg[a][n] = posneg[a].get(n, 0.0) + 1.0


# 原版道具的非属性词条（structure / pet / explosive ……），随机制行一起搬运
static func _extra_tags(src) -> Array:
	var out = []
	for t in src.tags:
		# 敌人数量词条只由敌人数量效果本身给出（见 _tags_for），不随来源道具继承到其他机制上
		if not Catalog.STATS.has(t) and not t in ["stat_curse", "more_enemies", "less_enemies"]:
			out.push_back(t)
	return out


static func _median(arr: Array) -> float:
	var a = arr.duplicate()
	a.sort()
	return a[a.size() / 2]


# 道具的价格：重组道具用本次生成的价格，其余（原版来源、保留原版的道具）用原版价格
func price_of(item) -> float:
	return float(gen_prices.get(item.my_id, item.value))


# 道具的效果预算（不含平均数值与浮动）
#   tier（默认）：同稀有度内与价格成正比，k = 原版纯属性道具的净价值中位数 / 价格中位数
#   intercept：价格 − 稀有度截距
func item_budget(item) -> float:
	var price = price_of(item)
	if cfg.get("budget_model", "tier") == "intercept":
		return max(3.0, price - Catalog.TIER_INTERCEPT[item.tier])
	var t = item.tier
	return max(2.0, tier_value_median[t] * max(1.0, price) / tier_price_median[t])


# 为每件重组道具生成价格：从同稀有度被重组道具的原版价格中有放回抽取（按种子与道具 ID 确定）
func assign_prices(gen_items: Array) -> void:
	var pools = [[], [], [], []]
	for it in gen_items:
		if it.value >= Catalog.PRICE_POOL_MIN:
			pools[it.tier].push_back(it.value)
	for t in 4:
		pools[t].sort()
	for it in gen_items:
		var pool: Array = pools[it.tier]
		if pool.empty():
			continue
		rng.seed = hash(str(seed_value) + "/price/" + it.my_id)
		gen_prices[it.my_id] = int(pool[rng.randi() % pool.size()])


# 道具机制估值：正面机制平分"价格 − 截距 − 属性行价值"；
# 负面机制的价值 = 来源道具因它多拿到的正面预算（正面属性价值 − 预算），至少 3
func _add_item_mechanics(src, mechs: Array, stat_value: float, pos_value: float) -> void:
	var ups = 0
	var downs = 0
	for e in mechs:
		if Catalog.is_downside_mechanic(e):
			downs += 1
		else:
			ups += 1
	var budget = item_budget(src)
	var each_up = max(5.0, (budget - stat_value) / max(1, ups)) * float(Catalog.MECHANIC_VALUE_MULT.get(src.my_id, 1.0))
	var each_down = max(3.0, 0.15 * max(budget, 0.0))
	if ups == 0 and downs > 0:
		each_down = max(3.0, (pos_value - budget) / downs)
	for e in mechs:
		var down = Catalog.is_downside_mechanic(e)
		var k = e.custom_key if e.custom_key != "" else e.key
		var scalar = ((e.get_script() == effect_script and e.storage_method == 0 and e.custom_key == "") or k in Catalog.SCALAR_EXTRA_KEYS) \
			and e.value != 0 and not e.key in Catalog.SCALAR_MECHANIC_EXCLUDED and not down
		var key_mult = float(Catalog.MECHANIC_VALUE_MULT.get(k, 1.0))
		mechanics_by_tier[src.tier].push_back({
			"effect": e, "value": -each_down if down else each_up * key_mult, "down": down, "source": src.my_id,
			"tags": _extra_tags(src), "scalar": scalar,
		})
		if cfg.get("more_double", false):
			_add_mirrored_mechanic(src, e, each_up * key_mult, down, scalar)


# 更多双面效果：可缩放正面机制的反面作为代价；敌人生命 / 伤害提高（负面机制）的反面作为好处
func _add_mirrored_mechanic(src, e, each_up: float, down: bool, scalar: bool) -> void:
	var k = e.key
	if e.custom_key != "" or e.value == 0:
		return
	if not down and scalar and Catalog.DOUBLE_NEG_CAPS.has(k):
		var me = e.duplicate()
		me.value = -e.value
		if not Catalog.is_downside_mechanic(me):
			return
		# 代价的价值 = 正面每单位价值 × 数值 / 负面除数
		mechanics_by_tier[src.tier].push_back({
			"effect": me, "value": -neg_value(each_up), "down": true, "source": src.my_id, "tags": [],
			"scalar": true, "top": Catalog.DOUBLE_NEG_CAPS[k], "mirror": true,
		})
	elif down and Catalog.DOUBLE_POS_ENEMY_CAPS.has(k) and e.value > 0:
		var pe = e.duplicate()
		pe.value = -e.value
		mechanics_by_tier[src.tier].push_back({
			"effect": pe, "value": Catalog.stat_w(k) * e.value, "down": false, "source": src.my_id, "tags": [],
			"scalar": true, "top": Catalog.DOUBLE_POS_ENEMY_CAPS[k], "mirror": true,
		})


# 角色机制估值：假设所有角色总价值相近。角色总价值 = 只由可估值行（属性行、原版触发行）组成的角色的中位数；
# 某角色的每条机制价值 = (角色总价值 − 该角色可估值部分) / 机制数，按价值放入对应稀有度
func _collect_character_mechanics(characters: Array, effect_keys: Dictionary) -> void:
	var known_only = []
	var per_char = []
	for ch in characters:
		var known = 0.0
		var mechs = []
		for e in ch.effects:
			if is_plain_stat(e) or is_gain_mod(e) or is_scaling(e) or (native_trigger_of(e) != null and Catalog.STATS.has(e.key)):
				known += char_line_value(e)
				continue
			if _is_transferable_character_mechanic(e, effect_keys):
				mechs.push_back(e)
		if mechs.empty():
			known_only.push_back(known)
		else:
			per_char.push_back([ch, known, mechs])
	if known_only.size() >= 3:
		known_only.sort()
		character_budget = max(Catalog.CHARACTER_BUDGET_DEFAULT, known_only[known_only.size() / 2])
	for entry in per_char:
		# 角色机制往往是整局核心（某类武器 +50% 攻速等），保守起见每条至少 30
		var each = clamp((character_budget - entry[1]) / entry[2].size(), 30.0, 80.0)
		var tier = 0 if each < 15.0 else (1 if each < 35.0 else (2 if each < 60.0 else 3))
		for e in entry[2]:
			mechanics_by_tier[tier].push_back({"effect": e, "value": each, "down": false, "source": entry[0].my_id, "tags": []})


func _is_transferable_character_mechanic(e, effect_keys: Dictionary) -> bool:
	if not is_mechanic(e) or Catalog.is_downside_mechanic(e):
		return false
	if e.key in Catalog.CHAR_MECHANIC_BANNED or e.custom_key in Catalog.CHAR_MECHANIC_BANNED 			or e.key.to_lower() in Catalog.CHAR_MECHANIC_BANNED or e.custom_key.to_lower() in Catalog.CHAR_MECHANIC_BANNED:
		return false
	if e.key.begins_with("starting_") or e.custom_key.begins_with("starting_") or e.custom_key.begins_with("cursed_starting"):
		return false
	# 只搬运正向数值（属性成长"降低"常为 -100%，等于禁用该属性）
	if e.value <= 0:
		return false
	if e.get_text(0, false) == "":
		return false
	return _mechanic_keys_exist(e, effect_keys)


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
		if not neg and cur_tier == 3 and s in Catalog.T4_BANNED_POSITIVE_STATS:
			continue
		if s in cur_stat_bans:
			continue
		if s in exclude:
			continue
		if allowed != null and not s in allowed:
			continue
		var w = src[s] + trigger_stat_prior.get(s, 0.0) * 0.5
		# 类型偏好：正面属性偏向本道具的正面类，负面属性偏向负面类
		var cat = neg_cat if neg else pos_cat
		if cat != "" and cat != "-" and Catalog.STAT_CATEGORY.get(s, "") == cat:
			w *= 4.0
		if s in wanted_bias:
			w *= 0.1 if neg else Catalog.WANTED_BIAS
		elif not neg and not wanted_bias.empty() and _stat_has_wanted_tag(s):
			w *= Catalog.WANTED_BIAS * 0.5
		# 共现偏好：原版中与主属性一起出现（或被它拿来交换）的属性
		if anchor_stat != "" and s != anchor_stat:
			var table = posneg if neg else cooc
			if table.has(anchor_stat):
				w *= 1.0 + 3.0 * table[anchor_stat].get(s, 0.0) / max(1.0, _max_value(table[anchor_stat]))
		weights[s] = w
	var s = _pick_weighted(weights)
	return s if s != null else "stat_max_hp"


# 伤害类型：近战 : 远程 : 元素 : 工程 = 2 : 2 : 2 : 1，偏向想要的词条；
# 传入已抽到的缩放属性时，只在它是伤害类型时重新分配（伤害 / 爆炸载荷）
func _pick_dmg_type(current: String = "") -> String:
	if current != "" and not Catalog.DMG_TYPES.has(current):
		return current
	var w = {}
	for s in Catalog.DMG_TYPES:
		w[s] = Catalog.DMG_TYPES[s] * (Catalog.WANTED_BIAS if s in wanted_bias else 1.0)
	return _pick_weighted(w)


func _wanted_dmg_type() -> bool:
	for s in Catalog.DMG_TYPES:
		if s in wanted_bias:
			return true
	return false


# 属性带有偏好的功能性词条（knockback / explosive / pickup / consumable）
func _stat_has_wanted_tag(s: String) -> bool:
	return Catalog.STAT_EXTRA_TAGS.has(s) and Catalog.STAT_EXTRA_TAGS[s] in wanted_bias


func _binding_wanted(k: String, extra: String = "") -> bool:
	if wanted_bias.empty():
		return false
	if extra != "" and extra in wanted_bias:
		return true
	for t in Catalog.tags_for_binding(k):
		if t in wanted_bias:
			return true
	return false


static func _max_value(d: Dictionary) -> float:
	var m = 0.0
	for k in d:
		m = max(m, d[k])
	return m


func _adj(options: Array) -> String:
	return options[rng.randi() % options.size()]


func _pick_class(tier: int) -> String:
	var w = {}
	for c in Catalog.CATEGORY_CLASSES:
		w[c] = class_counts[tier].get(c, 0.0) + 0.5
	return _pick_weighted(w)


func _avg_mult() -> float:
	return clamp(float(cfg.get("avg", 100)), 10.0, 500.0) / 100.0


# 对数正态浮动，中位数为 1
func _variance_mult() -> float:
	var sigma = NATIVE_VALUE_SIGMA * clamp(float(cfg.get("variance", 100)), 0.0, 400.0) / 100.0
	if sigma <= 0.0:
		return 1.0
	return exp(sigma * clamp(rng.randfn(0.0, 1.0), -2.0, 2.0))


func _trigger_rate() -> float:
	return clamp(float(cfg.get("triggers", 100)), 0.0, 400.0) / 100.0


# ============================================================
# 道具
# ============================================================
func generate_item(item, core_stat: String = "") -> Dictionary:
	_seed_for(item.my_id)
	if rng.randf() < float(cfg.get("native_ratio", 0)) / 100.0:
		return {}
	cur_stat_bans = Catalog.ITEM_STAT_BANS.get(item.my_id, [])
	if core_stat != "":
		return _generate_core_item(item, core_stat)
	return _generate_item_once(item, false)


func _generate_item_once(item, force_special: bool) -> Dictionary:
	cur_tier = item.tier
	var tier: int = item.tier
	var perm_mult: float = Catalog.PERM_MULT[tier]
	var budget: float = item_budget(item) * Catalog.HIDDEN_TIER_MULT[item.tier] * _avg_mult() * _variance_mult()
	var budget_total = budget
	var effects = []
	var used_stats = []
	var main_line = {"value": 0.0, "adj": ""}

	# 0) 道具类型：按原版同稀有度的 (正面类, 负面类) 分布抽取，先定主属性
	var cls = _pick_class(tier)
	pos_cat = cls[0]
	neg_cat = cls[1]
	# 以运营为代价的道具在原版中很少且无明确规律：负面自由生成
	if neg_cat == "E":
		neg_cat = "*"
	anchor_stat = ""
	var primary = _pick_stat(false)
	anchor_stat = primary
	used_stats.push_back(primary)

	# 1) 代价：负面效果的实际强度 = 换来的预算 × 负面除数
	var downsides = []
	if neg_cat != "-":
		var dres = _gen_downsides(item, budget_total * rng.randf_range(0.1, 0.35), perm_mult, used_stats, budget_total)
		downsides = dres.effects
		budget += dres.got
		# 代价是"无法回血"：同一道具不再出现回血相关的条款 / 机制
		for d in downsides:
			if d.key == "no_heal" and not "heal" in banned_payloads:
				banned_payloads.push_back("heal")
				banned_triggers.push_back("heal")
				item_banned_heal = true

	# 2) 特殊行：数量按原版同稀有度"带特殊行的比例" × 触发效果滑条；约 70% 为触发条款，其余为搬运机制
	var p_special = special_share_by_tier[tier] * _trigger_rate()
	var slots = 0
	if rng.randf() < min(0.95, p_special) or force_special:
		slots += 1
	if rng.randf() < p_special - 1.0:
		slots += 1
	for _slot in slots:
		if budget <= 4.0:
			break
		var share = rng.randf_range(0.4, 0.8) if slots == 1 else rng.randf_range(0.3, 0.5)
		var kind = _pick_weighted(Catalog.SPECIAL_KIND_WEIGHTS)
		var done = false
		if kind == "mechanic" and budget > 8.0:
			var m = _pick_mechanic(tier, false, budget * 1.1)
			if m != null:
				var me = _mechanic_copy(m, budget * share, item.my_id)
				var mv = me.get_meta("aa_value")
				effects.push_back(me)
				budget -= mv
				done = true
				if mv > main_line.value:
					main_line = {"value": mv, "adj": _adj(Catalog.ADJ_MECHANIC)}
		elif kind == "scaling":
			var sc = gen_scaling(budget * share, false)
			if not sc.empty():
				effects.push_back(sc.effect)
				budget -= sc.value
				done = true
				if sc.value > main_line.value:
					main_line = {"value": sc.value, "adj": _adj(Catalog.ADJ_SCALING)}
		elif kind == "next_wave":
			var nw = gen_next_wave(budget * share, perm_mult, true)
			if not nw.empty():
				effects += nw.effects
				budget -= nw.value
				done = true
				if nw.value > main_line.value:
					main_line = {"value": nw.value, "adj": _adj(Catalog.ADJ_BY_TRIGGER["wave_start"])}
		elif kind == "char":
			var ch = gen_char_component(budget * share, item)
			if not ch.empty():
				effects += ch.get("effects", [ch.effect])
				budget -= ch.value
				done = true
				if ch.value > main_line.value:
					main_line = {"value": ch.value, "adj": _adj(Catalog.ADJ_MECHANIC)}
		elif kind == "gain_mod":
			var gm = gen_gain_mod(budget * share, false)
			if not gm.empty():
				effects.push_back(gm.effect)
				budget -= gm.value
				done = true
				if gm.value > main_line.value:
					main_line = {"value": gm.value, "adj": _adj(Catalog.ADJ_GAIN_MOD)}
		if not done:
			var c = gen_clause(budget * share, perm_mult, false)
			if not c.empty():
				var cv = Valuation.clause_value(c, perm_mult)
				effects.push_back(TriggerEffect.make(c))
				_note_clause(c)
				budget -= cv
				# 同扳机正负成对：另写一条同扳机、同门控的负面条款（两条独立效果，诅咒由原版逐条处理）
				if c.payload in ["temp_stat", "perm_stat", "timed_stat"] and not c.get("reset", false) \
						and rng.randf() < Catalog.PAIRED_CLAUSE_CHANCE:
					var c2 = _make_pair(c, perm_mult)
					if not c2.empty():
						effects.push_back(TriggerEffect.make(c2))
						budget += neg_value(abs(Valuation.clause_value(c2, perm_mult)))
				if cv > main_line.value:
					main_line = {"value": cv, "adj": _adj(Catalog.ADJ_GRANT) if c.payload == "grant" and rng.randf() < 0.5 else _adj(Catalog.ADJ_BY_TRIGGER[c.trigger])}
				if c.get("stat", "") != "":
					used_stats.push_back(c.stat)

	# 3) 属性行：行数取自原版同稀有度道具的分布；剩余预算较多时至少补一行
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
	var primary_used = false
	for e in effects:
		if e is TriggerEffect and e.stat == primary:
			primary_used = true
	while i < n or (carry > 2.0 and i < n + 2):
		var s = primary if (i == 0 and not primary_used) else _pick_stat(false, used_stats)
		if s != primary:
			used_stats.push_back(s)
		var b = carry
		if i < n:
			b += max(budget, 2.0) * shares[i] / total_share
		# 次要属性（击退、范围）只拿一部分预算，余下的留给后面的属性行
		var held = 0.0
		if s != primary and Catalog.MINOR_POSITIVE_STATS.has(s):
			held = b * (1.0 - Catalog.MINOR_POSITIVE_STATS[s])
			b -= held
		var v = _round_to_unit(b / Catalog.stat_w(s), s)
		var cap = _line_cap(s, false)
		if v > cap:
			v = cap
		carry = max(0.0, b - v * Catalog.stat_w(s)) + held
		stat_lines.push_back(_stat_effect(s, v))
		if v * Catalog.stat_w(s) > main_line.value:
			main_line = {"value": v * Catalog.stat_w(s), "adj": _adj(Catalog.ADJ_BY_STAT.get(s, Catalog.ADJ_MECHANIC))}
		i += 1

	if item_banned_heal:
		banned_payloads.erase("heal")
		banned_triggers.erase("heal")
		item_banned_heal = false
	# 原版的书写顺序：正面属性在前，触发 / 机制随后，负面在最后
	var ordered = stat_lines + effects + _preserved_lines(item) + downsides
	_add_cursed_kill_curse(ordered)
	pos_cat = ""
	neg_cat = ""
	anchor_stat = ""
	cur_tier = -1

	return {
		"effects": ordered,
		"adj": main_line.adj if main_line.adj != "" else _adj(Catalog.ADJ_MECHANIC),
		"tags": _tags_for(ordered),
		"main_stats": main_stats(ordered),
		"budget": budget_total,
		"class": cls,
	}


# "击杀被诅咒的敌人时"需要有被诅咒的敌人：同原版黑旗，道具附带 +X 诅咒（已有诅咒行时不重复）
func _add_cursed_kill_curse(effects: Array) -> void:
	var has_trigger = false
	for e in effects:
		if e is TriggerEffect and e.trigger == "cursed_kill" and e.value > 0:
			has_trigger = true
		elif e.key == "stat_curse" and e.custom_key == "" and not e is TriggerEffect:
			return
	if has_trigger:
		effects.push_back(_stat_effect("stat_curse", Catalog.CURSED_KILL_CURSE))


# 原道具上保留的原版行（catalog.PRESERVED_NATIVE_KEYS），复制一份
func _preserved_lines(item) -> Array:
	var out = []
	for e in item.effects:
		if e.key in Catalog.PRESERVED_NATIVE_KEYS and e.custom_key == "":
			out.push_back(e.duplicate())
	return out


# 核心属性道具：唯一的正面效果是 stat 的一行数值，多数附带代价以提高数值；
# T3 必带代价（T3 单行道具不能是单纯数值）
func _generate_core_item(item, stat: String) -> Dictionary:
	cur_tier = item.tier
	var perm_mult: float = Catalog.PERM_MULT[item.tier]
	var budget: float = item_budget(item) * Catalog.HIDDEN_TIER_MULT[item.tier] * _avg_mult() * _variance_mult()
	var budget_total = budget
	pos_cat = ""
	neg_cat = "*"
	anchor_stat = stat
	var used_stats = [stat]
	var downsides = []
	if item.tier in Catalog.CORE_TIERS:
		var dres = _gen_downsides(item, budget_total * rng.randf_range(0.15, 0.4), perm_mult, used_stats, budget_total)
		downsides = dres.effects
		budget += dres.got
	var cap = int(ceil(_line_cap(stat, false) * Catalog.CORE_LINE_CAP_MULT))
	var v = int(min(_round_to_unit(budget / Catalog.stat_w(stat), stat), cap))
	var ordered = [_stat_effect(stat, v)] + downsides
	pos_cat = ""
	neg_cat = ""
	anchor_stat = ""
	cur_tier = -1
	return {
		"effects": ordered,
		"adj": _adj(Catalog.ADJ_BY_STAT.get(stat, Catalog.ADJ_MECHANIC)),
		"tags": _tags_for(ordered),
		"main_stats": main_stats(ordered),
		"budget": budget_total,
		"class": [Catalog.STAT_CATEGORY.get(stat, "A"), "*" if not downsides.empty() else "-"],
		"core": stat,
	}


# 代价：换来 comp 预算的负面效果（实际强度 = comp × 负面除数）
func _gen_downsides(item, comp: float, perm_mult: float, used_stats: Array, budget_total: float = -1.0) -> Dictionary:
	var tier: int = item.tier
	var downsides = []
	var got = 0.0
	var r = rng.randf()
	if r >= 0.25 and r < 0.33:
		var sc = gen_scaling(comp * divisor, true)
		if not sc.empty():
			downsides.push_back(sc.effect)
			got = neg_value(abs(sc.value))
	elif (r >= 0.45 and r < 0.52) or (r >= 0.41 and r < 0.45 and cfg.get("all_char_effects", false)):
		var cd = gen_char_downside(comp, perm_mult, budget_total)
		if not cd.empty():
			downsides += cd.effects
			got = cd.value
	elif r >= 0.37 and r < 0.40:
		var nd = gen_next_wave_downside(comp, perm_mult)
		if not nd.empty():
			downsides += nd.effects
			got = nd.value
	elif r >= 0.33 and r < 0.37:
		var gm = gen_gain_mod(comp * divisor, true)
		if not gm.empty():
			downsides.push_back(gm.effect)
			got = neg_value(abs(gm.value))
	elif r < 0.15:
		var c = gen_clause(-comp * divisor, perm_mult, true)
		if not c.empty():
			_note_clause(c)
			downsides.push_back(TriggerEffect.make(c))
			got = neg_value(abs(Valuation.clause_value(c, perm_mult)))
	elif r < 0.25:
		var m = _pick_mechanic(tier, true, comp * 2.0)
		if m != null:
			var dm = _mechanic_copy(m, comp if m.get("mirror", false) else -1.0, item.my_id)
			downsides.push_back(dm)
			got = abs(dm.get_meta("aa_value"))
	if got == 0.0:
		var s = _pick_stat(true, used_stats)
		var v = int(min(_round_to_unit(comp * divisor / Catalog.stat_w(s), s), _line_cap(s, true)))
		downsides.push_back(_stat_effect(s, -v))
		used_stats.push_back(s)
		got = neg_value(v * Catalog.stat_w(s))
	return {"effects": downsides, "got": got}


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
# target > 0 时，可缩放机制按预算调整数值（1 单位 .. 原版 1.5 倍），价值按比例折算。
# holder_id：新持有者道具 ID（"持有者键"类机制需要改写 key）
func _mechanic_copy(m: Dictionary, target: float = -1.0, holder_id: String = ""):
	var e = m.effect.duplicate()
	var v = m.value
	if target > 0.0 and m.get("scalar", false):
		var native_v = m.effect.value
		var sg = 1 if native_v > 0 else -1
		var want = round(abs(native_v) * target / abs(m.value))
		var top = max(1.0, ceil(abs(native_v) * 1.5))
		if m.has("top"):
			top = m.top
		if Catalog.pct_cap(e) > 0:
			top = min(top, Catalog.pct_cap(e))
		var ic = Catalog.MECHANIC_INTERCEPT.get(e.key, {})
		if not ic.empty():
			# 非线性：价值 = 单位价值 × (数值 - offset)
			want = round(ic.offset + (abs(native_v) - ic.offset) * target / abs(m.value))
		var nv = int(clamp(want, ic.get("min", 1), top)) * sg
		e.value = nv
		v = m.value * float(nv) / float(native_v)
		if not ic.empty():
			v = m.value * float(abs(nv) - ic.offset) / float(abs(native_v) - ic.offset)
		# 丑牙：减速上限保持为单次减速的 4 倍（与原版诅咒逻辑一致）
		if e.key == "remove_speed" and "value2" in e:
			e.value2 = nv * 4
	if holder_id != "":
		_adapt_to_holder(e, holder_id)
	e.set_meta("aa_value", v)
	e.set_meta("aa_tags", m.get("tags", []))
	return e


# 原版按道具 ID 查找持有者的机制：改写为新持有者；生效后会移除持有者的，在同一行注明
func _adapt_to_holder(e, holder_id: String) -> void:
	var k = e.custom_key if e.custom_key != "" else e.key
	if k in Catalog.HOLDER_KEYED:
		e.key = holder_id
		e.key_hash = Keys.generate_hash(holder_id)
	elif k == "enemy_percent_damage_taken" and "source_id" in e:
		# 受伤加成（冰块）：来源改为持有者，不同道具的同类效果可以相加（原版同一来源不叠层）
		e.source_id = holder_id
		e.source_id_hash = Keys.generate_hash(holder_id)
	elif k == "extra_item_in_crate" and e.key != "random":
		# 珍珠：箱子里额外出现"这件道具自己"
		e.key = holder_id
		e.key_hash = Keys.generate_hash(holder_id)
	if k in Catalog.CONSUMED_KEYS:
		note_text(e, "AA_NOTE_CONSUMED")


# 在效果原文后追加说明：生成一个新的描述 key（= 原文 + 说明），注册到当前语言与英文
static func note_text(e, note_key: String) -> void:
	var native_key = (e.text_key if e.text_key != "" else e.key).to_upper()
	if native_key.begins_with("AA_N_"):
		return
	var new_key = "AA_N_" + native_key + "__" + note_key
	var m = Engine.get_main_loop().root.get_node_or_null("/root/ModLoader/Mojimoon-AutoAnthony")
	if m != null:
		m.register_note(new_key, native_key, note_key)
	e.text_key = new_key


func _pick_mechanic(tier: int, downside: bool, max_abs_value: float):
	var pool = []
	for t in [tier, tier - 1, tier + 1]:
		if t < 0 or t > 3:
			continue
		for m in mechanics_by_tier[t]:
			var min_value = abs(m.value)
			if m.get("scalar", false):
				min_value = abs(m.value) / max(1.0, abs(m.effect.value))
				var ic = Catalog.MECHANIC_INTERCEPT.get(m.effect.key, {})
				if not ic.empty():
					min_value = abs(m.value) * (ic.min - ic.offset) / max(1.0, abs(m.effect.value) - ic.offset)
			var mk = m.effect.custom_key if m.effect.custom_key != "" else m.effect.key
			if "heal" in banned_payloads and mk in Catalog.HEAL_KEYS:
				continue
			if m.down == downside and min_value <= max_abs_value:
				pool.push_back(m)
		if not pool.empty():
			break
	if pool.empty():
		return null
	return pool[rng.randi() % pool.size()]


# 词条：正面属性 key + 原版风格的非属性词条（consumable / explosive / stand_still / structure ……）
func _tags_for(effects: Array) -> Array:
	var tags = []
	for e in effects:
		var add = []
		if e is TriggerEffect:
			if e.value > 0:
				if Catalog.STATS.has(e.stat) and e.payload in ["temp_stat", "perm_stat", "timed_stat"]:
					add.push_back(e.stat)
				add.push_back(Catalog.TRIGGER_TAGS.get(e.trigger, ""))
				add.push_back(Catalog.PAYLOAD_TAGS.get(e.payload, ""))
				add += Catalog.tags_for_binding("trigger:" + e.trigger)
				add.push_back(e.dmg_type)
				add += Catalog.tags_for_binding("payload:" + e.payload)
				if e.grant != null and is_scaling(e.grant):
					add += Catalog.tags_for_binding("counter:" + e.grant.stat_scaled)
					if Catalog.STATS.has(e.grant.stat_scaled):
						add.push_back(e.grant.stat_scaled)
				elif e.grant != null:
					add += Catalog.tags_for_binding("mech:" + e.grant.key)
				add.push_back(Catalog.STAT_EXTRA_TAGS.get(e.stat, ""))
				# 伤害 / 爆炸载荷：缩放属性也是词条（原版赛博球"按幸运造成伤害"带幸运）
				if e.payload in ["damage", "explode"] and Catalog.STATS.has(e.stat):
					add.push_back(e.stat)
				if e.grant != null:
					if is_scaling(e.grant):
						add.push_back(e.grant.key)
					elif is_gain_mod(e.grant):
						add.push_back(e.grant.stat_displayed)
					elif e.grant.has_meta("aa_tags"):
						add += e.grant.get_meta("aa_tags")
		elif e.get_script() == effect_script and Catalog.STATS.has(e.key) and e.custom_key == "":
			if e.value > 0:
				add.push_back(e.key)
				add.push_back(Catalog.STAT_EXTRA_TAGS.get(e.key, ""))
		elif is_scaling(e) or is_gain_mod(e):
			if e.value > 0:
				add.push_back(e.key if is_scaling(e) else e.stat_displayed)
				# 搬运来的机制恰好也用这两个效果类（改良工具：构筑物攻速）：同样按机制 key 绑定
				add += Catalog.tags_for_binding("mech:" + (e.custom_key if e.custom_key != "" else e.key))
				if e.has_meta("aa_tags") and e.get_meta("aa_value", 0.0) > 0:
					add += e.get_meta("aa_tags")
				if is_scaling(e):
					add += Catalog.tags_for_binding("counter:" + e.stat_scaled)
					# 计数属性也是词条（每点护甲 +生命：想要护甲的角色也会想要它）
					if Catalog.STATS.has(e.stat_scaled):
						add.push_back(e.stat_scaled)
		elif is_next_wave(e):
			if e.value > 0 and Catalog.STATS.has(e.key):
				add.push_back(e.key)
		elif e.has_meta("aa_tags") and e.get_meta("aa_value") > 0:
			add += e.get_meta("aa_tags")
			add += Catalog.tags_for_binding("mech:" + (e.custom_key if e.custom_key != "" else e.key))
		# 武器伤害随某属性缩放（冰冻之心、钉子）、武器类型加成：对应属性也是词条
		if e.custom_key == "weapon_scaling_stats" and e.value > 0 and Catalog.STATS.has(e.key):
			add.push_back(e.key)
		if e.get_script() == load("res://effects/items/class_bonus_effect.gd") and e.value > 0 and Catalog.STATS.has(e.stat_displayed_name):
			add.push_back(e.stat_displayed_name)
		# 功能性词条（与正负无关，原版角色按它们筛选）：+诅咒、敌人数量增减
		if e.key in Catalog.PRESERVED_NATIVE_KEYS and e.value > 0:
			add.push_back(e.key)
		# 消耗品持续治疗（代价）：带消耗品词条（原版干肉条）
		if e.key == "consumable_heal_over_time" and e.value > 0:
			add.push_back("consumable")
		if e.key == "number_of_enemies" and e.value != 0:
			add.push_back("more_enemies" if e.value > 0 else "less_enemies")
		# 敌人速度降低（蜗牛、丑牙）：老人想要 less_enemy_speed
		if e.key == "enemy_speed" and e.value < 0 and not e is TriggerEffect:
			add.push_back("less_enemy_speed")
		for t in add:
			# 爆炸伤害 / 范围、消耗品回复、拾取范围不是原版词条，原版用 explosive / consumable / pickup（已在上面加上）
			if Catalog.STAT_EXTRA_TAGS.get(t, t) != t:
				continue
			if t != "" and not t in tags:
				tags.push_back(t)
	return tags


# 原版道具被角色禁用的"原因"：规则性原因优先（回血、下波低血开局、满血条件），否则取正面价值最大的属性。
# 例如魔像禁用肾上腺素、额外的胃、怪异幽灵，原因都是"无法回血"，而不是闪避或最大生命值。
func ban_reasons(effects: Array) -> Array:
	var rules = []
	var vals = {}
	for e in effects:
		var k = e.custom_key if e.custom_key != "" else e.key
		if k in Catalog.HEAL_KEYS or (e is TriggerEffect and e.payload == "heal"):
			rules.push_back("heal")
		elif k in ["hp_start_next_wave", "hp_start_wave"] and e.value < 0:
			rules.push_back("hp_start")
		elif k == "lose_hp_per_second" and e.value > 0:
			rules.push_back("lose_hp")
		elif k in ["consumable_stats_while_max", "temp_consumable_stats_while_max"] or (e is TriggerEffect and e.trigger == "full_hp"):
			rules.push_back("full_hp")
		elif e.value > 0 and is_plain_stat(e):
			vals[e.key] = vals.get(e.key, 0.0) + Catalog.stat_w(e.key) * e.value
	if not rules.empty():
		return rules
	var best = ""
	var top = 0.0
	for k in vals:
		if vals[k] > top:
			top = vals[k]
			best = k
	return [best] if best != "" else []


# 主属性：正面价值不低于最大者一半的属性（用于重建原版"道具组"与角色禁用）；回血载荷记为 "heal"
func main_stats(effects: Array) -> Array:
	var vals = {}
	for e in effects:
		if Catalog.WEAPON_COUNTERS.has(e.custom_key) and e.value > 0:
			vals[e.key] = vals.get(e.key, 0.0) + e.get_meta("aa_value", 5.0)
			continue
		if e.get_script() == effect_script and e.key == "next_level_xp_needed" and e.value < 0:
			vals["xp_gain"] = vals.get("xp_gain", 0.0) + e.get_meta("aa_value", 10.0)
			continue
		if e.value <= 0:
			continue
		if e is TriggerEffect:
			if e.payload == "heal":
				vals["heal"] = vals.get("heal", 0.0) + 10.0
			elif Catalog.STATS.has(e.stat) and e.payload in ["temp_stat", "perm_stat", "timed_stat"]:
				vals[e.stat] = vals.get(e.stat, 0.0) + 10.0
		elif is_plain_stat(e):
			vals[e.key] = vals.get(e.key, 0.0) + Catalog.stat_w(e.key) * e.value
		elif is_scaling(e):
			vals[e.key] = vals.get(e.key, 0.0) + Valuation.scaling_value(e.key, e.value, e.stat_scaled, e.nb_stat_scaled)
		elif is_gain_mod(e) and e.stats_modified.size() > 0:
			vals[e.stats_modified[0]] = vals.get(e.stats_modified[0], 0.0) + Valuation.gain_mod_value(e.stats_modified[0], e.value)
		elif e.key == "weapon_slot" or e.key == "weapon_slot_upgrades":
			vals["weapon_slot"] = vals.get("weapon_slot", 0.0) + Catalog.WEAPON_SLOT_W
		elif is_next_wave(e) and Catalog.STATS.has(e.key):
			vals[e.key] = vals.get(e.key, 0.0) + e.get_meta("aa_value", 5.0)
		elif e.has_meta("aa_value"):
			var k = e.custom_key if e.custom_key != "" else e.key
			if k in Catalog.HEAL_KEYS:
				vals["heal"] = vals.get("heal", 0.0) + e.get_meta("aa_value")
	var top = _max_value(vals)
	var out = []
	for k in vals:
		if vals[k] >= top * 0.5:
			out.push_back(k)
	# 规则性语义：任何回血 / 低血开局 / 满血条件都记录（不要求是主效果）
	for e in effects:
		var k = e.custom_key if e.custom_key != "" else e.key
		var r = ""
		if (e is TriggerEffect and e.payload == "heal" and e.value > 0) or (k in Catalog.HEAL_KEYS and e.value > 0):
			r = "heal"
		elif k in ["hp_start_next_wave", "hp_start_wave"] and e.value < 0:
			r = "hp_start"
		elif k == "lose_hp_per_second" and e.value > 0:
			r = "lose_hp"
		elif e is TriggerEffect and e.trigger == "full_hp":
			r = "full_hp"
		if r != "" and not r in out:
			out.push_back(r)
	return out


func _note_clause(c: Dictionary) -> void:
	var k = c.trigger + "/" + c.payload
	used_combo[k] = used_combo.get(k, 0) + 1
	used_trigger[c.trigger] = used_trigger.get(c.trigger, 0) + 1
	used_payload[c.payload] = used_payload.get(c.payload, 0) + 1


# 自由触发的"获得效果"：从可缩放机制 / 计数型 / 属性修改中选一条"单位"效果。
# 返回 {effect, unit（单位价值）, max_units}；temp 模式只选战斗中实时生效的机制
func _pick_grant(mode: String) -> Dictionary:
	var kinds = {"mechanic": 0.5, "scaling": 0.3, "gain_mod": 0.2}
	for _attempt in 4:
		var kind = _pick_weighted(kinds)
		if kind == "mechanic":
			var pool = []
			for t in 4:
				for m in mechanics_by_tier[t]:
					var e = m.effect
					if m.down or m.get("mirror", false) or not m.get("scalar", false) or e.get_script() != effect_script or e.storage_method != 0 or e.custom_key != "":
						continue
					if e.key in Catalog.GRANT_BANNED_KEYS:
						continue
					if mode == "temp" and not e.key in Catalog.GRANT_TEMP_KEYS:
						continue
					pool.push_back(m)
			if pool.empty():
				continue
			var m = pool[rng.randi() % pool.size()]
			var tmpl = m.effect.duplicate()
			var native_v = m.effect.value
			tmpl.value = 1 if native_v > 0 else -1
			var tags = m.get("tags", [])
			tmpl.set_meta("aa_tags", tags)
			var max_units = max(1.0, ceil(abs(native_v) * 1.5))
			# 几率类：单次获得的数量不超过 100%（价值按单位计，数量受限即价值受限）
			if Catalog.pct_cap(tmpl) > 0:
				max_units = min(max_units, Catalog.pct_cap(tmpl))
			return {"effect": tmpl, "unit": abs(m.value) / max(1.0, abs(native_v)), "max_units": int(max_units)}
		elif kind == "scaling":
			var cw = {}
			for c in Catalog.COUNTER_TEXT:
				if mode == "temp" or not c in ["living_enemy", "burning_enemy", "living_tree"]:
					cw[c] = 0.6 + counter_prior.get(c, 0.0)
			for st in Catalog.SCALING_STATS:
				cw[st] = 0.15 * stat_pos_w.get(st, 0.5) / 5.0 + counter_prior.get(st, 0.0)
			var counter = _pick_weighted(cw)
			var allowed = []
			for st in Catalog.SCALING_STATS:
				if st != counter:
					allowed.push_back(st)
			var stat = _pick_stat(false, [], allowed)
			var unit = Catalog.stat_unit(stat)
			var nb = 1 if counter in Catalog.COUNTER_NB_FIXED else _nice_nb(Valuation.scaling_value(stat, unit, counter, 1) / 4.0)
			var e = scaling_script.new()
			e.key = stat
			e.key_hash = Keys.generate_hash(stat)
			e.custom_key_hash = Keys.generate_hash("")
			e.value = unit
			e.stat_scaled = counter
			e.stat_scaled_hash = Keys.generate_hash(counter)
			e.nb_stat_scaled = nb
			e.perm_stats_only = Catalog.STATS.has(counter) and rng.randf() < 0.5
			e.text_key = Catalog.counter_text(counter, e.perm_stats_only)
			e.effect_sign = Effect.Sign.FROM_VALUE
			return {"effect": e, "unit": Valuation.scaling_value(stat, unit, counter, nb), "max_units": 5}
		else:
			var stat = _pick_stat(false, [], Catalog.GAIN_MOD_STATS)
			var e = gain_mod_script.new()
			e.key = "effect_increase_stat_gains"
			e.key_hash = Keys.generate_hash(e.key)
			e.custom_key_hash = Keys.generate_hash("")
			e.value = 5
			e.stat_displayed = stat
			e.stats_modified = [stat]
			e.effect_sign = Effect.Sign.FROM_VALUE
			return {"effect": e, "unit": Valuation.gain_mod_value(stat, 5), "max_units": 10}
	return {}


# ============================================================
# 下一波（原版芹菜茶 / 孔雀）：一次性，下一波开始时生效一次。约一半附带同一行为下的负面行。
# 返回 {effects, value}（value 已扣除负面折算）
# ============================================================
func _next_wave_effect(stat: String, value: int) -> Effect:
	var e = effect_script.new()
	e.key = stat
	e.key_hash = Keys.generate_hash(stat)
	e.custom_key = "stats_next_wave"
	e.custom_key_hash = Keys.generate_hash("stats_next_wave")
	e.storage_method = Effect.StorageMethod.KEY_VALUE
	e.text_key = "effect_stat_next_wave"
	e.value = value
	# 敌人属性提高是坏事：按原版固定显示为负面颜色
	e.effect_sign = Effect.Sign.NEGATIVE if Catalog.ENEMY_STATS.has(stat) else Effect.Sign.FROM_VALUE
	return e


func gen_next_wave(target: float, perm_mult: float, allow_pair: bool) -> Dictionary:
	var W = Catalog.remaining_waves(perm_mult)
	var kinds = Catalog.NEXT_WAVE_POS_KINDS.duplicate()
	if cfg.get("more_double", false):
		kinds["enemy_down"] = 0.3
	var kind = _pick_weighted(kinds)
	var pair = allow_pair and kind != "enemy_down" and rng.randf() < Catalog.NEXT_WAVE_PAIR_CHANCE
	var comp = target * rng.randf_range(0.3, 0.6) if pair else 0.0
	var out = []
	var value = 0.0
	var capped = false
	if kind == "enemy_down":
		# 下一波敌人属性降低：一波的价值 = 整局价值 / 剩余波数
		var ek = Catalog.ENEMY_STATS.keys()[rng.randi() % Catalog.ENEMY_STATS.size()]
		var wn = Catalog.stat_w(ek) / W
		var vn = int(clamp(round((target + comp) / wn / 5.0) * 5, 5, Catalog.NEXT_WAVE_ENEMY_DOWN_MAX))
		var en = _next_wave_effect(ek, -vn)
		en.effect_sign = Effect.Sign.POSITIVE
		value = vn * wn
		capped = vn == Catalog.NEXT_WAVE_ENEMY_DOWN_MAX
		en.set_meta("aa_value", value)
		out.push_back(en)
	elif kind == "loot_aliens":
		var n = int(clamp(round((target + comp) / _loot_alien_value()), 1, 4))
		var e = effect_script.new()
		e.key = "extra_loot_aliens_next_wave"
		e.key_hash = Keys.generate_hash(e.key)
		e.custom_key_hash = Keys.generate_hash("")
		e.text_key = "effect_extra_loot_aliens_next_wave"
		e.value = n
		value = n * _loot_alien_value()
		e.set_meta("aa_value", value)
		e.set_meta("aa_tags", Catalog.tags_for_binding("mech:extra_loot_aliens_next_wave"))
		out.push_back(e)
	else:
		var stat = "xp_gain"
		var unit = Catalog.stat_unit(stat)
		var raw = (target + comp) * W / Catalog.stat_w(stat)
		var top = _line_cap(stat, false) * 2
		var v = int(max(unit, round(raw / unit) * unit))
		if v > top:
			# 下一波经验每 1% 很便宜，预算常远超上限：不再一律取上限，而是在上限的 40%–100% 间随机（取 5 的倍数），
			# 剩余预算留给道具的其他行；成对的代价按比例缩小
			v = int(max(5, round(top * rng.randf_range(0.4, 1.0) / 5.0) * 5))
			capped = true
		value = Valuation.next_wave_value(stat, v, perm_mult)
		if capped and pair:
			comp = min(comp, value * rng.randf_range(0.3, 0.6))
		var e2 = _next_wave_effect(stat, v)
		e2.set_meta("aa_value", value)
		out.push_back(e2)
	if pair:
		var side = _next_wave_side(comp, perm_mult, ["xp_gain"])
		if not side.empty():
			out.push_back(side.effect)
			value -= side.value
	if (value < target * 0.4 and not capped) or value > target * 1.6 or value <= 0.0:
		return {}
	return {"effects": out, "value": value}


# 每个额外战利品外星人的价值：优先取原版机制池的单位价值（诱饵），否则用目录默认值
func _loot_alien_value() -> float:
	for t in 4:
		for m in mechanics_by_tier[t]:
			if m.effect.key == "extra_loot_aliens_next_wave" and m.effect.value != 0:
				return max(2.0, abs(m.value) / abs(m.effect.value))
	return Catalog.LOOT_ALIEN_VALUE


# ============================================================
# 来自角色、默认进入道具池的效果。返回 {effect, value}
# ============================================================
var char_templates: Dictionary = {}		# 原版角色效果模板：class_bonus（列表）/ pacifist / burn_bonus / group_structures
# 全部角色效果："商店总是出售"的候选（一级、可掉落的道具 ID）
var guaranteed_candidates: Array = []


func _collect_char_templates(characters: Array, items: Array = []) -> void:
	char_templates = {"class_bonus": [], "weapon_counters": {}, "beta": {}}
	var class_script = load("res://effects/items/class_bonus_effect.gd")
	# 全部角色效果：按 key（列表型按 custom_key）收集模板
	var beta_keys = Catalog.BETA_RESTRICTIONS.keys() + Catalog.BETA_BUNDLES.values() + [
		"all_weapons_count_for_sets", "minimum_weapons_in_shop", "weapon_slot_upgrades", "item_steals",
		"item_steals_spawns_random_elite",
	]
	for ch in characters:
		for e in ch.effects:
			var bk = e.key
			if e.custom_key in ["remove_shop_items", "guaranteed_shop_items"]:
				bk = e.custom_key
				if e.custom_key == "remove_shop_items" and e.key != "structure":
					continue
			elif e.get_script() == scaling_script and e.stat_scaled.begins_with("item_"):
				bk = "item_counter"
			if (bk in beta_keys or bk in ["guaranteed_shop_items", "item_counter"]) and not char_templates.beta.has(bk):
				char_templates.beta[bk] = e
	guaranteed_candidates = []
	for it in items:
		if it.tier == 0 and it.can_be_looted and not it is CharacterData and not it is WeaponData 				and not it.my_id in Catalog.ANCHORED_ITEMS and not it.my_id in run_excluded_ids:
			guaranteed_candidates.push_back(it.my_id)
	guaranteed_candidates.sort()
	for src in items + characters:
		for e in src.effects:
			if Catalog.WEAPON_COUNTERS.has(e.custom_key) and not char_templates.weapon_counters.has(e.custom_key):
				char_templates.weapon_counters[e.custom_key] = e
	for ch in characters:
		for e in ch.effects:
			if e.key == "cryptid" and e.value > 0:
				char_templates["cryptid"] = e
			elif e.custom_key == "charm_on_hit" and e.key != "":
				char_templates["charm"] = e
			elif e.key == "beast_master_effect":
				char_templates["beast_master"] = e
			elif e.key == "map_size":
				char_templates["map_size"] = e
			elif e.custom_key == "specific_items_price" and e.value < 0:
				char_templates["self_price"] = e
			elif e.key == "weapons_price" and e.value < 0:
				char_templates["weapons_price"] = e
			elif e.key == "items_price" and e.value > 0:
				char_templates["items_price_up"] = e
			if e.get_script() == class_script:
				char_templates.class_bonus.push_back(e)
			elif e.key == "pacifist" and e.value > 0:
				char_templates["pacifist"] = e
			elif e.key == "bonus_non_elemental_damage_against_burning_targets" and e.value > 0:
				char_templates["burn_bonus"] = e
			elif e.key == "group_structures":
				char_templates["group_structures"] = e


func gen_char_component(target: float, holder = null) -> Dictionary:
	var weights = Catalog.CHAR_COMPONENT_WEIGHTS.duplicate()
	if cfg.get("char_effects", false):
		for k in Catalog.MORE_CHAR_COMPONENT_WEIGHTS:
			weights[k] = Catalog.MORE_CHAR_COMPONENT_WEIGHTS[k]
	if cfg.get("more_double", false):
		weights["enemy_decay"] = 0.1
	if cfg.get("all_char_effects", false):
		for k in Catalog.BETA_POSITIVE_WEIGHTS:
			weights[k] = Catalog.BETA_POSITIVE_WEIGHTS[k]
	var pm: float = Catalog.PERM_MULT[holder.tier] if holder != null else Catalog.PERM_MULT[2]
	for _attempt in 6:
		var kind = _pick_weighted(weights)
		if kind in Catalog.BETA_POSITIVE_WEIGHTS:
			var bp = _gen_beta_positive(kind, target, pm, holder)
			if bp.empty():
				continue
			return bp
		match kind:
			"enemy_decay":
				# 每波结束时敌人生命 / 伤害 -X%（船长的反面，逐波累积）
				var ek = ["enemy_health", "enemy_damage"][rng.randi() % 2]
				var wd = Catalog.stat_w(ek) * pm
				var vd = int(clamp(round(target / wd), 1, Catalog.ENEMY_DECAY_MAX))
				if vd * wd > target * 1.6:
					continue
				var ed = effect_script.new()
				ed.key = ek
				ed.key_hash = Keys.generate_hash(ek)
				ed.custom_key = "stats_end_of_wave"
				ed.custom_key_hash = Keys.generate_hash("stats_end_of_wave")
				ed.storage_method = Effect.StorageMethod.KEY_VALUE
				ed.text_key = "effect_gain_stat_end_of_wave"
				ed.value = -vd
				ed.effect_sign = Effect.Sign.POSITIVE
				ed.set_meta("aa_value", vd * wd)
				ed.set_meta("aa_tags", [])
				return {"effect": ed, "value": vd * wd}
			"cryptid":
				if not char_templates.has("cryptid"):
					continue
				var per = Catalog.CRYPTID_TREES * (Catalog.GOLD_W + Catalog.XP_W)
				var vc = int(clamp(round(target / per), 1, 20))
				var ec = char_templates.cryptid.duplicate()
				ec.value = vc
				var valc = vc * per
				ec.set_meta("aa_value", valc)
				ec.set_meta("aa_tags", ["economy", "exploration"])
				return {"effect": ec, "value": valc}
			"charm":
				if not char_templates.has("charm"):
					continue
				var vh = int(clamp(round(target / Catalog.CHARM_W / 5.0) * 5, 5, 75))
				var eh = char_templates.charm.duplicate()
				eh.value = vh
				var valh = vh * Catalog.CHARM_W
				eh.set_meta("aa_value", valh)
				eh.set_meta("aa_tags", [])
				return {"effect": eh, "value": valh}
			"beast_master":
				if not char_templates.has("beast_master") or target > Catalog.BEAST_MASTER_VALUE * 2.5:
					continue
				var eb = char_templates.beast_master.duplicate()
				eb.set_meta("aa_value", Catalog.BEAST_MASTER_VALUE)
				eb.set_meta("aa_tags", ["pet"])
				return {"effect": eb, "value": Catalog.BEAST_MASTER_VALUE}
			"map_size":
				# 价值约为 0：作为附带行（只占很少的预算）
				if not char_templates.has("map_size"):
					continue
				var em = char_templates.map_size.duplicate()
				em.value = Catalog.MAP_SIZE_VALUES[rng.randi() % Catalog.MAP_SIZE_VALUES.size()]
				var valm = abs(em.value) * Catalog.MAP_SIZE_W
				em.set_meta("aa_value", valm)
				em.set_meta("aa_tags", [])
				return {"effect": em, "value": valm}
			"self_price":
				if not char_templates.has("self_price") or holder == null:
					continue
				var es = char_templates.self_price.duplicate()
				es.key = holder.my_id
				es.key_hash = Keys.generate_hash(holder.my_id)
				es.value = -100
				var vals = item_budget(holder) * Catalog.SELF_PRICE_SHARE
				if vals > target * 1.6:
					continue
				es.set_meta("aa_value", vals)
				es.set_meta("aa_tags", ["economy"])
				return {"effect": es, "value": vals}
			"weapons_price":
				if not char_templates.has("weapons_price"):
					continue
				var per_w = Catalog.WEAPON_SPEND_PER_WAVE / 100.0 * Catalog.GOLD_W
				var vw = int(clamp(round(target / per_w / 5.0) * 5, 5, 50))
				var ew = char_templates.weapons_price.duplicate()
				ew.value = -vw
				var valw = vw * per_w
				ew.set_meta("aa_value", valw)
				ew.set_meta("aa_tags", ["economy"])
				return {"effect": ew, "value": valw}
			"class_bonus":
				var cb = _gen_class_bonus(target, false)
				if cb.empty():
					continue
				return cb
			"burn_bonus":
				if not char_templates.has("burn_bonus"):
					continue
				var e2 = char_templates.burn_bonus.duplicate()
				var v2 = int(clamp(round(target / Catalog.BURN_BONUS_W / 10.0) * 10, 10, 200))
				e2.value = v2
				var val2 = v2 * Catalog.BURN_BONUS_W
				e2.set_meta("aa_value", val2)
				e2.set_meta("aa_tags", Catalog.tags_for_binding("mech:bonus_non_elemental_damage_against_burning_targets"))
				return {"effect": e2, "value": val2}
			"pacifist":
				if not char_templates.has("pacifist"):
					continue
				var e3 = char_templates.pacifist.duplicate()
				var v3 = int(clamp(round(target / Catalog.PACIFIST_W / 5.0) * 5, 5, 65))
				e3.value = v3
				var val3 = v3 * Catalog.PACIFIST_W
				e3.set_meta("aa_value", val3)
				e3.set_meta("aa_tags", Catalog.tags_for_binding("mech:pacifist"))
				return {"effect": e3, "value": val3}
			"weapon_slot":
				if target < Catalog.WEAPON_SLOT_W * 0.6:
					continue
				var e4 = _stat_effect("weapon_slot", 2 if target >= Catalog.WEAPON_SLOT_W * 1.8 else 1)
				var val4 = e4.value * Catalog.WEAPON_SLOT_W
				e4.set_meta("aa_value", val4)
				e4.set_meta("aa_tags", [])
				return {"effect": e4, "value": val4}
			"xp_needed":
				# 目标价值 -> 等价获得经验 g% -> 所需经验 X% = 100/(1+g%) - 100（反比例）
				var g = target / Catalog.stat_w("xp_gain")
				var x = int(round(Catalog.xp_needed_for_equiv(g) / 5.0) * 5)
				x = int(clamp(x, Catalog.XP_NEEDED_MIN, -5))
				var e6 = _xp_needed_effect(x)
				var val6 = Catalog.stat_w("xp_gain") * Catalog.xp_needed_equiv_pct(x)
				e6.set_meta("aa_value", val6)
				e6.set_meta("aa_tags", ["xp_gain"])
				return {"effect": e6, "value": val6}
			"group_structures":
				if not char_templates.has("group_structures") or target > Catalog.GROUP_STRUCTURES_VALUE * 2.5:
					continue
				var e5 = char_templates.group_structures.duplicate()
				e5.set_meta("aa_value", Catalog.GROUP_STRUCTURES_VALUE)
				e5.set_meta("aa_tags", Catalog.tags_for_binding("mech:group_structures"))
				return {"effect": e5, "value": Catalog.GROUP_STRUCTURES_VALUE}
	return {}


# ============================================================
# 全部角色效果（BETA）：正面效果。返回 {effect, effects（全部行）, value}
# ============================================================
func _beta_tmpl(k: String):
	return char_templates.get("beta", {}).get(k, null)


func _beta_line(tmpl, value, aa_value: float, tags: Array = []):
	var e = tmpl.duplicate()
	e.value = value
	e.set_meta("aa_value", aa_value)
	e.set_meta("aa_tags", tags)
	return e


func _gen_beta_positive(kind: String, target: float, pm: float, holder) -> Dictionary:
	match kind:
		"all_weapons_sets":
			var t = _beta_tmpl("all_weapons_count_for_sets")
			var val = Catalog.ALL_WEAPONS_SETS_VALUE
			if t == null or target < val * 0.4 or target > val * 2.5:
				return {}
			var e = _beta_line(t, 1, val)
			return {"effect": e, "effects": [e], "value": val}
		"min_weapons_shop":
			var t = _beta_tmpl("minimum_weapons_in_shop")
			var val = Catalog.MIN_WEAPONS_SHOP_VALUE
			if t == null or target > val * 3.0:
				return {}
			var e = _beta_line(t, 1, val)
			return {"effect": e, "effects": [e], "value": val}
		"weapon_slot_upgrades":
			var t = _beta_tmpl("weapon_slot_upgrades")
			if t == null or target < Catalog.WEAPON_SLOT_UPGRADE_NET * 0.6:
				return {}
			var k = int(clamp(round(target / Catalog.WEAPON_SLOT_UPGRADE_NET), 1, 3))
			var val = k * Catalog.WEAPON_SLOT_UPGRADE_NET
			# 设定值：诅咒不放大（上限翻倍会让之后每次升级都变成武器栏）
			var e = _beta_line(t, 6 + k, val)
			e.effect_sign = Effect.Sign.NEUTRAL
			return {"effect": e, "effects": [e], "value": val}
		"item_steals":
			var t = _beta_tmpl("item_steals")
			var t2 = _beta_tmpl("item_steals_spawns_random_elite")
			var val = Catalog.ITEM_STEAL_PER_WAVE * pm
			if t == null or t2 == null or target < val * 0.6 or target > val * 1.8:
				return {}
			var e = _beta_line(t, 1, val, ["economy"])
			var e2 = t2.duplicate()
			return {"effect": e, "effects": [e, e2], "value": val}
		"guaranteed_item":
			var t = _beta_tmpl("guaranteed_shop_items")
			var tc = _beta_tmpl("item_counter")
			if t == null or tc == null or guaranteed_candidates.empty():
				return {}
			var x = guaranteed_candidates[rng.randi() % guaranteed_candidates.size()]
			if holder != null and x == holder.my_id:
				return {}
			var stat = _pick_stat(false, [], Catalog.SCALING_STATS)
			var unit = Catalog.stat_unit(stat)
			var per = Catalog.stat_w(stat) * unit * Catalog.counter_ref(x)
			var n = int(clamp(round(target / per), 1, 5))
			var val = n * per
			if val > target * 1.6:
				return {}
			var e = t.duplicate()
			e.key = x
			e.key_hash = Keys.generate_hash(x)
			e.set_meta("aa_value", 0.0)
			e.set_meta("aa_tags", [])
			var e2 = tc.duplicate()
			e2.key = stat
			e2.key_hash = Keys.generate_hash(stat)
			e2.value = n * unit
			e2.stat_scaled = x
			e2.stat_scaled_hash = Keys.generate_hash(x)
			e2.nb_stat_scaled = 1
			e2.set_meta("aa_value", val)
			e2.set_meta("aa_tags", [stat])
			return {"effect": e2, "effects": [e, e2], "value": val}
	return {}


# 全部角色效果（BETA）：重大限制作为代价。返回 {effects, value（换来的预算）}；budget_total 用于限制大代价只出现在高预算道具上
func gen_beta_restriction(comp: float, budget_total: float) -> Dictionary:
	var w = {}
	for k in Catalog.BETA_RESTRICTIONS:
		var r = Catalog.BETA_RESTRICTIONS[k]
		var tk = "remove_shop_items" if k == "remove_shop_items" else k
		if _beta_tmpl(tk) == null or budget_total < r.min_budget or r.got > max(comp * 4.0, budget_total * 1.2):
			continue
		if Catalog.BETA_BUNDLES.has(k) and _beta_tmpl(Catalog.BETA_BUNDLES[k]) == null:
			continue
		# 与预算越接近越常见
		w[k] = r.w / (1.0 + abs(log(max(0.5, r.got) / max(0.5, comp))))
	var k = _pick_weighted(w)
	if k == null:
		return {}
	var got: float = Catalog.BETA_RESTRICTIONS[k].got
	var tmpl = _beta_tmpl(k)
	var e = tmpl.duplicate()
	if k == "poisoned_fruit":
		var v = int(clamp(round(comp / got * tmpl.value / 5.0) * 5, 10, 50))
		e.value = v
		got = got * float(v) / float(tmpl.value)
	e.set_meta("aa_value", -got)
	e.set_meta("aa_tags", [])
	var out = [e]
	if Catalog.BETA_BUNDLES.has(k):
		var e2 = _beta_tmpl(Catalog.BETA_BUNDLES[k]).duplicate()
		e2.set_meta("aa_value", 0.0)
		e2.set_meta("aa_tags", [])
		out.push_back(e2)
	# 设定值型上限（近战 / 远程武器数、最高武器等级）：诅咒不改（原版会把上限当作负面减小，反而更严）
	for x in out:
		if x.key in ["max_melee_weapons", "max_ranged_weapons", "max_weapon_tier", "min_weapon_tier"]:
			x.effect_sign = Effect.Sign.NEUTRAL
	return {"effects": out, "value": got}


# 道具价格每 1% 的价值：取原版优惠券（-5% 道具价格）在机制池中的单位价值
func _items_price_value_per_pct() -> float:
	for t in 4:
		for m in mechanics_by_tier[t]:
			if m.effect.key == "items_price" and m.effect.value != 0:
				return abs(m.value) / abs(m.effect.value)
	return 0.0


# 武器数量计数："每把 [不同 / 所有 / IV 级 / I 级] 武器 +X [属性]"（原版角色 / 道具效果）
func gen_weapon_counter(target: float, negative: bool) -> Dictionary:
	var kinds = char_templates.get("weapon_counters", {}).keys()
	if kinds.empty():
		return {}
	for _attempt in 4:
		var kind = kinds[rng.randi() % kinds.size()]
		var stat = _pick_stat(negative, [], Catalog.SCALING_STATS)
		var unit = Catalog.stat_unit(stat)
		var per = Catalog.stat_w(stat) * unit * Catalog.WEAPON_COUNTERS[kind]
		var n = int(round(abs(target) / per))
		if n < 1 or n > 6:
			continue
		var e = char_templates.weapon_counters[kind].duplicate()
		e.key = stat
		e.key_hash = Keys.generate_hash(stat)
		e.value = n * unit * (-1 if negative else 1)
		e.effect_sign = Effect.Sign.FROM_VALUE
		var val = n * per
		e.set_meta("aa_value", -val if negative else val)
		e.set_meta("aa_tags", [stat] if not negative else [])
		return {"effect": e, "value": -val if negative else val}
	return {}


func _xp_needed_effect(x: int) -> Effect:
	var e = effect_script.new()
	e.key = "next_level_xp_needed"
	e.key_hash = Keys.generate_hash(e.key)
	e.custom_key_hash = Keys.generate_hash("")
	e.value = x
	# 所需经验降低是好事：显式标注正负（原版变异体为 POSITIVE），原版诅咒据此加强好处 / 减弱代价
	e.effect_sign = Effect.Sign.POSITIVE if x < 0 else Effect.Sign.NEGATIVE
	return e


# 代价：每波结束时敌人属性提高（船长），或 −1 武器栏。返回 {effects, value（折算后的补偿）}
func gen_char_downside(comp: float, perm_mult: float, budget_total: float = -1.0) -> Dictionary:
	var more = cfg.get("char_effects", false)
	if cfg.get("all_char_effects", false) and budget_total > 0.0 and rng.randf() < Catalog.BETA_RESTRICTION_CHANCE:
		var br = gen_beta_restriction(comp, budget_total)
		if not br.empty():
			return br
	# 更多角色效果：道具价格 +X%（变异体 / 节俭者）
	if (more or cfg.get("more_double", false)) and char_templates.has("items_price_up") and rng.randf() < Catalog.MORE_CHAR_DOWNSIDE_CHANCE * 0.5:
		var per_p = _items_price_value_per_pct()
		if per_p > 0.0:
			var xp_ = int(clamp(round(comp * divisor / per_p / 5.0) * 5, 5, 50))
			var ep = char_templates.items_price_up.duplicate()
			ep.value = xp_
			var got_p = neg_value(per_p * xp_)
			ep.set_meta("aa_value", -got_p)
			return {"effects": [ep], "value": got_p}
	# 更多角色效果：升级所需经验 +X%：等价于获得经验降低 1 - 1/(1+X%)
	if more and rng.randf() < Catalog.MORE_CHAR_DOWNSIDE_CHANCE * 0.5:
		var g = -comp * divisor / Catalog.stat_w("xp_gain")
		if g > -80.0:
			var x = int(clamp(round(Catalog.xp_needed_for_equiv(g) / 5.0) * 5, 5, Catalog.XP_NEEDED_MAX))
			var ex = _xp_needed_effect(x)
			var got_x = neg_value(abs(Catalog.stat_w("xp_gain") * Catalog.xp_needed_equiv_pct(x)))
			ex.set_meta("aa_value", -got_x)
			return {"effects": [ex], "value": got_x}
	var double = cfg.get("more_double", false)
	if double and rng.randf() < 0.35:
		var dd = _gen_double_char_downside(comp)
		if not dd.empty():
			return dd
	# -1 武器栏只在"更多双面效果"开启时出现（常规池只有 +1 武器栏）
	if double and comp >= Catalog.WEAPON_SLOT_W / divisor * 0.7 and comp <= Catalog.WEAPON_SLOT_W / divisor * 1.5 and rng.randf() < 0.3:
		var e = _stat_effect("weapon_slot", -1)
		var got = neg_value(Catalog.WEAPON_SLOT_W)
		e.set_meta("aa_value", -got)
		return {"effects": [e], "value": got}
	var keys = Catalog.ENEMY_STATS.keys()
	var stat = keys[rng.randi() % keys.size()]
	var w = Catalog.stat_w(stat)
	var v = int(clamp(round(comp * divisor / (w * perm_mult)), 1, 5))
	var e2 = effect_script.new()
	e2.key = stat
	e2.key_hash = Keys.generate_hash(stat)
	e2.custom_key = "stats_end_of_wave"
	e2.custom_key_hash = Keys.generate_hash("stats_end_of_wave")
	e2.storage_method = Effect.StorageMethod.KEY_VALUE
	e2.text_key = "effect_gain_stat_end_of_wave"
	e2.value = v
	e2.effect_sign = Effect.Sign.NEGATIVE
	var got2 = neg_value(w * v * perm_mult)
	e2.set_meta("aa_value", -got2)
	return {"effects": [e2], "value": got2}


# 武器类型加成：使用 [类型] 武器 ±X [属性]（catalog.CLASS_BONUS_KINDS）。返回 {effect, value}（value 带符号）
func _gen_class_bonus(target: float, negative: bool) -> Dictionary:
	if char_templates.class_bonus.empty() or ItemService.sets.empty():
		return {}
	var kinds = []
	for k in Catalog.CLASS_BONUS_KINDS:
		# 贯通为负可能低于 0：只作为好处
		if not (negative and Catalog.CLASS_BONUS_KINDS[k].get("ranged_only", false)):
			kinds.push_back(k)
	var disp = kinds[rng.randi() % kinds.size()]
	var kd = Catalog.CLASS_BONUS_KINDS[disp]
	var ranged = _ranged_only_sets()
	var sets = []
	for st in ItemService.sets:
		if st.my_id == "set_legendary":
			continue
		if kd.get("ranged_only", false) and not st.my_id in ranged:
			continue
		sets.push_back(st)
	if sets.empty():
		return {}
	var chosen = sets[rng.randi() % sets.size()]
	var per = kd.w * Catalog.CLASS_BONUS_SHARE
	var v = int(clamp(round(abs(target) / per / kd.unit) * kd.unit, kd.unit, kd.max))
	var e = char_templates.class_bonus[0].duplicate()
	e.stat_displayed_name = disp
	e.stat_name = kd.name
	e.stat_hash = Keys.generate_hash(kd.name)
	e.set_id = chosen.my_id
	e.set_id_hash = Keys.generate_hash(chosen.my_id)
	e.value = -v if negative else v
	e.effect_sign = Effect.Sign.FROM_VALUE
	var val = per * v
	var tag = "stat_crit_chance" if disp == "stat_crit_damage" else ("stat_ranged_damage" if disp == "piercing" else disp)
	e.set_meta("aa_value", -val if negative else val)
	e.set_meta("aa_tags", [tag] if Catalog.STATS.has(tag) and not negative else [])
	return {"effect": e, "value": -val if negative else val}


# 只包含远程武器的武器类型（可以加贯通）
var _ranged_sets_cache = null


func _ranged_only_sets() -> Array:
	if _ranged_sets_cache != null:
		return _ranged_sets_cache
	var types = {}
	for w in ItemService.weapons:
		for st in w.sets:
			if not types.has(st.my_id):
				types[st.my_id] = {}
			types[st.my_id][w.type] = true
	_ranged_sets_cache = []
	for id in types:
		if types[id].size() == 1 and types[id].has(WeaponType.RANGED):
			_ranged_sets_cache.push_back(id)
	return _ranged_sets_cache


# 更多双面效果的代价：-X% [类型] 武器属性、+X% 武器价格
func _gen_double_char_downside(comp: float) -> Dictionary:
	if rng.randf() < 0.5:
		var cb = _gen_class_bonus(comp * divisor, true)
		if not cb.empty():
			var got = neg_value(abs(cb.value))
			cb.effect.set_meta("aa_value", -got)
			cb.effect.set_meta("aa_tags", [])
			return {"effects": [cb.effect], "value": got}
	if char_templates.has("weapons_price"):
		var per_w = Catalog.WEAPON_SPEND_PER_WAVE / 100.0 * Catalog.GOLD_W
		var vw = int(clamp(round(comp * divisor / per_w / 5.0) * 5, 5, 50))
		var ew = char_templates.weapons_price.duplicate()
		ew.value = vw
		ew.effect_sign = Effect.Sign.NEGATIVE
		var got_w = neg_value(vw * per_w)
		ew.set_meta("aa_value", -got_w)
		ew.set_meta("aa_tags", [])
		return {"effects": [ew], "value": got_w}
	return {}


func gen_next_wave_downside(comp: float, perm_mult: float) -> Dictionary:
	var side = _next_wave_side(comp, perm_mult, [])
	if side.empty():
		return {}
	return {"effects": [side.effect], "value": side.value}


# 负面行：60% 敌人属性（生命 / 伤害 / 速度），40% 自身属性降低。返回 {effect, value（折算后的补偿，正数）}
func _next_wave_side(comp: float, perm_mult: float, exclude: Array) -> Dictionary:
	var W = Catalog.remaining_waves(perm_mult)
	var stat = ""
	var sign_v = 1
	if rng.randf() < 0.5:
		var keys = Catalog.ENEMY_STATS.keys()
		stat = keys[rng.randi() % keys.size()]
	else:
		stat = _pick_stat(true, exclude + Catalog.TEMP_STAT_BANNED, Catalog.NEXT_WAVE_STATS)
		sign_v = -1
	var w = Catalog.stat_w(stat)
	var unit = 5 if Catalog.ENEMY_STATS.has(stat) else Catalog.stat_unit(stat)
	var raw = comp * divisor * W / w
	var cap = 100 if Catalog.ENEMY_STATS.has(stat) else _line_cap(stat, true) * 2
	var v = int(clamp(round(raw / unit) * unit, unit, cap))
	var got = neg_value(w * v / W)
	var e = _next_wave_effect(stat, v * sign_v)
	e.set_meta("aa_value", -got)
	return {"effect": e, "value": got}


# 属性类触发条款的同扳机负面条款：同扳机、同门控、同载荷方式，属性换成敌人属性（50%，数值为正）
# 或自身其他属性（数值为负）；负面折算后的补偿约为正面价值的 30–60%
func _make_pair(c: Dictionary, perm_mult: float) -> Dictionary:
	# "获得提升 [属性] 的道具时"的条件属性就是效果属性，不配负面半边
	if c.trigger == "buy_stat":
		return {}
	var cv = Valuation.clause_value(c, perm_mult)
	if cv <= 0.0:
		return {}
	var stat = ""
	if rng.randf() < 0.5:
		var keys = Catalog.ENEMY_STATS.keys()
		stat = keys[rng.randi() % keys.size()]
	else:
		var banned = [c.stat, anchor_stat]
		if c.payload != "perm_stat":
			banned += Catalog.TEMP_STAT_BANNED
		stat = _pick_stat(true, banned)
	var enemy = Catalog.ENEMY_STATS.has(stat)
	var c2 = c.duplicate()
	c2.stat = stat
	c2.value = 1 if enemy else -1
	c2.erase("grant")
	var per_unit = abs(Valuation.clause_value(c2, perm_mult))
	if per_unit <= 0.0:
		return {}
	var comp = cv * rng.randf_range(0.3, 0.6)
	var cap = 10 if enemy else _line_cap(stat, true)
	if Valuation.raw_rate(c.trigger, c.param, c.chance) <= 1.5 or Catalog.TRIGGERS[c.trigger].kind == "state":
		cap *= 4
	var mag = int(clamp(round(comp * divisor / per_unit), 1, cap))
	c2.value = mag if enemy else -mag
	return c2


const NICE_NB = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100, 150, 200]


static func _nice_nb(raw: float) -> int:
	var best = 1
	for n in NICE_NB:
		if abs(log(max(0.01, raw)) - log(float(n))) < abs(log(max(0.01, raw)) - log(float(best))):
			best = n
	return best


# ============================================================
# 计数型："每有 [计数] 获得 [属性]"，计数与属性自由搭配。返回 {effect, value}（value 带符号）
# ============================================================
func gen_scaling(target: float, negative: bool) -> Dictionary:
	if rng.randf() < Catalog.WEAPON_COUNTER_CHANCE:
		var wc = gen_weapon_counter(target, negative)
		if not wc.empty():
			return wc
	for _attempt in 6:
		var cw = {}
		for c in Catalog.COUNTER_TEXT:
			cw[c] = 0.6 + counter_prior.get(c, 0.0)
			if not negative and _binding_wanted("counter:" + c):
				cw[c] *= Catalog.WANTED_BIAS
		for st in Catalog.SCALING_STATS:
			cw[st] = 0.15 * stat_pos_w.get(st, 0.5) / 5.0 + counter_prior.get(st, 0.0)
			if not negative and st in wanted_bias:
				cw[st] *= Catalog.WANTED_BIAS
		var counter = _pick_weighted(cw)
		var allowed = []
		for st in Catalog.SCALING_STATS:
			if st != counter:
				allowed.push_back(st)
		var stat = _pick_stat(negative, [], allowed)
		var unit = Catalog.stat_unit(stat)
		var per_unit_full = Valuation.scaling_value(stat, unit, counter, 1)
		var nb = _nice_nb(per_unit_full / max(0.1, abs(target)))
		var v = unit
		# 文本不显示 N 的计数：N 固定为 1；最小价值明显超过预算时（下面的区间检查）换别的计数 / 属性，全部失败则改用别的词条
		if counter in Catalog.COUNTER_NB_FIXED:
			nb = 1
		if per_unit_full < abs(target) * 0.7:
			# 每 1 个计数的价值都不够：提高数值
			nb = 1
			v = int(clamp(round(abs(target) / per_unit_full), 1, 5)) * unit
		var value = Valuation.scaling_value(stat, v, counter, nb)
		if value < abs(target) * 0.4 or value > abs(target) * 1.35:
			continue
		var e = scaling_script.new()
		e.key = stat
		e.key_hash = Keys.generate_hash(stat)
		e.custom_key_hash = Keys.generate_hash("")
		e.value = -v if negative else v
		e.stat_scaled = counter
		e.stat_scaled_hash = Keys.generate_hash(counter)
		e.nb_stat_scaled = nb
		e.perm_stats_only = Catalog.STATS.has(counter) and rng.randf() < 0.5
		e.text_key = Catalog.counter_text(counter, e.perm_stats_only)
		e.effect_sign = Effect.Sign.FROM_VALUE
		return {"effect": e, "value": -value if negative else value}
	return {}


# ============================================================
# 属性修改 ±XX%（来自角色）。返回 {effect, value}
# ============================================================
func gen_gain_mod(target: float, negative: bool) -> Dictionary:
	for _attempt in 4:
		var stat = _pick_stat(negative, [], Catalog.GAIN_MOD_STATS)
		var per_pct = Valuation.gain_mod_value(stat, 1)
		var raw = abs(target) / max(0.01, per_pct)
		var pct = 0
		var best = 1e9
		for step in Catalog.GAIN_MOD_STEPS:
			if abs(step - raw) < best:
				best = abs(step - raw)
				pct = step
		var value = Valuation.gain_mod_value(stat, pct)
		if value < abs(target) * 0.4 or value > abs(target) * 1.35:
			continue
		var e = gain_mod_script.new()
		e.key = "effect_reduce_stat_gains" if negative else "effect_increase_stat_gains"
		e.key_hash = Keys.generate_hash(e.key)
		e.custom_key_hash = Keys.generate_hash("")
		e.value = -pct if negative else pct
		e.stat_displayed = stat
		e.stats_modified = [stat]
		e.effect_sign = Effect.Sign.FROM_VALUE
		return {"effect": e, "value": -value if negative else value}
	return {}


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


const NEGATIVE_TRIGGERS = ["hit", "dodge", "kill", "interval", "still", "moving", "consumable"]


func _legal_payloads(trigger: String, negative: bool) -> Array:
	if negative:
		var neg = ["temp_stat"] if trigger in NEGATIVE_TRIGGERS else []
		# 更多双面效果：代价可以是"失去材料"
		if cfg.get("more_double", false) and trigger in Catalog.LOSE_GOLD_TRIGGERS and rng.randf() < Catalog.LOSE_GOLD_CHANCE:
			neg.push_back("gold")
		return neg
	var out = []
	var table = Catalog.FREE_LEGAL if cfg.get("free_triggers", true) else Catalog.LEGAL
	for p in table[trigger]:
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
			if t == "hit_typed" and not cfg.get("char_effects", false):
				continue
			var legal_t = _legal_payloads(t, negative)
			if legal_t.empty() or (fixed_payload != "" and not fixed_payload in legal_t):
				continue
			tw[t] = (Catalog.TRIGGERS[t].w + Catalog.NATIVE_PRIOR_STRENGTH * log(1.0 + trigger_prior[t]) / 2.0) \
				/ (1.0 + Catalog.REPEAT_PENALTY_TRIGGER * used_trigger.get(t, 0))
			if not negative and (_binding_wanted("trigger:" + t, Catalog.TRIGGER_TAGS.get(t, "")) 					or (t in Catalog.TYPED_TRIGGERS and _wanted_dmg_type())):
				tw[t] *= Catalog.WANTED_BIAS
		trigger = _pick_weighted(tw)
	if trigger == null:
		return {}
	var legal: Array = _legal_payloads(trigger, negative)
	if fixed_payload != "":
		legal = [fixed_payload] if fixed_payload in legal else []
	var pw = {}
	for p in legal:
		pw[p] = (Catalog.PAYLOADS[p].w + Catalog.NATIVE_PRIOR_STRENGTH * log(1.0 + payload_prior[p]) / 2.0) \
			/ (1.0 + Catalog.REPEAT_PENALTY_COMBO * used_combo.get(trigger + "/" + p, 0) + Catalog.REPEAT_PENALTY_PAYLOAD * used_payload.get(p, 0))
		if not negative and pos_cat != "" and Catalog.PAYLOAD_CATEGORY.get(p, "") == pos_cat:
			pw[p] *= 3.0
		if not negative and _binding_wanted("payload:" + p, Catalog.PAYLOAD_TAGS.get(p, "")):
			pw[p] *= Catalog.WANTED_BIAS
	var payload = _pick_weighted(pw)
	if payload == null:
		return {}

	var c = {"trigger": trigger, "payload": payload, "param": 1, "chance": 100, "cap": 0, "stat": "", "value": 1, "value2": 0}
	var t = Catalog.TRIGGERS[trigger]
	if trigger == "interval":
		c.param = Catalog.INTERVAL_CHOICES[rng.randi() % Catalog.INTERVAL_CHOICES.size()]
	if trigger in Catalog.TYPED_TRIGGERS:
		c.dmg_type = _pick_dmg_type()

	match payload:
		"temp_stat", "timed_stat":
			if negative and rng.randf() < Catalog.NEGATIVE_CLAUSE_ENEMY_CHANCE:
				var ek = Catalog.ENEMY_STATS.keys()
				c.stat = ek[rng.randi() % ek.size()]
				c.value = 1
			else:
				c.stat = _pick_stat(negative, Catalog.TEMP_STAT_BANNED + ([anchor_stat] if negative else []))
				c.value = Catalog.stat_unit(c.stat)
			if payload == "timed_stat":
				c.value2 = [3, 4, 5, 6, 8][rng.randi() % 5]
			if payload == "temp_stat" and t.kind == "event" and Valuation.raw_rate(trigger, 1, 100) > 6.0 and rng.randf() < 0.5:
				c.cap = [10, 15, 20, 30][rng.randi() % 4]
			if payload == "temp_stat" and not negative and t.kind == "event" and t.timing > 0.0 and t.timing < 1.0 \
					and trigger != "hit" and rng.randf() < Catalog.RESET_ON_HIT_CHANCE:
				c.reset = true
		"perm_stat":
			c.stat = _pick_stat(false)
			c.value = Catalog.stat_unit(c.stat)
			if Valuation.raw_rate(trigger, 1, 100) > 1.5:
				c.cap = 1 + rng.randi() % 3
		"heal", "gold":
			c.value = 1
		"xp":
			c.value = 3
		"grant":
			var mode = "temp"
			# 每波开始时"本波获得"= 整局一直持有该效果，与直接写在道具上无异：波初只允许"永久获得"（逐波累积）
			if t.kind == "shop" or trigger == "wave_end" or trigger == "wave_start":
				mode = "perm"
			elif t.kind == "event" and rng.randf() < 0.3:
				mode = "perm"
			var gr = _pick_grant(mode)
			if gr.empty():
				return {}
			c.grant = gr.effect
			c.grant_unit = gr.unit
			c.grant_max = gr.max_units
			c.grant_mode = mode
			c.value = 1
			if mode == "perm" and Valuation.raw_rate(trigger, 1, 100) > 1.5:
				c.cap = 1 + rng.randi() % 3
		"damage":
			c.stat = _pick_dmg_type(_pick_stat(false, [], Catalog.DAMAGE_SCALING_STATS))
			# 单次伤害可以较小：高频扳机更应该频繁触发，而不是攒很多次打一下
			c.value = [25, 50, 75, 100, 150][rng.randi() % 5]
		"explode":
			c.stat = _pick_dmg_type(_pick_stat(false, [], Catalog.DAMAGE_SCALING_STATS))
			c.value = [25, 50, 75, 100][rng.randi() % 4]
		"vuln":
			c.value = 5
			c.value2 = [2, 3, 4, 5][rng.randi() % 4]
		"hp_dmg":
			c.value = 1
		"ignite":
			c.value = 1
		"slow":
			c.value = 1
		"fruit":
			c.value = 1
		"rand_stats":
			c.value = 1
			if Valuation.raw_rate(trigger, 1, 100) > 1.5:
				c.cap = 1 + rng.randi() % 3

	# 高频扳机上的永久效果：先按预算定每波上限（2..10），再把频率调到上限的约两倍（多数波次能触发满）
	var is_perm = payload in ["perm_stat", "rand_stats"] or (payload == "grant" and c.get("grant_mode", "") == "perm")
	if is_perm and not negative and Valuation.raw_rate(trigger, 1, 100) > 1.5:
		c.cap = 1
		var per_fire = abs(Valuation.clause_value(c, perm_mult))
		if per_fire > 0.0 and per_fire * 2.0 <= budget:
			var cap = int(clamp(floor(budget / per_fire), 2, Catalog.PERM_CAP_MAX))
			c.cap = cap
			var rate = Valuation.raw_rate(trigger, 1, 100)
			# 触发频率调到上限的约两倍，且高频扳机至少 MIN_FIRES_HIGH_FREQ 次
			var want = cap * 2.0
			if t.kind == "event" and t.e >= 20.0:
				want = max(want, Catalog.MIN_FIRES_HIGH_FREQ)
			if rate > want:
				if t.gate == "every":
					c.param = int(max(1, floor(rate / want)))
				elif t.gate == "chance" or t.kind == "shop":
					c.chance = int(clamp(round(want / rate * 20.0) * 5, 5, 100))
				elif trigger == "interval":
					c.param = int(clamp(ceil(Catalog.WAVE_SECONDS / want), c.param, 30))
			if c.payload == "perm_stat":
				c.value = int(min(c.value, _line_cap(c.stat, false)))
			return c

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
		elif payload == "vuln":
			c.value = int(min(c.value * k, 50))
		elif payload == "hp_dmg":
			c.value = int(min(c.value * k, Catalog.HP_DMG_MAX))
		elif payload == "slow":
			c.value = int(min(c.value * k, Catalog.SLOW_MAX))
		elif payload == "xp":
			c.value = int(c.value * k)
		else:
			c.value = int(c.value * k)
	else:
		# 预算不足：按扳机的门控方式降低频率
		var ratio = budget / unit_v
		# 作用于目标敌人的效果只用单次 / 几率（"每 N 个敌人"中只有第 N 个被作用，不直观）
		var chance_only = payload in Catalog.TARGET_PAYLOADS
		if t.gate == "every" and (chance_only or (ratio >= 0.1 and rng.randf() < Catalog.CHANCE_GATE_ON_EVERY)):
			if ratio < 0.05:
				return {}
			c.chance = int(clamp(round(ratio * 20.0) * 5, 5, 100))
		elif t.gate == "every":
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
		# 永久属性 / 永久获得在高频扳机上再用每波上限收口
		if (payload in ["perm_stat", "rand_stats"] or (payload == "grant" and c.grant_mode == "perm")) and c.cap > 1:
			var per_fire = abs(Valuation.clause_value(c, perm_mult)) / max(0.01, Valuation.fires_per_wave(trigger, c.param, c.chance, c.cap))
			c.cap = int(clamp(floor(budget / max(0.01, per_fire)), 1, c.cap))

	# 高频扳机门槛过高（每波实际只触发几次）：换别的组合
	if t.kind == "event" and Catalog.TRIGGERS[trigger].e >= 20.0 and not negative 			and Valuation.raw_rate(trigger, c.param, c.chance) < Catalog.MIN_FIRES_HIGH_FREQ:
		return {}
	# 每隔 N 秒获得持续 M 秒的效果：M < N（否则等同于一直生效）
	if trigger == "interval" and payload == "timed_stat":
		c.value2 = int(clamp(c.value2, 1, max(1, c.param - 1)))
	# 单次触发的属性数值同样受原版单行上限约束
	if c.payload in ["temp_stat", "perm_stat", "timed_stat"]:
		c.value = int(min(c.value, _line_cap(c.stat, negative)))
	if negative:
		# 敌人属性的"代价"方向是提高（正值），自身属性 / 材料是降低（负值）
		c.value = abs(c.value) if Catalog.ENEMY_STATS.has(c.stat) else -abs(c.value)
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
		"rand_stats":
			return 8 if rate <= 1.5 else 2
		"hp_dmg":
			return Catalog.HP_DMG_MAX
		"ignite":
			return 10 if rate <= 3 else 4
		"slow":
			return Catalog.SLOW_MAX
		"fruit":
			return 3 if rate <= 3 else 1
		"timed_stat":
			return 20 if rate <= 2.0 else 8
		"heal":
			return 6
		"gold":
			# 稀有扳机（拾取箱子：原版袋子 +15 材料）允许较大的单次数值
			# 每波几次的扳机（击杀被诅咒的敌人约 5 次）也允许到 10
			return 30 if rate <= 1.5 else (10 if rate <= 6 else 3)
		"xp":
			return 20
		"damage", "explode":
			return 8
		"vuln":
			return 10
		"grant":
			var mx = int(c.get("grant_max", 5))
			if c.get("grant_mode", "temp") == "perm":
				return int(min(mx, 3 if rate <= 1.5 else 1))
			if kind == "state" or rate <= 1.5:
				return mx
			return int(min(mx, 3 if rate <= 10 else 1))
	return 5


# ============================================================
# 角色：保留身份行（初始装备、武器限制、规则、特殊机制、"禁用"某属性的 -100 / -100% 行），
# 其余可估值的行按同等价值重新组装，并偏向角色的偏好词条：
#   正面属性行 / 正面属性修改 / 正面计数 -> 属性行（偏好属性）、触发条款（偏好扳机 / 载荷）、计数型或属性修改之一
#   普通负面属性行 / 部分负面属性修改 -> 同类代价换一个非偏好属性
#   原版触发行只重组一半（保留扳机换载荷，或保留载荷换扳机），让角色仍然像自己
# ============================================================
func generate_character(ch) -> Dictionary:
	_seed_for(ch.my_id)
	var perm_mult = Catalog.PERM_MULT_CHARACTER
	banned_triggers = []
	banned_payloads = []
	wanted_bias = ch.wanted_tags.duplicate()
	for e in ch.effects:
		if e.key == "no_heal" and e.value > 0:
			banned_triggers.push_back("heal")
			banned_payloads.push_back("heal")
	var out = []
	var main_adj = ""
	var main_v = 0.0
	var used = []
	for e in ch.effects:
		if is_plain_stat(e) and e.value > 0 and e.value <= 20:
			var val = Valuation.stat_line_value(e.key, e.value) * _avg_mult()
			var r = _char_reassemble_positive(val, perm_mult, used)
			out.push_back(r.effect)
			if r.value > main_v:
				main_v = r.value
				main_adj = r.adj
			continue
		if is_plain_stat(e) and e.value < 0 and not is_disabling(e):
			var s2 = _pick_stat(true, used + [e.key] + wanted_bias)
			used.push_back(s2)
			# 同等数值强度（不按负面除数折算），换到非偏好属性上
			var mag = Catalog.stat_w(e.key) * min(abs(e.value), Catalog.counter_ref(e.key))
			var v2 = _round_to_unit(mag / Catalog.stat_w(s2), s2)
			out.push_back(_stat_effect(s2, -v2))
			continue
		if is_gain_mod(e) and e.stats_modified.size() > 0:
			# 偏好属性的正面修改（法师 +25% 元素）是角色的核心，保留
			if e.value > 0 and not e.stats_modified[0] in wanted_bias and rng.randf() < Catalog.CHAR_CONVERT_CHANCE:
				var gv = Valuation.gain_mod_value(e.stats_modified[0], e.value) * _avg_mult()
				var rg = _char_reassemble_positive(gv, perm_mult, used)
				out.push_back(rg.effect)
				if rg.value > main_v:
					main_v = rg.value
					main_adj = rg.adj
				continue
			if e.value < 0 and not is_disabling(e):
				# 部分降低（-25% .. -80%）：换一个非偏好属性，百分比不变
				var ns = _pick_stat(true, used + e.stats_modified + wanted_bias, Catalog.GAIN_MOD_STATS)
				used.push_back(ns)
				var ge = e.duplicate()
				ge.stat_displayed = ns
				ge.stats_modified = [ns]
				out.push_back(ge)
				continue
			out.push_back(e)
			continue
		if is_scaling(e) and e.value > 0 and not e.stat_scaled.begins_with("item_") and not e.key in wanted_bias 				and rng.randf() < Catalog.CHAR_CONVERT_CHANCE:
			var sv = Valuation.scaling_value(e.key, e.value, e.stat_scaled, e.nb_stat_scaled) * _avg_mult()
			var rs = _char_reassemble_positive(sv, perm_mult, used)
			out.push_back(rs.effect)
			if rs.value > main_v:
				main_v = rs.value
				main_adj = rs.adj
			continue
		var nt = native_trigger_of(e)
		if nt != null and Catalog.STATS.has(e.key) and e.value != 0 and not is_disabling(e):
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
					main_adj = _adj(Catalog.ADJ_BY_TRIGGER[c.trigger])
				continue
		out.push_back(e)
	if main_adj == "":
		main_adj = _adj(Catalog.ADJ_MECHANIC)
	banned_triggers = []
	banned_payloads = []
	wanted_bias = []
	return {"effects": out, "adj": main_adj}


# 角色的一条正面组件按价值 val 重新组装：属性行 / 触发条款 / 计数型 / 属性修改（偏向偏好词条）。返回 {effect, value, adj}
func _char_reassemble_positive(val: float, perm_mult: float, used: Array) -> Dictionary:
	var kind = _pick_weighted(Catalog.CHAR_REASSEMBLE_KINDS)
	if kind == "clause":
		var c = gen_clause(val, perm_mult, false)
		if not c.empty():
			_note_clause(c)
			return {"effect": TriggerEffect.make(c), "value": Valuation.clause_value(c, perm_mult), "adj": _adj(Catalog.ADJ_BY_TRIGGER[c.trigger])}
	elif kind == "scaling":
		var sc = gen_scaling(val, false)
		if not sc.empty():
			return {"effect": sc.effect, "value": sc.value, "adj": _adj(Catalog.ADJ_SCALING)}
	elif kind == "gain_mod":
		var gm = gen_gain_mod(val, false)
		if not gm.empty():
			return {"effect": gm.effect, "value": gm.value, "adj": _adj(Catalog.ADJ_GAIN_MOD)}
	var st = _pick_stat(false, used)
	used.push_back(st)
	var v = _round_to_unit(val / Catalog.stat_w(st), st)
	return {"effect": _stat_effect(st, v), "value": v * Catalog.stat_w(st), "adj": _adj(Catalog.ADJ_BY_STAT.get(st, Catalog.ADJ_MECHANIC))}


# "禁用"某属性的行：-100% 属性修改、数值大到让属性归零的负面行（吸血鬼 -100 消耗品回复、速度型 静止时 -100 护甲）。
# 这些数值本身没有意义，按"该属性的期望总量"封顶估值，重组时保留为身份行
func is_disabling(e) -> bool:
	if is_gain_mod(e):
		return e.value <= -100
	if e.value >= 0 or not Catalog.STATS.has(e.key):
		return false
	return abs(e.value) > Catalog.counter_ref(e.key) * 2.0


# 角色行的价值（负面按除数折算）；负面数值不超过该属性的期望总量（-100 与 -10 000 一样只是"归零"）
func char_line_value(e) -> float:
	if is_plain_stat(e):
		var mag = abs(e.value)
		if e.value < 0:
			mag = min(mag, Catalog.counter_ref(e.key))
		return line_value(e.key, int(mag) * int(sign(e.value)))
	if is_gain_mod(e) and e.stats_modified.size() > 0:
		var gv = Valuation.gain_mod_value(e.stats_modified[0], int(clamp(e.value, -100, 1000)))
		return gv if gv >= 0 else neg_value(gv)
	if is_scaling(e):
		var sv = Valuation.scaling_value(e.key, e.value, e.stat_scaled, e.nb_stat_scaled)
		return sv if sv >= 0 else neg_value(sv)
	var nt = native_trigger_of(e)
	if nt != null and Catalog.STATS.has(e.key):
		var v = e.value
		if v < 0:
			v = -int(min(abs(v), Catalog.counter_ref(e.key)))
		var cv = Valuation.clause_value({"trigger": nt[0], "payload": nt[1], "stat": e.key, "value": v, "param": 5 if nt[0] == "interval" else 1}, Catalog.PERM_MULT_CHARACTER)
		return cv if cv >= 0 else neg_value(cv)
	return 0.0


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


# ============================================================
# 覆盖说明：原版每一条非纯属性效果在本 mod 中的处理方式（用于审计与 COVERAGE.md）
#   plain     纯属性行：按权重重组
#   trigger   原版触发行：拆解为 (扳机, 载荷) 先验，由通用触发条款重新表达
#   scaling   计数型：计数 × 属性自由搭配重新生成
#   gain_mod  属性修改 ±XX%：按属性期望总量估值后重新生成
#   scalar    带数值的机制：搬运并按预算缩放数值
#   mechanic  固定机制：原样搬运，按来源道具剩余价值估值
#   downside  负面机制：作为代价搬运，价值 = 来源道具因它多得的正面预算
#   text      纯描述行（行为写在道具 ID 上）：不搬运，所在道具保持原样
#   identity  角色身份 / 结构性效果：保留在角色上，不进入道具池
#   excluded  依赖其他行或道具 ID 语义：不搬运
# ============================================================
func handling_of(e, src) -> String:
	if is_plain_stat(e):
		return "plain"
	if native_trigger_of(e) != null:
		return "trigger"
	if is_scaling(e):
		return "scaling"
	if is_gain_mod(e):
		return "gain_mod"
	if is_next_wave(e):
		return "next_wave"
	if e.get_script() == effect_script and e.key == "":
		return "text"
	var k = e.custom_key if e.custom_key != "" else e.key
	if Catalog.WEAPON_COUNTERS.has(e.custom_key):
		return "weapon_counter"
	if k in ["cryptid", "charm_on_hit", "beast_master_effect", "map_size", "specific_items_price", "weapons_price",
			"group_structures", "next_level_xp_needed"] or (k == "items_price" and e.value > 0):
		return "char_more"
	if e.key == "die_in_one_hit":
		return "char_beta"
	if k in Catalog.BETA_RESTRICTIONS or k in Catalog.BETA_BUNDLES.values() or k in [
			"all_weapons_count_for_sets", "weapon_slot_upgrades", "item_steals", "item_steals_spawns_random_elite",
			"guaranteed_shop_items"] or (is_scaling(e) and e.stat_scaled.begins_with("item_")):
		if not (k == "remove_shop_items" and e.key != "structure"):
			return "char_beta"
	if k in ["pacifist", "bonus_non_elemental_damage_against_burning_targets", "weapon_slot"] or e.get_script() == load("res://effects/items/class_bonus_effect.gd"):
		return "char_component"
	if src is CharacterData:
		if not _is_transferable_character_mechanic(e, PlayerRunData.init_effects()):
			return "identity"
	if e.key in Catalog.MECHANIC_BANNED_KEYS or e.custom_key in Catalog.MECHANIC_BANNED_KEYS:
		return "excluded"
	if Catalog.is_downside_mechanic(e):
		return "downside"
	if e.get_script() == effect_script and e.storage_method == 0 and e.custom_key == "" and not e.key in Catalog.SCALAR_MECHANIC_EXCLUDED:
		return "scalar"
	return "mechanic"
