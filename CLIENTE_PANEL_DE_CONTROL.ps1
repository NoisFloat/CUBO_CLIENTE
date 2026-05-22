# CLIENTE_PANEL_DE_CONTROL.ps1
# Ejecutar como Administrador

$PublicKey = @"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNbtAdN1ACSjGghRsH4SwU5Q6/SJA2RR0GktmRbd3UDiA5B2nzX1hDZQgZFbb1xhgzTOJCwJfakDio46mZAxUts/HtMFbIQ8HYDstr2G8qKVnCtyDHfiKCXVohwhfR2sF35rr2gpS0ov5dFGLiuauI7omZMRGTPv1KN5vbWtiJIPVpbeHtVQGByduJ+27uYds6tML1KH+CfIlJeH6MzOLbrlqjc7tCI2KEbmvRjzpJok52rr2Md70hbSnce3spZLCWvqIAI24NqoQH9CMCwQU6DHS8+4OcUfdjj5oEaPVWBFA8Ym19plaGd9eI13qMMSqeJ5/IKU8hg7H2cqtBdFBpAzmJYMabl5iivXVx0bIZUO6oWDAY6PDGqxVLlGEzKa8VJpVpJWM68jNmIhBMu+wqT5BzQPo5OC1rVrPsNgTIOq1jMYgOVNhlP+Iog+wccKmaybFQcWVEGTnvi4FznLTckVk2mLA9+lIRZBOY0lz7VEnKevkDlSGOt367r7kY5Z9XyC94QtvL/Teg6OHx+Dw3EliVP96/pc0ltg9JHzZSy/d6g5LHnLHSWRcIU+FS2Ig0HAHJm6uBj2h8MgefiCjYJ0GqWLtngBquAGsAl5Uqt89nNvfDC4nJMfehlYYnhQ+Dkx81dqfwx1PfSLkl7OVJEZQhtcQ==
"@.Trim()

# Validar administrador
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

# Instalar OpenSSH Server si falta
$Capability = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"

if ($Capability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

# Activar SSH
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

# Rutas
$SshDir = "C:\ProgramData\ssh"
$AdminKeys = "$SshDir\administrators_authorized_keys"

# Crear directorio y archivo necesarios
New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
Set-Content -Path $AdminKeys -Value $PublicKey -Encoding ascii

# Permisos requeridos por Windows OpenSSH
icacls $AdminKeys /inheritance:r | Out-Null
icacls $AdminKeys /grant:r "Administrators:F" | Out-Null
icacls $AdminKeys /grant:r "SYSTEM:F" | Out-Null

# Firewall puerto 22
if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow | Out-Null
}

Restart-Service sshd

Write-Host ""
Write-Host "SSH configurado correctamente." -ForegroundColor Green
Write-Host "Usuario Windows actual:"
Write-Host $env:USERNAME
Write-Host ""
Write-Host "Desde tu Mac prueba:"
Write-Host "ssh -o IdentitiesOnly=yes -i ~/Programming/PanelDeControlCubo/Servicios/id_rsa $env:USERNAME@IP_DEL_PC"
