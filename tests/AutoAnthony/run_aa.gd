extends SceneTree

# -s 入口。本脚本在 autoload 创建之前就被编译，所以不能引用任何游戏的 class_name / autoload；
# 等 autoload 和 ModLoader 就绪后再加载 test_cases.gd。

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var cases = load("res://mods/tests/AutoAnthony/test_cases.gd").new()
	var result = cases.run(self)
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	quit(int(result))
