# 默认设置下的全部重组道具

由测试在每次运行结束时自动生成（`test_base.gd` 的 `_write_items_table`）。默认设置：重组道具、重组名称开启，其余选项关闭，平均数值 100%、浮动范围 125%、触发效果 150%，保留原版道具 0%；种子 42。

共 234 件：T1 62、T2 67、T3 66、T4 39。锚定道具（望远镜、诱饵、口袋工厂、美西螈、鱼钩等）保持原版，不在表内。

词条为道具资源的 tags（角色的偏好词条、商店按词条加权抽取都用它），使用原版的词条 ID。

| 稀有度 | 道具 | 价格 | 效果 | 词条 | 备注 |
| --- | --- | --- | --- | --- | --- |
| T1 | 致命异形之舌 | 25 | +4 生命再生<br>每击杀4个被诅咒的敌人，+1最大生命值。每波最大值：+2<br>-10 %攻击速度<br>+5 诅咒 | stat_hp_regeneration, stat_max_hp, stat_curse |  |
| T1 | 律动的异形虫 | 25 | +3 元素伤害<br>每15秒将1点属性点随机分配到你的主要属性上（每波最多4次）<br>每1构筑物会-3%速度 [+0] | stat_elemental_damage |  |
| T1 | 野蛮的象宝宝 | 25 | +5 近战伤害<br>树木能被一击毙命<br>-2 远程伤害 | stat_melee_damage, exploration | 独特 |
| T1 | 修补匠的壁虎宝宝 | 28 | +3 工程学 | stat_engineering |  |
| T1 | 厚重的背包 | 18 | +2 最大生命值<br>-3 幸运 | stat_max_hp |  |
| T1 | 易爆的蝙蝠 | 15 | +5 %爆炸范围<br>每永久持有20远程伤害会-1%伤害 [+0] | explosive |  |
| T1 | 吸血鬼的无檐小便帽 | 30 | +4 %生命窃取<br>每持有1件IV等级武器有-5%伤害[+0] | stat_lifesteal |  |
| T1 | 处决沸水 | 25 | 每以暴击杀死7个敌人，获得3经验 | stat_crit_chance, xp_gain |  |
| T1 | 精巧的书本 | 30 | +8 工程学<br>下场敌袭以1点生命值开始 | stat_engineering |  |
| T1 | 坚毅的拳击手套 | 30 | +1 工程学<br>+1 护甲<br>-5 范围 | stat_engineering, stat_armor |  |
| T1 | 狂乱的裂口 | 25 | +3 %攻击速度 | stat_attack_speed |  |
| T1 | 急速蝴蝶 | 30 | +5 %攻击速度<br>-4击退 | stat_attack_speed |  |
| T1 | 共鸣蛋糕 | 18 | 每持有1件I等级武器有+2%闪避[+0]<br>-4 %伤害 | stat_dodge |  |
| T1 | 丰收木炭 | 18 | +13 收获<br>-2 %闪避 | stat_harvesting |  |
| T1 | 愈合的利爪树 | 8 | +1 生命再生<br>-1 %暴击率 | stat_hp_regeneration |  |
| T1 | 锋利的咖啡 | 25 | +5 %伤害<br>树木能被一击毙命<br>-3 最大生命值 | stat_percent_damage, exploration | 独特 |
| T1 | 厚重的被腐蚀的碎片 | 20 | +4 最大生命值<br>+1 诅咒<br>-3 %闪避 | stat_max_hp, stat_curse |  |
| T1 | 机械优惠券 | 30 | +9 工程学<br>站立不动时-13%闪避 | stat_engineering |  |
| T1 | 急速萌萌猴 | 20 | +7 %攻击速度<br>-4 %伤害 | stat_attack_speed | 核心 |
| T1 | 收成有缺陷的增强剂 | 20 | +11 收获<br>-2 %伤害 | stat_harvesting | 核心 |
| T1 | 锋利的胶带 | 12 | +4 %伤害<br>每受到3次伤害，-1%暴击率，直至敌袭结束 | stat_percent_damage | 核心 |
| T1 | 复仇炸药 | 15 | +1 %闪避<br>受到伤害时+1收获。每波最大值：+1<br>受到伤害时有20%概率-1%速度，直至敌袭结束 | stat_dodge, stat_harvesting |  |
| T1 | 疾行的羽毛 | 18 | +6 %速度<br>-4 %伤害 | stat_speed |  |
| T1 | 连发肥料 | 20 | +17 %攻击速度<br>下场敌袭以1点生命值开始 | stat_attack_speed |  |
| T1 | 丰饶的鲜肉 | 15 | +11 收获<br>树木能被一击毙命<br>-10 范围 | stat_harvesting, exploration | 独特 |
| T1 | 易爆的外星绅士 | 20 | +20 %爆炸范围<br>-3 %闪避 | explosive |  |
| T1 | 蛮力眼镜 | 20 | +2 近战伤害<br>每砍倒3棵树木，爆炸，造成相当于100%范围的伤害<br>受到伤害时有15%概率-1护甲，直至敌袭结束 | stat_melee_damage, explosive, exploration, stat_range |  |
| T1 | 收成山羊头骨 | 20 | +15 收获<br>受到伤害时有85%概率-1%攻击速度，直至敌袭结束 | stat_harvesting |  |
| T1 | 精准软糖狂战士 | 15 | +1 远程伤害<br>站立不动时-6%闪避 | stat_ranged_damage | 核心 |
| T1 | 修补匠的头部创伤 | 25 | +5 工程学<br>-7 %攻击速度 | stat_engineering | 核心 |
| T1 | 凶猛的刺猬 | 25 | +6 %伤害<br>-2 %暴击率 | stat_percent_damage |  |
| T1 | 奇特的头盔 | 18 | 地雷每12秒生成一次，并对一个区域造成10（+100%）伤害<br>-3 %速度 | explosive, structure |  |
| T1 | 莫测的注射剂 | 15 | +2 %暴击率<br>生成1台炮塔，造成10（+80%）伤害<br>敌袭结束后+1%敌人速度 | stat_crit_chance, structure |  |
| T1 | 觉醒精神异常 | 20 | +1 近战伤害<br>移动时，每永久持有12%速度会+1最大生命值 [+0]<br>每永久持有20元素伤害会-1生命再生 [+0] | stat_melee_damage, stat_speed, stat_max_hp |  |
| T1 | 成长果冻 | 15 | 每次获得一个提升%生命窃取的道具时，有30%概率+1%生命窃取<br>-1 %闪避 | stat_lifesteal |  |
| T1 | 恶毒的地雷 | 15 | +3 %暴击率<br>使用中世纪类武器时+30范围<br>-1 护甲 | stat_crit_chance, stat_range |  |
| T1 | 沉重的柠檬水 | 25 | +3 近战伤害<br>下场敌袭期间-14 最大生命值 | stat_melee_damage |  |
| T1 | 炽热的镜片 | 25 | +1 元素伤害<br>敌袭结束后+1%敌人伤害 | stat_elemental_damage | 核心 |
| T1 | 收成搜刮虫虫 | 25 | +20 收获<br>以暴击杀死敌人时，+2近战伤害，持续3秒<br>以暴击杀死敌人时，-2元素伤害，持续3秒<br>-3 %生命窃取 | stat_harvesting, stat_melee_damage, stat_crit_chance |  |
| T1 | 收成失落鸭鸭 | 20 | +16 收获<br>捡起消耗品时+5%拾取范围。每波最大值：+5<br>捡起消耗品时-1护甲。每波最大值：-1<br>-6 %攻击速度 | stat_harvesting, consumable, pickup |  |
| T1 | 铁甲伐木工人衬衫 | 15 | +1 护甲<br>站立不动时-2%速度 | stat_armor |  |
| T1 | 寄生的蘑菇 | 25 | +2 %闪避<br>+3 %生命窃取<br>受到伤害时有50%概率-1近战伤害，直至敌袭结束 | stat_dodge, stat_lifesteal |  |
| T1 | 锋利的异变 | 15 | +2 %伤害<br>每受到2次伤害，对随机1名敌人造成相当于100%幸运的伤害 | stat_percent_damage, stat_luck |  |
| T1 | 锋利的和平蜜蜂 | 12 | +2 %伤害<br>升级时爆炸，造成相当于200%远程伤害的伤害<br>每永久持有15元素伤害会-1最大生命值 [+0] | stat_percent_damage, explosive, stat_ranged_damage |  |
| T1 | 沉重的铅笔 | 20 | +5 近战伤害<br>-3 %伤害 | stat_melee_damage | 核心 |
| T1 | 远足的企鹅 | 30 | +1 护甲<br>每前进1步，有10%概率获得1个材料<br>-2 工程学 | stat_armor, economy, stat_speed |  |
| T1 | 远古植物 | 20 | +4 幸运<br>使用元素类武器时+10%攻击速度<br>%闪避的修改减少10% | stat_luck, stat_attack_speed |  |
| T1 | 精巧的螺旋桨帽 | 30 | +4 工程学<br>-4 %伤害 | stat_engineering |  |
| T1 | 滋补的鼠斯拉 | 20 | 使用消耗品恢复+1HP<br>-1 生命再生 | consumable |  |
| T1 | 睿智的疤痕 | 15 | +25 获得%经验<br>捡起消耗品时有65%概率-5范围，直至敌袭结束 | xp_gain | 核心 |
| T1 | 精准害怕的香肠 | 20 | +1 远程伤害 | stat_ranged_damage |  |
| T1 | 幻影尖头子弹 | 30 | +9 %闪避<br>-3 %伤害 | stat_dodge |  |
| T1 | 修长的小鱼 | 15 | +5 范围 | stat_range |  |
| T1 | 古怪的蛇 | 25 | 使用消耗品恢复+2HP<br>生成一个搜刮虫虫宠物，会为玩家收集材料和摧毁树木。每次拾取材料时，有10%几率将其翻倍 | consumable, economy, pickup, pet | 独特 |
| T1 | 回响的惊恐的洋葱 | 15 | +2 %速度<br>每持有1件IV等级武器有+2工程学[+0]<br>元素伤害的修改减少10% | stat_speed, stat_engineering |  |
| T1 | 坚毅的毒污泥 | 25 | +1 护甲<br>+10 范围<br>+1 最大生命值<br>下场敌袭期间+75 获得%经验<br>下场敌袭期间+50 %敌人生命值<br>-2 %速度 | stat_armor, stat_range, stat_max_hp, xp_gain |  |
| T1 | 离奇的树木 | 20 | 对生命值超过75%的目标造成+10%伤害<br>-1 近战伤害 | stat_percent_damage |  |
| T1 | 受祝福的炮塔 | 25 | +2击退<br>治疗时有15%概率+1生命再生，直至敌袭结束<br>下场敌袭期间-21 %伤害 | knockback, stat_hp_regeneration |  |
| T1 | 精准丑牙 | 20 | +1 远程伤害<br>下场敌袭期间+47 获得%经验 | stat_ranged_damage, xp_gain |  |
| T1 | 坚毅的奇怪的食物 | 25 | +2 护甲 | stat_armor |  |
| T1 | 远视的奇怪的幽灵 | 20 | +10 范围<br>闪避时有45%概率-1最大生命值，直至敌袭结束 | stat_range |  |
| T1 | 锋利的哨子 | 20 | +8 %伤害<br>持有每一异种武器-5范围 [+0] | stat_percent_damage |  |
| T2 | 异想天开的酸液 | 30 | +1 远程伤害<br>+12 %构建物的攻击速度 | stat_ranged_damage, structure |  |
| T2 | 收成异形眼球 | 60 | +18 收获<br>持有每一异种武器-5幸运 [+0] | stat_harvesting | 核心 |
| T2 | 风暴鱿鱼宝宝 | 35 | +2 元素伤害<br>移动时，每4构筑物会+3元素伤害 [+0] | stat_elemental_damage, structure |  |
| T2 | 睿智的旗帜 | 50 | +38 获得%经验<br>-5 %暴击率 | xp_gain |  |
| T2 | 暴食的黑带 | 50 | +3 %暴击率<br>捡起消耗品时有95%概率+1工程学。每波最大值：+1<br>%闪避的修改减少10% | stat_crit_chance, stat_engineering, consumable |  |
| T2 | 异想天开的焰蜥蜴 | 55 | +3 最大生命值<br>生成一只Bonk狗宠物，会造成10（+60%）伤害。它每5秒钟会进行一次冲刺攻击，在范围内造成8（+40%）爆炸伤害<br>下场敌袭期间+20 %敌人速度 | stat_max_hp, explosive, pet |  |
| T2 | 奥术眼罩 | 48 | +8 元素伤害<br>闪避时+3%敌人速度，直至敌袭结束 | stat_elemental_damage, stat_dodge | 核心 |
| T2 | 共鸣血蛭 | 40 | +10 %攻击速度<br>+2 生命再生<br>每永久持有1%闪避会+1幸运 [+0]<br>-16 %伤害 | stat_attack_speed, stat_hp_regeneration, stat_luck, stat_dodge |  |
| T2 | 精准骨骰 | 40 | +1 远程伤害<br>生命值低于50%时%攻击速度的修改增加50%<br>-1 近战伤害 | stat_ranged_damage, stat_attack_speed |  |
| T2 | 机械Bonk狗 | 55 | +8 工程学<br>-6 %闪避 | stat_engineering | 核心 |
| T2 | 轻盈布雷机器人 | 48 | +2 %生命窃取<br>闪避时恢复5点生命值 | stat_lifesteal, stat_dodge |  |
| T2 | 蛮力篝火 | 45 | +4 近战伤害<br>每17秒-1%闪避，直至敌袭结束。每波最大值：-30 | stat_melee_damage | 核心 |
| T2 | 诡异的猫特林机枪 | 50 | +1 %伤害<br>使用枪械类武器时+1贯通<br>-2 %暴击率 | stat_percent_damage, stat_ranged_damage |  |
| T2 | 修补匠的大锅 | 45 | +7 工程学<br>每以暴击杀死6个敌人，+1%暴击率。每波最大值：+4<br>下场敌袭期间+100 %敌人伤害 | stat_engineering, stat_crit_chance |  |
| T2 | 离奇的芹菜茶 | 40 | 生成一个焰蜥蜴宠物，造成1（+1%）伤害。每4秒钟，向所有方向发射燃烧的投射物，每发造成1（+1%）伤害。被这些攻击命中的敌人会受到5x3（+50%）燃烧伤害<br>每永久持有4%速度会-5范围 [-6] | pet |  |
| T2 | 古怪的机械黄蜂 | 55 | +1 远程伤害<br>在箱子中有+2%的几率发现额外的机械黄蜂<br>-1 护甲 | stat_ranged_damage |  |
| T2 | 扎根齿轮 | 40 | +16 获得%经验<br>站立不动时，每持有一异种I级别物品有+1元素伤害[+0]<br>下场敌袭一开始会出现特殊敌人 | xp_gain, stand_still, stat_elemental_damage |  |
| T2 | 异想天开的指南针 | 40 | +1 工程学<br>+5 %暴击率<br>使用音乐类武器时+20%暴击率<br>每持有一异种IV级别物品有-3%速度[+0] | stat_engineering, stat_crit_chance |  |
| T2 | 远足的珊瑚 | 40 | +2 工程学<br>每前进1步，有15%概率恢复1点生命值<br>-1 %生命窃取 | stat_engineering, stat_speed |  |
| T2 | 伸缩的赛博球 | 40 | +25 范围<br>每4秒+8%暴击率，持续3秒<br>每4秒-4远程伤害，持续3秒<br>每6秒-1%攻击速度，直至敌袭结束。每波最大值：-15 | stat_range, stat_crit_chance |  |
| T2 | 回响的独眼虫 | 40 | +5 范围<br>目前每一棵存活的树木有+1生命再生[+0] | stat_range, stat_hp_regeneration |  |
| T2 | 精炼的危险的兔子 | 40 | +4 生命再生<br>最大生命值的修改增加10%<br>-1 护甲 | stat_hp_regeneration, stat_max_hp |  |
| T2 | 回响的腐肉 | 60 | +5 %生命窃取<br>每25材料会+1生命再生 [+1]<br>每杀死14个敌人，-1远程伤害，直至敌袭结束 | stat_lifesteal, stat_hp_regeneration, economy |  |
| T2 | 灵巧的蛾医生 | 45 | +7 %闪避<br>处于最大生命值时%速度的修改增加50%<br>移动时-3远程伤害 | stat_dodge, stat_speed |  |
| T2 | 炽热的能量手环 | 45 | +1 元素伤害<br>离开商店时，锁定的道具和武器有7%的几率受到诅咒 | stat_elemental_damage, lock |  |
| T2 | 灵巧的海盗眼罩  | 35 | +5 %闪避<br>+10 收获<br>站立不动时，每永久持有6击退会+5%速度 [+0]<br>每4近战伤害会-5范围 [+0] | stat_dodge, stat_harvesting, stand_still, knockback, stat_speed |  |
| T2 | 奇特的眼部手术 | 50 | +4 %攻击速度<br>敌袭开始时+12%材料（在第20波敌袭后结束）<br>-7击退 | stat_attack_speed |  |
| T2 | 锐利的果篮 | 40 | +2 工程学<br>用元素伤害杀死敌人时，有40%概率爆炸，造成相当于75%生命再生的伤害<br>-2 远程伤害 | stat_engineering, explosive, stat_elemental_damage, stat_hp_regeneration |  |
| T2 | 躁动燃料箱 | 65 | +4 近战伤害<br>+5 收获<br>移动时+30范围<br>移动时-11%速度 | stat_melee_damage, stat_harvesting, stat_range |  |
| T2 | 黄昏赌博筹码 | 40 | 敌袭结束时获得23个材料 | economy |  |
| T2 | 离奇的花园 | 50 | +1 元素伤害<br>-6 %敌人速度 | stat_elemental_damage, less_enemy_speed |  |
| T2 | 镀层冰块 | 30 | +3 护甲<br>-5 %速度 | stat_armor |  |
| T2 | 神圣的干肉条 | 60 | +1 远程伤害<br>治疗时有85%概率对随机1名敌人造成相当于150%范围的伤害 | stat_ranged_damage, stat_range |  |
| T2 | 吸血鬼的皮革背心 | 35 | +3 %生命窃取<br>每5秒恢复2点生命值<br>-2 护甲 | stat_lifesteal |  |
| T2 | 凶猛的小青蛙 | 40 | +7 %伤害<br>下场敌袭期间+20 %敌人速度 | stat_percent_damage | 核心 |
| T2 | 回响的肌肉小子 | 55 | +20 范围<br>每1%速度会+1%攻击速度 [+5] | stat_range, stat_attack_speed, stat_speed |  |
| T2 | 共鸣鱼饵  | 40 | +2 元素伤害<br>每永久持有2护甲会+1工程学 [+0]<br>-5 %闪避 | stat_elemental_damage, stat_engineering, stat_armor |  |
| T2 | 离奇的精湛技艺 | 50 | +4 近战伤害<br>使用工具类武器时+50%攻击速度<br>-11 %速度 | stat_melee_damage, stat_attack_speed |  |
| T2 | 奇异的勋章 | 55 | +6 收获<br>燃烧速度提高9%<br>-2 近战伤害 | stat_harvesting, stat_elemental_damage |  |
| T2 | 诡异的金属探测器 | 45 | +4 %暴击率<br>生成一个布雷机器人构筑物，发射子弹造成10（+100%）伤害。同时每5生成一个地雷，在范围内造成10（+100%）伤害 | stat_crit_chance, pet, structure |  |
| T2 | 破晓金属板 | 40 | 下场敌袭期间+120 获得%经验<br>下场敌袭期间-10 生命再生 | xp_gain |  |
| T2 | 共鸣导弹 | 35 | +1 工程学<br>+3 %暴击率<br>持有每一异种武器+1远程伤害 [+0] | stat_engineering, stat_crit_chance, stat_ranged_damage |  |
| T2 | 睿智的护垫 | 48 | +64 获得%经验<br>-25 范围 | xp_gain | 核心 |
| T2 | 致命珍珠 | 48 | +4 %暴击率<br>每以暴击杀死3个敌人，+1%贯通伤害，不会高于基础伤害，直至敌袭结束 | stat_crit_chance |  |
| T2 | 厚重的猪猪存钱罐 | 40 | +6 最大生命值<br>刷新商店时，永久获得“每8近战伤害会+1%暴击率 [+0]”（每波最多1次）<br>-3 %速度 | stat_max_hp, stat_melee_damage, stat_crit_chance |  |
| T2 | 黄昏一堆书 | 50 | +9 收获<br>敌袭结束时获得60经验 | stat_harvesting, xp_gain |  |
| T2 | 共鸣南瓜 | 40 | 目前每一棵存活的树木有+1生命再生[+0]<br>-5% 敌人 | stat_hp_regeneration, less_enemies |  |
| T2 | 吸血鬼的回收装置 | 60 | +6 %生命窃取<br>下场敌袭期间+60 获得%经验<br>下场敌袭期间+50 %敌人生命值<br>捡起消耗品时-2%攻击速度，直至敌袭结束。每波最大值：-60 | stat_lifesteal, xp_gain |  |
| T2 | 半途强化钢 | 40 | +3 最大生命值<br>敌袭进行到一半时+2%伤害<br>敌袭进行到一半时-1生命再生 | stat_max_hp, stat_percent_damage |  |
| T2 | 精巧的反击 | 40 | +4 工程学<br>刷新商店时+5范围。每波最大值：+5 | stat_engineering, stat_range |  |
| T2 | 夺命的仪式 | 30 | +11 %暴击率<br>用远程伤害杀死敌人时，永久获得“每80材料会+1%攻击速度 [+0]”（每波最多1次）<br>下场敌袭期间-14 最大生命值 | stat_crit_chance, stat_ranged_damage, economy, stat_attack_speed |  |
| T2 | 狂乱的盐水 | 50 | +26 %攻击速度<br>每2%速度会-1%伤害 [-2] | stat_attack_speed | 核心 |
| T2 | 回响的瞄准镜 | 30 | +5 %攻击速度<br>每永久持有2护甲会+1最大生命值 [+0]<br>敌袭结束后+3%敌人生命值 | stat_attack_speed, stat_max_hp, stat_armor |  |
| T2 | 锋利的阴影药水 | 55 | +9 %伤害<br>+15 %构建物的攻击速度 | stat_percent_damage, structure |  |
| T2 | 急切的小型弹匣 | 40 | 敌人在首次被元素伤害命中时，有75%概率+1%攻击速度，持续6秒 | stat_attack_speed, stat_elemental_damage |  |
| T2 | 记仇的蜗牛 | 50 | +9 %速度<br>受到伤害时恢复5点生命值<br>-3 护甲 | stat_speed |  |
| T2 | 结实的雪球 | 45 | +2 生命再生<br>+5 最大生命值<br>处于最大生命值时%速度的修改增加50% | stat_hp_regeneration, stat_max_hp, stat_speed |  |
| T2 | 离奇的辣酱 | 40 | 商店免费刷新+1次 | economy |  |
| T2 | 灼烧的墨镜 | 40 | +1 工程学<br>杀死燃烧的敌人时，有35%概率+1%暴击率，直至敌袭结束<br>-2 %伤害 | stat_engineering, stat_crit_chance, stat_elemental_damage |  |
| T2 | 急切的触手 | 50 | +2 %生命窃取<br>+2 护甲<br>敌袭开始时永久获得“幸运的修改增加10%”<br>捡起消耗品时-1生命再生，直至敌袭结束 | stat_lifesteal, stat_armor, stat_luck |  |
| T2 | 回响的藏宝图 | 40 | 每5远程伤害会+1%速度 [+0] | stat_speed, stat_ranged_damage |  |
| T2 | 律动的燃烧炮塔 | 48 | +1 远程伤害<br>+2 近战伤害<br>每4秒+1工程学。每波最大值：+1<br>-5 获得%经验 | stat_ranged_damage, stat_melee_damage, stat_engineering |  |
| T2 | 离奇的医疗炮塔 | 40 | +2 生命再生<br>生成一个花园，每15秒可以结下一种水果 | stat_hp_regeneration, consumable, structure |  |
| T2 | 收成泰勒 | 40 | +13 收获<br>捡起消耗品时爆炸，造成相当于75%近战伤害的伤害<br>-6 %伤害 | stat_harvesting, consumable, explosive, stat_melee_damage |  |
| T2 | 鹰眼独轮车 | 40 | +3 远程伤害<br>每10秒+1%敌人速度，直至敌袭结束。每波最大值：+10 | stat_ranged_damage | 核心 |
| T2 | 莫测的磨刀石 | 35 | +2 %速度<br>离开商店时，锁定的道具和武器有30%的几率受到诅咒<br>杀死敌人时有10%概率-1生命再生，直至敌袭结束 | stat_speed, lock |  |
| T2 | 美味的白旗 | 40 | 使用消耗品恢复+2HP<br>站立不动时+19击退<br>移动时-2工程学 | consumable, knockback, stand_still |  |
| T3 | 成长肾上腺素 | 70 | +7 %伤害<br>升级时获得29个材料<br>+15 %敌人伤害 | stat_percent_damage, economy |  |
| T3 | 炽热的幼年异形 | 70 | +7 元素伤害<br>敌袭结束后+5%敌人生命值 | stat_elemental_damage |  |
| T3 | 神秘的外星魔法 | 85 | +3 %伤害<br>+6 幸运<br>+1 最大生命值<br>+15% 敌人<br>-3 %暴击率 | stat_percent_damage, stat_luck, stat_max_hp, more_enemies |  |
| T3 | 远古合金 | 50 | +3 %速度<br>+2 生命再生<br>使用原始类武器时+150％暴击伤害 | stat_speed, stat_hp_regeneration, stat_crit_chance |  |
| T3 | 暴食的长胡子的婴儿 | 80 | +5 %伤害<br>+5击退<br>+10 %攻击速度<br>+5 %暴击率<br>+2 工程学<br>捡起消耗品时对随机1名敌人造成相当于250%范围的伤害<br>+10 %敌人伤害 | stat_percent_damage, knockback, stat_attack_speed, stat_crit_chance, stat_engineering, consumable, stat_range |  |
| T3 | 增幅链球 | 75 | +4 %生命窃取<br>最大生命值的修改增加25%<br>每持有一异种I级别物品有-1%闪避[+0] | stat_lifesteal, stat_max_hp |  |
| T3 | 滑溜的头巾 | 60 | +9 幸运<br>+5 %闪避<br>武器和宠物伤害会受到10%元素伤害影响<br>敌袭结束后+5%敌人生命值 | stat_luck, stat_dodge, stat_elemental_damage |  |
| T3 | 共鸣藤壶 | 65 | +1 护甲<br>+4击退<br>+2 %生命窃取<br>每永久持有1%生命窃取会+1%速度 [+0]<br>-9 %速度 | stat_armor, knockback, stat_lifesteal, stat_speed |  |
| T3 | 伸缩的路障 | 65 | +30 范围<br>每以暴击杀死2个敌人，爆炸，造成相当于75%近战伤害的伤害<br>捡起消耗品时-2%暴击率，直至敌袭结束 | stat_range, explosive, stat_crit_chance, stat_melee_damage |  |
| T3 | 鹰眼豆老师 | 85 | +9 远程伤害<br>每杀死4个敌人，+1%伤害。每波最大值：+12<br>每杀死4个敌人，+1%敌人速度。每波最大值：+12<br>敌袭结束后+5%敌人伤害 | stat_ranged_damage, stat_percent_damage |  |
| T3 | 回响的黑旗 | 75 | +2 近战伤害<br>+1 远程伤害<br>每持有一异种I级别物品有+1工程学[+0]<br>+5 诅咒 | stat_melee_damage, stat_ranged_damage, stat_engineering, stat_curse |  |
| T3 | 离奇的献血 | 60 | +10 %伤害<br>复制你从商店获得的下一个道具（不能超过道具限制）（生效后此条效果消失）<br>-7 %攻击速度 | stat_percent_damage |  |
| T3 | 生机圆顶礼帽 | 50 | +4 生命再生<br>每持有1件I等级武器有+1护甲[+0] | stat_hp_regeneration, stat_armor |  |
| T3 | 远古蜡烛 | 55 | +3 工程学<br>从等级提升中获得+21%属性<br>-10% 敌人 | stat_engineering, less_enemies |  |
| T3 | 离奇的糖果袋 | 60 | 闪避上限为70%<br>每波敌袭有10%几率额外生成一个精英 | （无） | 独特 |
| T3 | 古怪的变色龙 | 70 | +1 %生命窃取<br>+1 生命再生<br>使用爆炸类武器时+10%暴击率<br>移动时-1最大生命值 | stat_lifesteal, stat_hp_regeneration, stat_crit_chance |  |
| T3 | 急速三叶草 | 85 | +36 %攻击速度<br>敌袭结束后+5%敌人生命值 | stat_attack_speed | 核心 |
| T3 | 急切的线圈 | 65 | +10 生命再生<br>每命中生命值高于75%的敌人2次，恢复1点生命值<br>-5 %生命窃取 | stat_hp_regeneration |  |
| T3 | 炽热的社区支持 | 70 | +3 元素伤害<br>刷新商店时+1工程学。每波最大值：+1<br>闪避时-1%伤害，直至敌袭结束 | stat_elemental_damage, stat_engineering |  |
| T3 | 沉重的王冠 | 85 | +2 %生命窃取<br>+5 近战伤害<br>敌袭结束时+1最大生命值<br>-5 %伤害 | stat_lifesteal, stat_melee_damage, stat_max_hp |  |
| T3 | 沉重的水晶 | 85 | +16 近战伤害<br>每以暴击杀死2个敌人，+1%暴击率。每波最大值：+9<br>每以暴击杀死2个敌人，-3幸运。每波最大值：-27<br>-25 %爆炸伤害 | stat_melee_damage, stat_crit_chance |  |
| T3 | 精炼的小精灵 | 80 | +6 生命再生<br>最大生命值的修改增加20% | stat_hp_regeneration, stat_max_hp |  |
| T3 | 幸运鳍 | 50 | +13 幸运<br>每杀死2个敌人，爆炸，造成相当于25%元素伤害的伤害 | stat_luck, explosive, stat_elemental_damage |  |
| T3 | 神秘的炒饭 | 65 | +4 生命再生<br>+4 %生命窃取<br>从等级提升中获得+53%属性<br>道具将在下次刷新后提升1个级别（生效后此条效果消失）<br>-10 %攻击速度 | stat_hp_regeneration, stat_lifesteal |  |
| T3 | 丰饶的冰冻的心 | 70 | +21 收获<br>每闪避2次，-1护甲，直至敌袭结束 | stat_harvesting | 核心 |
| T3 | 复仇幽灵服 | 65 | +2 远程伤害<br>受到伤害时爆炸，造成相当于75%最大生命值的伤害<br>燃烧速度降低100% | stat_ranged_damage, explosive, stat_max_hp |  |
| T3 | 常青的玻璃大炮 | 65 | +8 生命再生<br>敌袭结束时获得28个材料<br>-5 元素伤害 | stat_hp_regeneration, economy |  |
| T3 | 坚毅的高脚杯 | 100 | +5 护甲<br>每永久持有5收获会+1生命再生 [+1]<br>-13 幸运 | stat_armor, stat_hp_regeneration, stat_harvesting |  |
| T3 | 觉醒手铐 | 75 | +2 近战伤害<br>受到伤害时有85%概率工程学的修改增加5%，直至敌袭结束<br>武器和宠物伤害会受到10%元素伤害影响<br>-7 %暴击率 | stat_melee_damage, stat_engineering, stat_elemental_damage |  |
| T3 | 黄昏蜂蜜 | 60 | +4 近战伤害<br>敌袭结束时将4点属性点随机分配到你的主要属性上<br>复制你从商店获得的下一个道具（不能超过道具限制）（生效后此条效果消失）<br>移动时-28%伤害 | stat_melee_damage |  |
| T3 | 共鸣狩猎战利品 | 60 | +2 工程学<br>+2 %攻击速度<br>每持有1件I等级武器有+4%速度[+0]<br>+10 %敌人伤害 | stat_engineering, stat_attack_speed, stat_speed |  |
| T3 | 夺命的改进工具 | 55 | +9 %暴击率<br>每杀死5个敌人，恢复1点生命值<br>以-50%生命值开始敌袭 | stat_crit_chance |  |
| T3 | 常青的水母盾 | 60 | +7 生命再生<br>每12秒对随机1名敌人造成相当于400%最大生命值的伤害<br>对头目和精英怪造成+11%伤害<br>-11 %速度 | stat_hp_regeneration, stat_max_hp, stat_percent_damage |  |
| T3 | 精准结 | 55 | +3 远程伤害<br>每杀死3个敌人，+1生命再生，持续6秒<br>-6 %攻击速度 | stat_ranged_damage, stat_hp_regeneration |  |
| T3 | 黄昏灯塔 | 80 | +4 远程伤害<br>+6 近战伤害<br>敌袭结束时将8点属性点随机分配到你的主要属性上<br>-21 %伤害 | stat_ranged_damage, stat_melee_damage |  |
| T3 | 丰饶的护身符 | 80 | +50 收获<br>+18 幸运<br>每秒受到1伤害（不给予无敌时间） | stat_harvesting, stat_luck |  |
| T3 | 异想天开的镜子 | 50 | +15 范围<br>+5 工程学<br>生成1台发射贯通弹的炮塔，造成20（+125%）伤害<br>-9 %闪避 | stat_range, stat_engineering, structure |  |
| T3 | 精准老鼠 | 65 | +7 远程伤害<br>-5 生命再生 | stat_ranged_damage | 核心 |
| T3 | 共鸣钉子 | 60 | 拾取范围+10%<br>每永久持有2%拾取范围会+1%伤害 [+0] | pickup, stat_percent_damage | 限制 (3)，成长型 |
| T3 | 凶猛的孔雀 | 65 | +8 %伤害<br>闪避时爆炸，造成相当于100%最大生命值的伤害 | stat_percent_damage, explosive, stat_dodge, stat_max_hp |  |
| T3 | 莫测的塑性炸药 | 60 | +3 最大生命值<br>使用重型类武器时+100％暴击伤害 | stat_max_hp, stat_crit_chance |  |
| T3 | 锋利的毒性补品 | 85 | +15 %伤害<br>站立不动时-18%速度 | stat_percent_damage | 核心 |
| T3 | 成长发电机 | 80 | +2 远程伤害<br>升级时+5击退<br>每4幸运会-1%暴击率 [+0] | stat_ranged_damage, knockback |  |
| T3 | 共鸣狂怒 | 85 | +4 远程伤害<br>持有每一异种武器+25范围 [+0]<br>-7 工程学 | stat_ranged_damage, stat_range |  |
| T3 | 猎杀悲伤的番茄 | 80 | +3 生命再生<br>每杀死3个敌人，+1幸运。每波最大值：+13<br>-10% 敌人 | stat_hp_regeneration, stat_luck, less_enemies |  |
| T3 | 好学的围巾 | 50 | +77 获得%经验<br>捡起消耗品时+5%敌人伤害，直至敌袭结束。每波最大值：+150 | xp_gain, consumable | 核心 |
| T3 | 精巧的镣铐 | 60 | +10 工程学<br>受到伤害时+5%敌人生命值，直至敌袭结束。每波最大值：+100 | stat_engineering | 核心 |
| T3 | 回响的休穆糖 | 70 | +3 元素伤害<br>+1 工程学<br>持有每一异种武器+6%伤害 [+0]<br>每5最大生命值会-1%伤害 [-3] | stat_elemental_damage, stat_engineering, stat_percent_damage |  |
| T3 | 迅捷银质子弹 | 65 | +9 %速度<br>每15秒获得4个材料<br>-9 %暴击率 | stat_speed, economy |  |
| T3 | 收成海星 | 80 | +13 收获<br>敌袭结束时，收获提高3%<br>武器和宠物伤害会受到10%元素伤害影响 | stat_harvesting, stat_elemental_damage |  |
| T3 | 风暴雕像 | 75 | +6 元素伤害<br>-25 范围 | stat_elemental_damage | 核心 |
| T3 | 厚重的石头皮肤 | 80 | +8 最大生命值<br>下场敌袭期间+20 %敌人速度 | stat_max_hp |  |
| T3 | 风暴奇怪之书 | 80 | +4 元素伤害<br>每以暴击杀死2个敌人，对随机1名敌人造成相当于150%近战伤害的伤害 | stat_elemental_damage, stat_crit_chance, stat_melee_damage |  |
| T3 | 急速沉钟 | 70 | +22 %攻击速度<br>每拾取4个材料，获得1个材料<br>-7 最大生命值 | stat_attack_speed, economy, pickup |  |
| T3 | 沉重的水熊虫 | 50 | +14 近战伤害<br>-5 最大生命值 | stat_melee_damage | 核心 |
| T3 | 被眷顾的工具箱 | 50 | +16 幸运<br>敌袭结束时获得18个材料 | stat_luck, economy |  |
| T3 | 恶毒的拖拉机 | 75 | +7 %暴击率<br>+10 范围<br>+2 近战伤害<br>下场敌袭期间+100 获得%经验<br>-10% 敌人 | stat_crit_chance, stat_range, stat_melee_damage, xp_gain, less_enemies |  |
| T3 | 共鸣三角之力 | 80 | +2 %速度<br>+3 %伤害<br>+1 元素伤害<br>每1%生命窃取会+3收获 [+0]<br>每2幸运会-1%伤害 [+0] | stat_speed, stat_percent_damage, stat_elemental_damage, stat_harvesting, stat_lifesteal |  |
| T3 | 暴食的激光炮塔 | 80 | +8 %伤害<br>捡起消耗品时获得3个材料<br>每80材料会-1护甲 [+0] | stat_percent_damage, consumable, economy |  |
| T3 | 诡异的义警戒指 | 75 | +1 最大生命值<br>生成1台发射贯通弹的炮塔，造成20（+125%）伤害<br>-8 %攻击速度 | stat_max_hp, structure |  |
| T3 | 古怪的流浪机器人 | 80 | +4 幸运<br>复制你从商店获得的下一个道具（不能超过道具限制）（生效后此条效果消失）<br>-8 %暴击率 | stat_luck |  |
| T3 | 觉醒士兵头盔 | 55 | +1 元素伤害<br>+11 获得%经验<br>移动时，每150材料会+3近战伤害 [+0]<br>捡起消耗品时-3幸运，直至敌袭结束。每波最大值：-60 | stat_elemental_damage, xp_gain, economy, stat_melee_damage |  |
| T3 | 贪吃的小麦 | 65 | +2 远程伤害<br>+2 收获<br>捡起消耗品时获得3个材料 | stat_ranged_damage, stat_harvesting, consumable, economy |  |
| T3 | 厚重的鬼火 | 80 | +11 最大生命值<br>生命值低于50%时+38%伤害<br>生命值低于50%时-25%速度<br>闪避时+5%敌人伤害，直至敌袭结束 | stat_max_hp, stat_percent_damage, stat_dodge |  |
| T3 | 回响的翅膀 | 55 | +1 护甲<br>每永久持有1护甲会+2%攻击速度 [+0] | stat_armor, stat_attack_speed | 独特，成长型 |
| T3 | 回响的智慧 | 75 | +1 护甲<br>+1 %生命窃取<br>每持有一异种IV级别物品有+3%速度[+0] | stat_armor, stat_lifesteal, stat_speed |  |
| T4 | 奥术铁砧 | 100 | +8 元素伤害<br>敌袭开始时，永久获得“每8生命再生会+2最大生命值 [+0]”<br>-5 近战伤害 | stat_elemental_damage, stat_hp_regeneration, stat_max_hp |  |
| T4 | 回响的灰烬 | 110 | +8 近战伤害<br>+5 最大生命值<br>每持有一异种I级别物品有+5幸运[+0]<br>下场敌袭以1点生命值开始 | stat_melee_damage, stat_max_hp, stat_luck |  |
| T4 | 古怪的巨臂 | 100 | +15 范围<br>+1 武器栏<br>下场敌袭以1点生命值开始 | stat_range |  |
| T4 | 共鸣血淋淋的手 | 105 | +6 最大生命值<br>+4 %速度<br>每2%速度会+1生命再生 [+2]<br>闪避时-2护甲，直至敌袭结束 | stat_max_hp, stat_speed, stat_hp_regeneration |  |
| T4 | 厚重的斗篷 | 90 | +2 护甲<br>+6 最大生命值<br>每杀死16个敌人，+1%速度。每波最大值：+3 | stat_armor, stat_max_hp, stat_speed |  |
| T4 | 离奇的执照 | 100 | +4 %速度<br>每秒回复8生命值，但无法通过其他途径恢复生命值。 | stat_speed |  |
| T4 | 远视的Esty的沙发 | 100 | +55 范围<br>每持有1件武器+1工程学 [+0]<br>受到伤害时-5幸运，直至敌袭结束 | stat_range, stat_engineering |  |
| T4 | 律动的吞吞怪之帽 | 110 | +2 生命再生<br>+1 最大生命值<br>+1 护甲<br>每12秒获得9个材料<br>-10 %攻击速度 | stat_hp_regeneration, stat_max_hp, stat_armor, economy |  |
| T4 | 共鸣外骨骼 | 100 | +17 %闪避<br>+8 生命再生<br>每永久持有1近战伤害会+1最大生命值 [+0]<br>-25 %速度 | stat_dodge, stat_hp_regeneration, stat_max_hp, stat_melee_damage |  |
| T4 | 好学的爆裂弹 | 110 | +59 获得%经验<br>持有每一异种武器-3%攻击速度 [+0] | xp_gain |  |
| T4 | 蛮力另一个胃 | 100 | +25 近战伤害<br>+5 远程伤害<br>远程伤害的修改增加50%<br>%伤害的修改减少50% | stat_melee_damage, stat_ranged_damage |  |
| T4 | 回响的焦点 | 100 | +19 %速度<br>+2 工程学<br>每持有1件武器+2护甲 [+0]<br>下场敌袭以1点生命值开始 | stat_speed, stat_engineering, stat_armor |  |
| T4 | 生机巨型带 | 110 | +11 生命再生<br>每3秒击退附近的敌人 | stat_hp_regeneration | 独特 |
| T4 | 囤积的地精 | 100 | +3 元素伤害<br>+1 护甲<br>每拾取7个材料，+1%攻击速度。每波最大值：+7<br>捡起消耗品时-2%速度，直至敌袭结束 | stat_elemental_damage, stat_armor, stat_attack_speed, pickup |  |
| T4 | 古怪的希腊火 | 100 | 进入商店时，会随机升级一把武器。如果无武器可升级，则可获得+2护甲。<br>每杀死6个敌人，-1工程学，直至敌袭结束 | （无） |  |
| T4 | 急切的Grind的魔法绿叶 | 90 | +9 最大生命值<br>命中生命值高于50%的敌人时，有45%概率获得1个材料<br>-65 范围 | stat_max_hp, economy |  |
| T4 | 耐心的重型子弹 | 100 | +32 幸运<br>敌袭结束时永久获得“最大生命值的修改增加10%”<br>-26 %伤害 | stat_luck, stat_max_hp |  |
| T4 | 离奇的沙漏 | 100 | +2 最大生命值<br>+2 护甲<br>每秒回复5生命值，但无法通过其他途径恢复生命值。 | stat_max_hp, stat_armor |  |
| T4 | 锐利的喷气背包 | 110 | +30 %伤害<br>目前每一个存活的敌人+1 %伤害[+0]<br>每秒受到1伤害（不给予无敌时间） | stat_percent_damage |  |
| T4 | 锐利的克拉肯的眼睛 | 100 | +1 护甲<br>+4 近战伤害<br>+8 %伤害<br>刷新商店时将1点属性点随机分配到你的主要属性上（每波最多7次）<br>+15 诅咒<br>下场敌袭以1点生命值开始 | stat_armor, stat_melee_damage, stat_percent_damage, stat_curse |  |
| T4 | 精炼的灯笼 | 110 | +3 近战伤害<br>+3 生命再生<br>最大生命值的修改增加20%<br>移动时-5生命再生 | stat_melee_damage, stat_hp_regeneration, stat_max_hp |  |
| T4 | 灵巧的幸运硬币 | 110 | +13 %闪避<br>+1 武器栏<br>-15 %伤害 | stat_dodge |  |
| T4 | 共鸣猛犸 | 100 | +5 工程学<br>每永久持有2工程学会+5%伤害 [+0]<br>杀死敌人时-1%攻击速度，直至敌袭结束。每波最大值：-30 | stat_engineering, stat_percent_damage | 限制 (2)，成长型 |
| T4 | 沉重的急救包 | 105 | +18 近战伤害<br>使用音乐类武器时+200％暴击伤害<br>-80 范围 | stat_melee_damage, stat_crit_chance |  |
| T4 | 生机夜视镜 | 90 | +13 生命再生<br>+4 %攻击速度<br>%速度的修改增加50%<br>-24 %伤害 | stat_hp_regeneration, stat_attack_speed, stat_speed |  |
| T4 | 增幅章鱼 | 105 | +12 %暴击率<br>+8 %速度<br>+4 生命再生<br>%闪避的修改增加50% | stat_crit_chance, stat_speed, stat_hp_regeneration, stat_dodge |  |
| T4 | 炽热的熊猫 | 100 | +2 生命再生<br>+2 护甲<br>点燃敌人时造成敌人当前生命值的7%以作为奖励伤害（头目和精英怪的0.7%） | stat_hp_regeneration, stat_armor, stat_elemental_damage, stat_percent_damage |  |
| T4 | 增幅土豆 | 110 | +20 幸运<br>+12 %伤害<br>+8 近战伤害<br>工程学的修改增加50%<br>-10 %暴击率 | stat_luck, stat_percent_damage, stat_melee_damage, stat_engineering |  |
| T4 | 神秘的再生药水 | 90 | +8 %伤害<br>掉落+22%材料 | stat_percent_damage, economy, pickup |  |
| T4 | 充能的Retromation的连帽衫 | 105 | +5 工程学<br>+7 %伤害<br>捡起消耗品时，每永久持有30范围会+2%暴击率 [+0]，直至敌袭结束<br>每持有1件武器-2%伤害 [+0] | stat_engineering, stat_percent_damage, consumable, stat_range, stat_crit_chance |  |
| T4 | 鹰眼跳弹 | 110 | +10 远程伤害<br>+21 %伤害<br>下场敌袭期间+65 获得%经验<br>下场敌袭期间+35 %敌人伤害<br>-25 %速度 | stat_ranged_damage, stat_percent_damage, xp_gain |  |
| T4 | 处决机械臂 | 110 | +63 获得%经验<br>+15 范围<br>+7 幸运<br>以暴击杀死敌人时，获得1个材料<br>-7 最大生命值 | xp_gain, stat_range, stat_luck, economy, stat_crit_chance |  |
| T4 | 回响的替罪羔羊 | 110 | 每永久持有5最大生命值会+2%伤害 [+6]<br>-7击退 | stat_percent_damage, stat_max_hp | 独特，成长型 |
| T4 | 掠食者的海贝壳 | 110 | +2 工程学<br>+10击退<br>+13 %暴击率<br>+10 范围<br>+1 %速度<br>命中生命值高于90%的敌人时，对随机1名敌人造成相当于225%远程伤害的伤害<br>-5 护甲 | stat_engineering, knockback, stat_crit_chance, stat_range, stat_speed, stat_ranged_damage |  |
| T4 | 贪吃的Sifd的圣物 | 100 | +8 最大生命值<br>+20 范围<br>+1 护甲<br>捡起消耗品时获得15经验<br>-10 %伤害 | stat_max_hp, stat_range, stat_armor, consumable, xp_gain |  |
| T4 | 铁甲蜘蛛 | 90 | +5 护甲<br>+1 %生命窃取<br>以暴击杀死敌人时，+1%速度，持续8秒 | stat_armor, stat_lifesteal, stat_speed, stat_crit_chance |  |
| T4 | 古怪的拷问 | 100 | +5 最大生命值<br>+3 生命再生<br>掉落+16%材料<br>-4 远程伤害 | stat_max_hp, stat_hp_regeneration, economy, pickup |  |
| T4 | 耐心的爆炸炮塔 | 100 | +2 %闪避<br>+1 护甲<br>+1 %生命窃取<br>+2 %攻击速度<br>+2 最大生命值<br>敌袭结束时+3%速度<br>下场敌袭以1点生命值开始 | stat_dodge, stat_armor, stat_lifesteal, stat_attack_speed, stat_max_hp, stat_speed |  |
| T4 | 回响的野狼头盔 | 80 | +4 %闪避<br>每永久持有8%闪避会+5最大生命值 [+0]<br>杀死敌人时-1幸运，直至敌袭结束。每波最大值：-15 | stat_dodge, stat_max_hp | 独特，成长型 |
