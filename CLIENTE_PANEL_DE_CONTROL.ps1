$PublicKey = @
"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNbtAdN1ACSjGghRsH4SwU5Q6/SJA2RR0GktmRbd3UDiA5B2nzX1hDZQgZFbb1xhgzTOJCwJfakDio46mZAxUts/HtMFbIQ8HYDstr2G8qKVnCtyDHfiKCXVohwhfR2sF35rr2gpS0ov5dFGLiuauI7omZMRGTPv1KN5vbWtiJIPVpbeHtVQGByduJ+27uYds6tML1KH+CfIlJeH6MzOLbrlqjc7tCI2KEbmvRjzpJok52rr2Md70hbSnce3spZLCWvqIAI24NqoQH9CMCwQU6DHS8+4OcUfdjj5oEaPVWBFA8Ym19plaGd9eI13qMMSqeJ5/IKU8hg7H2cqtBdFBpAzmJYMabl5iivXVx0bIZUO6oWDAY6PDGqxVL9GlaxLDDTx890VLlGEzKa8VJpVpJWM68jNmIhBMu+wqT5BzQPo5OC1rVrPsNgTIOq1jMYgOVNhlP+Iog+wccKmaybFQcWVEGTnvi4FznLTckVk2mLA9+lIRZBOY0lz7VEnKevkDlSGOt367r7kY5Z9XyC94QtvL/Teg6OHx+Dw3EliVP96/pc0ltg9JHzZSy/d6g5LHnLHSWRcIU+FS2Ig0HAHJm6uBj2h8MgefiCjYJ0GqWLtngBquAGsAl5Uqt89nNvfDC4nJMfehlYYnhQ+Dkx81dqfwx1PfSLkl7OVJEZQhtcQ==
"@.Trim()

$AuthFile = "C:\ProgramData\ssh\administrators_authorized_keys"

# Instalar OpenSSH Server si falta
$capability = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"

if ($capability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name $capability.Name
}

# Activar e iniciar sshd
Set-Service sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

# Abrir firewall para SSH
if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
}

# Verificar que el archivo exista; no lo crea automáticamente
if (-not (Test-Path $AuthFile)) {
    Write-Error "No existe $AuthFile. Revisa si OpenSSH lo generó o créalo manualmente."
    exit 1
}

# Escribir únicamente la clave pública autorizada
Set-Content -Path $AuthFile -Value $PublicKey -Encoding ascii

# Permisos correctos para administrators_authorized_keys
icacls $AuthFile /inheritance:r | Out-Null
icacls $AuthFile /remove:g "Users" "Authenticated Users" "Everyone" 2>$null | Out-Null
icacls $AuthFile /grant "Administrators:F" | Out-Null
icacls $AuthFile /grant "SYSTEM:F" | Out-Null

# Reiniciar SSH
Restart-Service sshd

Write-Host "Listo. Prueba desde tu Mac:"
Write-Host "ssh -i ~/Programming/PanelDeControlCubo/Servicios/id_rsa USUARIO_WINDOWS@IP_DEL_PC"
