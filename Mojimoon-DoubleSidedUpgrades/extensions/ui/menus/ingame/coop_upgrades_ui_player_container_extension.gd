extends "res://ui/menus/ingame/coop_upgrades_ui_player_container.gd"

const UpgradeModifierScript = preload("res://mods-unpacked/Mojimoon-DoubleSidedUpgrades/extensions/ui/menus/ingame/helpers/upgrade_modifier.gd")

onready var _upgrade_modifier = UpgradeModifierScript.new()

func show_upgrades_for_level(level: int) -> void :
	.show_upgrades_for_level(level)
	_old_upgrades = _upgrade_modifier.apply_modified_upgrades(self, player_index, _old_upgrades)
