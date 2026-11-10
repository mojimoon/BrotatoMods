extends "res://ui/menus/shop/item_description.gd"

# BetterCodex：商店里（单人）可掉落异变果时，在道具 / 角色描述的最后加一段异变预览（当前异变值下可复制 / 可清除的效果），
# 前面是一条明显的分割线。行都加在效果列表里，下次 set_item 时随原版清空效果列表一起删掉。
# ImprovedTooltips 也扩展本脚本（改写效果行的生成）；这里只在 set_item 之后追加，先后顺序都不影响。

const BC_DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"
const BC_MUTANT_COLOR = Color("#d2ff5e")


func set_item(item_data: ItemParentData, player_index: int, item_count: = 1) -> void:
	.set_item(item_data, player_index, item_count)
	_bc_add_mutation_preview(item_data, player_index)


func _bc_add_mutation_preview(item_data, player_index: int) -> void:
	if not item_data is ItemData or RunData.is_coop_run or RunData.players_data.empty():
		return
	if find_parent("Shop") == null:
		return
	if not load(BC_DIR + "ui/shop_hook.gd").fruit_can_drop():
		return
	var Preview = load(BC_DIR + "preview.gd")
	var evolution = int(abs(RunData.get_player_effect(Keys.stat_evolution_hash, player_index)))
	var info = Preview.mutation(item_data, evolution, false)
	var box = get_effects()

	var sep = HSeparator.new()
	var line = StyleBoxLine.new()
	line.color = BC_MUTANT_COLOR
	line.thickness = 1
	sep.add_stylebox_override("separator", line)
	sep.add_constant_override("separation", 14)
	box.add_child(sep)
	# box.add_child(_bc_label("%s %d · %s x%s" % [tr("BC_MUTATION"), evolution, tr("BC_MUT_SCALE"), str(stepify(Preview.mut_scale(evolution), 0.01))]))
	box.add_child(_bc_label("%s x%s" % [tr("BC_MUTATION"), str(stepify(Preview.mut_scale(evolution), 0.01))]))
	if info.copy.empty():
		box.add_child(_bc_label(tr("BC_NO_MUT_COPY"), Color(0.65, 0.65, 0.65)))
	else:
		box.add_child(_bc_label(tr("BC_MUT_COPY")))
		for e in info.copy:
			_bc_add_effect(box, e, player_index)
	# 诅咒道具不能被异变：效果仍可被复制，但负面效果不会被清除
	if not item_data is CharacterData and ItemService.can_item_be_mutated(item_data) and not info.remove.empty():
		box.add_child(_bc_label(tr("BC_MUT_REMOVE")))
		for e in info.remove:
			_bc_add_effect(box, e, player_index, true)


func _bc_label(text: String, color: Color = BC_MUTANT_COLOR) -> Label:
	var l = Label.new()
	l.text = text
	l.autowrap = true
	l.add_font_override("font", load("res://resources/fonts/actual/base/font_smallest_text.tres"))
	l.add_color_override("font_color", color)
	return l


func _bc_add_effect(box: Control, effect, player_index: int, removed: bool = false) -> void:
	var line = effect_line.instance()
	box.add_child(line)
	line._display_effect(player_index, effect, true, true, removed)
