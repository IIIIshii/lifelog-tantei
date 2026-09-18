import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/mbti_type.dart';
import 'package:nikkinext/models/self_analysis.dart';
import 'package:nikkinext/prompts/ai_instructions.dart';

// 自己分析（MBTI）の保存モデルと、探偵AIへの差し込み文面を検証する。
//
// ここを固める理由:
// Firestore のドキュメントは手で書き換えたり項目を後から足したりするので、
// キーの欠損・未知のタイプコードで表示やプロンプトが壊れないことを機械で確かめておきたい。
// また「渡す/渡さない」を取り違えると意図しない個人情報がAIへ流れるため、
// 空のときは確実に何も出さないことをテストで固定する。
void main() {
  group('SelfAnalysis', () {
    test('何も登録していなければ未登録・共有トグルはON', () {
      const defaults = SelfAnalysis();
      expect(defaults.mbti, '');
      expect(defaults.hasProfile, isFalse);
      expect(defaults.shareWithInterview, isTrue);
      expect(defaults.shareWithAnalysis, isTrue);
    });

    test('空のマップから読んでもデフォルトで埋まる（項目追加前のドキュメント対策）', () {
      final loaded = SelfAnalysis.fromMap(const {});
      expect(loaded.mbti, '');
      expect(loaded.shareWithInterview, isTrue);
      expect(loaded.shareWithAnalysis, isTrue);
    });

    test('toMap → fromMap の往復で値が保たれる', () {
      const original = SelfAnalysis(
        mbti: 'ENFP',
        shareWithInterview: false,
        shareWithAnalysis: true,
      );
      final restored = SelfAnalysis.fromMap(original.toMap());
      expect(restored.mbti, 'ENFP');
      expect(restored.shareWithInterview, isFalse);
      expect(restored.shareWithAnalysis, isTrue);
    });

    test('copyWith は指定したフィールドだけ差し替える', () {
      const original = SelfAnalysis(mbti: 'ISTJ');
      final next = original.copyWith(shareWithAnalysis: false);
      expect(next.mbti, 'ISTJ');
      expect(next.shareWithInterview, isTrue);
      expect(next.shareWithAnalysis, isFalse);
    });

    test('未登録・未知のタイプコードはどちらも hasProfile が false', () {
      expect(const SelfAnalysis(mbti: '').hasProfile, isFalse);
      expect(const SelfAnalysis(mbti: 'XXXX').hasProfile, isFalse);
      expect(const SelfAnalysis(mbti: 'intj').hasProfile, isFalse); // 小文字は別物
      expect(const SelfAnalysis(mbti: 'INTJ').hasProfile, isTrue);
    });
  });

  group('SelfAnalysis.promptSummary', () {
    test('未登録なら空文字（AIへ何も渡さない）', () {
      expect(const SelfAnalysis(mbti: '').promptSummary(), '');
    });

    test('未知のタイプコードでも空文字（でたらめな人物像を渡さない）', () {
      expect(const SelfAnalysis(mbti: 'XXXX').promptSummary(), '');
    });

    test('登録済みならタイプコードと通称を含む', () {
      final summary = const SelfAnalysis(mbti: 'INTJ').promptSummary();
      expect(summary, contains('INTJ'));
      expect(summary, contains('建築家'));
      expect(summary, contains(kMbtiTypes['INTJ']!.description));
    });
  });

  group('AiInstructions.selfProfile', () {
    test('本文が空ならブロックごと省略される', () {
      expect(AiInstructions.selfProfile(''), '');
    });

    test('本文と、決めつけを禁じる注意書きを両方含む', () {
      final block = AiInstructions.selfProfile('- MBTI: INTJ（建築家）');
      expect(block, contains('- MBTI: INTJ（建築家）'));
      expect(block, contains('自己申告'));
      expect(block, contains('レッテル貼り'));
      // 記録された事実を優先させる指示が消えていないこと
      expect(block, contains('事実の方を優先'));
    });
  });

  group('kMbtiTypes', () {
    test('16タイプすべてが揃っている', () {
      expect(kMbtiTypes.length, 16);
    });

    test('マップのキーと MbtiType.key が一致する', () {
      for (final entry in kMbtiTypes.entries) {
        expect(entry.value.key, entry.key);
      }
    });

    test('通称と説明が空のタイプはない（一覧カードとAIの文面が欠けないこと）', () {
      for (final type in kMbtiTypes.values) {
        expect(type.label, isNotEmpty, reason: type.key);
        expect(type.description, isNotEmpty, reason: type.key);
      }
    });

    test('未知のキーと null には null を返す（デフォルトへフォールバックしない）', () {
      expect(mbtiTypeFor(null), isNull);
      expect(mbtiTypeFor(''), isNull);
      expect(mbtiTypeFor('XXXX'), isNull);
      expect(mbtiTypeFor('ESFP')?.label, 'エンターテイナー');
    });
  });
}
