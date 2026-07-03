extends Node

# Mojimoon-OneItemToRuleThemAll
# 将游戏生成的物品替换为目标物品，支持多目标 A-B-A-B 轮流、诅咒开关与原物品诅咒继承。
# 替换选项在弹窗内配置（不再使用 mod config），仅存内存，每局重选。

const MOD_ID = "Mojimoon-OneItemToRuleThemAll"
const VERSION = "1.0.0"

# ============================================================
# 运行时状态（每局开始前在弹窗配置，仅存内存）
# ============================================================
# 玩家选中的目标物品 my_id 列表（String）。空 = 不替换。
var target_item_ids: Array = []
# 弹窗"是否诅咒"全局开关：为 true 时所有替换物都被诅咒。
var force_cursed: bool = false
# A-B-A-B 轮流计数器，跨所有 hook 全局递增。
var replace_counter: int = 0

# ---------- 替换选项（弹窗内 checkbox 配置，默认值）----------
var cfg_replace_starting: bool = false
var cfg_replace_shop: bool = true
var cfg_replace_shop_first: bool = false	# 仅替换商店第一个（不替换锁住的）
var cfg_replace_crate: bool = true
var cfg_replace_legendary_crate: bool = false


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/extensions/"
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/item_service.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/run_data.gd")


func _ready() -> void:
	_register_translations()


# ============================================================
# 本地化（参考 cave-modtools；用程序化 Translation 避免 .translation 二进制依赖）
# ============================================================
const _I18N = {
	"MOJI_BTN_OPEN": {"en": "Replace Items", "zh": "替换物品", "zh_TW": "替換物品"},
	"MOJI_TITLE": {"en": "Replace Items Settings", "zh": "替换物品设置", "zh_TW": "替換物品設定"},
	"MOJI_SELECTED": {"en": "Selected targets: %d", "zh": "已选目标：%d 个", "zh_TW": "已選目標：%d 個"},
	"MOJI_CURSE": {"en": "Curse", "zh": "诅咒", "zh_TW": "詛咒"},
	"MOJI_CLEAR": {"en": "Clear All", "zh": "一键清空", "zh_TW": "一鍵清空"},
	"MOJI_HINT": {
		"en": "Click an item to add as replacement target (multiple targets rotate A-B-A-B; click selected to remove)",
		"zh": "点击物品添加为替换目标（多个目标将按 A-B-A-B 顺序轮流替换；点击已选物品可移除）",
		"zh_TW": "點擊物品添加為替換目標（多個目標將按 A-B-A-B 順序輪流替換；點擊已選物品可移除）"
	},
	"MOJI_REPLACE_STARTING": {"en": "Replace starting items", "zh": "替换起始物品", "zh_TW": "替換起始物品"},
	"MOJI_REPLACE_SHOP": {"en": "Replace shop items", "zh": "替换商店物品", "zh_TW": "替換商店物品"},
	"MOJI_REPLACE_SHOP_FIRST": {"en": "Replace shop first item only", "zh": "仅替换商店第一个", "zh_TW": "僅替換商店第一個"},
	"MOJI_REPLACE_CRATE": {"en": "Replace crate items", "zh": "替换箱子物品", "zh_TW": "替換箱子物品"},
	"MOJI_REPLACE_LEGENDARY": {"en": "Replace legendary crate items", "zh": "替换传奇箱子物品", "zh_TW": "替換傳奇箱子物品"},
	"MOJI_OPTIONS": {"en": "Replace options", "zh": "替换选项", "zh_TW": "替換選項"}
}

func _register_translations() -> void:
	var locales = ["en", "zh", "zh_TW"]
	for locale in locales:
		var t = Translation.new()
		t.locale = locale
		for key in _I18N:
			t.add_message(key, _I18N[key].get(locale, key))
		TranslationServer.add_translation(t)


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


# 取下一个替换物品。
# - A-B-A-B 轮流：按 replace_counter 取模选择目标
# - 诅咒继承：force_cursed 或 orig_item.is_cursed 时，对新物品施加诅咒
# 返回新物品（duplicate），不修改原物品；未配置目标时原样返回。
func get_replacement(orig_item, player_index: int):
	if target_item_ids.empty():
		return orig_item

	var target_id: String = target_item_ids[replace_counter % target_item_ids.size()]
	replace_counter += 1

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
func _curse_item(item_data, player_index: int):
	var progress_data = _autoload("ProgressData")
	if progress_data != null:
		var dlc = progress_data.get_dlc_data("abyssal_terrors")
		if dlc != null and dlc.has_method("curse_item"):
			return dlc.curse_item(item_data, player_index, true)
	if item_data != null:
		item_data.is_cursed = true
	return item_data


# 重置 A-B-A-B 计数器（新一局开始时由 run_data 扩展调用）
func reset_counter() -> void:
	replace_counter = 0


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
