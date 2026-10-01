extends "res://singletons/weapon_service.gd"

# "引发爆炸时"扳机：任何来源的玩家爆炸（原版爆炸道具 / 武器、本 mod 的爆炸载荷）都转发到触发总线；
# 本 mod 的爆炸载荷在参数上带有连锁深度（aa_depth），连锁从这里继续计数
#
# 武器类型加成的暴击率 / 贯通（本 mod 生成的效果，原版角色不用这两种）：
#   原版把类型加成的数值直接加到武器属性上：暴击率是小数（+5 会变成 +500%），这里改回 +5%；
#   贯通在远程武器的通用计算里会被重新赋值，这里在通用计算之后再加上
var _aa_piercing_bonus := 0


func explode(effect: ExplodingEffect, args: WeaponServiceExplodeArgs) -> Node:
	var instance = .explode(effect, args)
	if args != null and args.from_player_index >= 0:
		var main = Utils.get_scene_node()
		if main != null and main.has_method("_aa_rt"):
			var rt = main._aa_rt()
			if rt != null:
				var depth = int(args.get_meta("aa_depth")) if args.has_meta("aa_depth") else -1
				rt.fire("explode", args.from_player_index, args.pos, depth)
	return instance


func init_base_stats(from_stats: WeaponStats, player_index: int, args: WeaponServiceInitStatsArgs = null, is_structure: = false, is_special_spawn: = false, is_pet: = false) -> WeaponStats:
	if args == null:
		args = _init_stats_args_service
	var new_stats = .init_base_stats(from_stats, player_index, args, is_structure, is_special_spawn, is_pet)
	_aa_piercing_bonus = 0
	for class_bonus in RunData.get_player_effect(Keys.weapon_class_bonus_hash, player_index):
		var stat_name = Keys.hash_to_string.get(class_bonus[1], "")
		if stat_name != "crit_chance" and stat_name != "piercing":
			continue
		for set in args.sets:
			if set.my_id_hash == class_bonus[0]:
				if stat_name == "crit_chance":
					new_stats.crit_chance -= class_bonus[2] - class_bonus[2] / 100.0
				else:
					_aa_piercing_bonus += class_bonus[2]
	return new_stats


func _set_common_ranged_stats(new_stats: RangedWeaponStats, from_stats: RangedWeaponStats, player_index: int):
	._set_common_ranged_stats(new_stats, from_stats, player_index)
	if _aa_piercing_bonus != 0:
		new_stats.piercing = int(max(0, new_stats.piercing + _aa_piercing_bonus))
		_aa_piercing_bonus = 0
