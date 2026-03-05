extends Node

const MOD_ID = "Mojimoon-DoubleSidedUpgrades"
var data = ModLoaderStore.mod_data[MOD_ID]
var version = data.manifest.version_number

var settings_dict = {
	"DOUBLE_SIDED_UPGRADE_CHANCE": 0.5,
	"GLOBAL_UPGRADE_MULT": 1.0,
	"POSITIVE_UPGRADE_MULT": 2.0,
	"NEGATIVE_UPGRADE_MULT": -1.0,
	"CURSED_UPGRADE": true,
	"FORCE_CURSED_UPGRADE": false
}


func _init() -> void:
	ModLoaderLog.info("Init", MOD_ID)
	var dir = ModLoaderMod.get_unpacked_dir() + "Mojimoon-DoubleSidedUpgrades/extensions/"

	ModLoaderMod.install_script_extension(dir + "ui/menus/ingame/upgrades_ui_player_container_extension.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/ingame/coop_upgrades_ui_player_container_extension.gd")


func _ready() -> void:
	call_deferred("_config")

func _config() -> void:
	var ModsConfigInterface = get_node_or_null("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	if ModsConfigInterface != null:
		ModLoaderLog.info("Connect setting_changed", MOD_ID)
		if not ModsConfigInterface.is_connected("setting_changed", self, "setting_changed"):
			ModsConfigInterface.connect("setting_changed", self, "setting_changed")

	var config = ModLoaderConfig.get_config(MOD_ID, version)
	var defaultConfig = ModLoaderConfig.get_default_config(MOD_ID)
	if data != null:
		ModLoaderLog.info("Current Version is %s." % version, MOD_ID)
		if config != null:
			for key in settings_dict.keys():
				if not config.data.has(key):
					config.data[key] = settings_dict[key]
				if ModsConfigInterface != null:
					ModsConfigInterface.on_setting_changed(key, config.data[key], MOD_ID)
			config.save_path = "user://configs/Mojimoon-DoubleSidedUpgrades/" + version + ".json"
			config.save_to_file()
			ModLoaderLog.info("Loaded config data: %s" % str(config.data), MOD_ID)
		else:
			if defaultConfig != null:
				config = ModLoaderConfig.create_config(MOD_ID, version, defaultConfig.data)
			else:
				config = ModLoaderConfig.create_config(MOD_ID, version, {})
	else:
		if defaultConfig != null:
			config = ModLoaderConfig.create_config(MOD_ID, version, defaultConfig.data)
		else:
			config = ModLoaderConfig.create_config(MOD_ID, version, {})

func setting_changed(setting_name, value, mod_name) -> void:
	if mod_name != MOD_ID:
		return
	var config = ModLoaderConfig.get_current_config(MOD_ID)
	if config == null:
		ModLoaderLog.info("setting_changed ignored because current config is null", MOD_ID)
		return
	config.save_path = "user://configs/Mojimoon-DoubleSidedUpgrades/" + version + ".json"
	config.data[setting_name] = value
	config.save_to_file()
	ModLoaderLog.info("setting_changed %s=%s" % [str(setting_name), str(value)], MOD_ID)
