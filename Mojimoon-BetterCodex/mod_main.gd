extends Node

# Mojimoon-BetterCodex：把网页图鉴（brotato.mojimoon.top）的功能搬进游戏内图鉴
#   图鉴列表：角标（价格 / 数量上限 / 来源）、搜索与筛选、临时筛选
#   详情：标签与关联道具跳转、诅咒 / 机械化 / 异变预览、攻速计算器（实际冷却）、价格计算
#   商店：右键 / C / R3 打开图鉴定位到商品或已有物品
#   武器 / 难度选择界面：当前角色的偏好标签、禁用道具、异变预览，点击打开图鉴并筛选

const MOD_ID = "Mojimoon-BetterCodex"
const MOD_DIR = "res://mods-unpacked/Mojimoon-BetterCodex/"
const SETTINGS_PATH = "user://Mojimoon-BetterCodex.json"

var settings := {"badges": true}


func _init() -> void:
	var dir = MOD_DIR + "extensions/"
	ModLoaderMod.install_script_extension(dir + "ui/menus/pages/menu_codex.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	_load_translations()
	_load_settings()


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
func _load_translations() -> void:
	var f = File.new()
	if f.open(MOD_DIR + "translations/bettercodex.csv", File.READ) != OK:
		ModLoaderLog.error("translations not found", MOD_ID)
		return
	var header = f.get_csv_line()
	var tables = []
	for i in range(1, header.size()):
		var t = Translation.new()
		t.locale = header[i]
		tables.push_back(t)
	var en = Array(header).find("en")
	while not f.eof_reached():
		var row = f.get_csv_line()
		if row.size() < header.size() or row[0] == "":
			continue
		for i in range(1, header.size()):
			var v = row[i]
			if v == "":
				v = row[1] if header[i].begins_with("zh") else row[en]
			tables[i - 1].add_message(row[0], v)
	f.close()
	for t in tables:
		TranslationServer.add_translation(t)
