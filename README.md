# KoeType

日本語に特化した macOS 用の音声入力アプリ。メニューバーに常駐し、キーを押しながら話すと、
フォーカス中のアプリに整形済みの文章を入力する。音声認識は Mac の中で行い、利用時間の制限はない。

## 必要なもの

- macOS 14 以降、Apple Silicon の Mac
- Xcode（コマンドラインツールを含む）
- キーチェーンに登録された Apple Development 証明書
- OpenAI API キー（AI 整形を使う場合のみ。なくても使える）

## 導入

```bash
git clone https://github.com/caruxx/koetype.git
cd koetype
scripts/build-app.sh release
open ~/Applications/KoeType.app
```

1. 初回起動時に出る画面で、マイクとアクセシビリティを許可する。
2. 音声認識モデル（約 630MB）のダウンロードと準備を待つ。初回だけ数分かかる。

この時点で、Mac の中だけで完結する音声入力として使える（費用はかからない）。

## 整形の方法

設定の「AI で高精度に整える」で切り替える。

| 設定 | 内容 | 費用 |
|---|---|---|
| オフ（既定） | 句読点の付与と、「えーと」「あのー」などの除去。すべて Mac 内で処理 | 無料 |
| オン: この Mac の中で | 上に加えて、言い直しの整理、文脈からの誤認識の修正、アプリに合わせた文体。macOS 内蔵の AI を使い、文章は Mac の外に出ない。1 回 約 1 秒 | 無料 |
| オン: OpenAI API | 同じ処理を OpenAI の Luna（`gpt-6-luna`）で行う。精度を最も重視する場合 | 利用した分だけ課金 |
| オン: Codex CLI | ChatGPT にログイン済みの Codex CLI を通す。1 回 約 5 秒 | ChatGPT の利用枠 |

- AI に送るのは既定で 20 文字以上の発話だけ。短い発話はローカル処理だけで入力される。
- AI の結果が、話した内容を削りすぎている・別の内容になっている場合は採用せず、ローカル処理の結果を入力する。
- 内蔵の AI は速いが、文末の言い回しを変えるなど小さな書き換えをすることがある。忠実さを重視するなら OpenAI API を選ぶ。

### アプリ別の文体

AI 整形がオンのとき、文章を入力する先のアプリで整え方が変わる。設定の「アプリ別の文体…」で変更できる。

| 文体 | 既定のアプリ | 整え方 |
|---|---|---|
| チャット | Slack、LINE、メッセージ、Discord、Teams | 話し言葉のまま。文末の「。」は付けない |
| メール | メール、Outlook | です・ます調の丁寧な文 |
| 整形しない | ターミナル、iTerm、VS Code、Xcode | AI に送らず、ローカル処理だけ |
| 標準 | 上記以外 | 話した調子のまま清書 |

## 記録と文字起こし

メニューの「記録を開始（Mac の音とマイク）」で、会議アプリや動画の音と自分の声を録り、停止すると時刻つきの文字起こしを
`書類/KoeType/` に保存して表示する（最長 2 時間、音声そのものは保存しない）。初回は macOS の「画面収録とシステムオーディオ録音」の許可が必要。
「ファイルを文字起こし…」で、音声や動画のファイルも文字起こしできる。

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

既定の「ローカルのみ」では、外部への送信は行わない（音声認識モデルの初回ダウンロードを除く）。
「AI で高精度に整える」を選んだ場合に限り、設定した文字数以上の発話について、文字起こし後のテキストと辞書の内容を OpenAI の API に送る。音声は送らない。

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
