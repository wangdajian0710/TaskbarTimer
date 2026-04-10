<#
.SYNOPSIS
    Taskbar Timer - 任务栏计时器（极简版）
.DESCRIPTION
    默认：紧凑细条（拖动条+总计时+时钟+📌）
    点分段按钮：展开详情面板（分段时间+列表+操作按钮）
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============ 状态 ============
$script:running       = $false
$script:pinned        = $false
$script:startTime     = $null
$script:pausedElapsed = [System.TimeSpan]::Zero
$script:laps          = @()
$script:lapStart      = $null
$script:expanded       = $false   # 详情面板是否展开

# ============ 窗口尺寸（极简条） ============
$STRIP_W  = 210   # 细条宽度 ≈ 5cm
$STRIP_H  = 42    # 细条高度 ≈ 1cm
$TICK_MS  = 100

# ============ Native API ============
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    public const int WM_NCLBUTTONDOWN = 0xA1;
    public const int HTCAPTION = 2;
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Windows.Forms;
public class NativeMethods {
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
    [DllImport("user32.dll")] public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
}
"@

# ============ 主窗口（极简细条） ============
$form = New-Object System.Windows.Forms.Form
$form.Text            = "TaskbarTimer"
$form.FormBorderStyle  = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition    = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost          = $true
$form.ShowInTaskbar    = $false
$form.Size             = New-Object System.Drawing.Size($STRIP_W, $STRIP_H)
$form.AllowTransparency = $true
$form.BackColor        = [System.Drawing.Color]::FromArgb(1, 0, 0, 0)

$form.Add_Load({
    $form.Region = [System.Drawing.Region]::FromHrgn(
        [NativeMethods]::CreateRoundRectRgn(0, 0, $form.Width, $form.Height, 8, 8)
    )
})

$form.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 22, 24, 36))
    $g.FillRectangle($brush, 0, 0, $form.Width, $form.Height)
    $brush.Dispose()
})

# ============ 拖动条 ============
$dragBar = New-Object System.Windows.Forms.Panel
$dragBar.Dock       = [System.Windows.Forms.DockStyle]::Top
$dragBar.Height     = 6
$dragBar.BackColor  = [System.Drawing.Color]::FromArgb(180, 88, 91, 112)
$dragBar.Cursor     = [System.Windows.Forms.Cursors]::SizeAll
$script:barDragging = $false
$script:barStart    = $null

$dragBar.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $script:pinned) {
        $script:barDragging = $true
        $script:barStart   = $e.Location
        $dragBar.Capture   = $true
    }
})
$dragBar.Add_MouseMove({
    param($s, $e)
    if ($script:barDragging -and -not $script:pinned) {
        $pt = $form.PointToScreen($e.Location)
        $form.Location = New-Object System.Drawing.Point(
            ($pt.X - $script:barStart.X), ($pt.Y - $script:barStart.Y)
        )
    }
})
$dragBar.Add_MouseUp({ $script:barDragging = $false; $dragBar.Capture = $false })
[void]$form.Controls.Add($dragBar)

# ============ 内容行（总计时 + 时钟 + 📌 + 分段按钮） ============
$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock    = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.BackColor = [System.Drawing.Color]::Transparent
$contentPanel.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)

# 总计时标签
$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Dock      = [System.Windows.Forms.DockStyle]::Fill
$lblTotal.Font      = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
$lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
$lblTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTotal.Text      = "00:00.0"
$lblTotal.Cursor    = [System.Windows.Forms.Cursors]::SizeAll

# 分段按钮
$btnLap = New-Object System.Windows.Forms.Button
$btnLap.Dock       = [System.Windows.Forms.DockStyle]::Right
$btnLap.Width      = 42
$btnLap.Text       = "分段"
$btnLap.Font       = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnLap.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnLap.ForeColor  = [System.Drawing.Color]::FromArgb(200, 220, 255)
$btnLap.BackColor  = [System.Drawing.Color]::FromArgb(60, 65, 90)
$btnLap.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnLap.FlatAppearance.BorderSize = 0
$btnLap.Margin     = New-Object System.Windows.Forms.Padding(0)
$btnLap.Padding    = New-Object System.Windows.Forms.Padding(0)
$btnLap.Add_Click({
    ToggleDetail
})

# 📌固定按钮
$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Dock       = [System.Windows.Forms.DockStyle]::Right
$btnPin.Width      = 26
$btnPin.Text       = "📌"
$btnPin.Font       = New-Object System.Drawing.Font("Segoe UI Symbol", 9)
$btnPin.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor  = [System.Drawing.Color]::FromArgb(255, 220, 230, 255)
$btnPin.BackColor  = [System.Drawing.Color]::Transparent
$btnPin.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnPin.FlatAppearance.BorderSize = 0
$btnPin.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40, 80, 100, 130)
$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 255, 180)
        $dragBar.BackColor = [System.Drawing.Color]::FromArgb(160, 100, 180, 220)
        $dragBar.Cursor    = [System.Windows.Forms.Cursors]::No
        $notifyIcon.ShowBalloonTip(1500,"任务栏计时器","已固定位置，再点📌取消",[System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 230, 255)
        $dragBar.BackColor = [System.Drawing.Color]::FromArgb(180, 88, 91, 112)
        $dragBar.Cursor    = [System.Windows.Forms.Cursors]::SizeAll
        $notifyIcon.ShowBalloonTip(1500,"任务栏计时器","已取消固定",[System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# 开始/暂停按钮（整合为一个）
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Dock       = [System.Windows.Forms.DockStyle]::Right
$btnStart.Width      = 40
$btnStart.Text       = "开始"
$btnStart.Font       = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnStart.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnStart.ForeColor  = [System.Drawing.Color]::FromArgb(180, 200, 255)
$btnStart.BackColor  = [System.Drawing.Color]::FromArgb(55, 60, 85)
$btnStart.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.Add_Click({
    if (-not $script:running) {
        $script:running   = $true
        $script:lapStart  = Get-Date
        if (-not $script:startTime) { $script:startTime = Get-Date }
        $btnStart.Text = "暂停"
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 120)
    } else {
        $script:running     = $false
        $script:pausedElapsed += (Get-Date) - $script:lapStart
        $script:lapStart     = $null
        $btnStart.Text = "开始"
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 255)
    }
})

# 将各控件加入内容面板（不含时钟，节省空间）
[void]$contentPanel.Controls.Add($lblTotal)
[void]$contentPanel.Controls.Add($btnLap)
[void]$contentPanel.Controls.Add($btnPin)
[void]$contentPanel.Controls.Add($btnStart)

[void]$form.Controls.Add($contentPanel)

# ============ 详情弹窗（点击分段后展开） ============
$detailForm = New-Object System.Windows.Forms.Form
$detailForm.Text           = "TimerDetail"
$detailForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$detailForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$detailForm.TopMost         = $true
$detailForm.ShowInTaskbar   = $false
$detailForm.AllowTransparency = $true
$detailForm.BackColor      = [System.Drawing.Color]::FromArgb(1, 0, 0, 0)
$DETAIL_W = 210
$DETAIL_H = 320
$detailForm.Size = New-Object System.Drawing.Size($DETAIL_W, $DETAIL_H)

$detailForm.Add_Load({
    $detailForm.Region = [System.Drawing.Region]::FromHrgn(
        [NativeMethods]::CreateRoundRectRgn(0, 0, $DETAIL_W, $DETAIL_H, 10, 10)
    )
})

$detailForm.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 18, 22, 36))
    $g.FillRectangle($brush, 0, 0, $DETAIL_W, $DETAIL_H)
    $brush.Dispose()
})

# 详情面板跟随主窗口移动
$form.Add_Move({
    if ($script:expanded) {
        $detailForm.Location = New-Object System.Drawing.Point(
            $form.Left, ($form.Top + $form.Height + 6)
        )
    }
})

# ---- 详情头部：总计时 + 当前分段时间 ----
$detailTop = New-Object System.Windows.Forms.Panel
$detailTop.Dock    = [System.Windows.Forms.DockStyle]::Top
$detailTop.Height  = 50
$detailTop.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 4)
$detailTop.BackColor = [System.Drawing.Color]::Transparent

# 总计时（大字）
$lblDetailTotal = New-Object System.Windows.Forms.Label
$lblDetailTotal.Dock      = [System.Windows.Forms.DockStyle]::Top
$lblDetailTotal.Height   = 22
$lblDetailTotal.Font      = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 240, 255)
$lblDetailTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblDetailTotal.Text      = "00:00.0"

# 当前分段
$lblDetailLap = New-Object System.Windows.Forms.Label
$lblDetailLap.Dock      = [System.Windows.Forms.DockStyle]::Fill
$lblDetailLap.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblDetailLap.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 220)
$lblDetailLap.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblDetailLap.Text      = "分段 00:00.0"

[void]$detailTop.Controls.Add($lblDetailLap)
[void]$detailTop.Controls.Add($lblDetailTotal)

# ---- 操作按钮行 ----
$detailBtnRow = New-Object System.Windows.Forms.Panel
$detailBtnRow.Dock    = [System.Windows.Forms.DockStyle]::Top
$detailBtnRow.Height  = 32
$detailBtnRow.Padding = New-Object System.Windows.Forms.Padding(8, 3, 8, 3)
$detailBtnRow.BackColor = [System.Drawing.Color]::Transparent

$btnDetailStart = New-Object System.Windows.Forms.Button
$btnDetailStart.Dock       = [System.Windows.Forms.DockStyle]::Fill
$btnDetailStart.Text       = "开始"
$btnDetailStart.Font       = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailStart.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnDetailStart.ForeColor  = [System.Drawing.Color]::FromArgb(180, 200, 255)
$btnDetailStart.BackColor  = [System.Drawing.Color]::FromArgb(55, 65, 90)
$btnDetailStart.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnDetailStart.FlatAppearance.BorderSize = 0
$btnDetailStart.Add_Click($btnStart.Add_Click)

$btnDetailLap = New-Object System.Windows.Forms.Button
$btnDetailLap.Dock       = [System.Windows.Forms.DockStyle]::Left
$btnDetailLap.Width     = 46
$btnDetailLap.Text       = "分段"
$btnDetailLap.Font       = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailLap.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnDetailLap.ForeColor  = [System.Drawing.Color]::FromArgb(200, 220, 255)
$btnDetailLap.BackColor  = [System.Drawing.Color]::FromArgb(55, 65, 90)
$btnDetailLap.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnDetailLap.FlatAppearance.BorderSize = 0
$btnDetailLap.Add_Click({
    RecordLap
    ToggleDetail
})

$btnDetailClose = New-Object System.Windows.Forms.Button
$btnDetailClose.Dock       = [System.Windows.Forms.DockStyle]::Right
$btnDetailClose.Width     = 36
$btnDetailClose.Text       = "关闭"
$btnDetailClose.Font       = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailClose.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnDetailClose.ForeColor  = [System.Drawing.Color]::FromArgb(200, 180, 180)
$btnDetailClose.BackColor  = [System.Drawing.Color]::FromArgb(55, 65, 90)
$btnDetailClose.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnDetailClose.FlatAppearance.BorderSize = 0
$btnDetailClose.Add_Click({ ToggleDetail })

$btnDetailReset = New-Object System.Windows.Forms.Button
$btnDetailReset.Dock       = [System.Windows.Forms.DockStyle]::Right
$btnDetailReset.Width     = 36
$btnDetailReset.Text       = "清空"
$btnDetailReset.Font       = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailReset.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
$btnDetailReset.ForeColor  = [System.Drawing.Color]::FromArgb(200, 180, 180)
$btnDetailReset.BackColor  = [System.Drawing.Color]::FromArgb(55, 65, 90)
$btnDetailReset.Cursor     = [System.Windows.Forms.Cursors]::Hand
$btnDetailReset.FlatAppearance.BorderSize = 0
$btnDetailReset.Add_Click({
    $script:running       = $false
    $script:startTime     = $null
    $script:pausedElapsed = [System.TimeSpan]::Zero
    $script:laps          = @()
    $script:lapStart      = $null
    $lblTotal.Text        = "00:00.0"
    $lblTotal.ForeColor   = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
    $lblDetailTotal.Text  = "00:00.0"
    $lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 240, 255)
    $lblDetailLap.Text    = "分段 00:00.0"
    $btnStart.Text        = "开始"
    $btnStart.ForeColor   = [System.Drawing.Color]::FromArgb(180, 200, 255)
    $detailLapList.Items.Clear()
    $detailForm.Hide()
    $script:expanded = $false
})

[void]$detailBtnRow.Controls.Add($btnDetailStart)
[void]$detailBtnRow.Controls.Add($btnDetailLap)
[void]$detailBtnRow.Controls.Add($btnDetailClose)
[void]$detailBtnRow.Controls.Add($btnDetailReset)

# ---- 分段列表 ----
$detailLapList = New-Object System.Windows.Forms.ListBox
$detailLapList.Dock           = [System.Windows.Forms.DockStyle]::Fill
$detailLapList.BackColor     = [System.Drawing.Color]::FromArgb(15, 20, 32)
$detailLapList.ForeColor     = [System.Drawing.Color]::FromArgb(190, 205, 225)
$detailLapList.BorderStyle   = [System.Windows.Forms.BorderStyle]::None
$detailLapList.Font          = New-Object System.Drawing.Font("Consolas", 9)
$detailLapList.IntegralHeight = $false
$detailLapList.Padding       = New-Object System.Windows.Forms.Padding(4)

[void]$detailForm.Controls.Add($detailLapList)
[void]$detailForm.Controls.Add($detailBtnRow)
[void]$detailForm.Controls.Add($detailTop)

# ============ 托盘图标 ============
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon

function Build-TimerIcon {
    param([bool]$Running)
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $col = if ($Running) { [System.Drawing.Color]::FromArgb(255, 80, 220, 120) } else { [System.Drawing.Color]::FromArgb(255, 180, 180, 200) }
    $pen = New-Object System.Drawing.Pen($col, 2)
    $g.DrawEllipse($pen, 2, 2, 12, 12)
    if ($Running) { $g.FillEllipse((New-Object System.Drawing.SolidBrush($col)), 6, 6, 4, 4) }
    $g.Dispose(); $pen.Dispose()
    $ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    return $ico
}

function Format-Time {
    param([TimeSpan]$ts)
    if ($ts.TotalHours -ge 1) {
        return "{0:D2}:{1:D2}:{2:D2}.{3:D1}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 100)
    } else {
        return "{0:D2}:{1:D2}.{2:D1}" -f $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 100)
    }
}

function RecordLap {
    $elapsed = $script:pausedElapsed
    if ($script:running -and $script:lapStart) {
        $elapsed += (Get-Date) - $script:lapStart
    }
    if ($elapsed -gt [System.TimeSpan]::Zero) {
        $script:laps = @($elapsed) + $script:laps
        if ($script:laps.Count -gt 10) { $script:laps = $script:laps[0..9] }
        $detailLapList.BeginUpdate()
        $detailLapList.Items.Clear()
        for ($i = 0; $i -lt $script:laps.Count; $i++) {
            $ts  = $script:laps[$i]
            $gap = if ($i -eq 0) { $ts } else { $script:laps[$i-1] - $ts }
            $txt = "#{0:D2}  {1}  (+{2})" -f ($script:laps.Count - $i), (Format-Time -ts $ts), (Format-Time -ts $gap)
            [void]$detailLapList.Items.Add($txt)
        }
        $detailLapList.EndUpdate()
    }
}

function ToggleDetail {
    $script:expanded = -not $script:expanded
    if ($script:expanded) {
        # 展开：定位到主窗口下方
        $detailForm.Location = New-Object System.Drawing.Point(
            $form.Left, ($form.Top + $form.Height + 6)
        )
        $detailForm.Show()
        # 同步按钮状态
        if ($script:running) {
            $btnDetailStart.Text = "暂停"
            $btnDetailStart.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 120)
        } else {
            $btnDetailStart.Text = "开始"
            $btnDetailStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 255)
        }
    } else {
        $detailForm.Hide()
    }
}

# ============ 定时刷新 ============
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $TICK_MS

$timer.Add_Tick({

    $total = $script:pausedElapsed
    if ($script:running -and $script:lapStart) {
        $total += (Get-Date) - $script:lapStart
    }
    $ts = $total
    $totalStr = Format-Time -ts $ts
    $lblTotal.Text = $totalStr
    $lblDetailTotal.Text = $totalStr

    # 详情分段
    $lapStr = "分段 00:00.0"
    if ($script:running -and $script:lapStart) {
        $lapTs = (Get-Date) - $script:lapStart
        $lapStr = "分段 " + (Format-Time -ts $lapTs)
    }
    $lblDetailLap.Text = $lapStr

    # 颜色
    if ($script:running) {
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 160, 255, 180)
        $lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 160, 255, 180)
        $notifyIcon.Icon  = Build-TimerIcon -Running $true
        $notifyIcon.Text = "计时中 $totalStr"
    } elseif ($ts -gt [System.TimeSpan]::Zero) {
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 210, 150)
        $lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 210, 150)
        $notifyIcon.Icon  = Build-TimerIcon -Running $false
        $notifyIcon.Text = "已暂停 $totalStr"
    } else {
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
        $lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 240, 255)
        $notifyIcon.Icon  = Build-TimerIcon -Running $false
        $notifyIcon.Text = "任务栏计时器"
    }
})

# ============ 右键菜单 ============
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$menuPin = New-Object System.Windows.Forms.ToolStripMenuItem
$menuPin.Text = if ($script:pinned) { "取消固定" } else { "固定位置" }
$menuPin.Add_Click({
    $btnPin.PerformClick()
})
[void]$contextMenu.Items.Add($menuPin)

$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem
$menuExit.Text = "退出"
$menuExit.Add_Click({
    $detailForm.Close()
    $form.Close()
    $timer.Stop(); $timer.Dispose()
    if ($notifyIcon.Icon) { $notifyIcon.Icon.Dispose() }
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
[void]$contextMenu.Items.Add($menuExit)
$notifyIcon.ContextMenuStrip = $contextMenu

# ============ 启动 ============
$notifyIcon.Icon = Build-TimerIcon -Running $false

# 定位到屏幕右下角
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(
    ($screen.Right - $STRIP_W - 10),
    ($screen.Bottom - $STRIP_H - 4)
)

$form.Show()
$detailForm.Hide()
$timer.Start()

[System.Windows.Forms.Application]::Run()
