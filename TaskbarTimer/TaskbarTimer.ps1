<#
.SYNOPSIS
    Taskbar Timer - 任务栏计时器
.DESCRIPTION
    半透明浮动工具条，显示时钟 + 总计时 + 分段列表
    按钮：开始 / 暂停 / 分段 / 清空 / 固定
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============ 状态 ============
$script:running     = $false
$script:pinned      = $false
$script:startTime   = $null
$script:pausedElapsed = [System.TimeSpan]::Zero   # 暂停时已积累的总时间
$script:laps        = @()                         # 分段列表，每项 [TimeSpan]
$script:lapStart    = $null                       # 当前分段开始时间

# ============ 窗口尺寸 ============
$WINDOW_W   = 440
$HEADER_H   = 42    # 拖动条 + 总计时行高度
$LAP_ROW_H  = 22    # 每个分段行高度
$MAX_LAPS   = 10    # 最多显示分段数
$LAPS_AREA  = $LAP_ROW_H * $MAX_LAPS
$FORM_H     = $HEADER_H + $LAPS_AREA + 6

# ============ 主窗口 ============
$form = New-Object System.Windows.Forms.Form
$form.Text          = "Taskbar Timer"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost       = $true
$form.ShowInTaskbar = $false
$form.Size          = New-Object System.Drawing.Size($WINDOW_W, $FORM_H)
$form.AllowTransparency = $true
$form.BackColor     = [System.Drawing.Color]::FromArgb(1, 0, 0, 0)

# 圆角
$form.Add_Load({
    $form.Region = [System.Drawing.Region]::FromHrgn(
        [System.Windows.Forms.NativeMethods]::CreateRoundRectRgn(0, 0, $form.Width, $form.Height, 12, 12)
    )
})

# 背景Paint
$form.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 22, 24, 36))
    $rect  = New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()
    $rect.Dispose()
    $g.Dispose()
})

# ============ 拖动条（顶部细条） ============
$dragBar = New-Object System.Windows.Forms.Panel
$dragBar.Dock        = [System.Windows.Forms.DockStyle]::Top
$dragBar.Height      = 6
$dragBar.BackColor   = [System.Drawing.Color]::FromArgb(180, 88, 91, 112)
$dragBar.Cursor      = [System.Windows.Forms.Cursors]::SizeAll
$script:barDragging  = $false
$script:barStart     = $null

$dragBar.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $script:pinned) {
        $script:barDragging = $true
        $script:barStart    = New-Object System.Drawing.Point($e.X, $e.Y)
        $dragBar.Capture   = $true
    }
})
$dragBar.Add_MouseMove({
    param($s, $e)
    if ($script:barDragging -and -not $script:pinned) {
        $pt = $form.PointToScreen($e.Location)
        $form.Location = New-Object System.Drawing.Point(
            ($pt.X - $script:barStart.X),
            ($pt.Y - $script:barStart.Y)
        )
    }
})
$dragBar.Add_MouseUp({
    $script:barDragging = $false
    $dragBar.Capture = $false
})
[void]$form.Controls.Add($dragBar)

# ============ 头部面板（总计时 + 时钟 + 按钮） ============
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock    = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height  = 52
$headerPanel.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
$headerPanel.BackColor = [System.Drawing.Color]::Transparent

# 头部行布局（1行：左侧总计时+时钟 / 右侧按钮）
$headerTable = New-Object System.Windows.Forms.TableLayoutPanel
$headerTable.Dock       = [System.Windows.Forms.DockStyle]::Fill
$headerTable.ColumnCount = 2
$headerTable.RowCount   = 1
$headerTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 55)))
$headerTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 45)))

# --- 左列：总计时 + 时钟（同一行，分两格） ---
$timeCol = New-Object System.Windows.Forms.Panel
$timeCol.Dock = [System.Windows.Forms.DockStyle]::Fill
$timeCol.BackColor = [System.Drawing.Color]::Transparent

# 总计时（大字）
$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Dock      = [System.Windows.Forms.DockStyle]::Fill
$lblTotal.Font      = New-Object System.Drawing.Font("Consolas", 22, [System.Drawing.FontStyle]::Bold)
$lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
$lblTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTotal.Text      = "00:00.0"
$lblTotal.Padding   = New-Object System.Windows.Forms.Padding(0)
$lblTotal.Cursor    = [System.Windows.Forms.Cursors]::SizeAll

# 时钟（总计时右边的细小字）
$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Dock        = [System.Windows.Forms.DockStyle]::Right
$lblClock.Width       = 72
$lblClock.Font        = New-Object System.Drawing.Font("Consolas", 10)
$lblClock.ForeColor   = [System.Drawing.Color]::FromArgb(180, 200, 220)
$lblClock.TextAlign   = [System.Drawing.ContentAlignment]::MiddleRight
$lblClock.Text        = "HH:MM"
$lblClock.Padding    = New-Object System.Windows.Forms.Padding(0)
$lblClock.Cursor      = [System.Windows.Forms.Cursors]::SizeAll
$lblClock.Margin      = New-Object System.Windows.Forms.Padding(0)

[void]$timeCol.Controls.Add($lblTotal)
[void]$timeCol.Controls.Add($lblClock)

# --- 右列：按钮行 ---
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Dock    = [System.Windows.Forms.DockStyle]::Fill
$btnPanel.BackColor = [System.Drawing.Color]::Transparent

$btnRow = New-Object System.Windows.Forms.TableLayoutPanel
$btnRow.Dock           = [System.Windows.Forms.DockStyle]::Fill
$btnRow.ColumnCount    = 5
$btnRow.RowCount       = 1
$btnRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
$btnRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
$btnRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
$btnRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
$btnRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))

# 通用按钮工厂
function New-Btn {
    param([string]$Text, [string]$FgARGB, [string]$BgARGB, [scriptblock]$OnClick, [float]$FontSize = 10)
    $b = New-Object System.Windows.Forms.Button
    $b.Text          = $Text
    $b.FlatStyle      = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(150, 140, 160, 200)
    $r = [Convert]::ToInt32($FgARGB.Split(',')[0])
    $g = [Convert]::ToInt32($FgARGB.Split(',')[1])
    $b2= [Convert]::ToInt32($FgARGB.Split(',')[2])
    $a = [Convert]::ToInt32($FgARGB.Split(',')[3])
    $b.ForeColor      = [System.Drawing.Color]::FromArgb($a,$r,$g,$b2)
    $br = [Convert]::ToInt32($BgARGB.Split(',')[0])
    $bg = [Convert]::ToInt32($BgARGB.Split(',')[1])
    $bb2=[Convert]::ToInt32($BgARGB.Split(',')[2])
    $ba = [Convert]::ToInt32($BgARGB.Split(',')[3])
    $b.BackColor      = [System.Drawing.Color]::FromArgb($ba,$br,$bg,$bb2)
    $b.Font           = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
    $b.Cursor         = [System.Windows.Forms.Cursors]::Hand
    $b.Margin         = New-Object System.Windows.Forms.Padding(2)
    $b.Add_Click($OnClick)
    return $b
}

$btnStart = New-Btn -Text "开始" -FgARGB "180,240,180" -BgARGB "55,56,76" -OnClick {
    if (-not $script:running) {
        $script:running   = $true
        $script:lapStart  = Get-Date
        $btnStart.Text    = "计时中"
        $btnStart.BackColor = [System.Drawing.Color]::FromArgb(180, 166, 227, 161)
        $btnStart.ForeColor= [System.Drawing.Color]::FromArgb(255, 22, 24, 36)
    }
}

$btnPause = New-Btn -Text "暂停" -FgARGB "255,230,180" -BgARGB "55,56,76" -OnClick {
    if ($script:running) {
        $script:running     = $false
        $script:pausedElapsed += (Get-Date) - $script:lapStart
        $btnStart.Text      = "继续"
        $btnStart.BackColor = [System.Drawing.Color]::FromArgb(180, 55, 56, 76)
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 240, 180)
    }
}

$btnLap = New-Btn -Text "分段" -FgARGB "180,220,255" -BgARGB "55,56,76" -OnClick {
    if ($script:running -or $script:pausedElapsed -gt [System.TimeSpan]::Zero) {
        $total = $script:pausedElapsed
        if ($script:running -and $script:lapStart) {
            $total += (Get-Date) - $script:lapStart
        }
        if ($total -gt [System.TimeSpan]::Zero) {
            $script:laps = @($total) + $script:laps
            if ($script:laps.Count -gt $MAX_LAPS) {
                $script:laps = $script:laps[0..($MAX_LAPS-1)]
            }
            # 重置分段，继续计时
            $script:running  = $true
            $script:lapStart = Get-Date
            # 不清 pausedElapsed，保留总计时
            RefreshLapList
        }
    }
}

$btnReset = New-Btn -Text "清空" -FgARGB "255,160,185" -BgARGB "55,56,76" -OnClick {
    $script:running       = $false
    $script:pausedElapsed = [System.TimeSpan]::Zero
    $script:lapStart      = $null
    $script:laps          = @()
    $btnStart.Text        = "开始"
    $btnStart.BackColor   = [System.Drawing.Color]::FromArgb(180, 55, 56, 76)
    $btnStart.ForeColor   = [System.Drawing.Color]::FromArgb(180, 240, 180)
    $lblTotal.Text        = "00:00.0"
    $lblTotal.ForeColor   = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
    RefreshLapList
}

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Text          = "📌"
$btnPin.FlatStyle     = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.FlatAppearance.BorderSize = 1
$btnPin.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100, 180, 200, 230)
$btnPin.BackColor     = [System.Drawing.Color]::FromArgb(180, 50, 55, 75)
$btnPin.ForeColor     = [System.Drawing.Color]::FromArgb(255, 220, 230, 255)
$btnPin.Font          = New-Object System.Drawing.Font("Segoe UI Emoji", 11)
$btnPin.Cursor        = [System.Windows.Forms.Cursors]::Hand
$btnPin.Margin        = New-Object System.Windows.Forms.Padding(2)
$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.BackColor       = [System.Drawing.Color]::FromArgb(180, 166, 227, 161)
        $btnPin.ForeColor       = [System.Drawing.Color]::FromArgb(255, 22, 24, 36)
        $btnPin.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 166, 227, 161)
        $dragBar.BackColor      = [System.Drawing.Color]::FromArgb(200, 166, 227, 161)
        $dragBar.Cursor         = [System.Windows.Forms.Cursors]::No
        $lblClock.Cursor        = [System.Windows.Forms.Cursors]::Default
        $lblTotal.Cursor        = [System.Windows.Forms.Cursors]::Default
        $notifyIcon.ShowBalloonTip(1500,"任务栏计时器","已固定位置 - 再点📌取消固定",[System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $btnPin.BackColor       = [System.Drawing.Color]::FromArgb(180, 50, 55, 75)
        $btnPin.ForeColor       = [System.Drawing.Color]::FromArgb(255, 220, 230, 255)
        $btnPin.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100, 180, 200, 230)
        $dragBar.BackColor      = [System.Drawing.Color]::FromArgb(180, 88, 91, 112)
        $dragBar.Cursor         = [System.Windows.Forms.Cursors]::SizeAll
        $lblClock.Cursor        = [System.Windows.Forms.Cursors]::SizeAll
        $lblTotal.Cursor        = [System.Windows.Forms.Cursors]::SizeAll
        $notifyIcon.ShowBalloonTip(1500,"任务栏计时器","已取消固定 - 可自由拖动",[System.Windows.Forms.ToolTipIcon]::Info)
    }
})

[void]$btnRow.Controls.Add($btnStart, 0, 0)
[void]$btnRow.Controls.Add($btnPause, 1, 0)
[void]$btnRow.Controls.Add($btnLap,   2, 0)
[void]$btnRow.Controls.Add($btnReset,3, 0)
[void]$btnRow.Controls.Add($btnPin,  4, 0)
[void]$btnPanel.Controls.Add($btnRow)
[void]$headerTable.Controls.Add($timeCol,  0, 0)
[void]$headerTable.Controls.Add($btnPanel, 1, 0)

[void]$headerPanel.Controls.Add($headerTable)
[void]$form.Controls.Add($headerPanel)

# ============ 分段列表面板 ============
$lapListPanel = New-Object System.Windows.Forms.Panel
$lapListPanel.Dock    = [System.Windows.Forms.DockStyle]::Fill
$lapListPanel.BackColor = [System.Drawing.Color]::FromArgb(10, 18, 28)
$lapListPanel.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 4)

$lapListBox = New-Object System.Windows.Forms.ListBox
$lapListBox.Dock           = [System.Windows.Forms.DockStyle]::Fill
$lapListBox.BackColor     = [System.Drawing.Color]::FromArgb(10, 18, 28)
$lapListBox.ForeColor     = [System.Drawing.Color]::FromArgb(200, 210, 225)
$lapListBox.BorderStyle   = [System.Windows.Forms.BorderStyle]::None
$lapListBox.Font          = New-Object System.Drawing.Font("Consolas", 9)
$lapListBox.IntegralHeight = $false
$lapListBox.SelectionMode = [System.Windows.Forms.SelectionMode]::None
$lapListBox.DrawMode      = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$lapListBox.ItemHeight    = $LAP_ROW_H

function Format-LapTime {
    param([System.TimeSpan]$ts)
    if ($ts.TotalHours -ge 1) {
        return "{0:D2}:{1:D2}:{2:D2}.{3:D1}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 100)
    }
    return "{0:D2}:{1:D2}.{2:D1}" -f $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 100)
}

$lapListBox.Add_DrawItem({
    param($s, $e)
    $idx = $e.Index
    if ($idx -lt 0 -or $idx -ge $script:laps.Count) { return }
    $lap = $script:laps[$idx]
    $isOdd = ($idx % 2 -eq 0)
    $bg = if ($isOdd) {
        [System.Drawing.Color]::FromArgb(255, 16, 22, 34)
    } else {
        [System.Drawing.Color]::FromArgb(255, 20, 26, 38)
    }
    $e.DrawBackground()
    $bgBrush = New-Object System.Drawing.SolidBrush($bg)
    $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
    $bgBrush.Dispose()

    # 序号
    $rankColor = [System.Drawing.Color]::FromArgb(150, 120, 130, 145)
    $rankFont  = New-Object System.Drawing.Font("Consolas", 8)
    $timeFont  = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $rankStr = "#{0:D2}" -f ($script:laps.Count - $idx)
    $timeStr = Format-LapTime -ts $lap

    $rankBrush = New-Object System.Drawing.SolidBrush($rankColor)
    $rankSize = $e.Graphics.MeasureString($rankStr, $rankFont)
    $rx = $e.Bounds.X + 4
    $ry = $e.Bounds.Y + ($e.Bounds.Height - $rankSize.Height) / 2
    $e.Graphics.DrawString($rankStr, $rankFont, $rankBrush, $rx, $ry)

    # 分隔线
    $sepBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(50, 100, 120, 140))
    $sepX = $rx + $rankSize.Width + 6
    $e.Graphics.DrawLine(
        (New-Object System.Drawing.Pen($sepBrush, 1)),
        $sepX, $e.Bounds.Y + 4,
        $sepX, $e.Bounds.Bottom - 4
    )
    $sepBrush.Dispose()

    # 时间
    $timeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 185, 215, 245))
    $timeX = $sepX + 8
    $timeY = $e.Bounds.Y + ($e.Bounds.Height - $rankSize.Height) / 2
    $e.Graphics.DrawString($timeStr, $timeFont, $timeBrush, $timeX, $timeY)

    $rankBrush.Dispose()
    $timeBrush.Dispose()
    $rankFont.Dispose()
    $timeFont.Dispose()
    $e.DrawFocusRectangle()
})

function RefreshLapList {
    $lapListBox.BeginUpdate()
    $lapListBox.Items.Clear()
    for ($i = 0; $i -lt $script:laps.Count; $i++) {
        [void]$lapListBox.Items.Add($i)
    }
    $lapListBox.EndUpdate()
    if ($script:laps.Count -gt 0) {
        $last = $script:laps[0]
    }
}

[void]$lapListPanel.Controls.Add($lapListBox)
[void]$form.Controls.Add($lapListPanel)

# ============ 窗口拖动（时钟+总计时区域） ============
$script:winDragging = $false
$script:winDragStart = $null

foreach ($ctrl in @($lblClock, $lblTotal)) {
    $ctrl.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $script:pinned) {
            $script:winDragging = $true
            $script:winDragStart = New-Object System.Drawing.Point($e.X, $e.Y)
        }
    })
    $ctrl.Add_MouseMove({
        param($s, $e)
        if ($script:winDragging -and -not $script:pinned) {
            $pt = $s.PointToScreen($e.Location)
            $form.Location = New-Object System.Drawing.Point(
                ($pt.X - $script:winDragStart.X),
                ($pt.Y - $script:winDragStart.Y)
            )
        }
    })
    $ctrl.Add_MouseUp({ $script:winDragging = $false })
}

# ============ 托盘图标 ============
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Text    = "任务栏计时器"
$notifyIcon.Visible = $true

function New-TimerIcon {
    param([bool]$IsRunning = $false)
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $c   = if ($IsRunning) { [System.Drawing.Color]::FromArgb(255, 30, 144, 255) } else { [System.Drawing.Color]::FromArgb(255, 120, 120, 120) }
    $pen = New-Object System.Drawing.Pen($c, 1.5)
    $g.DrawEllipse($pen, 1, 1, 14, 14)
    $pen.Dispose()
    $l1  = New-Object System.Drawing.Pen($c, 1.5)
    $g.DrawLine($l1, 8, 8, 8, 3)
    $l1.Dispose()
    $l2  = New-Object System.Drawing.Pen(
        $(if ($IsRunning) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(255, 120, 120, 120) }), 1.5)
    $g.DrawLine($l2, 8, 8, 12, 8)
    $l2.Dispose()
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

# 右键菜单
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuPin = New-Object System.Windows.Forms.ToolStripMenuItem
$menuPin.Text = "📌 固定位置"
$menuPin.Add_Click({
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.BackColor = [System.Drawing.Color]::FromArgb(180, 166, 227, 161)
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 22, 24, 36)
        $dragBar.BackColor = [System.Drawing.Color]::FromArgb(200, 166, 227, 161)
        $dragBar.Cursor = [System.Windows.Forms.Cursors]::No
        $lblClock.Cursor = [System.Windows.Forms.Cursors]::Default
        $lblTotal.Cursor = [System.Windows.Forms.Cursors]::Default
        $menuPin.Text = "📌 取消固定"
        $notifyIcon.ShowBalloonTip(1500,"任务栏计时器","已固定位置",[System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $btnPin.BackColor = [System.Drawing.Color]::FromArgb(180, 50, 55, 75)
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 230, 255)
        $dragBar.BackColor = [System.Drawing.Color]::FromArgb(180, 88, 91, 112)
        $dragBar.Cursor = [System.Windows.Forms.Cursors]::SizeAll
        $lblClock.Cursor = [System.Windows.Forms.Cursors]::SizeAll
        $lblTotal.Cursor = [System.Windows.Forms.Cursors]::SizeAll
        $menuPin.Text = "📌 固定位置"
        $notifyIcon.ShowBalloonTip(1500,"任务栏计时器","已取消固定 - 可自由拖动",[System.Windows.Forms.ToolTipIcon]::Info)
    }
})
$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem
$menuExit.Text = "退出"
$menuExit.Add_Click({
    $notifyIcon.Visible = $false
    $form.Close()
    $timer.Stop()
    $timer.Dispose()
    if ($notifyIcon.Icon) { $notifyIcon.Icon.Dispose() }
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
[void]$contextMenu.Items.Add($menuPin)
[void]$contextMenu.Items.Add($menuExit)
$notifyIcon.ContextMenuStrip = $contextMenu

# ============ 定时刷新 ============
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100

$timer.Add_Tick({
    $lblClock.Text = (Get-Date).ToString("HH:mm:ss")

    # 总时间
    $total = $script:pausedElapsed
    if ($script:running -and $script:lapStart) {
        $total += (Get-Date) - $script:lapStart
    }
    $ts = $total
    $totalStr = if ($ts.TotalHours -ge 1) {
        "{0:D2}:{1:D2}:{2:D2}.{3:D1}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 100)
    } else {
        "{0:D2}:{1:D2}.{2:D1}" -f $ts.Minutes, $ts.Seconds, [int]($ts.Milliseconds / 100)
    }
    $lblTotal.Text = $totalStr

    # 当前分段（从小数点后一位精度重置开始算）
    if ($script:running -and $script:lapStart) {
        $lapTs = (Get-Date) - $script:lapStart
        $lapStr = if ($lapTs.TotalHours -ge 1) {
            "{0:D2}:{1:D2}:{2:D2}.{3:D1}" -f [int]$lapTs.TotalHours, $lapTs.Minutes, $lapTs.Seconds, [int]($lapTs.Milliseconds / 100)
        } else {
            "{0:D2}:{1:D2}.{2:D1}" -f $lapTs.Minutes, $lapTs.Seconds, [int]($lapTs.Milliseconds / 100)
        }
        $lblTotal.Text = $lapStr
    }

    # 托盘图标 + 提示文字
    if ($script:running) {
        $notifyIcon.Icon  = New-TimerIcon -IsRunning $true
        $notifyIcon.Text = "计时中 $totalStr"
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 240, 180)
    } elseif ($ts -gt [System.TimeSpan]::Zero) {
        $notifyIcon.Icon  = New-TimerIcon -IsRunning $false
        $notifyIcon.Text = "已暂停 $totalStr"
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 220, 160)
    } else {
        $notifyIcon.Icon  = New-TimerIcon -IsRunning $false
        $notifyIcon.Text = "任务栏计时器"
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
    }
})

# ============ 启动 ============
$notifyIcon.Icon = New-TimerIcon -IsRunning $false
RefreshLapList

# 定位到右下角
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(
    ($screen.Right - $form.Width - 10),
    ($screen.Bottom - $form.Height - 4)
)

$form.Show()
$timer.Start()

[System.Windows.Forms.Application]::Run()
