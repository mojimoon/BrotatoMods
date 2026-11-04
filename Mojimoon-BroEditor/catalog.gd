extends Reference

# BroEditor 静态目录：可编辑属性、扳机（原版"条件属性"效果的 custom_key）、效果库分类。
#
# 原版的触发 / 条件型属性效果都是同一个结构：Effect{ key = 属性, value = 数值, custom_key = 扳机, storage = KEY_VALUE }，
# 换扳机 = 换 custom_key（连同对应的 text_key / 额外参数），换属性 = 换 key。蓝图编辑器因此只需要
# "一个扳机模板 + 属性 + 数值"：从原版效果中找一条该扳机的效果作为模板，复制后改 key / value。
# （拆解方式参考 AutoAnthony 的 NATIVE_TRIGGER_MAP。）

# 初始属性页：[分组名 key, [属性 key...]]。不存在于本版本玩家效果表中的 key 运行时自动跳过。
const STAT_GROUPS = [
	["BE_GRP_PRIMARY", [
		"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage", "stat_melee_damage",
		"stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed", "stat_crit_chance", "stat_engineering",
		"stat_range", "stat_armor", "stat_dodge", "stat_speed", "stat_luck", "stat_harvesting",
	]],
	["BE_GRP_SECONDARY", [
		"xp_gain", "pickup_range", "knockback", "consumable_heal", "explosion_damage", "explosion_size",
		"piercing", "piercing_damage", "bounce", "bounce_damage", "projectiles", "damage_against_bosses",
		"burning_spread", "burning_cooldown_reduction", "structure_attack_speed", "structure_percent_damage",
		"structure_range", "accuracy", "harvesting_growth", "weapon_slot", "stat_curse", "chance_double_gold",
		"item_box_gold", "heal_when_pickup_gold", "burning_cooldown_increase", "hit_protection", "lose_hp_per_second",
		"bonus_crit_damage", "fire_puddle_size", "time_shift_on_hit",
	]],
	# 史前惧兽（DLC2）：进化（正 = 机械、负 = 异变）与相关机制；最后是进化相关的规则开关（EVOLUTION_RULES）
	["BE_GRP_EVOLUTION", [
		"stat_evolution", "enemy_evolution_chance", "mutation_fruit_chance", "mutate_into_better_tier_chance",
		"meca_parts_on_level_up", "dismantle_price", "material_on_evolved_enemy_kill", "heal_on_mutant_kill",
		"meca_only", "mutant_only", "dual_evolution", "effect_mutate_end_of_wave",
	]],
	["BE_GRP_GAIN", [
		"gain_stat_max_hp", "gain_stat_hp_regeneration", "gain_stat_lifesteal", "gain_stat_percent_damage",
		"gain_stat_melee_damage", "gain_stat_ranged_damage", "gain_stat_elemental_damage", "gain_stat_attack_speed",
		"gain_stat_crit_chance", "gain_stat_engineering", "gain_stat_range", "gain_stat_armor", "gain_stat_dodge",
		"gain_stat_speed", "gain_stat_luck", "gain_stat_harvesting", "gain_stat_curse", "gain_explosion_damage",
		"gain_piercing_damage", "gain_bounce_damage", "gain_damage_against_bosses",
	]],
	["BE_GRP_SHOP", [
		"items_price", "weapons_price", "reroll_price", "free_rerolls", "gold_drops", "enemy_gold_drops",
		"neutral_gold_drops", "increase_material_value", "gain_pct_gold_start_wave", "recycling_gains", "crate_chance",
		"minimum_weapons_in_shop", "item_steals", "next_level_xp_needed", "item_box_recycling_gains",
		"extra_starting_weapon_choices",
	]],
	["BE_GRP_MAP", [
		"map_size", "number_of_enemies", "enemy_health", "enemy_damage", "enemy_speed", "boss_strength",
		"stronger_elites_on_kill", "loot_alien_chance", "extra_loot_aliens", "loot_alien_speed",
		"stronger_loot_aliens_on_kill", "enemy_fruit_drops", "trees", "trees_start_wave", "hp_start_wave",
		"hp_start_next_wave", "dig_sites",
	]],
	["BE_GRP_CAPS", ["hp_cap", "speed_cap", "dodge_cap", "crit_chance_cap"]],
	# 规则开关：填 1 开启
	["BE_GRP_RULES", [
		"no_melee_weapons", "no_ranged_weapons", "no_duplicate_weapons", "one_shot_trees", "double_boss",
		"structures_can_crit", "instant_gold_attracting", "hp_shop", "no_heal", "pacifist", "torture",
		"materials_as_health", "damage_taken_on_materials", "no_level_upgrades", "effect_no_weapon_in_shop",
		"effect_crate_give_weapon", "no_cure_between_wave", "no_fruit_attracted_end_of_wave", "fog_of_war_permanent",
		"effect_mixing_up_wave", "more_horde", "burning_stacks", "has_plastic_boots",
	]],
	# 特殊规则：规则类、但数值不是开关（稀有度 / 件数 / 设定值）
	["BE_GRP_SPECIAL_RULES", [
		"min_weapon_tier", "max_weapon_tier", "max_melee_weapons", "max_ranged_weapons", "can_attack_while_moving",
		"weapon_set_bonus",
	]],
]
# 规则（蓝图不可用）：规则 / 特殊规则分组的全部，以及进化分组里的规则开关
const EVOLUTION_RULES = ["meca_only", "mutant_only", "dual_evolution", "effect_mutate_end_of_wave"]

# 扳机（蓝图编辑器）：[custom_key, 名称 key]。"" = 永久属性（无扳机）。
# 只列出"属性 = key、数值 = value"的扳机；模板在原版效果里找不到的扳机不会出现在列表里。
const TRIGGERS = [
	["", "BE_TRIG_NONE"],
	["stats_on_level_up", "BE_TRIG_LEVEL_UP"],
	["stats_end_of_wave", "BE_TRIG_WAVE_END"],
	["stats_next_wave", "BE_TRIG_NEXT_WAVE"],
	["temp_stats_while_not_moving", "BE_TRIG_STILL"],
	["temp_stats_while_moving", "BE_TRIG_MOVING"],
	["temp_stats_while_being_in_puddle", "BE_TRIG_PUDDLE"],
	["stats_below_half_health", "BE_TRIG_LOW_HP"],
	["temp_stats_on_hit", "BE_TRIG_HIT"],
	["temp_stats_on_dodge", "BE_TRIG_DODGE"],
	["temp_stats_per_interval", "BE_TRIG_INTERVAL"],
	["decaying_stats_on_hit", "BE_TRIG_DECAY_HIT"],
	["decaying_stats_on_consumable", "BE_TRIG_DECAY_CONSUMABLE"],
	["consumable_stats_while_max", "BE_TRIG_CONSUMABLE_MAX"],
	["temp_consumable_stats_while_max", "BE_TRIG_TEMP_CONSUMABLE_MAX"],
	["stats_on_fruit", "BE_TRIG_FRUIT"],
	["gain_stats_on_reroll", "BE_TRIG_REROLL"],
	["gain_stat_for_every_step_after_equip", "BE_TRIG_STEPS"],
	["gain_stat_for_killed_enemies_while_burning", "BE_TRIG_BURNING_KILL"],
]

# 效果库分类：[id, 名称 key]
const CATEGORIES = [
	["all", "BE_CAT_ALL"],
	["stat", "BE_CAT_STAT"],
	["stat_mod", "BE_CAT_STAT_MOD"],
	["trigger", "BE_CAT_TRIGGER"],
	["scaling", "BE_CAT_SCALING"],
	["combat", "BE_CAT_COMBAT"],
	["economy", "BE_CAT_ECONOMY"],
	["weapon", "BE_CAT_WEAPON"],
	["structure", "BE_CAT_STRUCTURE"],
	["pet", "BE_CAT_PET"],
	["evolution", "BE_CAT_EVOLUTION"],
	["start", "BE_CAT_START"],
	["other", "BE_CAT_OTHER"],
]

const START_KEYS = ["starting_item", "starting_weapon", "cursed_starting_item", "cursed_starting_weapon"]
# 普通属性效果（"属性"分类）里 stat_ 以外的 key
const PLAIN_STAT_KEYS = [
	"xp_gain", "pickup_range", "knockback", "consumable_heal", "explosion_damage", "explosion_size", "piercing",
	"piercing_damage", "bounce", "bounce_damage", "projectiles", "damage_against_bosses", "burning_spread",
	"burning_cooldown_reduction", "accuracy", "structure_attack_speed", "structure_percent_damage", "structure_range",
]
# 分类关键词：按词（key / custom_key / text_key 以非字母切分）匹配，顺序 = 优先级。
# 有 custom_key 时不看 key（key 常是"属性"本身，例如"闪避时造成近战伤害"的 key 是近战伤害）
# ponytail: 词表覆盖原版；mod 的新机制按同样的词归类，匹配不到落到"其他"
const CATEGORY_WORDS = [
	["pet", ["pet", "mosquitor", "dinosaur", "ammosaurus"]],
	# 史前惧兽：进化（机械 / 异变）相关
	["evolution", ["evolution", "evolved", "meca", "mecha", "mutant", "mutation", "mutate", "mutated", "dismantle", "fossil"]],
	["structure", ["turret", "turrets", "structure", "structures", "landmine", "landmines", "builder", "garden", "bot", "tyler"]],
	["combat", ["dmg", "heal", "explode", "explosion", "projectile", "projectiles", "eyes"]],
	["weapon", ["weapon", "weapons", "melee", "ranged", "tier", "unarmed", "lock"]],
	["economy", ["gold", "material", "materials", "price", "reroll", "rerolls", "harvesting", "harvest", "crate", "shop", "loot", "alien", "aliens", "recycling", "box", "piggy"]],
	["combat", ["burn", "burning", "pierce", "piercing", "bounce", "crit", "knockback", "damage", "slow", "speed", "dodge", "hp", "enemy", "enemies", "boss", "bosses", "curse", "cursed", "hit", "death", "lifesteal", "armor", "regen", "charm"]],
]


static func stat_keys() -> Array:
	var out = []
	for g in STAT_GROUPS:
		out += g[1]
	return out


# 武器属性加成可选的属性：次要属性后加上等级（同原版短木棍）
static func scaling_keys() -> Array:
	var out = []
	for g in STAT_GROUPS:
		out += g[1]
		if g[0] == "BE_GRP_SECONDARY":
			out.push_back("stat_levels")
	return out


# 蓝图可用的属性：不含规则（开关 / 设定值型，如"无法使用近战武器"、最低武器等级）
static func graph_stat_keys() -> Array:
	var out = []
	for g in STAT_GROUPS:
		if not g[0] in ["BE_GRP_RULES", "BE_GRP_SPECIAL_RULES"]:
			for k in g[1]:
				if not k in EVOLUTION_RULES:
					out.push_back(k)
	return out


static func is_stat_key(key: String) -> bool:
	return key in stat_keys()


static func trigger_keys() -> Array:
	var out = []
	for t in TRIGGERS:
		out.push_back(t[0])
	return out


static func is_plain_effect(e) -> bool:
	return e.get_script() != null and e.get_script().resource_path == "res://items/global/effect.gd"


# 属性修改：属性获取 %（gain_stat_x / gain_x）、上限、升级属性修改、属性转换 / 互换
static func is_stat_mod_key(key: String) -> bool:
	return (key.begins_with("gain_") and key != "gain_pct_gold_start_wave" and not key.begins_with("gain_stat_for")) or key.ends_with("_cap") or key.find("stat_gains") >= 0 or key.find("modifications") >= 0


static func category_of(e) -> String:
	var key: String = str(e.key).to_lower()
	var ck: String = str(e.custom_key).to_lower()
	var tk: String = str(e.text_key).to_lower()
	var script_path = e.get_script().resource_path.to_lower() if e.get_script() != null else ""
	if ck in START_KEYS:
		return "start"
	if ck != "" and ck in trigger_keys():
		return "trigger"
	if tk.find("gain_stat_for") >= 0 or script_path.find("gain_stat_for_every") >= 0 or ck == "stat_links":
		return "scaling"
	if is_stat_mod_key(key) or is_stat_mod_key(tk.trim_prefix("effect_")) or ck.begins_with("convert_stats") or tk.find("swap") >= 0 or tk.find("candy_bag") >= 0:
		return "stat_mod"
	if ck == "" and e.storage_method == 0 and (key.begins_with("stat_") or key in PLAIN_STAT_KEYS):
		return "stat"
	var words = {}
	for part in [ck, tk, script_path.get_file().get_basename()] + ([] if ck != "" else [key]):
		for w in _split_words(part):
			words[w] = true
	if tk.begins_with("effect_pet") or key in PET_KEYS:
		return "pet"
	# 武器自带的效果（脚本在 effects/weapons/、text_key 带 _weapon）：名字里的 "weapon" 不代表武器类，
	# 先不看它分类（琉特琴的增伤、粒子加速器的减速、十字弓的暴击贯通都属于战斗）
	if script_path.find("/effects/weapons/") >= 0 or tk.ends_with("_weapon"):
		var plain = words.duplicate()
		plain.erase("weapon")
		plain.erase("weapons")
		var cat = _category_from(plain)
		if cat != "other":
			return cat
	return _category_from(words)


static func _category_from(words: Dictionary) -> String:
	for c in CATEGORY_WORDS:
		for w in c[1]:
			if words.has(w):
				return c[0]
	return "other"


static func _split_words(s: String) -> Array:
	var out = []
	var cur = ""
	for i in s.length():
		var ch = s[i]
		if ch >= "a" and ch <= "z":
			cur += ch
		elif cur != "":
			out.push_back(cur)
			cur = ""
	if cur != "":
		out.push_back(cur)
	return out


# 效果库：原版角色与道具上的全部效果，按 (脚本, text_key, custom_key, key) 去重。
# sources: [[来源 id, 来源名称 key, 效果数组]...]（效果数组须为原版未改动的版本）
# 返回 [{from, i, effect, src, cat}...]
# dedup：同脚本、同 text_key（不分大小写）/ custom_key / key 的效果只保留第一条；
# 属性联动的 key（获得哪个属性）可以直接修改：同脚本时 text_key 相同即合并，没有 text_key 时按 key 合并
static func build_library(sources: Array, dedup: bool = true) -> Array:
	var seen = {}
	var out = []
	for s in sources:
		var effects: Array = s[2]
		for i in effects.size():
			var e = effects[i]
			if e == null or not e is Resource or not "key" in e:
				continue
			var cat = category_of(e)
			# 纯属性效果（stat_xxx）同名只保留一个（数值可在效果里改），不受去重设置影响
			if is_plain_effect(e) and e.custom_key == "" and str(e.key).begins_with("stat_"):
				var sk = "stat:" + str(e.key)
				if seen.has(sk):
					continue
				seen[sk] = true
			if dedup:
				var script = e.get_script().resource_path if e.get_script() != null else ""
				var tk = str(e.text_key).to_lower()
				var sig = [script, tk, e.custom_key, e.key]
				if cat == "scaling":
					sig = [script, tk] if tk != "" else [script, "", e.key]
				var k = JSON.print(sig)
				if seen.has(k):
					continue
				seen[k] = true
			out.push_back({"from": s[0], "i": i, "effect": e, "src": s[1], "cat": cat})
	return out


# 可在编辑器里修改的效果字段：脚本导出的 int / float / bool / String（数组和子资源保持模板原样）
const HIDDEN_FIELDS = ["custom_key", "custom_args", "script", "resource_name", "resource_path", "resource_local_to_scene"]
# 可编辑的数组字段（字符串数组）
const ARRAY_FIELDS = ["stats_modified"]
# 放在最后的高级字段
const LATE_FIELDS = ["text_key", "effect_sign", "storage_method"]


# ---------------- 蓝图诅咒 ----------------
# 符号：参数增大对玩家是 +1 有利 / -1 不利 / 0 无关。默认 +1，这里只列 -1 与 0。
#   扳机：只有 interval 有参数（间隔秒数越大越少触发）
#   条件：every / cooldown / hp_above / wave_min / stat_min 的数值越大越难满足；chance / cap / hp_below / wave_max / stat_max 为默认 +1；
#         if_moving / if_still 无参数
#   效果：属性类（temp_stat / perm_stat / timed_stat 的 value）的符号 = 该属性在原版效果里的好坏方向 × 数值正负
#         （由 mod_main._good_dir 从原版效果读取，如价格为 -1、敌人数量为 0）；其余效果的数值都是默认 +1
const CURSE_SIGNS = {
	"interval": {"secs": -1},
	"every": {"n": -1},
	"cooldown": {"secs": -1},
	"hp_above": {"pct": -1},
	"wave_min": {"n": -1},
	"diff_min": {"n": -1},
	"stat_min": {"n": -1},
	"steps": {"n": -1},
}
# 诅咒默认改效果的数值；路径上有以下节点时改它的数值、效果不变（同原版"每击杀 X 个敌人"诅咒的是 X；
# 徒步旅行者"每走 X 步"诅咒的也是步数 value2，获得的数值不变）
const CURSE_TARGETS = {"every": "n", "steps": "n"}
# 效果节点里被诅咒的数值参数（grant 引用的效果按原版对该类效果的规则诅咒，次数不变）
const CURSE_EFFECT_PARAMS = {
	"temp_stat": ["value"], "perm_stat": ["value"], "timed_stat": ["value", "secs"],
	"heal_hp": ["value"], "add_gold": ["value"], "xp": ["value"], "damage": ["pct", "damage"], "explode": ["pct", "damage"],
	"hp_dmg": ["pct"], "ignite": ["value"], "slow": ["pct"], "rand_stats": ["value"], "fruit": ["value"],
	"vuln": ["pct", "secs"],
	"meca_parts": ["value"], "slow_time": ["pct", "secs"],
}
# 百分比参数的上限
const CURSE_MAX = {"chance": {"pct": 100}, "hp_below": {"pct": 100}, "slow_time": {"pct": 95}}


static func curse_sign(kind: String, param: String) -> int:
	return CURSE_SIGNS.get(kind, {}).get(param, 1)


# 归入宠物类的效果 key（不以 effect_pet 开头的）
const PET_KEYS = ["beast_master_effect"]
# 子资源里不提供编辑的字段（音效、治疗武器标记）
const SUB_HIDDEN = ["sound_db_mod", "is_healing"]


# 效果里可在详细信息里编辑的子资源字段：带脚本的 Resource（燃烧数据、武器属性等；场景、音效除外）。
# 子资源是效果时（撬棍生成的炮塔）列出它的子资源，字段名为 "效果字段.子资源字段"（只展开一层）
static func sub_fields(e, nested: bool = true) -> Array:
	var out = []
	for p in e.get_property_list():
		if not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not p.usage & PROPERTY_USAGE_STORAGE or p.type != TYPE_OBJECT:
			continue
		var r = e.get(p.name)
		if not r is Resource or r.get_script() == null:
			continue
		if "key_hash" in r:
			if nested:
				for f in sub_fields(r, false):
					out.push_back(p.name + "." + f)
		elif not sub_child_fields(r).empty() or "scaling_stats" in r:
			out.push_back(p.name)
	return out


# 按 sub_fields 的字段名取子资源
static func sub_get(e, field: String):
	for part in field.split("."):
		if e == null or not part in e:
			return null
		e = e.get(part)
	return e


# 子资源的标量字段
static func sub_child_fields(r) -> Array:
	var out = []
	for p in r.get_property_list():
		if not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not p.usage & PROPERTY_USAGE_STORAGE:
			continue
		if p.name in SUB_HIDDEN or p.name.begins_with("_") or p.name.ends_with("_hash"):
			continue
		if p.type in [TYPE_INT, TYPE_REAL, TYPE_BOOL]:
			out.push_back({"name": p.name, "type": p.type})
	return out


# 字段的编辑值：Vector2 取 x（等比缩放）
static func field_value(obj, name: String):
	var v = obj.get(name)
	return v.x if v is Vector2 else v


static func editable_fields(e) -> Array:
	var out = []
	for p in e.get_property_list():
		if not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not p.usage & PROPERTY_USAGE_STORAGE:
			continue
		if p.name in HIDDEN_FIELDS or p.name.begins_with("_") or p.name.ends_with("_hash"):
			continue
		if p.type in [TYPE_INT, TYPE_REAL, TYPE_BOOL, TYPE_STRING] or (p.type == TYPE_ARRAY and p.name in ARRAY_FIELDS):
			out.push_back({"name": p.name, "type": p.type})
		elif p.type == TYPE_VECTOR2:
			# 二维缩放（火焰池大小等）按等比的一个数编辑
			out.push_back({"name": p.name, "type": TYPE_REAL})
	# key / value 放最前，文本 / 好坏 / 计算方式放最后
	out.sort_custom(FieldSorter, "by_field")
	return out


class FieldSorter:
	static func by_field(a, b) -> bool:
		var order = ["key", "value"]
		var ia = order.find(a.name)
		var ib = order.find(b.name)
		if ia < 0:
			ia = 99 if not a.name in LATE_FIELDS else 100 + LATE_FIELDS.find(a.name)
		if ib < 0:
			ib = 99 if not b.name in LATE_FIELDS else 100 + LATE_FIELDS.find(b.name)
		if ia != ib:
			return ia < ib
		return a.name < b.name


# ============================================================
# 蓝图节点（扳机 → 条件 → 效果，用路径连接；参考 AutoAnthony 的扳机 / 载荷拆分，不做合法性检查）
#   [id, 类型, 参数[[名称, 类型, 默认值]...]]；参数类型：int / stat / dmg（伤害类型）/ mode:<a>|<b> / effect（效果库引用）
#   部分扳机非原版（同 AutoAnthony）：命中敌人 / 首次命中 / 点燃由敌人身上的效果行为（graph/enemy_behavior.gd）转发，
#   引发爆炸由 WeaponService.explode 的扩展转发
#   名称 key = BE_N_<ID>；路径文本见 graph_effect.gd（扳机句式 BE_TX_*、效果句式 BE_PX_*、条件后缀 BE_CX_*）
#   状态扳机（still / moving / low_hp / full_hp / always）：按路径轮询，扳机状态与路径上的状态条件（STATE_CONDS）都满足时进入并执行，
#   任一不满足时撤销"本波属性"与"本波获得"
#   transform（道具变为）：只对道具上的蓝图有效；gain_item / lose_item（获得 / 失去道具）同样等到敌袭结束再执行
#   shop_add / shop_remove：本局商店（及箱子）中可以出现 / 不再出现某些道具（可解除"禁用"），随一局存档保存
#   charm：魅惑目标敌人（同浪漫之人）；spawn：生成敌人；break：持有者是武器时损坏（同砖块）
#   var_set / var_cmp：整数变量（按名称在玩家的全部蓝图间共享，初始为 0，整局保留、随存档保存；不受诅咒）
#   效果节点之后可以继续连接；一个节点的多条出线按目标节点在画布上的纵坐标从上到下执行
#   史前惧兽（DLC2）：evolved_kill / meca_kill / mutant_kill（杀死进化敌人）、mutated（自己的道具异变后，波次结束时）、
#   meca_upgrade（机械化武器后，商店 / 升级界面）；evo_camp（自己的进化方向）、target_evolved（目标是进化敌人）；
#   meca_parts（机械部件）、mutate（本波结束时多异变 n 次）、slow_time（敌人与敌方投射物减速，同怀表 / 时间扭曲者）
# ============================================================
const NODES = [
	["wave_start", "trigger", []],
	["wave_end", "trigger", []],
	["half_wave", "trigger", []],
	["interval", "trigger", [["secs", "int", 5]]],
	["level_up", "trigger", []],
	["kill", "trigger", []],
	["crit", "trigger", []],
	["crit_kill", "trigger", []],
	["enemy_hit", "trigger", []],
	["first_hit", "trigger", []],
	["on_ignite", "trigger", []],
	["on_explode", "trigger", []],
	["burning_kill", "trigger", []],
	["cursed_kill", "trigger", []],
	["evolved_kill", "trigger", []],
	["meca_kill", "trigger", []],
	["mutant_kill", "trigger", []],
	["tree_kill", "trigger", []],
	["hit", "trigger", []],
	["dodge", "trigger", []],
	["heal", "trigger", []],
	["gold", "trigger", []],
	["consumable", "trigger", []],
	["crate", "trigger", []],
	["steps", "trigger", [["n", "int", 1]]],
	["reroll", "trigger", []],
	["buy", "trigger", []],
	["mutated", "trigger", []],
	["meca_upgrade", "trigger", []],
	["still", "trigger", []],
	["moving", "trigger", []],
	["low_hp", "trigger", [["pct", "int", 50]]],
	["full_hp", "trigger", []],
	["in_puddle", "trigger", []],
	["always", "trigger", []],
	["tick", "trigger", []],
	["chance", "cond", [["pct", "int", 25]]],
	["stat_chance", "cond", [["base", "int", 0], ["stat", "stat", "stat_max_hp"], ["pct", "int", 50]]],
	["every", "cond", [["n", "int", 5]]],
	["cap", "cond", [["n", "int", 3]]],
	["cooldown", "cond", [["secs", "int", 3]]],
	["hp_below", "cond", [["pct", "int", 50]]],
	["hp_above", "cond", [["pct", "int", 50]]],
	["wave_min", "cond", [["n", "int", 5]]],
	["wave_max", "cond", [["n", "int", 10]]],
	["diff_min", "cond", [["n", "int", 3]]],
	["diff_max", "cond", [["n", "int", 2]]],
	["stat_min", "cond", [["stat", "stat", "stat_armor"], ["n", "int", 10]]],
	["stat_max", "cond", [["stat", "stat", "stat_armor"], ["n", "int", 10]]],
	["if_moving", "cond", []],
	["if_still", "cond", []],
	["enemy_hp_above", "cond", [["pct", "int", 50]]],
	["enemy_hp_below", "cond", [["pct", "int", 50]]],
	["dmg_type", "cond", [["stat", "stat", "stat_melee_damage"]]],
	["target_evolved", "cond", [["camp", "mode:any|meca|mutant", "any"]]],
	["evo_camp", "cond", [["camp", "mode:meca|mutant", "meca"]]],
	["once", "cond", []],
	["own_tag", "cond", [["tag", "tag", ""], ["cmp", "mode:at_least|at_most|exactly", "at_least"], ["n", "int", 2]]],
	["own_item", "cond", [["id", "owned", ""], ["cmp", "mode:at_least|at_most|exactly", "at_least"], ["n", "int", 1]]],
	["own_set", "cond", [["set", "set", ""], ["cmp", "mode:at_least|at_most|exactly", "at_least"], ["n", "int", 2]]],
	["weapon_kinds", "cond", [["cmp", "mode:at_least|at_most|exactly", "at_least"], ["n", "int", 3]]],
	["var_cmp", "cond", [["var", "var", "x"], ["cmp", "mode:at_least|at_most|exactly", "at_least"], ["n", "int", 2]]],
	["temp_stat", "effect", [["stat", "stat", "stat_percent_damage"], ["value", "int", 5]]],
	["perm_stat", "effect", [["stat", "stat", "stat_max_hp"], ["value", "int", 1]]],
	["timed_stat", "effect", [["stat", "stat", "stat_attack_speed"], ["value", "int", 20], ["secs", "int", 3]]],
	["heal_hp", "effect", [["value", "int", 3]]],
	["add_gold", "effect", [["value", "int", 1]]],
	["xp", "effect", [["value", "int", 5]]],
	["damage", "effect", [["stat", "stat", "stat_ranged_damage"], ["pct", "int", 100]]],
	["explode", "effect", [["stat", "stat", "stat_elemental_damage"], ["pct", "int", 100]]],
	["hp_dmg", "effect", [["pct", "int", 5]]],
	["ignite", "effect", [["value", "int", 5], ["secs", "int", 3], ["spread", "int", 0], ["stat", "stat", "stat_elemental_damage"], ["pct", "int", 100]]],
	["slow", "effect", [["pct", "int", 10], ["secs", "int", 0]]],
	["vuln", "effect", [["pct", "int", 10], ["secs", "int", 3]]],
	["rand_stats", "effect", [["value", "int", 1]]],
	["fruit", "effect", [["value", "int", 1]]],
	["transform", "effect", [["items", "items", []]]],
	["gain_item", "effect", [["items", "items", []]]],
	["lose_item", "effect", [["items", "items", []]]],
	["shop_add", "effect", [["items", "items", []]]],
	["shop_remove", "effect", [["items", "items", []]]],
	["charm", "effect", [["secs", "int", 8]]],
	["spawn", "effect", [["enemy", "enemy", "baby_alien"], ["n", "int", 1]]],
	["break", "effect", [["value", "int", 10]]],
	["grant", "effect", [["ref", "effect", null], ["n", "int", 1], ["mode", "mode:temp|timed|perm", "temp"], ["secs", "int", 5]]],
	["shop_force", "effect", [["items", "goods", []]]],
	["group_unlock", "effect", [["group", "group", ""]]],
	["group_lock", "effect", [["group", "group", ""]]],
	["var_set", "effect", [["var", "var", "x"], ["op", "mode:add|sub|set|mul|div", "add"], ["value", "int", 1]]],
	["meca_parts", "effect", [["value", "int", 1]]],
	["mutate", "effect", [["n", "int", 1]]],
	["slow_time", "effect", [["pct", "int", 50], ["secs", "int", 3]]],
]
# 节点的详细信息（弹窗编辑，存在节点 params 里；没有时用默认值）：[参数, 类型, 默认值]。
# 这些节点还可以添加额外的属性加成（params.scaling_stats：[[属性, 系数]...]）。
# 爆炸的默认值同运行时使用的原版爆炸（撕裂者）：缩放 0.65、暴击倍率 1.5
const NODE_DETAILS = {
	"explode": [["damage", TYPE_INT, 0], ["scale", TYPE_REAL, 0.65], ["crit_chance", TYPE_INT, 0], ["crit_damage", TYPE_REAL, 1.5], ["accuracy", TYPE_INT, 100]],
	"damage": [["damage", TYPE_INT, 0]],
	"ignite": [],
}
# 只在某个参数取某值时显示的参数：[节点, 参数] -> [条件参数, 值]
const PARAM_SHOW_IF = {"grant:secs": ["mode", "timed"]}
const STATE_TRIGGERS = ["still", "moving", "low_hp", "full_hp", "in_puddle", "always"]
# 状态条件：在状态扳机的路径上持续检查（全部满足时进入，任一不满足时撤销）；其余条件只在进入时检查一次
const STATE_CONDS = ["hp_below", "hp_above", "wave_min", "wave_max", "diff_min", "diff_max", "stat_min", "stat_max", "if_moving", "if_still", "own_tag", "own_set", "own_item", "weapon_kinds", "var_cmp", "evo_camp"]
# 不在敌袭中触发的扳机（商店、波次结束后的异变、升级界面的机械化）
const SHOP_TRIGGERS = ["reroll", "buy", "mutated", "meca_upgrade"]

# 不是普通 Effect 脚本、但也可以拆解的扳机（徒步旅行者的步数在 value2；浪漫之人 / 长笛的魅惑由 split_native 单独处理）
const SPLIT_ANY_SCRIPT = ["gain_stat_for_every_step_after_equip", "charm_on_hit"]


# 由 graph_effect._special_chain 拆解的原版效果（狩猎奖杯、肾上腺素、反击、巫妖、赛博球、小象、医疗箱……）
const SPLIT_SPECIAL = ["charm_on_hit", "gold_on_crit_kill", "heal_on_dodge", "dmg_on_dodge", "dmg_when_heal", "dmg_when_death", "dmg_when_pickup_gold", "temp_stats_per_interval", "enemy_percent_damage_taken"]
# 同上，按 key 识别（没有 custom_key 的史前惧兽效果：病毒、干扰背包、怀表）
const SPLIT_SPECIAL_KEYS = ["charm_evolved_on_hit", "slow_meca_on_hit", "slow_time_when_below_hp"]


static func can_split(e) -> bool:
	if e == null or not "custom_key" in e:
		return false
	if e.custom_key == "" and e.key in SPLIT_SPECIAL_KEYS:
		return true
	if e.custom_key in SPLIT_SPECIAL:
		# 造成伤害的效果需要缩放属性；受击后重置的间隔效果不拆
		if e.custom_key.begins_with("dmg_") and e.key == "":
			return false
		# 同 custom_key 的炮塔命中效果（血腥炮塔）没有几率与持续时间
		if e.custom_key == "enemy_percent_damage_taken" and not ("chance" in e and "duration_secs" in e):
			return false
		return not ("reset_on_hit" in e and e.reset_on_hit)
	return NATIVE_SPLIT.has(e.custom_key) and (is_plain_effect(e) or e.custom_key in SPLIT_ANY_SCRIPT)


# 原版触发型效果（Effect{key = 属性, value, custom_key = 扳机}）-> 蓝图 [扳机, [条件...], 效果]（"拆解"按钮用）
const NATIVE_SPLIT = {
		"stats_on_level_up": ["level_up", [], "perm_stat"],
	"gain_stat_for_every_step_after_equip": ["steps", [], "perm_stat"],
	"temp_stats_on_hit": ["hit", [], "temp_stat"],
	"temp_stats_on_dodge": ["dodge", [], "temp_stat"],
	"stats_end_of_wave": ["wave_end", [], "perm_stat"],
	"stats_next_wave": ["wave_start", [["once", {}]], "temp_stat"],
	"temp_stats_while_not_moving": ["still", [], "temp_stat"],
	"temp_stats_while_moving": ["moving", [], "temp_stat"],
	"temp_stats_while_being_in_puddle": ["in_puddle", [], "temp_stat"],
	"stats_below_half_health": ["low_hp", [], "temp_stat"],
	"gain_stats_on_reroll": ["reroll", [], "perm_stat"],
	"stats_on_fruit": ["consumable", [], "perm_stat"],
	"consumable_stats_while_max": ["consumable", [["hp_above", {"pct": 100}]], "perm_stat"],
	"temp_consumable_stats_while_max": ["consumable", [["hp_above", {"pct": 100}]], "temp_stat"],
	"decaying_stats_on_hit": ["hit", [], "timed_stat"],
	"decaying_stats_on_consumable": ["consumable", [], "timed_stat"],
}


static func node_def(kind: String):
	for d in NODES:
		if d[0] == kind:
			return d
	return null


static func node_type(kind: String) -> String:
	var d = node_def(kind)
	return d[1] if d != null else ""


# 新节点的默认参数
static func default_params(kind: String) -> Dictionary:
	var out = {}
	var d = node_def(kind)
	if d != null:
		for p in d[2]:
			out[p[0]] = p[2].duplicate() if p[2] is Array else p[2]
	return out


# 属性图标（同 cave-modtools）：没有原版属性图标的 key 借用相近属性的图标，或使用道具图标
const STAT_ICON_ALIASES = {
	"accuracy": "stat_ranged_damage", "bounce": "stat_ranged_damage", "bounce_damage": "stat_ranged_damage",
	"burning_cooldown_increase": "stat_elemental_damage", "burning_cooldown_reduction": "stat_elemental_damage",
	"burning_spread": "stat_elemental_damage", "chance_double_gold": "stat_luck", "consumable_heal": "stat_max_hp",
	"crit_chance_cap": "stat_crit_chance", "damage_against_bosses": "stat_percent_damage", "dodge_cap": "stat_dodge",
	"enemy_damage": "stat_percent_damage", "enemy_health": "stat_max_hp", "enemy_speed": "stat_speed",
	"explosion_size": "explosion_damage", "free_rerolls": "stat_materials", "gold_drops": "stat_materials",
	"harvesting_growth": "stat_harvesting", "heal_when_pickup_gold": "stat_luck", "hit_protection": "stat_armor",
	"hp_cap": "stat_max_hp", "item_box_gold": "stat_materials", "items_price": "stat_materials",
	"knockback": "stat_melee_damage", "lose_hp_per_second": "stat_max_hp", "map_size": "stat_range",
	"number_of_enemies": "stat_luck", "pickup_range": "stat_range", "piercing": "stat_ranged_damage",
	"piercing_damage": "stat_ranged_damage", "reroll_price": "stat_materials", "speed_cap": "stat_speed",
	"structure_attack_speed": "stat_attack_speed", "structure_percent_damage": "stat_engineering",
	"structure_range": "stat_engineering", "trees": "stat_luck", "weapon_slot": "stat_levels",
	"weapons_price": "stat_materials", "enemy_gold_drops": "stat_materials", "neutral_gold_drops": "stat_materials",
	"crate_chance": "stat_luck", "recycling_gains": "stat_materials", "increase_material_value": "stat_materials",
	"next_level_xp_needed": "xp_gain", "hp_start_wave": "stat_max_hp", "hp_start_next_wave": "stat_max_hp",
	"boss_strength": "stat_percent_damage", "gain_pct_gold_start_wave": "stat_materials", "enemy_fruit_drops": "stat_max_hp",
}
# 属性图标：key -> 候选（取第一个找得到的）：原版角色 / 道具 / 武器的 id（用它的图标，1.2 起路径不再固定）或贴图路径。
# 大部分取自 Yoko-Optimize 的次要属性图标（对应回原版贴图），其余按道具效果选择
const STAT_ICON_PATHS = {
	"xp_gain": ["item_celery_tea"],
	"next_level_xp_needed": ["item_celery_tea"],
	"pickup_range": ["item_alien_tongue"],
	"knockback": ["item_boxing_glove"],
	"consumable_heal": ["res://items/consumables/fruit/fruit.png"],
	"enemy_fruit_drops": ["res://items/consumables/fruit/fruit.png"],
	"heal_when_pickup_gold": ["item_cute_monkey"],
	"explosion_damage": ["item_dynamite"],
	"explosion_size": ["item_explosive_shells"],
	"piercing": ["item_sharp_bullet"],
	"piercing_damage": ["item_sharp_bullet"],
	"bounce": ["item_ricochet"],
	"bounce_damage": ["item_ricochet"],
	"projectiles": ["item_seashell", "weapon_double_barrel_shotgun_1"],
	"damage_against_bosses": ["item_silver_bullet"],
	"burning_spread": ["item_snake"],
	"burning_cooldown_reduction": ["item_campfire"],
	"burning_cooldown_increase": ["item_frozen_heart"],
	"structure_attack_speed": ["item_improved_tools"],
	"structure_percent_damage": ["character_builder"],
	"structure_range": ["item_rusty_antenna", "character_builder"],
	"accuracy": ["item_eyepatch"],
	"weapon_slot": ["weapon_pistol_1"],
	"minimum_weapons_in_shop": ["weapon_pistol_1"],
	"chance_double_gold": ["res://items/materials/material_bag_icon.png"],
	"item_box_gold": ["item_bag"],
	"hit_protection": ["item_tardigrade"],
	"lose_hp_per_second": ["item_blood_donation"],
	"items_price": ["item_coupon"],
	"reroll_price": ["item_spyglass"],
	"free_rerolls": ["item_dangerous_bunny"],
	"gold_drops": ["item_evil_hat"],
	"enemy_gold_drops": ["item_evil_hat"],
	"neutral_gold_drops": ["item_evil_hat"],
	"increase_material_value": ["item_crown"],
	"gain_pct_gold_start_wave": ["item_piggy_bank"],
	"recycling_gains": ["item_recycling_machine"],
	"crate_chance": ["res://items/consumables/item_box/item_box.png"],
	"item_steals": ["character_gangster"],
	"map_size": ["item_treasure_map"],
	"number_of_enemies": ["item_gentle_alien"],
	"enemy_health": ["item_alien_baby"],
	"enemy_damage": ["item_tentacle"],
	"enemy_speed": ["item_snail"],
	"boss_strength": ["res://ui/icons/misc/elite_icon.png"],
	"stronger_elites_on_kill": ["res://ui/icons/misc/elite_icon.png"],
	"loot_alien_chance": ["res://entities/units/enemies/crash_zone/basic/looter/looter_icon.png"],
	"extra_loot_aliens": ["res://entities/units/enemies/crash_zone/basic/looter/looter_icon.png"],
	"loot_alien_speed": ["res://entities/units/enemies/crash_zone/basic/looter/looter_icon.png"],
	"stronger_loot_aliens_on_kill": ["res://entities/units/enemies/crash_zone/basic/looter/looter_icon.png"],
	"trees": ["item_tree"],
	"trees_start_wave": ["item_tree"],
	"hp_start_wave": ["item_sad_tomato"],
	"hp_start_next_wave": ["item_weird_ghost"],
	"bonus_crit_damage": ["item_raptor_eye"],
	"dismantle_price": ["item_titanium_excess"],
	"item_box_recycling_gains": ["character_archaeologist", "item_dig_site"],
	"dig_sites": ["item_dig_site"],
	"mutation_fruit_chance": ["item_boosted_mitosis"],
	"enemy_evolution_chance": ["item_shaving_foam_can_meca"],
	"mutate_into_better_tier_chance": ["item_wildfire_mutation"],
	"meca_parts_on_level_up": ["character_droid"],
	"material_on_evolved_enemy_kill": ["item_flare"],
	"heal_on_mutant_kill": ["item_eldritch_figurine"],
	"extra_starting_weapon_choices": ["character_survivor"],
	"weapon_set_bonus": ["character_one_arm"],
	"burning_stacks": ["item_pyromaniac"],
	"has_plastic_boots": ["item_plastic_boots"],
	"more_horde": ["character_veteran"],
	"meca_only": ["character_droid"],
	"mutant_only": ["character_variant"],
	"dual_evolution": ["character_mad_scientist"],
	"materials_as_health": ["character_droid"],
	"damage_taken_on_materials": ["item_failsafe_core"],
	"no_level_upgrades": ["character_droid"],
	"effect_no_weapon_in_shop": ["character_survivor"],
	"effect_crate_give_weapon": ["character_survivor"],
	"effect_mutate_end_of_wave": ["character_variant"],
	"effect_mixing_up_wave": ["character_time_shifter"],
	"fog_of_war_permanent": ["character_caveman"],
	"no_cure_between_wave": ["character_veteran"],
	"no_fruit_attracted_end_of_wave": ["character_veteran"],
	# 其余次要属性与规则：带有它的原版角色 / 道具 / 武器
	"harvesting_growth": ["character_farmer", "item_crown"],
	"fire_puddle_size": ["weapon_molotov_1"],
	"time_shift_on_hit": ["character_time_shifter"],
	"weapons_price": ["character_arms_dealer"],
	"no_melee_weapons": ["character_ranger"],
	"no_ranged_weapons": ["character_gladiator"],
	"no_duplicate_weapons": ["character_vagabond"],
	"one_shot_trees": ["item_lumberjack_shirt"],
	"double_boss": ["res://ui/icons/misc/elite_icon.png"],
	"structures_can_crit": ["item_pile_of_books"],
	"instant_gold_attracting": ["item_baby_gecko"],
	"hp_shop": ["character_demon"],
	"no_heal": ["character_golem"],
	"pacifist": ["character_pacifist"],
	"torture": ["item_torture"],
	"min_weapon_tier": ["character_knight"],
	"max_weapon_tier": ["character_wildling"],
	"max_melee_weapons": ["character_generalist"],
	"max_ranged_weapons": ["character_generalist"],
	"can_attack_while_moving": ["character_soldier"],
}


# ============================================================
# 武器攻击间隔（移植自 AutoAnthony weapon_value.cooldown_seconds，即 codex 攻速计算器：
# 攻速 0、6 把武器；含后坐 / 近战出招收招的补间帧、随机冷却抖动、换弹折算到每发）
# ============================================================
const _FPS = 60.0
const _MIN_CD_FRAMES = 2
const _MELEE_ATTACK_DURATION = 0.2
const _WEAPON_COUNT = 6


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


# 平均每次攻击的间隔（秒）
static func attack_interval(st) -> float:
	var wcf = max(_MIN_CD_FRAMES, int(st.cooldown))
	var recoil = float(st.recoil_duration)
	var add_cd = 0.0
	var alt_bonus = 0.0
	if "attack_type" in st:
		var eff_range = max(25.0, float(st.max_range))
		var attack_dur = _MELEE_ATTACK_DURATION + max(0.0, eff_range / 70.0) * 0.15
		add_cd = _tween(recoil) + _tween(_MELEE_ATTACK_DURATION) - 1
		var half = _tween(attack_dur / 2.0)
		var quarter = _tween(attack_dur / 4.0)
		add_cd += half if int(st.attack_type) == 0 else 2 * quarter
		if st.alternate_attack_type and half > 2 * quarter:
			alt_bonus = 1.0
	else:
		add_cd = 2 * _tween(recoil) - 1
	var max_rand = min(_WEAPON_COUNT * wcf / 5.0, _WEAPON_COUNT * 5.0)
	var avg = add_cd + _avg_attack(max(1.0, wcf - max_rand), wcf + max_rand) - alt_bonus
	var cd = avg / _FPS
	var shots = int(st.additional_cooldown_every_x_shots)
	var mult = float(st.additional_cooldown_multiplier)
	if shots > 0 and mult > 0:
		var actual = (add_cd + wcf * mult) / _FPS
		cd += (actual - cd) / shots
	return cd
