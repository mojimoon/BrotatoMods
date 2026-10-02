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
	var taken = _aa_take_duplicates(player_index)
	.buy_item(item_data, player_index)
	_aa_apply_duplicates(taken, item_data, player_index)
	var m = AAMain.get_mod()
	if m != null:
		m.fire_shop("buy", player_index)
		m.fire_shop("buy_stat", player_index, item_data)
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


# 复制购买的道具（镜子效果）出现在重组道具上时由这里处理，不交给原版：原版对每个持有者 ID 按"复制份数"循环，
# 每份都按 ID 找一件持有者并整件移除；份数 > 1（重组按预算缩放、诅咒）时找不到持有者，对空值调用而闪退。
# 这里先把这些条目从效果列表里取出（原版只处理原版镜子），之后放回，再按份数复制购买的道具，持有者只失去这一条效果。
# 效果列表按持有者 ID 合并存储（[ID, 份数之和]），同 ID 的多件持有者一起生效，与原版多面镜子相同
func _aa_take_duplicates(p: int) -> Array:
	var arr: Array = RunData.get_player_effect(Keys.duplicate_item_hash, p)
	var taken = []
	for entry in arr.duplicate():
		var holders = []
		for it in RunData.get_player_items(p):
			if it.my_id_hash != entry[0]:
				continue
			if it.my_id_hash == Keys.item_mirror_hash and not _aa_generated(it):
				continue
			for e in it.effects:
				if e.custom_key == "duplicate_item":
					holders.push_back([it, e.value])
					break
		if holders.empty():
			continue
		taken.push_back([entry[0], entry[1], holders])
		arr.erase(entry)
	return taken


func _aa_apply_duplicates(taken: Array, item_data: ItemData, p: int) -> void:
	var arr: Array = RunData.get_player_effect(Keys.duplicate_item_hash, p)
	# 放回（购买的道具本身也可能带同 ID 的复制效果，已由原版加入列表：合并）
	for t in taken:
		var merged = false
		for entry in arr:
			if entry[0] == t[0]:
				entry[1] += t[1]
				merged = true
				break
		if not merged:
			arr.push_back([t[0], t[1]])
	var changed = false
	for t in taken:
		var count = int(min(t[1], RunData.get_remaining_max_nb_item(item_data, p)))
		if count <= 0:
			continue
		for _i in count:
			RunData.add_item(item_data, p)
		# 依次消耗持有者，直到覆盖复制份数
		var covered = 0
		for h in t[2]:
			if covered >= count:
				break
			_aa_replace_without(h[0], p, ["duplicate_item"])
			covered += max(1, h[1])
		changed = true
	if changed:
		var gear = _get_gear_container(p)
		if gear != null:
			gear.set_items_data(RunData.get_player_items(p))


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

