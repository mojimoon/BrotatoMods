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
		"minimum_weapons_in_shop", "item_steals", "next_level_xp_needed",
	]],
	["BE_GRP_MAP", [
		"map_size", "number_of_enemies", "enemy_health", "enemy_damage", "enemy_speed", "boss_strength",
		"stronger_elites_on_kill", "loot_alien_chance", "extra_loot_aliens", "loot_alien_speed",
		"stronger_loot_aliens_on_kill", "enemy_fruit_drops", "trees", "trees_start_wave", "hp_start_wave",
		"hp_start_next_wave",
	]],
	["BE_GRP_CAPS", ["hp_cap", "speed_cap", "dodge_cap", "crit_chance_cap"]],
	["BE_GRP_RULES", [
		"no_melee_weapons", "no_ranged_weapons", "no_duplicate_weapons", "min_weapon_tier", "max_weapon_tier",
		"max_melee_weapons", "max_ranged_weapons", "can_attack_while_moving", "one_shot_trees", "double_boss",
		"structures_can_crit", "instant_gold_attracting", "hp_shop", "no_heal", "pacifist", "torture",
	]],
]

# 扳机（蓝图编辑器）：[custom_key, 名称 key]。"" = 永久属性（无扳机）。
# 只列出"属性 = key、数值 = value"的扳机；模板在原版效果里找不到的扳机不会出现在列表里。
const TRIGGERS = [
	["", "BE_TRIG_NONE"],
	["stats_on_level_up", "BE_TRIG_LEVEL_UP"],
	["stats_end_of_wave", "BE_TRIG_WAVE_END"],
	["stats_next_wave", "BE_TRIG_NEXT_WAVE"],
	["temp_stats_while_not_moving", "BE_TRIG_STILL"],
	["temp_stats_while_moving", "BE_TRIG_MOVING"],
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
	["pet", ["pet"]],
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
	if tk.begins_with("effect_pet"):
		return "pet"
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
static func build_library(sources: Array) -> Array:
	var seen = {}
	var out = []
	for s in sources:
		var effects: Array = s[2]
		for i in effects.size():
			var e = effects[i]
			if e == null or not e is Resource or not "key" in e:
				continue
			var sig = [e.get_script().resource_path if e.get_script() != null else "", e.text_key, e.custom_key, e.key]
			var k = JSON.print(sig)
			if seen.has(k):
				continue
			seen[k] = true
			out.push_back({"from": s[0], "i": i, "effect": e, "src": s[1], "cat": category_of(e)})
	return out


# 可在编辑器里修改的效果字段：脚本导出的 int / float / bool / String（数组和子资源保持模板原样）
const HIDDEN_FIELDS = ["text_key", "custom_key", "storage_method", "effect_sign", "custom_args", "script", "resource_name", "resource_path", "resource_local_to_scene"]


static func editable_fields(e) -> Array:
	var out = []
	for p in e.get_property_list():
		if not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not p.usage & PROPERTY_USAGE_STORAGE:
			continue
		if p.name in HIDDEN_FIELDS or p.name.begins_with("_") or p.name.ends_with("_hash"):
			continue
		if p.type in [TYPE_INT, TYPE_REAL, TYPE_BOOL, TYPE_STRING]:
			out.push_back({"name": p.name, "type": p.type})
	# key / value 放最前
	out.sort_custom(FieldSorter, "by_field")
	return out


class FieldSorter:
	static func by_field(a, b) -> bool:
		var order = ["key", "value"]
		var ia = order.find(a.name)
		var ib = order.find(b.name)
		if ia < 0:
			ia = 99
		if ib < 0:
			ib = 99
		if ia != ib:
			return ia < ib
		return a.name < b.name


# ============================================================
# 蓝图节点（扳机 → 条件 → 效果，用路径连接；参考 AutoAnthony 的扳机 / 载荷拆分，不做合法性检查）
#   [id, 类型, 参数[[名称, 类型, 默认值]...]]；参数类型：int / stat / mode:<a>|<b> / effect（效果库引用）
#   名称 key = BE_N_<ID>；路径文本见 graph_effect.gd（扳机句式 BE_TX_*、效果句式 BE_PX_*、条件后缀 BE_CX_*）
#   状态扳机（still / moving / low_hp / full_hp）：进入状态时执行，离开时撤销"本波属性"与"本波获得"
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
	["burning_kill", "trigger", []],
	["cursed_kill", "trigger", []],
	["tree_kill", "trigger", []],
	["hit", "trigger", []],
	["dodge", "trigger", []],
	["heal", "trigger", []],
	["gold", "trigger", []],
	["consumable", "trigger", []],
	["crate", "trigger", []],
	["steps", "trigger", []],
	["reroll", "trigger", []],
	["buy", "trigger", []],
	["still", "trigger", []],
	["moving", "trigger", []],
	["low_hp", "trigger", []],
	["full_hp", "trigger", []],
	["chance", "cond", [["pct", "int", 25]]],
	["every", "cond", [["n", "int", 5]]],
	["cap", "cond", [["n", "int", 3]]],
	["cooldown", "cond", [["secs", "int", 3]]],
	["hp_below", "cond", [["pct", "int", 50]]],
	["hp_above", "cond", [["pct", "int", 50]]],
	["wave_min", "cond", [["n", "int", 5]]],
	["wave_max", "cond", [["n", "int", 10]]],
	["stat_min", "cond", [["stat", "stat", "stat_armor"], ["n", "int", 10]]],
	["stat_max", "cond", [["stat", "stat", "stat_armor"], ["n", "int", 10]]],
	["if_moving", "cond", []],
	["if_still", "cond", []],
	["temp_stat", "effect", [["stat", "stat", "stat_percent_damage"], ["value", "int", 5]]],
	["perm_stat", "effect", [["stat", "stat", "stat_max_hp"], ["value", "int", 1]]],
	["timed_stat", "effect", [["stat", "stat", "stat_attack_speed"], ["value", "int", 20], ["secs", "int", 3]]],
	["heal_hp", "effect", [["value", "int", 3]]],
	["add_gold", "effect", [["value", "int", 1]]],
	["xp", "effect", [["value", "int", 5]]],
	["damage", "effect", [["stat", "stat", "stat_ranged_damage"], ["pct", "int", 100]]],
	["explode", "effect", [["stat", "stat", "stat_elemental_damage"], ["pct", "int", 100]]],
	["hp_dmg", "effect", [["pct", "int", 5]]],
	["ignite", "effect", [["value", "int", 5]]],
	["slow", "effect", [["pct", "int", 10]]],
	["rand_stats", "effect", [["value", "int", 1]]],
	["fruit", "effect", [["value", "int", 1]]],
	["grant", "effect", [["ref", "effect", null], ["n", "int", 1], ["mode", "mode:temp|perm", "temp"]]],
]
const STATE_TRIGGERS = ["still", "moving", "low_hp", "full_hp"]
const SHOP_TRIGGERS = ["reroll", "buy"]

# 原版触发型效果（Effect{key = 属性, value, custom_key = 扳机}）-> 蓝图 [扳机, [条件...], 效果]（"拆解"按钮用）
const NATIVE_SPLIT = {
	"stats_on_level_up": ["level_up", [], "perm_stat"],
	"temp_stats_on_hit": ["hit", [], "temp_stat"],
	"temp_stats_on_dodge": ["dodge", [], "temp_stat"],
	"stats_end_of_wave": ["wave_end", [], "perm_stat"],
	"stats_next_wave": ["wave_start", [], "temp_stat"],
	"temp_stats_while_not_moving": ["still", [], "temp_stat"],
	"temp_stats_while_moving": ["moving", [], "temp_stat"],
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
			out[p[0]] = p[2]
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
# 属性图标：key -> 候选贴图（取第一个存在的；DLC 贴图在未安装 DLC 时跳过）。
# 大部分取自 Yoko-Optimize 的次要属性图标（对应回原版贴图），其余按道具效果选择
const ITEM_ICON = "res://items/all/%s/%s_icon.png"
const STAT_ICON_PATHS = {
	"xp_gain": ["res://items/all/celery_tea/celery_tea_icon.png"],
	"next_level_xp_needed": ["res://items/all/celery_tea/celery_tea_icon.png"],
	"pickup_range": ["res://items/all/alien_tongue/alien_tongue_icon.png"],
	"knockback": ["res://items/all/boxing_glove/boxing_glove_icon.png"],
	"consumable_heal": ["res://items/consumables/fruit/fruit.png"],
	"enemy_fruit_drops": ["res://items/consumables/fruit/fruit.png"],
	"heal_when_pickup_gold": ["res://items/all/cute_monkey/cute_monkey_icon.png"],
	"explosion_damage": ["res://items/all/dynamite/dynamite_icon.png"],
	"explosion_size": ["res://items/all/explosive_shells/explosive_shells_icon.png"],
	"piercing": ["res://items/all/sharp_bullet/sharp_bullet_icon.png"],
	"piercing_damage": ["res://items/all/sharp_bullet/sharp_bullet_icon.png"],
	"bounce": ["res://items/all/ricochet/ricochet_icon.png"],
	"bounce_damage": ["res://items/all/ricochet/ricochet_icon.png"],
	"projectiles": ["res://dlcs/dlc_1/items/seashell/seashell_icon.png", "res://weapons/ranged/double_barrel_shotgun/double_barrel_shotgun_icon.png"],
	"damage_against_bosses": ["res://items/all/silver_bullet/silver_bullet_icon.png"],
	"burning_spread": ["res://items/all/snake/snake_icon.png"],
	"burning_cooldown_reduction": ["res://items/all/campfire/campfire_icon.png"],
	"burning_cooldown_increase": ["res://items/all/frozen_heart/frozen_heart_icon.png"],
	"structure_attack_speed": ["res://items/all/improved_tools/improved_tools_icon.png"],
	"structure_percent_damage": ["res://items/all/heavy_bullets/heavy_bullets_icon.png"],
	"structure_range": ["res://weapons/melee/wrench/wrench_icon.png"],
	"accuracy": ["res://dlcs/dlc_1/items/eyepatch/eyepatch_icon.png"],
	"weapon_slot": ["res://weapons/ranged/pistol/pistol_icon.png"],
	"minimum_weapons_in_shop": ["res://weapons/ranged/pistol/pistol_icon.png"],
	"chance_double_gold": ["res://items/materials/material_bag_icon.png"],
	"item_box_gold": ["res://items/all/bag/bag_icon.png"],
	"hit_protection": ["res://items/all/tardigrade/tardigrade_icon.png"],
	"lose_hp_per_second": ["res://items/all/blood_donation/blood_donation_icon.png"],
	"items_price": ["res://items/all/coupon/coupon_icon.png"],
	"reroll_price": ["res://dlcs/dlc_1/items/spyglass/spyglass_icon.png"],
	"free_rerolls": ["res://items/all/dangerous_bunny/dangerous_bunny_icon.png"],
	"gold_drops": ["res://items/all/evil_hat/evil_hat_icon.png"],
	"enemy_gold_drops": ["res://items/all/evil_hat/evil_hat_icon.png"],
	"neutral_gold_drops": ["res://items/all/evil_hat/evil_hat_icon.png"],
	"increase_material_value": ["res://items/all/crown/crown_icon.png"],
	"gain_pct_gold_start_wave": ["res://items/all/piggy_bank/piggy_bank_icon.png"],
	"recycling_gains": ["res://items/all/recycling_machine/recycling_machine_icon.png"],
	"crate_chance": ["res://items/consumables/item_box/item_box.png"],
	"item_steals": ["res://dlcs/dlc_1/characters/gangster/gangster_icon.png"],
	"map_size": ["res://dlcs/dlc_1/items/treasure_map/treasure_map_icon.png"],
	"number_of_enemies": ["res://items/all/gentle_alien/gentle_alien_icon.png"],
	"enemy_health": ["res://items/all/alien_baby/alien_baby_icon.png"],
	"enemy_damage": ["res://items/all/tentacle/tentacle_icon.png"],
	"enemy_speed": ["res://items/all/snail/snail_icon.png"],
	"boss_strength": ["res://ui/icons/misc/elite_icon.png"],
	"stronger_elites_on_kill": ["res://ui/icons/misc/elite_icon.png"],
	"loot_alien_chance": ["res://entities/units/enemies/looter/looter_icon.png"],
	"extra_loot_aliens": ["res://entities/units/enemies/looter/looter_icon.png"],
	"loot_alien_speed": ["res://entities/units/enemies/looter/looter_icon.png"],
	"stronger_loot_aliens_on_kill": ["res://entities/units/enemies/looter/looter_icon.png"],
	"trees": ["res://items/all/tree/tree_icon.png"],
	"trees_start_wave": ["res://items/all/tree/tree_icon.png"],
	"hp_start_wave": ["res://items/all/sad_tomato/sad_tomato_icon.png"],
	"hp_start_next_wave": ["res://items/all/weird_ghost/weird_ghost_icon.png"],
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
