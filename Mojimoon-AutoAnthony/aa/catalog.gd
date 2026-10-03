extends Reference

# 东尼算法（Brotato）静态目录：价值货币、触发扳机、效果载荷、合法组合与原版触发器的拆解映射。
#
# 价值货币：1 点价值 ≈ 商店价格中的 1 材料。
# 对原版纯属性道具（97 件）做岭回归：价格 ≈ 稀有度截距 + Σ 正面属性权重 × 数值 + Σ 负面属性权重 × 数值 / D，
# 先验取 ArosRising MultiTool "Value Settings" 的升级等价比（闪避 1 : 最大生命 1 : 暴击 1 : 速度 1 : 近战 1.5 : 再生 1.5 :
# 工程 2 : 吸血 2 : 远程 3 : 元素 3 : 护甲 3 : %伤害 0.75 : 收获 0.75 : 攻速 0.6 : 幸运 0.4 : 范围 0.15）× 2 材料，
# 岭强度 300：R² = 0.95，价格的中位相对误差 9%。
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
# 击杀 / 拾取材料 / 受击 / 回血的次数现已不再高估。

const WAVE_SECONDS = 60.0

# 稀有度截距（Tier 0..3）：原版价格中与效果无关的部分（只用于可选的 intercept 预算模型）
const TIER_INTERCEPT = [11.9, 31.5, 44.6, 42.5]
# 永久累积倍率：Tier 越高通常购买越晚、剩余波数越少。角色视为整局持有。
# 由原版"每波永久成长"道具反推（警戒戒指 6.4、机械臂 3.5、魔法叶 3.3、鬼火 2.5、宝宝乌贼 6.1），中位约 3.5
const PERM_MULT = [5.0, 4.5, 4.0, 3.5]
# 高频扳机上永久效果的每波上限最大值
const PERM_CAP_MAX = 20
# 带每波上限的永久效果：每次触发的期望价值折算（上限常在波次后段才达到、后半局获得的永久属性用得少），
# 同样预算下每波上限约为原来的 2 倍
const PERM_CAPPED_FIRE_VALUE = 0.55
const PERM_MULT_CHARACTER = 7.0
# 负面效果的价值除数：-3 远程伤害只按 -1 远程伤害计价
const DOWNSIDE_DIVISOR = 2.5
# 隐藏价值乘数（按稀有度）：用"真实频率"审计生成道具与原版纯属性道具的强度比 real，
# real < 1 的档位乘以 1 / real 补齐，real >= 1 的保持不变。由测试 test_60 的审计结果标定。
const HIDDEN_TIER_MULT = [1.0, 1.12, 1.08, 1.0]
# 预算模型：同稀有度内 预算 = k × 价格（过原点的线性），k = 原版纯属性道具的净价值中位数 / 价格中位数
# （T1–T4 约 0.40 / 0.35 / 0.38 / 0.56）。原版档内"价值 - 价格"几乎没有斜率（档内 R² 只有 0.07–0.33），
# 任何档内曲线都是建模选择；旧的 价格^0.69 与正比模型对原版的拟合相同（R² 都是 0.918），而价格现在由本 mod 生成，
# 用正比关系最直接：贵一倍的道具就强一倍。
# 重组道具的价格：从同稀有度被重组道具的原版价格分布中有放回抽取（不是均匀分布；低于此值的占位价格不参与）
const PRICE_POOL_MIN = 5
# 不进入价格池的道具：金鱼（23）/ 休息的金鱼（30）的价格远低于同稀有度，会把重组道具的价格拉低
const PRICE_POOL_EXCLUDED = ["item_goldfish", "item_goldfish_used"]
# 机制估值修正：来源道具 / 机制 key -> 估值倍率（< 1 = 同样预算给出更高的数值）
#   从升级中获得的属性 +X%（藤壶）；MultiTool 里评级偏低的特殊机制道具（花园 C、眼罩）
const MECHANIC_VALUE_MULT = {"level_upgrades_modifications": 0.6, "item_garden": 0.75, "item_eyepatch": 0.8}

# ------------------------------------------------------------
# 属性：权重（材料 / 点）、每次触发的自然粒度、是否百分比显示、伤害参考值（用于"X% 某属性的伤害"）
# ------------------------------------------------------------
const STATS = {
	"stat_max_hp": {"w": 2.9, "unit": 1, "pct": false, "ref": 40.0},
	"stat_hp_regeneration": {"w": 3.0, "unit": 1, "pct": false, "ref": 8.0},
	"stat_lifesteal": {"w": 4.2, "unit": 1, "pct": true, "ref": 10.0},
	"stat_percent_damage": {"w": 1.65, "unit": 1, "pct": true, "ref": 25.0},
	"stat_melee_damage": {"w": 2.8, "unit": 1, "pct": false, "ref": 15.0},
	"stat_ranged_damage": {"w": 5.45, "unit": 1, "pct": false, "ref": 15.0},
	"stat_elemental_damage": {"w": 4.65, "unit": 1, "pct": false, "ref": 12.0},
	"stat_attack_speed": {"w": 1.35, "unit": 1, "pct": true, "ref": 25.0},
	"stat_crit_chance": {"w": 1.85, "unit": 1, "pct": true, "ref": 15.0},
	"stat_engineering": {"w": 3.3, "unit": 1, "pct": false, "ref": 15.0},
	"stat_range": {"w": 0.6, "unit": 5, "pct": false, "ref": 60.0},
	"stat_armor": {"w": 6.0, "unit": 1, "pct": false, "ref": 8.0},
	"stat_dodge": {"w": 2.4, "unit": 1, "pct": true, "ref": 20.0},
	"stat_speed": {"w": 2.1, "unit": 1, "pct": true, "ref": 15.0},
	"stat_luck": {"w": 0.9, "unit": 1, "pct": false, "ref": 30.0},
	"stat_harvesting": {"w": 0.95, "unit": 1, "pct": false, "ref": 40.0},
	"xp_gain": {"w": 0.5, "unit": 1, "pct": true, "ref": 0.0},
	"pickup_range": {"w": 0.3, "unit": 5, "pct": true, "ref": 0.0},
	"knockback": {"w": 0.7, "unit": 1, "pct": false, "ref": 0.0},
	"explosion_damage": {"w": 0.93, "unit": 5, "pct": true, "ref": 0.0},
	"explosion_size": {"w": 0.7, "unit": 5, "pct": true, "ref": 0.0},
	"consumable_heal": {"w": 5.2, "unit": 1, "pct": false, "ref": 0.0},
}

# 次要正面属性：作为属性行（非核心属性）时只分到通常份额的这一比例，余下预算交给其他属性行
const MINOR_POSITIVE_STATS = {"knockback": 0.4, "stat_range": 0.65, "pickup_range": 0.4}
# 只作为附属属性行出现、不做主属性 / 整行预算的属性（原版击退只是附属行，数值很小；拾取范围同理）。成长型道具的计数属性不受此限
const SIDE_ONLY_STATS = ["knockback", "pickup_range"]

# 可作为"对随机敌人造成 X% 属性伤害"缩放源的属性
const DAMAGE_SCALING_STATS = [
	"stat_max_hp", "stat_armor", "stat_luck", "stat_melee_damage", "stat_ranged_damage",
	"stat_elemental_damage", "stat_engineering", "stat_range", "stat_harvesting", "stat_hp_regeneration",
]
# 临时属性不允许的属性（收获在波末结算前生效、经验与拾取范围临时加成无意义）
const TEMP_STAT_BANNED = ["stat_harvesting", "xp_gain", "pickup_range", "consumable_heal"]

# 每点"每波持续获得量"的价值
# 下调（原值 1.2 / 1.0 / 0.3 / 0.055 由少数原版道具反推，与属性行比明显偏高）：
#   回血：+1 生命再生（权重 2.8）约每波回复 12 点 -> 每点约 0.25；按 0.5 计（触发回血可在需要时集中）
#   伤害：+1 远程伤害（权重 5）约作用于每波 300+ 次命中 -> 每点伤害约 0.015；按 0.022 计（直接伤害无视护甲 / 必中）
const HEAL_W = 0.5		# 每波回复 1 点生命
const GOLD_W = 0.75		# 每波获得 1 材料
const XP_W = 0.25		# 每波获得 1 经验
const DMG_W = 0.022		# 每波造成 1 点伤害
# 高频扳机（每波 20 次以上）的最低有效触发次数：更低就换别的组合，避免"每命中 30 次"这类门槛过高的条款
const MIN_FIRES_HIGH_FREQ = 6.0
# 高频扳机预算不足时，改用几率门控（"击杀敌人时（25% 几率）"，类似幸运币）而不是"每 N 次"的概率
const CHANCE_GATE_ON_EVERY = 0.5
const EXPLOSION_TARGETS = 2.5	# 爆炸平均命中数

# ------------------------------------------------------------
# 触发扳机
#   kind: event（事件）/ state（持续状态）/ shop（商店阶段事件）
#   e: 每波期望次数（state 为在场率）
#   timing: 临时属性叠层的时间系数（波开始时触发 = 整波生效）
#   gate: every = 通用门控（单次 / 几率 / 每 N 次，字符串 AA_T_X + AA_T_X_EVERY）；chance = 单次 / 几率（治疗频率不稳定、箱子太少，不计次）；
#         none = 只有单次（每波次数固定的扳机）
#   w: 基础出现权重（与原版先验相加）
# ------------------------------------------------------------
const TRIGGERS = {
	"kill": {"kind": "event", "e": 100.0, "timing": 0.5, "gate": "every", "w": 1.0},
	"hit": {"kind": "event", "e": 8.0, "timing": 0.5, "gate": "every", "w": 1.0},
	"dodge": {"kind": "event", "e": 4.0, "timing": 0.5, "gate": "every", "w": 1.0},
	"consumable": {"kind": "event", "e": 7.0, "timing": 0.5, "gate": "every", "w": 1.0},
	"gold": {"kind": "event", "e": 100.0, "timing": 0.5, "gate": "every", "w": 0.6},
	"heal": {"kind": "event", "e": 16.0, "timing": 0.5, "gate": "chance", "w": 0.4},
	"level_up": {"kind": "event", "e": 1.3, "timing": 0.5, "gate": "none", "w": 0.9},
	"wave_start": {"kind": "event", "e": 1.0, "timing": 1.0, "gate": "none", "w": 0.8},
	"wave_end": {"kind": "event", "e": 1.0, "timing": 0.0, "gate": "none", "w": 0.8},
	"interval": {"kind": "event", "e": 0.0, "timing": 0.5, "gate": "none", "w": 0.9},
	"still": {"kind": "state", "e": 0.25, "timing": 1.0, "gate": "none", "w": 1.0},
	"moving": {"kind": "state", "e": 0.75, "timing": 1.0, "gate": "none", "w": 1.0},
	"low_hp": {"kind": "state", "e": 0.15, "timing": 1.0, "gate": "none", "w": 0.5},
	"full_hp": {"kind": "state", "e": 0.45, "timing": 1.0, "gate": "none", "w": 0.4},
	"reroll": {"kind": "shop", "e": 3.0, "timing": 0.0, "gate": "every", "w": 0.5},
	# 暴击击杀（触手、狩猎奖杯）/ 击杀燃烧中的敌人（鬼火）：击杀的子集，频率取决于构筑；绑定暴击 / 元素词条
	"crit_kill": {"kind": "event", "e": 45.0, "timing": 0.5, "gate": "every", "w": 0.7},
	"burning_kill": {"kind": "event", "e": 30.0, "timing": 0.5, "gate": "every", "w": 0.3},
	# 每走 N 步（徒步旅行者）：移动时约每秒 3.33 步，每波约 200 步，实际强度不足，需要低估
	"steps": {"kind": "event", "e": 90.0, "timing": 0.5, "gate": "every", "w": 0.3},
	# 波次进行到一半时（赛博格）
	"half_wave": {"kind": "event", "e": 1.0, "timing": 0.5, "gate": "none", "w": 0.3},
	"buy": {"kind": "shop", "e": 3.0, "timing": 0.0, "gate": "every", "w": 0.2},
	# ---- 实验性扳机（低权重）----
	# 拾取箱子（原版袋子）
	"crate": {"kind": "event", "e": 0.8, "timing": 0.5, "gate": "chance", "w": 0.2},
	# 引发爆炸（任何来源：原版爆炸道具 / 武器）
	"explode": {"kind": "event", "e": 12.0, "timing": 0.5, "gate": "every", "w": 0.2},
	# 暴击命中（不必击杀）
	"crit": {"kind": "event", "e": 100.0, "timing": 0.5, "gate": "every", "w": 0.3},
	# 点燃敌人（敌人开始燃烧；原版以燃烧结算为准）
	"ignite": {"kind": "event", "e": 30.0, "timing": 0.5, "gate": "every", "w": 0.15},
	# 首次命中某个敌人（冰块、潜水员的"首次命中时"）；_typed = 限定伤害类型（条款的 dmg_type 字段，按命中的伤害缩放属性）
	# 一局通常只用一种伤害类型：限定类型与不限定的期望次数相同
	"first_hit": {"kind": "event", "e": 110.0, "timing": 0.5, "gate": "every", "w": 0.1},
	"first_hit_typed": {"kind": "event", "e": 110.0, "timing": 0.5, "gate": "every", "w": 0.16},
	# 命中生命值高于 / 低于 X% 的敌人（小鱼、原版"对高 / 低血敌人增伤"）：每次命中都计，按命中次数高估
	"hit_above_50": {"kind": "event", "e": 150.0, "timing": 0.5, "gate": "every", "w": 0.06},
	"hit_above_75": {"kind": "event", "e": 120.0, "timing": 0.5, "gate": "every", "w": 0.06},
	"hit_above_90": {"kind": "event", "e": 100.0, "timing": 0.5, "gate": "every", "w": 0.04},
	"hit_below_50": {"kind": "event", "e": 70.0, "timing": 0.5, "gate": "every", "w": 0.06},
	# 每次用某类伤害命中敌人（潜水员"被远程伤害命中的敌人受到伤害提高"）：只在"更多角色效果"开启时出现
	"hit_typed": {"kind": "event", "e": 150.0, "timing": 0.5, "gate": "every", "w": 0.2},
	# 用某类伤害击杀敌人（致命一击的伤害缩放属性；燃烧致死算元素）：同上，与击杀相同
	"kill_typed": {"kind": "event", "e": 100.0, "timing": 0.5, "gate": "every", "w": 0.3},
	# 击杀被诅咒的敌人（黑旗）：只在有诅咒时出现被诅咒的敌人，按每波约 5 个估计
	"cursed_kill": {"kind": "event", "e": 25.0, "timing": 0.5, "gate": "every", "w": 0.05},
	# 砍倒树木（口袋工厂）：每波约 3 棵
	"tree_kill": {"kind": "event", "e": 3.0, "timing": 0.5, "gate": "every", "w": 0.1},
	# 获得提升 [属性] 的道具（雪球）：商店阶段，条件属性 = 效果属性；每波约 0.5 件
	"buy_stat": {"kind": "shop", "e": 0.5, "timing": 0.0, "gate": "none", "w": 0.03},
}

# 实验性扳机（低权重）
const EXPERIMENTAL_TRIGGERS = [
	"crate", "explode", "crit", "ignite", "first_hit", "first_hit_typed", "hit_above_50", "hit_above_75", "hit_above_90",
	"hit_below_50", "hit_typed",
]
# 有目标敌人的扳机：可以挂"使该敌人受到的伤害提高"载荷
# 作用于目标敌人的载荷：门控只用单次 / 几率
const TARGET_PAYLOADS = ["vuln", "hp_dmg", "ignite", "slow"]
const ENEMY_TARGET_TRIGGERS = [
	"crit", "ignite", "first_hit", "first_hit_typed", "hit_above_50", "hit_above_75", "hit_above_90", "hit_below_50", "hit_typed",
]
# 限定伤害类型的扳机（条款的 dmg_type 字段）；hit_typed 只在"更多角色效果"开启时出现
const TYPED_TRIGGERS = ["first_hit_typed", "hit_typed", "kill_typed"]
# 伤害类型及其抽取权重（近战 : 远程 : 元素 : 工程 = 2 : 2 : 2 : 1）；伤害 / 爆炸载荷的缩放属性落在伤害类型上时同样按此分配
const DMG_TYPES = {"stat_melee_damage": 2.0, "stat_ranged_damage": 2.0, "stat_elemental_damage": 2.0, "stat_engineering": 1.0}
# 连锁深度上限（"A 触发 B、B 触发 C、C 触发 D"）；延迟生成的爆炸也携带深度
const MAX_CHAIN_DEPTH = 3
# 单条条款每秒最多触发次数（防止连锁在同一时刻刷屏）
const MAX_FIRES_PER_SECOND = 20
# 受伤加成载荷的估值：同时被伤害的敌人约 8 个，持续时间超过约 4 秒不再增值
const VULN_CONCURRENT_TARGETS = 8.0
const VULN_MAX_USEFUL_SECONDS = 4.0
# 受伤加成固定持续 3 秒（同原版冰块）
const VULN_SECONDS = 3
# 按当前生命值伤害：每 1%、每次触发的价值（巨型带：暴击约 80 次 / 波、10% ≈ 62 反推，实测偏强再 ×2）；单次上限 10%（同原版）
const HP_DMG_W = 0.16
const HP_DMG_MAX = 10
# 随机主属性：每点、每次触发的永久价值（糖果袋：每波 8 点、T3 估值 26.4 反推，实测偏强再 ×2）
const RAND_STAT_W = 1.7
# 点燃：3 跳燃烧、元素伤害参考值；减速：每 1%、每次触发（丑牙 5% / 命中约 150 次 / 估值 12.6 反推）；水果：每个
const IGNITE_TICKS = 3
const SLOW_W = 0.017
const SLOW_MAX = 10
const FRUIT_W = 2.0
# 击杀被诅咒的敌人：带这个扳机的道具附带原版黑旗式的 +X 诅咒（不计价值；诅咒让被诅咒的敌人出现）
const CURSED_KILL_CURSE = 5

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
	"perm_stat": {"w": 1.0},
	"timed_stat": {"w": 0.4},
	"heal": {"w": 0.3},
	"gold": {"w": 0.2},
	"xp": {"w": 0.2},
	"damage": {"w": 0.2},
	"explode": {"w": 0.4},
	"grant": {"w": 2.0},
	# 使该敌人受到的伤害提高 X%，持续 N 秒（原版冰块 / 潜水员的效果；只用于有目标敌人的扳机）
	"vuln": {"w": 0.5},
	# 按该敌人当前生命值的 X% 造成伤害（头目和精英为 X/10%）：巨型带（暴击时）、希腊火（燃烧时）；只用于有目标敌人的扳机
	"hp_dmg": {"w": 0.4},
	# 将 X 点属性点随机分配到主要属性上（糖果袋，永久）
	"rand_stats": {"w": 0.1},
	# 点燃该敌人（害怕的香肠）：3 次 × X（+100% 元素伤害）燃烧伤害
	"ignite": {"w": 0.4},
	# 降低该敌人速度 X%，最多 4X%（丑牙）
	"slow": {"w": 0.4},
	# 掉落 X 个水果（果篮）
	"fruit": {"w": 0.2},
}

# 合法组合：触发扳机 -> 允许的载荷
# 排除规则：状态扳机只挂临时属性；商店扳机只挂永久效果；回血扳机不挂回血（避免自激循环）；
# 拾取材料可以挂材料（直接加到材料数，不生成掉落物，不会循环；原版金属探测器）；波末 / 波初没有敌人和伤害意义的载荷被排除。
const LEGAL = {
	"kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats", "fruit"],
	"kill_typed": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats", "fruit"],
	"hit": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode"],
	"dodge": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode"],
	"consumable": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats"],
	"gold": ["temp_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode"],
	"heal": ["temp_stat", "timed_stat", "gold", "damage", "explode"],
	"level_up": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "damage", "explode", "rand_stats"],
	# 每波开始时"本波 +X 属性 / 本波获得"= 整波持有，与直接写在道具上无异：不生成
	"wave_start": ["perm_stat", "gold", "rand_stats"],
	"wave_end": ["perm_stat", "gold", "xp", "rand_stats"],
	"interval": ["temp_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode"],
	"still": ["temp_stat"],
	"moving": ["temp_stat"],
	"low_hp": ["temp_stat"],
	"full_hp": ["temp_stat"],
	"reroll": ["perm_stat", "gold", "rand_stats"],
	"buy": ["perm_stat", "gold", "rand_stats"],
	"crit_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats", "fruit"],
	"burning_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats", "fruit"],
	"steps": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "rand_stats"],
	"half_wave": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "rand_stats"],
	"crate": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "rand_stats"],
	"explode": ["temp_stat", "timed_stat", "heal", "gold", "damage"],
	"crit": ["temp_stat", "timed_stat", "heal", "gold", "damage", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"ignite": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"first_hit": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"first_hit_typed": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"hit_above_50": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"hit_above_75": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"hit_above_90": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"hit_below_50": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"hit_typed": ["temp_stat", "timed_stat", "heal", "gold", "damage", "explode", "vuln", "hp_dmg", "ignite", "slow", "fruit"],
	"cursed_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats", "fruit"],
	"tree_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "rand_stats", "fruit"],
	"buy_stat": ["perm_stat"],
}

# ============================================================
# 自由触发（选项）：任何扳机都能以"获得效果"为结果，合法表放宽为只排除自激循环与无意义组合
#   grant 载荷：触发时获得一条效果（可缩放机制 / 计数型 / 属性修改）
#     本波获得：可叠加，波末撤销；只允许战斗中实时生效的效果（GRANT_TEMP_KEYS）
#     永久获得：只允许求和型数值效果（存档安全）；商店扳机、波末只能永久获得
# ============================================================
const FREE_LEGAL = {
	"kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats", "fruit"],
	"kill_typed": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats", "fruit"],
	"hit": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"dodge": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"consumable": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"gold": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"heal": ["temp_stat", "perm_stat", "timed_stat", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"level_up": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "damage", "explode", "grant", "rand_stats"],
	"wave_start": ["perm_stat", "timed_stat", "gold", "xp", "grant", "rand_stats"],
	"wave_end": ["perm_stat", "gold", "xp", "grant", "rand_stats"],
	"interval": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"still": ["temp_stat", "grant"],
	"moving": ["temp_stat", "grant"],
	"low_hp": ["temp_stat", "grant"],
	"full_hp": ["temp_stat", "grant"],
	"reroll": ["perm_stat", "gold", "grant", "rand_stats"],
	"buy": ["perm_stat", "gold", "grant", "rand_stats"],
	"crit_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats", "fruit"],
	"burning_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats", "fruit"],
	"steps": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"half_wave": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	"crate": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats"],
	# 爆炸不挂爆炸（自激循环）；暴击不挂爆炸（爆炸可以暴击，形成循环）
	"explode": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "grant", "rand_stats"],
	"crit": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"ignite": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"first_hit": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"first_hit_typed": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"hit_above_50": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"hit_above_75": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"hit_above_90": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"hit_below_50": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"hit_typed": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "vuln", "hp_dmg", "rand_stats", "ignite", "slow", "fruit"],
	"cursed_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats", "fruit"],
	"tree_kill": ["temp_stat", "perm_stat", "timed_stat", "heal", "gold", "xp", "damage", "explode", "grant", "rand_stats", "fruit"],
	"buy_stat": ["perm_stat"],
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
	"dmg_on_dodge": ["dodge", "damage"],
	"dmg_when_death": ["kill", "damage"],
	"dmg_when_pickup_gold": ["gold", "damage"],
	"dmg_when_heal": ["heal", "damage"],
	"heal_on_dodge": ["dodge", "heal"],
	"heal_on_kill": ["kill", "heal"],
	"heal_on_crit_kill": ["crit_kill", "heal"],
	"heal_when_pickup_gold": ["gold", "heal"],
	"gold_on_crit_kill": ["crit_kill", "gold"],
	"gain_stat_for_every_step_after_equip": ["steps", "perm_stat"],
	"convert_stats_half_wave": ["half_wave", "temp_stat"],
	"explode_on_hit": ["hit", "explode"],
	"explode_on_death": ["kill", "explode"],
	"explode_on_consumable": ["consumable", "explode"],
	"gain_stat_for_killed_enemies_while_burning": ["burning_kill", "perm_stat"],
	"effect_gain_stat_every_killed_enemies": ["kill", "perm_stat"],
	# 袋子：拾取箱子时获得材料
	"item_box_gold": ["crate", "gold"],
	# 金属探测器：拾取材料时几率使其价值翻倍（= 几率 +1 材料）
	"chance_double_gold": ["gold", "gold"],
	# 巨型带 / 希腊火：暴击 / 燃烧时按敌人当前生命值造成伤害
	"giant_crit_damage": ["crit", "hp_dmg"],
	"burning_enemy_hp_percent_damage": ["ignite", "hp_dmg"],
	# 糖果袋：每波结束时随机主属性
	"gain_random_primary_stats_on_go_to_next_wave": ["wave_end", "rand_stats"],
	# 黑旗：击杀被诅咒的敌人时获得材料
	"gold_on_cursed_enemy_kill": ["cursed_kill", "gold"],
	# 害怕的香肠 / 丑牙：命中时点燃 / 减速（"命中敌人"类扳机，按命中高血敌人计）
	"burn_chance": ["hit_above_50", "ignite"],
	"remove_speed": ["hit_above_50", "slow"],
	# 雪球：获得提升 [属性] 的道具时 +[属性]
	"gain_stat_for_equipped_item_with_stat": ["buy_stat", "perm_stat"],
	# 冰块：首次被元素伤害命中时受伤加成（只认道具来源；潜水员的同类效果是角色身份）
	"enemy_percent_damage_taken": ["first_hit_typed", "vuln"],
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
# 沙漏 / 镜子本身会被重组（并去掉"用后变成另一件道具"），只保留它们不可获得的"用后形态"；
# 金鱼保持原样（低价是为了允许大量获取），它的效果仍参与组合
const ANCHORED_ITEMS = [
	"item_spyglass", "item_bait", "item_pocket_factory", "item_axolotl",
	"item_goldfish", "item_goldfish_used", "item_broken_hourglass", "item_broken_mirror",
	# 鱼钩（生物的诅咒初始道具、原版诅咒按 ID 特判）：本体保持原样，效果仍参与组合
	"item_fish_hook",
	"item_builder_turret_0", "item_builder_turret_1", "item_builder_turret_2", "item_builder_turret_3",
]
# 不作为机制来源：建造者炮台（角色专属）、蝾螈（属性互换按道具 ID 在商店中重置）
const MECHANIC_SOURCE_EXCLUDED = ["item_builder_turret_0", "item_builder_turret_1", "item_builder_turret_2", "item_builder_turret_3", "item_axolotl"]
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
	# 消耗品在 X 秒内持续治疗：文本是绿色，实际是代价（干肉条靠它换来高额属性）
	"consumable_heal_over_time": 0,
	"hp_start_next_wave": -1, "hp_start_wave": -1, "lose_hp_per_second": 1, "extra_elite_next_wave_chance": 1,
	"enemy_health": 1, "enemy_damage": 1, "enemy_speed": 1, "items_price": 1, "reroll_price": 1,
	"speed_cap": 0, "hp_cap": 0, "lock_current_weapons": 0, "extra_enemies_next_wave": 0, "number_of_enemies": -1,
	"gold_drops": -1, "enemy_gold_drops": -1, "dodge_cap": -1, "gain_pct_gold_start_wave": -1,
	"accuracy": -1, "burning_cooldown_reduction": -1, "piercing_damage": -1,
	# 更多双面效果：可缩放机制的反面
	"damage_against_bosses": -1, "recycling_gains": -1, "structure_attack_speed": -1, "loot_alien_chance": -1,
	"level_upgrades_modifications": -1,
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
	"enemy_percent_damage_taken",
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
	"fog_visibility", "stat_curse",
]

# 名称形容词：按主要效果选择（每项多个候选，按道具随机）
const ADJ_BY_STAT = {
	"stat_max_hp": ["AA_ADJ_STURDY", "AA_ADJ_HEARTY", "AA_ADJ_BULKY"],
	"stat_hp_regeneration": ["AA_ADJ_VITAL", "AA_ADJ_VERDANT", "AA_ADJ_MENDING"],
	"stat_lifesteal": ["AA_ADJ_THIRSTY", "AA_ADJ_VAMPIRIC", "AA_ADJ_LEECHING"],
	"stat_percent_damage": ["AA_ADJ_SHARP", "AA_ADJ_KEEN", "AA_ADJ_FIERCE"],
	"stat_melee_damage": ["AA_ADJ_BRUTAL", "AA_ADJ_HEAVY", "AA_ADJ_SAVAGE"],
	"stat_ranged_damage": ["AA_ADJ_AIMED", "AA_ADJ_PRECISE", "AA_ADJ_HAWKEYED"],
	"stat_elemental_damage": ["AA_ADJ_ARCANE", "AA_ADJ_BLAZING", "AA_ADJ_STORMY"],
	"stat_attack_speed": ["AA_ADJ_HASTY", "AA_ADJ_FRANTIC", "AA_ADJ_RAPID"],
	"stat_crit_chance": ["AA_ADJ_DEADLY", "AA_ADJ_LETHAL", "AA_ADJ_VICIOUS"],
	"stat_engineering": ["AA_ADJ_CLEVER", "AA_ADJ_MECHANICAL", "AA_ADJ_TINKERING"],
	"stat_range": ["AA_ADJ_FARSIGHTED", "AA_ADJ_LONG", "AA_ADJ_TELESCOPIC"],
	"stat_armor": ["AA_ADJ_ARMORED", "AA_ADJ_PLATED", "AA_ADJ_STALWART"],
	"stat_dodge": ["AA_ADJ_ELUSIVE", "AA_ADJ_SLIPPERY", "AA_ADJ_PHANTOM"],
	"stat_speed": ["AA_ADJ_SWIFT", "AA_ADJ_FLEET", "AA_ADJ_BREEZY"],
	"stat_luck": ["AA_ADJ_LUCKY", "AA_ADJ_FORTUNATE", "AA_ADJ_CHARMED"],
	"stat_harvesting": ["AA_ADJ_FERTILE", "AA_ADJ_BOUNTIFUL", "AA_ADJ_HARVEST"],
	"xp_gain": ["AA_ADJ_WISE", "AA_ADJ_STUDIOUS"],
	"pickup_range": ["AA_ADJ_MAGNETIC", "AA_ADJ_GRABBY"],
	"knockback": ["AA_ADJ_BOUNCY", "AA_ADJ_FORCEFUL"],
	"explosion_damage": ["AA_ADJ_VOLATILE", "AA_ADJ_EXPLOSIVE"],
	"explosion_size": ["AA_ADJ_VOLATILE", "AA_ADJ_EXPLOSIVE"],
	"consumable_heal": ["AA_ADJ_TASTY", "AA_ADJ_NOURISHING"],
}
const ADJ_BY_TRIGGER = {
	"crit_kill": ["AA_ADJ_DEADLY", "AA_ADJ_EXECUTING"], "burning_kill": ["AA_ADJ_BLAZING", "AA_ADJ_SCORCHING"],
	"steps": ["AA_ADJ_WANDERING", "AA_ADJ_HIKING"], "half_wave": ["AA_ADJ_MIDWAY", "AA_ADJ_TIMELY"],
	"kill": ["AA_ADJ_HUNTING", "AA_ADJ_PREDATORY"], "hit": ["AA_ADJ_VENGEFUL", "AA_ADJ_SPITEFUL"],
	"dodge": ["AA_ADJ_NIMBLE", "AA_ADJ_EVASIVE"], "consumable": ["AA_ADJ_HUNGRY", "AA_ADJ_GLUTTONOUS"],
	"gold": ["AA_ADJ_GREEDY", "AA_ADJ_HOARDING"], "heal": ["AA_ADJ_BLESSED", "AA_ADJ_HOLY"],
	"level_up": ["AA_ADJ_GROWING", "AA_ADJ_AMBITIOUS"], "wave_start": ["AA_ADJ_EAGER", "AA_ADJ_DAWNING"],
	"wave_end": ["AA_ADJ_PATIENT", "AA_ADJ_DUSK"], "interval": ["AA_ADJ_TICKING", "AA_ADJ_RHYTHMIC"],
	"still": ["AA_ADJ_ROOTED", "AA_ADJ_CALM"], "moving": ["AA_ADJ_RESTLESS", "AA_ADJ_WANDERING"],
	"low_hp": ["AA_ADJ_DESPERATE", "AA_ADJ_CORNERED"], "full_hp": ["AA_ADJ_PROUD", "AA_ADJ_PRISTINE"],
	"reroll": ["AA_ADJ_FICKLE", "AA_ADJ_GAMBLING"], "buy": ["AA_ADJ_THRIFTY", "AA_ADJ_SHOPAHOLIC"],
	"crate": ["AA_ADJ_GREEDY", "AA_ADJ_CURIOUS"], "explode": ["AA_ADJ_BLAZING", "AA_ADJ_FIERCE"],
	"crit": ["AA_ADJ_DEADLY", "AA_ADJ_KEEN"], "ignite": ["AA_ADJ_BLAZING", "AA_ADJ_SCORCHING"],
	"first_hit": ["AA_ADJ_EAGER", "AA_ADJ_KEEN"], "first_hit_typed": ["AA_ADJ_EAGER", "AA_ADJ_FIERCE"],
	"kill_typed": ["AA_ADJ_FIERCE", "AA_ADJ_KEEN"],
	"hit_above_50": ["AA_ADJ_PREDATORY", "AA_ADJ_EAGER"], "hit_above_75": ["AA_ADJ_PREDATORY", "AA_ADJ_EAGER"],
	"hit_above_90": ["AA_ADJ_PREDATORY", "AA_ADJ_EAGER"], "hit_below_50": ["AA_ADJ_EXECUTING", "AA_ADJ_DEADLY"],
	"hit_typed": ["AA_ADJ_FIERCE", "AA_ADJ_KEEN"],
	"cursed_kill": ["AA_ADJ_HUNTING", "AA_ADJ_DEADLY"],
	"tree_kill": ["AA_ADJ_WANDERING", "AA_ADJ_CURIOUS"], "buy_stat": ["AA_ADJ_GROWING", "AA_ADJ_AMBITIOUS"],
}
const ADJ_MECHANIC = ["AA_ADJ_ODD", "AA_ADJ_STRANGE", "AA_ADJ_CURIOUS", "AA_ADJ_ANCIENT"]
const ADJ_SCALING = ["AA_ADJ_RESONANT", "AA_ADJ_SYNERGIC"]
const ADJ_GAIN_MOD = ["AA_ADJ_AMPLIFIED", "AA_ADJ_REFINED"]
const ADJ_GRANT = ["AA_ADJ_AWAKENED", "AA_ADJ_CHARGED"]


static func is_downside_mechanic(e) -> bool:
	var k = e.key if DOWNSIDE_SIGN.has(e.key) else e.custom_key
	if not DOWNSIDE_SIGN.has(k):
		return false
	var sg = DOWNSIDE_SIGN[k]
	return sg == 0 or (sg > 0 and e.value > 0) or (sg < 0 and e.value < 0)


static func stat_w(stat: String) -> float:
	if STATS.has(stat):
		return STATS[stat].w
	if ENEMY_STATS.has(stat):
		return ENEMY_STATS[stat].w
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
const PAYLOAD_CATEGORY = {"heal": "S", "gold": "E", "xp": "E", "damage": "A", "explode": "A", "vuln": "A", "hp_dmg": "A", "ignite": "A", "slow": "S", "fruit": "S"}
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
	"stat_armor": 8.0, "stat_elemental_damage": 12.0, "stat_speed": 16.0, "stat_crit_chance": 25.0,
	"stat_dodge": 25.0, "knockback": 12.0,
	"materials": 240.0, "structure": 3.0, "living_enemy": 24.0, "burning_enemy": 8.0, "living_tree": 3.0,
	"percent_player_missing_health": 30.0, "different_item": 18.0, "common_item": 12.0, "legendary_item": 1.5,
	"free_weapon_slots": 0.8,
	# 成长型道具的计数（次要属性、诅咒）：诅咒按闪避估计
	"xp_gain": 30.0, "pickup_range": 40.0, "explosion_damage": 30.0, "explosion_size": 20.0, "consumable_heal": 4.0,
	"stat_curse": 25.0,
}
# ============================================================
# 成长型道具（原版石头皮肤、线圈、发电机、复古卫衣）：小概率生成，T2 及以上
#   可选的 +[属性 A] 行（数值像副属性）+ 高转化率的"每有 [属性 A] 获得 [属性 B]" + 可选的代价，带限制 (X)
#   B 只取 %伤害 / 攻速 / 最大生命（2 : 2 : 1）；A 取主 / 次要属性与诅咒
# ============================================================
const GROWTH_ITEM_CHANCE = 0.06
const GROWTH_TARGETS = {"stat_percent_damage": 2.0, "stat_attack_speed": 2.0, "stat_max_hp": 1.0}
const GROWTH_COUNTERS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage",
	"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
	"stat_range", "stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting",
	"xp_gain", "pickup_range", "knockback", "explosion_damage", "explosion_size", "consumable_heal", "stat_curse",
]
const GROWTH_LINE_CHANCE = 0.5
const GROWTH_LINE_SHARE = 0.2
const GROWTH_CURSE_LINE = 4
const GROWTH_DOWNSIDE_CHANCE = 0.5
# 限制 (X)：1 = 独特
const GROWTH_LIMITS = {1: 3.0, 2: 2.0, 3: 1.0}

# 可用的非属性计数与原版描述 key
const COUNTER_TEXT = {
	"free_weapon_slots": "EFFECT_GAIN_STAT_FOR_FREE_WEAPON_SLOTS",
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
	if counter.begins_with("item_"):
		return GUARANTEED_ITEM_COPIES
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
const SPECIAL_KIND_WEIGHTS = {"trigger": 0.43, "scaling": 0.16, "gain_mod": 0.07, "mechanic": 0.19, "next_wave": 0.06, "char": 0.09}
# 可按预算缩放数值的机制（原版 Effect，数值线性含义）：缩放范围为原版数值的 1 单位 .. 1.5 倍
const SCALAR_MECHANIC_EXCLUDED = ["hp_start_next_wave", "hp_start_wave", "speed_cap", "hp_cap", "lock_current_weapons", "dodge_cap", "one_shot_trees", "structures_can_crit"]


# ============================================================
# 敌人属性（作为代价）：每 1% 的"整局持有"价值。孔雀（+25% 经验，下一波 +100% 经验、+50% 敌人伤害，50 材料）
# 与芹菜茶校准后大致吻合；负面价值同样按负面除数折算
# ============================================================
const ENEMY_STATS = {
	"enemy_health": {"w": 0.6, "unit": 1},
	"enemy_damage": {"w": 0.8, "unit": 1},
	"enemy_speed": {"w": 2.4, "unit": 1},
}

# ============================================================
# 下一波（原版芹菜茶 / 孔雀 / 围巾）：一次性，写入 stats_next_wave，下一波开始时生效一次后清空。
# 一波的价值 = 整局持有价值 / 剩余波数，剩余波数 ≈ 2 × 永久累积倍率 − 1
# ============================================================
const NEXT_WAVE_STATS = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage",
	"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
	"stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting", "xp_gain",
]
# "下一波"正面行的属性权重：原版只用于经验，这里偏向运营属性（经验、收获、幸运），其余属性权重较低
# 只允许 +经验（权重高）与"下一波额外出现战利品外星人"（原版诱饵）
const NEXT_WAVE_POS_KINDS = {"xp_gain": 0.7, "loot_aliens": 0.3}
# 每个额外战利品外星人（一次性）的价值：原版诱饵 34 材料（+2 再生、下一波 +2 个）反推约 4.6
const LOOT_ALIEN_VALUE = 4.6
# "下一波"正面行附带同一行为下负面行的概率（原版芹菜茶、孔雀都是成对的）
const NEXT_WAVE_PAIR_CHANCE = 0.5
# 属性类触发条款附带同一扳机负面部分的概率
const PAIRED_CLAUSE_CHANCE = 0.4


static func remaining_waves(perm_mult: float) -> float:
	return max(2.0, 2.0 * perm_mult - 1.0)


# ============================================================
# 词条绑定：触发扳机 / 计数 / 载荷 / 机制 key -> 额外词条（角色的"想要词条"据此命中）
# 依据原版：暴击击杀类（触手、狩猎奖杯）带暴击；燃烧类（鬼火、希腊火、胆小香肠、蛇、眼部手术）带元素；
# 静止类（珊瑚、雕像）带静止；建筑相关带构筑物。原版漏标的"每个燃烧敌人""每个建筑"在这里补上。
# ============================================================
const TAG_BINDINGS = {
	"trigger:crit_kill": ["stat_crit_chance"], "trigger:burning_kill": ["stat_elemental_damage"],
	"trigger:still": ["stand_still"], "trigger:consumable": ["consumable"], "trigger:steps": ["stat_speed"],
	"counter:burning_enemy": ["stat_elemental_damage"], "counter:structure": ["structure"], "counter:pet": ["pet"],
	"counter:materials": ["economy"],
	"payload:explode": ["explosive"], "payload:gold": ["economy"], "payload:xp": ["xp_gain"],
	"trigger:explode": ["explosive"], "trigger:crit": ["stat_crit_chance"], "trigger:ignite": ["stat_elemental_damage"],
	"trigger:cursed_kill": ["stat_curse"], "payload:hp_dmg": ["stat_percent_damage"],
	"trigger:tree_kill": ["exploration"], "payload:ignite": ["stat_elemental_damage"], "payload:slow": ["less_enemy_speed"],
	"payload:fruit": ["consumable"],
	"mech:pierce_on_crit": ["stat_crit_chance"], "mech:giant_crit_damage": ["stat_crit_chance"],
	"mech:structures_can_crit": ["structure", "stat_crit_chance"],
	"mech:burning_spread": ["stat_elemental_damage"], "mech:burning_cooldown_reduction": ["stat_elemental_damage"],
	"mech:burn_chance": ["stat_elemental_damage"], "mech:burning_enemy_hp_percent_damage": ["stat_elemental_damage"],
	"mech:bonus_non_elemental_damage_against_burning_targets": ["stat_elemental_damage"],
	"mech:structure_attack_speed": ["structure"], "mech:tree_turrets": ["structure"], "mech:group_structures": ["structure"],
	"mech:structures_cooldown_reduction": ["structure"], "mech:pacifist": ["economy"],
	"mech:extra_loot_aliens_next_wave": ["economy"],
	# 依据原版：闪避触发（肾上腺素、还击）带闪避；拾取材料触发（可爱猴子、小象）带拾取；箱子（袋子）带探索；
	# 对高血量目标增伤（小鱼）带 %伤害；黑旗（诅咒敌人掉材料）带诅咒；其余机制按原版来源道具的词条
	"trigger:dodge": ["stat_dodge"], "trigger:gold": ["pickup"], "trigger:crate": ["exploration"],
	"payload:vuln": ["stat_percent_damage"],
	"mech:gold_on_cursed_enemy_kill": ["stat_curse"], "mech:harvesting_growth": ["stat_harvesting"],
	"mech:instant_gold_attracting": ["pickup"], "mech:chance_double_gold": ["pickup", "economy"],
	"mech:enemy_fruit_drops": ["consumable"], "mech:trees": ["exploration"], "mech:one_shot_trees": ["exploration"],
	"mech:free_rerolls": ["economy"], "mech:items_price": ["economy"], "mech:recycling_gains": ["economy"],
	"mech:remove_speed": ["less_enemy_speed"], "mech:bonus_damage_against_targets_above_hp": ["stat_percent_damage"],
	"mech:damage_against_bosses": ["stat_percent_damage"],
}


static func tags_for_binding(k: String) -> Array:
	return TAG_BINDINGS.get(k, [])


# ============================================================
# 来自角色、默认进入道具池的效果（直接生成，不依赖"道具含角色效果"选项）
#   武器类型加成（狂人、医生、斗士……）：使用 [类型] 武器 +X [属性]；价值 = 属性权重 × X × 该类型武器的平均占比
#   武器栏：+1（原版角色为"设定值"，道具改为累加）；燃烧目标额外伤害（厨师）；构筑物聚集（工程师）；
#   波末每个存活敌人获得材料与经验（和平主义者）；代价：每波结束敌人属性提高（船长）、−1 武器栏
# ============================================================
const CLASS_BONUS_SHARE = 0.35
# 武器类型加成可选的属性：显示名 -> {原版武器属性字段 name, 每点权重 w, 粒度 unit, 上限 max}
#   原版角色用过的（攻速、%伤害、范围、吸血、伤害、暴击伤害）之外，加入暴击率与贯通：
#   原版的类型加成直接把数值加到武器属性上，暴击率是小数、贯通会被远程武器的通用计算覆盖，
#   两者由本 mod 的 WeaponService 扩展修正（暴击率按百分比、贯通在通用计算之后再加）；
#   近战武器没有贯通字段，贯通只给全是远程武器的类型（原版只有枪械）
const CLASS_BONUS_KINDS = {
	"stat_attack_speed": {"name": "attack_speed_mod", "w": 1.4, "unit": 5, "max": 60},
	"stat_percent_damage": {"name": "stat_percent_damage", "w": 1.5, "unit": 5, "max": 60},
	"stat_range": {"name": "max_range", "w": 0.35, "unit": 10, "max": 100},
	"stat_lifesteal": {"name": "lifesteal", "w": 4.7, "unit": 5, "max": 30},
	"stat_damage": {"name": "damage", "w": 1.8, "unit": 5, "max": 15},
	"stat_crit_damage": {"name": "crit_damage", "w": 0.45, "unit": 25, "max": 200},
	"stat_crit_chance": {"name": "crit_chance", "w": 1.85, "unit": 5, "max": 25},
	"piercing": {"name": "piercing", "w": 15.0, "unit": 1, "max": 2, "ranged_only": true},
}
# （旧表，武器类型加成的权重见 CLASS_BONUS_KINDS）
const BURN_BONUS_W = 0.12		# 燃烧目标额外伤害，每 1%
const PACIFIST_W = 0.4			# 每 0.01 材料+经验 / 存活敌人（波末约 30 个存活敌人）
const WEAPON_SLOT_W = 25.0
const GROUP_STRUCTURES_VALUE = 6.0
const CHAR_COMPONENT_WEIGHTS = {"class_bonus": 0.5, "burn_bonus": 0.1, "pacifist": 0.05, "weapon_slot": 0.1}
# "更多角色效果"选项开启时追加的角色效果
const MORE_CHAR_COMPONENT_WEIGHTS = {
	"group_structures": 0.05, "xp_needed": 0.15, "cryptid": 0.1, "charm": 0.08, "beast_master": 0.05,
	"map_size": 0.04, "self_price": 0.06, "weapons_price": 0.08,
}
# 更多角色效果的代价：道具价格 +X%、升级所需经验 +X%
const MORE_CHAR_DOWNSIDE_CHANCE = 0.4
# 神秘生物：波末每棵存活的树获得 X 材料与经验；波末平均存活约 2 棵树
const CRYPTID_TREES = 2.0
# 浪漫者：命中低于 25% 生命的敌人时几率魅惑（几率随最大生命缩放，原版 50 = 最大生命的 50%）；每 1 点系数的价值
const CHARM_W = 0.3
# 驯兽师：宠物伤害随四种伤害属性缩放（只在有宠物时有用，不可叠加）
const BEAST_MASTER_VALUE = 8.0
# 地图大小 ±X%：好坏取决于流派，价值约为 0（同 +诅咒）
const MAP_SIZE_VALUES = [-15, -10, -5, 5, 10, 15]
const MAP_SIZE_W = 0.02
# 这件道具自身价格 -100%（渔夫的诱饵 / 潜水员的鱼叉枪）：后续同名道具免费，价值约为道具预算的 25%
const SELF_PRICE_SHARE = 0.25
# 武器价格 -X%（军火商）：每波约 40 材料花在武器上
const WEAPON_SPEND_PER_WAVE = 40.0
# 武器数量计数（常规池，计数型的一种）：原版的"每把不同武器 / 每把武器 / 每把 IV 级 / 每把 I 级武器"效果
# 计数期望：不同武器约 3.5、武器约 5、IV 级武器全局平均约 1、I 级武器约 1.2
const WEAPON_COUNTERS = {
	"unique_weapon_effects": 2.5, "additional_weapon_effects": 5.0,
	"tier_iv_weapon_effects": 1.0, "tier_i_weapon_effects": 1.2,
}
const WEAPON_COUNTER_CHANCE = 0.2
# 升级所需经验 ±X%（变异体 / 宝宝 / 技术法师 / 船长）：等价于获得经验 ×1/(1+X%)，非线性
#   -67% 所需经验 = +200% 获得经验；+100% 所需经验 = -50% 获得经验
const XP_NEEDED_MIN = -60		# 单条最多 -60%（= +150% 经验）
const XP_NEEDED_MAX = 100		# 代价最多 +100%（= -50% 经验）
# 运行时总和的下限：多条叠加（或诅咒放大）后所需经验不低于原版的 10%，避免 ≤ -100% 时除零 / 负数
const XP_NEEDED_TOTAL_FLOOR = -90


static func xp_needed_equiv_pct(x: float) -> float:
	return 100.0 / (1.0 + max(-99.0, x) / 100.0) - 100.0


static func xp_needed_for_equiv(g: float) -> float:
	return 100.0 / (1.0 + max(-99.0, g) / 100.0) - 100.0


# ============================================================
# 全部角色效果（BETA 选项）：其余可以原样搬到道具上的角色效果（不新增效果、不改原版逻辑）。
# 多数是重大限制，作为代价时换来的预算较高（got，已是折算后的补偿，单位：材料）；
# min_budget：道具总预算低于此值时不使用（避免低稀有度道具带"一击必死"这类代价）
# 捆绑：同一角色里互相依赖的两行一起出现（多面手的近战 / 远程武器上限、军火商的摧毁武器 + 商店至少一把武器）
# 排除（需要大量补丁 / 按角色或道具 ID 硬编码 / 诅咒处理不正确）：初始道具 / 武器、恶魔的材料转生命与生命购物、
# 建造者的材料转构筑物属性、渔夫的强化诱饵（只对诱饵生效）、无法装备武器、诅咒与空文本的内部效果
# ============================================================
const BETA_RESTRICTIONS = {
	"die_in_one_hit": {"got": 45.0, "w": 1.0, "min_budget": 35.0},
	"can_attack_while_moving": {"got": 30.0, "w": 0.8, "min_budget": 25.0},
	"destroy_weapons": {"got": 40.0, "w": 0.7, "min_budget": 30.0},
	"no_heal": {"got": 18.0, "w": 1.0, "min_budget": 14.0},
	"max_weapon_tier": {"got": 18.0, "w": 0.7, "min_budget": 14.0},
	"no_melee_weapons": {"got": 10.0, "w": 1.0, "min_budget": 8.0},
	"no_ranged_weapons": {"got": 10.0, "w": 1.0, "min_budget": 8.0},
	"no_duplicate_weapons": {"got": 8.0, "w": 0.8, "min_budget": 6.0},
	"max_melee_weapons": {"got": 6.0, "w": 0.7, "min_budget": 5.0},
	"min_weapon_tier": {"got": 4.0, "w": 0.5, "min_budget": 3.0},
	"poisoned_fruit": {"got": 6.0, "w": 0.7, "min_budget": 4.0},
	"stronger_elites_on_kill": {"got": 6.0, "w": 0.5, "min_budget": 4.0},
	"disable_item_locking": {"got": 8.0, "w": 0.6, "min_budget": 6.0},
	"remove_shop_items": {"got": 5.0, "w": 0.5, "min_budget": 4.0},
}
# 捆绑的第二行
const BETA_BUNDLES = {"max_melee_weapons": "max_ranged_weapons", "destroy_weapons": "minimum_weapons_in_shop"}
# 全部角色效果开启时，代价里使用这些限制的概率
const BETA_RESTRICTION_CHANCE = 0.5
# 正面效果（进入"角色效果"特殊行）
const BETA_POSITIVE_WEIGHTS = {
	"all_weapons_sets": 0.06, "min_weapons_shop": 0.03, "weapon_slot_upgrades": 0.05,
	"item_steals": 0.04, "guaranteed_item": 0.08,
}
# 升级属性 ±X%（船长 / 藤壶；正面已在常规机制池）：每波约 1.3 次升级，每次升级约值 8 材料
const LEVELS_PER_WAVE = 1.3
const LEVEL_UPGRADE_VALUE = 8.0
const ALL_WEAPONS_SETS_VALUE = 10.0
const MIN_WEAPONS_SHOP_VALUE = 2.0
# 升级时获得武器栏而不是属性（宝宝）：上限 6 + k，每个武器栏约 25，减去失去的一次升级
const WEAPON_SLOT_UPGRADE_NET = 13.0
# 每个商店可偷 1 件道具（黑帮，偷窃可能生成精英）：每波约值 12 材料
const ITEM_STEAL_PER_WAVE = 12.0
# 商店总是出售 [某件一级道具] + 每有 1 个该道具获得 +N 属性（渔夫与诱饵）：平均每两波买一件，持有期间平均约 3.5 件
const GUARANTEED_ITEM_COPIES = 3.5
# 带"设定值 / 列表"型角色效果（原版按角色只有一份）的道具设为独特，避免同一效果叠加后撤销出错
const BETA_UNIQUE_KEYS = [
	"die_in_one_hit", "can_attack_while_moving", "destroy_weapons", "minimum_weapons_in_shop", "max_weapon_tier",
	"min_weapon_tier", "max_melee_weapons", "max_ranged_weapons", "remove_shop_items", "weapon_slot_upgrades",
	"all_weapons_count_for_sets", "guaranteed_shop_items",
]
# 原版独特道具上、多份叠加会出技术问题的效果：带这些效果的重组道具设为独特
#   覆盖写入（多份不叠加，卖掉一份会恢复旧值）：击退光环（灯笼）、闪避上限（幽灵服）、消耗品持续回复（干肉条）、锁定武器（结）
#   只取一份 / 开关型（第二份无作用，或作为代价时白给预算）：生命 / 速度上限（手铐 / 镣铐）、最小攻击间隔（链球）、
#   每第 X 发投射物（海贝壳，按 X 互相覆盖）、构筑物可暴击（一堆书）、一击砍树（伐木工人衬衫）
const UNIQUE_MECHANIC_KEYS = [
	"knockback_aura", "dodge_cap", "consumable_heal_over_time", "lock_current_weapons", "hp_cap", "speed_cap",
	"minimum_weapon_cooldowns", "modify_every_x_projectile", "structures_can_crit", "one_shot_trees",
]
# 同上，按效果脚本识别：搜刮虫虫（刷怪器每个玩家只记录一只，多只追同一个目标）
const UNIQUE_MECHANIC_SCRIPTS = ["res://effects/items/lootworm_effect.gd"]

# ============================================================
# 更多双面效果（选项）：常规池里只以正面 / 只以负面出现的效果，加入它们的对立面
#   可缩放机制的反面作为代价（-X% 材料掉落 = 贪婪之帽的反面、+X% 刷新价格、+X% 敌人速度……）：
#     价值 = 正面每单位价值 × 数值 / 负面除数；数值上限见 DOUBLE_NEG_CAPS（避免 -100% 等于禁用）
#   负面机制的反面作为好处：-X% 敌人生命 / 伤害（黑旗的反面），按敌人属性的整局价值估值
#   -1 武器栏、-X% [类型] 武器属性、+X% 武器价格、+X% 道具价格（代价）；每波结束时敌人属性降低（船长的反面）、
#   下一波敌人属性降低；触发条款的代价可以是"失去材料"
# ============================================================
const DOUBLE_NEG_CAPS = {
	"gold_drops": 50, "enemy_gold_drops": 50, "damage_against_bosses": 50, "recycling_gains": 50,
	"gain_pct_gold_start_wave": 50, "structure_attack_speed": 30, "loot_alien_chance": 50,
	"level_upgrades_modifications": 40, "reroll_price": 50, "enemy_speed": 15,
}
const DOUBLE_POS_ENEMY_CAPS = {"enemy_health": 15, "enemy_damage": 15}
# 每波结束时敌人属性 -X%（每波累积）的单次上限
const ENEMY_DECAY_MAX = 2
# "失去材料"代价可以挂在这些扳机上
const LOSE_GOLD_TRIGGERS = ["kill", "hit", "dodge", "interval", "consumable"]
const LOSE_GOLD_CHANCE = 0.35
# 下一波正面：敌人属性降低（单条上限）
const NEXT_WAVE_ENEMY_DOWN_MAX = 40

# ============================================================
# 角色重组：正面组件（属性行 / 属性修改 / 计数）按同等价值换成这些类型之一；属性修改 / 计数换成别的类型的概率
# 偏好词条：偏好属性作为正面的权重 ×WANTED_BIAS（作为代价 ×0.1），绑定偏好词条的扳机 / 载荷 / 计数同样加权
# ============================================================
const CHAR_REASSEMBLE_KINDS = {"stat": 0.4, "clause": 0.35, "scaling": 0.13, "gain_mod": 0.12}
const CHAR_CONVERT_CHANCE = 0.5
const WANTED_BIAS = 4.0

# 非线性的机制：价值 = 单位价值 × (数值 - offset)，数值不低于 min
#   拷问（每秒回复 X 生命，不能以其他方式回血）：回复太少时整件道具等于"无法回血"，至少 4 点才有意义
const MECHANIC_INTERCEPT = {"torture": {"offset": 3, "min": 4}}

# T3 及以上（稀有度索引 >= 2）的道具至少有两条效果
const MIN_LINES_TIER = 2
const MIN_LINES = 2

# T4 道具不出现的正面属性（与原版一致：原版 T4 没有 +收获 / +拾取范围 / +消耗品回复）
const T4_BANNED_POSITIVE_STATS = ["stat_harvesting", "pickup_range", "consumable_heal"]
# 负面触发条款使用敌人属性（生命 / 伤害 / 速度提高）的概率
const NEGATIVE_CLAUSE_ENEMY_CHANCE = 0.3

# 核心属性道具：T1–T3 每档、每个重要输出 / 收获属性各保证一件"唯一正面效果就是该属性"的道具（可附带负面），作为构筑的过渡
const CORE_STATS = [
	"stat_percent_damage", "stat_melee_damage", "stat_ranged_damage", "stat_elemental_damage",
	"stat_engineering", "stat_attack_speed", "stat_harvesting", "xp_gain",
]
const CORE_TIERS = [0, 1, 2]
const CORE_VALUE_MULT = 1
# 核心道具单行上限相对普通上限的倍数（数值更高的单属性道具）
const CORE_LINE_CAP_MULT = 1.5

# 原版 DLC 诅咒按道具 ID 特判的属性行（鬼火的元素伤害行会写入 value3，普通效果没有该字段；
# 艾斯蒂的沙发的速度行无论正负都按正面加强，-速度会越诅咒越低）：这些道具上不生成对应的普通属性行
const ITEM_STAT_BANS = {"item_will_o_the_wisp": ["stat_elemental_damage"], "item_estys_couch": ["stat_speed"]}

# 原道具上保留的原版行：+诅咒（深海 DLC 的诅咒道具）。价值约为 0，但水手 / 生物等角色想要带"诅咒"词条的道具，
# 保留后这些道具仍带 stat_curse 词条
const PRESERVED_NATIVE_KEYS = ["stat_curse"]

# 原版这些计数的文本不显示"每 N 个"（原版只用 N = 1）：生成时 N 固定为 1，单个计数的价值即最小价值
const COUNTER_NB_FIXED = [
	"different_item", "common_item", "legendary_item", "living_enemy", "burning_enemy", "living_tree", "free_weapon_slots",
]


static func counter_text(counter: String, perm_only: bool) -> String:
	if COUNTER_TEXT.has(counter):
		return COUNTER_TEXT[counter]
	return "EFFECT_GAIN_STAT_FOR_EVERY_PERM_STAT" if perm_only else "EFFECT_GAIN_STAT_FOR_EVERY_STAT"

# 几率类效果的上限（%）：单条效果超过 100% 没有意义。生成时（机制缩放、获得效果的单次数量）不超过此上限，
# 价值按截断后的数值折算，多出的预算留给其他行。多条效果叠加 / 诅咒后超过 100% 与原版一致，不做限制。
# 战利品外星人出现几率是相对值（+100% = 基础几率 ×2），不在此列
const PCT_CAPS = {
	"instant_gold_attracting": 100, "chance_double_gold": 100, "curse_locked_items": 100, "extra_item_in_crate": 100,
}


static func pct_cap(e) -> int:
	if e == null:
		return -1
	var k = e.custom_key if e.custom_key != "" else e.key
	return int(PCT_CAPS.get(k, -1))
