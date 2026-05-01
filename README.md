# KeyCheck

<p align="center">
  <img src="Cluade_export/readme_hero_1600x800.png" alt="KeyCheck — macOS keyboard tester" width="100%">
</p>

自作キーボード(ZMK / QMK等)のキー入力を確認するための、シンプルなmacOS用キーテスター。

Karabiner-EventViewer風の表示で、**全キーで音が鳴る** (Karabinerは modifier キーで音が鳴らない問題を解決)。音量は0-150%まで調整可能。

## 機能

- **キー / マウスボタン / modifier の表示**: Karabinerスタイル (`{"key_code":"left_shift"}`) + USB HID usage code
- **音フィードバック**: 4種類の音 (Click / Beep / Pop / Tick) ・ 0-150%音量 (100%超は EQ ゲインで増幅)
- **キャプチャモード** (オプション): トグルONの間、システムのショートカット (Cmd+Space, Spotlight, Claude のホットキー等) を全部食う。キーテスト中に他のショートカットが暴発しないため
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
cd mac_keychec
./build.sh
open KeyCheck.app
```

`build.sh` は以下の優先度で署名を選択:
1. Apple Development / Developer ID (キーチェーンにあれば自動使用)
2. KeyCheck Local Signer (`./setup_signing.sh` で作成した自己署名)
3. Ad-hoc署名 (フォールバック・権限が再ビルドで失効する)

## 権限について

| 機能 | 必要権限 |
|---|---|
| 通常のキー監視 | **不要** (アプリにフォーカスがある時のみ動作) |
| キャプチャモード | **アクセシビリティ** (`システム設定 → プライバシーとセキュリティ → アクセシビリティ`) |

キャプチャモードは初回ONにした時に macOS が許可ダイアログを出します。許可後、トグルをOFF→ONし直してください。

### 権限がリセットされる時の対処

ad-hoc署名でビルドしている場合、リビルドの度に macOS が「別アプリ」として認識して権限が失われます。これを防ぐには:
- 上記の Apple Development 証明書を入れる (推奨)
- もしくは `./setup_signing.sh` で自己署名証明書を作る
- どちらも嫌なら、リビルド毎に `tccutil reset Accessibility local.yuchamichami.keycheck` で手動リセット

## ファイル構成

```
.
├── main.swift          # 全コード (UI + イベント監視 + 音)
├── Info.plist          # アプリバンドル設定
├── build.sh            # swiftc → .app バンドル化 + 自動署名
├── setup_signing.sh    # 自己署名証明書作成 (任意)
└── README.md
```

## License

MIT
