# 更好的下指/小零食mod

在《影之刃零》里使用《黑暗之魂 3》风格的粪块、附绳粪便壶和武器附魔。音效版会在投掷物离手和实际碰撞时播放不同的声音。适配 Steam Build 26367565，使用 Windows 版 UE4SS。

从 [Releases](https://github.com/zangielfwin-gif/PhantomBladeZero-DungPie-Mod/releases/latest) 下载一键安装 ZIP 并完整解压。退出游戏后双击 `Install_Mod.cmd` 安装或升级。需要卸载时，退出游戏并双击 `Uninstall_Mod.cmd`。详细步骤见 [中文说明](使用说明.txt)。

| 按键 | 操作 |
| --- | --- |
| O | 打开或关闭动作菜单，方向键选择，Enter 执行 |
| O + 0 | 切换中英文，默认中文 |
| F6 | 开关下指时的螺旋粪块，默认开启，下次下指生效 |
| F8 | 切换人松脂、火松脂和粪便附魔 |
| F9 / F10 | 分别开关普通粪块和附绳粪便壶的出手烟雾 |
| F7 | 开关本 Mod 的中毒外观和掉血 |
| Backspace | 关闭菜单，或取消当前动作并清除附魔 |

动作菜单位于屏幕中央。下指期间可用 WASD 或手柄左摇杆原地转向。下指时八块粪块会依次绕角色螺旋下落，碰撞后飞溅。普通粪块和附绳粪便壶合计成功投出五次会触发中毒。
安装整合版前请先卸载独立下指版。

## 源码和构建

`src/main.lua` 负责动作、投掷、特效和音效触发。`src/PBZThrowAudio.cpp` 通过 Windows XAudio2 播放音效。`installer` 是安装、卸载与备份脚本。

在仓库根目录打开 **x64 Native Tools Command Prompt for Visual Studio**。准备 Python 3、带 Windows SDK 的 MSVC、[vgmstream CLI](https://github.com/vgmstream/vgmstream/releases)，以及本地《黑暗之魂 3》的 `Game/sound/fdp_main.fsb`。以下命令的路径按实际位置替换。

```bat
py tools\prepare-waves.py "D:\Games\DARK SOULS III\Game\sound\fdp_main.fsb" "D:\Tools\vgmstream\vgmstream-cli.exe"
py tools\build-audio.py
py tools\repack.py "D:\Downloads\Better_PointDown_Snacks_AutoInstall.zip" --dll build\native\PBZThrowAudio.dll
```

重打包以整合版 Release 的安装包为基底，复用预先烘焙的动画、模型、菜单资源和 UE4SS 文件。省略 `--dll` 时沿用随包音效 DLL。菜单的 Unreal 5.7 编辑器生成脚本为 `tools/build-action-menu.py`。输出位于 `dist`。

人松脂和火松脂来自 wdsjjszr 的 [PR #1](https://github.com/zangielfwin-gif/PhantomBladeZero-DungPie-Mod/pull/1)。下指动画资源来自 [独立下指 Mod](https://github.com/le258o/PhantomBladeZero-PointingDown-Mod)，原动作为《艾尔登法环》下指。

## 许可与素材

Mod 自行编写的代码和构建脚本采用 [MIT 许可证](LICENSE)。《黑暗之魂 3》的动画、模型和音频，以及《影之刃零》的游戏素材，沿用各自权利归属。安装包包含可选的 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)，其许可证随安装包附带。
