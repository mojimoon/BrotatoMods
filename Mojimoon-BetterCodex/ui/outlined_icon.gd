extends Control

# 带黑色描边的小图标（列表角标）：先在 8 个方向画黑色剪影，再画着色的图标

var texture: Texture
var color := Color.white
var outline := 1.5


func _init(p_texture: Texture = null, p_color: Color = Color.white, size: float = 22.0) -> void:
	texture = p_texture
	color = p_color
	rect_min_size = Vector2(size, size)
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	if texture == null:
		return
	var ts = texture.get_size()
	var s = min((rect_size.x - outline * 2) / ts.x, (rect_size.y - outline * 2) / ts.y)
	var r = Rect2((rect_size - ts * s) / 2.0, ts * s)
	for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1)]:
		draw_texture_rect(texture, Rect2(r.position + d * outline, r.size), false, Color.black)
	draw_texture_rect(texture, r, false, color)
