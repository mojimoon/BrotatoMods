extends VBoxContainer

# 详情面板下方的附加区块（图鉴道具 / 武器详情、武器 / 难度选择界面的角色信息共用）：
#   标签 / 武器类别 / 关联道具 / 禁用道具（可点击）、诅咒、机械化、异变、攻速计算器、价格计算
# 诅咒 / 机械化改变的是描述本身：发出 display_changed，由宿主用 display_item() 重新显示描述。

signal tag_pressed(tag)
signal set_pressed(set_id)
signal item_pressed(item)
signal banned_pressed(character, item)
signal display_changed

const Calc = preload("res://mods-unpacked/Mojimoon-BetterCodex/calc.gd")
const Preview = preload("res://mods-unpacked/Mojimoon-BetterCodex/preview.gd")
const RangeSlider = preload("res://mods-unpacked/Mojimoon-BetterCodex/ui/range_slider.gd")
const EFFECT_LINE = preload("res://items/global/effect_line.tscn")
const FONT = preload("res://resources/fonts/actual/base/font_22.tres")
const TITLE_COLOR = Color(0.92, 0.89, 0.69)
const DIM_COLOR = Color(0.65, 0.65, 0.65)
const CURSE_COLOR = Color("#b75cff")
const MECA_COLOR = Color("#3fcafc")
const MUTANT_COLOR = Color("#d2ff5e")
const MUTANT_DARK = Color("#5a8a00")	# 按钮文字用：按下 / 聚焦时浅底上黄绿色看不清
const PRICE_WAVES = [1, 5, 10, 15, 19]
const MECA_MAX = 80

var item = null
var in_run := false
var curse_on := false
var curse_pct := 110
var curse_band := []	# [低, 中位, 高]：当前波次可能的诅咒强度
var meca_on := false
var meca_power := 1
var mut_on := false
var mut_val := 150
var atk := 0
var stat_range := 0
var count := Calc.DEFAULT_WEAPON_COUNT
var wave := 0
var nightmare := false

var icon_size := 44	# 关联 / 禁用道具的图标按钮大小
var _syncing := false
var _curse_btn: Button
var _meca_btn: Button
var _mut_box: VBoxContainer
var _calc_text: RichTextLabel
var _price_text: RichTextLabel
var _value_labels := {}


func _init() -> void:
	add_constant_override("separation", 12)
	size_flags_horizontal = SIZE_EXPAND_FILL


static func scene_in_run(tree: SceneTree) -> bool:
	var s = tree.current_scene
	return s != null and s.name in ["Main", "Shop", "CoopShop"]


# 每次打开图鉴：局内用当前值（诅咒取本波中位数），局外用网页图鉴的默认值
func reset_defaults() -> void:
	in_run = scene_in_run(get_tree()) and not RunData.players_data.empty()
	curse_on = false
	meca_on = false
	mut_on = false
	meca_power = 1
	var dlc1 = Preview.dlc(Preview.DLC1)
	curse_band = Calc.curse_range(dlc1, RunData.current_wave) if in_run and dlc1 != null else []
	curse_pct = int(clamp(curse_band[1], 10, 110)) if curse_band.size() > 0 else 110
	if in_run:
		mut_val = int(clamp(abs(RunData.get_player_effect(Keys.stat_evolution_hash, 0)), 1, Preview.mut_max()))
		atk = int(Utils.get_stat(Keys.stat_attack_speed_hash, 0))
		stat_range = int(Utils.get_stat(Keys.stat_range_hash, 0))
		count = int(clamp(RunData.get_player_weapons_ref(0).size(), 1, 6))
		wave = RunData.current_wave
		nightmare = RunData.get_player_effect(Keys.inflation_modifier_hash, 0) > 0
	else:
		mut_val = Preview.mut_max()
		atk = 0
		stat_range = 0
		count = Calc.DEFAULT_WEAPON_COUNT
		wave = 0
		nightmare = false


# 描述里实际显示的物品（应用诅咒 / 机械化）
func display_item(base):
	if base == null:
		return null
	if meca_on and Preview.can_meca(base):
		return Preview.meca(base, meca_power)
	if curse_on and Preview.can_curse(base):
		return Preview.cursed(base, curse_pct)
	return base


func show_item(p_item) -> void:
	item = p_item
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_mut_box = null
	_calc_text = null
	_price_text = null
	_curse_btn = null
	_meca_btn = null
	_value_labels = {}
	visible = item != null
	if item == null:
		return
	_build_links()
	if Preview.can_curse(item):
		_build_curse()
	if item is WeaponData and Preview.can_meca(item):
		_build_meca()
	if not item is WeaponData and Preview.can_mutate():
		_build_mutation()
	if item is WeaponData:
		_build_calc()
	if has_price(item):
		_build_price()


static func has_price(it) -> bool:
	if it is CharacterData or it.value <= 1 or not it.can_be_looted:
		return false
	return it is WeaponData or it.max_nb != 0


static func tag_name(tag: String) -> String:
	var k = "BC_TAG_" + tag.to_upper()
	var t = TranslationServer.translate(k)
	return t if t != k else TranslationServer.translate(tag.to_upper())


# 角色的禁用道具：banned_item_groups（ItemService.item_groups）+ banned_items，只影响商店（非无尽波次）
static func banned_items(character) -> Array:
	var ids = []
	for g in character.banned_item_groups:
		for id in ItemService.item_groups.get(g, []):
			if not ids.has(id):
				ids.push_back(id)
	for id in character.banned_items:
		if not ids.has(id):
			ids.push_back(id)
	var out = []
	for it in ItemService.items:
		if ids.has(it.my_id):
			out.push_back(it)
	return out


# replaced_by 链（沙漏、金鱼、恐龙蛋 → 弹药恐龙……）
static func related_chain(it) -> Array:
	var prev = {}
	for x in ItemService.items:
		if x.replaced_by != null:
			prev[x.replaced_by.my_id] = x
	var root = it
	for _i in 20:
		if not prev.has(root.my_id):
			break
		root = prev[root.my_id]
	var chain = [root]
	while chain.back().replaced_by != null and chain.size() < 20:
		var nxt = null
		for x in ItemService.items:
			if x.my_id == chain.back().replaced_by.my_id:
				nxt = x
		if nxt == null or chain.has(nxt):
			break
		chain.push_back(nxt)
	return chain if chain.size() > 1 else []


# ---- 控件工具 ----

func _label(text: String, color = null) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", FONT)
	l.autowrap = true
	if color != null:
		l.add_color_override("font_color", color)
	return l


func _rich() -> RichTextLabel:
	var r = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content_height = true
	r.scroll_active = false
	r.size_flags_horizontal = SIZE_EXPAND_FILL
	r.add_font_override("normal_font", FONT)
	return r


func _button(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.add_font_override("font", FONT)
	b.connect("pressed", self, method, args)
	return b


func _icon_button(it, method: String, args: Array) -> Button:
	var b = Button.new()
	b.icon = it.get_icon()
	b.expand_icon = true
	b.rect_min_size = Vector2(icon_size, icon_size)
	b.hint_tooltip = tr(it.name)
	var sb = StyleBoxFlat.new()
	ItemService.change_inventory_element_stylebox_from_tier(sb, it.tier, 0.25)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:	# 当前道具是 disabled：不覆盖的话主题的边距会把图标挤小
		b.add_stylebox_override(s, sb)
	b.connect("pressed", self, method, args)
	return b


func _flow() -> Container:
	var f = ClassDB.instance("HFlowContainer") if ClassDB.class_exists("HFlowContainer") else HBoxContainer.new()
	f.size_flags_horizontal = SIZE_EXPAND_FILL
	return f


func _section(title: String = "") -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 6)
	add_child(box)
	if title != "":
		box.add_child(_label(title, TITLE_COLOR))
	return box


# [标签/开关] [滑条] [数值]
func _slider_row(parent: Control, head: Control, key: String, lo: int, hi: int, value: int, method: String, suffix: String = ""):
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	head.rect_min_size.x = 90
	if head is Label:
		head.autowrap = false
	row.add_child(head)
	var s = RangeSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.rect_min_size = Vector2(110, 28)
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.connect("value_changed", self, method)
	row.add_child(s)
	var v = _label(str(value) + suffix)
	v.autowrap = false
	v.rect_min_size.x = 48
	row.add_child(v)
	_value_labels[key] = [v, suffix]
	parent.add_child(row)
	return s


func _set_value_label(key: String, value) -> void:
	if _value_labels.has(key):
		_value_labels[key][0].text = str(value) + _value_labels[key][1]


func _toggle(text: String, on: bool, method: String, color: Color) -> Button:
	var b = Button.new()
	b.text = text
	b.toggle_mode = true
	b.pressed = on
	b.add_font_override("font", FONT)
	for k in ["font_color_pressed", "font_color_hover_pressed"]:
		b.add_color_override(k, color)
	b.connect("toggled", self, method)
	return b


func _add_effect(parent: Control, effect, removed: bool = false, suffix: String = "") -> void:
	var line = EFFECT_LINE.instance()
	parent.add_child(line)
	line._display_effect(0, effect, true, true, removed)
	if suffix != "" and not line.is_queued_for_deletion():
		line.text_descr.bbcode_text += suffix


# ---- 区块 ----

func _build_links() -> void:
	if item is CharacterData:
		if item.wanted_tags.size() > 0:
			var box = _section(tr("BC_PREFERRED_TAGS"))
			var f = _flow()
			for tag in item.wanted_tags:
				f.add_child(_button(tag_name(tag), "_on_tag", [tag]))
			box.add_child(f)
		var banned = banned_items(item)
		if banned.size() > 0:
			var box = _section()
			box.add_child(_button("%s (%d)" % [tr("BC_BANNED_ITEMS"), banned.size()], "_on_banned", [null]))
			var f = _flow()
			for it in banned:
				f.add_child(_icon_button(it, "_on_banned", [it]))
			box.add_child(f)
	elif item is WeaponData:
		pass	# 武器类型 / 类别显示在图鉴标题下（menu_codex 扩展）
	else:
		# 道具标签显示在图鉴标题下的类别行（menu_codex 扩展）
		var chain = related_chain(item)
		if chain.size() > 0:
			var box = _section(tr("BC_RELATED"))
			var f = _flow()
			for it in chain:
				var b = _icon_button(it, "_on_related", [it])
				b.disabled = it.my_id == item.my_id
				f.add_child(b)
			box.add_child(f)


func _build_curse() -> void:
	var box = _section()
	_curse_btn = _toggle(tr("BC_CURSE"), curse_on, "_on_curse_toggled", CURSE_COLOR)
	var s = _slider_row(box, _curse_btn, "curse", 10, 110, curse_pct, "_on_curse_slid", "%")
	s.band_color = Color(CURSE_COLOR.r, CURSE_COLOR.g, CURSE_COLOR.b, 0.45)
	if curse_band.size() > 0:
		s.set_band(curse_band[0], curse_band[2])
		box.add_child(_label(tr("BC_CURSE_WAVE").format([curse_band[0], curse_band[2]]), CURSE_COLOR))


func _build_meca() -> void:
	var box = _section()
	_meca_btn = _toggle(tr("BC_MECHA"), meca_on, "_on_meca_toggled", MECA_COLOR)
	_slider_row(box, _meca_btn, "meca", 1, MECA_MAX, meca_power, "_on_meca_slid")


func _build_mutation() -> void:
	var box = _section()
	_slider_row(box, _toggle(tr("BC_MUTATION"), mut_on, "_on_mut_toggled", MUTANT_DARK), "mut", 1, Preview.mut_max(), mut_val, "_on_mut_slid")
	_mut_box = VBoxContainer.new()
	box.add_child(_mut_box)
	_refresh_mutation()


func _refresh_mutation() -> void:
	if _mut_box == null:
		return
	for c in _mut_box.get_children():
		_mut_box.remove_child(c)
		c.queue_free()
	if not mut_on:
		return
	var shown = display_item(item)	# 开着诅咒时：复制的基础值取诅咒后的
	var info = Preview.mutation(shown, mut_val)
	# _mut_box.add_child(_label("%s x%s" % [tr("BC_MUT_SCALE"), str(stepify(Preview.mut_scale(mut_val), 0.01))], DIM_COLOR))
	if info.copy.empty():
		_mut_box.add_child(_label(tr("BC_NO_MUT_COPY"), DIM_COLOR))
	else:
		_mut_box.add_child(_label(tr("BC_MUT_COPY"), MUTANT_COLOR))
		for e in info.copy:
			_add_effect(_mut_box, e)
	for pair in info.later:
		_add_effect(_mut_box, pair[0], false, " [color=#%s](%s)[/color]" % [DIM_COLOR.to_html(false), tr("BC_MUT_NEED").format([pair[1]])])
	if not item is CharacterData and ItemService.can_item_be_mutated(shown) and not info.remove.empty():
		_mut_box.add_child(_label(tr("BC_MUT_REMOVE"), MUTANT_COLOR))
		for e in info.remove:
			_add_effect(_mut_box, e, true)


func _build_calc() -> void:
	var box = _section(tr("BC_ATTACK_SPEED_CALC"))
	_calc_text = _rich()
	box.add_child(_calc_text)
	_slider_row(box, _label(tr("BC_ATTACK_SPEED")), "atk", -100, 600, atk, "_on_atk_slid")
	if Calc.is_melee(item.stats):
		_slider_row(box, _label(tr("BC_STAT_RANGE")), "range", -200, 200, stat_range, "_on_range_slid")
	_slider_row(box, _label(tr("BC_WEAPON_COUNT")), "count", 1, 6, count, "_on_count_slid")
	_refresh_calc()


func _refresh_calc() -> void:
	if _calc_text == null:
		return
	var s = item.stats
	var a = (atk + s.attack_speed_mod) / 100.0
	var t = Calc.timing(s, a, stat_range, count)
	var every = tr("BC_EVERY_SHOTS").replace("{shots}", str(t.shots))
	var dim = "[color=#%s]" % DIM_COLOR.to_html(false)
	var txt = "%s: %s" % [tr("BC_TOOLTIP_CD"), Calc.cooldown_str(t.tooltip)]
	if t.shots > 0:
		txt += " %s/ %s %s[/color]" % [dim, every, Calc.cooldown_str(t.reload_tooltip)]
	txt += "\n%s: [color=#ffffff]%s[/color] %s(%d-%d %s)[/color]" % [tr("BC_ACTUAL_CD"), Calc.actual_str(t.avg), dim, t.min, t.max, tr("BC_FRAMES")]
	if t.shots > 0:
		txt += " %s/ %s %s / %s %s[/color]" % [dim, every, Calc.actual_str(t.reload), tr("BC_EQUIV"), Calc.cooldown_str(Calc.effective_seconds(t))]
	var pct = Calc.dps_change(s, a, stat_range, count)
	var col = "#%s" % (ProgressData.settings.color_positive if pct > 0.05 else ProgressData.settings.color_negative if pct < -0.05 else "ffffff")
	txt += " [color=%s](DPS %s%s%%)[/color]" % [col, "+" if pct >= 0 else "", str(stepify(pct, 0.1))]
	var bps = Calc.breakpoints(s, stat_range, count)
	if bps.size() > 0:
		var parts = []
		for bp in bps:
			parts.push_back("%d: +%s%%" % [bp[0], str(stepify(bp[1], 0.1))])
		txt += "\n%s: %s%s[/color]" % [tr("BC_BREAKPOINTS"), dim, ", ".join(parts)]
	_calc_text.bbcode_text = txt


func _build_price() -> void:
	var box = _section(tr("BC_PRICE"))
	_price_text = _rich()
	box.add_child(_price_text)
	_slider_row(box, _label(tr("BC_WAVE")), "wave", 0, 40, wave, "_on_wave_slid")
	var nm = _toggle(tr("BC_NIGHTMARE"), nightmare, "_on_nightmare_toggled", Color("#ff6b6b"))
	nm.size_flags_horizontal = 0
	box.add_child(nm)
	_refresh_price()


func _refresh_price() -> void:
	if _price_text == null:
		return
	var v = item.value
	var w_ = item is WeaponData
	var dim = "[color=#%s]" % DIM_COLOR.to_html(false)
	var txt = "%s %d: [color=#ffffff]%d[/color] %s(+%s%s)[/color]" % [tr("BC_WAVE"), wave, Preview.price(v, wave, nightmare, w_), dim, str(stepify(Preview.price_increment(v, nightmare, w_), 0.01)), tr("BC_PER_WAVE")]
	var parts = []
	for w in PRICE_WAVES:
		parts.push_back("%d: %d" % [w, Preview.price(v, w, nightmare, w_)])
	txt += "\n" + dim + "   ".join(parts) + "[/color]"
	if in_run:
		var cur = ItemService.get_value(RunData.current_wave, v, 0, true, item is WeaponData, item.my_id_hash)
		txt += "\n%s: [color=#ffffff]%d[/color]" % [tr("BC_CURRENT_PRICE"), cur]
	_price_text.bbcode_text = txt


# ---- 回调 ----

func _on_tag(tag: String) -> void:
	emit_signal("tag_pressed", tag)


func _on_set(set_id: String) -> void:
	emit_signal("set_pressed", set_id)


func _on_related(it) -> void:
	emit_signal("item_pressed", it)


func _on_banned(it) -> void:
	emit_signal("banned_pressed", item, it)


func _on_curse_toggled(on: bool) -> void:
	if _syncing:
		return
	curse_on = on
	if on and meca_on:
		meca_on = false
		_sync(_meca_btn, false)
	emit_signal("display_changed")
	_refresh_mutation()


func _on_meca_toggled(on: bool) -> void:
	if _syncing:
		return
	meca_on = on
	if on and curse_on:
		curse_on = false
		_sync(_curse_btn, false)
	emit_signal("display_changed")


func _sync(b: Button, on: bool) -> void:
	if b == null:
		return
	_syncing = true
	b.pressed = on
	_syncing = false


func _on_curse_slid(v: float) -> void:
	curse_pct = int(v)
	_set_value_label("curse", curse_pct)
	if curse_on:
		emit_signal("display_changed")
		_refresh_mutation()


func _on_meca_slid(v: float) -> void:
	meca_power = int(v)
	_set_value_label("meca", meca_power)
	if meca_on:
		emit_signal("display_changed")


func _on_mut_toggled(on: bool) -> void:
	mut_on = on
	_refresh_mutation()


func _on_mut_slid(v: float) -> void:
	mut_val = int(v)
	_set_value_label("mut", mut_val)
	_refresh_mutation()


func _on_atk_slid(v: float) -> void:
	atk = int(v)
	_set_value_label("atk", atk)
	_refresh_calc()


func _on_range_slid(v: float) -> void:
	stat_range = int(v)
	_set_value_label("range", stat_range)
	_refresh_calc()


func _on_count_slid(v: float) -> void:
	count = int(v)
	_set_value_label("count", count)
	_refresh_calc()


func _on_wave_slid(v: float) -> void:
	wave = int(v)
	_set_value_label("wave", wave)
	_refresh_price()


func _on_nightmare_toggled(on: bool) -> void:
	nightmare = on
	_refresh_price()
