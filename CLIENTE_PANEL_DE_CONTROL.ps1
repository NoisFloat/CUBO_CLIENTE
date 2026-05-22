# CLIENTE_PANEL_DE_CONTROL.ps1
# Ejecutar como Administrador

$PublicKey = @"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNbtAdN1ACSjGghRsH4SwU5Q6/SJA2RR0GktmRbd3UDiA5B2nzX1hDZQgZFbb1xhgzTOJCwJfakDio46mZAxUts/HtMFbIQ8HYDstr2G8qKVnCtyDHfiKCXVohwhfR2sF35rr2gpS0ov5dFGLiuauI7omZMRGTPv1KN5vbWtiJIPVpbeHtVQGByduJ+27uYds6tML1KH+CfIlJeH6MzOLbrlqjc7tCI2KEbmvRjzpJok52rr2Md70hbSnce3spZLCWvqIAI24NqoQH9CMCwQU6DHS8+4OcUfdjj5oEaPVWBFA8Ym19plaGd9eI13qMMSqeJ5/IKU8hg7H2cqtBdFBpAzmJYMabl5iivXVx0bIZUO6oWDAY6PDGqxVL9GlaxLDDTx890VLlGEzKa8VJpVpJWM68jNmIhBMu+wqT5BzQPo5OC1rVrPsNgTIOq1jMYgOVNhlP+Iog+wccKmaybFQcWVEGTnvi4FznLTckVk2mLA9+lIRZBOY0lz7VEnKevkDlSGOt367r7kY5Z9XyC94QtvL/Teg6OHx+Dw3EliVP96/pc0ltg9JHzZSy/d6g5LHnLHSWRcIU+FS2Ig0HAHJm6uBj2h8MgefiCjYJ0GqWLtngBquAGsAl5Uqt89nNvfDC4nJMfehlYYnhQ+Dkx81dqfwx1PfSLkl7OVJEZQhtcQ==
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
