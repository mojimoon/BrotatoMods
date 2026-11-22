extends "res://items/global/effect.gd"

# 时间扭曲（time_shift_on_hit）：原版持续时间固定为玩家 ShiftTimer 的 3 秒，效果本身只有减速百分比。
# 本模组生成的此类效果多一个"持续时间"字段：应用时把与 3 秒的差加到 be_time_shift_secs（graph/runtime.gd 开波时加到计时器上）。
# 持续时间为 3 秒时按原版效果序列化（卸载本模组后存档照常读取）

const BASE_SECS = 3.0

export(float) var be_secs = BASE_SECS


static func get_id() -> String:
	return "be_time_shift"


func _delta() -> float:
	return be_secs - BASE_SECS


func apply(player_index: int) -> void:
	.apply(player_index)
	if _delta() != 0:
		var effects = RunData.get_player_effects(player_index)
		var h = Keys.generate_hash("be_time_shift_secs")
		effects[h] = effects.get(h, 0) + _delta()


func unapply(player_index: int) -> void:
	.unapply(player_index)
	if _delta() != 0:
		var effects = RunData.get_player_effects(player_index)
		var h = Keys.generate_hash("be_time_shift_secs")
		effects[h] = effects.get(h, 0) - _delta()


func get_text(player_index: int, colored: bool = true) -> String:
	var t = .get_text(player_index, colored)
	if t == "" or _delta() == 0:
		return t
	return t + tr("BE_TIME_SHIFT_SECS_SUFFIX").replace("{0}", str(stepify(be_secs, 0.01)))


func serialize() -> Dictionary:
	var d = .serialize()
	if _delta() != 0:
		d.be_secs = be_secs
	else:
		d.effect_id = "effect"
	return d


func deserialize_and_merge(effect: Dictionary) -> void:
	.deserialize_and_merge(effect)
	be_secs = float(effect.get("be_secs", BASE_SECS))
