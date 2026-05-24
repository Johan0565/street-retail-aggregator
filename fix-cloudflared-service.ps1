$ErrorActionPreference = 'Continue'
$log = 'C:\Games\street-retail-aggregator\fix-cloudflared.log'
Start-Transcript -Path $log -Force

Write-Host 'Stopping Cloudflared service'
Stop-Service Cloudflared -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$binPath = '"C:\Program Files (x86)\cloudflared\cloudflared.exe" --config "C:\Users\User\.cloudflared\config.yml" --no-autoupdate tunnel run retail-demo'
Write-Host "Setting ImagePath registry to: $binPath"
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Cloudflared' -Name 'ImagePath' -Value $binPath

Write-Host 'Verifying registry:'
(Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Cloudflared' -Name 'ImagePath').ImagePath

Write-Host 'Starting Cloudflared service'
Start-Service Cloudflared
Start-Sleep -Seconds 10

Write-Host 'Service status:'
Get-Service Cloudflared | Format-List Name, Status, StartType

Write-Host 'Recent event log entries (newest 10):'
Get-EventLog -LogName Application -Source 'Cloudflared' -Newest 10 -ErrorAction SilentlyContinue | Select-Object TimeGenerated, EntryType, @{N='Msg';E={$_.Message.Substring(0,[Math]::Min(300,$_.Message.Length))}} | Format-List

Stop-Transcript
