# Taskbar Timer - 分段接力计时版 v2
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:W = 360

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
    $base = ($s.PausedAt, (Get-Date) | Where-Object { $_ -ne $null })[0] - $s.StartTime
    return [TimeSpan]::FromMilliseconds([Math]::Max(0, $base.TotalMilliseconds - $s.TotalPausedMs))
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
$form.AutoScroll = $false

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
$lblTitle.Text = "  Taskbar Timer"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 170)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Dock = [System.Windows.Forms.DockStyle]::Right; $btnPin.Width = 26
$btnPin.Text = [char]0x1F4CC; $btnPin.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 8)
$btnPin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPin.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 160)
$btnPin.BackColor = [System.Drawing.Color]::Transparent
$btnPin.FlatAppearance.BorderSize = 0

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Dock = [System.Windows.Forms.DockStyle]::Right; $btnClose.Width = 26
$btnClose.Text = "X"; $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 180)
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.FlatAppearance.BorderSize = 0

[void]$titleBar.Controls.AddRange(@($lblTitle, $btnPin, $btnClose))

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
$tBar.Dock = [System.Windows.Forms.DockStyle]::Top; $tBar.Height = 54
$tBar.BackColor = [System.Drawing.Color]::FromArgb(220, 22, 26, 40)

$dragH = New-Object System.Windows.Forms.Panel
$dragH.Size = New-Object System.Drawing.Size(5, 18)
$dragH.BackColor = [System.Drawing.Color]::FromArgb(70, 75, 90)
$dragH.Location = New-Object System.Drawing.Point(6, 18)

$curBox = New-Object System.Windows.Forms.Panel
$curBox.Location = New-Object System.Drawing.Point(18, 8)
$curBox.Size = New-Object System.Drawing.Size(138, 38)
$curBox.BackColor = [System.Drawing.Color]::FromArgb(35, 28, 44, 58)
$curBox.Padding = [System.Windows.Forms.Padding]::new(6, 2, 6, 2)

$lblCL = New-Object System.Windows.Forms.Label
$lblCL.Dock = [System.Windows.Forms.DockStyle]::Left; $lblCL.Width = 28
$lblCL.Text = "Current"; $lblCL.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblCL.ForeColor = [System.Drawing.Color]::FromArgb(100, 110, 180)
$lblCL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$lblCur = New-Object System.Windows.Forms.Label
$lblCur.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblCur.Font = New-Object System.Drawing.Font("Consolas", 22, [System.Drawing.FontStyle]::Bold)
$lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 160, 255)
$lblCur.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCur.Text = "00:00.0"

[void]$curBox.Controls.AddRange(@($lblCL, $lblCur))

$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Location = New-Object System.Drawing.Point(162, 20)
$lblClock.Font = New-Object System.Drawing.Font("Consolas", 10)
$lblClock.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 110)
$lblClock.Text = "HH:MM"

function MkBtn($t, $x, $c) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, 10)
    $b.Size = New-Object System.Drawing.Size(44, 34)
    $b.Text = $t; $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $b.ForeColor = $c
    $b.BackColor = [System.Drawing.Color]::FromArgb(30, 35, 55)
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(45, 50, 75)
    return $b
}

$btnS = MkBtn "Start" 214 ([System.Drawing.Color]::FromArgb(200, 130, 255, 130))
$btnL = MkBtn "Split" 262 ([System.Drawing.Color]::FromArgb(200, 130, 130, 255))
$btnC = MkBtn "Clear" 310 ([System.Drawing.Color]::FromArgb(200, 255, 130, 130))

[void]$tBar.Controls.AddRange(@($dragH, $curBox, $lblClock, $btnS, $btnL, $btnC))

# ===== Segment Panel =====
$segPanel = New-Object System.Windows.Forms.Panel
$segPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$segPanel.BackColor = [System.Drawing.Color]::FromArgb(14, 15, 30)
$segPanel.AutoScroll = $true
$segPanel.Visible = $false

[void]$form.Controls.AddRange(@($segPanel, $tBar, $titleBar))

# ===== Segment Row Builder =====
function New-Row($seg) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Height = 42; $row.Dock = [System.Windows.Forms.DockStyle]::Top
    $row.BackColor = [System.Drawing.Color]::FromArgb(20, 22, 36)
    $row.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 1)

    $nL = New-Object System.Windows.Forms.Label
    $nL.Location = New-Object System.Drawing.Point(6, 0); $nL.Size = New-Object System.Drawing.Size(22, 42)
    $nL.Text = "#$($seg.Id)"; $nL.Font = New-Object System.Drawing.Font("Consolas", 8)
    $nL.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 90)
    $nL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $tL = New-Object System.Windows.Forms.Label
    $tL.Location = New-Object System.Drawing.Point(30, 2); $tL.Size = New-Object System.Drawing.Size(100, 22)
    $tL.Font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
    $tL.ForeColor = [System.Drawing.Color]::FromArgb(255, 68, 68)
    $tL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $tL.Text = "00:00.0"

    $sL = New-Object System.Windows.Forms.Label
    $sL.Location = New-Object System.Drawing.Point(30, 24); $sL.Size = New-Object System.Drawing.Size(100, 16)
    $sL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8)
    $sL.ForeColor = [System.Drawing.Color]::FromArgb(140, 55, 55)
    $sL.Text = [char]0x25CF + " running..."

    function MkSm($t, $x, $c, $act) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size = New-Object System.Drawing.Size(26, 26)
        $b.Location = New-Object System.Drawing.Point($x, 8)
        $b.Text = $t; $b.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 9)
        $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $b.ForeColor = $c
        $b.BackColor = [System.Drawing.Color]::FromArgb(28, 30, 44)
        $b.FlatAppearance.BorderSize = 0; $b.Tag = $seg.Id
        $b.Add_Click({ param($sender, $e)
            $id = $sender.Tag
            switch ($act) {
                "toggle" { Do-Toggle $id }
                "promote" { Do-Promote $id }
                "remove" { Do-Remove $id }
            }
        })
        return $b
    }

    $bPause = MkSm ([char]0x23F8) 260 ([System.Drawing.Color]::FromArgb(160, 160, 200)) "toggle"
    $bUp = MkSm ([char]0x2B06) 290 ([System.Drawing.Color]::FromArgb(160, 160, 200)) "promote"
    $bDel = MkSm [char]0x2715 320 ([System.Drawing.Color]::FromArgb(170, 90, 90)) "remove"

    [void]$row.Controls.AddRange(@($nL, $tL, $sL, $bPause, $bUp, $bDel))
    $script:segCtrls[$seg.Id] = @{ Row=$row; TL=$tL; SL=$sL; PB=$bPause }
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
        $form.ClientSize = New-Object System.Drawing.Size($script:W, 80)
    } else {
        $segPanel.Visible = $true
        foreach ($seg in $script:segments) {
            [void]$segPanel.Controls.Add((New-Row $seg))
        }
        $h = 80 + ($script:segments.Count * 42) + 4
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
    $btnS.Text = "Pause"
    $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
}

function Do-Pause {
    if ($script:current.StartTime -and -not $script:current.PausedAt) {
        $script:current.PausedAt = Get-Date
    }
    $script:current.Running = $false
    $btnS.Text = "Resume"
    $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
}

function Do-Split {
    if (-not $script:current.StartTime) { return }
    $wasRunning = $script:current.Running
    if ($wasRunning -and -not $script:current.PausedAt) {
        # Pause current briefly to capture state
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
        $btnS.Text = "Pause"
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
        # Auto-resume the segment too
        if ($seg.PausedAt) {
            $seg.TotalPausedMs += ((Get-Date) - $seg.PausedAt).TotalMilliseconds
            $seg.PausedAt = $null
        }
    } else {
        $btnS.Text = "Start"
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(180, 160, 255)
    }
    Rebuild-UI
}

function Do-Clear {
    $script:current = @{ StartTime=$null; PausedAt=$null; TotalPausedMs=[long]0; Running=$false }
    $script:segments.Clear()
    $btnS.Text = "Start"
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
        StartTime = $seg.StartTime
        PausedAt = $seg.PausedAt
        TotalPausedMs = $seg.TotalPausedMs
        Running = $seg.Running
    }
    $script:segments[$idx] = $old

    if ($script:current.Running) {
        $btnS.Text = "Pause"
        $lblCur.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 200, 100)
    } else {
        if ($script:current.StartTime) {
            $btnS.Text = "Resume"
        } else {
            $btnS.Text = "Start"
        }
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

# ===== Events =====
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
            $c.SL.Text = [char]0x25CF + " running..."
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(140, 55, 55)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(255, 68, 68)
            $c.PB.Text = [char]0x23F8
        } else {
            $c.SL.Text = "paused"
            $c.SL.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $c.TL.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
            $c.PB.Text = [char]0x25B6
        }
    }
})

# ===== Right-click =====
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$mp = New-Object System.Windows.Forms.ToolStripMenuItem("Pause/Resume"); $mp.Add_Click({ if ($script:current.Running) { Do-Pause } else { Do-Start } })
$mc = New-Object System.Windows.Forms.ToolStripMenuItem("Clear"); $mc.Add_Click({ Do-Clear })
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
$notifyIcon.Visible = $true; $notifyIcon.Icon = $ico; $notifyIcon.Text = "Taskbar Timer"

$tc = New-Object System.Windows.Forms.ContextMenuStrip
$m1 = New-Object System.Windows.Forms.ToolStripMenuItem("Show"); $m1.Add_Click({ $form.Show(); $form.Activate() })
$m2 = New-Object System.Windows.Forms.ToolStripMenuItem("Pin"); $m2.Add_Click({ $btnPin.PerformClick() })
$m3 = New-Object System.Windows.Forms.ToolStripMenuItem("Exit"); $m3.Add_Click({ $btnClose.PerformClick() })
[void]$tc.Items.AddRange(@($m1, $m2, $m3))
$notifyIcon.ContextMenuStrip = $tc

# ===== Position =====
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $script:W - 10), ($scr.Bottom - 120))

$tk.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
