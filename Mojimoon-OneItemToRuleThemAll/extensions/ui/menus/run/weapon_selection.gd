extends "res://ui/menus/run/weapon_selection.gd"

# 在武器选择界面右上角加“替换物品”按钮，点击打开物品选择弹窗。
# 参考 cave-modtools 的 weapon_selection 扩展。

const FONT_26 = preload("res://resources/fonts/actual/base/font_26.tres")
const UI_SCENE_PATH = "res://mods-unpacked/Mojimoon-OneItemToRuleThemAll/ui/item_picker_ui.tscn"

var _moji_picker_btn: Button = null


func _ready() -> void:
	._ready()
	_init_picker_button()


func _init_picker_button() -> void:
	var back_button = get_node_or_null("%BackButton")
	if back_button == null:
		return
	if back_button.has_node("MojiPickerBtn"):
		return

	_moji_picker_btn = Button.new()
	_moji_picker_btn.name = "MojiPickerBtn"
	_moji_picker_btn.text = "替换物品"
	_moji_picker_btn.rect_min_size = Vector2(220, 50)
	_moji_picker_btn.focus_mode = Control.FOCUS_ALL
	if FONT_26 != null:
		_moji_picker_btn.add_font_override("font", FONT_26)

	back_button.add_child(_moji_picker_btn)
	_moji_picker_btn.rect_position = Vector2(back_button.rect_size.x + 18, 0)

	_moji_picker_btn.focus_neighbour_left = _moji_picker_btn.get_path_to(back_button)
	back_button.focus_neighbour_right = back_button.get_path_to(_moji_picker_btn)

	_moji_picker_btn.connect("pressed", self, "_on_picker_btn_pressed")


func _on_picker_btn_pressed() -> void:
	_open_picker_ui()


func _open_picker_ui() -> void:
	var ui_scene = load(UI_SCENE_PATH)
	if ui_scene == null:
		return
	var ui = ui_scene.instance()
	var layer = CanvasLayer.new()
	layer.layer = 100
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(layer)
	layer.add_child(ui)
	ui.connect("tree_exited", layer, "queue_free")
