extends PanelContainer

# 武器 / 难度选择界面：当前角色的偏好标签、禁用道具、异变预览；点击标签 / 禁用道具打开图鉴并筛选

const EXTRAS = "res://mods-unpacked/Mojimoon-BetterCodex/ui/extras.gd"

var extras
var codex


func setup(character) -> void:
	name = "BCCharacterInfo"
	rect_min_size.x = 300
	size_flags_vertical = SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	add_stylebox_override("panel", sb)
	var scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)
	extras = load(EXTRAS).new()
	scroll.add_child(extras)
	extras.reset_defaults()
	extras.mut_on = true
	extras.icon_size = 50	# 300 宽的面板一行放 5 个
	extras.show_item(character)
	extras.connect("tag_pressed", self, "_on_tag")
	extras.connect("banned_pressed", self, "_on_banned")
	call_deferred("_ensure_codex")


func _codex():
	_ensure_codex()
	codex._pop()
	return codex


# 先建好图鉴节点：它进树后会在后台预先构建，第一次点开就很快
func _ensure_codex() -> void:
	if codex == null or not is_instance_valid(codex):
		codex = load("res://ui/menus/pages/menu_codex.tscn").instance()
		codex.name = "MenuCodex"
		get_tree().current_scene.add_child(codex)


# 偏好标签：一个临时筛选，包含带任一偏好标签的道具
func _on_tag(_tag: String) -> void:
	var c = extras.item
	var items = []
	for it in ItemService.items:
		for t in it.tags:
			if c.wanted_tags.has(t):
				items.push_back(it)
				break
	_codex().bc_temp_filter("%s · %s" % [tr(c.name), tr("BC_PREFERRED_TAGS")], items)


func _on_banned(character, item) -> void:
	_codex().bc_temp_filter("%s · %s" % [tr(character.name), tr("BC_BANNED_ITEMS")], load(EXTRAS).banned_items(character), item)
