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
		"structure_range", "accuracy", "harvesting_growth", "weapon_slot",
	]],
	["BE_GRP_WORLD", [
		"items_price", "weapons_price", "reroll_price", "free_rerolls", "gold_drops", "enemy_gold_drops",
		"neutral_gold_drops", "crate_chance", "loot_alien_chance", "recycling_gains", "map_size",
		"number_of_enemies", "enemy_health", "enemy_damage", "enemy_speed", "boss_strength", "trees",
		"trees_start_wave", "hp_start_wave", "hp_start_next_wave", "dodge_cap", "speed_cap", "hp_cap",
		"crit_chance_cap",
	]],
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
	["trigger", "BE_CAT_TRIGGER"],
	["scaling", "BE_CAT_SCALING"],
	["combat", "BE_CAT_COMBAT"],
	["economy", "BE_CAT_ECONOMY"],
	["weapon", "BE_CAT_WEAPON"],
	["summon", "BE_CAT_SUMMON"],
	["start", "BE_CAT_START"],
	["other", "BE_CAT_OTHER"],
]

const START_KEYS = ["starting_item", "starting_weapon", "cursed_starting_item", "cursed_starting_weapon"]
# ponytail: 关键字分类，覆盖原版常见 key；新机制落到"其他"，需要时再补关键字
const WEAPON_WORDS = ["weapon", "melee", "ranged", "tier_i", "tier_iv", "lock_current"]
const SUMMON_WORDS = ["turret", "structure", "landmine", "pet_", "wandering_bot", "tree_turret", "garden", "builder", "minion"]
const ECONOMY_WORDS = ["gold", "price", "reroll", "harvest", "crate", "shop", "material", "loot_alien", "recycling", "xp", "item_box", "duplicate_item", "hourglass", "mirror"]
const COMBAT_WORDS = ["explo", "burn", "pierc", "bounce", "projectile", "crit", "knockback", "dmg", "damage", "heal", "slow", "speed", "dodge", "hp", "enemy", "boss", "curse"]


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


static func category_of(e) -> String:
	var key: String = str(e.key).to_lower()
	var ck: String = str(e.custom_key).to_lower()
	var tk: String = str(e.text_key).to_lower()
	var script_path = e.get_script().resource_path.to_lower() if e.get_script() != null else ""
	if ck in START_KEYS:
		return "start"
	if ck != "" and ck in trigger_keys() and is_plain_effect(e):
		return "trigger"
	if tk.find("gain_stat_for_every") >= 0 or script_path.find("gain_stat_for_every") >= 0 or script_path.find("stat_links") >= 0:
		return "scaling"
	if ck == "" and is_plain_effect(e) and is_stat_key(key) and e.storage_method == 0:
		return "stat" if key.begins_with("stat_") or key in ["xp_gain", "pickup_range", "knockback", "consumable_heal"] else _keyword_category(key + " " + ck + " " + tk + " " + script_path)
	return _keyword_category(key + " " + ck + " " + tk + " " + script_path)


static func _keyword_category(s: String) -> String:
	for w in SUMMON_WORDS:
		if s.find(w) >= 0:
			return "summon"
	for w in WEAPON_WORDS:
		if s.find(w) >= 0:
			return "weapon"
	for w in ECONOMY_WORDS:
		if s.find(w) >= 0:
			return "economy"
	for w in COMBAT_WORDS:
		if s.find(w) >= 0:
			return "combat"
	return "other"


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
