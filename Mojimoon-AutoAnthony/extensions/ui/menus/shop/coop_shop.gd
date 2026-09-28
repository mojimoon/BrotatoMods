extends "res://ui/menus/shop/coop_shop.gd"

# 商店阶段扳机：刷新商店 / 购买道具。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


func _on_RerollButton_pressed(player_index: int) -> void:
	var before = _reroll_count[player_index]
	var snap = _aa_snapshot(["increase_tier_on_reroll"])
	._on_RerollButton_pressed(player_index)
	_aa_restore(snap)
	if _reroll_count[player_index] > before:
		var m = AAMain.get_mod()
		if m != null:
			m.fire_shop("reroll", player_index)


func buy_item(item_data: ItemData, player_index: int) -> void:
	var snap = _aa_snapshot(["duplicate_item"])
	.buy_item(item_data, player_index)
	_aa_restore(snap)
	var m = AAMain.get_mod()
	if m != null:
		m.fire_shop("buy", player_index)
	# 重组道具可能带有沙漏的"倒流"效果：购买后刷新"下一波"按钮上的波数
	update_go_next_button_text()
	# 重组道具可能改变武器栏数量：原版只在武器列表变化时刷新"武器 (n/上限)"标签
	_aa_refresh_weapon_label(player_index)


func _aa_refresh_weapon_label(player_index: int) -> void:
	var gear = _get_gear_container(player_index)
	if gear != null and is_instance_valid(gear):
		gear._on_weapons_changed()


# 沙漏的"倒流"效果在原版里按沙漏的道具 ID 查找并移除持有者；出现在其他道具上时由这里处理：
# 暂时从效果计数中扣除这些道具的份额（避免原版找不到沙漏而出错），进入下一波后再倒退波数并移除持有者
func _on_GoButton_pressed(player_index: int) -> void:
	var pending = []
	for p in RunData.get_player_count():
		var holders = []
		var count = 0
		for it in RunData.get_player_items(p):
			if it.my_id_hash == Keys.item_hourglass_hash and not _aa_generated(it):
				continue
			for e in it.effects:
				if e.key_hash == Keys.item_hourglass_hash:
					holders.push_back(it)
					count += e.value
		if count > 0:
			RunData.get_player_effects(p)[Keys.item_hourglass_hash] -= count
			pending.push_back([p, holders, count])
	var wave_before = RunData.current_wave
	._on_GoButton_pressed(player_index)
	var advanced = RunData.current_wave != wave_before
	for entry in pending:
		RunData.get_player_effects(entry[0])[Keys.item_hourglass_hash] += entry[2]
		if advanced:
			RunData.current_wave -= entry[2]
			for it in entry[1]:
				_aa_replace_without(it, entry[0], ["item_hourglass"])



# ============================================================
# 镜子（购买时复制）/ 金鱼（刷新升档）/ 沙漏（倒流）出现在其他重组道具上时：
# 原版生效后会移除持有者整件道具；这里改为只移除这一条效果——放回一件去掉该效果的副本
# ============================================================
const AA_NATIVE_HOLDERS = ["item_mirror", "item_goldfish", "item_hourglass"]


# 原版的镜子 / 金鱼 / 沙漏交给原版处理；重组后同 ID 的道具按本 mod 规则处理
func _aa_generated(it) -> bool:
	var m = AAMain.get_mod()
	return m != null and m.is_generated(it)


static func _aa_effect_key(e) -> String:
	return e.custom_key if e.custom_key != "" else e.key


# 记录每个玩家、每种持有者 ID 的数量与被消耗的效果
func _aa_snapshot(keys: Array) -> Array:
	var snap = []
	for p in RunData.get_player_count():
		var seen = {}
		for it in RunData.get_player_items_ref(p):
			if (it.my_id in AA_NATIVE_HOLDERS and not _aa_generated(it)) or seen.has(it.my_id):
				continue
			for e in it.effects:
				if _aa_effect_key(e) in keys:
					seen[it.my_id] = true
					snap.push_back([p, it, RunData.get_nb_item(it.my_id_hash, p, false), keys])
					break
	return snap


func _aa_restore(snap: Array) -> void:
	for entry in snap:
		var p: int = entry[0]
		var it = entry[1]
		var lost = entry[2] - RunData.get_nb_item(it.my_id_hash, p, false)
		for _i in max(0, lost):
			_aa_add_without(it, p, entry[3])


func _aa_replace_without(it, p: int, keys: Array) -> void:
	RunData.remove_item(it, p)
	_aa_add_without(it, p, keys)


func _aa_add_without(it, p: int, keys: Array) -> void:
	var copy = it.duplicate()
	var kept = []
	var removed = false
	for e in it.effects:
		if not removed and _aa_effect_key(e) in keys:
			removed = true
			continue
		kept.push_back(e)
	copy.effects = kept
	RunData.add_item(copy, p)
	var gear = _get_gear_container(p)
	if gear != null:
		gear.set_items_data(RunData.get_player_items(p))

