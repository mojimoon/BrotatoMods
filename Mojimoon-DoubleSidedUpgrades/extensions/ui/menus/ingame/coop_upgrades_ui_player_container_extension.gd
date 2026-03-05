extends "res://ui/menus/ingame/coop_upgrades_ui_player_container.gd"

const COOP_MOD_ID = "Mojimoon-DoubleSidedUpgrades"
var coop_mod_data = ModLoaderStore.mod_data[COOP_MOD_ID]
var coop_mod_version = coop_mod_data.manifest.version_number
const Coop_Shared = preload("res://mods-unpacked/Mojimoon-DoubleSidedUpgrades/extensions/ui/menus/ingame/double_sided_upgrades_shared.gd")

var coop_defaults = {
	"DOUBLE_SIDED_UPGRADE_CHANCE": 0.5,
	"GLOBAL_UPGRADE_MULT": 1.0,
	"POSITIVE_UPGRADE_MULT": 2.0,
	"NEGATIVE_UPGRADE_MULT": -1.0,
	"CURSED_UPGRADE": true,
	"FORCE_CURSED_UPGRADE": false
}

func show_upgrades_for_level(level: int) -> void :
	.show_upgrades_for_level(level)

	var conf = Coop_Shared.get_config_values(COOP_MOD_ID, coop_mod_version, coop_defaults)
	Coop_Shared.apply_upgrades(self, conf)
