extends "res://singletons/run_data.gd"

# 本局东尼算法状态随存档保存；回到主菜单时还原原版资源；读档时按种子重建。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")
const AACatalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")


func reset(restart: bool = false) -> void:
	if not restart:
		var m = AAMain.get_mod()
		if m != null:
			m.on_menu_reset()
	.reset(restart)


# 升级所需经验：本 mod 的道具可能叠加多条"-X% 所需经验"，总和不低于 XP_NEEDED_TOTAL_FLOOR
func get_next_level_xp_needed(player_index) -> float:
	var m = AAMain.get_mod()
	var v = get_player_effect(Keys.next_level_xp_needed_hash, player_index)
	if m == null or m.active_state == null or v >= AACatalog.XP_NEEDED_TOTAL_FLOOR:
		return .get_next_level_xp_needed(player_index)
	return get_xp_needed(get_player_level(player_index) + 1) * (1.0 + AACatalog.XP_NEEDED_TOTAL_FLOOR / 100.0)


func get_state() -> Dictionary:
	var state = .get_state()
	var m = AAMain.get_mod()
	state["aa_state"] = m.active_state.duplicate(true) if m != null and m.active_state != null else null
	return state


func resume_from_state(state: Dictionary) -> void:
	.resume_from_state(state)
	var m = AAMain.get_mod()
	if m != null:
		m.on_resume(state)
