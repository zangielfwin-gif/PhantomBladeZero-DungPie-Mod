# 影之刃零 · 粪便投掷与武器附魔

在《影之刃零》里使用《黑暗之魂 3》风格的粪块、附绳粪便壶和武器附魔。音效版会在投掷物离手和实际碰撞时播放不同的声音。适配 Steam Build 26367565，使用 Windows 版 UE4SS。

从 [Releases](https://github.com/zangielfwin-gif/PhantomBladeZero-DungPie-Mod/releases/latest) 下载音效版 ZIP 并完整解压。退出游戏后双击 `Install_Mod.cmd` 安装或升级。需要卸载时，退出游戏并双击 `Uninstall_Mod.cmd`。详细步骤见 [中文说明](使用说明.txt)。

| 按键 | 操作 |
| --- | --- |
| F8 | 主武器出鞘时施放附魔，持续 60 秒 |
| F8 + 0 | 在人松脂、火松脂、粪便之间切换 |
| F9 | 向前投掷普通粪块 |
| F10 | 向后投掷附绳粪便壶 |
| F9 + 0 / F10 + 0 | 分别开关两种投掷的出手烟雾 |
| F7 + 0 | 开关投掷触发的中毒掉血，默认开启 |
| Backspace | 取消当前动作并清除武器附魔 |

F9 和 F10 合计每成功投出五次，触发一次中毒外观。组合键可以按住数字 0，再点按对应的 F 键。

## 源码和构建

`src/main.lua` 负责动作、投掷、特效和音效触发。`src/PBZThrowAudio.cpp` 通过 Windows XAudio2 播放音效。`installer` 是安装、卸载与备份脚本。

在仓库根目录打开 **x64 Native Tools Command Prompt for Visual Studio**。准备 Python 3、带 Windows SDK 的 MSVC、[vgmstream CLI](https://github.com/vgmstream/vgmstream/releases)，以及本地《黑暗之魂 3》的 `Game/sound/fdp_main.fsb`。以下命令的路径按实际位置替换。

```bat
py tools\prepare-waves.py "D:\Games\DARK SOULS III\Game\sound\fdp_main.fsb" "D:\Tools\vgmstream\vgmstream-cli.exe"
py tools\build-audio.py
py tools\repack.py "D:\Downloads\PBZ_Dung_Pie_Mod_20261105_Audio_AutoInstall.zip"
```

重打包以 Release 的安装包为基底，复用其中预先烘焙的动画、模型和 UE4SS 安装文件，替换 Mod 的 Lua、音效 DLL、安装器和说明。输出位于 `dist`。

## 许可与素材

Mod 自行编写的代码和构建脚本采用 [MIT 许可证](LICENSE)。《黑暗之魂 3》的动画、模型和音频，以及《影之刃零》的游戏素材，沿用各自权利归属。安装包包含可选的 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)，其许可证随安装包附带。
