extends Reference

# 东尼算法（Brotato）静态目录：价值货币、触发扳机、效果载荷、合法组合与原版触发器的拆解映射。
#
# 价值货币：1 点价值 ≈ 商店价格中的 1 材料。
# 对原版纯属性道具做岭回归：价格 ≈ 稀有度截距 + Σ 正面属性权重 × 数值 + Σ 负面属性权重 × 数值 / D。
# 负面除数 D 的网格搜索（平均相对误差）：D=1 13.0%，1.5 12.7%，2 12.6%，2.5–8 12.4–12.5%，不计负面 12.8%。
# 数据只能说明"负面远不如正面值钱"（可以卖掉无关或次要的属性）；实验后取 D=2.5。
#
# 触发型效果的价值 = 单位价值 × 频率：
#   临时属性（本波有效，逐次叠加）  w × v × 平均叠层
#   状态属性（静止 / 低血量时）     w × v × 在场率
#   限时属性（N 秒）                w × v × 次数 × N / 波长
#   永久属性（逐次累积）            w × v × 次数 × 累积倍率（与购买时剩余波数有关）
#   回血 / 材料 / 经验 / 伤害       每波总量 × 对应单位价值
# 频率统一用"每波期望次数"表示（波长按 60 秒估计，大部分波次为 60 秒），见 TRIGGERS。
# 击杀 / 拾取材料 / 受击 / 回血的次数刻意高估，以压低这些高频扳机上的单次数值。

const WAVE_SECONDS = 60.0

# 稀有度截距（Tier 0..3）：原版价格中与效果无关的部分
const TIER_INTERCEPT = [11.5, 30.0, 40.9, 39.0]
# 永久累积倍率：Tier 越高通常购买越晚、剩余波数越少。角色视为整局持有。
const PERM_MULT = [7.5, 6.5, 5.5, 4.5]
const PERM_MULT_CHARACTER = 10.5
# 负面效果的价值除数：-3 远程伤害只按 -1 远程伤害计价
const DOWNSIDE_DIVISOR = 2.5
# 隐藏价值乘数（按稀有度）：用"真实频率"审计生成道具与原版纯属性道具的强度比 real，
# real < 1 的档位乘以 1 / real 补齐，real >= 1 的保持不变。由测试 test_60 的审计结果标定。
const HIDDEN_TIER_MULT = [1.0, 1.08, 1.05, 1.0]
# 档内价格弹性：原版同稀有度道具的 log(净价值) 对 log(价格) 的斜率（约 0.69）
const PRICE_ELASTICITY = 0.69

# ------------------------------------------------------------
# 属性：权重（材料 / 点）、每次触发的自然粒度、是否百分比显示、伤害参考值（用于"X% 某属性的伤害"）
# ------------------------------------------------------------
const STATS = {
	"stat_max_hp": {"w": 3.5, "unit": 1, "pct": false, "ref": 40.0},
	"stat_hp_regeneration": {"w": 2.8, "unit": 1, "pct": false, "ref": 8.0},
	"stat_lifesteal": {"w": 4.7, "unit": 1, "pct": true, "ref": 10.0},
	"stat_percent_damage": {"w": 1.8, "unit": 1, "pct": true, "ref": 25.0},
	"stat_melee_damage": {"w": 3.4, "unit": 1, "pct": false, "ref": 15.0},
	"stat_ranged_damage": {"w": 5.0, "unit": 1, "pct": false, "ref": 15.0},
	"stat_elemental_damage": {"w": 3.5, "unit": 1, "pct": false, "ref": 12.0},
	"stat_attack_speed": {"w": 1.4, "unit": 1, "pct": true, "ref": 25.0},
	"stat_crit_chance": {"w": 2.1, "unit": 1, "pct": true, "ref": 15.0},
	"stat_engineering": {"w": 2.1, "unit": 1, "pct": false, "ref": 15.0},
	"stat_range": {"w": 0.6, "unit": 5, "pct": false, "ref": 60.0},
	"stat_armor": {"w": 6.5, "unit": 1, "pct": false, "ref": 8.0},
	"stat_dodge": {"w": 2.6, "unit": 1, "pct": true, "ref": 20.0},
	"stat_speed": {"w": 2.4, "unit": 1, "pct": true, "ref": 15.0},
	"stat_luck": {"w": 1.1, "unit": 1, "pct": false, "ref": 30.0},
	"stat_harvesting": {"w": 0.95, "unit": 1, "pct": false, "ref": 40.0},
	"xp_gain": {"w": 0.66, "unit": 1, "pct": true, "ref": 0.0},
	"pickup_range": {"w": 0.46, "unit": 5, "pct": true, "ref": 0.0},
	"knockback": {"w": 0.8, "unit": 1, "pct": false, "ref": 0.0},
	"explosion_damage": {"w": 0.95, "unit": 5, "pct": true, "ref": 0.0},
	"explosion_size": {"w": 0.81, "unit": 5, "pct": true, "ref": 0.0},
	"consumable_heal": {"w": 5.2, "unit": 1, "pct": false, "ref": 0.0},
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
	"hit": {"kind": "event", "e": 10.0, "timing": 0.5, "gate": "chance", "w": 1.0},
	"dodge": {"kind": "event", "e": 4.0, "timing": 0.5, "gate": "chance", "w": 0.7},
	"consumable": {"kind": "event", "e": 7.0, "timing": 0.5, "gate": "chance", "w": 0.8},
	"gold": {"kind": "event", "e": 120.0, "timing": 0.5, "gate": "every", "w": 0.6},
	"heal": {"kind": "event", "e": 20.0, "timing": 0.5, "gate": "chance", "w": 0.4},
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

# 实际受击次数（用于"受伤时清空"条款的估值）
const REAL_HITS_PER_WAVE = 7.0
# 本波属性条款带"受伤时清空"的概率
const RESET_ON_HIT_CHANCE = 0.20

const INTERVAL_CHOICES = [3, 4, 5, 6, 8, 10, 12, 15]

# ------------------------------------------------------------
# 效果载荷
# ------------------------------------------------------------
const PAYLOADS = {
	"temp_stat": {"w": 0.4},
	"perm_stat": {"w": 0.3},
	"timed_stat": {"w": 0.5},
	"heal": {"w": 0.6},
	"gold": {"w": 0.5},
	"xp": {"w": 0.3},
	"damage": {"w": 0.6},
	"explode": {"w": 0.5},
	"grant": {"w": 1.2},
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

# ============================================================
# 自由触发（选项）：任何扳机都能以"获得效果"为结果，合法表放宽为只排除自激循环与无意义组合
#   grant 载荷：触发时获得一条效果（可缩放机制 / 计数型 / 属性修改）
#     本波获得：可叠加，波末撤销；只允许战斗中实时生效的效果（GRANT_TEMP_KEYS）
#     永久获得：只允许求和型数值效果（存档安全）；商店扳机、波末只能永久获得
# ============================================================
const FREE_LEGAL = {
	"kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant"],
	"hit": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant"],
	"dodge": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant"],
	"consumable": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant"],
	"gold": ["temp_stat", "perm_stat", "timed_stat", "heal", "xp", "damage", "explode", "grant"],
	"heal": ["temp_stat", "perm_stat", "timed_stat", "gold", "xp", "damage", "explode", "grant"],
	"level_up": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "damage", "explode", "grant"],
	"wave_start": ["temp_stat", "perm_stat", "timed_stat", "gold", "xp", "grant"],
	"wave_end": ["perm_stat", "gold", "xp", "grant"],
	"interval": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant"],
	"still": ["temp_stat", "grant"],
	"moving": ["temp_stat", "grant"],
	"low_hp": ["temp_stat", "grant"],
	"full_hp": ["temp_stat", "grant"],
	"reroll": ["perm_stat", "gold", "grant"],
	"buy": ["perm_stat", "gold", "grant"],
}
# 战斗中实时读取、可"本波获得"的机制 key（其余求和型机制只能永久获得）
const GRANT_TEMP_KEYS = [
	"bounce", "piercing", "piercing_damage", "pierce_on_crit", "burning_cooldown_reduction", "burning_spread",
	"chance_double_gold", "damage_against_bosses", "enemy_gold_drops", "gold_drops", "gold_on_cursed_enemy_kill",
	"instant_gold_attracting", "structure_attack_speed", "enemy_fruit_drops", "tree_turrets",
	"heal_when_pickup_gold", "heal_on_kill", "heal_on_crit_kill",
]
# 不能作为触发结果的机制：绑定 / 消耗持有者（镜子、金鱼、沙漏、珍珠），以及生效时机特殊的机制
const GRANT_BANNED_KEYS = [
	"duplicate_item", "increase_tier_on_reroll", "item_hourglass", "extra_item_in_crate", "hit_protection",
	"hp_start_next_wave", "hp_start_wave", "lose_hp_per_second", "jellyshield_count", "torture", "number_of_enemies",
]

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
# 同一道具池中重复出现的 (扳机, 载荷) 组合 / 扳机 / 载荷的降权强度（提高触发多样性）
const REPEAT_PENALTY_COMBO = 0.8
const REPEAT_PENALTY_TRIGGER = 0.15
const REPEAT_PENALTY_PAYLOAD = 0.08

# 行为写死在道具 ID 上的道具：保持原样，也不作为机制组件的来源
# 道具 ID 本身还有额外含义的道具（望远镜的升级预览、诱饵的渔夫计数、口袋工厂计入建筑数、美西螈的商店刷新规则、
# 金鱼 / 沙漏 / 镜子的"用后变成另一件道具"）：道具本身保持原样，但它们的效果可以出现在其他重组道具上
const ANCHORED_ITEMS = [
	"item_spyglass", "item_bait", "item_pocket_factory", "item_axolotl",
	"item_goldfish", "item_goldfish_used", "item_hourglass", "item_broken_hourglass",
	"item_mirror", "item_broken_mirror",
	"item_builder_turret_0", "item_builder_turret_1", "item_builder_turret_2", "item_builder_turret_3",
]
# 不作为组件来源的道具（建造者的角色专属炮台）
const MECHANIC_SOURCE_EXCLUDED = ["item_builder_turret_0", "item_builder_turret_1", "item_builder_turret_2", "item_builder_turret_3"]
# 效果里存"持有者道具 ID"的机制：搬运时改为新持有者的 ID
const HOLDER_KEYED = ["duplicate_item", "increase_tier_on_reroll"]
# 生效后持有者道具会被移除的机制：在同一行里注明
const CONSUMED_KEYS = ["duplicate_item", "increase_tier_on_reroll", "item_hourglass"]
# 虽非普通求和存储、但数值含义线性、可按预算缩放的机制
const SCALAR_EXTRA_KEYS = [
	"extra_item_in_crate", "curse_locked_items", "remove_speed", "number_of_enemies", "duplicate_item",
	"gain_pct_gold_start_wave", "loot_alien_chance", "loot_alien_speed",
]
# 固定机制中的负面效果（当作代价使用）：key -> 哪种符号是坏的
#   1 = 正值不利（敌人更强、价格更高、诅咒……），-1 = 负值不利（下波开局少血），0 = 总是不利
const DOWNSIDE_SIGN = {
	"hp_start_next_wave": -1, "hp_start_wave": -1, "lose_hp_per_second": 1, "extra_elite_next_wave_chance": 1,
	"enemy_health": 1, "enemy_damage": 1, "enemy_speed": 1, "items_price": 1, "reroll_price": 1,
	"speed_cap": 0, "hp_cap": 0, "lock_current_weapons": 0, "extra_enemies_next_wave": 0, "stat_curse": 1,
	"gold_drops": -1, "enemy_gold_drops": -1, "dodge_cap": -1, "gain_pct_gold_start_wave": -1,
	"accuracy": -1, "burning_cooldown_reduction": -1, "piercing_damage": -1,
}
# 角色效果中不能搬到道具上的身份 / 结构性 key
const CHAR_MECHANIC_BANNED = [
	"weapon_slot", "weapon_slot_upgrades", "min_weapon_tier", "max_weapon_tier", "no_melee_weapons",
	"no_ranged_weapons", "no_duplicate_weapons", "max_melee_weapons", "max_ranged_weapons", "destroy_weapons",
	"minimum_weapons_in_shop", "lock_current_weapons", "remove_shop_items", "guaranteed_shop_items",
	"specific_items_price", "hp_shop", "convert_stats_end_of_wave", "convert_stats_half_wave", "cryptid",
	"pacifist", "item_steals", "item_steals_spawns_random_elite", "disable_item_locking",
	"all_weapons_count_for_sets", "group_structures", "die_in_one_hit", "can_attack_while_moving",
	"beast_master_effect", "next_level_xp_needed", "level_upgrades_modifications", "no_heal", "weapons_price",
	"stronger_elites_on_kill", "charm_on_hit", "map_size", "weapon_scaling_stats", "convert_bonus_gold",
	"additional_weapon_effects", "tier_iv_weapon_effects", "tier_i_weapon_effects", "unique_weapon_effects",
	"poisoned_fruit", "upgraded_baits", "die_in_one_hit", "boosted_wanted_item_tag", "max_turret_count", "trees_start_wave",
]
# 角色效果（整局持有）的总价值估计找不到时的默认值
const CHARACTER_BUDGET_DEFAULT = 60.0
# 非 stat_ 前缀属性的原版描述 key（否则数值不会显示）
const STAT_TEXT_KEYS = {
	"knockback": "effect_knockback", "pickup_range": "effect_pickup_range", "consumable_heal": "effect_consumable_heal",
}

# 不适合搬运的机制 key（依赖其他行或道具 ID 语义）
const MECHANIC_BANNED_KEYS = [
	"stats_next_wave", "starting_item", "starting_weapon", "cursed_starting_item",
	"fog_visibility",
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


# ============================================================
# 道具池结构：攻击 A / 生存 S / 运营 E
# 原版约 49% 攻击、37% 生存、15% 运营为主；最常见的是同类内交换（+近战 −远程、+生命 −再生），
# 运营几乎从不作为代价。生成时按原版同稀有度的 (正面类, 负面类) 分布抽取道具类型。
# ============================================================
const STAT_CATEGORY = {
	"stat_melee_damage": "A", "stat_ranged_damage": "A", "stat_elemental_damage": "A", "stat_percent_damage": "A",
	"stat_attack_speed": "A", "stat_crit_chance": "A", "stat_engineering": "A", "stat_range": "A",
	"explosion_damage": "A", "explosion_size": "A", "knockback": "A",
	"stat_max_hp": "S", "stat_hp_regeneration": "S", "stat_lifesteal": "S", "stat_dodge": "S", "stat_armor": "S",
	"consumable_heal": "S", "stat_speed": "S",
	"stat_luck": "E", "stat_harvesting": "E", "xp_gain": "E", "pickup_range": "E",
}
const PAYLOAD_CATEGORY = {"heal": "S", "gold": "E", "xp": "E", "damage": "A", "explode": "A"}
const CATEGORY_CLASSES = ["AA", "AS", "AE", "A-", "SA", "SS", "SE", "S-", "EA", "ES", "EE", "E-"]

# 原版的非属性词条（角色的"想要词条"会用到）
const STAT_EXTRA_TAGS = {
	"consumable_heal": "consumable", "explosion_damage": "explosive", "explosion_size": "explosive",
	"knockback": "knockback", "pickup_range": "pickup",
}
const TRIGGER_TAGS = {"still": "stand_still", "consumable": "consumable"}
const PAYLOAD_TAGS = {"explode": "explosive", "gold": "economy"}

# 原版"道具组"（角色可整组禁用）对应的属性
const GROUP_STATS = {
	"harvesting": ["stat_harvesting"], "melee_damage": ["stat_melee_damage"], "ranged_damage": ["stat_ranged_damage"],
	"melee_and_ranged_damage": ["stat_melee_damage", "stat_ranged_damage"], "lifesteal": ["stat_lifesteal"],
	"lifesteal_and_hp_regeneration": ["stat_lifesteal", "stat_hp_regeneration"],
	"hp_regeneration": ["stat_hp_regeneration"], "consumable_heal": ["consumable_heal"], "speed": ["stat_speed"],
	"engineering": ["stat_engineering"], "elemental_damage": ["stat_elemental_damage"], "armor": ["stat_armor"],
	"dodge": ["stat_dodge"],
}
# 原版中表示"回血"的机制 key（用于把角色禁用的原版道具翻译成语义）
const HEAL_KEYS = ["heal_on_kill", "heal_on_crit_kill", "heal_when_pickup_gold", "heal_on_dodge", "consumable_heal_over_time", "hp_regen_bonus"]


# ============================================================
# 计数型效果：每有 [计数] 获得 [属性]（原版 GainStatForEveryStatEffect，计数与属性可自由搭配）
# 价值 = 目标属性权重 × 数值 × 计数期望 / 每 N
# 计数期望由原版道具校准：社区支持（每个存活敌人 +1 攻速）→ 存活敌人约 24；炒饭（每个燃烧敌人 +1 再生）→ 约 8；
# 石皮（每点护甲 +1 生命）→ 护甲约 10；奇怪的书（每点元素 +1 工程）→ 元素约 15；发电机（每点速度 +1% 伤害）→ 速度约 16；
# 幸运币（每点暴击 +2 幸运）→ 暴击约 25；复古卫衣（每点闪避 +2 攻速）→ 闪避约 25；护垫（每 80 材料 +1 生命）→ 材料约 160；
# 仙女（每个普通 / 传说道具）→ 普通约 12、传说约 1.5。其余属性取 STATS.ref × 1.2。
# ============================================================
const COUNTER_REF = {
	"stat_armor": 10.0, "stat_elemental_damage": 15.0, "stat_speed": 16.0, "stat_crit_chance": 25.0,
	"stat_dodge": 25.0, "knockback": 12.0,
	"materials": 160.0, "structure": 3.0, "living_enemy": 24.0, "burning_enemy": 8.0, "living_tree": 3.0,
	"percent_player_missing_health": 30.0, "different_item": 18.0, "common_item": 12.0, "legendary_item": 1.5,
}
# 可用的非属性计数与原版描述 key
const COUNTER_TEXT = {
	"materials": "EFFECT_GAIN_STAT_FOR_EVERY_STAT", "structure": "EFFECT_GAIN_STAT_FOR_EVERY_STAT",
	"living_enemy": "EFFECT_GAIN_STAT_FOR_EVERY_ENEMY", "burning_enemy": "EFFECT_GAIN_STAT_FOR_EVERY_BURNING_ENEMY",
	"living_tree": "EFFECT_GAIN_STAT_FOR_EVERY_TREE",
	"percent_player_missing_health": "EFFECT_GAIN_STAT_FOR_EVERY_PERCENT_PLAYER_MISSING_HEALTH",
	"different_item": "EFFECT_GAIN_STAT_FOR_EVERY_DIFFERENT_STAT", "common_item": "EFFECT_GAIN_STAT_FOR_EVERY_DIFFERENT_STAT",
	"legendary_item": "EFFECT_GAIN_STAT_FOR_EVERY_DIFFERENT_STAT",
}
# 可作为计数目标 / 计数来源的属性（需有 gain_ 以外的普通 stat key）
const SCALING_STATS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage",
	"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
	"stat_range", "stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting", "knockback",
]


static func counter_ref(counter: String) -> float:
	if COUNTER_REF.has(counter):
		return COUNTER_REF[counter]
	if STATS.has(counter) and STATS[counter].ref > 0:
		return STATS[counter].ref * 1.2
	return 10.0


# ============================================================
# 属性修改 ±XX%（原版 StatGainsModificationEffect，来自角色）：该属性的所有增减乘以 (1 + XX%)
# 价值 = 属性权重 × 该属性期望总量（同计数期望）× XX%；负值按负面除数折算
# ============================================================
const GAIN_MOD_STATS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage",
	"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
	"stat_range", "stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting",
]
const GAIN_MOD_STEPS = [10, 15, 20, 25, 33, 40, 50]

# 特殊行的类型比例：触发条款 / 计数型 / 属性修改 / 搬运机制
const SPECIAL_KIND_WEIGHTS = {"trigger": 0.5, "scaling": 0.2, "gain_mod": 0.08, "mechanic": 0.22}
# 可按预算缩放数值的机制（原版 Effect，数值线性含义）：缩放范围为原版数值的 1 单位 .. 1.5 倍
const SCALAR_MECHANIC_EXCLUDED = ["hp_start_next_wave", "hp_start_wave", "speed_cap", "hp_cap", "lock_current_weapons", "dodge_cap", "one_shot_trees", "structures_can_crit"]
