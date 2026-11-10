extends "res://singletons/run_data.gd"

# BetterCodex：每个玩家"可被异变的非角色道具"数量（异变果掉落条件 DLC2Data._has_enough_items_for_mutation_fruit），
# 获得 / 失去道具时增量更新（异变也是先 remove_item 再 add_item）；表里没有的玩家在下次读取时数一遍。
# 使用方在可能整体换掉道具列表之后（进商店）调用 bc_reset_mutable_counts。

var bc_mutable_counts = {}
var _bc_adds = 0


func bc_mutable_count(player_index: int) -> int:
	if not bc_mutable_counts.has(player_index):
		var n = 0
		for item in players_data[player_index].items:
			if _bc_is_mutable(item):
				n += 1
		bc_mutable_counts[player_index] = n
	return bc_mutable_counts[player_index]


func bc_reset_mutable_counts() -> void:
	bc_mutable_counts = {}


static func _bc_is_mutable(item) -> bool:
	return item != null and not item is CharacterData and ItemService.can_item_be_mutated(item)


func add_item(item: ItemData, player_index: int, is_selection: bool = false) -> void:
	.add_item(item, player_index, is_selection)
	_bc_adds += 1
	if bc_mutable_counts.has(player_index) and _bc_is_mutable(item):
		bc_mutable_counts[player_index] += 1


func remove_item(item: ItemData, player_index: int, by_id: bool = false, apply_replacement: bool = true) -> void:
	var before = players_data[player_index].items.size()
	var adds = _bc_adds
	.remove_item(item, player_index, by_id, apply_replacement)
	# 实际移除的个数 = 之前 + 期间加入的（替换品）- 之后；没找到时为 0
	var removed = before + (_bc_adds - adds) - players_data[player_index].items.size()
	if removed > 0 and bc_mutable_counts.has(player_index) and _bc_is_mutable(item):
		bc_mutable_counts[player_index] -= removed
