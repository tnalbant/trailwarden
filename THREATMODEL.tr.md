# Tehdit modeli

[English](THREATMODEL.md) · **Türkçe**

## Trailwarden nedir

Kodlama ajanlarının zaten diske yazdığı transkript dosyaları için yerel bir
okuyucu. Bu dosyaları aranabilir bir indekse çevirir, riskli adımları gösterir ve
maskelenmiş bir kaydı dışa aktarmana izin verir.

## Varsayımlar

1. Transkriptler zaten diskte, kullanıcının ev dizininde ve kullanıcı tarafından
   okunabilir durumda. Trailwarden bu açığı yaratmaz; olanı okur.
2. Makine ve hesap kullanıcıya ait.
3. Trailwarden kullanıcının yetkileriyle çalışır. Root istemez, yetkili bir
   yardımcı kurmaz ve arka plan servisi değildir.

4. Canlı bekçi uygulama sürecinin bir parçasıdır. Çekirdeğe (FSEvents) hangi
   transkript dosyalarının değiştiğini sorar ve kullanıcının kendi Bildirim
   Merkezi üzerinden yerel bildirimler gönderir; soket açmaz, yardımcı süreç
   başlatmaz.

## Neye karşı korur

- **Makineden çıkma.** Uygulama ajanlara dair hiçbir şey göndermez. Kod tabanında
  ağ çağrısı yapan tek dosya `Sources/TrailwardenApp/Update/UpdateChecker.swift`.
  İlki küçük bir JSON belgesi (`version`, `notes`, `url`) için bir GET isteğidir; çerez
  yok, tanımlayıcı yok, sorgu dizesi yok. Okuyucu "Güncellemeleri denetle"ye
  tıkladığında çalışır. Ayrıca, yalnızca okuyucu Ayarlar'dan bir takvim seçerse
  (varsayılan olarak kapalı) en fazla haftada ya da ayda bir çalışır. Aynı dosya
  yalnızca okuyucu "Fiyatları güncelle"ye tıkladığında bir GET daha yapar: projenin
  deposundaki herkese açık `prices.json`, API maliyet tahmini için. Takvimi yoktur;
  indirilen liste ayrıştırılabilmeli, tarih taşımalı ve makul fiyatlar içermelidir,
  yoksa saklanmaz. Okuyucunun girdiği bir fiyatı asla değiştirmez. Geri kalan
  her şey yerelde kalır; `Sources/` altındaki başka bir dosyada ağ API'si
  görünürse CI derlemeyi bozar.
- **Dışa aktarımlardaki gizli bilgiler.** Bilinen jeton biçimleri saklanmadan önce
  maskelenir, dışa aktarırken bir kez daha maskelenir; ham satır da maskelenir.
  Bir test belgelenmiş her desenin yakalandığını doğrular, bir dışa aktarım
  testi de bir jetonun dosyaya asla ulaşmadığını doğrular.
- **Paylaşılan dosyada kazara ifşa.** Ev dizini yolları `~` olur, dışa
  aktarımlar 0600'dür ve JSON sözleşmesi ham transkript satırı taşımaz.
- **Ajan temizlik yaptığında kaydın kaybolması.** Varsayılan olarak kapalı olan
  arşiv, Claude Code, Codex, Gemini CLI ve Copilot transkriptlerinin
  sıkıştırılmış bir kopyasını `~/Library/Application Support/Trailwarden/Archive/`
  altında tutar. Dosyalar 0600, klasörler 0700'dür. Yalnızca eklenir: kısaltılan
  ya da yeniden yazılan bir transkript önceki kopyasını sürüm olarak korur.
  Kopya maskelenmemiş ve şifrelenmemiştir: transkriptlerde ne gizli bilgi varsa
  onda da vardır ve senin kullanıcın olarak çalışan her şey onu okuyabilir. Bu
  yüzden isteğe bağlıdır. Cursor, opencode ve Hermes arşivlenmez.
- **Ajan ayarlarında unutulmuş gizli bilgiler.** R29 kuralı
  `~/.claude/settings*.json`, proje `.claude/settings*.json`,
  `~/.codex/config.toml` ve `~/.gemini/settings.json` dosyalarını salt okunur
  okur ve yalnızca maskelenmiş bir önizleme saklar. Bir bulgunun anahtarı dosya,
  kural ve maskelenmiş satırın özetinden oluşur; aynı satırda döndürülen bir
  gizli bilgi aynı anahtarı korur: gözden geçirdiğin bulgu gözden geçirilmiş
  kalır.
- **Kaydın sessizce değiştirilmesi.** Olayların kimlikleri transkriptten
  türetilir; bir dosya yeniden okunduğunda aynı satırlar yerine yazılır, satır
  eklenmez ya da kaybolmaz. Satırlar yalnızca açıkça `prune` ile ya da seçtiğin
  saklama süresiyle (varsayılan: sonsuza kadar) silinir, kural sonuçları da
  yalnızca kurallar değiştiğinde yeniden yazılır. Trailwarden indeksi
  değiştirilemez kılmaz: hesabın sahibi onu her dosya gibi düzenleyebilir.

## Neye karşı korumaz

- Hesabına zaten sahip olan bir saldırgan. İndeks senin kullanıcın tarafından
  okunabilir.
- Sahte transkript yazan ele geçirilmiş bir ajan. Trailwarden ajanın yazdığını
  kaydeder; ajanın dürüst olduğunu doğrulayamaz.
- Trailwarden çalışmadan önce ajanların kendi günlüklerine yazdığı gizli bilgiler.
  Maskeleme desen tabanlıdır: alışılmadık biçimde bir gizli bilgi geçebilir.
- Disk düzeyindeki saldırganlar (burada cevap FileVault'tur, bu uygulama değil).

## Güven sınırları

| Sınır | Risk | Önlem |
|---|---|---|
| transkript dosyaları → ayrıştırıcı | bozuk girdi | satır düzeyinde hoşgörü, bozuk bir dosya taramayı asla yarıda kesmez |
| editör durum veritabanı → Cursor ayrıştırıcısı | sohbetlerden fazlasını okumak (ayarlar ve oturum açma jetonları aynı dosyada durur) | salt okunur açılır; tek sorgular `cursorDiskKV` içindeki `composerData:` ve `bubbleId:` satırlarının anahtar aralığı okumalarıdır; `ItemTable` hiç sorgulanmaz ve bir test oraya bir jeton koyarak okunmadığını kanıtlar |
| `.zst` arşivi → çözücü | bozuk ya da kötü niyetli sıkıştırılmış veri | resmi Zstandard çözücüsü (kaynağında fuzz testinden geçmiş), sınırlı parçalar halinde akıtılır; 128 MB üzerinde pencere isteyen bir çerçeve reddedilir; bozuk ya da kesik bir dosya yalnızca kendisini başarısız kılar |
| ayrıştırıcı → veritabanı | maskeleme kaçırma | kurallar ham metin üzerinde çalışır, depo yalnızca maskelenmiş metni görür |
| veritabanı → dışa aktarım | yol veya jeton sızması | ikinci maskeleme geçişi, `~` kısaltması, 0600 |
| kural dosyası → regex motoru | yıkıcı geri izleme (catastrophic backtracking) | gelen desenler çapalı ve sınırlıdır, her biri eşleşmesi ve eşleşmemesi gereken komutlardan oluşan bir tabloyla denenir; kullanıcılar kuralları kapatabilir ya da derecesini değiştirebilir, yeni regex ekleyemez |
| indeks → bildirim | kilit ekranında görünen komut | bildirim zaten maskelenmiş komutu taşır; macOS kilit ekranında bildirim önizlemelerini varsayılan olarak gizler |
| indeks → paylaşılabilir özet | iş ayrıntılarının sızması | karnenin özeti yalnızca sayılardan, ajan adlarından ve kural başlıklarından oluşur; bir test hiçbir komutun, yolun ya da proje adının buna ulaşmadığını doğrular |
