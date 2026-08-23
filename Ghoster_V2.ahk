;Ghoster_V2.ahk
; Dims inactive windows, shows a transparent image across the desktop,
; Skrommel @2005
; AutoHotkey v2 translation

#Requires AutoHotkey v2.0
#SingleInstance Force

SetWinDelay(0)

^+x::ToggleMode()
^!x::ToggleEnabled()
^+s::ToggleBlankScreen()

applicationname := "Ghoster"
mainGui := ""
aboutGui := ""
guiid := 0
hCurs := 0
blankGui := ""
blankInputHook := ""
blankScreenActive := false
oldid := 0
oldtop := 0
progmanid := 0
taskbarid := 0
secondaryTaskbarIds := []
dimMode := "window"
dimEnabled := true
currentSettings := ""
monitorGuis := Map()

OnExit(EXIT)

START()

START() {
  global applicationname, mainGui, guiid, oldid, oldtop, progmanid, taskbarid, secondaryTaskbarIds, dimMode, dimEnabled, currentSettings

  settings := READINI()
  currentSettings := settings
  dimMode := NormalizeMode(settings.mode)
  dimEnabled := settings.enabled != 0
  if settings.modehotkey != "" && settings.modehotkey != "ERROR" {
    try {
      modehotkey := Trim(settings.modehotkey)
      if modehotkey != "^+x"
        Hotkey(modehotkey, (*) => ToggleMode(), "On")
    }
  }
  if settings.togglehotkey != "" && settings.togglehotkey != "ERROR" {
    try {
      togglehotkey := Trim(settings.togglehotkey)
      if togglehotkey != "^!x"
        Hotkey(togglehotkey, (*) => ToggleEnabled(), "On")
    }
  }
  TRAYMENU()
  CoordMode("Mouse", "Screen")
  progmanid := WinGetID("ahk_class Progman")
  taskbarid := WinGetID("ahk_class Shell_TrayWnd")
  secondaryTaskbarIds := WinGetList("ahk_class Shell_SecondaryTrayWnd")
  oldid := WinGetID("A")
  oldtop := WinGetExStyle("ahk_id " oldid) & 0x8

  params := ""
  desktopx := 0
  desktopy := 0
  desktopw := ""
  desktoph := ""
  x := settings.x
  y := settings.y
  width := settings.width
  height := settings.height

  if settings.multimon = 1 {
    desktopx := DllCall("GetSystemMetrics", "Int", 76, "Int")
    desktopy := DllCall("GetSystemMetrics", "Int", 77, "Int")
    desktopw := DllCall("GetSystemMetrics", "Int", 78, "Int")
    desktoph := DllCall("GetSystemMetrics", "Int", 79, "Int")
  }

  if settings.stretchwidth = 1 {
    width := desktopw
    x := 0
  }
  if settings.stretchheight = 1 {
    height := desktoph
    y := 0
  }
  if settings.keepaspect = 1 {
    if width != ""
      height := -1
    else
      width := -1
  }
  if x != ""
    params .= " X" x
  if y != ""
    params .= " Y" y
  if width != ""
    params .= " W" width
  if height != ""
    params .= " H" height

  mainGui := Gui("+ToolWindow -Disabled -SysMenu -Caption +E0x20", applicationname "Window")
  mainGui.MarginX := 0
  mainGui.MarginY := 0
  if settings.backcolor != ""
    mainGui.BackColor := settings.backcolor
  if settings.image != "" && FileExist(settings.image)
    mainGui.AddPicture(params, settings.image)
  mainGui.Show("X" desktopx " Y" desktopy " W" (desktopw != "" ? desktopw : A_ScreenWidth) " H" (desktoph != "" ? desktoph : A_ScreenHeight))
  guiid := mainGui.Hwnd
  WinSetTransparent(settings.transparency, applicationname "Window")
  settings.desktopx := desktopx
  settings.desktopy := desktopy
  settings.desktopw := (desktopw != "" ? desktopw : A_ScreenWidth)
  settings.desktoph := (desktoph != "" ? desktoph : A_ScreenHeight)

  if dimEnabled
    ApplyDimming(oldid, settings)
  else
    HideAllDimming()
  MainLoop(settings)
}

MainLoop(settings) {
  global applicationname, guiid, oldid, oldtop, progmanid, dimEnabled

  oldLButton := GetKeyState("LButton", "P")
  loop {
    Sleep(50)
    try
      winid := WinGetID("A")
    catch
      continue
    lbutton := GetKeyState("LButton", "P")
    clicked := lbutton && !oldLButton
    activeChanged := winid != oldid
    wintop := 0

    if !dimEnabled {
      oldid := winid
      oldLButton := lbutton
      continue
    }

    if IsBlacklistedWindow(winid, settings.blacklist) {
      oldLButton := lbutton
      continue
    }
    if IsTaskbarWindow(winid) && !IsMouseOverTaskbar() {
      oldLButton := lbutton
      continue
    }

    if (activeChanged || clicked) {
      try
        wintop := WinGetExStyle("ahk_id " winid) & 0x8
      catch
        continue
    }

    if activeChanged {
      if settings.showdesktop {
        if winid = progmanid {
          try {
            WinMove(settings.desktopx + settings.desktopw, settings.desktopy + settings.desktoph, , , applicationname "Window")
          }
          DestroyMonitorGuis()
          oldid := winid
          oldtop := wintop
          oldLButton := lbutton
          continue
        } else if oldid = progmanid {
          try {
            WinMove(settings.desktopx, settings.desktopy, , , applicationname "Window")
          }
        }
      }

      oldid := winid
      oldtop := wintop
    }

    if wintop {
      oldLButton := lbutton
      continue
    }

    if activeChanged || clicked {
      ApplyDimming(winid, settings)
    }
    oldLButton := lbutton
  }
}

IsBlacklistedWindow(winid, blacklistText) {
  if blacklistText = ""
    return false
  try
    proc := StrLower(WinGetProcessName("ahk_id " winid))
  catch
    return false
  try
    className := StrLower(WinGetClass("ahk_id " winid))
  catch
    className := ""
  try
    title := StrLower(WinGetTitle("ahk_id " winid))
  catch
    title := ""

  for _, item in StrSplit(blacklistText, ",") {
    name := Trim(StrLower(item))
    if name = ""
      continue
    if InStr(name, "class:") = 1 {
      if className = SubStr(name, 7)
        return true
      continue
    }
    if InStr(name, "title:") = 1 {
      if InStr(title, SubStr(name, 7))
        return true
      continue
    }
    if !InStr(name, ".") {
      if proc = name ".exe"
        return true
    }
    if proc = name
      return true
  }
  return false
}

IsTaskbarWindow(winid) {
  global taskbarid, secondaryTaskbarIds

  if winid = taskbarid
    return true
  for id in secondaryTaskbarIds {
    if winid = id
      return true
  }
  return false
}

IsMouseOverTaskbar() {
  global taskbarid, secondaryTaskbarIds

  try
    MouseGetPos(, , &mouseWinId)
  catch
    return false
  if mouseWinId = taskbarid
    return true
  for id in secondaryTaskbarIds {
    if mouseWinId = id
      return true
  }
  return false
}

NormalizeMode(mode) {
  mode := StrLower(Trim(mode))
  return mode = "monitor" ? "monitor" : "window"
}

ToggleMode(*) {
  global dimMode, dimEnabled, currentSettings, oldid

  dimMode := dimMode = "window" ? "monitor" : "window"
  if !dimEnabled {
    ShowStatusTip()
    return
  }
  winid := oldid
  try {
    if !WinExist("ahk_id " winid)
      winid := WinGetID("A")
  } catch {
    return
  }
  ApplyDimming(winid, currentSettings)
  ShowStatusTip()
}

ToggleEnabled(*) {
  global dimEnabled, currentSettings, oldid

  dimEnabled := !dimEnabled
  if !dimEnabled {
    HideAllDimming()
    ShowStatusTip()
    return
  }

  winid := oldid
  try {
    if !WinExist("ahk_id " winid)
      winid := WinGetID("A")
  } catch {
    ShowStatusTip()
    return
  }
  ApplyDimming(winid, currentSettings)
  ShowStatusTip()
}

ShowStatusTip() {
  global dimMode, dimEnabled

  if !dimEnabled
    text := "Ghoster: off"
  else
    text := dimMode = "monitor" ? "Ghoster: monitor mode" : "Ghoster: window mode"
  ToolTip(text)
  SetTimer(() => ToolTip(), -800)
}

ToggleBlankScreen(*) {
  BlankScreen()
}

BlankScreen(*) {
  global blankGui, blankInputHook, blankScreenActive

  if blankScreenActive
    return
  if IsObject(blankGui) {
    try
      blankGui.Destroy()
  }
  blankScreenActive := true

  GetVirtualScreenRect(&left, &top, &width, &height)
  blankGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
  blankGui.BackColor := "Black"
  blankGui.Show("NA X" left " Y" top " W" width " H" height)
  try
    WinMoveTop("ahk_id " blankGui.Hwnd)

  DllCall("ShowCursor", "Int", 0)

  SetBlankExitHotkeys("On")

  blankInputHook := InputHook("L1")
  blankInputHook.Start()
  blankInputHook.Wait()
  ExitBlank()
}

ExitBlank(*) {
  global blankGui, blankInputHook, blankScreenActive

  if !blankScreenActive
    return
  blankScreenActive := false

  SetBlankExitHotkeys("Off")

  if IsObject(blankInputHook) {
    try
      blankInputHook.Stop()
  }
  blankInputHook := ""

  DllCall("ShowCursor", "Int", 1)

  if IsObject(blankGui) {
    try
      blankGui.Destroy()
  }
  blankGui := ""
}

SetBlankExitHotkeys(state) {
  keys := [
    "LButton",
    "RButton",
    "MButton",
    "*LWin",
    "*RWin",
    "*Ctrl",
    "*LCtrl",
    "*RCtrl",
    "*Shift",
    "*LShift",
    "*RShift",
    "*Alt",
    "*LAlt",
    "*RAlt",
    "*Backspace",
    "*Delete",
    "*Insert"
  ]

  for key in keys {
    try
      Hotkey(key, ExitBlank, state)
  }
}

GetVirtualScreenRect(&left, &top, &width, &height) {
  left := DllCall("GetSystemMetrics", "Int", 76, "Int")
  top := DllCall("GetSystemMetrics", "Int", 77, "Int")
  width := DllCall("GetSystemMetrics", "Int", 78, "Int")
  height := DllCall("GetSystemMetrics", "Int", 79, "Int")
  if width <= 0
    width := A_ScreenWidth
  if height <= 0
    height := A_ScreenHeight
}

ApplyDimming(winid, settings) {
  global dimMode

  if dimMode = "monitor"
    ApplyMonitorDimming(winid, settings)
  else
    ApplyWindowDimming(winid, settings)
}

ApplyWindowDimming(winid, settings) {
  global applicationname, guiid, mainGui

  DestroyMonitorGuis()
  if IsObject(mainGui) {
    try {
      mainGui.Show("NA X" settings.desktopx " Y" settings.desktopy " W" settings.desktopw " H" settings.desktoph)
    }
  }

  if settings.showontop {
    try {
      WinMoveTop(applicationname "Window")
    }
  } else {
    SWP_NOMOVE := 2
    SWP_NOSIZE := 1
    SWP_NOACTIVATE := 0x10
    try {
      DllCall("SetWindowPos"
        , "Ptr", guiid
        , "Ptr", winid
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "UInt", SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
    }
    DimTaskbars(winid, guiid, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
  }
}

ApplyMonitorDimming(winid, settings) {
  global mainGui, monitorGuis, applicationname

  if IsObject(mainGui) {
    try {
      mainGui.Hide()
      WinMove(settings.desktopx + settings.desktopw, settings.desktopy + settings.desktoph, , , "ahk_id " mainGui.Hwnd)
    }
  }

  activeMonitor := GetWindowMonitorIndex(winid)
  count := MonitorGetCount()
  if count <= 1 {
    DestroyMonitorGuis()
    return
  }
  seen := Map()

  Loop count {
    index := A_Index
    if index = activeMonitor
      continue
    seen[index] := true
    if !monitorGuis.Has(index) {
      left := 0
      top := 0
      right := 0
      bottom := 0
      try {
        MonitorGet(index, &left, &top, &right, &bottom)
      } catch {
        continue
      }
      gui := Gui("+AlwaysOnTop +ToolWindow -Disabled -SysMenu -Caption +E0x20", applicationname "Monitor" index)
      gui.MarginX := 0
      gui.MarginY := 0
      gui.BackColor := settings.backcolor != "" && settings.backcolor != "ERROR" ? settings.backcolor : "000000"
      gui.Show("NA X" left " Y" top " W" (right - left) " H" (bottom - top))
      WinSetTransparent(settings.transparency, "ahk_id " gui.Hwnd)
      monitorGuis[index] := gui
    } else {
      try
        monitorGuis[index].Show("NA")
    }
  }

  removeIndexes := []
  for index, gui in monitorGuis {
    if !seen.Has(index)
      removeIndexes.Push(index)
  }
  for index in removeIndexes {
    if monitorGuis.Has(index) {
      gui := monitorGuis[index]
      try
        gui.Destroy()
      monitorGuis.Delete(index)
    }
  }
}

GetWindowMonitorIndex(winid) {
  px := 0
  py := 0
  try {
    WinGetPos(&x, &y, &w, &h, "ahk_id " winid)
    px := x + w // 2
    py := y + h // 2
  } catch {
    try
      MouseGetPos(&px, &py)
    catch
      return MonitorGetPrimary()
  }

  count := MonitorGetCount()
  Loop count {
    left := 0
    top := 0
    right := 0
    bottom := 0
    try {
      MonitorGet(A_Index, &left, &top, &right, &bottom)
    } catch {
      continue
    }
    if px >= left && px < right && py >= top && py < bottom
      return A_Index
  }
  return MonitorGetPrimary()
}

DestroyMonitorGuis() {
  global monitorGuis

  for index, gui in monitorGuis {
    try
      gui.Destroy()
  }
  monitorGuis := Map()
}

HideAllDimming() {
  global mainGui

  DestroyMonitorGuis()
  if IsObject(mainGui) {
    try
      mainGui.Hide()
  }
}

READINI() {
  global applicationname

  iniFile := applicationname ".ini"
  if !FileExist(iniFile) {
    ini := ";" applicationname ".ini"
    ini .= "`n`;backcolor=000000-FFFFFF or leave blank to speed up screen redraw."
    ini .= "`n`;image=                     Path to image or leave blank to speed up screen redraw."
    ini .= "`n`;x=any number or blank      Moves the image to the right."
    ini .= "`n`;y=any number or blank      Moves the image down."
    ini .= "`n`;width=any number or blank  Makes the image wider."
    ini .= "`n`;height=any number or blank Makes the image taller."
    ini .= "`n`;stretchwidth=1 or 0        Makes the image fill the width of the screen."
    ini .= "`n`;stretchheight=1 or 0       Makes the image fill the height of the screen."
    ini .= "`n`;keepaspect=1               Keeps the image from distorting."
    ini .= "`n`;transparency=0-255         Makes the ghosting more or less translucent."
    ini .= "`n`;jump=1 or 0                Makes the active window show through the ghosting."
    ini .= "`n`;showdesktop=1 or 0         Removes the ghosting when the desktop is active."
    ini .= "`n`;showontop=1 or 0           Removes ghosting from ontop windows like the taskbar."
    ini .= "`n`;multimon=1 or 0            Dim all monitors in a multimonitor system"
    ini .= "`n`;blacklist=                 Comma-separated process names to ignore. Supports class:NAME and title:TEXT."
    ini .= "`n`;mode=window or monitor     window: current window highlighted, monitor: current monitor highlighted."
    ini .= "`n`;modehotkey=^+x             Hotkey to switch mode. ^ Ctrl, + Shift, ! Alt, # Win."
    ini .= "`n`;enabled=1 or 0             Enables or disables dimming on startup."
    ini .= "`n`;togglehotkey=^!x           Hotkey to enable or disable dimming."
    ini .= "`n"
    ini .= "`n[Settings]"
    ini .= "`nbackcolor=000000"
    ini .= "`nimage=" A_WinDir "\Bubbles.bmp"
    ini .= "`nx="
    ini .= "`ny="
    ini .= "`nwidth="
    ini .= "`nheight="
    ini .= "`nstretchwidth=1"
    ini .= "`nstretchheight=1"
    ini .= "`nkeepaspect=1"
    ini .= "`ntransparency=150"
    ini .= "`njump=1"
    ini .= "`nshowdesktop=1"
    ini .= "`nshowontop=0"
    ini .= "`nmultimon=1"
    ini .= "`nblacklist=TextInputHost.exe,ctfmon.exe,Snipaste.exe,PixPin.exe"
    ini .= "`nmode=window"
    ini .= "`nmodehotkey=^+x"
    ini .= "`nenabled=1"
    ini .= "`ntogglehotkey=^!x"
    ini .= "`n"
    FileAppend(ini, iniFile)
  }

  return {
    backcolor: IniRead(iniFile, "Settings", "backcolor", "ERROR"),
    image: IniRead(iniFile, "Settings", "image", "ERROR"),
    x: IniRead(iniFile, "Settings", "x", "ERROR"),
    y: IniRead(iniFile, "Settings", "y", "ERROR"),
    width: IniRead(iniFile, "Settings", "width", "ERROR"),
    height: IniRead(iniFile, "Settings", "height", "ERROR"),
    stretchwidth: IniRead(iniFile, "Settings", "stretchwidth", "ERROR"),
    stretchheight: IniRead(iniFile, "Settings", "stretchheight", "ERROR"),
    keepaspect: IniRead(iniFile, "Settings", "keepaspect", "ERROR"),
    transparency: IniRead(iniFile, "Settings", "transparency", "ERROR"),
    jump: IniRead(iniFile, "Settings", "jump", "ERROR"),
    showdesktop: IniRead(iniFile, "Settings", "showdesktop", "ERROR"),
    showontop: IniRead(iniFile, "Settings", "showontop", "ERROR"),
    multimon: IniRead(iniFile, "Settings", "multimon", "ERROR"),
    blacklist: IniRead(iniFile, "Settings", "blacklist", "TextInputHost.exe,ctfmon.exe,Snipaste.exe,PixPin.exe"),
    mode: IniRead(iniFile, "Settings", "mode", "window"),
    modehotkey: IniRead(iniFile, "Settings", "modehotkey", "^+x"),
    enabled: IniRead(iniFile, "Settings", "enabled", "1"),
    togglehotkey: IniRead(iniFile, "Settings", "togglehotkey", "^!x")
  }
}

DimTaskbars(activeId, afterId, flags) {
  global taskbarid, secondaryTaskbarIds

  ids := []
  if taskbarid
    ids.Push(taskbarid)
  for id in secondaryTaskbarIds
    ids.Push(id)

  for id in ids {
    if IsTaskbarWindow(activeId)
      continue
    try {
      DllCall("SetWindowPos"
        , "Ptr", id
        , "Ptr", afterId
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "UInt", flags)
    }
  }
}

TRAYMENU() {
  global applicationname

  A_TrayMenu.Delete()
  A_TrayMenu.Add(applicationname, ABOUT)
  A_TrayMenu.Add()
  A_TrayMenu.Add("&Settings...", SETTINGS)
  A_TrayMenu.Add("&Toggle Mode", ToggleMode)
  A_TrayMenu.Add("Toggle &Enabled", ToggleEnabled)
  A_TrayMenu.Add("&About...", ABOUT)
  A_TrayMenu.Add("&Restart", RESTART)
  A_TrayMenu.Add("E&xit", EXIT)
  A_TrayMenu.Default := applicationname
}

SETTINGS(*) {
  global applicationname
  Run(applicationname ".ini")
}

RESTART(*) {
  DESTROY()
  START()
}

DESTROY() {
  global mainGui

  ExitBlank()
  if IsObject(mainGui)
    mainGui.Destroy()
  DestroyMonitorGuis()
}

ABOUT(*) {
  global applicationname, aboutGui, hCurs

  if IsObject(aboutGui)
    aboutGui.Destroy()
  aboutGui := Gui(, applicationname " About")
  aboutGui.MarginX := 20
  aboutGui.MarginY := 20
  aboutGui.OnEvent("Close", ABOUTCLOSE)

  aboutGui.AddPicture("xm Icon1", applicationname ".exe")
  aboutGui.SetFont("Bold")
  aboutGui.AddText("x+10 yp+10", applicationname " v1.2")
  aboutGui.SetFont()
  aboutGui.AddText("y+10", "Dims inactive windows and shows a transparent image across the screen")
  aboutGui.AddText("y+10", "- Change the image and other settings using Settings in the tray menu")

  aboutGui.AddPicture("xm y+20 Icon5", applicationname ".exe")
  aboutGui.SetFont("Bold")
  aboutGui.AddText("x+10 yp+10", "1 Hour Software by Skrommel")
  aboutGui.SetFont()
  aboutGui.AddText("y+10", "For more tools, information and donations, please visit ")
  aboutGui.SetFont("CBlue Underline")
  link1 := aboutGui.AddText("y+5", "www.1HourSoftware.com")
  link1.OnEvent("Click", (*) => Run("http://www.1hoursoftware.com", , "UseErrorLevel"))
  aboutGui.SetFont()

  aboutGui.AddPicture("xm y+20 Icon7", applicationname ".exe")
  aboutGui.SetFont("Bold")
  aboutGui.AddText("x+10 yp+10", "DonationCoder")
  aboutGui.SetFont()
  aboutGui.AddText("y+10", "Please support the contributors at")
  aboutGui.SetFont("CBlue Underline")
  link2 := aboutGui.AddText("y+5", "www.DonationCoder.com")
  link2.OnEvent("Click", (*) => Run("http://www.donationcoder.com", , "UseErrorLevel"))
  aboutGui.SetFont()

  aboutGui.AddPicture("xm y+20 Icon6", applicationname ".exe")
  aboutGui.SetFont("Bold")
  aboutGui.AddText("x+10 yp+10", "AutoHotkey")
  aboutGui.SetFont()
  aboutGui.AddText("y+10", "This tool was made using the powerful")
  aboutGui.SetFont("CBlue Underline")
  link3 := aboutGui.AddText("y+5", "www.AutoHotkey.com")
  link3.OnEvent("Click", (*) => Run("http://www.autohotkey.com", , "UseErrorLevel"))
  aboutGui.SetFont()

  aboutGui.Show()
  hCurs := DllCall("LoadCursor", "Ptr", 0, "Int", 32649, "Ptr")
  OnMessage(0x200, WM_MOUSEMOVE)
}

ABOUTCLOSE(*) {
  global aboutGui, hCurs

  if IsObject(aboutGui)
    aboutGui.Destroy()
  OnMessage(0x200, WM_MOUSEMOVE, 0)
  if hCurs
    DllCall("DestroyCursor", "Ptr", hCurs)
  hCurs := 0
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
  global hCurs

  MouseGetPos(, , , &ctrl)
  if ctrl = "Static8" || ctrl = "Static12" || ctrl = "Static16"
    DllCall("SetCursor", "Ptr", hCurs)
  return 0
}

EXIT(args*) {
  global oldid

  try {
    WinActivate("ahk_class Shell_TrayWnd")
    WinWaitActive("ahk_class Shell_TrayWnd", , 1)
  }
  DESTROY()
  if oldid {
    try {
      WinActivate("ahk_id " oldid)
    }
  }
  if args.Length != 2
    ExitApp()
}
