extends "res://ui/menus/shop/item_description.gd"

# BetterCodex：商店里（单人）可掉落异变果时，在道具 / 角色描述的最后加一段异变预览（ui/mutation_view.gd，与图鉴相同的显示）。
# 行都加在效果列表里，下次 set_item 时随原版清空效果列表一起删掉。图鉴里（含暂停菜单里的图鉴）由图鉴自己的异变开关显示，这里不加。
# ImprovedTooltips 也扩展本脚本（改写效果行的生成）；这里只在 set_item 之后追加，先后顺序都不影响。

const BC_DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"


func set_item(item_data: ItemParentData, player_index: int, item_count: = 1) -> void:
	.set_item(item_data, player_index, item_count)
	_bc_add_mutation_preview(item_data, player_index)


func _bc_add_mutation_preview(item_data, player_index: int) -> void:
	if not item_data is ItemData or RunData.is_coop_run or RunData.players_data.empty():
		return
	if find_parent("Shop") == null or find_parent("MenuCodex") != null:
		return
	if not load(BC_DIR + "ui/shop_hook.gd").mutation_preview_on():
		return
	var evolution = int(abs(RunData.get_player_effect(Keys.stat_evolution_hash, player_index)))
	load(BC_DIR + "ui/mutation_view.gd").build(get_effects(), item_data, evolution, player_index)
