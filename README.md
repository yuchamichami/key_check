# KeyCheck

<p align="center">
  <img src="Cluade_export/readme_hero_1600x800.png" alt="KeyCheck — macOS keyboard tester" width="100%">
</p>

自作キーボード(ZMK / QMK等)のキー入力を確認するための、シンプルなmacOS用キーテスター。

Karabiner-EventViewer風の表示で、**全キーで音が鳴る** (Karabinerは modifier キーで音が鳴らない問題を解決)。音量は0-150%まで調整可能。

**ブラウザ版もあります → https://yuchamichami.github.io/key_check/** (インストール不要・即起動)

## 機能

- **キー / マウスボタン / modifier の表示**: Karabinerスタイル (`{"key_code":"left_shift"}`) + USB HID usage code
- **音フィードバック**: 4種類の音 (Click / Beep / Pop / Tick) ・ 0-150%音量 (100%超は EQ ゲインで増幅)
- **左右別 modifier**: `left_command` / `right_shift` 等を区別
- **コピー / クリア**: イベントログをクリップボードへ

## 制約

NSEvent APIベースのため、以下のキーは取れません:
- `japanese_pc_nfer` (無変換)
- `japanese_pc_xfer` (変換)

これらの確認には [Karabiner-EventViewer](https://karabiner-elements.pqrs.org/) を併用してください。

## ビルド

### 必要なもの

- macOS 13.0+
- Xcode コマンドラインツール (`xcode-select --install`)
- Apple Development 証明書 (推奨。無料の Apple ID で取得可能。なくてもビルドはできるが署名なしになる)

### Apple Development 証明書の作成 (任意・初回のみ)

権限が再ビルドの度にリセットされるのを防ぐため、安定した署名を使うことを推奨。

1. Xcode を開く → Settings → Accounts → Apple ID を追加
2. アカウント選択後、Manage Certificates → `+` → "Apple Development"

これで `Apple Development:` 証明書がキーチェーンに入る。`build.sh` が自動検出して使う。

### ビルド & 起動

```bash
git clone <このリポジトリ>
cd key_check
./build.sh
open KeyCheck.app
```

`build.sh` は以下の優先度で署名を選択:
1. Apple Development / Developer ID (キーチェーンにあれば自動使用)
2. KeyCheck Local Signer (`./setup_signing.sh` で作成した自己署名)
3. Ad-hoc署名 (フォールバック・権限が再ビルドで失効する)

## 権限について

権限は **不要** です。NSEvent ローカルモニターを使うので、アプリにフォーカスがある時だけキー入力を捕捉します。

## ファイル構成

```
.
├── main.swift              # ネイティブ版コード (UI + イベント監視 + 音)
├── Info.plist              # アプリバンドル設定
├── build.sh                # swiftc → .app バンドル化 + 自動署名
├── setup_signing.sh        # 自己署名証明書作成 (任意)
├── KeyCheck.icns           # アプリアイコン
├── docs/index.html         # ブラウザ版 (GitHub Pagesから配信)
├── Cluade_export/          # アイコン・ヒーロー画像のソースアセット (Claude Design製)
├── Cladesign_export2/      # UI リデザインのソースアセット (モックアップ・トークン)
└── README.md
```

## License

MIT
