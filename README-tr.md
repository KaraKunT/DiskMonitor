# Disk İzleme Scripti

Bu script, Debian tabanlı sunucularda disk ve RAM kullanımını izlemek ve belirlenen eşiklerin aşılması durumunda e-posta ile bildirim göndermek için tasarlanmıştır.

📌 **[Click here for English](README.md)**

## 🚀 Kurulum

Aşağıdaki komut ile scripti indirip kurulumu başlatabilirsiniz:

```bash
curl -fsSL https://raw.githubusercontent.com/KaraKunT/DiskMonitor/main/disk-monitor-tr.sh -o /usr/local/bin/disk-monitor.sh && chmod +x /usr/local/bin/disk-monitor.sh && /usr/local/bin/disk-monitor.sh --init
```

veya

```bash
wget -qO /usr/local/bin/disk-monitor.sh https://raw.githubusercontent.com/KaraKunT/DiskMonitor/main/disk-monitor-tr.sh && chmod +x /usr/local/bin/disk-monitor.sh && /usr/local/bin/disk-monitor.sh --init
```

## 📌 Özellikler

- 📊 Disk kullanımını belirlenen eşiklere göre izler ve uyarı verir.
- 💾 RAM kullanımını kontrol eder ve kritik seviyelerde bildirim yapar.
- 📧 SMTP üzerinden e-posta bildirim desteği.
- 🛠 Kolay yapılandırma için interaktif kurulum sihirbazı.
- 🔄 Periyodik kontroller için otomatik crontab ekleme.

## 📖 Kullanım

Scripti çalıştırmak için aşağıdaki komutu kullanabilirsiniz:

```bash
/usr/local/bin/disk-monitor.sh
```

İlk kez çalıştırıldığında, interaktif bir kurulum sihirbazı açılacaktır ve disk seçimi, RAM eşiği ve e-posta bildirim ayarlarını yapılandırmanıza yardımcı olacaktır.

### 🛠 Ayarları Güncelleme

Mevcut ayarları yeniden yapılandırmak için aşağıdaki komutu çalıştırabilirsiniz:

```bash
/usr/local/bin/disk-monitor.sh --init
```

Bu işlem, önceki ayarları silmeden yapılandırmayı güncelleyecektir.

## 📜 Konfigürasyon Dosyası

Script, yapılandırma ayarlarını `/etc/disk-monitor.conf` dosyasına kaydeder. Manuel olarak düzenlemek isterseniz içeriği şu şekilde olabilir:

```bash
# Disk İzleme Konfigürasyonu
/dev/sda1 10
/dev/sdb2 15

# RAM Eşik Değeri%
RAM 25

# E-posta Ayarları
EMAIL_TO=ornek@example.com
EMAIL_FROM=noreply@example.com
SMTP_SERVER=smtp.example.com
SMTP_PORT=587
SMTP_USER=kullaniciadi
SMTP_PASS=sifre
```

## 📅 Crontab ile Otomatik Çalıştırma

Script, kurulum sırasında otomatik olarak `crontab` içerisine eklenir ve varsayılan olarak her 5 dakikada bir çalışır. Eğer zamanlamayı değiştirmek isterseniz:

```bash
crontab -e
```

Frekansı değiştirmek için ilgili satırı düzenleyin:

```bash
*/5 * * * * /usr/local/bin/disk-monitor.sh
```

Örneğin, her 10 dakikada bir çalışmasını isterseniz:

```bash
*/10 * * * * /usr/local/bin/disk-monitor.sh
```

## 📩 E-posta Bildirimleri

Eğer izlenen disk veya RAM kullanımı belirlenen eşik değerlerini aşarsa, sistem otomatik olarak belirtilen e-posta adresine bir uyarı mesajı gönderecektir.

### 🔎 Logları İnceleme

Script çalışmaları `/var/log/disk-monitor.log` dosyasına kaydedilir. Logları görmek için şu komutu kullanabilirsiniz:

```bash
tail -f /var/log/disk-monitor.log
```

## 🛠 Bağımlılıklar

Bu scriptin çalışabilmesi için `curl` gereklidir. Eğer sisteminizde yüklü değilse aşağıdaki komutla yükleyebilirsiniz:

```bash
apt update && apt install -y curl
```

## 📌 Desteklenen İşletim Sistemleri

- Debian 10+ (Buster, Bullseye, Bookworm)
- Ubuntu 20.04+

## 🤝 Katkıda Bulunma

Projeye katkıda bulunmak için pull request gönderebilirsiniz.

---

📌 **GitHub:** [KaraKunT/DiskMonitor](https://github.com/KaraKunT/DiskMonitor)
