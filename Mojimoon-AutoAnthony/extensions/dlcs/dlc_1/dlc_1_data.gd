extends "res://dlcs/dlc_1/dlc_1_data.gd"

# 诅咒（深海魔怪 DLC）：原版逐条加强效果的主数值（正面加强、负面减弱）。
# 东尼算法的"同扳机正负成对"条款还带有负面部分 side_value，原版不认识它——这里按诅咒系数同样减弱。

const AATriggerEffect = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd")


func curse_item(item_data: ItemParentData, player_index: int, turn_randomization_off: bool = false, min_modifier: float = 0.0) -> ItemParentData:
	var was_cursed = item_data.is_cursed
	var out = .curse_item(item_data, player_index, turn_randomization_off, min_modifier)
	if was_cursed or out == null:
		return out
	for e in out.effects:
		if e is AATriggerEffect and e.side_value != 0:
			e.side_value = int(max(1.0, floor(abs(e.side_value) / (1.0 + out.curse_factor))))
	return out
