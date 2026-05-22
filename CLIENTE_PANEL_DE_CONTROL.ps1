# CLIENTE_PANEL_DE_CONTROL_SEGURO.ps1
# Ejecutar como Administrador

$PublicKey = @"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNbtAdN1ACSjGghRsH4SwU5Q6/SJA2RR0GktmRbd3UDiA5B2nzX1hDZQgZFbb1xhgzTOJCwJfakDio46mZAxUts/HtMFbIQ8HYDstr2G8qKVnCtyDHfiKCXVohwhfR2sF35rr2gpS0ov5dFGLiuauI7omZMRGTPv1KN5vbWtiJIPVpbeHtVQGByduJ+27uYds6tML1KH+CfIlJeH6MzOLbrlqjc7tCI2KEbmvRjzpJok52rr2Md70hbSnce3spZLCWvqIAI24NqoQH9CMCwQU6DHS8+4OcUfdjj5oEaPVWBFA8Ym19plaGd9eI13qMMSqeJ5/IKU8hg7H2cqtBdFBpAzmJYMabl5iivXVx0bIZUO6oWDAY6PDGqxVLlGEzKa8VJpVpJWM68jNmIhBMu+wqT5BzQPo5OC1rVrPsNgTIOq1jMYgOVNhlP+Iog+wccKmaybFQcWVEGTnvi4FznLTckVk2mLA9+lIRZBOY0lz7VEnKevkDlSGOt367r7kY5Z9XyC94QtvL/Teg6OHx+Dw3EliVP96/pc0ltg9JHzZSy/d6g5LHnLHSWRcIU+FS2Ig0HAHJm6uBj2h8MgefiCjYJ0GqWLtngBquAGsAl5Uqt89nNvfDC4nJMfehlYYnhQ+Dkx81dqfwx1PfSLkl7OVJEZQhtcQ==
"@

# Validar administrador
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

$PublicKey = $PublicKey.Trim()

# Validar llave
if ($PublicKey -notmatch "^(ssh-rsa|ssh-ed25519)\s+[A-Za-z0-9+/=]+") {
    Write-Host "ERROR: Llave pública inválida." -ForegroundColor Red
    exit 1
}

# Instalar OpenSSH Server
$capability = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"

if ($capability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

# Activar servicio SSH
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

# Rutas oficiales de Windows OpenSSH
$sshDir = "C:\ProgramData\ssh"
$sshdConfig = "$sshDir\sshd_config"
$adminKeys = "$sshDir\administrators_authorized_keys"

if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

if (!(Test-Path $sshdConfig)) {
    Write-Host "ERROR: No existe sshd_config. Reinicia Windows y ejecuta otra vez." -ForegroundColor Red
    exit 1
}

# Backup
$backup = "$sshdConfig.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $sshdConfig $backup -Force

# Agregar llave sin duplicar
if (!(Test-Path $adminKeys)) {
    New-Item -ItemType File -Path $adminKeys -Force | Out-Null
}

$keysActuales = Get-Content $adminKeys -ErrorAction SilentlyContinue

if ($keysActuales -notcontains $PublicKey) {
    Add-Content -Path $adminKeys -Value $PublicKey -Encoding ascii
}

# Permisos requeridos
icacls $adminKeys /inheritance:r | Out-Null
icacls $adminKeys /grant:r "Administrators:F" | Out-Null
icacls $adminKeys /grant:r "SYSTEM:F" | Out-Null

# Configurar SSH solo con llave pública
$config = Get-Content $sshdConfig

function Set-SshConfigLine {
    param (
        [string[]]$Config,
        [string]$Key,
        [string]$Value
    )

    $pattern = "^\s*#?\s*$Key\s+.*"
    $line = "$Key $Value"

    if ($Config -match $pattern) {
        return $Config -replace $pattern, $line
    }

    return $Config + $line
}

$config = Set-SshConfigLine $config "PubkeyAuthentication" "yes"
$config = Set-SshConfigLine $config "PasswordAuthentication" "no"
$config = Set-SshConfigLine $config "PermitEmptyPasswords" "no"
$config = Set-SshConfigLine $config "KbdInteractiveAuthentication" "no"

Set-Content -Path $sshdConfig -Value $config -Encoding ascii

# Firewall solo red local
Get-NetFirewallRule -DisplayName "PanelDeControlCubo SSH" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

New-NetFirewallRule `
    -DisplayName "PanelDeControlCubo SSH" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Action Allow `
    -RemoteAddress LocalSubnet | Out-Null

Restart-Service sshd

Write-Host ""
Write-Host "Configuracion completada correctamente." -ForegroundColor Green
Write-Host "SSH activo solo desde red local."
Write-Host "Solo autenticacion por llave publica."
Write-Host "Backup creado en:"
Write-Host $backup
Write-Host ""
Write-Host "Usuario SSH para tu app:"
Write-Host $env:USERNAME
