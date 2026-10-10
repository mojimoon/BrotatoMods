extends "res://singletons/item_service.gd"

# 禁用道具 / 武器：抽取商店 / 箱子物品时，临时把本角色档案里禁用的 id 加入玩家的禁用列表（原版"禁用"机制：
# 同时从主池和备用池移除），抽完立即还原，不影响原版的禁用次数统计与存档。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _get_rand_item_for_wave(wave: int, player_index: int, type: int, args: GetRandItemForWaveArgs) -> ItemParentData:
	var m = BEMain.get_mod()
	var extra = m.ban_hashes(player_index) if m != null else []
	if extra.empty():
		return ._get_rand_item_for_wave(wave, player_index, type, args)
	var banned: Array = RunData.players_data[player_index].banned_items
	var n = banned.size()
	banned.append_array(extra)
	var item = ._get_rand_item_for_wave(wave, player_index, type, args)
	banned.resize(n)
	return item
