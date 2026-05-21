# CUBO-OPTIMIZER-MANUAL.ps1
# Seguro: solo pone en Manual servicios no esenciales.

$serviciosManual = @(
    # HDD al 100%
    # SysMain se encarga de disque mejorar precargando programas en ram
    # Preciso en ambientes donde se tiene mas en abundancia la ram o se tiene ssd"
    # Precarga apps, segun comportamiento no valido en computadoras compartidas
    "SysMain",
    # Este proporciona contenido indexado prepcargado (catching) para mostrar busquedas
    # Contenido y otro lo que implica lectura/escritura (uso de disco)
    "WSearch",

    # Impresoras
    
    # Uso de cola de impresión, (no se dispone impresoras conectadas al cubo pcs)
    "Spooler",
    # Manejo de notificaciones / Impresoras remotas (Ya se encuentra manual)
    "PrintNotify", 
    # Proporciona seguridad en el proceso de trabajos de impresión (Ya se encuentra manual)
    "PrintScanBrokerService",


    # Xbox / gaming
    # Servicios vinculados a videojuegos, suelen estar apagados por defecto
    # "XblAuthManager",
    # "XblGameSave",
    # "XboxGipSvc",
    # "XboxNetApiSvc",
    # Servicio para el manejo de drivers al conectar controles
    # "GameInputSvc",

    # Telemetría / ubicación / mapas
    # Envio de datos a windows para solo ellos saben que
    "DiagTrack",
    # Uso de GPS, ya que no suele moverse la pc, no lo miro viable
    # Ademas que dependen de energía externa y no tienen cuenta institucional
    "lfsvc",
    # Administrador de mapas descargados 
    "MapsBroker",


    # Teléfono / móvil
    # Servicio telefonico / no terminal / no VoIP
    "PhoneSvc",
    # Hora a partir de telefonia movil
    "autotimesvc",

    # Multimedia / UPnP
    # Uso compartido de multimedia
    "WMPNetworkSvc",

    # Escritorio remoto / acceso remoto
    # "TermService", # Desactivado por defecto
    # "SessionEnv", # Desactivado por defecto

    # No hay personal tecnico para revisar - Error Reporting Windows
    "WerSvc"
)

foreach ($servicio in $serviciosManual) {

    $existe = Get-Service -Name $servicio -ErrorAction SilentlyContinue

    if ($existe) {
        Write-Host "Configurando en Manual: $servicio"

        try {
            Set-Service -Name $servicio -StartupType Manual
        }
        catch {
            Write-Warning "No se pudo cambiar: $servicio"
        }
    }
    else {
        Write-Host "No existe en este sistema: $servicio"
    }
}

Write-Host "`nListo. Reinicia el equipo."

# TO DO: Desisntalar programas inutiles como DeviceHost
# Feedback Hub
# Phone Link - Mobile Devices

Get-AppxPackage Microsoft.YourPhone -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage Microsoft.WindowsFeedbackHub -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage Microsoft.Copilot -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue


#Adobe, Visual Studio, Halo, iTunes, Java, WPS (OFFICE trucho),