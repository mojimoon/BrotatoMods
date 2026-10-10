extends "res://singletons/run_data.gd"

# 开局状态：初始材料 / 等级 / 箱子 / 额外禁用次数（同 cave-modtools 的"初始状态"）。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func add_starting_items_and_weapons() -> void:
	.add_starting_items_and_weapons()
	var m = BEMain.get_mod()
	if m != null:
		m.apply_start_state()


func reset(restart: bool = false) -> void:
	.reset(restart)
	var m = BEMain.get_mod()
	if m != null and restart:
		m.apply_start_bans()
