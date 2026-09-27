extends "res://ui/menus/run/character_selection.gd"

# 在角色选择界面左上角（返回按钮旁）加"东尼算法"设置按钮。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


func _ready() -> void:
	._ready()
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_aa_init_button")


func _aa_init_button() -> void:
	AAMain.add_config_button(self)
