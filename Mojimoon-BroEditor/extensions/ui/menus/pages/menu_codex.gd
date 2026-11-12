extends "res://ui/menus/pages/menu_codex.gd"

# 图鉴：被本模组单独锁定的道具 / 武器显示解锁条件与说明（原版只显示 "???"）。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _on_InventoryItems_element_pressed(element: InventoryElement):
	._on_InventoryItems_element_pressed(element)
	_be_lock_text(element, $"%codex_item_description", inventory_items, "item")


func _on_InventoryWeapons_element_pressed(element: InventoryElement):
	._on_InventoryWeapons_element_pressed(element)
	_be_lock_text(element, $"%codex_weapon_description", inventory_weapons, "weapon")


func _be_lock_text(element, panel, inventory, kind: String) -> void:
	var m = BEMain.get_mod()
	if m == null or element == null or element.item == null or not element.item.is_locked:
		return
	var text = m.lock_text(kind, element.item.weapon_id if kind == "weapon" else element.item.my_id)
	if text != "":
		panel.set_custom_data("???\n" + text, inventory.locked_icon)
