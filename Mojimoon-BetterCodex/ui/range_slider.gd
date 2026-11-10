extends HSlider

# 带高亮区间的滑条（诅咒：当前波次可能的强度范围）；lo > hi 时不画

var lo := 0.0
var hi := -1.0
var band_color := Color(0.66, 0.33, 0.97, 0.45)


func set_band(p_lo: float, p_hi: float) -> void:
	lo = p_lo
	hi = p_hi
	update()


func _draw() -> void:
	if hi < lo or max_value <= min_value:
		return
	var grabber = get_icon("grabber")
	var pad = grabber.get_width() / 2.0 if grabber != null else 8.0
	var w = rect_size.x - pad * 2.0
	var a = pad + w * (clamp(lo, min_value, max_value) - min_value) / (max_value - min_value)
	var b = pad + w * (clamp(hi, min_value, max_value) - min_value) / (max_value - min_value)
	var h = rect_size.y * 0.5
	draw_rect(Rect2(a, (rect_size.y - h) / 2.0, max(2.0, b - a), h), band_color)
