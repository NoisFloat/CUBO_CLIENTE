function Cargar-ListaDominios($ruta) {
    $set = [System.Collections.Generic.HashSet[string]]::new()

    Get-Content $ruta |
        ForEach-Object { $_.Trim().ToLower() } |
        Where-Object { $_ -ne "" -and $_ -notlike "#*" } |
        ForEach-Object { [void]$set.Add($_) }

    return $set
}

function Dominio-En-Lista($dominio, $lista) {
    $dominio = $dominio.Trim().ToLower()
    return $lista.Contains($dominio)
}

function Crear-Alerta($titulo, $mensaje, $nivel) {
    $pc = $env:COMPUTERNAME

    $payload = @{
        "Titulo" = $titulo
        "Mensaje" = $mensaje
        "PC" = $pc
        "Fecha" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        "Nivel" = $nivel
    } | ConvertTo-Json

    $servidor = "http://10.10.120.217:5000/alerta"
    $token = "someTokenAAKSDMA2ETFK!"

    try {
        Invoke-RestMethod `
            -Uri $servidor `
            -Method Post `
            -Body $payload `
            -ContentType "application/json" `
            -Headers @{ "X-Alert-Token" = $token }

        Write-Host "Alerta enviada: $titulo" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Error enviando alerta: $_" -ForegroundColor Red
    }
}

function Cerrar-NavegadoresWeb {
    $navegadores = @(
        "chrome.exe",
        "msedge.exe",
        "firefox.exe",
        "brave.exe",
        "opera.exe",
        "iexplore.exe"
    )

    foreach ($navegador in $navegadores) {
        & taskkill.exe /F /IM $navegador /T 2>$null | Out-Null
    }
}

$porn    = Cargar-ListaDominios "./porn.txt"
$propio  = Cargar-ListaDominios "./propio.txt"

Write-Host "Listas cargadas:" -ForegroundColor Cyan
Write-Host "Malware: $($malware.Count)"
Write-Host "Propio:  $($propio.Count)"

$tshark = "C:\Program Files\Wireshark\tshark.exe"
$interfaz = "Ethernet"

while ($true) {
    Write-Host "Iniciando tshark en $interfaz..." -ForegroundColor Cyan

    & $tshark -q -i $interfaz -l `
      -a duration:60 `
      -f "tcp port 80 or tcp port 443 or udp port 53 or tcp port 53" `
      -Y "dns.qry.name or http.host or tls.handshake.extensions_server_name" `
      -T fields `
      -e dns.qry.name `
      -e http.host `
      -e tls.handshake.extensions_server_name |
    ForEach-Object {
        $linea = $_.Trim().ToLower()
        

        if ([string]::IsNullOrWhiteSpace($linea)) {
            continue
        }

        $partes = $linea -split "\s+"

        foreach ($dominioDetectado in $partes) {
            $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            if (Dominio-En-Lista $dominioDetectado $porn) {
                Write-Host "[$fecha] PORNO detectado: $dominioDetectado" -ForegroundColor Red
                ipconfig /flushdns
                Crear-Alerta "(PORNO detectado)" $dominioDetectado
                Cerrar-NavegadoresWeb
            }
            elseif (Dominio-En-Lista $dominioDetectado $propio) {
                Write-Host "[$fecha] DOMINIO detectado: $dominioDetectado" -ForegroundColor Green
                ipconfig /flushdns
                Crear-Alerta "(BAN Propio detectado)" $dominioDetectado
                Cerrar-NavegadoresWeb
            }
        }
    }

    Write-Host "Reiniciando tshark..." -ForegroundColor Yellow
}