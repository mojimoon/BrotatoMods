extends Control

# 编辑器的弹窗：半透明遮罩 + 居中面板（标题行 + 内容 + 底部按钮行）。
# 打开的弹窗记在编辑器的 _modals 里，Esc 关闭最上面的一个。
#   open(ui, 标题, 颜色, 尺寸)：空弹窗，内容加到 body / foot
#   confirm(ui, [提示...], 颜色, 对象, 方法, 参数)：确认框；有几条提示就要依次确认几次，全部确认后调用 对象.方法(参数)

signal closed

var ui = null
var head: HBoxContainer
var body: VBoxContainer
var foot: HBoxContainer
var ok_button: Button
var _steps: Array = []
var _target: Object = null
var _method := ""
var _args: Array = []


static func open(p_ui, title: String, accent: Color, size: Vector2):
	var m = load("res://mods-unpacked/Mojimoon-BroEditor/ui/modal.gd").new()
	m._build(p_ui, title, accent, size)
	return m


static func confirm(p_ui, messages: Array, accent: Color, target: Object, method: String, args: Array = []):
	var m = open(p_ui, p_ui.tr("BE_CONFIRM_TITLE"), accent, Vector2(720, 0))
	m._steps = messages.duplicate()
	m._target = target
	m._method = method
	m._args = args
	m._show_step()
	return m


func _build(p_ui, title: String, accent: Color, size: Vector2) -> void:
	ui = p_ui
	set_anchors_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_WIDE)
	add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_WIDE)
	add_child(center)
	var panel = PanelContainer.new()
	panel.rect_min_size = size
	panel.add_stylebox_override("panel", ui._style(ui.C_BG_PANEL, accent, 12, 2, 18, 14))
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 10)
	panel.add_child(box)
	head = HBoxContainer.new()
	head.add_constant_override("separation", 10)
	box.add_child(head)
	var t = ui._label(title, ui.FONT_NORMAL, accent)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	body = VBoxContainer.new()
	body.add_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	foot = HBoxContainer.new()
	foot.add_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGN_END
	box.add_child(foot)
	ui.add_child(self)
	ui._modals.push_back(self)


# 底部按钮
func add_button(text: String, accent: Color, target: Object, method: String, args: Array = []) -> Button:
	var b = ui._button(text, ui.FONT_SMALL)
	ui._apply_action_style(b, accent)
	b.connect("pressed", target, method, args)
	foot.add_child(b)
	return b


func close() -> void:
	if is_queued_for_deletion():
		return
	ui._modals.erase(self)
	emit_signal("closed")
	queue_free()


# ---------------- 确认框 ----------------
func _show_step() -> void:
	for c in body.get_children() + foot.get_children():
		c.queue_free()
	var msg = ui._label(_steps[0], ui.FONT_SMALL, ui.C_TEXT)
	msg.autowrap = true
	msg.rect_min_size = Vector2(680, 0)
	body.add_child(msg)
	add_button(ui.tr("BE_CANCEL"), ui.C_TEXT_DIM, self, "close")
	ok_button = add_button(ui.tr("BE_CONFIRM"), ui.C_DANGER, self, "_on_ok")


func _on_ok() -> void:
	_steps.pop_front()
	if not _steps.empty():
		_show_step()
		return
	close()
	if _target != null and is_instance_valid(_target):
		_target.callv(_method, _args)
