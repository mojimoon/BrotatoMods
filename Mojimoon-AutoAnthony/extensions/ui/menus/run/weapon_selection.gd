extends "res://ui/menus/run/weapon_selection.gd"

# 在武器选择界面左上角（返回按钮旁）加"东尼算法"设置按钮。
# 进入本界面时提前生成本局内容（界面上直接显示重组后的武器）；"任意初始武器"时列出对应稀有度的全部武器。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


func _ready() -> void:
	._ready()
	# 延迟到其他 mod 的按钮就位后再排位，避免重叠
	call_deferred("_aa_init_button")


func _aa_init_button() -> void:
	AAMain.add_config_button(self)


func _aa_any_start(player_index: int) -> Array:
	var m = AAMain.get_mod()
	if m == null:
		return []
	m.prepare_selection()
	return m.any_start_weapons(RunData.get_player_character(player_index))


func _get_all_possible_elements(player_index: int) -> Array:
	var any = _aa_any_start(player_index)
	if any.empty():
		return ._get_all_possible_elements(player_index)
	var character_data = RunData.get_player_character(player_index)
	return any + ItemService.get_ordered_starting_items(character_data.starting_items)


func _get_unlocked_elements(player_index: int) -> Array:
	var any = _aa_any_start(player_index)
	if any.empty():
		return ._get_unlocked_elements(player_index)
	var out = []
	for w in any:
		out.push_back(w.my_id_hash)
	for id in ._get_unlocked_elements(player_index):
		if not id in out:
			out.push_back(id)
	return out
