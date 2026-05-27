#Requires -RunAsAdministrator
<#
OPENSSH_SERVER_NUEVO_PUBLICKEY_STRICT_FINAL.ps1

Servidor nuevo:
- Instala OpenSSH Server si falta.
- Genera host keys.
- Repara permisos de C:\ProgramData\ssh.
- Repara permisos de C:\ProgramData\ssh\logs.
- Repara permisos de host keys.
- Configura administrators_authorized_keys.
- Configura authorized_keys del usuario actual como respaldo.
- Genera sshd_config limpio.
- Deshabilita password login.
- Habilita public key login.
- Recrea firewall OpenSSH.
- Inicia sshd.
- Muestra diagnóstico final.

IMPORTANTE:
Antes de ejecutar, reemplaza PEGA_AQUI_TU_LLAVE_PUBLICA_COMPLETA
por tu llave pública real en una sola línea.

Ejemplo para generar llave desde Mac:

ssh-keygen -t ed25519 -f ~/Programming/PanelDeControlCubo/Servicios/id_ed25519

Ver llave pública:

cat ~/Programming/PanelDeControlCubo/Servicios/id_ed25519.pub
#>

$ErrorActionPreference = "Stop"

# ============================================================
# 1. PEGA AQUÍ TU LLAVE PÚBLICA COMPLETA
# ============================================================

$PublicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCldfTtTpVsOwrjRTy66O0JZ4M9ihSr/FzFC7iGj7fG4Fayku6+/jsdCWqOabnycm3kcQJcM03RsK4EOZF4cd2DPQj6kpn4qVEojsdjc+AwoZlwZ5BBusAkgo/r4MJkj3YTzKaejGsejHooNe6Nv57lJq7BN6DzpXyHmi8Uqwel0EX4+qRevB7v5bbXYuLGgmFUWe7nclhlTKFPg0JhJT8a5QSR/KvSrwUvqEbVKFBFs3txgMhda6HkH+S4DBdkE0T+0ahm0j0Ti0bnqmH5+fskYQnWLhSYO3pghAiPpKp73Co4Z7zmAqdewDAe47hQ72k8oggy6P/ifMX7jmfYPO2fRoUTOW0WL3t1BBmEE6wn5HjY+UOSq2HE7basyU3wnly9t/6glehnmMQFn1uG/DOPoIM2GdoXl1/wKF0P7z+KEZjup7QzYuzvKQdhPnysCFxpCO/vfgOJqWwotUuT+KdtTSuEsHLieefTxWggqZ9UuXzVQEB9WOhvVBH+1TMiJEWBnENV5ru+yUI+hQllcGU3vDYPBmLjrtGzdTP1TNdufI+NquSR6GRMT2vdkEkQIkwz3UX9/06iaPMNKq56SfFSRW6K/kxU7FuWDJGXy1Hi9+jlSoau8mMUcN/7y6uvEU3dGDhQKoLuPE6cdAcCOEiTHT0ygmLAtf6RpROCCkxv+Q=="

# ============================================================
# 2. VARIABLES
# ============================================================

$SshPort = 22

$ComputerName = $env:COMPUTERNAME

$UserName = $env:USERNAME

$UserProfile = $env:USERPROFILE

$WindowsDir = $env:WINDIR

$ProgramDataDir = $env:ProgramData

$TempDir = $env:TEMP

$SshDir = Join-Path $ProgramDataDir "ssh"

$LogsDir = Join-Path $SshDir "logs"

$SshdConfig = Join-Path $SshDir "sshd_config"

$AdminKeys = Join-Path $SshDir "administrators_authorized_keys"

$SshdExe = Join-Path $OpenSshInstallDir "sshd.exe"

$SshKeygenExe = Join-Path $OpenSshInstallDir "ssh-keygen.exe"

$UserSshDir = Join-Path $UserProfile ".ssh"

$UserKeys = Join-Path $UserSshDir "authorized_keys"

$BackupTime = Get-Date -Format "yyyyMMdd_HHmmss"

$SshdConfigBackup = "$SshdConfig.bak_$BackupTime"

$TempConfig = Join-Path $TempDir "sshd_config_test_$BackupTime.tmp"

# ============================================================
# 3. VALIDAR ADMINISTRADOR
# ============================================================

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)

$IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Equipo:  $ComputerName" -ForegroundColor Cyan
Write-Host "Usuario: $UserName" -ForegroundColor Cyan
Write-Host "Perfil:  $UserProfile" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 4. VALIDAR LLAVE PÚBLICA
# ============================================================

if ([string]::IsNullOrWhiteSpace($PublicKey)) {
    throw "La variable `$PublicKey está vacía."
}

if ($PublicKey -like "*PEGA_AQUI*") {
    throw "Debes reemplazar PEGA_AQUI_TU_LLAVE_PUBLICA_COMPLETA por una llave pública real."
}

if ($PublicKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+\S+') {
    throw "La llave pública no parece válida. Debe empezar con ssh-ed25519, ssh-rsa o ecdsa-sha2-*."
}

if ($PublicKey -match "`r" -or $PublicKey -match "`n") {
    throw "La llave pública debe estar en una sola línea."
}

Write-Host "OK: llave pública validada." -ForegroundColor Green

# ============================================================
# 5. INSTALAR OPENSSH SERVER
# ============================================================

Write-Host "Verificando OpenSSH instalado por MSI..." -ForegroundColor Yellow

$PossibleOpenSshDirs = @(
    "C:\Program Files\OpenSSH",
    "C:\Program Files\OpenSSH-Win64",
    "C:\Program Files (x86)\OpenSSH"
)

$OpenSshInstallDir = $PossibleOpenSshDirs | Where-Object {
    Test-Path (Join-Path $_ "sshd.exe")
} | Select-Object -First 1

if (-not $OpenSshInstallDir) {
    throw "No se encontró sshd.exe. Instala primero Win32-OpenSSH MSI."
}

Write-Host "OK: OpenSSH MSI encontrado en $OpenSshInstallDir" -ForegroundColor Green

# ============================================================
# 6. CREAR CARPETAS
# ============================================================

Write-Host "Creando/verificando carpetas..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $SshDir -Force | Out-Null

New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

New-Item -ItemType Directory -Path $UserSshDir -Force | Out-Null

Write-Host "OK: carpetas verificadas." -ForegroundColor Green

# ============================================================
# 7. VALIDAR BINARIOS
# ============================================================

if (-not (Test-Path $SshdExe)) {
    throw "No se encontró sshd.exe en $SshdExe"
}

if (-not (Test-Path $SshKeygenExe)) {
    throw "No se encontró ssh-keygen.exe en $SshKeygenExe"
}

Write-Host "OK: sshd.exe encontrado." -ForegroundColor Green

Write-Host "OK: ssh-keygen.exe encontrado." -ForegroundColor Green

# ============================================================
# 8. DETENER sshd ANTES DE TOCAR PERMISOS
# ============================================================

Write-Host "Deteniendo sshd si está activo..." -ForegroundColor Yellow

$ExistingSshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue

if ($null -ne $ExistingSshdService) {
    Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Write-Host "OK: intento de detención completado." -ForegroundColor Green

# ============================================================
# 9. GENERAR HOST KEYS
# ============================================================

Write-Host "Generando/verificando host keys..." -ForegroundColor Yellow

& $SshKeygenExe -A | Out-Null

Write-Host "OK: host keys generadas/verificadas." -ForegroundColor Green

# ============================================================
# 10. REPARAR C:\ProgramData\ssh
# Causa común del Error 1067 si tiene permisos incorrectos.
# ============================================================

Write-Host "Reparando permisos de $SshDir ..." -ForegroundColor Yellow

takeown /f $SshDir /a /r /d y | Out-Null

icacls $SshDir /inheritance:r | Out-Null

icacls $SshDir /remove:g "Users" 2>$null | Out-Null

icacls $SshDir /remove:g "Authenticated Users" 2>$null | Out-Null

icacls $SshDir /remove:g "Everyone" 2>$null | Out-Null

icacls $SshDir /remove:g "Todos" 2>$null | Out-Null

icacls $SshDir /remove:g "Usuarios" 2>$null | Out-Null

icacls $SshDir /remove:g "Usuarios autentificados" 2>$null | Out-Null

icacls $SshDir /remove:g $UserName 2>$null | Out-Null

icacls $SshDir /grant:r "*S-1-5-18:(OI)(CI)(F)" | Out-Null

icacls $SshDir /grant:r "*S-1-5-32-544:(OI)(CI)(F)" | Out-Null

Write-Host "OK: permisos de $SshDir reparados." -ForegroundColor Green

# ============================================================
# 11. REPARAR C:\ProgramData\ssh\logs
# Esta carpeta puede romper sshd con Error 1067.
# ============================================================

Write-Host "Reparando permisos de $LogsDir ..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

takeown /f $LogsDir /a /r /d y | Out-Null

icacls $LogsDir /inheritance:r | Out-Null

icacls $LogsDir /remove:g "Users" 2>$null | Out-Null

icacls $LogsDir /remove:g "Authenticated Users" 2>$null | Out-Null

icacls $LogsDir /remove:g "Everyone" 2>$null | Out-Null

icacls $LogsDir /remove:g "Todos" 2>$null | Out-Null

icacls $LogsDir /remove:g "Usuarios" 2>$null | Out-Null

icacls $LogsDir /remove:g "Usuarios autentificados" 2>$null | Out-Null

icacls $LogsDir /remove:g $UserName 2>$null | Out-Null

icacls $LogsDir /grant:r "*S-1-5-18:(OI)(CI)(F)" | Out-Null

icacls $LogsDir /grant:r "*S-1-5-32-544:(OI)(CI)(F)" | Out-Null

Write-Host "OK: permisos de $LogsDir reparados." -ForegroundColor Green

# ============================================================
# 12. REPARAR HOST KEYS
# Las llaves privadas del host no deben quedar accesibles a usuarios normales.
# ============================================================

Write-Host "Reparando permisos de host keys privadas..." -ForegroundColor Yellow

$HostPrivateKeys = Get-ChildItem -Path $SshDir -Filter "ssh_host_*_key" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.pub" }

foreach ($HostPrivateKey in $HostPrivateKeys) {
    takeown /f $HostPrivateKey.FullName /a | Out-Null

    icacls $HostPrivateKey.FullName /inheritance:r | Out-Null

    icacls $HostPrivateKey.FullName /remove:g "Users" 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /remove:g "Authenticated Users" 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /remove:g "Everyone" 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /remove:g "Todos" 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /remove:g "Usuarios" 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /remove:g "Usuarios autentificados" 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /remove:g $UserName 2>$null | Out-Null

    icacls $HostPrivateKey.FullName /grant:r "*S-1-5-18:F" | Out-Null

    icacls $HostPrivateKey.FullName /grant:r "*S-1-5-32-544:F" | Out-Null
}

Write-Host "OK: permisos de host keys privadas reparados." -ForegroundColor Green

Write-Host "Reparando permisos de host keys públicas..." -ForegroundColor Yellow

$HostPublicKeys = Get-ChildItem -Path $SshDir -Filter "ssh_host_*_key.pub" -File -ErrorAction SilentlyContinue

foreach ($HostPublicKey in $HostPublicKeys) {
    takeown /f $HostPublicKey.FullName /a | Out-Null

    icacls $HostPublicKey.FullName /inheritance:r | Out-Null

    icacls $HostPublicKey.FullName /grant:r "*S-1-5-18:F" | Out-Null

    icacls $HostPublicKey.FullName /grant:r "*S-1-5-32-544:F" | Out-Null
}

Write-Host "OK: permisos de host keys públicas reparados." -ForegroundColor Green

# ============================================================
# 13. CONFIGURAR administrators_authorized_keys
# Para usuarios administradores.
# ============================================================

Write-Host "Configurando $AdminKeys ..." -ForegroundColor Yellow

if (-not (Test-Path $AdminKeys)) {
    New-Item -ItemType File -Path $AdminKeys -Force | Out-Null
}

$ExistingAdminKeys = Get-Content -Path $AdminKeys -ErrorAction SilentlyContinue

if ($ExistingAdminKeys -notcontains $PublicKey) {
    Add-Content -Path $AdminKeys -Value $PublicKey -Encoding ascii
}

takeown /f $AdminKeys /a | Out-Null

icacls $AdminKeys /inheritance:r | Out-Null

icacls $AdminKeys /remove:g "Users" 2>$null | Out-Null

icacls $AdminKeys /remove:g "Authenticated Users" 2>$null | Out-Null

icacls $AdminKeys /remove:g "Everyone" 2>$null | Out-Null

icacls $AdminKeys /remove:g "Todos" 2>$null | Out-Null

icacls $AdminKeys /remove:g "Usuarios" 2>$null | Out-Null

icacls $AdminKeys /remove:g "Usuarios autentificados" 2>$null | Out-Null

icacls $AdminKeys /remove:g $UserName 2>$null | Out-Null

icacls $AdminKeys /grant:r "*S-1-5-18:F" | Out-Null

icacls $AdminKeys /grant:r "*S-1-5-32-544:F" | Out-Null

Write-Host "OK: administrators_authorized_keys configurado." -ForegroundColor Green

# ============================================================
# 14. CONFIGURAR authorized_keys DEL USUARIO ACTUAL
# Respaldo útil si Match Group no aplica como esperamos.
# ============================================================

Write-Host "Configurando $UserKeys ..." -ForegroundColor Yellow

if (-not (Test-Path $UserKeys)) {
    New-Item -ItemType File -Path $UserKeys -Force | Out-Null
}

$ExistingUserKeys = Get-Content -Path $UserKeys -ErrorAction SilentlyContinue

if ($ExistingUserKeys -notcontains $PublicKey) {
    Add-Content -Path $UserKeys -Value $PublicKey -Encoding ascii
}

$CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User

$SystemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")

$AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

$Rights = [System.Security.AccessControl.FileSystemRights]::FullControl

$Allow = [System.Security.AccessControl.AccessControlType]::Allow

$UserSshDirAcl = Get-Acl $UserSshDir

$UserSshDirAcl.SetAccessRuleProtection($true, $false)

foreach ($Rule in @($UserSshDirAcl.Access)) {
    [void] $UserSshDirAcl.RemoveAccessRule($Rule)
}

$UserSshDirAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUserSid, $Rights, $Allow)))

$UserSshDirAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, $Rights, $Allow)))

$UserSshDirAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid, $Rights, $Allow)))

Set-Acl -Path $UserSshDir -AclObject $UserSshDirAcl

$UserKeysAcl = Get-Acl $UserKeys

$UserKeysAcl.SetAccessRuleProtection($true, $false)

foreach ($Rule in @($UserKeysAcl.Access)) {
    [void] $UserKeysAcl.RemoveAccessRule($Rule)
}

$UserKeysAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUserSid, $Rights, $Allow)))

$UserKeysAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, $Rights, $Allow)))

$UserKeysAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid, $Rights, $Allow)))

Set-Acl -Path $UserKeys -AclObject $UserKeysAcl

Write-Host "OK: authorized_keys del usuario actual configurado." -ForegroundColor Green

# ============================================================
# 15. DETECTAR GRUPO ADMINISTRADORES POR SID
# S-1-5-32-544 es el grupo local Administradores.
# En español suele ser Administradores.
# En inglés suele ser Administrators.
# ============================================================

Write-Host "Detectando grupo Administradores..." -ForegroundColor Yellow

$AdministratorsGroup = Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-544" } | Select-Object -First 1

if ($null -eq $AdministratorsGroup) {
    throw "No se pudo detectar el grupo local Administradores con SID S-1-5-32-544."
}

$AdministratorsGroupName = $AdministratorsGroup.Name

Write-Host "Grupo detectado: $AdministratorsGroupName" -ForegroundColor Green

# ============================================================
# 16. BACKUP DE sshd_config
# ============================================================

Write-Host "Preparando sshd_config..." -ForegroundColor Yellow

if (-not (Test-Path $SshdConfig)) {
    New-Item -ItemType File -Path $SshdConfig -Force | Out-Null
}

Copy-Item -Path $SshdConfig -Destination $SshdConfigBackup -Force

Write-Host "Backup creado: $SshdConfigBackup" -ForegroundColor Green

# ============================================================
# 17. CREAR sshd_config LIMPIO
# No usamos ListenAddress para evitar errores con IPv6/interfaces.
# ============================================================

Write-Host "Generando sshd_config limpio..." -ForegroundColor Yellow

$NewConfig = @"
# ============================================================
# sshd_config generado para servidor nuevo
# Equipo: $ComputerName
# Fecha: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================

Port $SshPort
AddressFamily any

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

PermitTTY yes
PrintMotd yes

AllowAgentForwarding yes
AllowTcpForwarding yes
X11Forwarding no

Subsystem sftp sftp-server.exe

Match Group $AdministratorsGroupName
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@

Set-Content -Path $TempConfig -Value $NewConfig -Encoding ascii -Force

Write-Host "OK: sshd_config temporal creado." -ForegroundColor Green

# ============================================================
# 18. VALIDAR CONFIGURACIÓN TEMPORAL
# ============================================================

Write-Host "Validando configuración temporal..." -ForegroundColor Yellow

& $SshdExe -t -f $TempConfig

if ($LASTEXITCODE -ne 0) {
    Remove-Item -Path $TempConfig -Force -ErrorAction SilentlyContinue
    throw "La configuración temporal no es válida. No se modificó sshd_config real."
}

Write-Host "OK: configuración temporal válida." -ForegroundColor Green

# ============================================================
# 19. APLICAR sshd_config REAL
# ============================================================

Copy-Item -Path $TempConfig -Destination $SshdConfig -Force

Remove-Item -Path $TempConfig -Force -ErrorAction SilentlyContinue

Write-Host "OK: sshd_config aplicado." -ForegroundColor Green

# ============================================================
# 20. REPARAR PERMISOS DE sshd_config
# ============================================================

Write-Host "Reparando permisos de $SshdConfig ..." -ForegroundColor Yellow

takeown /f $SshdConfig /a | Out-Null

icacls $SshdConfig /inheritance:r | Out-Null

icacls $SshdConfig /remove:g "Users" 2>$null | Out-Null

icacls $SshdConfig /remove:g "Authenticated Users" 2>$null | Out-Null

icacls $SshdConfig /remove:g "Everyone" 2>$null | Out-Null

icacls $SshdConfig /remove:g "Todos" 2>$null | Out-Null

icacls $SshdConfig /remove:g "Usuarios" 2>$null | Out-Null

icacls $SshdConfig /remove:g "Usuarios autentificados" 2>$null | Out-Null

icacls $SshdConfig /remove:g $UserName 2>$null | Out-Null

icacls $SshdConfig /grant:r "*S-1-5-18:F" | Out-Null

icacls $SshdConfig /grant:r "*S-1-5-32-544:F" | Out-Null

Write-Host "OK: permisos de sshd_config reparados." -ForegroundColor Green

# ============================================================
# 21. VALIDAR sshd_config REAL
# ============================================================

Write-Host "Validando sshd_config real..." -ForegroundColor Yellow

& $SshdExe -t -f $SshdConfig

if ($LASTEXITCODE -ne 0) {
    Copy-Item -Path $SshdConfigBackup -Destination $SshdConfig -Force
    throw "sshd_config quedó inválido. Se restauró el backup: $SshdConfigBackup"
}

Write-Host "OK: sshd_config real válido." -ForegroundColor Green

# ============================================================
# 22. CONFIGURAR SERVICIO sshd
# ============================================================

Write-Host "Configurando servicio sshd..." -ForegroundColor Yellow

Set-Service -Name sshd -StartupType Automatic

Write-Host "OK: sshd configurado como automático." -ForegroundColor Green

# ============================================================
# 23. RECREAR FIREWALL OPENSSH
# Para servidor nuevo es más seguro borrar y recrear la regla.
# ============================================================

Write-Host "Recreando regla de firewall OpenSSH..." -ForegroundColor Yellow

Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

New-NetFirewallRule `
    -Name "OpenSSH-Server-In-TCP" `
    -DisplayName "OpenSSH Server (sshd)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $SshPort `
    -Action Allow | Out-Null

Write-Host "OK: firewall configurado para puerto $SshPort." -ForegroundColor Green

# ============================================================
# 24. ÚLTIMA RECONFIRMACIÓN DE logs
# Redundante a propósito para evitar Error 1067.
# ============================================================

Write-Host "Reconfirmando permisos de logs..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

takeown /f $LogsDir /a /r /d y | Out-Null

icacls $LogsDir /inheritance:r | Out-Null

icacls $LogsDir /remove:g "Users" 2>$null | Out-Null

icacls $LogsDir /remove:g "Authenticated Users" 2>$null | Out-Null

icacls $LogsDir /remove:g "Everyone" 2>$null | Out-Null

icacls $LogsDir /remove:g "Todos" 2>$null | Out-Null

icacls $LogsDir /remove:g "Usuarios" 2>$null | Out-Null

icacls $LogsDir /remove:g "Usuarios autentificados" 2>$null | Out-Null

icacls $LogsDir /remove:g $UserName 2>$null | Out-Null

icacls $LogsDir /grant:r "*S-1-5-18:(OI)(CI)(F)" | Out-Null

icacls $LogsDir /grant:r "*S-1-5-32-544:(OI)(CI)(F)" | Out-Null

Write-Host "OK: logs reconfirmado." -ForegroundColor Green

# ============================================================
# 25. INICIAR sshd
# ============================================================

Write-Host "Iniciando sshd..." -ForegroundColor Yellow

try {
    Start-Service -Name sshd -ErrorAction Stop
} catch {
    Write-Host ""
    Write-Host "ERROR: sshd no pudo iniciar." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Write-Host ""
    Write-Host "Validando sshd_config:" -ForegroundColor Yellow
    & $SshdExe -t -f $SshdConfig

    Write-Host ""
    Write-Host "Permisos de C:\ProgramData\ssh:" -ForegroundColor Yellow
    icacls $SshDir

    Write-Host ""
    Write-Host "Permisos de C:\ProgramData\ssh\logs:" -ForegroundColor Yellow
    icacls $LogsDir

    Write-Host ""
    Write-Host "Permisos de sshd_config:" -ForegroundColor Yellow
    icacls $SshdConfig

    Write-Host ""
    Write-Host "Permisos de administrators_authorized_keys:" -ForegroundColor Yellow
    icacls $AdminKeys

    Write-Host ""
    Write-Host "Host keys privadas:" -ForegroundColor Yellow
    Get-ChildItem -Path $SshDir -Filter "ssh_host_*_key" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "*.pub" } |
        ForEach-Object {
            Write-Host ""
            Write-Host $_.FullName -ForegroundColor Cyan
            icacls $_.FullName
        }

    Write-Host ""
    Write-Host "Últimos eventos relacionados con sshd/OpenSSH:" -ForegroundColor Yellow
    Get-WinEvent -LogName Application -MaxEvents 100 |
        Where-Object {
            $_.ProviderName -match "sshd|OpenSSH" -or
            $_.Message -match "sshd|OpenSSH|1067|1053|7034"
        } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List

    throw "sshd falló al iniciar. Revisa el diagnóstico mostrado arriba."
}

Start-Sleep -Seconds 2

$SshdService = Get-Service -Name sshd

if ($SshdService.Status -ne "Running") {
    throw "sshd no quedó en ejecución. Estado actual: $($SshdService.Status)"
}

Write-Host "OK: sshd está ejecutándose." -ForegroundColor Green

# ============================================================
# 26. PROBAR PUERTO LOCAL
# ============================================================

Write-Host "Probando puerto local $SshPort ..." -ForegroundColor Yellow

$LocalPortTest = Test-NetConnection -ComputerName 127.0.0.1 -Port $SshPort -WarningAction SilentlyContinue

if ($LocalPortTest.TcpTestSucceeded) {
    Write-Host "OK: el puerto $SshPort responde localmente." -ForegroundColor Green
} else {
    Write-Host "ADVERTENCIA: el puerto $SshPort no respondió localmente." -ForegroundColor Yellow
}

# ============================================================
# 27. RESUMEN FINAL
# ============================================================

Write-Host ""
Write-Host "===== RESUMEN OPENSSH =====" -ForegroundColor Cyan

Write-Host ""
Write-Host "Servicio sshd:" -ForegroundColor Cyan
Get-Service -Name sshd | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "Firewall OpenSSH:" -ForegroundColor Cyan
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Format-Table Name, Enabled, Direction, Action -AutoSize

Write-Host ""
Write-Host "Puerto firewall:" -ForegroundColor Cyan
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Get-NetFirewallPortFilter | Format-Table Protocol, LocalPort -AutoSize

Write-Host ""
Write-Host "Permisos C:\ProgramData\ssh:" -ForegroundColor Cyan
icacls $SshDir

Write-Host ""
Write-Host "Permisos C:\ProgramData\ssh\logs:" -ForegroundColor Cyan
icacls $LogsDir

Write-Host ""
Write-Host "Permisos sshd_config:" -ForegroundColor Cyan
icacls $SshdConfig

Write-Host ""
Write-Host "Permisos administrators_authorized_keys:" -ForegroundColor Cyan
icacls $AdminKeys

Write-Host ""
Write-Host "Permisos authorized_keys del usuario:" -ForegroundColor Cyan
icacls $UserKeys

Write-Host ""
Write-Host "Host keys privadas:" -ForegroundColor Cyan
Get-ChildItem -Path $SshDir -Filter "ssh_host_*_key" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*.pub" } |
    Select-Object FullName |
    Format-Table -AutoSize

Write-Host ""
Write-Host "IPs IPv4 detectadas:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object IPAddress, InterfaceAlias |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Backup de sshd_config:" -ForegroundColor Cyan
Write-Host $SshdConfigBackup

Write-Host ""
Write-Host "OpenSSH quedó configurado correctamente." -ForegroundColor Green

Write-Host ""
Write-Host "Prueba desde tu Mac:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_ed25519 $UserName@IP_DEL_SERVIDOR"

Write-Host ""
Write-Host "Si cambiaste el puerto, usa:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -p $SshPort -i ~/Programming/PanelDeControlCubo/Servicios/id_ed25519 $UserName@IP_DEL_SERVIDOR"
