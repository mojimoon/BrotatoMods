extends Reference

const DEBUG_META_KEY = "Mojimoon_DSU_DebugLogged"

const VANILLA_STAT_VALUES = {
	"stat_max_hp": [3, 6, 9, 12],
	"stat_hp_regeneration": [2, 3, 4, 5],
	"stat_lifesteal": [1, 2, 3, 4],
	"stat_percent_damage": [5, 8, 12, 16],
	"stat_melee_damage": [2, 4, 6, 8],
	"stat_ranged_damage": [1, 2, 3, 4],
	"stat_elemental_damage": [1, 2, 3, 4],
	"stat_attack_speed": [5, 10, 15, 20],
	"stat_crit_chance": [3, 5, 7, 9],
	"stat_engineering": [2, 3, 4, 5],
	"stat_range": [15, 30, 45, 60],
	"stat_armor": [1, 2, 3, 4],
	"stat_dodge": [3, 6, 9, 12],
	"stat_speed": [3, 6, 9, 12],
	"stat_luck": [5, 10, 15, 20],
	"stat_harvesting": [5, 8, 10, 12]
}

const EFFECT_SCRIPT = preload("res://items/global/effect.gd")

static func get_config_values(mod_id: String, version: String, defaults: Dictionary) -> Dictionary:
	var conf = defaults.duplicate()
	var source = "defaults"
	var config = ModLoaderConfig.get_config(mod_id, version)
	if config != null:
		source = "get_config"
		for key in defaults.keys():
			if config.data.has(key):
				conf[key] = config.data[key]
	else:
		var default_config = ModLoaderConfig.get_default_config(mod_id)
		if default_config != null:
			source = "default_config"
			for key in defaults.keys():
				if default_config.data.has(key):
					conf[key] = default_config.data[key]

	var root = _get_root_for_logging()
	if root != null and not root.has_meta(DEBUG_META_KEY):
		ModLoaderLog.info("Debug(config) source=%s mod=%s version=%s conf=%s" % [source, mod_id, version, str(conf)], mod_id)
	return conf

static func apply_upgrades(container, conf: Dictionary) -> void:
	var before_count = container._old_upgrades.size()
	var modified_upgrades = []
	var changed_count = 0
	for original_upgrade in container._old_upgrades:
		var new_upgrade = _generate_new_upgrade(original_upgrade, conf, container.player_index)
		if _upgrade_signature(original_upgrade) != _upgrade_signature(new_upgrade):
			changed_count += 1
		modified_upgrades.append(new_upgrade)
	container._old_upgrades = modified_upgrades

	var upgrade_uis: = container._get_upgrade_uis()
	for i in upgrade_uis.size():
		var upgrade_ui = upgrade_uis[i]
		if upgrade_ui.visible and i < modified_upgrades.size():
			upgrade_ui.set_upgrade(modified_upgrades[i], container.player_index)

	var root = _get_root_for_logging(container)
	if root != null and not root.has_meta(DEBUG_META_KEY):
		root.set_meta(DEBUG_META_KEY, true)
		var container_path = "unknown"
		if container.get_script() != null:
			container_path = str(container.get_script().resource_path)
		ModLoaderLog.info("Debug(apply) container=%s player=%s upgrades=%s changed=%s chance=%s global=%s pos=%s neg=%s" % [container_path, str(container.player_index), str(before_count), str(changed_count), str(conf.get("DOUBLE_SIDED_UPGRADE_CHANCE", "?")), str(conf.get("GLOBAL_UPGRADE_MULT", "?")), str(conf.get("POSITIVE_UPGRADE_MULT", "?")), str(conf.get("NEGATIVE_UPGRADE_MULT", "?"))], "Mojimoon-DoubleSidedUpgrades")

static func _my_round(value: float) -> int:
	return int(round(value))

static func _generate_new_upgrade(original_upgrade: UpgradeData, conf: Dictionary, player_index: int) -> UpgradeData:
	var primary_stat_key = ""
	for effect in original_upgrade.effects:
		if primary_stat_key == "":
			primary_stat_key = effect.key
			break

	if primary_stat_key == "":
		return original_upgrade

	if not VANILLA_STAT_VALUES.has(primary_stat_key):
		return _generate_normal_upgrade(original_upgrade, conf, player_index)

	if randf() > conf["DOUBLE_SIDED_UPGRADE_CHANCE"]:
		return _generate_normal_upgrade(original_upgrade, conf, player_index)

	var new_upgrade = original_upgrade.duplicate()
	new_upgrade.effects = []
	for original_effect in original_upgrade.effects:
		var new_effect = original_effect.duplicate()
		var positive_value = original_effect.value
		positive_value = _my_round(positive_value * conf["GLOBAL_UPGRADE_MULT"] * conf["POSITIVE_UPGRADE_MULT"])
		new_effect.value = positive_value
		new_upgrade.effects.append(new_effect)

	var available_stats = VANILLA_STAT_VALUES.keys()
	available_stats.erase(primary_stat_key)

	var negative_stat = available_stats[randi() % available_stats.size()]
	var tier_index = clamp(new_upgrade.tier, 0, 3)
	var negative_base_value = VANILLA_STAT_VALUES[negative_stat][tier_index]

	var negative_effect = EFFECT_SCRIPT.new()
	negative_effect.key = negative_stat
	negative_effect.value = _my_round(negative_base_value * conf["GLOBAL_UPGRADE_MULT"] * conf["NEGATIVE_UPGRADE_MULT"])
	negative_effect.effect_sign = 3
	negative_effect.set("key_hash", Keys[negative_stat + '_hash'])
	new_upgrade.effects.append(negative_effect)

	return _try_curse(new_upgrade, conf, player_index)

static func _generate_normal_upgrade(original_upgrade: UpgradeData, conf: Dictionary, player_index: int) -> UpgradeData:
	var new_upgrade = original_upgrade.duplicate()
	new_upgrade.effects = []
	for original_effect in original_upgrade.effects:
		var new_effect = original_effect.duplicate()
		new_effect.value = _my_round(original_effect.value * conf["GLOBAL_UPGRADE_MULT"])
		new_upgrade.effects.append(new_effect)
	return _try_curse(new_upgrade, conf, player_index)

static func _try_curse(upgrade: UpgradeData, conf: Dictionary, player_index: int) -> UpgradeData:
	if not conf["CURSED_UPGRADE"]:
		return upgrade
	for dlc_id in RunData.enabled_dlcs:
		var dlc_data = ProgressData.get_dlc_data(dlc_id)
		if dlc_data and dlc_data.has_method("curse_item"):
			if conf["FORCE_CURSED_UPGRADE"]:
				upgrade = dlc_data.curse_item(upgrade, player_index)
			else:
				upgrade = dlc_data.update_item_effects(upgrade, player_index)
	return upgrade

static func _upgrade_signature(upgrade: UpgradeData) -> String:
	var parts = []
	for effect in upgrade.effects:
		parts.append(str(effect.key) + ":" + str(effect.value) + ":" + str(effect.effect_sign))
	return "|".join(parts)

static func _get_root_for_logging(container = null):
	if container != null and container.get_tree() != null:
		return container.get_tree().root
	return null
