# 土豆兄弟 1.1 → 1.2 变更与 mod 适配文档

对比对象：`1.1/`（1.1.15.4，本体 pck + `BrotatoAbyssalTerrors.pck`）与 `1.2/`（1.2.0.1，单一 `Brotato.pck`），均为 GDRE 反编译工程。
适配对象：`Mojimoon-BroEditor`（2.6.0）、`Mojimoon-AutoAnthony`（1.9.4）。

文中「P0」= 不改会报错或功能失效；「P1」= 行为错误或内容缺失；「P2」= 体验或新内容支持。

---

## 1. 打包、目录与加载

### 1.1 单一 pck
- 1.1：`ProgressData._ready → load_dlc_pcks()` 运行时 `ProjectSettings.load_resource_pack("BrotatoAbyssalTerrors.pck")`，再扫描 `res://dlcs/*/dlc_data.tres`，按拥有情况 `add_resources()` 把角色、道具、武器、精英、首领、属性、套装、图标、效果行为、翻译追加进各 Service。
- 1.2：`load_dlc_pcks()`、`available_dlcs`、`get_dlc_data()`、`activate_dlc()/deactivate_dlc()/force_deactivate_dlc()`、`get_active_dlc_ids()`、`reset_dlc_resources_to_active_dlcs()`、`update_dlc_resources_based_on_run_state()` 全部删除。所有 DLC 资源从启动起就在 `res://` 中。拥有情况只记录在 `ProgressData.available_dlc_ids`（`dlc_ids = ["primal_dread", "abyssal_terrors"]`，由 `Platform.is_dlc_owned` 判定）。
- 对 mod 加载的影响：
  - ModLoader 仍为 6.3.0，autoload 顺序不变（ModLoader 在 ProgressData / ItemService 之前）。
  - 现在可以直接 `install_script_extension` / `load()` 任何 DLC 脚本和资源，不必等 pck 挂载。
  - **`ResourceLoader.exists("res://dlcs/...")` 或"资源能否加载"不再代表拥有 DLC**。要判断拥有用 `ProgressData.is_dlc_available(id)`；要判断本局是否启用用 `id in ProgressData.active_update_data`（或 `RunData.active_update_data_ids`）。
  - `ItemService.get_dlc_data_by_id(id)` **不检查拥有情况**，未拥有也会返回 DLCData。

### 1.2 「物品套组」（Item Set / UpdateData）取代 DLC 开关
- 新类：`UpdateData`（`global/update_data.gd`：id、name、item_set、update_type DLC/UPDATE、icon、color、横幅、dlc_data）、`ItemSetData`（items / weapons / stats / characters / challenges）、`PrimalDreadItemSetData`（额外 `meca_items` / `mutant_items` / `evolution_items`）。
- 资源：`res://updates/`，`ItemService.base_game_item_set` = `base_game_set.tres`，`ItemService.update_data_list` = `u13_new_dawn`（新黎明，8 道具 + 3 武器）、`u14_paws_n_claws`（张牙舞爪，9 道具）、`dlc1_abyssal_terrors`、`dlc2_primal_dread`。
- 主菜单新增「物品套组」页（`ui/menus/pages/menu_item_sets.*`），选择/角色选择界面顶部有 `ItemSetBar`。玩家可以单独关闭任一套组（包括两个免费更新），存于存档的 `deactivated_update_data`（原 `settings.deactivated_dlcs` 删除）。
- `ProgressData`：`active_update_data`、`deactivated_update_data`、`set_item_set_selected()`（保存、`ItemService.init_unlocked_pool()`、发 `item_sets_changed` 信号）、`has_item_set()`、`refresh_active_update_data()`、`apply_run_update_data()`。
- 本局使用的套组记入 `RunData.active_update_data_ids` 并随存档保存，读档时 `apply_run_update_data()`。
- 角色 `required_item_set`（变异体、疯狂科学家、机械土豆 = `primal_dread`）：套组未启用时不可选。武器、道具通过 `ItemService.get_update_data_by_item_id()` 判定所属套组，未启用时在选择界面显示为不可用。

### 1.3 ItemService 内容列表改为惰性缓存（**重要**）
```gdscript
var items setget set_items, get_items          # characters / weapons 同理
func get_items():  if _items_dirty: _rebuild_items(); return _items
func _rebuild_items():  _items.clear(); 追加 base_game_item_set.items 与每个"已拥有"套组的 items
                        （primal_dread 还追加 meca/mutant/evolution_items）
```
- `_rebuild_*` 读 `ProgressData.available_dlc_ids`；**第一次访问后结果被缓存，之后只在 `invalidate_*_cache()`、`add_mod_item()`、`remove_mod_item()` 时重建**。原版没有任何地方调用 `invalidate_*_cache()`。
- `_mod_items` / `_mod_characters` / `_mod_weapons` 已声明，但 `_rebuild_*` 并不把它们加回去（`add_mod_item()` 加入的道具在下次重建后就不在 `items` 里了，原版 bug）。
- `ItemService.items.push_back(x)` 仍然有效（改的是缓存数组），但任何一次重建都会把它丢掉。
- `export var characters / items / weapons / elites` 不再在 tscn 中赋值；`elites` 与 `get_elites_from_zone()` / `get_bosses_from_zone()` 移到 `ZoneService`（区域数据新增 `bosses`、`elites`、`meca_elites`、`mutant_elites`、`dlc_id`）。`get_random_elite_id_hash_from_zone` 改为 `get_random_neutral_elite_id_hash_from_zone`。

### 1.4 商店池只来自套组（**重要**）
`ItemService.init_unlocked_pool()` 在 1.2 中遍历 `base_game_item_set` 与 `ProgressData.active_update_data` 中各套组的 `items` / `weapons`，**不再遍历 `ItemService.items` / `weapons`**。另外：
- 跳过 `RunData.current_difficulty < item.minimum_difficulty` 的道具（新字段）；
- 升级跳过 `required_item_set` 未启用者（新字段，进化升级用）；
- `RunData.reset()`、`RunData.resume_from_state()`、难度选择 `_on_element_pressed()`、切换套组时都会调用 `init_unlocked_pool()`，池子会被反复重建；
- `meca_items` / `mutant_items` / `evolution_items` 不在池中，而是在 `_get_rand_item_for_wave → update_pools()` 中按玩家进化值临时注入（见 3.6）。

结论：只推进 `ItemService.items/weapons` 的自定义内容永远进不了商店或箱子。

### 1.5 资源路径大迁移
| 1.1 | 1.2 |
| --- | --- |
| `res://items/all/<id>/` | `res://items/all/00_base_game/<id>/`；新黎明道具在 `02_new_dawn/`（candy_bag、evil_hat、fresh_meat、fruit_basket、ghost_outfit、hourglass、will_o_the_wisp）；张牙舞爪在 `03_paws_n_claws/`；DLC2 在 `04_primal_dread/` |
| `res://entities/units/enemies/<name>/` | `res://entities/units/enemies/crash_zone/{basic,elites,bosses}/<name>/`，深渊敌人在 `abyss/`，丛林在 `jungle/` |
| `res://dlcs/dlc_1/{enemies,elites,bosses,projectiles,sets,icons,translations,effect_behaviors}` | 移出 DLC 目录：`res://entities/...`、`res://projectiles/...`、`res://items/sets/{musical,naval}`、`res://effect_behaviors/{enemies,scenes,player}/` |
| `res://dlcs/dlc_1/effect_behaviors/enemy/charm_enemy_effect_behavior.tscn` | `res://effect_behaviors/enemies/charm_enemy_effect_behavior.tscn` |
| `res://dlcs/dlc_1/effect_behaviors/enemy/curse_enemy_effect_behavior.gd` | `res://effect_behaviors/enemies/curse_enemy_effect_behavior.gd` |
| `res://zones/zone_1` / `zone_2` / `zone_3` | `zones/zone_1_crash`、`zone_2_abyss`、`zone_3_jungle`（新） |
| 翻译：`.assets/resources/translations/translations.csv` + `.assets/dlcs/dlc_1/translations/translations.csv` | 单一 `resources/translations/translations.csv`（含 DLC1/DLC2，`key,en,fr,zh,ja,ko,zh_TW,ru,pl,es,pt,de,tr,it`） |

DLC1 自身内容（`dlcs/dlc_1/characters`、`items`、`weapons`）仍在原位。DLC2 的道具、武器、角色**不在** `res://dlcs/` 下（`res://dlcs/dlc_2/` 只有 `dlc_2_data.*` 与挑战）。

---

## 2. 新增内容（DLC2「史前惧兽 / Primal Dread」）

### 2.1 角色（10）
| id | 名称 | 效果 | 备注 |
| --- | --- | --- | --- |
| character_veteran | 老兵 | 每损失 X 生命值 +1% 伤害；每 10 波 +2 敌群（`more_horde`）；波次之间不回血（`no_cure_between_wave`）；-100 生命再生、-100% 生命窃取；波末不自动吸水果 | banned_meca_stats：生命再生、生命窃取 |
| character_archaeologist | 考古学家 | 每波 4 个挖掘点（站 5–6 秒挖出箱子，`dig_sites`）；回收箱子 +75% 材料（`item_box_recycling_gains`）；每收集一个箱子 +3% 经验；+25 拾取范围；-50% 敌人材料 | |
| character_droid | 机械土豆 | 受伤扣材料而非生命，材料耗尽死亡（`materials_as_health`）；只能机械进化（`meca_only`）；升级 +1 机械部件、升级时 +5% 敌人伤害；升级不给属性（`no_level_upgrades`）；波末 +1 进化 | 禁用 44 件回复类道具；banned_meca_stats：最大生命、再生、窃取；需要 primal_dread |
| character_time_shifter | 时间扭曲者 | 受伤时扭曲时间（敌人与敌方投射物减速 75%，并获得 `time_shift_stats` 临时属性）；部分波次乱序（`effect_mixing_up_wave`，第 2…n-1 波最多 4 对互换，距离 ≤3）；+5% 速度；闪避获取 -100% | banned_meca_stats：闪避 |
| character_variant | 异种 | -25% 经验；只能异变（`mutant_only`）；每波末自动异变一次；50% 异变时替换为高一级道具（`mutate_into_better_tier_chance`） | 需要 primal_dread |
| character_caveman | 穴居人 | 永久迷雾，逐波加深（`fog_of_war_permanent`）；可点燃武器照亮雾气（`burn_weapon`）；不能装备远程武器；点燃的原始武器按等级加伤害 [1,2,4,8]（`burn_weapon_give_primitive_bonus`） | banned_meca_stats：远程伤害 |
| character_arsonist | 纵火者 | 爆炸留下随爆炸大小变化的火焰池（`fire_explosion`）；燃烧致死的敌人 50% 留火焰池（`fire_puddle_on_burning_death`）；+5% 速度；近战 / 远程 / 工程获取 -100% | banned_meca_stats：三种伤害 |
| character_mad_scientist | 疯狂科学家 | 双进化（`dual_evolution`：进化值变化一律视为增加，同时提升机械与异变；敌人两种都会进化）；波末 +2 进化、-5% 经验；+100% 异变果几率 | 需要 primal_dread |
| character_poacher | 偷猎者 | 1 个狩猎区，区内每杀 15 个敌人 +3% 伤害（`gain_stat_for_killed_enemies_in_zone`）；区内击杀材料 -50% | |
| character_survivor | 幸存者 | 箱子给武器（`effect_crate_give_weapon`）；商店无武器（`effect_no_weapon_in_shop`）；8 个武器栏；更多树；+25% 箱子几率；-25% 材料；多选 1 把初始武器（`extra_starting_weapon_choices`）；-2 消耗品回复 | 武器选择界面支持多选 |

### 2.2 道具
**普通池（34，含形态变体）**：生命形态扫描仪（离开商店时把下一次精英事件换成敌群，然后变成"已使用"版本）、化石：左臂 / 右臂 / 左腿 / 右腿 / 尾巴 / 头骨 / 脊椎 / 下颚（各自有正负属性，"每装备一件化石物品 +X 属性"，`fossil_count`）、化石：牙齿（视作化石，-2 最大生命）、失落器官、猎食者之爪、泥巴爱好者（在泥潭中 +60% 伤害）、流血炮塔、恐龙蛋（地图上的蛋，守 3 波孵化成弹药恐龙；`item_dino_egg → _2 → _1 → item_ammosaurus`，蛋被打破则当波不前进）、飞箭陷阱、病毒（命中低血量进化敌人 25% 魅惑）、发热反应（进化敌人死亡爆炸）、盗龙眼（+50% 暴击伤害倍率，`bonus_crit_damage`）、纵火狂（不同武器燃烧叠加，`burning_stacks`）、感染皮肤（受击放棘刺，`spines_on_hit`）、岩浆靴（火焰轨迹 + 每秒 -1 生命）、阿蚊（宠物，命中后 5 秒 +30% 受伤，优先未受影响的敌人）、弹药恐龙（宠物，持有你最强武器的复制品）、臭臭大王花、发焰筒（击杀进化敌人 +1 材料）、好饿好饿的小恐龙（宠物，吃水果当波加伤害）、挖掘点、怀表（每波一次，低血时全场减速）、生锈天线、肿瘤（`item_tumor`，max_nb=0，只能由异变产生）。

**机械路线（6，`meca_items`，进化值 > 2 时注入商店）**：机械版进化飞跃（装备时进化值 ×2，+2 进化）、超量钛合金（-25% 拆卸价格）、干扰背包（+5 进化，命中机械敌人减速）、生化臂（+1 武器栏）、故障保险核心（生命归零后用材料承受伤害）、罐装剃须泡沫（机械版，+1 进化，敌人更易机械化）。

**异变路线（5，`mutant_items`，进化值 < -2 时注入）**：异变版进化飞跃、邪神像（-5 进化，击杀异变敌人 50% 回 1 血）、强化有丝分裂（+50% 异变果几率）、野火异变（25% 异变时升一级）、罐装剃须泡沫（异变版）。

**双路线（1，`evolution_items`，|进化值| > 2 时注入）**：塑料靴子（不受泥潭影响）。

### 2.3 武器（16 系列，64 个资源，位于 `res://weapons/{melee,ranged}/`，属于 DLC2 套组）
| 系列 | 等级 | 类别 | 特性 |
| --- | --- | --- | --- |
| 锥子 awl | T1–T4 | 工具 | 定时生成飞箭陷阱 |
| 铁指虎 cestus | T2–T4 | 徒手、钝器 | 击退 ≥ 阈值时伤害倍增（`WeaponDamageMultiplierIfStatEffect`） |
| 撬棍 crowbar | T1–T4 | 工具 | 每击杀 N 个敌人生成一台炮塔（`SpawnStructureEveryKilledEnemiesEffect`） |
| 连枷 flail | T1–T4 | 中世纪、原始 | 末端命中必暴击（`crit_on_whip_tip`） |
| 光剑 light_saber | T3–T4 | 刀刃、精准 | 反弹敌方投射物（`DeflectProjectilesEffect`） |
| 嫩肉锤 meat_tenderizer | T1–T4 | 钝器、医疗 | |
| 铲子 shovel | T1–T4 | 钝器、工具 | 击杀概率挖出箱子（`CrateDigChanceEffect`，50/100/150/200%） |
| 鞭子 whip | T1–T4 | 原始 | 命中减速（`WeaponTimedSlowOnHitEffect`） |
| 吹箭 blowgun | T1–T4 | 精准、原始 | 命中后敌人受伤 +20/30/40/50% |
| 回旋镖 boomerang | T1–T4 | 原始 | 返程可再次命中 |
| 碳纤维弓 carbon_bow | T1–T4 | 精准 | 每支箭按最高属性随机附带减速 / 穿透 / 燃烧 / 地雷（`CarbonBowStatEffect`） |
| 战斗霰弹枪 combat_shotgun | T2–T4 | 枪械 | |
| 机枪 machinegun | T1–T4 | 重型、枪械 | -3% 速度 |
| 莫洛托夫鸡尾酒 molotov | T1–T4 | 火焰 | 命中留火焰池（`FirePuddleOnHitEffect`）+ 燃烧 |
| 排笛 pan_flute | T1–T4 | 乐器 | |
| 粘性手雷 sticky_grenade | T1–T4 | 爆炸 | 粘附后延迟爆炸（`DelayedExplodingEffect`） |
| 麻醉枪 tranq_rifle | T1–T4 | 精准、枪械 | 命中范围减速（`SlowAreaOnHitEffect`） |

武器套装未新增（乐器 / 航海从 DLC1 目录移到 `items/sets/`）。`WeaponStats` 新字段 `can_shoot_without_target`。

### 2.4 区域、敌人、地形
- 新区域 `zone_3_jungle`（id=2，`dlc_id="primal_dread"`，`ZONE_JUNGLE`），20 波 + 敌群 / 杂兵 / 战利品组，有环境音（`ambient_stream`，设置新增「环境音量」）。
- 丛林敌人 31 种（`jungle/basic`，迅猛龙、三角龙、剑龙、翼龙、恐龙蛋、食人花等，多数带 `++` 强化版），精英 7（重爪龙、食肉牛龙、梁龙、风神翼龙、西里龙、棘龙、镰刀龙），首领 2（腕龙、霸王龙）。
- 区域数据 `meca_elites` / `mutant_elites`：精英波可能换成机械 / 异变阵营精英（`EliteCamp`）。
- 地形对象 GPE（`entities/gpe/`、`global/gpe_spawner.gd`）：泥潭 puddle（减速，泥巴爱好者 / 塑料靴子）、酸池、汽油池、火焰池、坑洞、挖掘点、狩猎区；`ZoneService` 新增禁区（`forbidden_circles`、`is_in_forbidden_zone`、`push_out_of_forbidden`），`get_rand_pos()` 改为按网格权重采样且不再接受 `edge` 参数。
- 新移动 / 目标 / 攻击行为（预判、绕后、环绕主人、贴边、跳跃攻击、带警示线冲锋、冲锋反弹子弹等），新投射物（回旋镖、吹箭、手雷、地雷、酸液、敌方激光、鱼叉、笛声等）。
- `EntityService.slow_enemy_time()`（时间扭曲 / 怀表）：敌人时间流速全局缩放，`enemy_time_slow_changed` 信号。

### 2.5 消耗品
| id | 效果 |
| --- | --- |
| `meca_consumable_fruit` 机械果 | +1 进化（拾取条件：非 mutant_only 且进化值 ≥ -2） |
| `mutant_consumable_fruit` 异变果 | -1 进化（非 meca_only 且进化值 ≤ 2） |
| `mutation_consumable_fruit` 异变催化果 | 本波末异变一件道具（`pending_mutations += 1`） |
| `meca_parts_consumable` 机械部件 | +2 机械部件（`GainMecaPartsEffect`） |

### 2.6 挑战（21）
10 个角色挑战 + bone_collector、clever_girl、crate_expectations、dig_site、egg_hunt、flesh_and_steel、floor_is_lava、petting_zoo、trophy_hunter、well_done、whip_it。`ProgressData.data` 新增 `dig_sites_dug_up`、`whip_jungle_kills`、`trophy_hunter_species`。

### 2.7 新属性 / 效果键 / 效果脚本
- 新属性 `stat_evolution`（`items/upgrades/evolution/stat_evolution.tres`，`is_primary_stat = true`，`is_dlc_stat = true`，正负两种配色）。
- `Keys` 新增 70 个哈希：`stat_evolution bonus_crit_damage has_plastic_boots enemy_evolution_chance stat_enemy_projectile_speed item_flare item_titanium_excess item_eldritch_figurine item_infected_skin item_magma_boots item_hungry_hungry_dinosaur effect_no_weapon_in_shop effect_crate_give_weapon extra_starting_weapon_choices weapon_set_bonus character_poacher fire_puddle_size mutation_fruit_chance material_on_evolved_enemy_kill charm_evolved_on_hit meca_consumable_fruit mutant_consumable_fruit mutation_consumable_fruit meca_parts_consumable crit_on_whip_tip burning_stacks slow_meca_on_hit slow_area_on_hit timed_slow_on_hit time_shift_stats heal_on_mutant_kill dismantle_price damage_taken_on_materials mutate_into_better_tier_chance fog_of_war_permanent burn_weapon burn_weapon_give_primitive_bonus burn_primitive_bonus fire_explosion fire_puddle_on_burning_death time_shift_on_hit slow_time_when_below_hp effect_mixing_up_wave no_cure_between_wave no_fruit_attracted_end_of_wave spines_on_hit fire_trail meca_parts_on_level_up poacher_zone_materials dig_sites dig_sites_every_x_waves item_box_recycling_gains dual_evolution crates_collected meca_only mutant_only effect_mutate_end_of_wave no_level_upgrades materials_as_health weapon_crowbar weapon_awl weapon_carbon_bow explode_on_evolved_death icon_gold_on_evolved_kill more_horde gain_stat_for_killed_enemies_in_zone item_lifeform_scanner item_ammosaurus fossil_count temp_stats_while_being_in_puddle`。
- 新效果脚本：道具 `effect_option`（EffectOption）、`modular`（ModularEffect）、`multiply_value`（MultiplyValueEffect，装备时 `effects[key] *= value`，卸下时除回）、`fire_trail`、`fire_puddle_on_burning_death`、`gain_meca_parts`、`hungry_hungry_dinosaur`、`mosquitor`、`slow_time_when_below_hp`、`spines_on_hit`；武器 `carbon_bow_stat`、`crate_dig_chance`、`deflect_projectiles`、`delayed_exploding`、`fire_puddle_on_hit`、`slow_area_on_hit`、`weapon_spawn_structure_every_killed_enemies`、`weapon_damage_multiplier_if_stat`、`weapon_timed_slow_on_hit`。
- `Effect` 新增：`Sign.EVOLUTION_MECA`(6)、`Sign.EVOLUTION_MUTANT`(7)；`added_by_mutation`；`get_applied_value(player_index)`（双进化时 `stat_evolution` 取绝对值）；`get_arg_value_tool / get_args_tool / get_scaling_stats_text_tool`（编辑器预览用）；`effect.gd` 成为 `tool` 脚本。
- `ItemParentData` 新增 `is_meca`、`is_mutant`、`mutation_removed_effects`（均序列化）；`ItemData.minimum_difficulty`；`WeaponData.meca_power`、`meca_rank`（序列化），**删除 `add_to_chars_as_starting`**；`CharacterData.banned_meca_stats`、`required_item_set`；`UpgradeData.required_item_set`；`ConsumableData.attracted_at_end_of_wave`；`DLCData` 只剩 `groups_in_all_zones / backgrounds / entities_items / effect_scripts / music_tracks / title_screen_backgrounds / tracked_items`。

---

## 3. 进化系统详解（机械化 / 异变）

核心是有符号的 `stat_evolution`：**正值 = 机械路线，负值 = 异变路线**。全部逻辑在 `dlcs/dlc_2/dlc_2_data.gd`（DLC2Data），调用点在 `ItemService`、`RunData`、`main.gd`、商店 UI。

### 3.1 进化值来源与阵营锁定
- 来源：机械果 +1 / 异变果 -1、进化道具、机械化武器自带 +1、异变道具每次 -1（首次 -2）、角色波末加成。
- 阵营锁定阈值 `ItemService.EVOLUTION_CAMP_LOCK_THRESHOLD = 2.0`：进化值 > 2 时只掉机械果、只能捡机械果；< -2 同理只走异变；介于两者之间随机掉落。
- `meca_only`（机械土豆）/ `mutant_only`（变异体）强制单一路线；`dual_evolution`（疯狂科学家）：进化值变化按绝对值计入（`Effect.get_applied_value`），两种果实都掉、两条路线的道具都进池、敌人两种都会进化。
- 精英、首领、战利品外星人之外的敌人死亡时，`main.spawn_evolution_fruit()` 以 `evolution_fruit_base_chance = 2%` 掉进化果（仅 primal_dread 启用时；进化敌人本身不掉）。

### 3.2 敌人进化（`effect_behaviors/scenes/evolution_scene_effect_behavior.gd`、`global/team_evolution.gd`）
- 每个敌人重生时用 `TeamEvolution` 计算全队进化几率：每名玩家 `Utils.get_evolution_factor(|进化值| × (1 + enemy_evolution_chance%)) / 2`（`f(v) = 100·(1 − 1/(1 + v/50))`，渐近上限 50%），无尽模式乘 `1 + endless_factor/2`，再在玩家间取平均；精英几率 ×4。
- 阵营按各玩家进化绝对值加权抽取；幅度 = 该阵营玩家的平均 |进化值|。
- 机械敌人：HP +50 + 2/点进化（幅度上限 300），伤害 +25%→50%、速度 +5%→25%（按 √ 曲线，进化 100 时满）；蓝色描边，换机械贴图。
- 异变敌人：HP +25 + 2.4/点，伤害 +15%→80%（线性到 150），速度 +5%→25%；绿色描边。
- 两者材料价值 +33%。死亡时：异变敌人按 `mutation_fruit_chance` 掉异变催化果（基础 2%，有保底 `misses/20`、每波递减 `1 + 0.5 × 已掉数`，且要求某玩家至少有 3 件可异变道具）；机械敌人掉机械部件（同样的保底与递减）。
- 道具联动：`explode_on_evolved_death`、`material_on_evolved_enemy_kill`、`charm_evolved_on_hit`、`heal_on_mutant_kill`、`slow_meca_on_hit`；DLC1「对诅咒敌人的武器类别加成」也适用于进化敌人。
- 精英：`RunData.apply_evolution_to_current_elite()` 按 `team.elite_chance` 把本波精英换成 `meca_elites` / `mutant_elites` 中的一种（`current_wave_elite_camp`）。生命形态扫描仪、`more_horde` 会调整精英 / 敌群的波次表（`switch_next_elite_to_horde`、`_add_more_horde_waves`、`reorderEliteSpawns`）。

### 3.3 机械化（只针对武器）
- **商店出现**：`ItemService.apply_item_effect_modifications()` → `DLC2Data.update_item_effects()`：武器以 `get_evolution_factor(max(3, 进化值), 1, 100)` 的几率被机械化（基础约 3%，随进化值上升）。同时启用 DLC1 与 DLC2 时，按进化值与诅咒值的大小决定先试哪个，**一件物品只会是诅咒、机械、异变之一**（`can_item_be_cursed / can_item_be_mutated / can_weapon_be_mechanized`）。
- **`meca_item()`**：复制武器，`is_meca = true`，加一条 `stat_evolution +1`，加计数行 `EFFECT_MECA_PARTS_COUNT`（记录投入的部件数，值 = 本次花费），再加两条 `EffectOption`：从 4 个类别（防御：最大生命、护甲、闪避、再生、窃取；辅助：速度、范围、幸运、收获；伤害：%伤害、攻速、暴击；构筑：近战 / 远程 / 工程 / 元素，取玩家当前最高者，平手时取武器加成系数最高者）随机选两个不同类别各出一个属性，数值 = 同稀有度属性升级的数值（更高花费按传说档的步长外推）。角色 `banned_meca_stats`、闪避已达上限、暴击已达上限的属性不会出现。
- **二选一**：商店卡片显示两个按钮；购买时 `DLC2Data.change_effect_option_to_modular_effect()` 把选中的那条转成 `ModularEffect`（同 key 已有则累加），两条 `EffectOption` 删除。
- **机械强度**（`meca_power`）：每次机械化 +（`meca_rank` + 1）。`apply_meca_power()` 以 `ItemService.get_base_weapon(my_id_hash)` 的原始属性为基准：伤害与加成系数 ×(1 + 5%·power)，暴击伤害 ×(1 + 2%·power)，有生命窃取的同比提高，每 4 点 +1 穿透（有弹跳的也 +1 弹跳）；建筑类效果的冷却 / 加成 / 燃烧同样增强。
- **机械部件**（`PlayerRunData.meca_parts`，`RunData.add_meca_parts / remove_meca_parts / get_player_meca_parts`，信号 `meca_parts_changed`）：来自机械部件消耗品、`meca_parts_on_level_up`、拆卸。
- **升级改造**：武器弹窗"机械升级"按钮花费 `meca_rank + 1` 个部件，再机械化一次（新的二选一，`meca_rank + 1`），`RunData.meca_upgrade_weapon()`；关卡升级界面同样可用。
- **拆卸**：商店里的机械武器可以付 `dismantle_price`（基础 11，随波次通胀，受 `dismantle_price`、`recycling_gains` 影响）拆掉，获得 1 个部件；机械武器售价额外加上拆卸价。
- **合成**：`RunData.combine_weapon()` → `ItemService.get_combined_weapon()`：机械武器合成时累加两把的 `meca_power` 与部件数，`meca_rank` 取较大者，保留并合并全部 `ModularEffect`；诅咒武器合成按两者最大诅咒系数重新诅咒（原 DLC1 逻辑迁移到 `_curse_upgrade`）。风味不兼容（诅咒 / 机械 / 异变互斥）的武器不能合成（`are_flavors_compatible`）。回收机械武器退还部件（`refund_weapon_meca_parts`）。

### 3.4 异变（针对道具，不含武器）
- **触发**：异变催化果（波末结算）、`effect_mutate_end_of_wave`（变异体每波末）。`RunData.on_wave_end()` 执行 `pending_mutations` 次 `mutate_random_item()`。条件：primal_dread 启用且进化值 < 0（双进化时 ≠ 0）；没有可异变道具时，变异体改为直接 -1 进化。
- **可异变道具**：非诅咒、非机械，且不是建造者炮台、进化飞跃、肿瘤、美西螈（`ItemService.can_item_be_mutated`）。
- **`mutant_item()`**：复制道具，`is_mutant = true`，进化值行 -1（首次 -2），然后二选一：
  - 有可去除的负面行时 50%：**删掉一条负面效果**（记入 `mutation_removed_effects`，UI 以删除线显示，`effect_line._display_effect(..., removed_by_mutation)`）；
  - 否则：**从玩家所有道具（含本件）中随机复制一条正面效果**，数值按 `scale = 0.1 + 0.9 × (|进化值|/150)^0.5` 缩放（几率、爆炸伤害、燃烧伤害等同步缩放），这条效果**加到肿瘤上**（`item_tumor`，没有就新建，可合并的同类效果直接累加）；
  - 两者都不可能时加一行"什么也没发生"。
- 复制限制（`can_effect_be_copied_by_mutation`）：排除建筑师炮台、MultiplyValue、ConvertStat、NullEffect、无 key 的非实体效果、`[EMPTY]` 文本（化石计数除外）、非正面、布尔型机制键（`mutation_boolean_keys`）、黑名单键（价格、上限、起始物品、沙漏、时间扭曲等 31 个）、恐龙蛋场景、已饱和的几率 / 爆炸 / 燃烧 / 果冻护盾 / 减速 / 穿透弹跳收益；生成实体的效果需要 scale ≥ 0.7，部分键有最低 scale。
- **升阶**：`mutate_into_better_tier_chance`（变异体 50%、野火异变 25%）时，改为把道具换成高一级、共享标签的随机道具再异变。
- 异变保留原道具的上限值（`_get_item_cap_values / _restore_cap_values`）。

### 3.5 风味互斥
`ItemFlavor {PLAIN, CURSED, MECA, MUTANT}`；`ItemService.get_preferred_flavor()`：|进化值| > 诅咒值时偏向进化（双进化随机），否则偏向诅咒。

### 3.6 进化道具进池
`ItemService.update_pools()`（每次抽道具时）：进化值 > 2 注入 `meca_items`；< -2（或双进化且 > 2）注入 `mutant_items`；|进化值| > 2 注入 `evolution_items`。注入的是 `item.duplicate()`，要求已解锁。

---

## 4. 其他新机制（1.2 本体 + DLC2）
- **多初始武器**：武器选择界面 `_player_weapons[i]` 由单个 WeaponData 改为 **Array**，按 `1 + extra_starting_weapon_choices` 次选择；`PlayerRunData.extra_selected_weapons` 在重开时保留。
- **初始武器写进角色资源**：删除 `WeaponData.add_to_chars_as_starting` 与 DLCData 的追加逻辑，各角色 `starting_weapons` 直接列出全部（含 DLC1 / DLC2 武器），未启用套组的武器在界面上禁用。
- **武器套装加成**：`weapon_set_bonus`（独臂 +3：武器额外计入 3 件同类别）。
- **升级记录**：`PlayerRunData.upgrades_taken`，`RunData.add_upgrade / remove_upgrade / get_player_upgrades`；`no_level_upgrades` 跳过升级队列。
- **箱子计数**：`crates_collected`（考古学家等）。
- **时间相关**：`slow_time_when_below_hp`（怀表）、`time_shift_on_hit`、`effect_mixing_up_wave`（`RunData.time_shifter_wave_mapping`，随存档保存）、`get_next_wave()` / `get_wave_reset_count()`（沙漏）。
- **生命形态扫描仪**：离开商店时 `switch_next_elite_to_horde()` 成功后按 id 找到并移除持有道具（替换为已使用版本，与沙漏同类的"按 id 消耗"机制）。
- **恐龙蛋**：`RunData.advance_dino_eggs()` 每波末按 `dino_egg_item_hashes` 找到蛋并替换为下一阶段，蛋被打破（`dino_egg_destroyed`）则不前进；诅咒蛋保持诅咒。
- **燃烧**：`burning_stacks`、火焰池（`WeaponService.get_fire_puddle_burning_data`）、`fire_trail`。
- **雾**：`fog_of_war_permanent`、`burn_weapon`。
- **商店**：`CHANCE_SAME_WEAPON` 0.2→0.23、`BONUS_CHANCE_SAME_WEAPON` 0.05→0.07，新增 `CHANCE_SAME_WEAPON_PER_UNIQUE_WEAPON` 0.02、`CHANCE_SAME_WEAPON_SET_PER_UNIQUE_WEAPON` 0.01、`MAX_UNIQUE_WEAPONS_FOR_SHOP_BONUS` 6；购买道具后若武器列表变化会刷新装备栏；`hp_shop` 时拆卸价按 1/20 换算。
- **`RunData.remove_item(item, p, by_id, apply_replacement = true)`**：先按引用查找，再退回 `is_same_item`；`apply_replacement = false` 不触发 `replaced_by`。
- **`get_remaining_max_nb_item()`** 把 `replaced_by` 链上的后代计入上限（`ItemService.get_limited_item_descendants`，结果缓存在 `_limited_item_origins_dirty`）。
- **刷怪**：`EntitySpawner.spawn_entity_birth(request: SpawnRequest)`，队列元素也是 `SpawnRequest`（`global/spawn_request.gd`：type、scene、position、data、player_index、charmed_by、group_count、source、is_meca、is_mutant），后代会继承来源的进化状态。新增 `EntityGroupBirth`。

## 5. 已有内容的改动
### 5.1 数值
| 对象 | 改动 |
| --- | --- |
| 潜水员（DLC1） | `enemy_health` 250 → 200 |
| 德鲁伊（DLC1） | `enemy_fruit_drops` 3 → 4 |
| 矮人（DLC1） | 每击杀 6 → 5 个敌人 +1 工程 |
| 登山者（DLC1） | 每 10 步获得材料 5 → 6；删除 -5% 速度 |
| 渔夫 | `enemy_gold_drops` -50 → -40 |
| 驯兽师 | 新增起始道具鼠王（item_ratzilla） |
| 农夫 | 新增起始道具花园（item_garden） |
| 独臂 | 新增 `weapon_set_bonus` 3（每件武器可以触发 +3 件的套装加成，即 1 个武器 = 4件套装加成） |
| 建造者（DLC1） | 禁用生锈天线 |
| 猎人 | 初始武器移除螺丝刀 |
| 各角色 | `starting_weapons` 补入 DLC1/DLC2 的新武器（共 62 个角色变化）；DLC1 角色 `banned_upgrades` 显式置空 |
| 冰块、鲁特琴 | 减速效果新增 `chance = 100`（行为不变） |
| 普通道具 / 武器 / 升级 / 难度 | 无数值变化；部分效果新增显示用 `custom_args`（中性符号）；`can_be_looted` 显式写出 |
| 诅咒（DLC1） | `curse_item` 新增对撬棍炮塔、阿蚊、小恐龙、弹药恐龙、恐龙蛋（跳一阶）、怀表、扫描仪、挖掘点、塑料靴子、纵火狂、岩浆靴、化石、MultiplyValue、`stat_evolution` 的特殊处理；不再诅咒机械 / 异变物品 |

### 5.2 结构
- 精英、首领从 ItemService 移到各区域数据；DLC1 的效果行为、套装、属性、图标、敌人全部并入本体。
- 未使用的 `consumable_cursed_chest`、`dlc_1/stats/reroll_price.tres` 删除。
- 设置保存改为内容不变则跳过写盘（`_last_saved_settings_json`）。
- 显示版本 `ProgressData.get_display_version()`。

---

## 6. 面向 mod 的 API 变化速查
| 1.1 | 1.2 | 两个 mod 是否使用 |
| --- | --- | --- |
| `ProgressData.get_dlc_data(id)` | `ItemService.get_dlc_data_by_id(id)`（不判拥有） | BE、AA、两套测试 |
| `ProgressData.available_dlcs`（DLCData 数组） | `ProgressData.available_dlc_ids`（String 数组）；内容在 `ItemService.update_data_list[i].item_set` | BE、BE 测试 |
| `ProgressData.is_dlc_available_and_active(id)` | 仍在，但等同 `is_dlc_available`；本局启用用 `id in ProgressData.active_update_data` | BE |
| `ProgressData.get_active_dlc_ids()` 等 DLC 开关 | 删除，改为套组 | — |
| `WeaponData.add_to_chars_as_starting` | 删除（赋值会报 Invalid set index） | BE |
| `EntitySpawner.spawn_entity_birth(type, scene, pos, data, player_index, source, charmed_by)` | `spawn_entity_birth(SpawnRequest)` | BE |
| `ZoneService.get_rand_pos(edge)` | `get_rand_pos()`（无参数） | BE（无参调用，不受影响） |
| `ItemService.get_elites_from_zone / get_bosses_from_zone` | `ZoneService.*` | — |
| `ItemService.items / characters / weapons`（普通数组） | setget 惰性缓存，见 1.3 | BE、AA |
| `init_unlocked_pool()` 遍历 `items/weapons` | 遍历套组，见 1.4 | BE、AA |
| `RunData.remove_item(item, p, by_id)` | 新增 `apply_replacement = true` | 兼容 |
| `effect_line._display_effect(...)` | 新增 `removed_by_mutation = false` | 兼容 |
| `RunData.enabled_dlcs` | 保留，值为 `available_dlc_ids` | — |
| 武器选择 `_player_weapons[i]`：WeaponData | Array | — |

两个 mod 所有扩展脚本覆盖的函数，签名在 1.2 中都没有变化（已逐个核对包括父类在内的继承链）。

---

## 7. BroEditor 需要调整的地方

### P0
1. **注册时机与内容缓存**（`mod_main.gd:144` `_ready → _register_customs()`）：mod 的 `_ready` 早于 `ProgressData._ready → check_for_available_dlcs()`。此时访问 `isvc.characters` 会以空的 `available_dlc_ids` 重建并**永久缓存**，导致 DLC1/DLC2 角色从列表中消失（道具 / 武器同理）。改法：把首次访问 `characters/items/weapons` 的代码全部推迟到 ProgressData 就绪之后（`call_deferred`，或检查 `ProgressData.available_dlc_ids` 已填充），首次访问前调用一次 `invalidate_*_cache()`。存档里正在进行的一局用到自定义角色这一需求：ProgressData 在 `_ready` 末尾才 `load_game_file()`，同一帧的 deferred 调用来不及；可在 `item_service.gd` 扩展中覆盖 `_rebuild_characters()`（见下条），让自定义角色在任何一次重建中都存在，这样无论何时访问都不会缺。
2. **自定义内容在重建后丢失**：扩展 `res://singletons/item_service.gd`（已有此扩展），覆盖 `_rebuild_items()` / `_rebuild_characters()` / `_rebuild_weapons()`：先调用父类，再把 `_custom_items` / `_customs` / `_custom_weapons` 追加进去；不要再直接 `push_back` / `erase` 缓存数组（`mod_main.gd:1122/1127/2665/2728/2787/2827/3059/3132`），改为改自己的表并 `invalidate_*_cache()`。
3. **商店池**：覆盖 `init_unlocked_pool()`，在父类之后把已解锁、`can_be_looted`、未禁用的自定义道具 / 武器按 tier 推入 `_tiers_data[tier][TierData.ALL_ITEMS / ITEMS / WEAPONS]`（照抄原版条件）。否则自定义道具、补低级武器永远不会出现在商店和箱子里。`_repool` 的处理改为依赖这一覆盖即可，因为 `RunData.reset()` 和难度选择都会重建池子。
4. `mod_main.gd:3123` `w.add_to_chars_as_starting = []`：删除。
5. `graph/runtime.gd:508`：
   ```gdscript
   var r = SpawnRequest.new(EntityType.ENEMY, scene, ZoneService.get_rand_pos())
   r.player_index = p
   main._entity_spawner.spawn_entity_birth(r)
   ```
6. `graph/runtime.gd:471` `CHARM_SCENE` → `res://effect_behaviors/enemies/charm_enemy_effect_behavior.tscn`。
7. `mod_main.gd:3232` `curse_graph`：`pd.get_dlc_data("abyssal_terrors")` → `ItemService.get_dlc_data_by_id("abyssal_terrors")`，并加 `"abyssal_terrors" in ProgressData.active_update_data` 判断（否则返回值永远非空）。
8. `mod_main.gd:3383` `_dlcs()`：`available_dlcs` 已不存在（当前会静默返回 `[]`，未拥有 DLC 的效果从效果库中消失）。改为返回未拥有 DLC 的 `update_data.item_set`（字段 `characters/items/weapons` 同名，`_find_dlc`、`_library_sources`、`library()` 无需再改），对 `PrimalDreadItemSetData` 另外并入 `meca_items + mutant_items + evolution_items`。

### P1
9. `catalog.gd:545–598` 属性图标路径（31 处 `res://items/all/<id>/…`、`res://entities/units/enemies/looter/…`）全部失效，见 1.5。建议改为运行时按 id 取道具的 `icon`（`find_target("item", id).icon`），不再写死路径；`catalog.gd:543` `ITEM_ICON` 未使用，可删除。
10. `mod_main.gd:2598` `source_of()`：DLC2 内容不在 `res://dlcs/` 下，会被判为 "vanilla"。改为 `ItemService.get_update_data_by_item_id(res)` 得到套组 id（角色需遍历 `item_set.characters`），用套组 id（或套组名 `tr(update.name)`）显示来源。
11. `mod_main.gd:1876`、`ui/editor_ui.gd:3730` `is_dlc_available_and_active("abyssal_terrors")`：语义已变（不再有单独停用），本局启用用 `"abyssal_terrors" in ProgressData.active_update_data`；编辑器里显示用 `ProgressData.is_dlc_available()`。
12. 自定义角色基于 DLC2 角色时，复制 `required_item_set` 与 `banned_meca_stats`（`_fill_custom`，`mod_main.gd:2730` 附近）；GMO 融合同理。否则变异体等角色的克隆在 DLC2 套组关闭时也能选，`mutant_only` 等效果失效。
13. 带物品 id 语义的新效果（复制到其他道具后会出问题）：`item_lifeform_scanner`（按 id 查找并移除持有者，与沙漏相同）、恐龙蛋链（按 id 推进）、`fossil_count`（按标记文本计数）、`item_ammosaurus`、`evolved_leap` / `item_tumor`（按 id 排除异变）、`EffectOption` / `ModularEffect`（只在机械武器上有意义）、`multiply_value`（只在装备时乘一次）。在效果库中标注或禁止这些来源。
14. 字段编辑：武器 `WSTAT_FIELDS` 加 `can_shoot_without_target`；道具可加 `minimum_difficulty`；角色可加 `banned_meca_stats`；不要暴露 `is_meca / is_mutant / meca_power / meca_rank`。
15. 效果符号：`Effect.Sign` 新增 `EVOLUTION_MECA = 6`、`EVOLUTION_MUTANT = 7`；凡是按 0–5 枚举或判断 `effect_sign` 的地方要能容纳新值（`catalog.gd:251` LATE_FIELDS、`mod_main.gd:3197` 的好坏方向判断）。
16. 蓝图触发 "cursed_kill"（`extensions/main.gd:57`）不受影响（`curse_enemy_effect_behavior.gd` 文件名未变）；可选新增"击杀进化敌人"触发：`enemy._is_meca or enemy._is_mutant`。
17. 商店"必定出现"（`inject_shop_force`，`mod_main.gd:3485`）：`apply_item_effect_modifications` 现在可能把武器机械化；目前只对 `ItemData` 调用，结果不变。若以后对武器也调用，要处理 `EffectOption` 二选一。

### P2
18. `manifest.json` `compatible_game_version` → `["1.2.X.X"]`。
19. 翻译取词来源改为 `1.2/resources/translations/translations.csv`（单表，含 DLC，约 530 个新 key，15 条 zh 有改动，en 无改动）。`broeditor.csv` 中引用的原版 key 未被删除。
20. 测试：`tests/BroEditor/suite_core.gd`（1072 鲁特琴效果路径仍有效；1224/1305/1474/1530/1557/2173/2204 用了 `get_dlc_data` / `available_dlcs`；528 引用 `dlc_1_data.gd` 仍在；1947 `res://items/all/alien_eyes/alien_eyes_stats.tres` → `00_base_game/`）、`suite_battle.gd:78`（rip_and_tear 路径）。`run_tests.sh` 的 `PROJECT=$HERE/../../..` 指向 `D:\dev\mod\Brotato`，那里已没有 `project.godot`（工程在 `1.1/`、`1.2/` 下），需要改成指向 `1.2`，并把 `mods-unpacked/` 放进 `1.2/`。
21. 截图、帮助文本里提到 DLC 开关的地方改为"物品套组"。
22. 新增对角色 `banned_upgrade_stats` 和 `banned_meca_stats` 的处理。

---

## 8. AutoAnthony 需要调整的地方

### P0
1. `mod_main.gd:879` `pd.get_dlc_data("abyssal_terrors")` → `ItemService.get_dlc_data_by_id("abyssal_terrors")`（本身只在 `it.is_cursed` 时用到，加上启用判断更稳）。目前调用不存在的方法会直接报错，读档 / 重放触发条款时出现。
2. `aa/runtime.gd:14` `EXPLOSION_EFFECT_PATH` → `res://items/all/00_base_game/rip_and_tear/rip_and_tear_effect_1.tres`（爆炸载荷全部失效）。
3. **补全低级武器进不了商店**（`mod_main.gd:469–483` `register_low_weapons` 推入 `isvc.weapons`，`:575`、`:732` 调 `init_unlocked_pool()`）：1.2 的池只来自套组，而且 `RunData.reset()`、难度选择、读档都会重建。需要新增 `extensions/singletons/item_service.gd`：覆盖 `init_unlocked_pool()`，父类之后把 `_low_weapons` 中已解锁的武器推入对应 tier 的 `ALL_ITEMS` 与 `WEAPONS`；覆盖 `_rebuild_weapons()` 把它们加回列表（否则 `get_weapon_from_weapon_id`、合成查找在重建后找不到）。别忘了在 `mod_main._init` 里 `install_script_extension`。
4. 首次访问 `isvc.items/characters/weapons` 的时机：AA 的注册是 `call_deferred` 的，早于读档但晚于 `check_for_available_dlcs()`，没问题；若以后有代码挪到 `_ready` 里同步执行，会触发 1.3 的缓存问题。

### P1
5. **原生物品清单**：`native_only(isvc.items)`（`mod_main.gd:453/509/523`）现在包含 `meca_items`、`mutant_items`、`evolution_items`、`item_tumor`（max_nb 0、价格 1）、`item_used_lifeform_scanner`、`item_dino_egg_2/_1`。按 1.1 的规则处理会出问题：
   - `aa/catalog.gd:409` `ANCHORED_ITEMS` 补：`item_tumor`、`item_used_lifeform_scanner`、`item_dino_egg`、`item_dino_egg_2`、`item_dino_egg_1`、`item_ammosaurus`（蛋链按 id 推进，最后一阶由弹药恐龙接手）、`item_meca_evolved_leap`、`item_mut_evolved_leap`（异变排除按 id）。
   - 价格分布（`PRICE_POOL_EXCLUDED`）排除肿瘤、已使用扫描仪、蛋的后两阶。
   - 机械 / 异变 / 双路线道具不在常规池里，是否重组、按什么稀有度统计要单独决定；它们在 `update_pools()` 里被 `duplicate()` 后注入，AA 原地修改原资源的做法对它们仍然有效。
6. **按 id 消耗的新机制**：`item_lifeform_scanner` 与沙漏一样，离开商店时 `RunData.get_player_item(Keys.item_lifeform_scanner_hash)` 找持有者并移除。要么加入 `CONSUMED_KEYS`（`catalog.gd:423`）和 `extensions/ui/menus/shop/*.gd` 的 `AA_NATIVE_HOLDERS` / `_on_GoButton_pressed` 特殊处理，要么加入 `MECHANIC_BANNED_KEYS`。注意 1.2 的 `_on_GoButton_pressed` 先算 `next_wave = RunData.get_next_wave()`（读 `item_hourglass` 效果计数），AA 现有的"先扣计数、再手动倒退波数"在 1.2 中仍然成立。
7. **新效果键分类**（`catalog.gd` 各表）：
   - 角色身份 → `CHAR_MECHANIC_BANNED`：`meca_only`、`mutant_only`、`dual_evolution`、`materials_as_health`、`no_level_upgrades`、`effect_no_weapon_in_shop`、`effect_crate_give_weapon`、`extra_starting_weapon_choices`、`fog_of_war_permanent`、`burn_weapon`、`burn_weapon_give_primitive_bonus`、`effect_mixing_up_wave`、`no_cure_between_wave`、`no_fruit_attracted_end_of_wave`、`more_horde`、`weapon_set_bonus`、`effect_mutate_end_of_wave`、`dig_sites`、`poacher_zone_materials`、`gain_stat_for_killed_enemies_in_zone`、`time_shift_on_hit`。
   - 依赖 id / 上下文 → `MECHANIC_BANNED_KEYS`：`fossil_count`、`item_lifeform_scanner`、`time_shift_stats`、`temp_stats_while_being_in_puddle`（只在丛林泥潭有意义，可考虑按区域）、`has_plastic_boots`。
   - `stat_evolution` → `PRESERVED_NATIVE_KEYS`（`catalog.gd:1027`，与 `stat_curse` 同理）：它决定果实拾取、商店注入和异变是否发生，重组掉会让 DLC2 道具失去身份。
   - 可作为普通机制 / 代价的：`bonus_crit_damage`、`burning_stacks`、`dismantle_price`（1 为不利）、`mutation_fruit_chance`、`mutate_into_better_tier_chance`、`enemy_evolution_chance`、`material_on_evolved_enemy_kill`、`heal_on_mutant_kill`、`explode_on_evolved_death`、`charm_evolved_on_hit`、`slow_meca_on_hit`、`spines_on_hit`、`fire_trail`、`fire_explosion`、`fire_puddle_on_burning_death`、`slow_time_when_below_hp`、`dig_sites_every_x_waves`、`item_box_recycling_gains`、`meca_parts_on_level_up`、`damage_taken_on_materials`。进化相关的几项只有进化值 ≠ 0 时才有价值，需要估值上的说明或排除。
   - `MultiplyValueEffect`、`EffectOption`、`ModularEffect` 不可搬运（前者"装备时乘一次"依赖时机，后两者只在机械武器上有意义）。
8. **武器重组**：16 个新武器系列的特殊效果脚本（见 2.7 武器部分）需要在 `weapon_gen.gd` / `weapon_value.gd` 中分类估值或排除；`SpawnStructureEveryKilledEnemiesEffect` 内嵌一个 `structure_effect`，`CarbonBowStatEffect` 是一组 5 条联动效果，不能单独拆。机械武器在商店生成时会以 `ItemService.get_base_weapon(my_id_hash)` 的属性为基准重算（`apply_meca_power`）：AA 原地修改原资源时没问题；补出的低级武器不在 `_base_weapon_lookup` 中，会退回用自身属性，也没问题。
9. **异变与 TriggerEffect**：`TriggerEffect.key = ID` 非空，若 `get_sign` 判为正面，会被异变复制进肿瘤并按 scale 缩放 `value`，还会参与肿瘤合并（比较 `serialize()`）。要么让 TriggerEffect 在 `can_effect_be_copied_by_mutation` 中被排除（如把 key 留空、用 `custom_key` 承载 ID，但要兼顾读档），要么确认缩放后的触发器语义正确并让 `runtime` 能从肿瘤上读到。异变产生的副本 `my_id` 不变，`is_generated()` 仍为 true。
10. **诅咒与机械互斥**：AA 对 `it.is_cursed` 的处理不变；新增 `is_meca` / `is_mutant` 的道具不会再被诅咒（`can_item_be_cursed`）。

### P2
11. 三个选择界面扩展仍然调用 `._ready()`（`extensions/ui/menus/run/character_selection.gd:13`、`weapon_selection.gd:10`、`difficulty_selection.gd:9`）。1.2 的 `_ready` 新增了 `ItemSetBar` 初始化和多初始武器状态（`_player_weapons[i] = []`、`_picked_elements`），重复执行可能导致重复连接信号或清空选择。删掉 super 调用（Godot 3 会自动调用每一层）。
12. "任意初始武器"（`any_start_weapons`）：DLC2 套组关闭时，返回的武器若属于未启用套组，会在界面上显示为不可用，但 `_get_unlocked_elements` 仍把它们列为已解锁；按 `ItemService.get_update_data_by_item_id(w)` + `ProgressData.has_item_set` 过滤。幸存者多选初始武器与 AA 的列表兼容。
13. `RunData.get_random_primary_stats()` 现在直接从 `primary_stats_list` 随机返回；`stat_evolution` 是 `is_primary_stat`，但不在 `primary_stats_list` 中，不受影响。
14. `manifest.json` → `["1.2.X.X"]`；测试 `tests/AutoAnthony/suite_core.gd:303/1052/1564`、`suite_audit.gd:557`（`get_dlc_data`）、`suite_battle.gd:195`（诅咒行为路径 → `res://effect_behaviors/enemies/curse_enemy_effect_behavior.gd`），`run_tests.sh` 的 PROJECT 路径同 BroEditor。
15. `COVERAGE.md`、`ITEMS.md` 等统计按 1.2 的原生物品重新生成（`tools/gen_coverage.py`）。

---

## 9. 核对方法（可复现）
- 删除 / 改签名的标识符：遍历 1.1 与 1.2 全部 `.gd` 的 `func/var/const/signal`（含多行参数），与两个 mod 中的调用取交集。得到 `get_dlc_data`、`available_dlcs`、`add_to_chars_as_starting`、`spawn_entity_birth`、`get_rand_pos`、`remove_item`、`_display_effect` 七项，已全部列入上文。
- 资源路径：提取两个 mod 中全部 `res://…(.png|.tres|.tscn|.gd)`，在 1.2 中逐个检查是否存在（33 个缺失，均为 1.5 所列迁移）。
- 内容差异：按 `my_id` 解析两版全部 `.tres`（内联子资源后逐字段比较）。

---

## 10. 1.2.0.1 → 1.2.0.2.beta-0 更新

对比对象：`1.2/`（1.2.0.1）与 `1.2.0.2.beta-0/`（GDRE 反编译）。只列有实际影响的平衡、机制和内容改动，bug 修复、文本修正、代码格式调整不在此列。

### 10.1 化石道具普遍加强
各化石的效果分三条：基础属性 / 负面属性 / 每个化石额外获得的属性（`EFFECT_GAIN_STAT_FOR_EVERY_FOSSIL`，按 `fossil_count` 计）。

| 道具 | 基础 | 负面 | 每个化石 |
| --- | --- | --- | --- |
| 化石下颚 `item_fossil_jaw` | 生命窃取 1 → **3** | 生命再生 -3 → **-2** | 生命窃取 1 → **2** |
| 化石左臂 `item_fossil_left_arm` | 护甲 1 → **3** | 速度 -3（不变） | 护甲 1（不变） |
| 化石左腿 `item_fossil_left_leg` | 速度 1 → **3** | 暴击率 -3（不变） | 速度 1 → **2** |
| 化石右臂 `item_fossil_right_arm` | 最大生命 1 → **3** | 闪避 -2（不变） | 最大生命 1 → **2** |
| 化石右腿 `item_fossil_right_leg` | 范围 5 → **15** | 攻速 -4（不变） | 范围 5（不变） |
| 化石头骨 `item_fossil_skull` | 伤害% 10（不变） | 闪避 -5 → **-3** | 伤害% 3 → **5** |
| 化石脊椎 `item_fossil_spine` | 生命再生 2 → **3** | 伤害% -5（不变） | 生命再生 1 → **2** |
| 化石尾巴 `item_fossil_tail` | 不变（收获 5 / 最大生命 -3 / 每个化石收获 3） | | |
| 化石牙齿 `item_fossil_tooth` | 最大生命 -2 → **-1** | | |

### 10.2 新道具与变异体改动
- **新道具「奇美拉细胞」`item_chimera_cells`**（`items/all/04_primal_dread/chimera_cells/`）：tier 1（稀有），价格 30，`max_nb = 5`，可锁定，默认未解锁；属于 DLC2 套组的 `mutant_items`（只在异变路线按进化值注入商店，见 3.6）。效果：新效果键 `mutate_item_on_equip_chance` = 25（「装备道具时有 25% 概率使其异变」）。图标暂用 `placeholder_item_icon.png`，翻译只有英文（`ITEM_CHIMERA_CELLS`、`EFFECT_MUTATE_ITEM_ON_EQUIP_CHANCE`）。
- **变异体挑战奖励**（`dlcs/dlc_2/challenges/variant_data.tres`）：野火异变 → 奇美拉细胞。**野火异变 `item_wildfire_mutation` 改为默认解锁**（`unlocked_by_default = true`）。
- **变异体角色效果**：`mutate_into_better_tier_chance` 50（异变时 50% 概率提升品质）→ `mutate_item_on_equip_chance` 10（装备道具时 10% 概率异变）。
- 装备时异变的规则（`RunData.try_mutate_item_on_equip`）：在商店购买（`base_shop`）和拾取道具箱（`main.gd`）后各判定一次；需要 `can_mutate_random_item(player_index)` 和 `ItemService.can_item_be_mutated(item)` 都成立，异变的就是刚得到的那件道具。原先的「随机挑一件道具异变」被拆成 `mutate_item(item, player_index)`，可以直接调用。异变复制该效果时的最低缩放 `mutation_min_scale` 为 0.7；该键属于饱和型概率（`mutation_saturating_chance_keys`）。

### 10.3 进化跃迁：吸引进化果实
- 机械进化跃迁 `item_meca_evolved_leap` 新增 `instant_meca_fruit_attracting` = 50；异变进化跃迁 `item_mut_evolved_leap` 新增 `instant_mutant_fruit_attracting` = 50（「机械/异变果实掉落时有 50% 概率立即被吸过来」）。
- 实现：`main.gd._try_attract_evolution_fruit()`，在果实生成时调用；多名玩家都有该效果时，按各自概率合并判定（至少一人成功的概率为 `1 - ∏(1 - p)`），再按概率加权选出吸引者。两个键都是饱和型概率。

### 10.4 机制数值
- **机械化属性数值**（`DLC2Data.get_meca_stat_value(stat, cost)`，`cost` = 机械零件花费）：旧版 cost 1/2/3/4 分别取普通/罕见/稀有/传说品质的升级数值，更高的 cost 按最后一级的差值线性外推，没有上限。新版 cost 截断到 1–8，在普通 → 传说之间等距插值后取整：cost 1 = 普通，cost 8 = 传说，cost 4 ≈ 罕见与稀有之间（位置 1.29），cost 超过 8 不再增加。**中高花费的机械化数值整体降低**。
- **异变复制效果的缩放**（`get_mutation_scale`）：缩放 = `0.1 + 0.9 * (|进化| / MAX)^EXP`。旧版 MAX = 150、EXP = 0.5；新版 MAX = **100**、EXP = **0.442**。同样的进化值得到的缩放更高：进化 10 / 25 / 50 / 100 时，旧版 0.33 / 0.47 / 0.62 / 0.83，新版 0.43 / 0.59 / 0.76 / 1.00。
- 敌人机械零件掉落率 `meca_parts_chance`：0.02 → **0.015**。
- 异变不再复制 `upgrade_random_weapon` 效果（加入 `mutation_copy_blacklist`）。
- 异变时如果既没有可删除的负面效果、也没有可复制的效果，不再添加占位效果「什么都没有发生」（`EFFECT_MUTATION_NOTHING_HAPPENED` 已删除）。
- 「生命值满时拾取消耗品获得属性」类效果（`consumable_stats_while_max`，如额外的胃）：本波上限只剩一部分时只加剩余的部分（以前整份照加），已达上限的这类效果不再作为异变复制的候选。
- 迷雾视野 `stat_fog_visibility`：角色带 `fog_of_war_permanent`（穴居人）时，非噩梦难度下也会显示和生效，并且可以被异变复制。文本 `FOG_VISIBILITY` 去掉了「噩梦难度下」。
- **禁用令牌**：本局开启禁用时，第 4 / 8 / 12 / 16 / 20 波结束时每名玩家 +1 令牌（`RunData.BAN_TOKEN_GAIN_EVERY_X_WAVES = 4`、`BAN_TOKEN_GAIN_MAX_WAVE = 20`，在 `on_wave_end()` 中发放）。
- 升级禁用：纵火犯额外禁用 `upgrade_engineering`；时间转换者禁用 `upgrade_dodge`。

### 10.5 丛林区域（DLC2）
- 酸液水坑：离开水坑后不再继续受酸液伤害（`dot_duration_after_exit` 3.0 → 0），每波伤害成长 0.1 → 0.075。玩家第一次进入酸液时，第一跳伤害要等满一个间隔才结算。
- 腕龙之足：落地时向周围 8 个方向发射子弹（普通 / 异变 / 机械三种形态各有一套攻击），移动速度 100 → 125。
- 敌人削弱：食人花之母 HP 40(+20/波) → 35(+16/波)、掉落 6 → 7，召唤冷却 70/50/100 → 90/75/110；翼龙 HP 10(+7) → 8(+6)，冲锋改为 0.5s 预判、持续 1.5s、速度降低；巨型蜻蜓冲锋速度 1000 → 700，冷却 45 → 55；双冠龙冷却 140 → 150；禽龙 HP 20 → 16；迅猛龙发现目标后的加速 100 → 90；谜标兽击退抗性 0.95 → 0.25；副栉龙击退抗性 0.7 → 0.5；肿头龙、厚鼻龙掉落 3 → 4。
- 刷怪：第 4 / 7 / 9 波的翼手龙（jeholopterus）换成小翼龙（baby_pterosaur）；杂兵组里的 jeholopterus 组（`000_trashes/unit_4`，已删除）换成 `unit_3`；第 3 / 11 / 17 波部分组从全图刷改为限定区域（`area` 200–500）；多处数量上限下调、间隔拉长（迅猛龙、食人花、谜标兽、三角龙、禽龙、异齿龙、双冠龙等），第 10 / 11 / 12 波的连续刷怪间隔最小值 1 → 2。
- 地洞布局（`entities/gpe/hole/holes_*`）：删除或挪动了几个洞。

### 10.6 其他
- 选择角色界面的「随机区域」改为在可用区域里随机抽取，并按区域 id 记住上次的选择（旧版按下标记录）。
- 读档 / 启动时自动同步挑战奖励：已完成的挑战会补发未解锁的道具/武器奖励（`ChallengeService.sync_challenge_rewards(false)`，在 `ProgressData` 加载存档后和 `ChallengeService` 初始化时调用；选项菜单的「已完成挑战」按钮（`_on_CompletedChallengeCheckButton_pressed`）用 `true`，同时重新锁上未完成挑战的奖励）。`unlock_reward(chal, track_in_run = true)` 新增参数。
- 图鉴完成度按已启用的 DLC 套组计算分母。

### 10.7 对两个 mod 的影响
- **API**：`FollowTargetAvoidForbiddenZonesMovementBehavior` 改名为 `AnticipateTargetAvoidForbiddenZonesMovementBehavior`（改为继承 `AnticipateTargetMovementBehavior`，路径不变）；两个 mod 都没有用到。`base_shop.gd` 中两处 `var next_wave := RunData.get_next_wave()` 改为 `=`，与 1.2 加载顺序陷阱（mod `_init` 时 RunData 还不存在）对应，shop 扩展仍在 `_ready` 安装，不受影响。`unlock_reward` 新增的参数有默认值，兼容。
- **新效果键**：`mutate_item_on_equip_chance`、`instant_meca_fruit_attracting`、`instant_mutant_fruit_attracting`（`Keys.*_hash`，已在 `player_run_data` 默认效果表中，`Text` 中有格式化参数）。
  - BroEditor：`catalog.gd` 的效果来源表可以补上这三个键（来源：`item_chimera_cells` / `character_variant`、`item_meca_evolved_leap`、`item_mut_evolved_leap`）；`mutate_into_better_tier_chance` 仍然来自野火异变。
  - AutoAnthony：`aa/catalog.gd` 的 `PATH_ITEMS` 可以加上 `item_chimera_cells: -1`（异变路线），机制表加上 `mutate_item_on_equip_chance`；化石数值变了，先验和审计统计需要重新跑。
- 新道具缺中文和其他语言的翻译，mod 显示新词条时会退回英文。
