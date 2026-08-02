#Requires AutoHotkey v2.0
#Include Lib\UIA.ahk

; 使用不可见按键屏蔽 Alt 快捷键释放后的系统菜单激活
A_MenuMaskKey := "vkE8"

; =====================================================
; 配置区域
; =====================================================

; 当前窗口内切换文本框焦点的快捷键
TextFocusHotkey := "!Esc"

; 防止一次按键因系统重复或 Alt 状态变化触发两次
TextFocusDebounceMs := 120

; 文本框聚焦方式："Click" 只用真实点击；"SetFocusThenClick" 先 Focus 再点击
TextFocusMethod := "Click"

; 聚焦文本框后轻点控件，让输入法候选窗获得正确的插入光标坐标
TextFocusClickAfterSetFocus := true

; 触发文本框切换后屏蔽本次 Alt 松开对窗口菜单的影响
TextFocusSuppressAltMenu := true

; 轻点控件后是否把鼠标移回原位
TextFocusRestoreMouseAfterClick := true

; 轻点后延迟多久再把鼠标移回原位
TextFocusMouseRestoreDelay := 200

; 点击位置：优先按比例点击，X/Y 均为控件宽高比例
TextFocusClickXRatio := 0.5
TextFocusClickYRatio := 0.5

; 如果 TextFocusClickXRatio 设为空字符串，则改用距离文本框左侧的像素偏移
TextFocusClickXOffset := 24

; 聚焦后是否把文本光标移动到当前行尾
TextFocusMoveCaretToLineEnd := true

; UIA 返回的文本框矩形低于这个尺寸时，视为 caret/占位矩形，改用父级或窗口区域点击
TextFocusMinClickableWidth := 80
TextFocusMinClickableHeight := 12

; Alt+Esc 会尝试聚焦的 UIA 控件类型，覆盖 input/textarea/contenteditable 等网页控件
TextFocusControlTypes := ["Edit", "ComboBox", "Document", "Custom"]

; 资源管理器 UIA 树很大，只扫 Edit，避免遍历文件列表导致延迟
TextFocusExplorerControlTypes := ["Edit"]

; Chrome 网页中的 select 元素不作为文本框候选
TextFocusIgnoreChromeSelect := true

; 调试日志：复现问题后查看同目录 AltEsc.log
TextFocusDebugLog := true
TextFocusLogFile := A_ScriptDir "\AltEsc.log"

; =====================================================
; 全局状态
; =====================================================

TextFocusLastIndex := Map()   ; Alt+Esc 每个窗口内文本框轮转位置
TextFocusCaretPoints := Map() ; Alt+Esc 每个文本框上次记录的 caret 坐标
TextFocusLastHotkeyTick := 0  ; Alt+Esc 防抖时间戳
TextFocusBusy := false        ; Alt+Esc 防重入
TextFocusNeedsAltUpMask := false ; Alt+Esc 后屏蔽物理 Alt 抬起触发菜单

; 注册可配置的文本框焦点切换快捷键
RegisterTextFocusHotkey()

; =====================================================
; Alt+Esc — 在当前窗口内按面积从大到小切换文本框焦点
; =====================================================

RegisterTextFocusHotkey()
{
    global TextFocusHotkey

    if (TextFocusHotkey = "")
        return

    if (IsAltTextFocusHotkey(&baseKey))
    {
        ; 物理 Alt 按住时拦截裸按键，避免逻辑 Alt 被临时释放后 Esc 透传给应用。
        HotIf(IsTextFocusPhysicalHotkeyActive)
        Hotkey("*" baseKey, (*) => HandleTextFocusHotkey())
        HotIf()

        ; 只在 Alt+Esc 触发后拦截一次 Alt Up，避免焦点跳到窗口菜单栏。
        HotIf(IsTextFocusAltUpMaskNeeded)
        Hotkey("*LAlt Up", (*) => SuppressTextFocusAltUpMenu())
        Hotkey("*RAlt Up", (*) => SuppressTextFocusAltUpMenu())
        HotIf()
    }
    else
    {
        Hotkey(TextFocusHotkey, (*) => HandleTextFocusHotkey())
    }
}

IsAltTextFocusHotkey(&baseKey)
{
    global TextFocusHotkey

    key := RegExReplace(TextFocusHotkey, "^[~*$<>!^+#]+")
    baseKey := key
    return InStr(TextFocusHotkey, "!")
}

IsTextFocusPhysicalHotkeyActive(*)
{
    global TextFocusHotkey

    if (InStr(TextFocusHotkey, "!") && !GetKeyState("Alt", "P"))
        return false
    if (InStr(TextFocusHotkey, "+") && !GetKeyState("Shift", "P"))
        return false
    if (InStr(TextFocusHotkey, "^") && !GetKeyState("Ctrl", "P"))
        return false
    if (InStr(TextFocusHotkey, "#") && !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P"))
        return false
    return true
}

IsTextFocusAltUpMaskNeeded(*)
{
    global TextFocusNeedsAltUpMask
    return TextFocusNeedsAltUpMask
}

SuppressTextFocusAltUpMenu()
{
    global TextFocusNeedsAltUpMask

    TextFocusNeedsAltUpMask := false
    Send("{" A_MenuMaskKey "}")
}

HandleTextFocusHotkey()
{
    global TextFocusSuppressAltMenu, TextFocusDebounceMs, TextFocusLastHotkeyTick, TextFocusBusy, TextFocusNeedsAltUpMask

    if (TextFocusBusy)
        return

    now := A_TickCount
    if (now - TextFocusLastHotkeyTick < TextFocusDebounceMs)
        return
    TextFocusLastHotkeyTick := now
    TextFocusBusy := true

    try
    {
        ; 允许物理 Alt 按住时连续切换，但点击前释放逻辑 Alt，避免变成 Alt+Click。
        Send("{Blind}{Alt up}")
        if (TextFocusSuppressAltMenu)
            TextFocusNeedsAltUpMask := true
        FocusNextTextBoxInActiveWindow()
        if (TextFocusSuppressAltMenu)
            Send("{" A_MenuMaskKey "}")
    }
    catch
    {
    }
    TextFocusBusy := false
}

FocusNextTextBoxInActiveWindow()
{
    global TextFocusLastIndex

    hwnd := WinExist("A")
    if (!hwnd)
        return

    textBoxes := GetSortedTextBoxes(hwnd)
    count := textBoxes.Length
    if (count = 0)
        return

    RememberFocusedTextCaret(textBoxes)

    currentIndex := 0
    for i, item in textBoxes
    {
        try
        {
            if (item.el.HasKeyboardFocus)
            {
                currentIndex := i
                break
            }
        }
    }

    if (currentIndex = 0 && TextFocusLastIndex.Has(hwnd))
        currentIndex := TextFocusLastIndex[hwnd]

    nextIndex := currentIndex + 1
    if (nextIndex > count)
        nextIndex := 1

    try
    {
        FocusTextBoxElement(textBoxes[nextIndex].el)
        TextFocusLastIndex[hwnd] := nextIndex
    }
}

FocusTextBoxElement(el)
{
    global TextFocusClickAfterSetFocus, TextFocusRestoreMouseAfterClick, TextFocusMouseRestoreDelay, TextFocusCaretPoints
    global TextFocusClickXOffset, TextFocusClickXRatio, TextFocusClickYRatio, TextFocusMethod, TextFocusMoveCaretToLineEnd

    if (TextFocusMethod = "SetFocusThenClick")
        el.SetFocus()
    if (!TextFocusClickAfterSetFocus && TextFocusMethod != "Click")
    {
        MoveTextCaretToLineEnd()
        return
    }

    ; Chromium/WebView 编辑器需要真实点击来建立 TSF/IME caret 坐标。
    try
    {
        loc := el.Location
        clickLoc := GetClickableTextElementRect(el, loc)
        elementKey := GetTextElementKey(el)
        branch := IsUsableTextClickRect(loc) ? "default" : "fallback-rect"
        pointText := "none"
        clickX := GetDefaultTextClickX(clickLoc)
        clickY := GetDefaultTextClickY(clickLoc)
        if (IsUsableTextClickRect(loc) && TextFocusCaretPoints.Has(elementKey) && IsPointInsideTextElement(TextFocusCaretPoints[elementKey], loc))
        {
            point := TextFocusCaretPoints[elementKey]
            pointText := FormatPoint(point)
            if (IsPointInsideScreen(point))
            {
                branch := "stored-caret"
                clickX := point.x
                clickY := point.y
            }
            else
            {
                branch := "offscreen-caret-center"
                ; 历史 caret 已滚出屏幕时，改点控件屏幕可见部分的中心，再用 End 移到当前行尾。
                visibleLoc := GetScreenVisibleTextElementRect(clickLoc)
                clickX := GetCenterTextClickX(visibleLoc)
                clickY := GetCenterTextClickY(visibleLoc)
            }
        }
        screen := GetVirtualScreenRect()
        visibleForLog := GetScreenVisibleTextElementRect(clickLoc)
        clickX := Min(Max(clickLoc.x + 1, clickX), clickLoc.x + Max(1, clickLoc.w - 1))
        clickY := Min(Max(clickLoc.y + 1, clickY), clickLoc.y + Max(1, clickLoc.h - 1))
        LogTextFocus("click branch=" branch
            " loc=" FormatRect(loc)
            " clickLoc=" FormatRect(clickLoc)
            " visible=" FormatRect(visibleForLog)
            " screen=" FormatRect(screen)
            " stored=" pointText
            " final=(" clickX "," clickY ")"
            " element=" GetElementDebugInfo(el))
    }
    catch as err
    {
        LogTextFocus("click error=" err.Message)
        return
    }

    saveCoordMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    if (TextFocusRestoreMouseAfterClick)
        MouseGetPos(&prevX, &prevY)

    try
        Click(clickX " " clickY " left 1")

    if (TextFocusRestoreMouseAfterClick)
    {
        Sleep(TextFocusMouseRestoreDelay)
        MouseMove(prevX, prevY, 0)
    }
    CoordMode("Mouse", saveCoordMode)

    if (TextFocusMoveCaretToLineEnd)
        MoveTextCaretToLineEnd()
}

GetDefaultTextClickX(loc)
{
    global TextFocusClickXOffset, TextFocusClickXRatio

    if (TextFocusClickXRatio != "")
        return loc.x + Round(loc.w * TextFocusClickXRatio)
    return loc.x + Min(Max(1, TextFocusClickXOffset), Max(1, loc.w - 1))
}

GetDefaultTextClickY(loc)
{
    global TextFocusClickYRatio
    return loc.y + Round(loc.h * TextFocusClickYRatio)
}

IsUsableTextClickRect(loc)
{
    global TextFocusMinClickableWidth, TextFocusMinClickableHeight
    return loc.w >= TextFocusMinClickableWidth && loc.h >= TextFocusMinClickableHeight
}

GetClickableTextElementRect(el, loc)
{
    if (IsUsableTextClickRect(loc))
        return loc

    try
    {
        parent := el.Parent
        Loop 8
        {
            parentLoc := parent.Location
            if (IsUsableTextClickRect(parentLoc) && RectIntersectsScreen(parentLoc))
                return GetScreenVisibleTextElementRect(parentLoc)
            parent := parent.Parent
        }
    }

    try
    {
        hwnd := WinExist("A")
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
        return {x: winX, y: winY, w: winW, h: winH}
    }

    return loc
}

GetCenterTextClickX(loc)
{
    return loc.x + Round(loc.w * 0.5)
}

GetCenterTextClickY(loc)
{
    return loc.y + Round(loc.h * 0.5)
}

GetScreenVisibleTextElementRect(loc)
{
    screen := GetVirtualScreenRect()
    left := Max(loc.x, screen.x)
    top := Max(loc.y, screen.y)
    right := Min(loc.x + loc.w, screen.x + screen.w)
    bottom := Min(loc.y + loc.h, screen.y + screen.h)

    if (right > left && bottom > top)
        return {x: left, y: top, w: right - left, h: bottom - top}
    return loc
}

RectIntersectsScreen(loc)
{
    screen := GetVirtualScreenRect()
    return loc.x < screen.x + screen.w
        && loc.x + loc.w > screen.x
        && loc.y < screen.y + screen.h
        && loc.y + loc.h > screen.y
}

IsPointInsideTextElement(point, loc)
{
    return point.x >= loc.x
        && point.x <= loc.x + loc.w
        && point.y >= loc.y
        && point.y <= loc.y + loc.h
}

IsPointInsideScreen(point)
{
    screen := GetVirtualScreenRect()
    return point.x >= screen.x
        && point.x <= screen.x + screen.w
        && point.y >= screen.y
        && point.y <= screen.y + screen.h
}

GetVirtualScreenRect()
{
    return {
        x: DllCall("user32\GetSystemMetrics", "int", 76, "int"),
        y: DllCall("user32\GetSystemMetrics", "int", 77, "int"),
        w: DllCall("user32\GetSystemMetrics", "int", 78, "int"),
        h: DllCall("user32\GetSystemMetrics", "int", 79, "int")
    }
}

MoveTextCaretToLineEnd()
{
    try
        Send("{End}")
}

LogTextFocus(message)
{
    global TextFocusDebugLog, TextFocusLogFile

    if (!TextFocusDebugLog)
        return

    try
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss.fff") " " message "`n", TextFocusLogFile, "UTF-8")
}

FormatRect(rect)
{
    return "(" rect.x "," rect.y "," rect.w "," rect.h ")"
}

FormatPoint(point)
{
    return "(" point.x "," point.y ")"
}

GetElementDebugInfo(el)
{
    info := ""
    try
        info .= "type=" el.Type " "
    try
        info .= "name=" StrReplace(el.Name, "`n", " ") " "
    try
        info .= "class=" el.ClassName " "
    try
        info .= "aid=" el.AutomationId " "
    try
        info .= "role=" el.AriaRole " "
    return Trim(info)
}

RememberFocusedTextCaret(textBoxes)
{
    global TextFocusCaretPoints

    try
    {
        focusedEl := UIA.GetFocusedElement()
        if (IsFocusableTextBox(focusedEl))
        {
            point := GetTextCaretPoint(focusedEl)
            if (point)
            {
                TextFocusCaretPoints[GetTextElementKey(focusedEl)] := point
                LogTextFocus("remember focused point=" FormatPoint(point)
                    " element=" GetElementDebugInfo(focusedEl))
            }
        }
    }

    for item in textBoxes
    {
        try
        {
            if (!item.el.HasKeyboardFocus)
                continue

            point := GetTextCaretPoint(item.el)
            if (point)
            {
                TextFocusCaretPoints[GetTextElementKey(item.el)] := point
                LogTextFocus("remember listed point=" FormatPoint(point)
                    " element=" GetElementDebugInfo(item.el))
            }
            return
        }
    }
}

GetTextElementKey(el)
{
    try
        return el.RuntimeId
    catch
    {
        try
            loc := el.Location
        catch
            return ""

        try
            name := el.Name
        catch
            name := ""
        return name "|" loc.x "|" loc.y "|" loc.w "|" loc.h
    }
}

GetTextCaretPoint(el)
{
    try
    {
        range := el.TextPattern.GetCaretRange()
        rects := range.GetBoundingRectangles()
        point := GetPointFromTextRects(rects)
        if (point)
            return point
    }

    try
    {
        ranges := el.TextPattern.GetSelection()
        if (ranges.Length > 0)
        {
            rects := ranges[1].GetBoundingRectangles()
            point := GetPointFromTextRects(rects)
            if (point)
                return point
        }
    }

    return 0
}

GetPointFromTextRects(rects)
{
    for rect in rects
    {
        if (rect.h <= 0)
            continue

        x := rect.x + Max(1, Min(3, Max(1, rect.w // 2)))
        y := rect.y + Max(1, rect.h // 2)
        return {x: x, y: y}
    }
    return 0
}

GetSortedTextBoxes(hwnd)
{
    global TextFocusControlTypes, TextFocusExplorerControlTypes

    startTick := A_TickCount
    result := []

    seen := Map()
    for rootInfo in GetTextFocusUIARoots(hwnd)
    {
        root := rootInfo.root
        controlTypes := (rootInfo.exe = "explorer.exe") ? TextFocusExplorerControlTypes : TextFocusControlTypes
        for typeName in controlTypes
        {
            typeTick := A_TickCount
            try
                elements := root.FindElements({Type:typeName}, 4)
            catch
                continue
            LogTextFocus("scan exe=" rootInfo.exe " type=" typeName " raw=" elements.Length " ms=" (A_TickCount - typeTick))

            for el in elements
            {
                if (!IsFocusableTextBox(el, typeName, rootInfo.isChromeBrowser))
                    continue

                key := GetTextElementKey(el)
                if (key != "" && seen.Has(key))
                    continue
                if (key != "")
                    seen[key] := true

                loc := el.Location
                area := loc.w * loc.h
                result.Push({el: el, area: area, x: loc.x, y: loc.y})
            }
        }
    }

    SortTextBoxesByArea(result)
    LogTextFocus("scan total exe=" (GetTextFocusProcessName(hwnd)) " found=" result.Length " ms=" (A_TickCount - startTick))
    return result
}

GetTextFocusUIARoots(hwnd)
{
    roots := []
    isChromeBrowser := false
    exe := ""

    try
    {
        cls := WinGetClass("ahk_id " hwnd)
        exe := StrLower(WinGetProcessName("ahk_id " hwnd))
        isChromeBrowser := (cls = "Chrome_WidgetWin_1" && StrLower(exe) = "chrome.exe")
    }

    if (isChromeBrowser)
    {
        ; Chrome 只取网页内容根，排除地址栏；地址栏可继续用 Ctrl+L。
        try
            roots.Push({root: UIA.ElementFromChromium("ahk_id " hwnd, 1000), isChromeBrowser: true, exe: exe})
        return roots
    }

    try
        roots.Push({root: UIA.ElementFromHandle(hwnd,,1000), isChromeBrowser: false, exe: exe})

    try
    {
        cls := WinGetClass("ahk_id " hwnd)
        if (cls = "Chrome_WidgetWin_1")
            roots.Push({root: UIA.ElementFromChromium("ahk_id " hwnd, 1000), isChromeBrowser: false, exe: exe})
    }

    return roots
}

GetTextFocusProcessName(hwnd)
{
    try
        return StrLower(WinGetProcessName("ahk_id " hwnd))
    catch
        return ""
}

IsFocusableTextBox(el, typeName := "", isChromeBrowser := false)
{
    global TextFocusIgnoreChromeSelect

    try
    {
        if (isChromeBrowser && TextFocusIgnoreChromeSelect && IsChromeSelectElement(el, typeName))
            return false

        if (!el.IsEnabled || !el.IsKeyboardFocusable || el.IsOffscreen)
            return false

        ; UIA 中有些只读值也暴露为 Edit，例如文件属性值；明确只读的一律跳过。
        if (el.IsValuePatternAvailable && el.ValueIsReadOnly)
            return false

        if (!el.IsValuePatternAvailable && !el.IsTextEditPatternAvailable && !el.IsTextPatternAvailable)
            return false

        ; Document/Custom 很容易匹配到整页容器，只接受明确像可编辑文本框的控件。
        if ((typeName = "Document" || typeName = "Custom") && !IsLikelyEditableTextBox(el))
            return false

        loc := el.Location
        if (loc.w <= 0 || loc.h <= 0)
            return false
    }
    catch
        return false

    return true
}

IsChromeSelectElement(el, typeName)
{
    if (typeName != "ComboBox")
        return false

    ; 原生 select 常暴露为 ComboBox；不要用裸 select，避免误伤 selected/selectable。
    role := ""
    aid := ""
    className := ""
    name := ""
    ariaProps := ""
    try
        role := StrLower(el.AriaRole)
    try
        aid := StrLower(el.AutomationId)
    try
        className := StrLower(el.ClassName)
    try
        name := StrLower(el.Name)
    try
        ariaProps := StrLower(el.AriaProperties)

    if (role = "textbox" || role = "searchbox")
        return false

    text := " " aid " " className " " name " " ariaProps " "
    return InStr(text, "selectbox")
        || InStr(text, "selectcontrol")
        || InStr(text, "_srcsl")
        || InStr(text, "_tgtsl")
        || InStr(text, "_tonesl")
        || InStr(text, "dropdown")
        || InStr(text, "drop down")
        || InStr(text, "下拉")
        || InStr(text, "语言选择")
}

IsLikelyEditableTextBox(el)
{
    try
    {
        if (el.IsTextEditPatternAvailable)
            return true
        if (el.IsValuePatternAvailable && !el.ValueIsReadOnly)
            return true
    }

    try
    {
        role := StrLower(el.AriaRole)
        if (role = "textbox" || role = "searchbox" || role = "combobox")
            return true
    }

    return false
}

; 面积大的文本框优先；同面积时按屏幕位置从上到下、从左到右
SortTextBoxesByArea(items)
{
    i := 2
    while (i <= items.Length)
    {
        current := items[i]
        j := i - 1
        while (j >= 1 && CompareTextBoxOrder(current, items[j]) < 0)
        {
            items[j + 1] := items[j]
            j--
        }
        items[j + 1] := current
        i++
    }
}

CompareTextBoxOrder(a, b)
{
    if (a.area != b.area)
        return (a.area > b.area) ? -1 : 1
    if (a.y != b.y)
        return (a.y < b.y) ? -1 : 1
    if (a.x != b.x)
        return (a.x < b.x) ? -1 : 1
    return 0
}
