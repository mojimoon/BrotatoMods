extends Node

# 商店：右键点商品 / 已有武器 / 道具，或悬停 / 聚焦时按快捷键（默认 C，可在图鉴设置里改；手柄 R3），打开图鉴并定位到它。
# 不改动物品弹窗（其他 mod 会往弹窗里加按钮、改焦点链，例如 ItemRefund），只监听输入。
# 左下角显示一行提示（含异变果能否掉落）；可掉落异变果时，悬停角色 / 已有道具，在物品弹窗旁显示哪些效果可被复制 / 清除。

const FONT = preload("res://resources/fonts/actual/base/font_22.tres")
const EFFECT_LINE = preload("res://items/global/effect_line.tscn")
const Preview = preload("res://mods-unpacked/Mojimoon-BetterCodex/preview.gd")
const MUTANT_COLOR = Color("#d2ff5e")

var shop
var codex
var hint: Label
var mut_panel: PanelContainer
var _mut_for = null	# 异变预览当前对应的物品
var _can_drop := false


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
	# 买道具（以及其他 mod 的回收）都会改变材料：随 gold_changed 刷新异变果提示
	RunData.connect("gold_changed", self, "_on_gold_changed")
	# var timer = Timer.new()
	# timer.wait_time = 5.0
	# timer.autostart = true
	# timer.connect("timeout", self, "update_hint")
	# add_child(timer)
	mut_panel = PanelContainer.new()
	mut_panel.name = "BCMutationPreview"
	mut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mut_panel.rect_min_size.x = 380
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.08, 0.92)
	sb.border_color = MUTANT_COLOR
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for m in [MARGIN_LEFT, MARGIN_TOP, MARGIN_RIGHT, MARGIN_BOTTOM]:
		sb.set_default_margin(m, 12)
	mut_panel.add_stylebox_override("panel", sb)
	mut_panel.visible = false
	shop.add_child(mut_panel)


func _on_gold_changed(_value, _player_index) -> void:
	call_deferred("update_hint")	# 买下的道具在扣钱之后才加入背包


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
	_can_drop = fruit_can_drop()


# 单人：P1 的物品弹窗显示角色 / 已有道具时，在旁边显示异变预览（当前异变值）
func _process(_delta: float) -> void:
	if RunData.is_coop_run or not shop.has_method("_get_item_popup"):
		return
	var popup = shop._get_item_popup(0)
	var it = null
	if _can_drop and popup != null and popup.visible and popup._is_inventory_element and popup._item_data is ItemData:
		it = popup._item_data
	if it != _mut_for:
		_mut_for = it
		_build_mutation(it)
	if it != null:
		var r = popup.get_global_rect()
		var view = shop.get_viewport_rect().size
		var x = r.position.x - mut_panel.rect_size.x - 8 if r.position.x + r.size.x / 2.0 > view.x / 2.0 else r.end.x + 8
		mut_panel.rect_global_position = Vector2(clamp(x, 0, view.x - mut_panel.rect_size.x), clamp(r.position.y, 0, view.y - mut_panel.rect_size.y))


func _build_mutation(it) -> void:
	for c in mut_panel.get_children():
		mut_panel.remove_child(c)
		c.queue_free()
	mut_panel.visible = it != null
	if it == null:
		return
	var evolution = int(abs(RunData.get_player_effect(Keys.stat_evolution_hash, 0)))
	var info = Preview.mutation(it, evolution)
	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mut_panel.add_child(box)	# 先进树：EffectLine 的 onready 变量在 _ready 后才有
	box.add_child(_label("%s %d · %s x%s" % [tr("BC_MUTATION"), evolution, tr("BC_MUT_SCALE"), str(stepify(Preview.mut_scale(evolution), 0.01))], MUTANT_COLOR))
	if info.copy.empty():
		box.add_child(_label(tr("BC_NO_MUT_COPY"), Color(0.65, 0.65, 0.65)))
	else:
		box.add_child(_label(tr("BC_MUT_COPY"), MUTANT_COLOR))
		for e in info.copy:
			_add_effect(box, e)
	if not it is CharacterData and ItemService.can_item_be_mutated(it) and not info.remove.empty():
		box.add_child(_label(tr("BC_MUT_REMOVE"), MUTANT_COLOR))
		for e in info.remove:
			_add_effect(box, e, true)
	mut_panel.rect_size = Vector2.ZERO	# 按内容重新计算大小


func _label(text: String, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.autowrap = true
	l.add_font_override("font", FONT)
	l.add_color_override("font_color", color)
	return l


func _add_effect(parent: Control, effect, removed: bool = false) -> void:
	var line = EFFECT_LINE.instance()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	line._display_effect(0, effect, true, true, removed)


# 异变果：需要 DLC2；机械路线（双进化除外）不显示；道具不足时显示进度
static func fruit_can_drop() -> bool:
	var d = ItemService.get_dlc_data_by_id("primal_dread")
	return fruit_text() != "" and d._has_enough_items_for_mutation_fruit()


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
