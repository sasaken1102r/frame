# ささけん＠の Steam Frame アプリ

PC なしで、Frame の中だけで手短にインストール。Steam Frame 用の自作アプリ 5 つを、Frame の Konsole にコマンドを入力して、メニューから選んでインストール・更新・アンインストール（削除）するためのスクリプトです。1 つだけでも、5 つ全部でも入れられます。

[English below](#english)

## インストールのしかた

ヘッドセットの Konsole（デスクトップモードのターミナル）で:

```sh
curl -fsSL https://frame.sasaken1102s.net | sh
```

アプリの一覧が出るので、インストールしたいアプリの番号を入力して Enter を押します（複数なら `1 3` のようにスペースで区切る、`a` で全部、`u` でアンインストール、`q` で終了）。インストール済みのアプリを選ぶと最新版に更新します。聞くのは、そのアプリで選ぶ必要のあることだけです（frameeyeosc のパネルもインストールするか、など）。

| アプリ | 中身 |
|---|---|
| [frameeyeosc](https://github.com/sasaken1102r/frameeyeosc) | 視線とまぶたを OSC で VRChat に送る |
| [frame-jp-keyboard](https://github.com/sasaken1102r/frame-jp-keyboard) | VR キーボードにフリック入力とかな漢字変換 |
| [frame-mic-tuner](https://github.com/sasaken1102r/frame-mic-tuner) | マイクのエコー除去・ノイズ除去を切り替える |
| [frame-perf-overlay](https://github.com/sasaken1102r/frame-perf-overlay) | フレームレート・温度などを視界の隅に出す |
| [frame-aux-shortcuts](https://github.com/sasaken1102r/frame-aux-shortcuts) | aux ボタンを、押し方ごとのショートカットにする |

使う前に、各アプリの README（必要なもの・注意）を読んでください。

## アンインストール（削除）のしかた

上と同じコマンドで、メニューの `u` から選びます。設定も消すかどうかは聞かれます（既定は残す）。

## やること・やらないこと

- 各アプリの GitHub の最新リリースから tar.gz と `SHA256SUMS` をダウンロードし、**SHA-256 が合ったものだけ**をインストールします。アーカイブに絶対パスや `..`、リンクが入っていたら止めます
- 展開したリリースの `install.sh` を実行するだけです。入る場所・入るものは、手で `./install.sh` したときと同じです（出力もそのまま見えます）
- **sudo は使いません**。書き込むのは**ホームフォルダの中だけ**です（一時フォルダ `~/.cache/frame-installer/` は終わったら消します）
- インストールしたあとの更新は、各アプリのパネルやキーボードの更新ボタンからもできます

`SHA256SUMS` は同じリリースに付いているチェックサムで、ダウンロードの破損は防げますが、署名ではありません。

## 質問なしで使う

```sh
curl -fsSL https://frame.sasaken1102s.net | sh -s -- install eye mic
curl -fsSL https://frame.sasaken1102s.net | sh -s -- install all --yes
curl -fsSL https://frame.sasaken1102s.net | sh -s -- uninstall perf
```

- アプリ名は短く `eye` `keyboard` `mic` `perf` `aux` でも、`all` で全部
- `--yes` 質問にはすべて既定の答えで進む（ターミナルが無いときも同じ）
- `--lang ja|en` 表示の言語（既定はロケール、無ければ Steam の言語設定）
- `--help` 使い方

インストール済みの版のほうが最新リリースより新しいときは、聞いてから戻します（`--yes` のときは戻さずにそのまま）。

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。非公式のツールで、Valve とは関係ありません。

---

## English

Steam Frame apps by sasaken@ — no PC needed: install right inside the Frame, in a few minutes. Install, update or uninstall the five apps (frameeyeosc, frame-jp-keyboard, frame-mic-tuner, frame-perf-overlay, frame-aux-shortcuts) by typing a command into the headset's Konsole and picking from the menu (one app or all five):

```sh
curl -fsSL https://frame.sasaken1102s.net | sh
```

Pick apps by number from the menu (`a` install all, `u` uninstall, `q` quit). Without questions: `... | sh -s -- install eye mic`, `install all --yes`, `uninstall perf`; `--lang ja|en`, `--help`.

It downloads each app's latest GitHub release with its `SHA256SUMS`, installs only when the SHA-256 matches, refuses archives with absolute paths, `..` or links, and runs the release's own `install.sh`. No sudo; it writes only inside your home folder. MIT licensed. Not affiliated with Valve.
