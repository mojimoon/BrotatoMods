extends Reference

# 异变预览的显示（商店描述末尾与图鉴的异变开关下共用）：分割线 + “异变可复制 x0.26” + 效果行 + “异变可清除” + 效果行
# with_later：图鉴里另外列出需要更高异变才能复制的效果（“需异变≥N”）

const Preview = preload("res://mods-unpacked/Mojimoon-BetterCodex/preview.gd")
const EFFECT_LINE = preload("res://items/global/effect_line.tscn")
const FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const MUTANT_COLOR = Color("#d2ff5e")
const DIM_COLOR = Color(0.65, 0.65, 0.65)


# box 必须已经在场景树里（EffectLine 的 onready 变量在 _ready 后才有）
static func build(box: Control, item, evolution: int, player_index: int, with_later: bool = false) -> void:
	var sep = HSeparator.new()
	var line = StyleBoxLine.new()
	line.color = MUTANT_COLOR
	line.thickness = 1
	sep.add_stylebox_override("separator", line)
	sep.add_constant_override("separation", 14)
	box.add_child(sep)

	var info = Preview.mutation(item, evolution, with_later)
	var scale = " x" + str(stepify(Preview.mut_scale(evolution), 0.01))
	if info.copy.empty():
		box.add_child(_label(TranslationServer.translate("BC_NO_MUT_COPY") + scale, DIM_COLOR))
	else:
		box.add_child(_label(TranslationServer.translate("BC_MUT_COPY") + scale, MUTANT_COLOR))
		for e in info.copy:
			_add_effect(box, e, player_index)
	for pair in info.later:
		_add_effect(box, pair[0], player_index, false, " [color=#%s](%s)[/color]" % [DIM_COLOR.to_html(false), TranslationServer.translate("BC_MUT_NEED").format([pair[1]])])
	# 诅咒（不能被异变）的道具与角色：效果仍可被复制，但不会被清除
	if not item is CharacterData and ItemService.can_item_be_mutated(item) and not info.remove.empty():
		box.add_child(_label(TranslationServer.translate("BC_MUT_REMOVE"), MUTANT_COLOR))
		for e in info.remove:
			_add_effect(box, e, player_index, true)


static func _label(text: String, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.autowrap = true
	l.add_font_override("font", FONT)
	l.add_color_override("font_color", color)
	return l


static func _add_effect(box: Control, effect, player_index: int, removed: bool = false, suffix: String = "") -> void:
	var line = EFFECT_LINE.instance()
	box.add_child(line)
	line._display_effect(player_index, effect, true, true, removed)
	if suffix != "" and not line.is_queued_for_deletion():
		line.text_descr.bbcode_text += suffix
