#Requires -Version 5.1
<#
.SYNOPSIS
    Bir yayin imzasini yayinlamadan once dogrular.

.DESCRIPTION
    Iki soruyu ayri ayri cevaplar ve ikisini birbirine karistirmaz:

      1. Imza gercekten dogru mu?      -> minisign -V, yani resmi dogrulayici.
      2. MKVI'nin `verify_artifact`'i bu .sig'i kabul eder mi?
                                    -> `update.rs:103-117`'nin istedigi on kosullar.

    Ikinci soru ayri soruluyor cunku 2026-09-26'da OLCULDU: resmi minisign
    imzasiyla `verify_artifact` uyumsuz DEGIL, ama resmi minisign *anahtariyla*
    uyumsuz. `minisign` her iki anahtar uretim yolunda da genel anahtari `Ed`
    ile etiketliyor (yalin anahtar 0x45 0x64), ve minisign'in yayimladigi bicim
    genel anahtar icin tam da `Ed` oneriyor. `mkvi_core::update::key_is_legacy`
    (`update.rs:129`) bu etiketi "legacy" sayiyor ve `verify_artifact`
    (`update.rs:103`) imzaya hic bakmadan `LegacyKey` donuyor.

    Bu arac o durumu sessizce gecmez: anahtar `Ed` ise cikis kodu 8 ile biter.
    Ayrinti ve olcum: `docs/signing.md`.

    ## Bu arac `mkvi_core`'i CALISTIRMAZ, ve bunu belirtir

    Arastirildi, `docs/signing.md` -> "Dogrulama aracinin arastirmasi" bolumunde
    yazili. Ozet: `crates/mkvi_core` bir kutuphane paketi (`[lib] crate-type =
    ["rlib"]`), `main.rs` yok, `cargo run` calistiracak bir sey bulamaz. Tek
    bir `.sig` + artefakt giris alan `cargo test` elde etmek uretim dogrulama
    yolunun icine ortam degiskeniyle surulen bir test kapiyi koymak demek, ve
    `mkvi_core` testleri `rusqlite`/bundled SQLite derledigi icin tek bir imza
    icin gereksiz maliyet tasir. `examples/` eklemek mumkun ve uyumlu olurdu,
    ama `cargo test` de bu otomatik derledigi icin her kapida odenecek bir hedef
    olurdu; kazanci bir sonraki adima birakildi.

    Sonuc: birincil dogrulayici resminin kendisi. Bu, `mkvi_core` ile dogrulamaktan
    zayif degil; `app/test/update/sign_compat_test.dart` resmi ciktiya karsi
    MKVI'nin okuma kurallarini sabitler, ve bu betik `verify_artifact`'in
    istedigi on kosullari ayni dosyada tek tek denetler.

.PARAMETER ArtifactPath
    Dogrulanacak indirilen dosya.

.PARAMETER SignaturePath
    `.sig` dosyasi.

.PARAMETER PublicKeyPath
    Genel anahtar dosyasi (`.pub`). Bu bir **genel** anahtardir; depoya girer.

.PARAMETER SelfTest
    Artefaktin bir kopyasini bayt degistirip reddedildigini dogrular. Aracin
    kendisinin lastik patlamasi olup olmadigini gosterir. Buyuk artefaktlarda
    ek yerdir, varsayilan KAPALI.

.PARAMETER MinisignPath
    minisign ikilisinin tam yolu. PATH'te bulunamazsa kullanilir.

.EXAMPLE
    .\tools\verify-signature.ps1 -ArtifactPath dist\mkvi_0.2.0_x64-setup.exe `
        -SignaturePath dist\mkvi_0.2.0_x64-setup.exe.minisig `
        -PublicKeyPath C:\anahtarlar\mkvi-release.key.pub

.OUTPUTS
    Cikti kodu:
      0  imza gecerli ve MKVI'nin on kosullari saglaniyor
      2  kullanim hatasi (zorunlu parametre eksik)
      3  artefakt veya imza dosyasi yok
      4  genel anahtar dosyasi yok
      5  minisign ikilisi bulunamadi
      6  minisign imzayi reddetti
      7  imza blogu MKVI'nin okuyamayacagi bir bicimde
      8  imza gecerli, AMA anahtar `Ed` etiketli: 0.2.0 bunu LegacyKey sayar
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ArtifactPath,
    [Parameter(Mandatory = $true)][string]$SignaturePath,
    [Parameter(Mandatory = $true)][string]$PublicKeyPath,
    [switch]$SelfTest,
    [string]$MinisignPath
)

$ErrorActionPreference = 'Stop'

$EXIT_OK = 0
$EXIT_USAGE = 2
$EXIT_ARTIFACT = 3
$EXIT_KEY = 4
$EXIT_NO_TOOL = 5
$EXIT_REJECTED = 6
$EXIT_BAD_SHAPE = 7
$EXIT_LEGACY_KEY = 8

function Stop-With([int]$Code, [string]$Message) {
    Write-Host "HATA: $Message" -ForegroundColor Red
    exit $Code
}

# --- paths ---------------------------------------------------------------------
foreach ($pair in @(
    @{ Label = 'artefakt'; Value = $ArtifactPath; Code = $EXIT_ARTIFACT },
    @{ Label = 'imza'; Value = $SignaturePath; Code = $EXIT_ARTIFACT },
    @{ Label = 'genel anahtar'; Value = $PublicKeyPath; Code = $EXIT_KEY })) {
    if (-not (Test-Path -LiteralPath $pair.Value -PathType Leaf)) {
        Stop-With $pair.Code "$($pair.Label) dosyasi yok: $($pair.Value)"
    }
}
$artifactFull = (Resolve-Path -LiteralPath $ArtifactPath).Path
$sigFull = (Resolve-Path -LiteralPath $SignaturePath).Path
$keyFull = (Resolve-Path -LiteralPath $PublicKeyPath).Path

# A secret key offered where a public key belongs is the failure mode that ends
# a release badly, and it is cheap to refuse.
if ([System.IO.Path]::GetExtension($keyFull) -eq '.key') {
    Stop-With $EXIT_KEY "-PublicKeyPath bir .key (ozel anahtar) dosyasi. Buraya genel anahtar (.key.pub) verilir."
}

$tool = $MinisignPath
if ([string]::IsNullOrWhiteSpace($tool)) {
    $found = Get-Command 'minisign' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $found) { $tool = $found.Source }
}
$toolMissing = [string]::IsNullOrWhiteSpace($tool) -or
    -not (Test-Path -LiteralPath $tool -PathType Leaf)

# --- shape checks: what `verify_artifact` insists on, before it is asked -------
# Read as bytes and decoded explicitly. `Get-Content` would apply the console's
# code page to a file whose whole content is base64, and a silently mangled
# character here reads as a signature failure rather than as a broken read.
$sigBytes = [System.IO.File]::ReadAllBytes($sigFull)
$sigText = [System.Text.Encoding]::UTF8.GetString($sigBytes)
$sigLines = $sigText -split "`r?`n"
if ($sigLines.Count -gt 0 -and $sigLines[$sigLines.Count - 1] -eq '') { $sigLines = $sigLines[0..($sigLines.Count - 2)] }
if ($sigLines.Count -ne 4) {
    Stop-With $EXIT_BAD_SHAPE "imza dosyasi dort satirlik degil ($($sigLines.Count) satir)."
}
$signed = [Convert]::FromBase64String($sigLines[1])
$globalSig = [Convert]::FromBase64String($sigLines[3])
if ($signed.Length -ne 74) {
    Stop-With $EXIT_BAD_SHAPE "imza blogu 74 bayt olmali, $($signed.Length) bayt."
}
if ($globalSig.Length -ne 64) {
    Stop-With $EXIT_BAD_SHAPE "global imza 64 bayt olmali, $($globalSig.Length) bayt."
}
$sigAlgorithm = [System.Text.Encoding]::ASCII.GetString($signed[0..1])
$sigKeyId = [System.Text.Encoding]::ASCII.GetString($signed[2..9])

$keyText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($keyFull))
$keyLines = $keyText -split "`r?`n"
if ($keyLines.Count -gt 0 -and $keyLines[$keyLines.Count - 1] -eq '') { $keyLines = $keyLines[0..($keyLines.Count - 2)] }
if ($keyLines.Count -lt 2) {
    Stop-With $EXIT_BAD_SHAPE "genel anahtar dosyasi iki satirlik degil ($($keyLines.Count) satir)."
}
$keyBytes = [Convert]::FromBase64String($keyLines[1])
if ($keyBytes.Length -ne 42) {
    Stop-With $EXIT_BAD_SHAPE "genel anahtar govdesi 42 bayt olmali, $($keyBytes.Length) bayt."
}
$keyAlgorithm = [System.Text.Encoding]::ASCII.GetString($keyBytes[0..1])
$keyKeyId = [System.Text.Encoding]::ASCII.GetString($keyBytes[2..9])

# The signature algorithm. `update.rs:109-113` accepts only `ED` and names
# everything else, so a legacy signature is caught here rather than on a user's
# machine after the upload.
if ($sigAlgorithm -ne 'ED') {
    Stop-With $EXIT_BAD_SHAPE "imza algoritma etiketi '$sigAlgorithm'. MKVI yalnizca prehashed 'ED' kabul eder."
}
# The key id. minisign-verify refuses a mismatch (`UnexpectedKeyId`) before it
# hashes anything, so this is cheap and it catches "signed with the old key".
if ($sigKeyId -ne $keyKeyId) {
    Stop-With $EXIT_BAD_SHAPE "anahtar kimligi eslesmiyor: imza '$sigKeyId', anahtar '$keyKeyId'. Imza baska bir anahtarla yapilmis."
}

Write-Host '-- bicim denetimi gecti' -ForegroundColor DarkGray
Write-Host "   imza algoritmasi   : $sigAlgorithm (prehashed)"
Write-Host "   anahtar etiketi    : $keyAlgorithm"
Write-Host "   anahtar kimligi    : $keyKeyId (imza ile ayni)"

# --- the real thing: the official verifier -------------------------------------
# The shape verdict above is pure PowerShell and is reported either way, because
# a missing signer must not hide the `Ed` finding: that finding is the one that
# stops the release, and it is true whether or not minisign happens to be
# installed on the machine doing the release.
if ($toolMissing) {
    Write-Host ''
    Write-Host 'ATLANDI: minisign bulunamadi, kriptografik dogrulama yapilmadi.' -ForegroundColor Yellow
    Write-Host '  Kur: `winget install jedisct1.minisign` veya `scoop install minisign`.'
    if ($keyAlgorithm -eq 'Ed') {
        Write-Host ''
        Write-Host 'OLCULDU: anahtar "Ed" etiketli, ve bu zaten yayini durduruyor.' -ForegroundColor Red
        Write-Host '  Ayri bkz. asagida. minisignin kurulu olmasi bunu duzeltmez.'
    }
    Stop-With $EXIT_NO_TOOL 'minisign ikilisi bulunamadi; kriptografik dogrulama yapilamadi.'
}

Write-Host ''
Write-Host '-- resmi dogrulayici (minisign -V)' -ForegroundColor Cyan
& $tool -V -q -p $keyFull -m $artifactFull -x $sigFull
if ($LASTEXITCODE -ne 0) {
    Stop-With $EXIT_REJECTED "minisign imzayi reddetti (cikis kodu $LASTEXITCODE). Artefakt imzalanmis degil ya da dosya bozulmus."
}
Write-Host '   imza gecerli.' -ForegroundColor Green

# --- optional: prove the checker can still say no ------------------------------
# A verifier that has never rejected anything has not been shown to work. This
# copies the artefact, flips one byte of the COPY, and requires a rejection. The
# original is never touched, and the copy goes away either way.
if ($SelfTest) {
    Write-Host ''
    Write-Host '-- kendi kendini sinama (bayt degistirilmis kopya)' -ForegroundColor Cyan
    $original = [System.IO.File]::ReadAllBytes($artifactFull)
    if ($original.Length -eq 0) {
        Write-Host '   atlandi: artefakt bos.' -ForegroundColor Yellow
    } else {
        $tampered = New-Object byte[] $original.Length
        [Array]::Copy($original, $tampered, $original.Length)
        $tampered[0] = $tampered[0] -bxor 0x01
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllBytes($tmp, $tampered)
            & $tool -V -q -p $keyFull -m $tmp -x $sigFull 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Stop-With $EXIT_BAD_SHAPE 'KENDI KENDINI SINAMA BASARISIZ: bir bayt degistirilmis kopyayi dogrulayici kabul etti. Bu arac guvenilir degil.'
            }
            Write-Host '   bir bayt degistirilince reddedildi. Dogrulayici calisiyor.' -ForegroundColor Green
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- the MKVI-specific precondition --------------------------------------------
# Reached only when the signature is cryptographically valid. Reporting it as
# success would be the exact failure this tool exists to prevent: a release that
# uploads cleanly and then cannot be installed by the app that published it.
Write-Host ''
if ($keyAlgorithm -eq 'Ed') {
    Write-Host 'OLCULDU: imza gecerli, AMA anahtar "Ed" etiketli.' -ForegroundColor Red
    Write-Host '  minisign genel anahtar formatini "Ed" olarak tanimlar ve resmi arac da "Ed" yazan'
    Write-Host '  anahtar uretir; bu bir hata degil, bicimin kendisi. Ancak MKVI 0.2.0 bu etiketi'
    Write-Host '  "legacy" sayar: mkvi_core::update::key_is_legacy (update.rs:129) -> true, ve'
    Write-Host '  verify_artifact (update.rs:103) imzaya bakmadan LegacyKey doner. Bu anahtarla'
    Write-Host '  yayinlanan bir guncelleme 0.2.0 tarafindan kurulamaz.'
    Write-Host '  Duzeltme docs/signing.md -> "Bulunan kusur" bolumunde. Simdilik YAYINLAMA.'
    exit $EXIT_LEGACY_KEY
}

Write-Host ''
Write-Host 'GECTI: imza gecerli ve MKVI 0.2.0 bunu kabul eder.' -ForegroundColor Green
exit $EXIT_OK
