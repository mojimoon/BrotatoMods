extends "res://ui/menus/run/character_selection.gd"

# 在角色选择界面左上角（返回按钮旁）加"东尼算法"设置按钮。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


# Godot 3 会自动调用每一层脚本的 _ready（父类先于本扩展），这里不能再调用 ._ready()，否则原版初始化执行两次
#（1.2 的物品套组栏、多初始武器状态会被重复初始化）。撤销放在 _enter_tree：在原版 _ready 建立角色列表之前执行


# 从武器选择界面返回（换角色）：撤销提前生成的内容
func _enter_tree() -> void:
	var m = AAMain.get_mod()
	if m != null:
		m.cancel_selection()


func _ready() -> void:
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_aa_init_button")


func _aa_init_button() -> void:
	AAMain.add_config_button(self)
