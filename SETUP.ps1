$taskName = "Analyst"

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument '-c "cd ''C:\Data\Cliente_PowerShell\''; Set-ExecutionPolicy Bypass -Scope Process; ./ANALYST.ps1"'

$bootTrigger = New-ScheduledTaskTrigger -AtStartup
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 72) `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$task = New-ScheduledTask `
    -Action $action `
    -Trigger @($bootTrigger, $logonTrigger) `
    -Principal $principal `
    -Settings $settings

Register-ScheduledTask `
    -TaskName $taskName `
    -InputObject $task