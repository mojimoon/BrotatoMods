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


# 异变的阈值 / 公式直接取游戏的（1.2.0.2-beta 起最高值与公式会变）
static func mut_max() -> int:
	var d = dlc(DLC2)
	if d == null:
		return 150
	return int(d.get_script().get_script_constant_map().get("MUTATION_SCALE_MAX_EVOLUTION", 150.0))


# 临时把 P1 的若干效果设为指定值，调用游戏函数后恢复（用游戏自己的公式算预览值）
static func _with_effects(values: Dictionary, obj: Object, method: String, args: Array):
	var effects: Dictionary = RunData.players_data[0].effects
	var saved = {}
	for k in values:
		saved[k] = [effects.has(k), effects.get(k)]
		effects[k] = values[k]
	var r = obj.callv(method, args)
	for k in saved:
		if saved[k][0]:
			effects[k] = saved[k][1]
		else:
			effects.erase(k)
	return r


static func _with_evolution(evolution: float, obj: Object, method: String, args: Array):
	return _with_effects({Keys.stat_evolution_hash: evolution}, obj, method, args)


static func mut_scale(evolution: float) -> float:
	if not can_mutate():
		return 1.0
	return _with_evolution(evolution, dlc(DLC2), "get_mutation_scale", [0])


# 异变值为 evolution 时：可被复制的效果（已缩放的副本）、可被移除的负面效果、需要更高异变才能复制的效果 [效果, 最低异变]
static func mutation(item, evolution: int, with_later: bool = true) -> Dictionary:
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
		if not with_later:
			continue
		for v in range(evolution + 1, mut_max() + 1):
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


# ---- 价格：ItemService.get_value，去掉 P1 的价格效果；噩梦 = 噩梦难度数据里的 inflation_modifier ----

static func nightmare_inflation() -> int:
	for d in ItemService.difficulties:
		for e in d.effects:
			if e.key_hash == Keys.inflation_modifier_hash and e.value > 0:
				return int(e.value)
	return 0


static func price(base: int, wave: int, nightmare: bool, is_weapon: bool) -> int:
	if RunData.players_data.empty():
		return base
	var values = {
		Keys.weapons_price_hash: 0, Keys.items_price_hash: 0, Keys.specific_items_price_hash: [],
		Keys.inflation_modifier_hash: nightmare_inflation() if nightmare else 0,
	}
	return _with_effects(values, ItemService, "get_value", [wave, base, 0, true, is_weapon, Keys.empty_hash])


# 每波涨价（显示用）：前 20 波（无无尽加成）的平均值
static func price_increment(base: int, nightmare: bool, is_weapon: bool) -> float:
	return (price(base, 20, nightmare, is_weapon) - price(base, 0, nightmare, is_weapon)) / 20.0
