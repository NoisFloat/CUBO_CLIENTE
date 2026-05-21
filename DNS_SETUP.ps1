# DNS antimalware y contenido inapropiado, ejecutar como administrador
Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
    Set-DnsClientServerAddress `
        -InterfaceIndex $_.InterfaceIndex `
        -ServerAddresses ("1.1.1.3","1.0.0.3")
}