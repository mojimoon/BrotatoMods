extends Reference

# 公式：蓝图节点的整数参数可以填公式（字符串）代替固定数值，每次用到时现算。
#   名称        变量（按名称在玩家的全部蓝图间共享；以 _ 开头的是本蓝图的局部变量）；名称里有空格或符号时写成 {名称}
#   @来源       取值：@属性key（如 @stat_armor）、SOURCES 里的名称、@count:<道具 / 武器 id>、@tag:<词条>
#   其余是算式：+ - * / % ( )、FUNCS 里的函数（比较要包在 int() 里：int(x > 3) 成立为 1）。整数相除舍去小数，结果四舍五入为整数；
#   写错或除以 0 时为 0
# 公式会随分享码来自别人：只放行白名单里的字符与函数名，再交给原版 Expression 求值（没有可调用的对象）

const FUNCS = ["min", "max", "abs", "floor", "ceil", "round", "pow", "sqrt", "clamp", "sign", "randi", "float", "int"]
const SOURCES = [
	"gold", "wave", "level", "hp", "max_hp", "hp_pct", "enemies", "weapons", "items", "difficulty", "time",
	"meca_parts", "tier", "name", "target_hp",
]


static func _is_word(c: String, first: bool) -> bool:
	var o = ord(c)
	return c == "_" or c == "@" or o > 127 or (o >= 97 and o <= 122) or (o >= 65 and o <= 90) or (not first and ((o >= 48 and o <= 57) or c == ":"))


# 切成 [[是否引用, 文本]...]；花括号不成对时返回 null
static func tokens(text: String):
	var out = []
	var raw = ""
	var i = 0
	var n = text.length()
	while i < n:
		var c = text[i]
		var ref = ""
		if c == "{":
			var j = text.find("}", i)
			if j < 0:
				return null
			ref = text.substr(i + 1, j - i - 1).strip_edges()
			i = j + 1
			if ref == "":
				return null
		elif _is_word(c, true):
			var j = i
			while j < n and _is_word(text[j], j == i):
				j += 1
			var word = text.substr(i, j - i)
			var k = j
			while k < n and text[k] == " ":
				k += 1
			i = j
			# 后面跟着括号的是函数
			if k < n and text[k] == "(" and word in FUNCS:
				raw += word
				continue
			ref = word
		else:
			raw += c
			i += 1
			continue
		if raw != "":
			out.push_back([false, raw])
			raw = ""
		out.push_back([true, ref])
	if raw != "":
		out.push_back([false, raw])
	return out


# -> {"expr": Expression, "refs": [引用...]}；不合法返回 null
static func compile(text: String):
	var toks = tokens(text)
	if toks == null or toks.empty():
		return null
	var refs = []
	var src = ""
	var ok = RegEx.new()
	ok.compile("^[0-9a-z ._,+\\-*/%()<>=!&|]*$")
	for t in toks:
		if t[0]:
			if refs.find(t[1]) < 0:
				refs.push_back(t[1])
			src += "v" + str(refs.find(t[1]))
		elif ok.search(t[1]) == null:
			return null
		else:
			src += t[1]
	# 引用只当数值用：不能在它上面取成员 / 调用
	ok.compile("v[0-9]+ *[.(]|[.)] *[.v]|[.] *[a-z_]")
	if ok.search(src) != null:
		return null
	var names = PoolStringArray()
	for i in refs.size():
		names.push_back("v" + str(i))
	var ex = Expression.new()
	if ex.parse(src, names) != OK:
		return null
	return {"expr": ex, "refs": refs}


static func run(c: Dictionary, values: Array) -> int:
	var r = c.expr.execute(values, null, false)
	if c.expr.has_execute_failed() or not typeof(r) in [TYPE_INT, TYPE_REAL, TYPE_BOOL]:
		return 0
	if typeof(r) == TYPE_REAL and (is_nan(r) or is_inf(r)):
		return 0
	return int(round(float(r)))


# 描述里显示的公式：引用换成名称
static func display(text: String, mod) -> String:
	var toks = tokens(text)
	if toks == null:
		return text
	var out = ""
	for t in toks:
		out += ref_name(t[1], mod) if t[0] else t[1]
	out = out.strip_edges()
	return out if toks.size() == 1 else "(" + out + ")"


static func ref_name(ref: String, mod) -> String:
	if not ref.begins_with("@"):
		return ref
	var k = ref.substr(1)
	if k.begins_with("count:"):
		return TranslationServer.translate("BE_SRC_COUNT").replace("{0}", mod.owned_name(k.substr(6)) if mod != null else k.substr(6))
	if k.begins_with("tag:"):
		return TranslationServer.translate("BE_SRC_COUNT").replace("{0}", mod.tag_name(k.substr(4)) if mod != null else k.substr(4))
	if k in SOURCES:
		return TranslationServer.translate("BE_SRC_" + k.to_upper())
	return mod.stat_name(k).strip_edges() if mod != null else k
