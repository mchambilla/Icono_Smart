#Requires -Version 5.0
param(
    [switch]$MonitorOnly
)

# SmartSouth Tray Icon - Info del equipo
# Creado por: Martin Chambilla

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─── CONFIGURACION ───────────────────────────────────────────────────────────
$SoporteMail  = "ayuda@smartsouth.net"
$SoportePhone = "+54 9 11 6794-7386"
$AppTitle     = "Smart South - Soporte IT"
$ColorHeader  = [System.Drawing.Color]::FromArgb(24, 81, 163)
$IconPath     = Join-Path $PSScriptRoot "Logo.ico"
$PngPath      = Join-Path $PSScriptRoot "Logo.png"
$GlpiService  = "glpi-agent"
$GracePeriodDays = 15
$MonitorTaskPrefix = "SmartSouthTray GLPI Agent Monitor"
$StartupTaskPrefix = "SmartSouthTray Startup"
# ─────────────────────────────────────────────────────────────────────────────

function Get-ManagedAppRoot {
    $localAppRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $env:LOCALAPPDATA "SmartSouthTray")
    )
    $versionsRoot = Join-Path $localAppRoot "versions"
    $scriptDirectory = [System.IO.Path]::GetFullPath($PSScriptRoot)

    if (-not [string]::Equals(
        (Split-Path -Parent $scriptDirectory),
        $versionsRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return $null
    }

    return $localAppRoot
}

function Get-MonitorTaskName {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return "$MonitorTaskPrefix - $($identity.User.Value)"
}

function Get-StartupTaskName {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return "$StartupTaskPrefix - $($identity.User.Value)"
}

function Write-MonitorLog {
    param([string]$Message)

    $logPath = Join-Path $script:ManagedAppRoot "monitor.log"
    $line = "{0} {1}" -f [DateTime]::UtcNow.ToString("o"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
}

function Register-MonitorTask {
    if (-not $script:ManagedAppRoot) {
        throw "La política de desinstalación requiere instalar SmartSouthTray con el bootstrapper en %LOCALAPPDATA%\SmartSouthTray."
    }

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskName = Get-MonitorTaskName
    $powershellPath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    $scriptPath = Join-Path $PSScriptRoot "SmartSouthTray.ps1"
    $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -MonitorOnly"

    $action = New-ScheduledTaskAction -Execute $powershellPath -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 5)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Controla el servicio GLPI-Agent y la vigencia de SmartSouthTray." `
        -Force `
        -ErrorAction Stop | Out-Null

    $startupAction = New-ScheduledTaskAction `
        -Execute $powershellPath `
        -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $startupSettings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName (Get-StartupTaskName) `
        -Action $startupAction `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $startupSettings `
        -Description "Inicia SmartSouthTray al iniciar sesión." `
        -Force `
        -ErrorAction Stop | Out-Null

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    if ($task.State -ne "Running") {
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    }
}

function Invoke-MonitorCheck {
    $statePath = Join-Path $script:ManagedAppRoot "glpi-agent-stopped-since.txt"
    $service = Get-CimInstance `
        -ClassName Win32_Service `
        -Filter "Name='$GlpiService'" `
        -ErrorAction Stop

    if ($service -and $service.State -eq "Running") {
        if (Test-Path -LiteralPath $statePath) {
            Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop
            Write-MonitorLog "GLPI-Agent está en ejecución; se reinició el período de gracia."
        }
        return $false
    }

    if (-not (Test-Path -LiteralPath $statePath)) {
        [DateTime]::UtcNow.ToString("o") |
            Set-Content -LiteralPath $statePath -Encoding ASCII -ErrorAction Stop
        Write-MonitorLog "GLPI-Agent está detenido o no instalado; comenzó el período de gracia de $GracePeriodDays días."
        return $false
    }

    $stoppedSinceText = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop
    try {
        $stoppedSince = [DateTime]::Parse(
            $stoppedSinceText.Trim(),
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
    } catch {
        [DateTime]::UtcNow.ToString("o") |
            Set-Content -LiteralPath $statePath -Encoding ASCII -ErrorAction Stop
        Write-MonitorLog "El registro del período de gracia no era válido; se inició uno nuevo de $GracePeriodDays días."
        return $false
    }
    $elapsed = [DateTime]::UtcNow - $stoppedSince

    if ($elapsed.TotalDays -ge $GracePeriodDays) {
        Write-MonitorLog "GLPI-Agent lleva detenido al menos $GracePeriodDays días; se inicia la desinstalación."
        return $true
    }

    return $false
}

function Uninstall-SmartSouthTray {
    $versionsRoot = Join-Path $script:ManagedAppRoot "versions"
    $scriptPattern = '(?i)-File\s+"?' +
        [regex]::Escape($versionsRoot) +
        '\\[^"]+\\SmartSouthTray\.ps1'

    $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.Name -in @("powershell.exe", "pwsh.exe") -and
            $_.CommandLine -and
            $_.CommandLine -match $scriptPattern
        }

    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    }

    foreach ($taskName in @((Get-MonitorTaskName), (Get-StartupTaskName))) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        }
    }
    Remove-Item -LiteralPath $script:ManagedAppRoot -Recurse -Force -ErrorAction Stop
}

function Start-MonitorLoop {
    while ($true) {
        try {
            if (Invoke-MonitorCheck) {
                Uninstall-SmartSouthTray
                return
            }
        } catch {
            Write-MonitorLog "Error al comprobar el servicio o aplicar la política: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 3600
    }
}

$script:ManagedAppRoot = Get-ManagedAppRoot
if ($MonitorOnly) {
    if (-not $script:ManagedAppRoot) {
        exit 1
    }
    Start-MonitorLoop
    exit 0
}

# ─── OBTENER INFO DEL EQUIPO ─────────────────────────────────────────────────
function Get-EquipoInfo {
    $info = @{}

    $info.HostName = $env:COMPUTERNAME
    $info.Usuario  = $env:USERNAME

    # Días sin reiniciar (Uptime)
    try {
        $lastBoot = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        $uptime = (Get-Date) - $lastBoot
        $info.DiasSinReiniciar = [int][math]::Floor($uptime.TotalDays)
    } catch {
        $info.DiasSinReiniciar = "N/A"
    }

    # IP Local
    $info.IP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1).IPAddress
    if (-not $info.IP) { $info.IP = "No disponible" }

    # IP Pública
    try {
        $webRequest = [System.Net.WebRequest]::Create("https://ifconfig.me/ip")
        $webRequest.Timeout = 2000
        $response = $webRequest.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $info.IPPublica = $reader.ReadToEnd().Trim()
        $reader.Close()
        $response.Close()
    } catch {
        $info.IPPublica = "No disponible"
    }

    # TeamViewer ID
    $tvId = $null
    $tvPaths = @("HKLM:\SOFTWARE\TeamViewer", "HKLM:\SOFTWARE\WOW6432Node\TeamViewer")
    foreach ($path in $tvPaths) {
        if (Test-Path $path) {
            $tvId = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).ClientID
            if ($tvId) { break }
        }
    }
    if ($tvId) {
        $s = $tvId.ToString()
        $info.TeamViewerID = $s -replace '(\d)(?=(\d{3})+$)', '$1 '
    } else {
        $info.TeamViewerID = "No instalado"
    }

    return $info
}

try {
    Register-MonitorTask
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "No se pudieron configurar correctamente las tareas de inicio y control de GLPI-Agent. SmartSouthTray continuará abierto, pero podría no iniciarse automáticamente ni aplicar la desinstalación automática.`r`n`r`n$($_.Exception.Message)",
        "Smart South - Configuración",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

# ─── CARGAR O GENERAR ICONO ─────────────────────────────────────────────────
function Get-SmartIcon {
    if (Test-Path $IconPath) {
        return New-Object System.Drawing.Icon($IconPath)
    } elseif (Test-Path $PngPath) {
        $source = [System.Drawing.Bitmap]::FromFile($PngPath)
        try {
            for ($y = 0; $y -lt $source.Height; $y++) {
                for ($x = 0; $x -lt $source.Width; $x++) {
                    $pixel = $source.GetPixel($x, $y)
                    $isDarkBackground = ($pixel.R -lt 80 -and $pixel.G -lt 60 -and $pixel.B -lt 100)
                    $isWhiteBackground = ($pixel.R -gt 220 -and $pixel.G -gt 220 -and $pixel.B -gt 220)
                    if ($isDarkBackground -or $isWhiteBackground) {
                        $source.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                    }
                }
            }

            $bmp = New-Object System.Drawing.Bitmap 32, 32
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.DrawImage($source, 0, 0, 32, 32)
            } finally {
                $graphics.Dispose()
            }
        } finally {
            $source.Dispose()
        }

        $hIcon = $bmp.GetHicon()
        $bmp.Dispose()
        return [System.Drawing.Icon]::FromHandle($hIcon)
    } else {
        $bmp = New-Object System.Drawing.Bitmap 32, 32
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 145, 0))
        $g.FillEllipse($brush, 1, 1, 30, 30)
        $g.Dispose()
        $hIcon = $bmp.GetHicon()
        $bmp.Dispose()
        return [System.Drawing.Icon]::FromHandle($hIcon)
    }
}

# ─── POPUP DE INFORMACION ─────────────────────────────────────────────────────
function Show-InfoPopup {
    param($info)

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = $AppTitle
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true
    $form.BackColor       = [System.Drawing.Color]::FromArgb(244, 246, 250)
    $form.ClientSize      = New-Object System.Drawing.Size(380, 470)
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $header = New-Object System.Windows.Forms.Panel
    $header.Size     = New-Object System.Drawing.Size(380, 60)
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.BackColor = $ColorHeader

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "Smart South"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location  = New-Object System.Drawing.Point(20, 8)
    $lblTitle.AutoSize  = $true
    $header.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text      = "Resumen del dispositivo"
    $lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 232, 248)
    $lblSubtitle.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $lblSubtitle.Location  = New-Object System.Drawing.Point(21, 34)
    $lblSubtitle.AutoSize  = $true
    $header.Controls.Add($lblSubtitle)
    $form.Controls.Add($header)

    $accentColor = [System.Drawing.Color]::FromArgb(24, 81, 163)
    $textColor = [System.Drawing.Color]::FromArgb(35, 45, 60)
    $mutedColor = [System.Drawing.Color]::FromArgb(115, 125, 140)
    $cardColor = [System.Drawing.Color]::White
    $currentY = 76

    $diasText = if ($info.DiasSinReiniciar -eq 0) {
        "Hoy (menos de 24 hs)"
    } elseif ($info.DiasSinReiniciar -eq 1) {
        "1 día"
    } elseif ($info.DiasSinReiniciar -eq "N/A") {
        "No disponible"
    } else {
        "$($info.DiasSinReiniciar) días"
    }

    $requiereReiniciar = ($info.DiasSinReiniciar -is [int] -and $info.DiasSinReiniciar -ge 7)
    $uptimeColor = if ($requiereReiniciar) {
        [System.Drawing.Color]::FromArgb(190, 55, 55)
    } else {
        $accentColor
    }

    $uptimeCard = New-Object System.Windows.Forms.Panel
    $uptimeCard.Location  = New-Object System.Drawing.Point(18, $currentY)
    $uptimeCard.Size      = New-Object System.Drawing.Size(344, 70)
    $uptimeCard.BackColor = $cardColor

    $uptimeAccent = New-Object System.Windows.Forms.Panel
    $uptimeAccent.Location  = New-Object System.Drawing.Point(0, 0)
    $uptimeAccent.Size      = New-Object System.Drawing.Size(4, 70)
    $uptimeAccent.BackColor = $uptimeColor
    $uptimeCard.Controls.Add($uptimeAccent)

    $lblUptimeTitle = New-Object System.Windows.Forms.Label
    $lblUptimeTitle.Text      = "TIEMPO SIN REINICIAR"
    $lblUptimeTitle.Location  = New-Object System.Drawing.Point(17, 10)
    $lblUptimeTitle.AutoSize  = $true
    $lblUptimeTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lblUptimeTitle.ForeColor = $mutedColor
    $uptimeCard.Controls.Add($lblUptimeTitle)

    $lblUptimeValue = New-Object System.Windows.Forms.Label
    $lblUptimeValue.Text      = $diasText
    $lblUptimeValue.Location  = New-Object System.Drawing.Point(17, 30)
    $lblUptimeValue.AutoSize  = $true
    $lblUptimeValue.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblUptimeValue.ForeColor = $uptimeColor
    $uptimeCard.Controls.Add($lblUptimeValue)

    $lblUptimeHint = New-Object System.Windows.Forms.Label
    $lblUptimeHint.Text      = if ($requiereReiniciar) { "Se recomienda reiniciar el equipo" } else { "Estado de actividad del equipo" }
    $lblUptimeHint.Location  = New-Object System.Drawing.Point(175, 34)
    $lblUptimeHint.Size      = New-Object System.Drawing.Size(158, 30)
    $lblUptimeHint.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblUptimeHint.ForeColor = $mutedColor
    $lblUptimeHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $uptimeCard.Controls.Add($lblUptimeHint)
    $form.Controls.Add($uptimeCard)

    $currentY += 84
    $lblDeviceSection = New-Object System.Windows.Forms.Label
    $lblDeviceSection.Text      = "DISPOSITIVO"
    $lblDeviceSection.Location  = New-Object System.Drawing.Point(19, $currentY)
    $lblDeviceSection.AutoSize  = $true
    $lblDeviceSection.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lblDeviceSection.ForeColor = $mutedColor
    $form.Controls.Add($lblDeviceSection)
    $currentY += 20

    $deviceItems = @(
        @{ Label = "NOMBRE DEL EQUIPO"; Value = $info.HostName }
        @{ Label = "USUARIO"; Value = $info.Usuario }
        @{ Label = "IP LOCAL"; Value = $info.IP }
        @{ Label = "IP PÚBLICA"; Value = $info.IPPublica }
    )
    if ($info.TeamViewerID -ne "No instalado") {
        $deviceItems += @{ Label = "TEAMVIEWER ID"; Value = $info.TeamViewerID }
    }

    $tileWidth = 167
    $tileHeight = 62
    $tileGap = 10
    for ($i = 0; $i -lt $deviceItems.Count; $i++) {
        $column = $i % 2
        $row = [math]::Floor($i / 2)
        $tile = New-Object System.Windows.Forms.Panel
        $tile.Location  = New-Object System.Drawing.Point((18 + ($column * ($tileWidth + $tileGap))), ($currentY + ($row * ($tileHeight + $tileGap))))
        $tile.Size      = New-Object System.Drawing.Size($tileWidth, $tileHeight)
        $tile.BackColor = $cardColor

        $tileLabel = New-Object System.Windows.Forms.Label
        $tileLabel.Text      = $deviceItems[$i].Label
        $tileLabel.Location  = New-Object System.Drawing.Point(11, 8)
        $tileLabel.AutoSize  = $true
        $tileLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
        $tileLabel.ForeColor = $mutedColor
        $tile.Controls.Add($tileLabel)

        $tileValue = New-Object System.Windows.Forms.Label
        $tileValue.Text      = [string]$deviceItems[$i].Value
        $tileValue.Location  = New-Object System.Drawing.Point(11, 28)
        $tileValue.Size      = New-Object System.Drawing.Size(($tileWidth - 20), 25)
        $tileValue.AutoEllipsis = $true
        $tileValue.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
        $tileValue.ForeColor = $textColor
        $tile.Controls.Add($tileValue)
        $form.Controls.Add($tile)
    }

    $deviceRows = [math]::Ceiling($deviceItems.Count / 2.0)
    $currentY += ($deviceRows * ($tileHeight + $tileGap)) - $tileGap + 14

    $lblSupportSection = New-Object System.Windows.Forms.Label
    $lblSupportSection.Text      = "CONTACTO DE SOPORTE"
    $lblSupportSection.Location  = New-Object System.Drawing.Point(19, $currentY)
    $lblSupportSection.AutoSize  = $true
    $lblSupportSection.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lblSupportSection.ForeColor = $mutedColor
    $form.Controls.Add($lblSupportSection)
    $currentY += 19

    $supportCard = New-Object System.Windows.Forms.Panel
    $supportCard.Location  = New-Object System.Drawing.Point(18, $currentY)
    $supportCard.Size      = New-Object System.Drawing.Size(344, 58)
    $supportCard.BackColor = $cardColor

    $btnWhatsApp = New-Object System.Windows.Forms.Button
    $btnWhatsApp.Text      = "WhatsApp  ·  $SoportePhone"
    $btnWhatsApp.Location  = New-Object System.Drawing.Point(8, 7)
    $btnWhatsApp.Size      = New-Object System.Drawing.Size(328, 22)
    $btnWhatsApp.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnWhatsApp.FlatAppearance.BorderSize = 0
    $btnWhatsApp.BackColor = $cardColor
    $btnWhatsApp.ForeColor = $accentColor
    $btnWhatsApp.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnWhatsApp.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $btnWhatsApp.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnWhatsApp.Add_Click({
        $cleanNum = $SoportePhone -replace '[^\d]', ''
        Start-Process "https://wa.me/$cleanNum"
    })
    $supportCard.Controls.Add($btnWhatsApp)

    $btnEmail = New-Object System.Windows.Forms.Button
    $btnEmail.Text      = "Correo  ·  $SoporteMail"
    $btnEmail.Location  = New-Object System.Drawing.Point(8, 30)
    $btnEmail.Size      = New-Object System.Drawing.Size(328, 22)
    $btnEmail.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnEmail.FlatAppearance.BorderSize = 0
    $btnEmail.BackColor = $cardColor
    $btnEmail.ForeColor = $accentColor
    $btnEmail.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnEmail.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $btnEmail.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnEmail.Add_Click({
        Start-Process ("mailto:" + $SoporteMail + "?subject=Soporte IT - " + $env:COMPUTERNAME)
    })
    $supportCard.Controls.Add($btnEmail)
    $form.Controls.Add($supportCard)
    $currentY += 70

    $lblAuthor = New-Object System.Windows.Forms.Label
    $lblAuthor.Text      = "Desarrollado por Martin Chambilla"
    $lblAuthor.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblAuthor.ForeColor = $mutedColor
    $lblAuthor.Location  = New-Object System.Drawing.Point(19, $currentY)
    $lblAuthor.AutoSize  = $true
    $form.Controls.Add($lblAuthor)

    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text      = "Cerrar"
    $btnCerrar.Size      = New-Object System.Drawing.Size(72, 28)
    $btnCerrar.Location  = New-Object System.Drawing.Point(290, ($currentY - 6))
    $btnCerrar.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCerrar.BackColor = $ColorHeader
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.Add_Click({ $form.Close() })
    $form.Controls.Add($btnCerrar)

    $form.ClientSize = New-Object System.Drawing.Size(380, ($currentY + 32))
    $form.Location = New-Object System.Drawing.Point(
        [math]::Max($screen.Left + 10, ($screen.Right - $form.Width - 10)),
        [math]::Max($screen.Top + 10, ($screen.Bottom - $form.Height - 10))
    )

    $form.Add_Deactivate({ $form.Close() })
    $form.ShowDialog() | Out-Null
}

# ─── SISTEMA TRAY ────────────────────────────────────────────────────────────
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon    = Get-SmartIcon
$notifyIcon.Text    = "Smart South - Soporte IT"
$notifyIcon.Visible = $true

# Menú contextual (clic derecho)
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$itemInfo = New-Object System.Windows.Forms.ToolStripMenuItem
$itemInfo.Text = "Ver info del equipo"
$itemInfo.Add_Click({ Show-InfoPopup (Get-EquipoInfo) })

$itemWapp = New-Object System.Windows.Forms.ToolStripMenuItem
$itemWapp.Text = "Contactar por WhatsApp"
$itemWapp.Add_Click({
    $cleanNum = $SoportePhone -replace '[^\d]', ''
    Start-Process "https://wa.me/$cleanNum"
})

$itemMail = New-Object System.Windows.Forms.ToolStripMenuItem
$itemMail.Text = "Enviar mail de soporte"
$itemMail.Add_Click({
    Start-Process ("mailto:" + $SoporteMail + "?subject=Soporte IT - " + $env:COMPUTERNAME)
})

$itemSalir = New-Object System.Windows.Forms.ToolStripMenuItem
$itemSalir.Text = "Salir"
$itemSalir.Add_Click({
    $notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$contextMenu.Items.Add($itemInfo)  | Out-Null
$contextMenu.Items.Add($itemWapp)  | Out-Null
$contextMenu.Items.Add($itemMail)  | Out-Null
$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$contextMenu.Items.Add($itemSalir) | Out-Null

$notifyIcon.ContextMenuStrip = $contextMenu

# Clic izquierdo
$notifyIcon.Add_MouseClick({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-InfoPopup (Get-EquipoInfo)
    }
})

# ─── LOOP PRINCIPAL ──────────────────────────────────────────────────────────
[System.Windows.Forms.Application]::Run()
$notifyIcon.Visible = $false