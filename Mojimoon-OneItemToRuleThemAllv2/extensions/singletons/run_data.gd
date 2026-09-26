extends "res://singletons/run_data.gd"

# 替换起始物品为目标物品。
# 调父类 add_starting_items_and_weapons 后，遍历每个玩家的 items 数组，
# 把 ItemData 替换为目标物品。
# 跳过 CharacterData（角色也是 ItemData 子类，会被误替换）和 WeaponData。
# 同时在开局重置 A-B-A-B 计数器。

const ModMain = preload("res://mods-unpacked/Mojimoon-OneItemToRuleThemAll/mod_main.gd")


func add_starting_items_and_weapons() -> void:
	.add_starting_items_and_weapons()

	# 新一局开始：重置 A-B-A-B 轮流计数器
	var m = ModMain._get_mod()
	if m == null:
		return
	m.reset_counter()

	if not m.cfg_replace_starting or m.target_item_ids.empty():
		return

	for player_index in players_data.size():
		var items: Array = players_data[player_index].items
		for i in range(items.size()):
			var item = items[i]
			# 只替换物品位；跳过角色（CharacterData 是 ItemData 子类）和武器
			if item is ItemData and not item is CharacterData:
				items[i] = m.get_replacement(item, player_index)
