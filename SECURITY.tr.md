# Güvenlik politikası

[English](SECURITY.md) · **Türkçe**

Trailwarden yerel ajan transkriptlerini okur ve aynı makinede bir denetim indeksi
oluşturur. Ajanlarına dair hiçbir şey makineden çıkmaz. Tek ağ çağrısı
`Sources/TrailwardenApp/Update/UpdateChecker.swift` içindeki güncelleme denetimidir:
küçük bir JSON dosyası için bir GET isteği. Bu istek, "Güncellemeleri denetle"ye
tıkladığında ya da açabileceğin haftalık/aylık takvimde (varsayılan olarak kapalı)
yapılır. `URLSession`, `NSURLConnection`, `URLRequest`, `CFNetwork` veya
`import Network` `Sources/` altındaki başka bir dosyada görünürse CI başarısız olur.

## Güvenlik açığı bildirmek

Lütfen herkese açık bir issue yerine GitHub'da özel bir güvenlik bildirimi
(security advisory) aç (`Security` → `Advisories` → `Report a vulnerability`).
`trailwarden --version` çıktısındaki sürümü, macOS sürümünü ve en küçük
yeniden üretim adımlarını ekle. Yedi gün içinde yanıt vermeyi hedefliyoruz.

Kapsam içi:

- maskeleme atlatmaları: veritabanına, bir dışa aktarıma ya da bir günlüğe ulaşan
  bir gizli bilgi
- `--out`, kurallar veya tercih dosyaları üzerinden dizin dışına çıkma (path traversal)
  ya da dosya üzerine yazma
- veritabanının herkes tarafından okunabilir oluşturulması ya da bir dışa
  aktarımın 0600 izni olmadan yazılması
- istemlerin, komutların veya dosya içeriklerinin indeksin dışındaki bir dosyada
  görünmesi
- güncelleme isteği dışındaki herhangi bir verinin makineden çıkması

Kapsam dışı:

- ajanların kendi transkript dosyaları (onları korumak bize düşmez)
- kullanıcı hesabına zaten sahip bir saldırgan gerektiren her şey

## Veri konumu ve izinler

- indeks: `~/Library/Application Support/Trailwarden/trailwarden.sqlite` (0600)
- kural tercihleri: `~/Library/Application Support/Trailwarden/rule-preferences.json` (0600)
- dışa aktarımlar: nereye kaydedersen oraya, 0600 ile atomik olarak yazılır
- telemetri yok, çökme raporu yok, hesap yok; güncelleme denetimleri yalnızca yukarıdaki gibi
