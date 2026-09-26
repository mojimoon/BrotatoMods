extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

# 在难度选择界面左上角（返回按钮旁）加"东尼算法"设置按钮。

const AA_FONT_26 = preload("res://resources/fonts/actual/base/font_26.tres")
const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")
const AA_UI_SCENE = "res://mods-unpacked/Mojimoon-AutoAnthony/ui/settings_ui.tscn"


func _ready() -> void:
	._ready()
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_aa_init_button")


func _aa_init_button() -> void:
	var back_button = get_node_or_null("%BackButton")
	if back_button == null or back_button.has_node("AutoAnthonyBtn"):
		return
	var btn = Button.new()
	btn.name = "AutoAnthonyBtn"
	btn.text = tr("AA_BTN_OPEN")
	btn.rect_min_size = Vector2(200, 50)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_font_override("font", AA_FONT_26)
	AAMain.place_config_button(back_button, btn)
	btn.connect("pressed", self, "_aa_open_settings")


func _aa_open_settings() -> void:
	var scene = load(AA_UI_SCENE)
	if scene == null:
		return
	var ui = scene.instance()
	var layer = CanvasLayer.new()
	layer.layer = 100
	get_tree().current_scene.add_child(layer)
	layer.add_child(ui)
	ui.connect("tree_exited", layer, "queue_free")


# 选定难度、进入战斗前：生成本局的东尼算法内容，并把已持有的角色 / 道具 / 武器换成生成版本
func _on_element_pressed(element: InventoryElement, inventory_player_index: int) -> void:
	if not difficulty_selected and element != null and not element.is_special:
		var m = AAMain.get_mod()
		if m != null:
			m.start_new_run()
	._on_element_pressed(element, inventory_player_index)
