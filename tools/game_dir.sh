# 选择游戏工程：由 tests/*/run_tests.sh 以 `. game_dir.sh` 引入（共享调用者的参数，需先设好 ROOT = 工作区根目录）
#   --game <目录> / --game=<目录>：工作区根目录下的目录名（如 1.2.0.4）或绝对路径；可放在任意位置，从参数中移除
#   默认：环境变量 BROTATO_GAME，否则 1.2
#   结果：PROJECT = 游戏工程的绝对路径
GAME=${BROTATO_GAME:-1.2}
_ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--game) GAME=${2:-}; shift; [ $# -gt 0 ] && shift ;;
		--game=*) GAME=${1#--game=}; shift ;;
		*) _ARGS+=("$1"); shift ;;
	esac
done
set -- ${_ARGS[@]+"${_ARGS[@]}"}
unset _ARGS
case "$GAME" in
	/*|[A-Za-z]:*) PROJECT=$GAME ;;
	*) PROJECT=$ROOT/$GAME ;;
esac
if [ ! -f "$PROJECT/project.godot" ]; then
	echo "project.godot not found in $PROJECT (use --game <dir>)" >&2
	exit 2
fi
# 测试从 res://mods/tests 加载：工程里需要指向本仓库的目录联接
if [ ! -d "$PROJECT/mods/tests" ]; then
	echo "$PROJECT/mods is missing; create the junction: New-Item -ItemType Junction -Path \"$(cygpath -w "$PROJECT")\mods\" -Target \"$(cygpath -w "$ROOT")\mods\"" >&2
	exit 2
fi
