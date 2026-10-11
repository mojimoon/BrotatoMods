extends Effect

# 通用触发条款：任意触发扳机 × 任意合法载荷。
# 本效果不写入玩家 effects 字典（原版每种触发器都有自己的专用 key 和数据格式，互不通用）；
# 运行时由 aa/runtime.gd 扫描玩家持有的道具 / 角色 / 武器上的本效果并统一派发。
#
#   trigger  触发扳机 id（见 catalog.TRIGGERS）
#   param    每 N 次（gate = every 的扳机）或间隔秒数（interval）
#   dmg_type 限定伤害类型的扳机（TYPED_TRIGGERS）的伤害缩放属性
#   chance   每次触发的几率（%）
#   payload  载荷 id（见 catalog.PAYLOADS）
#   stat     属性 key（属性类载荷）或伤害缩放属性（damage / explode）
#   value    属性数值 / 回复量 / 材料 / 经验 / 伤害百分比
#   value2   限时属性的持续秒数
#   cap      每波最多触发次数（0 = 不限）

const ID = "aa_trigger"
const Catalog = preload("res://mods-unpacked/Mojimoon-AutoAnthony/aa/catalog.gd")

export(String) var trigger := ""
export(int) var param := 1
export(int) var chance := 100
export(String) var payload := ""
export(String) var stat := ""
export(String) var dmg_type := ""
export(int) var value2 := 0
export(int) var cap := 0
# 受到伤害时清空本条款累积的本波属性（原版水晶）
export(bool) var reset := false
# grant 载荷：触发时获得的效果（单位数值）、模式（temp 本波 / perm 永久）、单位价值（估值用）
export(Resource) var grant = null
export(String) var grant_mode := "temp"
export(float) var grant_unit := 0.0
# 商店扳机的计次（每 N 次刷新 / 购买）
var shop_count := 0

# 诅咒探针（装进道具 / 武器时 probe()）：value 固定为 CURSE_PROBE、效果符号为正面，原版诅咒
# （dlc_1_data.curse_item 的通用分支）把它放大为 ceil(CURSE_PROBE × (1 + 系数))，据此还原系数；
# 真实数值存在 amount。文本 / 运行时 / 估值读 live()：未诅咒为原数值，诅咒后按条款规则重算（见 _curse）
#（原版 DLC 脚本在 DLC 资源包里，ProgressData._ready 才加载，晚于 ModLoader 安装脚本扩展，无法扩展 curse_item）
const CURSE_PROBE = 1000
const STAT_PAYLOADS = ["temp_stat", "perm_stat", "timed_stat"]
export(bool) var probed := false
export(int) var amount := 0
var _live = null


static func get_id() -> String:
	return ID


static func make(c: Dictionary) -> Effect:
	var e = load("res://mods-unpacked/Mojimoon-AutoAnthony/aa/trigger_effect.gd").new()
	e.key = ID
	e.key_hash = Keys.generate_hash(ID)
	e.custom_key_hash = Keys.empty_hash
	e.text_key = ""
	e.trigger = c.trigger
	e.param = int(c.get("param", 1))
	e.chance = int(c.get("chance", 100))
	e.payload = c.payload
	e.stat = c.get("stat", "")
	e.dmg_type = c.get("dmg_type", "")
	e.value = int(c.value)
	e.value2 = int(c.get("value2", 0))
	e.cap = int(c.get("cap", 0))
	e.reset = bool(c.get("reset", false))
	if c.get("grant") != null:
		e.grant = c.grant.duplicate()
		e.grant_mode = c.get("grant_mode", "temp")
		e.grant_unit = float(c.get("grant_unit", 0.0))
		e.value = int(c.value)
	# 敌人属性提高是坏事：显式标为负面，原版诅咒系统会减弱它、文本按负面着色
	e.effect_sign = Effect.Sign.NEGATIVE if Catalog.ENEMY_STATS.has(e.stat) else Effect.Sign.FROM_VALUE
	return e


# 转成探针形式（生成阶段 value 仍是真实数值，装进资源时调用；可重复调用）
func probe() -> void:
	if probed:
		return
	amount = value
	value = CURSE_PROBE
	effect_sign = Effect.Sign.POSITIVE
	probed = true
	_live = null


static func probe_all(effects: Array) -> void:
	for e in effects:
		if e.has_method("probe"):
			e.probe()


func curse_modifier() -> float:
	return float(value) / CURSE_PROBE - 1.0 if probed and value > CURSE_PROBE else 0.0


# 实际生效的条款（value = 真实数值，未诅咒时与 amount 相同）；非探针形式（生成阶段 / 旧存档）就是自己
func live():
	if not probed:
		return self
	if _live == null:
		var v = live_base()
		var m = curse_modifier()
		if m > 0.0:
			_curse(v, m)
		_live = v
	return _live


# 条款对玩家的好坏 E：属性载荷 = 该属性在原版效果里的好方向 × 数值正负；grant = 被获得效果的原版符号；其余 = 数值正负
static func goodness(v) -> int:
	if v.payload == "grant":
		if v.grant == null:
			return 0
		var g = v.scaled_grant()
		var s = g.get_sign(g.effect_sign, g.value)
		return 1 if s in [Effect.Sign.POSITIVE, Effect.Sign.OVERRIDE] else (-1 if s == Effect.Sign.NEGATIVE else 0)
	if v.value == 0:
		return 0
	var sv = 1 if v.value > 0 else -1
	if v.payload in STAT_PAYLOADS:
		var m = _mod()
		return (m.good_dir(v.stat) if m != null else 1) * sv
	return sv


# 按系数 m 诅咒条款 v（就地）：每 N 次的扳机诅咒 N（方向 -E），否则诅咒载荷（方向 E；限时属性连同持续时间）；
# E = 0 不变。方向交给原版：做成代理效果放进临时道具调 curse_item（属性载荷用属性 key，原版按 key 的特判同样生效）
static func _curse(v, m: float) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var pd = tree.root.get_node_or_null("ProgressData") if tree != null and tree.root != null else null
	var dlc = pd.get_dlc_data("abyssal_terrors") if pd != null else null
	var e_sign = goodness(v)
	if dlc == null or e_sign == 0:
		return
	var proxies = []
	if Catalog.TRIGGERS[v.trigger].gate == "every":
		proxies.push_back(_proxy("param", "aa_param", v.param, -e_sign))
	elif v.payload == "grant":
		var g = v.scaled_grant()
		g.resource_name = "grant"
		proxies.push_back(g)
	else:
		proxies.push_back(_proxy("value", v.stat if v.payload in STAT_PAYLOADS else "aa_param", v.value, e_sign))
		if v.payload == "timed_stat":
			proxies.push_back(_proxy("value2", "aa_param", v.value2, e_sign))
	var item = load("res://items/global/item_data.gd").new()
	item.my_id = "aa_trigger_curse"
	item.effects = proxies
	# 用给定系数：关掉随机，并临时压低基础系数，使 max(最低系数, 基础系数) = 给定系数
	var base = dlc.cursed_item_base_percent_modifier
	dlc.cursed_item_base_percent_modifier = -100000
	var cursed = dlc.curse_item(item, 0, true, m)
	dlc.cursed_item_base_percent_modifier = base
	for ce in cursed.effects:
		match str(ce.resource_name):
			"param":
				v.param = int(max(1, ce.value))
			"value":
				v.value = int(ce.value)
			"value2":
				v.value2 = int(max(1, ce.value))
			"grant":
				# 诅咒后的效果就是实际获得的效果（数量并入效果本身）
				v.grant = ce
				v.grant_unit *= v.value
				v.value = 1


# 方向 +1：|值| 按原版正面放大；-1：按原版负面缩小（与数值本身的正负无关）
static func _proxy(field: String, key: String, val: int, dir: int) -> Effect:
	var e = Effect.new()
	e.key = key
	e.value = val
	e.effect_sign = Effect.Sign.POSITIVE if dir > 0 else Effect.Sign.NEGATIVE
	e.resource_name = field
	e._generate_hashes()
	return e


static func _mod():
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/ModLoader/Mojimoon-AutoAnthony")


func to_clause() -> Dictionary:
	return {
		"trigger": trigger, "param": param, "chance": chance, "payload": payload,
		"stat": stat, "dmg_type": dmg_type, "value": value, "value2": value2, "cap": cap, "reset": reset,
		"grant_mode": grant_mode, "grant_unit": grant_unit,
	}


func is_downside() -> bool:
	return value < 0 or Catalog.ENEMY_STATS.has(stat)


# 不写入 effects 字典；只通知运行时重建触发索引
func apply(_player_index: int) -> void:
	_mark_dirty()


func unapply(_player_index: int) -> void:
	_mark_dirty()


func _mark_dirty() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var m = tree.root.get_node_or_null("/root/ModLoader/Mojimoon-AutoAnthony")
	if m != null:
		m.triggers_dirty = true


func get_icon(_player_index: int) -> Texture:
	if stat != "" and payload in ["temp_stat", "perm_stat", "timed_stat"]:
		var icon = ItemService.get_stat_small_icon(Keys.generate_hash(stat))
		if icon != null:
			return icon
	return UIService.empty_stat


func _col(text: String, good: bool, colored: bool) -> String:
	if not colored:
		return text
	var c = ProgressData.settings.color_positive if good else ProgressData.settings.color_negative
	return "[color=#" + c + "]" + text + "[/color]"


func _signed(v: int) -> String:
	return ("+" if v >= 0 else "") + str(v)


# 句式按语言（AA_FMT / AA_FMT_CHANCE，同原版）：中日韩、土耳其语"触发 + 效果"，其余语言"效果 + 触发"
func get_text(_player_index: int, colored: bool = true) -> String:
	if probed:
		return live().get_text(_player_index, colored)
	var k = "AA_FMT" if chance >= 100 else "AA_FMT_CHANCE"
	# 获得效果：内层是一整句原版效果文本，效果在前的语言改为"触发：效果"（{T} = 首字母大写的触发）
	if payload == "grant":
		k = "AA_FMT_GRANT" if chance >= 100 else "AA_FMT_GRANT_CHANCE"
	var t = _trigger_text(colored)
	# 短条件直接接效果（"移动时+5%速度"）；获得的是计数型效果（"每2构筑物会……"）时补上长条件的分隔符，避免两个"每"连读
	var sep = tr("AA_LONG_SEP").strip_edges() if tr("AA_LONG_SEP") != "AA_LONG_SEP" else ""
	if sep != "" and payload == "grant" and grant != null and grant.get_script() != null 			and grant.get_script().resource_path.ends_with("gain_stat_for_every_stat_effect.gd") and not t.ends_with(sep):
		t += sep
	var tc = t.lstrip(" ,")
	if tc.length() > 0:
		tc = tc.substr(0, 1).to_upper() + tc.substr(1)
	var s = tr(k).replace("{T}", tc).replace("{t}", t).replace("{p}", _payload_text(colored)) 		.replace("{c}", _col(str(chance) + "%", true, colored))
	return s + _cap_text()


# 通用模板：单次 AA_T_X、计次 AA_T_X_EVERY（{0} = 次数），几率由 AA_FMT_CHANCE 包裹；{1} = 伤害类型 / 生命百分比 / 属性
func _trigger_text(_colored: bool) -> String:
	if trigger == "interval":
		return tr("AA_T_INTERVAL").replace("{0}", str(param))
	var base = "AA_T_" + trigger.to_upper()
	var arg = ""
	if trigger in Catalog.TYPED_TRIGGERS:
		arg = tr(dmg_type.to_upper())
	elif trigger.begins_with("hit_above_") or trigger.begins_with("hit_below_"):
		base = "AA_T_HIT_ABOVE" if trigger.begins_with("hit_above_") else "AA_T_HIT_BELOW"
		arg = trigger.get_slice("_", 2)
	elif trigger == "buy_stat":
		# 条件属性 = 效果属性（同原版雪球）
		arg = tr(stat.to_upper())
	if param > 1 and Catalog.TRIGGERS[trigger].gate == "every":
		base += "_EVERY"
	return tr(base).replace("{0}", str(param)).replace("{1}", arg)


func _payload_text(colored: bool) -> String:
	var good = (value >= 0) != Catalog.ENEMY_STATS.has(stat)
	var stat_name = tr(stat.to_upper()) if stat != "" else ""
	match payload:
		"temp_stat":
			var k = "AA_P_STATE_STAT" if Catalog.TRIGGERS[trigger].kind == "state" else "AA_P_TEMP_STAT"
			return tr(k).replace("{0}", _col(_signed(value), good, colored)).replace("{1}", stat_name)
		"perm_stat":
			return tr("AA_P_PERM_STAT").replace("{0}", _col(_signed(value), good, colored)).replace("{1}", stat_name)
		"timed_stat":
			return tr("AA_P_TIMED_STAT").replace("{0}", _col(_signed(value), good, colored)).replace("{1}", stat_name).replace("{2}", str(value2))
		"heal":
			return tr("AA_P_HEAL").replace("{0}", _col(str(value), good, colored))
		"gold":
			if value < 0:
				return tr("AA_P_LOSE_GOLD").replace("{0}", _col(str(-value), good, colored))
			return tr("AA_P_GOLD").replace("{0}", _col(str(value), good, colored))
		"xp":
			return tr("AA_P_XP").replace("{0}", _col(str(value), good, colored))
		"damage":
			return tr("AA_P_DAMAGE").replace("{0}", _col(str(value) + "%", good, colored)).replace("{1}", stat_name)
		"grant":
			var inner = scaled_grant().get_text(0, colored) if grant != null else ""
			var k = "AA_P_GRANT_PERM" if grant_mode == "perm" else ("AA_P_GRANT_STATE" if Catalog.TRIGGERS[trigger].kind == "state" else "AA_P_GRANT_TEMP")
			return tr(k).replace("{0}", inner)
		"explode":
			return tr("AA_P_EXPLODE").replace("{0}", _col(str(value) + "%", good, colored)).replace("{1}", stat_name)
		"hp_dmg":
			# 原版的百分比写法：头目和精英为 1/10（巨型带 10% / 1%）
			var boss = str(stepify(value / 10.0, 0.1)).trim_suffix(".0") + "%"
			return tr("AA_P_HP_DMG").replace("{0}", _col(str(value) + "%", good, colored)).replace("{1}", boss)
		"ignite":
			return tr("AA_P_IGNITE").replace("{0}", _col(str(value), good, colored)).replace("{1}", str(Catalog.IGNITE_TICKS))
		"slow":
			return tr("AA_P_SLOW").replace("{0}", _col(str(value) + "%", good, colored)).replace("{1}", str(int(min(90, value * 4))) + "%")
		"fruit":
			return tr("AA_P_FRUIT_1" if value == 1 else "AA_P_FRUIT").replace("{0}", _col(str(value), good, colored))
		"rand_stats":
			return tr("AA_P_RAND_STATS_1" if value == 1 else "AA_P_RAND_STATS").replace("{0}", _col(str(value), good, colored))
		"vuln":
			return tr("AA_P_VULN").replace("{0}", _col(str(value) + "%", good, colored)).replace("{1}", str(value2))
	return ""


# grant 保存"单位"效果；实际获得的效果 = 单位 × 条款数量（诅咒会提高条款数量）
func scaled_grant():
	var d = grant.duplicate()
	d.value = grant.value * value
	return d


func _cap_text() -> String:
	var t = ""
	if cap > 0:
		# 属性类效果写每波可获得的总量（原版"每波最大值：+8"），其余写次数
		if payload in ["temp_stat", "perm_stat"]:
			t += tr("AA_CAP_STAT").replace("{0}", _signed(value * cap))
		else:
			t += tr("AA_CAP_1") if cap == 1 else tr("AA_CAP").replace("{0}", str(cap))
	if reset:
		t += tr("AA_RESET_ON_HIT")
	return t


func serialize() -> Dictionary:
	var s = .serialize()
	s.trigger = trigger
	s.param = param
	s.chance = chance
	s.payload = payload
	s.stat = stat
	s.dmg_type = dmg_type
	s.value2 = value2
	s.cap = cap
	s.reset = reset
	s.grant_mode = grant_mode
	s.grant_unit = grant_unit
	s.grant = grant.serialize() if grant != null else null
	s.probed = probed
	s.amount = amount
	# 诅咒后的条款原样存档（原版个别特判带随机，如闪避上限 72~76，读档不重抽）
	if probed and curse_modifier() > 0.0:
		var v = live()
		s.live = {"param": v.param, "value": v.value, "value2": v.value2, "grant_unit": v.grant_unit,
			"grant": v.grant.serialize() if v.grant != null else null}
	return s


func deserialize_and_merge(s: Dictionary) -> void:
	.deserialize_and_merge(s)
	trigger = str(s.get("trigger", ""))
	param = int(s.get("param", 1))
	chance = int(s.get("chance", 100))
	payload = str(s.get("payload", ""))
	stat = str(s.get("stat", ""))
	dmg_type = str(s.get("dmg_type", ""))
	value2 = int(s.get("value2", 0))
	cap = int(s.get("cap", 0))
	reset = bool(s.get("reset", false))
	grant_mode = str(s.get("grant_mode", "temp"))
	grant_unit = float(s.get("grant_unit", 0.0))
	grant = _load_effect(s.get("grant", null))
	probed = bool(s.get("probed", false))
	amount = int(s.get("amount", value))
	_live = null
	var ls = s.get("live", null)
	if probed and ls is Dictionary:
		var v = live_base()
		v.param = int(ls.get("param", param))
		v.value = int(ls.get("value", amount))
		v.value2 = int(ls.get("value2", value2))
		v.grant_unit = float(ls.get("grant_unit", grant_unit))
		if ls.get("grant") is Dictionary:
			v.grant = _load_effect(ls.grant)
		_live = v


# 未诅咒的实际条款（读档还原诅咒结果用）
func live_base():
	var v = duplicate()
	v.probed = false
	v.value = amount
	v.effect_sign = Effect.Sign.NEGATIVE if Catalog.ENEMY_STATS.has(stat) else Effect.Sign.FROM_VALUE
	return v


static func _load_effect(gs):
	if gs is Dictionary:
		for script in ItemService.effects:
			if script.get_id() == gs.get("effect_id", ""):
				var g = script.new()
				g.deserialize_and_merge(gs)
				return g
	return null
