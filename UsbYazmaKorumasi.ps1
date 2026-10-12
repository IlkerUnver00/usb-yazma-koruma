<#
.SYNOPSIS
    USB belleklere, harici disklere, telefonlara (MTP) ve CD/DVD'ye yazmayı engeller
    veya serbest bırakır. Okuma serbest kalır.

.DESCRIPTION
    İki katmanı birlikte uygular:

      Katman 1  HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies\WriteProtect
                Yalnızca usbstor.sys (USB Bulk-Only) sürücüsü okur. UASP kullanan USB 3
                SSD/NVMe kutularını, SD yuvalarını ve telefonları KAPSAMAZ.

      Katman 2  "Çıkarılabilir Depolama Erişimi" grup ilkesinin kayıt defteri değerleri
                (gpedit ile aynı değerler): çıkarılabilir diskler, WPD (telefon/MTP),
                CD/DVD, disket ve teyp için Deny_Write = 1. WPDBusEnum hizmeti uygular.

    Parametresiz çalıştırılırsa menü açılır. Yönetici değilse UAC ile kendini yükseltir.
    Sınırlar ve ayrıntılar için README.md'ye bakın.

    Çıkış kodları: 0 başarılı, 1 hata, 2 "Test" en az bir sürücüye yazabildi.

.PARAMETER Islem
    Ac     Korumayı açar.
    Kapat  Bu scriptin yazdığı değerleri siler.
    Durum  Ayarları, bağlı harici sürücüleri ve uyarıları gösterir; hiçbir şeyi değiştirmez.
    Test   USB/SD/çıkarılabilir sürücülere küçük bir dosya yazmayı dener, yazabilirse siler.

.EXAMPLE
    .\UsbYazmaKorumasi.ps1 -Islem Ac

.EXAMPLE
    .\UsbYazmaKorumasi.ps1 -Islem Test
#>
[CmdletBinding()]
param(
    [ValidateSet('Ac', 'Kapat', 'Durum', 'Test')]
    [string]$Islem,

    # İç kullanım: kendini yükselten pencere sonuç okunmadan kapanmasın.
    [switch]$Bekle,

    # İç kullanım: UAC ile yeniden başlatıldı; hâlâ yönetici değilse döngüye girme.
    [switch]$Yukseltildi
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --- 64 bit + yönetici olarak yeniden başlatma ------------------------------------

function Test-Yonetici {
    $kimlik = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $kimlik).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Yazılan anahtarlar WOW64 yönlendirmesinden etkilenmez (SOFTWARE\Policies paylaşımlı, SYSTEM
# yönlendirilmez). 64 bite geçiş, yönetici listesini okuyan LocalAccounts modülü 32 bit Windows
# PowerShell'de olmadığı için. sysnative + RunAs birlikte çalışmaz; önce aynı konsolda 64 bite geç.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $gecir = @()
    if ($Islem) { $gecir += @('-Islem', $Islem) }
    if ($Bekle) { $gecir += '-Bekle' }
    if ($Yukseltildi) { $gecir += '-Yukseltildi' }
    & "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @gecir
    exit $LASTEXITCODE
}

if (-not (Test-Yonetici)) {
    if ($Yukseltildi) {
        # UAC kapalıyken (EnableLUA=0) RunAs sessizce yetkisiz başlatır.
        Write-Host 'Yönetici yetkisi alınamadı (UAC kapalı olabilir). Yönetici hesabıyla oturum açıp tekrar çalıştırın.' -ForegroundColor Red
        [void](Read-Host 'Kapatmak için Enter')
        exit 1
    }

    # ISE gibi barındırıcılar -File ile script çalıştırmaz; konsol PowerShell'ini seç.
    if ($PSVersionTable.PSEdition -eq 'Core') { $exe = Join-Path $PSHOME 'pwsh.exe' }
    else { $exe = Join-Path $PSHOME 'powershell.exe' }

    # Yükseltilmiş oturum kullanıcının bağladığı ağ sürücülerini görmez; UNC yola çevir.
    $yol = $PSCommandPath
    if ($yol -match '^[A-Za-z]:') {
        $surucu = Get-PSDrive -Name $yol.Substring(0, 1) -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($surucu -and $surucu.DisplayRoot -like '\\*') { $yol = $surucu.DisplayRoot.TrimEnd('\') + $yol.Substring(2) }
    }

    $argumanlar = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$yol`"", '-Yukseltildi')
    if ($Islem) { $argumanlar += @('-Islem', $Islem, '-Bekle') }
    Write-Host 'Yönetici penceresi açılıyor; o pencere kapanınca bu pencere de kapanır.'
    try {
        $surec = Start-Process -FilePath $exe -ArgumentList $argumanlar -Verb RunAs -Wait -PassThru
        exit $surec.ExitCode
    } catch {
        Write-Host "Yönetici penceresi açılamadı: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Hiçbir şey değiştirilmedi.' -ForegroundColor Red
        exit 1
    }
}

# --- Kurallar ---------------------------------------------------------------------

$SdpAnahtar = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
$RsdKok     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'

# Katman 2 anahtarları ve GUID'ler C:\Windows\PolicyDefinitions\RemovableStorage.admx ile doğrulandı.
# WPD ilkesi aynı değeri İKİ anahtara yazar; biri eksik kalırsa telefonlar engellenmeyebilir.
$Kurallar = @(
    [pscustomobject]@{ Ad = 'Katman 1  USB toplu depolama (usbstor)'; Yol = $SdpAnahtar;                                         Deger = 'WriteProtect' }
    [pscustomobject]@{ Ad = 'Katman 2  Çıkarılabilir diskler';         Yol = "$RsdKok\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"; Deger = 'Deny_Write' }
    [pscustomobject]@{ Ad = 'Katman 2  Telefon / MTP (WPD) 1/2';       Yol = "$RsdKok\{6AC27878-A6FA-4155-BA85-F98F491D4F33}"; Deger = 'Deny_Write' }
    [pscustomobject]@{ Ad = 'Katman 2  Telefon / MTP (WPD) 2/2';       Yol = "$RsdKok\{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}"; Deger = 'Deny_Write' }
    [pscustomobject]@{ Ad = 'Katman 2  CD / DVD';                      Yol = "$RsdKok\{53f56308-b6bf-11d0-94f2-00a0c91efb8b}"; Deger = 'Deny_Write' }
    [pscustomobject]@{ Ad = 'Katman 2  Disket';                        Yol = "$RsdKok\{53f56311-b6bf-11d0-94f2-00a0c91efb8b}"; Deger = 'Deny_Write' }
    [pscustomobject]@{ Ad = 'Katman 2  Teyp';                          Yol = "$RsdKok\{53f5630b-b6bf-11d0-94f2-00a0c91efb8b}"; Deger = 'Deny_Write' }
)

$GunlukYolu = Join-Path $env:ProgramData 'UsbYazmaKorumasi\islem.log'

# --- Yardımcılar ------------------------------------------------------------------

function Write-Gunluk([string]$Mesaj) {
    try {
        $klasor = Split-Path $GunlukYolu
        if (-not (Test-Path $klasor)) { New-Item -ItemType Directory -Path $klasor | Out-Null }
        $satir = '{0:yyyy-MM-dd HH:mm:ss}  {1,-8}  {2}' -f (Get-Date), $Mesaj,
            [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Add-Content -Path $GunlukYolu -Value $satir -Encoding UTF8
    } catch { }
}

function Get-KuralDegeri($Kural) {
    $oge = Get-ItemProperty -Path $Kural.Yol -Name $Kural.Deger -ErrorAction SilentlyContinue
    if ($null -eq $oge) { return $null }
    $oge.($Kural.Deger)
}

function Get-GenelDurum {
    $acik = @($Kurallar | Where-Object { (Get-KuralDegeri $_) -eq 1 }).Count
    if ($acik -eq $Kurallar.Count) { 'AÇIK' }
    elseif ($acik -eq 0) { 'KAPALI' }
    else { "KISMİ ($acik/$($Kurallar.Count))" }
}

function Remove-BosAnahtar([string]$Yol) {
    if (-not (Test-Path $Yol)) { return }
    $anahtar = Get-Item -Path $Yol
    if ($anahtar.ValueCount -eq 0 -and $anahtar.SubKeyCount -eq 0) { Remove-Item -Path $Yol }
}

function Get-SurucuTuru($Disk) {
    if (-not $Disk) { return 'disk eşlenemedi' }
    if ([string]$Disk.BusType -ne 'USB') { return [string]$Disk.BusType }
    # Türkçe yerel ayarda I/i karşılaştırması bozulabilir; kültürden bağımsız küçült.
    # Dahili NVMe diskin yolu da \scsi# içerir; bu yüzden yalnızca USB veriyolunda bakılır.
    $yol = ([string]$Disk.Path).ToLowerInvariant()
    if ($yol.Contains('usbstor#')) { return 'USB  usbstor (BOT)' }
    if ($yol.Contains('\scsi#')) { return 'USB  UASP (uaspstor)' }
    'USB  diğer sürücü'
}

# Thunderbolt/eSATA/hot-swap yuvası gibi USB dışı ama takılıp çıkarılabilen diskler.
function Test-HotPlug($Disk) {
    try {
        $id = (Get-CimInstance Win32_DiskDrive -Filter "Index=$($Disk.Number)").PNPDeviceID
        if (-not $id) { return $false }
        $kap = Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_InLocalMachineContainer -ErrorAction SilentlyContinue
        if ($kap -and $kap.Data -eq $false) { return $true }
        # 2 = düzenli çıkarma, 3 = ani çıkarma beklenir; 1 = kalıcı dahili disk.
        $pol = Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_RemovalPolicy -ErrorAction SilentlyContinue
        if ($pol -and $pol.Data -in 2, 3) { return $true }
    } catch { }
    $false
}

# Harf atanmış harici birimler. Otomatik=$true olanlara Test yazar; diğerleri (Thunderbolt,
# eSATA, hot-swap yuvası) yalnızca listelenir: delil diski olabilecek bir diske yazılmaz.
function Get-HariciBirim {
    foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -ne 'CD-ROM' })) {
        $harf = [string]$v.DriveLetter
        if ("${harf}:" -eq $env:SystemDrive) { continue }

        $disk = $null
        try { $disk = Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop | Get-Disk -ErrorAction Stop } catch { }
        if ($disk -and ($disk.IsBoot -or $disk.IsSystem)) { continue }

        $veriyolu = $disk -and ([string]$disk.BusType -in 'USB', 'SD', 'MMC', '1394')
        $otomatik = $veriyolu -or $v.DriveType -eq 'Removable'
        if (-not $otomatik -and -not ($disk -and (Test-HotPlug $disk))) { continue }

        $surucu = Get-SurucuTuru $disk
        $adi = if ($disk) { $disk.FriendlyName } else { $v.FileSystemLabel }
        [pscustomobject]@{
            Harf         = $harf
            Ad           = $adi
            DosyaSistemi = [string]$v.FileSystem
            Surucu       = $surucu
            Katman1      = $surucu -like '*usbstor*'
            Otomatik     = $otomatik
        }
    }
}

function Get-Telefonlar {
    # WPD sınıfı USB belleklerin kendisini de (SWD\WPDBUSENUM\...) listeler; onları ayıkla.
    try {
        @(Get-PnpDevice -Class WPD -PresentOnly -ErrorAction Stop |
            Where-Object { $_.Status -eq 'OK' -and $_.InstanceId -notlike 'SWD\WPDBUSENUM\*' })
    } catch { @() }
}

function Get-Uyarilar {
    $uyarilar = @()

    $surum = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if ($surum.EditionID -like 'Core*') {
        $uyarilar += 'Windows Home: Katman 2 Home sürümünde Microsoft tarafından desteklenmiyor; Katman 1''in de bazı Home sistemlerde çalışmadığı bildirildi. Pro veya üstünü kullanın ve "Test" ile doğrulayın.'
    }

    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        $uyarilar += 'Bilgisayar etki alanına bağlı: bir GPO aynı ilkeyi "Devre dışı" yaparsa buradaki değerlerin üzerine yazar. Etki alanında bu ayarları GPO ile dağıtın.'
    }

    $hizmet = Get-Service -Name WPDBusEnum -ErrorAction SilentlyContinue
    if (-not $hizmet) {
        $uyarilar += 'WPDBusEnum hizmeti bulunamadı: Katman 2 uygulanamaz.'
    } elseif ($hizmet.StartType -eq 'Disabled') {
        $uyarilar += 'WPDBusEnum hizmeti devre dışı: Katman 2 uygulanmaz. "Ac" işlemi bunu düzeltir.'
    }

    try {
        $yoneticiler = @(Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object {
                $_.PrincipalSource -ne 'Local' -or $_.ObjectClass -ne 'User' -or (Get-LocalUser -SID $_.SID).Enabled
            } | ForEach-Object { $_.Name })
        if ($yoneticiler.Count) {
            $uyarilar += 'Bu hesaplar yönetici; korumayı kapatabilirler: ' + ($yoneticiler -join ', ') +
                '. Personel standart kullanıcı hesabıyla çalışmalı.'
        }
    } catch {
        $uyarilar += 'Yerel yönetici listesi okunamadı. Personelin yönetici olmadığından emin olun.'
    }

    $uyarilar
}

function Show-Uyarilar {
    $uyarilar = @(Get-Uyarilar)
    if (-not $uyarilar.Count) { return }
    Write-Host ''
    Write-Host 'Uyarılar' -ForegroundColor Yellow
    foreach ($u in $uyarilar) { Write-Host "  ! $u" -ForegroundColor Yellow }
}

# --- İşlemler ---------------------------------------------------------------------

function Enable-Koruma {
    foreach ($k in $Kurallar) {
        # New-Item -Force var olan anahtarı yeniden oluşturup değerlerini silebilir; yalnızca yoksa oluştur.
        if (-not (Test-Path $k.Yol)) { New-Item -Path $k.Yol -Force | Out-Null }
        New-ItemProperty -Path $k.Yol -Name $k.Deger -PropertyType DWord -Value 1 -Force | Out-Null
    }

    # Katman 2'yi WPDBusEnum uygular; devre dışıysa ilke hiç uygulanmaz.
    $hizmet = Get-Service -Name WPDBusEnum -ErrorAction SilentlyContinue
    if ($hizmet -and $hizmet.StartType -eq 'Disabled') {
        Set-Service -Name WPDBusEnum -StartupType Manual
        Write-Host 'WPDBusEnum hizmeti devre dışıydı; varsayılanı (El ile) geri yüklendi.' -ForegroundColor Yellow
    }

    Write-Gunluk 'AC'
    Write-Host ''
    Write-Host 'Koruma AÇILDI.' -ForegroundColor Green
    Write-Host '  - Şu anda takılı aygıtlar çıkarılıp yeniden takılana kadar yazılabilir kalır.'
    Write-Host '  - Katman 2 bazı aygıtlarda ancak yeniden başlatmadan sonra devreye girer.'
    Write-Host '    Bilgisayarı yeniden başlatın, sonra "Test" ile doğrulayın.'
}

function Disable-Koruma {
    foreach ($k in $Kurallar) {
        if (-not (Test-Path $k.Yol)) { continue }
        Remove-ItemProperty -Path $k.Yol -Name $k.Deger -ErrorAction SilentlyContinue
        Remove-BosAnahtar $k.Yol
    }
    Remove-BosAnahtar $RsdKok

    Write-Gunluk 'KAPAT'
    Write-Host ''
    Write-Host 'Koruma KAPATILDI.' -ForegroundColor Green
    Write-Host '  - Takılı aygıtlar çıkarılıp yeniden takılınca yazılabilir olur; bazıları için yeniden başlatma gerekebilir.'
}

function Show-Durum {
    Write-Host ''
    Write-Host 'Ayarlar' -ForegroundColor Cyan
    foreach ($k in $Kurallar) {
        $deger = Get-KuralDegeri $k
        if ($deger -eq 1) { $metin, $renk = 'AÇIK', 'Green' }
        elseif ($null -eq $deger) { $metin, $renk = 'kapalı', 'DarkGray' }
        else { $metin, $renk = "kapalı (değer: $deger)", 'DarkGray' }
        Write-Host ('  {0,-42} {1}' -f $k.Ad, $metin) -ForegroundColor $renk
    }

    $hizmet = Get-Service -Name WPDBusEnum -ErrorAction SilentlyContinue
    if ($hizmet) { Write-Host ('  {0,-42} {1}' -f 'WPDBusEnum hizmeti (Katman 2)', $hizmet.StartType) }
    $isletim = Get-CimInstance Win32_OperatingSystem
    Write-Host ('  {0,-42} {1} ({2})' -f 'Windows', $isletim.Caption, $isletim.BuildNumber)

    Write-Host ''
    Write-Host 'Bağlı harici sürücüler' -ForegroundColor Cyan
    $birimler = @(Get-HariciBirim)
    if (-not $birimler.Count) { Write-Host '  (yok)' -ForegroundColor DarkGray }
    foreach ($b in $birimler) {
        if ($b.Katman1) { $not = 'Katman 1 + 2' }
        elseif ($b.Otomatik) { $not = 'yalnızca Katman 2' }
        else { $not = 'Katman 2 belirsiz; otomatik test edilmez, elle deneyin' }
        Write-Host ('  {0}:  {1,-30} {2,-22} {3}' -f $b.Harf, $b.Ad, $b.Surucu, $not)
    }
    foreach ($t in Get-Telefonlar) {
        Write-Host ('  --  {0,-30} {1,-22} {2}' -f $t.FriendlyName, 'WPD / MTP', 'yalnızca Katman 2; Gezgin''den elle deneyin')
    }

    Show-Uyarilar
}

# Yazabildiği sürücü sayısını döndürür.
function Test-Yazma {
    $genel = Get-GenelDurum
    Write-Host ''
    Write-Host "Koruma: $genel" -ForegroundColor Cyan
    if ($genel -eq 'KAPALI') {
        Write-Host '  Koruma kapalı: bu, TEMEL ÇİZGİ testidir. Test aygıtlarının hepsi YAZILABİLİR çıkmalı;' -ForegroundColor DarkGray
        Write-Host '  çıkmayan aygıt (dolu, kilit anahtarı açık SD kart vb.) korumayı doğrulamak için kullanılamaz.' -ForegroundColor DarkGray
    } else {
        Write-Host '  ENGELLENDİ sonucu yalnızca koruma kapalıyken YAZILABİLİR çıkmış aygıtlar için kanıttır.' -ForegroundColor DarkGray
        Write-Host '  SD kartlarda kilit anahtarının kapalı olduğunu kontrol edin.' -ForegroundColor DarkGray
    }

    $birimler = @(Get-HariciBirim)
    if (-not $birimler.Count) {
        Write-Host '  Bağlı harici sürücü bulunamadı. Bir USB bellek takıp tekrar deneyin.'
    }

    $yazilabilir = 0
    foreach ($b in $birimler) {
        $etiket = '  {0}:  {1,-30} {2,-22}' -f $b.Harf, $b.Ad, $b.Surucu
        if (-not $b.Otomatik) {
            Write-Host "$etiket otomatik test edilmedi (Thunderbolt/eSATA/yuva); Gezgin'den elle deneyin" -ForegroundColor Yellow
            continue
        }
        if (-not $b.DosyaSistemi) {
            Write-Host "$etiket test edilemedi (dosya sistemi yok ya da BitLocker kilitli)" -ForegroundColor DarkGray
            continue
        }

        $dosya = $null
        try {
            $dosya = Join-Path "$($b.Harf):\" ('yazma_testi_{0}.tmp' -f [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($dosya, 'UsbYazmaKorumasi test')
            Write-Host "$etiket YAZILABİLİR" -ForegroundColor Red
            $yazilabilir++
        } catch [UnauthorizedAccessException] {
            # Katman 2: aygıtın erişim izni yazmayı reddeder.
            Write-Host "$etiket ENGELLENDİ  (erişim reddedildi)" -ForegroundColor Green
        } catch [IO.IOException] {
            # Katman 1 ya da fiziksel kilit: ERROR_WRITE_PROTECT (0x80070013).
            if ($_.Exception.HResult -eq -2147024877) {
                Write-Host "$etiket ENGELLENDİ  (ortam yazma korumalı)" -ForegroundColor Green
            } else {
                Write-Host "$etiket BELİRSİZ  ($($_.Exception.Message.Trim()))" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "$etiket BELİRSİZ  ($($_.Exception.GetBaseException().Message.Trim()))" -ForegroundColor Yellow
        } finally {
            if ($dosya -and (Test-Path -LiteralPath $dosya)) { Remove-Item -LiteralPath $dosya -Force -ErrorAction SilentlyContinue }
        }
    }

    foreach ($t in Get-Telefonlar) {
        Write-Host ('  --  {0,-30} {1,-22} otomatik test edilemez; Gezgin''den bir dosya kopyalamayı deneyin' -f $t.FriendlyName, 'WPD / MTP') -ForegroundColor Yellow
    }

    if ($yazilabilir -and $genel -ne 'KAPALI') {
        Write-Host ''
        Write-Host '  Yazılabilir çıkan aygıtları çıkarıp yeniden takın ya da bilgisayarı yeniden başlatıp tekrar test edin.' -ForegroundColor Yellow
        Write-Host '  Yeniden başlatmadan sonra da yazılabiliyorsa bu aygıt bu yöntemle korunmuyor (README: Sınırlar).' -ForegroundColor Yellow
    }
    Write-Gunluk "TEST yazilabilir=$yazilabilir"
    $yazilabilir
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '=== USB Yazma Koruması ===' -ForegroundColor Cyan
        Write-Host "Durum: $(Get-GenelDurum)"
        Write-Host ''
        Write-Host '  1) Korumayı AÇ'
        Write-Host '  2) Korumayı KAPAT'
        Write-Host '  3) Ayrıntılı durum'
        Write-Host '  4) Bağlı sürücülere yazma testi'
        Write-Host '  5) Bilgisayarı yeniden başlat'
        Write-Host '  0) Çıkış'
        $secim = Read-Host 'Seçim'
        try {
            switch ($secim) {
                '1' { Enable-Koruma; Show-Uyarilar }
                '2' { Disable-Koruma }
                '3' { Show-Durum }
                '4' { [void](Test-Yazma) }
                '5' {
                    if ((Read-Host 'Bilgisayar 30 saniye içinde yeniden başlatılsın mı? (E/H)') -match '^e') {
                        shutdown.exe /r /t 30 /c 'USB yazma koruması: yeniden başlatılıyor. İptal: shutdown /a'
                        return
                    }
                }
                '0' { return }
            }
        } catch {
            Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
            Write-Gunluk "HATA $($_.Exception.Message)"
        }
    }
}

# --- Giriş ------------------------------------------------------------------------

$kod = 0
try {
    if (-not $Islem) {
        Show-Menu
    } else {
        switch ($Islem) {
            'Ac'    { Enable-Koruma; Show-Uyarilar }
            'Kapat' { Disable-Koruma }
            'Durum' { Show-Durum }
            'Test'  { if ((Test-Yazma) -gt 0) { $kod = 2 } }
        }
    }
} catch {
    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Gunluk "HATA $($_.Exception.Message)"
    $kod = 1
} finally {
    if ($Bekle) { [void](Read-Host "`nKapatmak için Enter") }
}
exit $kod
