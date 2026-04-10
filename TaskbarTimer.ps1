# Taskbar Timer - 同步计时版
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$W = 280; $H = 280

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Drawing; using System.Windows.Forms;
public class Win32Forms {
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
    [DllImport("user32.dll")] public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    public const uint LWA_ALPHA = 2;
}
"@

# 计时器变量
$script:running = $false
$script:pinned = $false
$script:startTime = $null
$script:laps = @()
$script:lapStartTime = $null  # 当前分段的开始时间

# 主窗口
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($W, $H)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 18, 20, 32)

$form.Add_Load({
    $rgn = [Win32Forms]::CreateRoundRectRgn(0, 0, $form.Width, $form.Height, 10, 10)
    $form.Region = [System.Drawing.Region]::FromHrgn($rgn)
})
$form.Add_Shown({
    $null = [Win32Forms]::SetLayeredWindowAttributes($form.Handle, 0, 235, [Win32Forms]::LWA_ALPHA)
})

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
$btnPin.Dock = [System.Windows.Forms.DockStyle]::Right
$btnPin.Width = 28
$btnPin.Text = "📌"
$btnPin.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 9)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
$btnPin.BackColor = [System.Drawing.Color]::Transparent
$btnPin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPin.FlatAppearance.BorderSize = 0

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Dock = [System.Windows.Forms.DockStyle]::Right
$btnClose.Width = 28
$btnClose.Text = "X"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.FlatAppearance.BorderSize = 0

[void]$titleBar.Controls.Add($lblTitle)
[void]$titleBar.Controls.Add($btnPin)
[void]$titleBar.Controls.Add($btnClose)

# 拖动
$script:isDragging = $false
$lblTitle.Add_MouseDown({
    if (-not $script:pinned -and $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDragging = $true
        $script:dragOffset = $_.Location
    }
})
$lblTitle.Add_MouseMove({
    if ($script:isDragging -and -not $script:pinned) {
        $form.Location = [System.Drawing.Point]::new($form.Location.X + $_.X - $script:dragOffset.X, $form.Location.Y + $_.Y - $script:dragOffset.Y)
    }
})
$lblTitle.Add_MouseUp({ $script:isDragging = $false })

# 时钟行
$clockRow = New-Object System.Windows.Forms.Panel
$clockRow.Dock = [System.Windows.Forms.DockStyle]::Top
$clockRow.Height = 22
$clockRow.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)

$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Dock = [System.Windows.Forms.DockStyle]::Right
$lblClock.Width = 50
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

# 总时间区域
$totalBox = New-Object System.Windows.Forms.Panel
$totalBox.Location = New-Object System.Drawing.Point(12, 10)
$totalBox.Size = New-Object System.Drawing.Size(($W - 24), 70)
$totalBox.BackColor = [System.Drawing.Color]::FromArgb(60, 40, 90, 160)
$totalBox.Padding = [System.Windows.Forms.Padding]::new(10, 8, 10, 8)

$lblTotalTitle = New-Object System.Windows.Forms.Label
$lblTotalTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$lblTotalTitle.Height = 18
$lblTotalTitle.Text = "总时间"
$lblTotalTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$lblTotalTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 150, 200, 255)
$lblTotalTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblTotal.Font = New-Object System.Drawing.Font("Consolas", 32, [System.Drawing.FontStyle]::Bold)
$lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 160, 255)
$lblTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTotal.Text = "00:00.0"

[void]$totalBox.Controls.Add($lblTotal)
[void]$totalBox.Controls.Add($lblTotalTitle)

# 分段记录区域
$lapBox = New-Object System.Windows.Forms.Panel
$lapBox.Location = New-Object System.Drawing.Point(12, 86)
$lapBox.Size = New-Object System.Drawing.Size(($W - 24), 114)
$lapBox.BackColor = [System.Drawing.Color]::FromArgb(80, 25, 28, 35)
$lapBox.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 6)

$lblLapTitle = New-Object System.Windows.Forms.Label
$lblLapTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$lblLapTitle.Height = 20
$lblLapTitle.Text = "分段记录"
$lblLapTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8, [System.Drawing.FontStyle]::Bold)
$lblLapTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 200)
$lblLapTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$lapList = New-Object System.Windows.Forms.ListBox
$lapList.Dock = [System.Windows.Forms.DockStyle]::Fill
$lapList.BackColor = [System.Drawing.Color]::FromArgb(40, 30, 35, 45)
$lapList.ForeColor = [System.Drawing.Color]::FromArgb(220, 255, 255, 255)
$lapList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lapList.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)

[void]$lapBox.Controls.Add($lapList)
[void]$lapBox.Controls.Add($lblLapTitle)

[void]$timerPanel.Controls.Add($totalBox)
[void]$timerPanel.Controls.Add($lapBox)

# 按钮区
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$btnPanel.Height = 40
$btnPanel.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)
$btnPanel.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 6)

function MakeBtn($text, $width) {
    $b = New-Object System.Windows.Forms.Button
    $b.Dock = [System.Windows.Forms.DockStyle]::Left
    $b.Width = $width
    $b.Text = $text
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
    $b.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 80)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(70, 75, 100)
    return $b
}

$btnStart = MakeBtn "开始" 52
$btnLap = MakeBtn "分段" 52
$btnReset = MakeBtn "清空" 52
$btnPause = MakeBtn "暂停" 52
$btnPause.Visible = $false  # 开始后显示暂停

[void]$btnPanel.Controls.Add($btnReset)
[void]$btnPanel.Controls.Add($btnLap)
[void]$btnPanel.Controls.Add($btnPause)
[void]$btnPanel.Controls.Add($btnStart)

[void]$form.Controls.Add($btnPanel)
[void]$form.Controls.Add($timerPanel)
[void]$form.Controls.Add($clockRow)
[void]$form.Controls.Add($titleBar)

# 函数
function Start-Timer {
    $script:running = $true
    if (-not $script:startTime) {
        $script:startTime = Get-Date
        $script:lapStartTime = Get-Date
    }
    $btnStart.Visible = $false
    $btnPause.Visible = $true
    $btnPause.Text = "暂停"
}

function Stop-Timer {
    $script:running = $false
    $btnStart.Text = "继续"
    $btnStart.Visible = $true
    $btnPause.Visible = $false
}

# 按钮事件
$btnStart.Add_Click({ Start-Timer })

$btnPause.Add_Click({
    if ($script:running) { Stop-Timer } else { Start-Timer }
})

$btnLap.Add_Click({
    if ($script:startTime -and $script:running) {
        # 记录当前总时间
        $totalElapsed = (Get-Date) - $script:startTime
        $totalStr = $totalElapsed.ToString("mm\:ss\.f")
        
        # 同步计时：每段独立计时，从分段时刻开始重新计
        $script:lapStartTime = Get-Date
        
        # 添加到列表
        $script:laps = @($totalStr) + $script:laps
        if ($script:laps.Count -gt 20) { $script:laps = $script:laps[0..19] }
        
        $lapList.Items.Clear()
        foreach ($l in $script:laps) { [void]$lapList.Items.Add($l) }
    }
})

$btnReset.Add_Click({
    $script:running = $false
    $script:startTime = $null
    $script:lapStartTime = $null
    $script:laps = @()
    $lblTotal.Text = "00:00.0"
    $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 160, 255)
    $lapList.Items.Clear()
    $btnStart.Text = "开始"
    $btnStart.Visible = $true
    $btnPause.Visible = $false
})

$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 255, 180)
        $titleBar.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 55, 80)
        $lblTitle.Cursor = [System.Windows.Forms.Cursors]::No
    } else {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
        $titleBar.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 38, 58)
        $lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll
    }
})

$btnClose.Add_Click({
    $timer.Stop()
    $timer.Dispose()
    $notifyIcon.Dispose()
    $form.Close()
    [System.Windows.Forms.Application]::Exit()
})

# 定时器
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100

$timer.Add_Tick({
    $lblClock.Text = (Get-Date).ToString("HH:mm")
    
    if ($script:startTime) {
        $elapsed = (Get-Date) - $script:startTime
        $lblTotal.Text = $elapsed.ToString("mm\:ss\.f")
        if ($script:running) {
            $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
        }
    }
})

# 右键菜单
$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$mPause = New-Object System.Windows.Forms.ToolStripMenuItem("暂停")
$mPause.Add_Click({ if ($script:running) { Stop-Timer } else { Start-Timer } })
$mClear = New-Object System.Windows.Forms.ToolStripMenuItem("清除")
$mClear.Add_Click({ $btnReset.PerformClick() })
[void]$ctxMenu.Items.Add($mPause)
[void]$ctxMenu.Items.Add($mClear)
$timerPanel.ContextMenuStrip = $ctxMenu

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
$mShow.Add_Click({ $form.Show(); $form.Activate() })
$mPin = New-Object System.Windows.Forms.ToolStripMenuItem("固定位置")
$mPin.Add_Click({ $btnPin.PerformClick() })
$mExit = New-Object System.Windows.Forms.ToolStripMenuItem("退出")
$mExit.Add_Click({ $btnClose.PerformClick() })
[void]$trayCtx.Items.Add($mShow)
[void]$trayCtx.Items.Add($mPin)
[void]$trayCtx.Items.Add($mExit)
$notifyIcon.ContextMenuStrip = $trayCtx

# 定位
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $W - 10), ($scr.Bottom - $H - 4))

$timer.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
