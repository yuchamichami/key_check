# KeyCheck

<p align="center">
  <img src="design/brand/readme_hero_1600x800.png" alt="KeyCheck — keyboard tester" width="100%">
</p>

自作キーボード(ZMK / QMK等)用のキーテスター。Karabiner-EventViewer風表示で、**全キーで音が鳴る** (modifier含む)、音量0–150%。

| | 即起動 | カスタム | 無変換/変換 |
|---|:---:|:---:|:---:|
| 🌐 [**ブラウザ版**](https://yuchamichami.github.io/key_check/) | ✅ | — | ✅ Chrome等で取れる |
| 🖥️ ネイティブ (.app) | — | ✅ ZMK向けカスタマイズ可 | ❌ NSEvent制約 |

## 機能

- **Karabinerスタイル表示**: `{"key_code":"left_shift"}` + USB HID usage page/code、左右別 modifier (`left_command` / `right_shift` 等)
- **全キー音響フィードバック** — 4音色 (Click / Beep / Pop / Tick)、ロータリーノブで0–150%音量 (100%超は EQ ゲインで増幅)
- **マウスボタン対応** — `{"pointing_button":"buttonN"}`
- **Copy / Clear** — イベントログをクリップボードへ

## クイックスタート

### ブラウザ版 (推奨)
何もインストールせずに即起動: **https://yuchamichami.github.io/key_check/**

### ネイティブ (.app) 版

```bash
git clone https://github.com/yuchamichami/key_check.git
cd key_check
./build.sh
open KeyCheck.app
```

`build.sh` が以下の優先度で自動署名:
1. **Apple Development / Developer ID** (キーチェーンにあれば自動使用 — 推奨)
2. **KeyCheck Local Signer** (`./setup_signing.sh` で自己署名作成)
3. **Ad-hoc** (フォールバック)

> Apple Development 証明書は Xcode → Settings → Accounts に Apple ID を追加して `+` から無料で作成できます。安定したcdhashになるので、リビルドしても権限がリセットされません(NSEventベースの現行版は権限不要なので関係なし)。

## 制約

| | 取れない / 制限あり |
|---|---|
| ネイティブ版 | `japanese_pc_nfer` (無変換)、`japanese_pc_xfer` (変換) — NSEventがmacOSレベルでこれらを配信しないため |
| ブラウザ版 | `Cmd+W` `Cmd+Q` `Cmd+R` `Cmd+T` — ブラウザ/OSが先取りする |

## ファイル構成

```
.
├── main.swift              # ネイティブ版コード (UI + イベント監視 + 音)
├── Info.plist              # アプリバンドル設定
├── build.sh                # swiftc → .app バンドル化 + 自動署名
├── setup_signing.sh        # 自己署名証明書作成 (任意)
├── KeyCheck.icns           # アプリアイコン
├── docs/
│   └── index.html          # ブラウザ版 (GitHub Pagesから配信)
└── design/
    ├── brand/              # アイコン・ヒーロー・ソーシャルプレビューのソース
    └── ui/                 # UIリデザインのモックアップ・トークン
```

## License

MIT

## Corcellの出荷前キー検査（ブラウザ版）

DYA Studioを開かずに、KeyCheckからUSB経由で物理キーを検査できます。
レイヤー切替など、PCにキーコードを送らない親指キーも押下音と色で確認できます。
Macアプリ版にはこの機能は含まれません。

1. PC版Chrome / EdgeでKeyCheckを開き、**dya-studio版ファームのCorcell右側**をUSB接続します。左側も電源を入れます。
2. **USBを選んで検査開始**でCorcellのポートを選びます。DYA Studioなど、同じポートを使うタブは閉じてください。
3. キーを**1つずつ押して離す**と、押下時に音が鳴り、確認済みのキーが緑になります。音色・音量は既存のコントロールで調整できます。
4. **50 / 50**で全キーの押下・解放を確認済みです。必要なら**結果を保存**でJSONを保存します。
5. 別の個体を接続するときはUSBを選び直します。同じポートの抜き差しでは、このタブが開いている間は再接続を試みます。切断すると検査結果はクリアされます。

初回のポート選択はブラウザの許可操作なので省略できません。ポートが2つ表示されて応答がない場合は、もう一方を選んでください。USB入力が出ない場合はL3+UでUSB出力にします。現行dya-studio設定ではUSBのStudioアンロック操作は不要です。

表示はCorcellの初期配列に対応する50個の物理位置です。通常のキー動作も有効なので、検査中はレイヤーキーと他のキーを同時押ししないでください。押下・解放の欠落や不整合を検出した場合は「検査をやり直す」で再検査してください。

これは物理キーの導通確認です。チャタリングの定量検査、Bluetooth、ポインタ、電池などの出荷判定は別途必要です。結果の保存先はローカルで、キー情報をサーバーへ送信しません。

### 開発・検証

```sh
node --test tests/corcell.test.mjs
python3 -m http.server 8765 --directory docs
```

`http://localhost:8765`で確認できます（HTMLの直接ファイル起動は非対応）。
USB通信には既存ファームの`zmk__input_stream`を使用し、キーマップや設定の書き換えは行いません。
プロトコルは[cormoranのStudioクライアント](https://github.com/cormoran/zmk-studio-ts-client/tree/custom-studio-protocol%2Bbluefy)と[入力ストリーム定義](https://github.com/cormoran/zmk-feature-input-stream/blob/main/proto/zmk/input_stream/input_stream.proto)を参照しています。
自動テストは通信フレーム・動的な機能番号・押下/解放・接続/切断を模擬します。実機のUSB、左右間通信、音の確認は別途必要です。

### 英数・かな・変換の検査

ブラウザ版は`Lang1`を`japanese_kana`、`Lang2`を`japanese_eisuu`として表示します。`code`が空でも、識別できる`key`名や変換キーの旧イベント値から判定します。IMEの汎用イベント（`Process` / 229）だけでは特定の日本語キーを押したと推定しません。

「ブラウザ入力の受信状況」にはフィルター前の`keydown` / `keyup`が表示されます。ページにフォーカスがある状態でも件数が増えず、Karabinerにだけ表示される場合は、ページがキーイベントを受け取れていません。JavaScriptの名前変換だけでは復元できないため、上のUSB物理キー検査で直接通知を受信してください。

日本語キー判定を含むテスト: `node --test tests/*.test.*`
