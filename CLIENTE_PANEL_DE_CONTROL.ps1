#Requires -RunAsAdministrator
<#
CLIENTE_PANEL_DE_CONTROL_OPENSSH_PUBLICKEY_FINAL.ps1
Windows Server 2019 / 2022 / 2025
Windows 10 / Windows 11

Objetivo:
- Instalar y configurar OpenSSH Server en servidores nuevos.
- Habilitar autenticación por llave pública.
- Deshabilitar autenticación por contraseña.
- Configurar correctamente usuarios administradores y usuario actual.
- Crear backup de sshd_config.
- Validar configuración antes de aplicarla.
- Usar SID para permisos y detectar nombre localizado del grupo Administradores.

Uso:
1. Genera llave en tu Mac/Linux/cliente:
   ssh-keygen -t ed25519 -f ~/Programming/PanelDeControlCubo/Servicios/id_ed25519

2. Obtén la llave pública:
   cat ~/Programming/PanelDeControlCubo/Servicios/id_ed25519.pub

3. Pega la llave pública completa en $PublicKey.

4. Ejecuta este script en PowerShell como Administrador.
#>

$ErrorActionPreference = "Stop"

# ============================================================
# 1. PEGA AQUI TU LLAVE PUBLICA
# ============================================================

$PublicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCldfTtTpVsOwrjRTy66O0JZ4M9ihSr/FzFC7iGj7fG4Fayku6+/jsdCWqOabnycm3kcQJcM03RsK4EOZF4cd2DPQj6kpn4qVEojsdjc+AwoZlwZ5BBusAkgo/r4MJkj3YTzKaejGsejHooNe6Nv57lJq7BN6DzpXyHmi8Uqwel0EX4+qRevB7v5bbXYuLGgmFUWe7nclhlTKFPg0JhJT8a5QSR/KvSrwUvqEbVKFBFs3txgMhda6HkH+S4DBdkE0T+0ahm0j0Ti0bnqmH5+fskYQnWLhSYO3pghAiPpKp73Co4Z7zmAqdewDAe47hQ72k8oggy6P/ifMX7jmfYPO2fRoUTOW0WL3t1BBmEE6wn5HjY+UOSq2HE7basyU3wnly9t/6glehnmMQFn1uG/DOPoIM2GdoXl1/wKF0P7z+KEZjup7QzYuzvKQdhPnysCFxpCO/vfgOJqWwotUuT+KdtTSuEsHLieefTxWggqZ9UuXzVQEB9WOhvVBH+1TMiJEWBnENV5ru+yUI+hQllcGU3vDYPBmLjrtGzdTP1TNdufI+NquSR6GRMT2vdkEkQIkwz3UX9/06iaPMNKq56SfFSRW6K/kxU7FuWDJGXy1Hi9+jlSoau8mMUcN/7y6uvEU3dGDhQKoLuPE6cdAcCOEiTHT0ygmLAtf6RpROCCkxv+Q=="

# ============================================================
# 2. Opciones para servidores nuevos
# ============================================================

$SshPort = 22

# Para servidores nuevos, recomendado: solo llaves, sin password.
$DisablePasswordAuthentication = $true

# Configura también C:\Users\<usuario>\.ssh\authorized_keys.
# Útil si el usuario actual no cae en Match Group Administrators por algún caso raro.
$AlsoConfigureCurrentUserAuthorizedKeys = $true

# En servidores nuevos, esta opción deja sshd_config limpio y controlado.
# Se conserva backup antes de escribir.
$ReplaceSshdConfigForNewServer = $true

# ============================================================
# 3. Validar Administrador
# ============================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

# ============================================================
# 4. Datos del equipo
# ============================================================

$ComputerName = $env:COMPUTERNAME
$UserName     = $env:USERNAME
$UserProfile  = $env:USERPROFILE

Write-Host ""
Write-Host "Equipo:  $ComputerName" -ForegroundColor Cyan
Write-Host "Usuario: $UserName" -ForegroundColor Cyan
Write-Host "Perfil:  $UserProfile" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 5. Validar llave publica
# ============================================================

if ([string]::IsNullOrWhiteSpace($PublicKey) -or $PublicKey -like "*PEGA_AQUI*") {
    throw "Debes pegar una llave pública real en `$PublicKey."
}

if ($PublicKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+\S+') {
    throw "La llave pública no parece válida. Debe empezar con ssh-ed25519, ssh-rsa o ecdsa-sha2-*."
}

if ($PublicKey -match '\r|\n') {
    throw "La llave pública debe estar en una sola línea."
}

# ============================================================
# 6. Funciones auxiliares
# ============================================================

function Add-PublicKeyIfMissing {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $PublicKey
    )

    $Parent = Split-Path -Parent $Path

    if (-not (Test-Path $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    $Existing = Get-Content -Path $Path -ErrorAction SilentlyContinue

    if ($Existing -notcontains $PublicKey) {
        Add-Content -Path $Path -Value $PublicKey -Encoding ascii
        Write-Host "Llave agregada en: $Path" -ForegroundColor Green
    } else {
        Write-Host "La llave ya existe en: $Path" -ForegroundColor Green
    }
}

function Set-StrictAclForAdminKeys {
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    takeown /f $Path /a | Out-Null

    icacls $Path /inheritance:r | Out-Null
    icacls $Path /remove:g `
        "Users" `
        "Authenticated Users" `
        "Everyone" `
        "Todos" `
        "Usuarios" `
        "Usuarios autentificados" `
        2>$null | Out-Null

    # SYSTEM = S-1-5-18
    # Administrators = S-1-5-32-544
    icacls $Path /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron aplicar permisos correctos a $Path"
    }
}

function Set-StrictAclForUserSshPath {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [System.Security.Principal.SecurityIdentifier] $UserSid
    )

    $SystemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $AdminSid  = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

    $Acl = Get-Acl $Path
    $Acl.SetAccessRuleProtection($true, $false)

    foreach ($Rule in @($Acl.Access)) {
        [void] $Acl.RemoveAccessRule($Rule)
    }

    $Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $Allow  = [System.Security.AccessControl.AccessControlType]::Allow

    $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($UserSid,   $Rights, $Allow)))
    $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, $Rights, $Allow)))
    $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid,  $Rights, $Allow)))

    Set-Acl -Path $Path -AclObject $Acl
}

function Get-BuiltinAdministratorsGroupName {
    try {
        $Group = Get-LocalGroup |
            Where-Object { $_.SID -eq "S-1-5-32-544" } |
            Select-Object -First 1

        if ($null -ne $Group -and -not [string]::IsNullOrWhiteSpace($Group.Name)) {
            return $Group.Name
        }
    } catch {
        Write-Host "ADVERTENCIA: No se pudo detectar el grupo Administradores con Get-LocalGroup." -ForegroundColor Yellow
    }

    # Fallback habitual en Windows en inglés.
    return "administrators"
}

# ============================================================
# 7. Instalar OpenSSH Server si falta
# ============================================================

Write-Host "Verificando OpenSSH Server..." -ForegroundColor Yellow

$ServerCapability = Get-WindowsCapability -Online |
    Where-Object Name -like "OpenSSH.Server*" |
    Select-Object -First 1

if ($null -eq $ServerCapability) {
    throw "No se encontró OpenSSH.Server en las características opcionales de Windows."
}

if ($ServerCapability.State -ne "Installed") {
    Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name $ServerCapability.Name | Out-Null
    Write-Host "OpenSSH Server instalado." -ForegroundColor Green
} else {
    Write-Host "OpenSSH Server ya está instalado." -ForegroundColor Green
}

# ============================================================
# 8. Rutas
# ============================================================

$SshDir       = Join-Path $env:ProgramData "ssh"
$SshdConfig   = Join-Path $SshDir "sshd_config"
$AdminKeys    = Join-Path $SshDir "administrators_authorized_keys"
$SshdExe      = Join-Path $env:WINDIR "System32\OpenSSH\sshd.exe"
$SshKeygenExe = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"

New-Item -ItemType Directory -Path $SshDir -Force | Out-Null

if (-not (Test-Path $SshdExe)) {
    throw "No se encontró sshd.exe en $SshdExe"
}

# ============================================================
# 9. Generar host keys si faltan
# ============================================================

Write-Host "Verificando host keys..." -ForegroundColor Yellow

if (Test-Path $SshKeygenExe) {
    & $SshKeygenExe -A | Out-Null
    Write-Host "Host keys verificadas/generadas." -ForegroundColor Green
} else {
    Write-Host "ADVERTENCIA: No se encontró ssh-keygen.exe en $SshKeygenExe." -ForegroundColor Yellow
}

# ============================================================
# 10. Configurar llave para administradores
# ============================================================

Write-Host "Configurando llave para administradores..." -ForegroundColor Yellow

Add-PublicKeyIfMissing -Path $AdminKeys -PublicKey $PublicKey
Set-StrictAclForAdminKeys -Path $AdminKeys

Write-Host "OK: administrators_authorized_keys configurado." -ForegroundColor Green

# ============================================================
# 11. Configurar llave para usuario actual, opcional
# ============================================================

if ($AlsoConfigureCurrentUserAuthorizedKeys) {
    Write-Host "Configurando llave para el usuario actual..." -ForegroundColor Yellow

    $UserSshDir = Join-Path $UserProfile ".ssh"
    $UserKeys   = Join-Path $UserSshDir "authorized_keys"

    New-Item -ItemType Directory -Path $UserSshDir -Force | Out-Null
    Add-PublicKeyIfMissing -Path $UserKeys -PublicKey $PublicKey

    $CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User

    Set-StrictAclForUserSshPath -Path $UserSshDir -UserSid $CurrentUserSid
    Set-StrictAclForUserSshPath -Path $UserKeys   -UserSid $CurrentUserSid

    Write-Host "OK: authorized_keys del usuario actual configurado." -ForegroundColor Green
}

# ============================================================
# 12. Crear sshd_config para servidor nuevo
# ============================================================

Write-Host "Configurando sshd_config..." -ForegroundColor Yellow

if (-not (Test-Path $SshdConfig)) {
    New-Item -ItemType File -Path $SshdConfig -Force | Out-Null
}

$Backup = "$SshdConfig.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $SshdConfig $Backup -Force
Write-Host "Backup creado: $Backup" -ForegroundColor Green

$AdministratorsGroupName = Get-BuiltinAdministratorsGroupName
Write-Host "Grupo Administradores detectado para Match Group: $AdministratorsGroupName" -ForegroundColor Cyan

if ($DisablePasswordAuthentication) {
    $PasswordAuthentication = "no"
    $KbdInteractiveAuthentication = "no"
} else {
    $PasswordAuthentication = "yes"
    $KbdInteractiveAuthentication = "yes"
}

if ($ReplaceSshdConfigForNewServer) {
    $NewConfig = @"
# ============================================================
# sshd_config generado para servidor nuevo
# Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Equipo: $ComputerName
# ============================================================

Port $SshPort
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication $PasswordAuthentication
KbdInteractiveAuthentication $KbdInteractiveAuthentication
PermitEmptyPasswords no

AllowAgentForwarding yes
AllowTcpForwarding yes
X11Forwarding no

Subsystem sftp sftp-server.exe

Match Group $AdministratorsGroupName
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@
} else {
    $Config = Get-Content $SshdConfig -Raw -ErrorAction SilentlyContinue

    if ($null -eq $Config) {
        $Config = ""
    }

    $Config = $Config -replace "`r`n", "`n"
    $Config = $Config -replace "`r", "`n"

    $Config = [regex]::Replace(
        $Config,
        "(?mis)^\s*Match\s+Group\s+.*administr.*\s*$.*?(?=^\s*Match\s+|\z)",
        ""
    )

    $FirstMatch = [regex]::Match($Config, "(?mi)^\s*Match\s+")

    if ($FirstMatch.Success) {
        $GlobalPart = $Config.Substring(0, $FirstMatch.Index)
        $MatchPart  = $Config.Substring($FirstMatch.Index)
    } else {
        $GlobalPart = $Config
        $MatchPart  = ""
    }

    function Set-GlobalDirective {
        param(
            [string] $Text,
            [string] $Directive,
            [string] $Value
        )

        $Pattern = "(?mi)^\s*#?\s*$([regex]::Escape($Directive))\s+.*$"
        $Text = [regex]::Replace($Text, $Pattern, "")
        return ($Text.TrimEnd() + "`r`n$Directive $Value`r`n")
    }

    $GlobalPart = Set-GlobalDirective $GlobalPart "Port" "$SshPort"
    $GlobalPart = Set-GlobalDirective $GlobalPart "PubkeyAuthentication" "yes"
    $GlobalPart = Set-GlobalDirective $GlobalPart "AuthorizedKeysFile" ".ssh/authorized_keys"
    $GlobalPart = Set-GlobalDirective $GlobalPart "PasswordAuthentication" "$PasswordAuthentication"
    $GlobalPart = Set-GlobalDirective $GlobalPart "KbdInteractiveAuthentication" "$KbdInteractiveAuthentication"
    $GlobalPart = Set-GlobalDirective $GlobalPart "PermitEmptyPasswords" "no"

    if ($GlobalPart -notmatch "(?mi)^\s*Subsystem\s+sftp\s+") {
        $GlobalPart = $GlobalPart.TrimEnd() + "`r`nSubsystem sftp sftp-server.exe`r`n"
    }

    $AdminMatchBlock = @"
Match Group $AdministratorsGroupName
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@

    $NewConfig = $GlobalPart.TrimEnd() + "`r`n`r`n"

    if (-not [string]::IsNullOrWhiteSpace($MatchPart)) {
        $NewConfig += $MatchPart.TrimEnd() + "`r`n`r`n"
    }

    $NewConfig += $AdminMatchBlock.TrimEnd() + "`r`n"
}

# ============================================================
# 13. Validar configuración antes de aplicarla
# ============================================================

$TempConfig = Join-Path $env:TEMP "sshd_config_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
Set-Content -Path $TempConfig -Value $NewConfig -Encoding ascii -Force

Write-Host "Validando sshd_config temporal..." -ForegroundColor Yellow
& $SshdExe -t -f $TempConfig

if ($LASTEXITCODE -ne 0) {
    Remove-Item $TempConfig -Force -ErrorAction SilentlyContinue
    throw "La configuración temporal no es válida. No se modificó sshd_config real. Backup: $Backup"
}

Copy-Item $TempConfig $SshdConfig -Force
Remove-Item $TempConfig -Force -ErrorAction SilentlyContinue

Write-Host "Validando sshd_config real..." -ForegroundColor Yellow
& $SshdExe -t -f $SshdConfig

if ($LASTEXITCODE -ne 0) {
    Copy-Item $Backup $SshdConfig -Force
    throw "sshd_config quedó inválido. Se restauró backup: $Backup"
}

Write-Host "OK: sshd_config válido." -ForegroundColor Green

# ============================================================
# 14. Activar servicio sshd
# ============================================================

Write-Host "Activando servicio sshd..." -ForegroundColor Yellow

Set-Service -Name sshd -StartupType Automatic

# ============================================================
# 15. Firewall
# ============================================================

Write-Host "Configurando firewall para puerto $SshPort..." -ForegroundColor Yellow

$FirewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

if ($null -eq $FirewallRule) {
    New-NetFirewallRule `
        -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $SshPort `
        -Action Allow | Out-Null
} else {
    Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Out-Null

    try {
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Direction Inbound -Action Allow | Out-Null
        Set-NetFirewallPortFilter -AssociatedNetFirewallRule $FirewallRule -Protocol TCP -LocalPort $SshPort | Out-Null
    } catch {
        Write-Host "ADVERTENCIA: No se pudo ajustar el puerto de la regla existente. Se intentará continuar." -ForegroundColor Yellow
    }
}

# ============================================================
# 16. Reiniciar servicio
# ============================================================

Write-Host "Reiniciando sshd..." -ForegroundColor Yellow

try {
    Restart-Service sshd -Force -ErrorAction Stop
} catch {
    Start-Service sshd -ErrorAction Stop
}

Start-Sleep -Seconds 2

$Service = Get-Service sshd

if ($Service.Status -ne "Running") {
    throw "sshd no quedó en ejecución. Estado: $($Service.Status)"
}

Write-Host "OK: sshd está ejecutándose." -ForegroundColor Green

# ============================================================
# 17. Pruebas y resumen
# ============================================================

Write-Host ""
Write-Host "Verificando puerto local $SshPort..." -ForegroundColor Cyan

$Test = Test-NetConnection -ComputerName 127.0.0.1 -Port $SshPort -WarningAction SilentlyContinue

if ($Test.TcpTestSucceeded) {
    Write-Host "OK: Puerto $SshPort responde localmente." -ForegroundColor Green
} else {
    Write-Host "ADVERTENCIA: El puerto $SshPort no respondió localmente." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Grupos del usuario actual relacionados con administradores:" -ForegroundColor Cyan
whoami /groups | findstr /i "Administradores Administrators"

Write-Host ""
Write-Host "Permisos de administrators_authorized_keys:" -ForegroundColor Cyan
icacls $AdminKeys

if ($AlsoConfigureCurrentUserAuthorizedKeys) {
    Write-Host ""
    Write-Host "Permisos de authorized_keys del usuario:" -ForegroundColor Cyan
    icacls $UserKeys
}

Write-Host ""
Write-Host "Servicio sshd:" -ForegroundColor Cyan
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize

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
Write-Host "OpenSSH configurado correctamente para servidor nuevo." -ForegroundColor Green
Write-Host ""
Write-Host "Desde tu Mac prueba con:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_ed25519 $UserName@IP_DEL_SERVIDOR"
Write-Host ""
Write-Host "Si cambiaste el puerto:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -p $SshPort -i ~/Programming/PanelDeControlCubo/Servicios/id_ed25519 $UserName@IP_DEL_SERVIDOR"
Write-Host ""
Write-Host "Backup de sshd_config:" -ForegroundColor Cyan
Write-Host $Backup
