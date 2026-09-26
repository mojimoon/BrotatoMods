extends "res://ui/menus/shop/shop.gd"

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
