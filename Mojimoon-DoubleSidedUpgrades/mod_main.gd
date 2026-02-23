extends Node

const MOD_ID = "Mojimoon-DoubleSidedUpgrades"
var config: ModConfig
var config_changed = false


func _init() -> void:
	var dir = ModLoaderMod.get_unpacked_dir() + "Mojimoon-DoubleSidedUpgrades/extensions/"

	ModLoaderMod.install_script_extension(dir + "ui/menus/pages/main_menu.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/ingame/upgrades_ui_player_container_extension.gd")
	set_process(true)

func _process(_delta):
	if ProgressData.SAVE_DIR == "":
		return
	set_process(false)

	var save_path = ProgressData.SAVE_DIR.plus_file(MOD_ID + ".json")
	if load_settings(save_path):
		init_mod_options()

func _exit_tree():
	save_settings()

func load_settings(save_path: String) -> bool:
	var data = _ModLoaderFile.get_json_as_dict(save_path)
	config = ModConfig.new(MOD_ID, data, save_path)
	var default_config = ModLoaderConfig.get_default_config(MOD_ID)
	var has_default = default_config != null && default_config.is_valid
	if !config.is_valid:
		if !has_default:
			return false
		config = ModConfig.new(MOD_ID, default_config.data, save_path)
		config_changed = true
	if has_default:
		if ModLoaderConfig.get_current_config(MOD_ID) == null:
			ModLoaderConfig.set_current_config(default_config)
		for key in config.data:
			if !default_config.data.has(key):
				config.data.erase(key)
				config_changed = true
		for key in default_config.data:
			if !config.data.has(key):
				config.data[key] = default_config.data[key]
				config_changed = true
	return true

func save_settings() -> bool:
	if !config_changed || !config.is_valid():
		return false
	return ModLoaderConfig.update_config(config) != null

func init_mod_options():
	var mci = get_node_or_null("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	if mci == null:
		return
	for key in config.data:
		mci.on_setting_changed(key, config.data[key], MOD_ID)
	mci.connect("setting_changed", self, "mod_options_setting_changed")

func mod_options_setting_changed(setting_name: String, value, mod_name: String):
	if mod_name != MOD_ID || !config.data.has(setting_name):
		return
	config.data[setting_name] = value
	config_changed = true
