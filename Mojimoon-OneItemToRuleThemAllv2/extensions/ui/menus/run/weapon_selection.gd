extends "res://ui/menus/run/weapon_selection.gd"

# 在武器选择界面左上角（返回按钮旁）加"替换物品"按钮，点击打开物品选择弹窗。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAllv2/mod_main.gd")


func _ready() -> void:
	._ready()
	# 延迟到其他 mod（如 cave-modtools）的按钮就位后再排位，避免重叠
	call_deferred("_moji_init_button")


func _moji_init_button() -> void:
	ModMain.add_config_button(self)
