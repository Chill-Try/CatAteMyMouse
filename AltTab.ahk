#Requires AutoHotkey v2.0
DetectHiddenWindows true

; 使用不可见按键屏蔽 Alt 热键释放后的系统菜单激活
A_MenuMaskKey := "vkE8"

; =====================================================
; 配置区域
; =====================================================

; Alt+Tab 前台窗口最大显示数
MaxForegroundWindows := 3

; Alt+Tab 后台窗口最大显示数
MaxBackgroundWindows := 2

; 后台列表是否显示最小化到托盘的程序
ShowTrayBackgroundWindows := false

; 后台窗口按 MRU 排序后置底（false 表示和前台窗口一起按 MRU 排序）
BackgroundWindowsAlwaysAtBottom := true

; 窗口预览时是否隐藏其它普通窗口，仅保留箭头指向窗口和桌面背景
PreviewOnlySelectedWindow := false

; UI 字体大小
UIFontSize := 18

; UI 行间距
UIRowGap := 8

; UI 进程图标大小（像素）
UIIconSize := 24

; 第二列程序名最大列宽（像素）
MaxProcessColumnWidth := 300

; 第三列标题列宽（像素）
TitleColumnWidth := 380

; UI 程序别名映射：原名 -> 显示名（键不区分大小写）
ProcessAliasMap := Map(
    "voicemeeterpro_x64",   "VoiceMeeter",
    "Code",                 "VSCode",
    "SteamWebHelper",       "Steam",
    "Explorer",             "文件夹",
    "ChatGPT",              "GPT",
    "RainbowSix",           "R6",
    "Editor",               "EQ APO",
)

; 是否启用 Alt+数字快捷启动
EnableQuickLaunch := true

; Alt+数字 快捷程序映射
QuickPrograms := Map(
    1, "explorer.exe",
    2, "chrome.exe",
    3, "code.exe",
    4, "chatgpt.exe",
)

; Alt+数字 启动器覆盖：用于 exe 名字无法直接启动的应用
QuickProgramLaunchers := Map(
    "chatgpt.exe", "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
)

; 黑名单 — 不列入切换列表的进程
Blacklist := [
    "ApplicationFrameHost.exe",
    "SearchHost.exe",
    "TextInputHost.exe",
    "ShellExperienceHost.exe",
    "PowerDimmer.exe",
    "SpookyView_1.1.0_x64_Portable.exe",
    "AutoHotkey64.exe",
]

; 白名单 — 即使未曾作为前台窗口记录，也允许作为后台窗口列入
BackgroundProcessAllowlist := [
    "HeSuVi.exe",
]

; 白名单 — 允许 owned window 作为真实应用窗口列入
OwnedWindowProcessAllowlist := [
    "HeSuVi.exe",
]

; 黑名单 — 不作为应用主窗口处理的辅助窗口类
ClassBlacklist := [
    "Progman",
    "WorkerW",
    "Shell_TrayWnd",
    "IME",
    "MSCTFIME UI",
    "GDI+ Hook Window Class",
    "Chrome_WidgetWin_0",
    "Chrome_StatusTrayWindow",
    "Base_PowerMessageWindow",
    "crashpad_SessionEndWatcher",
    "OwlElectron_NotifyIconHostWindow",
    "tray_icon_app",
    "global_hotkey_app",
    "Tao Thread Event Target",
    "OleDdeWndClass",
    "AutoHotkey",
    "CiceroUIWndFrame",
    ".NET-BroadcastEventWindow.5c39d4.0",
]

; 黑名单 — 动态类名前缀
ClassPrefixBlacklist := [
    "HwndWrapper[PowerDimmer;;",
    "WindowsForms10.Window.0.app.0.5c39d4",
    "WindowsForms10.Window.808.app.0.5c39d4",
]

; ; 自定义快捷键，Ctrl+Shift+S 关屏幕
; ^+s::
; {
;     DllCall("SendMessage", "ptr", 0xFFFF, "uint", 0x0112, "ptr", 0xF170, "ptr", 2)
; }

; =====================================================
; 全局状态
; =====================================================

WindowHistory := []          ; 窗口 HWND 列表（MRU 顺序：索引 1 为最近）
ForegroundProcessSeen := Map() ; 曾经作为前台窗口出现过的进程
DisplayWindows := []         ; 当前 UI 实际显示的 HWND 列表
DisplayWindowWasBackground := Map() ; 切换开始时每个 UI 窗口是否为后台/最小化
Switching := false           ; 是否正在切换中
Index := 1                   ; 当前选中序号
GuiObj := ""                 ; GUI 对象引用
ForegroundProcessControls := [] ; GUI 前台进程名控件列表
BackgroundProcessControls := [] ; GUI 后台进程名控件列表
IconControls := []           ; GUI 进程图标控件列表
TitleControls := []          ; GUI 标题控件列表
ArrowControls := []          ; GUI 箭头控件列表
QuickProgramLastHwnd := Map() ; Alt+数字 多窗口轮转位置
QuickProgramWindowOrder := Map() ; Alt+数字 每个程序的稳定窗口顺序
QuickProgramHistoryFocus := Map() ; Alt+数字 激活后，同进程只保留目标窗口进入 Alt+Tab 队列
QuickProgramShortcutCache := Map() ; exe 名 -> 开始菜单快捷方式路径
PreviewZOrder := []            ; 进入 Alt+Tab 时普通窗口 Z 序快照
PreviewTransparentWindows := Map() ; 预览独占模式下被临时透明的窗口
PreviewShownMinimizedWindows := Map() ; 预览时被临时无激活显示的最小化窗口
PreviewCurrentHwnd := 0        ; 当前预览窗口

; =====================================================
; 窗口枚举 — WinAPI EnumWindows
; =====================================================

; 每 500ms 后台扫描新窗口，追加到历史末尾
SetTimer(UpdateWindowHistory, 500)

; 启动后预创建窗口列表 GUI，首次 Alt+Tab 时只需要填充文本
SetTimer(PreCreateListGui, -100)

UpdateWindowHistory()
{
    global WindowHistory, ForegroundProcessSeen, Switching
    ; Alt 按住期间冻结列表，避免 UI 和 MRU 在切换中跳动
    if (Switching)
        return

    ; 外部打开/切换窗口时，也把当前活动窗口提升到 MRU 最前
    activeHwnd := WinExist("A")
    if (activeHwnd && IsAltTabCandidate(activeHwnd, false))
    {
        MarkForegroundProcessSeen(activeHwnd)
        UpdateQuickProgramHistoryFocus(activeHwnd)
        PromoteWindow(activeHwnd)
    }

    windows := EnumWindowsList(false)

    ; 只记录当前可见前台窗口；后台窗口必须先作为前台出现过
    for hwnd in windows
    {
        if (ShouldSkipQuickProgramHistoryWindow(hwnd))
            continue
        dup := false
        for h in WindowHistory
        {
            if (h = hwnd)
            {
                dup := true
                break
            }
        }
        if (!dup)
            WindowHistory.Push(hwnd)
        MarkForegroundProcessSeen(hwnd)
    }

    ; 安全移除已关闭或不再适合 Alt-Tab 的窗口
    RemoveInvalidWindows()

    ; 历史上限 60 条
    while (WindowHistory.Length > 60)
        WindowHistory.RemoveAt(61)
}

MarkForegroundProcessSeen(hwnd)
{
    global ForegroundProcessSeen

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return

    if (exe != "")
        ForegroundProcessSeen[exe] := true
}

; 如果用户手动切到同程序其它窗口，把 Alt+数字保留目标同步为当前窗口
UpdateQuickProgramHistoryFocus(hwnd)
{
    global QuickProgramHistoryFocus

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return

    if (QuickProgramHistoryFocus.Has(exe))
        QuickProgramHistoryFocus[exe] := hwnd
}

; Alt+数字轮转过的程序，在 Alt+Tab 队列中只保留最后目标窗口
ShouldSkipQuickProgramHistoryWindow(hwnd)
{
    global QuickProgramHistoryFocus

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return false

    if (!QuickProgramHistoryFocus.Has(exe))
        return false

    focusedHwnd := QuickProgramHistoryFocus[exe]
    if (!DllCall("user32\IsWindow", "ptr", focusedHwnd))
    {
        QuickProgramHistoryFocus.Delete(exe)
        return false
    }

    return hwnd != focusedHwnd
}

; 调用 EnumWindows 遍历顶级窗口，返回筛选后的 HWND 列表
EnumWindowsList(allowBackground := false)
{
    result := []

    callback(hwnd, lParam)
    {
        if (IsAltTabCandidate(hwnd, allowBackground))
            result.Push(hwnd)
        return true
    }

    cb := CallbackCreate(callback)
    DllCall("user32\EnumWindows", "ptr", cb, "ptr", 0)
    CallbackFree(cb)

    return result
}

; 判断窗口是否应出现在自定义 Alt-Tab 列表
IsAltTabCandidate(hwnd, allowBackground := false)
{
    global Blacklist, ShowTrayBackgroundWindows

    if (!WinExist("ahk_id " hwnd))
        return false

    visible := DllCall("user32\IsWindowVisible", "ptr", hwnd)
    iconic := DllCall("user32\IsIconic", "ptr", hwnd)

    ; 后台窗口仅在调用方明确允许时保留；最小化到托盘常见为隐藏但非最小化。
    if ((!visible || iconic) && !allowBackground)
        return false
    if (!visible && !iconic && !ShowTrayBackgroundWindows)
        return false
    isSeenTrayWindow := allowBackground && ShowTrayBackgroundWindows
        && !visible && !iconic && IsSeenForegroundProcess(hwnd)

    try
        title := WinGetTitle("ahk_id " hwnd)
    catch
        return false
    if (title = "")
        return false

    try
    {
        cls := WinGetClass("ahk_id " hwnd)
        if (IsBlacklistedClass(cls))
            return false
    }

    ; 先读窗口样式，过滤工具窗、免激活窗口和从属窗口。
    exStyle := DllCall("user32\GetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr")
    hasToolWindow := (exStyle & 0x80) != 0
    hasAppWindow := (exStyle & 0x40000) != 0
    hasNoActivate := (exStyle & 0x08000000) != 0
    owner := DllCall("user32\GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
    if (!isSeenTrayWindow && ((hasToolWindow && !hasAppWindow) || hasNoActivate || (owner && !hasAppWindow && !IsOwnedWindowProcessAllowed(hwnd))))
        return false

    try
    {
        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute"
            , "ptr", hwnd
            , "uint", 14             ; DWMWA_CLOAKED
            , "int*", &cloaked
            , "uint", 4)
        if (cloaked && !isSeenTrayWindow)
            return false
    }

    try
    {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        if ((w <= 10 || h <= 10) && !(allowBackground && (!visible || iconic)))
            return false
    }

    try
    {
        exe := WinGetProcessName("ahk_id " hwnd)
        if (exe = "explorer.exe" && cls != "CabinetWClass")
            return false
        for item in Blacklist
            if (exe = item)
                return false
    }

    return true
}

; 快捷启动可激活最小化窗口，所以临时放宽后台窗口过滤
IsRunnableWindowCandidate(hwnd)
{
    try
        return IsAltTabCandidate(hwnd, true)
    catch
        return false
}

; 将窗口提升到 MRU 最前，避免外部切换后列表仍停在旧顺序
PromoteWindow(hwnd)
{
    global WindowHistory

    foundIndex := 0
    for i, h in WindowHistory
    {
        if (h = hwnd)
        {
            foundIndex := i
            break
        }
    }

    if (foundIndex = 1)
        return
    if (foundIndex > 1)
        WindowHistory.RemoveAt(foundIndex)
    WindowHistory.InsertAt(1, hwnd)
}

; 移除同进程其它窗口，避免 Alt+数字轮转经过的窗口污染 Alt+Tab 队列
KeepOnlyProgramWindowInHistory(exeName, keepHwnd)
{
    global WindowHistory

    i := WindowHistory.Length
    while (i >= 1)
    {
        hwnd := WindowHistory[i]
        try
            exe := WinGetProcessName("ahk_id " hwnd)
        catch
        {
            i--
            continue
        }

        if (exe = exeName && hwnd != keepHwnd)
            WindowHistory.RemoveAt(i)
        i--
    }
}

; =====================================================
; Alt+Tab 切换逻辑
; =====================================================

#HotIf !GetKeyState("Shift", "P")

; 按住 Alt，首次 Tab 显示列表，后续 Tab 循环选中下一项
~Alt & Tab::
{
    global Switching
    if (!Switching)
    {
        StartSwitching()
        ShowList()
    }
    else
    {
        MoveSelection(1)
        RefreshList()
    }
}

#HotIf GetKeyState("Shift", "P")

; 按住 Alt+Shift，Tab 反向循环选中上一项
~Alt & Tab::
{
    global Switching
    if (!Switching)
    {
        StartSwitching(-1)
        ShowList()
    }
    else
    {
        MoveSelection(-1)
        RefreshList()
    }
}

#HotIf

StartSwitching(step := 1)
{
    global Switching, Index, DisplayWindows
    ; 热键路径只同步处理当前前台窗口，避免全量枚举阻塞首帧 UI。
    CaptureActiveWindowForSwitching()
    RemoveClosedWindowsFromHistory()
    DisplayWindows := GetDisplayWindows(false)
    CaptureDisplayWindowStates()
    Switching := true
    count := DisplayWindows.Length
    if (count <= 1)
        Index := 1
    else if (step < 0)
        Index := count
    else
        Index := 2

}

MoveSelection(step)
{
    global Index, DisplayWindows
    ; step 为 1 正向，-1 反向，超出后循环
    count := DisplayWindows.Length
    if (count <= 0)
    {
        Index := 1
        return
    }

    Index += step
    if (Index > count)
        Index := 1
    else if (Index < 1)
        Index := count
}

; 松开 Alt：激活选中窗口，关闭列表
~Alt Up::
{
    FinishSwitching()
}

; 统一结束切换流程，避免热键和定时器各自维护状态
FinishSwitching()
{
    global Switching, DisplayWindows, DisplayWindowWasBackground, Index
    if (!Switching)
        return

    selectedHwnd := (Index >= 1 && Index <= DisplayWindows.Length) ? DisplayWindows[Index] : 0
    RestoreWindowPreview(selectedHwnd)
    ActivateSelected()
    Switching := false
    DisplayWindowWasBackground := Map()
    HideList()
    SetTimer(PreCreateListGui, -50)
}

; =====================================================
; UI — 深色主题窗口列表（防闪烁：复用 GUI 和文本控件）
; =====================================================

ShowList()
{
    RefreshList()
}

; 更新 GUI 三列内容：箭头、程序名、标题
RefreshList()
{
    global GuiObj, ForegroundProcessControls, BackgroundProcessControls, IconControls, TitleControls, ArrowControls, DisplayWindows, Index, Switching

    Critical "On"
    if (!IsListGuiReady())
        CreateListGui()
    if (!IsListGuiReady())
        return

    if (Switching)
        PruneDisplayWindows()
    else
    {
        RemoveInvalidWindows()
        DisplayWindows := GetDisplayWindows()
        CaptureDisplayWindowStates()
    }
    maxRows := GetMaxDisplayWindows()
    count := DisplayWindows.Length
    if (Index > count)
        Index := count
    if (Index < 1)
        Index := 1

    maxProcessWidth := 0
    Loop maxRows
    {
        foregroundProcessCtrl := ForegroundProcessControls[A_Index]
        backgroundProcessCtrl := BackgroundProcessControls[A_Index]
        iconCtrl := IconControls[A_Index]
        titleCtrl := TitleControls[A_Index]
        arrowCtrl := ArrowControls[A_Index]
        if (A_Index > count)
        {
            ; 未使用的行隐藏，避免旧文本残留
            arrowCtrl.Text := ""
            arrowCtrl.Opt("+Hidden")
            foregroundProcessCtrl.Text := ""
            foregroundProcessCtrl.Opt("+Hidden")
            backgroundProcessCtrl.Text := ""
            backgroundProcessCtrl.Opt("+Hidden")
            iconCtrl.Value := ""
            iconCtrl.Opt("+Hidden")
            titleCtrl.Text := ""
            titleCtrl.Opt("+Hidden")
            continue
        }

        ; 安全获取标题，窗口可能在渲染瞬间关闭
        hwnd := DisplayWindows[A_Index]
        try
            text := WinGetTitle("ahk_id " hwnd)
        catch
            continue
        try
            exe := WinGetProcessName("ahk_id " hwnd)
        catch
            exe := ""
        if (text = "")
            text := FormatProcessName(exe)

        arrowCtrl.Text := (A_Index = Index) ? "▶" : ""
        arrowCtrl.Opt("-Hidden")
        iconPath := GetWindowIconPath(hwnd)
        UpdateIconControl(iconCtrl, iconPath)
        processText := FormatProcessName(exe)
        processFontSize := (A_Index = 1) ? Max(1, UIFontSize - 3) : UIFontSize
        isBackgroundDisplay := IsDisplayWindowBackground(hwnd)
        if (isBackgroundDisplay)
        {
            processDisplayText := "__" processText
            backgroundProcessCtrl.Text := processDisplayText
            backgroundProcessCtrl.Opt("-Hidden")
            foregroundProcessCtrl.Text := ""
            foregroundProcessCtrl.Opt("+Hidden")
        }
        else
        {
            processDisplayText := processText
            foregroundProcessCtrl.Text := processDisplayText
            foregroundProcessCtrl.Opt("-Hidden")
            backgroundProcessCtrl.Text := ""
            backgroundProcessCtrl.Opt("+Hidden")
        }
        titleDisplayText := FormatWindowTitle(text, exe)
        titleCtrl.Text := titleDisplayText
        titleCtrl.Opt("-Hidden")

        measuredWidth := MeasureDisplayTextWidth(processDisplayText, processFontSize, isBackgroundDisplay) + 12
        maxProcessWidth := Max(maxProcessWidth, measuredWidth)
    }

    ApplyListColumnWidths(maxProcessWidth)
    if (!Switching || !GetKeyState("Alt", "P"))
    {
        if (Switching)
            FinishSwitching()
        else
            HideList()
        return
    }
    RestoreListTopmost(false)
    try
        GuiObj.Show("AutoSize Center NoActivate")
    RestoreListTopmost(true)

    ; Show 后再兜底一次，处理 Alt 在渲染最后一刻松开的情况
    if (!Switching || !GetKeyState("Alt", "P"))
    {
        if (Switching)
            FinishSwitching()
        else
            HideList()
        return
    }

    ApplyWindowPreview()
    RestoreListTopmost(true)
}

CaptureActiveWindowForSwitching()
{
    activeHwnd := WinExist("A")
    if (!activeHwnd)
        return

    if (IsAltTabCandidate(activeHwnd, false))
    {
        MarkForegroundProcessSeen(activeHwnd)
        UpdateQuickProgramHistoryFocus(activeHwnd)
        PromoteWindow(activeHwnd)
    }
}

RemoveClosedWindowsFromHistory()
{
    global WindowHistory

    i := WindowHistory.Length
    while (i >= 1)
    {
        if (!WinExist("ahk_id " WindowHistory[i]))
            WindowHistory.RemoveAt(i)
        i--
    }
}

; 按当前内容宽度排列第二、第三列，第二列不超过上限
ApplyListColumnWidths(processWidth := 0)
{
    global ForegroundProcessControls, BackgroundProcessControls, TitleControls, MaxProcessColumnWidth, TitleColumnWidth, UIIconSize

    if (!IsListGuiReady())
        return

    if (processWidth <= 0)
        processWidth := MaxProcessColumnWidth
    processWidth := Min(processWidth, MaxProcessColumnWidth)
    titleWidth := TitleColumnWidth
    processX := GetProcessColumnX()
    titleX := processX + processWidth

    Loop GetMaxDisplayWindows()
    {
        ForegroundProcessControls[A_Index].Move(processX, , processWidth)
        BackgroundProcessControls[A_Index].Move(processX, , processWidth)
        TitleControls[A_Index].Move(titleX, , titleWidth)
    }
}

GetIconColumnX()
{
    return 40
}

GetProcessColumnX()
{
    global UIIconSize
    return GetIconColumnX() + UIIconSize + 8
}

GetWindowIconPath(hwnd)
{
    try
    {
        path := WinGetProcessPath("ahk_id " hwnd)
        if (path != "" && FileExist(path))
            return path
    }
    catch
        return ""

    return ""
}

UpdateIconControl(iconCtrl, iconPath)
{
    global UIIconSize

    if (iconPath = "")
    {
        iconCtrl.Value := ""
        iconCtrl.Opt("+Hidden")
        return
    }

    try
    {
        iconCtrl.Move(, , UIIconSize, UIIconSize)
        iconCtrl.Value := "*w" UIIconSize " *h" UIIconSize " " iconPath
        iconCtrl.Opt("-Hidden")
    }
    catch
    {
        try
        {
            iconCtrl.Value := ""
            iconCtrl.Opt("+Hidden")
        }
    }
}

; 切换开始时冻结每一行的后台/最小化标记，避免预览恢复窗口后 UI 分组跳动。
CaptureDisplayWindowStates()
{
    global DisplayWindows, DisplayWindowWasBackground

    DisplayWindowWasBackground := Map()
    for hwnd in DisplayWindows
        DisplayWindowWasBackground[hwnd] := IsBackgroundWindow(hwnd)
}

IsDisplayWindowBackground(hwnd)
{
    global Switching, DisplayWindowWasBackground

    if (Switching && DisplayWindowWasBackground.Has(hwnd))
        return DisplayWindowWasBackground[hwnd]
    return IsBackgroundWindow(hwnd)
}

; 切换期间只清理已关闭窗口，不重建列表，避免预览激活最小化窗口后被数量限制挤出。
PruneDisplayWindows()
{
    global DisplayWindows

    i := DisplayWindows.Length
    while (i >= 1)
    {
        hwnd := DisplayWindows[i]
        if (!WinExist("ahk_id " hwnd))
            DisplayWindows.RemoveAt(i)
        i--
    }
}

; 记录切换开始时普通窗口的 Z 序，结束前恢复，避免预览过程永久改变其它窗口排列
CapturePreviewZOrder()
{
    global PreviewZOrder, PreviewTransparentWindows, PreviewShownMinimizedWindows, PreviewCurrentHwnd

    PreviewZOrder := []
    PreviewTransparentWindows := Map()
    PreviewShownMinimizedWindows := Map()
    PreviewCurrentHwnd := 0

    for hwnd in EnumWindowsRaw()
    {
        if (IsPreviewManagedWindow(hwnd, true))
            PreviewZOrder.Push(hwnd)
    }
}

; 将箭头指向窗口展示出来。先无激活抬高，再实际激活，确保窗口可见。
ApplyWindowPreview()
{
    global DisplayWindows, Index, PreviewOnlySelectedWindow, PreviewCurrentHwnd, PreviewZOrder

    if (Index < 1 || Index > DisplayWindows.Length)
        return

    hwnd := DisplayWindows[Index]
    if (!WinExist("ahk_id " hwnd))
        return

    if (PreviewZOrder.Length = 0)
        CapturePreviewZOrder()

    if (PreviewOnlySelectedWindow)
        ApplyPreviewOnlyMode(hwnd)
    else
        RestorePreviewTransparency(hwnd)

    ShowPreviewWindow(hwnd)
    ActivatePreviewWindow(hwnd)
    PreviewCurrentHwnd := hwnd
}

; 独占预览：其它普通窗口透明，让桌面成为背景。置顶/贴图/工具窗不处理。
ApplyPreviewOnlyMode(selectedHwnd)
{
    global PreviewTransparentWindows

    for hwnd in EnumWindowsRaw()
    {
        if (hwnd = selectedHwnd)
            continue
        if (!IsPreviewManagedWindow(hwnd, false))
            continue
        if (!PreviewTransparentWindows.Has(hwnd))
        {
            try
                PreviewTransparentWindows[hwnd] := WinGetTransparent("ahk_id " hwnd)
            catch
                PreviewTransparentWindows[hwnd] := ""
        }
        try
            WinSetTransparent(0, "ahk_id " hwnd)
    }

    RestoreOnePreviewTransparency(selectedHwnd)
}

; 关闭独占模式或选中某个曾被透明化的窗口时，恢复透明度。
RestorePreviewTransparency(exceptHwnd := 0)
{
    global PreviewTransparentWindows

    for hwnd, originalTransparency in PreviewTransparentWindows.Clone()
    {
        if (hwnd = exceptHwnd)
            continue
        if (WinExist("ahk_id " hwnd))
        {
            try
            {
                if (originalTransparency = "")
                    WinSetTransparent("Off", "ahk_id " hwnd)
                else
                    WinSetTransparent(originalTransparency, "ahk_id " hwnd)
            }
        }
        PreviewTransparentWindows.Delete(hwnd)
    }
}

RestoreOnePreviewTransparency(hwnd)
{
    global PreviewTransparentWindows

    if (!PreviewTransparentWindows.Has(hwnd))
        return

    originalTransparency := PreviewTransparentWindows[hwnd]
    if (WinExist("ahk_id " hwnd))
    {
        try
        {
            if (originalTransparency = "")
                WinSetTransparent("Off", "ahk_id " hwnd)
            else
                WinSetTransparent(originalTransparency, "ahk_id " hwnd)
        }
    }
    PreviewTransparentWindows.Delete(hwnd)
}

; 尽量不激活地先展示候选窗口，后续再实际激活兜底。
ShowPreviewWindow(hwnd)
{
    global PreviewShownMinimizedWindows

    if (IsWindowPreviewProtected(hwnd))
        return

    visible := DllCall("user32\IsWindowVisible", "ptr", hwnd)
    iconic := DllCall("user32\IsIconic", "ptr", hwnd)
    if (!visible && !iconic)
        return

    if (iconic)
    {
        if (!PreviewShownMinimizedWindows.Has(hwnd))
            PreviewShownMinimizedWindows[hwnd] := true
        DllCall("user32\ShowWindow", "ptr", hwnd, "int", 4) ; SW_SHOWNOACTIVATE
    }

    ; HWND_TOP=0；0x13 = NOSIZE | NOMOVE | NOACTIVATE
    DllCall("user32\SetWindowPos"
        , "ptr", hwnd
        , "ptr", 0
        , "int", 0
        , "int", 0
        , "int", 0
        , "int", 0
        , "uint", 0x13)
}

; 实际激活候选窗口，保证箭头移动时用户能看到该窗口。
ActivatePreviewWindow(hwnd)
{
    global PreviewCurrentHwnd

    if (hwnd = PreviewCurrentHwnd)
        return
    if (IsWindowPreviewProtected(hwnd))
        return

    visible := DllCall("user32\IsWindowVisible", "ptr", hwnd)
    iconic := DllCall("user32\IsIconic", "ptr", hwnd)
    if (!visible && !iconic)
        return

    try
    {
        if (iconic)
            DllCall("user32\ShowWindow", "ptr", hwnd, "int", 9) ; SW_RESTORE
        WinActivate("ahk_id " hwnd)
    }
}

; 恢复预览造成的透明、最小化和普通窗口 Z 序。最终选中的窗口交给 ActivateWindow 处理。
RestoreWindowPreview(exceptHwnd := 0)
{
    global PreviewZOrder, PreviewShownMinimizedWindows, PreviewCurrentHwnd

    RestorePreviewTransparency(exceptHwnd)

    for hwnd, _ in PreviewShownMinimizedWindows.Clone()
    {
        if (hwnd = exceptHwnd)
            continue
        if (WinExist("ahk_id " hwnd))
        {
            try
                DllCall("user32\ShowWindow", "ptr", hwnd, "int", 6) ; SW_MINIMIZE
        }
        PreviewShownMinimizedWindows.Delete(hwnd)
    }

    i := PreviewZOrder.Length
    while (i >= 1)
    {
        hwnd := PreviewZOrder[i]
        if (hwnd != exceptHwnd && WinExist("ahk_id " hwnd) && !IsWindowPreviewProtected(hwnd))
        {
            try
                DllCall("user32\SetWindowPos"
                    , "ptr", hwnd
                    , "ptr", 0
                    , "int", 0
                    , "int", 0
                    , "int", 0
                    , "int", 0
                    , "uint", 0x13)
        }
        i--
    }

    PreviewZOrder := []
    PreviewShownMinimizedWindows := Map()
    PreviewCurrentHwnd := 0
}

; 只管理普通应用窗口，避免影响置顶窗口、贴图窗口、任务栏和桌面。
IsPreviewManagedWindow(hwnd, allowIconic := false)
{
    if (!WinExist("ahk_id " hwnd))
        return false
    if (IsWindowPreviewProtected(hwnd))
        return false
    if (!DllCall("user32\IsWindowVisible", "ptr", hwnd))
        return false
    if (!allowIconic && DllCall("user32\IsIconic", "ptr", hwnd))
        return false
    try
        return IsAltTabCandidate(hwnd, allowIconic)
    catch
        return false
}

IsWindowPreviewProtected(hwnd)
{
    global GuiObj

    if (IsObject(GuiObj))
    {
        try
            if (hwnd = GuiObj.Hwnd)
                return true
    }

    exStyle := DllCall("user32\GetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr")
    return (exStyle & 0x8) != 0 ; WS_EX_TOPMOST
}

; 清理历史列表中的无效窗口，渲染前和定时刷新都会调用
RemoveInvalidWindows()
{
    global WindowHistory

    i := WindowHistory.Length
    while (i >= 1)
    {
        hwnd := WindowHistory[i]
        if (!IsAltTabCandidate(hwnd, true))
            WindowHistory.RemoveAt(i)
        i--
    }
}

; 按 MRU 顺序取 UI 列表，同时分别限制前台/后台数量
GetDisplayWindows(includeBackgroundFallback := true)
{
    global WindowHistory, MaxForegroundWindows, MaxBackgroundWindows, BackgroundWindowsAlwaysAtBottom

    result := []
    backgroundResult := []
    foregroundCount := 0
    backgroundCount := 0
    for hwnd in WindowHistory
    {
        if (IsBackgroundWindow(hwnd))
        {
            hwnd := GetBestBackgroundWindow(hwnd)
            if (ArrayContains(result, hwnd) || ArrayContains(backgroundResult, hwnd))
                continue
            if (backgroundCount >= MaxBackgroundWindows)
                continue
            backgroundCount += 1
            if (BackgroundWindowsAlwaysAtBottom)
            {
                backgroundResult.Push(hwnd)
                continue
            }
        }
        else
        {
            if (foregroundCount >= MaxForegroundWindows)
                continue
            foregroundCount += 1
        }
        result.Push(hwnd)
    }

    ; 有些应用托盘化后换隐藏主窗口句柄，只允许“曾经前台出现过”的进程兜底。
    if (includeBackgroundFallback && backgroundCount < MaxBackgroundWindows)
    {
        for hwnd in EnumWindowsRaw()
        {
            if (backgroundCount >= MaxBackgroundWindows)
                break
            if (ShouldSkipQuickProgramHistoryWindow(hwnd))
                continue
            if (ArrayContains(result, hwnd) || ArrayContains(backgroundResult, hwnd))
                continue
            if (!IsBackgroundWindow(hwnd) || (!IsSeenForegroundProcess(hwnd) && !IsBackgroundProcessAllowed(hwnd)))
                continue
            if (!IsAltTabCandidate(hwnd, true))
                continue
            hwnd := GetBestBackgroundWindow(hwnd)
            if (ArrayContains(result, hwnd) || ArrayContains(backgroundResult, hwnd))
                continue
            backgroundCount += 1
            if (BackgroundWindowsAlwaysAtBottom)
                backgroundResult.Push(hwnd)
            else
                result.Push(hwnd)
        }
    }

    if (BackgroundWindowsAlwaysAtBottom)
    {
        for hwnd in backgroundResult
            result.Push(hwnd)
    }

    return result
}

; 同一进程托盘化后可能有多个隐藏窗，取标题有效且面积最大的那个作为主窗口
GetBestBackgroundWindow(hwnd)
{
    if (!IsBackgroundWindow(hwnd) || !IsSeenForegroundProcess(hwnd))
        return hwnd

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return hwnd

    bestHwnd := hwnd
    bestArea := GetWindowArea(hwnd)
    for candidate in EnumWindowsRaw()
    {
        if (!IsBackgroundWindow(candidate) || (!IsSeenForegroundProcess(candidate) && !IsBackgroundProcessAllowed(candidate)))
            continue
        try
            candidateExe := WinGetProcessName("ahk_id " candidate)
        catch
            continue
        if (candidateExe != exe)
            continue
        if (!IsAltTabCandidate(candidate, true))
            continue

        area := GetWindowArea(candidate)
        if (area > bestArea)
        {
            bestArea := area
            bestHwnd := candidate
        }
    }

    return bestHwnd
}

GetWindowArea(hwnd)
{
    try
    {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return w * h
    }
    catch
        return 0
}

IsSeenForegroundProcess(hwnd)
{
    global ForegroundProcessSeen

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return false

    return ForegroundProcessSeen.Has(exe)
}

IsBackgroundProcessAllowed(hwnd)
{
    global BackgroundProcessAllowlist

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return false

    for item in BackgroundProcessAllowlist
        if (exe = item)
            return true
    return false
}

IsOwnedWindowProcessAllowed(hwnd)
{
    global OwnedWindowProcessAllowlist

    try
        exe := WinGetProcessName("ahk_id " hwnd)
    catch
        return false

    for item in OwnedWindowProcessAllowlist
        if (exe = item)
            return true
    return false
}

; UI 最大行数由前台和后台两个上限相加得到
GetMaxDisplayWindows()
{
    global MaxForegroundWindows, MaxBackgroundWindows
    return MaxForegroundWindows + MaxBackgroundWindows
}

; 后台窗口用于 UI 标记和数量分组
IsBackgroundWindow(hwnd)
{
    visible := DllCall("user32\IsWindowVisible", "ptr", hwnd)
    iconic := DllCall("user32\IsIconic", "ptr", hwnd)
    return !visible || iconic
}

; 创建一次 GUI 和固定行控件，后续只更新文本以减少闪烁
CreateListGui()
{
    global GuiObj, ForegroundProcessControls, BackgroundProcessControls, IconControls, TitleControls, ArrowControls, UIFontSize, UIRowGap, UIIconSize
    global MaxProcessColumnWidth, TitleColumnWidth

    Critical "On"
    GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow")
    GuiObj.BackColor := "202020"
    GuiObj.SetFont("s" UIFontSize, "Microsoft YaHei UI")

    rowHeight := GetUIRowHeight()
    rowStep := rowHeight + UIRowGap
    processWidth := MaxProcessColumnWidth
    titleWidth := TitleColumnWidth
    iconX := GetIconColumnX()
    processX := GetProcessColumnX()
    titleX := processX + processWidth
    ForegroundProcessControls := []
    BackgroundProcessControls := []
    IconControls := []
    TitleControls := []
    ArrowControls := []
    Loop GetMaxDisplayWindows()
    {
        y := 8 + (A_Index - 1) * rowStep
        textFontSize := (A_Index = 1) ? Max(1, UIFontSize - 3) : UIFontSize
        arrowY := y - 1
        iconY := y + Max(0, Floor((rowHeight - UIIconSize) / 2))
        processColor := (A_Index = 1) ? "7A97B8" : "B8D7FF"
        titleColor := (A_Index = 1) ? "B0B0B0" : "FFFFFF"
        textStyle := " +0xC +0x200" ; 单行不换行，并在行高内垂直居中
        GuiObj.SetFont("s" UIFontSize " Norm", "Microsoft YaHei UI")
        arrowCtrl := GuiObj.AddText("x12 y" arrowY " cFFFFFF w24 h" rowHeight " Center +0x200", "")
        iconCtrl := GuiObj.AddPicture("x" iconX " y" iconY " w" UIIconSize " h" UIIconSize " +Hidden", "")
        GuiObj.SetFont("s" textFontSize " Norm", "Microsoft YaHei UI")
        foregroundProcessCtrl := GuiObj.AddText("x" processX " y" y " c" processColor " w" processWidth " h" rowHeight " +Hidden" textStyle, "")
        GuiObj.SetFont("s" textFontSize " Norm Italic", "Microsoft YaHei UI")
        backgroundProcessCtrl := GuiObj.AddText("x" processX " y" y " c" processColor " w" processWidth " h" rowHeight " +Hidden" textStyle, "")
        GuiObj.SetFont("s" textFontSize " Norm", "Microsoft YaHei UI")
        titleCtrl := GuiObj.AddText("x" titleX " y" y " c" titleColor " w" titleWidth " h" rowHeight textStyle, "")
        arrowCtrl.OnEvent("Click", SelectWindowByClick.Bind(A_Index))
        iconCtrl.OnEvent("Click", SelectWindowByClick.Bind(A_Index))
        foregroundProcessCtrl.OnEvent("Click", SelectWindowByClick.Bind(A_Index))
        backgroundProcessCtrl.OnEvent("Click", SelectWindowByClick.Bind(A_Index))
        titleCtrl.OnEvent("Click", SelectWindowByClick.Bind(A_Index))
        ArrowControls.Push(arrowCtrl)
        IconControls.Push(iconCtrl)
        ForegroundProcessControls.Push(foregroundProcessCtrl)
        BackgroundProcessControls.Push(backgroundProcessCtrl)
        TitleControls.Push(titleCtrl)
    }
}

; 空闲时预创建 GUI，降低第一次 Alt+Tab 的显示延迟
PreCreateListGui()
{
    if (!IsListGuiReady())
        CreateListGui()
}

; 复用隐藏 GUI 时，置顶状态可能被系统或其它窗口打掉；每次显示前后重新声明
RestoreListTopmost(showWindow := false)
{
    global GuiObj

    if (!IsObject(GuiObj))
        return

    try
        GuiObj.Opt("+AlwaysOnTop")

    try
        hwnd := GuiObj.Hwnd
    catch
        return

    ; HWND_TOPMOST=-1；0x13 = NOSIZE | NOMOVE | NOACTIVATE，显示后再加 SHOWWINDOW
    flags := showWindow ? 0x53 : 0x13
    DllCall("user32\SetWindowPos"
        , "ptr", hwnd
        , "ptr", -1
        , "int", 0
        , "int", 0
        , "int", 0
        , "int", 0
        , "uint", flags)
}

; 确认 GUI 和固定控件都创建完整，避免快速松开 Alt 时访问半销毁对象
IsListGuiReady()
{
    global GuiObj, ForegroundProcessControls, BackgroundProcessControls, IconControls, TitleControls, ArrowControls

    maxRows := GetMaxDisplayWindows()
    return IsObject(GuiObj)
        && ForegroundProcessControls.Length >= maxRows
        && BackgroundProcessControls.Length >= maxRows
        && IconControls.Length >= maxRows
        && TitleControls.Length >= maxRows
        && ArrowControls.Length >= maxRows
}

; 根据字体大小估算文本控件高度，UIRowGap 只负责行间距
GetUIRowHeight()
{
    global UIFontSize
    return Ceil(UIFontSize * 2.0)
}

; 鼠标点任意列都切换到对应行窗口
SelectWindowByClick(row, ctrl, info)
{
    global Index, DisplayWindows
    count := DisplayWindows.Length
    if (row < 1 || row > count)
        return

    Index := row
    FinishSwitching()
}

; 激活选中的窗口，成功后将其提升到 MRU 最前
ActivateSelected()
{
    global DisplayWindows, Index

    if (Index < 1 || Index > DisplayWindows.Length)
        return

    hwnd := DisplayWindows[Index]
    if (!hwnd)
        return

    ; 激活窗口（可能已关闭，try 防抛异常）
    try
    {
        activatedHwnd := ActivateWindow(hwnd)
        if (!activatedHwnd)
            return
    }
    catch
        return

    ; MRU: 将刚激活的窗口移到列表首位
    PromoteWindow(activatedHwnd)
}

; 关闭列表
HideList()
{
    global GuiObj, ForegroundProcessControls, BackgroundProcessControls, IconControls, TitleControls, ArrowControls
    Critical "On"
    if (IsObject(GuiObj))
    {
        try
            GuiObj.Hide()

        maxRows := GetMaxDisplayWindows()
        Loop maxRows
        {
            try
            {
                ArrowControls[A_Index].Text := ""
                ArrowControls[A_Index].Opt("+Hidden")
                ForegroundProcessControls[A_Index].Text := ""
                ForegroundProcessControls[A_Index].Opt("+Hidden")
                BackgroundProcessControls[A_Index].Text := ""
                BackgroundProcessControls[A_Index].Opt("+Hidden")
                IconControls[A_Index].Value := ""
                IconControls[A_Index].Opt("+Hidden")
                TitleControls[A_Index].Text := ""
                TitleControls[A_Index].Opt("+Hidden")
            }
        }
    }
}

; =====================================================
; Alt + 数字 — 快捷启动程序
; =====================================================

#HotIf EnableQuickLaunch

!1::
!2::
!3::
!4::
!5::
!6::
!7::
!8::
!9::
{
    global QuickPrograms
    key := SubStr(A_ThisHotkey, 2)             ; 去掉 ! 前缀，取数字部分
    if (QuickPrograms.Has(Integer(key)))
    {
        program := QuickPrograms[Integer(key)]
        if (!ActivateExistingProgram(program))
            RunQuickProgram(program)
    }
}

#HotIf

; Alt+数字：优先激活已有窗口，多个同进程窗口按上次位置轮转
ActivateExistingProgram(program)
{
    global QuickProgramLastHwnd, QuickProgramHistoryFocus
    exeName := GetProgramExeName(program)
    if (exeName = "")
        return false

    candidates := GetQuickProgramCandidates(exeName)
    launchCommand := ResolveQuickLaunchCommand(program)

    if (candidates.Length = 0)
    {
        if (launchCommand = "")
            return false
        try
            Run(launchCommand)
        catch
            return false
        return true
    }

    activeIndex := GetActiveWindowIndex(candidates)
    if (activeIndex > 0)
    {
        nextIndex := activeIndex + 1
        if (nextIndex > candidates.Length)
            nextIndex := 1
    }
    else
    {
        nextIndex := 1
        if (QuickProgramLastHwnd.Has(exeName))
        {
            for i, hwnd in candidates
            {
                if (hwnd = QuickProgramLastHwnd[exeName])
                {
                    nextIndex := i
                    break
                }
            }
        }
    }

    hwnd := candidates[nextIndex]
    try
    {
        activatedHwnd := ActivateWindow(hwnd, launchCommand)
        if (!activatedHwnd)
            return false
    }
    catch
        return false

    QuickProgramLastHwnd[exeName] := activatedHwnd
    QuickProgramHistoryFocus[exeName] := activatedHwnd
    KeepOnlyProgramWindowInHistory(exeName, activatedHwnd)
    PromoteWindow(activatedHwnd)
    return true
}

; Alt+数字安全启动入口：避免裸 Run("xxx.exe") 解析失败时报错
RunQuickProgram(program)
{
    launchCommand := ResolveQuickLaunchCommand(program)
    if (launchCommand = "")
        return false

    try
        Run(launchCommand)
    catch
        return false

    return true
}

; 找不到现成窗口时，用这里的命令启动或恢复应用
ResolveQuickLaunchCommand(program)
{
    global QuickProgramLaunchers

    if (QuickProgramLaunchers.Has(program))
        return QuickProgramLaunchers[program]

    for key, value in QuickProgramLaunchers
    {
        if (StrLower(key) = StrLower(program))
            return value
    }

    shortcutPath := FindStartMenuShortcutForProgram(program)
    if (shortcutPath != "")
        return shortcutPath

    return program
}

; 在公共/用户开始菜单中按快捷方式目标 exe 匹配程序
FindStartMenuShortcutForProgram(program)
{
    global QuickProgramShortcutCache

    exeName := GetProgramExeName(program)
    if (exeName = "")
        return ""

    cacheKey := StrLower(exeName)
    if (QuickProgramShortcutCache.Has(cacheKey))
        return QuickProgramShortcutCache[cacheKey]

    roots := [
        EnvGet("ProgramData") "\Microsoft\Windows\Start Menu\Programs",
        A_AppData "\Microsoft\Windows\Start Menu\Programs"
    ]

    for root in roots
    {
        if (!DirExist(root))
            continue

        Loop Files root "\*.lnk", "R"
        {
            shortcutPath := A_LoopFileFullPath
            if (!ShortcutMayReferenceExe(shortcutPath, exeName))
                continue

            try
            {
                FileGetShortcut(shortcutPath, &targetPath)
                SplitPath(targetPath, &targetExe)
                if (StrLower(targetExe) = cacheKey)
                {
                    QuickProgramShortcutCache[cacheKey] := shortcutPath
                    return shortcutPath
                }
            }
        }
    }

    QuickProgramShortcutCache[cacheKey] := ""
    return ""
}

; .lnk 是二进制文件，先按 ASCII/UTF-16LE 搜 exe 名，命中后再解析快捷方式
ShortcutMayReferenceExe(shortcutPath, exeName)
{
    try
        data := FileRead(shortcutPath, "RAW")
    catch
        return false

    needle := StrLower(exeName)
    return BufferContainsAsciiText(data, needle) || BufferContainsUtf16LeText(data, needle)
}

BufferContainsAsciiText(data, needle)
{
    needleLen := StrLen(needle)
    if (needleLen = 0)
        return true
    if (data.Size < needleLen)
        return false

    maxStart := data.Size - needleLen
    Loop maxStart + 1
    {
        start := A_Index - 1
        matched := true
        Loop needleLen
        {
            b := NumGet(data, start + A_Index - 1, "UChar")
            if (b >= 65 && b <= 90)
                b += 32
            if (b != Ord(SubStr(needle, A_Index, 1)))
            {
                matched := false
                break
            }
        }
        if (matched)
            return true
    }

    return false
}

BufferContainsUtf16LeText(data, needle)
{
    needleLen := StrLen(needle)
    byteLen := needleLen * 2
    if (needleLen = 0)
        return true
    if (data.Size < byteLen)
        return false

    maxStart := data.Size - byteLen
    Loop maxStart + 1
    {
        start := A_Index - 1
        matched := true
        Loop needleLen
        {
            charOffset := start + (A_Index - 1) * 2
            b := NumGet(data, charOffset, "UChar")
            high := NumGet(data, charOffset + 1, "UChar")
            if (high != 0)
            {
                matched := false
                break
            }
            if (b >= 65 && b <= 90)
                b += 32
            if (b != Ord(SubStr(needle, A_Index, 1)))
            {
                matched := false
                break
            }
        }
        if (matched)
            return true
    }

    return false
}

; 当前活动窗口属于同一程序时，从它的位置开始轮转
GetActiveWindowIndex(candidates)
{
    activeHwnd := WinExist("A")
    if (!activeHwnd)
        return 0

    for i, hwnd in candidates
    {
        if (hwnd = activeHwnd)
            return i
    }

    return 0
}

; 维护每个程序的稳定窗口顺序：关闭的删掉，新开的追加，激活不重排
GetQuickProgramCandidates(exeName)
{
    global QuickProgramWindowOrder

    current := []
    rawWindows := EnumWindowsRaw()
    i := rawWindows.Length
    while (i >= 1)
    {
        hwnd := rawWindows[i]
        if (IsWindowProcess(hwnd, exeName))
            current.Push(hwnd)
        i--
    }

    if (!QuickProgramWindowOrder.Has(exeName))
        QuickProgramWindowOrder[exeName] := []

    ordered := QuickProgramWindowOrder[exeName]

    i := ordered.Length
    while (i >= 1)
    {
        if (!ArrayContains(current, ordered[i]))
            ordered.RemoveAt(i)
        i--
    }

    for hwnd in current
    {
        if (!ArrayContains(ordered, hwnd))
            ordered.Push(hwnd)
    }

    QuickProgramWindowOrder[exeName] := ordered
    return ordered
}

; 隐藏托盘窗口优先走应用单实例入口；最小化窗口直接恢复到任务栏窗口
ActivateWindow(hwnd, launchCommand := "")
{
    visible := DllCall("user32\IsWindowVisible", "ptr", hwnd)
    iconic := DllCall("user32\IsIconic", "ptr", hwnd)
    exeName := ""

    if (!visible && !iconic)
    {
        if (launchCommand = "")
        {
            try
            {
                path := WinGetProcessPath("ahk_id " hwnd)
                if (path != "")
                    launchCommand := '"' path '"'
            }
        }
        exeName := GetProgramExeName(launchCommand)
        if (exeName = "")
        {
            try
                exeName := WinGetProcessName("ahk_id " hwnd)
        }

        if (launchCommand != "")
        {
            Run(launchCommand)
            Loop 10
            {
                Sleep(100)
                visibleHwnd := FindVisibleProgramWindow(exeName)
                if (visibleHwnd)
                {
                    WinActivate("ahk_id " visibleHwnd)
                    return visibleHwnd
                }
                visible := DllCall("user32\IsWindowVisible", "ptr", hwnd)
                iconic := DllCall("user32\IsIconic", "ptr", hwnd)
                if (visible || iconic)
                    break
            }
        }

        ; 仍未显示时不强制 ShowWindow，避免破坏应用自己的托盘状态机。
        if (!visible && !iconic)
            return false
    }

    if (!visible || iconic)
        DllCall("user32\ShowWindow", "ptr", hwnd, "int", 9) ; SW_RESTORE
    WinActivate("ahk_id " hwnd)
    return hwnd
}

FindVisibleProgramWindow(exeName)
{
    if (exeName = "")
        return 0

    for hwnd in EnumWindowsRaw()
    {
        if (!DllCall("user32\IsWindowVisible", "ptr", hwnd))
            continue
        if (!IsWindowProcess(hwnd, exeName))
            continue
        return hwnd
    }

    return 0
}

; 原始枚举所有顶级窗口，供 QuickPrograms 查找最小化窗口
EnumWindowsRaw()
{
    result := []

    callback(hwnd, lParam)
    {
        result.Push(hwnd)
        return true
    }

    cb := CallbackCreate(callback)
    DllCall("user32\EnumWindows", "ptr", cb, "ptr", 0)
    CallbackFree(cb)

    return result
}

; AHK v2 数组没有按值查找，这里做简单去重
ArrayContains(arr, value)
{
    for item in arr
    {
        if (item = value)
            return true
    }
    return false
}

; 判断窗口进程是否匹配指定 exe 名
IsWindowProcess(hwnd, exeName)
{
    if (!IsQuickProgramWindowCandidate(hwnd, exeName))
        return false

    try
        return StrLower(WinGetProcessName("ahk_id " hwnd)) = StrLower(exeName)
    catch
        return false
}

; QuickPrograms 只激活真正应用窗口，避免 helper/托盘消息窗被轮转到
IsQuickProgramWindowCandidate(hwnd, exeName)
{
    if (!IsRunnableWindowCandidate(hwnd))
        return false

    try
        cls := WinGetClass("ahk_id " hwnd)
    catch
        return false

    if (StrLower(exeName) = "explorer.exe")
        return cls = "CabinetWClass"

    ; 这些类即使同进程存在，也不是用户期望打开的窗口
    if (IsBlacklistedClass(cls)
        || InStr(cls, "Chrome_WidgetWin_0")
        || InStr(cls, "NotifyIcon")
        || InStr(cls, "PowerMessage")
        || InStr(cls, "SessionEndWatcher"))
        return false

    return true
}

IsBlacklistedClass(cls)
{
    global ClassBlacklist, ClassPrefixBlacklist

    for item in ClassBlacklist
        if (cls = item)
            return true

    for prefix in ClassPrefixBlacklist
        if (SubStr(cls, 1, StrLen(prefix)) = prefix)
            return true

    return false
}

; 从 Run 配置中提取 exe 文件名，支持带引号路径
GetProgramExeName(program)
{
    path := ""
    if RegExMatch(program, 'i)^\s*"([^"]+\.exe)"', &m)
        path := m[1]
    else if RegExMatch(program, "i)^\s*([^\s]+\.exe)", &m)
        path := m[1]

    if (path = "")
        return ""

    SplitPath(path, &exeName)
    return exeName
}

; UI 显示用：去掉 .exe，首字母大写
FormatProcessName(exe)
{
    global ProcessAliasMap

    name := RegExReplace(exe, "i)\.exe$")
    if (name = "")
        return ""

    name := StrUpper(SubStr(name, 1, 1)) SubStr(name, 2)
    alias := LookupProcessAlias(name)
    if (alias != "")
        return alias
    return name
}

; UI 程序别名：大小写无关查找
LookupProcessAlias(name)
{
    global ProcessAliasMap

    target := StrLower(name)
    for aliasName, displayName in ProcessAliasMap
    {
        if (StrLower(aliasName) = target)
            return displayName
    }
    return ""
}

; 按实际字体测量文本宽度，用于第二列动态收紧
MeasureDisplayTextWidth(text, fontSize, italic := false)
{
    if (text = "")
        return 0

    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    if (!hdc)
        return 0

    dpi := DllCall("gdi32\GetDeviceCaps", "ptr", hdc, "int", 90, "int")
    height := -Round(fontSize * dpi / 72)
    hFont := DllCall(
        "gdi32\CreateFontW"
        , "int", height
        , "int", 0
        , "int", 0
        , "int", 0
        , "int", 400
        , "uint", italic ? 1 : 0
        , "uint", 0
        , "uint", 0
        , "uint", 1
        , "uint", 0
        , "uint", 0
        , "uint", 5
        , "uint", 49
        , "str", "Microsoft YaHei UI"
        , "ptr")

    if (!hFont)
    {
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
        return 0
    }

    oldFont := DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", hFont, "ptr")
    sizeBuf := Buffer(8, 0)
    DllCall("gdi32\GetTextExtentPoint32W", "ptr", hdc, "ptr", StrPtr(text), "int", StrLen(text), "ptr", sizeBuf)
    width := NumGet(sizeBuf, 0, "int")

    DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", oldFont, "ptr")
    DllCall("gdi32\DeleteObject", "ptr", hFont)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return width
}

; UI 显示用：去掉标题末尾包含程序名的 " - XXX" 后缀
FormatWindowTitle(title, exe)
{
    processName := FormatProcessName(exe)
    if (processName = "")
        return title

    suffixStart := InStr(title, " - ", , -1)
    if (!suffixStart)
        return title

    suffix := SubStr(title, suffixStart + 3)
    if InStr(StrLower(suffix), StrLower(processName))
        return SubStr(title, 1, suffixStart - 1)

    return title
}
