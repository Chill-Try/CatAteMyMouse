#Requires AutoHotkey v2.0
#SingleInstance Force

cursorPath := "D:\Code_Space\AutoHotkey\click.cur"

; 按你的屏幕缩放改：
; 100% 用 32
; 150% 用 48
; 200% 用 64
; 300% 用 96
cursorSize := 48

IMAGE_CURSOR := 2
LR_LOADFROMFILE := 0x10
SPI_SETCURSORS := 0x57

; 常见系统光标角色
cursorRoles := [
    32512, ; OCR_NORMAL
    32513, ; OCR_IBEAM 文本输入
    32514, ; OCR_WAIT
    32515, ; OCR_CROSS
    32516, ; OCR_UP
    32640, ; OCR_SIZE
    32642, ; OCR_SIZENWSE
    32643, ; OCR_SIZENESW
    32644, ; OCR_SIZEWE
    32645, ; OCR_SIZENS
    32646, ; OCR_SIZEALL
    32648, ; OCR_NO
    32649, ; OCR_HAND 链接
    32650, ; OCR_APPSTARTING
    32651  ; OCR_HELP
]

pressedCount := 0

~*LButton::PressCursor()
~*RButton::PressCursor()
~*MButton::PressCursor()
~*XButton1::PressCursor()
~*XButton2::PressCursor()

~*LButton Up::ReleaseCursor()
~*RButton Up::ReleaseCursor()
~*MButton Up::ReleaseCursor()
~*XButton1 Up::ReleaseCursor()
~*XButton2 Up::ReleaseCursor()

PressCursor() {
    global pressedCount

    pressedCount += 1
    if pressedCount = 1
        ApplyCustomCursor()
}

ReleaseCursor() {
    global pressedCount

    pressedCount := Max(pressedCount - 1, 0)
    if pressedCount = 0
        RestoreCursor()
}

ApplyCustomCursor() {
    global cursorPath, cursorSize, cursorRoles, IMAGE_CURSOR, LR_LOADFROMFILE

    for role in cursorRoles {
        hCur := DllCall(
            "LoadImage",
            "Ptr", 0,
            "Str", cursorPath,
            "UInt", IMAGE_CURSOR,
            "Int", cursorSize,
            "Int", cursorSize,
            "UInt", LR_LOADFROMFILE,
            "Ptr"
        )

        if !hCur {
            MsgBox "加载光标失败: " cursorPath
            return
        }

        ; SetSystemCursor 会接管/销毁句柄，所以每个 role 都要重新 LoadImage
        DllCall("SetSystemCursor", "Ptr", hCur, "UInt", role)
    }
}

RestoreCursor(*) {
    global SPI_SETCURSORS
    DllCall("SystemParametersInfo", "UInt", SPI_SETCURSORS, "UInt", 0, "Ptr", 0, "UInt", 0)
}

OnExit RestoreCursor
