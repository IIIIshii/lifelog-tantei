# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language

必ず日本語で応答すること。

## コード変更の前に確認すること

コードの変更を求められた場合、いきなりコードを書き換えてはいけない。必ず以下の順序で対応すること：

1. **意図の説明** — なぜその変更が必要か、どういう目的で行うかを説明する
2. **変更箇所の説明** — どのファイルのどの部分をどのように変えようとしているかを具体的に説明する
3. **確認** — ユーザーに「この方針で変更してよいか」を確認する
4. **実装** — ユーザーの承認を得てからコードを書き換える

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app (requires a connected device or emulator)
flutter run

# Analyze (lint)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart
```

## Architecture

`AuthGate` → `MainShell` がルート。`MainShell` が NavigationBar の4タブ
（事務所 / 事件簿 / 相談室 / 設定）を遅延 IndexedStack で束ねる。
事件簿タブ（CaseFilesPage）は上部タブで「アーカイブ」と「分析」を切り替える。

- `lib/pages/` — 画面。
  - 日々の記録: RecordSheetPage（その日の表）/ FieldSettingsPage（記録の型の編集）
  - 日記: DiaryPage（聴取）/ DiaryDetailPage / DiaryEditPage /
    DiaryArchiveView・DiaryMonthPage（アーカイブ）/ AnalyticsView（分析）
  - 目標: ConsultHubPage（事件一覧）/ ConsultPage（見立ての壁打ち）/ GoalLogPage（記録の閲覧）
- `lib/core/` — UI から独立した純関数（`daily_record` / `goal_progress` / `chart_scale` /
  `streak` / `numeric_answer` / `question_schedule` / `scroll`）とテーマ。
  Firestore を使わずテストできる形に保つ
- `lib/services/` — auth / firestore / gemini / health / notification / speech のシングルトン
- `lib/models/`, `lib/roles/`, `lib/prompts/`, `lib/widgets/`

**日々の記録と聴取の分離:** 事実（睡眠時間・気分・何をしたか・カスタム項目・目標の行動項目）は
日々の記録の表（RecordSheetPage）で受け、聴取（DiaryPage）では聞かない。
聴取は「出来事を選ぶ → 深掘り」を何度でも繰り返し、最後に1日1件の日記本文にまとめる。
記録があれば読み込んで、話題の候補出しと日記の材料に使う。
ホームの FAB は「日々の記録（未記入があれば）→ 聴取」の順に開く。
表は「探偵に話す」（RecordTellSheet）でまとめて話して埋めることもできる。AI が項目へ振り分けた
結果は下書きとして確認してから入れ、既に値がある項目は勝手に上書きしない。
一問一答の対話入力は未実装（Role の q_* はそのための文面）。

**端末（Health Connect）からの取得:** スマートウォッチのアプリが Health Connect に書いた
歩数・睡眠・心拍などを、表を開いたとき・聴取を始めるときに読んで表に入れる（Android のみ・前面のみ）。
項目は「記録する項目」→「端末と連携する」（HealthConnectPage）で、直近30日に記録があった種類だけを足す。
取る種類と1日分のまとめ方は `core/health_daily.dart` の `kHealthMetrics`。入れてよい欄の判断
（`deviceFillTargets`）は、空欄・端末が前に入れた欄・AI が会話から入れた欄だけで、利用者の値は上書きしない。
端末の項目は記入状況（「記入 3/6」）に数えず、端末の値だけの日は「記録した日」にも数えない。

**Initialization order in `main()`:**
1. `WidgetsFlutterBinding.ensureInitialized()` — must come first (required before any MethodChannel/platform call)
2. `dotenv.load()` — load API keys from .env
3. `NotificationService.instance.initialize()` — timezone + notification plugin setup
4. `Firebase.initializeApp()`
5. `ThemeController.instance.load()` — SharedPreferences からテーマを読む（初回フレームのちらつきを防ぐため await する）

**Data model (Firestore):**

「記録の型」（RecordField）と「日々の記録の実データ」を分けて持つ。
その日の事実はすべて `records/{date}` の `values` に「項目 id → 値」で入り、
値は Firestore の型のまま（数値は num、はい／いいえは bool、選択肢・テキストは String）。
項目 id はプリセットが `sleep` / `mood` など、カスタムが `custom_<uuid>`、
目標の行動項目が `goal_<actionId>`、端末の項目が `health_<種類>`（`health_steps` など固定の名前）。

記録の型の置き場所は2つ: 生活の記録・カスタム項目は `settings/fields`、
目標の行動項目は `goals/{goalId}.actions`（目標を閉じれば表から外れる）。
`RecordField.fromGoalAction` で同じ形に読み替え、`fieldsForDay` がその日の表を組む。
項目は消さずに `active: false` にする（消すと過去の値が何の記録か読めなくなる）。

```
users/{uid}/
├ settings/preferences                  ← UserSettings（担当探偵・通知）
├ settings/fields                       ← 記録の型 items[]（RecordField）
│   id / label / kind(numeric|yesNo|choice|text) / unit / target / choices /
│   weekdays / source(preset|self|consult|health) / useInDiary / shareWithAi / active
│   （shareWithAi: false の項目は、日記・話題の候補・所見・期間の集計のどれにも値を渡さない）
├ records/{YYYY-MM-DD}                  ← 日々の記録
│   values{項目id: 値} / updatedAt
│   autoFilled[]（AI が会話から入れた項目）/ deviceFilled[]（端末から入れた項目）/
│   autoRejected[]（利用者が「消す」で取り消した項目。その日はもう自動で入れない）
├ diaries/{YYYY-MM-DD}                  ← 日記（1日1件）
│   text / topics[]（聴取で話した出来事）/ role / mode('interview'|'manual') / updatedAt
│   └ interview/{autoId}  role / text / order / topic / timestamp
├ analyses/{autoId}                      ← AI所見・今日のコメント（上書きせず積む）
│   kind('period'|'daily') / text / date / periodDays / generatedAt
├ self-analysis/profile                  ← SelfAnalysis
└ goals/{goalId}                         ← 目標（追跡を終えても消さない）
    id / title / metric / deadline / actions[] / suggestedQuestions[] / createdAt
    steps[]: id / title / deadline / doneAt（途中の段階。順番どおり。今の段階＝未達成の先頭）
    status: 'active' | 'solved' | 'abandoned' | 'closed'
    closedAt: 'YYYY-MM-DD'（追跡中は空文字）
```

遅延移行（読み取りのついでに直し、失敗しても読み込みは成功させる）:
- 旧 `goals/current` → `goals/{goalId}`
- 旧 `goal-archive/{goalId}` → `goals/{goalId}` に `status` / `closedAt` を付けて引き上げ
  （`outcome` が読めないものは `status: 'closed'`）

**Auth:** Anonymous auth only (`FirebaseAuth.instance.signInAnonymously()`), called on every save.

**AI:** Gemini via `google_generative_ai` package. API key loaded from `.env` as `GEMINI_API_KEY`. Model: `gemini-2.5-flash`.

## Environment

Requires a `.env` file at the project root (included as a Flutter asset):
```
GEMINI_API_KEY=your_key_here
```
