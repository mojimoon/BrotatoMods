extends "res://ui/menus/run/weapon_selection.gd"

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


# Godot 3 会自动调用每一层脚本的 _ready：这里不调用 ._ready()
func _ready() -> void:
	call_deferred("_be_init_button")


func _be_init_button() -> void:
	BEMain.add_editor_button(self)


# 禁用的初始武器 / 道具显示为未解锁（不可选）
func _get_unlocked_elements(player_index: int) -> Array:
	var out = ._get_unlocked_elements(player_index)
	var m = BEMain.get_mod()
	return m.without(out, m.global_ban_hashes()) if m != null else out
