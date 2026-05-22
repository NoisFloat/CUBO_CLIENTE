#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configura OpenSSH Server en Windows para acceso SSH por llave pública.

.DESCRIPTION
    - Instala OpenSSH Server si falta.
    - Genera host keys si faltan.
    - Configura administrators_authorized_keys para usuarios administradores.
    - Opcionalmente configura authorized_keys del usuario actual.
    - Aplica permisos estrictos compatibles con Windows OpenSSH.
    - Modifica sshd_config de forma conservadora, sin reescribirlo completo.
    - Crea backup antes de modificar sshd_config.
    - Valida la configuración antes de aplicarla.
    - Restaura backup si la configuración queda inválida.
    - Configura firewall.
    - Reinicia sshd y valida que el puerto responda.

.USO RECOMENDADO
    .\CLIENTE_PANEL_DE_CONTROL_OPENSSH_SEGURO.ps1 `
        -PublicKeyPath "C:\Temp\id_rsa.pub" `
        -AllowedRemoteAddress "LocalSubnet"

    O restringido a la IP de tu Mac:

    .\CLIENTE_PANEL_DE_CONTROL_OPENSSH_SEGURO.ps1 `
        -PublicKeyPath "C:\Temp\id_rsa.pub" `
        -AllowedRemoteAddress "192.168.1.50"

.PRIMERA PRUEBA OPCIONAL
    Para evitar quedarte sin acceso SSH en la primera prueba:

    .\CLIENTE_PANEL_DE_CONTROL_OPENSSH_SEGURO.ps1 `
        -PublicKeyPath "C:\Temp\id_rsa.pub" `
        -AllowedRemoteAddress "192.168.1.50" `
        -AllowPasswordFallbackForFirstRun

    Luego, cuando confirmes que la llave funciona, ejecútalo otra vez SIN
    -AllowPasswordFallbackForFirstRun.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PublicKey,

    [Parameter(Mandatory = $false)]
    [string]$PublicKeyPath,

    [Parameter(Mandatory = $false)]
    [int]$Port = 22,

    [Parameter(Mandatory = $false)]
    [string[]]$AllowedRemoteAddress = @("LocalSubnet"),

    [Parameter(Mandatory = $false)]
    [string]$TargetUser = $env:USERNAME,

    [Parameter(Mandatory = $false)]
    [string]$TargetUserProfile = $env:USERPROFILE,

    [Parameter(Mandatory = $false)]
    [switch]$AlsoConfigureUserAuthorizedKeys,

    [Parameter(Mandatory = $false)]
    [switch]$AllowPasswordFallbackForFirstRun
)

$ErrorActionPreference = "Stop"

# ============================================================
# Funciones auxiliares
# ============================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK: $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "ADVERTENCIA: $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Normalize-PublicKey {
    param([string]$Key)

    $clean = ($Key -replace "`r", "" -replace "`n", "").Trim()

    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "La llave pública está vacía."
    }

    $validKeyPattern = '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+/=]+(\s+.*)?$'

    if ($clean -notmatch $validKeyPattern) {
        throw "La llave pública no parece tener formato OpenSSH válido. Debe empezar con ssh-rsa, ssh-ed25519 o ecdsa-sha2-*."
    }

    return $clean
}

function Set-StrictAclForAdminKeys {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "No existe el archivo para aplicar ACL: $Path"
    }

    # SYSTEM = S-1-5-18
    # BUILTIN\Administrators = S-1-5-32-544
    takeown /f $Path /a | Out-Null

    icacls $Path /inheritance:r | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo desactivar herencia en $Path"
    }

    icacls $Path /remove:g "Users" "Authenticated Users" "Everyone" "Todos" "Usuarios" 2>$null | Out-Null

    icacls $Path /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron aplicar permisos estrictos a $Path"
    }
}

function Set-StrictAclForUserKeys {
    param(
        [string]$Path,
        [string]$UserName
    )

    if (-not (Test-Path $Path)) {
        throw "No existe el archivo para aplicar ACL: $Path"
    }

    $acl = Get-Acl -Path $Path
    $acl.SetAccessRuleProtection($true, $false)

    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRule($rule)
    }

    $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $adminSid  = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

    try {
        if ($UserName -eq $env:USERNAME) {
            $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        }
        else {
            $account = New-Object System.Security.Principal.NTAccount($UserName)
            $userSid = $account.Translate([System.Security.Principal.SecurityIdentifier])
        }
    }
    catch {
        throw "No se pudo resolver el SID del usuario '$UserName'. Verifica -TargetUser y -TargetUserProfile."
    }

    $rights      = [System.Security.AccessControl.FileSystemRights]::FullControl
    $inheritance = [System.Security.AccessControl.InheritanceFlags]::None
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow       = [System.Security.AccessControl.AccessControlType]::Allow

    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($userSid,   $rights, $inheritance, $propagation, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $rights, $inheritance, $propagation, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid,  $rights, $inheritance, $propagation, $allow)))

    Set-Acl -Path $Path -AclObject $acl
}

function Set-SshdDirectiveInGlobalBlock {
    param(
        [string]$ConfigText,
        [string]$Directive,
        [string]$Value
    )

    $line = "$Directive $Value"
    $pattern = "(?mi)^\s*#?\s*$([regex]::Escape($Directive))\s+.*$"

    # Quitamos todas las apariciones globales de esa directiva.
    $ConfigText = [regex]::Replace($ConfigText, $pattern, "")

    # Agregamos una sola versión limpia al final del bloque global.
    return ($ConfigText.TrimEnd() + "`r`n" + $line + "`r`n")
}

function Update-SshdConfigConservatively {
    param(
        [string]$SshdConfigPath,
        [string]$SshdExePath,
        [int]$Port,
        [bool]$PasswordFallback
    )

    Write-Step "Configurando sshd_config de forma conservadora"

    if (-not (Test-Path $SshdConfigPath)) {
        New-Item -ItemType File -Path $SshdConfigPath -Force | Out-Null
    }

    $backup = "$SshdConfigPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $SshdConfigPath -Destination $backup -Force
    Write-Ok "Backup creado: $backup"

    $raw = Get-Content -Path $SshdConfigPath -Raw -ErrorAction SilentlyContinue

    if ($null -eq $raw) {
        $raw = ""
    }

    # Normalizar saltos de línea.
    $raw = $raw -replace "`r`n", "`n"
    $raw = $raw -replace "`r", "`n"

    # Quitar cualquier bloque viejo de administradores para evitar duplicados o errores.
    # Solo quitamos Match Group administrators / Administradores.
    $raw = [regex]::Replace(
        $raw,
        "(?mis)^\s*Match\s+Group\s+(administrators|administradores|administrators,administradores|administradores,administrators)\s*$.*?(?=^\s*Match\s+|\z)",
        ""
    )

    # Dividir configuración global y bloques Match existentes.
    # En OpenSSH, las directivas globales deben ir antes del primer Match.
    $firstMatch = [regex]::Match($raw, "(?mi)^\s*Match\s+")

    if ($firstMatch.Success) {
        $globalPart = $raw.Substring(0, $firstMatch.Index)
        $matchPart  = $raw.Substring($firstMatch.Index)
    }
    else {
        $globalPart = $raw
        $matchPart  = ""
    }

    # Limpiar exceso de líneas vacías.
    $globalPart = $globalPart.TrimEnd()
    $matchPart  = $matchPart.Trim()

    # Directivas mínimas y estables.
    # No agregamos StrictModes, PermitRootLogin ni ListenAddress porque pueden romper
    # en algunas versiones/configuraciones de Windows OpenSSH.
    $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "Port" -Value "$Port"
    $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "PubkeyAuthentication" -Value "yes"
    $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "AuthorizedKeysFile" -Value ".ssh/authorized_keys"

    if ($PasswordFallback) {
        $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "PasswordAuthentication" -Value "yes"
        Write-Warn "PasswordAuthentication quedará ACTIVADO temporalmente por -AllowPasswordFallbackForFirstRun."
        Write-Warn "Después de probar la llave, ejecuta otra vez sin ese parámetro."
    }
    else {
        $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "PasswordAuthentication" -Value "no"
    }

    $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "KbdInteractiveAuthentication" -Value "no"
    $globalPart = Set-SshdDirectiveInGlobalBlock -ConfigText $globalPart -Directive "PermitEmptyPasswords" -Value "no"

    # Asegurar SFTP si no existe en la parte global.
    if ($globalPart -notmatch "(?mi)^\s*Subsystem\s+sftp\s+") {
        $globalPart = $globalPart.TrimEnd() + "`r`nSubsystem sftp sftp-server.exe`r`n"
    }

    # Bloque oficial para usuarios administradores.
    # Debe ir al final.
    $adminMatchBlock = @"
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@

    $newConfig = $globalPart.TrimEnd() + "`r`n`r`n"

    if (-not [string]::IsNullOrWhiteSpace($matchPart)) {
        $newConfig += $matchPart.TrimEnd() + "`r`n`r`n"
    }

    $newConfig += $adminMatchBlock.TrimEnd() + "`r`n"

    $tempConfig = Join-Path $env:TEMP "sshd_config_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
    Set-Content -Path $tempConfig -Value $newConfig -Encoding ascii -Force

    Write-Step "Validando configuración temporal de sshd"

    & $SshdExePath -t -f $tempConfig
    $tempExitCode = $LASTEXITCODE

    if ($tempExitCode -ne 0) {
        Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue
        throw "La configuración temporal de sshd no es válida. No se modificó sshd_config real. Backup intacto: $backup"
    }

    Write-Ok "Configuración temporal válida"

    Copy-Item -Path $tempConfig -Destination $SshdConfigPath -Force
    Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue

    Write-Step "Validando sshd_config real"

    & $SshdExePath -t -f $SshdConfigPath
    $realExitCode = $LASTEXITCODE

    if ($realExitCode -ne 0) {
        Copy-Item -Path $backup -Destination $SshdConfigPath -Force
        throw "sshd_config real falló validación. Se restauró el backup: $backup"
    }

    Write-Ok "sshd_config actualizado y validado correctamente"

    return $backup
}

# ============================================================
# 1. Validar parámetros
# ============================================================

Write-Step "Validando parámetros"

if ([string]::IsNullOrWhiteSpace($PublicKey) -and [string]::IsNullOrWhiteSpace($PublicKeyPath)) {
    throw @"
Debes indicar -PublicKey o -PublicKeyPath.

Ejemplo recomendado:
.\CLIENTE_PANEL_DE_CONTROL_OPENSSH_SEGURO.ps1 -PublicKeyPath "C:\Temp\id_rsa.pub" -AllowedRemoteAddress "LocalSubnet"
"@
}

if (-not [string]::IsNullOrWhiteSpace($PublicKeyPath)) {
    if (-not (Test-Path $PublicKeyPath)) {
        throw "No existe el archivo de llave pública: $PublicKeyPath"
    }

    $PublicKey = Get-Content -Path $PublicKeyPath -Raw
}

$PublicKey = Normalize-PublicKey -Key $PublicKey

if ($Port -lt 1 -or $Port -gt 65535) {
    throw "Puerto inválido: $Port"
}

Write-Ok "Parámetros validados"
Write-Host "Equipo:  $env:COMPUTERNAME"
Write-Host "Usuario: $TargetUser"
Write-Host "Perfil:  $TargetUserProfile"
Write-Host "Puerto:  $Port"
Write-Host "Firewall permitido desde: $($AllowedRemoteAddress -join ', ')"

# ============================================================
# 2. Rutas principales
# ============================================================

$SshDir           = Join-Path $env:ProgramData "ssh"
$SshdConfig       = Join-Path $SshDir "sshd_config"
$AdminKeys        = Join-Path $SshDir "administrators_authorized_keys"
$SshdExe          = Join-Path $env:WINDIR "System32\OpenSSH\sshd.exe"
$SshKeygen        = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
$FirewallRuleName = "OpenSSH-Server-In-TCP"

Ensure-Directory -Path $SshDir

# ============================================================
# 3. Instalar OpenSSH Server si falta
# ============================================================

Write-Step "Verificando OpenSSH Server"

$serverCapability = Get-WindowsCapability -Online |
    Where-Object { $_.Name -like "OpenSSH.Server*" } |
    Select-Object -First 1

if ($null -eq $serverCapability) {
    throw "No se encontró OpenSSH.Server como característica opcional en este Windows."
}

if ($serverCapability.State -ne "Installed") {
    Write-Warn "OpenSSH Server no está instalado. Instalando..."
    Add-WindowsCapability -Online -Name $serverCapability.Name | Out-Null
    Write-Ok "OpenSSH Server instalado"
}
else {
    Write-Ok "OpenSSH Server ya estaba instalado"
}

if (-not (Test-Path $SshdExe)) {
    throw "No se encontró sshd.exe en: $SshdExe"
}

# ============================================================
# 4. Generar host keys si faltan
# ============================================================

Write-Step "Verificando host keys de OpenSSH"

if (Test-Path $SshKeygen) {
    & $SshKeygen -A | Out-Null
    Write-Ok "Host keys verificadas/generadas"
}
else {
    Write-Warn "No se encontró ssh-keygen.exe. Se continuará, pero sshd podría fallar si no existen host keys."
}

# ============================================================
# 5. Configurar administrators_authorized_keys
# ============================================================

Write-Step "Configurando administrators_authorized_keys"

Set-Content -Path $AdminKeys -Value $PublicKey -Encoding ascii -Force
Set-StrictAclForAdminKeys -Path $AdminKeys

Write-Ok "Llave pública instalada en: $AdminKeys"
Write-Ok "Permisos estrictos aplicados a administrators_authorized_keys"

# ============================================================
# 6. Opcional: configurar authorized_keys para el usuario
# ============================================================

if ($AlsoConfigureUserAuthorizedKeys) {
    Write-Step "Configurando authorized_keys del usuario"

    if ([string]::IsNullOrWhiteSpace($TargetUserProfile) -or -not (Test-Path $TargetUserProfile)) {
        throw "No existe el perfil del usuario: $TargetUserProfile"
    }

    $UserSshDir = Join-Path $TargetUserProfile ".ssh"
    $UserKeys   = Join-Path $UserSshDir "authorized_keys"

    Ensure-Directory -Path $UserSshDir

    Set-Content -Path $UserKeys -Value $PublicKey -Encoding ascii -Force
    Set-StrictAclForUserKeys -Path $UserKeys -UserName $TargetUser

    Write-Ok "Llave pública instalada en: $UserKeys"
    Write-Ok "Permisos estrictos aplicados a authorized_keys del usuario"
}

# ============================================================
# 7. Configurar sshd_config sin destruirlo
# ============================================================

$BackupCreated = Update-SshdConfigConservatively `
    -SshdConfigPath $SshdConfig `
    -SshdExePath $SshdExe `
    -Port $Port `
    -PasswordFallback ([bool]$AllowPasswordFallbackForFirstRun)

# ============================================================
# 8. Configurar servicio sshd
# ============================================================

Write-Step "Configurando servicio sshd"

$service = Get-Service -Name sshd -ErrorAction SilentlyContinue

if ($null -eq $service) {
    throw "El servicio sshd no existe aunque OpenSSH Server parece instalado."
}

Set-Service -Name sshd -StartupType Automatic

Write-Ok "Servicio sshd configurado como automático"

# ============================================================
# 9. Configurar firewall
# ============================================================

Write-Step "Configurando firewall"

$existingRule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue

if ($null -ne $existingRule) {
    Remove-NetFirewallRule -Name $FirewallRuleName
}

New-NetFirewallRule `
    -Name $FirewallRuleName `
    -DisplayName "OpenSSH Server (sshd)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $Port `
    -RemoteAddress $AllowedRemoteAddress `
    -Action Allow | Out-Null

Write-Ok "Firewall configurado para puerto $Port desde: $($AllowedRemoteAddress -join ', ')"

# ============================================================
# 10. Reiniciar sshd
# ============================================================

Write-Step "Reiniciando sshd"

try {
    Restart-Service -Name sshd -Force -ErrorAction Stop
}
catch {
    Write-Warn "No se pudo reiniciar sshd directamente. Intentando iniciar el servicio..."
    Start-Service -Name sshd -ErrorAction Stop
}

Start-Sleep -Seconds 2

$service = Get-Service -Name sshd

if ($service.Status -ne "Running") {
    throw "El servicio sshd no quedó en estado Running. Estado actual: $($service.Status)"
}

Write-Ok "Servicio sshd ejecutándose"

# ============================================================
# 11. Probar puerto local
# ============================================================

Write-Step "Probando puerto local"

$test = Test-NetConnection -ComputerName "127.0.0.1" -Port $Port -WarningAction SilentlyContinue

if (-not $test.TcpTestSucceeded) {
    throw "sshd está iniciado, pero el puerto $Port no responde localmente."
}

Write-Ok "Puerto $Port responde localmente"

# ============================================================
# 12. Mostrar resumen
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " OpenSSH Server configurado correctamente" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Equipo:" -ForegroundColor Cyan
Write-Host "  $env:COMPUTERNAME"

Write-Host ""
Write-Host "Usuario para conectar:" -ForegroundColor Cyan
Write-Host "  $TargetUser"

Write-Host ""
Write-Host "Puerto SSH:" -ForegroundColor Cyan
Write-Host "  $Port"

Write-Host ""
Write-Host "Firewall permite conexiones desde:" -ForegroundColor Cyan
Write-Host "  $($AllowedRemoteAddress -join ', ')"

Write-Host ""
Write-Host "Backup de sshd_config:" -ForegroundColor Cyan
Write-Host "  $BackupCreated"

Write-Host ""
Write-Host "Archivo de llaves para administradores:" -ForegroundColor Cyan
Write-Host "  $AdminKeys"

if ($AlsoConfigureUserAuthorizedKeys) {
    Write-Host ""
    Write-Host "Archivo de llaves del usuario:" -ForegroundColor Cyan
    Write-Host "  $UserKeys"
}

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
Write-Host "Permisos de administrators_authorized_keys:" -ForegroundColor Cyan
icacls $AdminKeys

Write-Host ""
Write-Host "Servicio sshd:" -ForegroundColor Cyan
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "Para probar desde tu Mac:" -ForegroundColor Green
Write-Host "ssh -vvv -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_rsa $TargetUser@IP_DEL_SERVIDOR -p $Port"

Write-Host ""
Write-Host "Si usaste -AllowPasswordFallbackForFirstRun y la llave ya funciona," -ForegroundColor Yellow
Write-Host "ejecuta nuevamente el script SIN ese parámetro para dejar PasswordAuthentication no." -ForegroundColor Yellow
