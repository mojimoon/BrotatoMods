#!/usr/bin/env bash
# BroEditor 无头测试
# 用法（Git Bash）：bash mods/tests/BroEditor/run_tests.sh [core|ui|battle|compat|all|core,ui]
#   默认 = core,ui,battle；compat = 与 QianMo-BroLab、cave-modtools 同时加载的兼容性测试；all = 全部
#   compat 之后自动再运行 compat_off：卸下这两个 mod、沿用同一个 user://，检查停用 mod 后的表现
#   BE_ONLY=<名字片段> 只跑名字含该片段的测试；BE_KEEP_LOG=<路径> 保留完整日志
#
# - 在反编译的游戏工程（本仓库的上一级目录）里运行，使用真实的 ItemService / RunData / ModLoader
# - 先把 mods/<MOD> 同步到 mods-unpacked/<MOD>（编辑器模式下 ModLoader 只加载这里的 mod）
# - compat 组在单独的进程里运行：临时把 other_mods/mods-unpacked 下的两个 mod 复制进 mods-unpacked，结束后删除
# - APPDATA 指向临时目录：user:// 与真实存档、ModLoader 配置完全隔离
# - 测试文件在 mods/tests 下，不会被打包进 mod
set -u
BE_KEEP_LOG=${BE_KEEP_LOG:-}

HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(cd "$HERE/../../.." && pwd)
MOD=Mojimoon-BroEditor
COMPAT_MODS="QianMo-BroLab cave-modtools"
SEL=${1:-core,ui,battle}
[ "$SEL" = "all" ] && SEL=core,ui,battle,compat
GODOT=${GODOT:-/d/env/godot_3.7-dev1/Godot_v3.7-dev1_win64.exe}

if [ ! -f "$PROJECT/project.godot" ]; then
	echo "project.godot not found in $PROJECT" >&2
	exit 2
fi

# 同步 mod 源码
rm -rf "$PROJECT/mods-unpacked/$MOD"
mkdir -p "$PROJECT/mods-unpacked"
cp -r "$PROJECT/mods/$MOD" "$PROJECT/mods-unpacked/$MOD"

# 普通组与 compat 组分开运行
NORMAL=$(echo "$SEL" | tr ',' '\n' | grep -v '^compat$' | paste -sd, -)
HAS_COMPAT=$(echo "$SEL" | tr ',' '\n' | grep -c '^compat$')

cleanup_compat() {
	for m in $COMPAT_MODS; do rm -rf "$PROJECT/mods-unpacked/$m"; done
}

# 运行一次 Godot；$1 = 组列表，$2 = 日志，$3 = 沿用的 user 目录（可选，不删除）
run_godot() {
	local sandbox=${3:-}
	[ -z "$sandbox" ] && sandbox=$(mktemp -d)
	(cd "$PROJECT" && APPDATA=$(cygpath -w "$sandbox") BE_TEST=1 BE_SUITE="$1" timeout 900 "$GODOT" --no-window --audio-driver Dummy --path . \
		-s "res://mods/tests/BroEditor/run_be.gd" > "$2" 2>&1)
	local st=$?
	[ -z "${3:-}" ] && rm -rf "$sandbox"
	return $st
}

# 检查一次运行的日志；返回非 0 表示失败
report() {
	local log=$1 st=$2
	# 只关心 mod / 测试自身的脚本错误（游戏在无头模式下有一些与 mod 无关的报错）
	local errors
	errors=$(awk '
		/SCRIPT ERROR|Parse Error|Script error/ { pending = $0; next }
		pending != "" {
			if ($0 ~ /Mojimoon-BroEditor|mods\/tests\//) print pending "\n" $0
			pending = ""
		}
	' "$log")
	# 测试打印 "watch begin" / "watch end" 之间的任何脚本错误（包括原版和其他 mod 的脚本）都算失败：
	# 用于检查与其他 mod 同时加载时的真实战斗（无头启动时原版固有的 ProgressData / 光标报错忽略）
	local watched
	watched=$(awk '
		/watch begin/ { on = 1; next }
		/watch end/ { on = 0; next }
		on && /SCRIPT ERROR/ { cur = $0; if ((getline nxt) > 0 && nxt !~ /progress_data.gd|cursor_manager.gd/) { print cur; print nxt } }
	' "$log")
	if [ -n "$watched" ]; then
		echo
		echo "Script errors during a watched battle:"
		echo "$watched" | head -40
		st=1
	fi
	grep -aE "(suite |  ran |FAIL |[0-9]+ checks|ALL TESTS PASSED|user dir|Refusing|Mod node|unknown suite)" "$log" | grep -aoE "(suite |  ran |FAIL |[0-9]+ checks|ALL TESTS PASSED|user dir|Refusing|Mod node|unknown suite).*"
	if [ -n "$errors" ]; then
		echo
		echo "Script errors from the mod or tests:"
		echo "$errors"
		st=1
	fi
	if ! grep -q "ALL TESTS PASSED" "$log"; then
		[ $st -eq 0 ] && st=1
		echo
		echo "---- last 40 log lines ----"
		tail -40 "$log"
	fi
	return $st
}

LOGDIR=$(mktemp -d)
trap 'cleanup_compat; [ -n "$BE_KEEP_LOG" ] && cat "$LOGDIR"/*.log > "$BE_KEEP_LOG"; rm -rf "$LOGDIR"' EXIT
STATUS=0

if [ -n "$NORMAL" ]; then
	run_godot "$NORMAL" "$LOGDIR/normal.log"
	report "$LOGDIR/normal.log" $? || STATUS=1
fi

if [ "$HAS_COMPAT" -gt 0 ]; then
	for m in $COMPAT_MODS; do
		if [ ! -d "$PROJECT/other_mods/mods-unpacked/$m" ]; then
			echo "compat: $m not found in other_mods/mods-unpacked" >&2
			exit 2
		fi
		rm -rf "$PROJECT/mods-unpacked/$m"
		cp -r "$PROJECT/other_mods/mods-unpacked/$m" "$PROJECT/mods-unpacked/$m"
	done
	[ -n "$NORMAL" ] && echo
	SHARED=$(mktemp -d)
	run_godot compat "$LOGDIR/compat.log" "$SHARED"
	report "$LOGDIR/compat.log" $? || STATUS=1
	cleanup_compat
	echo
	run_godot compat_off "$LOGDIR/compat_off.log" "$SHARED"
	report "$LOGDIR/compat_off.log" $? || STATUS=1
	rm -rf "$SHARED"
fi
exit $STATUS
