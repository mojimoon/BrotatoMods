extends SceneTree

# -s 入口：autoload 与 ModLoader 就绪后再加载 test_cases.gd（本文件不能引用游戏的 class_name / autoload）

func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var cases = load("res://mods/tests/BetterCodex/test_cases.gd").new()
	var result = cases.run(self)
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	quit(int(result))
