extends SceneTree

# -s 入口。本脚本在 autoload 创建之前就被编译，所以不能引用任何游戏的 class_name / autoload；
# 等 autoload 和 ModLoader 就绪后再加载测试组（AA_SUITE：core / audit / battle，逗号分隔；all = 全部）。

const DIR = "res://mods/tests/AutoAnthony/"
const ALL = ["core", "audit", "battle"]


func _initialize() -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var sel = OS.get_environment("AA_SUITE")
	var suites = ALL if sel == "all" else Array((sel if sel != "" else "core").split(","))
	var ctx = {"checks": 0, "failures": []}
	var last = null
	print("user dir: ", OS.get_user_data_dir())
	for s in suites:
		if not s in ALL:
			printerr("unknown suite: ", s)
			quit(2)
			return
		var cases = load(DIR + "suite_" + s + ".gd").new()
		var err = cases.setup(self, ctx)
		if err != 0:
			quit(err)
			return
		print("suite ", s)
		var state = cases.run_suite()
		if state is GDScriptFunctionState:
			yield(state, "completed")
		last = cases
	quit(last.finish())
