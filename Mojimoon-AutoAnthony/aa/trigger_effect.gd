extends Effect

# 通用触发条款：任意触发扳机 × 任意合法载荷。
# 本效果不写入玩家 effects 字典（原版每种触发器都有自己的专用 key 和数据格式，互不通用）；
# 运行时由 aa/runtime.gd 扫描玩家持有的道具 / 角色 / 武器上的本效果并统一派发。
#
#   trigger  触发扳机 id（见 catalog.TRIGGERS）
#   param    每 N 次（kill / gold）或间隔秒数（interval）
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
export(int) var value2 := 0
export(int) var cap := 0
# 受到伤害时清空本条款累积的本波属性（原版水晶）
export(bool) var reset := false
# 同扳机的负面部分（属性类载荷）：side_stat 可为玩家属性或敌人属性，side_value 为有害方向的数值
export(String) var side_stat := ""
export(int) var side_value := 0
# grant 载荷：触发时获得的效果（单位数值）、模式（temp 本波 / perm 永久）、单位价值（估值用）
export(Resource) var grant = null
export(String) var grant_mode := "temp"
export(float) var grant_unit := 0.0


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
	e.value = int(c.value)
	e.value2 = int(c.get("value2", 0))
	e.cap = int(c.get("cap", 0))
	e.reset = bool(c.get("reset", false))
	e.side_stat = str(c.get("side_stat", ""))
	e.side_value = int(c.get("side_value", 0))
	if c.get("grant") != null:
		e.grant = c.grant.duplicate()
		e.grant_mode = c.get("grant_mode", "temp")
		e.grant_unit = float(c.get("grant_unit", 0.0))
		e.value = int(c.value)
	e.effect_sign = Effect.Sign.FROM_VALUE
	return e


func to_clause() -> Dictionary:
	return {
		"trigger": trigger, "param": param, "chance": chance, "payload": payload,
		"stat": stat, "value": value, "value2": value2, "cap": cap, "reset": reset,
		"side_stat": side_stat, "side_value": side_value,
		"grant_mode": grant_mode, "grant_unit": grant_unit,
	}


func is_downside() -> bool:
	return value < 0


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


func get_text(_player_index: int, colored: bool = true) -> String:
	var t = tr(_trigger_text(colored)) + tr("AA_SEP") + _payload_text(colored)
	if side_stat != "" and side_value != 0:
		t += tr("AA_AND") + _side_text(colored)
	return t + _cap_text()


# 负面部分：与正面同一载荷模板，数值按"有害方向"着色（敌人属性为 +，玩家属性为 −）
func _side_text(colored: bool) -> String:
	var v = side_signed()
	var k = "AA_P_TEMP_STAT"
	match payload:
		"perm_stat":
			k = "AA_P_PERM_STAT"
		"timed_stat":
			k = "AA_P_TIMED_STAT"
		"temp_stat":
			k = "AA_P_STATE_STAT" if Catalog.TRIGGERS[trigger].kind == "state" else "AA_P_TEMP_STAT"
	return tr(k).replace("{0}", _col(_signed(v), false, colored)).replace("{1}", tr(side_stat.to_upper())).replace("{2}", str(value2))


# 负面部分实际施加的数值：敌人属性为正（更强），玩家属性为负
func side_signed() -> int:
	return int(abs(side_value)) if Catalog.ENEMY_STATS.has(side_stat) else -int(abs(side_value))


func _trigger_text(colored: bool) -> String:
	var t: String
	match trigger:
		"kill":
			t = tr("AA_T_KILL") if param <= 1 else tr("AA_T_KILL_EVERY").replace("{0}", str(param))
		"gold":
			t = tr("AA_T_GOLD") if param <= 1 else tr("AA_T_GOLD_EVERY").replace("{0}", str(param))
		"crit_kill":
			t = tr("AA_T_CRIT_KILL") if param <= 1 else tr("AA_T_CRIT_KILL_EVERY").replace("{0}", str(param))
		"burning_kill":
			t = tr("AA_T_BURNING_KILL") if param <= 1 else tr("AA_T_BURNING_KILL_EVERY").replace("{0}", str(param))
		"steps":
			t = tr("AA_T_STEPS_EVERY").replace("{0}", str(max(1, param)))
		"interval":
			t = tr("AA_T_INTERVAL").replace("{0}", str(param))
		_:
			t = tr("AA_T_" + trigger.to_upper())
	if chance < 100:
		t += tr("AA_CHANCE").replace("{0}", _col(str(chance) + "%", true, colored))
	return t


func _payload_text(colored: bool) -> String:
	var good = value >= 0
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
	return ""


# grant 保存"单位"效果；实际获得的效果 = 单位 × 条款数量（诅咒会提高条款数量）
func scaled_grant():
	var d = grant.duplicate()
	d.value = grant.value * value
	return d


func _cap_text() -> String:
	var t = ""
	if cap > 0:
		t += tr("AA_CAP").replace("{0}", str(cap))
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
	s.value2 = value2
	s.cap = cap
	s.reset = reset
	s.side_stat = side_stat
	s.side_value = side_value
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
	value2 = int(s.get("value2", 0))
	cap = int(s.get("cap", 0))
	reset = bool(s.get("reset", false))
	side_stat = str(s.get("side_stat", ""))
	side_value = int(s.get("side_value", 0))
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
