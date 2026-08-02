#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; 动态窗口透明度 (Dynamic Window Transparency)
;
; 功能: 聚焦某个窗口时，该窗口逐渐变得不透明（透明度降低），
; 其它非聚焦窗口逐渐变得透明（透明度提升）。
;
; 快捷键:
;   Win+Z   - 暂停/恢复透明效果
;   Win+Esc - 退出脚本
; ============================================================

; ============================================================
; 用户设置 - 按需修改以下参数
; ============================================================

; 聚焦窗口的不透明度 (0=全透明, 255=不透明)
FOCUSED_OPACITY   := 255

; 非聚焦窗口的不透明度 (越低越透明)
UNFOCUSED_OPACITY := 200

; 每步变化量 (越大过渡越快)
FADE_STEP         := 5

; 透明度动画间隔 (毫秒)
FADE_INTERVAL     := 15

; 检测活跃窗口变化的间隔 (毫秒)
POLL_INTERVAL     := 100

; 是否跳过置顶窗口 (true=不改变置顶窗口透明度)
SKIP_ALWAYSONTOP  := true

; 从最小化恢复时是否瞬间到位 (true=直接跳到目标透明度)
RESTORE_SPEED     := true

; 要排除的进程名列表 (不改变这些进程窗口的透明度，且强制不透明)
EXCLUDE_PROCESSES := [
    ; "notepad.exe",
    ; "mspaint.exe",
    "LeDimmer.exe",
    "wallpaper64.exe",
    "Code.exe",
    "MobaXterm.exe",
    "XWin_MobaX.exe",
    "RainbowSix.exe",
    "AK.exe"
]

; ---- 悬停聚焦 ----

; Switch A: 鼠标悬停在窗口上时，聚焦该窗口（但不抬升）
HOVER_FOCUS       := true

; Switch B: 聚焦时同时抬升窗口到顶层（需 HOVER_FOCUS 为 true）
RAISE_ON_ACTIVATE := false

; 悬停检测间隔 (毫秒，保持较快轮询以保证响应速度)
HOVER_INTERVAL    := 100

; 悬停延迟 (毫秒) — 鼠标进入窗口后等待多久才触发聚焦
HOVER_DELAY       := 500

; ============================================================
; 内部状态
; ============================================================

_active_hwnd  := 0             ; 当前活跃窗口的句柄
_opacity_map  := Map()         ; hwnd -> {current, target}
_paused       := false         ; 暂停标志
_windowState  := Map()         ; hwnd -> WinGetMinMax 状态 (-1=最小化, 0=普通, 1=最大化)
_hover_active      := false         ; 悬停聚焦处于激活状态（阻止 CheckActiveWindow 覆盖）
_last_hover              := 0             ; 上次悬停检测到的窗口句柄
_hover_pending_hwnd       := 0            ; 悬停等待触发的窗口句柄
_hover_pending_at        := 0             ; 悬停等待开始的时间戳
_hover_foreground_at_start := 0           ; 进入悬停模式时的前台窗口句柄

; ---- X-Mouse 运行时状态 ----
_xmouse_active           := false        ; X-Mouse 当前是否启用
_xmouse_saved            := false        ; 是否已保存原始设置 (仅保存一次)
_xmouse_hook_disabled    := false        ; 键盘钩子已临时关闭 X-Mouse
_xmouse_saved_tracking   := 0           ; 保存的 SPI_SETACTIVEWINDOWTRACKING
_xmouse_saved_zorder     := 0           ; 保存的 SPI_SETACTIVEWNDTRKZORDER
_xmouse_saved_timeout    := 0           ; 保存的 SPI_SETACTIVEWNDTRKTIMEOUT

; ---- 键盘钩子 (防 Alt+Tab 光标瞬移) ----
_hook_handle             := 0           ; WH_KEYBOARD_LL 句柄
_hook_callback           := 0           ; CallbackCreate 对象，必须持久化防止 GC 回收
_alt_down                := false       ; Alt 键当前是否按下
_win_down                := false       ; Win 键当前是否按下
_hook_reenable_pending   := false       ; 有延迟重启用定时器待处理

; ---- 日志 ----
_log_file := ""  ; 日志文件路径，在初始化时设置

; ============================================================
; 日志函数：追加一行带时间戳的日志到脚本同目录下的 log 文件
; 用于追踪运行流程，辅助定位闪退崩溃原因。
; ============================================================
Log(msg) {
    global _log_file
    if _log_file = ""
        _log_file := A_ScriptDir "\DynamicWindowTransparency.log"
    try FileAppend("[" A_YYYY "-" A_MM "-" A_DD " " A_Hour ":" A_Min ":" A_Sec "." A_MSec "] " msg "`n", _log_file)
}

; 需要跳过的系统窗口类名 (任务栏、阴影等)
SKIP_CLASSES := [
    "Shell_TrayWnd",           ; 任务栏
    "NotifyIconOverflowWindow", ; 通知区域溢出面板
    "SysShadow",               ; 系统窗口阴影
    "DV2ControlHost",          ; 桌面视图 (Desktop View)
    "Windows.UI.Core.CoreWindow", ; UWP 后台窗口
    "Progman",                 ; 桌面 (Program Manager)
    "WorkerW"                  ; 桌面壁纸/图标层
]

; ============================================================
; 初始化
; ============================================================

_active_hwnd := WinExist("A")  ; 获取当前活跃窗口
if _active_hwnd && IsRealWindow(_active_hwnd) {
    ScanWindows()              ; 初始扫描所有窗口
}

SetTimer(CheckActiveWindow, POLL_INTERVAL)  ; 检测窗口切换（轻量，不改全局）
SetTimer(AnimateOpacity,    FADE_INTERVAL)  ; 透明度动画
SetTimer(MaintenanceScan,   3000)           ; 定期扫描新窗口/清理旧窗口
SetTimer(HoverCheck,        HOVER_INTERVAL) ; 悬停聚焦检测

; 启用 X-Mouse（窗口激活跟踪），实现悬停聚焦但不抬升。
; 超时设为 HOVER_DELAY，与我们的悬停延迟同步。
; X-Mouse 在脚本运行期间保持开启；键盘钩子在 Alt+Tab 等
; 系统按键组合时临时关闭 X-Mouse 以防止光标瞬移。
InstallXMouseHook()
EnableXMouse(true, HOVER_DELAY)

Log("脚本启动，初始活跃窗口: " (WinExist("A") ? Format("0x{:X}", WinExist("A")) : "无"))

TrayTip "动态窗口透明度已启动", "Win+Z 暂停/恢复"

; ============================================================
; 设置窗口透明度
;
; 始终保持 WS_EX_LAYERED 样式，只通过
; SetLayeredWindowAttributes 调节 alpha。
; ============================================================
SetWindowOpacity(hwnd, alpha) {
    exStyle := DllCall("GetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr")
    if !(exStyle & 0x80000) {
        DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr", exStyle | 0x80000)
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0
            , "int", 0, "int", 0, "int", 0, "int", 0
            , "uint", 0x0017)
    }
    DllCall("SetLayeredWindowAttributes", "ptr", hwnd, "uint", 0, "uchar", alpha, "uint", 2)
}

; ============================================================
; 判断窗口是否为可追踪的普通用户窗口
; 跳过桌面、任务栏、IME 候选窗等系统/临时窗口
; ============================================================
IsRealWindow(hwnd) {
    global SKIP_CLASSES
    buf := Buffer(256)
    ; 检查类名是否在 SKIP_CLASSES 中
    DllCall("GetClassName", "ptr", hwnd, "ptr", buf, "int", 128)
    cls := StrGet(buf)
    for s in SKIP_CLASSES {
        if cls = s
            return false
    }
    ; 无标题窗口通常不是普通用户窗口
    DllCall("GetWindowText", "ptr", hwnd, "ptr", buf, "int", 256)
    title := StrGet(buf)
    if title = ""
        return false
    ; 工具窗口（WS_EX_TOOLWINDOW）不是普通用户窗口
    ; IME 候选窗（含小狼毫）、浮动面板等使用此样式
    exStyle := DllCall("GetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr")
    if exStyle & 0x00000080  ; WS_EX_TOOLWINDOW
        return false
    return true
}

; ============================================================
; 判断窗口是否属于排除进程列表
; 属于排除进程的窗口不参与透明度变化。
; ============================================================
IsExcludedProcess(hwnd) {
    global EXCLUDE_PROCESSES
    if EXCLUDE_PROCESSES.Length = 0
        return false
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid:=0)
    if !pid
        return false
    try procName := ProcessGetName(pid)
    catch
        return false
    for name in EXCLUDE_PROCESSES {
        if StrCompare(procName, name, false) = 0
            return true
    }
    return false
}

; ============================================================
; 定时检测当前活跃窗口是否发生变化
; 新活跃窗口瞬间到位（alpha=255），永不经过半透明状态
;
; 轻量实现：只更新旧/新活跃窗口的 target，不调用
; ScanWindows（避免临时窗口触发全量重扫导致闪烁）。
; 全量扫描由 MaintenanceScan 定时执行。
;
; 跳过系统窗口（桌面、IME 候选窗等），防止临时窗口
; 误将活跃窗口句柄指向非用户窗口。
;
; 当悬停聚焦（HOVER_FOCUS）激活时，不覆盖 _active_hwnd。
; ============================================================
CheckActiveWindow() {
    global _paused, _active_hwnd, _opacity_map
    global UNFOCUSED_OPACITY, _hover_active, _hover_foreground_at_start

    if _paused
        return

    ; ---- 悬停聚焦激活时，不覆盖 _active_hwnd ----
    ;
    ; 在悬停模式（RAISE_ON_ACTIVATE=false）下，_active_hwnd 是悬停聚焦的窗口，
    ; 但前台窗口（WinExist("A")）仍是旧窗口。因此不能拿 WinExist("A") 和
    ; _active_hwnd 比较，否则会误判为"用户切换了窗口"而立即撤销悬停。
    ;
    ; 正确做法：保存进入悬停模式时的前台窗口（_hover_foreground_at_start）。
    ; 仅当前台窗口变得**既不是**旧前台窗口、**也不是**悬停窗口时，
    ; 才认为用户主动切换到了第三个窗口，退出悬停模式。
    ; ============================================================
    if _hover_active {
        if !WinExist("ahk_id " _active_hwnd) {
            ; 悬停聚焦的窗口已关闭
            Log("悬停模式退出: 悬停窗口已关闭 0x" Format("{:X}", _active_hwnd))
            _hover_active := false
        } else {
            active := WinExist("A")
            if active && active != _hover_foreground_at_start && active != _active_hwnd {
                ; 前台窗口变成了第三个窗口，退出悬停模式
                Log("悬停模式退出: 前台窗口变更为 0x" Format("{:X}", active))
                _hover_active := false
            } else {
                return  ; 仍处于悬停聚焦状态，不做修改
            }
        }
    }

    active := WinExist("A")
    if active && IsRealWindow(active) && active != _active_hwnd {
        Log("活跃窗口切换: 0x" Format("{:X}", _active_hwnd) " → 0x" Format("{:X}", active))
        ; 旧活跃窗口设回非聚焦透明度
        if _opacity_map.Has(_active_hwnd) && _opacity_map[_active_hwnd].target != UNFOCUSED_OPACITY {
            _opacity_map[_active_hwnd].target := UNFOCUSED_OPACITY
        }
        ; 排除进程不改变透明度，也不加入 _opacity_map
        if !IsExcludedProcess(active) {
            SetWindowOpacity(active, 255)
            if _opacity_map.Has(active) {
                _opacity_map[active].current := 255
                _opacity_map[active].target := 255
            }
        }
        _active_hwnd := active
    }
}

; ============================================================
; X-Mouse 运行时控制
;
; 使用 SystemParametersInfo API 启用/禁用 Windows 内置的
; "活跃窗口跟踪"（X-Mouse），实现悬停聚焦但不抬升窗口。
;
; 这是 Windows 内核级功能（与 UserPreferencesMask 注册表项
; 相同的机制），与 SetActiveWindow / SetFocus 等用户态 API
; 不同，它可以真正分离"活跃窗口"（键盘输入目标）与
; "前台窗口"（Z-order 顶部）。
;
; 不修改注册表（不使用 SPIF_UPDATEINIFILE 标志）。
; ============================================================

EnableXMouse(noRaise := true, timeoutMs := 500) {
    global _xmouse_active, _xmouse_saved, _xmouse_saved_tracking, _xmouse_saved_zorder, _xmouse_saved_timeout

    ; 保存当前设置（仅在第一次启用时保存一次）
    if !_xmouse_saved {
        DllCall("SystemParametersInfo", "UInt", 0x1000, "UInt", 0, "UInt*", &_xmouse_saved_tracking, "UInt", 0)
        DllCall("SystemParametersInfo", "UInt", 0x100C, "UInt", 0, "UInt*", &_xmouse_saved_zorder, "UInt", 0)
        DllCall("SystemParametersInfo", "UInt", 0x2002, "UInt", 0, "UInt*", &_xmouse_saved_timeout, "UInt", 0)
        _xmouse_saved := true
        Log("X-Mouse 首次启用，保存原始设置: tracking=" _xmouse_saved_tracking " zorder=" _xmouse_saved_zorder " timeout=" _xmouse_saved_timeout)
    }

    ; 设置 Z-order（先设好再启用跟踪）
    DllCall("SystemParametersInfo", "UInt", 0x100D, "UInt", 0, "UInt", noRaise ? 0 : 1, "UInt", 0)
    ; 设置超时（光标静止多久后激活）
    DllCall("SystemParametersInfo", "UInt", 0x2003, "UInt", 0, "UInt", timeoutMs, "UInt", 0)
    ; 启用跟踪——此调用触发 Windows 激活光标下的窗口
    DllCall("SystemParametersInfo", "UInt", 0x1001, "UInt", 0, "UInt", 1, "UInt", 0)

    _xmouse_active := true
    _xmouse_hook_disabled := false
    Log("X-Mouse 已启用 noRaise=" noRaise " timeout=" timeoutMs)
}

RestoreXMouse() {
    global _xmouse_active, _xmouse_hook_disabled, _xmouse_saved_tracking, _xmouse_saved_zorder, _xmouse_saved_timeout
    if !_xmouse_active && !_xmouse_hook_disabled
        return

    Log("X-Mouse 恢复: 恢复前 active=" _xmouse_active " hook_disabled=" _xmouse_hook_disabled)

    ; 恢复原始设置（注意顺序：先恢复行为，再关闭跟踪）
    DllCall("SystemParametersInfo", "UInt", 0x100D, "UInt", 0, "UInt", _xmouse_saved_zorder, "UInt", 0)
    DllCall("SystemParametersInfo", "UInt", 0x2003, "UInt", 0, "UInt", _xmouse_saved_timeout, "UInt", 0)
    DllCall("SystemParametersInfo", "UInt", 0x1001, "UInt", 0, "UInt", _xmouse_saved_tracking, "UInt", 0)

    _xmouse_active := false
    _xmouse_hook_disabled := false
}

; ============================================================
; 低层级键盘钩子 (WH_KEYBOARD_LL)
;
; 检测 Alt+Tab / Win+Key 等系统按键组合，提前关闭 X-Mouse，
; 防止 Windows 将光标瞬移到新窗口上。组合键结束后恢复。
; ============================================================

InstallXMouseHook() {
    global _hook_handle, _hook_callback
    hModule := DllCall("GetModuleHandle", "ptr", 0, "ptr")
    _hook_callback := CallbackCreate(XMouseHookProc, "F", 3)
    _hook_handle := DllCall("SetWindowsHookEx", "int", 13  ; WH_KEYBOARD_LL
        , "ptr", _hook_callback, "ptr", hModule, "uint", 0)
}

XMouseHookProc(nCode, wParam, lParam) {
    global _alt_down, _win_down, _xmouse_active, _xmouse_hook_disabled
    global _hook_reenable_pending

    if nCode >= 0 {
        ; Alt 键产生 WM_SYSKEYDOWN(0x104)/WM_SYSKEYUP(0x105) 而非
        ; WM_KEYDOWN(0x100)/WM_KEYUP(0x101)，必须同时处理两种消息。
        if wParam = 0x100 || wParam = 0x104 {  ; WM_KEYDOWN || WM_SYSKEYDOWN
            vkCode := NumGet(lParam + 0, 0, "UInt")
            if vkCode = 18 {         ; VK_MENU (Alt)
                _alt_down := true
                Log("键盘钩子: Alt 按下")
                ; 取消待处理的延迟重启用
                if _hook_reenable_pending {
                    SetTimer(HookReenableAfterDelay, 0)
                    _hook_reenable_pending := false
                    Log("键盘钩子: 取消待处理的延迟重启用")
                }
                ; 关闭 X-Mouse。
                ; 注意：使用 SPI 0 标志（不广播 WM_SETTINGCHANGE），
                ; 避免 SystemParametersInfo 重入钩子回调导致栈溢出。
                if _xmouse_active {
                    DllCall("SystemParametersInfo", "UInt", 0x1001
                        , "UInt", 0, "UInt", 0, "UInt", 0)
                    _xmouse_active := false
                    _xmouse_hook_disabled := true
                    Log("X-Mouse 已关闭 (Alt 按下触发)")
                }
            } else if vkCode = 91 || vkCode = 92 {  ; VK_LWIN / VK_RWIN
                _win_down := true
                Log("键盘钩子: Win 按下")
                ; 取消待处理的延迟重启用
                if _hook_reenable_pending {
                    SetTimer(HookReenableAfterDelay, 0)
                    _hook_reenable_pending := false
                }
                ; 关闭 X-Mouse（同上）
                if _xmouse_active {
                    DllCall("SystemParametersInfo", "UInt", 0x1001
                        , "UInt", 0, "UInt", 0, "UInt", 0)
                    _xmouse_active := false
                    _xmouse_hook_disabled := true
                    Log("X-Mouse 已关闭 (Win 按下触发)")
                }
            }
        } else if wParam = 0x101 || wParam = 0x105 {  ; WM_KEYUP || WM_SYSKEYUP
            vkCode := NumGet(lParam + 0, 0, "UInt")
            if vkCode = 18 {
                _alt_down := false
                Log("键盘钩子: Alt 释放")
                ; 不立即重启用 SPIF_SENDCHANGE（会阻塞钩子回调导致超时），
                ; 改为延迟 200ms 后在主线程中重启用。
                if !_win_down && _xmouse_hook_disabled && !_hook_reenable_pending {
                    _hook_reenable_pending := true
                    SetTimer(HookReenableAfterDelay, -200)
                    Log("键盘钩子: 设定 200ms 延迟重启用")
                }
            } else if vkCode = 91 || vkCode = 92 {
                _win_down := false
                Log("键盘钩子: Win 释放")
                if !_alt_down && _xmouse_hook_disabled && !_hook_reenable_pending {
                    _hook_reenable_pending := true
                    SetTimer(HookReenableAfterDelay, -200)
                }
            }

            ; 所有修饰键释放后的兜底检查（任何键抬起都可能触发）
            if !_alt_down && !_win_down && _xmouse_hook_disabled && !_hook_reenable_pending {
                _hook_reenable_pending := true
                SetTimer(HookReenableAfterDelay, -200)
                Log("键盘钩子: 兜底触发重启用 (vkCode=" vkCode ")")
            }
        }
    }
    return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
}

; 延迟重启用 X-Mouse：在修饰键释放后稍等片刻再调用
; SPIF_SENDCHANGE，避免在钩子回调中阻塞导致被旁路。
HookReenableAfterDelay() {
    global _alt_down, _win_down, _xmouse_hook_disabled, _hook_reenable_pending
    Log("延迟重启用触发, _xmouse_hook_disabled=" _xmouse_hook_disabled " _alt_down=" _alt_down " _win_down=" _win_down)
    if _xmouse_hook_disabled && !_alt_down && !_win_down {
        EnableXMouse(true, HOVER_DELAY)
    }
    ; 必须在 EnableXMouse 完成之后才释放 guard，
    ; 否则 EnableXMouse 中途若被 Log/SystemParametersInfo 插队，
    ; 钩子回调会看到 _xmouse_hook_disabled=1 && _hook_reenable_pending=0，
    ; 重新调度定时器 → 无限循环。
    _hook_reenable_pending := false
}

; ============================================================
; 悬停聚焦检测
;
; 鼠标悬停到新窗口时，等待 HOVER_DELAY 毫秒后触发聚焦。
; 期间如果鼠标离开该窗口（移到其它窗口或空白区域），
; 取消待处理的聚焦。
;
; 根据 RAISE_ON_ACTIVATE 决定聚焦方式（不抬升 / 抬升）。
; ============================================================
HoverCheck() {
    global HOVER_FOCUS, RAISE_ON_ACTIVATE, HOVER_DELAY, _paused
    global _active_hwnd, _opacity_map, _last_hover, _hover_active
    global _hover_pending_hwnd, _hover_pending_at
    global UNFOCUSED_OPACITY

    if _paused || !HOVER_FOCUS
        return

    ; 拖拽中不切换聚焦
    if GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
        return

    ; 获取光标下窗口
    MouseGetPos(,, &mouse_hwnd)
    if !mouse_hwnd {
        _hover_pending_hwnd := 0
        return
    }

    ; 获取顶层父窗口
    root_hwnd := DllCall("GetAncestor", "ptr", mouse_hwnd, "uint", 2, "ptr")
    if !root_hwnd
        root_hwnd := mouse_hwnd

    ; ---- 鼠标仍在上次检测到的窗口上 ----
    if root_hwnd = _last_hover {
        ; 有悬停等待触发？
        if _hover_pending_hwnd && _hover_pending_hwnd = root_hwnd {
            if A_TickCount - _hover_pending_at >= HOVER_DELAY {
                ; 延迟已到，触发聚焦
                _hover_pending_hwnd := 0
                DoHoverFocus(root_hwnd)
            }
        }
        return
    }

    ; ---- 鼠标移到新窗口 ----
    _last_hover := root_hwnd
    _hover_pending_hwnd := 0  ; 取消之前的待处理

    ; 跳过系统/桌面/IME 窗口
    if !IsRealWindow(root_hwnd)
        return

    ; 跳过已经是活跃窗口
    if root_hwnd = _active_hwnd
        return

    ; 开始悬停等待
    _hover_pending_hwnd := root_hwnd
    _hover_pending_at := A_TickCount
}

; ============================================================
; 执行悬停聚焦（定时器延迟到期后调用）
; ============================================================
DoHoverFocus(hwnd) {
    global RAISE_ON_ACTIVATE, _active_hwnd, _opacity_map, _hover_active
    global UNFOCUSED_OPACITY, _hover_foreground_at_start

    Log("执行悬停聚焦: hwnd=0x" Format("{:X}", hwnd) " 旧活跃=0x" Format("{:X}", _active_hwnd) " RAISE_ON_ACTIVATE=" RAISE_ON_ACTIVATE)

    ; 旧活跃窗口设回非聚焦透明度
    if _opacity_map.Has(_active_hwnd) {
        _opacity_map[_active_hwnd].target := UNFOCUSED_OPACITY
    }

    ; 排除进程不改变透明度，也不加入 _opacity_map
    if !IsExcludedProcess(hwnd) {
        ; 新窗口设为不透明
        SetWindowOpacity(hwnd, 255)
        if _opacity_map.Has(hwnd) {
            _opacity_map[hwnd].current := 255
            _opacity_map[hwnd].target := 255
        }
    }

    _active_hwnd := hwnd

    if RAISE_ON_ACTIVATE {
        _hover_active := false
        WinActivate("ahk_id " hwnd)
    } else {
        _hover_foreground_at_start := WinExist("A")
        _hover_active := true
        ; X-Mouse 已在启动时全局启用（超时 = HOVER_DELAY），
        ; 此刻光标在 B 上已停留了 HOVER_DELAY 毫秒，
        ; Windows 内核自动将 B 设为活跃窗口（键盘输入目标），
        ; 但保持 A 在前台（Z-order 不变）。
        ;
        ; 无需额外调用 EnableXMouse — 它始终保持开启，
        ; 键盘钩子在 Alt+Tab 时临时关闭 X-Mouse 以防光标瞬移。
    }
}

; ============================================================
; 定期维护扫描：发现新窗口、清理已关闭窗口
; 独立定时器，不影响 CheckActiveWindow 的响应速度。
; ============================================================
MaintenanceScan() {
    global _active_hwnd
    if _active_hwnd && IsRealWindow(_active_hwnd) {
        ScanWindows()
    }
}

; ============================================================
; 枚举所有可见顶层窗口，为每个窗口分配目标透明度
; ============================================================
ScanWindows() {
    global _active_hwnd, _opacity_map, SKIP_CLASSES
    global FOCUSED_OPACITY, UNFOCUSED_OPACITY, SKIP_ALWAYSONTOP, EXCLUDE_PROCESSES
    global _windowState

    seen := Map()                            ; 记录本次枚举到的窗口
    active := _active_hwnd

    ; EnumWindows 回调 - 对每个顶层窗口调用一次
    enum_fn(hwnd, _) {
        ; 跳过不可见窗口
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            return 1

        ; 获取窗口类名
        buf := Buffer(256)
        DllCall("GetClassName", "ptr", hwnd, "ptr", buf, "int", 128)
        cls := StrGet(buf)

        ; 跳过系统/Shell窗口 (任务栏、阴影等)
        for s in SKIP_CLASSES {
            if cls = s
                return 1
        }

        ; 获取窗口标题
        DllCall("GetWindowText", "ptr", hwnd, "ptr", buf, "int", 256)
        title := StrGet(buf)
        ; 跳过无标题窗口
        if title = ""
            return 1

        ; ---- 功能: 跳过置顶窗口 ----
        if SKIP_ALWAYSONTOP {
            exStyle := DllCall("GetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr")
            if exStyle & 0x00000008  ; WS_EX_TOPMOST
                return 1
        }

        ; ---- 功能: 排除指定进程（不改变其透明度） ----
        if IsExcludedProcess(hwnd)
            return 1

        ; 根据是否为活跃窗口设置目标透明度
        target := (hwnd = active) ? FOCUSED_OPACITY : UNFOCUSED_OPACITY

        if _opacity_map.Has(hwnd) {
            _opacity_map[hwnd].target := target
        } else {
            curr := 255
            try curr := WinGetTransparent("ahk_id " hwnd)
            if curr = "" || curr < 0
                curr := 255
            _opacity_map[hwnd] := {current: curr, target: target}
        }

        ; 记录最小化状态
        try _windowState[hwnd] := WinGetMinMax("ahk_id " hwnd)

        seen[hwnd] := 1
        return 1
    }

    cb := CallbackCreate(enum_fn, "F", 2)
    DllCall("EnumWindows", "ptr", cb, "ptr", 0)
    CallbackFree(cb)

    ; 清理已关闭或不再显示的窗口（先收集再删除，避免迭代时修改 Map）
    removeList := []
    for hwnd in _opacity_map {
        if !seen.Has(hwnd)
            removeList.Push(hwnd)
    }
    for hwnd in removeList {
        _opacity_map.Delete(hwnd)
    }
    removeList := []
    for hwnd in _windowState {
        if !seen.Has(hwnd)
            removeList.Push(hwnd)
    }
    for hwnd in removeList {
        _windowState.Delete(hwnd)
    }
}

; ============================================================
; 动画定时器：逐步拉近所有窗口透明度至目标值
; 活跃窗口的渐变已由 CheckActiveWindow 瞬间到位处理，
; 此函数只负责非活跃窗口的 255→UNFOCUSED_OPACITY 渐变。
; ============================================================
AnimateOpacity() {
    global _opacity_map, FADE_STEP, _windowState
    global RESTORE_SPEED

    ; ---- 窗口状态维护 + 渐变动画 ----
    remove := []

    for hwnd, entry in _opacity_map {
        if !WinExist("ahk_id " hwnd) {
            remove.Push(hwnd)
            continue
        }

        cur := entry.current
        tgt := entry.target

        ; ---- 窗口刚从最小化恢复 → 瞬间到位 ----
        try {
            mm := WinGetMinMax("ahk_id " hwnd)
            prev := _windowState.Has(hwnd) ? _windowState[hwnd] : 0
            _windowState[hwnd] := mm
            if RESTORE_SPEED && prev = -1 && mm = 0 {
                if cur != tgt {
                    SetWindowOpacity(hwnd, tgt)
                    entry.current := tgt
                }
                continue
            }
        }

        if cur = tgt                                    ; 已达目标
            continue

        if cur < tgt                                    ; 向目标前进一步
            cur := Min(cur + FADE_STEP, tgt)
        else
            cur := Max(cur - FADE_STEP, tgt)

        entry.current := cur
        SetWindowOpacity(hwnd, cur)
    }

    for hwnd in remove {
        _opacity_map.Delete(hwnd)
        if _windowState.Has(hwnd)
            _windowState.Delete(hwnd)
    }
}

; ============================================================
; 快捷键
; ============================================================

; Win+Z: 暂停/恢复透明效果
#z:: {
    global _paused, _opacity_map, _active_hwnd, _hover_active, _last_hover
    global _hover_pending_hwnd, _hover_foreground_at_start
    _paused := !_paused
    if _paused {
        for hwnd in _opacity_map {
            try SetWindowOpacity(hwnd, 255)
        }
        _opacity_map := Map()
        RestoreXMouse()
        _active_hwnd := 0
        _hover_active := false
        _last_hover := 0
        _hover_pending_hwnd := 0
        _hover_foreground_at_start := 0
        TrayTip "动态透明度: 已暂停", "所有窗口已恢复不透明"
    } else {
        EnableXMouse(true, HOVER_DELAY)
        TrayTip "动态透明度: 已恢复"
    }
}

; Win+Esc: 退出脚本
#Esc:: {
    RestoreXMouse()
    ExitApp
}
