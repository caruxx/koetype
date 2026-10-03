# KoeType

日本語に特化した macOS 用の音声入力アプリ。メニューバーに常駐し、キーを押しながら話すと、
フォーカス中のアプリに整形済みの文章を入力する。音声認識は Mac の中で行い、利用時間の制限はない。

## 必要なもの

- macOS 14 以降、Apple Silicon の Mac
- Xcode（コマンドラインツールを含む）
- キーチェーンに登録された Apple Development 証明書
- OpenAI API キー（整形を使う場合）

## 導入

```bash
git clone https://github.com/caruxx/koetype.git
cd koetype
scripts/build-app.sh release
open ~/Applications/KoeType.app
```

1. 初回起動時に出る画面で、マイクとアクセシビリティを許可する。
2. 音声認識モデル（約 630MB）のダウンロードと準備を待つ。初回だけ数分かかる。
3. メニューバーのマイクのアイコンから「設定を開く」を選び、API キーを保存して「接続テスト」を押す。

## 使い方

| 操作 | 動作 |
|---|---|
| 右 Command を押しながら話し、離す | 話した内容が入力される |
| 右 Command を素早く 2 回押す | ハンズフリー録音を開始。もう一度押すと終了（最長 10 分） |
| 録音中に Esc | 取り消し |

- 入力欄が見つからないときは、画面下部にコピーボックスが出る。30 秒で自動的に閉じるが、内容は履歴に残る。
- 「履歴を開く」で過去の入力を検索・再コピーできる（直近 1,000 件）。
- 「辞書を開く」で固有名詞や専門用語を登録すると、認識と整形の両方で使われる。
- ホットキーは設定で 右 Command / 右 Option / 右 Control / Fn から選べる。

## 別の Mac への導入

その Mac で上の「導入」を行う。証明書の名前が違う場合は次のように指定する。

```bash
KOETYPE_SIGN_IDENTITY="Apple Development: name@example.com (XXXXXXXXXX)" scripts/build-app.sh release
```

モデルは Mac ごとに初回起動時にダウンロードされる。辞書と履歴は Mac ごとに別々に保存される。

## データの保存場所

| 内容 | 場所 |
|---|---|
| 履歴 | `~/Library/Application Support/KoeType/history.json` |
| 辞書 | `~/Library/Application Support/KoeType/dictionary.json` |
| 音声認識モデル | `~/Library/Application Support/KoeType/Models` |
| API キー | キーチェーン（サービス名 `jp.caruvistar.koetype`） |

音声そのものは保存しない。

## 外部に送られるもの

整形を有効にしている場合、文字起こし後のテキストと辞書の内容を OpenAI の API に送る。
音声は送らない。整形を無効にすると、外部への送信は行わない（モデルの初回ダウンロードを除く）。

## 困ったとき

- **ホットキーが効かない**: システム設定の「プライバシーとセキュリティ」>「アクセシビリティ」で KoeType を許可する。
  パスワード入力欄などでセキュア入力が有効な間は、macOS の仕様で効かない。
- **整形されない**: 設定の「接続テスト」に出るエラー文を確認する。整形に失敗しても、整形なしの文章は入力される。
- **Typeless や Wispr Flow と同時に使う**: ホットキーが重ならないように設定する。
- **アイコンに斜線が入っている**: 権限が足りないか、モデルを準備中。メニューの 1 行目に理由が出る。

## 開発

```bash
scripts/test.sh                 # 自動テスト
scripts/build.sh                # ビルド
scripts/build-app.sh release    # ~/Applications/KoeType.app を作って署名
```

ビルド生成物は `~/Library/Caches/KoeType/build` に出る（リポジトリの中には作らない）。
検証用に、音声ファイルを処理して結果と所要時間を表示できる。

```bash
~/Library/Caches/KoeType/build/out/Products/Release/KoeType --transcribe-file sample.wav
```

設計は `docs/superpowers/specs/`、実装計画は `docs/superpowers/plans/`、検証記録は `docs/verification.md` にある。
