<#
.SYNOPSIS
    USB belleklere, harici disklere, telefonlara (MTP) ve CD/DVD'ye yazmayı engeller
    veya serbest bırakır. Okuma serbest kalır.

.DESCRIPTION
    İki koruma modu vardır:

    Tam engel (Ac)
      Katman 1  HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies\WriteProtect
                Yalnızca usbstor.sys (USB Bulk-Only) sürücüsü okur. UASP kullanan USB 3
                SSD/NVMe kutularını, SD yuvalarını ve telefonları KAPSAMAZ.
      Katman 2  "Çıkarılabilir Depolama Erişimi" grup ilkesinin kayıt defteri değerleri
                (gpedit ile aynı değerler): çıkarılabilir diskler, WPD (telefon/MTP),
                CD/DVD, disket ve teyp için Deny_Write = 1. WPDBusEnum hizmeti uygular.

    BitLocker izin listesi (BitLocker)
      Yalnızca laboratuvar kimliğiyle damgalanmış BitLocker'lı çıkarılabilir disklere
      yazılabilir; diğerleri salt okunur bağlanır. Katman 1 ve "Çıkarılabilir diskler"
      değeri bu modda kaldırılır (açıkken BitLocker ilkesi yok sayılır). Telefon, CD/DVD,
      disket ve teyp engeli kalır. Lab diskleri "Hazirla" ile hazırlanır.

    Parametresiz çalıştırılırsa menü açılır. Yönetici değilse UAC ile kendini yükseltir.
    Sınırlar ve ayrıntılar için README.md'ye bakın.

    Çıkış kodları: 0 başarılı, 1 hata, 2 "Test" lab diski olmayan en az bir sürücüye yazabildi.

.PARAMETER Islem
    Ac         Tam engeli açar.
    BitLocker  BitLocker izin listesi modunu açar (-LabKimligi gerekir).
    Hazirla    Bir çıkarılabilir diski lab diski yapar: BitLocker'ı açar, kimlikle damgalar (-Surucu).
    Kapat      Bu scriptin yazdığı değerlerin hepsini siler (iki mod da).
    Durum      Ayarları, bağlı harici sürücüleri ve uyarıları gösterir; hiçbir şeyi değiştirmez.
    Test       USB/SD/çıkarılabilir sürücülere küçük bir dosya yazmayı dener, yazabilirse siler.

.PARAMETER LabKimligi
    BitLocker modu için laboratuvar kimliği: harf, rakam, nokta, tire, alt çizgi; en çok 64 karakter.

.PARAMETER Surucu
    Hazirla için sürücü harfi (ör. E).

.EXAMPLE
    .\UsbYazmaKorumasi.ps1 -Islem Ac

.EXAMPLE
    .\UsbYazmaKorumasi.ps1 -Islem BitLocker -LabKimligi ANKARA-LAB

.EXAMPLE
    .\UsbYazmaKorumasi.ps1 -Islem Hazirla -Surucu E
#>
[CmdletBinding()]
param(
    [ValidateSet('Ac', 'BitLocker', 'Hazirla', 'Kapat', 'Durum', 'Test')]
    [string]$Islem,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$LabKimligi,

    [ValidatePattern('^[A-Za-z]:?$')]
    [string]$Surucu,

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

# Yeniden başlatmada aynen geçirilecek parametreler.
$gecir = @()
if ($Islem) { $gecir += @('-Islem', $Islem) }
if ($LabKimligi) { $gecir += @('-LabKimligi', $LabKimligi) }
if ($Surucu) { $gecir += @('-Surucu', $Surucu) }

# Yazılan anahtarlar WOW64 yönlendirmesinden etkilenmez (SOFTWARE\Policies paylaşımlı, SYSTEM
# yönlendirilmez). 64 bite geçiş, yönetici listesini okuyan LocalAccounts modülü 32 bit Windows
# PowerShell'de olmadığı için. sysnative + RunAs birlikte çalışmaz; önce aynı konsolda 64 bite geç.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ek = @()
    if ($Bekle) { $ek += '-Bekle' }
    if ($Yukseltildi) { $ek += '-Yukseltildi' }
    & "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @gecir @ek
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
        $agSurucusu = Get-PSDrive -Name $yol.Substring(0, 1) -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($agSurucusu -and $agSurucusu.DisplayRoot -like '\\*') { $yol = $agSurucusu.DisplayRoot.TrimEnd('\') + $yol.Substring(2) }
    }

    # LabKimligi ve Surucu boşluk içeremez (ValidatePattern); tırnak gerekmez.
    $argumanlar = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$yol`"", '-Yukseltildi') + $gecir
    if ($Islem) { $argumanlar += '-Bekle' }
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
$FveSistem  = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE'
$FveYazilim = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'

function New-Kural($Grup, $Ad, $Yol, $Deger, $Tip, $Veri) {
    [pscustomobject]@{ Grup = $Grup; Ad = $Ad; Yol = $Yol; Deger = $Deger; Tip = $Tip; Veri = $Veri }
}

# Gruplar: Usb = yalnızca tam engel (BitLocker ilkesini ezer), Ortak = iki modda da,
# BitLocker = yalnızca izin listesi modu. Veri $null ise lab kimliği yazılır.
# Anahtarlar RemovableStorage.admx ve VolumeEncryption.admx ile doğrulandı.
# WPD ilkesi aynı değeri İKİ anahtara yazar; biri eksik kalırsa telefonlar engellenmeyebilir.
$Kurallar = @(
    New-Kural 'Usb'       'Katman 1  USB toplu depolama (usbstor)'       $SdpAnahtar 'WriteProtect' 'DWord' 1
    New-Kural 'Usb'       'Katman 2  Çıkarılabilir diskler'               "$RsdKok\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}" 'Deny_Write' 'DWord' 1
    New-Kural 'Ortak'     'Katman 2  Telefon / MTP (WPD) 1/2'             "$RsdKok\{6AC27878-A6FA-4155-BA85-F98F491D4F33}" 'Deny_Write' 'DWord' 1
    New-Kural 'Ortak'     'Katman 2  Telefon / MTP (WPD) 2/2'             "$RsdKok\{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}" 'Deny_Write' 'DWord' 1
    New-Kural 'Ortak'     'Katman 2  CD / DVD'                            "$RsdKok\{53f56308-b6bf-11d0-94f2-00a0c91efb8b}" 'Deny_Write' 'DWord' 1
    New-Kural 'Ortak'     'Katman 2  Disket'                              "$RsdKok\{53f56311-b6bf-11d0-94f2-00a0c91efb8b}" 'Deny_Write' 'DWord' 1
    New-Kural 'Ortak'     'Katman 2  Teyp'                                "$RsdKok\{53f5630b-b6bf-11d0-94f2-00a0c91efb8b}" 'Deny_Write' 'DWord' 1
    New-Kural 'BitLocker' 'BitLocker  Korumasız sürücüye yazma yok'       $FveSistem  'RDVDenyWriteAccess'           'DWord'  1
    New-Kural 'BitLocker' 'BitLocker  Başka kuruluşun diskine yazma yok'  $FveYazilim 'RDVDenyCrossOrg'              'DWord'  1
    New-Kural 'BitLocker' 'BitLocker  Kuruluş kimliği etkin'              $FveYazilim 'IdentificationField'          'DWord'  1
    New-Kural 'BitLocker' 'BitLocker  Kimlik alanı'                       $FveYazilim 'IdentificationFieldString'    'String' $null
    New-Kural 'BitLocker' 'BitLocker  İzin verilen kimlikler'             $FveYazilim 'SecondaryIdentificationField' 'String' $null
    New-Kural 'BitLocker' 'BitLocker  Çıkarılabilir sürücü denetimi'      $FveYazilim 'RDVConfigureBDE'              'DWord'  1
    New-Kural 'BitLocker' 'BitLocker  Kullanıcı BitLocker açamaz'         $FveYazilim 'RDVAllowBDE'                  'DWord'  0
    New-Kural 'BitLocker' 'BitLocker  Kullanıcı BitLocker kapatamaz'      $FveYazilim 'RDVDisableBDE'                'DWord'  0
)

$GunlukYolu = Join-Path $env:ProgramData 'UsbYazmaKorumasi\islem.log'
$KimlikDeseni = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

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

function Get-Grup([string[]]$Ad) { @($Kurallar | Where-Object { $Ad -contains $_.Grup }) }

function Get-KuralDegeri($Kural) {
    $oge = Get-ItemProperty -Path $Kural.Yol -Name $Kural.Deger -ErrorAction SilentlyContinue
    if ($null -eq $oge) { return $null }
    $oge.($Kural.Deger)
}

function Test-KuralUygulanmis($Kural) {
    $deger = Get-KuralDegeri $Kural
    if ($null -eq $deger) { return $false }
    if ($null -eq $Kural.Veri) { return [bool]([string]$deger) }
    $deger -eq $Kural.Veri
}

function Set-Kural($Kural, [string]$Lab) {
    $veri = $Kural.Veri
    if ($null -eq $veri) { $veri = $Lab }
    # New-Item -Force var olan anahtarı yeniden oluşturup değerlerini silebilir; yalnızca yoksa oluştur.
    if (-not (Test-Path $Kural.Yol)) { New-Item -Path $Kural.Yol -Force | Out-Null }
    New-ItemProperty -Path $Kural.Yol -Name $Kural.Deger -PropertyType $Kural.Tip -Value $veri -Force | Out-Null
}

function Remove-BosAnahtar([string]$Yol) {
    if (-not (Test-Path $Yol)) { return }
    $anahtar = Get-Item -Path $Yol
    if ($anahtar.ValueCount -eq 0 -and $anahtar.SubKeyCount -eq 0) { Remove-Item -Path $Yol }
}

function Remove-Kural($Kural) {
    if (-not (Test-Path $Kural.Yol)) { return }
    Remove-ItemProperty -Path $Kural.Yol -Name $Kural.Deger -ErrorAction SilentlyContinue
    Remove-BosAnahtar $Kural.Yol
}

function Get-Mod {
    $sayac = @{}
    foreach ($g in 'Usb', 'Ortak', 'BitLocker') {
        $sayac[$g] = @(Get-Grup $g | Where-Object { Test-KuralUygulanmis $_ }).Count
    }
    $tamUsb = $sayac['Usb'] -eq @(Get-Grup 'Usb').Count
    $tamOrtak = $sayac['Ortak'] -eq @(Get-Grup 'Ortak').Count
    $tamBl = $sayac['BitLocker'] -eq @(Get-Grup 'BitLocker').Count
    if ($tamUsb -and $tamOrtak -and $sayac['BitLocker'] -eq 0) { return 'TAM' }
    if ($sayac['Usb'] -eq 0 -and $tamOrtak -and $tamBl) { return 'BITLOCKER' }
    if ($sayac['Usb'] + $sayac['Ortak'] + $sayac['BitLocker'] -eq 0) { return 'KAPALI' }
    'KISMI'
}

function Get-ModMetni([string]$Mod) {
    switch ($Mod) {
        'TAM'       { 'AÇIK (tam engel)' }
        'BITLOCKER' { 'AÇIK (BitLocker izin listesi)' }
        'KAPALI'    { 'KAPALI' }
        default     { 'KISMİ / karışık (ayrıntılı durum ekranına bakın)' }
    }
}

function Get-LabKimligi {
    $oge = Get-ItemProperty -Path $FveYazilim -Name IdentificationFieldString -ErrorAction SilentlyContinue
    if ($null -eq $oge) { return '' }
    [string]$oge.IdentificationFieldString
}

function Get-IzinliKimlikler {
    $liste = @(Get-LabKimligi)
    $oge = Get-ItemProperty -Path $FveYazilim -Name SecondaryIdentificationField -ErrorAction SilentlyContinue
    if ($oge) { $liste += ([string]$oge.SecondaryIdentificationField).Split(',') }
    @($liste | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
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
            Boyut        = [double]$v.Size
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

# --- BitLocker yardımcıları -------------------------------------------------------

function Get-CimCikti($Ornek, [string]$Metot, [string]$Alan) {
    try {
        $sonuc = Invoke-CimMethod -InputObject $Ornek -MethodName $Metot -ErrorAction Stop
        if ($sonuc.ReturnValue -ne 0) { return $null }
        $sonuc.$Alan
    } catch { $null }
}

# Win32_EncryptableVolume yönetici ister; Türkçe manage-bde çıktısını ayrıştırmamak için WMI.
function Get-BitLockerBilgisi([string]$Harf) {
    try {
        $v = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='${Harf}:'" -ErrorAction Stop
    } catch { return $null }
    if (-not $v) { return $null }

    $kilitli = (Get-CimCikti $v 'GetLockStatus' 'LockStatus') -eq 1
    $donusum = Get-CimCikti $v 'GetConversionStatus' 'ConversionStatus'
    $yuzde = Get-CimCikti $v 'GetConversionStatus' 'EncryptionPercentage'
    [pscustomobject]@{
        Tur     = [int]$v.VolumeType          # 0 işletim sistemi, 1 sabit, 2 çıkarılabilir
        Kilitli = $kilitli
        Donusum = $donusum                    # 0 şifresiz, 1 tamamen şifreli, 2 şifreleniyor
        Yuzde   = $yuzde
        Sifreli = $kilitli -or ($null -ne $donusum -and $donusum -ne 0)
        Kimlik  = [string](Get-CimCikti $v 'GetIdentificationField' 'IdentificationField')
    }
}

# BitLocker modunda bir sürücünün lab diski olup olmadığı ve beklenen davranış.
function Get-LabDurumu([string]$Harf, [string[]]$Izinli) {
    $bl = Get-BitLockerBilgisi $Harf
    $durum = { param($lab, $kapsamDisi, $metin) [pscustomobject]@{ Lab = $lab; KapsamDisi = $kapsamDisi; Metin = $metin } }
    if (-not $bl) { return & $durum $false $false 'BitLocker bilgisi okunamadı' }
    if ($bl.Tur -eq 1) { return & $durum $false $true 'Windows sabit disk sayıyor: BitLocker modu KAPSAMAZ' }
    if ($bl.Kilitli) { return & $durum $false $false 'BitLocker kilitli' }
    if (-not $bl.Sifreli) { return & $durum $false $false 'BitLocker yok: salt okunur beklenir' }
    if (-not $bl.Kimlik) { return & $durum $false $false 'BitLocker var, kimlik yok: salt okunur beklenir (7 ile damgalayın)' }
    if ($Izinli -ccontains $bl.Kimlik) { return & $durum $true $false "lab diski ($($bl.Kimlik)): yazılabilir beklenir" }
    & $durum $false $false "başka kimlik ($($bl.Kimlik)): salt okunur beklenir"
}

# Kullanıcı ilkesi (HKCU) "Çıkarılabilir diskler: yazmayı reddet" veya "Tüm erişimi reddet"
# BitLocker ilkesini ezer. Yüklü kullanıcı profillerine bakılır.
function Get-KullaniciEngelleri {
    $sonuc = @()
    foreach ($h in @(Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -notlike '*_Classes' })) {
        $kok = "Registry::HKEY_USERS\$($h.PSChildName)\Software\Policies\Microsoft\Windows\RemovableStorageDevices"
        $dw = Get-ItemProperty -Path "$kok\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}" -Name Deny_Write -ErrorAction SilentlyContinue
        $da = Get-ItemProperty -Path $kok -Name Deny_All -ErrorAction SilentlyContinue
        if (($dw -and $dw.Deny_Write -eq 1) -or ($da -and $da.Deny_All -eq 1)) {
            try { $sonuc += (New-Object Security.Principal.SecurityIdentifier $h.PSChildName).Translate([Security.Principal.NTAccount]).Value }
            catch { $sonuc += $h.PSChildName }
        }
    }
    $sonuc
}

function Read-LabKimligi {
    $mevcut = Get-LabKimligi
    $ipucu = if ($mevcut) { " [Enter = $mevcut]" } else { '' }
    $giris = ([string](Read-Host "Laboratuvar kimliği (harf, rakam, . - _ ; ör. ANKARA-LAB)$ipucu")).Trim()
    if (-not $giris) { $giris = $mevcut }
    $giris
}

# --- Uyarılar ---------------------------------------------------------------------

function Get-Uyarilar {
    $uyarilar = @()

    $surum = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if ($surum.EditionID -like 'Core*') {
        $uyarilar += 'Windows Home: Katman 2 ve BitLocker ilkeleri Home sürümünde desteklenmiyor; Katman 1''in de bazı Home sistemlerde çalışmadığı bildirildi. Pro veya üstünü kullanın ve "Test" ile doğrulayın.'
    }

    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        $uyarilar += 'Bilgisayar etki alanına bağlı: bir GPO aynı ilkeyi "Devre dışı" yaparsa buradaki değerlerin üzerine yazar. Etki alanında bu ayarları GPO ile dağıtın.'
    }

    $hizmet = Get-Service -Name WPDBusEnum -ErrorAction SilentlyContinue
    if (-not $hizmet) {
        $uyarilar += 'WPDBusEnum hizmeti bulunamadı: Katman 2 uygulanamaz.'
    } elseif ($hizmet.StartType -eq 'Disabled') {
        $uyarilar += 'WPDBusEnum hizmeti devre dışı: Katman 2 uygulanmaz. Korumayı açmak bunu düzeltir.'
    }

    if ((Get-Mod) -eq 'BITLOCKER') {
        $engelli = @(Get-KullaniciEngelleri)
        if ($engelli.Count) {
            $uyarilar += 'Şu kullanıcı profillerinde "Çıkarılabilir diskler: yazmayı reddet" kullanıcı ilkesi açık; BitLocker izin listesi onlar için çalışmaz, lab disklerine de yazamazlar: ' + ($engelli -join ', ')
        }
        $hepsi = Get-ItemProperty -Path $RsdKok -Name Deny_All -ErrorAction SilentlyContinue
        if ($hepsi -and $hepsi.Deny_All -eq 1) {
            $uyarilar += '"Tüm çıkarılabilir depolama: tüm erişimi reddet" (Deny_All) açık; lab disklerine de erişilemez.'
        }
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

function Enable-Wpd {
    # Katman 2'yi WPDBusEnum uygular; devre dışıysa ilke hiç uygulanmaz.
    $hizmet = Get-Service -Name WPDBusEnum -ErrorAction SilentlyContinue
    if ($hizmet -and $hizmet.StartType -eq 'Disabled') {
        Set-Service -Name WPDBusEnum -StartupType Manual
        Write-Host 'WPDBusEnum hizmeti devre dışıydı; varsayılanı (El ile) geri yüklendi.' -ForegroundColor Yellow
    }
}

function Enable-Koruma {
    foreach ($k in (Get-Grup 'BitLocker')) { Remove-Kural $k }
    foreach ($k in (Get-Grup 'Usb', 'Ortak')) { Set-Kural $k }
    Remove-BosAnahtar $FveYazilim
    Enable-Wpd

    Write-Gunluk 'AC'
    Write-Host ''
    Write-Host 'Koruma AÇILDI (tam engel).' -ForegroundColor Green
    Write-Host '  - Şu anda takılı aygıtlar çıkarılıp yeniden takılana kadar yazılabilir kalır.'
    Write-Host '  - Katman 2 bazı aygıtlarda ancak yeniden başlatmadan sonra devreye girer.'
    Write-Host '    Bilgisayarı yeniden başlatın, sonra "Test" ile doğrulayın.'
}

function Enable-BitLockerModu([string]$Lab) {
    if (-not $Lab) { $Lab = Get-LabKimligi }
    if (-not $Lab) { throw 'Laboratuvar kimliği gerekli (ör. -LabKimligi ANKARA-LAB).' }
    if ($Lab -cnotmatch $KimlikDeseni) { throw "Geçersiz laboratuvar kimliği: '$Lab'. Yalnızca harf, rakam, nokta, tire, alt çizgi; en çok 64 karakter." }

    # Katman 1 ve "Çıkarılabilir diskler" açıkken BitLocker ilkesi yok sayılır; lab diskleri de salt okunur kalır.
    foreach ($k in (Get-Grup 'Usb')) { Remove-Kural $k }
    foreach ($k in (Get-Grup 'Ortak', 'BitLocker')) { Set-Kural $k $Lab }
    Enable-Wpd

    Write-Gunluk "BITLOCKER lab=$Lab"
    Write-Host ''
    Write-Host "Koruma AÇILDI (BitLocker izin listesi, lab kimliği: $Lab)." -ForegroundColor Green
    Write-Host '  - Yalnızca bu kimlikle damgalanmış BitLocker''lı çıkarılabilir disklere yazılabilir.'
    Write-Host '  - Telefon (MTP), CD/DVD, disket ve teyp engeli açık kalır.'
    Write-Host '  - Lab disklerini menüde 7 ile hazırlayın. Takılı aygıtları çıkarıp takın,'
    Write-Host '    bilgisayarı yeniden başlatın, sonra "Test" ile doğrulayın.'
}

function Disable-Koruma {
    foreach ($k in $Kurallar) { Remove-Kural $k }
    Remove-BosAnahtar $RsdKok
    Remove-BosAnahtar $FveYazilim

    Write-Gunluk 'KAPAT'
    Write-Host ''
    Write-Host 'Koruma KAPATILDI.' -ForegroundColor Green
    Write-Host '  - Takılı aygıtlar çıkarılıp yeniden takılınca yazılabilir olur; bazıları için yeniden başlatma gerekebilir.'
}

function Wait-Sifreleme([string]$Harf) {
    Start-Sleep -Seconds 2
    while ($true) {
        $bl = Get-BitLockerBilgisi $Harf
        if (-not $bl -or $bl.Donusum -ne 2) { break }
        $yuzde = [int]$bl.Yuzde
        Write-Progress -Activity "${Harf}: şifreleniyor (sürücüyü çıkarmayın)" -Status "%$yuzde" -PercentComplete $yuzde
        Start-Sleep -Seconds 2
    }
    Write-Progress -Activity "${Harf}: şifreleniyor" -Completed
}

# Bir çıkarılabilir diski lab diski yapar: BitLocker yoksa açar, lab kimliğiyle damgalar.
function Initialize-LabDiski([string]$Harf) {
    if ((Get-Mod) -ne 'BITLOCKER') { throw 'Önce BitLocker izin listesi modunu açın (menüde 6).' }
    $lab = Get-LabKimligi

    if (-not $Harf) { $Harf = [string](Read-Host 'Lab diski yapılacak sürücünün harfi (ör. E)') }
    $Harf = $Harf.Trim().TrimEnd(':', '\').ToUpperInvariant()
    if ($Harf -cnotmatch '^[A-Z]$') { throw "Geçersiz sürücü harfi: '$Harf'." }

    $birim = @(Get-HariciBirim | Where-Object { $_.Harf -eq $Harf })
    if (-not $birim.Count) { throw "${Harf}: harici/çıkarılabilir sürücü olarak bulunamadı. Dahili diskler lab diski yapılamaz." }
    $birim = $birim[0]

    $bl = Get-BitLockerBilgisi $Harf
    if (-not $bl) { throw "${Harf}: BitLocker bilgisi okunamadı." }
    if ($bl.Tur -eq 1) {
        throw "${Harf}: Windows bu diski sabit veri sürücüsü sayıyor; BitLocker izin listesi onu zaten kapsamıyor (README)."
    }
    if ($bl.Kilitli) { throw "${Harf}: BitLocker kilitli. Önce Gezgin'de çift tıklayıp parolayla kilidini açın." }

    Write-Host ''
    Write-Host ('Sürücü {0}:  {1}  ({2:N1} GB, {3})' -f $Harf, $birim.Ad, ($birim.Boyut / 1GB), $birim.Surucu) -ForegroundColor Cyan
    Write-Host "Lab kimliği: $lab"

    if (-not $bl.Sifreli) {
        Write-Host ''
        Write-Host 'Bu sürücüde BitLocker yok; şifrelenecek. Veriler silinmez ama işlem bitene kadar' -ForegroundColor Yellow
        Write-Host 'sürücüyü ÇIKARMAYIN. Sizden bir parola istenecek; ardından ekrana 48 haneli bir' -ForegroundColor Yellow
        Write-Host 'kurtarma parolası yazılacak: onu güvenli bir yere kaydedin.' -ForegroundColor Yellow
        $onay = ([string](Read-Host "Onaylamak için sürücü harfini tekrar yazın ($Harf)")).Trim().TrimEnd(':').ToUpperInvariant()
        if ($onay -cne $Harf) {
            Write-Host 'İptal edildi; hiçbir şey değiştirilmedi.'
            return
        }

        # "Kullanıcı BitLocker açamaz" yöneticiyi de engelleyebilir; şifreleme süresince geçici izin ver.
        New-ItemProperty -Path $FveYazilim -Name RDVAllowBDE -PropertyType DWord -Value 1 -Force | Out-Null
        try {
            & manage-bde.exe -on "${Harf}:" -UsedSpaceOnly -Password -RecoveryPassword
            if ($LASTEXITCODE -ne 0) { throw "manage-bde -on başarısız (kod $LASTEXITCODE)." }
        } finally {
            New-ItemProperty -Path $FveYazilim -Name RDVAllowBDE -PropertyType DWord -Value 0 -Force | Out-Null
        }
        Wait-Sifreleme $Harf
        $bl = Get-BitLockerBilgisi $Harf
    }

    # Yeni şifrelenen diske kimlik kendiliğinden yazılır; eski BitLocker'lı diske manage-bde ile yaz.
    if (-not $bl -or $bl.Kimlik -cne $lab) {
        & manage-bde.exe -SetIdentifier "${Harf}:"
        if ($LASTEXITCODE -ne 0) { throw "manage-bde -SetIdentifier başarısız (kod $LASTEXITCODE)." }
        $bl = Get-BitLockerBilgisi $Harf
    }

    $son = if ($bl) { $bl.Kimlik } else { '' }
    Write-Gunluk "HAZIRLA ${Harf}: kimlik=$son"
    if ($son -ceq $lab) {
        Write-Host ''
        Write-Host "${Harf}: lab diski hazır (kimlik: $son)." -ForegroundColor Green
        Write-Host '  Sürücüyü güvenle çıkarıp yeniden takın, kilidini açın, sonra "Test" ile yazılabildiğini doğrulayın.'
    } else {
        throw "${Harf}: kimlik yazılamadı (okunan: '$son'). Sürücüyü çıkarıp takın ve tekrar deneyin."
    }
}

function Show-Durum {
    $mod = Get-Mod
    Write-Host ''
    Write-Host "Koruma: $(Get-ModMetni $mod)" -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Ayarlar' -ForegroundColor Cyan
    foreach ($k in $Kurallar) {
        $deger = Get-KuralDegeri $k
        if (Test-KuralUygulanmis $k) {
            $metin, $renk = 'AÇIK', 'Green'
            if ($k.Tip -eq 'String') { $metin = "AÇIK ($deger)" }
        }
        elseif ($null -eq $deger) { $metin, $renk = 'kapalı', 'DarkGray' }
        else { $metin, $renk = "kapalı (değer: $deger)", 'DarkGray' }
        Write-Host ('  {0,-46} {1}' -f $k.Ad, $metin) -ForegroundColor $renk
    }

    $hizmet = Get-Service -Name WPDBusEnum -ErrorAction SilentlyContinue
    if ($hizmet) { Write-Host ('  {0,-46} {1}' -f 'WPDBusEnum hizmeti (Katman 2)', $hizmet.StartType) }
    $isletim = Get-CimInstance Win32_OperatingSystem
    Write-Host ('  {0,-46} {1} ({2})' -f 'Windows', $isletim.Caption, $isletim.BuildNumber)

    Write-Host ''
    Write-Host 'Bağlı harici sürücüler' -ForegroundColor Cyan
    $birimler = @(Get-HariciBirim)
    if (-not $birimler.Count) { Write-Host '  (yok)' -ForegroundColor DarkGray }
    $izinli = @(Get-IzinliKimlikler)
    foreach ($b in $birimler) {
        if ($mod -eq 'BITLOCKER') { $not = (Get-LabDurumu $b.Harf $izinli).Metin }
        elseif ($b.Katman1) { $not = 'Katman 1 + 2' }
        elseif ($b.Otomatik) { $not = 'yalnızca Katman 2' }
        else { $not = 'Katman 2 belirsiz; otomatik test edilmez, elle deneyin' }
        Write-Host ('  {0}:  {1,-30} {2,-22} {3}' -f $b.Harf, $b.Ad, $b.Surucu, $not)
    }
    foreach ($t in Get-Telefonlar) {
        Write-Host ('  --  {0,-30} {1,-22} {2}' -f $t.FriendlyName, 'WPD / MTP', 'yalnızca Katman 2; Gezgin''den elle deneyin')
    }

    Show-Uyarilar
}

# Lab diski olmayıp yazılabilen sürücü sayısını döndürür.
function Test-Yazma {
    $mod = Get-Mod
    Write-Host ''
    Write-Host "Koruma: $(Get-ModMetni $mod)" -ForegroundColor Cyan
    if ($mod -eq 'KAPALI') {
        Write-Host '  Koruma kapalı: bu, TEMEL ÇİZGİ testidir. Test aygıtlarının hepsi YAZILABİLİR çıkmalı;' -ForegroundColor DarkGray
        Write-Host '  çıkmayan aygıt (dolu, kilit anahtarı açık SD kart vb.) korumayı doğrulamak için kullanılamaz.' -ForegroundColor DarkGray
    } else {
        Write-Host '  ENGELLENDİ sonucu yalnızca koruma kapalıyken YAZILABİLİR çıkmış aygıtlar için kanıttır.' -ForegroundColor DarkGray
        Write-Host '  SD kartlarda kilit anahtarının kapalı olduğunu kontrol edin.' -ForegroundColor DarkGray
    }
    if ($mod -eq 'BITLOCKER') {
        Write-Host '  BitLocker modu: lab diskleri YAZILABİLİR, diğerleri ENGELLENDİ çıkmalı.' -ForegroundColor DarkGray
    }

    $birimler = @(Get-HariciBirim)
    if (-not $birimler.Count) {
        Write-Host '  Bağlı harici sürücü bulunamadı. Bir USB bellek takıp tekrar deneyin.'
    }

    $izinli = @(Get-IzinliKimlikler)
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

        $lab = $null
        if ($mod -eq 'BITLOCKER') {
            $lab = Get-LabDurumu $b.Harf $izinli
            Write-Host "        [$($lab.Metin)]" -ForegroundColor DarkGray
        }
        $labDiski = $lab -and $lab.Lab

        $dosya = $null
        try {
            $dosya = Join-Path "$($b.Harf):\" ('yazma_testi_{0}.tmp' -f [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($dosya, 'UsbYazmaKorumasi test')
            if ($labDiski) {
                Write-Host "$etiket YAZILABİLİR  (lab diski: beklenen)" -ForegroundColor Green
            } else {
                Write-Host "$etiket YAZILABİLİR" -ForegroundColor Red
                $yazilabilir++
            }
        } catch [UnauthorizedAccessException] {
            # Katman 2: aygıtın erişim izni yazmayı reddeder.
            $sonuc = 'ENGELLENDİ  (erişim reddedildi)'
            if ($labDiski) { Write-Host "$etiket $sonuc ama lab diski: çıkarıp takın, kimliği kontrol edin" -ForegroundColor Yellow }
            else { Write-Host "$etiket $sonuc" -ForegroundColor Green }
        } catch [IO.IOException] {
            # Katman 1, BitLocker salt okunur bağlama ya da fiziksel kilit: ERROR_WRITE_PROTECT (0x80070013).
            if ($_.Exception.HResult -eq -2147024877) {
                $sonuc = 'ENGELLENDİ  (ortam yazma korumalı)'
                if ($labDiski) { Write-Host "$etiket $sonuc ama lab diski: çıkarıp takın, kimliği kontrol edin" -ForegroundColor Yellow }
                else { Write-Host "$etiket $sonuc" -ForegroundColor Green }
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

    if ($yazilabilir -and $mod -ne 'KAPALI') {
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
        Write-Host "Durum: $(Get-ModMetni (Get-Mod))"
        Write-Host ''
        Write-Host '  1) Korumayı AÇ (tam engel)'
        Write-Host '  2) Korumayı KAPAT'
        Write-Host '  3) Ayrıntılı durum'
        Write-Host '  4) Bağlı sürücülere yazma testi'
        Write-Host '  5) Bilgisayarı yeniden başlat'
        Write-Host '  6) Korumayı AÇ: BitLocker izin listesi (yalnızca lab diskleri yazılabilir)'
        Write-Host '  7) Lab diski hazırla (BitLocker + lab kimliği)'
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
                '6' { Enable-BitLockerModu (Read-LabKimligi); Show-Uyarilar }
                '7' { Initialize-LabDiski }
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
            'Ac'        { Enable-Koruma; Show-Uyarilar }
            'BitLocker' { Enable-BitLockerModu $LabKimligi; Show-Uyarilar }
            'Hazirla'   { Initialize-LabDiski $Surucu }
            'Kapat'     { Disable-Koruma }
            'Durum'     { Show-Durum }
            'Test'      { if ((Test-Yazma) -gt 0) { $kod = 2 } }
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
