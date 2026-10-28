# Web'den bakım kaydı: ara depo kurulumu

Uygulaması olmayan bir telefon, cihazın karekodunu okutup bakım kaydı bırakabilsin diye
araya küçük bir "ara depo" konur. Ücretsiz Google hesabınız yeterlidir; sunucu gerekmez.

```
Karekodu okutan telefon ──► cihaz sayfası (GitHub Pages) ──► Google Apps Script + Sheet
                                                                  ▲
Sizin telefonunuz (Homecare) ── açılışta kayıtları çeker, cihazları gönderir ─┘
```

## Kurulum (yaklaşık 10 dakika)

1. **Sheet oluşturun.** <https://sheets.new> adresinden boş bir tablo açın, adını "Homecare Ara Depo" yapın.
2. **Betiği ekleyin.** Tabloda `Uzantılar → Apps Script`. Açılan düzenleyicide `Code.gs` içindeki her şeyi
   silip bu klasördeki [`Code.gs`](Code.gs) dosyasının içeriğini yapıştırın, kaydedin.
3. **Gizli anahtarı belirleyin.** Sol menüde dişli simgesi (`Proje ayarları`) → aşağıda `Betik özellikleri`
   → `Betik özelliği ekle`: ad **`SECRET`**, değer en az 12 karakterlik rastgele bir metin
   (ör. bir parola yöneticisinden). Bu anahtarı bir yere not edin, 6. adımda lazım.
4. **Web uygulaması olarak yayınlayın.** Sağ üstte `Dağıt → Yeni dağıtım`, dişli simgesinden
   `Web uygulaması` seçin:
   - **Şu kullanıcı olarak çalıştır:** Ben
   - **Erişimi olan:** **Herkes** (“Google hesabı olanlar” değil; aksi hâlde uygulamasız telefonlar giriş sayfası görür)

   `Dağıt`a basın, istenen izinleri verin (Sheet'inize erişim). Çıkan, **`/exec` ile biten** Web uygulaması URL'sini kopyalayın.
5. **Adresi web sayfasına yazın.** Depodaki [`docs/config.js`](../../docs/config.js) dosyasında
   `window.HOMECARE_BACKEND_URL = '...';` satırına URL'yi yapıştırın, commit edip GitHub'a gönderin
   (GitHub Pages bir iki dakikada günceller).
6. **Uygulamayı ayarlayın.** Homecare → Ayarlar → **Eşitleme Adresi** (aynı URL) ve **Eşitleme Anahtarı**
   (3. adımdaki `SECRET`). Sonra **Şimdi Eşitle**: cihazlarınız ara depoya gönderilir.
7. **Karekodları yeniden yazdırın.** Her cihazın karekoduna o cihaza özel bir anahtar eklenir; anahtarsız eski
   karekodlarla web'den kayıt yapılamaz (uygulamanın kendi tarayıcısı eskisi gibi çalışır).

### Doğru kurulduğunu denemek

- Tarayıcıda `URL?action=ping&key=SECRET` adresini açın (URL ve SECRET yerine kendi değerleriniz). `{"ok":true}` görmelisiniz.
  `forbidden` anahtarın yanlış olduğunu, Google giriş sayfası görürseniz 4. adımdaki “Herkes” ayarının yapılmadığını gösterir.
- Bir cihazın karekodunu telefonun kamerasıyla okutun: cihaz sayfası ve görev listesi açılmalı.
  Bir görev seçip **Bakımı Kaydet**'e basın. Sheet'te `Kayitlar` sayfasında satır belirir.
- Uygulamayı açın (ya da Ayarlar → Şimdi Eşitle): "Web'den 1 bakım kaydı eklendi" yazar, Geçmiş'te kayıt
  “Web'den” işaretiyle görünür.

Betiği sonradan değiştirirseniz `Dağıt → Dağıtımları yönet → düzenle → Yeni sürüm` demeniz gerekir;
yoksa eski sürüm çalışmaya devam eder.

## Nasıl çalışır, neye dikkat etmeli?

- **İki tür anahtar.** Sahip anahtarı (`SECRET`) yalnızca uygulamadadır: cihaz yükler, bekleyen kayıtları çeker.
  Karekoda yazılan anahtar `HMAC-SHA256(SECRET, cihaz numarası)`'nın ilk 16 hanesidir: **yalnızca o cihazın**
  bilgisini okur ve o cihaza kayıt bırakır. Birinin karekodun fotoğrafını çekmesi diğer cihazları açmaz, ama o cihazın
  bilgisini (servis, notlar dahil) görmesini ve sahte kayıt bırakmasını sağlar. Evdeki kullanım için makul bir
  ödünleşimdir; aşırı kayıt bırakılırsa bekleyen kayıt sınırı (500) ve 60 sn tekrar koruması devreye girer.
- **Sahte kaydı fark edersiniz.** Web'den gelen her kayıt geçmişte “Web'den” işaretiyle görünür.
- **Veriler sizde kalır.** Cihaz bilgileri ve kayıtlar yalnızca sizin Google hesabınızdaki Sheet'te durur,
  herkese açık bir depoya yazılmaz. Eski GitHub token ile eşitleme isteğe bağlı olarak çalışmaya devam eder
  ama artık gerekmez; `docs/config.js` doluyken sayfa verileri Sheet'ten alır.
- **Tek sahip telefonu.** Kayıtlar çekilince “alındı” işaretlenir; aynı anahtarla iki telefon eşitlenirse
  kaydı yalnızca ilk çeken telefon görür.
- **`SECRET`'ı değiştirirseniz** uygulamadaki anahtarı da güncelleyin ve karekodları yeniden yazdırın.
- Kayıt zamanı **sunucu saatidir**; telefonun saati yanlış olsa da kayıt doğru tarihle düşer.

## Yerelde deneme (Google'a bağlanmadan)

```bash
node --test backend/apps-script/Code.test.js   # betik mantığının testleri
node backend/apps-script/serve.js              # sayfa + taklit ara depo; çıktıdaki adresi tarayıcıda açın
```
