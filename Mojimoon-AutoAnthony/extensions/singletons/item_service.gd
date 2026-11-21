extends "res://singletons/item_service.gd"

# 1.2 起 weapons 是按物品套组重建的缓存，商店池也只从已启用的套组建立：
# "补全低级武器"补出的武器在每次重建后补回列表（按 ID 查找、合成、读档）与商店池；
# 本局被新化石替换的原版化石不进商店池（"保留原版道具"保留的原版化石照常）（_backups 非空 = 重组生效中，还原时先清空 _backups 再重建）

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


func _rebuild_weapons() -> void:
	._rebuild_weapons()
	var m = AAMain.get_mod()
	if m != null:
		for w in m._low_weapons:
			if not w in _weapons:
				_weapons.push_back(w)


func init_unlocked_pool() -> void:
	.init_unlocked_pool()
	var m = AAMain.get_mod()
	if m == null:
		return
	for w in m._low_weapons:
		if w.can_be_looted and ProgressData.weapons_unlocked.has(w.weapon_id_hash):
			_tiers_data[w.tier][TierData.ALL_ITEMS].push_back(w)
			_tiers_data[w.tier][TierData.WEAPONS].push_back(w)
	if not m._backups.empty() and m.has_fossils():
		var replaced = m.plan.replaced_fossils
		for tier in _tiers_data:
			for type in [TierData.ALL_ITEMS, TierData.ITEMS]:
				var kept = []
				for it in tier[type]:
					if not it.my_id in replaced:
						kept.push_back(it)
				tier[type] = kept


# 属性说明弹窗（商店 / 暂停界面悬停属性）：补上面板里看不到的修正。
# 该属性的"修改增加 / 减少 X%"（重组道具上的属性修改效果）；收获另外列出敌人掉落材料的加成
func get_stat_description_text(stat_hash: int, value: int, player_index: int) -> String:
	var text = .get_stat_description_text(stat_hash, value, player_index)
	if player_index < 0 or player_index >= RunData.get_player_count() or not Keys.hash_to_string.has(stat_hash):
		return text
	var stat = Keys.hash_to_string[stat_hash]
	var extra = []
	var gain_hash = Keys.generate_hash("gain_" + stat)
	var effects = RunData.get_player_effects(player_index)
	if effects.has(gain_hash) and int(effects[gain_hash]) != 0:
		var g = int(effects[gain_hash])
		extra.push_back(Text.text("EFFECT_INCREASE_STAT_GAINS" if g > 0 else "EFFECT_REDUCE_STAT_GAINS", [tr(stat.to_upper()), str(abs(g)) + "%"]))
	if stat_hash == Keys.stat_harvesting_hash:
		for k in [Keys.gold_drops_hash, Keys.enemy_gold_drops_hash]:
			if effects.has(k) and int(effects[k]) != 0:
				var v = int(effects[k])
				var key = "EFFECT_GOLD_DROPS" if k == Keys.gold_drops_hash else "EFFECT_ENEMY_GOLD_DROPS"
				extra.push_back(tr(key).replace("{0}", ("+" if v > 0 else "") + str(v) + "%"))
	if extra.empty():
		return text
	return text + "\n\n" + PoolStringArray(extra).join("\n")
