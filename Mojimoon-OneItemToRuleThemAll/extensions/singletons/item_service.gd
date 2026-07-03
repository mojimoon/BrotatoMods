extends "res://singletons/item_service.gd"

# 替换商店 / 箱子 / 传奇箱子 / 战利品 物品为目标物品。
# - 商店：cfg_replace_shop 替换所有 item 位；cfg_replace_shop_first 仅替换第一个（不替换锁住的）
# - 箱子：区分普通/传奇，分别受 cfg_replace_crate / cfg_replace_legendary_crate 控制
# - 战利品（藏宝图等）：归入 cfg_replace_crate 控制
# 诅咒传递 + A-B-A-B 轮流由 mod 节点的 get_replacement 处理。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAll/mod_main.gd")


# 商店物品
# 父类返回的 new_items 只含新生成的物品（锁住的已在 _shop_items 前,不在此数组中）。
func get_player_shop_items(wave: int, player_index: int, args) -> Array:
	var new_items: Array = .get_player_shop_items(wave, player_index, args)
	var m = ModMain._get_mod()
	if m == null or m.target_item_ids.empty():
		return new_items

	# 优先级：replace_shop（全部）> replace_shop_first（仅第一个）
	if m.cfg_replace_shop:
		var result: Array = []
		for entry in new_items:
			var item = entry[0]
			if item is ItemData:
				item = m.get_replacement(item, player_index)
			result.push_back([item, entry[1]])
		return result
	elif m.cfg_replace_shop_first:
		# new_items[0] 是第一个非锁住的新物品
		if new_items.size() > 0 and new_items[0][0] is ItemData:
			var entry = new_items[0]
			entry[0] = m.get_replacement(entry[0], player_index)
	return new_items


# 箱子（普通 + 传奇）
func process_item_box(consumable_data, wave: int, player_index: int):
	var item = .process_item_box(consumable_data, wave, player_index)
	var m = ModMain._get_mod()
	if m == null or m.target_item_ids.empty():
		return item

	var is_legendary: bool = consumable_data != null and consumable_data.my_id_hash == Keys.consumable_legendary_item_box_hash
	var do_replace: bool = m.cfg_replace_legendary_crate if is_legendary else m.cfg_replace_crate

	if do_replace and item is ItemData:
		return m.get_replacement(item, player_index)
	return item


# 战利品 / 藏宝图
func get_rand_item_for_wave(wave: int, player_index: int):
	var item = .get_rand_item_for_wave(wave, player_index)
	var m = ModMain._get_mod()
	if m == null or m.target_item_ids.empty():
		return item
	if m.cfg_replace_crate and item is ItemData:
		return m.get_replacement(item, player_index)
	return item
