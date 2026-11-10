# BetterCodex - Better In-Game Codex / 更好的游戏内图鉴

[CHANGELOG / 更新日志](CHANGELOG.md)

[English](#english) | [中文](#中文) | [Screenshots](#screenshots) | [截图](#截图)

> modid: Mojimoon-BetterCodex

## English

**For Brotato 1.2 (incl. Primal Dread and the 1.2.0.2 beta).**

**Everything from the [web codex](https://brotato.mojimoon.top/) — filters, curse / mecha / mutation previews, actual attack speed, price calculator — right inside the game.** All numbers come from the game's own calculations, so they stay correct when the game changes them.

### Features

**Codex list**

- **Badges** on every entry: base price (top left), item limit (top right; red = unique, orange = limited) and source (bottom right: the colored item set icon, or the meca part / mutation fruit icon for Primal Dread's meca and mutant items). Each badge can be turned off in Settings.
- **Search and filters**: rarity, item tag, source (base game / DLC / update), special (fossils, meca items, mutant items); for weapons: type (melee / ranged), class and source. Long lists open as a compact grid.
- In a run, **items banned for P1 are greyed out** (the character's banned items and the ones banned with ban tokens).

**Details**

- **Clickable links** under the name: item tags and weapon classes filter the list. "Unique / Limited (X) / Structure" replace the original category line.
- **Related items** (Hourglass, Goldfish, Dino Egg → Ammosaurus …): click to jump.
- **Curse preview** (10–110 %): the description shows the cursed item. In a run, the bar highlights the range this wave can roll and starts at its median.
- **Mecha preview** for weapons (power 1–80).
- **Mutation preview**: which effects can be copied (already scaled) and which negative effects can be removed. Below the threshold (67 / 40 depending on the game version) it shows "Mutation too low (X/threshold)" and the effects that unlock at the threshold. Cursed items cannot be mutated: their effects can still be copied (with cursed values) but nothing is removed.
- **Attack speed calculator**: actual average cooldown with the frame range, reload and equivalent cooldown, DPS change and attack speed breakpoints, for any attack speed, range and number of weapons. The weapon stats always show the **actual** cooldown instead of the tooltip value.
- **Price calculator**: price at any wave, with or without Nightmare inflation, plus the current actual price in a run.
- In a run, mutation, attack speed, range, weapon count, wave and difficulty start at your current values; the mutation preview is already on when a mutation fruit can drop.

**Character info on weapon / difficulty selection**

- Preferred tags, banned items and a mutation preview for the selected character. Clicking a tag or a banned item opens the codex with a matching filter.

**Shop**

- **Right-click** a shop item or one of your weapons / items (or hover it and press **C**, gamepad **R3**) to open it in the codex. Owned cursed / meca items open with their actual strength.
- When a mutation fruit can drop, every item and character description ends with a **mutation preview**. When it can't, the hint in the bottom-left corner shows how many uncursed items are still missing (x/3).

**Settings** (the Settings button in the codex)

- Toggle each badge, change the shop hotkey, **unlock the whole codex without touching your save**, open the codex without its animation (on by default), hide the shop hint, turn off right-click in the shop (only the hotkey then; right-clicks are left untouched for other mods).

**Faster codex**: the codex is built in the background and reused while nothing changes, so it usually opens in about 10 ms.

Supports all 13 game languages. All added text follows the game's font size setting.

### Compatibility

- Tested with **ImprovedTooltips**, **ItemRefund** and **BroEditor**. The item popup itself is not modified.
- Known issue (not caused by this mod): **DebugMenu 1.2.0 + ImprovedTooltips** together crash when entering the shop, because DebugMenu preloads its menu scene too early. Loading the menu with `load()` when it is opened fixes it.

## 中文

**适用于土豆兄弟 1.2（含史前惧兽 DLC 与 1.2.0.2 测试版）。**

**把[网页图鉴](https://brotato.mojimoon.top/)的功能搬进游戏：筛选、诅咒 / 机械化 / 异变预览、实际攻速、价格计算。** 数值都直接调用游戏自身的计算，游戏调整数值后也不会过时。

### 功能

**图鉴列表**

- **角标**：基础价格（左上）、数量上限（右上；红色为独特，橙色为限制）、来源（右下：物品套组的彩色图标，史前惧兽的机械 / 异变道具显示机械部件 / 异变果图标）。每种角标都可以在设置里关掉。
- **搜索与筛选**：稀有度、道具标签、来源（本体 / DLC / 更新）、特殊（化石、机械道具、异变道具）；武器为类型（近战 / 远程）、武器类别、来源。长列表以网格弹出。
- 局内打开时，**P1 被禁用的道具会变灰**（角色自带禁用和消耗禁用次数禁掉的）。

**详情**

- 名字下方是**可点击的链接**：道具标签、武器类别，点击即筛选；“独特的 / 限制 (X) / 构筑物”代替原来的类别文字。
- **关联内容**（沙漏、金鱼、恐龙蛋 → 弹药恐龙……）：点击跳转。
- **诅咒预览**（10–110%）：描述直接显示诅咒后的物品。局内会在滑条上高亮本波可能出现的强度范围，默认取中位数。
- 武器的**机械化预览**（强度 1–80）。
- **异变预览**：可被复制的效果（已按异变缩放）与可被清除的负面效果。低于阈值时（按游戏版本为 67 / 40）显示“异变不足 (X/阈值)”和到阈值才能复制的效果。诅咒道具不能被异变：效果仍可被复制（按诅咒后的数值），但不会被清除。
- **攻速计算器**：任意攻速、范围、武器数量下的实际平均冷却与帧数范围、换弹与等效冷却、DPS 变化和攻速断点。武器属性里的冷却也总是显示**实际冷却**，而不是游戏提示里的值。
- **价格计算**：任意波次、是否噩梦的价格，局内另外显示当前实际价格。
- 局内打开时，异变、攻速、范围、武器数量、波次、难度默认取当前值；可掉落异变果时异变预览默认打开。

**武器 / 难度选择界面的角色信息**

- 当前角色的偏好标签、禁用道具和异变预览；点击标签或禁用道具，打开图鉴并显示对应的筛选。

**商店**

- **右键**商品或已有的武器 / 道具（或悬停后按 **C**，手柄 **R3**），在图鉴里打开它；已有的诅咒 / 机械化物品按实际强度预览。
- 可掉落异变果时，每个道具和角色的描述末尾都有**异变预览**；不可掉落时，左下角提示还差几个未诅咒道具（x/3）。

**设置**（图鉴里的“设置”按钮）

- 分别开关各种角标、修改商店快捷键、**解锁全部图鉴（不修改存档）**、快速打开图鉴（跳过动画，默认开启）、隐藏商店提示、关掉商店里的右键打开（只用快捷键，右键完全留给其他 mod）。

**更快的图鉴**：图鉴会在后台预先构建，内容不变时直接复用，通常约 10 毫秒就能打开。

支持游戏的全部 13 种语言，新增的文字都跟随设置里的字体大小。

### 兼容性

- 与 **ImprovedTooltips**、**ItemRefund**、**BroEditor** 一起测试过；不修改物品弹窗本身。
- 已知问题（与本 mod 无关）：**DebugMenu 1.2.0 与 ImprovedTooltips** 同时加载时，进入商店会崩溃，原因是 DebugMenu 过早预加载了它的菜单场景；改为打开菜单时再 `load()` 即可。

## Screenshots

Mutation preview in the shop / 商店里的异变预览

![](../img/BetterCodex/bc-en-1.jpg)

Filters, badges and the price calculator / 筛选、角标与价格计算

![](../img/BetterCodex/bc-en-2.jpg)

Mutation: copyable and removable effects / 异变：可复制与可清除的效果

![](../img/BetterCodex/bc-en-3.jpg)

Related items and the mutation threshold / 关联内容与异变阈值

![](../img/BetterCodex/bc-en-4.jpg)

Mecha preview and the attack speed calculator / 机械化预览与攻速计算器

![](../img/BetterCodex/bc-en-5.jpg)

## 截图

![](../img/BetterCodex/bc-zh-1.jpg)

![](../img/BetterCodex/bc-zh-2.jpg)

![](../img/BetterCodex/bc-zh-3.jpg)

![](../img/BetterCodex/bc-zh-4.jpg)

![](../img/BetterCodex/bc-zh-5.jpg)

## Development / 开发

- Tests: `bash mods/tests/BetterCodex/run_tests.sh` (normal); `compat` also loads ImprovedTooltips (3019195689) and ItemRefund (3834897339). Set `BROTATO_GAME` to test against another decompiled game version.
- Screenshots: `godot --path 1.2 -s res://mods/tests/BetterCodex/shot.gd` (`BC_SHOT_DIR`, `BC_SHOT_FONT`).
- Pack: `python mods/tools/pack_mod.py BetterCodex "D:\SteamLibrary\steamapps\workshop\content\1942280\3671094202"`.
- Translations: `translations/bettercodex.csv` (13 languages, hand-edited).
