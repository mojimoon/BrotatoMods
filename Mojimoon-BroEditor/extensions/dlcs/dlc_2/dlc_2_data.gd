extends "res://dlcs/dlc_2/dlc_2_data.gd"

# 异变（史前惧兽）：效果的"异变复制 / 异变清除"选项（档案里按效果设置，见 mod_main.mutation_flags）。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _get_copy_candidates(mutated_item: ItemParentData, player_index: int) -> Array:
	var out = ._get_copy_candidates(mutated_item, player_index)
	var m = BEMain.get_mod()
	return m.filter_mutation_copies(out, mutated_item, player_index, get_mutation_scale(player_index)) if m != null else out


func _get_removable_negative_effect_indexes(item_data: ItemParentData) -> Array:
	var out = ._get_removable_negative_effect_indexes(item_data)
	var m = BEMain.get_mod()
	return m.filter_mutation_removals(out, item_data) if m != null else out
