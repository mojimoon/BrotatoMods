extends Reference

# 东尼算法（Brotato）静态目录：价值货币、触发扳机、效果载荷、合法组合与原版触发器的拆解映射。
#
# 价值货币：1 点价值 ≈ 商店价格中的 1 材料（对原版纯属性道具做岭回归得到，MAPE≈10%）。
# 原版价格 ≈ 稀有度截距 + Σ 正面属性权重 × 数值；负面属性几乎不降价（由更大的正面收益"买单"）。
#
# 触发型效果的价值 = 单位价值 × 频率：
#   临时属性（本波有效，逐次叠加）  w × v × 平均叠层
#   状态属性（静止 / 低血量时）     w × v × 在场率
#   限时属性（N 秒）                w × v × min(1, 次数 × N / 波长)
#   永久属性（逐次累积）            w × v × 次数 × 累积倍率（与购买时剩余波数有关）
#   回血 / 材料 / 经验 / 伤害       每波总量 × 对应单位价值
# 频率统一用"每波期望次数"表示（波长按 60 秒估计，大部分波次为 60 秒），见 TRIGGERS。

const WAVE_SECONDS = 60.0

# 稀有度截距（Tier 0..3）：原版价格中与效果无关的部分
const TIER_INTERCEPT = [7.0, 20.0, 24.0, 15.0]
# 永久累积倍率：Tier 越高通常购买越晚、剩余波数越少。角色视为整局持有。
const PERM_MULT = [7.5, 6.5, 5.5, 4.5]
const PERM_MULT_CHARACTER = 10.5
# 负面效果换取的额外正面预算比例
const DOWNSIDE_COMPENSATION = 0.8

# ------------------------------------------------------------
# 属性：权重（材料 / 点）、每次触发的自然粒度、是否百分比显示、伤害参考值（用于"X% 某属性的伤害"）
# ------------------------------------------------------------
const STATS = {
	"stat_max_hp": {"w": 4.2, "unit": 1, "pct": false, "ref": 40.0},
	"stat_hp_regeneration": {"w": 4.7, "unit": 1, "pct": false, "ref": 8.0},
	"stat_lifesteal": {"w": 4.3, "unit": 1, "pct": true, "ref": 10.0},
	"stat_percent_damage": {"w": 2.1, "unit": 1, "pct": true, "ref": 25.0},
	"stat_melee_damage": {"w": 2.8, "unit": 1, "pct": false, "ref": 15.0},
	"stat_ranged_damage": {"w": 3.3, "unit": 1, "pct": false, "ref": 15.0},
	"stat_elemental_damage": {"w": 3.6, "unit": 1, "pct": false, "ref": 12.0},
	"stat_attack_speed": {"w": 1.9, "unit": 1, "pct": true, "ref": 25.0},
	"stat_crit_chance": {"w": 3.0, "unit": 1, "pct": true, "ref": 15.0},
	"stat_engineering": {"w": 2.6, "unit": 1, "pct": false, "ref": 15.0},
	"stat_range": {"w": 0.5, "unit": 5, "pct": false, "ref": 60.0},
	"stat_armor": {"w": 6.7, "unit": 1, "pct": false, "ref": 8.0},
	"stat_dodge": {"w": 2.3, "unit": 1, "pct": true, "ref": 20.0},
	"stat_speed": {"w": 2.9, "unit": 1, "pct": true, "ref": 15.0},
	"stat_luck": {"w": 1.3, "unit": 1, "pct": false, "ref": 30.0},
	"stat_harvesting": {"w": 1.1, "unit": 1, "pct": false, "ref": 40.0},
	"xp_gain": {"w": 0.85, "unit": 1, "pct": true, "ref": 0.0},
	"pickup_range": {"w": 0.65, "unit": 5, "pct": true, "ref": 0.0},
	"knockback": {"w": 1.0, "unit": 1, "pct": false, "ref": 0.0},
	"explosion_damage": {"w": 0.9, "unit": 5, "pct": true, "ref": 0.0},
	"explosion_size": {"w": 1.4, "unit": 5, "pct": true, "ref": 0.0},
	"consumable_heal": {"w": 6.6, "unit": 1, "pct": false, "ref": 0.0},
}

# 可作为"对随机敌人造成 X% 属性伤害"缩放源的属性
const DAMAGE_SCALING_STATS = [
	"stat_max_hp", "stat_armor", "stat_luck", "stat_melee_damage", "stat_ranged_damage",
	"stat_elemental_damage", "stat_engineering", "stat_range", "stat_harvesting", "stat_hp_regeneration",
]
# 临时属性不允许的属性（收获在波末结算前生效、经验与拾取范围临时加成无意义）
const TEMP_STAT_BANNED = ["stat_harvesting", "xp_gain", "pickup_range", "consumable_heal"]

# 每点"每波持续获得量"的价值
const HEAL_W = 1.2		# 每波回复 1 点生命
const GOLD_W = 1.0		# 每波获得 1 材料
const XP_W = 0.3		# 每波获得 1 经验
const DMG_W = 0.055		# 每波造成 1 点伤害
const EXPLOSION_TARGETS = 2.5	# 爆炸平均命中数

# ------------------------------------------------------------
# 触发扳机
#   kind: event（事件）/ state（持续状态）/ shop（商店阶段事件）
#   e: 每波期望次数（state 为在场率）
#   timing: 临时属性叠层的时间系数（波开始时触发 = 整波生效）
#   gate: none / every（每 N 次）/ chance（几率）
#   w: 基础出现权重（与原版先验相加）
# ------------------------------------------------------------
const TRIGGERS = {
	"kill": {"kind": "event", "e": 120.0, "timing": 0.5, "gate": "every", "w": 1.0},
	"hit": {"kind": "event", "e": 8.0, "timing": 0.5, "gate": "chance", "w": 1.0},
	"dodge": {"kind": "event", "e": 4.0, "timing": 0.5, "gate": "chance", "w": 0.7},
	"consumable": {"kind": "event", "e": 7.0, "timing": 0.5, "gate": "chance", "w": 0.8},
	"gold": {"kind": "event", "e": 120.0, "timing": 0.5, "gate": "every", "w": 0.6},
	"heal": {"kind": "event", "e": 13.0, "timing": 0.5, "gate": "chance", "w": 0.4},
	"level_up": {"kind": "event", "e": 1.3, "timing": 0.5, "gate": "none", "w": 0.9},
	"wave_start": {"kind": "event", "e": 1.0, "timing": 1.0, "gate": "none", "w": 0.8},
	"wave_end": {"kind": "event", "e": 1.0, "timing": 0.0, "gate": "none", "w": 0.8},
	"interval": {"kind": "event", "e": 0.0, "timing": 0.5, "gate": "none", "w": 0.9},
	"still": {"kind": "state", "e": 0.25, "timing": 1.0, "gate": "none", "w": 0.7},
	"moving": {"kind": "state", "e": 0.75, "timing": 1.0, "gate": "none", "w": 0.4},
	"low_hp": {"kind": "state", "e": 0.15, "timing": 1.0, "gate": "none", "w": 0.5},
	"full_hp": {"kind": "state", "e": 0.45, "timing": 1.0, "gate": "none", "w": 0.4},
	"reroll": {"kind": "shop", "e": 3.0, "timing": 0.0, "gate": "chance", "w": 0.5},
	"buy": {"kind": "shop", "e": 3.0, "timing": 0.0, "gate": "chance", "w": 0.4},
}

const INTERVAL_CHOICES = [3, 4, 5, 6, 8, 10, 12, 15]

# ------------------------------------------------------------
# 效果载荷
# ------------------------------------------------------------
const PAYLOADS = {
	"temp_stat": {"w": 1.0},
	"perm_stat": {"w": 0.8},
	"timed_stat": {"w": 0.5},
	"heal": {"w": 0.6},
	"gold": {"w": 0.5},
	"xp": {"w": 0.3},
	"damage": {"w": 0.6},
	"explode": {"w": 0.5},
}

# 合法组合：触发扳机 -> 允许的载荷
# 排除规则：状态扳机只挂临时属性；商店扳机只挂永久效果；回血扳机不挂回血（避免自激循环），
# 拾取材料不挂材料；波末 / 波初没有敌人和伤害意义的载荷被排除。
const LEGAL = {
	"kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode"],
	"hit": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode"],
	"dodge": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode"],
	"consumable": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode"],
	"gold": ["temp_stat", "timed_stat", "heal", "xp", "damage", "explode"],
	"heal": ["temp_stat", "timed_stat", "gold", "damage", "explode"],
	"level_up": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "damage", "explode"],
	"wave_start": ["temp_stat", "perm_stat", "gold"],
	"wave_end": ["perm_stat", "gold", "xp"],
	"interval": ["temp_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode"],
	"still": ["temp_stat"],
	"moving": ["temp_stat"],
	"low_hp": ["temp_stat"],
	"full_hp": ["temp_stat"],
	"reroll": ["perm_stat", "gold"],
	"buy": ["perm_stat", "gold"],
}

# 原版触发型效果 -> [扳机, 载荷]（custom_key 或 key）。这些原版行在重组时被"拆解"为先验，
# 由通用触发器重新表达；不会原样搬到别的道具上。
const NATIVE_TRIGGER_MAP = {
	"stats_on_level_up": ["level_up", "perm_stat"],
	"temp_stats_on_hit": ["hit", "temp_stat"],
	"temp_stats_on_dodge": ["dodge", "temp_stat"],
	"stats_end_of_wave": ["wave_end", "perm_stat"],
	"temp_stats_while_not_moving": ["still", "temp_stat"],
	"temp_stats_while_moving": ["moving", "temp_stat"],
	"stats_below_half_health": ["low_hp", "temp_stat"],
	"temp_consumable_stats_while_max": ["consumable", "temp_stat"],
	"consumable_stats_while_max": ["consumable", "perm_stat"],
	"temp_stats_per_interval": ["interval", "temp_stat"],
	"decaying_stats_on_hit": ["hit", "timed_stat"],
	"decaying_stats_on_consumable": ["consumable", "timed_stat"],
	"gain_stats_on_reroll": ["reroll", "perm_stat"],
	"stats_on_fruit": ["consumable", "perm_stat"],
	"stats_next_wave": ["wave_start", "temp_stat"],
	"dmg_on_dodge": ["dodge", "damage"],
	"dmg_when_death": ["kill", "damage"],
	"dmg_when_pickup_gold": ["gold", "damage"],
	"dmg_when_heal": ["heal", "damage"],
	"heal_on_dodge": ["dodge", "heal"],
	"heal_on_kill": ["kill", "heal"],
	"heal_on_crit_kill": ["kill", "heal"],
	"heal_when_pickup_gold": ["gold", "heal"],
	"gold_on_crit_kill": ["kill", "gold"],
	"explode_on_hit": ["hit", "explode"],
	"explode_on_death": ["kill", "explode"],
	"explode_on_consumable": ["consumable", "explode"],
	"gain_stat_for_killed_enemies_while_burning": ["kill", "perm_stat"],
	"effect_gain_stat_every_killed_enemies": ["kill", "perm_stat"],
}
# 原版先验在组合权重中的强度
const NATIVE_PRIOR_STRENGTH = 0.6

# 行为写死在道具 ID 上的道具：保持原样，也不作为机制组件的来源
const ANCHORED_ITEMS = [
	"item_spyglass", "item_coupon", "item_hourglass", "item_goldfish", "item_goldfish_used",
	"item_axolotl", "item_bait", "item_whistle", "item_crown", "item_pocket_factory",
	"item_recycling_machine", "item_mirror", "item_broken_mirror", "item_broken_hourglass",
	"item_crystal", "item_scared_sausage", "item_builder_turret_0", "item_builder_turret_1",
	"item_builder_turret_2", "item_builder_turret_3", "item_fairy", "item_pearl",
	"item_treasure_map", "item_piggy_bank", "item_fish_hook",
]
# 固定机制中的负面效果（当作代价使用）：key -> 哪种符号是坏的
#   1 = 正值不利（敌人更强、价格更高、诅咒……），-1 = 负值不利（下波开局少血），0 = 总是不利
const DOWNSIDE_SIGN = {
	"hp_start_next_wave": -1, "hp_start_wave": -1, "lose_hp_per_second": 1, "extra_elite_next_wave_chance": 1,
	"enemy_health": 1, "enemy_damage": 1, "enemy_speed": 1, "items_price": 1, "reroll_price": 1,
	"speed_cap": 0, "hp_cap": 0, "lock_current_weapons": 0, "extra_enemies_next_wave": 0, "stat_curse": 1,
}
# 非 stat_ 前缀属性的原版描述 key（否则数值不会显示）
const STAT_TEXT_KEYS = {
	"knockback": "effect_knockback", "pickup_range": "effect_pickup_range", "consumable_heal": "effect_consumable_heal",
}

# 不适合搬运的机制 key（依赖其他行或道具 ID 语义）
const MECHANIC_BANNED_KEYS = [
	"stats_next_wave", "starting_item", "starting_weapon", "cursed_starting_item", "item_box_gold",
	"curse_locked_items", "extra_item_in_crate", "duplicate_item", "increase_tier_on_reroll",
	"item_hourglass", "remove_speed", "fog_visibility", "number_of_enemies",
]

# 名称形容词：按主要效果选择
const ADJ_BY_STAT = {
	"stat_max_hp": "AA_ADJ_STURDY", "stat_hp_regeneration": "AA_ADJ_VITAL", "stat_lifesteal": "AA_ADJ_THIRSTY",
	"stat_percent_damage": "AA_ADJ_SHARP", "stat_melee_damage": "AA_ADJ_BRUTAL", "stat_ranged_damage": "AA_ADJ_AIMED",
	"stat_elemental_damage": "AA_ADJ_ARCANE", "stat_attack_speed": "AA_ADJ_HASTY", "stat_crit_chance": "AA_ADJ_DEADLY",
	"stat_engineering": "AA_ADJ_CLEVER", "stat_range": "AA_ADJ_FARSIGHTED", "stat_armor": "AA_ADJ_ARMORED",
	"stat_dodge": "AA_ADJ_ELUSIVE", "stat_speed": "AA_ADJ_SWIFT", "stat_luck": "AA_ADJ_LUCKY",
	"stat_harvesting": "AA_ADJ_FERTILE",
}
const ADJ_BY_TRIGGER = {
	"kill": "AA_ADJ_HUNTING", "hit": "AA_ADJ_VENGEFUL", "dodge": "AA_ADJ_NIMBLE", "consumable": "AA_ADJ_HUNGRY",
	"gold": "AA_ADJ_GREEDY", "heal": "AA_ADJ_BLESSED", "level_up": "AA_ADJ_GROWING", "wave_start": "AA_ADJ_EAGER",
	"wave_end": "AA_ADJ_PATIENT", "interval": "AA_ADJ_TICKING", "still": "AA_ADJ_ROOTED", "moving": "AA_ADJ_RESTLESS",
	"low_hp": "AA_ADJ_DESPERATE", "full_hp": "AA_ADJ_PROUD", "reroll": "AA_ADJ_FICKLE", "buy": "AA_ADJ_THRIFTY",
}


static func is_downside_mechanic(e) -> bool:
	var k = e.key if DOWNSIDE_SIGN.has(e.key) else e.custom_key
	if not DOWNSIDE_SIGN.has(k):
		return false
	var sg = DOWNSIDE_SIGN[k]
	return sg == 0 or (sg > 0 and e.value > 0) or (sg < 0 and e.value < 0)


static func stat_w(stat: String) -> float:
	if STATS.has(stat):
		return STATS[stat].w
	return 1.0


static func stat_unit(stat: String) -> int:
	if STATS.has(stat):
		return STATS[stat].unit
	return 1


static func is_pct_stat(stat: String) -> bool:
	return STATS.has(stat) and STATS[stat].pct


static func payload_needs_stat(payload: String) -> bool:
	return payload in ["temp_stat", "perm_stat", "timed_stat", "damage", "explode"]


static func events_per_wave(trigger: String, param: int) -> float:
	if trigger == "interval":
		return WAVE_SECONDS / max(1, param)
	return TRIGGERS[trigger].e
