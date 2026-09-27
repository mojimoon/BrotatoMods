#!/usr/bin/env bash
# AutoAnthony 无头测试
# 用法（Git Bash）：bash mods/tests/AutoAnthony/run_tests.sh
#
# - 在反编译的游戏工程（本仓库的上一级目录）里运行，使用真实的 ItemService / RunData / ModLoader
# - 先把 mods/<MOD> 同步到 mods-unpacked/<MOD>（编辑器模式下 ModLoader 只加载这里的 mod）
# - APPDATA 指向临时目录：user:// 与真实存档、ModLoader 配置完全隔离
# - 测试文件在 mods/tests 下，不会被打包进 mod
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(cd "$HERE/../../.." && pwd)
MOD=Mojimoon-AutoAnthony
GODOT=${GODOT:-/d/env/godot_3.7-dev1/Godot_v3.7-dev1_win64.exe}

if [ ! -f "$PROJECT/project.godot" ]; then
	echo "project.godot not found in $PROJECT" >&2
	exit 2
fi

# 同步 mod 源码
rm -rf "$PROJECT/mods-unpacked/$MOD"
mkdir -p "$PROJECT/mods-unpacked"
cp -r "$PROJECT/mods/$MOD" "$PROJECT/mods-unpacked/$MOD"

# 隔离 user://
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
LOG="$SANDBOX/test.log"

cd "$PROJECT"
APPDATA=$(cygpath -w "$SANDBOX") AA_TEST=1 timeout 600 "$GODOT" --no-window --audio-driver Dummy --path . \
	-s "res://mods/tests/AutoAnthony/run_aa.gd" > "$LOG" 2>&1
STATUS=$?

# 只关心 mod / 测试自身的脚本错误（游戏在无头模式下有一些与 mod 无关的报错）
# 与游戏的崩溃检测一致：任何 "ERROR:" 行（或其下一行）提到本 mod 都算失败——游戏会因此在下次启动时禁用所有 mod
CRASH=$(awk -v mod="$MOD" '
	/ERROR:/ { cur = $0; if ((getline nxt) > 0) { if (index(cur, "mods-unpacked/" mod) || index(nxt, "mods-unpacked/" mod)) { print cur; print nxt } } }
' "$LOG")
if [ -n "$CRASH" ]; then
	echo
	echo "Errors mentioning the mod (the game's crash detector would disable mods):"
	echo "$CRASH"
	STATUS=1
fi
ERRORS=$(awk '
	/SCRIPT ERROR|Parse Error|Script error/ { pending = $0; next }
	pending != "" {
		if ($0 ~ /Mojimoon-AutoAnthony|mods\/tests\//) print pending "\n" $0
		pending = ""
	}
' "$LOG")

grep -E "^(  ran |FAIL |[0-9]+ checks|ALL TESTS PASSED|user dir|Refusing|Mod node|AUDIT)" "$LOG"
if [ -n "$ERRORS" ]; then
	echo
	echo "Script errors from the mod or tests:"
	echo "$ERRORS"
	STATUS=1
fi
if ! grep -q "ALL TESTS PASSED" "$LOG"; then
	[ $STATUS -eq 0 ] && STATUS=1
	echo
	echo "---- last 40 log lines ----"
	tail -40 "$LOG"
fi
exit $STATUS
