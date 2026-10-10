extends "res://ui/menus/run/weapon_selection.gd"

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _ready() -> void:
	._ready()
	call_deferred("_be_init_button")


func _be_init_button() -> void:
	BEMain.add_editor_button(self)
