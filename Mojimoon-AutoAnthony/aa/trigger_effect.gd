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
		"stat": stat, "value": value, "value2": value2, "cap": cap, "reset": reset,
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


func get_text(_player_index: int, colored: bool = true) -> String:
	return tr(_trigger_text(colored)) + tr("AA_SEP") + _payload_text(colored) + _cap_text()


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
			t = tr("AA_T_STEPS") if param <= 1 else tr("AA_T_STEPS_EVERY").replace("{0}", str(param))
		"interval":
			t = tr("AA_T_INTERVAL").replace("{0}", str(param))
		"explode", "crit", "ignite", "first_hit":
			t = tr("AA_T_" + trigger.to_upper()) if param <= 1 else tr("AA_T_" + trigger.to_upper() + "_EVERY").replace("{0}", str(param))
		_:
			if Catalog.FIRST_HIT_STATS.has(trigger):
				var k = "AA_T_FIRST_HIT_TYPED" if param <= 1 else "AA_T_FIRST_HIT_TYPED_EVERY"
				t = tr(k).replace("{0}", str(param)).replace("{1}", tr(Catalog.FIRST_HIT_STATS[trigger].to_upper()))
			elif Catalog.HIT_STATS.has(trigger):
				var kh = "AA_T_HIT_TYPED" if param <= 1 else "AA_T_HIT_TYPED_EVERY"
				t = tr(kh).replace("{0}", str(param)).replace("{1}", tr(Catalog.HIT_STATS[trigger].to_upper()))
			elif trigger.begins_with("hit_above_") or trigger.begins_with("hit_below_"):
				var base = "AA_T_HIT_ABOVE" if trigger.begins_with("hit_above_") else "AA_T_HIT_BELOW"
				var k2 = base if param <= 1 else base + "_EVERY"
				t = tr(k2).replace("{0}", str(param)).replace("{1}", trigger.get_slice("_", 2))
			else:
				t = tr("AA_T_" + trigger.to_upper())
	if chance < 100:
		t += tr("AA_CHANCE").replace("{0}", _col(str(chance) + "%", true, colored))
	return t


func _payload_text(colored: bool) -> String:
	var good = (value >= 0) != Catalog.ENEMY_STATS.has(stat)
	var stat_name = tr(Catalog.STAT_NAME_KEYS.get(stat, stat.to_upper())) if stat != "" else ""
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
