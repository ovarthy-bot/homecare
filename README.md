<div align="center">
  
  <img src="https://via.placeholder.com/150/121212/3F51B5?text=Ev+Sagligi" alt="Ev Sağlığı Logo" width="120">

  # 🏠 Ev Sağlığı (Homecare)

  **Akıllı Ev Aletleri ve Cihaz Bakım Takip Uygulaması**

  [![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
  [![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)](#)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](#)
  [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg?style=for-the-badge)](#)

  [Özellikler](#-özellikler) • [Nasıl Çalışır?](#-nasıl-çalışır) • [Kurulum](#-kurulum) • [Katkıda Bulunma](#-katkıda-bulunma)

</div>

---

## 🌟 Hakkında

**Ev Sağlığı (Homecare)**, evinizdeki beyaz eşyaların, klimaların, su arıtma cihazlarının ve diğer elektronik aletlerin bakım sürelerini takip etmenizi sağlayan modern bir mobil uygulamadır. 

Filtre değişimlerini unutmaya, cihazların kireçlenmesine veya garanti belgelerini kaybetmeye son! Geliştirdiğimiz **Akıllı Karekod (QR) Sistemi** sayesinde, cihazınızın üzerine yapıştırdığınız karekodu okutarak anında bakım kaydı oluşturabilir ve bir sonraki bakım için otomatik hatırlatıcı kurabilirsiniz.

## ✨ Özellikler

*   📱 **Kapsamlı Cihaz Yönetimi:** Cihazlarınızı odalara veya kategorilere göre ayırın.
*   🔗 **Akıllı Karekod (QR) Entegrasyonu:** Her cihaza özel QR kod oluşturun. Bakım yaptığınızda kamerayla taratarak işlemi saniyeler içinde sisteme kaydedin.
*   🔔 **Otomatik Hatırlatıcılar:** "Filtre değişimi yaklaştı", "Kireç çözme zamanı" gibi özelleştirilebilir bildirimler alın.
*   📄 **Belge ve Garanti Takibi:** Cihaz faturası, garanti belgesi ve kullanım kılavuzlarını dijital olarak saklayın.
*   🛡️ **Çevrimdışı Çalışma (Offline-First):** İnternet bağlantısına ihtiyaç duymadan verilerinize erişin ve güncelleyin. Verileriniz cihazınızda güvende kalır.
*   🌙 **Modern ve Karanlık Tema (Dark Mode):** Göz yormayan, şık kullanıcı arayüzü.

## 🚀 Nasıl Çalışır?

1.  **Ekle:** Uygulamaya cihazınızı ekleyin (Örn: Mutfak Su Arıtma Cihazı).
2.  **Yazdır:** Sistemden o cihaza özel üretilen QR kodun çıktısını alın.
3.  **Yapıştır:** Çıktıyı cihazın uygun bir yerine yapıştırın.
4.  **Tara ve Kaydet:** Bakım / filtre değişimi yaptığınızda uygulamayı açın, QR kodu okutun ve bakımı onaylayın. Sıradaki tarihi uygulama sizin için takip etsin!

## 📸 Ekran Görüntüleri

| Ana Sayfa | Cihaz Detayı | QR Tarama |
| :---: | :---: | :---: |
| <img src="https://via.placeholder.com/250x500/1E1E1E/FFFFFF?text=Ana+Sayfa" width="200"> | <img src="https://via.placeholder.com/250x500/1E1E1E/FFFFFF?text=Cihaz+Detayi" width="200"> | <img src="https://via.placeholder.com/250x500/1E1E1E/FFFFFF?text=QR+Tarama" width="200"> |

*(Buraya projenizin gerçek ekran görüntülerini ekleyebilirsiniz.)*

## 🛠️ Teknik Detaylar

Bu proje **Flutter** kullanılarak geliştirilmiştir. 

*   **Framework:** Flutter (SDK >=3.0.0)
*   **Dil:** Dart
*   **Yerel Veritabanı:** Hive / Isar / SQLite *(Projede kullandığınızı yazabilirsiniz)*
*   **Durum Yönetimi (State Management):** Provider / Riverpod / Bloc *(Projede kullandığınızı yazabilirsiniz)*
*   **Paketler:** `qr_code_scanner`, `flutter_local_notifications`, vb.

## 💻 Kurulum

Projeyi kendi bilgisayarınızda çalıştırmak için aşağıdaki adımları izleyin:

1. Depoyu klonlayın:
   ```bash
   git clone https://github.com/KULLANICI_ADINIZ/ev-saglisi-homecare.git
   ```
2. Proje dizinine gidin:
   ```bash
   cd ev-saglisi-homecare
   ```
3. Gerekli paketleri indirin:
   ```bash
   flutter pub get
   ```
4. Uygulamayı çalıştırın:
   ```bash
   flutter run
   ```

## 🤝 Katkıda Bulunma

Bu proje açık kaynaktır ve her türlü katkıya (Pull Request, Bug Report, Feature Request) açıktır. Katkıda bulunmak isterseniz lütfen önce bir "Issue" açarak fikrinizi belirtin.

1. Bu depoyu forklayın.
2. Yeni bir dal (branch) oluşturun: `git checkout -b ozellik/YeniHarikaOzellik`
3. Değişikliklerinizi commit edin: `git commit -m 'Yeni harika özellik eklendi'`
4. Dalınıza push yapın: `git push origin ozellik/YeniHarikaOzellik`
5. Bir Pull Request oluşturun.

## 📝 Lisans

Bu proje **MIT Lisansı** ile lisanslanmıştır. Daha fazla bilgi için [LICENSE](LICENSE) dosyasına göz atabilirsiniz.

---
*Evinizin sağlığı bizim için önemli! 💙 Destek olmak isterseniz projeye ⭐ (Yıldız) vermeyi unutmayın.*