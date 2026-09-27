extends "res://ui/menus/shop/coop_shop.gd"

# 商店阶段扳机：刷新商店 / 购买道具。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


func _on_RerollButton_pressed(player_index: int) -> void:
	var before = _reroll_count[player_index]
	._on_RerollButton_pressed(player_index)
	if _reroll_count[player_index] > before:
		var m = AAMain.get_mod()
		if m != null:
			m.fire_shop("reroll", player_index)


func buy_item(item_data: ItemData, player_index: int) -> void:
	.buy_item(item_data, player_index)
	var m = AAMain.get_mod()
	if m != null:
		m.fire_shop("buy", player_index)
	# 重组道具可能带有沙漏的"倒流"效果：购买后刷新"下一波"按钮上的波数
	update_go_next_button_text()


# 沙漏的"倒流"效果在原版里按沙漏的道具 ID 查找并移除持有者；出现在其他道具上时由这里处理：
# 暂时从效果计数中扣除这些道具的份额（避免原版找不到沙漏而出错），进入下一波后再倒退波数并移除持有者
func _on_GoButton_pressed(player_index: int) -> void:
	var pending = []
	for p in RunData.get_player_count():
		var holders = []
		var count = 0
		for it in RunData.get_player_items(p):
			if it.my_id_hash == Keys.item_hourglass_hash:
				continue
			for e in it.effects:
				if e.key_hash == Keys.item_hourglass_hash:
					holders.push_back(it)
					count += e.value
		if count > 0:
			RunData.get_player_effects(p)[Keys.item_hourglass_hash] -= count
			pending.push_back([p, holders, count])
	var wave_before = RunData.current_wave
	._on_GoButton_pressed(player_index)
	var advanced = RunData.current_wave != wave_before
	for entry in pending:
		RunData.get_player_effects(entry[0])[Keys.item_hourglass_hash] += entry[2]
		if advanced:
			RunData.current_wave -= entry[2]
			for it in entry[1]:
				RunData.remove_item(it, entry[0])
