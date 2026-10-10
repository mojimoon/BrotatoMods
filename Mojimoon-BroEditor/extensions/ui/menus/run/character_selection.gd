extends "res://ui/menus/run/character_selection.gd"

# 选角界面：先按档案改写角色（列表与说明面板显示编辑后的角色），再在左上角加"角色编辑器"按钮。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _ready() -> void:
	var m = BEMain.get_mod()
	if m != null:
		m.apply_all()
	._ready()
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_be_init_button")


func _be_init_button() -> void:
	BEMain.add_editor_button(self)
