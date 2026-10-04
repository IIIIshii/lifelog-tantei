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

`AuthGate` → `MainShell` がルート。`MainShell` が NavigationBar の5タブ
（事務所 / 事件簿 / 相談室 / 分析室 / 設定）を遅延 IndexedStack で束ねる。

- `lib/pages/` — 画面。日記側は DiaryPage / DiaryListPage / DiaryDetailPage / DiaryEditPage、
  目標側は ConsultHubPage（事件一覧）/ ConsultPage（見立ての壁打ち）/
  GoalCheckInPage（毎日の報告）/ GoalLogPage・GoalLogDetailPage（記録の閲覧）
- `lib/core/` — UI から独立した純関数（`goal_progress` / `chart_scale` / `streak` /
  `numeric_answer` / `scroll`）とテーマ。Firestore を使わずテストできる形に保つ
- `lib/services/` — auth / firestore / gemini / notification / speech のシングルトン
- `lib/models/`, `lib/roles/`, `lib/prompts/`, `lib/widgets/`

**日記と目標の分離:** 日記の質問フロー（DiaryPage）に目標の関心事を混ぜない。
目標の日々の報告は GoalCheckInPage が受け、保存先も別コレクション（下記データモデル）。
ホームの FAB は「目標の報告 → 日記の新規捜査」の順に開く。

**Initialization order in `main()`:**
1. `WidgetsFlutterBinding.ensureInitialized()` — must come first (required before any MethodChannel/platform call)
2. `dotenv.load()` — load API keys from .env
3. `NotificationService.instance.initialize()` — timezone + notification plugin setup
4. `Firebase.initializeApp()`
5. `ThemeController.instance.load()` — SharedPreferences からテーマを読む（初回フレームのちらつきを防ぐため await する）

**Data model (Firestore):**

日記と目標は別のコレクションに分かれている。目標にも日記と同じ形の日付エントリと
会話記録を持たせてあり、違いは日記本文（`diary`）を持たない点だけ。
これにより `lib/core/goal_progress.dart` の集計を両方に使える（回答キーは `goal_<actionId>`）。

```
users/{uid}/
├ settings/preferences                  ← UserSettings
├ entries/{YYYY-MM-DD}                  ← 日記
│   diary / diaryMode / answers / numericAnswers / skipped / timestamp
│   └ conversation/{autoId}  role / text / order / timestamp
├ analyses/latest, analyses/today        ← AI所見・今日のコメント
├ self-analysis/profile                  ← SelfAnalysis
└ goals/{goalId}                         ← 目標（追跡を終えても消さない）
    id / title / metric / deadline / actions[] / suggestedQuestions[] / createdAt
    status: 'active' | 'solved' | 'abandoned' | 'closed'
    closedAt: 'YYYY-MM-DD'（追跡中は空文字）
    └ entries/{YYYY-MM-DD}               ← 目標の日々の報告（diary は無い）
        answers / numericAnswers / skipped / timestamp
        └ conversation/{autoId}  role / text / order / timestamp
```

遅延移行（読み取りのついでに直し、失敗しても読み込みは成功させる）:
- 旧 `goals/current` → `goals/{goalId}`
- 旧 `goal-archive/{goalId}` → `goals/{goalId}` に `status` / `closedAt` を付けて引き上げ
  （`outcome` が読めないものは `status: 'closed'`）

**Auth:** Anonymous auth only (`FirebaseAuth.instance.signInAnonymously()`), called on every save.

**AI:** Gemini via `google_generative_ai` package. API key loaded from `.env` as `GEMINI_API_KEY`. Model: `gemini-2.5-flash`.

## MVP Feature Plan (from README)

1. **AIとの対話** — AI asks questions and follows up 1–2 times
2. **証拠提出** — User selects from choices or short-text answers
3. **事件簿生成** — AI generates a 100–300 char diary from the conversation
4. **証拠保存** — Diary saved to Firestore
5. **事件簿の閲覧** — List view of past diary entries

Features 1–2 are partially implemented (single weather question, no multi-turn conversation yet).

## Environment

Requires a `.env` file at the project root (included as a Flutter asset):
```
GEMINI_API_KEY=your_key_here
```
