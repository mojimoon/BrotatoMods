extends "res://singletons/item_service.gd"

# 禁用道具 / 武器：抽取商店 / 箱子物品时，临时把本角色档案里禁用的 id 加入玩家的禁用列表（原版"禁用"机制：
# 同时从主池和备用池移除），抽完立即还原，不影响原版的禁用次数统计与存档。
#
# 1.2 起原版的 items / characters / weapons 是按物品套组重建的缓存（失效后重建时只含套组内容），
# 商店池也只从已启用的套组建立：本模组新增的角色 / 道具 / 武器等级在每次重建后补回列表与商店池。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func _rebuild_items() -> void:
	var old = _items.duplicate()
	_be_strip_own(_items, _mod_items)
	._rebuild_items()
	_restore_extras("items", _items, old, "_custom_items", _mod_items)


func _rebuild_characters() -> void:
	var old = _characters.duplicate()
	_be_strip_own(_characters, _mod_characters)
	._rebuild_characters()
	_restore_extras("characters", _characters, old, "_customs", _mod_characters)


func _rebuild_weapons() -> void:
	var old = _weapons.duplicate()
	_be_strip_own(_weapons, _mod_weapons)
	._rebuild_weapons()
	_restore_extras("weapons", _weapons, old, "_custom_weapons", _mod_weapons)


# 其他 mod（如 Capybara）在重建前把列表里所有"非套组"对象记进 _mod_items / _mod_characters / _mod_weapons 并在重建后补回：
# 本模组的对象也会被记进去，删除后仍留在列表 / 商店池里。重建前先把本模组的对象从列表和 _mod_* 里拿掉，重建后由 _restore_extras 按当前注册补回。
static func _be_strip_own(list: Array, mod_list: Array) -> void:
	for arr in [list, mod_list]:
		for r in arr.duplicate():
			if r != null and r.has_meta("broeditor"):
				arr.erase(r)


# 上一次重建时由套组 / _mod_items / 本模组提供的对象（不是"直接加进列表的"）：[列表名] -> {对象: true}
var _be_managed: Dictionary = {}


# 重建后补回：
# 1. 本模组当前注册的对象；
# 2. 原版 add_mod_item() 登记在 _mod_items 里的对象：1.2.0.1 的 _rebuild_items 没有把 _mod_items 放回列表（原版 bug，
#    _mod_characters / _mod_weapons 同样没用到），用这个接口加的道具重建后就不见了。官方修复后这里只是重复检查，不会重复加入，
#    届时可以删掉这一步；
# 3. 重建前在列表里、但上一次重建时不是由套组 / _mod_items / 本模组提供的对象：其他 mod 直接加进
#    items / characters / weapons 的内容（1.1 的做法），不能因为本模组作废缓存而丢失（它们仍然进不了原版商店池：
#    原版只从套组建池）。上一次由套组等提供、这次不在了的对象是被移除了（如 BroLab 删除自己的内容、remove_mod_item），不补回。
func _restore_extras(name: String, list: Array, old: Array, field: String, mod_list: Array) -> void:
	var managed = {}
	for r in list:
		managed[r] = true
	var m = BEMain.get_mod()
	var own = m.get(field).values() if m != null else []
	for r in own + mod_list:
		if r != null and not r in list:
			list.push_back(r)
		managed[r] = true
	var prev: Dictionary = _be_managed.get(name, {})
	for r in old:
		if r != null and not r in list and not prev.has(r) and not r.has_meta("broeditor"):
			list.push_back(r)
	_be_managed[name] = managed


# 原版只把套组里的道具 / 武器放进商店池：本模组的自定义道具与武器等级按原版条件补进去
func init_unlocked_pool() -> void:
	# 其他 mod 可能已把本模组的对象（包括已删除的）记进 _mod_*、并在建池时加进池：前后都去掉记录，下面加池时跳过已在池里的
	for arr in [_mod_items, _mod_weapons, _mod_characters]:
		_be_strip_own([], arr)
	.init_unlocked_pool()
	for arr in [_mod_items, _mod_weapons, _mod_characters]:
		_be_strip_own([], arr)
	var m = BEMain.get_mod()
	if m == null:
		return
	for item in m._custom_items.values():
		if item == null or not item.can_be_looted or item.max_nb == 0:
			continue
		if RunData.current_difficulty < item.minimum_difficulty or not ProgressData.items_unlocked.has(item.my_id_hash):
			continue
		if item in _tiers_data[item.tier][TierData.ALL_ITEMS]:
			continue
		_tiers_data[item.tier][TierData.ALL_ITEMS].push_back(item)
		_tiers_data[item.tier][TierData.ITEMS].push_back(item)
	for weapon in m._custom_weapons.values():
		if weapon == null or not weapon.can_be_looted or not m.weapon_in_active_set(weapon):
			continue
		if not ProgressData.weapons_unlocked.has(weapon.weapon_id_hash):
			continue
		if weapon in _tiers_data[weapon.tier][TierData.ALL_ITEMS]:
			continue
		_tiers_data[weapon.tier][TierData.ALL_ITEMS].push_back(weapon)
		_tiers_data[weapon.tier][TierData.WEAPONS].push_back(weapon)


# 蓝图"商店必定出现"
func get_player_shop_items(wave: int, player_index: int, args: ItemServiceGetShopItemsArgs) -> Array:
	var out = .get_player_shop_items(wave, player_index, args)
	var m = BEMain.get_mod()
	if m != null:
		m.inject_shop_force(out, player_index, wave)
	return out


func _get_rand_item_for_wave(wave: int, player_index: int, type: int, args: GetRandItemForWaveArgs) -> ItemParentData:
	var m = BEMain.get_mod()
	var extra = m.ban_hashes(player_index) if m != null else []
	if extra.empty():
		return ._get_rand_item_for_wave(wave, player_index, type, args)
	var banned: Array = RunData.players_data[player_index].banned_items
	var n = banned.size()
	banned.append_array(extra)
	var item = ._get_rand_item_for_wave(wave, player_index, type, args)
	banned.resize(n)
	return item
