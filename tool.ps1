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
    .\tool.ps1 gate-quick   # yalniz hizli olanlar (analyze)
    .\tool.ps1 build     # uygulamanin release derlemesi
    .\tool.ps1 version   # surum kaynaklarini karsilastir
    .\tool.ps1 clean     # uretim girdilerini sil
#>
[CmdletBinding()]
param(
    [ValidateSet('gate', 'gate-quick', 'build', 'version', 'docs', 'clean', 'resources', 'help')]
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
    # 2026-09-26: `src/` 0.1.x Tauri hattiyle birlikte silindi ve yerine
    # `app/lib` geldi. `cloudflare/src` Worker icindir ve kaliyor.
    #
    # 2026-09-26 (ayni gun, ikinci duzeltme): kok `.md` dosyalari KAPSAM DIYDI.
    # Yani README, SECURITY, CONTRIBUTING, THIRD-PARTY-NOTICES, NOTICE ve
    # ARCHITECTURE bu denetimden gecmiyordu - oysa Turkce metnin en yogun
    # oldugu dosyalar tam olarak bunlar. Bir kapi, denetledigi seyi yazmazsa
    # denetlemiyor demektir.
    $roots = @('app/lib', 'app/test', 'app/windows', 'crates', 'cloudflare/src', 'design', 'docs') |
        Where-Object { Test-Exists $_ }
    $rootDocs = @(
        'README.md', 'SECURITY.md', 'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md',
        'THIRD-PARTY-NOTICES.md', 'NOTICE', 'ARCHITECTURE.md', 'ROADMAP.md',
        'AGENTS.md', 'CLAUDE.md', 'VERSION'
    ) | Where-Object { Test-Path (Join-Path $root $_) }

    if ($roots.Count -eq 0 -and $rootDocs.Count -eq 0) {
        Add-Result 'Kodlama denetimi' 'ATLANDI' '(kaynak klasoru yok)'
        return
    }

    # 1) Turkce metin tutan kaynaklarda BOM olmamali. .ps1 disinda istisna yok.
    $bomOffenders = New-Object System.Collections.Generic.List[string]
    # 2) Mojibake izleri: Turkce yazilmis bir dosya bir kez su isaretlerden gecmis demektir.
    $mojibakeOffenders = New-Object System.Collections.Generic.List[string]
    $textExtensions = @('.dart', '.ts', '.tsx', '.rs', '.json', '.jsonc', '.yaml', '.yml', '.toml', '.md', '.css', '.html')

    # Denetlenecek dosyalar: once dizinler, sonra kok dosyalar. Ikisi de ayni
    # kurallardan gecer; ayri bir dongu yazmamak, iki yerde farkli kural
    # birakmaktan iyidir.
    $filesToCheck = New-Object System.Collections.Generic.List[string]
    foreach ($r in $roots) {
        Get-ChildItem -Path (Join-Path $root $r) -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() } |
            ForEach-Object { $filesToCheck.Add($_.FullName) }
    }
    foreach ($d in $rootDocs) { $filesToCheck.Add((Join-Path $root $d)) }

    foreach ($f in $filesToCheck) {
        if (-not (Test-Path $f)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($f)
        if ($bytes.Length -lt 3) { continue }
        if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bomOffenders.Add($f.Replace($root + '\', ''))
        }
        # Mojibake kontrolu: dosyayi UTF-8 olarak okuyup bozuk bayt aramak yerine
        # tipik bozukluk desenlerini ariyoruz.
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match 'Ã¶|Ã¼|Ã§|Ã¶|Å\u015f|Ä\u0131|Å°|Ã„|â€™|â€œ|â€') {
            $mojibakeOffenders.Add($f.Replace($root + '\', ''))
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
    foreach ($f in $filesToCheck) {
        if (-not (Test-Path $f)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($f)
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 0) { $nulOffenders.Add($f.Replace($root + '\', '')); break }
        }
    }
    if ($nulOffenders.Count -gt 0) {
        Add-Result 'Kodlama: ham NUL bayti' 'KALDI' ("$($nulOffenders.Count) dosyada: " + ($nulOffenders -join ', '))
    } else { Add-Result 'Kodlama: ham NUL bayti' 'GECTI' }
}

function Test-Resources {
    <#
        Derleme kapiyi calistirmadan once kaynaklari olcer. Bu proje ayni anda birden
        fazla agir is yurutebilir (cargo + flutter + vitest + ajanlar). 32 GB RAM'li
        bir makinede hepsi ayni anda kostugunda swap veya OOM kapıyı yanlis yere
        kirmizi yapar; yani "kaynak yetersiz" ile "kod bozuk" birbirine karisir.
        O yuzden once olcer, sonra uyarir.
    #>
    Write-Step 'Sistem kaynaklari'
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $os -or -not $cpu) { Add-Result 'Sistem kaynaklari' 'ATLANDI' '(WMI okunamadi)'; return }

    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $freePct = if ($totalGB -gt 0) { [math]::Round($freeGB / $totalGB * 100) } else { 0 }
    $load = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
    $cores = $cpu.NumberOfLogicalProcessors
    $diskFree = [math]::Round((Get-PSDrive C).Free / 1GB, 1)

    Write-Host "   RAM $freeGB / $totalGB GB bos ($freePct%) · CPU yukü $load% ($cores cekirdek) · C: $diskFree GB bos" -ForegroundColor DarkGray

    # En yogun uc surec: derleme sirasinda neyin kaynak yedigini gormek icin.
    Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 3 |
        ForEach-Object { Write-Host ("   {0,-18} {1,6} MB" -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB)) -ForegroundColor DarkGray }

    $problems = @()
    if ($freeGB -lt 4) { $problems += "RAM yetersiz ($freeGB GB)" }
    if ($freePct -lt 15) { $problems += "RAM dolu ($freePct%)" }
    if ($load -ge 90) { $problems += "CPU yukü $load%" }
    if ($diskFree -lt 10) { $problems += "disk az ($diskFree GB)" }

    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Host "   ! KAYNAK UYARISI: $($problems -join '; ')" -ForegroundColor Yellow
        Write-Host '   ! Bu bir KOD hatasi degil. Asagidaki KALDI satirlari kaynak yetersizliginden' -ForegroundColor Yellow
        Write-Host '   ! kaynaklanmis olabilir. Once arka plandaki derlemeleri bitir, sonra tekrar calistir.' -ForegroundColor Yellow
        if ($env:MKVI_STRICT_RESOURCES -eq '1') {
            Add-Result 'Sistem kaynaklari' 'KALDI' ($problems -join '; ')
            return $false
        }
        Add-Result 'Sistem kaynaklari' 'GECTI' ("UYARI: " + ($problems -join '; '))
        return $true
    }
    Add-Result 'Sistem kaynaklari' 'GECTI' ("RAM $freeGB GB · CPU $load%")
    return $true
}

function Test-VersionConsistency {
    <#
        Surumun kaynaklarini okur ve KARSILASTIRIR; ayrisma varsa KALDI doner.

        Neden bu bir yazdirma degil de bir kapi: 2026-09-26'da olculdu. VERSION
        0.2.0, app/pubspec.yaml 0.2.0+1 idi ama src-tauri/Cargo.toml,
        tauri.conf.json, package.json ve iki crate 0.1.4'te kalmisti.
        `publish-update.yml` surumu `tauri.conf.json`'dan okuyor, yani `v0.2.0`
        etiketiyle tetiklense bile besleme 0.1.4 yayinliyordu. Ustelik Flutter
        istemcisi `UpdateConfig.currentVersion` 0.2.0 oldugu icin 0.1.4
        beslemesini "daha yeni degil" sayiyordu: dogru yayinlansa bile 0.2.0
        istemcisi guncellenmeyi hic gormezdi.

        `app/pubspec.yaml` yorumu "CI ikisinin eslestigini dogrular" diyordu;
        boyle bir adim ne CI'da ne de tool.ps1'de vardi.

        IKI GRUP, FARKLI KURALLAR (2026-09-26'da TEK GRUBA INDIRILDI):

        Once iki grup vardi. CANLI (karsilastirilir): VERSION,
        app/pubspec.yaml, iki crate. DONMUS (yazdirilir, karsilastirilmaz):
        src-tauri/Cargo.toml, tauri.conf.json, package.json - 0.1.x Tauri
        hatti, Faz 8'de silinecekti.

        **0.1.x hatti 2026-09-26'da emekliye ayrildi ve silindi.** Kullanici
        karari: geriye donuk uyumluluk, migration ve eski istemcilerin otomatik
        guncellenmesi gerekmiyor; iki kullanicinin ikisi de yeni surumu elle
        kuracak. Bu yuzden "donmus" grup kalmadi ve karsilastirma tek gruba
        indi.

        Neden o zaman iki grupti, cunku donmus hatta 0.1.4 DOGRU bir bilgiydi:
        kapida sayilmasaydi kapi surekli kirmizi kalir ve kirmizi bir kapi
        bakimsiz bir kapiye donusur. Simdi o tuzak yok.
    #>
    Write-Step 'Surum kaynaklari'
    $live = [ordered]@{}

    if (Test-Exists 'VERSION') { $live['VERSION'] = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim() }

    $pub = Get-Content (Join-Path $root 'app\pubspec.yaml') -Raw
    if ($pub -match "(?m)^version:\s*([0-9][^\s]*)") {
        # `0.2.0+1` -> `0.2.0`: build metasi surumun parcasi degil.
        $live['app/pubspec.yaml'] = ($Matches[1] -split '\+')[0]
    }
    foreach ($toml in @('crates\mkvi_core\Cargo.toml', 'crates\mkvi_bridge\Cargo.toml')) {
        if (Test-Exists $toml) {
            $text = Get-Content (Join-Path $root $toml) -Raw
            if ($text -match '(?m)^version\s*=\s*"([^"]+)"') {
                $live[($toml -replace '\\', '/')] = $Matches[1]
            }
        }
    }
    # 2026-09-26: bu kaynak 2026-09-26'da kapiya eklendi. Dart tarafi 0.1.4'te
    # kalmisti ve Rust tarafi 0.2.0'a gecmisken kapi yesildi - yani ayrilma
    # olmadigi halde kapi gormuyordu. Kapi, gormedigi seyi yazmaz.
    $bridgeDart = 'crates\mkvi_bridge\dart\pubspec.yaml'
    if (Test-Exists $bridgeDart) {
        $text = Get-Content (Join-Path $root $bridgeDart) -Raw
        if ($text -match '(?m)^version:\s*([0-9][^\s]*)') {
            $live['crates/mkvi_bridge/dart/pubspec.yaml'] = ($Matches[1] -split '\+')[0]
        }
    }
    # 0.1.x Tauri hatti 2026-09-26'da emekliye ayrildi ve silindi; artik
    # karsilastirilacak donmus bir grup yok. CANLI grup tek gruptur.

    $baseline = $null
    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $live.GetEnumerator()) {
        if ($null -eq $baseline) { $baseline = $entry.Value }
        $same = ($entry.Value -eq $baseline)
        $colour = if ($same) { 'DarkGray' } else { 'Red' }
        Write-Host ("   {0,-46} {1}" -f $entry.Key, $entry.Value) -ForegroundColor $colour
        if (-not $same) { $mismatches.Add("$($entry.Key) = $($entry.Value)") }
    }
    # Yayin harti etiketten okur; etiket ile dosya ayrisma durumunda yayin
    # yanlis surumle baslar ve bu sessizce olur. Bu yuzden yaziliyor.
    $tag = $env:GITHUB_REF_NAME
    if ($tag -and $tag -match '^v?(\d+\.\d+\.\d+)' -and $baseline -ne $Matches[1]) {
        Write-Host ("   ETIKET v$($Matches[1]), dosya surumu $baseline -> yayin yanlis surumle baslar") -ForegroundColor Red
    }

    if ($mismatches.Count -gt 0) {
        Add-Result 'Surum tutarliligi' 'KALDI' ("$($mismatches.Count) kaynak ayri (referans $baseline): " + ($mismatches -join ', '))
    } else {
        Add-Result 'Surum tutarliligi' 'GECTI' "hepsi $baseline"
    }
}

function Sync-ClaudeMirror {
    <#
        CLAUDE.md, AGENTS.md'nin TURETI. Elle yazilmaz; buradan uretilir.

        Neden bir ture araci, iki dosyayi elle esitlemek degil:

        Iki yazili kaynak bir gun ayrisir ve ayrisma SESSIZ olur. 0.1.x
        doneminde tam olarak bu oldu: `CLAUDE.md` `.gitignore`'daydi, yani git
        izlemiyordu ve public depoya hic girmeyecekti. Dosya oradaydi, ama kimse
        - katilimci da dahil - onu goremeyecekti. Iki yazili kaynagin
        ayrilmasi bir tesaduf degil, bir zaman meselesidir.

        Bu yuzden: tek yazili kaynak (AGENTS.md) + turet (CLAUDE.md).
        Arac ayrilmasi bir gunde degil, her kapida yakalar.

        Cikti BOM'SUZ yazilir. Kaynak da BOM'suz; bir turet BOM tasimamali.
        Satir sonu CRLF: PowerShell 5.1'in Turkce okumasi icin.
    #>
    Write-Step 'CLAUDE.md aynasi (AGENTS.md -> CLAUDE.md)'

    if (-not (Test-Exists 'AGENTS.md')) {
        Add-Result 'CLAUDE.md aynasi' 'KALDI' 'AGENTS.md yok; kaynak dosya bulunamadi'
        return
    }

    $banner = @(
        '<!-- GENERATED FILE - DO NOT EDIT. Source of truth: AGENTS.md -->',
        '<!-- Regenerate with: .\tool.ps1 docs -->',
        ''
    ) -join "`r`n"

    $source = [System.IO.File]::ReadAllText((Join-Path $root 'AGENTS.md'))
    $generated = $banner + $source

    $target = Join-Path $root 'CLAUDE.md'
    $current = if (Test-Exists 'CLAUDE.md') {
        [System.IO.File]::ReadAllText($target)
    } else { '' }

    if ($current -ne $generated) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($target, $generated, $utf8)
        Add-Result 'CLAUDE.md aynasi' 'GECTI' 'yeniden uretildi (AGENTS.md degismis)'
    } else {
        Add-Result 'CLAUDE.md aynasi' 'GECTI' 'guncel'
    }
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
        Test-VersionConsistency
        Show-Summary
        break
    }

    'gate-quick' {
        Write-Host 'HIZLI KAPI (flutter analyze + dart analyze design)' -ForegroundColor Yellow
        if (Test-Exists 'app') {
            Invoke-Check -Name 'flutter analyze (app)' -WorkDir 'app' -Command @('flutter', 'analyze', '--no-pub')
        } else { Add-Result 'flutter analyze (app)' 'ATLANDI' '(app/ yok)' }
        if (Test-Exists 'design\pubspec.yaml') {
            Invoke-Check -Name 'dart analyze (design)' -WorkDir 'design' -Command @('dart', 'analyze')
        }
        Show-Summary
        break
    }

    'gate' {
        Write-Host ''
        Write-Host 'MKVI KAPI - butun dogrulamalar' -ForegroundColor White
        Write-Host ("Surum: " + (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()) -ForegroundColor DarkGray

        # Kaynak olcumu once yapilir: yetersiz RAM/CPU altinda bir derlemenin
        # kirmizi cikmasi kod hatasi degildir ve yanlis teşhis edilir.
        if (-not (Test-Resources)) { Show-Summary; break }

        # 0) Surum tutarliligi. Yayin harti etiketten okur; dosya surumu ile
        #    etiket ayrisma durumunda yayin yanlis surumle basar. Once olcum,
        #    sonra derleme.
        Test-VersionConsistency

        # 0b) CLAUDE.md aynasi. Kapinin bir parcasi cunku bayat bir kilavuz
        #     hicbir seyi yazmaz: 0.1.x'te `.gitignore`'da oldugu icin public
        #     depoya hic girmiyordu. Burada URETILIR - biri elle
        #     AGENTS.md'yi degistirdiginde fark bir sonraki kapida yakalanir.
        Sync-ClaudeMirror

        # 1) Rust cekirdek. 0.1.x Tauri hatti silindigi icin `src-tauri` artik
        #    yok ve kapi onu kosmuyor.
        if (Test-Exists 'crates\mkvi_core') {
            Invoke-Check -Name 'cargo test (mkvi_core)' -WorkDir 'crates\mkvi_core' -Command @('cargo', 'test', '--locked')
        } else { Add-Result 'cargo test (mkvi_core)' 'ATLANDI' '(crates/mkvi_core yok)' }
        # mkvi_bridge 15 testini 2026-09-26'ya kadar hicbir yer kosmuyordu: ne
        # tool.ps1 ne ci.yml. Kapida olmamak "yesil" demek degil, hic olculmemek
        # demek; bu yuzden burada.
        if (Test-Exists 'crates\mkvi_bridge') {
            Invoke-Check -Name 'cargo test (mkvi_bridge)' -WorkDir 'crates\mkvi_bridge' -Command @('cargo', 'test')
        } else { Add-Result 'cargo test (mkvi_bridge)' 'ATLANDI' '(crates/mkvi_bridge yok)' }

        # 2) Sinyalleme sunucusu (Cloudflare Worker). Yalniz Worker TypeScript'i
        #    kaldi; kok `package.json` ve `vitest` 0.1.x ile birlikte silindi.
        if (Test-Exists 'cloudflare\node_modules') {
            Invoke-Check -Name 'wrangler deploy --dry-run' -WorkDir 'cloudflare' -Command @('npm', 'run', 'check')
            Invoke-Check -Name 'vitest (worker)' -WorkDir 'cloudflare' -Command @('npx', 'vitest', 'run')
        } else { Add-Result 'wrangler deploy --dry-run' 'ATLANDI' '(cloudflare/node_modules yok)' }

        # 3) Tasarim sistemi. `design/` bilincli olarak Flutter'siz saf Dart
        #    paketidir; kontrast kapisi Flutter arac zincirine ihtiyac duymaz.
        if (Test-Exists 'design\pubspec.yaml') {
            Invoke-Check -Name 'dart analyze (design)' -WorkDir 'design' -Command @('dart', 'analyze')
            Invoke-Check -Name 'dart test (design kontrast)' -WorkDir 'design' -Command @('dart', 'test')
        } else { Add-Result 'dart test (design)' 'ATLANDI' '(design/ yok)' }

        # 4) Flutter uygulamasi
        if (Test-Exists 'app') {
            Invoke-Check -Name 'flutter analyze (app)' -WorkDir 'app' -Command @('flutter', 'analyze', '--no-pub')
            # `flutter test`, not `dart test`: the app is a Flutter package and
            # `package:test` is not in its dependency graph, so `dart test`
            # cannot run there at all. Same runner the CI job uses.
            Invoke-Check -Name 'flutter test (app)' -WorkDir 'app' -Command @('flutter', 'test')
        } else { Add-Result 'flutter test (app)' 'ATLANDI' '(app/ yok)' }

        # 5) Kodlama kurallari
        Test-Encoding

        Show-Summary
        break
    }

    'resources' {
        if (-not (Test-Resources)) { Show-Summary; break }
        Show-Summary
        break
    }

    'build' {
        # Uygulamanin gercek derlemesi. 0.1.x'te `.\tool.ps1 spike` bunu
        # yapiyordu; simdi hedef uygulamanin kendisi.
        if (-not (Test-Resources)) { Show-Summary; break }
        if (-not (Test-Exists 'app')) { Add-Result 'flutter build' 'ATLANDI' '(app/ yok)'; Show-Summary; break }
        Invoke-Check -Name 'flutter build (app, release)' -WorkDir 'app' -Command @('flutter', 'build', 'windows', '--release')
        Show-Summary
        break
    }

    'docs' {
        Sync-ClaudeMirror
        Show-Summary
        break
    }

    'clean' {
        $targets = @('app\build', 'app\.dart_tool', 'design\.dart_tool')
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
