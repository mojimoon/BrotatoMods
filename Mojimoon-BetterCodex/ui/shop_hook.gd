extends Node

# 商店：右键点商品 / 已有武器 / 道具，或悬停 / 聚焦时按 C（手柄 R3），打开图鉴并定位到它。
# 不改动物品弹窗（其他 mod 会往弹窗里加按钮、改焦点链，例如 ItemRefund），只监听输入。

var shop
var codex


func _input(event: InputEvent) -> void:
	var use_mouse = false
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_RIGHT:
		use_mouse = true
	elif event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_C:
		use_mouse = true
	elif not (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_R3):
		return
	if codex != null and is_instance_valid(codex) and codex.visible:
		return
	var it = null
	if use_mouse:
		it = _item_at(shop, shop.get_global_mouse_position())
	if it == null and not (event is InputEventMouseButton):
		it = _item_of(shop.get_focus_owner())
	if it == null or it is CharacterData:
		return
	get_tree().set_input_as_handled()
	open(it)


func open(it) -> void:
	if codex == null or not is_instance_valid(codex):
		codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
		codex.name = "MenuCodex"
		shop.add_child(codex)
	codex._pop()
	codex.bc_open_item(it)


# 控件（或其祖先）对应的物品：商品卡片 ShopItem.item_data / 背包元素 InventoryElement.item
static func _item_of(node):
	while node != null and node is Control:
		if node is ShopItem:
			return node.item_data
		if node is InventoryElement:
			return node.item if node.item is ItemParentData else null
		node = node.get_parent()
	return null


static func _item_at(node: Node, pos: Vector2):
	for c in node.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if (c is ShopItem or c is InventoryElement) and c.get_global_rect().has_point(pos):
			var it = _item_of(c)
			if it != null:
				return it
		var found = _item_at(c, pos)
		if found != null:
			return found
	return null
