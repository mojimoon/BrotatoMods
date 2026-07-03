extends Node

# Mojimoon-OneItemToRuleThemAll
# 将游戏生成的物品替换为目标物品，支持多目标 A-B-A-B 轮流、诅咒开关与原物品诅咒继承。
# 注意：Godot 3.x 不支持 static var，运行时状态存本节点实例成员；
# 外部用 _get_mod() 定位节点（挂在 /root/ModLoader/<MOD_ID> 下）。

const MOD_ID = "Mojimoon-OneItemToRuleThemAll"
const VERSION = "1.0.0"

# ============================================================
# 运行时状态（每局开始前在弹窗配置，仅存内存，每局重选）
# ============================================================
var target_item_ids: Array = []
var force_cursed: bool = false
var replace_counter: int = 0

# ============================================================
# 持久 config 缓存（从 ModLoaderConfig 同步，供扩展脚本快速读取）
# ============================================================
var cfg_replace_starting: bool = false
var cfg_replace_shop: bool = true
var cfg_replace_crate: bool = true
var cfg_replace_legendary_crate: bool = false

var _settings_dict: Dictionary = {
	"REPLACE_STARTING_ITEMS": false,
	"REPLACE_SHOP_ITEMS": true,
	"REPLACE_CRATE_ITEMS": true,
	"REPLACE_LEGENDARY_CRATE_ITEMS": false,
}


# 定位本 mod 节点（参考 cave-modtools feature_access.gd 的路径模式）
static func _get_mod() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("ModLoader/" + MOD_ID)


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/extensions/"
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/item_service.gd")
	ModLoaderMod.install_script_extension(dir + "singletons/run_data.gd")


func _ready() -> void:
	call_deferred("_config")


# ---------- 持久 config（参考 Mojimoon-DoubleSidedUpgrades）----------
func _config() -> void:
	var ModsConfigInterface = get_node_or_null("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	if ModsConfigInterface != null:
		if not ModsConfigInterface.is_connected("setting_changed", self, "setting_changed"):
			ModsConfigInterface.connect("setting_changed", self, "setting_changed")

	var config = ModLoaderConfig.get_config(MOD_ID, VERSION)
	var default_config = ModLoaderConfig.get_default_config(MOD_ID)
	if config != null:
		for key in _settings_dict.keys():
			if not config.data.has(key):
				config.data[key] = _settings_dict[key]
			if ModsConfigInterface != null:
				ModsConfigInterface.on_setting_changed(key, config.data[key], MOD_ID)
		config.save_path = "user://configs/Mojimoon-OneItemToRuleThemAll/" + VERSION + ".json"
		config.save_to_file()
	else:
		var data: Dictionary = default_config.data if default_config != null else {}
		config = ModLoaderConfig.create_config(MOD_ID, VERSION, data)
	_sync_cfg(config)


func setting_changed(setting_name, value, mod_name) -> void:
	if mod_name != MOD_ID:
		return
	var config = ModLoaderConfig.get_current_config(MOD_ID)
	if config == null:
		return
	config.save_path = "user://configs/Mojimoon-OneItemToRuleThemAll/" + VERSION + ".json"
	config.data[setting_name] = value
	config.save_to_file()
	_sync_cfg(config)


func _sync_cfg(config) -> void:
	if config == null or config.data == null:
		return
	cfg_replace_starting = bool(config.data.get("REPLACE_STARTING_ITEMS", false))
	cfg_replace_shop = bool(config.data.get("REPLACE_SHOP_ITEMS", true))
	cfg_replace_crate = bool(config.data.get("REPLACE_CRATE_ITEMS", true))
	cfg_replace_legendary_crate = bool(config.data.get("REPLACE_LEGENDARY_CRATE_ITEMS", false))


# ============================================================
# 替换工具（供扩展脚本调用，实例方法，通过 _get_mod() 访问）
# ============================================================

# 取下一个替换物品。
# - A-B-A-B 轮流：按 replace_counter 取模选择目标
# - 诅咒继承：force_cursed 或 orig_item.is_cursed 时，对新物品施加诅咒
# 返回新物品（duplicate），不修改原物品；未配置目标时原样返回。
func get_replacement(orig_item, player_index: int):
	if target_item_ids.empty():
		return orig_item

	var target_id: String = target_item_ids[replace_counter % target_item_ids.size()]
	replace_counter += 1

	# ItemService 是 autoload，节点内可直接用全局名访问
	var target_data = ItemService.get_element_safe(ItemService.items, target_id)
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
	# ProgressData 是 autoload，节点内可直接用全局名访问
	var dlc = ProgressData.get_dlc_data("abyssal_terrors")
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
	# （避免与 cave-modtools 已设的 focus_neighbour_right 冲突）
	if left_neighbour != null:
		btn.focus_neighbour_left = btn.get_path_to(left_neighbour)
	else:
		btn.focus_neighbour_left = btn.get_path_to(back_button)

