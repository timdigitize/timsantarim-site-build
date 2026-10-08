# timsantarim.com - otomatik yayin kurulumu (bir kez, yonetici PowerShell ile)
# Kullanim (Kurtarma Konsolu Shift iletmedigi icin Shift'siz yazilir):
#   curl.exe --location raw.githubusercontent.com/timdigitize/timsantarim-site-build/main/ops/install.ps1 --output \ts-install.ps1
#   powershell -executionpolicy bypass -file \ts-install.ps1
# Ne yapar: deploy-site.ps1'i indirir, site kokunu IIS'ten bulur, "Timsan-TimsantarimDeploy" zamanlanmis
# gorevini (SYSTEM, 5 dk) kurar ve deneme calistirmasini DryRun olarak yapar. Gercek ilk yayin icin: deploy-site.ps1 -Force

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Ops = 'C:\ProgramData\TimsanOps\timsantarim-deploy'
$Script = Join-Path $Ops 'deploy-site.ps1'
$Raw = 'https://raw.githubusercontent.com/timdigitize/timsantarim-site-build/main/ops/deploy-site.ps1'

New-Item -ItemType Directory -Force -Path $Ops | Out-Null
Invoke-WebRequest -Uri $Raw -OutFile $Script -UseBasicParsing -Headers @{ 'User-Agent' = 'timsan-site-deploy' }
Write-Host "Indirildi: $Script"

$taskName = 'Timsan-TimsantarimDeploy'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
# timdigitize gorevi ile ayni dakikaya denk gelmesin diye 2,5 dk kaydirilmis baslangic
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(150) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "Zamanlanmis gorev kuruldu: $taskName (her 5 dk)"

Write-Host '--- Deneme calistirma (DryRun, degisiklik yapmaz) ---'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script -Force -DryRun
Write-Host "--- Site koku: $(Get-Content (Join-Path $Ops 'site-root.txt') -ErrorAction SilentlyContinue) ---"
Write-Host 'Gercek ilk yayin icin:'
Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Script`" -Force"
Write-Host "Gunluk: $Ops\deploy.log"
