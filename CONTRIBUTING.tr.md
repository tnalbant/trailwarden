# Katkıda bulunmak

[English](CONTRIBUTING.md) · **Türkçe**

İlgilendiğin için teşekkürler. Bu küçük ve kendi görüşü olan bir araç; en hızlı
yol, ne yaparken ne olduğunu anlatan bir issue açmak.

## Temel kurallar

- **Çevrimdışı kalır.** `Sources/` altında ağ kodu yok. CI, `URLSession`,
  `URLRequest`, `CFNetwork` ve benzerlerini arar, bulursa derlemeyi bozar. Eve
  haber vermesi gereken bir özellik kapsam dışıdır.
- **Gerçek transkript yok.** Testler `Tests/**/Fixtures/` altındaki elle yazılmış
  sentetik dosyaları kullanır. Gerçek bir `.jsonl`, gerçek bir indeks veritabanı
  ya da kendi oturumlarının ekran görüntüsünü asla commit etme. CI başıboş
  `.jsonl` dosyalarını reddeder; README'deki ekran görüntüleri
  `scripts/seed-demo.py` ile üretilir.
- **Pull request başına tek mantıksal değişiklik.** Yoldan geçerken yapılan biçim
  düzeltmesi ya da bağımlılık yükseltmesi olmasın. Üçüncü taraf bütçesinin
  tamamı tek bir sabitlenmiş paket ve `Sources/CZstd` içindeki gömülü Zstandard
  çözücüsüdür (onu yalnızca kendi README'sinin söylediği gibi güncelle).
- Her Swift dosyası SPDX başlığıyla başlar.

## Derleme

```bash
swift build --build-tests
swift test
xcodegen generate && open Trailwarden.xcodeproj   # app target
```

## Testler

Davranış değişikliği, o değişiklik olmadan başarısız olan bir test ister. Değişikliğini
geri alarak takımı (suite) başarısız yapamıyorsan, o test bir kanıt değildir. Sabit
literal değerler (`"3 events"`), test edilen sabite karşı yazılmış doğrulamalardan
iyidir.

## Kural eklemek

Kurallar işe girmenin en kolay yoludur. Her kural,
`Sources/TrailwardenCore/Resources/rules.json` içinde bir kayıttır:

- `tool` (`Bash`, `Write|Edit`, …), `commandRegex`, `pathGlobs` ve
  `excludePathGlobs`; `anyOf` seçenekleri listeler, böylece tek bir kural hem
  "kabuk `~/.zshrc` dosyasına ekleme yapar" hem de "düzenleme aracı
  `~/.zshrc` dosyasını yeniden yazar" durumunu kapsayabilir.
- Kabuk desenleri ortak komut başlangıcı önekiyle başlar (satır başı, `;`,
  `&&`, `|`, `(` sonrası ya da `sudo` ardı), böylece `echo 'rm -rf /'` bir silme
  sayılmaz.
- Ardından `python3 scripts/embed-rules.py` çalıştır: kurallar bu dosyadan
  programın içine derlenir; ikisi farklıyken bir test başarısız olur.
- Metinleri altı dilde de `RuleLocalization+Added.swift` içine ekle.
- `RuleCatalogExpansionTests` içine satırlar ekle: eşleşmesi gereken komutlar
  **ve** eşleşmemesi gereken yakın örnekler. Olumsuz örneği olmayan bir kural
  gözden geçirilemez.
- PR açmadan önce kendi geçmişinde dene:
  `trailwarden rules apply && trailwarden scan --since 30d`. Sıradan işlerde
  tetikleniyorsa ilk gün kapatılır.

## Ajan eklemek

Yeni ajanlar, diskteki biçimleri doğrulanabiliyorsa memnuniyetle karşılanır:

- JSONL / oturum başına tek belge transkriptleri: `AgentParser` uygula ve bir
  `ScanRoot` ekle (`GeminiCLIParser` ve `ClaudeCodeParser`'a bak).
- SQLite geçmişi: `DatabaseAgentParser` uygula ve bir `DatabaseSource` ekle
  (`HermesDatabaseParser`'a bak; kaldığı yerden okumayı da gösterir).
- Örnek veriler sentetik olmalı; ayrıştırıcı bozuk bir satırda taramayı
  yarıda kesmek yerine o satırı hoş görmeli.

Gerçek çıktısına karşı çalıştıramadığın bir biçim için lütfen adaptör gönderme.
Sessizce hiçbir şey üretmeyen bir ayrıştırıcı, hiç olmayan bir ayrıştırıcıdan
daha kötüdür.
