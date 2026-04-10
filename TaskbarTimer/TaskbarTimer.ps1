# Taskbar Timer - 分段接力计时版
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:W = 340

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Drawing; using System.Windows.Forms;
public class Win32H {
    [DllImport("user32.dll")] public static extern IntPtr CreateRoundRectRgn(int x1,int y1,int x2,int y2,int w,int h);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint crKey,byte bAlpha,uint dwFlags);
    public const uint LWA_ALPHA = 2;
}
"@

# ===== State =====
$script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
$script:segments = [System.Collections.ArrayList]::new()
$script:nextId = 1
$script:pinned = $false
$script:segCtrls = @{}

function Get-Elapsed($s) {
    if (-not $s.StartTime) { return [TimeSpan]::Zero }
    $end = if ($s.PausedAt) { $s.PausedAt } else { Get-Date }
    return [TimeSpan]::FromMilliseconds([Math]::Max(0, ($end - $s.StartTime).TotalMilliseconds - $s.TotalPausedMs))
}
function Fmt($ts) {
    if ($ts.TotalHours -ge 1) { return $ts.ToString("hh\:mm\:ss\.f") }
    return $ts.ToString("mm\:ss\.f")
}

# ===== Form =====
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($script:W, 90)
$form.MinimumSize = New-Object System.Drawing.Size($script:W, 90)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 22, 35)

$form.Add_Load({
    $form.Region = [System.Drawing.Region]::FromHrgn(
        [Win32H]::CreateRoundRectRgn(0,0,$form.Width,$form.Height,12,12))
})
$form.Add_Shown({
    [Win32H]::SetLayeredWindowAttributes($form.Handle, 0, 230, [Win32H]::LWA_ALPHA) | Out-Null
})

# ===== Title Bar =====
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = [System.Windows.Forms.DockStyle]::Top
$titleBar.Height = 26
$titleBar.BackColor = [System.Drawing.Color]::FromArgb(180, 30, 34, 55)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblTitle.Text = "  " + [char]0x23F0 + " Taskbar Timer"
$lblTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 190)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Dock = [System.Windows.Forms.DockStyle]::Right; $btnPin.Width = 28
$btnPin.Text = [char]0x1F4CC
$btnPin.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 9)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 160)
$btnPin.BackColor = [System.Drawing.Color]::Transparent
$btnPin.FlatAppearance.BorderSize = 0

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Dock = [System.Windows.Forms.DockStyle]::Right; $btnClose.Width = 28
$btnClose.Text = "X"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 180)
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.FlatAppearance.BorderSize = 0

[void]$titleBar.Controls.AddRange(@($lblTitle, $btnPin, $btnClose))

# Drag
$script:isDrag = $false
$lblTitle.Add_MouseDown({ param($s,$e)
    if (-not $script:pinned -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDrag = $true; $script:dOff = $e.Location }
})
$lblTitle.Add_MouseMove({ param($s,$e)
    if ($script:isDrag -and -not $script:pinned) {
        $form.Location = [System.Drawing.Point]::new($form.Location.X + $e.X - $script:dOff.X, $form.Location.Y + $e.Y - $script:dOff.Y) }
})
$lblTitle.Add_MouseUp({ $script:isDrag = $false })

# ===== Timer Bar (matches mockup exactly) =====
$tBar = New-Object System.Windows.Forms.Panel
$tBar.Dock = [System.Windows.Forms.DockStyle]::Top
$tBar.Height = 52
$tBar.BackColor = [System.Drawing.Color]::FromArgb(200, 25, 28, 42)
$tBar.Padding = [System.Windows.Forms.Padding]::new(10, 0, 10, 0)

# Drag handle
$dragH = New-Object System.Windows.Forms.Panel
$dragH.Size = New-Object System.Drawing.Size(6, 20)
$dragH.BackColor = [System.Drawing.Color]::FromArgb(80, 85, 100)
$dragH.Location = New-Object System.Drawing.Point(4, 16)
$dragH.Cursor = [System.Windows.Forms.Cursors]::SizeAll

# Current time box
$curBox = New-Object System.Windows.Forms.Panel
$curBox.Location = New-Object System.Drawing.Point(18, 8)
$curBox.Size = New-Object System.Drawing.Size(140, 36)
$curBox.BackColor = [System.Drawing.Color]::FromArgb(35, 28, 44, 58)
$curBox.Padding = [System.Windows.Forms.Padding]::new(8, 4, 8, 4)

$lblCL = New-Object System.Windows.Forms.Label
$lblCL.Dock = [System.Windows.Forms.DockStyle]::Left; $lblCL.Width = 32
$lblCL.Text = [char]0x5F53 + [char]0x524D
$lblCL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblCL.ForeColor = [System.Drawing.Color]::FromArgb(110, 120, 190)
$lblCL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$lblCur = New-Object System.Windows.Forms.Label
$lblCur.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblCur.Font = New-Object System.Drawing.Font("Consolas", 22, [System.Drawing.FontStyle]::Bold)
$lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 160, 255)
$lblCur.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCur.Text = "00:00.0"

[void]$curBox.Controls.AddRange(@($lblCL, $lblCur))

# Clock
$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Location = New-Object System.Drawing.Point(166, 18)
$lblClock.Font = New-Object System.Drawing.Font("Consolas", 10)
$lblClock.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 120)
$lblClock.Text = "HH:MM"

# Buttons - Chinese text matching mockup
function MkBtn($t, $x, $c) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, 10)
    $b.Size = New-Object System.Drawing.Size(42, 32)
    $b.Text = $t
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.ForeColor = $c
    $b.BackColor = [System.Drawing.Color]::FromArgb(35, 40, 60)
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 55, 80)
    return $b
}

$btnS = MkBtn ([char]0x5F00 + [char]0x59CB) 220 ([System.Drawing.Color]::FromArgb(200, 136, 255, 136))
$btnL = MkBtn ([char]0x5206 + [char]0x6BB5) 268 ([System.Drawing.Color]::FromArgb(200, 136, 136, 255))
$btnC = MkBtn ([char]0x6E05 + [char]0x7A7A) 316 ([System.Drawing.Color]::FromArgb(200, 255, 136, 136))

[void]$tBar.Controls.AddRange(@($dragH, $curBox, $lblClock, $btnS, $btnL, $btnC))

# ===== Segment Panel =====
$segPanel = New-Object System.Windows.Forms.Panel
$segPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$segPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 17, 34)
$segPanel.AutoScroll = $true
$segPanel.Visible = $false

[void]$form.Controls.AddRange(@($segPanel, $tBar, $titleBar))

# ===== Build Segment Row (matches mockup exactly) =====
function New-Row($seg) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Height = 42
    $row.Dock = [System.Windows.Forms.DockStyle]::Top
    $row.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 38)
    $row.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 1)

    # #N
    $nL = New-Object System.Windows.Forms.Label
    $nL.Location = New-Object System.Drawing.Point(6, 0)
    $nL.Size = New-Object System.Drawing.Size(24, 42)
    $nL.Text = "#$($seg.Id)"
    $nL.Font = New-Object System.Drawing.Font("Consolas", 9)
    $nL.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 100)
    $nL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    # Time (red)
    $tL = New-Object System.Windows.Forms.Label
    $tL.Location = New-Object System.Drawing.Point(30, 2)
    $tL.Size = New-Object System.Drawing.Size(100, 22)
    $tL.Font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
    $tL.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 68, 68)
    $tL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $tL.Text = "00:00.0"

    # Status
    $sL = New-Object System.Windows.Forms.Label
    $sL.Location = New-Object System.Drawing.Point(30, 24)
    $sL.Size = New-Object System.Drawing.Size(100, 16)
    $sL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8)
    $sL.ForeColor = [System.Drawing.Color]::FromArgb(150, 60, 60)
    $sL.Text = [char]0x25CF + " " + [char]0x8BA1 + [char]0x65F6 + [char]0x4E2D + "..."

    # Segment buttons: ⏸ ⬆ ✕
    function MkSb($t, $x, $c, $act) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size = New-Object System.Drawing.Size(26, 26)
        $b.Location = New-Object System.Drawing.Point($x, 8)
        $b.Text = $t
        $b.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 10)
        $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $b.ForeColor = $c
        $b.BackColor = [System.Drawing.Color]::FromArgb(30, 34, 48)
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(45, 48, 68)
        $b.Tag = $seg.Id
        $b.Add_Click({ param($sender, $e)
            $id = $sender.Tag
            switch ($act) {
                "toggle"  { Do-Toggle $id }
                "promote" { Do-Promote $id }
                "remove"  { Do-Remove $id }
            }
        })
        return $b
    }

    $bP = MkSb [char]0x23F8 254 ([System.Drawing.Color]::FromArgb(170, 170, 200)) "toggle"
    $bU = MkSb [char]0x2B06 284 ([System.Drawing.Color]::FromArgb(170, 170, 200)) "promote"
    $bD = MkSb [char]0x2715 314 ([System.Drawing.Color]::FromArgb(170, 100, 100)) "remove"

    [void]$row.Controls.AddRange(@($nL, $tL, $sL, $bP, $bU, $bD))
    $script:segCtrls[$seg.Id] = @{ Row=$row; TL=$tL; SL=$sL; PB=$bP }
    return $row
}

function Rebuild-UI {
    foreach ($k in @($script:segCtrls.Keys)) {
        $c = $script:segCtrls[$k]
        if ($c.Row.Parent) { $c.Row.Parent.Controls.Remove($c.Row) }
        $c.Row.Dispose()
    }
    $script:segCtrls.Clear()
    if ($script:segments.Count -eq 0) {
        $segPanel.Visible = $false
        $form.ClientSize = New-Object System.Drawing.Size($script:W, 78)
    } else {
        $segPanel.Visible = $true
        foreach ($seg in $script:segments) { [void]$segPanel.Controls.Add((New-Row $seg)) }
        $h = 78 + ($script:segments.Count * 42) + 4
        $scr = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        if ($h -gt $scr.Height - 40) { $h = $scr.Height - 40 }
        $form.ClientSize = New-Object System.Drawing.Size($script:W, $h)
    }
}

# ===== Actions =====
function Do-Start {
    if (-not $script:current.StartTime) { $script:current.StartTime = Get-Date }
    if ($script:current.PausedAt) {
        $script:current.TotalPausedMs += ((Get-Date) - $script:current.PausedAt).TotalMilliseconds
        $script:current.PausedAt = $null
    }
    $script:current.Running = $true
    $btnS.Text = [char]0x6682 + [char]0x505C
    $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
}

function Do-Pause {
    if ($script:current.StartTime -and -not $script:current.PausedAt) {
        $script:current.PausedAt = Get-Date
    }
    $script:current.Running = $false
    $btnS.Text = [char]0x7EE7 + [char]0x7EED
    $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
}

function Do-Split {
    if (-not $script:current.StartTime) { return }
    $wasRunning = $script:current.Running
    if ($wasRunning -and -not $script:current.PausedAt) {
        $script:current.PausedAt = Get-Date
    }
    $seg = @{
        Id = $script:nextId++
        StartTime = $script:current.StartTime
        PausedAt = $script:current.PausedAt
        TotalPausedMs = $script:current.TotalPausedMs
        Running = $wasRunning
    }
    [void]$script:segments.Insert(0, $seg)
    if ($script:segments.Count -gt 30) { $script:segments.RemoveAt($script:segments.Count - 1) }

    $script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
    $lblCur.Text = "00:00.0"

    if ($wasRunning) {
        $script:current.StartTime = Get-Date
        $script:current.Running = $true
        $btnS.Text = [char]0x6682 + [char]0x505C
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
        if ($seg.PausedAt) {
            $seg.TotalPausedMs += ((Get-Date) - $seg.PausedAt).TotalMilliseconds
            $seg.PausedAt = $null
        }
    } else {
        $btnS.Text = [char]0x5F00 + [char]0x59CB
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    }
    Rebuild-UI
}

function Do-Clear {
    $script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
    $script:segments.Clear()
    $btnS.Text = [char]0x5F00 + [char]0x59CB
    $lblCur.Text = "00:00.0"
    $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    Rebuild-UI
}

function Do-Toggle($id) {
    $seg = $null
    foreach ($s in $script:segments) { if ($s.Id -eq $id) { $seg = $s; break } }
    if (-not $seg) { return }
    if ($seg.Running) {
        if (-not $seg.PausedAt) { $seg.PausedAt = Get-Date }
        $seg.Running = $false
    } else {
        if ($seg.PausedAt) {
            $seg.TotalPausedMs += ((Get-Date) - $seg.PausedAt).TotalMilliseconds
            $seg.PausedAt = $null
        }
        if ($seg.StartTime) { $seg.Running = $true }
    }
}

function Do-Promote($id) {
    $idx = -1
    for ($i = 0; $i -lt $script:segments.Count; $i++) {
        if ($script:segments[$i].Id -eq $id) { $idx = $i; break }
    }
    if ($idx -lt 0) { return }
    $seg = $script:segments[$idx]

    $old = @{
        Id = $script:nextId++
        StartTime = $script:current.StartTime
        PausedAt = $script:current.PausedAt
        TotalPausedMs = $script:current.TotalPausedMs
        Running = $script:current.Running
    }
    $script:current = @{
        StartTime = $seg.StartTime; PausedAt = $seg.PausedAt
        TotalPausedMs = $seg.TotalPausedMs; Running = $seg.Running
    }
    $script:segments[$idx] = $old

    if ($script:current.Running) {
        $btnS.Text = [char]0x6682 + [char]0x505C
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
    } elseif ($script:current.StartTime) {
        $btnS.Text = [char]0x7EE7 + [char]0x7EED
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    } else {
        $btnS.Text = [char]0x5F00 + [char]0x59CB
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    }
    Rebuild-UI
}

function Do-Remove($id) {
    for ($i = 0; $i -lt $script:segments.Count; $i++) {
        if ($script:segments[$i].Id -eq $id) { $script:segments.RemoveAt($i); break }
    }
    Rebuild-UI
}

# ===== Button Events =====
$btnS.Add_Click({ if ($script:current.Running) { Do-Pause } else { Do-Start } })
$btnL.Add_Click({ Do-Split })
$btnC.Add_Click({ Do-Clear })

$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 255, 180)
        $lblTitle.Cursor = [System.Windows.Forms.Cursors]::No
    } else {
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 160)
        $lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll
    }
})

$btnClose.Add_Click({
    $tk.Stop(); $tk.Dispose(); $notifyIcon.Dispose()
    $form.Close(); [System.Windows.Forms.Application]::Exit()
})

# ===== Tick =====
$tk = New-Object System.Windows.Forms.Timer; $tk.Interval = 100
$tk.Add_Tick({
    $lblClock.Text = (Get-Date).ToString("HH:mm")
    if ($script:current.StartTime) {
        $lblCur.Text = Fmt (Get-Elapsed $script:current)
    }
    foreach ($seg in $script:segments) {
        if (-not $script:segCtrls.ContainsKey($seg.Id)) { continue }
        $c = $script:segCtrls[$seg.Id]
        $c.TL.Text = Fmt (Get-Elapsed $seg)
        if ($seg.Running) {
            $c.SL.Text = [char]0x25CF + " " + [char]0x8BA1 + [char]0x65F6 + [char]0x4E2D + "..."
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(140, 55, 55)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 68, 68)
            $c.PB.Text = [char]0x23F8
        } else {
            $c.SL.Text = [char]0x5DF2 + [char]0x6682 + [char]0x505C
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
            $c.PB.Text = [char]0x25B6
        }
    }
})

# ===== Right-click =====
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$mp = New-Object System.Windows.Forms.ToolStripMenuItem(([char]0x6682 + [char]0x505C + "/" + [char]0x7EE7 + [char]0x7EED))
$mp.Add_Click({ if ($script:current.Running) { Do-Pause } else { Do-Start } })
$mc = New-Object System.Windows.Forms.ToolStripMenuItem(([char]0x6E05 + [char]0x7A7A))
$mc.Add_Click({ Do-Clear })
[void]$ctx.Items.AddRange(@($mp, $mc))
$curBox.ContextMenuStrip = $ctx
$segPanel.ContextMenuStrip = $ctx

# ===== Tray =====
$bmp = New-Object System.Drawing.Bitmap(16, 16)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 80, 160, 255)), 1, 1, 14, 14)
$g.Dispose()
$ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true; $notifyIcon.Icon = $ico
$notifyIcon.Text = "Taskbar Timer"

$tc = New-Object System.Windows.Forms.ContextMenuStrip
$m1 = New-Object System.Windows.Forms.ToolStripMenuItem(([char]0x663E + [char]0x793A + [char]0x7A97 + [char]0x53E3))
$m1.Add_Click({ $form.Show(); $form.Activate() })
$m2 = New-Object System.Windows.Forms.ToolStripMenuItem(([char]0x56FA + [char]0x5B9A + [char]0x4F4D + [char]0x7F6E))
$m2.Add_Click({ $btnPin.PerformClick() })
$m3 = New-Object System.Windows.Forms.ToolStripMenuItem(([char]0x9000 + [char]0x51FA))
$m3.Add_Click({ $btnClose.PerformClick() })
[void]$tc.Items.AddRange(@($m1, $m2, $m3))
$notifyIcon.ContextMenuStrip = $tc

# ===== Position =====
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $script:W - 10), ($scr.Bottom - 120))

$tk.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
