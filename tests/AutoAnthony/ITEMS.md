# 默认设置下的全部重组道具

由测试在每次运行结束时自动生成（`test_base.gd` 的 `_write_items_table`）。默认设置：重组道具、重组名称开启，其余选项关闭，平均数值 100%、浮动范围 125%、触发效果 150%，保留原版道具 0%；种子 42。

共 206 件：T1 57、T2 58、T3 56、T4 35。锚定道具（望远镜、诱饵、口袋工厂、美西螈、鱼钩等）保持原版，不在表内。

词条为道具资源的 tags（角色的偏好词条、商店按词条加权抽取都用它），使用原版的词条 ID。

| 稀有度 | 道具 | 价格 | 效果 | 词条 | 备注 |
| --- | --- | --- | --- | --- | --- |
| T1 | 贪吃的异形之舌 | 15 | +2 生命再生<br>捡起消耗品时爆炸，造成相当于250%元素伤害的伤害<br>-7 %攻击速度 | stat_hp_regeneration, consumable, explosive, stat_elemental_damage |  |
| T1 | 律动的异形虫 | 18 | +1 元素伤害<br>+1 远程伤害<br>每15秒将1点属性点随机分配到你的主要属性上（每波最多3次）<br>每1构筑物会-2%速度 [+0] | stat_elemental_damage, stat_ranged_damage |  |
| T1 | 野蛮的象宝宝 | 30 | +4 近战伤害<br>-8 %道具价格<br>-2 远程伤害 | stat_melee_damage, economy |  |
| T1 | 修补匠的壁虎宝宝 | 30 | +3 工程学 | stat_engineering |  |
| T1 | 厚重的背包 | 25 | +2 最大生命值<br>+1 元素伤害<br>-5 幸运 | stat_max_hp, stat_elemental_damage |  |
| T1 | 易爆的蝙蝠 | 25 | +10 %爆炸范围<br>每永久持有12远程伤害会-1%伤害 [+0] | explosive |  |
| T1 | 吸血鬼的无檐小便帽 | 15 | +2 %生命窃取<br>每持有1件IV等级武器有-1近战伤害[+0] | stat_lifesteal |  |
| T1 | 致命沸水 | 25 | +2 %攻击速度<br>以暴击杀死敌人时，对随机1名敌人造成相当于25%近战伤害的伤害 | stat_attack_speed, stat_crit_chance, stat_melee_damage |  |
| T1 | 精巧的书本 | 20 | +6 工程学<br>下场敌袭以1点生命值开始 | stat_engineering |  |
| T1 | 精巧的拳击手套 | 15 | +1 工程学<br>-5 范围 | stat_engineering |  |
| T1 | 狂乱的裂口 | 15 | +2 %攻击速度 | stat_attack_speed |  |
| T1 | 急速蝴蝶 | 25 | +5 %攻击速度<br>-5 %爆炸伤害 | stat_attack_speed |  |
| T1 | 镀层蛋糕 | 20 | +1 护甲<br>每持有1件I等级武器有+2%闪避[+0]<br>-4 %伤害 | stat_armor, stat_dodge |  |
| T1 | 丰收木炭 | 15 | +11 收获<br>-2 %闪避 | stat_harvesting |  |
| T1 | 连发利爪树 | 25 | +8 %攻击速度<br>下场敌袭以1点生命值开始 | stat_attack_speed | 核心 |
| T1 | 收成咖啡 | 20 | +12 收获<br>-20%贯通伤害 | stat_harvesting | 核心 |
| T1 | 锋利的优惠券 | 25 | +16 %伤害<br>-7 %速度 | stat_percent_damage | 核心 |
| T1 | 被眷顾的萌萌猴 | 18 | +9 幸运<br>-2 %伤害 | stat_luck |  |
| T1 | 凶猛的有缺陷的增强剂 | 25 | +4 %伤害<br>生成1台炮塔，造成10（+80%）伤害<br>-1 工程学 | stat_percent_damage, structure |  |
| T1 | 觉醒胶带 | 20 | 敌袭结束时永久获得“+3 %构建物的攻击速度”<br>-5击退 | structure |  |
| T1 | 复仇炸药 | 15 | +1 %闪避<br>受到伤害时+1收获。每波最大值：+1<br>受到伤害时有45%概率-1幸运，直至敌袭结束 | stat_dodge, stat_harvesting |  |
| T1 | 连发肥料 | 15 | +13 %攻击速度<br>-20%贯通伤害 | stat_attack_speed |  |
| T1 | 莫测的鲜肉 | 15 | +5 收获<br>+2击退<br>+1 %闪避<br>-7 %道具价格<br>-1 护甲 | stat_harvesting, knockback, stat_dodge, economy |  |
| T1 | 收成外星绅士 | 20 | +10 %爆炸范围<br>+8 收获<br>-3 %闪避 | explosive, stat_harvesting |  |
| T1 | 古怪的眼镜 | 30 | +2 近战伤害<br>生成1台炮塔，造成10（+80%）伤害<br>受到伤害时有50%概率-1%闪避，直至敌袭结束 | stat_melee_damage, structure |  |
| T1 | 诡异的山羊头骨 | 30 | +9 收获<br>使用枪械类武器时+1贯通<br>受到伤害时-1%攻击速度，直至敌袭结束 | stat_harvesting, stat_ranged_damage |  |
| T1 | 精准软糖狂战士 | 20 | +1 远程伤害<br>站立不动时-8%闪避 | stat_ranged_damage | 核心 |
| T1 | 修补匠的头部创伤 | 20 | +4 工程学<br>-5 %攻击速度 | stat_engineering | 核心 |
| T1 | 野蛮的刺猬 | 8 | +1 近战伤害<br>-1 %攻击速度 | stat_melee_damage |  |
| T1 | 风暴头盔 | 28 | +2 元素伤害<br>+1 生命再生<br>持有每一异种武器+1最大生命值 [+0]<br>-4 %速度 | stat_elemental_damage, stat_hp_regeneration |  |
| T1 | 莫测的注射剂 | 25 | +1 %暴击率<br>+1 远程伤害<br>生成1台炮塔，造成10（+80%）伤害<br>敌袭结束后+1%敌人速度 | stat_crit_chance, stat_ranged_damage, structure |  |
| T1 | 离奇的精神异常 | 30 | 生成更多树木<br>每永久持有12元素伤害会-1生命再生 [+0] | exploration |  |
| T1 | 凶猛的果冻 | 20 | +3 %伤害<br>生命再生的修改减少10% | stat_percent_damage |  |
| T1 | 修补匠的地雷 | 28 | +2 工程学<br>使用虚灵类武器时+50范围<br>-5 范围 | stat_engineering, stat_range |  |
| T1 | 沉重的柠檬水 | 18 | +3 近战伤害<br>下场敌袭期间-12 最大生命值 | stat_melee_damage |  |
| T1 | 炽热的镜片 | 15 | +1 元素伤害<br>敌袭结束后+1%敌人伤害 | stat_elemental_damage | 核心 |
| T1 | 致命搜刮虫虫 | 20 | +10 收获<br>+1 远程伤害<br>以暴击杀死敌人时，+2近战伤害，持续3秒<br>以暴击杀死敌人时，-2元素伤害，持续3秒<br>-3 %生命窃取 | stat_harvesting, stat_ranged_damage, stat_melee_damage, stat_crit_chance |  |
| T1 | 丰饶的失落鸭鸭 | 22 | +14 收获<br>-6 %攻击速度 | stat_harvesting |  |
| T1 | 铁甲伐木工人衬衫 | 25 | +1 护甲<br>移动时-1%速度 | stat_armor |  |
| T1 | 蛮力蘑菇 | 15 | +4 近战伤害<br>-4 %伤害 | stat_melee_damage | 核心 |
| T1 | 锐利的异变 | 15 | +4 %伤害 | stat_percent_damage |  |
| T1 | 急切的和平蜜蜂 | 25 | +3 %伤害<br>敌人在首次被近战伤害命中时，使其额外承受5%伤害，持续3秒<br>每永久持有8元素伤害会-1最大生命值 [+0] | stat_percent_damage, stat_melee_damage |  |
| T1 | 回响的铅笔 | 15 | +1 工程学<br>每永久持有20范围会+1%暴击率 [+0]<br>每永久持有40范围会-1%伤害 [+0] | stat_engineering, stat_crit_chance, stat_range |  |
| T1 | 被眷顾的植物 | 22 | +10 幸运<br>%闪避的修改减少10% | stat_luck |  |
| T1 | 精巧的螺旋桨帽 | 15 | +2 工程学<br>-2 %伤害 | stat_engineering |  |
| T1 | 滋补的鼠斯拉 | 25 | 使用消耗品恢复+1HP<br>-1 %生命窃取 | consumable |  |
| T1 | 睿智的疤痕 | 20 | +33 获得%经验<br>捡起消耗品时有85%概率-5范围，直至敌袭结束 | xp_gain | 核心 |
| T1 | 精准害怕的香肠 | 18 | +1 远程伤害 | stat_ranged_damage |  |
| T1 | 镀层尖头子弹 | 20 | +2 %闪避<br>+2 护甲<br>-1 近战伤害 | stat_dodge, stat_armor |  |
| T1 | 古怪的蛇 | 15 | 生成更多树木 | exploration |  |
| T1 | 疾行的惊恐的洋葱 | 20 | +4 %速度<br>每持有1件IV等级武器有+1护甲[+0]<br>元素伤害的修改减少15% | stat_speed, stat_armor |  |
| T1 | 镀层毒污泥 | 15 | +1 护甲<br>下场敌袭期间+115 获得%经验<br>下场敌袭期间+90 %敌人生命值<br>-1 %速度 | stat_armor, xp_gain |  |
| T1 | 离奇的树木 | 22 | +1 %生命窃取<br>生成更多树木<br>-1 近战伤害 | stat_lifesteal, exploration |  |
| T1 | 嗜血炮塔 | 20 | +1 %生命窃取<br>治疗时有10%概率+1生命再生，直至敌袭结束<br>下场敌袭期间-17 %伤害 | stat_lifesteal, stat_hp_regeneration |  |
| T1 | 精准丑牙 | 25 | +1 远程伤害<br>下场敌袭期间+59 获得%经验 | stat_ranged_damage, xp_gain |  |
| T1 | 坚毅的奇怪的食物 | 20 | +1 护甲 | stat_armor |  |
| T1 | 伸缩的奇怪的幽灵 | 25 | +10 范围<br>受到伤害时+1%敌人伤害，直至敌袭结束。每波最大值：+10 | stat_range |  |
| T2 | 丰饶的酸液 | 45 | +19 收获<br>护甲的修改减少20% | stat_harvesting | 核心 |
| T2 | 奥术异形眼球 | 45 | +2 元素伤害<br>-1 %速度 | stat_elemental_damage |  |
| T2 | 易爆的旗帜 | 40 | +10 %爆炸伤害<br>+1 远程伤害<br>-4 %伤害 | explosive, stat_ranged_damage |  |
| T2 | 致命黑带 | 55 | +6 %暴击率<br>捡起消耗品时有75%概率+1工程学，直至敌袭结束。每波最大值：+15<br>捡起消耗品时有75%概率+2%敌人速度，直至敌袭结束。每波最大值：+30<br>%闪避的修改减少10% | stat_crit_chance, stat_engineering, consumable |  |
| T2 | 厚重的焰蜥蜴 | 65 | +5 最大生命值<br>生成1台燃烧炮塔，造成8x5（+33%）燃烧伤害<br>下场敌袭期间+25 %敌人速度 | stat_max_hp, structure |  |
| T2 | 奥术眼罩 | 45 | +7 元素伤害<br>闪避时+3%敌人速度，直至敌袭结束 | stat_elemental_damage, stat_dodge | 核心 |
| T2 | 走运的血蛭 | 40 | +13 %攻击速度<br>+27 幸运<br>-16 %伤害 | stat_attack_speed, stat_luck |  |
| T2 | 机械Bonk狗 | 50 | +7 工程学<br>-6 %闪避 | stat_engineering | 核心 |
| T2 | 轻盈布雷机器人 | 40 | +1 %生命窃取<br>闪避时恢复4点生命值 | stat_lifesteal, stat_dodge |  |
| T2 | 囤积的篝火 | 40 | 每拾取7个材料，爆炸，造成相当于25%收获的伤害<br>杀死敌人时有20%概率+1%敌人生命值，直至敌袭结束 | explosive, pickup, stat_harvesting |  |
| T2 | 蛮力猫特林机枪 | 55 | +7 近战伤害<br>下场敌袭一开始会出现特殊敌人 | stat_melee_damage | 核心 |
| T2 | 离奇的芹菜茶 | 55 | +3 %伤害<br>+5击退<br>+1 护甲<br>生成一个花园，每15秒可以结下一种水果<br>每永久持有3%速度会-5范围 [-8] | stat_percent_damage, knockback, stat_armor, consumable, structure |  |
| T2 | 古怪的机械黄蜂 | 50 | +1 远程伤害<br>商店免费刷新+1次<br>-3 %闪避 | stat_ranged_damage, economy |  |
| T2 | 扎根齿轮 | 40 | +16 获得%经验<br>站立不动时，每持有一异种I级别物品有+1元素伤害[+0]<br>下场敌袭一开始会出现特殊敌人 | xp_gain, stand_still, stat_elemental_damage |  |
| T2 | 异想天开的指南针 | 35 | +1 工程学<br>+4 %暴击率<br>使用元素类武器时+20%暴击率<br>每持有一异种IV级别物品有-3%速度[+0] | stat_engineering, stat_crit_chance |  |
| T2 | 沉静的赛博球 | 40 | +15 范围<br>站立不动时+19%速度<br>每6秒-1%攻击速度，直至敌袭结束。每波最大值：-15 | stat_range, stat_speed, stand_still |  |
| T2 | 回响的独眼虫 | 35 | +1 护甲<br>每损失12%生命值，有+1最大生命值[+2] | stat_armor, stat_max_hp |  |
| T2 | 常青的危险的兔子 | 60 | +13 生命再生<br>-2 护甲 | stat_hp_regeneration |  |
| T2 | 复仇腐肉 | 35 | +3 %生命窃取<br>受到伤害时恢复4点生命值<br>受到伤害时有65%概率-1元素伤害，直至敌袭结束 | stat_lifesteal |  |
| T2 | 破晓蛾医生 | 55 | +10 范围<br>敌袭开始时获得25个材料 | stat_range, economy |  |
| T2 | 幻影能量手环 | 30 | +2 %闪避<br>每12元素伤害会+1最大生命值 [+0]<br>-1 近战伤害 | stat_dodge, stat_max_hp, stat_elemental_damage |  |
| T2 | 适时的眼部手术 | 40 | 敌袭进行到一半时对随机1名敌人造成相当于400%范围的伤害 | stat_range |  |
| T2 | 锐利的果篮 | 40 | +2 工程学<br>用元素伤害杀死敌人时，有35%概率爆炸，造成相当于75%生命再生的伤害<br>-2 元素伤害 | stat_engineering, explosive, stat_elemental_damage, stat_hp_regeneration |  |
| T2 | 远古燃料箱 | 55 | +1 远程伤害<br>+1 元素伤害<br>生成1台燃烧炮塔，造成8x5（+33%）燃烧伤害<br>-3 %速度 | stat_ranged_damage, stat_elemental_damage, structure |  |
| T2 | 丰饶的赌博筹码 | 50 | +16 收获<br>敌袭结束时+1近战伤害 | stat_harvesting, stat_melee_damage |  |
| T2 | 离奇的花园 | 55 | +2 元素伤害<br>生成一只猫特林机枪宠物，发射子弹造成10（+60%）伤害。当与玩家或其他宠物接近时，攻速会上升 | stat_elemental_damage, pet |  |
| T2 | 镀层冰块 | 55 | +5 护甲<br>+2 生命再生<br>-10 %速度 | stat_armor, stat_hp_regeneration |  |
| T2 | 觉醒皮革背心 | 60 | +4 %生命窃取<br>移动时燃烧速度提高30%<br>-3 护甲 | stat_lifesteal, stat_elemental_damage |  |
| T2 | 远古小青蛙 | 35 | 使用重型类武器时+10%攻击速度 | stat_attack_speed |  |
| T2 | 回响的肌肉小子 | 40 | +5 范围<br>每1%速度会+1%攻击速度 [+5] | stat_range, stat_attack_speed, stat_speed |  |
| T2 | 锐利的鱼饵  | 45 | +13 %伤害<br>-3 %闪避 | stat_percent_damage | 核心 |
| T2 | 离奇的精湛技艺 | 35 | +2 近战伤害<br>使用重型类武器时+35%攻击速度<br>-7 %速度 | stat_melee_damage, stat_attack_speed |  |
| T2 | 奇异的勋章 | 50 | 生成1台燃烧炮塔，造成8x5（+33%）燃烧伤害<br>-1 远程伤害 | structure |  |
| T2 | 致命金属探测器 | 55 | +18 %暴击率 | stat_crit_chance |  |
| T2 | 炽热的金属板 | 60 | +3 元素伤害<br>下场敌袭期间+120 获得%经验<br>下场敌袭期间-14 最大生命值 | stat_elemental_damage, xp_gain |  |
| T2 | 修补匠的导弹 | 40 | +8 工程学 | stat_engineering |  |
| T2 | 掠食者的护垫 | 55 | +6 %闪避<br>命中生命值高于50%的敌人时，有15%概率使其燃烧，造成3x1（+100%元素伤害）的燃烧伤害<br>下场敌袭一开始会出现特殊敌人 | stat_dodge, stat_elemental_damage |  |
| T2 | 结实的猪猪存钱罐 | 30 | +5 最大生命值<br>处于最大生命值时，每20%生命窃取会+5护甲 [+0]<br>-1 护甲 | stat_max_hp, stat_lifesteal, stat_armor |  |
| T2 | 睿智的一堆书 | 50 | +64 获得%经验<br>-7 最大生命值 | xp_gain | 核心 |
| T2 | 共鸣南瓜 | 48 | +3 %暴击率<br>目前每一棵存活的树木有+1生命再生[+0]<br>-5% 敌人 | stat_crit_chance, stat_hp_regeneration, less_enemies |  |
| T2 | 嗜血回收装置 | 40 | +2 %生命窃取<br>+2 生命再生<br>下场敌袭期间+60 获得%经验<br>下场敌袭期间+50 %敌人生命值<br>捡起消耗品时-1%攻击速度，直至敌袭结束。每波最大值：-30 | stat_lifesteal, stat_hp_regeneration, xp_gain |  |
| T2 | 幸运强化钢 | 50 | +20 幸运<br>治疗时有35%概率爆炸，造成相当于100%最大生命值的伤害<br>使用消耗品恢复-3HP | stat_luck, explosive, stat_max_hp |  |
| T2 | 骄傲的反击 | 45 | +2 工程学<br>+2 最大生命值<br>处于最大生命值时+40范围 | stat_engineering, stat_max_hp, stat_range |  |
| T2 | 致命仪式 | 45 | +13 %暴击率<br>命中生命值低于50%的敌人时，有35%概率使其燃烧，造成3x1（+100%元素伤害）的燃烧伤害<br>下场敌袭期间-14 最大生命值 | stat_crit_chance, stat_elemental_damage |  |
| T2 | 急速瞄准镜 | 55 | +20 %攻击速度<br>-4 近战伤害 | stat_attack_speed | 核心 |
| T2 | 离奇的阴影药水 | 60 | +7 %伤害<br>生成一个花园，每15秒可以结下一种水果 | stat_percent_damage, consumable, structure |  |
| T2 | 炽热的小型弹匣 | 60 | +10 %爆炸范围<br>每点燃6个敌人，+5范围。每波最大值：+10 | explosive, stat_range, stat_elemental_damage |  |
| T2 | 轻风蜗牛 | 40 | +8 %速度<br>受到伤害时恢复3点生命值<br>-2 护甲 | stat_speed |  |
| T2 | 处决雪球 | 35 | +3 生命再生<br>每以暴击杀死5个敌人，永久获得“对头目和精英怪造成+1%伤害”（每波最多5次） | stat_hp_regeneration, stat_crit_chance, stat_percent_damage |  |
| T2 | 离奇的辣酱 | 60 | 生成1台医疗炮塔，恢复3（+5%）生命值 | structure |  |
| T2 | 处决墨镜 | 40 | 以暴击杀死敌人时，有20%概率+1%暴击率，直至敌袭结束<br>-2 %伤害 | stat_crit_chance |  |
| T2 | 吸血鬼的触手 | 45 | +4 %生命窃取<br>升级时，每永久持有12最大生命值会+5收获 [+6]，直至敌袭结束<br>捡起消耗品时-1生命再生，直至敌袭结束 | stat_lifesteal, stat_max_hp, stat_harvesting |  |
| T2 | 精准燃烧炮塔 | 50 | +2 远程伤害<br>+2 元素伤害<br>敌袭结束时+1%攻击速度<br>敌袭结束时-1%伤害<br>-7击退 | stat_ranged_damage, stat_elemental_damage, stat_attack_speed |  |
| T2 | 离奇的医疗炮塔 | 60 | +2 生命再生<br>+1 最大生命值<br>商店免费刷新+2次 | stat_hp_regeneration, stat_max_hp, economy |  |
| T2 | 闪身的泰勒 | 55 | +4 收获<br>+4 %闪避<br>闪避时爆炸，造成相当于300%近战伤害的伤害<br>-8 %伤害 | stat_harvesting, stat_dodge, explosive, stat_melee_damage |  |
| T2 | 增幅独轮车 | 45 | +6 %伤害<br>工程学的修改增加20%<br>-6 %暴击率 | stat_percent_damage, stat_engineering |  |
| T2 | 精准磨刀石 | 55 | +5 远程伤害<br>-7击退 | stat_ranged_damage | 核心 |
| T2 | 丰满的白旗 | 65 | 使用消耗品恢复+2HP<br>+4 最大生命值<br>移动时-4工程学 | consumable, stat_max_hp |  |
| T3 | 受祝福的肾上腺素 | 75 | +5 %伤害<br>+2 %生命窃取<br>治疗时爆炸，造成相当于100%幸运的伤害<br>每波敌袭有10%几率额外生成一个精英 | stat_percent_damage, stat_lifesteal, explosive, stat_luck |  |
| T3 | 炽热的幼年异形 | 75 | +7 元素伤害<br>敌袭结束后+5%敌人生命值 | stat_elemental_damage |  |
| T3 | 神秘的外星魔法 | 80 | 生成一个水母盾宠物，环绕玩家移动。可以阻挡投射物<br>-4 %攻击速度 | pet |  |
| T3 | 远古合金 | 75 | +6 %速度<br>+3 生命再生<br>使用徒手类武器时+200％暴击伤害 | stat_speed, stat_hp_regeneration, stat_crit_chance |  |
| T3 | 锋利的长胡子的婴儿 | 50 | +18 %伤害<br>捡起消耗品时对随机1名敌人造成相当于150%范围的伤害<br>燃烧速度降低100% | stat_percent_damage, consumable, stat_range |  |
| T3 | 增幅链球 | 80 | +1 %生命窃取<br>+2 生命再生<br>+3 最大生命值<br>最大生命值的修改增加25%<br>每持有一异种I级别物品有-1%速度[+0] | stat_lifesteal, stat_hp_regeneration, stat_max_hp |  |
| T3 | 走运的头巾 | 70 | +25 幸运<br>武器和宠物伤害会受到10%元素伤害影响<br>敌袭结束后+5%敌人生命值 | stat_luck, stat_elemental_damage |  |
| T3 | 铁甲路障 | 55 | +2 护甲<br>+2 工程学<br>捡起消耗品时+1击退。每波最大值：+10<br>捡起消耗品时-5范围，直至敌袭结束 | stat_armor, stat_engineering, knockback, consumable |  |
| T3 | 风暴豆老师 | 60 | +8 元素伤害<br>每杀死5个敌人，+1%伤害。每波最大值：+9<br>每杀死5个敌人，+1%敌人速度。每波最大值：+9<br>敌袭结束后+5%敌人伤害 | stat_elemental_damage, stat_percent_damage |  |
| T3 | 凶猛的献血 | 65 | +23 %伤害<br>武器和宠物伤害会受到10%元素伤害影响<br>-6 %暴击率 | stat_percent_damage, stat_elemental_damage |  |
| T3 | 生机圆顶礼帽 | 85 | +5 生命再生<br>每持有1件I等级武器有+2护甲[+0] | stat_hp_regeneration, stat_armor |  |
| T3 | 远古蜡烛 | 85 | +3 工程学<br>生成1个小型机器人，使周围敌人减速<br>燃烧速度降低100% | stat_engineering, less_enemy_speed, structure, pet |  |
| T3 | 狂乱的糖果袋 | 70 | +17 %攻击速度<br>每杀死2个敌人，+1%敌人伤害，直至敌袭结束。每波最大值：+15 | stat_attack_speed | 核心 |
| T3 | 古怪的变色龙 | 50 | +1 %生命窃取<br>使用原始类武器时+10%暴击率<br>移动时-1最大生命值 | stat_lifesteal, stat_crit_chance |  |
| T3 | 古怪的三叶草 | 60 | +1 %闪避<br>使用枪械类武器时+2贯通<br>敌袭结束后+5%敌人生命值 | stat_dodge, stat_ranged_damage |  |
| T3 | 生机线圈 | 60 | +13 生命再生<br>敌袭开始时获得60经验<br>-5 %生命窃取 | stat_hp_regeneration, xp_gain |  |
| T3 | 风暴社区支持 | 70 | +4 元素伤害<br>生命值低于50%时+13工程学<br>生命值低于50%时-24%伤害<br>闪避时-1%伤害，直至敌袭结束 | stat_elemental_damage, stat_engineering |  |
| T3 | 吸血鬼的王冠 | 75 | +5 %生命窃取<br>每6秒爆炸，造成相当于225%生命再生的伤害<br>-2 生命再生 | stat_lifesteal, explosive, stat_hp_regeneration |  |
| T3 | 生机小精灵 | 75 | +10 生命再生<br>每杀死3个敌人，获得1个材料<br>+10 %敌人生命值 | stat_hp_regeneration, economy |  |
| T3 | 猎杀鳍 | 75 | +14 幸运<br>杀死敌人时爆炸，造成相当于25%元素伤害的伤害 | stat_luck, explosive, stat_elemental_damage |  |
| T3 | 丰饶的炒饭 | 80 | +17 收获<br>-2 近战伤害 | stat_harvesting | 核心 |
| T3 | 回响的冰冻的心 | 75 | +1 远程伤害<br>目前每一棵存活的树木有+4近战伤害[+0]<br>-30 范围 | stat_ranged_damage, stat_melee_damage |  |
| T3 | 复仇幽灵服 | 55 | +2 元素伤害<br>受到伤害时爆炸，造成相当于75%最大生命值的伤害<br>以-50%生命值开始敌袭 | stat_elemental_damage, explosive, stat_max_hp |  |
| T3 | 结实的玻璃大炮 | 92 | +5 生命再生<br>+8 最大生命值<br>敌袭结束时获得30个材料<br>-5 元素伤害 | stat_hp_regeneration, stat_max_hp, economy |  |
| T3 | 充能的手铐 | 65 | +2 近战伤害<br>受到伤害时工程学的修改增加5%，直至敌袭结束<br>-6 %暴击率 | stat_melee_damage, stat_engineering |  |
| T3 | 蛮力蜂蜜 | 70 | +16 近战伤害<br>使用枪械类武器时+2贯通<br>杀死敌人时-1%生命窃取，直至敌袭结束。每波最大值：-10 | stat_melee_damage, stat_ranged_damage |  |
| T3 | 共鸣狩猎战利品 | 70 | +2 工程学<br>+4 %攻击速度<br>每持有1件I等级武器有+4%速度[+0]<br>-10% 敌人 | stat_engineering, stat_attack_speed, stat_speed, less_enemies |  |
| T3 | 猎杀改进工具 | 70 | +6 %暴击率<br>+3 元素伤害<br>每杀死5个敌人，获得1个材料<br>+10 %敌人生命值 | stat_crit_chance, stat_elemental_damage, economy |  |
| T3 | 生机水母盾 | 75 | +9 生命再生<br>站立不动时+13%生命窃取<br>每持有一异种IV级别物品有+5最大生命值[+0]<br>-13 %速度 | stat_hp_regeneration, stat_lifesteal, stand_still, stat_max_hp |  |
| T3 | 丰饶的护身符 | 100 | +50 收获<br>+15 幸运<br>燃烧速度降低100% | stat_harvesting, stat_luck |  |
| T3 | 精准老鼠 | 80 | +9 远程伤害<br>-5 生命再生 | stat_ranged_damage | 核心 |
| T3 | 共鸣钉子 | 70 | +9 收获<br>每永久持有6收获会+3%伤害 [+4] | stat_harvesting, stat_percent_damage | 限制 (3)，成长型 |
| T3 | 愈合的孔雀 | 75 | +5 %伤害<br>+1 护甲<br>+4 生命再生<br>下场敌袭期间+65 获得%经验<br>下场敌袭期间+10 %敌人速度<br>-7 收获 | stat_percent_damage, stat_armor, stat_hp_regeneration, xp_gain |  |
| T3 | 锐利的塑性炸药 | 80 | +28 %伤害<br>-7 最大生命值 | stat_percent_damage | 核心 |
| T3 | 异想天开的毒性补品 | 50 | 使用辅助类武器时+10伤害<br>每200材料会-1元素伤害 [+0] | （无） |  |
| T3 | 成长发电机 | 75 | +1 远程伤害<br>升级时+5击退<br>每2%速度会-1%暴击率 [-2] | stat_ranged_damage, knockback |  |
| T3 | 好学的狂怒 | 85 | +65 获得%经验<br>燃烧速度降低100% | xp_gain | 核心 |
| T3 | 修补匠的悲伤的番茄 | 70 | +13 工程学<br>-10 %攻击速度 | stat_engineering | 核心 |
| T3 | 贪婪的镣铐 | 85 | +2 远程伤害<br>每拾取12个材料，+1近战伤害。每波最大值：+4<br>每永久持有10范围会-1%攻击速度 [+0] | stat_ranged_damage, stat_melee_damage, pickup |  |
| T3 | 回响的休穆糖 | 60 | +2 元素伤害<br>+3 近战伤害<br>持有每一异种武器+5%伤害 [+0]<br>每6最大生命值会-1%伤害 [-2] | stat_elemental_damage, stat_melee_damage, stat_percent_damage |  |
| T3 | 走运的银质子弹 | 70 | +20 幸运<br>敌袭结束时获得18个材料<br>-3 远程伤害 | stat_luck, economy |  |
| T3 | 风暴雕像 | 80 | +7 元素伤害<br>-25 范围 | stat_elemental_damage | 核心 |
| T3 | 厚重的石头皮肤 | 60 | +6 最大生命值<br>下场敌袭期间+15 %敌人速度 | stat_max_hp |  |
| T3 | 风暴奇怪之书 | 60 | +3 元素伤害<br>刷新商店时永久获得“生命再生的修改增加5%”（每波最多3次） | stat_elemental_damage, stat_hp_regeneration |  |
| T3 | 急切的水熊虫 | 75 | 在下场敌袭中会出现4个额外的战利品外星人<br>下场敌袭期间+100 %敌人生命值 | economy |  |
| T3 | 黄昏工具箱 | 65 | +12 幸运<br>+3 生命再生<br>敌袭结束时获得23个材料 | stat_luck, stat_hp_regeneration, economy |  |
| T3 | 蛮力拖拉机 | 75 | +11 近战伤害<br>每3秒+2%敌人生命值，直至敌袭结束。每波最大值：+60 | stat_melee_damage | 核心 |
| T3 | 共鸣三角之力 | 70 | +9 幸运<br>每1%生命窃取会+4击退 [+0]<br>每1%速度会-1%伤害 [-5] | stat_luck, knockback, stat_lifesteal |  |
| T3 | 锐利的激光炮塔 | 70 | +11 %伤害<br>敌袭开始时+1%闪避<br>敌袭开始时+1%敌人速度<br>每100材料会-1护甲 [+0] | stat_percent_damage, stat_dodge |  |
| T3 | 丰满的义警戒指 | 80 | +9 最大生命值<br>每次获得一个提升远程伤害的道具时，+1远程伤害<br>下场敌袭期间+50 %敌人速度 | stat_max_hp, stat_ranged_damage |  |
| T3 | 幸运流浪机器人 | 75 | +23 幸运<br>武器的攻击间隔最小为 0.75 秒<br>-8 %暴击率 | stat_luck | 独特 |
| T3 | 奥术士兵头盔 | 75 | +5 元素伤害<br>站立不动时，每150材料会+5近战伤害 [+1]<br>捡起消耗品时-4幸运，直至敌袭结束。每波最大值：-80 | stat_elemental_damage, stand_still, economy, stat_melee_damage |  |
| T3 | 莫测的小麦 | 50 | +1 元素伤害<br>生成1个小型机器人，使周围敌人减速<br>每60材料会-1生命再生 [+0] | stat_elemental_damage, less_enemy_speed, structure, pet |  |
| T3 | 结实的鬼火 | 70 | +6 最大生命值<br>移动时+7生命再生<br>闪避时+5%敌人伤害，直至敌袭结束 | stat_max_hp, stat_hp_regeneration, stat_dodge |  |
| T3 | 回响的翅膀 | 80 | +1 护甲<br>每永久持有1护甲会+3%攻击速度 [+0] | stat_armor, stat_attack_speed | 独特，成长型 |
| T3 | 回响的智慧 | 75 | +1 护甲<br>+1 %生命窃取<br>每持有一异种IV级别物品有+3%速度[+0] | stat_armor, stat_lifesteal, stat_speed |  |
| T4 | 风暴铁砧 | 100 | +10 元素伤害<br>站立不动时最大生命值的修改增加50%<br>-5 近战伤害 | stat_elemental_damage, stand_still, stat_max_hp |  |
| T4 | 修补匠的巨臂 | 100 | +10 工程学<br>下场敌袭以1点生命值开始 | stat_engineering |  |
| T4 | 共鸣血淋淋的手 | 100 | +5 最大生命值<br>+3 %速度<br>每2%速度会+1生命再生 [+2]<br>闪避时-2护甲，直至敌袭结束 | stat_max_hp, stat_speed, stat_hp_regeneration |  |
| T4 | 铁甲斗篷 | 100 | +4 护甲<br>+1 生命再生<br>每杀死12个敌人，+1%速度。每波最大值：+4 | stat_armor, stat_hp_regeneration, stat_speed |  |
| T4 | 离奇的执照 | 100 | +4 %速度<br>每秒回复8生命值，但无法通过其他途径恢复生命值。 | stat_speed |  |
| T4 | 远视的Esty的沙发 | 105 | +60 范围<br>每持有1件武器+1工程学 [+0]<br>受到伤害时-5幸运，直至敌袭结束 | stat_range, stat_engineering |  |
| T4 | 生机吞吞怪之帽 | 105 | +10 生命再生<br>每12秒恢复6点生命值<br>-10 %攻击速度 | stat_hp_regeneration |  |
| T4 | 共鸣外骨骼 | 110 | +17 %闪避<br>每永久持有1%伤害会+1最大生命值 [+0]<br>-25 %速度 | stat_dodge, stat_max_hp, stat_percent_damage |  |
| T4 | 好学的爆裂弹 | 100 | +51 获得%经验<br>持有每一异种武器-3%攻击速度 [+0] | xp_gain |  |
| T4 | 精炼的另一个胃 | 110 | +6 近战伤害<br>+3 远程伤害<br>+2 护甲<br>+6 %暴击率<br>+10 %爆炸伤害<br>+7击退<br>+13 %伤害<br>+2 元素伤害<br>+15 范围<br>+1 %生命窃取<br>远程伤害的修改增加50%<br>%伤害的修改减少50% | stat_melee_damage, stat_ranged_damage, stat_armor, stat_crit_chance, explosive, knockback, stat_percent_damage, stat_elemental_damage, stat_range, stat_lifesteal |  |
| T4 | 回响的焦点 | 100 | +19 %速度<br>+2 工程学<br>每持有1件武器+2护甲 [+0]<br>下场敌袭以1点生命值开始 | stat_speed, stat_engineering, stat_armor |  |
| T4 | 生机巨型带 | 80 | +5 生命再生<br>+2 护甲 | stat_hp_regeneration, stat_armor |  |
| T4 | 囤积的地精 | 110 | +3 元素伤害<br>+1 护甲<br>+1 %暴击率<br>每拾取7个材料，+1%攻击速度。每波最大值：+7<br>捡起消耗品时-2%速度，直至敌袭结束 | stat_elemental_damage, stat_armor, stat_crit_chance, stat_attack_speed, pickup |  |
| T4 | 常青的希腊火 | 110 | +11 %速度<br>+9 生命再生<br>+16 %伤害<br>持有每一异种武器-3%攻击速度 [+0]<br>每杀死5个敌人，-1工程学，直至敌袭结束 | stat_speed, stat_hp_regeneration, stat_percent_damage |  |
| T4 | 急切的Grind的魔法绿叶 | 100 | +10 最大生命值<br>命中生命值高于50%的敌人时，有50%概率获得1个材料<br>-21 %速度 | stat_max_hp, economy |  |
| T4 | 幸运重型子弹 | 120 | +38 幸运<br>+5 护甲<br>+10 最大生命值<br>-31 %伤害 | stat_luck, stat_armor, stat_max_hp |  |
| T4 | 铁甲沙漏 | 110 | +2 最大生命值<br>+3 护甲<br>持有每一异种武器-3%攻击速度 [+0] | stat_max_hp, stat_armor |  |
| T4 | 共鸣喷气背包 | 105 | +19 %伤害<br>目前每一个燃烧的敌人有+4%伤害[+4]<br>每秒受到1伤害（不给予无敌时间） | stat_percent_damage, stat_elemental_damage |  |
| T4 | 离奇的幸运硬币 | 90 | +5 %速度<br>+10 %爆炸伤害<br>+1 武器栏<br>-5 近战伤害 | stat_speed, explosive |  |
| T4 | 共鸣猛犸 | 100 | +9 %暴击率<br>每永久持有3%暴击率会+4%伤害 [+0]<br>杀死敌人时-1%攻击速度，直至敌袭结束。每波最大值：-30 | stat_crit_chance, stat_percent_damage | 限制 (2)，成长型 |
| T4 | 远古急救包 | 100 | +4 近战伤害<br>+4 元素伤害<br>+3 生命再生<br>+4 最大生命值<br>使用中世纪类武器时+200％暴击伤害<br>-75 范围 | stat_melee_damage, stat_elemental_damage, stat_hp_regeneration, stat_max_hp, stat_crit_chance |  |
| T4 | 常青的夜视镜 | 100 | +13 生命再生<br>+7 %生命窃取<br>-26 %伤害 | stat_hp_regeneration, stat_lifesteal |  |
| T4 | 修补匠的章鱼 | 110 | +13 工程学<br>+5 远程伤害<br>%速度的修改增加50% | stat_engineering, stat_ranged_damage, stat_speed |  |
| T4 | 炽热的熊猫 | 90 | +5 生命再生<br>点燃敌人时造成敌人当前生命值的6%以作为奖励伤害（头目和精英怪的0.6%） | stat_hp_regeneration, stat_elemental_damage, stat_percent_damage |  |
| T4 | 睿智的土豆 | 100 | +63 获得%经验<br>+7击退<br>+4 远程伤害<br>工程学的修改增加50%<br>-60 范围 | xp_gain, knockback, stat_ranged_damage, stat_engineering |  |
| T4 | 炽热的再生药水 | 100 | +3 最大生命值<br>+3 护甲<br>每杀死2个燃烧的敌人，掉落1个水果<br>每2%暴击率会-1%速度 [+0] | stat_max_hp, stat_armor, stat_elemental_damage, consumable |  |
| T4 | 充能的Retromation的连帽衫 | 105 | +8 工程学<br>捡起消耗品时，每永久持有30范围会+2%暴击率 [+0]，直至敌袭结束<br>每持有1件武器-2%伤害 [+0] | stat_engineering, consumable, stat_range, stat_crit_chance |  |
| T4 | 鹰眼跳弹 | 110 | +10 远程伤害<br>+21 %伤害<br>下场敌袭期间+65 获得%经验<br>下场敌袭期间+35 %敌人伤害<br>-25 %速度 | stat_ranged_damage, stat_percent_damage, xp_gain |  |
| T4 | 处决机械臂 | 110 | +63 获得%经验<br>+15 范围<br>+7 幸运<br>以暴击杀死敌人时，获得1个材料<br>-7 最大生命值 | xp_gain, stat_range, stat_luck, economy, stat_crit_chance |  |
| T4 | 回响的替罪羔羊 | 100 | 每永久持有8最大生命值会+3%伤害 [+5]<br>-7击退 | stat_percent_damage, stat_max_hp | 独特，成长型 |
| T4 | 丰满的Sifd的圣物 | 100 | +13 最大生命值<br>闪避时获得30经验<br>-10 %伤害 | stat_max_hp, stat_dodge, xp_gain |  |
| T4 | 铁甲蜘蛛 | 90 | +5 护甲<br>+2 %生命窃取<br>刷新商店时+1%速度。每波最大值：+6 | stat_armor, stat_lifesteal, stat_speed |  |
| T4 | 古怪的拷问 | 100 | 生成1台发射爆破弹的炮塔，造成25（+150%）范围伤害<br>-4 远程伤害 | structure |  |
| T4 | 耐心的爆炸炮塔 | 100 | +9 %闪避<br>敌袭结束时+3%速度<br>下场敌袭以1点生命值开始 | stat_dodge, stat_speed |  |
| T4 | 回响的野狼头盔 | 110 | +3 护甲<br>每永久持有1护甲会+2最大生命值 [+0]<br>杀死敌人时-2幸运，直至敌袭结束。每波最大值：-30 | stat_armor, stat_max_hp | 独特，成长型 |
