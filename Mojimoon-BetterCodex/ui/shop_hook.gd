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


# 图鉴跨波次保留：离开商店时如果还开着就关掉（不留在下一个场景上）
func _exit_tree() -> void:
	if codex != null and is_instance_valid(codex) and codex.get("bc_persistent"):
		if codex.is_connected("codex_closed", self, "update_hint"):
			codex.disconnect("codex_closed", self, "update_hint")
		if codex.visible:
			codex._on_BackButton_pressed()
		if _mod() != null:
			_mod().call_deferred("shop_codex_detach")


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
	var text = tr("BC_SHOP_HINT" if _right_click() else "BC_SHOP_HINT_KEY").format([OS.get_scancode_string(hotkey())])
	var preview = []
	var fruit = ""
	for i in RunData.get_player_count():
		preview.push_back(mutation_preview_on(i))
		if fruit == "":
			fruit = fruit_text(i)	# 多人：数量是所有玩家共用的条件，显示第一个能获得异变果的玩家即可
	if fruit != "" and not fruit_can_drop():
		text += " " + fruit
	hint.text = text
	var m = _mod()
	hint.visible = m == null or m.settings.get("shop_hint", true)
	# 能否掉落变了：商品卡片的描述（带不带异变预览）重新生成；弹窗每次显示都会重新生成
	if _can_drop != null and str(preview) != _can_drop:
		for n in _all_nodes(shop):
			if n is ShopItem and n.item_data is ItemData and n.is_visible_in_tree():
				n._item_description.set_item(n.item_data, n.player_index)
	_can_drop = str(preview)


# 异变果：需要 DLC2；机械路线（双进化除外）不显示；道具不足时显示进度
# 是否显示异变预览（商店描述末尾、局内图鉴默认打开）：设置“启用异变预览”
#   默认 = 可掉落异变果；进化 <= 0 = 有 DLC2、不是强制机械路线、进化 <= 0；关 = 不显示
static func mutation_preview_on(p: int = 0) -> bool:
	var m = Engine.get_main_loop().root.get_node_or_null("ModLoader/Mojimoon-BetterCodex")
	var mode = str(m.settings.get("mut_preview", "default")) if m != null else "default"
	if mode == "off":
		return false
	if mode == "evo":
		return "primal_dread" in ProgressData.active_update_data and p < RunData.players_data.size() \
			and not RunData.is_meca_only(p) and RunData.get_player_effect(Keys.stat_evolution_hash, p) <= 0
	return fruit_can_drop(p)


static func fruit_can_drop(p: int = 0) -> bool:
	var d = ItemService.get_dlc_data_by_id("primal_dread")
	return fruit_text(p) != "" and fruit_count() >= d.mutation_fruit_min_items


# 同 DLC2Data._has_enough_items_for_mutation_fruit：任一玩家的可异变道具达到数量就可以掉落（多人共用）
static func fruit_count() -> int:
	var n = 0
	for i in RunData.get_player_count():
		n = max(n, RunData.bc_mutable_count(i))
	return n


# 数量用 RunData 扩展里增量维护的值（不每次遍历道具）；判断同 DLC2Data._has_enough_items_for_mutation_fruit（单人）
static func fruit_text(p: int = 0) -> String:
	if not "primal_dread" in ProgressData.active_update_data or p >= RunData.players_data.size():
		return ""
	var d = ItemService.get_dlc_data_by_id("primal_dread")
	if d == null or d.mutation_fruit == null:
		return ""
	var dual = RunData.is_dual_evolution(p)
	if not dual and (RunData.is_meca_only(p) or RunData.get_player_effect(Keys.stat_evolution_hash, p) > ItemService.EVOLUTION_CAMP_LOCK_THRESHOLD):
		return ""
	var name = TranslationServer.translate(d.mutation_fruit.name)
	var count = fruit_count()
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
	var node = null
	if use_mouse:
		node = _node_at(shop, shop.get_global_mouse_position())
	if node == null and not (event is InputEventMouseButton):
		node = _focused_node(event)
	var it = _item_of(node)
	if it == null or it is CharacterData:
		return
	get_tree().set_input_as_handled()
	open(it, _player_of(node))


# 多人：每个玩家有自己的 FocusEmulator，按键盘 / 手柄找到按键的玩家，取他聚焦的控件
func _focused_node(event: InputEvent):
	if not RunData.is_coop_run:
		return shop.get_focus_owner()
	var fallback = null
	for i in RunData.get_player_count():
		var pad = CoopService.is_player_using_gamepad(i)
		if pad != (event is InputEventJoypadButton):
			continue
		var fe = Utils.get_focus_emulator(i)
		var c = fe.focused_control if fe != null else null
		if _item_of(c) == null:
			continue
		if not pad or CoopService.get_remapped_player_device(i) == event.device:
			return c
		if fallback == null:
			fallback = c
	return fallback


func open(it, player: int = 0) -> void:
	_ensure_codex()
	if _mod() != null:
		codex = _mod().shop_codex()	# 放回场景树
	codex.bc_player = player
	codex.player_index = player	# 原版：手柄右摇杆滚动、LB / RB 图标
	codex._pop()
	codex.bc_open_item(it)


# 取跨波次保留的图鉴（mod_main.shop_codex），在进商店那一帧预先构建（内容没变时什么都不做），之后打开很快。
# 构建放在切换场景的加载帧里，不在玩家操作时卡顿
func _ensure_codex() -> void:
	if codex == null or not is_instance_valid(codex):
		var m = _mod()
		if m != null:
			codex = m.shop_codex()
		else:
			codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
			codex.name = "MenuCodex"
			shop.add_child(codex)
		if not codex.is_connected("codex_closed", self, "update_hint"):
			codex.connect("codex_closed", self, "update_hint")
		codex.bc_prewarm()
		if m != null:
			m.call_deferred("shop_codex_detach")	# 构建时排队的延迟调用先执行，再移出树


static func _all_nodes(node: Node) -> Array:
	var out = [node]
	for c in node.get_children():
		out += _all_nodes(c)
	return out


# 控件或其祖先中的商品卡片 ShopItem / 背包元素 InventoryElement
static func _entry_of(node):
	while node != null and node is Control:
		if node is ShopItem or node is InventoryElement:
			return node
		node = node.get_parent()
	return null


# 对应的物品：ShopItem.item_data / InventoryElement.item
static func _item_of(node):
	var e = _entry_of(node)
	if e is ShopItem:
		return e.item_data
	if e is InventoryElement and e.item is ItemParentData:
		return e.item
	return null


# 所属玩家（多人商店里每个玩家各有一组商品 / 背包）
static func _player_of(node) -> int:
	var e = _entry_of(node)
	return e.player_index if e != null else 0


static func _node_at(node: Node, pos: Vector2):
	for c in node.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if (c is ShopItem or c is InventoryElement) and c.get_global_rect().has_point(pos) and _item_of(c) != null:
			return c
		var found = _node_at(c, pos)
		if found != null:
			return found
	return null
