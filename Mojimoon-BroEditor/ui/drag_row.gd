extends PanelContainer

# 效果列表中可拖动排序的一行：按住行（按钮以外的地方）拖到另一行上松开即可移动，落在目标行的上半 / 下半决定插在前 / 后。

var editor = null
var index := -1


func get_drag_data(_pos: Vector2):
	if editor == null:
		return null
	var preview = PanelContainer.new()
	preview.add_stylebox_override("panel", get_stylebox("panel"))
	preview.rect_size = Vector2(rect_size.x, 0)
	var lbl = Label.new()
	lbl.text = editor.drag_text(index)
	lbl.add_font_override("font", editor.FONT_DESC)
	preview.add_child(lbl)
	preview.modulate.a = 0.8
	set_drag_preview(preview)
	return {"be_effect_row": index}


func can_drop_data(_pos: Vector2, data) -> bool:
	return data is Dictionary and data.has("be_effect_row") and editor != null


func drop_data(pos: Vector2, data) -> void:
	editor.move_effect_to(int(data.be_effect_row), index, pos.y > rect_size.y / 2.0)
