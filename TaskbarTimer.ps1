# Taskbar Timer - 极简版（修复可见性）
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$W = 210; $H = 42; $TICK = 100

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
$script:laps = @(); $script:lapStart = $null; $script:expanded = $false

$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($W, $H)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 22, 24, 36)

$form.Add_Load({
    $rgn = [Win32Forms]::CreateRoundRectRgn(0, 0, $form.Width, $form.Height, 8, 8)
    $form.Region = [System.Drawing.Region]::FromHrgn($rgn)
})

$form.Add_Shown({ $null = [Win32Forms]::SetLayeredWindowAttributes($form.Handle, 0, 180, [Win32Forms]::LWA_ALPHA) })

$dragBar = New-Object System.Windows.Forms.Panel
$dragBar.Dock = [System.Windows.Forms.DockStyle]::Top
$dragBar.Height = 6
$dragBar.BackColor = [System.Drawing.Color]::FromArgb(200, 88, 91, 112)
$dragBar.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$barDragging = $false; $barStart = $null
$dragBar.Add_MouseDown({ if (!$script:pinned -and $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:barDragging = $true; $script:barStart = $_.Location; $dragBar.Capture = $true } })
$dragBar.Add_MouseMove({ if ($script:barDragging -and !$script:pinned) { $p = $form.PointToScreen($_.Location); $form.Location = New-Object System.Drawing.Point($p.X - $script:barStart.X, $p.Y - $script:barStart.Y) } })
$dragBar.Add_MouseUp({ $script:barDragging = $false; $dragBar.Capture = $false })

$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblTotal.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
$lblTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblTotal.Text = "00:00.0"

$btnLap = New-Object System.Windows.Forms.Button
$btnLap.Dock = [System.Windows.Forms.DockStyle]::Right; $btnLap.Width = 42
$btnLap.Text = "分段"; $btnLap.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnLap.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnLap.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 255)
$btnLap.BackColor = [System.Drawing.Color]::FromArgb(60, 65, 90); $btnLap.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnLap.FlatAppearance.BorderSize = 0; $btnLap.Margin = [System.Windows.Forms.Padding]::0; $btnLap.Padding = [System.Windows.Forms.Padding]::0
$btnLap.Add_Click({ ToggleDetail })

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Dock = [System.Windows.Forms.DockStyle]::Right; $btnPin.Width = 26
$btnPin.Text = "固定"; $btnPin.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
$btnPin.BackColor = [System.Drawing.Color]::Transparent; $btnPin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPin.FlatAppearance.BorderSize = 0
$btnPin.Add_Click({ TogglePin })

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Dock = [System.Windows.Forms.DockStyle]::Right; $btnStart.Width = 40
$btnStart.Text = "开始"; $btnStart.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 255)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(55, 60, 85); $btnStart.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.Add_Click({ ToggleTimer })

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Padding = [System.Windows.Forms.Padding]::new(4, 0, 4, 0)
[void]$contentPanel.Controls.Add($lblTotal)
[void]$contentPanel.Controls.Add($btnLap)
[void]$contentPanel.Controls.Add($btnPin)
[void]$contentPanel.Controls.Add($btnStart)

$form.Controls.Add($contentPanel)
$form.Controls.Add($dragBar)

$DW = 210; $DH = 310

$detailForm = New-Object System.Windows.Forms.Form
$detailForm.Size = New-Object System.Drawing.Size($DW, $DH)
$detailForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$detailForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$detailForm.TopMost = $true; $detailForm.ShowInTaskbar = $false
$detailForm.BackColor = [System.Drawing.Color]::FromArgb(220, 22, 24, 36)
$detailForm.Add_Load({
    $rgn = [Win32Forms]::CreateRoundRectRgn(0, 0, $detailForm.Width, $detailForm.Height, 8, 8)
    $detailForm.Region = [System.Drawing.Region]::FromHrgn($rgn)
})
$detailForm.Add_Shown({ $null = [Win32Forms]::SetLayeredWindowAttributes($detailForm.Handle, 0, 220, [Win32Forms]::LWA_ALPHA) })

$detailTop = New-Object System.Windows.Forms.Panel
$detailTop.Dock = [System.Windows.Forms.DockStyle]::Top
$detailTop.Height = 50; $detailTop.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 4)
$detailTop.BackColor = [System.Drawing.Color]::Transparent

$lblDetailTotal = New-Object System.Windows.Forms.Label
$lblDetailTotal.Dock = [System.Windows.Forms.DockStyle]::Top; $lblDetailTotal.Height = 22
$lblDetailTotal.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 240, 255)
$lblDetailTotal.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $lblDetailTotal.Text = "00:00.0"

$lblDetailLap = New-Object System.Windows.Forms.Label
$lblDetailLap.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblDetailLap.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblDetailLap.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 220)
$lblDetailLap.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $lblDetailLap.Text = "分段 00:00.0"

[void]$detailTop.Controls.Add($lblDetailLap); [void]$detailTop.Controls.Add($lblDetailTotal)

$detailBtnRow = New-Object System.Windows.Forms.Panel
$detailBtnRow.Dock = [System.Windows.Forms.DockStyle]::Top; $detailBtnRow.Height = 32
$detailBtnRow.Padding = [System.Windows.Forms.Padding]::new(8, 3, 8, 3)
$detailBtnRow.BackColor = [System.Drawing.Color]::Transparent

$btnDetailStart = New-Object System.Windows.Forms.Button
$btnDetailStart.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnDetailStart.Text = "开始"; $btnDetailStart.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDetailStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 255)
$btnDetailStart.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 90); $btnDetailStart.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDetailStart.FlatAppearance.BorderSize = 0
$btnDetailStart.Add_Click({ ToggleTimer; SyncDetailStart })

$btnDetailLap = New-Object System.Windows.Forms.Button
$btnDetailLap.Dock = [System.Windows.Forms.DockStyle]::Left; $btnDetailLap.Width = 46
$btnDetailLap.Text = "分段"; $btnDetailLap.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailLap.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDetailLap.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 255)
$btnDetailLap.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 90); $btnDetailLap.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDetailLap.FlatAppearance.BorderSize = 0
$btnDetailLap.Add_Click({ RecordLap; ToggleDetail })

$btnDetailClose = New-Object System.Windows.Forms.Button
$btnDetailClose.Dock = [System.Windows.Forms.DockStyle]::Right; $btnDetailClose.Width = 36
$btnDetailClose.Text = "关闭"; $btnDetailClose.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDetailClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 180, 180)
$btnDetailClose.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 90); $btnDetailClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDetailClose.FlatAppearance.BorderSize = 0
$btnDetailClose.Add_Click({ ToggleDetail })

$btnDetailReset = New-Object System.Windows.Forms.Button
$btnDetailReset.Dock = [System.Windows.Forms.DockStyle]::Right; $btnDetailReset.Width = 36
$btnDetailReset.Text = "清空"; $btnDetailReset.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDetailReset.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDetailReset.ForeColor = [System.Drawing.Color]::FromArgb(200, 180, 180)
$btnDetailReset.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 90); $btnDetailReset.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDetailReset.FlatAppearance.BorderSize = 0
$btnDetailReset.Add_Click({
    $script:running = $false; $script:startTime = $null
    $script:pausedElapsed = [TimeSpan]::Zero; $script:laps = @(); $script:lapStart = $null
    $lblTotal.Text = "00:00.0"; $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 255)
    $lblDetailTotal.Text = "00:00.0"; $lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 240, 255)
    $lblDetailLap.Text = "分段 00:00.0"
    $btnStart.Text = "开始"; $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 255)
    $detailLapList.Items.Clear(); $detailForm.Hide(); $script:expanded = $false
})

[void]$detailBtnRow.Controls.Add($btnDetailStart)
[void]$detailBtnRow.Controls.Add($btnDetailLap)
[void]$detailBtnRow.Controls.Add($btnDetailClose)
[void]$detailBtnRow.Controls.Add($btnDetailReset)

$detailLapList = New-Object System.Windows.Forms.ListBox
$detailLapList.Dock = [System.Windows.Forms.DockStyle]::Fill
$detailLapList.BackColor = [System.Drawing.Color]::FromArgb(40, 22, 24, 36)
$detailLapList.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 220)
$detailLapList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$detailLapList.Font = New-Object System.Drawing.Font("Consolas", 9)

[void]$detailForm.Controls.Add($detailLapList)
[void]$detailForm.Controls.Add($detailBtnRow)
[void]$detailForm.Controls.Add($detailTop)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $TICK
$timer.Add_Tick({
    if ($script:running) {
        $elapsed = $script:pausedElapsed + (Get-Date) - $script:startTime
        $ts = $elapsed.ToString("mm\:ss\.f")
        $lblTotal.Text = $ts; $lblDetailTotal.Text = $ts
        $lapElapsed = if ($script:lapStart) { (Get-Date) - $script:lapStart } else { [TimeSpan]::Zero }
        $lblDetailLap.Text = "分段 " + $lapElapsed.ToString("mm\:ss\.f")
        $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 210, 150)
        $lblDetailTotal.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 210, 150)
    }
})

function ToggleTimer {
    if (-not $script:running) {
        $script:running = $true
        $script:lapStart = if ($script:lapStart) { $script:lapStart } else { Get-Date }
        if (-not $script:startTime) { $script:startTime = Get-Date }
        $btnStart.Text = "暂停"; $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 120)
        SyncDetailStart
    } else {
        $script:running = $false
        $script:pausedElapsed += if ($script:lapStart) { (Get-Date) - $script:lapStart } else { [TimeSpan]::Zero }
        $script:lapStart = $null
        $btnStart.Text = "开始"; $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 255)
        SyncDetailStart
    }
}

function SyncDetailStart {
    $btnDetailStart.Text = $btnStart.Text
    $btnDetailStart.ForeColor = $btnStart.ForeColor
}

function TogglePin {
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 255, 180)
        $dragBar.BackColor = [System.Drawing.Color]::FromArgb(200, 100, 180, 220)
        $dragBar.Cursor = [System.Windows.Forms.Cursors]::No
        $notifyIcon.ShowBalloonTip(1500, "任务栏计时器", "已固定位置，再点固定取消", [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
        $dragBar.BackColor = [System.Drawing.Color]::FromArgb(200, 88, 91, 112)
        $dragBar.Cursor = [System.Windows.Forms.Cursors]::SizeAll
    }
}

function RecordLap {
    $total = if ($script:startTime) { $script:pausedElapsed + (Get-Date) - $script:startTime } else { $script:pausedElapsed }
    $lap = if ($script:lapStart) { (Get-Date) - $script:lapStart } else { [TimeSpan]::Zero }
    $script:laps = @("$($total.ToString('mm\:ss\.f')) [+$($lap.ToString('mm\:ss\.f'))]") + $script:laps
    if ($script:laps.Count -gt 10) { $script:laps = $script:laps[0..9] }
    $detailLapList.Items.Clear(); foreach ($l in $script:laps) { [void]$detailLapList.Items.Add($l) }
    $script:lapStart = Get-Date
}

function ToggleDetail {
    if (-not $script:expanded) {
        $sp = $form.Location
        $detailForm.Location = New-Object System.Drawing.Point($sp.X, $sp.Y - $DH - 2)
        $detailForm.Show(); $script:expanded = $true
        SyncDetailStart
    } else {
        $detailForm.Hide(); $script:expanded = $false
    }
}

function Build-TimerIcon {
    param($Running = $false)
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $c = if ($Running) { [System.Drawing.Color]::FromArgb(255, 255, 160, 50) } else { [System.Drawing.Color]::FromArgb(255, 100, 180, 255) }
    $g.FillEllipse([System.Drawing.SolidBrush]::new($c), 1, 1, 14, 14)
    $g.Dispose()
    [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true
$notifyIcon.Icon = Build-TimerIcon -Running $false
$notifyIcon.Text = "任务栏计时器"

$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$mPin = New-Object System.Windows.Forms.ToolStripMenuItem("固定位置")
$mPin.Add_Click({ TogglePin })
$mExit = New-Object System.Windows.Forms.ToolStripMenuItem("退出")
$mExit.Add_Click({
    $timer.Stop(); $timer.Dispose()
    if ($notifyIcon.Icon) { $notifyIcon.Icon.Dispose() }
    $notifyIcon.Dispose()
    $detailForm.Close()
    $form.Close()
    [System.Windows.Forms.Application]::Exit()
})
[void]$ctxMenu.Items.Add($mPin); [void]$ctxMenu.Items.Add($mExit)
$notifyIcon.ContextMenuStrip = $ctxMenu

$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $W - 10), ($scr.Bottom - $H - 4))

$timer.Start()
$form.Show()
$detailForm.Hide()
[System.Windows.Forms.Application]::Run()
