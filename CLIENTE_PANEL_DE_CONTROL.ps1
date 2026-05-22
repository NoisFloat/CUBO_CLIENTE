# CLIENTE_PANEL_DE_CONTROL.ps1
# Ejecutar como Administrador

$PublicKey = @"
PEGA_AQUI_TU_LLAVE_PUBLICA
"@

# 1. Instalar OpenSSH Server
$server = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"

if ($server.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

# 2. Iniciar SSH
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# 3. Carpeta .ssh del usuario actual
$sshDir = "$env:USERPROFILE\.ssh"
$authorizedKeys = "$sshDir\authorized_keys"

if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# 4. Tomar control si ya existía con permisos malos
if (Test-Path $authorizedKeys) {
    takeown /f $authorizedKeys | Out-Null
    icacls $authorizedKeys /reset | Out-Null
    attrib -R $authorizedKeys
}

# 5. Crear/Reescribir authorized_keys
Set-Content -Path $authorizedKeys -Value $PublicKey.Trim() -Encoding ascii -Force

# 6. Permisos de .ssh y authorized_keys
icacls $sshDir /inheritance:r | Out-Null
icacls $sshDir /grant:r "$env:USERNAME:F" | Out-Null
icacls $sshDir /remove "Users" "Authenticated Users" "Everyone" 2>$null | Out-Null

icacls $authorizedKeys /inheritance:r | Out-Null
icacls $authorizedKeys /grant:r "$env:USERNAME:F" | Out-Null
icacls $authorizedKeys /remove "Users" "Authenticated Users" "Everyone" 2>$null | Out-Null

# 7. Configurar sshd_config
$sshdConfig = "C:\ProgramData\ssh\sshd_config"

$config = Get-Content $sshdConfig

$config = $config `
    -replace "^\s*#?\s*PubkeyAuthentication\s+.*", "PubkeyAuthentication yes" `
    -replace "^\s*#?\s*PasswordAuthentication\s+.*", "PasswordAuthentication no" `
    -replace "^\s*#?\s*PermitEmptyPasswords\s+.*", "PermitEmptyPasswords no" `
    -replace "^\s*#?\s*KbdInteractiveAuthentication\s+.*", "KbdInteractiveAuthentication no"

Set-Content $sshdConfig $config -Encoding ascii

if (-not (Select-String -Path $sshdConfig -Pattern "^PubkeyAuthentication yes" -Quiet)) {
    Add-Content $sshdConfig "PubkeyAuthentication yes"
}

if (-not (Select-String -Path $sshdConfig -Pattern "^PasswordAuthentication no" -Quiet)) {
    Add-Content $sshdConfig "PasswordAuthentication no"
}

if (-not (Select-String -Path $sshdConfig -Pattern "^PermitEmptyPasswords no" -Quiet)) {
    Add-Content $sshdConfig "PermitEmptyPasswords no"
}

if (-not (Select-String -Path $sshdConfig -Pattern "^KbdInteractiveAuthentication no" -Quiet)) {
    Add-Content $sshdConfig "KbdInteractiveAuthentication no"
}

# 8. Firewall: permitir SSH solo desde la red local
Get-NetFirewallRule -DisplayName "PanelDeControlCubo SSH" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

New-NetFirewallRule `
    -DisplayName "PanelDeControlCubo SSH" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Action Allow `
    -RemoteAddress LocalSubnet | Out-Null

# 9. Reiniciar SSH
Restart-Service sshd

Write-Host ""
Write-Host "Cliente configurado correctamente."
Write-Host "SSH activo solo desde la red local."
Write-Host "Solo autenticacion por llave publica."
Write-Host "PasswordAuthentication desactivado."
Write-Host "Usuario SSH:"
Write-Host $env:USERNAME
