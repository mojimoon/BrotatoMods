extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


# Godot 3 会自动调用每一层脚本的 _ready：这里不调用 ._ready()
func _ready() -> void:
	call_deferred("_be_init_button")


func _be_init_button() -> void:
	BEMain.add_editor_button(self)


# 选定难度：额外禁用次数（原版此时发放禁用次数）、起始波次
func _on_element_pressed(element: InventoryElement, inventory_player_index: int) -> void:
	var was_selected = difficulty_selected
	._on_element_pressed(element, inventory_player_index)
	var m = BEMain.get_mod()
	if m != null and not was_selected and difficulty_selected:
		m.apply_start_bans()
		m.apply_start_wave()
