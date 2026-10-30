package com.example.nikkinext

import io.flutter.embedding.android.FlutterFragmentActivity

// Health Connect の権限画面は registerForActivityResult で開くため、
// それを持つ FlutterFragmentActivity を親にする（health パッケージの要件）。
class MainActivity : FlutterFragmentActivity()
