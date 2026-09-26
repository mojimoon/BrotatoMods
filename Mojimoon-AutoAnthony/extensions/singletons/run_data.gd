extends "res://singletons/run_data.gd"

# 本局东尼算法状态随存档保存；回到主菜单时还原原版资源；读档时按种子重建。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")


func reset(restart: bool = false) -> void:
	if not restart:
		var m = AAMain.get_mod()
		if m != null:
			m.on_menu_reset()
	.reset(restart)


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
