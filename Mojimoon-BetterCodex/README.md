# BetterCodex

游戏内图鉴增强（Brotato 1.2）：角标、搜索筛选、跳转、诅咒 / 机械化 / 异变预览、攻速计算器（实际冷却）、价格计算；选择界面的角色信息；商店里右键 / 快捷键（默认 C）/ R3 打开图鉴；图鉴内“设置”。

- 测试：`bash mods/tests/BetterCodex/run_tests.sh [normal|compat|all]`（compat 同时加载 ImprovedTooltips 3019195689 与 ItemRefund 3834897339）
- 截图：`godot --path 1.2 -s res://mods/tests/BetterCodex/shot.gd`（BC_SHOT_DIR）
- 打包：`python mods/tools/pack_mod.py BetterCodex "D:\dev\mod\Brotato\1.2\dist-BetterCodex"`
- 翻译：`translations/bettercodex.csv`（13 种语言，手工维护；初版从 codex/ui_strings.json 生成）
