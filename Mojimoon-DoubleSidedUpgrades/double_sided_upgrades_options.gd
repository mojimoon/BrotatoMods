extends Node


const MOD_ID = "Mojimoon-DoubleSidedUpgrades"
const SAVE_PATH = "user://mods/Mojimoon-DoubleSidedUpgrades/config.cfg"
const SAVE_SECTION = "settings"

var double_sided_upgrade_chance: float = 0.1
var global_upgrade_mult: float = 1.0
var positive_upgrade_mult: float = 2.0
var negative_upgrade_mult: float = -1.0
# var cursed_upgrade: bool = false

func _ready() -> void:
	load_mod_options()


func load_mod_options() -> void:
	if not $"/root/ModLoader".has_node("dami-ModOptions"):
		return

	var mod_configs = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface").mod_configs

	if mod_configs.has(MOD_ID):
		var config = mod_configs[MOD_ID]

		if config.has("DOUBLE_SIDED_UPGRADE_CHANCE"):
			double_sided_upgrade_chance = config["DOUBLE_SIDED_UPGRADE_CHANCE"]

		if config.has("GLOBAL_UPGRADE_MULT"):
			global_upgrade_mult = config["GLOBAL_UPGRADE_MULT"]
		
		if config.has("POSITIVE_UPGRADE_MULT"):
			positive_upgrade_mult = config["POSITIVE_UPGRADE_MULT"]
		
		if config.has("NEGATIVE_UPGRADE_MULT"):
			negative_upgrade_mult = config["NEGATIVE_UPGRADE_MULT"]
		
		# if config.has("CURSED_UPGRADE"):
		# 	cursed_upgrade = config["CURSED_UPGRADE"]
