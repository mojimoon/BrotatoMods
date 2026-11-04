extends "res://singletons/item_service.gd"

# 1.2 起 weapons 是按物品套组重建的缓存，商店池也只从已启用的套组建立：
# "补全低级武器"补出的武器在每次重建后补回列表（按 ID 查找、合成、读档）与商店池；
# 本局生成了新化石时，原版化石不进商店池（_backups 非空 = 重组生效中，还原时先清空 _backups 再重建）

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
		for tier in _tiers_data:
			for type in [TierData.ALL_ITEMS, TierData.ITEMS]:
				var kept = []
				for it in tier[type]:
					if not it.my_id in AAMain.Catalog.FOSSIL_ITEMS:
						kept.push_back(it)
				tier[type] = kept
