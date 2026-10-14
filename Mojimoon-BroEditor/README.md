# BroEditor - Universal Visual Editor / 万能可视化编辑器

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817655214) | [Open in Steam Client](https://link.steam.watch/url/CommunityFilePage/3817655214) | [CHANGELOG / 更新日志](CHANGELOG.md)

[English](#english) | [中文](#中文) | [Screenshots](#screenshots) | [截图](#截图)

> modid: Mojimoon-BroEditor

![](../img/BroEditor/be-icon.png)

## English

**Edit any character, item or weapon, or create your own — all with in-game visual editor. No coding required.**

### Features

- **Three tabs: Characters / Items / Weapons**, each with a master switch to turn all its changes on or off.
- **Stats**: starting stats and stat modifiers for characters; price, rarity, limit and tags for items; damage, cooldown, crit, range, projectiles, scaling and more for weapons.
- **Effects**: add any effect from every vanilla character, item and weapon, then tweak its values; drag to reorder.
- **Blueprint**: build your own effects as *trigger → condition → effect* node graphs.
- **Characters**: starting state (materials, levels, crates, starting wave…), starting weapons and items, **GMO (character fusion)**, banned items and weapons.
- **Create new** characters, items and weapons from any vanilla one, then DIY whatever you want. Choose an icon or import your own.
- **Disable** characters, items and weapons.
- **Share** with a code (one object, a whole tab, or everything), or by sending the object's file (see below).
- Dependency free, supports all 13 game languages, compatible with all mod objects.

Heartfelt thanks to [BroLab](https://steamcommunity.com/sharedfiles/filedetails/?id=3145676266) and [Modtools](https://steamcommunity.com/sharedfiles/filedetails/?id=3672826836) for the inspiration! This mod is also compatible with their features.

### How to use

Click **BroEditor** in the top-left corner of the character, weapon or difficulty selection screen. The interface should be self-explanatory, but if you need help, click **Help** in the top-right corner.

About the buttons in the top-right corner:

- **Import**: Import a code from the clipboard to load a project, character, item, weapon or everything.
- **Export**: Export a code for the current object (BE0:), all characters (BEC:), all items (BEI:), all weapons (BEW:) or everything (BEA:). Different types have different formats, and the mod will automatically detect the type when importing from clipboard.
- **Help**: a how-to guide for the current tab (characters, items or weapons).
- **Settings**:
  - **Font Size**: 80–125%, scales the editor's text.
  - **Effect Library Dedup**: effects with the same keys but different values count as one in the Effect Library.
  - **Hide Numbers**: by default, custom objects using vanilla icons show a number in the bottom-right corner to tell them apart. Enable this option to hide it.
  - **Show Keys**: show the key names of all stats, effects, item tags and weapon types for easy searching.
  - **Detailed Keys**: requires Show Keys. Effects show all their keys (`key (text_key) / custom_key`), and field names are shown when editing effects.

### Files

Files are saved in `%APPDATA%\Brotato\Mojimoon-BroEditor\` (Windows), `~/Library/Application Support/Brotato/Mojimoon-BroEditor/` (Mac) or `~/.local/share/Brotato/Mojimoon-BroEditor/` (Linux):

- `profiles.json`: changes to vanilla characters, items and weapons, and the editor settings.
- `custom\character\`, `custom\item\`, `custom\weapon\`: one `<id>.json` file per character, item or weapon you created. To share, send the files or a whole folder; the receiver puts them in the same folder and restarts the game.
- `icons\`: imported icon images. Send them along with the file if your object uses one.

<!-- BBCode

[pullquote]Edit any character, item or weapon, or create your own — all with in-game visual editor. No coding required.[/pullquote]

[h1]Features[/h1]

[list]
[*][b]Three tabs[/b]: Characters / Items / Weapons, each with a master switch to turn all its changes on or off.
[*][b]Stats[/b]: starting stats and stat modifiers for characters; price, rarity, limit and tags for items; damage, cooldown, crit, range, projectiles, scaling and more for weapons.
[*][b]Effects[/b]: add any effect from every vanilla character, item and weapon, then tweak its values; drag to reorder.
[*][b]Blueprint[/b]: build your own effects as *trigger → condition → effect* node graphs.
[*][b]Characters[/b]: starting state (materials, levels, crates, starting wave…), starting weapons and items, [b]GMO (character fusion)[/b], banned items and weapons.
[*][b]Create new[/b] characters, items and weapons from any vanilla one, then DIY whatever you want. Choose an icon or import your own.
[*][b]Disable[/b] characters, items and weapons.
[*][b]Share[/b] with a code (one object, a whole tab, or everything), or by sending the object's file (see below).
[*]Dependency free, supports all 13 game languages, compatible with all mod objects.
[/list]

Heartfelt thanks to [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3145676266]BroLab[/url] and [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3672826836]Modtools[/url] for the inspiration! This mod is also compatible with their features.

[h1]How to use[/h1]

Click [b]BroEditor[/b] in the top-left corner of the character, weapon or difficulty selection screen. The interface should be self-explanatory, but if you need help, click [b]Help[/b] in the top-right corner.

About the buttons in the top-right corner:

[list]
[*][b]Import / Export[/b]: export a code for the current object (BE0:), all characters (BEC:), all items (BEI:), all weapons (BEW:) or everything (BEA:). Different types have different formats, and the mod will automatically detect the type when importing from clipboard.
[*][b]Help[/b]: a how-to guide for the current tab (characters, items or weapons).
[*][b]Settings[/b]:
[list]
[*][b]Font Size[/b]: 80–125%, scales the editor's text.
[*][b]Effect Library Dedup[/b]: effects with the same keys but different values count as one in the Effect Library.
[*][b]Hide Numbers[/b]: by default, custom objects using vanilla icons show a number in the bottom-right corner to tell them apart. Enable this option to hide it.
[*][b]Show Keys[/b]: show the key names of all stats, effects, item tags and weapon types for easy searching.
[*][b]Detailed Keys[/b]: requires Show Keys. Effects show all their keys ([i]key (text_key) / custom_key[/i]), and field names are shown when editing effects.
[/list]
[/list]

[h1]Files[/h1]

Files are saved in [i]%APPDATA%\Brotato\Mojimoon-BroEditor\[/i] (Windows), [i]~/Library/Application Support/Brotato/Mojimoon-BroEditor/[/i] (Mac) or [i]~/.local/share/Brotato/Mojimoon-BroEditor/[/i] (Linux):

[list]
[*][i]profiles.json[/i]: changes to vanilla characters, items and weapons, and the editor settings.
[*][i]custom\character\[/i], [i]custom\item\[/i], [i]custom\weapon\[/i]: one [i]<id>.json[/i] file per character, item or weapon you created. To share, send the files or a whole folder; the receiver puts them in the same folder and restarts the game.
[*][i]icons\[/i]: imported icon images. Send them along with the file if your object uses one.
[/list]

[pullquote]If you like this mod, please consider liking, favoriting and sharing it, thank you! Comments and suggestions are also very welcome![/pullquote]

GitHub repo: [url=https://github.com/mojimoon/BrotatoMods]mojimoon/BrotatoMods[/url]

-->

### Screenshots

![](../img/BroEditor/be-en-1.jpg)

![](../img/BroEditor/be-en-2.jpg)

![](../img/BroEditor/be-en-3.jpg)

![](../img/BroEditor/be-en-4.jpg)

![](../img/BroEditor/be-en-5.jpg)

![](../img/BroEditor/be-en-6.jpg)

![](../img/BroEditor/be-en-7.jpg)

---

## 中文

**修改原版角色、道具、武器，或者原创一个——都能在游戏中可视化编辑，无需代码。**

### 功能

- **分三页：角色 / 道具 / 武器**，每页都有一个总开关，可一键启用或禁用当前页的全部修改。
- **属性**：角色的初始属性与属性修改%；道具的价格、稀有度、数量限制、标签；武器的伤害、冷却、暴击、范围、投射物、属性加成等……一切都能随心修改。
- **效果**：从全部原版角色、道具、武器的效果库中任选添加并修改数值和参数，拖动调整顺序。
- **蓝图**：用"触发 → 条件 → 效果"的节点图，组合出成千上万种效果。
- **角色**：开局状态（材料、等级、箱子、起始波次……）、初始武器与道具、**GMO (角色融合)**、禁用道具与武器。
- **新建**角色、道具、武器：以任意原版对象为基底，尽情 DIY。可选图标或导入图片。
- **禁用**角色、道具和武器。
- **分享**：可以导入、导出分享码（当前项目 / 角色 / 道具 / 武器 / 全部），或以文件形式分享（见下）。
- 免依赖，支持全部 13 种语言，兼容所有 mod 内容。

万分感谢 [BroLab](https://steamcommunity.com/sharedfiles/filedetails/?id=3145676266) 和 [Modtools](https://steamcommunity.com/sharedfiles/filedetails/?id=3672826836) 提供的灵感！本 mod 也兼容它们的功能。

### 使用

在角色、武器或难度选择界面左上角点击 **BroEditor**。界面简单明了，如果有不懂的，可以点击右上角 **帮助**。

关于右上角的按钮：

- **导入 / 导出**：导出当前项目 (BE0:)、角色 (BEC:)、道具 (BEI:)、武器 (BEW:) 或全部 (BEA:) 的分享码。不同类型的格式不同，从剪贴版导入时会自动识别。
- **帮助**：显示当前栏（角色、道具或武器）的操作指南。
- **设置**：
  - **字体大小**：80–125%，控制 BroEditor 的文字大小。
  - **效果库去重**：效果库中同键名不同数值的效果视为同一条。
  - **隐藏编号**：默认情况下，使用原版图标自定义的内容右下角会显示一个编号，方便区分。启用时隐藏编号。
  - **显示键名**：显示所有属性、效果、道具标签、武器类型的内部键名 (key)，方便查找。
  - **更详细键名**：需要先开启显示键名。效果显示全部键名（`key (text_key) / custom_key`），编辑效果时额外显示字段名。

### 文件

文件保存在 `%APPDATA%\Brotato\Mojimoon-BroEditor\` (Windows)、`~/Library/Application Support/Brotato/Mojimoon-BroEditor/` (Mac) 或 `~/.local/share/Brotato/Mojimoon-BroEditor/` (Linux)：

- `profiles.json`：对原版角色、道具、武器的修改，以及编辑器设置。
- `custom\character\`、`custom\item\`、`custom\weapon\`：每个新建的角色、道具、武器各一个 `<id>.json` 文件。分享时发送文件或整个文件夹，对方放进相同的文件夹后重启游戏即可。
- `icons\`：导入的图标图片。如果对象用了导入的图标，一并发送。

<!-- BBCode

[pullquote]修改原版角色、道具、武器，或者原创一个——都能在游戏中可视化编辑，无需代码。[/pullquote]

[h1]功能[/h1]

[list]
[*][b]分三页：角色 / 道具 / 武器[/b]，每页都有一个总开关，可一键启用或禁用当前页的全部修改。
[*][b]属性[/b]：角色的初始属性与属性修改%；道具的价格、稀有度、数量限制、标签；武器的伤害、冷却、暴击、范围、投射物、属性加成等……一切都能随心修改。
[*][b]效果[/b]：从全部原版角色、道具、武器的效果库中任选添加并修改数值和参数，拖动调整顺序。
[*][b]蓝图[/b]：用"触发 → 条件 → 效果"的节点图，组合出成千上万种效果。
[*][b]角色[/b]：开局状态（材料、等级、箱子、起始波次……）、初始武器与道具、[b]GMO (角色融合)[/b]、禁用道具与武器。
[*][b]新建[/b]角色、道具、武器：以任意原版对象为基底，尽情 DIY。可选图标或导入图片。
[*][b]禁用[/b]角色、道具和武器。
[*][b]分享[/b]：可以导入、导出分享码（当前项目 / 角色 / 道具 / 武器 / 全部），或以文件形式分享（见下）。
[*]免依赖，支持全部 13 种语言，兼容所有 mod 内容。
[/list]

万分感谢 [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3145676266]BroLab[/url] 和 [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3672826836]Modtools[/url] 提供的灵感！本 mod 也兼容它们的功能。

[h1]使用[/h1]

在角色、武器或难度选择界面左上角点击 [b]BroEditor[/b]。界面简单明了，如果有不懂的，可以点击右上角 [b]帮助[/b]。关于右上角的按钮：

[list]
[*][b]导入 / 导出[/b]：导出当前项目 (BE0:)、角色 (BEC:)、道具 (BEI:)、武器 (BEW:) 或全部 (BEA:) 的分享码。不同类型的格式不同，从剪贴版导入时会自动识别。
[*][b]帮助[/b]：显示当前栏（角色、道具或武器）的操作指南。
[*][b]设置[/b]：
[list]
[*][b]字体大小[/b]：80–125%，控制 BroEditor 的文字大小。
[*][b]效果库去重[/b]：效果库中同键名不同数值的效果视为同一条。
[*][b]隐藏编号[/b]：默认情况下，使用原版图标自定义的内容右下角会显示一个编号，方便区分。启用时隐藏编号。
[*][b]显示键名[/b]：显示所有属性、效果、道具标签、武器类型的内部键名 (key)，方便查找。
[*][b]更详细键名[/b]：需要先开启显示键名。效果显示全部键名（[i]key (text_key) / custom_key[/i]），编辑效果时额外显示字段名。
[/list]
[/list]

[h1]文件[/h1]

文件保存在 [i]%APPDATA%\Brotato\Mojimoon-BroEditor\[/i] (Windows)、[i]~/Library/Application Support/Brotato/Mojimoon-BroEditor/[/i] (Mac) 或 [i]~/.local/share/Brotato/Mojimoon-BroEditor/[/i] (Linux)：

[list]
[*][i]profiles.json[/i]：对原版角色、道具、武器的修改，以及编辑器设置。
[*][i]custom\character\[/i]、[i]custom\item\[/i]、[i]custom\weapon\[/i]：每个新建的角色、道具、武器各一个 [i]<id>.json[/i] 文件。分享时发送文件或整个文件夹，对方放进相同的文件夹后重启游戏即可。
[*][i]icons\[/i]：导入的图标图片。如果对象用了导入的图标，一并发送。
[/list]

[pullquote]如果你喜欢这个 mod，欢迎点赞、收藏、转发，多谢啦！有问题或建议欢迎在评论区留言！[/pullquote]

GitHub 仓库：[url=https://github.com/mojimoon/BrotatoMods]mojimoon/BrotatoMods[/url]

-->

### 截图

![](../img/BroEditor/be-zh-1.jpg)

![](../img/BroEditor/be-zh-2.jpg)

![](../img/BroEditor/be-zh-3.jpg)

![](../img/BroEditor/be-zh-4.jpg)

![](../img/BroEditor/be-zh-5.jpg)

![](../img/BroEditor/be-zh-6.jpg)

![](../img/BroEditor/be-zh-7.jpg)

<!--

BroEditor 多功能可视化编辑器现已上线！

修改原版角色、道具、武器，或者原创一个——都能在游戏中可视化编辑，无需代码。

- 能改：角色、道具、武器。每个 Tab 都有总开关，每个对象均可单独启用或禁用。
- 什么都能改：属性、开局状态、初始武器与道具、禁用列表、价格、稀有度、数量限制、标签；武器的伤害、冷却、投射物、属性加成，每个等级分别调整。
- 效果库：全部原版角色、道具、武器的效果任选添加，再细调数值和参数。
- 蓝图：如果原版效果还满足不了你，可以用"触发 → 条件 → 效果"的节点图组合效果，二十多种触发、十几种条件，末端接任意效果。
- 自定义内容：以任意原版对象为基底，新建角色、道具和整套武器家族；可选图标或导入自己的图片。还能给原版武器补上缺少的低级版本。
- 一键分享：以分享码或文件形式分享单个对象、整页或全部内容，或者单独一张蓝图。
- 免依赖，支持游戏全部 13 种语言，兼容 BroLab 与 Modtools。

--->