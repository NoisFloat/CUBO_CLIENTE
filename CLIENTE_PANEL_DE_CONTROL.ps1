#Requires -RunAsAdministrator
<#
OPENSSH_SERVER_YA_INSTALADO_RUTAS_FIJAS_VALIDADO.ps1

Escenario:
- OpenSSH YA esta instalado manualmente/MSI en: C:\Program Files\OpenSSH
- Los datos/configuracion se guardan como Windows Capability en: C:\ProgramData\ssh

Este script:
- NO usa Add-WindowsCapability.
- NO usa Get-WindowsCapability.
- NO depende de Windows Update.
- Valida binarios en C:\Program Files\OpenSSH.
- Usa C:\ProgramData\ssh para sshd_config, host keys, logs y authorized_keys de administradores.
- Genera host keys.
- Repara permisos estrictos.
- Configura administrators_authorized_keys.
- Configura authorized_keys del usuario actual como respaldo.
- Genera sshd_config limpio.
- Deshabilita password login.
- Habilita public key login.
- Crea/recrea servicio sshd apuntando a C:\Program Files\OpenSSH\sshd.exe.
- Recrea regla de firewall.
- Inicia sshd.
- Muestra diagnostico final.

IMPORTANTE:
Antes de ejecutar, reemplaza PEGA_AQUI_TU_LLAVE_PUBLICA_COMPLETA
por tu llave publica real en una sola linea.
#>

$ErrorActionPreference = "Stop"

# ============================================================
# 1. PEGA AQUI TU LLAVE PUBLICA COMPLETA
# ============================================================

$PublicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCldfTtTpVsOwrjRTy66O0JZ4M9ihSr/FzFC7iGj7fG4Fayku6+/jsdCWqOabnycm3kcQJcM03RsK4EOZF4cd2DPQj6kpn4qVEojsdjc+AwoZlwZ5BBusAkgo/r4MJkj3YTzKaejGsejHooNe6Nv57lJq7BN6DzpXyHmi8Uqwel0EX4+qRevB7v5bbXYuLGgmFUWe7nclhlTKFPg0JhJT8a5QSR/KvSrwUvqEbVKFBFs3txgMhda6HkH+S4DBdkE0T+0ahm0j0Ti0bnqmH5+fskYQnWLhSYO3pghAiPpKp73Co4Z7zmAqdewDAe47hQ72k8oggy6P/ifMX7jmfYPO2fRoUTOW0WL3t1BBmEE6wn5HjY+UOSq2HE7basyU3wnly9t/6glehnmMQFn1uG/DOPoIM2GdoXl1/wKF0P7z+KEZjup7QzYuzvKQdhPnysCFxpCO/vfgOJqWwotUuT+KdtTSuEsHLieefTxWggqZ9UuXzVQEB9WOhvVBH+1TMiJEWBnENV5ru+yUI+hQllcGU3vDYPBmLjrtGzdTP1TNdufI+NquSR6GRMT2vdkEkQIkwz3UX9/06iaPMNKq56SfFSRW6K/kxU7FuWDJGXy1Hi9+jlSoau8mMUcN/7y6uvEU3dGDhQKoLuPE6cdAcCOEiTHT0ygmLAtf6RpROCCkxv+Q=="
# ============================================================
# 2. VARIABLES FIJAS
# ============================================================

$SshPort = 22

$ComputerName = $env:COMPUTERNAME
$UserName = $env:USERNAME
$UserProfile = $env:USERPROFILE
$TempDir = $env:TEMP

# Rutas fijas solicitadas
$OpenSshDir = "C:\Program Files\OpenSSH"
$SshDir = "C:\ProgramData\ssh"

$LogsDir = Join-Path $SshDir "logs"
$SshdConfig = Join-Path $SshDir "sshd_config"
$AdminKeys = Join-Path $SshDir "administrators_authorized_keys"

$SshdExe = Join-Path $OpenSshDir "sshd.exe"
$SshKeygenExe = Join-Path $OpenSshDir "ssh-keygen.exe"
$SftpServerExe = Join-Path $OpenSshDir "sftp-server.exe"

$UserSshDir = Join-Path $UserProfile ".ssh"
$UserKeys = Join-Path $UserSshDir "authorized_keys"

$BackupTime = Get-Date -Format "yyyyMMdd_HHmmss"
$SshdConfigBackup = "$SshdConfig.bak_$BackupTime"
$TempConfig = Join-Path $TempDir "sshd_config_test_$BackupTime.tmp"

# ============================================================
# 3. FUNCIONES
# ============================================================

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

function Remove-IcaclsIdentityIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Identity
    )

    icacls $Path /remove:g $Identity 2>$null | Out-Null
}

function Reset-SshDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    takeown /f $Path /a /r /d y | Out-Null

    icacls $Path /inheritance:r | Out-Null

    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Users"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Authenticated Users"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Everyone"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Todos"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Usuarios"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Usuarios autentificados"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Usuarios autenticados"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity $UserName

    # SYSTEM y Administradores por SID, independiente del idioma del Windows
    icacls $Path /grant:r "*S-1-5-18:(OI)(CI)(F)" | Out-Null
    icacls $Path /grant:r "*S-1-5-32-544:(OI)(CI)(F)" | Out-Null
}

function Reset-SshFileAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    takeown /f $Path /a | Out-Null

    icacls $Path /inheritance:r | Out-Null

    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Users"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Authenticated Users"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Everyone"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Todos"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Usuarios"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Usuarios autentificados"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity "Usuarios autenticados"
    Remove-IcaclsIdentityIfExists -Path $Path -Identity $UserName

    # SYSTEM y Administradores por SID, independiente del idioma del Windows
    icacls $Path /grant:r "*S-1-5-18:F" | Out-Null
    icacls $Path /grant:r "*S-1-5-32-544:F" | Out-Null
}

function Set-CurrentUserSshAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $DirectoryPath,

        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    if (-not (Test-Path $DirectoryPath)) {
        New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
    }

    if (-not (Test-Path $FilePath)) {
        New-Item -ItemType File -Path $FilePath -Force | Out-Null
    }

    $CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $SystemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

    $Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $Allow = [System.Security.AccessControl.AccessControlType]::Allow
    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None

    $UserSshDirAcl = Get-Acl $DirectoryPath
    $UserSshDirAcl.SetAccessRuleProtection($true, $false)

    foreach ($Rule in @($UserSshDirAcl.Access)) {
        [void] $UserSshDirAcl.RemoveAccessRule($Rule)
    }

    $UserSshDirAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUserSid, $Rights, $InheritanceFlags, $PropagationFlags, $Allow)))
    $UserSshDirAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, $Rights, $InheritanceFlags, $PropagationFlags, $Allow)))
    $UserSshDirAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid, $Rights, $InheritanceFlags, $PropagationFlags, $Allow)))

    Set-Acl -Path $DirectoryPath -AclObject $UserSshDirAcl

    $UserKeysAcl = Get-Acl $FilePath
    $UserKeysAcl.SetAccessRuleProtection($true, $false)

    foreach ($Rule in @($UserKeysAcl.Access)) {
        [void] $UserKeysAcl.RemoveAccessRule($Rule)
    }

    $UserKeysAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUserSid, $Rights, $Allow)))
    $UserKeysAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, $Rights, $Allow)))
    $UserKeysAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid, $Rights, $Allow)))

    Set-Acl -Path $FilePath -AclObject $UserKeysAcl
}

# ============================================================
# 4. VALIDAR ADMINISTRADOR
# ============================================================

Write-Section "Validando ejecucion como administrador"

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
$IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

Write-Host "OK: PowerShell se esta ejecutando como administrador." -ForegroundColor Green
Write-Host "Equipo:  $ComputerName" -ForegroundColor Cyan
Write-Host "Usuario: $UserName" -ForegroundColor Cyan
Write-Host "Perfil:  $UserProfile" -ForegroundColor Cyan

# ============================================================
# 5. VALIDAR LLAVE PUBLICA
# ============================================================

Write-Section "Validando llave publica"

if ([string]::IsNullOrWhiteSpace($PublicKey)) {
    throw "La variable `$PublicKey esta vacia."
}

if ($PublicKey -like "*PEGA_AQUI*") {
    throw "Debes reemplazar PEGA_AQUI_TU_LLAVE_PUBLICA_COMPLETA por una llave publica real."
}

if ($PublicKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+\S+') {
    throw "La llave publica no parece valida. Debe empezar con ssh-ed25519, ssh-rsa o ecdsa-sha2-*."
}

if ($PublicKey -match "`r" -or $PublicKey -match "`n") {
    throw "La llave publica debe estar en una sola linea."
}

Write-Host "OK: llave publica validada." -ForegroundColor Green

# ============================================================
# 6. VALIDAR OPENSSH YA INSTALADO EN C:\Program Files\OpenSSH
# ============================================================

Write-Section "Validando OpenSSH ya instalado"

if (-not (Test-Path $OpenSshDir)) {
    throw "No existe la carpeta $OpenSshDir. Este script asume OpenSSH ya instalado en esa ruta."
}

if (-not (Test-Path $SshdExe)) {
    throw "No se encontro sshd.exe en $SshdExe"
}

if (-not (Test-Path $SshKeygenExe)) {
    throw "No se encontro ssh-keygen.exe en $SshKeygenExe"
}

if (-not (Test-Path $SftpServerExe)) {
    throw "No se encontro sftp-server.exe en $SftpServerExe"
}

Write-Host "OK: OpenSSH encontrado en $OpenSshDir" -ForegroundColor Green
Write-Host "sshd.exe:       $SshdExe" -ForegroundColor Cyan
Write-Host "ssh-keygen.exe: $SshKeygenExe" -ForegroundColor Cyan
Write-Host "sftp-server:    $SftpServerExe" -ForegroundColor Cyan

# ============================================================
# 7. CREAR CARPETAS
# ============================================================

Write-Section "Creando/verificando carpetas"

New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
New-Item -ItemType Directory -Path $UserSshDir -Force | Out-Null

Write-Host "OK: carpetas verificadas." -ForegroundColor Green
Write-Host $SshDir -ForegroundColor Cyan
Write-Host $LogsDir -ForegroundColor Cyan
Write-Host $UserSshDir -ForegroundColor Cyan

# ============================================================
# 8. DETENER sshd ANTES DE TOCAR PERMISOS
# ============================================================

Write-Section "Deteniendo sshd si esta activo"

$ExistingSshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue

if ($null -ne $ExistingSshdService) {
    Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Write-Host "OK: intento de detencion completado." -ForegroundColor Green

# ============================================================
# 9. CREAR O CORREGIR SERVICIO sshd
# ============================================================

Write-Section "Creando/corrigiendo servicio sshd"

$SshdServiceInfo = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
$ExpectedBinaryPath = "`"$SshdExe`""

if ($null -eq $SshdServiceInfo) {
    Write-Host "Servicio sshd no existe. Creandolo..." -ForegroundColor Yellow

    New-Service `
        -Name "sshd" `
        -BinaryPathName $ExpectedBinaryPath `
        -DisplayName "OpenSSH SSH Server" `
        -StartupType Automatic | Out-Null

    Write-Host "OK: servicio sshd creado apuntando a $SshdExe" -ForegroundColor Green
} else {
    Write-Host "Servicio sshd existente:" -ForegroundColor Yellow
    Write-Host $SshdServiceInfo.PathName -ForegroundColor Cyan

    $CurrentPathNormalized = ($SshdServiceInfo.PathName -replace '"', '').Trim()
    $ExpectedPathNormalized = $SshdExe.Trim()

    if ($CurrentPathNormalized -ne $ExpectedPathNormalized) {
        Write-Host "El servicio sshd no apunta a $SshdExe. Se recreara." -ForegroundColor Yellow

        Stop-Service sshd -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete sshd | Out-Null
        Start-Sleep -Seconds 3

        New-Service `
            -Name "sshd" `
            -BinaryPathName $ExpectedBinaryPath `
            -DisplayName "OpenSSH SSH Server" `
            -StartupType Automatic | Out-Null

        Write-Host "OK: servicio sshd recreado apuntando a $SshdExe" -ForegroundColor Green
    } else {
        Set-Service -Name sshd -StartupType Automatic
        Write-Host "OK: servicio sshd ya apunta al binario correcto." -ForegroundColor Green
    }
}

# ============================================================
# 10. GENERAR HOST KEYS
# ============================================================

Write-Section "Generando/verificando host keys"

& $SshKeygenExe -A | Out-Null

if ($LASTEXITCODE -ne 0) {
    throw "ssh-keygen -A fallo."
}

Write-Host "OK: host keys generadas/verificadas." -ForegroundColor Green

# ============================================================
# 11. REPARAR C:\ProgramData\ssh
# ============================================================

Write-Section "Reparando permisos de $SshDir"

Reset-SshDirectoryAcl -Path $SshDir

Write-Host "OK: permisos de $SshDir reparados." -ForegroundColor Green

# ============================================================
# 12. REPARAR C:\ProgramData\ssh\logs
# ============================================================

Write-Section "Reparando permisos de $LogsDir"

Reset-SshDirectoryAcl -Path $LogsDir

Write-Host "OK: permisos de $LogsDir reparados." -ForegroundColor Green

# ============================================================
# 13. REPARAR HOST KEYS
# ============================================================

Write-Section "Reparando permisos de host keys"

$HostPrivateKeys = Get-ChildItem -Path $SshDir -Filter "ssh_host_*_key" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*.pub" }

foreach ($HostPrivateKey in $HostPrivateKeys) {
    Reset-SshFileAcl -Path $HostPrivateKey.FullName
}

Write-Host "OK: permisos de host keys privadas reparados." -ForegroundColor Green

$HostPublicKeys = Get-ChildItem -Path $SshDir -Filter "ssh_host_*_key.pub" -File -ErrorAction SilentlyContinue

foreach ($HostPublicKey in $HostPublicKeys) {
    Reset-SshFileAcl -Path $HostPublicKey.FullName
}

Write-Host "OK: permisos de host keys publicas reparados." -ForegroundColor Green

# ============================================================
# 14. CONFIGURAR administrators_authorized_keys
# ============================================================

Write-Section "Configurando $AdminKeys"

if (-not (Test-Path $AdminKeys)) {
    New-Item -ItemType File -Path $AdminKeys -Force | Out-Null
}

$ExistingAdminKeys = @(Get-Content -Path $AdminKeys -ErrorAction SilentlyContinue)

if ($ExistingAdminKeys -notcontains $PublicKey) {
    Add-Content -Path $AdminKeys -Value $PublicKey -Encoding ascii
    Write-Host "OK: llave agregada a administrators_authorized_keys." -ForegroundColor Green
} else {
    Write-Host "OK: la llave ya existia en administrators_authorized_keys." -ForegroundColor Green
}

Reset-SshFileAcl -Path $AdminKeys

Write-Host "OK: administrators_authorized_keys configurado." -ForegroundColor Green

# ============================================================
# 15. CONFIGURAR authorized_keys DEL USUARIO ACTUAL COMO RESPALDO
# ============================================================

Write-Section "Configurando $UserKeys"

if (-not (Test-Path $UserKeys)) {
    New-Item -ItemType File -Path $UserKeys -Force | Out-Null
}

$ExistingUserKeys = @(Get-Content -Path $UserKeys -ErrorAction SilentlyContinue)

if ($ExistingUserKeys -notcontains $PublicKey) {
    Add-Content -Path $UserKeys -Value $PublicKey -Encoding ascii
    Write-Host "OK: llave agregada a authorized_keys del usuario." -ForegroundColor Green
} else {
    Write-Host "OK: la llave ya existia en authorized_keys del usuario." -ForegroundColor Green
}

Set-CurrentUserSshAcl -DirectoryPath $UserSshDir -FilePath $UserKeys

Write-Host "OK: authorized_keys del usuario actual configurado." -ForegroundColor Green

# ============================================================
# 16. DETECTAR GRUPO ADMINISTRADORES POR SID
# ============================================================

Write-Section "Detectando grupo local Administradores"

$AdministratorsGroup = Get-LocalGroup |
    Where-Object { $_.SID -eq "S-1-5-32-544" } |
    Select-Object -First 1

if ($null -eq $AdministratorsGroup) {
    throw "No se pudo detectar el grupo local Administradores con SID S-1-5-32-544."
}

$AdministratorsGroupName = $AdministratorsGroup.Name

Write-Host "Grupo detectado: $AdministratorsGroupName" -ForegroundColor Green

# ============================================================
# 17. BACKUP DE sshd_config
# ============================================================

Write-Section "Preparando sshd_config"

if (-not (Test-Path $SshdConfig)) {
    New-Item -ItemType File -Path $SshdConfig -Force | Out-Null
}

Copy-Item -Path $SshdConfig -Destination $SshdConfigBackup -Force

Write-Host "Backup creado: $SshdConfigBackup" -ForegroundColor Green

# ============================================================
# 18. CREAR sshd_config LIMPIO
# ============================================================

Write-Section "Generando sshd_config limpio"

$NewConfig = @"
# ============================================================
# sshd_config generado para OpenSSH ya instalado
# Equipo: $ComputerName
# Fecha: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Binario sshd: $SshdExe
# Datos SSH: $SshDir
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

Subsystem sftp "$SftpServerExe"

Match Group $AdministratorsGroupName
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@

Set-Content -Path $TempConfig -Value $NewConfig -Encoding ascii -Force

Write-Host "OK: sshd_config temporal creado." -ForegroundColor Green

# ============================================================
# 19. VALIDAR CONFIGURACION TEMPORAL
# ============================================================

Write-Section "Validando configuracion temporal"

& $SshdExe -t -f $TempConfig

if ($LASTEXITCODE -ne 0) {
    Remove-Item -Path $TempConfig -Force -ErrorAction SilentlyContinue
    throw "La configuracion temporal no es valida. No se modifico sshd_config real."
}

Write-Host "OK: configuracion temporal valida." -ForegroundColor Green

# ============================================================
# 20. APLICAR sshd_config REAL
# ============================================================

Write-Section "Aplicando sshd_config real"

Copy-Item -Path $TempConfig -Destination $SshdConfig -Force
Remove-Item -Path $TempConfig -Force -ErrorAction SilentlyContinue

Write-Host "OK: sshd_config aplicado." -ForegroundColor Green

# ============================================================
# 21. REPARAR PERMISOS DE sshd_config
# ============================================================

Write-Section "Reparando permisos de $SshdConfig"

Reset-SshFileAcl -Path $SshdConfig

Write-Host "OK: permisos de sshd_config reparados." -ForegroundColor Green

# ============================================================
# 22. VALIDAR sshd_config REAL
# ============================================================

Write-Section "Validando sshd_config real"

& $SshdExe -t -f $SshdConfig

if ($LASTEXITCODE -ne 0) {
    Copy-Item -Path $SshdConfigBackup -Destination $SshdConfig -Force
    throw "sshd_config quedo invalido. Se restauro el backup: $SshdConfigBackup"
}

Write-Host "OK: sshd_config real valido." -ForegroundColor Green

# ============================================================
# 23. CONFIGURAR SERVICIO sshd
# ============================================================

Write-Section "Configurando servicio sshd"

Set-Service -Name sshd -StartupType Automatic

$FinalSshdServiceInfo = Get-CimInstance Win32_Service -Filter "Name='sshd'"

Write-Host "OK: sshd configurado como automatico." -ForegroundColor Green
Write-Host "Ruta del servicio:" -ForegroundColor Cyan
Write-Host $FinalSshdServiceInfo.PathName -ForegroundColor Cyan

# ============================================================
# 24. RECREAR FIREWALL OPENSSH
# ============================================================

Write-Section "Recreando regla de firewall OpenSSH"

Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

Get-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -ErrorAction SilentlyContinue |
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
# 25. RECONFIRMAR PERMISOS DE LOGS
# ============================================================

Write-Section "Reconfirmando permisos de logs"

Reset-SshDirectoryAcl -Path $LogsDir

Write-Host "OK: logs reconfirmado." -ForegroundColor Green

# ============================================================
# 26. INICIAR sshd
# ============================================================

Write-Section "Iniciando sshd"

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
    Write-Host "Informacion del servicio sshd:" -ForegroundColor Yellow
    Get-CimInstance Win32_Service -Filter "Name='sshd'" |
        Select-Object Name, State, StartMode, PathName |
        Format-List

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
    Write-Host "Ultimos eventos relacionados con sshd/OpenSSH:" -ForegroundColor Yellow
    Get-WinEvent -LogName Application -MaxEvents 150 |
        Where-Object {
            $_.ProviderName -match "sshd|OpenSSH" -or
            $_.Message -match "sshd|OpenSSH|1067|1053|7034"
        } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List

    throw "sshd fallo al iniciar. Revisa el diagnostico mostrado arriba."
}

Start-Sleep -Seconds 2

$SshdService = Get-Service -Name sshd

if ($SshdService.Status -ne "Running") {
    throw "sshd no quedo en ejecucion. Estado actual: $($SshdService.Status)"
}

Write-Host "OK: sshd esta ejecutandose." -ForegroundColor Green

# ============================================================
# 27. PROBAR PUERTO LOCAL
# ============================================================

Write-Section "Probando puerto local $SshPort"

$LocalPortTest = Test-NetConnection -ComputerName 127.0.0.1 -Port $SshPort -WarningAction SilentlyContinue

if ($LocalPortTest.TcpTestSucceeded) {
    Write-Host "OK: el puerto $SshPort responde localmente." -ForegroundColor Green
} else {
    Write-Host "ADVERTENCIA: el puerto $SshPort no respondio localmente." -ForegroundColor Yellow
}

# ============================================================
# 28. RESUMEN FINAL
# ============================================================

Write-Section "RESUMEN OPENSSH"

Write-Host ""
Write-Host "OpenSSH:" -ForegroundColor Cyan
Write-Host $OpenSshDir

Write-Host ""
Write-Host "Datos/configuracion:" -ForegroundColor Cyan
Write-Host $SshDir

Write-Host ""
Write-Host "Servicio sshd:" -ForegroundColor Cyan
Get-Service -Name sshd | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "Ruta del servicio sshd:" -ForegroundColor Cyan
Get-CimInstance Win32_Service -Filter "Name='sshd'" |
    Select-Object Name, State, StartMode, PathName |
    Format-List

Write-Host ""
Write-Host "Firewall OpenSSH:" -ForegroundColor Cyan
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" |
    Format-Table Name, Enabled, Direction, Action -AutoSize

Write-Host ""
Write-Host "Puerto firewall:" -ForegroundColor Cyan
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" |
    Get-NetFirewallPortFilter |
    Format-Table Protocol, LocalPort -AutoSize

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
Write-Host "OpenSSH quedo configurado correctamente." -ForegroundColor Green

Write-Host ""
Write-Host "Prueba desde tu Mac:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_ed25519 $UserName@IP_DEL_SERVIDOR"

Write-Host ""
Write-Host "Si cambiaste el puerto, usa:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -p $SshPort -i ~/Programming/PanelDeControlCubo/Servicios/id_ed25519 $UserName@IP_DEL_SERVIDOR"