# ライフログ探偵

> AIの探偵キャラクターの質問に答えるだけで、文字を書かずに日記が完成するスマホアプリ

---

## アプリ概要

設定した時刻に通知を受け取り、アプリを開くと選んだ**探偵キャラクター**が事件（＝今日の出来事）について質問を投げかけてきます。
ユーザーは**選択肢をタップ**するか、**短い文章（音声入力も可）**で答えるだけ。答えにくい質問は**スキップ**もできます。
AIが証言（会話）を分析し、100〜300字の「事件簿（日記）」を自動生成して保存します。
蓄積された記録は**証拠分析室**でグラフ化され、AI探偵の所見とあわせて自分の行動・習慣を振り返ることができます。

世界観は一貫して**探偵事務所**。日記は「事件簿」、過去ログは「事件簿アーカイブ」、分析は「証拠分析室」、設定は「探偵事務所」として表現されます。

---

## 主な機能（実装済み）

| 機能 | 説明 |
|------|------|
| 認証 | Googleログイン / ゲスト（匿名）の2系統。`AuthGate` がログイン状態に応じて画面を出し分ける |
| 探偵キャラクター選択 | 口調・質問文・日記の文体・深掘り回数が異なる4種の探偵から選べる（後述）。ホームの専用ページで切替 |
| AIとの対話 | 出来事を 5W1H（いつ/どこで/誰が/何があった/どう感じた）で順に質問。選択肢は2択ならボタン、3択以上はドロップダウンで提示 |
| AI深堀り質問 | 構造化質問の後、Geminiが会話を読んで追加質問を生成。ロールごとに設定された回数（2〜4回）まで繰り返し、「証言十分」と判断すれば自動で打ち切る |
| AIリアクション | 各回答に探偵が相槌を返す（選択肢→ロール定義の固定文面 / 自由記述→Geminiが生成） |
| 質問のスキップ | 回答したくない質問は「この質問をスキップ」で飛ばせる。スキップした事実だけがFirestoreに残り、日記生成には渡されない |
| 進捗バー | 質問フェーズ中、回答済み/全質問数に応じた進捗バーを表示 |
| 音声入力 | 自由記述の回答はマイクボタンでOS標準の音声認識（日本語）でも入力できる |
| 事件簿生成 | 会話内容をもとにGeminiが選択ロールの文体で日記テキストを自動作成 |
| 手動入力・編集 | 「自分で入力」モードや生成後の「編集する」から、テキストで直接記述・修正できる |
| 追記・作り直し | その日の日記が既にある場合、「追記する / いちから作り直す / 日記を確認する」を選べる |
| 証拠保存 | 生成した日記・回答・数値データ・スキップ情報をFirestoreに保存 |
| 事件簿アーカイブ | 過去の日記をリスト表示（リアルタイム更新）し、タップで全文表示・編集 |
| 証拠分析室 | 探偵の所見（直近14日）・今日の行動コメント・サマリー・感情/場所の円グラフ・睡眠時間の棒グラフ・活動記録テーブル |
| AI所見 | 「探偵に推理させる」で直近14日を読み返した所見を生成・キャッシュ。「今日の行動」では本日分のコメントを生成・キャッシュ |
| 通知 | 設定した時刻に毎日ローカル通知（リマインダー）を送る |
| 設定（探偵事務所） | 記録項目・カスタム質問・テーマ・通知時刻・アカウント・CSVエクスポートを管理 |
| カスタム質問 | ユーザーが自由に質問を追加でき、対話と分析表に反映される |
| テーマ切替 | 3種のテーマを切替（端末ローカルに永続化） |
| CSVエクスポート | 全エントリ（日付・日記・回答）をBOM付きCSVに書き出して共有 |
| デモ | ゲストログイン＋サンプル事件簿14日分の一括投入（ログイン画面 / デバッグ設定） |

---

## 探偵キャラクター（ロール）

選んだロールにより、質問文・相槌・生成される日記の文体・AI深堀りの回数が変わります。
定義は `lib/roles/` に1ファイル1キャラで分離され、`lib/roles/roles.dart` のレジストリに登録されています。

| キー | 名称 | 特徴 | 深掘り回数 |
|------|------|------|:--:|
| `hardboiled` | ハードボイルド探偵 | 寡黙でクール。硬質・簡潔な三人称の捜査ログ調（デフォルト） | 2 |
| `novice` | 新卒探偵 | 入社1日目。ぎこちない丁寧語で一生懸命、前向きに寄り添う | 3 |
| `alien` | エイリアン | 地球を観察中の宇宙人。カタカナ混じりの観測記録調 | 2 |
| `psychologist` | 心理学者 | 穏やかで内省的。事実より「何を感じたか」を掘り下げる | 4 |

各ロールは「人格指示（`interviewerInstruction`）」「質問・ナレーション文面」「ボタン選択への固定リアクション」「日記/所見の文体」「深掘り回数（`followUpCount`）」をまとめて保持します。
新しいロールは `lib/roles/<name>.dart` を追加し、`roles.dart` の `kRoles` に登録するだけで増やせます（ロール選択画面の一覧もレジストリを参照するため自動反映）。

---

## テーマ

設定画面で切り替えられ、選択は `SharedPreferences` に保存されます（起動時のチラつきを避けるため同期的に読み込み）。

| テーマ | 説明 |
|--------|------|
| 探偵（ライト） | 羊皮紙のような温かみのあるセピア調 |
| 探偵（ダーク / ノワール） | 深夜の探偵事務所。インク色の闇とゴールド |
| 書斎 | ロンドンの古書斎。緑と真鍮の落ち着いた雰囲気 |

色は `ThemeExtension`（`AppColors`）でドメイン固有トークン（`gold` / `cardBorder` / `bubbleUser` など）として配信し、`context.colors.gold` の形で参照します。

---

## 質問フロー

日記作成（`DiaryPage`）は内部状態 `_Phase` に沿って次の順序で進みます。

```
（その日の日記が既にある場合）
   ┗ 追記する / いちから作り直す / 日記を確認する を選択
       ├ 追記する     → 既存日記を初期値にテキスト編集画面（DiaryEditPage）へ
       ├ 日記を確認する → 既存日記を表示（閉じる / 編集する）
       └ いちから作り直す → 既存日記を破棄し、下記の通常フローを開始

1. カスタム質問（設定でONの項目：睡眠 / 食事 / 運動 / 勉強 ＋ ユーザー定義の質問）
     → 回答後「この内容も報告書に含めるか？」（はい / いいえ）
2. 思い出しアシスト（設定ONのみ：午前 → 午後 → 夜）
     → 回答後「この内容も報告書に含めるか？」（はい / いいえ）
3. 作成モード選択（質問に沿って作成 / 自分で入力）
4. 出来事の構造化質問（質問に沿って作成を選んだ場合）
     いつ？ → どこで？ → 誰が？ → 何があった？ → どう感じた？
5. AIによる深堀り質問（Geminiが会話を読み、ロールの回数まで / 十分なら打ち切り）
6. 追記事項の確認（はい→自由記述 / いいえ→生成へ）
7. 事件簿生成 → 確認（これを記録 / 編集する / 生成しなおす / はじめから質問をやりなおす）
8. 完了（事件簿はアーカイブに保存済み。ホームへ / 事件簿アーカイブへ）
```

- 回答対象の質問では「この質問をスキップ」が表示され、回答せず次へ進めます。
- 「自分で入力」を選ぶと、AIとの対話を経ずにテキスト編集画面（`DiaryEditPage`）へ遷移します。

---

## ホーム画面構成

| カード | 内容 |
|--------|------|
| No.01 新規事件を開く | 今日の日記を書く（`DiaryPage`） |
| No.02 事件簿アーカイブ | 過去の日記を見る（`DiaryListPage`） |
| No.03 証拠分析室 | 習慣や行動をグラフ・AI所見で確認（`AnalyticsPage`） |
| No.04 探偵を指名する | 探偵キャラクターを選ぶ（`RoleSelectPage`） |
| No.05 探偵事務所 | 設定する（`SettingsPage`） |

---

## 証拠分析室（AnalyticsPage）

直近14日分のエントリを集計し、次のセクションを縦に並べて表示します。

| セクション | 内容 |
|--------|------|
| 探偵の所見（直近14日間） | 「探偵に推理させる」で直近14日を読み返したAI所見を生成。`analyses/latest` にキャッシュし「再推理」で再生成 |
| 今日の行動（本日分） | 今日の記録に対するAIコメントを生成。`analyses/today` にキャッシュ（日付が変わると非表示） |
| サマリー（直近14日間） | 平均睡眠 / 運動実施率 / 勉強実施率 / 連続記録日数 |
| 出来事の傾向 | 感情（`event_how`）・場所（`event_where`）の分布を円グラフで表示 |
| 睡眠時間（直近14日間） | `numericAnswers['sleep']` を棒グラフで表示 |
| 活動記録（直近14日間） | 食事・運動・勉強＋カスタム質問の回答を日付別テーブルで表示 |

---

## 設定項目（探偵事務所）

設定はトグル操作のたびに即時Firestoreへ保存されます（探偵キャラクターの選択はホームの専用ページに分離）。

- **アカウント** — ログイン情報の表示・ログアウト（ゲストはデータ喪失を警告）
- **捜査項目の選択**
  - その日の印象的なイベント（必須・常時ON）
  - 思い出しアシスト（午前・午後・夜を追加質問）
  - 睡眠時間 / 食べたもの / 運動習慣 / 勉強内容
- **独自質問リスト** — カスタム質問の追加・削除
- **テーマ** — 3種から選択（カラープレビュー付き）
- **デバッグ**（デバッグビルドのみ）— モックデータ投入
- **通知設定** — 毎日リマインダーのON/OFFと時刻（デフォルト21:00）
- **データ管理** — CSVエクスポート

---

## 認証

`AuthService`（シングルトン）と `AuthGate` に認証フローを集約しています。

- **Googleログイン** — `google_sign_in` 7.x の `authenticate()` でIDトークンを取得し、`GoogleAuthProvider` 経由で Firebase Auth に通す。`.env` の `GOOGLE_WEB_CLIENT_ID`（Firebase の Web クライアントID）が必須。
- **ゲスト（匿名）** — `signInAnonymously()`。端末固有でありデータの引き継ぎ不可。
- `AuthGate` が `authStateChanges()` を購読し、未ログインなら `LoginPage`、ログイン済みなら `HomePage` を表示。各ページは個別にサインインを呼ばない。

---

## 技術スタック

| 種別 | 内容 |
|------|------|
| フレームワーク | Flutter (Dart, SDK `^3.11.1`) |
| 認証 | Firebase Auth（Google / 匿名）+ google_sign_in 7.x |
| DB | Cloud Firestore |
| AI | Google Gemini 2.5 Flash（`google_generative_ai`、モデル `gemini-2.5-flash`） |
| グラフ | fl_chart |
| 通知 | flutter_local_notifications + timezone / flutter_timezone |
| 音声入力 | speech_to_text |
| 設定永続化 | shared_preferences（テーマ） |
| フォント | google_fonts（Playfair Display 等） |
| 共有/出力 | share_plus + path_provider（CSVエクスポート） |
| 環境変数 | flutter_dotenv |
| その他 | intl, table_calendar（依存に追加済み・カレンダー表示は今後） |

---

## プロジェクト構成

```
lib/
├── main.dart                       # エントリーポイント・初期化
├── firebase_options.dart           # Firebase設定
├── core/
│   └── theme/
│       ├── app_colors.dart             # 色トークン（ThemeExtension）+ context.colors 拡張
│       ├── app_theme.dart              # 3テーマ定義とThemeDataビルダー
│       ├── detective_text_styles.dart  # フォント定義（色は使用側で注入）
│       └── theme_controller.dart       # テーマ選択状態の管理とSharedPreferences永続化
├── models/
│   └── user_settings.dart          # 設定データモデル（ロール・通知・記録項目など）
├── roles/
│   ├── role.dart                   # ロールのモデル定義
│   ├── roles.dart                  # ロールのレジストリ（kRoles / roleFor）
│   ├── hardboiled.dart             # ハードボイルド探偵
│   ├── novice.dart                 # 新卒探偵
│   ├── alien.dart                  # エイリアン
│   └── psychologist.dart           # 心理学者
├── pages/
│   ├── auth_gate.dart              # 認証状態によるLogin/Homeの出し分け
│   ├── login_page.dart             # Googleログイン / ゲスト / デモ
│   ├── home_page.dart              # ホーム画面（事件ファイル風カード）
│   ├── role_select_page.dart       # 探偵キャラクターの選択
│   ├── diary_page.dart             # 日記作成（AIとの対話）
│   ├── diary_edit_page.dart        # 日記の手動入力・編集
│   ├── diary_list_page.dart        # 事件簿アーカイブ（一覧）
│   ├── diary_detail_page.dart      # 事件報告書（詳細）
│   ├── analytics_page.dart         # 証拠分析室（グラフ・AI所見）
│   └── settings_page.dart          # 探偵事務所（設定）
├── services/
│   ├── auth_service.dart           # Google / 匿名サインインの一元管理
│   ├── firestore_service.dart      # Firestore読み書き・モックデータ投入
│   ├── gemini_service.dart         # Gemini API（対話/日記/分析/リアクション）
│   ├── notification_service.dart   # ローカル通知のスケジューリング
│   └── speech_service.dart         # OS音声認識のラッパー
├── widgets/
│   ├── message_bubble.dart         # チャットバブル（探偵 / 証言）UI
│   ├── diary_card.dart             # 生成日記カード（事件報告書）UI
│   └── input_area.dart             # テキスト＋音声入力エリア
└── prompts/
    ├── ai_instructions.dart        # ロール非依存のシステム指示（生成/分析/深堀り/相槌）
    └── diary_prompts.dart          # プロンプトのテンプレート組み立て
```

---

## データモデル（Firestore）

```
users/{uid}/
├── settings/preferences            # UserSettings（記録項目・ロール・通知設定など）
├── entries/{YYYY-MM-DD}
│   ├── diary: string               # 生成（または手動入力）された日記本文
│   ├── answers: map<string,string> # 質問キー → 回答（event_*, sleep, food, custom_n ...）
│   ├── numericAnswers: map<string,double> # 数値化した回答（例: sleep）
│   ├── skipped: string[]           # 「質問したが未回答（スキップ）」のキー一覧
│   ├── timestamp: serverTimestamp
│   └── conversation/{autoId}       # 会話ログ（順序復元用の order 付き）
│       ├── role: 'ai' | 'user'
│       ├── text: string
│       ├── order: int
│       └── timestamp: serverTimestamp
└── analyses/
    ├── latest                      # 直近14日のAI所見キャッシュ
    │   ├── text: string
    │   ├── periodDays: 14
    │   └── generatedAt: serverTimestamp
    └── today                       # 今日の行動コメントキャッシュ
        ├── text: string
        └── generatedAt: serverTimestamp
```

---

## セットアップ

### 必要なもの

- Flutter SDK（`pubspec.yaml` の `environment.sdk` を参照：`^3.11.1`）
- Firebase プロジェクト（Authentication と Cloud Firestore を有効化）
  - Authentication で **Google** と **匿名** のサインインを有効化
- Gemini API キー
- （Googleログインを使う場合）Firebase の **Web クライアントID**

### 手順

**1. リポジトリをクローン**

```bash
git clone <repo-url>
cd nikkinext
```

**2. `.env` ファイルを作成**

プロジェクトルートに `.env` を作成します（`pubspec.yaml` の assets に登録済み）。`.env.example` をコピーして埋めるのが簡単です。

```
# Gemini API Key（https://aistudio.google.com/ で取得）
GEMINI_API_KEY=your_api_key_here

# Firebase の Web クライアントID（Googleログインに必須）
# google-services.json の client_type:3 の client_id と同じ値
GOOGLE_WEB_CLIENT_ID=your_web_client_id_here.apps.googleusercontent.com
```

> `GOOGLE_WEB_CLIENT_ID` が未設定だと Googleログインはエラーになります（ゲスト利用は可能）。

**3. Firebase の設定**

`lib/firebase_options.dart` と、`google-services.json`（Android）・`GoogleService-Info.plist`（iOS）を配置します。
Androidで Googleログインを使う場合は、Firebase に **SHA-1 指紋** の登録も必要です。

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

> `test/widget_test.dart` はテンプレートのカウンターテストのままで、Firebase未初期化のため現状は失敗します（既知の課題）。

### デバッグ方法

**VS Code**
1. 右下のバーからエミュレータデバイスを選択
2. `F5` キーを押す（または Run → Start Debugging）

**Android Studio**
1. デバイスセレクタでエミュレータを起動
2. ▶ ボタンを押して実行

---

## アーキテクチャ補足

### `main()` の初期化順序

```dart
WidgetsFlutterBinding.ensureInitialized(); // 1. プラットフォーム呼び出し前に必須
await dotenv.load(fileName: ".env");        // 2. APIキー読み込み
await NotificationService.instance.initialize(); // 3. タイムゾーン+通知プラグイン
await Firebase.initializeApp();             // 4. Firebase
await ThemeController.instance.load();       // 5. 保存テーマを同期的に反映
```

### Gemini の使い方（`GeminiService`）

用途ごとに `GenerativeModel` を分け、それぞれに専用のシステム指示をセットします（モデルはいずれも `gemini-2.5-flash`）。

- **対話（深堀り質問）** — 選択ロールの人格指示。`responseSchema` で `{sufficient, question}` のJSONを強制し、終了判定を堅牢化
- **リアクション（相槌）** — 同じ人格でプレーンテキストを返す
- **日記生成** — `AiInstructions.diaryWriter()` ＋ ロールの `diaryStyle`（100〜300字・ネガティブ禁止などの不変ルールは指示側に集約）
- **所見/今日のコメント生成** — `AiInstructions.analyst()` ＋ ロールの `analystStyle`

### テーマ／ロールの拡張ポイント

- **テーマ追加** — `app_theme.dart` の `AppThemeName` と `colorsOf()` に追加
- **ロール追加** — `lib/roles/<name>.dart` を作り `roles.dart` の `kRoles` に登録（ロール選択画面の一覧は自動反映）

---

## 今後の予定

- カレンダービュー（依存 `table_calendar` は導入済み・未使用）
- AIによる深掘り回数のユーザーカスタマイズ
- さらなる分析指標の拡充

---

## 注意事項

- `.env` はGitに含まれません。各自で作成してください（`.env.example` を参照）。
- `pubspec.yaml` を変更したら必ず `flutter pub get` を実行してください。
- ゲスト（匿名）ログインのデータは端末固有で、別端末からは参照できません。
- 通知・音声入力は端末の権限許可が前提です（初回利用時に権限ダイアログが出ます）。
