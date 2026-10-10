extends "res://ui/menus/shop/base_shop.gd"

func _on_tree_exited() -> void:
	._on_tree_exited()

    for player_index in range(RunData.get_player_count()):
        var locked_items: Array = RunData.locked_shop_items[player_index]
        var pityed: bool = false

        for i in locked_items.size():
            if not locked_items[i][0].is_cursed:
                for dlc_id in RunData.enabled_dlcs:
                    var dlc_data = ProgressData.get_dlc_data(dlc_id)
                    if dlc_data and dlc_data.has_method("curse_item"):
                        locked_items[i][0] = dlc_data.curse_item(locked_items[i][0], player_index)
                        pityed = true
        
        if pityed:
            RunData.players_data[player_index].curse_locked_shop_items_pity = 0
            RunData.set_tracked_value(player_index, Keys.item_fish_hook_hash, RunData.players_data[player_index].curse_locked_shop_items_pity)
