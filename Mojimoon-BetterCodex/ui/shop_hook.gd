extends Node

# 商店：右键点商品 / 已有武器 / 道具，或悬停 / 聚焦时按快捷键（默认 C，可在图鉴设置里改；手柄 R3），打开图鉴并定位到它。
# 不改动物品弹窗（其他 mod 会往弹窗里加按钮、改焦点链，例如 ItemRefund），只监听输入。
# 左下角显示跳转图鉴的提示，不可掉落异变果时附带道具数量（设置里可隐藏）；异变预览本身加在描述末尾（extensions/ui/menus/shop/item_description.gd）。

const Fonts = preload("res://mods-unpacked/Mojimoon-BetterCodex/ui/fonts.gd")

var shop
var codex
var hint: Label
var _can_drop = null


func _ready() -> void:
	hint = Label.new()
	hint.name = "BCShopHint"
	hint.add_font_override("font", Fonts.font(22))
	hint.add_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.add_color_override("font_outline_modulate", Color.black)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_LEFT)
	hint.margin_left = 12
	hint.margin_top = -30
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	shop.add_child(hint)
	var pause = shop.get_node_or_null("PauseMenu")
	if pause != null:	# 放在暂停菜单下面：暂停时被盖住
		shop.move_child(hint, pause.get_index())
	RunData.bc_reset_mutable_counts()	# 进商店时数一遍，之后随获得 / 失去道具增量更新
	update_hint()
	# 买道具（以及其他 mod 的回收）都会改变材料：随 gold_changed 刷新异变果提示
	RunData.connect("gold_changed", self, "_on_gold_changed")
	call_deferred("_ensure_codex")
	# var timer = Timer.new()
	# timer.wait_time = 5.0
	# timer.autostart = true
	# timer.connect("timeout", self, "update_hint")
	# add_child(timer)


func _on_gold_changed(_value, _player_index) -> void:
	call_deferred("update_hint")	# 买下的道具在扣钱之后才加入背包


func _mod():
	return get_node_or_null("/root/ModLoader/Mojimoon-BetterCodex")


# 设置里可关掉右键（只留快捷键）：关掉时完全不处理右键事件，避免与其他 mod 冲突
func _right_click() -> bool:
	var m = _mod()
	return m == null or m.settings.get("right_click", true)


func hotkey() -> int:
	var m = _mod()
	return int(m.settings.get("hotkey", KEY_C)) if m != null else KEY_C


# “右键或 C 跳转图鉴。”，不可掉落异变果时再加“不可掉落异变果（未诅咒道具 x/3）”；可在图鉴设置里隐藏
func update_hint() -> void:
	var can_drop = fruit_can_drop()
	var preview = mutation_preview_on()
	var text = tr("BC_SHOP_HINT" if _right_click() else "BC_SHOP_HINT_KEY").format([OS.get_scancode_string(hotkey())])
	var fruit = fruit_text()
	if fruit != "" and not can_drop:
		text += " " + fruit
	hint.text = text
	var m = _mod()
	hint.visible = m == null or m.settings.get("shop_hint", true)
	# 能否掉落变了：商品卡片的描述（带不带异变预览）重新生成；弹窗每次显示都会重新生成
	if _can_drop != null and preview != _can_drop:
		for n in _all_nodes(shop):
			if n is ShopItem and n.item_data is ItemData and n.is_visible_in_tree():
				n._item_description.set_item(n.item_data, 0)
	_can_drop = preview


# 异变果：需要 DLC2；机械路线（双进化除外）不显示；道具不足时显示进度
# 是否显示异变预览（商店描述末尾、局内图鉴默认打开）：设置“启用异变预览”
#   默认 = 可掉落异变果；进化 <= 0 = 有 DLC2、不是强制机械路线、进化 <= 0；关 = 不显示
static func mutation_preview_on() -> bool:
	var m = Engine.get_main_loop().root.get_node_or_null("ModLoader/Mojimoon-BetterCodex")
	var mode = str(m.settings.get("mut_preview", "default")) if m != null else "default"
	if mode == "off":
		return false
	if mode == "evo":
		return "primal_dread" in ProgressData.active_update_data and not RunData.players_data.empty() \
			and not RunData.is_meca_only(0) and RunData.get_player_effect(Keys.stat_evolution_hash, 0) <= 0
	return fruit_can_drop()


static func fruit_can_drop() -> bool:
	var d = ItemService.get_dlc_data_by_id("primal_dread")
	return fruit_text() != "" and RunData.bc_mutable_count(0) >= d.mutation_fruit_min_items


# 数量用 RunData 扩展里增量维护的值（不每次遍历道具）；判断同 DLC2Data._has_enough_items_for_mutation_fruit（单人）
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
	var count = RunData.bc_mutable_count(0)
	if count >= d.mutation_fruit_min_items:
		return TranslationServer.translate("BC_FRUIT_YES").format([name])
	return TranslationServer.translate("BC_FRUIT_NO").format([name, count, d.mutation_fruit_min_items])


func _input(event: InputEvent) -> void:
	var use_mouse = false
	if event is InputEventMouseButton:
		if not (event.pressed and event.button_index == BUTTON_RIGHT and _right_click()):
			return
		use_mouse = true
	elif event is InputEventKey and event.pressed and not event.echo and (event.scancode == hotkey() or event.physical_scancode == hotkey()):	# 物理键位也认：输入法 / 键盘布局可能改变 scancode
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
	_ensure_codex()
	codex._pop()
	codex.bc_open_item(it)


# 先建好图鉴节点：它进树后会在后台预先构建，第一次打开就很快
func _ensure_codex() -> void:
	if codex == null or not is_instance_valid(codex):
		codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
		codex.name = "MenuCodex"
		shop.add_child(codex)
		codex.connect("codex_closed", self, "update_hint")


static func _all_nodes(node: Node) -> Array:
	var out = [node]
	for c in node.get_children():
		out += _all_nodes(c)
	return out


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
