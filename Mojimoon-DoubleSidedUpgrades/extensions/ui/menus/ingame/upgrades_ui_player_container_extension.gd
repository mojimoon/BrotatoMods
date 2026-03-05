extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

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

const EffectScript = preload("res://items/global/effect.gd")

func show_upgrades_for_level(level: int) -> void :
	.show_upgrades_for_level(level)

	var options = $"/root/DoubleSidedUpgradesOptions"
	options.load_mod_options()

	var modified_upgrades = []
	for original_upgrade in _old_upgrades:
		var new_upgrade = _generate_new_upgrade(original_upgrade, options)
		modified_upgrades.append(new_upgrade)
	
	_old_upgrades = modified_upgrades
	
	var upgrade_uis: = _get_upgrade_uis()
	for i in upgrade_uis.size():
		var upgrade_ui = upgrade_uis[i]
		if upgrade_ui.visible and i < modified_upgrades.size():
			upgrade_ui.set_upgrade(modified_upgrades[i], player_index)

func _my_round(value: float) -> int:
	# if abs(value) < 1:
	# 	return value > 0 ? 1 : -1
	return int(round(value))

func _generate_new_upgrade(original_upgrade: UpgradeData, conf) -> UpgradeData:

	var primary_stat_key = ""
	for effect in original_upgrade.effects:
		if primary_stat_key == "":
			primary_stat_key = effect.key
			break
	
	if primary_stat_key == "":
		return original_upgrade
	
	if not VANILLA_STAT_VALUES.has(primary_stat_key):
		return _generate_normal_upgrade(original_upgrade, conf)
	
	if randf() > conf.double_sided_upgrade_chance:
		return _generate_normal_upgrade(original_upgrade, conf)
	
	var new_upgrade = original_upgrade.duplicate()
	new_upgrade.effects = []
	for original_effect in original_upgrade.effects:
		var new_effect = original_effect.duplicate()
		var positive_value = original_effect.value
		positive_value = _my_round(positive_value * conf.global_upgrade_mult * conf.positive_upgrade_mult)
		new_effect.value = positive_value
		new_upgrade.effects.append(new_effect)
	
	var available_stats = VANILLA_STAT_VALUES.keys()
	available_stats.erase(primary_stat_key)
	
	var negative_stat = available_stats[randi() % available_stats.size()]
	var tier_index = clamp(new_upgrade.tier, 0, 3)
	var negative_base_value = VANILLA_STAT_VALUES[negative_stat][tier_index]
	
	var negative_effect = EffectScript.new()
	negative_effect.key = negative_stat
	negative_effect.value = _my_round(negative_base_value * conf.global_upgrade_mult * conf.negative_upgrade_mult)
	negative_effect.effect_sign = 3

	negative_effect.set("key_hash", Keys[negative_stat+'_hash'])
	
	new_upgrade.effects.append(negative_effect)

	return _try_curse(new_upgrade, conf)

func _generate_normal_upgrade(original_upgrade: UpgradeData, conf) -> UpgradeData:
	
	var new_upgrade = original_upgrade.duplicate()
	new_upgrade.effects = []
	for original_effect in original_upgrade.effects:
		var new_effect = original_effect.duplicate()
		var new_value = _my_round(original_effect.value * conf.global_upgrade_mult)
		new_effect.value = new_value
		new_upgrade.effects.append(new_effect)

	return _try_curse(new_upgrade, conf)

func _try_curse(upgrade: UpgradeData, conf) -> UpgradeData:
	if not conf.cursed_upgrade:
		return upgrade
	
	for dlc_id in RunData.enabled_dlcs:
		var dlc_data = ProgressData.get_dlc_data(dlc_id)
		if dlc_data and dlc_data.has_method("curse_item"):
			if conf.force_cursed_upgrade:
				upgrade = dlc_data.curse_item(upgrade, player_index)
			else:
				upgrade = dlc_data.update_item_effects(upgrade, player_index)
	
	return upgrade
