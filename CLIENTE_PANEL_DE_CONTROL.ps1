# CLIENTE_PANEL_DE_CONTROL.ps1
# Ejecutar como Administrador

$PublicKey = @"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNbtAdN1ACSjGghRsH4SwU5Q6/SJA2RR0GktmRbd3UDiA5B2nzX1hDZQgZFbb1xhgzTOJCwJfakDio46mZAxUts/HtMFbIQ8HYDstr2G8qKVnCtyDHfiKCXVohwhfR2sF35rr2gpS0ov5dFGLiuauI7omZMRGTPv1KN5vbWtiJIPVpbeHtVQGByduJ+27uYds6tML1KH+CfIlJeH6MzOLbrlqjc7tCI2KEbmvRjzpJok52rr2Md70hbSnce3spZLCWvqIAI24NqoQH9CMCwQU6DHS8+4OcUfdjj5oEaPVWBFA8Ym19plaGd9eI13qMMSqeJ5/IKU8hg7H2cqtBdFBpAzmJYMabl5iivXVx0bIZUO6oWDAY6PDGqxVL9GlaxLDDTx890VLlGEzKa8VJpVpJWM68jNmIhBMu+wqT5BzQPo5OC1rVrPsNgTIOq1jMYgOVNhlP+Iog+wccKmaybFQcWVEGTnvi4FznLTckVk2mLA9+lIRZBOY0lz7VEnKevkDlSGOt367r7kY5Z9XyC94QtvL/Teg6OHx+Dw3EliVP96/pc0ltg9JHzZSy/d6g5LHnLHSWRcIU+FS2Ig0HAHJm6uBj2h8MgefiCjYJ0GqWLtngBquAGsAl5Uqt89nNvfDC4nJMfehlYYnhQ+Dkx81dqfwx1PfSLkl7OVJEZQhtcQ==
"@

# Instalar OpenSSH Server
$server = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"

if ($server.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

# Iniciar SSH
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Crear .ssh y authorized_keys
$sshDir = "$env:USERPROFILE\.ssh"
$authorizedKeys = "$sshDir\authorized_keys"

if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
}

if (!(Test-Path $authorizedKeys)) {
    New-Item -ItemType File -Path $authorizedKeys | Out-Null
}

# Agregar llave pública si no existe
$llave = $PublicKey.Trim()
$contenido = Get-Content $authorizedKeys -ErrorAction SilentlyContinue

if ($contenido -notcontains $llave) {
    Add-Content -Path $authorizedKeys -Value $llave
}

# Permisos
icacls $sshDir /inheritance:r
icacls $sshDir /grant:r "$env:USERNAME:F"

icacls $authorizedKeys /inheritance:r
icacls $authorizedKeys /grant:r "$env:USERNAME:F"

# Configurar SSH solo con llave pública
$sshdConfig = "C:\ProgramData\ssh\sshd_config"

if (Test-Path $sshdConfig) {
    $config = Get-Content $sshdConfig

    $config = $config `
        -replace "^\s*#?\s*PubkeyAuthentication\s+.*", "PubkeyAuthentication yes" `
        -replace "^\s*#?\s*PasswordAuthentication\s+.*", "PasswordAuthentication no" `
        -replace "^\s*#?\s*PermitEmptyPasswords\s+.*", "PermitEmptyPasswords no"

    Set-Content $sshdConfig $config

    $config = Get-Content $sshdConfig

    if ($config -notmatch "^PubkeyAuthentication yes") {
        Add-Content $sshdConfig "PubkeyAuthentication yes"
    }

    if ($config -notmatch "^PasswordAuthentication no") {
        Add-Content $sshdConfig "PasswordAuthentication no"
    }

    if ($config -notmatch "^PermitEmptyPasswords no") {
        Add-Content $sshdConfig "PermitEmptyPasswords no"
    }
}

# Firewall solo red local
Get-NetFirewallRule -DisplayName "PanelDeControlCubo SSH" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

New-NetFirewallRule `
    -DisplayName "PanelDeControlCubo SSH" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Action Allow `
    -RemoteAddress LocalSubnet

# Reiniciar servicio
Restart-Service sshd

Write-Host "Cliente configurado correctamente."
Write-Host "SSH activo solo desde red local."
Write-Host "Autenticacion por contraseña desactivada."
Write-Host "Autenticacion por llave publica activada."
Write-Host "Usuario SSH:"
Write-Host $env:USERNAME