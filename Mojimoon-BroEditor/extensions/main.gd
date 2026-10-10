extends "res://main.gd"

# 战斗场景：把原版事件转发给蓝图运行时（graph/runtime.gd），并处理开局状态（结算升级、开局箱子、波次时长）。

const BEMain = preload("res://mods-unpacked/Mojimoon-BroEditor/mod_main.gd")


# 波次时长在 main._ready 里读取：在进入场景树时（_ready 之前）设置。
# 注意：Godot 3 会自动调用每一层脚本的 _ready / _enter_tree，扩展里不能再调用 ._ready()（否则原版 _ready 执行两次）
func _enter_tree() -> void:
	var m = BEMain.get_mod()
	if m != null:
		m.apply_wave_duration()


func _be_rt():
	var m = BEMain.get_mod()
	return m.runtime if m != null and m.runtime != null and not m.runtime.wave_over else null


func _on_EntitySpawner_players_spawned(players: Array) -> void:
	._on_EntitySpawner_players_spawned(players)
	var m = BEMain.get_mod()
	if m == null:
		return
	m.apply_pending_start(self)
	m.runtime.start_wave(self)
	for player in players:
		if player != null:
			var _e = player.connect("took_damage", self, "_be_on_player_took_damage")
	for p in RunData.get_player_count():
		m.runtime.fire("wave_start", p)


func _be_on_player_took_damage(unit, value: int, _knockback, _is_crit: bool, is_dodge: bool, _is_protected: bool, _armor_did_something: bool, _args, _hit_type: int, _is_one_shot: bool) -> void:
	var rt = _be_rt()
	if rt == null or unit == null or not is_instance_valid(unit):
		return
	if is_dodge:
		rt.fire("dodge", unit.player_index, unit.global_position)
	elif value > 0:
		rt.fire("hit", unit.player_index, unit.global_position)


func on_levelled_up(player_index: int) -> void:
	.on_levelled_up(player_index)
	var rt = _be_rt()
	if rt != null:
		rt.fire("level_up", player_index)


func _on_enemy_died(enemy: Enemy, args: Entity.DieArgs) -> void:
	var counts = not _cleaning_up and args.enemy_killed_by_player
	var pos = enemy.global_position
	var burning = args.is_burning or (is_instance_valid(enemy) and enemy._is_burning)
	var cursed = _be_is_cursed(enemy)
	._on_enemy_died(enemy, args)
	var rt = _be_rt()
	if rt == null or not counts:
		return
	var killers = [args.killed_by_player_index] if args.killed_by_player_index >= 0 else []
	if killers.empty():
		for player in _get_live_players():
			killers.push_back(player.player_index)
	for p in killers:
		rt.fire("kill", p, pos)
		if burning:
			rt.fire("burning_kill", p, pos)
		if cursed:
			rt.fire("cursed_kill", p, pos)


static func _be_is_cursed(enemy) -> bool:
	if not is_instance_valid(enemy) or not "effect_behaviors" in enemy or enemy.effect_behaviors == null:
		return false
	for b in enemy.effect_behaviors.get_children():
		if b.get_script() != null and b.get_script().resource_path.ends_with("curse_enemy_effect_behavior.gd"):
			return true
	return false


func _on_neutral_died(neutral: Neutral, args: Entity.DieArgs) -> void:
	var counts = not _cleaning_up
	var pos = neutral.global_position
	._on_neutral_died(neutral, args)
	var rt = _be_rt()
	if rt == null or not counts:
		return
	if args.killed_by_player_index >= 0:
		rt.fire("tree_kill", args.killed_by_player_index, pos)
	else:
		for player in _get_live_players():
			rt.fire("tree_kill", player.player_index, pos)


func _on_enemy_took_damage(enemy: Enemy, value: int, knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, args: TakeDamageArgs, hit_type: int, is_one_shot: bool) -> void:
	._on_enemy_took_damage(enemy, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
	if not is_crit or _cleaning_up or args.from_player_index < 0:
		return
	var rt = _be_rt()
	if rt == null:
		return
	# 原版的死亡是延迟调用：按"本次伤害后生命为 0"判断暴击击杀
	var killed = enemy.dead or enemy.current_stats.health <= 0
	rt.fire("crit", args.from_player_index, enemy.global_position, enemy if not killed else null)
	if killed:
		rt.fire("crit_kill", args.from_player_index, enemy.global_position)


func _on_HalfWaveTimer_timeout() -> void:
	._on_HalfWaveTimer_timeout()
	var rt = _be_rt()
	if rt != null:
		for p in RunData.get_player_count():
			rt.fire("half_wave", p)


func on_consumable_picked_up(consumable: Node, player_index: int) -> void:
	var was_picked = consumable.already_picked_up
	var pos = consumable.global_position
	var data = consumable.consumable_data
	.on_consumable_picked_up(consumable, player_index)
	var rt = _be_rt()
	if rt != null and not was_picked and not _cleaning_up:
		rt.fire("consumable", player_index, pos)
		if data != null and (data.my_id_hash == Keys.consumable_item_box_hash or data.my_id_hash == Keys.consumable_legendary_item_box_hash):
			rt.fire("crate", player_index, pos)


func on_gold_picked_up(gold: Node, player_index: int) -> void:
	var was_picked = gold.already_picked_up
	.on_gold_picked_up(gold, player_index)
	var rt = _be_rt()
	if rt != null and not was_picked and player_index >= 0 and not _cleaning_up:
		rt.fire("gold", player_index)


func on_player_healed(value: int, player_index: int) -> void:
	.on_player_healed(value, player_index)
	var rt = _be_rt()
	if rt != null and value > 0:
		rt.fire("heal", player_index)


func _on_WaveTimer_timeout() -> void:
	var rt = _be_rt()
	if rt != null:
		for p in RunData.get_player_count():
			rt.fire("wave_end", p)
		rt.end_wave()
	._on_WaveTimer_timeout()
