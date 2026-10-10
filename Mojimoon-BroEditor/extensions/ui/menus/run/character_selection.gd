extends "res://ui/menus/run/character_selection.gd"

# 选角界面：先按档案改写角色（列表与说明面板显示编辑后的角色），再在左上角加"角色编辑器"按钮。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


# 原版 _ready 构建角色列表之前（_enter_tree 先于 _ready）应用档案。
# Godot 3 会自动调用每一层脚本的 _ready，扩展里不调用 ._ready()
func _enter_tree() -> void:
	var m = BEMain.get_mod()
	if m != null:
		m.apply_all()
		m.clear_start_wave()


func _ready() -> void:
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_be_init_button")


func _be_init_button() -> void:
	BEMain.add_editor_button(self)
