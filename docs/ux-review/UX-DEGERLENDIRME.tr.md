# Trailwarden — Kullanıcı Deneyimi ve Kullanıcı Faydası Değerlendirmesi

**Sürüm:** v0.2.4 · **Tarih:** 22 Kasım 2026 (HN doğrulamasıyla güncellendi: 23 Kasım 2026) · **Kapsam:** menü çubuğu uygulaması, ana pencere, canlı koruma, CLI/MCP'nin kullanıcıya dokunan kısımları

---

## 0. Yöntem ve sınırlar

| Kaynak | Ne yapıldı |
|---|---|
| Arayüz kodu | `Sources/TrailwardenApp` altındaki tüm görünümler (menü paneli, ilk açılış, Bugün, Zaman çizelgesi, Olay detayı, Rapor, Kullanım, Kurallar, Ayarlar) ve onları besleyen çekirdek kod satır satır okundu. |
| Ekran görüntüleri | `docs/screenshots/*` (demo veritabanı) incelendi. |
| Erişilebilirlik | Yazı boyutları sayıldı; renk kontrastı WCAG formülüyle hesaplandı. |
| Kural motoru | `rules.json` ve `RuleEngine` Python'da yeniden kurularak gerçekçi komut derlemlerine karşı yanlış alarm / kaçırma testi yapıldı (§7). |
| Hacker News (23 Kasım) | Algolia API ile ~195 sorgu, ~12.000 benzersiz kayıt, ~54 başlık tam okundu; hipotezler tek tek doğrulandı veya çürütüldü (§11). |
| Pazar sesi | Üç araştırma: (a) kullanım/maliyet izleyiciler (ccusage, Claude‑Code‑Usage‑Monitor, CodexBar, ClaudeBar, Usage4Claude, ccstatusline…), (b) oturum/geçmiş görüntüleyiciler (Agent Sessions, claude‑code‑history‑viewer, Sniffly, opcode…), (c) güvenlik/koruma araçları ve gerçek olaylar (dcg, cc‑safe‑setup, sandbox, mcp‑scan, Little Snitch/LuLu, Replit, ev dizini silinmesi…). |

**Sınırlar — dürüstçe:**
- Uygulama macOS'a özel; bu ortamda (Linux, Swift yok) **çalıştırılamadı**. Değerlendirme kod okuma + ekran görüntüleri + hesaplamaya dayanıyor. Animasyon, gerçek hız, bildirim zamanlaması gibi şeyler gözlenmedi.
- Reddit bu ortamdan erişilemedi: Reddit bulut sunucularından gelen istekleri kendi tarafında engelliyor, arama aracı da Reddit içeriğine ulaşamıyor. Hacker News sonradan tarandı (§11); Product Hunt yorumlarına erişilemedi. Pazar sesi ağırlıkla **GitHub issue'ları (tepki sayılarıyla)**, resmî dokümanlar, olay haberleri ve blog yazılarından geliyor. Kanıt gücü her bölümde belirtildi.

---

## 1. Yönetici özeti

**Genel hüküm:** Trailwarden mühendislik olarak olgun, gizlilik konusunda sınıfının en iyisi ve yedi ajanı tek yerde birleştiren nadir bir araç. Ama bugünkü haliyle **"çok şey gösteren, az şeyi bitiren"** bir ürün: kullanıcıya bir şey olduğunu söylüyor, ancak (1) bunu önlemek, (2) sonucunu anlamak, (3) bulguyu kapatmak için ona yeterli araç vermiyor. En büyük fırsatlar yeni ekranlarda değil, mevcut akışların sonuna eklenecek **"peki şimdi ne yapayım?"** adımlarında.

**En önemli 8 bulgu**

1. **"Girişte aç" yok.** Uygulama Login Item kaydı yapmıyor, belgelerde de anılmıyor. Mac yeniden başlatılınca canlı koruma sessizce kapalı kalıyor. Bir "bekçi" için bu en temel işlev açığı.
2. **"Ne değişti?" sorusu en yaygın ajanda cevapsız.** Claude Code `Edit`/`Write` olaylarında önizleme, alfabetik ilk anahtar olan `file_path`'e düşüyor (`ClaudeCodeParser.swift:242`). Detay panelinde fark (diff) yerine yalnızca yol görünüyor. Gemini `replace` için de durum aynı (ekran görüntüsünde de böyle). Fark yalnızca Codex yamalarında çalışıyor.
3. **Bulgular kapatılamıyor.** "İncelendi / beklenen davranış" durumu yok. Menü çubuğundaki kırmızı sayı gün boyu yanıyor, tek seçenek "30 gün sustur". Muadil güvenlik araçlarının kullanıcıları en çok **alarm yorgunluğundan** ve **tek tıkla izin listesinin olmamasından** şikâyet ediyor.
4. **Tespit, önlemeden sonra geliyor, ama önleme yarışına girmek de doğru değil.** Gerçek olaylarda mağdurların istediği **önleme** ve **geri alma**. `rm -rf ~` için "saniyeler içinde bildirim" geç kalır; HN'de denetim aracına ilk tepki "Çözümünüz çok geç gelmiyor mu?" oluyor. Öte yandan HN, ajanları onaysız çalıştırmanın (YOLO) çok yaygın olduğunu ve bu modda **kancaların eşzamansız çalıştığını** gösteriyor: komut, kanca onu engelleyemeden yürütülüyor. Satıcılar da "auto mode" ile önlemeyi kendisi yapıyor. Doğru konum: **ajandan bağımsız kayıt + önleme katmanlarını denetleyen gözlemci** ("sandbox etki alanını daraltır; Trailwarden içinde ve dışında ne olduğunu söyler"). Bkz. §11.
5. **Pazarın en yüksek sesli acısı geçmiş kaybı, ve Trailwarden bunu zaten kısmen çözüyor ama söylemiyor.** Claude Code'un 30 günlük `cleanupPeriodDays` temizliği eski oturumları siliyor (anthropics/claude-code#46621, ≥12 ilgili issue, HN'de buna ayrılmış bir başlık ve ~20 mağdur yorumu). Ayrıca bağlam sıkıştırma (compaction) sıkıştırma öncesi geçmişi değiştiriyor. Trailwarden'ın dizini kaynak dosya silinse de olayları tutuyor, ama önizlemeler 500 karakterle sınırlı, yani **tam bir arşiv değil**. Bu, ürünün en güçlü edinme kancası olabilir; README'de tek kelime yok.
6. **Oturumlar insan diliyle adlandırılmamış.** Kenar çubuğunda oturum `gemini d23f0824` gibi görünüyor. İlk istem, başlık, dal, süre ve maliyet yok. Görüntüleyici kullanıcılarının en sık istekleri: oturum başlığı, eşleşen pasajı gösteren tam metin arama, tek tıkla resume.
7. **Kritik kümesi fazla geniş.** Kural testinde (§7) sıradan geliştirme trafiği temiz çıktı. Ama altyapı/DB/kimlik bilgisi işi yoğun bir günde varsayılan eşikte bile **~10–12 kritik bildirim** oluşuyor (`ls ~/.ssh`, test DB'sinde `DROP TABLE`, `kubectl delete pod`, `curl -d @payload.json localhost`). Yakalama oranı %74; `bash -c`, değişken dolaylaması ve `eval "$(curl …)"` yapısal kör noktalar. Beş kural düzeltmesiyle kritik bildirim yarıya iniyor, yakalama artıyor.
8. **Erişilebilirlik ciddi biçimde eksik.** Kodda **sıfır** erişilebilirlik etiketi var. Metinlerin yaklaşık %73'ü 10 pt ve altında (en sık 9–9,5 pt). Açık temada üçüncül metin kontrastı **2,66:1**, vurgu rengindeki küçük düğmeler **3,45:1** (WCAG AA küçük metin için 4,5:1 ister). Seçiciler boş etiketli, olay listesi klavyeyle gezilemiyor.

**Önerilen ilk 6 adım (HN doğrulamasından sonra güncellendi; etki/çaba sırasıyla)**

1. Girişte aç anahtarı: ilk açılışta ve Ayarlar'da (`SMAppService.mainApp`). *Çaba: S*
2. **Geçmişin silinmez:** kaynak silinince rozet ve resume uyarısı, Claude'un temizlik ayarını okuyup bilgilendirme, ve isteğe bağlı **tam kalitede arşiv** (ham transkriptin sıkıştırılmış kopyası; temizlik ve sıkıştırmaya karşı). README'nin ilk vaadi bu olsun. *Çaba: S→M*
3. Bulgu "gelen kutusu": Yeni → İncelendi → Beklenen durumları, bildirimde eylem düğmeleri (Aç / Bu projede beklenen / Sustur) ve komutun **sade dille açıklaması** ("Ev klasörünüzün tamamını siler"). Menü çubuğu sayısı yalnızca **incelenmemiş** bulguları göstersin. *Çaba: M*
4. Kural ayarı: §7'deki 5 düzeltmeyle kritik bildirimi yarıya indir. Ağırlığı **sırlar, kimlik bilgileri ve kalıcılık** tarafına kaydır (ör. ajan ayar dosyalarına yazılan parolalar). Yanlış alarm derlemini CI'a ekle. *Çaba: M*
5. **Kota sinyalleri** (transkriptten, ağsız) ve oturum/proje maliyeti. Abonelik kullanıcısının asıl sorusu "limite takılacak mıyım?". *Çaba: M*
6. **Geri çağırma**: oturum adları, eşleşen pasajı gösteren arama, ve aynı aramanın MCP üzerinden ajana açılması ("geçen sefer bunu nasıl çözmüştük?"). *Çaba: M*

*İlk sürümdeki "Kalkan" (komut öncesi engelleme) önerisi geri çekildi; yerine "Koruma doğrulayıcı" geldi (§8.3 S1, §11).*

---

## 2. Ürün nerede duruyor? Konumlandırma haritası

Trailwarden normalde üç ayrı ürün kategorisinin işini tek uygulamada yapıyor:

| İş (job‑to‑be‑done) | Tipik rakipler | Kullanıcıların en çok istediği | Trailwarden bugün |
|---|---|---|---|
| **A. Geçmiş / oturum görüntüleme** | Agent Sessions (~955★, en yakın rakip), claude‑code‑history‑viewer, opcode, onlarca tek amaçlı arama aracı | Silinmeyen arşiv · çalışan tam metin arama (eşleşen pasajla) · tek tıkla resume · okunabilir oturum başlıkları · gürültü filtreleme | Zaman çizelgesi, proje gruplama, resume komutu, FTS arama **var**. Başlık, eşleşen pasaj ve diff **zayıf**. Arşiv niteliği **pazarlanmıyor**. |
| **B. Kullanım / maliyet** | ccusage (~11–16k★), Claude‑Code‑Usage‑Monitor, CodexBar, ClaudeBar, Usage4Claude | **Kalan kota ve sıfırlanma saati** (dolardan çok) · resmî sayılarla tutarlılık · hızlı ve sade menü çubuğu · keychain izni istememesi | 30 günlük token grafiği, model başına "API karşılığı" maliyet, ajan dağılımı. Kota/sıfırlanma **yok**, oturum ve proje başına maliyet **yok**. |
| **C. Güvenlik / denetim** | dcg, cc‑safe‑setup, Claude Code sandbox ve auto mode, mcp‑scan, OTel/Compliance API | **Önleme** (engelleme) · **geri alma** · düşük gürültü · tek tıkla izin listesi · ekip/denetim kaydı | 27 kural, canlı bildirim, CI kapısı, maskeli dışa aktarım, MCP. Önleme **yok**, kurtarma rehberi **yok**, bulguyu kapatma **yok**. |

**Çıkarım:** Trailwarden'ın gerçek farkı, her üç kategoride de **7 ajan × tamamen yerel × salt okunur** üçlüsü. Rakiplerin hiçbiri bunu birlikte sunmuyor. Ajan **sayısı** tek başına bir fark değil: Agent Sessions 16 biçimi okuyor. Fark, geçmiş + maliyet + güvenliğin aynı yerel dizinde buluşması. Risk de buradan doğuyor: CodexBar'ın en çok tepki alan issue'ları "**bloat**" ve "**lag**" (#1364 37👍, #1274 35👍, #1321 34👍). Üç kategoriyi birden yapan bir ürün, odak ve hız disiplinini kaybederse aynı tepkiyi alır.

---

## 3. Korunması gereken güçlü yönler

- **Gizlilik tasarımı örnek niteliğinde.** Hesap yok, telemetri yok. CI, `Sources/` içinde ağ API'si görürse derlemeyi kırıyor. Dışa aktarımlar 0600 izinli, sırlar maskeli. Rakiplerde keychain/çerez izinleri en büyük şikâyet kaynaklarından biri (CodexBar'da 5 ayrı issue, her biri 26–36👍). Trailwarden'ın "yalnızca transkript okurum" yaklaşımı bu sorunu yapısal olarak yaşamıyor. Bu bir **pazarlama silahı**.
- **Çoklu ajan kapsaması ve ayrıştırma derinliği.** Codex "code mode" JavaScript'inden komut çıkarma, `.jsonl.zst` okuma, opencode'un `credential` tablosuna hiç dokunmama: rakip görüntüleyicilerin en sık hataları ayrıştırma kaynaklı (yinelenen oturumlar, "Invalid Date", sıfır mesaj). Bu titizlik değerli.
- **Tek pencere + sekmeler (0.2.3).** Altı pencereden bire inmek doğru karardı. ⌘1…⌘5, ⌘R, ⌘F kısayolları var.
- **Yazılı tasarım düşüncesi.** Kod yorumları ("bir sayı ancak onu doğuran komutun yanında anlam taşır") ürün sahibinin kullanıcıyı düşündüğünü gösteriyor. Boş durumlarda "Filtreleri temizle" çıkışı, yerelleştirilmiş kural metinleri, ilk taramada ilerleme gösterimi iyi örnekler.
- **Rapor kartı** görsel olarak ürünün en olgun ekranı (`report-light.png`). Tipografi hiyerarşisi, "Göz atmaya değer" listesi ve güvenle yapıştırılabilir özet iyi düşünülmüş.
- **Maliyet tahmini dürüst çerçevelenmiş.** "API karşılığı, fatura değil" notu ve fiyatsız modeller için uyarı, ccusage'ın "yeni model $0 görünüyor" (#855) tuzağından kaçınıyor.
- **CLI + MCP + uygulama** aynı çekirdeği paylaşıyor. `file_history` MCP aracı (bir ajanın düzenlemeden önce "bu dosyaya başka kim dokunuyor?" diye sorması) özgün bir fikir.

---

## 4. Pazar sesi: muadil uygulamaların kullanıcıları ne diyor?

### 4.1 Kullanım/maliyet izleyiciler

- **#1 şikâyet: resmî limitle tutarsızlık.** Yaklaşık 12 issue. ccusage #483 (27 yorum): araç boş alan gösterirken Claude "limit doldu" diyor. Monitor #48: "%50 kaldı" görünürken API çağrıları başarısız. Monitor #137: "Token'ların çoğu alt ajanlarda harcanıyor." Kullanıcının güveni, araç ile satıcının söylediği arasındaki ilk uyuşmazlıkta kırılıyor.
- **#2 istek: kalan kota, sıfırlanma saati, harcama hızı.** Monitor #167 (20👍): "Harika araç. Haftalık kullanımı ve sıfırlanma gününü ekleyin." ccusage #146: "Claude'un yazdığı sıfırlanma saatini kullanın, tahmin etmeyin." ccstatusline #124: geçen süre yerine kalan süre. **Abonelik kullanıcıları dolardan çok "limite takılacak mıyım?" sorusunu soruyor.**
- **#3: menü çubuğu uygulamasında hız ve sadelik.** CodexBar'ın en çok tepki alan 6 issue'su performans ve şişkinlikle ilgili.
- **#4: izin/keychain sürtünmesi.** Trailwarden'ın yapısal avantajı.
- **Diğer:** birden çok makine/hesap, alt ajan atfı, para birimi.

### 4.2 Oturum/geçmiş görüntüleyiciler

- **En yüksek sesli acı: geçmişin silinmesi.** anthropics/claude-code#46621: "Projeyi 3 hafta duraklatırsan bütün loglar gider." "Tatile gittim, döndüğümde 2 büyük projenin tüm konuşmaları yoktu." "Kendi makinemden içeriğimin silineceğine dair hiçbir işaret yoktu." Bu konuda en az 12 ilgili issue var, The Register'da da haber oldu.
- **Arama gerçekten çalışsın ve eşleşen pasajı göstersin.** claude-code-history-viewer #215, #390, #394, #806; Agent Sessions #95.
- **Resume:** bağlam menüsünden kopyalama (#134), farklı terminaller (#88), PATH sorunları (#58).
- **Gürültü filtreleme ve başlıklar:** projeyi gizleme (#87), alt ajan oturumlarını gizleme (#49), Claude'un otomatik oturum başlıklarını gösterme (#601).
- **Zayıf kanıt:** diff görünümü, rapor kartı, "agent blame", dışa aktarım için açık kullanıcı talebi bulunamadı. Bu, bu özelliklerin değersiz olduğu anlamına gelmiyor. Ama **talep doğrulanmamış**, dolayısıyla pazarlamada öncelik onlar olmamalı.

### 4.3 Güvenlik/koruma araçları ve gerçek olaylar

- **Önleme, tespitten önce geliyor.** Olay sonrası tartışmalar ve araçların neredeyse tamamı ön‑yürütme odaklı (kanca, sandbox, konteyner). Mağdurlar arasında "keşke bildirim alsaydım" diyen bulunamadı. "Keşke engellenseydi" ve "keşke geri alabilseydim" diyenler çok.
- **Onay/alarm yorgunluğu merkezi problem.** Anthropic'in kendi ifadesiyle kullanıcılar bir süre sonra onay istemlerini okumayı bırakıyor. Little Snitch belgeleri boş kural setiyle başlayınca neredeyse her bağlantı için sorduğunu kabul ediyor. LuLu kullanıcıları kapatılamayan uyarılardan yakınıyor.
- **İzin listesi beklenen asgari özellik.** dcg'de kural kimliğiyle allowlist, mcp‑scan'de whitelist, Little Snitch'te "geçici" kurallar var. İzin listesine **uyarının içinden tek tıkla** ulaşılabilmeli.
- **Kanca tabanlı korumalar kırılgan.** Zincirlenmiş komutlar (`cd x && rm -rf …`) kaçıyor, yanlış çıkış kodu sessizce "açık" kalıyor, alt ajanlar kancayı atlayabiliyor. **Bağımsız bir gözlemcinin "korumam gerçekten devreye girdi mi?" çapraz kontrolü** olarak değeri var. Rakiplerde bu konumda bir ürün yok.
- **Kurallar her şeyi yakalamaz.** Gemini CLI olayında zarar, sıradan komutların zincirinden doğdu: `mkdir` sessizce başarısız oldu, ardından `mv` dosyaların üzerine yazdı. Regex kuralları bunu göremez. Davranışsal sinyaller (çok sayıda dosyanın kaybolması, aynı hedefe art arda `mv`) görebilir.
- **Ajanlar yanlış bilgi verebiliyor.** Replit olayında ajan geri alma imkânsız dedi, ama mümkündü. **Ajandan bağımsız bir kayıt**, Trailwarden'ın doğal değer önerisi.

---

## 5. Bulgular — arayüz ve işlevsellik

Önem: 🔴 yüksek · 🟠 orta · 🟡 düşük

### 5.1 İlk açılış ve menü çubuğu paneli

| # | Bulgu | Önem |
|---|---|---|
| 1 | **Girişte aç / Login Item yok.** Kodda `SMAppService` geçmiyor, README/INSTALL'da da söz edilmiyor. Yeniden başlatmadan sonra canlı koruma çalışmaz ve kullanıcı bunu fark etmez (panel ancak açılınca "Live off" der). | 🔴 |
| 2 | İlk açılış ekranı bildirim iznini doğru anda soruyor (iyi). Ama: canlı korumanın **olaydan sonra** uyardığı söylenmiyor; eşik (yalnızca kritik / uyarı + kritik) burada seçilmiyor; girişte açma sorulmuyor; ajan adları ham `rawValue` ile gösteriliyor (`OnboardingView.swift:25`). | 🟠 |
| 3 | İlk tarama geçmişe dönük onlarca bulgu çıkarabilir. Bunları "geçmiş, toplu incelendi say" diye kapatma yolu yok. Kullanıcının ilk günü kırmızı sayılarla başlıyor: **alarm yorgunluğu daha ilk günden**. | 🟠 |
| 4 | Panel başlığının altındaki satır kalıcı olarak "v0.2.4 · Güncellemeleri denetle" ile dolu. Panelin en değerli alanı nadir kullanılan bir eyleme ayrılmış. Yalnızca güncelleme **varsa** gösterilmeli. | 🟡 |
| 5 | Panelde "Bugün" yalnızca **son kritik** bulguyu gösteriyor; uyarılar panelde hiç görünmüyor. Kritik sayısı incelendikten sonra da azalmıyor (bkz. 5.2). | 🟠 |
| 6 | "Son ne oldu" satırlarına ve "Bugün" sekmesindeki satırlara tıklayınca oturum açılıyor, ama **o olay seçilmiyor** (`MenuBarView.swift:223`, `FeedView.swift:98`, yalnızca `sessionID` gönderiliyor). Rapor'daki bulgu listesi bunu doğru yapıyor (`openEvent`). Kullanıcı yüzlerce satır içinde olayı tekrar aramak zorunda kalıyor. | 🟠 |
| 7 | Panelde metinler 8,5–9,5 pt. Menü çubuğu panelinde bile macOS'un alt sınırı pratikte 11 pt civarı. | 🟠 |

### 5.2 Canlı koruma ve bildirimler

| # | Bulgu | Önem |
|---|---|---|
| 8 | Bildirimlerde **eylem düğmesi yok** (`UNNotificationCategory` tanımlı değil). Tıklayınca olay açılıyor (iyi), ama "Sustur", "Bu projede beklenen", "İncelendi" bildirimden yapılamıyor. Little Snitch/dcg dersi: izin listesi uyarının içinden tek tıkla erişilebilir olmalı. | 🔴 |
| 9 | **Bulgu yaşam döngüsü yok:** yeni / incelendi / beklenen / yanlış alarm ayrımı yapılamıyor. Menü çubuğundaki sayı "bugünkü kritik sayısı" olarak kalıyor ve hiç sönmüyor. Sürekli yanan rozet kısa sürede görmezden gelinir. | 🔴 |
| 10 | Susturma yalnızca **30 gün** ve yalnızca **birebir komut metni** için (`RuleEngine.target` boşlukları normalleştirilmiş komutun tamamını kullanıyor). "Bu proje için", "bu kural için her zaman", "şu kalıp için" gibi kapsamlar yok. `rm -rf ./dist` ile `rm -rf ./dist/` iki ayrı susturma gerektiriyor. | 🟠 |
| 11 | Toplu bildirim mantığı makul: 3'ten fazlası "+N bulgu daha" özetine dönüşüyor, oturuma göre gruplanıyor (`threadIdentifier`). Ancak özet bildirimine tıklayınca nereye gidileceği belirsiz (`userInfo` yok). | 🟡 |
| 12 | Varsayılan eşikte bile kritik kümesi geniş: yoğun altyapı/DB günlerinde ~10–12 kritik bildirim (§7). "Uyarı + kritik" eşiği seçilirse 13 kural daha devreye giriyor ve gürültü katlanıyor. | 🟠 |

### 5.3 Zaman çizelgesi ve olay detayı

| # | Bulgu | Önem |
|---|---|---|
| 13 | **Diff çoğu ajanda yok.** `DiffExtractor` yalnızca birleşik diff veya Codex yaması görürse çalışıyor. Claude Code `Edit`/`MultiEdit` için önizleme `file_path`'e düşüyor, `old_string`/`new_string` yalnızca 2048 karakterlik ham JSON içinde, o da çoğu zaman kesik. Ekran görüntüsünde de Gemini `replace` detayında METİN alanı = dosya yolu. "Ajan bu dosyada ne değiştirdi?" ürünün ana sorularından biri. | 🔴 |
| 14 | **Oturumlar kimlikle adlandırılıyor** (`gemini d23f0824`). `SessionSummary` başlık, ilk istem, maliyet, süre taşımıyor. `gitBranch` modelde var ama kenar çubuğunda gösterilmiyor. | 🔴 |
| 15 | **Araç adları ajana özgü ve ham:** `run_shell_command`, `replace`, `write_file`, `Bash`, `exec_command`… Aynı eylem 7 ajanda 7 farklı adla görünüyor. `RuleEngine.canonicalTool` zaten normalleştiriyor; arayüz bunu kullanıp "Çalıştırdı / Düzenledi / Okudu / Yazdı / Dedi" fiilleri ve simgelerle göstermeli. Ajana özgü ad detayda kalsın. | 🟠 |
| 16 | **Satırlarda mutlak yollar tekrar ediyor** (`/Users/demo/dev/pixel-forge/tests/...`). Oturumun `cwd`'sine göre göreli yol gösterilirse satırlar yarı yarıya kısalır. | 🟠 |
| 17 | Satırdaki risk rozeti `R12 critical` şeklinde. Kural kimliği kullanıcı için anlamsız; rozette kural başlığı ("Yıkıcı silme") olmalı (`EventRowView.swift:53`). | 🟡 |
| 18 | "Bu dosyadaki diğer ajanlar" başlığı altında **aynı ajanın** başka oturumları listeleniyor (filtre ajana değil oturuma göre). Ekran görüntüsünde 6 satırın hepsi `gemini`. Başlık "Bu dosyaya dokunan diğer oturumlar" olmalı. Eylem metni (`changed`) yerelleştirilmemiş (`EventDetailView.swift:307`). | 🟡 |
| 19 | Olay listesi `LazyVStack` + `onTapGesture` (`TimelineView.swift:218`): ↑/↓ ile gezinme yok, VoiceOver satırları düğme olarak görmüyor, çoklu seçim/kopyalama yok. | 🟠 |
| 20 | Olaylar düz bir akış. Görüntüleyici kullanıcılarının zihinsel modeli **konuşma turu**: "Ben şunu istedim → ajan 14 eylem yaptı → şunu söyledi". Mesajlar ile araç çağrıları aynı görsel ağırlıkta karışıyor. | 🟠 |
| 21 | Arama sonuçları eşleşen pasajı vurgulamıyor; arama sözdizimi yok (`agent:`, `project:`, `rule:`). Görüntüleyici kullanıcılarının bir numaralı isteği bu. | 🟠 |
| 22 | Üst çubukta "Tüm oturumlar" etiketi, kenar çubuğundaki seçimle yineleniyor (ekran görüntüsü). | 🟡 |
| 23 | **Kaynak transkript silinmişse** (ör. Claude'un 30 günlük temizliği) resume komutu yine de gösteriliyor ve çalışmayacak. Bu durum tespit edilip "kaynak silindi, Trailwarden'da saklandı" rozetiyle gösterilmeli. | 🟠 |

### 5.4 Rapor

| # | Bulgu | Önem |
|---|---|---|
| 24 | Aralık seçicide "Hafta / Ay / **90**". Son seçenekte birim eksik (`ReportView.swift:89`). | 🟡 |
| 25 | Ekranın en olgun sayfası. Eksikler: dönem karşılaştırması (geçen aya göre ↑↓), proje başına kırılım, maliyet satırı, "incelenmemiş bulgu" sayısı. Ajan adları burada `Codex`/`Claude Code` (displayName), diğer ekranlarda `codex`/`claude`: **adlandırma tutarsız**. | 🟡 |
| 26 | Paylaşılabilir çıktı yalnızca "özet kopyala" (sayılar) ve CLI `export --md`. Uygulama içinden PDF/HTML rapor, haftalık otomatik rapor dosyası yok. Ekip/denetim senaryosu için gerekli. | 🟡 |

### 5.5 Kullanım

| # | Bulgu | Önem |
|---|---|---|
| 27 | **Kota/sıfırlanma bilgisi yok.** Pazarın 1 numaralı isteği bu. Codex transkriptleri `token_count` olaylarında `rate_limits` (kullanılan yüzde, pencere, sıfırlanmaya kalan süre) yazıyor; kodda hiç okunmuyor (`rate_limit` araması boş). Claude Code "usage limit reached" mesajları da transkriptte görünüyor. Bunlar **ağa çıkmadan** kota sinyali sağlar. *(Biçim sürümle değişebilir, doğrulanmalı.)* | 🔴 |
| 28 | Maliyet yalnızca model düzeyinde. **Oturum ve proje başına maliyet** yok ("bu özellik bana kaça mal oldu?"). Agent Sessions'ın ana farkı oturum başına maliyet. | 🟠 |
| 29 | Günlük grafik tek renk; hangi ajanın/modelin hangi gün yaktığı görünmüyor. Ajan veya model bazında yığılmış (stacked) çubuk daha bilgilendirici. | 🟡 |
| 30 | Jargon: "34 counters" (sayaç), "tokens processed". Kullanıcı için anlamsız. Satır ipucundaki "input / cache read / output" metinleri yerelleştirilmemiş (`UsageView.swift:200`). | 🟡 |
| 31 | Başlıktaki "25 days" ifadesinin "aktif gün" olduğu anlaşılmıyor. | 🟡 |

### 5.6 Kurallar

| # | Bulgu | Önem |
|---|---|---|
| 32 | Sekme her açıldığında **tüm dizine kurallar yeniden uygulanıyor** (`RulesView.swift:29`). Büyük geçmişte her ziyarette dönen bir gösterge ve CPU harcaması demek. Yalnızca kurallar değiştiğinde yapılmalı. | 🟠 |
| 33 | Satırlarda ham regex gösteriliyor (`/(^|[;&|])\s*rm\s+…/`). Çoğu kullanıcı için gürültü. Bunun yerine "Eşleşen örnekler" ve "Eşleşmeyen örnekler" listesi daha öğretici (bu tablolar `rules.json`'da zaten var). | 🟡 |
| 34 | CLI'daki `rules test "<komut>"` uygulamada yok. Bir "Komutu dene" kutusu kural güvenini artırır. Özel kural ekleme arayüzü de yok. | 🟡 |
| 35 | Susturma listesi kural kimliği + ham hedef metni gösteriyor; düzenleme ve kapsam değiştirme yok. | 🟡 |

### 5.7 Ayarlar

| # | Bulgu | Önem |
|---|---|---|
| 36 | Saklama süresi "eski olayları sil" olarak sunuluyor. Asıl kullanıcı değeri tersi: "**Ajanlar silse de geçmişini ben saklarım**". Ayar böyle çerçevelenmeli, varsayılanı da "sınırsız" (veya disk kotası) olmalı. | 🟠 |
| 37 | Hata mesajları `String(describing: error)` ile ham olarak gösteriliyor (`AppModel.swift:132/226/253`). Kullanıcı dostu metin ve "Ne yapmalıyım?" önerisi yok. | 🟡 |

### 5.8 Görsel dil ve erişilebilirlik

| # | Bulgu | Önem |
|---|---|---|
| 38 | **Sıfır erişilebilirlik etiketi.** Seçicilerin çoğu `Picker("")` + `.labelsHidden()`, yani VoiceOver hiçbir şey okumuyor. Sekmeler, filtre çipleri ve satırlar özel `Button`/`onTapGesture`. Severity yalnızca renkle (nokta/çizgi) anlatılıyor. | 🔴 |
| 39 | **Yazı boyutu:** boyutu belirtilmiş 166 metin çağrısının 121'i (~%73) ≤10 pt (dağılım: 8–8,5 pt: 6 · 9 pt: 36 · 9,5 pt: 43 · 10 pt: 36 · 10,5 pt: 17 · ≥11 pt: 28). Dinamik boyut veya "metin boyutu" ayarı yok. Ekran görüntüleri 2× ölçekte rahat görünüyor; gerçek 1× okumada küçük kalıyor. | 🔴 |
| 40 | **Kontrast (açık tema, kâğıt zemin #FAF7F2 üzerinde):** üçüncül %42 → **2,66:1** ❌ · uyarı rengi (satır şeridi) → **3,06:1** ❌ · vurgu #E4572E → **3,45:1** ❌ (küçük "Kopyala", "30 gün sustur", "Yeniden uygula" bağlantıları ve kritik sayılar) · ikincil %66 → 5,59:1 ✅. Koyu temada vurgu 6,75:1 ✅, üçüncül 3,5:1 ❌. | 🟠 |
| 41 | Uyarı rengi iki yerde farklı: satır şeridinde `Color(0.72, 0.52, 0.12)` (`EventRowView.swift:11`), noktalarda `Palette.severity(.warn)` = #8A5A00. | 🟡 |
| 42 | Monospace yazı her yerde (tarih, ajan, araç, sayılar). Komut ve yollar için doğru seçim, ama tarih ve etiketlerde de kullanılması ekranı "terminal log" gibi yoğunlaştırıyor. Hiyerarşi zayıflıyor. | 🟡 |
| 43 | Sekme çubuğu yerel toolbar yerine özel düğmeler. Yerel hissi azaltıyor ama 0.2.3 notlarındaki gerekçe makul. **Değiştirmeyin; yalnızca erişilebilirlik ekleyin.** | — |

### 5.9 Doğrudan hatalar (hızlı düzeltmeler)

| Dosya:satır | Hata |
|---|---|
| `Sources/TrailwardenApp/UI/TimelineView.swift:284` | Liste boşken alt satırda **sabit Türkçe "0 olay"**. İngilizce/Almanca/… arayüzde de Türkçe görünür. |
| `Sources/TrailwardenApp/UI/EventDetailView.swift:307` | `touch.action.rawValue` (`changed`/`read`…) yerelleştirilmemiş. |
| `Sources/TrailwardenApp/UI/UsageView.swift:200-204` | Token kırılım ipucu sabit İngilizce. |
| `Sources/TrailwardenApp/UI/OnboardingView.swift:25` | Ajan adı `rawValue` ile gösteriliyor (ör. `claude-code`). `displayName` olmalı. |
| `Sources/TrailwardenApp/UI/ReportView.swift:89` | "90" etiketi birimsiz. |
| `Sources/TrailwardenApp/UI/EventRowView.swift:11` | Uyarı rengi paletten farklı. |
| `Sources/TrailwardenApp/Support/Formatting.swift:53` ↔ `Agent.displayName` | Ajan adlandırması ekranlar arasında tutarsız (`claude` ↔ `Claude Code`). |
| `Sources/TrailwardenCore/Parsers/ClaudeCodeParser.swift:242` | Edit/Write önizlemesi alfabetik ilk anahtara (`file_path`) düşüyor, düzenleme içeriği kayboluyor. |
| `Sources/TrailwardenApp/UI/MenuBarView.swift:223`, `UI/FeedView.swift:98` | Olaya değil yalnızca oturuma derin bağlantı. |

---

## 6. Kullanıcı faydası değerlendirmesi

Her iş için puan, "kullanıcı bugün bu araçla bu işi ne kadar bitirebiliyor?" sorusuna dayanıyor (1–5).

| İş | Puan | Gerekçe |
|---|---|---|
| **"Ajanım az önce durduracağım bir şey yaptı mı?"** | **3/5** | Bildirim hızlı ve yerel. Ama yeniden başlatmadan sonra çalışmıyor (#1). `rm -rf` gibi anlık zararlarda geç kalıyor. Bulgu kapatılamıyor. Yavaş/sinsi zararlarda (kalıcılık, sır okuma, force‑push, `terraform destroy`, CI düzenleme) değerli. |
| **"Bu dosyayı hangi ajan, ne zaman, nasıl değiştirdi?"** | **2,5/5** | "Kim/ne zaman" iyi cevaplanıyor (who, komşu oturumlar, MCP). "**Nasıl**" (diff) Claude Code ve Gemini'de cevapsız. |
| **"Ajanlarım bu ay ne yaptı?"** | **4/5** | Rapor kartı güçlü. Proje/maliyet kırılımı ve dönem karşılaştırması eksik. |
| **"O oturumu bulup devam edeyim."** | **3/5** | Resume komutu var. Oturum adı ve arama pasajı olmadığı için **bulmak** zor. Kaynak silinmişse komut bozuk. |
| **"Ne kadar harcıyorum, limite takılacak mıyım?"** | **2/5** | Dolar tahmini var; kota/sıfırlanma, oturum/proje maliyeti yok. Abonelik kullanıcısının asıl sorusu cevapsız. |
| **"CI ajan riskini yakalasın / denetime kanıt vereyim."** | **3,5/5** | `--fail-on`, maskeli markdown var. SARIF/JSON, değiştirilemezlik (hash zinciri) ve zamanlanmış rapor yok. |
| **"Geçmişim kaybolmasın."** *(fark edilmemiş iş)* | **3/5 (potansiyel 5)** | Dizin, kaynak silinse de olayları tutuyor. Ama önizlemeler 500 karakter, mesajlar kırpık, ve bunu kimse bilmiyor. |

**"Olaydan sonra uyarı" konusunda net görüş (HN doğrulamasıyla güncellendi):** Trailwarden'ın salt okunur gözlemci kimliği **güven** açısından değerli ve korunmalı. Pazarın sesi açık: en pahalı zararlarda bildirim tek başına yetmiyor. Ama önlemeyi Trailwarden'ın kendi kancasıyla yapmak da çözüm değil: onaysız modda kancalar komutu durduramıyor, satıcılar da önlemeyi kendisi üstleniyor. Doğru strateji: **(1) ajandan bağımsız, eksiksiz kayıt**, **(2) önleme katmanlarının (sandbox, auto mode, kancalar, deny-list) gerçekten çalışıp çalışmadığını denetlemek** ve **(3) olay sonrası kurtarma rehberi**. Böylece Trailwarden, önleme araçlarıyla yarışan değil, onları **bağımsız olarak denetleyen** tek ürün olur.

---

## 7. Kural motoru: yanlış alarm ve kaçırma testi

**Nasıl test edildi:** `rules.json`'daki regex'ler, `anyOf` mantığı, araç kapsamı, glob'lar, `~` normalleştirmesi, yol belirteci çıkarma ve heredoc ayıklama Python'a aktarıldı. Bu kopya, `RuleEngineTests` ve `RuleCatalogExpansionTests`'teki **163 beklentinin 163'ünü** karşıladı. Ardından iki derlem üzerinde çalıştırıldı:

- 427 zararsız Bash komutu (sıklığa göre ağırlıklı; ~100'ü bilerek "sınırda": `sudo apt`, test DB'sini silme, `publish --dry-run` gibi) ve 66 zararsız dosya okuma/düzenleme olayı
- 216 riskli komut (14 kategori, kaçış denemeleri dahil)

Swift çalıştırılamadığı için sonuçlar **yaklaşık**tır. Riskli derlemdeki bazı örnekler tartışmalı, dolayısıyla kaçırma sayısı bir üst sınırdır.

| Ölçüm | Sonuç |
|---|---|
| Yakalama (recall) | 216 riskli komutun **160'ı** (%74) |
| Yanlış alarm, Bash | 427 zararsız komutun **72'si** (%17); bunların büyük kısmı "sınırda" örneklerden |
| Yanlış alarm, dosya olayları | 66 zararsız olayın **28'i** (R20 CI düzenleme 9, R15 ajan ayarı 7, R11 `.env` 6, R4 5) |
| Sıradan günlük trafik | git, npm/pip/cargo, `rm -rf node_modules/dist`, `sed -i`, `curl` GET, migration, `terraform plan`: **neredeyse temiz** (gün başına 0–2 uyarı, 0 kritik) |
| Altyapı/DB/kimlik bilgisiyle yoğun bir gün | gün başına **~10–12 kritik** (p95 14–17), yani varsayılan eşikte ~10 bildirim, çoğu "beklenen" |

**En çok yanlış alarm üreten kurallar (doğrulandı):**

- **R4 Sır dosyası (kritik):** çıplak `**/.ssh`, `**/.aws` ve `**/*keychain*` glob'ları `ls ~/.ssh`, `cat ~/.aws/config`, `keychain_service.swift` gibi zararsız işleri kritik sayıyor.
- **R7 Dışarı veri gönderme (kritik):** her `curl -d @dosya` / `-F x=@` / `-T` yüklemesi kritik. `curl -d @payload.json http://localhost` bile.
- **R24 Yıkıcı SQL ve R25 Altyapı silme (kritik):** test veritabanında `DROP TABLE IF EXISTS`, `kubectl delete pod`, `terraform apply -auto-approve`, `helm uninstall` kritik sayılıyor.
- **R10 (uyarı):** derleme klasöründeki `find … -delete`, `git restore --staged .` uyarı veriyor.
- **Bağlam körlüğü:** kurallar komutun yanında `preview` metnini de tarıyor (`RuleEngine.swift:132`). Bir README'yi `cat` ile okuyan bir komutun çıktısında geçen `rm -rf ~` satırı, çıktı olayının araç adını taşıdığı durumlarda kural tetikleyebiliyor. Commit mesajındaki ".env" kelimesi R11'i tetikliyor.

**Yapısal kaçırmalar:** dolaylı çalıştırma (`bash -c 'rm -rf ~'`, `X=~; rm -rf $X`, `xargs`, Python/Perl tek satırlıkları), `eval "$(curl …)"` ve `source <(curl …)`, `base64 -d | sh`, kapsanan klasörler dışındaki sırlar (`~/.claude/.credentials.json`, `~/.npmrc`, `echo $ANTHROPIC_API_KEY`, tarayıcı çerezleri), `git push origin :main`, `branch -D main`, `TRUNCATE users` (TABLE kelimesi olmadan), `FLUSHDB`, `aws ec2 terminate-instances`, `npm unpublish`.

**Bellekte denenen 5 iyileştirmenin etkisi:** zararsız Bash yanlış alarmı 72'den **50**'ye düştü, yakalama 160'tan **170**'e çıktı, yoğun günde kritik bildirim ~12'den **~6,5**'e indi. 5 mevcut test beklentisinin güncellenmesi gerekiyor.

1. **Ortak önek:** `bash -c '…'`, `FOO=1 rm`, `env/nohup/time/exec/command` sarmalayıcılarını da komut başlangıcı say.
2. **R7:** yalnızca hassas bir kaynak gönderildiğinde tetiklen (`.ssh`, `.aws`, `.env`, `id_*`, `.pem`, `credentials`, `.netrc`, `.npmrc`, `.kube`, `cookies`… ya da `@-`).
3. **R4:** çıplak `.ssh`/`.aws` klasör glob'larını kaldır, `*keychain*` yerine `*.keychain`, `*.keychain-db`, `**/Keychains/**` kullan, `.aws/config`'i hariç tut, komut belirteçlerini yalnızca içerik okuyan komutlarda yol say.
4. **R10/R5:** `find -delete` yalnızca geniş kökte (`/`, `~`, `$HOME`, `..`) tetiklensin. `git restore --staged` hariç tutulsun. Force‑push yalnızca korumalı dallarda (main/master/develop/prod/release*) olsun; `--delete` ve `:ref` eklensin.
5. **R24/R25/R2 seviye ayrımı:** `DROP DATABASE|SCHEMA`, `terraform destroy`, `kubectl delete ns|node|pv|--all|deployment` **kritik** kalsın. `DROP TABLE`, `TRUNCATE`, `kubectl delete pod|-f`, `terraform apply -auto-approve`, `helm uninstall` **uyarıya** insin. `TRUNCATE`, `FLUSHDB`, `.drop()`, `aws … (terminate|deregister)-` ve `eval/source <(curl …)`, `base64 -d | sh` eklensin.

Ek: araç **çıktısı** olaylarını ve Bash `description` alanını kural taramasından çıkar; commit mesajı ve `echo` içindeki tırnaklı metni yol eşleştirmeden önce ayıkla.

**UX sonucu:** Varsayılan eşik (yalnızca kritik) doğru, ama **kritik kümesi fazla geniş**. Kritik, "geri dönüşü olmayan ve proje dışına taşan" eylemlere ayrılmalı. R20 (CI), R15 (ajan ayarı), R11 (proje `.env`), R24/R25 (geliştirme bağlamı), R19 (yayımlama), R5 (dallar) **proje bazlı izin listesi** olmadan gürültü üretir (bkz. K2). Ayrıca, **"bildirim yok" "güvenli" demek değil**: dolaylı çalıştırma regex'in yapısal kör noktası. Bu, arayüzde ve README'de dürüstçe söylenmeli ve S3 (davranışsal kurallar) ile azaltılmalı.

> Test betikleri ve derlemler bu oturumun geçici dizininde üretildi; depoya eklenmedi. Kalıcı olmasını isterseniz `Tests/` altına bir "yanlış alarm derlemi" testi olarak taşınabilir. Bu da bir öneri: **kural değişikliklerinde yanlış alarm oranını CI'da ölçen bir regresyon derlemi**.

---

## 8. Öneriler — önceliklendirilmiş yol haritası

Çaba: **S** ≤1 gün · **M** 2–5 gün · **L** 1–3 hafta. Etki: ★ (az) → ★★★ (çok).

### 8.1 Hemen (0.2.5 — "güven ve cila" sürümü)

| # | Öneri | Neden (kanıt) | Çaba | Etki |
|---|---|---|---|---|
| H1 | **Girişte aç** anahtarı (`SMAppService.mainApp`): ilk açılışta varsayılan açık öneri, Ayarlar'da anahtar. Panelde koruma kapalıysa sarı uyarı şeridi. | Bekçi kapalıyken kullanıcı korunduğunu sanıyor. Kanca araçlarının "sessizce açık kalma" sorununun aynısı. | S | ★★★ |
| H2 | §5.9'daki hataları düzelt (yerelleştirme, adlandırma tutarlılığı, "90 gün", renk). | Altı dilli bir üründe sabit Türkçe metin güveni zedeler. | S | ★★ |
| H3 | Bugün sekmesi ve panel satırlarından **olaya** derin bağlantı (`eventToSelect`). | Kullanıcı yüzlerce satırda olayı yeniden aramak zorunda. | S | ★★ |
| H4 | Bildirim eylemleri: **Aç · İncelendi · Bu projede beklenen · Sustur…** (`UNNotificationCategory`). | Little Snitch/dcg dersi: izin listesine uyarının içinden tek tıkla ulaşılmalı. | S–M | ★★★ |
| H5 | **Kontrast ve boyut**: üçüncülü %42'den %60'a çıkar (4,58:1), metin için koyulaştırılmış bir `accentText` tanımla (açık temada ≈#B8431F: kâğıt üzerinde 5,09:1, yüzey üzerinde 4,63:1), pencere gövde metnini 11–12 pt, paneli 10,5–11 pt tabanına çek. "Metin boyutu: Normal / Büyük" ayarı ekle. | 3 kontrast hatası, metinlerin ~%73'ü ≤10 pt. | S–M | ★★ |
| H6 | **Erişilebilirlik temeli**: tüm `Picker("")` seçicilere gerçek etiket + `.labelsHidden()`; satırlara `.accessibilityElement(children: .combine)` ve `accessibilityLabel` ("Kritik: yıkıcı silme, Gemini, 14:24"); sekmelere `.accessibilityAddTraits(.isSelected)`; olay listesine klavye gezintisi (↑/↓, ⏎ ile aç, ⌘C ile komutu kopyala). | Sıfır etiket var. | M | ★★ |
| H7 | Kurallar sekmesinde yeniden uygulamayı yalnızca kurallar "kirli" olduğunda yap. | Her ziyarette tüm dizin taranıyor. | S | ★ |
| H8 | Panelin güncelleme satırını yalnızca güncelleme **varken** göster. Sürümü `…` menüsüne taşı. | Panelin en değerli alanı. | S | ★ |
| H9 | **Kural ayarı**: §7'deki 5 düzeltme (R4 glob'ları, R7 hassas kaynak şartı, R10/R5 daraltma, R24/R25 seviye ayrımı, ortak önek). Araç çıktısını taramadan çıkar. Zararsız/riskli derlemi `Tests/` altına regresyon testi olarak ekle. | Kritik bildirim ~12'den ~6,5'e, yakalama %74'ten %79'a. | M | ★★★ |

### 8.2 Kısa vade (0.3 — "bulguyu kapat, değişikliği gör" sürümü)

| # | Öneri | Ayrıntı | Çaba | Etki |
|---|---|---|---|---|
| K1 | **Bulgu gelen kutusu** | Durumlar: Yeni · İncelendi · Beklenen · Yanlış alarm. Menü çubuğu rozeti = incelenmemiş kritik sayısı. "Tümünü incelendi say" ve ilk taramadan sonra "**Geçmiş bulguları toplu incelendi say**" seçeneği. Bugün sekmesinin üstünde "İncelenecek 3 bulgu" şeridi. | M | ★★★ |
| K2 | **Kapsamlı izin listesi** | Susturma kapsamları: *bu komut* · *bu projede bu kural* · *bu kural için şu kalıp* (ör. `rm -rf ./dist*`) · *her zaman*. Süreler: 1 gün / 30 gün / süresiz. Yanlış alarm işaretlemeleri yerel bir "kural geri bildirimi" dosyasına yazılsın; kullanıcı isterse issue şablonuna yapıştırsın (telemetri olmadan iyileştirme döngüsü). | M | ★★★ |
| K3 | **Tüm ajanlar için diff — "neden"iyle birlikte** | Claude `Edit/MultiEdit/Write`, Gemini `replace/write_file`, Copilot `str_replace`, Cursor, opencode düzenlemelerinden eski/yeni metni çıkar; maskele, sınırla (ör. 16 KB), birleşik diff olarak sakla. *HN notu:* kod incelemesi zaten `git diff` ile yapılıyor; Trailwarden'ın katkısı diff'i **onu doğuran konuşmayla** (hemen önceki istem ve ajan açıklaması) yan yana göstermek ve git'in görmediğini, yani **commit edilmemiş, sonra geri alınmış veya repo dışındaki** değişiklikleri göstermek. | M | ★★ |
| K4 | **Oturum kimliği yerine oturum adı** | İlk kullanıcı istemi (kısaltılmış) + dal + süre + olay sayısı + (varsa) maliyet. Claude'un kendi `summary` kayıtları varsa onları kullan. Kenar çubuğunda tarihe göre ("Bugün / Dün / Bu hafta") gruplama. | M | ★★★ |
| K5 | **Konuşma görünümü** | Olay akışını "tur" kartlarına böl: *Sen: "retry döngüsünü düzelt" → 12 eylem (3 düzenleme, 6 komut, 1 ⚠︎) → Ajan: "hatayı yüzeye çıkardım"*. Ham akış bir anahtar olarak kalsın. | M–L | ★★ |
| K6 | **Ortak eylem fiilleri** | `canonicalTool` ile satırlarda simge + fiil (▶ Çalıştırdı, ✎ Düzenledi, 👁 Okudu, 💬 Dedi). Ajana özgü ad detayda. Yollar `cwd`'ye göre göreli. | S | ★★ |
| K7 | **Arama** | Eşleşen pasajı vurgulu göster, mesajları ve istemleri de ara, `agent: project: rule: since:` sözdizimi, ⌘K ile "her yerden ara". | M | ★★ |
| K8 | **"Geçmişin silinmez" özelliği** | (a) Kaynak transkripti silinmiş oturumlara rozet: "Kaynak silindi — Trailwarden'da saklı". (b) Bu oturumlarda resume komutunu devre dışı bırak ve nedenini söyle. (c) Claude Code'un `cleanupPeriodDays` değerini oku (yalnızca okuma) ve "Claude bu oturumları N gün içinde silecek; Trailwarden saklıyor" bilgisini ver. (d) Saklama ayarını "ne kadar süre saklayayım" olarak yeniden çerçevele, varsayılan sınırsız. (e) README'de bunu ilk vaat yap. (f) **İsteğe bağlı tam kalitede arşiv:** ham transkriptlerin sıkıştırılmış kopyası (Apple Compression/LZFSE ile, ek bağımlılık olmadan), ajan temizliğine ve bağlam sıkıştırmasına (compaction) karşı. Disk kullanımı Ayarlar'da görünsün. *HN: bu konuya ayrılmış başlık ve ~20 mağdur; itiraz eden ~5 kişi "tek satırlık ayar" diyor, değer otomatik olmasında.* | M | ★★★ |
| K9 | **Oturum/proje maliyeti** | Zaman çizelgesinde oturum başlığında "≈$0,84", raporda proje başına maliyet. Grafiği ajana göre yığılmış yap. "sayaç" jargonunu kaldır. | M | ★★ |
| K10 | **Kota sinyalleri (ağsız)** | Codex `rate_limits` alanlarından 5 saatlik ve haftalık pencere doluluğu + sıfırlanma saati. Claude'un "usage limit reached · resets …" mesajlarından "Bu hafta 3 kez limite takıldın, son sıfırlanma 15:00". Açıkça **"transkriptten okunan, tahmini"** etiketiyle. Panelde tek satır, isteğe bağlı. *HN: kota/tempo yorumları dolar yorumlarından fazla; dolar rakamı karar girdisi değil, "aboneliğim ne kadar kârlı" övünmesi. Ama maliyet, kullanıcıların bu araç kategorisine ilk giriş kapısı.* | M | ★★★ |
| K11 | **Repo dışı yan etkiler görünümü** | Oturum başına "proje klasörü dışında dokunulanlar": LaunchAgent/cron, shell başlangıç dosyaları, `~/.ssh`, `~/.aws`, ajan ayar dosyaları, global paket kurulumları. *HN'de karşılanmamış asıl ihtiyaç: "repo içi değişikliği diff gösteriyor; dışarıda ne yaptığını hiçbir şey göstermiyor."* | M | ★★★ |
| K12 | **Sade dilde uyarılar** | Bildirim ve satırlarda ham komut yerine önce sonucu yaz: "Ev klasörünüzün tamamını siler", "AWS kimlik bilgilerinizi okudu". Ham komut ikinci satırda. *HN: ajanların ürettiği shell komutları "gördüğüm en okunaksız bash".* | S–M | ★★ |
| K13 | **Ajan için geri çağırma (MCP)** | Mevcut MCP sunucusuna `recall` / `search_sessions` gibi araçlar (eşleşen pasaj + oturum başlığı + resume komutu), uygulamada tek tıkla MCP kurulum sihirbazı. *HN: kazanan anlatım "ajanın kendi geçmişini sorgulaması"; Trailwarden'da bu altyapı zaten var ama görünmüyor.* | M | ★★ |
| K14 | **Ajan ayarlarında sır taraması** | Ajanların izin listelerine kaydettiği komutlarda parola/token var mı? (`.claude/settings.local.json` vb.). *HN'de 629 puanlık "Don't Ask Again parolaları açığa çıkarıyor" başlığı.* Mevcut maskeleme altyapısıyla yeni bir kural. | S | ★★ |

### 8.3 Orta vade (0.4–0.5 — stratejik bahisler)

**S1. Koruma doğrulayıcı ve bağımsız kayıt** *(M, ★★★)* — *HN doğrulamasından sonra "Kalkan" önerisinin yerini aldı*

İlk sürümde önerilen "Kalkan" (Trailwarden'ın kendi PreToolUse kancası) **geri çekildi**. Üç neden var:

1. **Onaysız mod (YOLO) çok yaygın** ve bu modda kancalar eşzamansız çalışıyor; komut, kanca engelleyemeden yürütülüyor (`nah` geliştiricisinin açıklaması ve anthropics/claude-code#20946).
2. **Kancalar atlatılabiliyor:** zincir komutlar, alt ajanlar, "izin ver" denince tekrar deneme.
3. **Satıcı önleme alanını kendisi dolduruyor:** auto mode varsayılan oldu, sandbox ürünleşti.

Trailwarden bu yarışa üçüncü bir kırılgan kanca olarak girerse farklılaşamaz. Bunun yerine bu katmanların **üstünde** durmalı:

- **"Korumanız devreye girmedi" uyarısı.** Ajan ayarlarından kurulu kancaları, izin/engel listelerini ve modu (auto/YOLO/sandbox) yalnızca okuyarak çıkar. Engellenmesi gereken bir komut transkriptte **çalışmış** görünüyorsa bunu ayrı ve yüksek öncelikli bir bulgu türü olarak göster: "Engel listenizde `~/.env` var ama Claude 14:02'de okudu."
- **Oturum güvenlik profili.** Her oturumun başında hangi modda çalıştığı (onaysız, sandbox, auto) rozet olarak görünsün. Rapor, "bu ay oturumların %62'si onaysız moddaydı" gibi bir içgörü versin.
- **Konumlandırma:** "Ajanın özeti değil, gerçekte ne yaptığının bağımsız kaydı." HN'de en çok karşılık bulan dil bu ("Not the agent's summary, the actual sequence"; "the only way to know what the agent did is logs"). Her tanıtımda gelecek **"Neden sandbox kullanmıyorsunuz?"** sorusunun cevabı hazır olsun: *"Kullanın. Sandbox etki alanını daraltır, Trailwarden içinde ve dışında ne olduğunu söyler."*
- Önleme isteyen kullanıcıya Trailwarden'ın kendi kancası yerine **mevcut araçları doğru kurdurmak**: ajanın sandbox/auto mode ayarına giden yol, deny-list önerisi (Trailwarden'ın bulgularından üretilmiş, kopyalanabilir).

**S2. Kurtarma asistanı: "Şimdi ne yapmalıyım?" kartları** *(M, ★★★)*

Her kural için olay detayında, kopyalanabilir ama **asla otomatik çalıştırılmayan** adımlar:

- *Yıkıcı silme* → yol git deposunda mı (`git status`/`git restore` önerisi), Time Machine yerel anlık görüntüleri (`tmutil listlocalsnapshots /`, yerel komut), Çöp Kutusu kontrolü.
- *Force‑push* → `git reflog` + önceki SHA ile kurtarma komutu.
- *launchd/cron kalıcılığı* → oluşturulan plist yolu ve `launchctl bootout` komutu.
- *Sır okuma / API anahtarı komutta* → ilgili sağlayıcının anahtar döndürme sayfası adı, `.env`'in git geçmişine girip girmediği kontrolü.
- *Yıkıcı SQL* → son yedek/migration hatırlatması.

Bu, "bildirim aldım ama ne yapacağım?" boşluğunu kapatır. Araştırmada mağdurların ikinci en sık talebi geri alma/kurtarma.

**S3. Davranışsal kurallar (regex ötesi)** *(M–L, ★★)*

- Oturum içi dizi kuralları: *sır okundu → ardından ağ komutu* (sızdırma deseni); *kısa sürede N'den fazla dosya silindi/üzerine yazıldı*; *aynı hedefe art arda `mv`* (Gemini olayı); *proje dışına yazma patlaması*.
- Gürültüyü artırmamak için varsayılan olarak "uyarı" seviyesinde ve yalnızca raporda göster.

**S4. Ekip/denetim katmanı (hâlâ tamamen yerel)** *(M, ★ — HN'de talep zayıf, ertelenebilir)*

*HN doğrulaması: yaklaşık 15 "yönetişim" Show HN'i çoğunlukla 1–3 puan aldı; kurumsal ilgi sonradan okunan loglardan çok erişim kısıtlama ve kimlik tarafında. Bu katman, geçmiş/kota/gelen kutusu işleri bitmeden başlatılmamalı.*

- `export --json`, `--csv`, **`--sarif`**. SARIF ile CI kapısı GitHub code scanning'e doğrudan bağlanır.
- **Değiştirilemezlik kanıtı:** dışa aktarımlara hash zinciri veya imza; "bu kayıt sonradan değiştirilmedi" denetçiye gösterilebilir.
- Zamanlanmış **haftalık rapor dosyası** (ör. `~/Documents/Trailwarden/2026-W47.md`) ve isteğe bağlı haftalık yerel bildirim: "Bu hafta: 4 bulgu (3'ü incelendi), ≈$18 API karşılığı, en çok değişen dosya `router.ts`".

**S5. Bilgi mimarisi sadeleştirme** *(M, ★★)*

Bugün ↔ Rapor ↔ panel arasında örtüşme var. Görev odaklı 4 bölüm önerisi:

1. **Gelen kutusu**: incelenecek bulgular, bugünün özeti.
2. **Oturumlar**: konuşma görünümü, arama, resume, diff.
3. **İçgörüler**: rapor + kullanım + maliyet, tek dönem seçicisi.
4. **Kurallar ve koruma**: kurallar, izin listesi, koruma doğrulayıcı.

Ayarlar ayrı kalır. Bu, CodexBar'ın "şişkinlik" tuzağına karşı da bir sigorta: her yeni özelliğin hangi bölüme ait olduğu sorusu disiplini korur.

### 8.4 Yapmayın / dikkat

- **Sağlayıcı API'lerine, çerezlere veya keychain'e gidip kesin kota çekmeyin.** Rakiplerin en büyük şikâyet kaynağı (keychain istemleri, oturum kopmaları). Gizlilik sözünüzü bozar. Transkriptten okunan sinyallerle yetinin ve "tahmini" deyin.
- **Menü çubuğu panelini büyütmeyin.** Panel 5 saniyelik cevap yeri olarak kalsın: koruma durumu, incelenecek bulgu sayısı, son 5 eylem, (isteğe bağlı) tek satır kota. Gerisi pencerede.
- **Bulut senkronizasyonu eklemeyin.** Çoklu makine talebi var, ama ürünün kimliği yerellik. Bunun yerine "dizini dışa/içe aktar" (dosya) yeterli.
- **Kendi önleme kancanızı yazmayın** (bkz. S1). Onaysız modda kancalar komutu durduramıyor ve bu alanı satıcılar dolduruyor; üçüncü bir kırılgan kanca farklılaşma getirmez.
- **Kalabalık kategoride "slop" algısına dikkat.** HN'de yeni araçlara ilk tepki "CodexBar'dan farkı ne?" ve "AI ile üretilmiş gibi". README kısa, insan sesiyle yazılmış olsun ve rakiplerle bir karşılaştırma tablosu içersin.
- **Kural sayısını pazarlama metriği yapmayın** ("27 kural"). Kullanıcı için anlamlı metrik **yanlış alarm oranı**dır.

---

## 9. Yeni fikirler (farklılaştırıcılar)

1. **"Gece vardiyası raporu."** Uzun/gözetimsiz çalışan oturumlar bittiğinde (oturum X dakika sessiz kaldı) tek bildirim: "Codex gece 412 komut çalıştırdı · 23 dosya değişti · 1 uyarı · ≈$3,10 · [Özeti aç]". README'deki "400 komut + kötü bir his" senaryosunun birebir cevabı.
2. **Ajan karşılaştırma kartı.** Aynı projede ajanlara göre değişen satır, test çalıştırma sıklığı, bulgu oranı, maliyet. "Hangi ajan bu repoda daha güvenli/ucuz?" sorusu. 7 ajanı okuyan tek ürün olmanın doğal getirisi.
3. **Proje güven profili.** Her proje için "beklenen davranışlar" (ör. bu repoda `.github/workflows` düzenlemek normal, `DROP TABLE` test DB'sinde normal). İzin listesi kapsamlarının kullanıcı dostu yüzü.
4. **MCP'yi kullanıcıya görünür kılmak.** "Ajanlarınız Trailwarden'a şu soruları sordu" paneli ve MCP kurulumunu tek tıkla yapan sihirbaz (Claude Code/Codex/Cursor yapılandırmasına eklenecek satırı gösterip kopyalatan).
5. **Dosya dosya "Ajan blame" kenar çubuğu.** Bir dosyayı pencereye sürükle-bırak → o dosyanın tüm ajan geçmişi, diff'leriyle. CLI'daki `who` komutunun görsel karşılığı.
6. **Kural "dersleri".** Her bulgu detayında 2 cümlelik "bu neden riskli?" açıklaması ve ilgili ajanın güvenli ayarına bağlantı (ör. "Codex'te `--sandbox workspace-write` kullanın"). Ürünü bir öğretmene dönüştürür ve güveni artırır.
7. **Haftalık "temiz hafta" serisi.** Hafif oyunlaştırma: "3 haftadır kritik bulgu yok". Raporda küçük bir rozet. Abartmadan, bilgi amaçlı.

---

## 10. Telemetrisiz ürün ölçümü önerisi

Trailwarden telemetri toplamıyor (doğru karar). Yine de neyin işe yaradığını öğrenmenin yolları:

- **Yerel ölçüm ve gönüllü paylaşım:** `trailwarden doctor --share` yalnızca sayıları içeren, maskelenmiş bir özet üretsin (kural başına bulgu ve yanlış alarm işaretleme sayıları, ajan dağılımı, sürüm). Kullanıcı isterse issue'ya yapıştırır.
- **Yanlış alarm geri bildirimi (K2)** doğrudan kural kalitesini ölçer.
- **GitHub Discussions'ta** "Bu bulgu işe yaradı mı?" anketi, sürüm notlarında "en çok istenenler" bölümü.
- İzlenecek başarı göstergeleri (kullanıcı beyanı + gönüllü özetler): ilk haftadan sonra canlı korumanın açık kalma oranı · incelenmeyen bulgu birikimi · kural başına yanlış alarm oranı · "geçmişimi kurtardı" anekdotları.

---

## 11. Hacker News doğrulaması (23 Kasım 2026)

İlk raporun hipotezleri Hacker News'te sınandı. Yöntem: Algolia API ile ~195 sorgu (Ocak 2025 sonrası), ~12.000 benzersiz kayıt, ~54 başlık baştan sona okundu. Sayımlar regex tahminidir ve araç yapımcılarının kendi tanıtımlarını da içerir. Alıntıların bir kısmı kaynaktan ayrıca kontrol edildi. Reddit'e erişilemedi.

| Hipotez | Sonuç | Kanıt özeti |
|---|---|---|
| Geçmiş kaybı güçlü bir acı, kalıcı arşiv isteniyor | **Güçlendi (en güçlü)** | Konuya ayrılmış başlık ([48732846](https://news.ycombinator.com/item?id=48732846)), ~20 yazardan ~23 yorum, en az 5 arşiv aracı. "Some CLI startup paths don't load the config, use the 30 day default. Boom, your chats are gone… silently" ([48735074](https://news.ycombinator.com/item?id=48735074)). "Two of my projects lost their whole history that way" ([48921255](https://news.ycombinator.com/item?id=48921255)). İtiraz: "crontab ile kopyala" (~5 kişi). |
| Tam metin arama, okunabilir oturum adları, resume | **Arama güçlendi, resume'a nüans** | Yerleşik seçici "yalnızca ilk mesaja veya isme göre filtreliyor" ([48012400](https://news.ycombinator.com/item?id=48012400)). Asıl iş **geri çağırma** ("geçen sefer nasıl çözmüştük"). Resume ise çoğunlukla kota dolunca veya yeniden başlatınca gerekiyor; bazıları hiç kullanmıyor. |
| Değişiklik incelemesi (diff) | **Değişmedi, keskin nüans** | İnceleme `git diff` ile yapılıyor. "Bu dosyaya hangi ajan dokundu" için kendiliğinden gelen talep yok. Karşılanmamış ihtiyaç: **repo dışı yan etkiler** ve **neden**. |
| Yerellik / telemetri yok önemli | **Güçlendi (giriş şartı)** | ~98 yorum. Oturum yükleyen araçlara sert tepki: "Your Claude Code sessions will now be uploaded automatically. No, thanks" ([47350914](https://news.ycombinator.com/item?id=47350914)). Yerellik tek başına çekim yaratmıyor ama yokluğu eliyor. |
| Çoklu ajan kullanıcıları tek görünüm istiyor | **Güçlendi (orta)** | 2026'da en az 10 ajanlar arası geçmiş aracı çıktı. Kullanıcılar kota yüzünden ajan değiştiriyor ([48828332](https://news.ycombinator.com/item?id=48828332)). Risk: satıcıların masaüstü uygulamaları kendi birleşik geçmişini getiriyor. |
| Abonelik kullanıcısı için kota > dolar | **Güçlendi** | Kota/tempo yorumları dolar yorumlarından fazla (~638'e ~536). "I want… 'you've used x% of your paid quota'" ([44714435](https://news.ycombinator.com/item?id=44714435)). Dolar rakamları karar girdisi değil, "aboneliğim ne kadar kârlı" övünmesi. Satıcının limitleri opak olduğu için doğruluk güvensizliği de var. |
| Önleme > tespit; geri alma isteniyor | **Çoğunlukla doğrulandı + gerçek bir azınlık** | Baskın görüş sandbox ve önleme. Bir denetim aracına ilk yanıt: "Sounds like your solution comes too late, innit?" ([50382260](https://news.ycombinator.com/item?id=50382260)). Ama bağımsız kayıt savunucuları da var: "don't try to prevent, just have an independent record of what the agent actually did. Not the agent's summary" ([47364428](https://news.ycombinator.com/item?id=47364428)). Trailwarden'a en yakın örnek de bu çizgide: bir Claude Code oturumunun fark edilmeden LaunchAgent yazdığını anlatıyor ([48830674](https://news.ycombinator.com/item?id=48830674)). |
| Onay/alarm yorgunluğu merkezi | **Güçlendi** | ~49 yorum; YOLO, sandbox ve auto mode araçlarının çıkış hikâyesi. İzin listeleri kırılgan: oturumdan oturuma küçük farklar listeye uymuyor ([49239569](https://news.ycombinator.com/item?id=49239569)). |
| Menü çubuğu araçları hızlı ve sade olmalı | **Hafif güçlendi (zayıf kanıt)** | ~4 kendiliğinden gelen şikâyet. Keychain istemi yüzünden kaldırma: "prompted at least once a day… going to uninstall it" ([46827649](https://news.ycombinator.com/item?id=46827649)). |
| Ekipler denetim/uyum istiyor | **Değişmedi ile zayıf arası** | ~15 yönetişim Show HN'i çoğunlukla 1–3 puan. Kurumsal ilgi erişim kısıtlama ve kimlik tarafında. |
| YOLO modu yaygın mı? | **Güçlü biçimde doğrulandı** | ~194 birinci ağızdan kullanım anlatımı; ~72'si konteyner/VM/sandbox anıyor, bir kısmı açıkça kendi makinesinde. "alias claude='claude --dangerously-skip-permissions'… everyday for about a year" ([49240228](https://news.ycombinator.com/item?id=49240228)). **Sonradan okunan bir gözlemcinin değerini doğrudan büyüten bulgu.** |
| Kanca tabanlı korumalar kırılgan | **Güçlendi** | YOLO modunda kancalar eşzamansız çalışıyor: "commands execute before nah can block them" ([47344639](https://news.ycombinator.com/item?id=47344639)). `~/.env` engeli "izin ver" denince aşıldı ([46417111](https://news.ycombinator.com/item?id=46417111)). |

**HN'den çıkan yeni temalar ve rapora etkileri**

1. **Kimlik bilgileri ve kalıcılık, `rm -rf`'ten daha çok yankı buluyor.** Geniş yetkili API token'ları, LaunchAgent, ayar dosyalarına sızan parolalar (629 puanlık "Don't Ask Again" başlığı). → Kural ağırlığı bu yöne kaymalı (K14, ilk adımlar #4).
2. **Ajanın kendi anlatımına güvenilmiyor.** → "Bağımsız kayıt" konumlandırması (S1).
3. **Ajan bir tüketici olarak.** Geçmişi ajanın sorgulaması en çok ilgi gören anlatım. → MCP geri çağırma (K13).
4. **Maliyet giriş kapısı.** Kullanıcılar maliyet için gelip geçmiş için kalıyor. → Kullanım ekranı edinme kanalı olarak önemli; kota sinyali öncelik kazandı (K10).
5. **Okunaksız komutlar.** → Sade dilde uyarılar (K12).
6. **Bağlam sıkıştırması geçmişi değiştiriyor.** → Tam kalitede arşiv (K8-f).
7. **Kategori doygunluğu ve "slop" yorgunluğu.** → README ve tanıtım dili (§8.4).

**Önerilere net etkisi:** "Kalkan" geri çekildi, yerine "Koruma doğrulayıcı" geldi. Arşiv, kota sinyali, repo dışı yan etkiler ve sade dilde uyarılar yükseldi. Ekip/denetim katmanı ertelendi. Diff önerisi "neden" ve "git'in görmediği" yönüne çevrildi.

## Ek A — Muadil ürünlerden seçilmiş kaynaklar

**Kullanım/maliyet:** ccusage [#483](https://github.com/ccusage/ccusage/issues/483), [#146](https://github.com/ccusage/ccusage/issues/146), [#855](https://github.com/ccusage/ccusage/issues/855), [#222](https://github.com/ccusage/ccusage/issues/222) · Claude‑Code‑Usage‑Monitor [#167](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/167), [#48](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/48), [#137](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/137) · CodexBar [#1364](https://github.com/steipete/CodexBar/issues/1364), [#1274](https://github.com/steipete/CodexBar/issues/1274), [#340](https://github.com/steipete/CodexBar/issues/340), [#81](https://github.com/steipete/CodexBar/issues/81) · ccstatusline [#124](https://github.com/sirmalloc/ccstatusline/issues/124)

**Geçmiş/oturum:** [anthropics/claude-code#46621](https://github.com/anthropics/claude-code/issues/46621) (30 günlük silme) · [Agent Sessions](https://github.com/jazzyalex/agent-sessions) ve [issue listesi](https://github.com/jazzyalex/agent-sessions/issues) · [claude-code-history-viewer issue'ları](https://github.com/jhlee0409/claude-code-history-viewer/issues)

**Güvenlik/olaylar:** [dcg](https://github.com/Dicklesworthstone/destructive_command_guard) · [cc-safe-setup hook hataları](https://dev.to/yurukusa/5-claude-code-hook-mistakes-that-silently-break-your-safety-net-58l3) · [Anthropic: auto mode](https://anthropic.com/engineering/claude-code-auto-mode) · [Anthropic: sandboxing](https://anthropic.com/engineering/claude-code-sandboxing) · [Docker: rm -rf olayı](https://www.docker.com/blog/coding-agent-horror-stories-the-rm-rf-incident/) · [Simon Willison](https://simonwillison.net/2025/Dec/9/claude/) · [Fortune: Replit](https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database-called-it-a-catastrophic-failure/) · [Little Snitch uyarı tercihleri](https://help.obdev.at/littlesnitch6/pref-alert) · [Claude Code checkpointing](https://code.claude.com/docs/en/checkpointing)

*Not: Yıldız ve tepki sayıları araştırma anındaki anlık görüntülerdir; bazı kaynaklar yalnızca arama özetinden doğrulanabildi.*
