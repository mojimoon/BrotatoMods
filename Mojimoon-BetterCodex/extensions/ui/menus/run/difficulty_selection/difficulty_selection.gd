extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

# 角色面板右侧加角色信息（BetterCodex/ui/char_info.gd）；联机时原版也隐藏角色面板，不加


func _ready() -> void:
	if not RunData.is_coop_run:
		var info = load("res://mods-unpacked/Mojimoon-BetterCodex/ui/char_info.gd").new()
		_character_panel.get_parent().add_child_below_node(_character_panel, info)
		info.setup(RunData.players_data[0].current_character)
