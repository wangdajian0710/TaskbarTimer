# Taskbar Timer - 中文版 1.5x
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$W = 510
$H_MAIN = 117

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
$form.Size = New-Object System.Drawing.Size($W, 130)
$form.MinimumSize = New-Object System.Drawing.Size($W, 130)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 22, 35)

# ===== Title Bar =====
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = [System.Windows.Forms.DockStyle]::Top
$titleBar.Height = 39
$titleBar.BackColor = [System.Drawing.Color]::FromArgb(30, 34, 55)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblTitle.Text = "  >> Taskbar Timer"
$lblTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 190)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Dock = [System.Windows.Forms.DockStyle]::Right; $btnPin.Width = 42
$btnPin.Text = "Pin"
$btnPin.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 160)
$btnPin.BackColor = [System.Drawing.Color]::Transparent
$btnPin.FlatAppearance.BorderSize = 0

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Dock = [System.Windows.Forms.DockStyle]::Right; $btnClose.Width = 42
$btnClose.Text = "X"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
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

# ===== Timer Bar =====
$tBar = New-Object System.Windows.Forms.Panel
$tBar.Dock = [System.Windows.Forms.DockStyle]::Top
$tBar.Height = 78
$tBar.BackColor = [System.Drawing.Color]::FromArgb(25, 28, 42)
$tBar.Padding = [System.Windows.Forms.Padding]::new(15, 0, 15, 0)

# Drag handle
$dragH = New-Object System.Windows.Forms.Panel
$dragH.Size = New-Object System.Drawing.Size(9, 30)
$dragH.BackColor = [System.Drawing.Color]::FromArgb(80, 85, 100)
$dragH.Location = New-Object System.Drawing.Point(6, 24)
$dragH.Cursor = [System.Windows.Forms.Cursors]::SizeAll

# Current time box
$curBox = New-Object System.Windows.Forms.Panel
$curBox.Location = New-Object System.Drawing.Point(27, 12)
$curBox.Size = New-Object System.Drawing.Size(210, 54)
$curBox.BackColor = [System.Drawing.Color]::FromArgb(28, 44, 58)
$curBox.Padding = [System.Windows.Forms.Padding]::new(12, 6, 12, 6)

$lblCL = New-Object System.Windows.Forms.Label
$lblCL.Dock = [System.Windows.Forms.DockStyle]::Left; $lblCL.Width = 48
$lblCL.Text = [string][char]0x5F53 + [string][char]0x524D
$lblCL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14)
$lblCL.ForeColor = [System.Drawing.Color]::FromArgb(110, 120, 190)
$lblCL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$lblCur = New-Object System.Windows.Forms.Label
$lblCur.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblCur.Font = New-Object System.Drawing.Font("Consolas", 33, [System.Drawing.FontStyle]::Bold)
$lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
$lblCur.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCur.Text = "00:00.0"

[void]$curBox.Controls.AddRange(@($lblCL, $lblCur))

# Clock
$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Location = New-Object System.Drawing.Point(249, 27)
$lblClock.Font = New-Object System.Drawing.Font("Consolas", 15)
$lblClock.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 120)
$lblClock.Text = "HH:MM"

# Buttons
function MkBtn($t, $x, $c) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, 15)
    $b.Size = New-Object System.Drawing.Size(63, 48)
    $b.Text = $t
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.ForeColor = $c
    $b.BackColor = [System.Drawing.Color]::FromArgb(35, 40, 60)
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 55, 80)
    return $b
}

$btnS = MkBtn ([string][char]0x5F00 + [string][char]0x59CB) 310 ([System.Drawing.Color]::FromArgb(200, 136, 255, 136))
$btnL = MkBtn ([string][char]0x5206 + [string][char]0x6BB5) 380 ([System.Drawing.Color]::FromArgb(200, 136, 136, 255))
$btnC = MkBtn ([string][char]0x6E05 + [string][char]0x7A7A) 450 ([System.Drawing.Color]::FromArgb(200, 255, 136, 136))

[void]$tBar.Controls.AddRange(@($dragH, $curBox, $lblClock, $btnS, $btnL, $btnC))

# ===== Segment Panel =====
$segPanel = New-Object System.Windows.Forms.Panel
$segPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$segPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 17, 34)
$segPanel.AutoScroll = $true
$segPanel.Visible = $false

[void]$form.Controls.AddRange(@($segPanel, $tBar, $titleBar))

# ===== Build Segment Row =====
function New-Row($seg) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Height = 63
    $row.Dock = [System.Windows.Forms.DockStyle]::Top
    $row.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 38)
    $row.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 2)

    $nL = New-Object System.Windows.Forms.Label
    $nL.Location = New-Object System.Drawing.Point(9, 0)
    $nL.Size = New-Object System.Drawing.Size(36, 63)
    $nL.Text = "#$($seg.Id)"
    $nL.Font = New-Object System.Drawing.Font("Consolas", 14)
    $nL.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 100)
    $nL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $tL = New-Object System.Windows.Forms.Label
    $tL.Location = New-Object System.Drawing.Point(45, 3)
    $tL.Size = New-Object System.Drawing.Size(150, 33)
    $tL.Font = New-Object System.Drawing.Font("Consolas", 23, [System.Drawing.FontStyle]::Bold)
    $tL.ForeColor = [System.Drawing.Color]::FromArgb(255, 68, 68)
    $tL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $tL.Text = "00:00.0"

    $sL = New-Object System.Windows.Forms.Label
    $sL.Location = New-Object System.Drawing.Point(45, 36)
    $sL.Size = New-Object System.Drawing.Size(150, 24)
    $sL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12)
    $sL.ForeColor = [System.Drawing.Color]::FromArgb(150, 60, 60)
    $sL.Text = [string][char]0x25CF + " " + [string][char]0x8BA1 + [string][char]0x65F6 + [string][char]0x4E2D + "..."

    function MkSb($t, $x, $c, $act) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size = New-Object System.Drawing.Size(39, 39)
        $b.Location = New-Object System.Drawing.Point($x, 12)
        $b.Text = $t
        $b.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 15)
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

    $bP = MkSb "||" 381 ([System.Drawing.Color]::FromArgb(170, 170, 200)) "toggle"
    $bU = MkSb "^" 426 ([System.Drawing.Color]::FromArgb(170, 170, 200)) "promote"
    $bD = MkSb "X" 471 ([System.Drawing.Color]::FromArgb(170, 100, 100)) "remove"

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
        $form.ClientSize = New-Object System.Drawing.Size($W, $H_MAIN)
    } else {
        $segPanel.Visible = $true
        foreach ($seg in $script:segments) { [void]$segPanel.Controls.Add((New-Row $seg)) }
        $h = $H_MAIN + ($script:segments.Count * 63) + 6
        $scr = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        if ($h -gt $scr.Height - 40) { $h = $scr.Height - 40 }
        $form.ClientSize = New-Object System.Drawing.Size($W, $h)
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
    $btnS.Text = [string][char]0x6682 + [string][char]0x505C
    $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
}

function Do-Pause {
    if ($script:current.StartTime -and -not $script:current.PausedAt) {
        $script:current.PausedAt = Get-Date
    }
    $script:current.Running = $false
    $btnS.Text = [string][char]0x7EE7 + [string][char]0x7EED
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
        $btnS.Text = [string][char]0x6682 + [string][char]0x505C
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
        if ($seg.PausedAt) {
            $seg.TotalPausedMs += ((Get-Date) - $seg.PausedAt).TotalMilliseconds
            $seg.PausedAt = $null
        }
    } else {
        $btnS.Text = [string][char]0x5F00 + [string][char]0x59CB
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    }
    Rebuild-UI
}

function Do-Clear {
    $script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
    $script:segments.Clear()
    $btnS.Text = [string][char]0x5F00 + [string][char]0x59CB
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
        StartTime = $script:current.StartTime; PausedAt = $script:current.PausedAt
        TotalPausedMs = $script:current.TotalPausedMs; Running = $script:current.Running
    }
    $script:current = @{
        StartTime = $seg.StartTime; PausedAt = $seg.PausedAt
        TotalPausedMs = $seg.TotalPausedMs; Running = $seg.Running
    }
    $script:segments[$idx] = $old
    if ($script:current.Running) {
        $btnS.Text = [string][char]0x6682 + [string][char]0x505C
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
    } elseif ($script:current.StartTime) {
        $btnS.Text = [string][char]0x7EE7 + [string][char]0x7EED
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    } else {
        $btnS.Text = [string][char]0x5F00 + [string][char]0x59CB
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
    if ($script:current.StartTime) { $lblCur.Text = Fmt (Get-Elapsed $script:current) }
    foreach ($seg in $script:segments) {
        if (-not $script:segCtrls.ContainsKey($seg.Id)) { continue }
        $c = $script:segCtrls[$seg.Id]
        $c.TL.Text = Fmt (Get-Elapsed $seg)
        if ($seg.Running) {
            $c.SL.Text = [string][char]0x25CF + " " + [string][char]0x8BA1 + [string][char]0x65F6 + [string][char]0x4E2D + "..."
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(140, 55, 55)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(255, 68, 68)
            $c.PB.Text = "||"
        } else {
            $c.SL.Text = [string][char]0x5DF2 + [string][char]0x6682 + [string][char]0x505C
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
            $c.PB.Text = ">"
        }
    }
})

# ===== Right-click =====
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$mp = New-Object System.Windows.Forms.ToolStripMenuItem(([string][char]0x6682 + [string][char]0x505C + "/" + [string][char]0x7EE7 + [string][char]0x7EED))
$mp.Add_Click({ if ($script:current.Running) { Do-Pause } else { Do-Start } })
$mc = New-Object System.Windows.Forms.ToolStripMenuItem(([string][char]0x6E05 + [string][char]0x7A7A))
$mc.Add_Click({ Do-Clear })
[void]$ctx.Items.AddRange(@($mp, $mc))
$curBox.ContextMenuStrip = $ctx
$segPanel.ContextMenuStrip = $ctx

# ===== Tray =====
$bmp = New-Object System.Drawing.Bitmap(16, 16)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::White)
$g.FillEllipse([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(80, 160, 255)), 1, 1, 14, 14)
$g.Dispose()
$ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true; $notifyIcon.Icon = $ico
$notifyIcon.Text = "Taskbar Timer"

$tc = New-Object System.Windows.Forms.ContextMenuStrip
$m1 = New-Object System.Windows.Forms.ToolStripMenuItem(([string][char]0x663E + [string][char]0x793A + [string][char]0x7A97 + [string][char]0x53E3))
$m1.Add_Click({ $form.Show(); $form.Activate() })
$m2 = New-Object System.Windows.Forms.ToolStripMenuItem(([string][char]0x56FA + [string][char]0x5B9A + [string][char]0x4F4D + [string][char]0x7F6E))
$m2.Add_Click({ $btnPin.PerformClick() })
$m3 = New-Object System.Windows.Forms.ToolStripMenuItem(([string][char]0x9000 + [string][char]0x51FA))
$m3.Add_Click({ $btnClose.PerformClick() })
[void]$tc.Items.AddRange(@($m1, $m2, $m3))
$notifyIcon.ContextMenuStrip = $tc

# ===== Position =====
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $W - 10), ($scr.Bottom - 170))

$tk.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
