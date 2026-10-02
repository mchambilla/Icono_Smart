#Requires -Version 5.0
# SmartSouth Tray Icon - Info del equipo
# Creado por: Martin Chambilla

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─── CONFIGURACION ───────────────────────────────────────────────────────────
$SoporteMail  = "ayuda@smartsouth.net"
$SoportePhone = "+54 9 11 6794-7386"
$AppTitle     = "Smart South - Soporte IT"
$ColorHeader  = [System.Drawing.Color]::FromArgb(24, 81, 163)
$IconPath     = Join-Path $PSScriptRoot "logo.ico"
$PngPath      = Join-Path $PSScriptRoot "Logo.png"
# ─────────────────────────────────────────────────────────────────────────────

# ─── OBTENER INFO DEL EQUIPO ─────────────────────────────────────────────────
function Get-EquipoInfo {
    $info = @{}

    $info.HostName = $env:COMPUTERNAME
    $info.Usuario  = $env:USERNAME

    # IP Local
    $info.IP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1).IPAddress
    if (-not $info.IP) { $info.IP = "No disponible" }

    # IP Pública (Timeout 2s)
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

# ─── CARGAR O GENERAR ICONO ─────────────────────────────────────────────────
function Get-SmartIcon {
    if (Test-Path $IconPath) {
        return New-Object System.Drawing.Icon($IconPath)
    } elseif (Test-Path $PngPath) {
        $bmp = [System.Drawing.Bitmap]::FromFile($PngPath)
        $hIcon = $bmp.GetHicon()
        return [System.Drawing.Icon]::FromHandle($hIcon)
    } else {
        # Respaldo si no encuentra el archivo de imagen
        $bmp = New-Object System.Drawing.Bitmap 16, 16
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $brush = New-Object System.Drawing.SolidBrush ($ColorHeader)
        $g.FillEllipse($brush, 0, 0, 15, 15)
        $g.Dispose()
        return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    }
}

# ─── POPUP DE INFORMACION ─────────────────────────────────────────────────────
function Show-InfoPopup {
    param($info)

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = $AppTitle
    $form.Size            = New-Object System.Drawing.Size(320, 440)
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true
    $form.BackColor       = [System.Drawing.Color]::White
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(
        ($screen.Right  - $form.Width  - 10),
        ($screen.Bottom - $form.Height - 10)
    )

    # Header
    $header = New-Object System.Windows.Forms.Panel
    $header.Size     = New-Object System.Drawing.Size(320, 40)
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.BackColor = $ColorHeader

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "  Smart South - Info del equipo"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblTitle.AutoSize  = $false
    $lblTitle.Size      = New-Object System.Drawing.Size(320, 40)
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $header.Controls.Add($lblTitle)
    $form.Controls.Add($header)

    $script:currentY = 55

    function Add-Row {
        param($label, $value, $isLink = $false, $isPhone = $false)

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text      = $label
        $lbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
        $lbl.Location  = New-Object System.Drawing.Point(20, $script:currentY)
        $lbl.AutoSize  = $true
        $form.Controls.Add($lbl)

        if ($isLink) {
            $ctrl = New-Object System.Windows.Forms.LinkLabel
            $ctrl.Text      = $value
            $ctrl.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
            $ctrl.LinkColor = [System.Drawing.Color]::FromArgb(24, 81, 163)
            $ctrl.Location  = New-Object System.Drawing.Point(20, ($script:currentY + 15))
            $ctrl.AutoSize  = $true
            
            if ($isPhone) {
                $ctrl.Add_LinkClicked({
                    $cleanNum = $SoportePhone -replace '[^\d]', ''
                    Start-Process "https://wa.me/$cleanNum"
                })
            } else {
                $ctrl.Add_LinkClicked({
                    Start-Process ("mailto:" + $SoporteMail + "?subject=Soporte IT - " + $env:COMPUTERNAME)
                })
            }
        } else {
            $ctrl = New-Object System.Windows.Forms.Label
            $ctrl.Text      = $value
            $ctrl.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
            $ctrl.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
            $ctrl.Location  = New-Object System.Drawing.Point(20, ($script:currentY + 15))
            $ctrl.AutoSize  = $true
        }
        $form.Controls.Add($ctrl)

        $script:currentY += 43
    }

    Add-Row "Hostname"       $info.HostName
    Add-Row "Usuario"        $info.Usuario
    Add-Row "IP Local"       $info.IP
    Add-Row "IP Pública"     $info.IPPublica

    if ($info.TeamViewerID -ne "No instalado") {
        Add-Row "ID TeamViewer" $info.TeamViewerID
    }

    Add-Row "Teléfono / WhatsApp" $SoportePhone $true $true
    Add-Row "Correo Electrónico" $SoporteMail $true $false

    # Separador
    $sep = New-Object System.Windows.Forms.Panel
    $sep.Size      = New-Object System.Drawing.Size(280, 1)
    $sep.Location  = New-Object System.Drawing.Point(20, ($script:currentY + 2))
    $sep.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $form.Controls.Add($sep)

    # Firma de Autor
    $lblAuthor = New-Object System.Windows.Forms.Label
    $lblAuthor.Text      = "Desarrollado por Martin Chambilla"
    $lblAuthor.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Italic)
    $lblAuthor.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $lblAuthor.Location  = New-Object System.Drawing.Point(20, ($script:currentY + 6))
    $lblAuthor.AutoSize  = $true
    $form.Controls.Add($lblAuthor)

    # Botón Cerrar
    $btnCerrar = New-Object System.Windows.Forms.Button
    $btnCerrar.Text      = "Cerrar"
    $btnCerrar.Size      = New-Object System.Drawing.Size(270, 30)
    $btnCerrar.Location  = New-Object System.Drawing.Point(20, ($script:currentY + 26))
    $btnCerrar.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCerrar.BackColor = $ColorHeader
    $btnCerrar.ForeColor = [System.Drawing.Color]::White
    $btnCerrar.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnCerrar.FlatAppearance.BorderSize = 0
    $btnCerrar.Add_Click({ $form.Close() })
    $form.Controls.Add($btnCerrar)

    $form.ClientSize = New-Object System.Drawing.Size(320, ($script:currentY + 66))
    
    $form.Location = New-Object System.Drawing.Point(
        ($screen.Right  - $form.Width  - 10),
        ($screen.Bottom - $form.Height - 10)
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