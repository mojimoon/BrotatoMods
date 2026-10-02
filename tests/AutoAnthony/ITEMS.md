# 默认设置下的全部重组道具

由测试在每次运行结束时自动生成（`test_cases.gd` 的 `_write_items_table`）。默认设置：重组道具、重组名称开启，其余选项关闭，平均数值 100%、浮动范围 125%、触发效果 150%，保留原版道具 0%；种子 42。

共 235 件：T1 62、T2 67、T3 67、T4 39。锚定道具（望远镜、诱饵、口袋工厂、美西螈、鱼钩等）保持原版，不在表内。

词条为道具资源的 tags（角色的偏好词条、商店按词条加权抽取都用它），使用原版的词条 ID。

| 稀有度 | 道具 | 价格 | 效果 | 词条 | 备注 |
| --- | --- | --- | --- | --- | --- |
| T1 | 常青的异形之舌 | 25 | +6 生命再生<br>拾取消耗品时：对随机敌人造成相当于 400% 工程学 的伤害<br>-10 %攻击速度 | stat_hp_regeneration, consumable, stat_engineering |  |
| T1 | 掠食者的异形虫 | 25 | +9 %攻击速度<br>每击杀 5 个敌人：对随机敌人造成相当于 75% 范围 的伤害<br>每1构筑物会-3%速度 [+0] | stat_attack_speed, stat_range |  |
| T1 | 野蛮的象宝宝 | 25 | +4 近战伤害<br>+8% 敌人<br>-2 远程伤害 | stat_melee_damage, more_enemies |  |
| T1 | 伸缩的壁虎宝宝 | 28 | +15 范围 | stat_range |  |
| T1 | 厚重的背包 | 18 | +2 最大生命值<br>-3 幸运 | stat_max_hp |  |
| T1 | 易爆的蝙蝠 | 15 | +5 %爆炸伤害<br>每永久持有20远程伤害会-1%伤害 [+0] | explosive |  |
| T1 | 锐利的无檐小便帽 | 30 | +11 %伤害<br>每持有1件IV等级武器有-1远程伤害[+0] | stat_percent_damage |  |
| T1 | 善变的沸水 | 25 | +1 %暴击率<br>刷新商店时：获得 2 材料 | stat_crit_chance, economy |  |
| T1 | 远视的书本 | 30 | +45 范围<br>下场敌袭以1点生命值开始 | stat_range |  |
| T1 | 修补匠的拳击手套 | 30 | +5 范围<br>+2 工程学<br>-1 护甲 | stat_range, stat_engineering |  |
| T1 | 夺命的裂口 | 25 | +2 %暴击率 | stat_crit_chance |  |
| T1 | 恶毒的蝴蝶 | 30 | +4 %暴击率<br>生命再生的修改减少10% | stat_crit_chance |  |
| T1 | 共鸣蛋糕 | 18 | 每持有1件I等级武器有+2%闪避[+0]<br>-4 %伤害 | stat_dodge |  |
| T1 | 好学的木炭 | 18 | +26 获得%经验<br>-3 %速度 | xp_gain |  |
| T1 | 愈合的利爪树 | 8 | +1 生命再生<br>-1 %暴击率 | stat_hp_regeneration |  |
| T1 | 离奇的咖啡 | 25 | +4 %伤害<br>击中敌人时能使其降低3%速度，最高12%<br>-3 最大生命值 | stat_percent_damage, less_enemy_speed |  |
| T1 | 厚重的被腐蚀的碎片 | 20 | +4 最大生命值<br>+1 诅咒<br>-3 %闪避 | stat_max_hp, stat_curse |  |
| T1 | 修长的优惠券 | 30 | +35 范围<br>-8 %道具价格<br>拾取消耗品时：本波 +2%敌人速度（每波最多 30 次） | stat_range, economy, consumable |  |
| T1 | 急速萌萌猴 | 20 | +7 %攻击速度<br>-4 %伤害 | stat_attack_speed | 核心 |
| T1 | 收成有缺陷的增强剂 | 20 | +11 收获<br>-2 %伤害 | stat_harvesting | 核心 |
| T1 | 锐利的胶带 | 12 | +5 %伤害<br>每击杀 31 个敌人：本波 -1%暴击率 | stat_percent_damage | 核心 |
| T1 | 回响的炸药 | 15 | 每150材料会+1最大生命值 [+0]<br>受到伤害时（45%几率）：本波 -1幸运 | stat_max_hp, economy |  |
| T1 | 丰满的羽毛 | 18 | +2 %速度<br>+2 最大生命值 | stat_speed, stat_max_hp |  |
| T1 | 恶毒的肥料 | 20 | +13 %暴击率<br>下场敌袭以1点生命值开始 | stat_crit_chance |  |
| T1 | 好学的鲜肉 | 15 | +22 获得%经验<br>生成1台炮塔，造成10（+80%）伤害<br>-4 %伤害 | xp_gain, structure |  |
| T1 | 易爆的外星绅士 | 20 | +20 %爆炸范围<br>-3 %闪避 | explosive |  |
| T1 | 骄傲的眼镜 | 20 | +1 近战伤害<br>生命值全满时：获得「每永久持有4%闪避会+2击退 [+0]」<br>受到伤害时（15%几率）：本波 -1护甲 | stat_melee_damage, stat_dodge, knockback |  |
| T1 | 古怪的山羊头骨 | 20 | +4 收获<br>使用枪械类武器时+2贯通<br>受到伤害时（85%几率）：本波 -1%攻击速度 | stat_harvesting, stat_ranged_damage |  |
| T1 | 精准软糖狂战士 | 15 | +1 远程伤害<br>静止时：-6%闪避 | stat_ranged_damage | 核心 |
| T1 | 修补匠的头部创伤 | 25 | +5 工程学<br>-7 %攻击速度 | stat_engineering | 核心 |
| T1 | 野蛮的刺猬 | 25 | +3 近战伤害<br>-2 %攻击速度 | stat_melee_damage |  |
| T1 | 远古头盔 | 18 | 对生命值超过75%的目标造成+10%伤害<br>-3 %速度 | stat_percent_damage |  |
| T1 | 古怪的注射剂 | 15 | +1 工程学<br>击中敌人时能使其降低3%速度，最高12%<br>敌袭结束后+1%敌人速度 | stat_engineering, less_enemy_speed |  |
| T1 | 鹰眼精神异常 | 20 | +1 远程伤害<br>静止时：获得「每永久持有12%速度会+3生命再生 [+1]」<br>每永久持有20元素伤害会-1生命再生 [+0] | stat_ranged_damage, stand_still, stat_speed, stat_hp_regeneration |  |
| T1 | 囤积的果冻 | 15 | 拾取材料时（20%几率）：+5范围，持续 3 秒<br>拾取材料时（20%几率）：-1%暴击率，持续 3 秒<br>-1 %闪避 | stat_range, pickup |  |
| T1 | 远古地雷 | 15 | +1 工程学<br>使用中世纪类武器时+30范围<br>-5 范围 | stat_engineering, stat_range |  |
| T1 | 沉重的柠檬水 | 25 | +3 近战伤害<br>下场敌袭期间-14 最大生命值 | stat_melee_damage |  |
| T1 | 炽热的镜片 | 25 | +1 元素伤害<br>敌袭结束后+1%敌人伤害 | stat_elemental_damage | 核心 |
| T1 | 骄傲的搜刮虫虫 | 25 | 生命值全满时：+25%伤害<br>-3 %生命窃取 | stat_percent_damage |  |
| T1 | 强力的失落鸭鸭 | 20 | +12击退<br>波次进行到一半时：本波 +8%伤害<br>波次进行到一半时：本波 -8%速度<br>-1 护甲 | knockback, stat_percent_damage |  |
| T1 | 铁甲伐木工人衬衫 | 15 | +1 护甲<br>静止时：-2%速度 | stat_armor |  |
| T1 | 共鸣蘑菇 | 25 | 每持有1件武器+1生命再生 [+0]<br>受到伤害时（50%几率）：本波 -1近战伤害 | stat_hp_regeneration |  |
| T1 | 灼烧的异变 | 15 | 每点燃 3 个敌人：本波获得「+1%敌人掉落的材料」 | stat_elemental_damage |  |
| T1 | 神圣的和平蜜蜂 | 12 | 恢复生命时（40%几率）：引发爆炸，造成相当于 75% 远程伤害 的伤害<br>每永久持有15元素伤害会-1最大生命值 [+0] | explosive, stat_ranged_damage |  |
| T1 | 沉重的铅笔 | 20 | +5 近战伤害<br>-3 %伤害 | stat_melee_damage | 核心 |
| T1 | 精打细算的企鹅 | 30 | +1 护甲<br>购买道具时：获得 3 材料<br>-2 工程学 | stat_armor, economy |  |
| T1 | 远古植物 | 20 | +4 收获<br>使用元素类武器时+10%攻击速度<br>%闪避的修改减少10% | stat_harvesting, stat_attack_speed |  |
| T1 | 远视的螺旋桨帽 | 30 | +20 范围<br>-1 元素伤害 | stat_range |  |
| T1 | 滋补的鼠斯拉 | 20 | 使用消耗品恢复+1HP<br>-1 生命再生 | consumable |  |
| T1 | 睿智的疤痕 | 15 | +25 获得%经验<br>拾取消耗品时（65%几率）：本波 -5范围 | xp_gain | 核心 |
| T1 | 精准害怕的香肠 | 20 | +1 远程伤害 | stat_ranged_damage |  |
| T1 | 轻风尖头子弹 | 30 | +10 %速度<br>-1 元素伤害 | stat_speed |  |
| T1 | 疾行的小鱼 | 15 | +1 %速度 | stat_speed |  |
| T1 | 滋补的蛇 | 25 | 使用消耗品恢复+2HP<br>攻击有25%机率造成3x1（+100%）的燃烧伤害 | consumable, stat_elemental_damage |  |
| T1 | 回响的惊恐的洋葱 | 15 | +2 %速度<br>每持有1件IV等级武器有+2工程学[+0]<br>元素伤害的修改减少10% | stat_speed, stat_engineering |  |
| T1 | 坚毅的毒污泥 | 25 | +1 护甲<br>+10 范围<br>+1 最大生命值<br>下场敌袭期间+75 获得%经验<br>下场敌袭期间+50 %敌人生命值<br>-2 %速度 | stat_armor, stat_range, stat_max_hp, xp_gain |  |
| T1 | 离奇的树木 | 20 | +1 %生命窃取<br>地雷每12秒生成一次，并对一个区域造成10（+100%）伤害<br>-1 近战伤害 | stat_lifesteal, explosive, structure |  |
| T1 | 嗜血炮塔 | 25 | +1 %生命窃取<br>恢复生命时（15%几率）：本波 +1生命再生<br>下场敌袭期间-10 近战伤害 | stat_lifesteal, stat_hp_regeneration |  |
| T1 | 精准丑牙 | 20 | +1 远程伤害<br>下场敌袭期间+47 获得%经验 | stat_ranged_damage, xp_gain |  |
| T1 | 被眷顾的奇怪的食物 | 25 | +11 幸运 | stat_luck |  |
| T1 | 复仇奇怪的幽灵 | 20 | +5 范围<br>受到伤害时（50%几率）：本波 +1%暴击率（每波最多 30 次）<br>受到伤害时（50%几率）：本波 -1%攻击速度（每波最多 30 次）<br>受到伤害时（80%几率）：本波 +1%敌人伤害（每波最多 10 次） | stat_range, stat_crit_chance |  |
| T1 | 锋利的哨子 | 20 | +8 %伤害<br>持有每一异种武器-5范围 [+0] | stat_percent_damage |  |
| T2 | 鹰眼酸液 | 30 | +1 远程伤害<br>消耗品会在4秒内持续为你治疗，而非瞬间治疗 | stat_ranged_damage, consumable |  |
| T2 | 收成异形眼球 | 60 | +17 收获<br>持有每一异种武器-5幸运 [+0] | stat_harvesting | 核心 |
| T2 | 奇异的鱿鱼宝宝 | 35 | +2 元素伤害<br>商店免费刷新+1次<br>-4 工程学 | stat_elemental_damage, economy |  |
| T2 | 弹力旗帜 | 50 | +19击退<br>+6 幸运<br>-2 元素伤害 | knockback, stat_luck |  |
| T2 | 远视的黑带 | 50 | +1 工程学<br>+10 范围<br>+1 远程伤害<br>拾取消耗品时：永久 +1%暴击率（每波最多 1 次）<br>拾取消耗品时：永久 -1生命再生（每波最多 1 次）<br>%速度的修改减少15% | stat_engineering, stat_range, stat_ranged_damage, stat_crit_chance, consumable |  |
| T2 | 厚重的焰蜥蜴 | 55 | +6 最大生命值<br>你的构筑物可以暴击<br>下场敌袭期间+20 %敌人速度 | stat_max_hp, structure, stat_crit_chance |  |
| T2 | 奥术眼罩 | 48 | +8 元素伤害<br>闪避时：本波 +3%敌人速度 | stat_elemental_damage, stat_dodge | 核心 |
| T2 | 共鸣血蛭 | 40 | +9 %攻击速度<br>+2 生命再生<br>每永久持有1%闪避会+1幸运 [+0]<br>-15 %伤害 | stat_attack_speed, stat_hp_regeneration, stat_luck, stat_dodge |  |
| T2 | 精准骨骰 | 40 | +1 远程伤害<br>静止时：获得「%攻击速度的修改增加25%」<br>-1 近战伤害 | stat_ranged_damage, stand_still, stat_attack_speed |  |
| T2 | 机械Bonk狗 | 55 | +8 工程学<br>-6 %闪避 | stat_engineering | 核心 |
| T2 | 吸血鬼的布雷机器人 | 48 | +2 %生命窃取<br>闪避时：回复 4 点生命 | stat_lifesteal, stat_dodge |  |
| T2 | 蛮力篝火 | 45 | +4 近战伤害<br>每 18 秒：本波 -1%闪避（每波最多 30 次） | stat_melee_damage | 核心 |
| T2 | 蛮力猫特林机枪 | 50 | +3 %伤害<br>+2 近战伤害<br>使用枪械类武器时+1贯通<br>-2 %暴击率 | stat_percent_damage, stat_melee_damage, stat_ranged_damage |  |
| T2 | 机械大锅 | 45 | +8 工程学<br>每 4 秒：获得 1 材料<br>下场敌袭期间+100 %敌人伤害 | stat_engineering, economy |  |
| T2 | 锋利的芹菜茶 | 40 | +7 %伤害<br>+15 %构建物的攻击速度<br>每永久持有4%速度会-5范围 [-6] | stat_percent_damage, structure |  |
| T2 | 离奇的机械黄蜂 | 55 | 生成一个花园，每15秒可以结下一种水果<br>-1 护甲 | consumable, structure |  |
| T2 | 律动的齿轮 | 40 | 拾取范围+15%<br>每 10 秒：本波获得「每2构筑物会+1生命再生 [+0]」<br>下场敌袭一开始会出现特殊敌人 | pickup, structure, stat_hp_regeneration |  |
| T2 | 远古指南针 | 40 | +1 工程学<br>+5 %暴击率<br>使用音乐类武器时+20%暴击率<br>每持有一异种IV级别物品有-3%速度[+0] | stat_engineering, stat_crit_chance |  |
| T2 | 修补匠的珊瑚 | 40 | +3 工程学<br>每暴击击杀 2 个敌人：+1最大生命值，持续 6 秒<br>每暴击击杀 2 个敌人：+5%敌人伤害，持续 6 秒<br>-1 %生命窃取 | stat_engineering, stat_max_hp, stat_crit_chance |  |
| T2 | 律动的赛博球 | 40 | +5 %闪避<br>每 4 秒：+5工程学，持续 3 秒<br>每 4 秒：-5近战伤害，持续 3 秒<br>每 17 秒：本波 -1远程伤害（每波最多 15 次） | stat_dodge, stat_engineering |  |
| T2 | 回响的独眼虫 | 40 | +1 护甲<br>目前每一棵存活的树木有+1最大生命值[+0] | stat_armor, stat_max_hp |  |
| T2 | 精炼的危险的兔子 | 40 | +3 生命再生<br>最大生命值的修改增加10%<br>-1 护甲 | stat_hp_regeneration, stat_max_hp |  |
| T2 | 回响的腐肉 | 60 | +5 %生命窃取<br>每25材料会+1生命再生 [+1]<br>受到伤害时（90%几率）：本波 -1远程伤害 | stat_lifesteal, stat_hp_regeneration, economy |  |
| T2 | 躁动蛾医生 | 45 | +5 %闪避<br>移动时：获得「%速度的修改增加50%」<br>移动时：-3远程伤害 | stat_dodge, stat_speed |  |
| T2 | 奇异的能量手环 | 45 | +3 %攻击速度<br>+8 %构建物的攻击速度 | stat_attack_speed, structure |  |
| T2 | 灵巧的海盗眼罩  | 35 | +4 %闪避<br>+10 收获<br>静止时：获得「每永久持有6击退会+5%速度 [+0]」<br>每4近战伤害会-5范围 [+0] | stat_dodge, stat_harvesting, stand_still, knockback, stat_speed |  |
| T2 | 致命眼部手术 | 50 | +4 %暴击率<br>在箱子中有+1%的几率发现额外的眼部手术<br>拾取范围-15% | stat_crit_chance |  |
| T2 | 炽热的果篮 | 40 | +10 范围<br>点燃敌人时：对随机敌人造成相当于 175% 元素伤害 的伤害<br>-7 %攻击速度 | stat_range, stat_elemental_damage |  |
| T2 | 远古燃料箱 | 65 | +1 远程伤害<br>生成向周围缓慢发射10枚贯通雷电投射物的小伙伴，每枚投射物造成12 （+90%+90%）伤害<br>-4 %速度 | stat_ranged_damage, structure |  |
| T2 | 黄昏赌博筹码 | 40 | +13击退<br>每波结束时：永久 +1近战伤害 | knockback, stat_melee_damage |  |
| T2 | 远古花园 | 50 | -6 %敌人速度 | less_enemy_speed |  |
| T2 | 镀层冰块 | 30 | +3 护甲<br>-5 %速度 | stat_armor |  |
| T2 | 鹰眼干肉条 | 60 | +5 远程伤害<br>升级时：永久 +1最大生命值<br>升级时：永久 +7%敌人生命值 | stat_ranged_damage, stat_max_hp |  |
| T2 | 嗜血皮革背心 | 35 | +3 %生命窃取<br>静止时：获得「对头目和精英怪造成+38%伤害」<br>-2 护甲 | stat_lifesteal, stand_still, stat_percent_damage |  |
| T2 | 凶猛的小青蛙 | 40 | +6 %伤害<br>下场敌袭期间+15 %敌人速度 | stat_percent_damage | 核心 |
| T2 | 回响的肌肉小子 | 55 | +5 %闪避<br>每1%速度会+1%攻击速度 [+5] | stat_dodge, stat_attack_speed, stat_speed |  |
| T2 | 共鸣鱼饵  | 40 | 每永久持有2护甲会+1工程学 [+0]<br>-4 %闪避 | stat_engineering, stat_armor |  |
| T2 | 古怪的精湛技艺 | 50 | +3 近战伤害<br>使用工具类武器时+50%攻击速度<br>-10 %速度 | stat_melee_damage, stat_attack_speed |  |
| T2 | 远古勋章 | 55 | +7击退<br>敌袭开始时+12%材料（在第20波敌袭后结束）<br>-3 %伤害 | knockback |  |
| T2 | 恶毒的金属探测器 | 45 | +12 %暴击率<br>你的构筑物可以暴击 | stat_crit_chance, structure |  |
| T2 | 破晓金属板 | 40 | 下场敌袭期间+120 获得%经验<br>下场敌袭期间-14 最大生命值 | xp_gain |  |
| T2 | 共鸣导弹 | 35 | +1 工程学<br>+3 %暴击率<br>持有每一异种武器+1远程伤害 [+0] | stat_engineering, stat_crit_chance, stat_ranged_damage |  |
| T2 | 睿智的护垫 | 48 | +62 获得%经验<br>-25 范围 | xp_gain | 核心 |
| T2 | 觉醒珍珠 | 48 | +1 工程学<br>+5 范围<br>+2 %伤害<br>生命值全满时：获得「生命再生的修改增加50%」 | stat_engineering, stat_range, stat_percent_damage, stat_hp_regeneration |  |
| T2 | 囤积的猪猪存钱罐 | 40 | +2 最大生命值<br>+3 生命再生<br>拾取材料时：对随机敌人造成相当于 75% 护甲 的伤害<br>-3 %速度 | stat_max_hp, stat_hp_regeneration, pickup, stat_armor |  |
| T2 | 成长一堆书 | 50 | +9 收获<br>升级时：获得 15 材料 | stat_harvesting, economy |  |
| T2 | 夺命的南瓜 | 40 | +3 %暴击率<br>使用爆炸类武器时+10%伤害<br>-1 生命再生 | stat_crit_chance, stat_percent_damage |  |
| T2 | 寄生的回收装置 | 60 | +5 %生命窃取<br>受到伤害时：永久 +1生命再生（每波最多 1 次）<br>受到伤害时：永久 -1工程学（每波最多 1 次）<br>闪避时：本波 -3%攻击速度 | stat_lifesteal, stat_hp_regeneration |  |
| T2 | 丰满的强化钢 | 40 | +5 最大生命值<br>闪避时：回复 4 点生命<br>使用消耗品恢复-2HP | stat_max_hp, stat_dodge |  |
| T2 | 机械反击 | 40 | +3 工程学<br>生命值低于 50% 时：+105范围 | stat_engineering, stat_range |  |
| T2 | 精巧的仪式 | 30 | +5 工程学<br>闪避时：获得 12 经验<br>下场敌袭期间-14 最大生命值 | stat_engineering, stat_dodge, xp_gain |  |
| T2 | 狂乱的盐水 | 50 | +25 %攻击速度<br>每2%速度会-1%伤害 [-2] | stat_attack_speed | 核心 |
| T2 | 回响的瞄准镜 | 30 | +3 %暴击率<br>每永久持有2护甲会+1生命再生 [+0]<br>敌袭结束后+3%敌人生命值 | stat_crit_chance, stat_hp_regeneration, stat_armor |  |
| T2 | 锋利的阴影药水 | 55 | +7 %伤害<br>在箱子中有+15%的几率发现额外的道具 | stat_percent_damage |  |
| T2 | 离奇的小型弹匣 | 40 | +5 %爆炸范围<br>拾取箱子时：永久 +5范围 | explosive, stat_range, exploration |  |
| T2 | 猎杀蜗牛 | 50 | +5 %速度<br>+1 护甲<br>击杀敌人时（75%几率）：+1最大生命值，持续 5 秒<br>-4 工程学 | stat_speed, stat_armor, stat_max_hp |  |
| T2 | 完好的雪球 | 45 | +2 生命再生<br>+1 最大生命值<br>生命值全满时：获得「对头目和精英怪造成+36%伤害」 | stat_hp_regeneration, stat_max_hp, stat_percent_damage |  |
| T2 | 离奇的辣酱 | 40 | 商店免费刷新+1次 | economy |  |
| T2 | 赌徒的墨镜 | 40 | +2 工程学<br>刷新商店时：永久 +1%暴击率（每波最多 2 次）<br>-2 %伤害 | stat_engineering, stat_crit_chance |  |
| T2 | 嗜血触手 | 50 | +5 %生命窃取<br>升级时：引发爆炸，造成相当于 400% 幸运 的伤害<br>拾取消耗品时：本波 -1生命再生 | stat_lifesteal, explosive, stat_luck |  |
| T2 | 回响的藏宝图 | 40 | 每5远程伤害会+1%速度 [+0] | stat_speed, stat_ranged_damage |  |
| T2 | 奥术燃烧炮塔 | 48 | +2 元素伤害<br>+1 远程伤害<br>每波结束时：永久 +1%攻击速度<br>每波结束时：永久 -1%伤害<br>-7击退 | stat_elemental_damage, stat_ranged_damage, stat_attack_speed |  |
| T2 | 愈合的医疗炮塔 | 40 | +4 生命再生<br>+15 %构建物的攻击速度 | stat_hp_regeneration, structure |  |
| T2 | 强力的泰勒 | 40 | +15击退<br>拾取消耗品时：引发爆炸，造成相当于 100% 近战伤害 的伤害<br>-6 %伤害 | knockback, consumable, explosive, stat_melee_damage |  |
| T2 | 鹰眼独轮车 | 40 | +3 远程伤害<br>静止时：-10%攻击速度 | stat_ranged_damage | 核心 |
| T2 | 离奇的磨刀石 | 35 | +2 %速度<br>+2 生命再生<br>对燃烧目标造成非属性来源的+120%伤害<br>每击杀 11 个敌人：本波 -1生命再生 | stat_speed, stat_hp_regeneration, stat_elemental_damage |  |
| T2 | 美味的白旗 | 40 | 使用消耗品恢复+2HP<br>每 16 秒：本波 +1工程学<br>每 16 秒：本波 -2%闪避<br>移动时：-2工程学 | consumable, stat_engineering |  |
| T3 | 连发肾上腺素 | 70 | +21 %攻击速度<br>+2 远程伤害<br>+10 %暴击率<br>-15 %伤害 | stat_attack_speed, stat_ranged_damage, stat_crit_chance |  |
| T3 | 奇异的幼年异形 | 75 | +1 最大生命值<br>+3 %闪避<br>+2 %速度<br>对燃烧目标造成非属性来源的+160%伤害 | stat_max_hp, stat_dodge, stat_speed, stat_elemental_damage |  |
| T3 | 精炼的外星魔法 | 70 | +5 幸运<br>+5 %伤害<br>+3 %闪避<br>+5 %暴击率<br>+5 范围<br>%暴击率的修改增加50%<br>拾取消耗品时（95%几率）：本波 -1远程伤害（每波最多 10 次） | stat_luck, stat_percent_damage, stat_dodge, stat_crit_chance, stat_range |  |
| T3 | 共鸣合金 | 60 | +15 范围<br>每20材料会+1%攻击速度 [+1] | stat_range, stat_attack_speed, economy |  |
| T3 | 远古长胡子的婴儿 | 60 | +3 %伤害<br>+3 %攻击速度<br>下场敌袭期间+100 获得%经验<br>使用钝器类武器时+50％暴击伤害<br>-2 生命再生 | stat_percent_damage, stat_attack_speed, xp_gain, stat_crit_chance |  |
| T3 | 锋利的链球 | 85 | +8 %速度<br>+13 %伤害<br>武器和宠物伤害会受到10%元素伤害影响<br>-5 近战伤害 | stat_speed, stat_percent_damage, stat_elemental_damage |  |
| T3 | 远古头巾 | 70 | +23 获得%经验<br>+3 近战伤害<br>生成1台发射贯通弹的炮塔，造成20（+125%）伤害<br>移动时：+4工程学<br>移动时：+25%敌人生命值<br>-10 %攻击速度 | xp_gain, stat_melee_damage, structure, stat_engineering |  |
| T3 | 离奇的藤壶 | 70 | +3 工程学<br>+13% 敌人 | stat_engineering, more_enemies |  |
| T3 | 结实的路障 | 65 | +7 最大生命值<br>每持有一异种IV级别物品有+2护甲[+0] | stat_max_hp, stat_armor |  |
| T3 | 共鸣豆老师 | 70 | +7 最大生命值<br>每永久持有1远程伤害会+1%伤害 [+0]<br>-4 远程伤害 | stat_max_hp, stat_percent_damage, stat_ranged_damage |  |
| T3 | 处决黑旗 | 80 | +1 %生命窃取<br>每暴击击杀 5 个敌人：永久 +1%闪避（每波最多 2 次）<br>+5 诅咒<br>-2 工程学 | stat_lifesteal, stat_dodge, stat_crit_chance, stat_curse |  |
| T3 | 愈合的献血 | 65 | +5 生命再生<br>在下场敌袭中会出现4个额外的战利品外星人<br>移动时：-3工程学 | stat_hp_regeneration, economy |  |
| T3 | 滴答圆顶礼帽 | 70 | 使用消耗品恢复+2HP<br>+1 生命再生<br>每 15 秒：永久 +1护甲（每波最多 1 次）<br>刷新商店时（90%几率）：永久获得「每永久持有20%闪避会+5范围 [+0]」（每波最多 1 次） | consumable, stat_hp_regeneration, stat_armor, stat_dodge, stat_range |  |
| T3 | 生机蜡烛 | 70 | +3 生命再生<br>对燃烧目标造成非属性来源的+60%伤害<br>升级时：本波获得「+5%敌人掉落的材料」<br>-6 %伤害 | stat_hp_regeneration, stat_elemental_damage |  |
| T3 | 精炼的糖果袋 | 75 | %生命窃取的修改增加20%<br>使用精准类武器时+10%暴击率<br>受到伤害时（60%几率）：本波 -1%速度 | stat_lifesteal, stat_crit_chance |  |
| T3 | 狂乱的变色龙 | 70 | +38 %攻击速度<br>-13 %伤害 | stat_attack_speed | 核心 |
| T3 | 风暴三叶草 | 100 | +5 元素伤害<br>敌袭结束时，收获提高7%<br>闪避上限为70%<br>-5 护甲 | stat_elemental_damage, stat_harvesting |  |
| T3 | 回响的线圈 | 60 | +8 最大生命值<br>每持有1件武器+4%伤害 [+0]<br>每波开始时：永久获得「燃烧速度提高2%」<br>-10 %攻击速度 | stat_max_hp, stat_percent_damage, stat_elemental_damage |  |
| T3 | 增幅社区支持 | 65 | +8 最大生命值<br>护甲的修改增加50%<br>拾取消耗品时：本波 +5%敌人伤害 | stat_max_hp, stat_armor, consumable |  |
| T3 | 丰满的王冠 | 85 | +3 最大生命值<br>每波开始时：获得 33 经验<br>每波结束时：永久 +1幸运 | stat_max_hp, xp_gain, stat_luck |  |
| T3 | 神圣的水晶 | 65 | +2 最大生命值<br>恢复生命时（75%几率）：永久 +5范围（每波最多 1 次）<br>每暴击 2 次：对随机敌人造成相当于 25% 护甲 的伤害<br>每8击退会-1工程学 [+0] | stat_max_hp, stat_range, stat_crit_chance, stat_armor |  |
| T3 | 回响的小精灵 | 55 | +4 %闪避<br>+1 生命再生<br>每损失6%生命值，有+1%闪避[+5] | stat_dodge, stat_hp_regeneration |  |
| T3 | 远古鳍 | 75 | +1 远程伤害<br>使用原始类武器时+20%攻击速度<br>暴击击杀敌人时（35%几率）：引发爆炸，造成相当于 100% 元素伤害 的伤害 | stat_ranged_damage, stat_attack_speed, explosive, stat_crit_chance, stat_elemental_damage |  |
| T3 | 离奇的炒饭 | 55 | 对燃烧目标造成非属性来源的+40%伤害<br>-5 范围 | stat_elemental_damage |  |
| T3 | 精炼的冰冻的心 | 75 | +2 最大生命值<br>%伤害的修改增加33%<br>敌袭结束后+1%敌人速度 | stat_max_hp, stat_percent_damage |  |
| T3 | 收成幽灵服 | 60 | +55 收获<br>每持有1件武器-2近战伤害 [+0] | stat_harvesting | 核心 |
| T3 | 回响的玻璃大炮 | 60 | +3 工程学<br>每永久持有5近战伤害会+1远程伤害 [+0] | stat_engineering, stat_ranged_damage, stat_melee_damage |  |
| T3 | 奇异的高脚杯 | 65 | +1 工程学<br>+1 远程伤害<br>+3 %暴击率<br>使用枪械类武器时+100范围 | stat_engineering, stat_ranged_damage, stat_crit_chance, stat_range |  |
| T3 | 回响的金鱼 | 75 | 每永久持有5%速度会+1远程伤害 [+1]<br>每永久持有3护甲会-5范围 [+0] | stat_ranged_damage, stat_speed |  |
| T3 | 常青的手铐 | 70 | +4 生命再生<br>下场敌袭期间+110 获得%经验<br>-3 %速度 | stat_hp_regeneration, xp_gain |  |
| T3 | 坚毅的蜂蜜 | 60 | +4 护甲<br>+2 %攻击速度<br>在敌人攻击波结束时，每有1个活着的敌人，你获得0.55个材料和经验值。<br>移动时：+10%伤害<br>移动时：+29%敌人伤害<br>-6 最大生命值 | stat_armor, stat_attack_speed, economy, stat_percent_damage |  |
| T3 | 常青的狩猎战利品 | 60 | +11 生命再生<br>使用枪械类武器时+2贯通<br>-14 %伤害 | stat_hp_regeneration, stat_ranged_damage |  |
| T3 | 吸血鬼的改进工具 | 75 | +8 %生命窃取<br>每波结束时：获得 60 经验<br>-5 生命再生 | stat_lifesteal, xp_gain |  |
| T3 | 精炼的水母盾 | 80 | +7 %暴击率<br>近战伤害的修改增加40% | stat_crit_chance, stat_melee_damage |  |
| T3 | 律动的结 | 75 | +2 工程学<br>每 7 秒：引发爆炸，造成相当于 75% 幸运 的伤害 | stat_engineering, explosive, stat_luck |  |
| T3 | 急切的灯塔 | 70 | +3 最大生命值<br>+2 生命再生<br>+1 工程学<br>每首次用元素伤害命中 11 个敌人：永久 +1近战伤害（每波最多 2 次）<br>每60材料会-5范围 [-2] | stat_max_hp, stat_hp_regeneration, stat_engineering, stat_melee_damage, stat_elemental_damage |  |
| T3 | 鹰眼护身符 | 70 | +4 远程伤害<br>-6 %速度 | stat_ranged_damage | 核心 |
| T3 | 锋利的镜子 | 70 | +13 %伤害<br>暴击击杀敌人时：回复 1 点生命<br>-10 %速度 | stat_percent_damage, stat_crit_chance |  |
| T3 | 灼烧的老鼠 | 80 | +8 %速度<br>+6 %暴击率<br>击杀燃烧中的敌人时：获得 3 经验<br>-4 工程学 | stat_speed, stat_crit_chance, stat_elemental_damage, xp_gain |  |
| T3 | 共鸣钉子 | 60 | +2 最大生命值<br>+3 %闪避<br>+1 护甲<br>每持有1件武器+2%暴击率 [+0]<br>敌袭结束后+5%敌人生命值 | stat_max_hp, stat_dodge, stat_armor, stat_crit_chance |  |
| T3 | 离奇的孔雀 | 65 | +4 工程学<br>使用虚灵类武器时+25%暴击率 | stat_engineering, stat_crit_chance |  |
| T3 | 锐利的塑性炸药 | 70 | +25 %伤害<br>-7 最大生命值 | stat_percent_damage | 核心 |
| T3 | 远古毒性补品 | 65 | 武器和宠物伤害会受到20%工程学影响<br>使用重型类武器时+5伤害<br>-9 %攻击速度 | stat_engineering |  |
| T3 | 凶猛的发电机 | 65 | +10 %伤害<br>每引发 2 次爆炸：对随机敌人造成相当于 150% 范围 的伤害 | stat_percent_damage, explosive, stat_range |  |
| T3 | 回响的狂怒 | 80 | +3 生命再生<br>+2 最大生命值<br>+3 %攻击速度<br>每50材料会+1最大生命值 [+0]<br>使用消耗品恢复-3HP | stat_hp_regeneration, stat_max_hp, stat_attack_speed, economy |  |
| T3 | 睿智的悲伤的番茄 | 65 | +87 获得%经验<br>-40 范围 | xp_gain | 核心 |
| T3 | 修补匠的围巾 | 75 | +18 工程学<br>每 12 秒：本波 -5%伤害 | stat_engineering | 核心 |
| T3 | 回响的镣铐 | 65 | +4 生命再生<br>每永久持有2%生命窃取会+1近战伤害 [+0] | stat_hp_regeneration, stat_melee_damage, stat_lifesteal |  |
| T3 | 离奇的休穆糖 | 75 | +5 生命再生<br>生成1台发射贯通弹的炮塔，造成20（+125%）伤害<br>%伤害的修改减少40% | stat_hp_regeneration, structure |  |
| T3 | 丰满的银质子弹 | 50 | +3 最大生命值<br>闪避时：回复 2 点生命<br>在下场敌袭中会出现1个额外的战利品外星人<br>下场敌袭期间-13 %攻击速度<br>-7击退 | stat_max_hp, stat_dodge, economy |  |
| T3 | 炽热的海星 | 80 | +4 元素伤害<br>下场敌袭期间-35 %伤害 | stat_elemental_damage | 核心 |
| T3 | 急切的雕像 | 75 | +6 收获<br>首次用远程伤害命中敌人时（50%几率）：回复 1 点生命 | stat_harvesting, stat_ranged_damage |  |
| T3 | 赌徒的石头皮肤 | 75 | +2 近战伤害<br>刷新商店时：获得 8 材料<br>每波敌袭有10%几率额外生成一个精英 | stat_melee_damage, economy |  |
| T3 | 猎杀奇怪之书 | 50 | +1 %暴击率<br>+5 %攻击速度<br>击杀敌人时（25%几率）：获得 3 经验 | stat_crit_chance, stat_attack_speed, xp_gain |  |
| T3 | 暴食的沉钟 | 65 | +7 %伤害<br>拾取消耗品时：+3远程伤害，持续 8 秒<br>-4 工程学 | stat_percent_damage, stat_ranged_damage, consumable |  |
| T3 | 沉重的水熊虫 | 60 | +17 近战伤害<br>-7 最大生命值 | stat_melee_damage | 核心 |
| T3 | 易爆的工具箱 | 80 | +10 %爆炸伤害<br>升级时：引发爆炸，造成相当于 400% 远程伤害 的伤害<br>下场敌袭期间+105 获得%经验<br>下场敌袭期间-22 %速度<br>%速度的修改减少25% | explosive, stat_ranged_damage, xp_gain |  |
| T3 | 厚重的拖拉机 | 85 | +5 最大生命值<br>击杀敌人时（95%几率）：+1生命再生，持续 3 秒 | stat_max_hp, stat_hp_regeneration |  |
| T3 | 猎杀三角之力 | 75 | +10 %伤害<br>每击杀 3 个敌人：引发爆炸，造成相当于 75% 元素伤害 的伤害 | stat_percent_damage, explosive, stat_elemental_damage |  |
| T3 | 滴答激光炮塔 | 90 | +6击退<br>+1 远程伤害<br>每 10 秒：+5近战伤害，持续 6 秒<br>每 10 秒：+10%敌人伤害，持续 6 秒<br>下场敌袭期间+106 获得%经验<br>下场敌袭期间+50 %敌人伤害<br>-4 %伤害 | knockback, stat_ranged_damage, stat_melee_damage, xp_gain |  |
| T3 | 丰饶的义警戒指 | 75 | +22 收获<br>每波结束时：永久获得「敌袭开始时+3%材料（在第20波敌袭后结束）」 | stat_harvesting |  |
| T3 | 奇异的流浪机器人 | 50 | +6 最大生命值<br>每次敌袭中，当你生命值低于40%时，你会爆炸并造成100（+500%+500%+500%+500%）伤害<br>-12 %速度 | stat_max_hp, explosive |  |
| T3 | 愈合的士兵头盔 | 75 | +9 生命再生<br>使用枪械类武器时+100范围<br>-11 %伤害 | stat_hp_regeneration, stat_range |  |
| T3 | 奇异的小麦 | 75 | +13 收获<br>从等级提升中获得+25%属性 | stat_harvesting |  |
| T3 | 被眷顾的鬼火 | 55 | +9 幸运<br>每暴击击杀 3 个敌人：永久获得「+1 %构建物的攻击速度」（每波最多 4 次）<br>-1 最大生命值 | stat_luck, stat_crit_chance, structure |  |
| T3 | 回响的翅膀 | 80 | +1 元素伤害<br>+3 最大生命值<br>+3 %速度<br>每永久持有2%速度会+1生命再生 [+2] | stat_elemental_damage, stat_max_hp, stat_speed, stat_hp_regeneration |  |
| T3 | 共鸣智慧 | 80 | +30 范围<br>每6材料会+1%攻击速度 [+5]<br>-18 %速度 | stat_range, stat_attack_speed, economy |  |
| T4 | 沉重的铁砧 | 100 | +10 近战伤害<br>持有每一异种武器+3最大生命值 [+0]<br>-10 %闪避 | stat_melee_damage, stat_max_hp |  |
| T4 | 离奇的灰烬 | 110 | +19击退<br>+8 近战伤害<br>生成1台发射爆破弹的炮塔，造成25（+150%）范围伤害 | knockback, stat_melee_damage, structure |  |
| T4 | 常青的巨臂 | 100 | +13 生命再生<br>+19 %暴击率<br>+55 范围<br>-32 %伤害 | stat_hp_regeneration, stat_crit_chance, stat_range |  |
| T4 | 共鸣血淋淋的手 | 105 | +2 护甲<br>+1 %速度<br>每10最大生命值会+1护甲 [+1]<br>-4 最大生命值 | stat_armor, stat_speed, stat_max_hp |  |
| T4 | 迅捷斗篷 | 90 | +9 %速度<br>+37 获得%经验<br>暴击击杀敌人时：本波获得「对头目和精英怪造成+1%伤害」<br>-5 护甲 | stat_speed, xp_gain, stat_crit_chance, stat_percent_damage |  |
| T4 | 幻影执照 | 100 | +17 %闪避<br>-5 生命再生 | stat_dodge |  |
| T4 | 愈合的Esty的沙发 | 100 | +13 生命再生<br>升级时：本波 +12最大生命值<br>升级时：本波 -8%生命窃取 | stat_hp_regeneration, stat_max_hp |  |
| T4 | 共鸣吞吞怪之帽 | 110 | +10 范围<br>每损失2%生命值，有+1%速度[+16]<br>-8 %伤害 | stat_range, stat_speed |  |
| T4 | 致命外骨骼 | 100 | +14 %暴击率<br>+20 范围<br>+2 工程学<br>拾取消耗品时：永久获得「+1%贯通伤害，不会高于基础伤害」（每波最多 16 次）<br>-5 远程伤害 | stat_crit_chance, stat_range, stat_engineering, consumable |  |
| T4 | 坚毅的爆裂弹 | 110 | +3 %闪避<br>+4 最大生命值<br>+3 护甲<br>受到伤害时：引发爆炸，造成相当于 400% 生命再生 的伤害<br>-10 %攻击速度 | stat_dodge, stat_max_hp, stat_armor, explosive, stat_hp_regeneration |  |
| T4 | 野蛮的另一个胃 | 100 | +3 远程伤害<br>+13 近战伤害<br>+3 元素伤害<br>闪避时：永久 +1%伤害（每波最多 9 次）<br>闪避时：永久 -1%闪避（每波最多 9 次）<br>下场敌袭以1点生命值开始 | stat_ranged_damage, stat_melee_damage, stat_elemental_damage, stat_percent_damage, stat_dodge |  |
| T4 | 充能的焦点 | 100 | +5 最大生命值<br>闪避时（70%几率）：本波获得「投射物贯通1个额外目标」<br>受到伤害时：本波 -4%攻击速度（每波最多 10 次） | stat_max_hp, stat_dodge |  |
| T4 | 远古巨型带 | 110 | 生成1台发射爆破弹的炮塔，造成25（+150%）范围伤害<br>-11 %伤害 | structure |  |
| T4 | 远古地精 | 100 | +1 %伤害<br>生成一个替罪羔羊宠物，绕着地图移动并取代玩家被敌人攻击。当其死亡时，玩家可以站在它身边将其复活<br>-7 最大生命值 | stat_percent_damage, pet |  |
| T4 | 厚重的希腊火 | 100 | +5 最大生命值<br>每首次用元素伤害命中 4 个敌人：回复 1 点生命 | stat_max_hp, stat_elemental_damage |  |
| T4 | 增幅Grind的魔法绿叶 | 90 | +20 获得%经验<br>+2 护甲<br>最大生命值的修改增加50%<br>-13 幸运 | xp_gain, stat_armor, stat_max_hp |  |
| T4 | 古怪的重型子弹 | 100 | +4 %暴击率<br>+2 远程伤害<br>+2 近战伤害<br>生成一个替罪羔羊宠物，绕着地图移动并取代玩家被敌人攻击。当其死亡时，玩家可以站在它身边将其复活<br>-5 护甲 | stat_crit_chance, stat_ranged_damage, stat_melee_damage, pet |  |
| T4 | 回响的沙漏 | 100 | +30 幸运<br>+17 %暴击率<br>每持有1件武器+3工程学 [+0]<br>-5 远程伤害 | stat_luck, stat_crit_chance, stat_engineering |  |
| T4 | 愈合的喷气背包 | 110 | +12 生命再生<br>每波结束时：永久 +3%速度 | stat_hp_regeneration, stat_speed |  |
| T4 | 精准克拉肯的眼睛 | 100 | +6 远程伤害<br>升级时：永久 +1消耗性治疗<br>+15 诅咒<br>%伤害的修改减少50% | stat_ranged_damage, consumable, stat_curse |  |
| T4 | 坚毅的灯笼 | 110 | +5 护甲<br>+10 最大生命值<br>刷新商店时：永久 +1%闪避（每波最多 6 次）<br>-5 %生命窃取 | stat_armor, stat_max_hp, stat_dodge |  |
| T4 | 回响的幸运硬币 | 110 | +29 %伤害<br>每永久持有1%闪避会+1工程学 [+0]<br>敌袭结束后+5%敌人速度 | stat_percent_damage, stat_engineering, stat_dodge |  |
| T4 | 贪婪的猛犸 | 100 | +11 %伤害<br>+23 幸运<br>+10 工程学<br>拾取材料时：引发爆炸，造成相当于 100% 近战伤害 的伤害<br>击杀敌人时（60%几率）：本波 -1%闪避 | stat_percent_damage, stat_luck, stat_engineering, explosive, pickup, stat_melee_damage |  |
| T4 | 丰满的急救包 | 105 | +19 最大生命值<br>+4击退<br>+1 生命再生<br>生成1台发射爆破弹的炮塔，造成25（+150%）范围伤害 | stat_max_hp, knockback, stat_hp_regeneration, structure |  |
| T4 | 回响的夜视镜 | 90 | +10 %速度<br>每1%速度会+2%暴击率 [+10]<br>-5 护甲 | stat_speed, stat_crit_chance |  |
| T4 | 修补匠的章鱼 | 105 | +25 工程学<br>+3 元素伤害<br>+2 %攻击速度<br>拾取消耗品时：本波获得「每4远程伤害会+3幸运 [+0]」<br>-7 最大生命值 | stat_engineering, stat_elemental_damage, stat_attack_speed, consumable, stat_ranged_damage, stat_luck |  |
| T4 | 奇异的熊猫 | 100 | +7 %速度<br>有+100%概率立即吸收掉落的材料<br>-10 %攻击速度 | stat_speed, pickup |  |
| T4 | 远古土豆 | 110 | +2 最大生命值<br>+3 生命再生<br>有+100%概率立即吸收掉落的材料 | stat_max_hp, stat_hp_regeneration, pickup |  |
| T4 | 远古再生药水 | 90 | +2 元素伤害<br>将时间倒回，将当前波次减少1（生效后此条效果消失）<br>-10 %暴击率 | stat_elemental_damage |  |
| T4 | 结实的Retromation的连帽衫 | 105 | +14 最大生命值<br>每击杀 16 个敌人：永久获得「商店免费刷新+1次」（每波最多 2 次）<br>下场敌袭以1点生命值开始 | stat_max_hp, economy |  |
| T4 | 离奇的跳弹 | 110 | +19击退<br>+4 元素伤害<br>生成1台发射爆破弹的炮塔，造成25（+150%）范围伤害 | knockback, stat_elemental_damage, structure |  |
| T4 | 美味的机械臂 | 110 | 使用消耗品恢复+5HP<br>+9击退<br>+2 %生命窃取<br>每击杀 2 个敌人：回复 1 点生命<br>拾取消耗品时：本波 -2%生命窃取（每波最多 10 次） | consumable, knockback, stat_lifesteal |  |
| T4 | 回响的替罪羔羊 | 110 | +34 %伤害<br>每损失1%生命值，有+1%闪避[+33]<br>%攻击速度的修改减少50% | stat_percent_damage, stat_dodge |  |
| T4 | 沉重的海贝壳 | 110 | +25 近战伤害<br>+14击退<br>+11 %攻击速度<br>每秒受到1伤害（不给予无敌时间） | stat_melee_damage, knockback, stat_attack_speed |  |
| T4 | 厚重的Sifd的圣物 | 100 | +10 最大生命值<br>+5 %生命窃取<br>生命值全满时：+13元素伤害<br>生命值全满时：+32%敌人速度 | stat_max_hp, stat_lifesteal, stat_elemental_damage |  |
| T4 | 律动的蜘蛛 | 90 | +5 %速度<br>每 12 秒：对随机敌人造成相当于 400% 最大生命值 的伤害 | stat_speed, stat_max_hp |  |
| T4 | 急切的拷问 | 100 | +3 %攻击速度<br>+1 护甲<br>+2 %伤害<br>首次用工程学命中敌人时：该敌人受到的伤害提高 30%，持续 4 秒<br>敌袭结束后+3%敌人伤害 | stat_attack_speed, stat_armor, stat_percent_damage, stat_engineering |  |
| T4 | 幻影爆炸炮塔 | 100 | +19 %攻击速度<br>+15 %闪避<br>+35 幸运<br>%闪避的修改增加50%<br>-32 %伤害 | stat_attack_speed, stat_dodge, stat_luck |  |
| T4 | 闪身的野狼头盔 | 80 | +5 护甲<br>+19 %攻击速度<br>闪避时：永久 +1%生命窃取（每波最多 5 次）<br>闪避时：永久 -3%伤害（每波最多 5 次）<br>下场敌袭以1点生命值开始 | stat_armor, stat_attack_speed, stat_lifesteal, stat_dodge |  |
