extends Reference

# 本 mod 新增界面的字体：按设置里的字体大小（ProgressData.settings.font_size）缩放的游戏字体副本，按字号缓存
# （游戏本身只缩放 font_smallest_text；我们的控件用这里的字体才能一起跟随）

const BASE = preload("res://resources/fonts/actual/base/font_22.tres")
const OUTLINE = preload("res://resources/fonts/actual/base/font_26_outline.tres")


static func scale() -> float:
	return float(ProgressData.settings.get("font_size", 1.0))


# size = 字体大小为 1 时的字号；fixed = 不缩放（列表元素上的角标：元素大小固定）
static func font(size: int, outline: bool = false, fixed: bool = false) -> DynamicFont:
	var px = size if fixed else int(round(size * scale()))
	var key = ("o" if outline else "n") + str(px)
	# 缓存放在 mod 节点上（随场景树释放）；放在 Engine 的 meta 里会在字体系统关闭后才释放，退出游戏时崩溃
	var m = Engine.get_main_loop().root.get_node_or_null("ModLoader/Mojimoon-BetterCodex")
	var cache = m.font_cache if m != null else {}
	if not cache.has(key):
		var f = (OUTLINE if outline else BASE).duplicate()
		f.size = px
		cache[key] = f
	return cache[key]
