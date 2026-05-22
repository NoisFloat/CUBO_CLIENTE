# CLIENTE_PANEL_DE_CONTROL.ps1
# Ejecutar como Administrador

$PublicKey = @"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNbtAdN1ACSjGghRsH4SwU5Q6/SJA2RR0GktmRbd3UDiA5B2nzX1hDZQgZFbb1xhgzTOJCwJfakDio46mZAxUts/HtMFbIQ8HYDstr2G8qKVnCtyDHfiKCXVohwhfR2sF35rr2gpS0ov5dFGLiuauI7omZMRGTPv1KN5vbWtiJIPVpbeHtVQGByduJ+27uYds6tML1KH+CfIlJeH6MzOLbrlqjc7tCI2KEbmvRjzpJok52rr2Md70hbSnce3spZLCWvqIAI24NqoQH9CMCwQU6DHS8+4OcUfdjj5oEaPVWBFA8Ym19plaGd9eI13qMMSqeJ5/IKU8hg7H2cqtBdFBpAzmJYMabl5iivXVx0bIZUO6oWDAY6PDGqxVLlGEzKa8VJpVpJWM68jNmIhBMu+wqT5BzQPo5OC1rVrPsNgTIOq1jMYgOVNhlP+Iog+wccKmaybFQcWVEGTnvi4FznLTckVk2mLA9+lIRZBOY0lz7VEnKevkDlSGOt367r7kY5Z9XyC94QtvL/Teg6OHx+Dw3EliVP96/pc0ltg9JHzZSy/d6g5LHnLHSWRcIU+FS2Ig0HAHJm6uBj2h8MgefiCjYJ0GqWLtngBquAGsAl5Uqt89nNvfDC4nJMfehlYYnhQ+Dkx81dqfwx1PfSLkl7OVJEZQhtcQ==
"@.Trim()

# -----------------------------
# Validar administrador
# -----------------------------

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

# -----------------------------
# Instalar OpenSSH Server si falta
# -----------------------------

$Capability = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"

if ($Capability.State -ne "Installed") {
    Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

# -----------------------------
# Activar servicio SSH
# -----------------------------

Write-Host "Activando servicio sshd..." -ForegroundColor Yellow

Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

# -----------------------------
# Rutas
# -----------------------------

$SshDir = "C:\ProgramData\ssh"
$SshdConfig = "$SshDir\sshd_config"
$AdminKeys = "$SshDir\administrators_authorized_keys"

# -----------------------------
# Crear directorio SSH si falta
# -----------------------------

New-Item -ItemType Directory -Path $SshDir -Force | Out-Null

# -----------------------------
# Crear archivo de llaves para administradores
# -----------------------------

Write-Host "Configurando administrators_authorized_keys..." -ForegroundColor Yellow

Set-Content -Path $AdminKeys -Value $PublicKey -Encoding ascii

# Permisos requeridos por Windows OpenSSH
icacls $AdminKeys /inheritance:r | Out-Null
icacls $AdminKeys /grant:r "Administrators:F" | Out-Null
icacls $AdminKeys /grant:r "SYSTEM:F" | Out-Null

# -----------------------------
# Crear regla de firewall para puerto 22
# -----------------------------

Write-Host "Configurando firewall para puerto 22..." -ForegroundColor Yellow

if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow | Out-Null
}

# -----------------------------
# Configurar sshd_config
# Solo autenticación por llave
# -----------------------------

Write-Host "Endureciendo sshd_config: solo autenticacion por llaves..." -ForegroundColor Yellow

if (-not (Test-Path $SshdConfig)) {
    Write-Host "ERROR: No existe $SshdConfig. Verifica instalacion de OpenSSH Server." -ForegroundColor Red
    exit 1
}

$BackupPath = "$SshdConfig.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $SshdConfig $BackupPath -Force

function Set-SshdConfigValue {
    param (
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    $Content = Get-Content $Path -Raw

    if ($Content -match "(?m)^\s*#?\s*$Key\s+") {
        $Content = $Content -replace "(?m)^\s*#?\s*$Key\s+.*$", "$Key $Value"
    } else {
        $Content = $Content.TrimEnd() + "`r`n$Key $Value`r`n"
    }

    Set-Content -Path $Path -Value $Content -Encoding ascii
}

Set-SshdConfigValue -Path $SshdConfig -Key "PubkeyAuthentication" -Value "yes"
Set-SshdConfigValue -Path $SshdConfig -Key "PasswordAuthentication" -Value "no"
Set-SshdConfigValue -Path $SshdConfig -Key "KbdInteractiveAuthentication" -Value "no"
Set-SshdConfigValue -Path $SshdConfig -Key "PermitEmptyPasswords" -Value "no"

# Eliminar bloques Match Group administrators duplicados simples
$ConfigText = Get-Content $SshdConfig -Raw

# Asegurar que los administradores usen administrators_authorized_keys
if ($ConfigText -notmatch "(?ms)^Match\s+Group\s+administrators\s+.*?AuthorizedKeysFile\s+__PROGRAMDATA__/ssh/administrators_authorized_keys") {
    Add-Content -Path $SshdConfig -Encoding ascii -Value @"

Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@
}

# -----------------------------
# Validar configuración SSH
# -----------------------------

Write-Host "Validando sshd_config..." -ForegroundColor Yellow

$SshdExe = "$env:WINDIR\System32\OpenSSH\sshd.exe"

if (-not (Test-Path $SshdExe)) {
    Write-Host "ERROR: No se encontro sshd.exe en $SshdExe" -ForegroundColor Red
    Copy-Item $BackupPath $SshdConfig -Force
    exit 1
}

& $SshdExe -t

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: sshd_config tiene un problema. Restaurando backup:" -ForegroundColor Red
    Write-Host $BackupPath
    Copy-Item $BackupPath $SshdConfig -Force
    exit 1
}

# -----------------------------
# Reiniciar servicio SSH
# -----------------------------

Write-Host "Reiniciando sshd..." -ForegroundColor Yellow

Restart-Service sshd

# -----------------------------
# Resultado
# -----------------------------

Write-Host ""
Write-Host "SSH configurado correctamente." -ForegroundColor Green
Write-Host "Autenticacion por password: DESACTIVADA" -ForegroundColor Green
Write-Host "Autenticacion por llave publica: ACTIVADA" -ForegroundColor Green
Write-Host ""
Write-Host "Usuario Windows actual:"
Write-Host $env:USERNAME
Write-Host ""
Write-Host "Desde tu Mac prueba:"
Write-Host "ssh -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_rsa $env:USERNAME@IP_DEL_PC"
Write-Host ""
Write-Host "Para confirmar que password esta bloqueado:"
Write-Host "ssh -o PreferredAuthentications=password $env:USERNAME@IP_DEL_PC"
