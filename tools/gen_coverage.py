# 用法：python mods/tools/gen_coverage.py <godot 测试日志> <输出 COVERAGE.md>
import sys,collections,re
log=open(sys.argv[1],encoding='utf8',errors='replace').read().splitlines()
rows=[l.split('|',5) for l in log if l.startswith('COVER|')]
H=collections.OrderedDict((t[0],(t[1],t[2])) for t in [
 ('trigger','拆解为 (扳机, 载荷) 先验，由通用触发条款重新表达','单位价值 × 每波频率（见 README 第 4 节）'),
 ('scaling','计数 × 属性自由搭配重新生成（原版 GainStatForEveryStatEffect）','目标属性权重 × 数值 × 计数期望 / 每 N；计数期望由原版道具校准'),
 ('next_wave','下一波（芹菜茶 / 孔雀）：一次性，下一波开始时生效；约一半附带同一行为下的负面行（敌人属性或自身属性降低）','一波的价值 = 整局价值 / 剩余波数（≈ 2 × 永久累积倍率 − 1）；孔雀校准吻合'),
 ('gain_mod','属性修改 ±XX% 重新生成（原版 StatGainsModificationEffect）','属性权重 × 属性期望总量 × XX%'),
 ('scalar','原样搬运，并按预算缩放数值（1 单位 .. 原版 1.5 倍）','来源道具剩余价值按数值比例折算'),
 ('mechanic','原样搬运（炮台、宠物、爆炸、武器类加成……）','道具：来源道具 (预算 − 属性行价值) / 机制数；角色：(角色总价值 − 可估值部分) / 机制数，限制 30–80'),
 ('downside','作为代价搬运','来源道具因它多拿到的正面预算（至少 3）'),
 ('weapon_counter','武器数量计数（常规池）："每把 [不同 / 所有 / IV 级 / I 级] 武器 +X [属性]"，属性与数值重新生成','属性权重 × 数值 × 计数期望（不同武器 3.5 / 武器 5 / IV 级 1 / I 级 1.2）'),
 ('char_component','角色效果（常规池）：武器类型加成、对燃烧目标额外伤害、和平主义者、+武器栏','按原版角色数值与对应属性 / 材料估值'),
 ('char_more','更多角色效果（选项开启时进入道具池）：构筑物聚集、升级所需经验 ±、神秘生物（每棵存活的树）、几率魅惑、宠物伤害缩放、地图大小 ±、自身价格 −100%、武器价格 −X%、道具价格 +X%（代价）','升级所需经验按反比例（等价获得经验）；地图大小价值约为 0；其余按材料 / 经验 / 伤害估值'),
 ('char_beta','全部角色效果（BETA 选项）：一击必死、移动时无法攻击、进店摧毁武器、无法回血、武器等级 / 类型 / 数量限制、毒果、精英变强、无法锁定、无法拥有构筑物（代价，高补偿）；所有武器计入套装、商店至少一把武器、升级获得武器栏、每店偷 1 件、商店总是出售某道具 + 每有 1 个该道具获得属性','限制按固定补偿（3–45 材料，大代价只出现在高预算道具上）；正面按武器栏 / 商店价值估值；设定值型效果所在道具为独特'),
 ('identity','保留在角色上，不进入道具池（武器限制、初始装备、商店规则、负向机制……）','—'),
 ('anchored','建造者炮台的角色专属效果：不作为组件来源','—'),
 ('text','纯描述行：需要的说明已合并进对应效果的同一行（“生效后此道具消失”“受到伤害时清空”），其余为音效 / 已用状态的提示','—'),
 ('excluded','迷雾视野：只在迷雾事件中有意义，不搬运','—'),
 ('weapon','武器专属效果：仅在“重组武器”时于同类型武器家族间整套交换','按等级对齐，不单独估值'),
])
out=['# 原版效果覆盖表','',
'本表由测试 `test_80_native_effect_coverage` 遍历原版全部道具、角色、武器自动生成，列出每一种**非纯属性增减**效果在东尼算法中的处理方式。纯属性行（22 种属性）统一按价格回归的权重重组，不在此列。','',
'## 处理方式','','| 处理 | 含义 | 估值 |','| --- | --- | --- |']
cnt=collections.Counter(r[2] for r in rows)
for k,(desc,val) in H.items():
    out.append('| `%s`（%d 种） | %s | %s |'%(k,cnt.get(k,0),desc,val))
out+=['','## 明细','']
for k in H:
    rs=[r for r in rows if r[2]==k]
    if not rs: continue
    out+=['### `%s`'%k,'','| 效果 key | 次数 | 来源 | 示例 |','| --- | --- | --- | --- |']
    for r in sorted(rs,key=lambda x:x[1]):
        ex=r[5].replace('|','/').replace('[color=white]','').replace('[/color]','')
        import re
        ex=re.sub(r'\[img=[^\]]*\][^\[]*\[/img\]','',ex)
        out.append('| `%s` | %s | %s | %s |'%(r[1],r[3],r[4],ex))
    out.append('')
open(sys.argv[2],'w',encoding='utf8',newline='\n').write('\n'.join(out)+'\n')
print(len(rows))
