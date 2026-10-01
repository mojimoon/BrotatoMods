extends Node

# Mojimoon-OneItemToRuleThemAllv2
# 将游戏生成的物品替换为目标物品，支持多目标 A-B-A-B 轮流、诅咒开关与原物品诅咒继承。
# 替换选项在弹窗内配置，持久化到 user://（JSON，不暴露给玩家）。

const MOD_ID = "Mojimoon-OneItemToRuleThemAllv2"
const VERSION = "1.0.0"
const SETTINGS_PATH = "user://Mojimoon-OneItemToRuleThemAllv2/settings.json"

# ============================================================
# 运行时状态（弹窗配置，持久化到 JSON）
# ============================================================
# 总开关：关闭时不做任何替换（设置保留）。
var enabled: bool = true
# 商店替换池（my_id 列表，String）。"同商店"模式的箱子也使用它。空 = 不替换。
var target_item_ids: Array = []
# 弹窗"是否诅咒"全局开关：为 true 时所有替换物都被诅咒。
var force_cursed: bool = false
# A-B-A-B 轮流计数器，跨所有 hook 全局递增（不持久化，每局重置）。
var replace_counter: int = 0

# ---------- 箱子 / T4 箱子 ----------
# 两者各有一个替换模式和一个专用替换池
enum Mode { NONE, SHOP, SEQUENTIAL, ONCE }
# NONE       不替换
# SHOP       同商店：使用商店替换池
# SEQUENTIAL 独立替换：使用专用池，A-B-A-B 轮流
# ONCE       单次替换：使用专用池，每个物品只替换一次，用完后自然随机生成
var crate_mode: int = Mode.SHOP
var crate_item_ids: Array = []
var crate_counter: int = 0
var legendary_mode: int = Mode.NONE
var legendary_item_ids: Array = []
var legendary_counter: int = 0

# ---------- 商店替换选项（弹窗内 chip 配置，默认值）----------
var cfg_replace_starting: bool = false
var cfg_replace_shop: bool = true
var cfg_replace_shop_first: bool = false	# MOJI_SHOP_ALWAYS_APPEAR：每次商店刷新固定替换一个槽位（跳过 guaranteed items）
var cfg_replace_shop_once: bool = false	# MOJI_SHOP_ONCE_PER_WAVE：每波商店依次销售所选物品各一次
# 以上三个商店选项（cfg_replace_shop / _first / _once）互斥

# 每波销售一次：player_index -> { "wave": int, "queue": Array（本波尚未出现的物品 id）}
# 不持久化，每局重置
var _shop_once_state: Dictionary = {}


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/extensions/"
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/item_service.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/run_data.gd")


func _ready() -> void:
	_register_translations()
	_load_settings()


# ============================================================
# 设置持久化（JSON，存 user://，不使用 ModConfig）
# ============================================================
func _settings_dict() -> Dictionary:
	return {
		"version": VERSION,
		"enabled": enabled,
		"target_item_ids": target_item_ids,
		"force_cursed": force_cursed,
		"cfg_replace_starting": cfg_replace_starting,
		"cfg_replace_shop": cfg_replace_shop,
		"cfg_replace_shop_first": cfg_replace_shop_first,
		"cfg_replace_shop_once": cfg_replace_shop_once,
		"crate_mode": crate_mode,
		"crate_item_ids": crate_item_ids,
		"legendary_mode": legendary_mode,
		"legendary_item_ids": legendary_item_ids
	}


# 逐字段读取，缺失字段用默认值
func _apply_settings(data: Dictionary) -> void:
	enabled = bool(data.get("enabled", true))
	target_item_ids = _id_list(data.get("target_item_ids", []))
	force_cursed = bool(data.get("force_cursed", false))
	cfg_replace_starting = bool(data.get("cfg_replace_starting", false))
	cfg_replace_shop = bool(data.get("cfg_replace_shop", true))
	cfg_replace_shop_first = bool(data.get("cfg_replace_shop_first", false))
	cfg_replace_shop_once = bool(data.get("cfg_replace_shop_once", false))
	crate_mode = _clamp_mode(data.get("crate_mode", Mode.SHOP))
	crate_item_ids = _id_list(data.get("crate_item_ids", []))
	legendary_mode = _clamp_mode(data.get("legendary_mode", Mode.NONE))
	legendary_item_ids = _id_list(data.get("legendary_item_ids", []))


static func _clamp_mode(value) -> int:
	return int(clamp(int(value), Mode.NONE, Mode.ONCE))


static func _id_list(value) -> Array:
	var ids: Array = []
	if value is Array:
		for v in value:
			if v is String:
				ids.push_back(v)
	return ids


func _save_settings() -> void:
	var dir = Directory.new()
	var dir_path = SETTINGS_PATH.get_base_dir()
	if not dir.dir_exists(dir_path):
		dir.make_dir_recursive(dir_path)
	var file = File.new()
	var err = file.open(SETTINGS_PATH, File.WRITE)
	if err != OK:
		ModLoaderLog.error("Failed to save settings: " + str(err), MOD_ID)
		return
	file.store_string(JSON.print(_settings_dict(), "\t"))
	file.close()


func _load_settings() -> void:
	var file = File.new()
	if not file.file_exists(SETTINGS_PATH):
		return
	var err = file.open(SETTINGS_PATH, File.READ)
	if err != OK:
		ModLoaderLog.error("Failed to load settings: " + str(err), MOD_ID)
		return
	var text: String = file.get_as_text()
	file.close()

	var parse_result: JSONParseResult = JSON.parse(text)
	if parse_result.error != OK or not parse_result.result is Dictionary:
		ModLoaderLog.error("Settings JSON parse error: " + parse_result.error_string, MOD_ID)
		return
	_apply_settings(parse_result.result)
	ModLoaderLog.info("Settings loaded: %d shop targets, %d crate targets, %d T4 crate targets" % [target_item_ids.size(), crate_item_ids.size(), legendary_item_ids.size()], MOD_ID)


# 导出 / 导入设置：分享码 = "OITRTA1:" + Base64(JSON)，字段与本地设置文件相同
const SHARE_PREFIX = "OITRTA1:"


func export_settings_code() -> String:
	return SHARE_PREFIX + Marshalls.utf8_to_base64(JSON.print(_settings_dict()))


# 成功返回 true；无法识别的文本不改动任何设置
func import_settings_code(code: String) -> bool:
	code = code.strip_edges()
	if not code.begins_with(SHARE_PREFIX):
		return false
	var parsed = JSON.parse(Marshalls.base64_to_utf8(code.substr(SHARE_PREFIX.length())))
	if parsed.error != OK or not parsed.result is Dictionary or not parsed.result.has("target_item_ids"):
		return false
	_apply_settings(parsed.result)
	_save_settings()
	return true


# ============================================================
# 本地化（运行时解析 translations/mojimoon_oitrta.csv，单数据源）
# 用 get_as_text + 手动 CSV 解析，避免 get_csv_line 在某些环境的异常
# ============================================================
const CSV_PATH = "res://mods-unpacked/Mojimoon-OneItemToRuleThemAllv2/translations/mojimoon_oitrta.csv"

func _register_translations() -> void:
	var file = File.new()
	if not file.file_exists(CSV_PATH):
		ModLoaderLog.error("i18n csv not found: " + CSV_PATH, MOD_ID)
		return
	var err = file.open(CSV_PATH, File.READ)
	if err != OK:
		ModLoaderLog.error("Failed to open i18n csv: " + str(err), MOD_ID)
		return
	var text: String = file.get_as_text()
	file.close()

	var lines: PoolStringArray = text.split("\n", false)
	if lines.size() < 2:
		ModLoaderLog.error("i18n csv too short: " + str(lines.size()) + " lines", MOD_ID)
		return

	# 第一行 locale header
	var header: PoolStringArray = _parse_csv_line(lines[0])
	if header.size() < 2:
		ModLoaderLog.error("i18n csv header invalid: " + str(header.size()) + " cols", MOD_ID)
		return

	var locales: Array = []
	var translations: Dictionary = {}
	for i in range(1, header.size()):
		var locale = header[i].strip_edges()
		if locale == "":
			continue
		locales.push_back(locale)
		var t = Translation.new()
		t.locale = locale
		translations[locale] = t

	# 后续每行 key + 各 locale 翻译
	for line_idx in range(1, lines.size()):
		var row: PoolStringArray = _parse_csv_line(lines[line_idx])
		if row.size() < 2:
			continue
		var key = row[0].strip_edges()
		if key == "":
			continue
		for i in range(1, min(row.size(), header.size())):
			# 支持 \n 等转义（CSV 按行解析，单元格内不能有真实换行）
			var value = row[i].c_unescape()
			if value == "":
				value = key
			translations[locales[i - 1]].add_message(key, value)

	for locale in locales:
		TranslationServer.add_translation(translations[locale])
	ModLoaderLog.info("Loaded i18n: %d locales, %d keys" % [locales.size(), lines.size() - 1], MOD_ID)


# 手动 CSV 行解析：正确处理引号包裹（含转义 ""）和逗号分隔
static func _parse_csv_line(line: String) -> PoolStringArray:
	var result: PoolStringArray = PoolStringArray()
	var current: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					current += "\""
					i += 1
				else:
					in_quotes = false
			else:
				current += ch
		else:
			if ch == "\"":
				in_quotes = true
			elif ch == ",":
				result.append(current)
				current = ""
			else:
				current += ch
		i += 1
	result.append(current)
	return result


# ============================================================
# 替换工具（供扩展脚本调用）
# ============================================================

# 在 static 上下文里访问 autoload 单例
static func _autoload(name_: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/" + name_)


# 定位本 mod 节点（路径 /root/ModLoader/<MOD_ID>）
static func _get_mod() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/ModLoader/" + MOD_ID)


# 取下一个替换物品（常规替换池）。
# - A-B-A-B 轮流：按 replace_counter 取模选择目标
# - 诅咒继承：force_cursed 或 orig_item.is_cursed 时，对新物品施加诅咒
# 返回新物品（duplicate），不修改原物品；未配置目标时原样返回。
func get_replacement(orig_item, player_index: int):
	if not enabled or target_item_ids.empty():
		return orig_item

	var target_id: String = target_item_ids[replace_counter % target_item_ids.size()]
	replace_counter += 1
	return _make_replacement(target_id, orig_item, player_index)


# 箱子 / 战利品替换，按 crate_mode 分派。不替换时原样返回。
func get_crate_replacement(orig_item, player_index: int):
	return _mode_replacement(crate_mode, crate_item_ids, "crate_counter", orig_item, player_index)


# T4 箱子替换，按 legendary_mode 分派。不替换时原样返回。
func get_legendary_replacement(orig_item, player_index: int):
	return _mode_replacement(legendary_mode, legendary_item_ids, "legendary_counter", orig_item, player_index)


func _mode_replacement(mode: int, ids: Array, counter_prop: String, orig_item, player_index: int):
	if not enabled:
		return orig_item
	if mode == Mode.SHOP:
		return get_replacement(orig_item, player_index)
	var counter: int = get(counter_prop)
	if not _mode_has_replacement(mode, ids, counter):
		return orig_item

	var target_id: String
	if mode == Mode.SEQUENTIAL:
		target_id = ids[counter % ids.size()]
	else:	# ONCE
		target_id = ids[counter]
	set(counter_prop, counter + 1)
	return _make_replacement(target_id, orig_item, player_index)


# 箱子 / T4 箱子是否可能被替换（供扩展脚本做早退判断）
func has_crate_replacement() -> bool:
	return _mode_has_replacement(crate_mode, crate_item_ids, crate_counter)


func has_legendary_replacement() -> bool:
	return _mode_has_replacement(legendary_mode, legendary_item_ids, legendary_counter)


func _mode_has_replacement(mode: int, ids: Array, counter: int) -> bool:
	if mode == Mode.SHOP:
		return not target_item_ids.empty()
	if mode == Mode.SEQUENTIAL:
		return not ids.empty()
	if mode == Mode.ONCE:
		return counter < ids.size()
	return false


# 每波销售一次：从该玩家本波的队列里取出最多 count 个物品 id（按选择顺序）。
# 每个新的波次重新装满队列；取完后返回空数组（商店恢复随机）。
func take_shop_once_ids(wave: int, player_index: int, count: int) -> Array:
	if not enabled or target_item_ids.empty() or count <= 0:
		return []
	var state = _shop_once_state.get(player_index)
	if state == null or state["wave"] != wave:
		state = {"wave": wave, "queue": target_item_ids.duplicate()}
		_shop_once_state[player_index] = state
	var ids: Array = []
	while ids.size() < count and not state["queue"].empty():
		ids.push_back(state["queue"].pop_front())
	return ids


# 按 target_id 生成替换物品，并处理诅咒。找不到目标时原样返回。
func _make_replacement(target_id: String, orig_item, player_index: int):
	var item_service = _autoload("ItemService")
	if item_service == null:
		return orig_item

	var target_data = item_service.get_element_safe(item_service.items, target_id)
	if target_data == null:
		return orig_item

	var new_item = target_data.duplicate()

	var should_curse: bool = force_cursed or (orig_item != null and orig_item.is_cursed)
	if should_curse and not new_item.is_cursed:
		new_item = _curse_item(new_item, player_index)

	return new_item


# 对物品施加诅咒。优先用 DLC abyssal_terrors 的 curse_item（参考 dlcs/dlc_1/dlc_1_data.gd:49）；
# DLC 未启用时仅标记 is_cursed（降级处理）。
# turn_randomization_off=false：使用原版"按波次提升 + 随机"的诅咒强度
# （base 40% + 2%/wave，random ±30%），与商店/箱子自然掉落的诅咒一致。
# 注：原版起始诅咒物品（如诅咒鱼钩）用 turn_randomization_off=true，固定 38%
# （40 + 2*min(20,-1)），本 mod 不沿用此固定值。
func _curse_item(item_data, player_index: int):
	var progress_data = _autoload("ProgressData")
	if progress_data != null:
		var dlc = progress_data.get_dlc_data("abyssal_terrors")
		if dlc != null and dlc.has_method("curse_item"):
			return dlc.curse_item(item_data, player_index, false)
	if item_data != null:
		item_data.is_cursed = true
	return item_data


# 重置 A-B-A-B 计数器（新一局开始时由 run_data 扩展调用）
func reset_counter() -> void:
	_shop_once_state.clear()
	replace_counter = 0
	crate_counter = 0
	legendary_counter = 0


# ============================================================
# 按钮定位 helper（兼容其他 mod，如 cave-modtools 的 CaveItemConfigBtn）
# ============================================================
# 把 btn 挂到 back_button 下，并排到已有按钮的最右侧，避免与 cave-modtools 等重叠。
# 应在 call_deferred 中调用，确保其他 mod 的按钮已就位。
static func place_config_button(back_button: Node, btn: Button) -> void:
	if back_button == null or btn == null:
		return
	back_button.add_child(btn)

	# 扫描已有 Button 子节点，找最右边的作为左邻
	var left_neighbour: Button = null
	var max_right: float = -1.0
	for child in back_button.get_children():
		if child is Button and child != btn and child.is_inside_tree():
			var right: float = child.rect_position.x + child.rect_size.x
			if right > max_right:
				max_right = right
				left_neighbour = child

	var base_x: float = back_button.rect_size.x
	if left_neighbour != null:
		base_x = left_neighbour.rect_position.x + left_neighbour.rect_size.x
	btn.rect_position = Vector2(base_x + 18.0, 0.0)

	# focus 链：只设自己的 left neighbour，不覆盖其他按钮的 right neighbour
	if left_neighbour != null:
		btn.focus_neighbour_left = btn.get_path_to(left_neighbour)
	else:
		btn.focus_neighbour_left = btn.get_path_to(back_button)
