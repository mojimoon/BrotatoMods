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
	grant = null
	var gs = s.get("grant", null)
	if gs is Dictionary:
		for script in ItemService.effects:
			if script.get_id() == gs.get("effect_id", ""):
				grant = script.new()
				grant.deserialize_and_merge(gs)
				break
