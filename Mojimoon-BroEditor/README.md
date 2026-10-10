# BroEditor

> Character, item & weapon editor for Brotato / 土豆兄弟角色、道具、武器编辑器

Edit any character, item or weapon in Brotato, or create your own — all in-game, no coding.

### Features

- **Three tabs: Characters / Items / Weapons**, each with a master switch to turn all its changes on or off.
- **Stats**: starting stats and stat modifiers for characters; price, rarity, limit and tags for items; damage, cooldown, crit, range, projectiles, scaling and more for weapons (every tier).
- **Effects**: add any effect from every vanilla character, item and weapon, then tweak its values; drag to reorder.
- **Blueprint**: build your own effects as *trigger → condition → effect* node graphs.
- **Characters**: starting state (materials, levels, crates, starting wave…), starting weapons and items, banned items and weapons.
- **Create new** characters, items and weapons from any vanilla one; pick or import an icon.
- **Disable** characters (they can no longer be picked), items and weapons (they no longer show up).
- **Share** with a code (one object, a whole tab, or everything), or by sending the object's file (see below).
- All 13 game languages. Works with BroLab and Modtools.

### How to use

Click **BroEditor** in the top-left corner of the character, weapon or difficulty selection screen.

### Files

Everything is saved in `%APPDATA%\Brotato\Mojimoon-BroEditor\`:

- `profiles.json`: changes to vanilla characters, items and weapons, and the editor settings.
- `custom\<id>.json`: one file per character, item or weapon you created. To share one, send the file; the receiver puts it in their own `custom\` folder and restarts the game.
- `icons\`: imported icon images. Send them along with the file if your object uses one.

<!-- BBCode

Edit any character, item or weapon in Brotato, or create your own — all in-game, no coding.

[h1]Features[/h1]

[list]
[*][b]Three tabs: Characters / Items / Weapons[/b], each with a master switch to turn all its changes on or off.
[*][b]Stats[/b]: starting stats and stat modifiers for characters; price, rarity, limit and tags for items; damage, cooldown, crit, range, projectiles, scaling and more for weapons (every tier).
[*][b]Effects[/b]: add any effect from every vanilla character, item and weapon, then tweak its values; drag to reorder.
[*][b]Blueprint[/b]: build your own effects as [i]trigger → condition → effect[/i] node graphs.
[*][b]Characters[/b]: starting state (materials, levels, crates, starting wave…), starting weapons and items, banned items and weapons.
[*][b]Create new[/b] characters, items and weapons from any vanilla one; pick or import an icon.
[*][b]Disable[/b] characters (they can no longer be picked), items and weapons (they no longer show up).
[*][b]Share[/b] with a code (one object, a whole tab, or everything), or by sending the object's file (see below).
[*]All 13 game languages. Works with BroLab and Modtools.
[/list]

[h1]How to use[/h1]

Click [b]BroEditor[/b] in the top-left corner of the character, weapon or difficulty selection screen.

[h1]Files[/h1]

Everything is saved in [code]%APPDATA%\Brotato\Mojimoon-BroEditor\[/code]:

[list]
[*][code]profiles.json[/code]: changes to vanilla characters, items and weapons, and the editor settings.
[*][code]custom\<id>.json[/code]: one file per character, item or weapon you created. To share one, send the file; the receiver puts it in their own [code]custom\[/code] folder and restarts the game.
[*][code]icons\[/code]: imported icon images. Send them along with the file if your object uses one.
[/list]

-->

---

在游戏里直接修改任意角色、道具、武器，或者新建自己的，不用写代码。

### 功能

- **角色 / 道具 / 武器三栏**，每栏一个总开关，可一键启用或停用该栏的全部修改。
- **属性**：角色的初始属性与属性修改；道具的价格、稀有度、数量限制、标签；武器的伤害、冷却、暴击、范围、投射物、属性加成等（每个等级分别设置）。
- **效果**：从全部原版角色、道具、武器的效果中任选添加并修改数值，拖动调整顺序。
- **蓝图**：用"触发 → 条件 → 效果"的节点图自己组合效果。
- **角色专属**：开局状态（材料、等级、箱子、起始波次……）、初始武器与道具、禁用道具与武器。
- **新建**角色、道具、武器：以任意原版对象为基底，可选图标或导入图片。
- **禁用**角色（不能再选）、道具和武器（不再出现）。
- **分享**：分享码（当前对象 / 一整栏 / 全部），或者直接发送对象的文件（见下）。
- 支持游戏全部 13 种语言；兼容 BroLab 与 Modtools。

### 使用

在角色、武器或难度选择界面左上角点击 **BroEditor**。

### 文件

全部保存在 `%APPDATA%\Brotato\Mojimoon-BroEditor\`：

- `profiles.json`：对原版角色、道具、武器的修改，以及编辑器设置。
- `custom\<id>.json`：每个新建的角色、道具、武器各一个文件。分享时发送这个文件，对方放进自己的 `custom\` 文件夹后重启游戏即可。
- `icons\`：导入的图标图片。如果对象用了导入的图标，一并发送。

<!-- BBCode

在游戏里直接修改任意角色、道具、武器，或者新建自己的，不用写代码。

[h1]功能[/h1]

[list]
[*][b]角色 / 道具 / 武器三栏[/b]，每栏一个总开关，可一键启用或停用该栏的全部修改。
[*][b]属性[/b]：角色的初始属性与属性修改；道具的价格、稀有度、数量限制、标签；武器的伤害、冷却、暴击、范围、投射物、属性加成等（每个等级分别设置）。
[*][b]效果[/b]：从全部原版角色、道具、武器的效果中任选添加并修改数值，拖动调整顺序。
[*][b]蓝图[/b]：用"触发 → 条件 → 效果"的节点图自己组合效果。
[*][b]角色专属[/b]：开局状态（材料、等级、箱子、起始波次……）、初始武器与道具、禁用道具与武器。
[*][b]新建[/b]角色、道具、武器：以任意原版对象为基底，可选图标或导入图片。
[*][b]禁用[/b]角色（不能再选）、道具和武器（不再出现）。
[*][b]分享[/b]：分享码（当前对象 / 一整栏 / 全部），或者直接发送对象的文件（见下）。
[*]支持游戏全部 13 种语言；兼容 BroLab 与 Modtools。
[/list]

[h1]使用[/h1]

在角色、武器或难度选择界面左上角点击 [b]BroEditor[/b]。

[h1]文件[/h1]

全部保存在 [code]%APPDATA%\Brotato\Mojimoon-BroEditor\[/code]：

[list]
[*][code]profiles.json[/code]：对原版角色、道具、武器的修改，以及编辑器设置。
[*][code]custom\<id>.json[/code]：每个新建的角色、道具、武器各一个文件。分享时发送这个文件，对方放进自己的 [code]custom\[/code] 文件夹后重启游戏即可。
[*][code]icons\[/code]：导入的图标图片。如果对象用了导入的图标，一并发送。
[/list]

-->
