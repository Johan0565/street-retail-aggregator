$ErrorActionPreference = 'Continue'
$log = 'C:\Games\street-retail-aggregator\install-services.log'
Start-Transcript -Path $log -Force

Write-Host '=== STEP 1: Install NSSM ==='
winget install --id NSSM.NSSM --silent --accept-package-agreements --accept-source-agreements --scope machine

$nssm = 'C:\Program Files\WinGet\Packages\NSSM.NSSM_Microsoft.Winget.Source_8wekyb3d8bbwe\nssm-2.24-101-g897c7ad\win64\nssm.exe'
if (-not (Test-Path $nssm)) {
    $nssm = (Get-ChildItem 'C:\Program Files\WinGet\Packages' -Recurse -Filter 'nssm.exe' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*win64*' } | Select-Object -First 1).FullName
}
Write-Host "NSSM at: $nssm"
if (-not $nssm) { Write-Host 'NSSM NOT FOUND - aborting'; Stop-Transcript; exit 1 }

Write-Host '=== STEP 2: Install cloudflared service ==='
& 'C:\Program Files (x86)\cloudflared\cloudflared.exe' --config 'C:\Users\User\.cloudflared\config.yml' service install 2>&1

Write-Host '=== STEP 3: Remove old retail-backend service if exists ==='
& $nssm stop retail-backend 2>&1
& $nssm remove retail-backend confirm 2>&1

Write-Host '=== STEP 4: Install retail-backend via NSSM ==='
$java = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot\bin\java.exe'
$jar = 'C:\Games\street-retail-aggregator\backend\build\libs\backend-0.0.1-SNAPSHOT.jar'
$workdir = 'C:\Games\street-retail-aggregator\backend'
$logDir = 'C:\Games\street-retail-aggregator\backend\logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

& $nssm install retail-backend $java "-jar `"$jar`" --spring.profiles.active=dev"
& $nssm set retail-backend AppDirectory $workdir
& $nssm set retail-backend AppStdout "$logDir\stdout.log"
& $nssm set retail-backend AppStderr "$logDir\stderr.log"
& $nssm set retail-backend AppStopMethodSkip 0
& $nssm set retail-backend AppExit Default Restart
& $nssm set retail-backend Start SERVICE_AUTO_START
& $nssm set retail-backend Description 'Spring Boot backend for Street Retail Aggregator'

Write-Host '=== STEP 5: Start services ==='
Start-Service cloudflared -ErrorAction Continue
& $nssm start retail-backend

Write-Host '=== STEP 6: Service status ==='
Get-Service cloudflared, retail-backend -ErrorAction Continue | Format-Table -AutoSize

Stop-Transcript
Write-Host 'Done. Log:' $log
