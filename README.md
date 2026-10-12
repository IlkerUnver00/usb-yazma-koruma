# USB Yazma Koruması · USB Write Protection

**Türkçe** · [English](#english)

Laboratuvar bilgisayarlarından USB belleklere, harici disklere, telefonlara (MTP) ve CD/DVD'ye
dosya kopyalanmasını engeller. **Okuma serbest kalır**; yalnızca yazma engellenir.

Amaç: X-Ways Forensics (XWF) klasörünün taşınabilir bir aygıta kopyalanıp dışarı çıkarılmasını
zorlaştırmak. Sınırlarını mutlaka okuyun ([Neyi engellemez](#neyi-engellemez)). Özellikle
yönetici hesabı olan biri bu korumayı iki tıkla kaldırabilir.

## Dosyalar

| Dosya | Ne işe yarar |
|---|---|
| `usb_yazma_korumasi_ac.reg` | Çift tıkla → korumayı açar (iki katman birlikte) |
| `usb_yazma_korumasi_kapat.reg` | Çift tıkla → aynı değerleri geri alır |
| `UsbYazmaKorumasi.cmd` | Menüyü açar: Aç / Kapat / Durum / Test / Yeniden başlat / BitLocker izin listesi / Lab diski hazırla |
| `UsbYazmaKorumasi.ps1` | Menünün asıl scripti; komut satırından da kullanılır |

`.reg` dosyaları yalnızca tam engeli açıp kapatır. [BitLocker izin listesi](#laboratuvarın-kendi-disklerine-yazması-gerekiyorsa-bitlocker-izin-listesi)
modu menüden veya komut satırından açılır.

## Kullanım

**En basit yol:** `usb_yazma_korumasi_ac.reg` → çift tık → *Evet* → **bilgisayarı yeniden başlatın**.

**Menüyle:** `UsbYazmaKorumasi.cmd` → çift tık → UAC'de *Evet*. Menüde durum, bağlı sürücülerin
listesi ve yazma testi de var.

**Komut satırından** (birden çok makineye dağıtım için):

```bat
UsbYazmaKorumasi.cmd -Islem Ac
UsbYazmaKorumasi.cmd -Islem Durum
UsbYazmaKorumasi.cmd -Islem Test
UsbYazmaKorumasi.cmd -Islem Kapat
UsbYazmaKorumasi.cmd -Islem BitLocker -LabKimligi ANKARA-LAB
UsbYazmaKorumasi.cmd -Islem Hazirla -Surucu E
```

Script yönetici değilse UAC ile kendini yükseltir ve yükseltilmiş pencerenin çıkış kodunu geri verir.
Çıkış kodları: `0` başarılı, `1` hata, `2` Test, lab diski olmayan en az bir sürücüye yazabildi. Dağıtım aracıyla
SYSTEM hesabında çalıştırırsanız UAC penceresi açılmaz.

Aç, Kapat ve Test işlemleri `%ProgramData%\UsbYazmaKorumasi\islem.log` dosyasına tarih ve kullanıcı
adıyla kaydedilir. `.reg` dosyalarıyla yapılan değişiklikler bu günlüğe girmez.

## Ne yapar: iki katman

İnternette sık önerilen tek anahtar (`StorageDevicePolicies\WriteProtect`) tek başına yetmiyor.
Test makinesinde (Windows 11 Pro 25H2, derleme 26200) tüm sürücü dosyaları tarandı. Bu değeri **yalnızca
`usbstor.sys`** okuyor. `uaspstor.sys`, `sdstor.sys`, `stornvme.sys` ve `disk.sys` okumuyor. Bu yüzden
ikinci bir katman eklendi:

| | Katman 1: `StorageDevicePolicies\WriteProtect` | Katman 2: Çıkarılabilir Depolama Erişimi ilkesi |
|---|---|---|
| Kayıt yeri | `HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{sınıf GUID}\Deny_Write` |
| Uygulayan | `usbstor.sys` sürücüsü | WPDBusEnum hizmeti (aygıtın erişim izinlerini değiştirir) |
| USB bellek (klasik, BOT) | ✅ | ✅ |
| USB 3 SSD/NVMe kutusu (UASP) | ❌ | ✅ (belgelere göre; aygıtınızla test edin) |
| Harici HDD ("Yerel Disk" görünen) | yalnızca usbstor ise | ✅ (belgelere göre) |
| Dahili SD kart yuvası (PCIe/SD veriyolu) | ❌ | ❓ belirsiz, test edin |
| Telefon / kamera (MTP, PTP) | ❌ | ✅ WPD ilkesi (iki GUID birlikte) |
| CD/DVD yazma | ❌ | ✅ Windows yazdırması; üçüncü parti yazılımlar aşabilir |
| Thunderbolt / USB4 NVMe | ❌ | ❓ belirsiz, test edin |
| eSATA / hot-swap SATA yuvası | ❌ | ❓ belirsiz, test edin (aşağıdaki yan etkiye bakın) |

> **Yan etki: dahili hot-swap yuvaları.** Katman 2 diskleri USB olup olmamalarına göre değil,
> Windows'un onları takılıp çıkarılabilir (hot-plug) sayıp saymamasına göre seçer. BIOS'ta hot-plug
> açık olan SATA/eSATA portlarındaki dahili diskler de salt okunur olabilir. Bu diskler "Donanımı
> Güvenle Kaldır" listesinde görünür. Forensic iş istasyonlarında vaka diskleri çoğu zaman bu tür
> yuvalardadır: korumayı açtıktan sonra XWF'nin çıktı yazdığı disklere yazılabildiğini mutlaka
> kontrol edin. Yazılabilir kalması gereken yuva için BIOS'ta o portun Hot Plug ayarını kapatın.

Katman 2'nin değer adları ve GUID'leri makinedeki
`C:\Windows\PolicyDefinitions\RemovableStorage.admx` dosyasından birebir alındı:

| İlke | Alt anahtar |
|---|---|
| Çıkarılabilir Diskler | `{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}` |
| WPD Aygıtları (ikisi birlikte) | `{6AC27878-A6FA-4155-BA85-F98F491D4F33}` ve `{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}` |
| CD ve DVD | `{53f56308-b6bf-11d0-94f2-00a0c91efb8b}` |
| Disket | `{53f56311-b6bf-11d0-94f2-00a0c91efb8b}` |
| Teyp | `{53f5630b-b6bf-11d0-94f2-00a0c91efb8b}` |

> Sık yapılan hata: `Deny_Write` değerini doğrudan `RemovableStorageDevices` anahtarına yazmak.
> Orada tanımlı bir ilke yok, hiçbir şey olmaz. Değer sınıf GUID'li alt anahtarda olmalı.

Kayıt defterine doğrudan yazılan değerler `gpedit.msc` ve `gpresult` çıktısında **görünmez**, ama
uygulanır. Denetimde "ilke yok" sanılmasın.

## Ne zaman devreye girer

- **Takılı aygıtlar etkilenmez.** Çıkarıp yeniden takana kadar yazılabilir kalırlar.
- **Katman 2** yeni takılan aygıtlarda genelde hemen devreye girer. Kullanımdaki aygıtlar için ise
  Microsoft'un açıklaması "işletim sistemi yeniden başlatılana kadar etkili olmaz" der.
  **Açtıktan sonra yeniden başlatın.**
- **Kapatınca da** aygıtları çıkarıp takın; bazıları için yeniden başlatma gerekir.

## Doğrulama (her makinede ve her Windows güncellemesinden sonra)

1. **Temel çizgi (koruma KAPALIYKEN):** laboratuvarda bulunan her tür aygıtı takın: klasik USB
   bellek, USB 3 SSD kutusu, harici disk, SD kart (hem USB okuyucuyla hem dahili yuvayla) ve bir
   Android telefon. Menüden **4) Yazma testi** çalıştırın. Hepsi **YAZILABİLİR** çıkmalı. Çıkmayan
   aygıt (dolu, kilit anahtarı açık SD kart vb.) korumayı doğrulamak için kullanılamaz.
2. Korumayı açın, bilgisayarı yeniden başlatın.
3. Aynı aygıtları takıp **4) Yazma testi**ni tekrar çalıştırın. Sonuçların anlamı:
   - yeşil **ENGELLENDİ**: aygıt korunuyor;
   - kırmızı **YAZILABİLİR**: aygıt korunmuyor (script test dosyasını siler);
   - sarı **BELİRSİZ**: yazma başka bir nedenle başarısız oldu (disk dolu, G/Ç hatası). Sonuç yok.
4. Script yalnızca USB/SD/çıkarılabilir sürücülere otomatik yazar. Thunderbolt, eSATA ve hot-swap
   yuvasındaki diskleri listeler ama bunlara **yazmaz**, çünkü delil diski olabilirler. Bunları ve
   telefonu (MTP) Gezgin'den bir dosya kopyalayarak elle deneyin. Durum ekranı her sürücünün hangi
   sürücüyle bağlandığını da gösterir (usbstor / UASP).

Microsoft, 2025'te bazı güncellemelerin (KB5058379, KB5050092, KB5062552) bu ilkenin uygulanmasını
sessizce bozduğunu ve Known Issue Rollback ile düzelttiğini bildirdi. Güncellemeden sonra testi
tekrarlayın.

## Neyi engellemez

**1. Yönetici hesapları. En büyük açık budur.** Bu ayarların hepsi kayıt defterindeki birer değer.
Yerel yönetici olan biri değeri silebilir, WPDBusEnum hizmetini kapatabilir, kopyalamayı SYSTEM
hesabıyla yapabilir (ilke SYSTEM'i etkilemez) ya da sürücü yükleyebilir. Personel **standart
kullanıcı** hesabıyla çalışmalı; yönetici parolası ayrı ve az kişide olmalı. `Durum` ekranı
yönetici hesaplarını listeler.

> **XWF ile çelişki:** XWF kılavuzuna göre fiziksel bir diske sektör düzeyinde erişmek için
> yönetici yetkisi gerekiyor. İnceleyiciler yönetici olursa bu koruma da onlar için anlamsızlaşır.
> Seçenekler:
> - inceleyiciler imaj (E01) üzerinde standart kullanıcıyla çalışır, imajı yönetici ya da donanım
>   imajlayıcı alır;
> - ham disk erişimi gerektiğinde XWF'yi yönetici gelip kendi parolasıyla yükseltir. **Dikkat:**
>   yükseltilmiş XWF, o oturum boyunca inceleyiciye yönetici yetkisi verir. XWF'nin içinden
>   ("Execute", harici programla aç, dosya iletişim kutuları) yükseltilmiş cmd veya regedit açılıp
>   koruma kapatılabilir. Yönetici iş bitene kadar başında kalmalı ve sonunda XWF'yi kapatmalı;
> - ya da yöneticilere zaten güvenilir ve asıl koruma lisans anahtarının saklanmasıyla sağlanır
>   (aşağıya bakın).

**2. Ağ ve internet:** paylaşım klasörleri (SMB), OneDrive/Dropbox, webmail, tarayıcıdan yükleme,
e-posta. XWF birkaç MB olduğu için bu yollardan kolayca gider. Gerçek çözüm, Windows Güvenlik
Duvarı'nda **tüm profillerde** giden trafiği varsayılan olarak engelleyip yalnızca gerekenlere izin
vermek (`Set-NetFirewallProfile -All -DefaultOutboundAction Block` ve izin kuralları). Bu kural
sonradan eklenen ağ bağdaştırıcılarını da kapsar. OneDrive için
`HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1` kullanılabilir.

"Ağ kablosunu çekmek" yetmez:
- **Wi-Fi:** standart kullanıcı bir hotspot'a bağlanabilir. Kablosuz kartı UEFI'den kapatın.
- **Telefonla internet paylaşımı (USB tethering):** telefon depolama aygıtı olarak değil ağ
  bağdaştırıcısı (RNDIS/NCM) olarak takılır. WPD engeli buna uygulanmaz ve sürücü yönetici
  izni olmadan kurulur. Güvenlik duvarı kuralıyla ya da Aygıt Yükleme Kısıtlamaları'yla RNDIS/NCM
  uyumlu kimliklerini engelleyerek kapatın.

**3. Bluetooth ile dosya gönderme** ve **dışarıya RDP bağlantısı** (bağlanılan makineye yerel
sürücüler aktarılır). Bluetooth'u UEFI'den veya hizmetten kapatın; giden 3389 portunu engelleyin.

**4. Kısmi ya da belirsiz kalanlar:**
- ADB (`adb push`) WPD kullanmaz, büyük olasılıkla engellenmez.
- iPhone'a Apple yazılımıyla yazma belirsiz.
- Üçüncü parti CD yazdırma programları CD/DVD ilkesini aşabilir.

**5. Fiziksel erişim:** USB'den canlı sistem başlatmak ya da diski söküp başka makineye takmak
Windows ayarlarının hepsini atlar. Önlem: UEFI yönetici parolası, USB'den önyüklemeyi kapatmak,
Secure Boot ve sistem diskinde BitLocker.

**6. Bu bir adli yazma engelleyici (write-blocker) DEĞİLDİR.** Delil disklerini salt okunur yapıyor
gibi görünse de UASP, SD ve NVMe boşlukları var. Katman 1'in, yönetici yetkisiyle çalışan bir
disk editörünün (WinHex/XWF) ham sektör yazmasını durdurup durdurmadığı da belgelenmemiş. Delil
edinimi için donanım yazma engelleyici kullanmaya devam edin.

## XWF için asıl korunacak şey: lisans anahtarı

x-ways.net'in resmi sayfalarına göre XWF kurulum gerektirmez, klasörden veya USB bellekten çalışır.
Tam ürün yalnızca bir anahtar varken açılır:

- **Yerel dongle** (USB) veya **ağ dongle'ı**.
- **BYOD:** müşterinin kendi USB belleği, harici diski ya da dahili diski anahtar olur; o aygıt
  bilgisayara takılı olmalıdır.
- **BYOD+:** X-Ways sunucusu çevrim içi anahtar olur; program çalışırken internet gerekir.

Yani yalnızca klasörü kopyalamak, anahtar olmadan tam ürünü açmaya yetmez. Asıl önemli olanlar:

- Dongle'ın ya da BYOD belleğin kimde olduğu. Dahili diski BYOD anahtarı yapmak veya dongle'ı
  kasaya kilitlemek lisansı o makineye bağlar.
- **BYOD+** ve **ağ dongle'ı** için kopyalanan klasörün başka makinede çalışıp çalışmayacağı resmi
  sayfalarda net değil; X-Ways'e sorun.
- BYOD anahtarınız bir USB bellekse, korumayı açtıktan sonra XWF'nin hâlâ açıldığını kontrol edin
  (anahtar bellek artık salt okunur).

## Laboratuvarın kendi disklerine yazması gerekiyorsa: BitLocker izin listesi

Tam engel açıkken rapor veya imaj da harici diske yazılamaz. Bunun için ikinci bir mod var:
**yalnızca laboratuvar kimliğiyle damgalanmış BitLocker'lı disklere yazılabilir**; diğer bütün USB
bellek ve diskler salt okunur kalır. Telefon (MTP), CD/DVD, disket ve teyp engeli bu modda da açıktır.

> Bu mod gerçek BitLocker diskleriyle denenmedi. Mod geçişleri, kayıt defteri değerleri ve lab
> diski hazırlama adımları sahte sürücülerle test edildi. Önce tek bir makinede deneyin.

**Kurulum:**

1. Menüde **6** → laboratuvar kimliğini yazın (ör. `ANKARA-LAB`; harf, rakam, `.` `-` `_`).
   Komut satırı: `UsbYazmaKorumasi.cmd -Islem BitLocker -LabKimligi ANKARA-LAB`
2. Her lab diskini takın, menüde **7** → sürücü harfi.
   Komut satırı: `UsbYazmaKorumasi.cmd -Islem Hazirla -Surucu E`
   - Diskte BitLocker yoksa şifrelenir. Bir parola istenir ve ekrana **48 haneli kurtarma
     parolası** yazılır; onu güvenli bir yere kaydedin. Veriler silinmez ama işlem bitene kadar
     diski çıkarmayın.
   - Diskte BitLocker zaten varsa yalnızca lab kimliğiyle damgalanır (`manage-bde -SetIdentifier`).
3. Diski çıkarıp takın, kilidini açın, bilgisayarı yeniden başlatın.
4. Menüde **4** (yazma testi): lab diskleri yeşil **YAZILABİLİR (lab diski: beklenen)**, diğerleri
   **ENGELLENDİ** çıkmalı. Durum ekranı her diskin BitLocker durumunu ve kimliğini gösterir.

**Yazılan değerler** (`VolumeEncryption.admx` ile doğrulandı):

| Ayar | Değer |
|---|---|
| BitLocker'la korunmayan çıkarılabilir sürücülere yazmayı reddet | `HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE` → `RDVDenyWriteAccess = 1` |
| Başka kuruluşta yapılandırılmış aygıtlara yazma izni verme | `HKLM\SOFTWARE\Policies\Microsoft\FVE` → `RDVDenyCrossOrg = 1` |
| Kuruluş kimliği | aynı anahtar → `IdentificationField = 1`; `IdentificationFieldString` ve `SecondaryIdentificationField` = lab kimliği |
| Personel BitLocker açıp kapatamasın | aynı anahtar → `RDVConfigureBDE = 1`, `RDVAllowBDE = 0`, `RDVDisableBDE = 0` |

Bu modda Katman 1 ve "Çıkarılabilir Diskler" `Deny_Write` kaldırılır. Açık kalırlarsa BitLocker
ilkesi yok sayılır ve lab diskleri de salt okunur olur. Lab diski hazırlarken script, şifreleme
süresince `RDVAllowBDE` değerini geçici olarak 1 yapar ve iş bitince (hata olsa da) 0'a döndürür.

Dikkat edilecekler:
- `.reg` dosyaları bu modu açmaz ama bu modun değerlerini kaldırır: `ac.reg` tam engele,
  `kapat.reg` korumasız duruma geçirir.
- Kimlik dizesi gizli değildir; her kullanıcı okuyabilir. Başka bir bilgisayarda yönetici olan biri
  kendi belleğini aynı kimlikle damgalayabilir. Kararlı birine karşı değil, gelişigüzel kopyalamaya
  karşı işe yarar.
- Lab diskleri şifreli ama taşınabilirdir: parolası bilinen bir lab diskine XWF kopyalanıp başka
  bilgisayarda açılabilir. Parolalar ve kurtarma parolaları yöneticide kalmalı, diskler imza
  karşılığı verilmelidir.
- Bir kullanıcı profilinde "Çıkarılabilir Diskler: Yazmayı reddet" **kullanıcı** ilkesi açıksa
  BitLocker ilkesi o kullanıcı için çalışmaz. Durum ekranı bunu uyarı olarak gösterir.
- Bu ilke yalnızca BitLocker'ın **"çıkarılabilir veri sürücüsü"** saydığı aygıtları kapsar. Sabit
  disk sayılan harici diskler (Thunderbolt, eSATA, bazı USB SSD'ler) bu modda **hiç engellenmez**.
  Durum ve Test ekranı bunları "BitLocker modu KAPSAMAZ" diye işaretler.
- İşletim sistemi diskinin BitLocker'ı USB başlangıç anahtarı kullanıyorsa ya da kurtarma
  anahtarını USB'ye kaydediyorsa bu mod onunla çakışır (Microsoft'un belirttiği kısıt).
- Kapat ve tam engel, bu modun yazdığı `FVE` değerlerini siler. Kuruluşunuz `IdentificationField`
  değerlerini başka bir amaçla (ör. veri kurtarma aracısı) kullanıyorsa bu modu kullanmayın.

## Etki alanı / Intune

- Makine bir etki alanındaysa, aynı ilkeyi "Devre dışı" yapan bir GPO buradaki değerlerin üzerine
  yazar. Etki alanında bu ayarları **GPO ile** dağıtın (Bilgisayar Yapılandırması > Yönetim
  Şablonları > Sistem > Çıkarılabilir Depolama Erişimi).
- Intune'daki `Storage/RemovableDiskDenyWriteAccess` gibi ayarlar aynı kayıt değerlerini yazar.

## Kaynaklar

- Grup İlkesi tanımları: `C:\Windows\PolicyDefinitions\RemovableStorage.admx`, `VolumeEncryption.admx`
- [Microsoft: Removable storage policy troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/windows-server/group-policy/removable-devices-group-policy-troubleshooting-guidance)
- [Microsoft: Policy CSP – Storage (WPD uyarısı)](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-storage)
- [Microsoft Q&A: StorageDevicePolicies and UASP](https://learn.microsoft.com/en-us/answers/questions/3a8b46cd-6532-4aa1-b3bb-b39ff53ff9a4/storagedevicepolicies-and-uasp?forum=windows-all)
- [CCL: NVMe, UASP and write-blocking using the Windows registry (2018)](https://malware.news/t/nvme-uasp-and-write-blocking-using-the-windows-registry/23611)
- [USB write blocking with registry – beware (2015)](https://forensenellanebbia.blogspot.com/2015/08/usb-write-blocking-with-registry-beware.html)
- [PassMark OSForensics: USB write-block limitations (2025)](https://forums.passmark.com/osforensics-osfmount-osfclone/58657-usb-write-block-feature-%E2%80%93-limitations-findings)
- [Microsoft: BitLocker yapılandırması](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/configure)
- [Microsoft: Aygıt yükleme kısıtlamaları](https://learn.microsoft.com/en-us/windows/client-management/client-tools/manage-device-installation-with-group-policy)
- X-Ways: [forensics](https://www.x-ways.net/forensics/), [dongle](https://www.x-ways.net/dongle.html), [BYOD](https://www.x-ways.net/BYOD.html), [BYOD+](https://www.x-ways.net/BYOD+.html)

---

## English

Blocks copying files from lab PCs to USB sticks, external disks, phones (MTP) and CD/DVD.
**Reading stays allowed**; only writing is blocked.

Goal: make it harder to carry the X-Ways Forensics (XWF) folder out of the lab on a portable
device. Read the limits first ([What it does not block](#what-it-does-not-block)). Above all,
anyone with a local administrator account can undo this in two clicks.

The menu, messages and command-line values are in Turkish. The names are explained below.

### Files

| File | Purpose |
|---|---|
| `usb_yazma_korumasi_ac.reg` | Double-click → turns protection **on** (both layers) |
| `usb_yazma_korumasi_kapat.reg` | Double-click → turns protection **off** (removes the same values) |
| `UsbYazmaKorumasi.cmd` | Opens the menu: on / off / status / test / restart / BitLocker allow-list / prepare lab disk |
| `UsbYazmaKorumasi.ps1` | The script behind the menu; also usable from the command line |

The `.reg` files only turn full blocking on and off. The
[BitLocker allow-list](#if-the-lab-needs-to-write-to-its-own-disks-bitlocker-allow-list) mode is
turned on from the menu or the command line.

### Usage

**Simplest:** double-click `usb_yazma_korumasi_ac.reg` → *Yes* → **restart the computer**.

**With the menu:** double-click `UsbYazmaKorumasi.cmd` → *Yes* at the UAC prompt.

| Menu | Meaning |
|---|---|
| `1) Korumayı AÇ (tam engel)` | Turn protection on (full block) |
| `2) Korumayı KAPAT` | Turn protection off |
| `3) Ayrıntılı durum` | Detailed status: settings, attached drives, warnings (changes nothing) |
| `4) Bağlı sürücülere yazma testi` | Write test on attached drives |
| `5) Bilgisayarı yeniden başlat` | Restart the computer (in 30 s; cancel with `shutdown /a`) |
| `6) Korumayı AÇ: BitLocker izin listesi` | Turn protection on in BitLocker allow-list mode (only lab disks writable) |
| `7) Lab diski hazırla` | Prepare a lab disk (BitLocker + lab identifier) |
| `0) Çıkış` | Exit |

**From the command line** (for deploying to several machines). `Ac` = on, `Kapat` = off,
`Durum` = status, `Test` = write test, `BitLocker` = allow-list mode, `Hazirla` = prepare lab disk:

```bat
UsbYazmaKorumasi.cmd -Islem Ac
UsbYazmaKorumasi.cmd -Islem Durum
UsbYazmaKorumasi.cmd -Islem Test
UsbYazmaKorumasi.cmd -Islem Kapat
UsbYazmaKorumasi.cmd -Islem BitLocker -LabKimligi ANKARA-LAB
UsbYazmaKorumasi.cmd -Islem Hazirla -Surucu E
```

If not run as administrator, the script elevates itself through UAC and returns the elevated
window's exit code: `0` success, `1` error, `2` the test could write to at least one drive that is
not a lab disk. Run by a
deployment tool under the SYSTEM account, no UAC prompt appears.

On, off and test actions are logged with date and user name to
`%ProgramData%\UsbYazmaKorumasi\islem.log`. Changes made with the `.reg` files are not logged.

### How it works: two layers

The single registry value that is widely recommended online
(`StorageDevicePolicies\WriteProtect`) is not enough on its own. A scan of every driver file on the
test machine (Windows 11 Pro 25H2, build 26200) shows that **only `usbstor.sys`** reads it;
`uaspstor.sys`, `sdstor.sys`, `stornvme.sys` and `disk.sys` do not. So a second layer was added:

| | Layer 1: `StorageDevicePolicies\WriteProtect` | Layer 2: Removable Storage Access policy |
|---|---|---|
| Registry | `HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{class GUID}\Deny_Write` |
| Enforced by | the `usbstor.sys` driver | the WPDBusEnum service (changes the device's access permissions) |
| USB stick (classic, BOT) | ✅ | ✅ |
| USB 3 SSD/NVMe enclosure (UASP) | ❌ | ✅ (per documentation; test with your device) |
| External HDD (shown as "Local Disk") | only if on usbstor | ✅ (per documentation) |
| Internal SD card slot (PCIe/SD bus) | ❌ | ❓ unclear, test it |
| Phone / camera (MTP, PTP) | ❌ | ✅ WPD policy (both GUIDs together) |
| CD/DVD burning | ❌ | ✅ Windows burning; third-party software may bypass it |
| Thunderbolt / USB4 NVMe | ❌ | ❓ unclear, test it |
| eSATA / hot-swap SATA bay | ❌ | ❓ unclear, test it (see the side effect below) |

> **Side effect: internal hot-swap bays.** Layer 2 picks disks by whether Windows treats them as
> hot-pluggable, not by whether they are USB. Internal disks on SATA/eSATA ports with hot-plug
> enabled in the BIOS can become read-only too; they appear in the "Safely Remove Hardware" list.
> On forensic workstations case drives often sit in such bays: after turning protection on, check
> that the drives XWF writes its output to are still writable. For a bay that must stay writable,
> disable Hot Plug for that port in the BIOS.

Layer 2 value names and GUIDs were taken verbatim from the local
`C:\Windows\PolicyDefinitions\RemovableStorage.admx`:

| Policy | Subkey |
|---|---|
| Removable Disks | `{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}` |
| WPD Devices (both together) | `{6AC27878-A6FA-4155-BA85-F98F491D4F33}` and `{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}` |
| CD and DVD | `{53f56308-b6bf-11d0-94f2-00a0c91efb8b}` |
| Floppy Drives | `{53f56311-b6bf-11d0-94f2-00a0c91efb8b}` |
| Tape Drives | `{53f5630b-b6bf-11d0-94f2-00a0c91efb8b}` |

> Common mistake: writing `Deny_Write` directly under `RemovableStorageDevices`. No policy is
> defined there and nothing happens. The value must sit in the class-GUID subkey.

Values written directly to the registry **do not show up** in `gpedit.msc` or `gpresult`, but they
are enforced. Do not let an audit conclude "no policy is set".

### When it takes effect

- **Devices already attached are not affected.** They stay writable until unplugged and replugged.
- **Layer 2** usually applies at once to newly attached devices. For devices in use, Microsoft
  says the change "does not take effect until the operating system is restarted".
  **Restart after turning it on.**
- **After turning it off**, replug devices too; some need a restart.

### Verification (on every machine and after every Windows update)

1. **Baseline (protection OFF):** attach every kind of device the lab has: classic USB stick, USB 3
   SSD enclosure, external disk, SD card (both in a USB reader and in the internal slot) and an
   Android phone. Run menu item **4**. All must show **YAZILABİLİR** (writable). A device that does
   not (full, SD card with the lock switch on, etc.) cannot be used to verify protection.
2. Turn protection on and restart.
3. Attach the same devices and run item **4** again. Results:
   - green **ENGELLENDİ**: blocked, the device is protected;
   - red **YAZILABİLİR**: writable, the device is NOT protected (the test file is deleted);
   - yellow **BELİRSİZ**: inconclusive, the write failed for another reason (disk full, I/O error).
4. The script writes automatically only to USB/SD/removable drives. It lists Thunderbolt, eSATA and
   hot-swap-bay disks but does **not** write to them, because they may hold evidence. Test those
   and the phone (MTP) by hand by copying a file in Explorer. The status screen also shows which
   driver each drive uses (usbstor / UASP).

In 2025 Microsoft reported that some updates (KB5058379, KB5050092, KB5062552) silently broke
enforcement of this policy, fixed with a Known Issue Rollback. Re-run the test after updates.

### What it does not block

**1. Administrator accounts. This is the biggest gap.** Every setting here is a registry value. A
local administrator can delete the values, stop the WPDBusEnum service, copy as SYSTEM (the policy
does not apply to SYSTEM) or load a driver. Staff should work with **standard user** accounts and
the administrator password should be separate and known to few people. The status screen lists
administrator accounts.

> **Conflict with XWF:** according to the XWF manual, sector-level access to a physical disk needs
> administrator rights. If examiners are administrators, this protection is meaningless for them.
> Options:
> - examiners work on images (E01) as standard users; an administrator or a hardware imager makes
>   the image;
> - when raw disk access is needed, an administrator elevates XWF with their own password.
>   **Caution:** an elevated XWF gives the examiner administrator rights for that session. From
>   inside XWF ("Execute", open with an external program, file dialogs) an elevated cmd or regedit
>   can be started and the protection removed. The administrator should stay until the work is
>   done and close XWF afterwards;
> - or administrators are trusted anyway and the real protection is custody of the license key
>   (see below).

**2. Network and internet:** file shares (SMB), OneDrive/Dropbox, webmail, browser uploads, e-mail.
XWF is only a few MB, so it leaves easily this way. This tool does not cover the network; handle
outbound traffic at the network level (router or company firewall) together with your IT team. For
OneDrive, `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1` can be used.

Unplugging the network cable is not enough:
- **Wi-Fi:** a standard user can join a hotspot. Disable the wireless card in UEFI.
- **USB tethering from a phone:** the phone attaches as a network adapter (RNDIS/NCM), not as a
  storage device. The WPD block does not apply and the driver installs without administrator
  rights. Block the RNDIS/NCM compatible IDs with Device Installation Restrictions.

**3. Bluetooth file transfer** and **outgoing RDP sessions** (local drives are redirected to the
remote machine). Disable Bluetooth in UEFI or as a service; restrict outgoing RDP at the network
level.

**4. Partial or unclear:**
- ADB (`adb push`) does not use WPD and is most likely not blocked.
- Writing to an iPhone with Apple software is unclear.
- Third-party CD burning programs may bypass the CD/DVD policy.

**5. Physical access:** booting a live system from USB, or removing the disk and attaching it to
another machine, bypasses every Windows setting. Countermeasures: UEFI administrator password,
USB boot disabled, Secure Boot and BitLocker on the system disk.

**6. This is NOT a forensic write-blocker.** It may look like it makes evidence disks read-only,
but there are UASP, SD and NVMe gaps. Whether Layer 1 stops raw sector writes by a disk editor
running as administrator (WinHex/XWF) is also undocumented. Keep using a hardware write-blocker
for evidence acquisition.

### What really needs protecting for XWF: the license key

According to the official x-ways.net pages, XWF needs no installation and runs from a folder or a
USB stick. The full product only opens when a key is present:

- **Local dongle** (USB) or **network dongle**.
- **BYOD:** the customer's own USB stick, external disk or internal disk becomes the key; that
  device must be attached to the computer.
- **BYOD+:** the X-Ways server acts as an online key; internet access is needed while running.

So copying the folder alone is not enough to open the full product without a key. What matters:

- Who holds the dongle or BYOD device. Making an internal disk the BYOD key, or locking the dongle
  inside the case, ties the license to that machine.
- For **BYOD+** and the **network dongle**, the official pages do not say clearly whether a copied
  folder would run on another machine; ask X-Ways.
- If your BYOD key is a USB stick, check after turning protection on that XWF still starts (the key
  stick is now read-only).

### If the lab needs to write to its own disks: BitLocker allow-list

With full blocking on, reports and images cannot be written to external disks either. For that
there is a second mode: **only BitLocker disks stamped with the lab identifier are writable**; every
other USB stick and disk stays read-only. The phone (MTP), CD/DVD, floppy and tape blocks stay on in
this mode too.

> This mode was not tried with real BitLocker disks. Mode switching, the registry values and the
> lab-disk preparation steps were tested with simulated drives. Try it on one machine first.

**Setup:**

1. Menu **6** → enter the lab identifier (e.g. `ANKARA-LAB`; letters, digits, `.` `-` `_`).
   Command line: `UsbYazmaKorumasi.cmd -Islem BitLocker -LabKimligi ANKARA-LAB`
2. Attach each lab disk, menu **7** → drive letter.
   Command line: `UsbYazmaKorumasi.cmd -Islem Hazirla -Surucu E`
   - If the disk has no BitLocker, it is encrypted. You are asked for a password and a **48-digit
     recovery password** is printed; store it somewhere safe. Data is not erased, but do not
     unplug the disk until it finishes.
   - If the disk already has BitLocker, it is only stamped with the lab identifier
     (`manage-bde -SetIdentifier`).
3. Unplug and replug the disk, unlock it, restart the computer.
4. Menu **4** (write test): lab disks must show green **YAZILABİLİR (lab diski: beklenen)**
   (writable, expected for a lab disk), all others **ENGELLENDİ** (blocked). The status screen shows
   each disk's BitLocker state and identifier.

**Values written** (checked against `VolumeEncryption.admx`):

| Setting | Value |
|---|---|
| Deny write access to removable drives not protected by BitLocker | `HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE` → `RDVDenyWriteAccess = 1` |
| Do not allow write access to devices configured in another organization | `HKLM\SOFTWARE\Policies\Microsoft\FVE` → `RDVDenyCrossOrg = 1` |
| Organization identifier | same key → `IdentificationField = 1`; `IdentificationFieldString` and `SecondaryIdentificationField` = lab identifier |
| Staff cannot turn BitLocker on or off | same key → `RDVConfigureBDE = 1`, `RDVAllowBDE = 0`, `RDVDisableBDE = 0` |

In this mode Layer 1 and the Removable Disks `Deny_Write` value are removed. If they stayed on, the
BitLocker policy would be ignored and lab disks would be read-only too. While preparing a lab disk,
the script sets `RDVAllowBDE` to 1 for the duration of the encryption and back to 0 afterwards, even
on error.

Notes:
- The `.reg` files do not turn this mode on, but they remove its values: `ac.reg` switches to full
  blocking, `kapat.reg` to no protection.
- The identifier string is not secret; every user can read it. Anyone who is administrator on
  another computer can stamp their own stick with the same identifier. This stops casual copying,
  not a determined insider.
- Lab disks are encrypted but portable: XWF can be copied to a lab disk whose password is known and
  opened on another computer. Passwords and recovery passwords must stay with the administrator,
  and disks should be signed out and in.
- If the **user** policy "Removable Disks: Deny write access" is on in a user profile, the BitLocker
  policy does not work for that user. The status screen shows this as a warning.
- This policy only covers what BitLocker counts as a **"removable data drive"**. External disks
  treated as fixed disks (Thunderbolt, eSATA, some USB SSDs) are **not blocked at all** in this
  mode. The status and test screens mark them "BitLocker modu KAPSAMAZ" (not covered).
- If BitLocker on the operating-system disk uses a USB startup key, or saves its recovery key to
  USB, this mode conflicts with it (a restriction stated by Microsoft).
- Turning protection off and full blocking both delete the `FVE` values this mode writes. If your
  organization uses the `IdentificationField` values for another purpose (e.g. a data recovery
  agent), do not use this mode.

### Domain / Intune

- If the machine is in a domain, a GPO that sets the same policy to "Disabled" overwrites these
  values. In a domain, deploy these settings **through GPO** (Computer Configuration >
  Administrative Templates > System > Removable Storage Access).
- Intune settings such as `Storage/RemovableDiskDenyWriteAccess` write the same registry values.

### References

See [Kaynaklar](#kaynaklar) above; the links are the same.

---

## Lisans · License

MIT. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakın. Bu araç kayıt defterini değiştirir;
kendi sorumluluğunuzda ve önce bir test makinesinde kullanın.

MIT. See [LICENSE](LICENSE). This tool changes the registry; use it at your own risk and try it on
a test machine first.
