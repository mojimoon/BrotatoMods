extends "res://singletons/run_data.gd"

# 开局状态：初始材料 / 等级 / 箱子 / 额外禁用次数（同 cave-modtools 的"初始状态"）。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


func add_starting_items_and_weapons() -> void:
	.add_starting_items_and_weapons()
	var m = BEMain.get_mod()
	if m != null:
		m.apply_start_state()


func reset(restart: bool = false) -> void:
	.reset(restart)
	var m = BEMain.get_mod()
	if m != null:
		m.run_shop = m.new_run_shop()
	if m != null and restart:
		m.apply_start_bans()


# 本局商店的变化随一局存档保存
func get_state() -> Dictionary:
	var s = .get_state()
	var m = BEMain.get_mod()
	if m != null:
		s["broeditor_shop"] = m.run_shop.duplicate(true)
	return s


func resume_from_state(state: Dictionary) -> void:
	.resume_from_state(state)
	var m = BEMain.get_mod()
	if m != null:
		m.load_run_shop(state.get("broeditor_shop"))


# 史前惧兽：一次异变结束后（令牌清理、蓝图扳机"道具异变时"）
func mutate_random_item(player_index: int):
	var mutated = .mutate_random_item(player_index)
	var m = BEMain.get_mod()
	if m != null:
		m.after_mutation(player_index, mutated)
	return mutated


# 蓝图扳机"机械化武器时"（商店 / 升级界面花机械部件改造武器）
func meca_upgrade_weapon(weapon_data: WeaponData, upgraded_weapon: WeaponData, player_index: int) -> WeaponData:
	var w = .meca_upgrade_weapon(weapon_data, upgraded_weapon, player_index)
	var m = BEMain.get_mod()
	if w != null and m != null and m.runtime != null:
		m.runtime.fire("meca_upgrade", player_index)
	return w
