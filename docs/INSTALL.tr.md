<!-- SPDX-License-Identifier: Apache-2.0 -->
# Trailwarden kurulumu

[English](INSTALL.md) · **Türkçe**

Her yöntem menü çubuğu uygulamasını, komut satırı araçlarını (`trailwarden`,
`trailwarden-mcp`) ya da ikisini birden kurar. Kurulumdan sonra ajanlarına dair
hiçbir şey makineden çıkmaz; ağ okumaları yalnızca isteğe bağlı güncelleme
denetimi ve, yalnızca "Fiyatları güncelle"ye tıkladığında, herkese açık
`prices.json` dosyasıdır ([Gizlilik](../README.tr.md#gizlilik) bölümüne bak).

| # | Yöntem | Ne kurar | Ne zaman |
|---|---|---|---|
| 1 | Homebrew cask (kendi tap'i) | Uygulama | evet |
| 2 | Homebrew formula (kaynaktan derler) | CLI + MCP | evet |
| 3 | DMG (GitHub Releases) | Uygulama | evet |
| 4 | npm (`-g`) | MCP sunucusu | evet |
| 5 | Kaynaktan (`make install`) | CLI + MCP | evet |
| 6 | Resmi `homebrew-cask` | Uygulama | repo koşulları sağladıktan sonra |

Gereksinimler: macOS 14 (Sonoma) veya üstü. Kaynaktan derlemek için Xcode komut
satırı araçları (Swift 6) gerekir.

## 1. Homebrew cask (kendi tap'i)

```bash
brew trust tnalbant/trailwarden   # bir kez: yeni Homebrew üçüncü taraf tap'leri kullanmadan önce onay ister
brew tap tnalbant/trailwarden     # bir kez
brew install --cask trailwarden
```

En yeni sürümün DMG'sini indirir, sağlama toplamını denetler ve
`Trailwarden.app` dosyasını `/Applications` içine koyar.

## 2. Homebrew formula (CLI + MCP, kaynaktan)

```bash
brew install trailwarden-cli      # yukarıdaki iki "bir kez" satırından sonra
```

Xcode komut satırı araçları gerekir; Swift ile derler (yaklaşık bir dakika).

## 3. DMG (GitHub Releases)

[Releases](https://github.com/tnalbant/trailwarden/releases) sayfasından
`Trailwarden-<version>.dmg` dosyasını indir, aç ve `Trailwarden.app` dosyasını
`/Applications` içine sürükle.

İmzalı ve Apple tarafından onaylanmış (notarized) bir derleme Gatekeeper uyarısı vermeden açılır.
İmzasız bir derleme için: `System Settings → Privacy & Security → Open Anyway`.

## 4. npm (MCP sunucusu)

```bash
npm install -g trailwarden-mcp
```

Paket derlenmiş Swift ikilisini içerir; bu yüzden kurulum için npm kayıt
defterinin kendisi dışında ağ erişimi gerekmez.

Bir MCP istemcisine eklemek için:

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
make install                   # /usr/local/bin (may need sudo)
make install PREFIX=~/.local   # or anywhere on your PATH
```

`make app` menü çubuğu uygulamasını derler; `make release` DMG'yi, CLI tar
arşivini ve bunların SHA-256 sağlama toplamlarını üretir.

## 6. Resmi homebrew-cask

Resmi repo uygulamaları ancak yeterince tanındıktan sonra kabul eder (yıldız,
fork ve izleyici sayısına bakar). O zamana kadar yukarıdaki tap'i kullan.

---

## Çalıştığını denetle

```bash
trailwarden doctor          # which agent histories it can read
trailwarden watch           # live: print each finding as it happens
trailwarden who README.md   # which agent touched this file
trailwarden --help
```

Uygulama ilk açılışta neyi okuyacağını gösterir. **Tara** mevcut geçmişleri
indeksler, sonra 30 günlük karneyi açar. Bundan sonra canlı bekçi kendiliğinden
çalışır ve bir ajan kritik bir şey çalıştırdığında bildirim gönderir
(Ayarlar → Canlı bekçi).

## Kaldırma

```bash
brew uninstall --cask trailwarden        # or drag Trailwarden.app to the Trash
brew uninstall trailwarden-cli
make uninstall                           # if installed from source
rm -rf ~/Library/Application\ Support/Trailwarden   # the index; your agents' files are untouched
```
