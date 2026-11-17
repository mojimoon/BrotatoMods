extends "res://ui/menus/shop/coop_shop.gd"

# 商店阶段扳机：刷新商店 / 购买。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _on_RerollButton_pressed(player_index: int) -> void:
	var before = _reroll_count[player_index]
	._on_RerollButton_pressed(player_index)
	var m = BEMain.get_mod()
	if m != null and _reroll_count[player_index] > before:
		m.fire_shop("reroll", player_index)


func buy_item(item_data: ItemData, player_index: int) -> void:
	.buy_item(item_data, player_index)
	var m = BEMain.get_mod()
	if m != null:
		m.fire_shop("buy", player_index)


# 蓝图扳机"锁定并离开商店时" / "锁定的商品被诅咒时"（原版鱼钩在这里诅咒锁定的商品）
func _on_tree_exited() -> void:
	var m = BEMain.get_mod()
	var snap = m.runtime.locked_leave() if m != null and m.runtime != null else null
	._on_tree_exited()
	if snap != null:
		m.runtime.locked_cursed(snap)
