extends Effect

# 蓝图效果：一张"扳机 → 条件 → 效果"的节点图，挂在角色效果列表里。
# 本效果不写入玩家 effects 字典；战斗 / 商店中由 graph/runtime.gd 扫描玩家持有的本效果并派发事件。
# graph = {"nodes": [{"id", "kind", "params", "pos"}], "links": [[from_id, to_id]...], "next": 下一个 id}

const ID = "broeditor_graph"
const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const MAX_PATHS = 40
# 诅咒探针：value 固定为 CURSE_PROBE、效果符号为"正面"。原版诅咒把它当作普通正面效果放大为
# ceil(CURSE_PROBE × (1 + 诅咒系数))，据此还原诅咒系数，再按系数诅咒图里的数值（mod_main.curse_graph）
const CURSE_PROBE = 1000

var graph: Dictionary = {}
var _cursed: Dictionary = {}	# 诅咒系数 -> 诅咒后的图（缓存）


static func get_id() -> String:
	return ID


static func make(g: Dictionary) -> Effect:
	var e = load("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd").new()
	e.key = ID
	e.key_hash = Keys.generate_hash(ID)
	e.custom_key_hash = Keys.empty_hash
	e.text_key = ""
	e.value = CURSE_PROBE
	e.effect_sign = 0	# POSITIVE
	e.graph = g.duplicate(true)
	return e


# 诅咒系数（未诅咒为 0；旧存档里 value = 0 也视为未诅咒）
func curse_modifier() -> float:
	return max(0.0, float(value) / CURSE_PROBE - 1.0) if value > CURSE_PROBE else 0.0


# 实际生效的图：未诅咒为原图；诅咒后为数值按系数调整后的图
func live_graph() -> Dictionary:
	var m = curse_modifier()
	if m <= 0.0:
		return graph
	if not _cursed.has(m):
		var mod = _mod()
		_cursed[m] = mod.curse_graph(graph, m) if mod != null else graph
	return _cursed[m]


static func _mod():
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/ModLoader/Mojimoon-BroEditor")


func apply(_player_index: int) -> void:
	_mark_dirty()


func unapply(_player_index: int) -> void:
	_mark_dirty()


func _mark_dirty() -> void:
	var m = _mod()
	if m != null:
		m.graph_dirty = true


func duplicate(subresources := false) -> Resource:
	var d = .duplicate(subresources)
	d.graph = graph.duplicate(true)
	return d


# ============================================================
# 图结构
# ============================================================
static func nodes_by_id(g: Dictionary) -> Dictionary:
	var out = {}
	for n in g.get("nodes", []):
		out[int(n.id)] = n
	return out


static func outgoing(g: Dictionary, id: int) -> Array:
	var out = []
	for l in g.get("links", []):
		if int(l[0]) == id:
			out.push_back(int(l[1]))
	return out


# 从扳机出发、终止于效果的全部路径（节点 id 列表；遇到环停止）
static func paths(g: Dictionary) -> Array:
	var by_id = nodes_by_id(g)
	var out = []
	for n in g.get("nodes", []):
		if Catalog.node_type(n.kind) == "trigger":
			_walk_paths(g, by_id, [int(n.id)], out)
	return out


static func _walk_paths(g: Dictionary, by_id: Dictionary, path: Array, out: Array) -> void:
	if out.size() >= MAX_PATHS:
		return
	for to in outgoing(g, path[-1]):
		if to in path or not by_id.has(to):
			continue
		var t = Catalog.node_type(by_id[to].kind)
		if t == "effect":
			out.push_back(path + [to])
		elif t == "cond":
			_walk_paths(g, by_id, path + [to], out)


# ============================================================
# 文本：每条路径一行 "扳机，条件，条件：效果"
# ============================================================
func get_text(_player_index: int, colored: bool = true) -> String:
	return graph_text(live_graph(), colored)


# 一条路径的文本，句式同 AutoAnthony / 原版："扳机 + 效果"，几率与"每 N 次"并入句式，
# 其余条件与每波上限以括号后缀接在后面。语序由各语言的 BE_FMT* 决定（中文"扳机在前"，英文"效果在前"）
static func graph_text(g: Dictionary, colored: bool = true) -> String:
	var by_id = nodes_by_id(g)
	var lines = []
	for path in paths(g):
		lines.push_back(path_text(by_id, path, colored))
	return PoolStringArray(lines).join("\n")


static func _tr(k: String) -> String:
	return TranslationServer.translate(k)


static func _p(n: Dictionary, k: String, default = 0):
	return n.get("params", {}).get(k, default)


static func path_text(by_id: Dictionary, path: Array, colored: bool = true) -> String:
	var trig = by_id[path[0]]
	var eff = by_id[path[-1]]
	var chance = 100.0
	var every = 1
	var suffix = ""
	for i in range(1, path.size() - 1):
		var n = by_id[path[i]]
		match n.kind:
			"chance":
				chance *= float(_p(n, "pct", 100)) / 100.0
			"every":
				every *= max(1, int(_p(n, "n", 1)))
			"cap":
				var c = int(_p(n, "n", 1))
				suffix += _tr("BE_CAP_1") if c == 1 else _tr("BE_CAP").replace("{0}", str(c))
			_:
				suffix += _cond_text(n)
	var t = _trigger_text(trig, every)
	if every > 1 and _tr("BE_TX_" + trig.kind.to_upper() + "_EVERY") == "BE_TX_" + trig.kind.to_upper() + "_EVERY":
		# 没有"每 N 次"句式的扳机：作为后缀
		suffix = _tr("BE_CX_EVERY").replace("{n}", str(every)) + suffix
	var k = "BE_FMT_GRANT" if eff.kind == "grant" else "BE_FMT"
	if chance < 100.0:
		k += "_CHANCE"
	var tc = t.strip_edges().lstrip(",，")
	if tc.length() > 0:
		tc = tc.substr(0, 1).to_upper() + tc.substr(1)
	var c_text = str(stepify(chance, 0.1)).trim_suffix(".0") + "%"
	return _tr(k).replace("{T}", tc).replace("{t}", t).replace("{p}", _payload_text(eff, trig.kind, colored)).replace("{c}", _col(c_text, true, colored)) + suffix


static func _trigger_text(trig: Dictionary, every: int) -> String:
	var base = "BE_TX_" + trig.kind.to_upper()
	if every > 1 and _tr(base + "_EVERY") != base + "_EVERY":
		return _tr(base + "_EVERY").replace("{0}", str(every))
	return _tr(base).replace("{0}", str(int(_p(trig, "secs", 1))))


static func _cond_text(n: Dictionary) -> String:
	var t = _tr("BE_CX_" + n.kind.to_upper())
	for k in ["n", "pct", "secs"]:
		t = t.replace("{" + k + "}", str(int(_p(n, k, 0))))
	return t.replace("{stat}", _stat_name(str(_p(n, "stat", ""))))


static func _signed(v: int) -> String:
	return ("+" if v >= 0 else "") + str(v)


static func _payload_text(n: Dictionary, trigger_kind: String, colored: bool) -> String:
	var v = int(_p(n, "value", 0))
	var good = v >= 0
	var stat = _stat_name(str(_p(n, "stat", "")))
	var state = trigger_kind in Catalog.STATE_TRIGGERS
	match n.kind:
		"temp_stat":
			return _tr("BE_PX_STATE_STAT" if state else "BE_PX_TEMP_STAT").replace("{0}", _col(_signed(v), good, colored)).replace("{1}", stat)
		"perm_stat":
			return _tr("BE_PX_PERM_STAT").replace("{0}", _col(_signed(v), good, colored)).replace("{1}", stat)
		"timed_stat":
			return _tr("BE_PX_TIMED_STAT").replace("{0}", _col(_signed(v), good, colored)).replace("{1}", stat).replace("{2}", str(int(_p(n, "secs", 1))))
		"heal_hp":
			return _tr("BE_PX_HEAL").replace("{0}", _col(str(v), good, colored))
		"add_gold":
			if v < 0:
				return _tr("BE_PX_LOSE_GOLD").replace("{0}", _col(str(-v), false, colored))
			return _tr("BE_PX_GOLD").replace("{0}", _col(str(v), true, colored))
		"xp":
			return _tr("BE_PX_XP").replace("{0}", _col(str(v), good, colored))
		"damage", "explode":
			var pct = str(int(_p(n, "pct", 100))) + "%"
			return _tr("BE_PX_" + n.kind.to_upper()).replace("{0}", _col(pct, true, colored)).replace("{1}", stat)
		"hp_dmg":
			var pct = int(_p(n, "pct", 1))
			return _tr("BE_PX_HP_DMG").replace("{0}", _col(str(pct) + "%", true, colored)).replace("{1}", str(stepify(pct / 10.0, 0.1)).trim_suffix(".0") + "%")
		"ignite":
			return _tr("BE_PX_IGNITE").replace("{0}", _col(str(v), true, colored)).replace("{1}", "3")
		"slow":
			var pct = int(_p(n, "pct", 10))
			return _tr("BE_PX_SLOW").replace("{0}", _col(str(pct) + "%", true, colored)).replace("{1}", str(int(min(90, pct * 4))) + "%")
		"fruit":
			return _tr("BE_PX_FRUIT_1" if v == 1 else "BE_PX_FRUIT").replace("{0}", _col(str(v), good, colored))
		"rand_stats":
			return _tr("BE_PX_RAND_STATS_1" if v == 1 else "BE_PX_RAND_STATS").replace("{0}", _col(str(v), good, colored))
		"grant":
			var inner = _grant_text(n, colored)
			var k = "BE_PX_GRANT_PERM" if str(_p(n, "mode", "temp")) == "perm" else ("BE_PX_GRANT_STATE" if state else "BE_PX_GRANT_TEMP")
			return _tr(k).replace("{0}", inner)
	return ""


static func _grant_text(n: Dictionary, colored: bool) -> String:
	var m = _mod()
	var ref = n.get("params", {}).get("ref")
	if m == null or not ref is Dictionary:
		return TranslationServer.translate("BE_GRANT_NONE")
	var e = m.make_effect(ref)
	if e == null:
		return TranslationServer.translate("BE_GRANT_NONE")
	e.value = e.value * int(n.params.get("n", 1))
	return m.effect_text(e, colored)


static func _stat_name(key: String) -> String:
	var m = _mod()
	return m.stat_name(key) if m != null else key


static func _col(text: String, good: bool, colored: bool) -> String:
	if not colored:
		return text
	var c = ProgressData.settings.color_positive if good else ProgressData.settings.color_negative
	return "[color=#" + c + "]" + text + "[/color]"


# ============================================================
# 存档
# ============================================================
func serialize() -> Dictionary:
	var s = .serialize()
	s.graph = JSON.print(graph)
	return s


func deserialize_and_merge(s: Dictionary) -> void:
	.deserialize_and_merge(s)
	graph = {}
	var parsed = JSON.parse(str(s.get("graph", "{}")))
	if parsed.error == OK and parsed.result is Dictionary:
		graph = parsed.result


# ============================================================
# 编辑（数据层；界面与"拆解"共用）
# ============================================================
static func new_graph() -> Dictionary:
	return {"nodes": [], "links": [], "next": 1}


static func add_node(g: Dictionary, kind: String, pos: Vector2, params = null) -> int:
	var id = int(g.get("next", 1))
	g.next = id + 1
	var p = Catalog.default_params(kind)
	if params is Dictionary:
		for k in params:
			p[k] = params[k]
	g.nodes.push_back({"id": id, "kind": kind, "params": p, "pos": [pos.x, pos.y]})
	return id


static func add_link(g: Dictionary, from_id: int, to_id: int) -> void:
	for l in g.links:
		if int(l[0]) == from_id and int(l[1]) == to_id:
			return
	g.links.push_back([from_id, to_id])


static func remove_node(g: Dictionary, id: int) -> void:
	var nodes = []
	for n in g.nodes:
		if int(n.id) != id:
			nodes.push_back(n)
	g.nodes = nodes
	var links = []
	for l in g.links:
		if int(l[0]) != id and int(l[1]) != id:
			links.push_back(l)
	g.links = links


# 原版触发型效果 -> 一条路径（扳机 → 条件 → 效果）；不支持的返回 false
static func split_native(g: Dictionary, e, origin: Vector2) -> bool:
	if e == null or not Catalog.NATIVE_SPLIT.has(e.custom_key):
		return false
	var d = Catalog.NATIVE_SPLIT[e.custom_key]
	var prev = add_node(g, d[0], origin)
	var x = origin.x
	for c in d[1]:
		x += 300
		var cid = add_node(g, c[0], Vector2(x, origin.y), c[1])
		add_link(g, prev, cid)
		prev = cid
	var eid = add_node(g, d[2], Vector2(x + 300, origin.y), {"stat": e.key, "value": e.value})
	add_link(g, prev, eid)
	return true
