extends Effect

# 蓝图效果：一张"扳机 → 条件 → 效果"的节点图，挂在角色效果列表里。
# 本效果不写入玩家 effects 字典；战斗 / 商店中由 graph/runtime.gd 扫描玩家持有的本效果并派发事件。
# graph = {"nodes": [{"id", "kind", "params", "pos"}], "links": [[from_id, to_id]...], "next": 下一个 id}

const ID = "broeditor_graph"
const Catalog = preload("res://mods-unpacked/Mojimoon-BroEditor/catalog.gd")
const MAX_PATHS = 40

var graph: Dictionary = {}


static func get_id() -> String:
	return ID


static func make(g: Dictionary) -> Effect:
	var e = load("res://mods-unpacked/Mojimoon-BroEditor/graph/graph_effect.gd").new()
	e.key = ID
	e.key_hash = Keys.generate_hash(ID)
	e.custom_key_hash = Keys.empty_hash
	e.text_key = ""
	e.value = 0
	e.effect_sign = 3
	e.graph = g.duplicate(true)
	return e


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
	return graph_text(graph, colored)


static func graph_text(g: Dictionary, colored: bool = true) -> String:
	var by_id = nodes_by_id(g)
	var lines = []
	for path in paths(g):
		var parts = []
		for id in path:
			parts.push_back(node_text(by_id[id], colored))
		var head = PoolStringArray(parts.slice(0, parts.size() - 2)).join(TranslationServer.translate("BE_SEP_COND"))
		lines.push_back(head + TranslationServer.translate("BE_SEP_EFFECT") + parts[-1])
	return PoolStringArray(lines).join("\n")


static func node_text(n: Dictionary, colored: bool = true) -> String:
	var kind: String = n.kind
	var params: Dictionary = n.get("params", {})
	var t = TranslationServer.translate("BE_NT_" + kind.to_upper())
	for k in params:
		var v = params[k]
		var s = str(v)
		match k:
			"stat":
				s = _stat_name(str(v))
			"value":
				s = _col(("+" if int(v) >= 0 and kind in ["temp_stat", "perm_stat", "timed_stat"] else "") + str(int(v)), int(v) >= 0, colored)
			"pct", "n", "secs":
				s = str(int(v))
			"ref":
				s = _grant_text(n, colored)
			"mode":
				s = TranslationServer.translate("BE_MODE_" + str(v).to_upper())
		t = t.replace("{" + k + "}", s)
	return t


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
