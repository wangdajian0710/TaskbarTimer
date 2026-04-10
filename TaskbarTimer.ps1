# Taskbar Timer - 分段继续计时版
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$W = 280; $H = 240

Add-Type @"
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern int SendMessage(System.IntPtr hWnd, int msg, System.IntPtr wParam, System.IntPtr lParam);
    public const int WM_NCLBUTTONDOWN = 0xA1;
    public const int HTCAPTION = 2;
}
"@

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Drawing; using System.Windows.Forms;
public class Win32Forms {
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
    [DllImport("user32.dll")] public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    public const uint LWA_ALPHA = 2;
}
"@

$script:running = $false; $script:pinned = $false
$script:startTime = $null; $script:pausedElapsed = [TimeSpan]::Zero
$script:laps = @(); $script:lapStart = $null; $script:lastLapTime = [TimeSpan]::Zero

# 主窗口
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($W, $H)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 18, 20, 32)

$form.Add_Load({
    $rgn = [Win32Forms]::CreateRoundRectRgn(0, 0, $form.Width, $form.Height, 10, 10)
    $form.Region = [System.Drawing.Region]::FromHrgn($rgn)
})
$form.Add_Shown({ $null = [Win32Forms]::SetLayeredWindowAttributes($form.Handle, 0, 235, [Win32Forms]::LWA_ALPHA) })

# 标题栏
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = [System.Windows.Forms.DockStyle]::Top
$titleBar.Height = 28
$titleBar.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblTitle.Text = "  任务栏计时器"
$lblTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Dock = [System.Windows.Forms.DockStyle]::Right; $btnPin.Width = 28
$btnPin.Text = "📌"; $btnPin.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 9)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
$btnPin.BackColor = [System.Drawing.Color]::Transparent
$btnPin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPin.FlatAppearance.BorderSize = 0
$btnPin.Add_Click({ TogglePin })

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Dock = [System.Windows.Forms.DockStyle]::Right; $btnClose.Width = 28
$btnClose.Text = "X"; $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Add_Click({ ExitApp })

[void]$titleBar.Controls.Add($lblTitle)
[void]$titleBar.Controls.Add($btnPin)
[void]$titleBar.Controls.Add($btnClose)

$titleDrag = $false; $titleStart = $null
$lblTitle.Add_MouseDown({ if (!$script:pinned -and $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:titleDrag = $true; $script:titleStart = $_.Location; $lblTitle.Capture = $true } })
$lblTitle.Add_MouseMove({ if ($script:titleDrag -and !$script:pinned) { $p = $form.PointToScreen($_.Location); $form.Location = New-Object System.Drawing.Point($p.X - $script:titleStart.X, $p.Y - $script:titleStart.Y) } })
$lblTitle.Add_MouseUp({ $script:titleDrag = $false; $lblTitle.Capture = $false })

# 时钟行
$clockRow = New-Object System.Windows.Forms.Panel
$clockRow.Dock = [System.Windows.Forms.DockStyle]::Top
$clockRow.Height = 22
$clockRow.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)
$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Dock = [System.Windows.Forms.DockStyle]::Right; $lblClock.Width = 50
$lblClock.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblClock.ForeColor = [System.Drawing.Color]::FromArgb(160, 170, 200)
$lblClock.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblClock.Text = "HH:MM"
$lblClock.Padding = [System.Windows.Forms.Padding]::new(0, 0, 8, 0)
[void]$clockRow.Controls.Add($lblClock)

# 计时显示区
$timerPanel = New-Object System.Windows.Forms.Panel
$timerPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$timerPanel.BackColor = [System.Drawing.Color]::Transparent
$timerPanel.ContextMenuStrip = $null

$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$mPause = New-Object System.Windows.Forms.ToolStripMenuItem("暂停")
$mPause.Add_Click({ ToggleTimer })
$mClear = New-Object System.Windows.Forms.ToolStripMenuItem("清除")
$mClear.Add_Click({ ResetAll })
[void]$ctxMenu.Items.Add($mPause)
[void]$ctxMenu.Items.Add($mClear)
$timerPanel.ContextMenuStrip = $ctxMenu

# 总计时
$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Location = New-Object System.Drawing.Point(12, 8)
$lblTotal.Size = New-Object System.Drawing.Size(($W - 24), 52)
$lblTotal.Font = New-Object System.Drawing.Font("Consolas", 28, [System.Drawing.FontStyle]::Bold)
$lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 245, 255)
$lblTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTotal.Text = "00:00.0"

# 当前分段
$lblLap = New-Object System.Windows.Forms.Label
$lblLap.Location = New-Object System.Drawing.Point(12, 62)
$lblLap.Size = New-Object System.Drawing.Size(($W - 24), 22)
$lblLap.Font = New-Object System.Drawing.Font("Consolas", 11)
$lblLap.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 220)
$lblLap.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblLap.Text = "分段 00:00.0"

# 分段列表
$lapList = New-Object System.Windows.Forms.ListBox
$lapList.Location = New-Object System.Drawing.Point(12, 88)
$lapList.Size = New-Object System.Drawing.Size(($W - 24), 80)
$lapList.BackColor = [System.Drawing.Color]::FromArgb(40, 20, 22, 35)
$lapList.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lapList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lapList.Font = New-Object System.Drawing.Font("Consolas", 9)

[void]$timerPanel.Controls.Add($lblTotal)
[void]$timerPanel.Controls.Add($lblLap)
[void]$timerPanel.Controls.Add($lapList)

# 按钮区
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$btnPanel.Height = 40
$btnPanel.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)
$btnPanel.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 6)

function MakeBtn($text, $width) {
    $b = New-Object System.Windows.Forms.Button
    $b.Dock = [System.Windows.Forms.DockStyle]::Left; $b.Width = $width
    $b.Text = $text
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
    $b.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 80)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(70, 75, 100)
    $b
}

$btnStart = MakeBtn "开始" 60
$btnStart.Add_Click({ ToggleTimer })

$btnLap = MakeBtn "分段" 60
$btnLap.Add_Click({ RecordLap })

$btnReset = MakeBtn "清空" 60
$btnReset.Add_Click({ ResetAll })

[void]$btnPanel.Controls.Add($btnReset)
[void]$btnPanel.Controls.Add($btnLap)
[void]$btnPanel.Controls.Add($btnStart)

[void]$form.Controls.Add($btnPanel)
[void]$form.Controls.Add($timerPanel)
[void]$form.Controls.Add($clockRow)
[void]$form.Controls.Add($titleBar)

# 定时器 - 始终更新显示（暂停时也显示当前值）
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    $lblClock.Text = (Get-Date).ToString("HH:mm")
    
    # 总是计算并显示总时间
    if ($script:startTime) {
        $elapsed = $script:pausedElapsed + (Get-Date) - $script:startTime
        $ts = $elapsed.ToString("mm\:ss\.f")
        $lblTotal.Text = $ts
        if ($script:running) {
            $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 210, 130)
        } else {
            $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 210, 220)
        }
    }
    
    # 总是计算并显示分段时间（即使暂停也显示暂停时的值）
    $lapElapsed = [TimeSpan]::Zero
    if ($script:running -and $script:lapStart) {
        $lapElapsed = $script:lastLapTime + ((Get-Date) - $script:lapStart)
    } else {
        $lapElapsed = $script:lastLapTime
    }
    $lblLap.Text = "分段 " + $lapElapsed.ToString("mm\:ss\.f")
})

function ToggleTimer {
    if (-not $script:running) {
        # 开始/继续
        $script:running = $true
        if (-not $script:startTime) { 
            $script:startTime = Get-Date 
            $script:lapStart = Get-Date
        } elseif (-not $script:lapStart) {
            # 恢复时继续分段计时
            $script:lapStart = Get-Date
        }
        $btnStart.Text = "暂停"
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 220, 130)
        $btnStart.BackColor = [System.Drawing.Color]::FromArgb(70, 65, 45)
        $mPause.Text = "暂停"
    } else {
        # 暂停
        if ($script:lapStart) {
            $script:lastLapTime += (Get-Date) - $script:lapStart
            $script:lapStart = $null
        }
        $script:running = $false
        $btnStart.Text = "开始"
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
        $btnStart.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 80)
        $mPause.Text = "开始"
    }
}

function RecordLap {
    # 计算当前分段时长
    $lapElapsed = [TimeSpan]::Zero
    if ($script:running -and $script:lapStart) {
        $lapElapsed = $script:lastLapTime + ((Get-Date) - $script:lapStart)
    } else {
        $lapElapsed = $script:lastLapTime
    }
    
    $total = if ($script:startTime) { $script:pausedElapsed + (Get-Date) - $script:startTime } else { $script:pausedElapsed }
    
    $lapStr = $lapElapsed.ToString("mm\:ss\.f")
    $script:laps = @("$($total.ToString('mm\:ss\.f')) [+$lapStr]") + $script:laps
    if ($script:laps.Count -gt 20) { $script:laps = $script:laps[0..19] }
    
    $lapList.Items.Clear()
    foreach ($l in $script:laps) { [void]$lapList.Items.Add($l) }
    
    # 重置当前分段，继续计时
    $script:lastLapTime = [TimeSpan]::Zero
    if ($script:running) {
        $script:lapStart = Get-Date
    }
}

function ResetAll {
    $script:running = $false; $script:startTime = $null
    $script:pausedElapsed = [TimeSpan]::Zero; $script:laps = @()
    $script:lapStart = $null; $script:lastLapTime = [TimeSpan]::Zero
    $lblTotal.Text = "00:00.0"
    $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 245, 255)
    $lblLap.Text = "分段 00:00.0"
    $lapList.Items.Clear()
    $btnStart.Text = "开始"
    $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 80)
    $mPause.Text = "开始"
}

function TogglePin {
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 255, 180)
        $titleBar.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 55, 80)
        $lblTitle.Cursor = [System.Windows.Forms.Cursors]::No
        $notifyIcon.ShowBalloonTip(1500, "任务栏计时器", "已固定位置", [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
        $titleBar.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)
        $lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll
    }
}

function ExitApp {
    $timer.Stop(); $timer.Dispose()
    if ($notifyIcon.Icon) { $notifyIcon.Icon.Dispose() }
    $notifyIcon.Dispose()
    $form.Close()
    [System.Windows.Forms.Application]::Exit()
}

# 图标
$bmp = New-Object System.Drawing.Bitmap(16, 16)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 80, 160, 255)), 1, 1, 14, 14)
$g.Dispose()
$ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true
$notifyIcon.Icon = $ico
$notifyIcon.Text = "任务栏计时器"

$trayCtx = New-Object System.Windows.Forms.ContextMenuStrip
$mShow = New-Object System.Windows.Forms.ToolStripMenuItem("显示窗口")
$mShow.Add_Click({ $form.Location = New-Object System.Drawing.Point(100, 100); $form.Show(); $form.Activate() })
$mPin = New-Object System.Windows.Forms.ToolStripMenuItem("固定位置")
$mPin.Add_Click({ TogglePin })
$mExit = New-Object System.Windows.Forms.ToolStripMenuItem("退出")
$mExit.Add_Click({ ExitApp })
[void]$trayCtx.Items.Add($mShow); [void]$trayCtx.Items.Add($mPin); [void]$trayCtx.Items.Add($mExit)
$notifyIcon.ContextMenuStrip = $trayCtx

# 定位
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $W - 10), ($scr.Bottom - $H - 4))

$timer.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
