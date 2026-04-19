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

Currently a single-file Flutter app (`lib/main.dart`) with all logic in one place. The app is intended to grow into a multi-screen diary app.

**Initialization order in `main()`:**
1. `WidgetsFlutterBinding.ensureInitialized()` — must come first (required before any MethodChannel/platform call)
2. `dotenv.load()` — load API keys from .env
3. `NotificationService.instance.initialize()` — timezone + notification plugin setup
4. `Firebase.initializeApp()`

**Data model (Firestore):**
```
users/{uid}/entries/{YYYY-MM-DD}
  - weather: string
  - timestamp: serverTimestamp
```

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
