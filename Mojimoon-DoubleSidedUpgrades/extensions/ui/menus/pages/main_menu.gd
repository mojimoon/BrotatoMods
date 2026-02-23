extends "res://ui/menus/pages/main_menu.gd"


const DoubleSidedUpgradesOptions = preload("res://mods-unpacked/Mojimoon-DoubleSidedUpgrades/double_sided_upgrades_options.gd")


func _ready() -> void:
	var options = DoubleSidedUpgradesOptions.new()
	options.set_name("DoubleSidedUpgradesOptions")
	$"/root".add_child(options)

	._ready()
