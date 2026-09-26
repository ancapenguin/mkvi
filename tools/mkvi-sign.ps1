#Requires -Version 5.1
<#
.SYNOPSIS
    Bir yayin artefaktini minisign ile imzalar. **ANAHTAR URETMEZ.**

.DESCRIPTION
    Imzayi ureten arac bu degil, minisign'dir. Bu betik yalnizca dogru baytlari
    dogru sirayla minisign'e gecer ve sonucu denetler.

    **Anahtar uretmez, ve uretmemeye calismaz.** -SecretKeyPath verilen dosya
    yoksa betik `minisign -G` CALISTIRMAZ; hata verip anahtar uretim adimini
    `docs/signing.md` icindeki prosedureye yonlendirir. Anahtar uretimi tek
    kullanicinin, kendi makin esinde, kendi iradesiyle yapacagi bir adimdir;
    bir betigin bir seyi uretirken o anahtarin hangi diskte, hangi yedekle
    oldugunu bilmezsiniz.

    Yayinlamadan once imzayi `tools\verify-signature.ps1` ile dogrulayin. Bu
    betik imzayi olusturur, dogrulamaz.

.PARAMETER InputPath
    Imzalanacak dosya. Genellikle `mkvi_<surum>_x64-setup.exe`.

.PARAMETER SecretKeyPath
    minisign ozel anahtar dosyasi (`*.key`). Parola korumaludur; parola
    interaktif olarak sorulur. `-W` ile uretilmis parolasiz bir anahtar icin
    `-Unencrypted` verilir.

.PARAMETER OutputPath
    `.sig` ciktisi. Varsayilan: `<InputPath>.minisig`.

.PARAMETER TrustedComment
    Imzaya gomulecek guvenilir yorum. minisign varsayilani
    `timestamp:<epoch>` yazar. Bir surum ya da dosya adi eklemek isteyen
    yayin sifresini buraya koyar.

.PARAMETER Unencrypted
    Anahtarin parolasi yok. `minisign -G -W` ile uretilmis anahtar icin.

.PARAMETER MinisignPath
    minisign ikilisinin tam yolu. PATH'te bulunamazsa kullanilir.

.EXAMPLE
    .\tools\mkvi-sign.ps1 -InputPath dist\mkvi_0.2.0_x64-setup.exe `
        -SecretKeyPath C:\anahtarlar\mkvi-release.key

.OUTPUTS
    Cikti kodu:
      0  imza olusturuldu
      2  kullanim hatasi (zorunlu parametre eksik)
      3  -InputPath yok, dosya degil, veya ozel anahtar gibi gorunuyor
      4  -SecretKeyPath yok
      5  minisign ikilisi bulunamadi
      6  minissign hata dondurdu
      7  imza olusmadi ya da beklenen bicimde degil
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$SecretKeyPath,
    [string]$OutputPath,
    [string]$TrustedComment,
    [switch]$Unencrypted,
    [string]$MinisignPath
)

$ErrorActionPreference = 'Stop'

# --- exit code constants, so the numbers above and the numbers here cannot drift
$EXIT_OK = 0
$EXIT_USAGE = 2
$EXIT_INPUT = 3
$EXIT_SECRET = 4
$EXIT_NO_TOOL = 5
$EXIT_TOOL_FAILED = 6
$EXIT_BAD_OUTPUT = 7

function Stop-With([int]$Code, [string]$Message) {
    Write-Host "HATA: $Message" -ForegroundColor Red
    exit $Code
}

# --- input checks --------------------------------------------------------------
# Checked BEFORE the signer is looked up. Cheap, decisive, and about this
# machine's own files: a missing artefact must not be reported as "minisign is
# not installed", which sends the reader to install a tool they do not need yet.
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    Stop-With $EXIT_INPUT "imzalanacak dosya yok: $InputPath"
}
$inputFull = (Resolve-Path -LiteralPath $InputPath).Path

# Signing your own private key is the one mistake here that is unrecoverable in
# every sense: the artefact would then be published carrying the key that can
# forge every future signature. The name is the only signal available, so it is
# checked before anything else touches the key.
if ([System.IO.Path]::GetExtension($inputFull) -eq '.key') {
    Stop-With $EXIT_INPUT 'imzalanacak dosya bir .key dosyasi. Ozel anahtar imzalanmaz; bu, anahtari herkese acik bir artefakt yapardi.'
}

if (-not (Test-Path -LiteralPath $SecretKeyPath -PathType Leaf)) {
    # Deliberately NOT falling back to `minisign -G`. See .DESCRIPTION.
    Stop-With $EXIT_SECRET "ozel anahtar dosyasi yok: $SecretKeyPath. BU BETIK ANAHTAR URETMEZ. Uretim adimi `docs/signing.md` -> \"Anahtar uretimi\" basligindadir ve bilerek ayri bir adim birakildi."
}

$secretFull = (Resolve-Path -LiteralPath $SecretKeyPath).Path
if (-not $OutputPath) {
    $OutputPath = "$inputFull.minisig"
}
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)

# An output that lands in the same directory as the secret key is how a key ends
# up in a release upload by accident, so it is a refusal and not a warning.
if ([System.IO.Path]::GetDirectoryName($outputFull) -eq [System.IO.Path]::GetDirectoryName($secretFull)) {
    Stop-With $EXIT_INPUT "imza ciktisi ozel anahtarinin bulundugu dizine yazilamaz: $outputFull"
}

# --- locate the signer ---------------------------------------------------------
# An empty -MinisignPath is not "use the empty string as a path": it is "look it
# up", and a lookup that fails has to be an error rather than an empty result
# that later turns into a confusing "cannot find path" from somewhere else.
$tool = $MinisignPath
if ([string]::IsNullOrWhiteSpace($tool)) {
    $found = Get-Command 'minisign' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $found) { $tool = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($tool)) {
    Stop-With $EXIT_NO_TOOL 'minisign bulunamadi. Kur: `winget install jedisct1.minisign` veya `scoop install minisign`. Kurulu degilse -MinisignPath ile tam yol ver.'
}
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    Stop-With $EXIT_NO_TOOL "minisign yolu gosterilen dosya degil: $tool"
}

# --- sign ----------------------------------------------------------------------
$arguments = @('-S', '-s', $secretFull, '-m', $inputFull, '-x', $outputFull)
if ($TrustedComment) { $arguments += @('-t', $TrustedComment) }
if ($Unencrypted) { $arguments += '-W' }

Write-Host "-- imzalaniyor" -ForegroundColor Cyan
Write-Host "   artefakt : $inputFull"
Write-Host "   imza     : $outputFull"
Write-Host "   arac     : $tool"

& $tool @arguments
$toolExit = $LASTEXITCODE
if ($toolExit -ne 0) {
    Stop-With $EXIT_TOOL_FAILED "minisign $toolExit dondurdu. Imza yazilmadi."
}

# --- verify what was written, not what was asked for ---------------------------
# A signer that exits 0 and writes nothing is a failure this script must not
# report as success, because the next step would be publishing a `latest.json`
# pointing at a signature file that does not exist.
if (-not (Test-Path -LiteralPath $outputFull -PathType Leaf)) {
    Stop-With $EXIT_BAD_OUTPUT "minisign basarili dondu ama imza dosyasi yazilmadi: $outputFull"
}

$bytes = [System.IO.File]::ReadAllBytes($outputFull)
if ($bytes.Length -eq 0) {
    Stop-With $EXIT_BAD_OUTPUT "imza dosyasi bos: $outputFull"
}

# The four line wire shape, checked here rather than at publish time. Line 1 must
# decode to `algorithm(2) || key_id(8) || signature(64)` = 74 bytes, and the
# algorithm must be the prehashed `ED`: MKVI's `verify_artifact`
# (crates/mkvi_core/src/update.rs:109-113) refuses anything else by name, and a
# signature rejected only after it has been uploaded is a wasted release.
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$lines = $text -split "`r?`n"
if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
if ($lines.Count -ne 4) {
    Stop-With $EXIT_BAD_OUTPUT "imza dosyasi dort satirlik degil ($($lines.Count) satir)."
}
if (-not $lines[0].StartsWith('untrusted comment: ')) {
    Stop-With $EXIT_BAD_OUTPUT 'imza dosyasinin 1. satiri "untrusted comment: " ile baslamiyor.'
}
if (-not $lines[2].StartsWith('trusted comment: ')) {
    Stop-With $EXIT_BAD_OUTPUT 'imza dosyasinin 3. satiri "trusted comment: " ile baslamiyor.'
}
$signed = [Convert]::FromBase64String($lines[1])
if ($signed.Length -ne 74) {
    Stop-With $EXIT_BAD_OUTPUT "imza blogu 74 bayt olmali, $($signed.Length) bayt."
}
$algorithm = [System.Text.Encoding]::ASCII.GetString($signed[0..1])
if ($algorithm -ne 'ED') {
    Stop-With $EXIT_BAD_OUTPUT "imza algoritma etiketi '$algorithm'. MKVI yalnizca prehashed 'ED' kabul eder; '-l' (legacy) ile imzalama."
}
$global = [Convert]::FromBase64String($lines[3])
if ($global.Length -ne 64) {
    Stop-With $EXIT_BAD_OUTPUT "global imza 64 bayt olmali, $($global.Length) bayt."
}

# --- report the value the feed needs ------------------------------------------
# Printed, not written anywhere: the caller pastes it into `latest.json`, and a
# script that maintained the feed itself would be a second source of truth for
# the one document an attacker can rewrite.
$sigB64 = [Convert]::ToBase64String($bytes)
Write-Host ''
Write-Host "GECTI: imza olusturuldu ve bicimi dogrulandi." -ForegroundColor Green
Write-Host "   algoritma      : $algorithm (prehashed)"
Write-Host "   guvenilir yorum: $($lines[2].Substring(17))"
Write-Host "   boyut          : $($bytes.Length) bayt"
Write-Host ''
Write-Host 'latest.json icin gereken deger (base64, tek satir):' -ForegroundColor Cyan
Write-Host $sigB64
Write-Host ''
Write-Host 'Dogrulamadan once yayinlamayin: .\tools\verify-signature.ps1 -ArtifactPath <artefakt> -SignaturePath <imza> -PublicKeyPath <anahtar.pub>'
exit $EXIT_OK
