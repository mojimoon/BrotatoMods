extends Reference

# 诅咒 / 机械化 / 异变预览：直接调用游戏 DLC 数据里的函数，结果与实际游戏一致。

const DLC1 = "abyssal_terrors"
const DLC2 = "primal_dread"


static func dlc(id: String):
	if not ProgressData.available_dlc_ids.has(id):
		return null
	return ItemService.get_dlc_data_by_id(id)


static func can_curse(item) -> bool:
	return dlc(DLC1) != null and ItemService.can_item_be_cursed(item) and not item is CharacterData


static func can_meca(item) -> bool:
	return dlc(DLC2) != null and ItemService.can_weapon_be_mechanized(item)


static func can_mutate() -> bool:
	return dlc(DLC2) != null and not RunData.players_data.empty()


# 诅咒强度固定为 pct%（DLC1Data.curse_item 关闭随机后强度 = 基础 + 每波增量 × min(20, -1)，临时把增量设为 0）
static func cursed(item, pct: int):
	var d = dlc(DLC1)
	var base = d.cursed_item_base_percent_modifier
	var inc = d.cursed_item_percent_modifier_increase_each_wave
	d.cursed_item_base_percent_modifier = pct
	d.cursed_item_percent_modifier_increase_each_wave = 0
	var out = d.curse_item(item, 0, true)
	d.cursed_item_base_percent_modifier = base
	d.cursed_item_percent_modifier_increase_each_wave = inc
	return out


# 机械化强度 power（DLC2Data.apply_meca_power）
static func meca(weapon, power: int):
	var w = weapon.duplicate()
	w.is_meca = true
	dlc(DLC2).apply_meca_power(w, power)
	return w


# 异变值为 evolution 时：可被复制的效果（已缩放的副本）、可被移除的负面效果、需要更高异变才能复制的效果 [效果, 最低异变]
static func mutation(item, evolution: int) -> Dictionary:
	var out = {"copy": [], "remove": [], "later": []}
	if not can_mutate():
		return out
	var d = dlc(DLC2)
	var effects: Dictionary = RunData.players_data[0].effects
	var key = Keys.stat_evolution_hash
	var had = effects.has(key)
	var old = effects.get(key)
	for e in item.effects:
		if e is EffectOption:
			continue
		effects[key] = evolution
		if d.can_effect_be_copied_by_mutation(e, 0):
			var c = e.duplicate()
			c.added_by_mutation = true
			d._scale_copied_effect(c, 0)
			if d.mutation_marker_text_keys.has(c.key_hash):
				c.text_key = d.mutation_marker_text_keys[c.key_hash]
			out.copy.push_back(c)
			continue
		for v in range(evolution + 1, int(d.MUTATION_SCALE_MAX_EVOLUTION) + 1):
			effects[key] = v
			if d.can_effect_be_copied_by_mutation(e, 0):
				out.later.push_back([e, v])
				break
	if had:
		effects[key] = old
	else:
		effects.erase(key)
	for i in d._get_removable_negative_effect_indexes(item):
		out.remove.push_back(item.effects[i])
	return out
