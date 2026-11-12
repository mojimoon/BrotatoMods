extends SceneTree

# 商店性能（非测试）：godot --no-window --path 1.2 -s res://mods/tests/BetterCodex/prof_shop.gd
# 本文件不能引用游戏的 class_name / autoload，逻辑在 prof_shop_cases.gd

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var p = load("res://mods/tests/BetterCodex/prof_shop_cases.gd").new()
	var r = p.run(self)
	if r is GDScriptFunctionState:
		yield(r, "completed")
	quit()
