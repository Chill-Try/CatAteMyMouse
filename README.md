# CatAteMyMouse

一组 AutoHotkey v2 脚本，覆盖窗口切换、透明度控制和控件聚焦等常用桌面操作。

## 脚本

- `AltTab.ahk`：自定义 Alt+Tab 窗口切换界面。
- `AltEsc.ahk`：在当前窗口内切换文本框焦点。
- `DynamicWindowTransparency.ahk`：根据当前激活窗口自动调整透明度。
- `Ghoster_V2.ahk`：对非活动窗口做透明/暗化处理，并支持模式切换。

## 依赖

- AutoHotkey v2.0
- `Lib/UIA.ahk`（`AltEsc.ahk` 使用）

## 使用

直接用 AutoHotkey v2 运行对应 `.ahk` 文件即可。各脚本顶部都提供了配置项，按需调整后再运行。

## 目录

- `Lib/`：共享库文件
- `*.ahk`：脚本本体
- `*.log`：运行日志，不纳入版本控制
