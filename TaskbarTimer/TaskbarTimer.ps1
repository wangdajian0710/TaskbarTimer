Add-Type -AssemblyName System.Windows.Forms
Add-Type System.Drawing

$W = 420
$H = 100

$form = New-Object System.Windows.Forms.Form
$form.ClientSize = New-Object System.Drawing.Size($W, $H)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::White

# Top bar
$top = New-Object System.Windows.Forms.Panel
$top.Location = New-Object System.Drawing.Point(0, 0)
$top.Size = New-Object System.Drawing.Size($W, 30)
$top.BackColor = [System.Drawing.Color]::DodgerBlue

$lblT = New-Object System.Windows.Forms.Label
$lblT.Location = New-Object System.Drawing.Point(10, 0)
$lblT.Size = New-Object System.Drawing.Size(350, 30)
$lblT.Text = "  Taskbar Timer  (drag here)"
$lblT.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblT.ForeColor = [System.Drawing.Color]::White
$lblT.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$btnX = New-Object System.Windows.Forms.Button
$btnX.Location = New-Object System.Drawing.Point($W - 30, 0)
$btnX.Size = New-Object System.Drawing.Size(30, 30)
$btnX.Text = "X"
$btnX.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnX.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnX.BackColor = [System.Drawing.Color]::Red
$btnX.ForeColor = [System.Drawing.Color]::White
$btnX.FlatAppearance.BorderSize = 0

# Timer display
$lblTimer = New-Object System.Windows.Forms.Label
$lblTimer.Location = New-Object System.Drawing.Point(15, 35)
$lblTimer.Size = New-Object System.Drawing.Size(200, 55)
$lblTimer.Font = New-Object System.Drawing.Font("Consolas", 32, [System.Drawing.FontStyle]::Bold)
$lblTimer.ForeColor = [System.Drawing.Color]::Black
$lblTimer.BackColor = [System.Drawing.Color]::WhiteSmoke
$lblTimer.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblTimer.Text = "00:00.0"
$lblTimer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

# Buttons
function MkBtn($text, $x, $bg) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, 38)
    $b.Size = New-Object System.Drawing.Size(55, 45)
    $b.Text = $text
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $bg
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::LightGray
    return $b
}

$btnStart = MkBtn "Start" 230 [System.Drawing.Color]::Green
$btnSplit = MkBtn "Split" 295 [System.Drawing.Color]::Orange
$btnClear = MkBtn "Clear" 360 [System.Drawing.Color]::DarkRed

[void]$form.Controls.AddRange(@($top, $lblT, $btnX, $lblTimer, $btnStart, $btnSplit, $btnClear))

# Drag
$drag = $false; $dOff = $null
$lblT.Add_MouseDown({ param($s,$e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:drag=$true; $script:dOff=$e.Location } })
$lblT.Add_MouseMove({ param($s,$e) if ($script:drag) { $form.Location = [System.Drawing.Point]::new($form.Location.X+$e.X-$script:dOff.X, $form.Location.Y+$e.Y-$script:dOff.Y) } })
$lblT.Add_MouseUp({ $script:drag=$false })

# State
$script:st = @{ Start=$null; Pause=$null; Paused=0; On=$false }
$script:segs = [System.Collections.ArrayList]::new()
$script:segCtrls = @{}
$script:nid = 1
$script:pinned = $false

function Elapsed($s) {
    if (-not $s.Start) { return [TimeSpan]::Zero }
    $end = if ($s.Pause) { $s.Pause } else { Get-Date }
    return [TimeSpan]::FromMilliseconds([Math]::Max(0, ($end - $s.Start).TotalMilliseconds - $s.Paused))
}
function Fmt($ts) {
    if ($ts.TotalHours -ge 1) { return $ts.ToString("hh\:mm\:ss\.f") }
    return $ts.ToString("mm\:ss\.f")
}

# Segment panel
$segP = New-Object System.Windows.Forms.Panel
$segP.Location = New-Object System.Drawing.Point(0, 100)
$segP.Size = New-Object System.Drawing.Size($W, 0)
$segP.BackColor = [System.Drawing.Color]::LightGray
$segP.Visible = $false
$form.Controls.Add($segP)

function MkSegRow($seg) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Size = New-Object System.Drawing.Size($W, 40)
    $row.BackColor = [System.Drawing.Color]::WhiteSmoke

    $nL = New-Object System.Windows.Forms.Label
    $nL.Location = New-Object System.Drawing.Point(5, 0); $nL.Size = New-Object System.Drawing.Size(30, 40)
    $nL.Text = "#$($seg.Id)"; $nL.Font = New-Object System.Drawing.Font("Consolas", 9)
    $nL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $tL = New-Object System.Windows.Forms.Label
    $tL.Location = New-Object System.Drawing.Point(35, 2); $tL.Size = New-Object System.Drawing.Size(100, 36)
    $tL.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
    $tL.ForeColor = [System.Drawing.Color]::Red
    $tL.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $tL.Text = "00:00.0"

    $sL = New-Object System.Windows.Forms.Label
    $sL.Location = New-Object System.Drawing.Point(140, 8); $sL.Size = New-Object System.Drawing.Size(80, 24)
    $sL.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $sL.ForeColor = [System.Drawing.Color]::Gray; $sL.Text = "running..."

    function MkSB($txt, $x, $bg, $act) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size = New-Object System.Drawing.Size(38, 30); $b.Location = New-Object System.Drawing.Point($x, 5)
        $b.Text = $txt; $b.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $b.BackColor = $bg; $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize = 1; $b.Tag = $seg.Id
        $b.Add_Click({ param($sn,$ev)
            switch ($act) {
                "toggle" { Toggle-Seg $sn.Tag }
                "promote" { Promote-Seg $sn.Tag }
                "remove" { Remove-Seg $sn.Tag }
            }
        })
        return $b
    }
    $b1 = MkSB "||" 230 [System.Drawing.Color]::SteelBlue "toggle"
    $b2 = MkSB "^" 275 [System.Drawing.Color]::MediumSeaGreen "promote"
    $b3 = MkSB "X" 320 [System.Drawing.Color]::IndianRed "remove"

    [void]$row.Controls.AddRange(@($nL,$tL,$sL,$b1,$b2,$b3))
    $script:segCtrls[$seg.Id] = @{ Row=$row; TL=$tL; SL=$sL; PB=$b1 }
    return $row
}

function Rebuild-SegUI {
    foreach ($k in @($script:segCtrls.Keys)) {
        $c = $script:segCtrls[$k]
        if ($c.Row.Parent) { $c.Row.Parent.Controls.Remove($c.Row) }
        $c.Row.Dispose()
    }
    $script:segCtrls.Clear()
    if ($script:segs.Count -eq 0) {
        $segP.Visible = $false
        $form.ClientSize = New-Object System.Drawing.Size($W, $H)
    } else {
        $segP.Visible = $true
        foreach ($sg in $script:segs) { [void]$segP.Controls.Add((MkSegRow $sg)) }
        $sh = $script:segs.Count * 40
        $segP.Size = New-Object System.Drawing.Size($W, $sh)
        $th = $H + $sh
        $scr = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        if ($th -gt $scr.Height - 40) { $th = $scr.Height - 40 }
        $form.ClientSize = New-Object System.Drawing.Size($W, $th)
    }
}

function Start-Timer {
    $s = $script:st
    if (-not $s.Start) { $s.Start = Get-Date }
    if ($s.Pause) {
        $s.Paused += (Get-Date - $s.Pause).TotalMilliseconds
        $s.Pause = $null
    }
    $s.On = $true
    $btnStart.Text = "Pause"
    $btnStart.BackColor = [System.Drawing.Color]::Orange
}
function Pause-Timer {
    $s = $script:st
    if ($s.Start -and -not $s.Pause) { $s.Pause = Get-Date }
    $s.On = $false
    $btnStart.Text = "Resume"
    $btnStart.BackColor = [System.Drawing.Color]::Green
}
function Split-Timer {
    $s = $script:st
    if (-not $s.Start) { return }
    $sg = @{ Id=$script:nid++; Start=$s.Start; Pause=$s.Pause; Paused=$s.Paused; On=$s.On }
    [void]$script:segs.Insert(0, $sg)
    if ($script:segs.Count -gt 20) { $script:segs.RemoveAt($script:segs.Count-1) }
    $script:st = @{ Start=$null; Pause=$null; Paused=[long]0; On=$false }
    $lblTimer.Text = "00:00.0"
    $btnStart.Text = "Start"; $btnStart.BackColor = [System.Drawing.Color]::Green
    Rebuild-SegUI
}
function Clear-Timer {
    $script:st = @{ Start=$null; Pause=$null; Paused=[long]0; On=$false }
    $script:segs.Clear()
    $lblTimer.Text = "00:00.0"
    $btnStart.Text = "Start"; $btnStart.BackColor = [System.Drawing.Color]::Green
    Rebuild-SegUI
}
function Toggle-Seg($id) {
    foreach ($sg in $script:segs) {
        if ($sg.Id -eq $id) {
            if ($sg.On) { if (-not $sg.Pause) { $sg.Pause = Get-Date }; $sg.On = $false }
            else { if ($sg.Pause) { $sg.Paused += (Get-Date - $sg.Pause).TotalMilliseconds; $sg.Pause = $null }; if ($sg.Start) { $sg.On = $true } }
            break
        }
    }
}
function Promote-Seg($id) {
    $idx = -1
    for ($i=0; $i -lt $script:segs.Count; $i++) { if ($script:segs[$i].Id -eq $id) { $idx=$i; break } }
    if ($idx -lt 0) { return }
    $sg = $script:segs[$idx]
    $old = @{ Id=$script:nid++; Start=$script:st.Start; Pause=$script:st.Pause; Paused=$script:st.Paused; On=$script:st.On }
    $script:st = @{ Start=$sg.Start; Pause=$sg.Pause; Paused=$sg.Paused; On=$sg.On }
    $script:segs[$idx] = $old
    if ($script:st.On) { $btnStart.Text="Pause"; $btnStart.BackColor=[System.Drawing.Color]::Orange }
    elseif ($script:st.Start) { $btnStart.Text="Resume"; $btnStart.BackColor=[System.Drawing.Color]::Green }
    else { $btnStart.Text="Start"; $btnStart.BackColor=[System.Drawing.Color]::Green }
    Rebuild-SegUI
}
function Remove-Seg($id) {
    for ($i=0; $i -lt $script:segs.Count; $i++) { if ($script:segs[$i].Id -eq $id) { $script:segs.RemoveAt($i); break } }
    Rebuild-SegUI
}

$btnStart.Add_Click({ if ($script:st.On) { Pause-Timer } else { Start-Timer } })
$btnSplit.Add_Click({ Split-Timer })
$btnClear.Add_Click({ Clear-Timer })
$lblTimer.Add_Click({ if ($script:st.On) { Pause-Timer } else { Start-Timer } })

$btnX.Add_Click({ $tmr.Stop(); $tmr.Dispose(); $ni.Dispose(); $form.Close(); [System.Windows.Forms.Application]::Exit() })

# Tick
$tmr = New-Object System.Windows.Forms.Timer; $tmr.Interval = 100
$tmr.Add_Tick({
    if ($script:st.Start) { $lblTimer.Text = Fmt (Elapsed $script:st) }
    foreach ($sg in $script:segs) {
        if (-not $script:segCtrls.ContainsKey($sg.Id)) { continue }
        $c = $script:segCtrls[$sg.Id]
        $c.TL.Text = Fmt (Elapsed $sg)
        if ($sg.On) {
            $c.SL.Text = "running..."; $c.SL.ForeColor = [System.Drawing.Color]::Red
            $c.TL.ForeColor = [System.Drawing.Color]::Red; $c.PB.Text = "||"
        } else {
            $c.SL.Text = "paused"; $c.SL.ForeColor = [System.Drawing.Color]::Gray
            $c.TL.ForeColor = [System.Drawing.Color]::Gray; $c.PB.Text = ">"
        }
    }
})

# Tray icon
$bmp = New-Object System.Drawing.Bitmap(16,16)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.FillEllipse([System.Drawing.SolidBrush]::new([System.Drawing.Color]::Green), 1,1,14,14)
$g.Dispose()
$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$ni.Visible = $true; $ni.Text = "Taskbar Timer"
$tc = New-Object System.Windows.Forms.ContextMenuStrip
$tc.Items.Add("Show").Add_Click({ $form.Show(); $form.Activate() })
$tc.Items.Add("Exit").Add_Click({ $btnX.PerformClick() })
$ni.ContextMenuStrip = $tc

# Position
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($scr.Right - $W - 20), ($scr.Bottom - 150))

$tmr.Start()
$form.Show()
[System.Windows.Forms.Application]::Run()
