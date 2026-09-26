extends "res://main.gd"

# 把原版战斗事件转发给东尼算法的通用触发总线（aa/runtime.gd）。

const AAMain = preload("res://mods-unpacked/Mojimoon-AutoAnthony/mod_main.gd")
const AARuntime = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/runtime.gd")

var _aa_runtime = null


func _aa_rt():
	if _aa_runtime != null and is_instance_valid(_aa_runtime):
		return _aa_runtime
	return null


func _on_EntitySpawner_players_spawned(players: Array) -> void:
	._on_EntitySpawner_players_spawned(players)
	var m = AAMain.get_mod()
	if m == null or m.active_state == null:
		return
	_aa_runtime = AARuntime.new()
	add_child(_aa_runtime)
	_aa_runtime.setup(self, m)
	for player in players:
		if player != null:
			var _e = player.connect("took_damage", _aa_runtime, "on_player_took_damage")
	for p in RunData.get_player_count():
		_aa_runtime.fire("wave_start", p)


func on_levelled_up(player_index: int) -> void:
	.on_levelled_up(player_index)
	var rt = _aa_rt()
	if rt != null:
		rt.fire("level_up", player_index)


func _on_enemy_died(enemy: Enemy, args: Entity.DieArgs) -> void:
	var counts = not _cleaning_up and args.enemy_killed_by_player
	var pos = enemy.global_position
	._on_enemy_died(enemy, args)
	var rt = _aa_rt()
	if rt == null or not counts:
		return
	if args.killed_by_player_index >= 0:
		rt.fire("kill", args.killed_by_player_index, pos)
	else:
		for player in _get_live_players():
			rt.fire("kill", player.player_index, pos)


func on_consumable_picked_up(consumable: Node, player_index: int) -> void:
	var was_picked = consumable.already_picked_up
	var pos = consumable.global_position
	.on_consumable_picked_up(consumable, player_index)
	var rt = _aa_rt()
	if rt != null and not was_picked and not _cleaning_up:
		rt.fire("consumable", player_index, pos)


func on_gold_picked_up(gold: Node, player_index: int) -> void:
	var was_picked = gold.already_picked_up
	.on_gold_picked_up(gold, player_index)
	var rt = _aa_rt()
	if rt != null and not was_picked and player_index >= 0 and not _cleaning_up:
		rt.fire("gold", player_index)


func on_player_healed(value: int, player_index: int) -> void:
	.on_player_healed(value, player_index)
	var rt = _aa_rt()
	if rt != null and value > 0:
		rt.fire("heal", player_index)


func _on_WaveTimer_timeout() -> void:
	var rt = _aa_rt()
	if rt != null:
		for p in RunData.get_player_count():
			rt.fire("wave_end", p)
		rt.on_wave_end()
	._on_WaveTimer_timeout()
