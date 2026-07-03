extends "res://singletons/item_service.gd"

# 替换商店 / 箱子 / 传奇箱子 / 战利品 物品为目标物品。
# - 商店：只替换 ItemData（WeaponData 完全不碰）
# - 箱子：区分普通/传奇，分别受 REPLACE_CRATE_ITEMS / REPLACE_LEGENDARY_CRATE_ITEMS 控制
# - 战利品（藏宝图等）：归入 REPLACE_CRATE_ITEMS 控制
# 诅咒传递 + A-B-A-B 轮流由 mod 节点的 get_replacement 处理。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAll/mod_main.gd")


# 商店物品
func get_player_shop_items(wave: int, player_index: int, args) -> Array:
	var new_items: Array = .get_player_shop_items(wave, player_index, args)
	var m = ModMain._get_mod()
	if m == null or not m.cfg_replace_shop or m.target_item_ids.empty():
		return new_items

	var result: Array = []
	for entry in new_items:
		var item = entry[0]
		# 只替换物品位，武器位保留原样
		if item is ItemData:
			item = m.get_replacement(item, player_index)
		result.push_back([item, entry[1]])
	return result


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
