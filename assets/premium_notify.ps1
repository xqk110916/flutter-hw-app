param(
    [string]$title = "System Notification",
    [string]$message = "The background task has completed successfully!"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$signature = @"
[DllImport("user32.dll")]
public static extern IntPtr GetForegroundWindow();

[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@

$win32 = Add-Type -MemberDefinition $signature -Name "Win32Focus" -Namespace "Win32" -PassThru

$fgHwnd = $win32::GetForegroundWindow()
$consoleHwnd = $win32::GetConsoleWindow()

if ($fgHwnd -eq $consoleHwnd -and $consoleHwnd -ne [IntPtr]::Zero) {
    exit
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 33, 64)
$form.Width = 360
$form.Height = 90
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Left = $screen.Width - $form.Width - 6
$form.Top = $screen.Height - $form.Height - 6

$iconLabel = New-Object System.Windows.Forms.Label
$iconLabel.Width = 36
$iconLabel.Height = 36
$iconLabel.Left = 20
$iconLabel.Top = 27
$iconLabel.Text = "v"
$iconLabel.Font = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Bold)
$iconLabel.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$iconLabel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($iconLabel)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $title
$titleLabel.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Left = 65
$titleLabel.Top = 20
$titleLabel.Width = 240
$titleLabel.Height = 25
$form.Controls.Add($titleLabel)

$descLabel = New-Object System.Windows.Forms.Label
$descLabel.Text = $message
$descLabel.Font = New-Object System.Drawing.Font("Arial", 10)
$descLabel.ForeColor = [System.Drawing.Color]::FromArgb(209, 226, 255)
$descLabel.Left = 65
$descLabel.Top = 45
$descLabel.Width = 240
$descLabel.Height = 30
$form.Controls.Add($descLabel)

$closeLabel = New-Object System.Windows.Forms.Label
$closeLabel.Text = "x"
$closeLabel.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$closeLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 180)
$closeLabel.Left = 332
$closeLabel.Top = 8
$closeLabel.Width = 20
$closeLabel.Height = 20
$closeLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
$closeLabel.BackColor = [System.Drawing.Color]::Transparent

$closeLabel.add_MouseEnter({
    $closeLabel.ForeColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
})
$closeLabel.add_MouseLeave({
    $closeLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 180)
})
$closeLabel.add_Click({
    $form.Close()
})
$form.Controls.Add($closeLabel)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({
    $form.Close()
})
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
