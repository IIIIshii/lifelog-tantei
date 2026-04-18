# ライフログ探偵

> AIの質問に答えるだけで、文字を書かずに日記が完成するスマホアプリ

---

## アプリ概要

指定した時刻に通知を受け取り、アプリを開くと探偵キャラクターのAIが質問を投げかけてきます。
ユーザーは選択肢をタップするか、短い文章で答えるだけ。
AIがその内容を分析し、100〜300字の日記を自動生成します。
蓄積されたデータはグラフで可視化され、自分の行動・習慣を振り返ることができます。

---

## 機能一覧

### 実装済み

| 機能 | 説明 |
|------|------|
| AIとの対話 | 構造化された質問（いつ/どこで/誰が/誰と/何をした/どうだった）をAIが順番に行う |
| AI深堀り質問 | 構造化質問の後、Geminiが会話を読んで追加質問を1回生成する |
| 事件簿生成 | 会話内容をもとにGeminiが日記テキストを自動作成する |
| 証拠保存 | 生成した日記をFirebase Firestoreに保存する |
| 事件簿アーカイブ | 過去の日記をリスト形式で一覧表示し、タップで詳細を読める |
| 設定（セットアップ） | 記録したい項目をスイッチで選択できる |
| カスタム質問 | ユーザーが自由に質問を追加できる |

### 未実装（予定）

| 機能 | 説明 |
|------|------|
| 選択肢式UI | テキスト入力に加え、ボタンタップで回答できるUI |
| カレンダービュー | 日記一覧をカレンダー形式で表示する |
| 証拠分析室 | 蓄積データを習慣・行動のグラフで可視化する |
| 通知 | 指定した時刻にプッシュ通知を送る |

---

## セットアップ項目（設定画面）

記録したい内容は設定画面から選択できます。選んだ項目に応じて質問が追加されます。

- **その日の印象的なイベント**（デフォルトON・変更不可）
  - 思い出しアシスト：午前・午後・夜に何をしたか追加で質問
- 睡眠時間
- 食べたもの
- 運動習慣
- 勉強内容
- カスタム質問（自由記述で追加）

---

## 質問フロー

日記作成時は以下の順序で質問が進みます。

```
1. 固定質問（設定に応じて：思い出しアシスト / 睡眠 / 食事 / 運動 / 勉強）
2. 出来事の構造化質問
     いつ？ → どこで？ → 誰が？ → 誰と？ → 何をした？ → どうだった？
3. AIによる深堀り質問（Geminiが会話を読んで1問生成）
4. 追記事項の確認
5. カスタム質問（設定で追加した質問）
6. 確認（「この内容で日記を生成しますか？」）
7. 日記生成・保存
```

---

## ホーム画面構成

| カード | 内容 |
|--------|------|
| No.01 新規事件を開く | 今日の日記を書く |
| No.02 事件簿アーカイブ | 過去の日記を見る |
| No.03 証拠分析室 | 習慣や行動をグラフで確認する（未実装） |
| No.04 探偵事務所 | 設定する |

---

## 技術スタック

| 種別 | 内容 |
|------|------|
| フレームワーク | Flutter (Dart) |
| 認証 | Firebase Anonymous Auth |
| DB | Firebase Firestore |
| AI | Google Gemini 2.5 Flash (`google_generative_ai`) |
| 環境変数 | flutter_dotenv |
| グラフ（予定） | fl_chart |
| カレンダー（予定） | table_calendar |
| 通知（予定） | flutter_local_notifications |

---

## プロジェクト構成

```
lib/
├── main.dart                   # エントリーポイント・初期化
├── firebase_options.dart       # Firebase設定
├── core/
│   └── theme/
│       ├── app_colors.dart           # テーマごとの色トークン（ThemeExtension）
│       ├── app_theme.dart            # テーマ定義（ライト/ダーク/書斎）とThemeDataビルダー
│       ├── detective_text_styles.dart # フォント定義（色はテーマ側から注入）
│       └── theme_controller.dart     # テーマ選択状態の管理とSharedPreferences永続化
├── models/
│   └── user_settings.dart      # 設定データモデル
├── pages/
│   ├── home_page.dart          # ホーム画面
│   ├── diary_page.dart         # 日記作成（AIとの対話）
│   ├── diary_list_page.dart    # 日記一覧
│   ├── diary_detail_page.dart  # 日記詳細
│   └── settings_page.dart      # 設定画面
├── services/
│   ├── auth_service.dart       # 認証
│   ├── firestore_service.dart  # Firestore操作
│   └── gemini_service.dart     # Gemini API
├── widgets/
│   ├── message_bubble.dart     # チャットバブルUI
│   ├── diary_card.dart         # 生成日記カードUI
│   └── input_area.dart         # テキスト入力エリア
└── prompts/
    └── diary_prompts.dart      # Geminiへのプロンプト定義
```

---

## セットアップ

### 必要なもの

- Flutter SDK（`pubspec.yaml` の `environment.sdk` を参照）
- Firebase プロジェクト（Auth・Firestore を有効化）
- Gemini API キー

### 手順

**1. リポジトリをクローン**

```bash
git clone <repo-url>
cd nikkinext
```

**2. `.env` ファイルを作成**

プロジェクトルートに `.env` を作成し、APIキーを設定します。

```
GEMINI_API_KEY=your_gemini_api_key_here
```

**3. Firebase の設定**

`lib/firebase_options.dart` と `google-services.json`（Android）・`GoogleService-Info.plist`（iOS）を配置します。

**4. 依存パッケージをインストール**

```bash
flutter pub get
```

**5. アプリを起動**

```bash
flutter run
```

---

## 開発コマンド

```bash
# 依存パッケージのインストール
flutter pub get

# アプリ起動（デバイス/エミュレータが必要）
flutter run

# 静的解析
flutter analyze

# テスト実行
flutter test

# 特定のテストファイルのみ実行
flutter test test/widget_test.dart
```

### デバッグ方法

**VS Code**
1. 右下のバーからエミュレータデバイスを選択
2. `F5` キーを押す（または Run → Start Debugging）

**Android Studio**
1. デバイスセレクタでエミュレータを起動
2. ▶ ボタンを押して実行

---

## Issue管理

- 作業前に必ずIssueを立ててからパッチする
- Issueに取り組む場合は Assignee に自分を追加する

---

## 注意事項

- `.env` はGitに含まれません。各自で作成してください
- `pubspec.yaml` を変更したら必ず `flutter pub get` を実行してください
- 初期化順序は `dotenv.load()` → `WidgetsFlutterBinding.ensureInitialized()` → `Firebase.initializeApp()` の順を守ること
