extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

const MOD_ID = "Mojimoon-DoubleSidedUpgrades"
var mod_data = ModLoaderStore.mod_data[MOD_ID]
var mod_version = mod_data.manifest.version_number
const Shared = preload("res://mods-unpacked/Mojimoon-DoubleSidedUpgrades/extensions/ui/menus/ingame/double_sided_upgrades_shared.gd")

var settings_dict = {
	"DOUBLE_SIDED_UPGRADE_CHANCE": 0.5,
	"GLOBAL_UPGRADE_MULT": 1.0,
	"POSITIVE_UPGRADE_MULT": 2.0,
	"NEGATIVE_UPGRADE_MULT": -1.0,
	"CURSED_UPGRADE": true,
	"FORCE_CURSED_UPGRADE": false
}

func show_upgrades_for_level(level: int) -> void :
	.show_upgrades_for_level(level)

	var conf = Shared.get_config_values(MOD_ID, mod_version, settings_dict)
	Shared.apply_upgrades(self, conf)
