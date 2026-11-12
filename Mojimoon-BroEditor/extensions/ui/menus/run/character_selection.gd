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


# 禁用的角色显示为未解锁（不可选）
func _get_unlocked_elements(player_index: int) -> Array:
	var out = ._get_unlocked_elements(player_index)
	var m = BEMain.get_mod()
	return m.without(out, m.disabled_character_hashes()) if m != null else out


# 被本模组单独锁定的角色：锁定面板显示解锁条件与说明（原版显示解锁它的挑战，没有时为 NOT_SET）
func _update_locked_panel(element: InventoryElement, player_index: int) -> void:
	._update_locked_panel(element, player_index)
	var m = BEMain.get_mod()
	var panels = _get_locked_panels()
	if m == null or player_index < 0 or player_index >= panels.size() or not panels[player_index].visible:
		return
	if element.item == null or not element.item.is_locked:
		return
	var text = m.lock_text("character", element.item.my_id)
	if text != "":
		panels[player_index].set_description(text)
