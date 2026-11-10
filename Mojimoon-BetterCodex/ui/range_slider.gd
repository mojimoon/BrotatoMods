extends HSlider

# 带高亮区间的滑条（诅咒：当前波次可能的强度范围）：区间铺满滑轨内部的高度，滑块重新画在最上面；lo > hi 时不画

var lo := 0.0
var hi := -1.0
var band_color := Color(0.66, 0.33, 0.97, 0.55)


func set_band(p_lo: float, p_hi: float) -> void:
	lo = p_lo
	hi = p_hi
	update()


func _draw() -> void:
	if hi < lo or max_value <= min_value:
		return
	var style = get_stylebox("slider")
	var hovered = get_global_rect().has_point(get_global_mouse_position())
	var grabber = get_icon("grabber_highlight" if hovered or has_focus() else "grabber")
	var area = rect_size.x - grabber.get_width()
	# 滑轨实际画出的内部：居中的滑轨矩形（样式最小高度）+ 外扩边距 - 边框（游戏主题的滑轨就是靠外扩边距画粗的）
	var wh = style.get_minimum_size().y + style.get_center_size().y
	var inset = [0, 0, 0, 0]
	var top = (rect_size.y - wh) / 2.0
	var h = wh
	if style is StyleBoxFlat:
		inset = [style.border_width_left, style.border_width_top, style.border_width_right, style.border_width_bottom]
		top += -style.expand_margin_top + inset[1]
		h += style.expand_margin_top + style.expand_margin_bottom - inset[1] - inset[3]
	var a = max(_x_of(lo, area, grabber.get_width()), inset[0])
	var b = min(_x_of(hi, area, grabber.get_width()), rect_size.x - inset[2])
	if b > a and h > 0:
		draw_rect(Rect2(a, top, b - a, h), band_color)
	draw_texture(grabber, Vector2(round(get_as_ratio() * area), round((rect_size.y - grabber.get_height()) / 2.0)))


func _x_of(v: float, area: float, grabber_w: float) -> float:
	return (clamp(v, min_value, max_value) - min_value) / (max_value - min_value) * area + grabber_w / 2.0
