extends "res://singletons/item_service.gd"

# 替换商店 / 箱子 / 传奇箱子 / 战利品 物品为目标物品。
# - 商店（三选一）：cfg_replace_shop 替换所有 item 位；cfg_replace_shop_first 每次刷新替换一个；
#   cfg_replace_shop_once 每波依次放出所选物品各一次（均不影响锁住的物品）
# - 箱子：普通箱子受 cfg_replace_crate 控制；传奇箱子按 legendary_mode 分派（见 mod_main.get_legendary_replacement）
# - 战利品（藏宝图等）：归入 cfg_replace_crate 控制
# 诅咒传递 + A-B-A-B 轮流由 mod 节点的 get_replacement 处理。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAllv2/mod_main.gd")


# 商店物品
# 父类返回的 new_items 只含新生成的物品（锁住的已在 _shop_items 前,不在此数组中）。
func get_player_shop_items(wave: int, player_index: int, args) -> Array:
	var new_items: Array = .get_player_shop_items(wave, player_index, args)
	var m = ModMain._get_mod()
	if m == null or m.target_item_ids.empty():
		return new_items

	# 优先级：replace_shop（全部）> replace_shop_first（MOJI_SHOP_ALWAYS_APPEAR）
	if m.cfg_replace_shop:
		var result: Array = []
		for entry in new_items:
			var item = entry[0]
			if item is ItemData:
				item = m.get_replacement(item, player_index)
			result.push_back([item, entry[1]])
		return result
	elif m.cfg_replace_shop_first:
		# 替换 new_items 中最后一个 ItemData；若没有（全是武器）则替换最后一个条目。
		# guaranteed_shop_items 由角色效果产生，通常排在 new_items 前部，
		# 取最后一个物品槽可避开对 guaranteed items 的影响。
		if new_items.size() > 0:
			var target_idx = -1
			for i in range(new_items.size() - 1, -1, -1):
				if new_items[i][0] is ItemData:
					target_idx = i
					break
			if target_idx == -1:
				target_idx = new_items.size() - 1
			new_items[target_idx][0] = m.get_replacement(new_items[target_idx][0], player_index)
	elif m.cfg_replace_shop_once:
		# 占用靠后的物品槽位（避开排在前面的 guaranteed items），按选择顺序从左到右放置；
		# 没有物品槽位（全是武器）时占用最后一个槽位。
		var slots: Array = []
		for i in new_items.size():
			if new_items[i][0] is ItemData:
				slots.push_back(i)
		if slots.empty() and new_items.size() > 0:
			slots.push_back(new_items.size() - 1)
		var ids: Array = m.take_shop_once_ids(wave, player_index, slots.size())
		slots = slots.slice(slots.size() - ids.size(), slots.size() - 1) if not ids.empty() else []
		for k in ids.size():
			var idx: int = slots[k]
			new_items[idx][0] = m._make_replacement(ids[k], new_items[idx][0], player_index)
	return new_items


# 箱子（普通 + 传奇）
func process_item_box(consumable_data, wave: int, player_index: int):
	var item = .process_item_box(consumable_data, wave, player_index)
	var m = ModMain._get_mod()
	if m == null or not item is ItemData:
		return item

	var is_legendary: bool = consumable_data != null and consumable_data.my_id_hash == Keys.consumable_legendary_item_box_hash
	if is_legendary:
		return m.get_legendary_replacement(item, player_index)
	if m.cfg_replace_crate:
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
