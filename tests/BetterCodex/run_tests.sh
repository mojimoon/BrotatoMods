#!/usr/bin/env bash
# BetterCodex 无头测试
# 用法（Git Bash）：bash mods/tests/BetterCodex/run_tests.sh [normal|compat|all]（默认 normal；compat 需要时再跑）
#   normal = 只加载本 mod；compat = 同时加载 _wl-ImprovedTooltips（创意工坊 3019195689）与 RefundTools-ItemRefund（3834897339），检查兼容性
#   BC_ONLY=<名字片段> 只跑名字含该片段的测试
# - 在 1.2/ 工程里运行（BROTATO_GAME 可覆盖），APPDATA 指向临时目录隔离 user://；测试文件不打包进 mod
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PROJECT=${BROTATO_GAME:-$ROOT/1.2}
MOD=Mojimoon-BetterCodex
IT=_wl-ImprovedTooltips
IT_ZIP=${BC_IT_ZIP:-/d/SteamLibrary/steamapps/workshop/content/1942280/3019195689/_wl-ImprovedTooltips-1.10.4.zip}
RF=RefundTools-ItemRefund
RF_ZIP=${BC_RF_ZIP:-/d/SteamLibrary/steamapps/workshop/content/1942280/3834897339/ItemRefund-1.0.3.zip}
SEL=${1:-normal}
GODOT=${GODOT:-/d/env/godot_3.7-dev1/Godot_v3.7-dev1_win64.exe}

rm -rf "$PROJECT/mods-unpacked/$MOD"
mkdir -p "$PROJECT/mods-unpacked"
cp -r "$PROJECT/mods/$MOD" "$PROJECT/mods-unpacked/$MOD"

LOGDIR=$(mktemp -d)
cleanup() { rm -rf "$PROJECT/mods-unpacked/$IT" "$PROJECT/mods-unpacked/$RF" "$LOGDIR"; }
trap cleanup EXIT

run() {
	local log="$LOGDIR/$1.log" sandbox
	sandbox=$(mktemp -d)
	(cd "$PROJECT" && APPDATA=$(cygpath -w "$sandbox") BC_TEST=1 BC_MODE="$1" timeout 600 "$GODOT" --no-window --audio-driver Dummy --path . \
		-s "res://mods/tests/BetterCodex/run_bc.gd" > "$log" 2>&1)
	local st=$?
	rm -rf "$sandbox"
	[ -n "${BC_KEEP_LOG:-}" ] && cp "$log" "$BC_KEEP_LOG.$1.log"
	local errors
	errors=$(awk '
		/SCRIPT ERROR|Parse Error|Script error/ { pending = $0; next }
		pending != "" {
			if ($0 ~ /Mojimoon-BetterCodex|mods\/tests\/|ImprovedTooltips|ItemRefund/) print pending "\n" $0
			pending = ""
		}
	' "$log")
	local watched
	watched=$(awk '/watch begin/ { on = 1; next } /watch end/ { on = 0; next } on && /SCRIPT ERROR/ { cur = $0; if ((getline nxt) > 0 && nxt !~ /cursor_manager.gd|progress_data.gd|utils.gd:(250|715)/) { print cur; print nxt } }' "$log")
	[ -n "$watched" ] && errors="$errors
watched: $watched"
	echo "== $1"
	grep -aoE "(  ran |FAIL |[0-9]+ checks|ALL TESTS PASSED|Refusing|Mod node|IT loaded).*" "$log"
	if [ -n "$errors" ]; then echo; echo "Script errors:"; echo "$errors" | head -40; st=1; fi
	if ! grep -q "ALL TESTS PASSED" "$log"; then
		[ $st -eq 0 ] && st=1
		echo "---- last 40 log lines ----"; tail -40 "$log"
	fi
	return $st
}

STATUS=0
if [ "$SEL" = "normal" ] || [ "$SEL" = "all" ]; then
	rm -rf "$PROJECT/mods-unpacked/$IT"
	run normal || STATUS=1
fi
if [ "$SEL" = "compat" ] || [ "$SEL" = "all" ]; then
	TMPZ=$(mktemp -d)
	unzip -q "$IT_ZIP" -d "$TMPZ"
	unzip -q -o "$RF_ZIP" -d "$TMPZ"
	cp -r "$TMPZ/mods-unpacked/$IT" "$TMPZ/mods-unpacked/$RF" "$PROJECT/mods-unpacked/"
	rm -rf "$TMPZ"
	run compat || STATUS=1
	rm -rf "$PROJECT/mods-unpacked/$IT" "$PROJECT/mods-unpacked/$RF"
fi
exit $STATUS
