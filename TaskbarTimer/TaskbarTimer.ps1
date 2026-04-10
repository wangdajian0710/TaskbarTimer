# Taskbar Timer v5
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== Constants (avoid $script:W math bug in PS5.1) =====
$W = 400
$H_MAIN = 86

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
$form.ClientSize = New-Object System.Drawing.Size($W, $H_MAIN)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 32, 48)

# ===== Title Bar (y=0) =====
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Location = New-Object System.Drawing.Point(0, 0)
$titleBar.Size = New-Object System.Drawing.Size($W, 26)
$titleBar.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 62)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = New-Object System.Drawing.Point(0, 0)
$lblTitle.Size = New-Object System.Drawing.Size(344, 26)
$lblTitle.Text = "  Taskbar Timer"
$lblTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 210)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Location = New-Object System.Drawing.Point(344, 0)
$btnPin.Size = New-Object System.Drawing.Size(28, 26)
$btnPin.Text = "Pin"
$btnPin.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 160)
$btnPin.BackColor = [System.Drawing.Color]::Transparent
$btnPin.FlatAppearance.BorderSize = 0

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location = New-Object System.Drawing.Point(372, 0)
$btnClose.Size = New-Object System.Drawing.Size(28, 26)
$btnClose.Text = "X"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.FlatAppearance.BorderSize = 0

[void]$form.Controls.AddRange(@($titleBar, $lblTitle, $btnPin, $btnClose))

# Drag
$script:isDrag = $false
$lblTitle.Add_MouseDown({ param($s,$e)
    if (-not $script:pinned -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDrag = $true; $script:dOff = $e.Location }
})
$lblTitle.Add_MouseMove({ param($s,$e)
    if ($script:isDrag -and -not $script:pinned) {
        $form.Location = New-Object System.Drawing.Point($form.Location.X + $e.X - $script:dOff.X, $form.Location.Y + $e.Y - $script:dOff.Y) }
})
$lblTitle.Add_MouseUp({ $script:isDrag = $false })
$lblTitle.Add_MouseDoubleClick({ $form.Hide() })

# ===== Timer Bar (y=26) =====
$tBar = New-Object System.Windows.Forms.Panel
$tBar.Location = New-Object System.Drawing.Point(0, 26)
$tBar.Size = New-Object System.Drawing.Size($W, 60)
$tBar.BackColor = [System.Drawing.Color]::FromArgb(35, 37, 55)

# Current time box
$curBox = New-Object System.Windows.Forms.Panel
$curBox.Location = New-Object System.Drawing.Point(10, 10)
$curBox.Size = New-Object System.Drawing.Size(160, 40)
$curBox.BackColor = [System.Drawing.Color]::FromArgb(50, 52, 75)
$curBox.Cursor = [System.Windows.Forms.Cursors]::Hand

$lblCL = New-Object System.Windows.Forms.Label
$lblCL.Location = New-Object System.Drawing.Point(8, 0)
$lblCL.Size = New-Object System.Drawing.Size(35, 40)
$lblCL.Text = [string][char]0x5F53 + [string][char]0x524D
$lblCL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$lblCL.ForeColor = [System.Drawing.Color]::FromArgb(130, 140, 210)
$lblCL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$lblCur = New-Object System.Windows.Forms.Label
$lblCur.Location = New-Object System.Drawing.Point(42, 0)
$lblCur.Size = New-Object System.Drawing.Size(110, 40)
$lblCur.Font = New-Object System.Drawing.Font("Consolas", 24, [System.Drawing.FontStyle]::Bold)
$lblCur.ForeColor = [System.Drawing.Color]::White
$lblCur.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCur.Text = "00:00.0"

[void]$form.Controls.AddRange(@($tBar, $curBox, $lblCL, $lblCur))
$curBox.Add_Click({ if ($script:current.Running) { Do-Pause } else { Do-Start } })

# Clock
$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Location = New-Object System.Drawing.Point(180, 22)
$lblClock.Font = New-Object System.Drawing.Font("Consolas", 11)
$lblClock.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 150)
$lblClock.Text = "HH:MM"
$form.Controls.Add($lblClock)

# Buttons
function MkBtn($t, $x, $c) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, 32)
    $b.Size = New-Object System.Drawing.Size(50, 30)
    $b.Text = $t
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.ForeColor = $c
    $b.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 78)
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(70, 75, 100)
    return $b
}

$btnS = MkBtn "Start" 240 White
$btnL = MkBtn "Split" 296 ([System.Drawing.Color]::FromArgb(180, 180, 255))
$btnC = MkBtn "Clear" 352 ([System.Drawing.Color]::FromArgb(255, 180, 180))

[void]$form.Controls.AddRange(@($btnS, $btnL, $btnC))

# ===== Segment Panel (y=86) =====
$segPanel = New-Object System.Windows.Forms.Panel
$segPanel.Location = New-Object System.Drawing.Point(0, 86)
$segPanel.Size = New-Object System.Drawing.Size($W, 0)
$segPanel.BackColor = [System.Drawing.Color]::FromArgb(25, 27, 40)
$segPanel.Visible = $false
$form.Controls.Add($segPanel)

# ===== Segment Row =====
function New-Row($seg) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Size = New-Object System.Drawing.Size($W, 46)
    $row.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 58)

    $nL = New-Object System.Windows.Forms.Label
    $nL.Location = New-Object System.Drawing.Point(8, 0); $nL.Size = New-Object System.Drawing.Size(28, 46)
    $nL.Text = "#$($seg.Id)"; $nL.Font = New-Object System.Drawing.Font("Consolas", 10)
    $nL.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 130)
    $nL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $tL = New-Object System.Windows.Forms.Label
    $tL.Location = New-Object System.Drawing.Point(38, 2); $tL.Size = New-Object System.Drawing.Size(110, 24)
    $tL.Font = New-Object System.Drawing.Font("Consolas", 16, [System.Drawing.FontStyle]::Bold)
    $tL.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
    $tL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $tL.Text = "00:00.0"

    $sL = New-Object System.Windows.Forms.Label
    $sL.Location = New-Object System.Drawing.Point(38, 26); $sL.Size = New-Object System.Drawing.Size(110, 18)
    $sL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $sL.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 70)
    $sL.Text = "* running..."

    function MkSb($t, $x, $c, $act) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size = New-Object System.Drawing.Size(40, 32)
        $b.Location = New-Object System.Drawing.Point($x, 7)
        $b.Text = $t; $b.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $b.ForeColor = $c
        $b.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 80)
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 85, 110)
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(75, 78, 105)
        $b.Tag = $seg.Id
        $b.Add_Click({ param($sender, $e)
            switch ($act) {
                "toggle"  { Do-Toggle $sender.Tag }
                "promote" { Do-Promote $sender.Tag }
                "remove"  { Do-Remove $sender.Tag }
            }
        })
        return $b
    }

    $bP = MkSb "||" 260 White "toggle"
    $bU = MkSb "^" 308 White "promote"
    $bD = MkSb "X" 356 ([System.Drawing.Color]::FromArgb(255, 120, 120)) "remove"

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
        $h = $script:segments.Count * 46
        $segPanel.Size = New-Object System.Drawing.Size($W, $h)
        $totalH = $H_MAIN + $h
        $scr = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        if ($totalH -gt $scr.Height - 40) { $totalH = $scr.Height - 40 }
        $form.ClientSize = New-Object System.Drawing.Size($W, $totalH)
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
    $btnS.Text = "Pause"
    $btnS.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 100)
}

function Do-Pause {
    if ($script:current.StartTime -and -not $script:current.PausedAt) {
        $script:current.PausedAt = Get-Date
    }
    $script:current.Running = $false
    $btnS.Text = "Resume"
    $btnS.ForeColor = [System.Drawing.Color]::White
}

function Do-Split {
    if (-not $script:current.StartTime) { return }
    $seg = @{
        Id = $script:nextId++
        StartTime = $script:current.StartTime
        PausedAt = $script:current.PausedAt
        TotalPausedMs = $script:current.TotalPausedMs
        Running = $script:current.Running
    }
    [void]$script:segments.Insert(0, $seg)
    if ($script:segments.Count -gt 20) { $script:segments.RemoveAt($script:segments.Count - 1) }
    $script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
    $lblCur.Text = "00:00.0"
    $btnS.Text = "Start"
    $btnS.ForeColor = [System.Drawing.Color]::White
    Rebuild-UI
}

function Do-Clear {
    $script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
    $script:segments.Clear()
    $btnS.Text = "Start"
    $lblCur.Text = "00:00.0"
    $btnS.ForeColor = [System.Drawing.Color]::White
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
        $btnS.Text = "Pause"
        $btnS.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 100)
    } elseif ($script:current.StartTime) {
        $btnS.Text = "Resume"
        $btnS.ForeColor = [System.Drawing.Color]::White
    } else {
        $btnS.Text = "Start"
        $btnS.ForeColor = [System.Drawing.Color]::White
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
        $btnPin.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 160)
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
            $c.SL.Text = "* running..."
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 70)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
            $c.PB.Text = "||"
        } else {
            $c.SL.Text = "paused"
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
            $c.PB.Text = ">"
        }
    }
})

# ===== Right-click =====
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$mp = New-Object System.Windows.Forms.ToolStripMenuItem("Pause / Resume")
$mp.Add_Click({ if ($script:current.Running) { Do-Pause } else { Do-Start } })
$mc = New-Object System.Windows.Forms.ToolStripMenuItem("Clear")
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
$m1 = New-Object System.Windows.Forms.ToolStripMenuItem("Show")
$m1.Add_Click({ $form.Show(); $form.Activate() })
$m2 = New-Object System.Windows.Forms.ToolStripMenuItem("Pin / Unpin")
$m2.Add_Click({ $btnPin.PerformClick() })
$m3 = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")
$m3.Add_Click({ $btnClose.PerformClick() })
[void]$tc.Items.AddRange(@($m1, $m2, $m3))
$notifyIcon.ContextMenuStrip = $tc

# ===== Position =====
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $W - 10), ($scr.Bottom - 140))

$tk.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
