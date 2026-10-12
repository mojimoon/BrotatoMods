extends "res://singletons/weapon_service.gd"

# 蓝图扳机"引发爆炸时"：任何来源的玩家爆炸都转发给蓝图运行时；蓝图自己的爆炸（参数带 be_bp）不转发，
# 并在爆炸节点上标记，使其命中不触发"命中敌人"扳机（防止无限连锁）。爆炸节点会被对象池复用：每次都重设标记


func explode(effect: ExplodingEffect, args: WeaponServiceExplodeArgs) -> Node:
	var instance = .explode(effect, args)
	if args == null:
		return instance
	var bp = args.has_meta("be_bp")
	if instance != null:
		instance.set_meta("be_bp", bp)
	if bp or args.from_player_index < 0:
		return instance
	var m = Engine.get_main_loop().root.get_node_or_null("/root/ModLoader/Mojimoon-BroEditor")
	if m != null and m.runtime != null and not m.runtime.wave_over:
		m.runtime.fire("on_explode", args.from_player_index, args.pos)
	return instance
