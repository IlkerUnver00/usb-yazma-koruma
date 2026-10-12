# USB Yazma Koruması

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
| `UsbYazmaKorumasi.cmd` | Menüyü açar: Aç / Kapat / Durum / Test / Yeniden başlat |
| `UsbYazmaKorumasi.ps1` | Menünün asıl scripti; komut satırından da kullanılır |

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
```

Script yönetici değilse UAC ile kendini yükseltir ve yükseltilmiş pencerenin çıkış kodunu geri verir.
Çıkış kodları: `0` başarılı, `1` hata, `2` Test en az bir sürücüye yazabildi. Dağıtım aracıyla
SYSTEM hesabında çalıştırırsanız UAC penceresi açılmaz.

Aç, Kapat ve Test işlemleri `%ProgramData%\UsbYazmaKorumasi\islem.log` dosyasına tarih ve kullanıcı
adıyla kaydedilir. `.reg` dosyalarıyla yapılan değişiklikler bu günlüğe girmez.

## Ne yapar: iki katman

Yapıştırdığınız tek anahtar (`StorageDevicePolicies\WriteProtect`) tek başına yetmiyor. Bu makinede
(Windows 11 Pro 25H2, derleme 26200) tüm sürücü dosyaları tarandı. Bu değeri **yalnızca
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

## Laboratuvarın kendi disklerine yazması gerekiyorsa

Bu koruma açıkken rapor veya imaj da harici diske yazılamaz. İzin listesi gerekiyorsa Windows Pro'da
yerleşik bir seçenek var: **yalnızca laboratuvarın BitLocker'lı disklerine yazma izni.** Aşağıdaki
değerler `VolumeEncryption.admx` ile doğrulandı ama **bu script tarafından uygulanmıyor ve test
edilmedi.** Önce tek bir makinede deneyin.

| Ayar | Değer |
|---|---|
| BitLocker'la korunmayan çıkarılabilir sürücülere yazmayı reddet | `HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE` → `RDVDenyWriteAccess = 1` |
| Başka kuruluşta yapılandırılmış aygıtlara yazma izni verme | `HKLM\SOFTWARE\Policies\Microsoft\FVE` → `RDVDenyCrossOrg = 1` |
| Kuruluş tanımlayıcısı | aynı anahtar → `IdentificationField = 1`, `IdentificationFieldString = "<lab-kimliği>"` |
| Kullanıcılar kendi belleğini şifreleyemesin | aynı anahtar → `RDVConfigureBDE = 1`, `RDVAllowBDE = 0` |

Dikkat edilecekler:
- Bu yöntem, bu scriptin **Katman 1**'i ve **"Çıkarılabilir Diskler" Deny_Write** değeriyle
  birlikte kullanılamaz; Deny_Write açıkken BitLocker ilkesi yok sayılır. WPD ve CD/DVD değerleri
  kalabilir.
- `RDVAllowBDE = 0` yapılmazsa personel kendi belleğini bu makinede şifreler. Bellek otomatik olarak
  lab kimliğiyle damgalanır ve yazılabilir olur.
- Kimlik dizesi gizli değildir; her kullanıcı okuyabilir. Kararlı birine karşı değil, gelişigüzel
  kopyalamaya karşı işe yarar.
- Lab diskleri şifreli ama taşınabilirdir. Parolaları ve kurtarma anahtarları yöneticide kalmalı,
  diskler imza karşılığı verilmelidir.
- Bu ilke yalnızca BitLocker'ın **"çıkarılabilir veri sürücüsü"** saydığı aygıtları kapsar.
  Sabit disk olarak görünen harici diskler (Thunderbolt, eSATA, bazı USB SSD'ler) bu modda hiç
  engellenmeyebilir. Karşılığı olan "BitLocker'la korunmayan sabit sürücülere yazmayı reddet"
  (`FDVDenyWriteAccess`) ilkesi ise BitLocker'sız tüm dahili veri disklerini de salt okunur yapar.
  Her aygıt türünün nasıl sınıflandığını `manage-bde -status` ile kontrol edin ve Gezgin'den test
  edin.

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

## Lisans

MIT. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakın. Bu araç kayıt defterini değiştirir;
kendi sorumluluğunuzda ve önce bir test makinesinde kullanın.
