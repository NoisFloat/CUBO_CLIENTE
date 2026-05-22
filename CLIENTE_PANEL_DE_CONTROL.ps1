# CLIENTE_PANEL_DE_CONTROL_OPENSSH.ps1
# Ejecutar en PowerShell como Administrador.
# Windows 10 / Windows 11.
# Configura OpenSSH Server para aceptar SOLO autenticación por llave pública.

$ErrorActionPreference = "Stop"

# ============================================================
# 1. Llave pública autorizada
# Esta debe coincidir con:
# ssh-keygen -y -f ~/Programming/PanelDeControlCubo/Servicios/id_rsa
# ============================================================

$PublicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCquPxv3J0kvfUFaTI7muUV5ovGSOk8YVdsKUU3KcW8ZiNU/hQag1p2/oFEZlTxum8oPhKIYdwRL/t12Y+IJrYwlKDyxHGA8zJ9z7JL5YXkn9k3T+j7ArkxJh6Mv45EMb0Cx/td07mS2FtLGwjX1i/E3s/0pAxriiBlcX+8VqcMp6WGCnIRDVeCCOr8APp3ZvWuxL5bj1NIBuPsAL7vVDW2eL9mWIu64AvzI0tFFaraFv4iDSzzcJefreKLj0lnYnaGWfe/Ev7hN7h/S9HsTXlIcOJhGRETvwGDymwdSbmwj61KD3N6OEsRHJ2zb6+Zx5v7X7tU+69Ah06CQNHFSd4Ik1KKjoRUiXrkZe0Jkaq07Qx8bnFVCKMC8HiXTyOIH7IptuvI5j4cz8F3E5VVYUyUEGpJUA9xmJvoMFQX1joLyvZM2GF7MtpONfPmM15tKFcCd3QrRWWqfOx9tNaQPWDiyjY2hkO8NtAAvk/xp72cYJTrj7jCAE8KvxVtdZPxOjw6PZEhK88Oarg9j+yp87xVkvPYe2QgbHjD4nkB2jdxVM9iBYJVjO/SeUbb32V3MlD6uZLLfw0dlZJBYCH8PiFSQ8gJwqfMUvfGxx96D3TeL7BZbYMd/S/Mv9WR6qnnVUqBSUxXXUTtPsEUo5GsDnfje+kBa8WNbJ1ZHk/rv6uPeQ=="

# ============================================================
# 2. Validar que el script corre como Administrador
# ============================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

# ============================================================
# 3. Datos reales de esta máquina
# ============================================================

$ComputerName = $env:COMPUTERNAME
$UserName     = $env:USERNAME
$UserProfile  = $env:USERPROFILE

Write-Host "Equipo:  $ComputerName" -ForegroundColor Cyan
Write-Host "Usuario: $UserName" -ForegroundColor Cyan
Write-Host "Perfil:  $UserProfile" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 4. Instalar OpenSSH Server si falta
# ============================================================

$ServerCapability = Get-WindowsCapability -Online |
    Where-Object Name -like "OpenSSH.Server*"

if ($ServerCapability.State -ne "Installed") {
    Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
} else {
    Write-Host "OpenSSH Server ya esta instalado." -ForegroundColor Green
}

# ============================================================
# 5. Rutas usadas por Windows OpenSSH
# ============================================================

$SshDir     = Join-Path $env:ProgramData "ssh"
$SshdConfig = Join-Path $SshDir "sshd_config"
$AdminKeys  = Join-Path $SshDir "administrators_authorized_keys"
$SshdExe    = Join-Path $env:WINDIR "System32\OpenSSH\sshd.exe"

New-Item -ItemType Directory -Path $SshDir -Force | Out-Null

# ============================================================
# 6. Crear administrators_authorized_keys
# Para usuarios administradores, Windows OpenSSH usa este archivo.
# ============================================================

Write-Host "Escribiendo llave publica en $AdminKeys" -ForegroundColor Yellow

Set-Content -Path $AdminKeys -Value $PublicKey -Encoding ascii -Force

# ============================================================
# 7. Aplicar ACL estrictas
# Deben quedar solo Administradores y SYSTEM.
# Se intenta por SID y por nombres ingles/español.
# ============================================================

Write-Host "Configurando permisos del archivo de llaves..." -ForegroundColor Yellow

takeown /f $AdminKeys /a | Out-Null
icacls $AdminKeys /inheritance:r | Out-Null

$AdminIdentities = @(
    "*S-1-5-32-544",           # SID universal de BUILTIN\Administrators / Administradores
    "BUILTIN\Administrators",
    "BUILTIN\Administradores",
    "Administrators",
    "Administradores"
)

$SystemIdentities = @(
    "*S-1-5-18",               # SID universal de LOCAL SYSTEM
    "NT AUTHORITY\SYSTEM",
    "SYSTEM"
)

$AdminAclOk = $false
foreach ($Identity in $AdminIdentities) {
    icacls $AdminKeys /grant:r "$Identity`:F" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Permiso Administradores aplicado con: $Identity" -ForegroundColor Green
        $AdminAclOk = $true
        break
    }
}

$SystemAclOk = $false
foreach ($Identity in $SystemIdentities) {
    icacls $AdminKeys /grant:r "$Identity`:F" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Permiso SYSTEM aplicado con: $Identity" -ForegroundColor Green
        $SystemAclOk = $true
        break
    }
}

if (-not $AdminAclOk) {
    throw "No se pudo aplicar permiso de Administradores al archivo $AdminKeys"
}

if (-not $SystemAclOk) {
    throw "No se pudo aplicar permiso de SYSTEM al archivo $AdminKeys"
}

# ============================================================
# 8. Activar servicio sshd
# ============================================================

Write-Host "Activando servicio sshd..." -ForegroundColor Yellow

Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

# ============================================================
# 9. Habilitar firewall para puerto 22
# ============================================================

Write-Host "Configurando firewall para puerto 22..." -ForegroundColor Yellow

$FirewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

if ($null -eq $FirewallRule) {
    New-NetFirewallRule `
        -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow | Out-Null
} else {
    Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Out-Null
}

# ============================================================
# 10. Configurar sshd_config
# Se deja solo llave pública.
# PasswordAuthentication queda apagado.
# El bloque Match Group administrators debe ir al final.
# ============================================================

Write-Host "Configurando sshd_config..." -ForegroundColor Yellow

if (-not (Test-Path $SshdConfig)) {
    New-Item -ItemType File -Path $SshdConfig -Force | Out-Null
}

$Backup = "$SshdConfig.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $SshdConfig $Backup -Force

$SshdConfigContent = @"
# sshd_config generado por CLIENTE_PANEL_DE_CONTROL_OPENSSH.ps1

Port 22
AddressFamily any

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

Subsystem sftp sftp-server.exe

Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@

Set-Content -Path $SshdConfig -Value $SshdConfigContent -Encoding ascii

# ============================================================
# 11. Validar configuración antes de reiniciar sshd
# ============================================================

Write-Host "Validando sshd_config..." -ForegroundColor Yellow

if (-not (Test-Path $SshdExe)) {
    throw "No se encontro sshd.exe en $SshdExe"
}

& $SshdExe -t

if ($LASTEXITCODE -ne 0) {
    Copy-Item $Backup $SshdConfig -Force
    throw "sshd_config invalido. Se restauro el backup: $Backup"
}

# ============================================================
# 12. Reiniciar sshd
# ============================================================

Write-Host "Reiniciando sshd..." -ForegroundColor Yellow
Restart-Service sshd

# ============================================================
# 13. Verificación final
# ============================================================

Write-Host ""
Write-Host "OpenSSH configurado correctamente." -ForegroundColor Green
Write-Host ""

Write-Host "Usuario Windows para conectar:" -ForegroundColor Cyan
Write-Host $UserName
Write-Host ""

Write-Host "Grupos del usuario actual:" -ForegroundColor Cyan
whoami /groups | findstr /i "Administradores Administrators"
Write-Host ""

Write-Host "Permisos finales de administrators_authorized_keys:" -ForegroundColor Cyan
icacls $AdminKeys
Write-Host ""

Write-Host "Servicio sshd:" -ForegroundColor Cyan
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize

Write-Host "IPs IPv4 detectadas:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object IPAddress, InterfaceAlias |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Desde tu Mac prueba:" -ForegroundColor Green
Write-Host "ssh -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_rsa $UserName@IP_DE_ESTA_VM"
