extends "res://ui/menus/run/weapon_selection.gd"

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


# Godot 3 会自动调用每一层脚本的 _ready：这里不调用 ._ready()
func _ready() -> void:
	call_deferred("_be_init_button")


func _be_init_button() -> void:
	BEMain.add_editor_button(self)
