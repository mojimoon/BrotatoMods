extends Node

# Mojimoon-BetterCodex：把网页图鉴（brotato.mojimoon.top）的功能搬进游戏内图鉴
#   图鉴列表：角标（价格 / 数量上限 / 来源）、搜索与筛选、临时筛选
#   详情：标签与关联道具跳转、诅咒 / 机械化 / 异变预览、攻速计算器（实际冷却）、价格计算
#   商店：右键 / C / R3 打开图鉴定位到商品或已有物品
#   武器 / 难度选择界面：当前角色的偏好标签、禁用道具、异变预览，点击打开图鉴并筛选

const MOD_ID = "Mojimoon-BetterCodex"
const MOD_DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"
const SETTINGS_PATH = "user://Mojimoon-BetterCodex.json"

var font_cache := {}	# ui/fonts.gd：按字号缓存的字体
var settings := {"badge_price": true, "badge_limit": true, "badge_source": true, "unlock_all": false, "shop_hint": true, "right_click": true, "mut_preview": "default", "hotkey": KEY_C}


func _init() -> void:
	var dir = MOD_DIR + "extensions/"
	ModLoaderMod.install_script_extension(dir + "ui/menus/pages/menu_codex.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/run_data.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/shop/item_description.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderLog.info("extensions installed", MOD_ID)
	_load_translations()
	_load_settings()
	ModLoaderLog.info("init done", MOD_ID)


# 商店：挂一个只监听输入的节点（ui/shop_hook.gd），不扩展商店脚本
func _ready() -> void:
	get_tree().connect("node_added", self, "_on_node_added")


func _on_node_added(node: Node) -> void:
	if node.filename in ["res://ui/menus/shop/shop.tscn", "res://ui/menus/shop/coop_shop.tscn"]:
		call_deferred("_attach_shop", node)


func _attach_shop(shop: Node) -> void:
	if not is_instance_valid(shop) or shop.has_node("BCShopHook"):
		return
	var hook = load(MOD_DIR + "ui/shop_hook.gd").new()
	hook.name = "BCShopHook"
	hook.shop = shop
	shop.add_child(hook)


func _load_settings() -> void:
	var f = File.new()
	if f.open(SETTINGS_PATH, File.READ) != OK:
		return
	var data = parse_json(f.get_as_text())
	f.close()
	if data is Dictionary:
		for k in data:
			settings[k] = data[k]


func save_settings() -> void:
	var f = File.new()
	if f.open(SETTINGS_PATH, File.WRITE) == OK:
		f.store_string(to_json(settings))
		f.close()


# CSV：key,zh,en,...；空格子回退：中文系 → zh，其他 → en
# 整个读成文本再拆行：从 zip 读取时逐行读 File（eof_reached / get_position）会让游戏启动卡死
func _load_translations() -> void:
	var f = File.new()
	if f.open(MOD_DIR + "translations/bettercodex.csv", File.READ) != OK:
		ModLoaderLog.error("translations not found", MOD_ID)
		return
	var lines = f.get_as_text().split("\n", false)
	f.close()
	var header = parse_csv_line(lines[0].strip_edges())
	var tables = []
	for i in range(1, header.size()):
		var t = Translation.new()
		t.locale = header[i]
		tables.push_back(t)
	var en = Array(header).find("en")
	for li in range(1, lines.size()):
		var row = parse_csv_line(lines[li].strip_edges())
		if row.size() < header.size() or row[0] == "":
			continue
		for i in range(1, header.size()):
			var v = row[i]
			if v == "":
				v = row[1] if header[i].begins_with("zh") else row[en]
			tables[i - 1].add_message(row[0], v)
	for t in tables:
		TranslationServer.add_translation(t)


# 一行 CSV（支持引号与 "" 转义；不支持字段内换行）
static func parse_csv_line(line: String) -> Array:
	var out = []
	var cur = ""
	var quoted = false
	var i = 0
	while i < line.length():
		var ch = line[i]
		if quoted:
			if ch == "\"" and i + 1 < line.length() and line[i + 1] == "\"":
				cur += "\""
				i += 1
			elif ch == "\"":
				quoted = false
			else:
				cur += ch
		elif ch == "\"":
			quoted = true
		elif ch == ",":
			out.push_back(cur)
			cur = ""
		else:
			cur += ch
		i += 1
	out.push_back(cur)
	return out
