extends "res://singletons/weapon_service.gd"

# "引发爆炸时"扳机：任何来源的玩家爆炸（原版爆炸道具 / 武器、本 mod 的爆炸载荷）都转发到触发总线；
# 本 mod 的爆炸载荷在参数上带有连锁深度（aa_depth），连锁从这里继续计数


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
