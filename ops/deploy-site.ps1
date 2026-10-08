# timsantarim.com - otomatik yayin (sunucu tarafi)
# GitHub'daki timsantarim-site-build deposunun son halini indirir ve IIS site kokune kopyalar.
# Calistiran: zamanlanmis gorev "Timsan-TimsantarimDeploy" (SYSTEM, 5 dakikada bir). Elle: powershell -File deploy-site.ps1 [-Force] [-DryRun]
# Site koku IIS'ten (timsantarim.com baglantisi olan site) bulunur ve site-root.txt'ye yazilir; elle de duzeltilebilir.
param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo      = 'timdigitize/timsantarim-site-build'
$Branch    = 'main'
$Domain    = 'timsantarim.com'
$Ops       = 'C:\ProgramData\TimsanOps\timsantarim-deploy'
$StateFile = Join-Path $Ops 'current-sha.txt'
$RootFile  = Join-Path $Ops 'site-root.txt'
$LogFile   = Join-Path $Ops 'deploy.log'
$BackupDir = Join-Path $Ops 'backup'
$HealthUrl = 'https://timsantarim.com/'
# Sunucuya ozel, depoda olmayan klasorler: asla dokunulmaz
$KeepDirs  = @('App_Data', '.well-known', 'aspnet_client')

New-Item -ItemType Directory -Force -Path $Ops, $BackupDir | Out-Null

function Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-SiteRoot {
    if (Test-Path $RootFile) { return (Get-Content $RootFile -Raw).Trim() }
    Import-Module WebAdministration
    $sites = @(Get-Website | Where-Object { ($_.bindings.Collection | ForEach-Object { $_.bindingInformation }) -match [regex]::Escape($Domain) })
    if ($sites.Count -ne 1) {
        $all = (Get-Website | ForEach-Object { "$($_.name) -> $($_.physicalPath)" }) -join '; '
        throw "IIS'te $Domain icin tek site bulunamadi ($($sites.Count)). Siteler: $all. Dogru yolu $RootFile dosyasina yazin."
    }
    $root = [Environment]::ExpandEnvironmentVariables($sites[0].physicalPath).TrimEnd('\')
    Set-Content -Path $RootFile -Value $root -Encoding ASCII
    Log "Site koku IIS'ten bulundu: $($sites[0].name) -> $root"
    return $root
}

# Site kokunun icinde duran baska IIS sitelerinin klasorleri (ornegin timdigitize-site): kopyalama/yedek disinda tutulur
function Get-NestedSiteDirs($root) {
    try {
        Import-Module WebAdministration
        Get-Website | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_.physicalPath).TrimEnd('\') } |
            Where-Object { $_ -and $_ -ne $root -and $_.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) }
    } catch { @() }
}

try {
    $headers = @{ 'User-Agent' = 'timsan-site-deploy'; 'Accept' = 'application/vnd.github+json' }
    $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits/$Branch" -Headers $headers -TimeoutSec 30
    $sha = $commit.sha
    $current = if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { '' }

    if (-not $Force -and $sha -eq $current) {
        # Degisiklik yok; sessizce cik (log sisirmemek icin yazmiyoruz)
        exit 0
    }
    Log "Yeni surum: $sha (mevcut: $(if ($current) { $current } else { 'yok' }))"

    $SiteRoot = Get-SiteRoot
    if (-not (Test-Path (Join-Path $SiteRoot 'index.html'))) { throw "Site kokunde index.html yok: $SiteRoot - yol yanlis olabilir, $RootFile dosyasini kontrol edin" }
    $nested = @(Get-NestedSiteDirs $SiteRoot)
    $exclude = $KeepDirs + $nested
    Log "Site koku: $SiteRoot$(if ($nested) { ' | haric: ' + ($nested -join ', ') })"

    # Betik kendini gunceller (bir sonraki calismada devreye girer)
    try {
        $selfUrl = "https://raw.githubusercontent.com/$Repo/$Branch/ops/deploy-site.ps1"
        $latest = (Invoke-WebRequest -Uri $selfUrl -UseBasicParsing -Headers $headers -TimeoutSec 30).Content
        $mine = Get-Content $PSCommandPath -Raw
        if ($latest -and $latest.Length -gt 1000 -and $latest.Trim() -ne $mine.Trim()) {
            [IO.File]::WriteAllText($PSCommandPath, $latest, (New-Object Text.UTF8Encoding $false))
            Log 'deploy-site.ps1 guncellendi (yeni surum bir sonraki calismada gecerli)'
        }
    } catch { Log "Betik guncelleme atlandi: $($_.Exception.Message)" }

    # Calisma klasoru: sha + zaman damgasi (ayni surum icin es zamanli iki calisma cakismasin)
    Get-ChildItem $Ops -Directory -Filter 'work-*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-2) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $work = Join-Path $Ops ('work-' + $sha.Substring(0, 7) + '-' + (Get-Date -Format 'HHmmss') + '-' + $PID)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $zip = Join-Path $work 'site.zip'

    Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/zip/refs/heads/$Branch" -OutFile $zip -Headers @{ 'User-Agent' = 'timsan-site-deploy' } -TimeoutSec 300
    Expand-Archive -Path $zip -DestinationPath $work -Force
    $src = Get-ChildItem -Path $work -Directory | Where-Object { $_.Name -like 'timsantarim-site-build-*' } | Select-Object -First 1
    if (-not $src) { throw 'Zip icinde site klasoru bulunamadi' }
    $srcPath = $src.FullName

    # Guvenlik kontrolleri: bos veya yarim derleme yayinlanmasin
    foreach ($must in @('index.html', 'web.config', 'en\index.html', 'urunler\index.html', 'sitemap.xml', 'VERSION.txt')) {
        if (-not (Test-Path (Join-Path $srcPath $must))) { throw "Eksik dosya: $must - yayin iptal" }
    }
    $pageCount = (Get-ChildItem -Path $srcPath -Recurse -Filter index.html).Count
    if ($pageCount -lt 400) { throw "Sayfa sayisi supheli dusuk ($pageCount) - yayin iptal" }
    # Depo icindeki ops/ ve README sunucuya kopyalanmaz
    Remove-Item (Join-Path $srcPath 'ops') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $srcPath 'README.md') -Force -ErrorAction SilentlyContinue

    # Mevcut canlinin yedegi (son 5 yedek tutulur; ic ice duran diger siteler haric)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $BackupDir $stamp
    if (-not $DryRun) {
        $bkArgs = @($SiteRoot, $backup, '/MIR', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
        if ($nested) { $bkArgs += @('/XD') + $nested }
        robocopy @bkArgs | Out-Null
        Get-ChildItem $BackupDir -Directory | Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Kopyalama: robocopy /E (yeni ve degisen dosyalar yazilir, sunucudaki fazla dosyalar SILINMEZ;
    # eski siteden kalan dosyalar ve sunucuya ozel klasorler korunur)
    $rcArgs = @($srcPath, $SiteRoot, '/E', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NP', '/XD') + $exclude
    if ($DryRun) { $rcArgs += '/L' }
    $out = & robocopy @rcArgs
    $rc = $LASTEXITCODE
    Log ("robocopy cikis kodu {0}{1}" -f $rc, $(if ($DryRun) { ' (DryRun)' } else { '' }))
    if ($rc -ge 8) { throw "robocopy hatasi ($rc)" }

    if ($DryRun) { $out | Select-Object -Last 12 | ForEach-Object { Write-Host $_ }; Log 'DryRun bitti, degisiklik yapilmadi'; exit 0 }

    # Saglik kontrolu; basarisizsa yedege don
    Start-Sleep -Seconds 3
    try {
        $resp = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 30 -Headers @{ 'Cache-Control' = 'no-cache' }
        if ($resp.StatusCode -ne 200 -or $resp.Content.Length -lt 5000) { throw "Beklenmeyen yanit: $($resp.StatusCode) / $($resp.Content.Length) bayt" }
        Log "Saglik kontrolu OK ($($resp.StatusCode), $($resp.Content.Length) bayt)"
    } catch {
        Log "SAGLIK KONTROLU BASARISIZ: $($_.Exception.Message) - yedege donuluyor"
        robocopy $backup $SiteRoot /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD $exclude | Out-Null
        throw 'Geri alindi'
    }

    Set-Content -Path $StateFile -Value $sha -Encoding ASCII
    $ver = Get-Content (Join-Path $srcPath 'VERSION.txt') -Raw
    Log ("YAYINLANDI {0} | {1}" -f $sha.Substring(0, 7), ($ver -replace "`r?`n", ' '))
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
catch {
    Log "HATA: $($_.Exception.Message)"
    exit 1
}
