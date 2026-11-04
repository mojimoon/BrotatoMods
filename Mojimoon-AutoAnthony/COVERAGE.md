# 原版效果覆盖表

本表由测试 `test_80_native_effect_coverage` 遍历原版全部道具、角色、武器自动生成，列出每一种**非纯属性增减**效果在东尼算法中的处理方式。纯属性行（22 种属性）统一按价格回归的权重重组，不在此列。

## 处理方式

| 处理 | 含义 | 估值 |
| --- | --- | --- |
| `trigger`（40 种） | 拆解为 (扳机, 载荷) 先验，由通用触发条款重新表达 | 单位价值 × 每波频率（见 README 第 4 节） |
| `scaling`（28 种） | 计数 × 属性自由搭配重新生成（原版 GainStatForEveryStatEffect） | 目标属性权重 × 数值 × 计数期望 / 每 N；计数期望由原版道具校准 |
| `next_wave`（1 种） | 下一波（芹菜茶 / 孔雀）：一次性，下一波开始时生效；约一半附带同一行为下的负面行（敌人属性或自身属性降低） | 一波的价值 = 整局价值 / 剩余波数（≈ 2 × 永久累积倍率 − 1）；孔雀校准吻合 |
| `gain_mod`（3 种） | 属性修改 ±XX% 重新生成（原版 StatGainsModificationEffect） | 属性权重 × 属性期望总量 × XX% |
| `scalar`（44 种） | 原样搬运，并按预算缩放数值（1 单位 .. 原版 1.5 倍） | 来源道具剩余价值按数值比例折算 |
| `mechanic`（58 种） | 原样搬运（炮台、宠物、爆炸、武器类加成……） | 道具：来源道具 (预算 − 属性行价值) / 机制数；角色：(角色总价值 − 可估值部分) / 机制数，限制 30–80 |
| `downside`（15 种） | 作为代价搬运 | 来源道具因它多拿到的正面预算（至少 3） |
| `weapon_counter`（4 种） | 武器数量计数（常规池）："每把 [不同 / 所有 / IV 级 / I 级] 武器 +X [属性]"，属性与数值重新生成 | 属性权重 × 数值 × 计数期望（不同武器 3.5 / 武器 5 / IV 级 1 / I 级 1.2） |
| `char_component`（5 种） | 角色效果（常规池）：武器类型加成、对燃烧目标额外伤害、和平主义者、+武器栏 | 按原版角色数值与对应属性 / 材料估值 |
| `char_more`（11 种） | 更多角色效果（选项开启时进入道具池）：构筑物聚集、升级所需经验 ±、神秘生物（每棵存活的树）、几率魅惑、宠物伤害缩放、地图大小 ±、自身价格 −100%、武器价格 −X%、道具价格 +X%（代价）、每波异变一次、挖掘点 | 升级所需经验按反比例（等价获得经验）；地图大小价值约为 0；其余按材料 / 经验 / 伤害估值 |
| `char_beta`（28 种） | 全部角色效果（BETA 选项）：一击必死、移动时无法攻击、进店摧毁武器、无法回血、武器等级 / 类型 / 数量限制、毒果、精英变强、无法锁定、无法拥有构筑物（代价，高补偿）；所有武器计入套装、商店至少一把武器、升级获得武器栏、每店偷 1 件、商店总是出售某道具 + 每有 1 个该道具获得属性；史前惧兽：受伤时时间变慢，代价 波次之间不回血、波末不吸取果实、永久迷雾、更多尸潮、商店不出售武器（+ 箱子给武器） | 限制按固定补偿（3–45 材料，大代价只出现在高预算道具上）；正面按武器栏 / 商店价值估值；设定值型效果所在道具为独特 |
| `identity`（39 种） | 保留在角色上，不进入道具池（武器限制、初始装备、商店规则、负向机制……） | — |
| `anchored`（14 种） | 不作为组件来源：建造者炮台的角色专属效果；史前惧兽的进化飞跃与剃须泡沫、恐龙蛋链与弹药恐龙、肿瘤、生命形态扫描仪、原版化石（按道具 ID 实现或就是路线本身，道具本身保持原版） | — |
| `text`（6 种） | 纯描述行：需要的说明已合并进对应效果的同一行（“生效后此道具消失”“受到伤害时清空”），其余为音效 / 已用状态的提示 | — |
| `excluded`（3 种） | 不搬运：迷雾视野（只在迷雾事件中有意义）、进化值（决定进化路线，是道具身份）、生命形态扫描仪（按道具 ID 消耗）、化石计数（只由化石带，见 DESIGN"化石"） | — |
| `weapon`（50 种） | 武器专属效果：仅在“重组武器”时于同类型武器家族间整套交换 | 按等级对齐，不单独估值 |

## 明细

### `trigger`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `burn_chance` | 1 | item | scared_sausage Attacks have a 25% chance to deal 3x1 (+100%[/c |
| `burning_enemy_hp_percent_damage` | 1 | item | greek_fire Burning deals an additional 10% of current enemy HP as damag |
| `chance_double_gold` | 1 | item | metal_detector +5% chance to double the value of picked up materials |
| `consumable_stats_while_max` | 3 | item,char | extra_stomach +1 Max HP when picking up a consumable while at maximum heal / c:farmer +1 Harvesting when picking up a consumable while at maximum  |
| `convert_stats_half_wave` | 1 | char | c:cyborg 100% of your Ranged Damage are temporarily converted into En |
| `decaying_stats_on_consumable` | 1 | item | cauldron +20 % Damage for 2 seconds after picking up a consumable |
| `decaying_stats_on_hit` | 1 | item | saltwater +10 % Speed for 3 seconds when you take damage |
| `dmg_on_dodge` | 1 | item | riposte 100% chance to deal 1 (300%[img=15x15]r |
| `dmg_when_death` | 1 | item | cyberball 25% chance to deal 1 (25%[img=15x15]res |
| `dmg_when_heal` | 1 | char | c:lich 100% chance to deal 15 (100%[img=15x15] |
| `dmg_when_pickup_gold` | 2 | item,char | baby_elephant 25% chance to deal 1 (25%[img=15x15]res / c:lucky 75% chance to deal 1 (15%[img=15x15]res |
| `effect_gain_stat_every_killed_enemies` | 12 | weapon | w:ghost_flint_1 +1 % Attack Speed for every 20 enemies you kill during a wav / w:ghost_flint_2 +1 % Attack Speed for every 18 enemies you kill during a wav |
| `enemy_percent_damage_taken` | 2 | item | ice_cube Enemies take 10% more damage for 3 seconds when first hit by / smelly_rafflesia Attacks have a 25% chance to make enemies take 25% more dama |
| `explode_on_consumable` | 2 | item,char | spicy_sauce Consumables have a 50% chance to explode for 15 ([color=whit / c:glutton Consumables have a 100% chance to explode for 10 ([color=whi |
| `explode_on_death` | 1 | item | rip_and_tear Enemies have a 20% chance to explode for 10 (+5 |
| `explode_on_hit` | 2 | item,char | krakens_eye You have a 50% chance to explode for 10 (+500%[ / c:bull You explode for 30 (+300%[img=15x15]res |
| `gain_random_primary_stats_on_go_to_next_wave` | 1 | item | candy_bag Each wave grants 8 points randomly split between your primar |
| `gain_stat_for_equipped_item_with_stat` | 1 | item | snowball +1 Elemental Damage every time you get an item that increase |
| `gain_stat_for_every_step_after_equip` | 6 | char,weapon | c:hiker Earn 6 materials for every 10 steps you take during a wave / c:hiker +1 Max HP for every 80 steps you take during a wave |
| `gain_stat_for_killed_enemies_while_burning` | 1 | item | will_o_the_wisp +1 Elemental Damage for every 30 burning enemies you kill du |
| `gain_stats_on_reroll` | 2 | item | bone_dice +50% chance to get +1 % Damage when rerolling in the shop / bone_dice +10% chance to get -1 Max HP when rerolling in the shop |
| `giant_crit_damage` | 1 | item | giant_belt Critical hits deal 10% of an enemy��s current health as bonus |
| `gold_on_crit_kill` | 6 | item,weapon | hunting_trophy 33% chance to gain 1 material when killing an enemy with a c / w:dagger_1 50% chance to gain 1 material when killing an enemy with a c |
| `gold_on_cursed_enemy_kill` | 1 | item | black_flag +1 material when you kill a cursed enemy |
| `heal_on_crit_kill` | 1 | item | tentacle +20% chance to heal 1 HP when killing an enemy with a critic |
| `heal_on_dodge` | 1 | item | adrenaline 50% chance to heal 5 HP when dodging an attack |
| `heal_on_kill` | 1 | item | goblet +15% chance to heal 1 HP when killing an enemy |
| `heal_when_pickup_gold` | 1 | item | cute_monkey +8% chance to heal 1 HP when picking up a material |
| `item_box_gold` | 1 | item | bag +15 materials when you pick up a crate |
| `remove_speed` | 1 | item | ugly_tooth Hitting an enemy removes 5% of their speed. Max 20% |
| `stats_below_half_health` | 2 | char | c:golem +40 % Attack Speed when you have less than 50% health / c:golem +20 % Speed when you have less than 50% health |
| `stats_end_of_wave` | 18 | item,char | celery_tea +5 % XP Gain at the end of a wave / grinds_magical_leaf +3 Max HP at the end of a wave |
| `stats_on_fruit` | 1 | char | c:druid 33% chance to get +1 Luck when you pick up a fruit |
| `stats_on_level_up` | 11 | item,char | decomposing_flesh +1 % Life Steal when you level up / decomposing_flesh -1 Max HP when you level up |
| `temp_consumable_stats_while_max` | 1 | item | penguin +1 HP Regeneration until the end of the wave when picking up |
| `temp_stats_on_dodge` | 1 | char | c:cryptid +3 % Attack Speed until the end of the wave when you dodge a |
| `temp_stats_on_hit` | 3 | item,char,weapon | triangle_of_power -2 % Damage when you take damage until the end of the wave / c:masochist +5 % Damage when you take damage until the end of the wave |
| `temp_stats_per_interval` | 4 | item,weapon | medikit +2 HP Regeneration every 5 seconds until the end of the wave / wisdom +5 % Damage every 5 seconds until the end of the wave |
| `temp_stats_while_moving` | 2 | char | c:streamer +40 % Damage while moving / c:streamer +40 % Attack Speed while moving |
| `temp_stats_while_not_moving` | 10 | item,char,weapon | barricade +8 Armor while standing still / chameleon +20 % Dodge while standing still |

### `scaling`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `gain_stat_for_every:burning_enemy` | 1 | item | fried_rice +1 HP Regeneration for every currently burning enemy [+0] |
| `gain_stat_for_every:common_item` | 3 | item,char | fairy +1 HP Regeneration for every different Tier I item you have  / c:king -2 Max HP for every different Tier I item you have [+0] |
| `gain_stat_for_every:crates_collected` | 1 | char | c:archaeologist +3 % XP Gain for every crate collected [+0] |
| `gain_stat_for_every:different_item` | 1 | char | c:curious +2 % XP Gain for every different Item you have [+0] |
| `gain_stat_for_every:duplicate_item` | 1 | char | c:curious -10 % Damage for every duplicate item or weapon you have [+0 |
| `gain_stat_for_every:free_weapon_slots` | 1 | char | c:captain +60 % XP Gain for every free weapon slot you have [+360] |
| `gain_stat_for_every:item_bait` | 1 | char | c:fisherman +2 Harvesting for every 1 Bait you have [+0] |
| `gain_stat_for_every:knockback` | 1 | item | coil +1 % Damage for every 1 Knockback you have [+0] |
| `gain_stat_for_every:legendary_item` | 2 | item,char | fairy -3 HP Regeneration for every different Tier IV item you have / c:king +5 Max HP for every different Tier IV item you have [+5] |
| `gain_stat_for_every:living_enemy` | 1 | item | community_support +1 % Attack Speed for every current living enemy [+0] |
| `gain_stat_for_every:living_tree` | 1 | char | c:cryptid +3 HP Regeneration for every current living tree [+0] |
| `gain_stat_for_every:materials` | 4 | item,char | padding +1 Max HP for every 80 Materials you have [+0] / c:saver +1 % Damage for every 25 Materials you have [+1] |
| `gain_stat_for_every:percent_player_missing_health` | 8 | char,weapon | c:vampire +2 % Damage for every 1% of missing health [+0] / c:vampire +1 % Life Steal for every 3% of missing health [+0] |
| `gain_stat_for_every:pet` | 1 | char | c:beast_master +2 % Speed for every permanent 1 Pet you have [+0] |
| `gain_stat_for_every:stat_armor` | 2 | item,char | stone_skin +1 Max HP for every permanent 1 Armor you have [+0] / c:knight +2 Melee Damage for every 1 Armor you have [+0] |
| `gain_stat_for_every:stat_crit_chance` | 1 | item | lucky_coin +2 Luck for every 1 % Crit Chance you have [+0] |
| `gain_stat_for_every:stat_curse` | 2 | char | c:romantic -3 % Damage for every 5 Curse you have [+0] / c:romantic -1 Armor for every 5 Curse you have [+0] |
| `gain_stat_for_every:stat_dodge` | 1 | item | retromations_hoodie +2 % Attack Speed for every 1 % Dodge you have [+0] |
| `gain_stat_for_every:stat_elemental_damage` | 3 | item,char | strange_book +1 Engineering for every permanent 1 Elemental Damage you ha / c:artificer +4 % Explosion Size for every 1 Elemental Damage you have [+ |
| `gain_stat_for_every:stat_engineering` | 1 | char | c:dwarf +1 Melee Damage for every permanent 2 Engineering you have [ |
| `gain_stat_for_every:stat_lifesteal` | 1 | item | bloody_hand +2 % Damage for every 1 % Life Steal you have [+0] |
| `gain_stat_for_every:stat_luck` | 1 | item | pearl +1 % Damage for every permanent 10 Luck you have [+0] |
| `gain_stat_for_every:stat_max_hp` | 1 | char | c:chunky +1 % Damage for every permanent 3 Max HP you have [+5] |
| `gain_stat_for_every:stat_melee_damage` | 2 | char | c:generalist +1 Ranged Damage for every 2 Melee Damage you have [+0] / c:diver +1 HP Regeneration for every 2 Melee Damage you have [+0] |
| `gain_stat_for_every:stat_range` | 1 | char | c:hunter +1 % Damage for every 10 Range you have [+0] |
| `gain_stat_for_every:stat_ranged_damage` | 1 | char | c:generalist +2 Melee Damage for every 1 Ranged Damage you have [+0] |
| `gain_stat_for_every:stat_speed` | 3 | item,char | estys_couch +2 HP Regeneration for every permanent -1 % Speed you have [ / power_generator +1 % Damage for every permanent 1 % Speed you have [+5] |
| `gain_stat_for_every:structure` | 3 | item,char | lighthouse -1 Engineering for every 1 Structure you have [+0] / c:streamer +2 Armor for every 1 Structure you have [+0] |

### `next_wave`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `stats_next_wave` | 5 | item | celery_tea +50 % XP Gain during the next wave / celery_tea +100 % Enemy health during the next wave |

### `gain_mod`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `EFFECT_REDUCE_STAT_GAINS` | 2 | char | c:entrepreneur Damage modifications are reduced by 50% / c:vampire Max HP modifications are reduced by 25% |
| `effect_increase_stat_gains` | 17 | char | c:ranger Ranged Damage modifications are increased by 50% / c:mage Elemental Damage modifications are increased by 25% |
| `effect_reduce_stat_gains` | 32 | char | c:ranger Max HP modifications are reduced by 25% / c:mage Melee Damage modifications are reduced by 100% |

### `scalar`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `bonus_crit_damage` | 1 | item | raptor_eye +0.5x Critical Damage Multiplier |
| `bounce` | 1 | item | ricochet Your projectiles gain +1 bounce |
| `burning_cooldown_reduction` | 1 | item | eyes_surgery Burning activates 20% faster |
| `burning_spread` | 1 | item | snake Burning spreads to an additional nearby enemy |
| `crate_chance` | 1 | char | c:survivor +25% chance to find crates |
| `curse_locked_items` | 1 | item | fish_hook Locked items and weapons have a 20% chance to become cursed  |
| `damage_against_bosses` | 2 | item,char | silver_bullet +25% damage against bosses and elites / c:jack +125% damage against bosses and elites |
| `dismantle_price` | 1 | item | titanium_excess -25% Dismantle price |
| `enemy_fruit_drops` | 2 | item,char | fruit_basket Enemies have a higher chance of dropping fruits / c:druid Enemies have a higher chance of dropping fruits |
| `enemy_gold_drops` | 1 | item | starfish +20% materials dropped from enemies |
| `enemy_speed` | 1 | item | snail -8 % Enemy Speed |
| `extra_loot_aliens` | 1 | char | c:curious 2 additional loot aliens appear every wave |
| `extra_loot_aliens_next_wave` | 1 | item | lure 2 additional loot aliens appear during the next wave |
| `free_rerolls` | 1 | item | dangerous_bunny +1 free reroll in the shop |
| `gain_pct_gold_start_wave` | 1 | item | piggy_bank +20% of your materials at the start of waves (stops working  |
| `gold_drops` | 2 | item,char | evil_hat +70% materials dropped / c:jack +200% materials dropped |
| `harvesting_growth` | 2 | item,char | crown Harvesting increases by an additional 8% at the end of a wav / c:farmer Harvesting increases by an additional 3% at the end of a wav |
| `heal_on_mutant_kill` | 1 | item | eldritch_figurine +50% chance to heal 1 HP when killing a mutated enemy |
| `hit_protection` | 1 | item | tardigrade Nullifies the damage of one hit taken every wave |
| `increase_material_value` | 1 | char | c:buccaneer Picked up materials have +100% value |
| `instant_gold_attracting` | 2 | item | baby_gecko +25% chance to instantly attract a material when it��s droppe / sifds_relic +100% chance to instantly attract a material when it��s dropp |
| `item_box_recycling_gains` | 1 | char | c:archaeologist Gain 75% more materials from recycling crates |
| `item_hourglass` | 1 | item | hourglass Turns back time, decreasing the current wave count by 1 |
| `items_price` | 1 | item | coupon -5 % Items Price |
| `jellyshield_count` | 1 | item | jellyshield Spawns a Jellyshield pet that orbits around the player. It c |
| `level_upgrades_modifications` | 1 | item | barnacle +35% stats gained from level upgrades |
| `loot_alien_chance` | 1 | item | whistle +50% chance for loot aliens to appear |
| `loot_alien_speed` | 1 | item | whistle +20% movement speed for loot aliens |
| `material_on_evolved_enemy_kill` | 1 | item | flare +1 material when you kill evolved (mecha and mutated) enemie |
| `mutate_into_better_tier_chance` | 2 | item,char | wildfire_mutation 25% chance that a mutating item is replaced by a mutated ite / c:variant 50% chance that a mutating item is replaced by a mutated ite |
| `mutation_fruit_chance` | 1 | item | boosted_mitosis +50% chance for mutated enemies to drop a mutation fruit |
| `number_of_enemies` | 6 | item,char | gentle_alien +5% Enemies / mouse +10% Enemies |
| `pierce_on_crit` | 1 | item | eyepatch Projectiles get +1 piercing on critical hit |
| `piercing` | 3 | item,char | bandana Projectiles pierce through 1 additional target / sharp_bullet Projectiles pierce through 1 additional target |
| `piercing_damage` | 1 | item | pumpkin +15% Piercing Damage. Can't go above base damage |
| `projectiles` | 1 | char | c:renegade +2 projectiles |
| `recycling_gains` | 2 | item,char | recycling_machine Gain 35% more materials from recycling items / c:entrepreneur Gain 25% more materials from recycling items |
| `reroll_price` | 1 | item | spyglass -25 % Reroll Price |
| `stronger_loot_aliens_on_kill` | 1 | char | c:curious All future loot aliens become stronger when you kill a loot  |
| `structure_attack_speed` | 1 | item | clockwork_wasp +10 % Structure attack speed |
| `structure_range` | 1 | item | rusty_antenna +15 Structure Range |
| `torture` | 1 | item | torture Restore 5 HP per second. Cannot heal any other way. |
| `tree_turrets` | 1 | item | pocket_factory Killing a tree spawns a turret |
| `trees` | 4 | item,char | tree More trees spawn / c:explorer More trees spawn |

### `mechanic`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `()` | 1 | item | jellyshield  |
| `(EFFECT_MELEE_WEAPON_BONUS)` | 1 | char | c:romantic +50 Range with melee weapons |
| `(EFFECT_PET_BLAZEMANDER)` | 1 | item | blazemander Spawns a Blazemander pet that deals 1 (+1%[/col |
| `(EFFECT_PET_BONK_DOG)` | 1 | item | bonk_dog Spawns a Bonk Dog pet that deals 10 (+60%[/colo |
| `(EFFECT_PET_BOT_O_MINE)` | 1 | item | bot_o_mine Spawns a Bot-O-Mine structure that shoots bullets dealing 10 |
| `(EFFECT_PET_CATLING_GUN)` | 1 | item | catling_gun Spawns a Catling Gun pet that shoots bullets dealing 10 ([co |
| `(EFFECT_PET_DOC_MOTH)` | 1 | item | doc_moth Spawns a Doc Moth pet that flies around the map. When the pl |
| `(EFFECT_PET_HUNGRY_HUNGRY_DINOSAUR)` | 1 | item | hungry_hungry_dinosaur Spawns a Hungry Hungry Dinosaur pet that deals 15 ([color=wh |
| `(EFFECT_PET_LOOTWORM)` | 1 | item | lootworm Spawns a Lootworm pet that collects materials and destroys t |
| `(EFFECT_PET_MOSQUITOR)` | 1 | item | mosquitor Spawns a Mosquitor pet that flies around you and shoots enem |
| `(EFFECT_PET_RATZILLA)` | 1 | item | ratzilla Spawns a Ratzilla pet that deals 5 (+10%[/color |
| `(EFFECT_PET_SCAPEGOAT)` | 1 | item | scapegoat Spawns a Scapegoat pet that moves around the map and gets ta |
| `(effect_dart_trap)` | 1 | item | dart_trap A dart trap spawns every 12 seconds, firing 6 darts dealing  |
| `(effect_garden)` | 1 | item | garden Spawns a garden that creates a fruit every 15 seconds |
| `(effect_landmines)` | 1 | item | landmines A landmine spawns every 12 seconds dealing 10 ( |
| `(effect_turret)` | 1 | item | turret Spawns a turret that shoots bullets dealing 10 ([color=white |
| `(effect_turret_damage_taken)` | 1 | item | bleeding_turret Spawns a turret that shoots bullets dealing 8 ( |
| `(effect_turret_flame)` | 1 | item | turret_flame Spawns a turret that shoots flames dealing 8x5 ([color=white |
| `(effect_turret_healing)` | 1 | item | turret_healing Spawns a medical turret that shoots bullets healing 3 ([colo |
| `(effect_turret_laser)` | 1 | item | turret_laser Spawns a turret that shoots piercing bullets dealing 20 ([co |
| `(effect_turret_rocket)` | 1 | item | turret_rocket Spawns a turret that shoots explosive bullets dealing 25 ([c |
| `(effect_tyler)` | 1 | item | tyler Spawns a little guy that slowly shoots 10 piercing lightning |
| `alien_eyes` | 1 | item | alien_eyes Shoots 6 alien eyes around you every 3 seconds dealing 8 ([c |
| `bonus_damage_against_targets_above_hp` | 1 | item | small_fish +10% damage against targets above 75% health |
| `bonus_weapon_class_damage_against_cursed_enemies` | 1 | char | c:sailor +200% damage with Naval weapons against cursed enemies |
| `burning_stacks` | 1 | item | pyromaniac Burning from your different weapons stacks instead of only k |
| `charm_evolved_on_hit` | 1 | item | virus Hitting evolved (mecha and mutated) enemies that have less t |
| `damage_taken_on_materials` | 1 | item | failsafe_core You do not die when your life reaches 0. Damage is taken on  |
| `dig_sites_every_x_waves` | 1 | item | dig_site 1 dig site appears every 3 waves, stay on it for 5 to 6 seco |
| `dodge_cap` | 4 | item,char | ghost_outfit Dodge is capped at 70% / c:ghost Dodge is capped at 90% |
| `duplicate_item` | 1 | item | mirror Duplicates the next item you get from the shop (item limits  |
| `explode_on_consumable_burning` | 1 | char | c:chef Consumables explode for 5x1 (+100%[img= |
| `explode_on_evolved_death` | 1 | item | exothermic_reaction Evolved (mecha and mutated) enemies have a 33% chance to exp |
| `explode_on_overkill` | 1 | char | c:ogre Enemies taking double their max health as damage explode for |
| `explode_when_below_hp` | 1 | item | sunken_bell Once per wave, you explode for 100 (+500%[/colo |
| `extra_item_in_crate` | 2 | item | pearl +3% chance of finding an extra Pearl in a crate / treasure_map +20% chance of finding an extra item in a crate |
| `fire_explosion` | 1 | char | c:arsonist Explosions leave a puddle of fire that scales with explosion |
| `fire_puddle_on_burning_death` | 1 | char | c:arsonist 50% chance for enemies dying while burning to leave a puddle |
| `fire_trail` | 1 | item | magma_boots You leave a trail of fire behind you that deals 5x3 ([color= |
| `gain_stat_when_attack_killed_enemies` | 1 | char | c:dwarf +1 Engineering when killing at least 5 enemies with a direct |
| `has_plastic_boots` | 1 | item | plastic_boots You are no longer affected by puddles |
| `hp_regen_bonus` | 1 | item | potion HP Regeneration is doubled when you have less than 50% healt |
| `increase_tier_on_reroll` | 1 | item | goldfish Items will be 1 tier higher after the next reroll |
| `knockback_aura` | 1 | item | lantern Knocks nearby enemies back every 3 seconds |
| `minimum_weapon_cooldowns` | 1 | item | ball_and_chain Weapons have a minimum cooldown of 0.75 seconds between atta |
| `modify_every_x_projectile` | 1 | item | seashell Every ranged weapon's 5th projectile has +3 projectiles |
| `one_shot_trees` | 1 | item | lumberjack_shirt Trees die in one hit |
| `projectiles_on_death` | 1 | item | baby_with_a_beard One bullet dealing 1 (+100%[img=15x15]r |
| `reload_when_pickup_gold` | 1 | char | c:buccaneer Picking up a material resets the cooldown of all your weapon |
| `slow_meca_on_hit` | 1 | item | jamming_backpack Hitting mecha enemies slows them by 50% for 2 seconds |
| `slow_time_when_below_hp` | 1 | item | pocket_watch Once per wave, enemies and their projectiles are slowed by 7 |
| `spines_on_hit` | 1 | item | infected_skin 33% chance to shoot 8 spines around you dealing 5 ([color=wh |
| `structures_can_crit` | 1 | item | pile_of_books Your structures can crit |
| `structures_cooldown_reduction` | 1 | item | improved_tools Increases the attack speed of your structures by 0% ([color= |
| `temp_stats_while_being_in_puddle` | 1 | item | mud_lover 60 % Damage while being in a puddle |
| `upgrade_random_weapon` | 1 | item | anvil A random weapon is upgraded when entering a shop. If you hav |
| `wandering_bot` | 1 | item | wandering_bot Spawns a little bot that slows down nearby enemies |
| `weapon_scaling_stats` | 2 | item | frozen_heart Weapon and pet damage additionally scales with 10% Elemental / nail Weapon and pet damage additionally scales with 20% Engineeri |

### `downside`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `accuracy` | 1 | item | eyepatch -10% Accuracy |
| `burning_cooldown_reduction` | 1 | item | frozen_heart Burning activates 100% slower |
| `consumable_heal_over_time` | 1 | item | jerky Consumables heal you over 4 seconds instead of instantly |
| `enemy_damage` | 3 | item | black_flag +10 % Enemy damage / starfish +15 % Enemy damage |
| `enemy_health` | 2 | item | alien_baby +10 % Enemy health / black_flag +10 % Enemy health |
| `extra_elite_next_wave_chance` | 1 | item | candy_bag Each wave, 10% chance to spawn an additional elite  |
| `extra_enemies_next_wave` | 1 | item | bait Special enemies appear at the beginning of the next wave |
| `hp_cap` | 1 | item | handcuffs Your Max HP is capped at its current value [15] |
| `hp_start_next_wave` | 3 | item | weird_ghost Start the next wave with 1 HP / hourglass Start the next wave with 1 HP |
| `hp_start_wave` | 1 | item | sad_tomato Start waves with -50% HP |
| `lock_current_weapons` | 1 | item | knot Weapons can no longer be upgraded or recycled |
| `lose_hp_per_second` | 3 | item | blood_donation You take 1 damage per second (does not give invulnerability  / bloody_hand You take 1 damage per second (does not give invulnerability  |
| `number_of_enemies` | 2 | item | candle -10% Enemies / white_flag -5% Enemies |
| `piercing_damage` | 1 | item | sharp_bullet -20% Piercing Damage |
| `speed_cap` | 1 | item | shackles Your Speed is capped at its current value [5] |

### `weapon_counter`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `additional_weapon_effects` | 1 | char | c:multitasker -5 % Damage for every weapon you have [+0] |
| `tier_i_weapon_effects` | 2 | char | c:king -15 % Damage for every Tier I weapon you have [+0] / c:king -15 % Attack Speed for every Tier I weapon you have [+0] |
| `tier_iv_weapon_effects` | 2 | char | c:king +25 % Damage for every Tier IV weapon you have [+0] / c:king +25 % Attack Speed for every Tier IV weapon you have [+0] |
| `unique_weapon_effects` | 4 | item,char | focus -3 % Attack Speed for every different weapon you have [+0] / jelly +1 Max HP for every different weapon you have [+0] |

### `char_component`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `EFFECT_WEAPON_CLASS_BONUS` | 4 | char | c:brawler +50 % Attack Speed with Unarmed weapons / c:wildling +30 % Life Steal with Primitive weapons |
| `bonus_non_elemental_damage_against_burning_targets` | 1 | char | c:chef +200% damage from non elemental sources against burning targ |
| `effect_weapon_class_bonus` | 3 | char | c:crazy +100 Range with Precise weapons / c:artificer +100 % Damage with Tool weapons |
| `pacifist` | 1 | char | c:pacifist Gain 0.65 material and XP for every living enemy at the end  |
| `weapon_slot` | 7 | item,char | cybernetic_arm +1 Weapon Slot / c:multitasker You can equip up to 12 weapons at a time |

### `char_more`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `beast_master_effect` | 1 | char | c:beast_master Pet damage also scales with Melee Damage, Ranged Damage, Ele |
| `charm_on_hit` | 1 | char | c:romantic Hitting an enemy that has less than 25% health has a 7% ([co |
| `cryptid` | 1 | char | c:cryptid Gain 12 material and XP for every living tree at the end of  |
| `dig_sites` | 1 | char | c:archaeologist 4 dig sites appear on the map each wave, stay on one for 5 t |
| `effect_mutate_end_of_wave` | 1 | char | c:variant Automatically mutate once at the end of each wave |
| `group_structures` | 1 | char | c:engineer Structures spawn close to each other |
| `items_price` | 4 | char | c:mutant +50 % Items Price / c:saver +50 % Items Price |
| `map_size` | 2 | char | c:old -33% Map Size / c:explorer +33% Map Size |
| `next_level_xp_needed` | 4 | char | c:mutant -66% XP required to level up / c:baby +130% XP required to level up |
| `specific_items_price` | 2 | char | c:fisherman -100% Bait price / c:diver -100% Harpoon Gun price |
| `weapons_price` | 1 | char | c:arms_dealer -95% Weapons Price |

### `char_beta`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `DIE_IN_ONE_HIT` | 1 | char | c:wounded This character dies in One Hit |
| `all_weapons_count_for_sets` | 1 | char | c:vagabond Equipped weapons always contribute to the class bonuses of o |
| `can_attack_while_moving` | 1 | char | c:soldier You can��t attack while moving |
| `destroy_weapons` | 1 | char | c:arms_dealer All of your weapons are destroyed when entering a shop |
| `disable_item_locking` | 1 | char | c:gangster Can't lock items |
| `effect_crate_give_weapon` | 1 | char | c:survivor Crate loot gives weapon |
| `effect_no_weapon_in_shop` | 1 | char | c:survivor No weapon in the shop |
| `fog_of_war_permanent` | 1 | char | c:caveman There is a permanent obscuring fog increasing each wave |
| `guaranteed_shop_items` | 1 | char | c:fisherman Shops always sell a Bait |
| `item_steals` | 1 | char | c:gangster Can steal 1 item per shop |
| `item_steals_spawns_random_elite` | 1 | char | c:gangster Stealing from the shop can spawn an elite |
| `max_melee_weapons` | 1 | char | c:generalist You can only equip 3 melee weapons and 3 ranged weapons at a |
| `max_ranged_weapons` | 1 | char | c:generalist  |
| `max_weapon_tier` | 1 | char | c:wildling You can��t equip weapons above tier II |
| `min_weapon_tier` | 2 | char | c:knight You can only equip tier II weapons or above / c:sailor You can only equip tier II weapons or above |
| `minimum_weapons_in_shop` | 2 | char | c:arms_dealer Shops always sell at least one weapon / c:baby Shops always sell at least one weapon |
| `more_horde` | 1 | char | c:veteran +2 Horde waves every 10 waves |
| `no_cure_between_wave` | 1 | char | c:veteran HP is not restored between waves |
| `no_duplicate_weapons` | 1 | char | c:vagabond You can't equip two of the same weapon at the same time |
| `no_fruit_attracted_end_of_wave` | 1 | char | c:veteran Fruits are not attracted at the end of waves |
| `no_heal` | 1 | char | c:golem You can��t heal in any way |
| `no_melee_weapons` | 2 | char | c:ranger You can't equip melee weapons / c:renegade You can't equip melee weapons |
| `no_ranged_weapons` | 5 | char | c:gladiator You can't equip ranged weapons / c:knight You can't equip ranged weapons |
| `poisoned_fruit` | 1 | char | c:druid 33% of fruits are poisoned and hurt you (ignores Dodge and A |
| `remove_shop_items` | 1 | char | c:builder You can't have structures |
| `stronger_elites_on_kill` | 1 | char | c:gangster All future elites and bosses become stronger when you kill a |
| `time_shift_on_hit` | 1 | char | c:time_shifter You can shift time when you take damage |
| `weapon_slot_upgrades` | 1 | char | c:baby You gain a weapon slot when you level up instead of a stat u |

### `identity`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `accuracy` | 1 | char | c:renegade -50% Accuracy |
| `boosted_wanted_item_tag` | 1 | char | c:beast_master  |
| `burn_primitive_bonus` | 1 | char | c:caveman Burning weapon gives bonus damage on primitive weapons based |
| `burn_weapon` | 1 | char | c:caveman You can burn your weapons to increase the visibility of the  |
| `convert_bonus_gold` | 1 | char | c:builder Every 5 uncollected materials are converted into 1 % Structu |
| `convert_stats_end_of_wave` | 1 | char | c:demon 50% of your Materials are converted into Max HP at the end o |
| `cursed_starting_item` | 1 | char | c:creature You start with 1 cursed Fish Hook |
| `dual_evolution` | 1 | char | c:mad_scientist Every Evolution change counts as positive and feeds both the |
| `effect_mixing_up_wave` | 1 | char | c:time_shifter Some waves come out of order (the first and final waves neve |
| `enemy_damage` | 1 | char | c:jack +35 % Enemy damage |
| `enemy_gold_drops` | 5 | char | c:explorer -50% materials dropped from enemies / c:cryptid -50% materials dropped from enemies |
| `enemy_health` | 4 | char | c:jack +175 % Enemy health / c:curious +25 % Enemy health |
| `enemy_percent_damage_taken` | 1 | char | c:diver Enemies take 300% more damage for 3 seconds when hit by Rang |
| `enemy_speed` | 2 | char | c:old -25 % Enemy Speed / c:explorer +10 % Enemy Speed |
| `extra_starting_weapon_choices` | 1 | char | c:survivor Choose 1 additional starting weapon |
| `gain_pct_gold_start_wave` | 1 | char | c:entrepreneur -100% of your materials at the start of waves |
| `gain_stat_for_killed_enemies_in_zone` | 1 | char | c:poacher Add 1 hunting area which gives +3% Damage for every 15 enemi |
| `gold_drops` | 4 | char | c:farmer -50% materials dropped / c:streamer -50% materials dropped |
| `hp_shop` | 1 | char | c:demon You buy items using Max HP instead of materials |
| `items_price` | 2 | char | c:entrepreneur -25 % Items Price / c:baby -20 % Items Price |
| `level_upgrades_modifications` | 1 | char | c:captain +100% stats gained from level upgrades |
| `lose_hp_per_second` | 1 | char | c:sick You take 1 damage per second (does not give invulnerability  |
| `materials_as_health` | 1 | char | c:droid Damage taken removes materials instead of HP. You die when y |
| `max_turret_count` | 1 | char | c:builder  |
| `meca_only` | 1 | char | c:droid Can only evolve on the Mecha side |
| `meca_parts_on_level_up` | 1 | char | c:droid +1 mecha part when you level up |
| `mutant_only` | 1 | char | c:variant Can only evolve on the Mutant side |
| `mutation_fruit_chance` | 1 | char | c:mad_scientist  |
| `no_level_upgrades` | 1 | char | c:droid No upgrade when leveling up |
| `number_of_enemies` | 2 | char | c:old -10% Enemies / c:jack -70% Enemies |
| `poacher_zone_materials` | 1 | char | c:poacher -50% materials dropped by enemies killed inside the hunting  |
| `remove_shop_items` | 1 | char | c:gangster  |
| `starting_item` | 14 | char | c:mage You start with 1 Snake / c:mage You start with 1 Scared Sausage |
| `starting_weapon` | 7 | char | c:brawler You start with 1 Fist / c:crazy You start with 1 Knife |
| `stat_curse` | 1 | char | c:sailor +25 Curse |
| `trees_start_wave` | 1 | char | c:explorer  |
| `upgraded_baits` | 1 | char | c:fisherman Baits make some special enemies spawn throughout all future  |
| `weapon_scaling_stats` | 1 | char | c:creature Weapon and pet damage additionally scales with 35% Curse |
| `weapon_set_bonus` | 1 | char | c:one_arm Your weapon has 3 set bonus for its weapon categorie.  |

### `anchored`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `(EFFECT_DINO_EGG_1)` | 1 | item | dino_egg_1 Spawns an egg on the map. Defend it for 1 more wave and it h |
| `(EFFECT_DINO_EGG_2)` | 1 | item | dino_egg_2 Spawns an egg on the map. Defend it for 2 more waves and it  |
| `(EFFECT_DINO_EGG_3)` | 1 | item | dino_egg Spawns an egg on the map. Defend it for 3 more waves and it  |
| `(EFFECT_PET_AMMOSAURUS)` | 1 | item | ammosaurus Spawns an Ammosaurus pet wielding a copy of your best weapon |
| `(EFFECT_SWAP_MAX_MIN_STAT_POS)` | 1 | item | axolotl Your highest (Max HP) and lowest (% Speed) positive primary  |
| `(EFFECT_USED_LIFEFORM_SCANNER)` | 1 | item | used_lifeform_scanner This item has been used to replace an Elite event by a Horde |
| `enemy_evolution_chance` | 2 | item | shaving_foam_can_meca Enemies have more chance to spawn mecha / shaving_foam_can_mutant Enemies have more chance to spawn mutated |
| `fossil_count` | 9 | item | fossil_left_arm  / fossil_right_arm  |
| `gain_stat_for_every:fossil_count` | 8 | item | fossil_left_arm +1 Armor for every fossil item equipped [+0] / fossil_right_arm +1 Max HP for every fossil item equipped [+0] |
| `item_lifeform_scanner` | 1 | item | lifeform_scanner When leaving a shop, the next planned elite event is replace |
| `projectile` | 4 | item | builder_turret_0 +1 projectile when you reach 30 Structure Range [0/30] / builder_turret_1 +1 projectile |
| `projectiles` | 2 | item | builder_turret_2 +2 projectiles / builder_turret_3 +3 projectiles |
| `stat_engineering` | 4 | item | builder_turret_0 This turret's stats are derived from your best ranged weapon / builder_turret_1 This turret's stats are derived from your best ranged weapon |
| `stat_evolution` | 6 | item | meca_evolved_leap Evolution gets multiplied by 2 when equipping / meca_evolved_leap +2 Evolution |

### `text`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `(EFFECT_BROKEN_HOURGLASS)` | 1 | item | broken_hourglass This hourglass broke after resetting the wave counter, also  |
| `(EFFECT_BROKEN_MIRROR)` | 1 | item | broken_mirror This mirror duplicated an item |
| `(EFFECT_GOLDFISH_USED)` | 1 | item | goldfish_used This goldfish is resting after a hard day's work |
| `(EFFECT_LOST_ON_HIT)` | 1 | item | crystal Bonus is lost when taking damage |
| `(EFFECT_WHISTLE_SOUND)` | 1 | item | whistle Whistles when a loot alien spawns |
| `(WOUNDED_ITEMS_EXPLANATION)` | 1 | char | c:wounded Shop items and crates are cleared of items focusing on Max H |

### `excluded`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `fog_visibility` | 5 | item | campfire  / candle  |
| `stat_curse` | 4 | item | black_flag +5 Curse / fish_hook +1 Curse |
| `stat_evolution` | 3 | item | jamming_backpack +5 Evolution / eldritch_figurine -5 Evolution |

### `weapon`

| 效果 key | 次数 | 来源 | 示例 |
| --- | --- | --- | --- |
| `(EFFECT_BOOMERANG_RETURN)` | 4 | weapon | w:boomerang_1 Flies back to you, hitting enemies again on the way back / w:boomerang_2 Flies back to you, hitting enemies again on the way back |
| `(EFFECT_BURNING)` | 4 | weapon | w:carbon_bow_1 Deals 3x3 (+100%[img=15x15]res://items/ / w:carbon_bow_2 Deals 5x5 (+100%[img=15x15]res://items/ |
| `(EFFECT_CARBON_BOW_ENGINEERING)` | 4 | weapon | w:carbon_bow_1 2% chance to drop a landmine dealing 10 (+100%[ / w:carbon_bow_2 3% chance to drop a landmine dealing 10 (+100%[ |
| `(EFFECT_CARBON_BOW_MELEE)` | 4 | weapon | w:carbon_bow_1 Slows the enemy by 50% for 0.5s / w:carbon_bow_2 Slows the enemy by 50% for 1s |
| `(EFFECT_CARBON_BOW_RANDOM_SCALING)` | 4 | weapon | w:carbon_bow_1 Each arrow scales with one of these stats, picked at random: / w:carbon_bow_2 Each arrow scales with one of these stats, picked at random: |
| `(EFFECT_CARBON_BOW_RANGED)` | 4 | weapon | w:carbon_bow_1 +1 piercing / w:carbon_bow_2 +1 piercing |
| `(EFFECT_CRATE_DIG_CHANCE)` | 4 | weapon | w:shovel_1 0.5% chance to dig up a crate when it kills an enemy / w:shovel_2 1% chance to dig up a crate when it kills an enemy |
| `(EFFECT_DEFLECT_PROJECTILES)` | 2 | weapon | w:light_saber_3 Deflects enemy projectiles toward the nearest enemy, dealing / w:light_saber_4 Deflects enemy projectiles toward the nearest enemy, dealing |
| `(EFFECT_ONE_SHOT_ON_HIT_EFFECT)` | 3 | weapon | w:vorpal_sword_2 1% chance to one shot the target when hitting it / w:vorpal_sword_3 2% chance to one shot the target when hitting it |
| `(EFFECT_WEAPON_DOUBLE_DAMAGE_IF_STAT)` | 3 | weapon | w:cestus_2 If your Knockback is +10 or higher, this weapon's base damag / w:cestus_3 If your Knockback is +10 or higher, this weapon's base damag |
| `(effect_dart_trap)` | 4 | weapon | w:awl_1 A dart trap spawns every 12 seconds, firing 6 darts dealing  / w:awl_2 A dart trap spawns every 9 seconds, firing 6 darts dealing 8 |
| `(effect_garden)` | 4 | weapon | w:pruner_1 Spawns a garden that creates a fruit every 15 seconds / w:pruner_2 Spawns a garden that creates a fruit every 14 seconds |
| `(effect_landmines)` | 4 | weapon | w:screwdriver_1 A landmine spawns every 12 seconds dealing 10 ( / w:screwdriver_2 A landmine spawns every 9 seconds dealing 10 (+ |
| `(effect_turret)` | 1 | weapon | w:wrench_1 Spawns a turret that shoots bullets dealing 10 ([color=white |
| `(effect_turret_flame)` | 1 | weapon | w:wrench_2 Spawns a turret that shoots flames dealing 8x5 ([color=white |
| `(effect_turret_laser)` | 1 | weapon | w:wrench_3 Spawns a turret that shoots piercing bullets dealing 20 ([co |
| `(effect_turret_rocket)` | 1 | weapon | w:wrench_4 Spawns a turret that shoots explosive bullets dealing 25 ([c |
| `EFFECT_PROJECTILES_ON_HIT` | 2 | weapon | w:sniper_gun_3 Hitting an enemy spawns 5 projectiles dealing 5 ([color=whit / w:sniper_gun_4 Hitting an enemy spawns 8 projectiles dealing 5 ([color=whit |
| `EFFECT_SLOW_PROJECTILES_ON_HIT` | 2 | weapon | w:thunder_sword_3 Hitting an enemy spawns 2 projectiles that deal 1 ([color=wh / w:thunder_sword_4 Hitting an enemy spawns 4 projectiles that deal 1 ([color=wh |
| `EFFECT_WEAPON_SLOW_ON_HIT` | 2 | weapon | w:particle_accelerator_3 Slows enemies by 1% on hit for every 1 Engineering you have  / w:particle_accelerator_4 Slows enemies by 2% on hit for every 1 Engineering you have  |
| `EFFECT_WEAPON_STACK` | 4 | weapon | w:stick_1 Deals +4 Damage for every additional Stick you have [+0] / w:stick_2 Deals +6 Damage for every additional Stick you have [+0] |
| `additional_weapon_effects` | 1 | weapon | w:excalibur_4 -2 Armor for every weapon you have [+0] |
| `bonus_current_health_damage` | 2 | weapon | w:chainsaw_3 Deals 10% of an enemy��s current health as bonus damage (1% f / w:chainsaw_4 Deals 20% of an enemy��s current health as bonus damage (2% f |
| `bonus_damage_against_targets_above_hp` | 3 | weapon | w:trident_2 +30% damage against targets above 80% health / w:trident_3 +40% damage against targets above 80% health |
| `bonus_damage_against_targets_below_hp` | 4 | weapon | w:sickle_1 +20% damage against targets below 30% health / w:sickle_2 +30% damage against targets below 30% health |
| `bounce_on_crit` | 4 | weapon | w:shuriken_1 Bounces up to 1 times on critical hit / w:shuriken_2 Bounces up to 2 times on critical hit |
| `break_on_hit` | 4 | weapon | w:brick_1 Has a 1% chance to break and drop 10 materials on hit / w:brick_2 Has a 1% chance to break and drop 30 materials on hit |
| `burning_spread` | 2 | weapon | w:torch_3 Burning spreads to an additional nearby enemy / w:torch_4 Burning spreads to an additional nearby enemy |
| `charm_on_hit` | 4 | weapon | w:flute_1 Hitting an enemy that has less than 60% health has a 10% cha / w:flute_2 Hitting an enemy that has less than 65% health has a 15% cha |
| `crit_on_hitting_burning_target` | 4 | weapon | w:spoon_1 Always crits when hitting burning targets / w:spoon_2 Always crits when hitting burning targets |
| `crit_on_whip_tip` | 4 | weapon | w:flail_1 Enemies hit by the tip of the flail are always critically hi / w:flail_2 Enemies hit by the tip of the flail are always critically hi |
| `effect_burning` | 23 | weapon | w:flaming_brass_knuckles_3 Deals 6x15 (+100%[img=15x15]res://items / w:torch_1 Deals 3x3 (+100%[img=15x15]res://items/ |
| `effect_explode` | 16 | weapon | w:rocket_launcher_2 Projectiles explode on hit / w:rocket_launcher_3 Projectiles explode on hit |
| `effect_explode_custom` | 3 | weapon | w:shredder_1 Projectiles have a 50% chance to explode on hit / w:shredder_2 Projectiles have a 65% chance to explode on hit |
| `effect_explode_melee` | 9 | weapon | w:plasma_sledgehammer_3 25% chance to explode on hit / w:plasma_sledgehammer_4 50% chance to explode on hit |
| `effect_lightning_on_hit` | 5 | weapon | w:lightning_shiv_1 Hitting an enemy spawns a lightning projectile that bounces  / w:lightning_shiv_2 Hitting an enemy spawns a lightning projectile that bounces  |
| `effect_no_hit_boost` | 4 | weapon | w:rail_gun_1 Deals +3 Base Damage every 5 seconds until the end of the wa / w:rail_gun_2 Deals +4 Base Damage every 5 seconds until the end of the wa |
| `effect_projectiles_on_hit` | 4 | weapon | w:cacti_club_1 Hitting an enemy spawns 3 projectiles dealing 1 ([color=whit / w:cacti_club_2 Hitting an enemy spawns 4 projectiles dealing 2 ([color=whit |
| `effect_slow_in_zone` | 7 | weapon | w:taser_1 Slows enemies in a radius around the projectile / w:taser_2 Slows enemies in a radius around the projectile |
| `enemy_percent_damage_taken` | 8 | weapon | w:lute_1 Enemies hit take 10% more damage for 3 seconds (max: 30%) / w:lute_2 Enemies hit take 10% more damage for 3 seconds (max: 50%) |
| `fire_puddle_on_hit` | 4 | weapon | w:molotov_1 Creates a pool of fire on impact for 3 seconds, dealing 4x3  / w:molotov_2 Creates a pool of fire on impact for 3.5 seconds, dealing 4x |
| `lose_hp_per_second` | 1 | weapon | w:scythe_4 You take 3 damage per second (does not give invulnerability  |
| `modify_every_x_projectile` | 4 | weapon | w:javelin_1 Every 5th projectile has +100 % Crit Chance / w:javelin_2 Every 4th projectile has +100 % Crit Chance |
| `pierce_on_crit` | 4 | weapon | w:crossbow_1 Pierces up to 1 times on critical hit / w:crossbow_2 Pierces up to 2 times on critical hit |
| `reload_turrets_on_shoot` | 2 | weapon | w:war_hammer_3 Resets the cooldown of all offensive turrets when attacking / w:war_hammer_4 Resets the cooldown of all offensive turrets when attacking |
| `reload_when_pickup_gold` | 3 | weapon | w:blunderbuss_2 Cooldown is reset when you pick up a material / w:blunderbuss_3 Cooldown is reset when you pick up a material |
| `slow_area_on_hit` | 4 | weapon | w:tranq_rifle_1 Hits slow enemies within 125 range by 50% for 2 seconds / w:tranq_rifle_2 Hits slow enemies within 150 range by 50% for 2 seconds |
| `spawn_structure_every_killed_enemies` | 4 | weapon | w:crowbar_1 For every 18 enemies you kill during a wave with this weapon / w:crowbar_2 For every 16 enemies you kill during a wave with this weapon |
| `stat_damage` | 2 | weapon | w:captains_sword_3 Deals +25 Damage for every free weapon slot you have [+150] / w:captains_sword_4 Deals +50 Damage for every free weapon slot you have [+300] |
| `timed_slow_on_hit` | 4 | weapon | w:whip_1 Slows the enemy hit by 50% for 0.5s / w:whip_2 Slows the enemy hit by 50% for 1s |

