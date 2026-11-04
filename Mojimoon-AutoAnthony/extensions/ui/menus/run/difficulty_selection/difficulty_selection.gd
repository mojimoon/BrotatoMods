extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

# 在难度选择界面左上角（返回按钮旁）加"东尼算法"设置按钮。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


# Godot 3 会自动调用每一层脚本的 _ready（父类先于本扩展），不能再调用 ._ready()
func _ready() -> void:
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_aa_init_button")


func _aa_init_button() -> void:
	AAMain.add_config_button(self)


# 选定难度、进入战斗前：生成本局的东尼算法内容，并把已持有的角色 / 道具 / 武器换成生成版本
func _on_element_pressed(element: InventoryElement, inventory_player_index: int) -> void:
	if not difficulty_selected and element != null and not element.is_special:
		var m = AAMain.get_mod()
		if m != null:
			m.start_new_run()
	._on_element_pressed(element, inventory_player_index)
