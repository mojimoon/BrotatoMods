extends Node

# 商店：右键点商品 / 已有武器 / 道具，或悬停 / 聚焦时按快捷键（默认 C，可在图鉴设置里改；手柄 R3），打开图鉴并定位到它。
# 不改动物品弹窗（其他 mod 会往弹窗里加按钮、改焦点链，例如 ItemRefund），只监听输入。
# 左下角显示一行提示（含异变果能否掉落）。

const FONT = preload("res://resources/fonts/actual/base/font_22.tres")

var shop
var codex
var hint: Label


func _ready() -> void:
	hint = Label.new()
	hint.name = "BCShopHint"
	hint.add_font_override("font", FONT)
	hint.add_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.add_color_override("font_outline_modulate", Color.black)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_LEFT)
	hint.margin_left = 12
	hint.margin_top = -30
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	shop.add_child(hint)
	update_hint()
	var timer = Timer.new()	# 买卖道具后刷新异变果提示
	timer.wait_time = 0.5
	timer.autostart = true
	timer.connect("timeout", self, "update_hint")
	add_child(timer)


func _mod():
	return get_node_or_null("/root/ModLoader/Mojimoon-BetterCodex")


func hotkey() -> int:
	var m = _mod()
	return int(m.settings.get("hotkey", KEY_C)) if m != null else KEY_C


func update_hint() -> void:
	var text = tr("BC_SHOP_HINT").format([OS.get_scancode_string(hotkey())])
	var fruit = fruit_text()
	if fruit != "":
		text += " " + fruit
	hint.text = text


# 异变果：需要 DLC2；机械路线（双进化除外）不显示；道具不足时显示进度
static func fruit_text() -> String:
	if not "primal_dread" in ProgressData.active_update_data or RunData.players_data.empty():
		return ""
	var d = ItemService.get_dlc_data_by_id("primal_dread")
	if d == null or d.mutation_fruit == null:
		return ""
	var dual = RunData.is_dual_evolution(0)
	if not dual and (RunData.is_meca_only(0) or RunData.get_player_effect(Keys.stat_evolution_hash, 0) > ItemService.EVOLUTION_CAMP_LOCK_THRESHOLD):
		return ""
	var name = TranslationServer.translate(d.mutation_fruit.name)
	if d._has_enough_items_for_mutation_fruit():
		return TranslationServer.translate("BC_FRUIT_YES").format([name])
	var count = 0
	for it in RunData.players_data[0].get_list_of_items_that_can_get_mutated():
		if not it is CharacterData:
			count += 1
	return TranslationServer.translate("BC_FRUIT_NO").format([name, count, d.mutation_fruit_min_items])


func _input(event: InputEvent) -> void:
	var use_mouse = false
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_RIGHT:
		use_mouse = true
	elif event is InputEventKey and event.pressed and not event.echo and event.scancode == hotkey():
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
		codex.connect("codex_closed", self, "update_hint")
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
