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
	var burning = args.is_burning or (is_instance_valid(enemy) and enemy._is_burning)
	var killers = [args.killed_by_player_index] if args.killed_by_player_index >= 0 else []
	if killers.empty():
		for player in _get_live_players():
			killers.push_back(player.player_index)
	var cursed = _aa_is_cursed(enemy)
	for p in killers:
		rt.fire("kill", p, pos)
		if burning:
			rt.fire("burning_kill", p, pos)
		if cursed:
			rt.fire("cursed_kill", p, pos)


# 砍倒树木（口袋工厂同一入口）
func _on_neutral_died(neutral: Neutral, args: Entity.DieArgs) -> void:
	var counts = not _cleaning_up
	var pos = neutral.global_position
	._on_neutral_died(neutral, args)
	var rt = _aa_rt()
	if rt == null or not counts:
		return
	if args.killed_by_player_index >= 0:
		rt.fire("tree_kill", args.killed_by_player_index, pos)
	else:
		for player in _get_live_players():
			rt.fire("tree_kill", player.player_index, pos)


# 被诅咒的敌人（DLC 的诅咒效果行为，与黑旗"击杀被诅咒的敌人"同一判断）
static func _aa_is_cursed(enemy) -> bool:
	if not is_instance_valid(enemy) or not "effect_behaviors" in enemy or enemy.effect_behaviors == null:
		return false
	for b in enemy.effect_behaviors.get_children():
		if b.get_script() != null and b.get_script().resource_path.ends_with("curse_enemy_effect_behavior.gd"):
			return true
	return false


# 暴击 / 暴击击杀：原版在敌人受伤信号里带有是否暴击（致死时死亡尚未执行，见下）
func _on_enemy_took_damage(enemy: Enemy, value: int, knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, args: TakeDamageArgs, hit_type: int, is_one_shot: bool) -> void:
	._on_enemy_took_damage(enemy, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
	if not is_crit or _cleaning_up or args.from_player_index < 0:
		return
	var rt = _aa_rt()
	if rt != null:
		# 原版的死亡是延迟调用（unit.take_damage 里 call_deferred("die")），发出受伤信号时 enemy.dead 仍为假：
		# 按"本次伤害后生命为 0"判断暴击击杀
		var killed = enemy.dead or enemy.current_stats.health <= 0
		rt.fire("crit", args.from_player_index, enemy.global_position, -1, enemy if not killed else null)
		if killed:
			rt.fire("crit_kill", args.from_player_index, enemy.global_position)


func _on_HalfWaveTimer_timeout() -> void:
	._on_HalfWaveTimer_timeout()
	var rt = _aa_rt()
	if rt != null:
		for p in RunData.get_player_count():
			rt.fire("half_wave", p)


func on_consumable_picked_up(consumable: Node, player_index: int) -> void:
	var was_picked = consumable.already_picked_up
	var pos = consumable.global_position
	var data = consumable.consumable_data
	.on_consumable_picked_up(consumable, player_index)
	var rt = _aa_rt()
	if rt != null and not was_picked and not _cleaning_up:
		rt.fire("consumable", player_index, pos)
		if data != null and (data.my_id_hash == Keys.consumable_item_box_hash or data.my_id_hash == Keys.consumable_legendary_item_box_hash):
			rt.fire("crate", player_index, pos)


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
