<!-- SPDX-License-Identifier: Apache-2.0 -->
# Kurulum yöntemleri

Her yöntem aynı iki şeyi kurar: menü çubuğu uygulaması ve/veya komut satırı araçları
(`trailwarden`, `trailwarden-mcp`). Uygulama ağ erişimi kullanmaz; kurulumdan sonra
da hiçbir veri dışarı gitmez.

| # | Yöntem | Ne kurar | Durum |
|---|---|---|---|
| 1 | Homebrew cask (kendi tap) | Uygulama | Tap açılınca |
| 2 | Homebrew formula (kaynaktan) | CLI + MCP | Tap açılınca |
| 3 | DMG (GitHub Releases) | Uygulama | İmzalı sürüm hazır olunca |
| 4 | npm (`-g`) | MCP sunucusu | Paket yayınlanınca |
| 5 | Kaynaktan (`make install`) | CLI + MCP | **Bugün çalışır** |
| 6 | Resmî `homebrew-cask` | Uygulama | 75 yıldız sonrası başvuru |

## 1. Homebrew cask (kendi tap)

```bash
brew install --cask tnalbant/trailwarden/trailwarden
```

Tap bir kez açıldığında bu komut DMG'yi indirir, imzasını doğrular ve uygulamayı
`/Applications` içine koyar.

## 2. Homebrew formula (CLI + MCP, kaynaktan)

```bash
brew install tnalbant/trailwarden/trailwarden-cli
```

Xcode komut satırı araçlarını gerektirir; Swift ile derler (~1 dk).

## 3. DMG (GitHub Releases)

Releases sayfasından `Trailwarden-<sürüm>.dmg` indir, aç, `Trailwarden.app`'i
`/Applications` içine sürükle.

İmzalı ve notarized sürümde Gatekeeper uyarı çıkarmaz. İmzasız sürümde:
`System Settings → Privacy & Security → Open Anyway`.

## 4. npm (MCP sunucusu)

```bash
npm install -g trailwarden-mcp
```

Paket, derlenmiş Swift ikilisini içinde taşır: kurulumda ağ erişimi gerekmez.

MCP istemcisine eklemek için:

```json
{
  "mcpServers": {
    "trailwarden": {
      "command": "trailwarden-mcp",
      "args": ["--db", "~/Library/Application Support/Trailwarden/trailwarden.sqlite"]
    }
  }
}
```

## 5. Kaynaktan

```bash
git clone https://github.com/tnalbant/trailwarden.git
cd trailwarden
make install            # /usr/local/bin (gerekirse sudo)
make install PREFIX=~/.local
```

`make app` uygulamayı derler, `make release` DMG + tarball + sha256 üretir.

## 6. Resmî homebrew-cask

Resmî depoya girmek için 75 yıldız şartı var; o eşiğe gelince başvurulur. O zamana
kadar kendi tap kullanılır.

---

## Doğrulama

```bash
trailwarden doctor          # okunabilen ajan dosyalarını listeler
trailwarden watch           # canlı: her bulguyu oluştuğu anda yazar
trailwarden who README.md   # bu dosyaya hangi ajan dokundu
trailwarden --help
```

Uygulama ilk açılışta neyi okuyacağını gösterir; `Tara` düğmesi mevcut
transkriptleri indeksler ve ardından 30 günlük karneyi açar. Canlı bekçi bundan
sonra kendiliğinden çalışır ve kritik bir komutta bildirim gönderir (Ayarlar →
Canlı bekçi).
