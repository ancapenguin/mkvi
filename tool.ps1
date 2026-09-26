#Requires -Version 5.1
<#
.SYNOPSIS
    MKVI gelistirme kapisi. Butun dogrulamalari TEK komutta toplar.

.DESCRIPTION
    Bu betik, "hangi sirayi nasil dogrularim" sorusunun yerine gecer. ROADMAP.md'deki
    "tam kapı" kuralinin tek uygulamasi: dort ayri komut tutmak yerine burada sirali
    kosulur ve sonunda tek ozet verilir.

    Bir adim SKIP ise o bilesen depoda henuz yok demektir; FAIL degildir. Yeni bir
    makinede el aleti eksikse kapinin sessizce yesil gecmesi engellenir ama eksik
    bilesen de sorun cikarmaz.

    PowerShell 5.1 Turkce karakterleri dogru okusun diye bu dosyanin BASINDA BOM
    vardir. BOM yalnizca .ps icin kasitlidir; kaynak dosyalarda BOM yazmak derlemeyi
    kirar (bkz. ROADMAP.md calisma kurallari).

.EXAMPLE
    .\tool.ps1 gate      # butun dogrulamalar
    .\tool.ps1 gate -Quick   # yalniz hizli olanlar (tsc, vitest, dart analyze)
    .\tool.ps1 spike     # Hafta 0 probu derlemesi
    .\tool.ps1 version   # surum kaynaklarini karsilastir
    .\tool.ps1 clean     # uretim girdilerini sil
#>
[CmdletBinding()]
param(
    [ValidateSet('gate', 'gate-quick', 'spike', 'version', 'clean', 'help')]
    [string]$Task = 'gate'
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $root

$script:Results = New-Object System.Collections.Generic.List[object]
$script:Failed = 0
$script:Skipped = 0

function Write-Step([string]$Name, [string]$Detail = '') {
    Write-Host ''
    Write-Host "-- $Name" -ForegroundColor Cyan
    if ($Detail) { Write-Host "   $Detail" -ForegroundColor DarkGray }
}

function Add-Result([string]$Name, [string]$State, [string]$Note = '') {
    $script:Results.Add([pscustomobject]@{ Ad = $Name; Durum = $State; Not = $Note })
    switch ($State) {
        'GECTI' { $script:Failed += 0; Write-Host "   [GECTI] $Name" -ForegroundColor Green }
        'ATLANDI' { $script:Skipped++; Write-Host "   [ATLANDI] $Name $Note" -ForegroundColor Yellow }
        default { $script:Failed++; Write-Host "   [KALDI] $Name $Note" -ForegroundColor Red }
    }
}

function Test-Exists([string]$Relative) {
    return (Test-Path (Join-Path $root $Relative))
}

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

<# Bir komutu calistirip sonucu gunceller. Cikti onemliyse $LogDegerine yazilir. #>
function Invoke-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string[]]$Command,
        [int[]]$SuccessCodes = @(0),
        [switch]$CaptureOutput
    )
    Write-Step $Name
    if (-not (Test-Exists $WorkDir)) { Add-Result $Name 'ATLANDI' "(klasor yok: $WorkDir)"; return $null }
    Push-Location (Join-Path $root $WorkDir)
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = & $Command[0] $Command[1..($Command.Length - 1)] 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $previous
        $text = ($output | Out-String)
        if ($SuccessCodes -contains $code) { Add-Result $Name 'GECTI' } else { Add-Result $Name 'KALDI' "(kod $code)"; Write-Host $text }
        if ($CaptureOutput) { return $text } else { return $null }
    } catch {
        Add-Result $Name 'KALDI' $_.Exception.Message
        return $null
    } finally { Pop-Location }
}

function Test-Encoding {
    Write-Step 'Kodlama denetimi (BOM ve mojibake)'
    $roots = @('src', 'app/lib', 'app/test', 'crates', 'cloudflare/src', 'design') |
        Where-Object { Test-Exists $_ }
    if ($roots.Count -eq 0) { Add-Result 'Kodlama denetimi' 'ATLANDI' '(kaynak klasoru yok)'; return }

    # 1) Turkce metin tutan kaynaklarda BOM olmamali. .ps1 disinda istisna yok.
    $bomOffenders = New-Object System.Collections.Generic.List[string]
    # 2) Mojibake izleri: Turkce yazilmis bir dosya bir kez su isaretlerden gecmis demektir.
    $mojibakeOffenders = New-Object System.Collections.Generic.List[string]
    $textExtensions = @('.dart', '.ts', '.tsx', '.rs', '.json', '.jsonc', '.yaml', '.yml', '.toml', '.md', '.css', '.html')

    foreach ($r in $roots) {
        Get-ChildItem -Path (Join-Path $root $r) -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() } |
            ForEach-Object {
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                if ($bytes.Length -lt 3) { return }
                if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                    $bomOffenders.Add($_.FullName.Replace($root + '\', ''))
                }
                # Mojibake kontrolu: dosyayi UTF-8 olarak okuyup bozuk bayt aramak yerine
                # tipik bozukluk desenlerini ariyoruz.
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                if ($text -match 'Ã¶|Ã¼|Ã§|Ã¶|Å\u015f|Ä\u0131|Å°|Ã„|â€™|â€œ|â€') {
                    $mojibakeOffenders.Add($_.FullName.Replace($root + '\', ''))
                }
            }
    }

    if ($bomOffenders.Count -gt 0) {
        Add-Result 'Kodlama: BOM' 'KALDI' ("$($bomOffenders.Count) dosyada BOM: " + ($bomOffenders -join ', '))
    } else { Add-Result 'Kodlama: BOM' 'GECTI' }

    if ($mojibakeOffenders.Count -gt 0) {
        Add-Result 'Kodlama: mojibake' 'KALDI' ("$($mojibakeOffenders.Count) dosyada bozuk metin: " + ($mojibakeOffenders -join ', '))
    } else { Add-Result 'Kodlama: mojibake' 'GECTI' }

    # Ham NUL bayti: git dosyayi binary sayip diffi korl ediyor.
    $nulOffenders = New-Object System.Collections.Generic.List[string]
    foreach ($r in $roots) {
        Get-ChildItem -Path (Join-Path $root $r) -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() } |
            ForEach-Object {
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                for ($i = 0; $i -lt $bytes.Length; $i++) {
                    if ($bytes[$i] -eq 0) { $nulOffenders.Add($_.FullName.Replace($root + '\', '')); break }
                }
            }
    }
    if ($nulOffenders.Count -gt 0) {
        Add-Result 'Kodlama: ham NUL bayti' 'KALDI' ("$($nulOffenders.Count) dosyada: " + ($nulOffenders -join ', '))
    } else { Add-Result 'Kodlama: ham NUL bayti' 'GECTI' }
}

function Show-Summary {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkGray
    $passed = ($script:Results | Where-Object { $_.Durum -eq 'GECTI' }).Count
    if ($script:Failed -eq 0) {
        Write-Host "KAPI YESIL: $passed gecti, $script:Skipped atlandi" -ForegroundColor Green
    } else {
        Write-Host "KAPI KIRMIZI: $passed gecti, $script:Failed kaldi, $script:Skipped atlandi" -ForegroundColor Red
        $script:Results | Where-Object { $_.Durum -eq 'KALDI' } | ForEach-Object {
            Write-Host "  - $($_.Ad) $($_.Not)" -ForegroundColor Red
        }
    }
    Write-Host '============================================================' -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------

switch ($Task) {

    'version' {
        $version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
        Write-Host "VERSION dosyasi: $version" -ForegroundColor Cyan
        $pub = Get-Content (Join-Path $root 'app\pubspec.yaml') -Raw
        if ($pub -match "(?m)^version:\s*([0-9][^\s]*)") { Write-Host "app/pubspec.yaml: $($Matches[1])" }
        $cargo = Get-Content (Join-Path $root 'src-tauri\Cargo.toml') -Raw
        if ($cargo -match '(?m)^version\s*=\s*"([^"]+)"') { Write-Host "src-tauri/Cargo.toml: $($Matches[1])" }
        $conf = Get-Content (Join-Path $root 'src-tauri\tauri.conf.json') -Raw
        if ($conf -match '"version"\s*:\s*"([^"]+)"') { Write-Host "tauri.conf.json: $($Matches[1])" }
        break
    }

    'gate-quick' {
        Write-Host 'HIZLI KAPI (tsc + vitest + flutter analyze)' -ForegroundColor Yellow
        Invoke-Check -Name 'tsc --noEmit' -WorkDir '.' -Command @('npx', 'tsc', '--noEmit')
        Invoke-Check -Name 'vitest (root)' -WorkDir '.' -Command @('npx', 'vitest', 'run')
        if (Test-Exists 'app') {
            Invoke-Check -Name 'flutter analyze (app)' -WorkDir 'app' -Command @('flutter', 'analyze', '--no-pub')
        } else { Add-Result 'flutter analyze (app)' 'ATLANDI' '(app/ yok)' }
        Show-Summary
        break
    }

    'gate' {
        Write-Host ''
        Write-Host 'MKVI KAPI - butun dogrulamalar' -ForegroundColor White
        Write-Host ("Surum: " + (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()) -ForegroundColor DarkGray

        # 1) Web / TypeScript (donmus Tauri hatti)
        Invoke-Check -Name 'tsc --noEmit' -WorkDir '.' -Command @('npx', 'tsc', '--noEmit')
        Invoke-Check -Name 'vitest (root, worker dahil)' -WorkDir '.' -Command @('npx', 'vitest', 'run')

        # 2) Rust cekirdek
        Invoke-Check -Name 'cargo test (src-tauri)' -WorkDir 'src-tauri' -Command @('cargo', 'test', '--locked')
        if (Test-Exists 'crates\mkvi_core') {
            Invoke-Check -Name 'cargo test (mkvi_core)' -WorkDir 'crates\mkvi_core' -Command @('cargo', 'test')
        } else { Add-Result 'cargo test (mkvi_core)' 'ATLANDI' '(crates/mkvi_core yok)' }

        # 3) Sinyalleme sunucusu
        if (Test-Exists 'cloudflare\node_modules') {
            Invoke-Check -Name 'wrangler deploy --dry-run' -WorkDir 'cloudflare' -Command @('npm', 'run', 'check')
        } else { Add-Result 'wrangler deploy --dry-run' 'ATLANDI' '(cloudflare/node_modules yok)' }

        # 4) Flutter uygulamasi
        if (Test-Exists 'app') {
            Invoke-Check -Name 'flutter analyze (app)' -WorkDir 'app' -Command @('flutter', 'analyze', '--no-pub')
            Invoke-Check -Name 'dart test (app)' -WorkDir 'app' -Command @('flutter', 'test')
        } else { Add-Result 'flutter test (app)' 'ATLANDI' '(app/ yok)' }

        # 5) Tasarim sistemi
        if (Test-Exists 'design\pubspec.yaml') {
            Invoke-Check -Name 'dart test (design kontrast)' -WorkDir 'design' -Command @('dart', 'test')
        } else { Add-Result 'dart test (design)' 'ATLANDI' '(design/ yok)' }

        # 6) Kodlama kurallari
        Test-Encoding

        Show-Summary
        break
    }

    'spike' {
        if (-not (Test-Exists 'spike')) { Write-Host 'spike/ klasoru yok.' -ForegroundColor Red; exit 1 }
        Invoke-Check -Name 'spike derlemesi (release)' -WorkDir 'spike' -Command @('flutter', 'build', 'windows', '--release')
        Show-Summary
        break
    }

    'clean' {
        $targets = @('app\build', 'app\.dart_tool', 'spike\build', 'spike\.dart_tool', 'design\.dart_tool', 'dist')
        foreach ($t in $targets) {
            $p = Join-Path $root $t
            if (Test-Path $p) { Remove-Item $p -Recurse -Force; Write-Host "silindi: $t" -ForegroundColor Green }
        }
        Write-Host 'Rust hedefleri silinmedi (yeniden derlemek dakikalar surer).' -ForegroundColor DarkGray
        break
    }

    default {
        Get-Help $MyInvocation.MyCommand
    }
}

if ($script:Failed -gt 0) { exit 1 }
exit 0
