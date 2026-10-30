import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/auto_fill.dart';
import 'package:nikkinext/core/daily_record.dart';
import 'package:nikkinext/core/health_daily.dart';
import 'package:nikkinext/core/period_stats.dart';
import 'package:nikkinext/models/record_field.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';

// 端末（Health Connect）の記録を、日々の記録の1日分にまとめる判断を検証する。
//
// 睡眠をどの日の分にするか、2つのアプリが同じ種類を書いたときに二重に数えないか、
// 利用者が書いた値を上書きしないか、AI に渡さない項目が漏れないか。
// どれも間違えても画面は正常に見えるので、ここで固める。
void main() {
  // 10月30日（木）。睡眠はその前の晩から始まる
  final day = DateTime(2026, 10, 30);
  DateTime at(int dayOfMonth, int hour, [int minute = 0]) =>
      DateTime(2026, 10, dayOfMonth, hour, minute);

  HealthSample sample(
    String type,
    double value,
    DateTime from, {
    DateTime? to,
    String source = 'com.watch',
    String label = '',
  }) => HealthSample(
    type: type,
    value: value,
    from: from,
    to: to,
    source: source,
    label: label,
  );

  Map<String, Object> valuesForDay(List<HealthSample> samples) =>
      healthValuesForDay(samples, day);

  group('kHealthMetrics', () {
    test('項目 id は重ならず、プリセット以外は health_ で始まる', () {
      final ids = kHealthMetrics.map((m) => m.fieldId).toList();
      expect(ids.toSet().length, ids.length);
      for (final metric in kHealthMetrics) {
        if (metric.isPreset) {
          expect([kSleepFieldId, kExerciseFieldId], contains(metric.fieldId));
        } else {
          expect(metric.fieldId, startsWith(kHealthFieldPrefix));
          expect(metric.toField().isHealth, isTrue);
        }
      }
    });

    test('合計・平均・最後の値でまとめる項目は、読む種類が1つ', () {
      const single = [
        HealthReduce.total,
        HealthReduce.average,
        HealthReduce.last,
      ];
      for (final metric in kHealthMetrics) {
        if (single.contains(metric.reduce)) {
          expect(metric.types, hasLength(1), reason: metric.label);
        }
      }
    });

    test('体の数値は、最初から AI に渡さない', () {
      for (final id in [
        'health_heart_rate',
        'health_blood_glucose',
        'health_bp_systolic',
        'health_weight',
        'health_menstruation',
      ]) {
        final field = healthMetricFor(id)!.toField();
        expect(field.shareWithAi, isFalse, reason: id);
        expect(field.usableInDiary, isFalse, reason: id);
      }
      expect(healthMetricFor('health_steps')!.toField().usableInDiary, isTrue);
    });

    test('読む種類それぞれの読み取り権限が、マニフェストに宣言されている', () {
      // 種類 → Health Connect の権限。宣言が無いと、許可画面に出ず読めない
      const permissions = {
        HcType.steps: 'READ_STEPS',
        HcType.distance: 'READ_DISTANCE',
        HcType.floors: 'READ_FLOORS_CLIMBED',
        HcType.activeEnergy: 'READ_ACTIVE_CALORIES_BURNED',
        HcType.totalEnergy: 'READ_TOTAL_CALORIES_BURNED',
        HcType.basalEnergy: 'READ_BASAL_METABOLIC_RATE',
        HcType.workout: 'READ_EXERCISE',
        HcType.sleepSession: 'READ_SLEEP',
        HcType.heartRate: 'READ_HEART_RATE',
        HcType.restingHeartRate: 'READ_RESTING_HEART_RATE',
        HcType.hrv: 'READ_HEART_RATE_VARIABILITY',
        HcType.respiratoryRate: 'READ_RESPIRATORY_RATE',
        HcType.bloodOxygen: 'READ_OXYGEN_SATURATION',
        HcType.weight: 'READ_WEIGHT',
        HcType.height: 'READ_HEIGHT',
        HcType.bodyFat: 'READ_BODY_FAT',
        HcType.leanMass: 'READ_LEAN_BODY_MASS',
        HcType.bodyWater: 'READ_BODY_WATER_MASS',
        HcType.systolic: 'READ_BLOOD_PRESSURE',
        HcType.diastolic: 'READ_BLOOD_PRESSURE',
        HcType.bodyTemperature: 'READ_BODY_TEMPERATURE',
        HcType.bloodGlucose: 'READ_BLOOD_GLUCOSE',
        HcType.water: 'READ_HYDRATION',
        HcType.nutrition: 'READ_NUTRITION',
        HcType.menstruation: 'READ_MENSTRUATION',
      };
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final type in healthTypesFor(kHealthMetrics)) {
        // 睡眠の段階は、睡眠と同じ権限で読む
        if (HcType.sleepStages.contains(type)) continue;
        final permission = permissions[type];
        expect(permission, isNotNull, reason: '$type の権限が表に無い');
        expect(
          manifest,
          contains('android.permission.health.$permission"'),
          reason: type,
        );
      }
    });
  });

  group('healthValuesForDay: 合計・平均・最後の値', () {
    test('区間の記録は、その日に始まった分だけを足す', () {
      final values = valuesForDay([
        sample(HcType.floors, 3, at(30, 8), to: at(30, 9)),
        sample(HcType.floors, 4, at(30, 18), to: at(30, 19)),
        sample(HcType.floors, 9, at(29, 18), to: at(29, 19)), // 前の日
        sample(HcType.floors, 9, at(31, 8), to: at(31, 9)), // 次の日
      ]);
      expect(values['health_floors'], 7);
    });

    test('2つのアプリが同じ種類を書いていたら、多く記録している方だけを使う', () {
      final values = valuesForDay([
        sample(HcType.distance, 3000, at(30, 8), source: 'com.phone'),
        sample(HcType.distance, 4200, at(30, 8), source: 'com.watch'),
        sample(HcType.distance, 1100, at(30, 18), source: 'com.watch'),
      ]);
      // 3000 + 5300 ではなく、ウォッチの 5300m だけ
      expect(values['health_distance'], 5.3);
    });

    test('単位をそろえて丸める（m → km、L → ml、整数の項目は int）', () {
      final values = valuesForDay([
        sample(HcType.distance, 1234, at(30, 8)),
        sample(HcType.water, 0.25, at(30, 9)),
        sample(HcType.water, 0.3, at(30, 12)),
        sample(HcType.activeEnergy, 120.6, at(30, 9)),
      ]);
      expect(values['health_distance'], 1.2);
      expect(values['health_water'], 550);
      expect(values['health_active_calories'], 121);
      expect(values['health_active_calories'], isA<int>());
    });

    test('平均は、件数の多いアプリの記録で出す', () {
      final values = valuesForDay([
        sample(HcType.heartRate, 60, at(30, 8)),
        sample(HcType.heartRate, 70, at(30, 9)),
        sample(HcType.heartRate, 80, at(30, 10)),
        sample(HcType.heartRate, 120, at(30, 9), source: 'com.phone'),
      ]);
      expect(values['health_heart_rate'], 70);
    });

    test('測った時点の値は、その日の最後のものを使う', () {
      final values = valuesForDay([
        sample(HcType.weight, 62.44, at(30, 7)),
        sample(HcType.weight, 61.96, at(30, 21)),
        sample(HcType.weight, 70, at(31, 7)), // 次の日
        sample(HcType.systolic, 121, at(30, 7)),
        sample(HcType.diastolic, 79, at(30, 7)),
      ]);
      expect(values['health_weight'], 62.0);
      expect(values['health_bp_systolic'], 121);
      expect(values['health_bp_diastolic'], 79);
    });

    test('基礎代謝は1日あたりの値なので、何回記録されていても足さない', () {
      final values = valuesForDay([
        sample(HcType.basalEnergy, 1500, at(30, 0)),
        sample(HcType.basalEnergy, 1520, at(30, 12)),
      ]);
      expect(values['health_bmr'], 1520);
    });

    test('記録の無い種類は入れない（0 として入れない）', () {
      final values = valuesForDay([sample(HcType.floors, 2, at(30, 8))]);
      expect(values.keys, ['health_floors']);
    });
  });

  group('healthValuesForDay: 睡眠', () {
    // 前の晩 23:00 に寝て、朝 7:00 に起きた（8時間）。途中で20分起きていた
    List<HealthSample> night({String source = 'com.watch'}) => [
      sample(
        HcType.sleepSession,
        480,
        at(29, 23),
        to: at(30, 7),
        source: source,
      ),
      sample(HcType.sleepLight, 0, at(29, 23), to: at(30, 3), source: source),
      sample(
        HcType.sleepAwake,
        0,
        at(30, 3),
        to: at(30, 3, 20),
        source: source,
      ),
      sample(HcType.sleepDeep, 0, at(30, 3, 20), to: at(30, 5), source: source),
      sample(HcType.sleepRem, 0, at(30, 5), to: at(30, 7), source: source),
    ];

    test('前の晩に寝て朝に起きた睡眠は、朝の日の分になる', () {
      expect(valuesForDay(night())[kSleepFieldId], 7.7); // 460分
      expect(
        healthValuesForDay(night(), DateTime(2026, 10, 29)),
        isNot(contains(kSleepFieldId)),
      );
    });

    test('段階ごとの分と、寝た時刻・起きた時刻', () {
      final values = valuesForDay(night());
      expect(values['health_sleep_light'], 240);
      expect(values['health_sleep_awake'], 20);
      expect(values['health_sleep_deep'], 100);
      expect(values['health_sleep_rem'], 120);
      expect(values['health_bedtime'], '23:00');
      expect(values['health_wake_time'], '07:00');
    });

    test('段階を書かないアプリなら、睡眠時間だけを入れる（段階を 0分にしない）', () {
      final values = valuesForDay([
        sample(HcType.sleepSession, 420, at(29, 23, 30), to: at(30, 6, 30)),
      ]);
      expect(values[kSleepFieldId], 7);
      expect(values, isNot(contains('health_sleep_deep')));
      expect(values, isNot(contains('health_sleep_awake')));
    });

    test('昼寝は睡眠時間に足すが、寝た時刻・起きた時刻は一番長い睡眠で決める', () {
      final values = valuesForDay([
        sample(HcType.sleepSession, 420, at(29, 23, 30), to: at(30, 6, 30)),
        sample(HcType.sleepSession, 30, at(30, 13), to: at(30, 13, 30)),
      ]);
      expect(values[kSleepFieldId], 7.5);
      expect(values['health_bedtime'], '23:30');
      expect(values['health_wake_time'], '06:30');
    });

    test('2つのアプリが同じ睡眠を書いていたら、二重に数えない', () {
      final values = valuesForDay([...night(), ...night(source: 'com.phone')]);
      expect(values[kSleepFieldId], 7.7);
      expect(values['health_sleep_deep'], 100);
    });
  });

  group('healthValuesForDay: 運動・BMI・月経', () {
    test('運動の記録があれば「運動した」、時間を足し、種類を日本語で並べる', () {
      final values = valuesForDay([
        sample(
          HcType.workout,
          0,
          at(30, 7),
          to: at(30, 7, 30),
          label: 'RUNNING',
        ),
        sample(HcType.workout, 0, at(30, 19), to: at(30, 20), label: 'YOGA'),
        sample(
          HcType.workout,
          0,
          at(30, 21),
          to: at(30, 21, 10),
          label: 'RUNNING',
        ),
        sample(HcType.workout, 0, at(30, 22), to: at(30, 23), label: 'NEW'),
      ]);
      expect(values[kExerciseFieldId], isTrue);
      expect(values['health_workout_minutes'], 160);
      expect(values['health_workout_kinds'], 'ランニング、ヨガ、その他の運動');
    });

    test('運動の記録が無い日は「運動した」を入れない（いいえにしない）', () {
      expect(valuesForDay([]), isNot(contains(kExerciseFieldId)));
    });

    test('BMI は、その日の体重と、前に測った身長から出す', () {
      final values = valuesForDay([
        sample(HcType.height, 1.7, at(1, 9)),
        sample(HcType.weight, 63.58, at(30, 7)),
      ]);
      expect(values['health_bmi'], 22.0);
    });

    test('身長が無ければ BMI は出さない', () {
      final values = valuesForDay([sample(HcType.weight, 63, at(30, 7))]);
      expect(values, isNot(contains('health_bmi')));
    });

    test('月経は、その日の一番多い量を選択肢にする（量が不明なら「量は不明」）', () {
      expect(
        valuesForDay([
          sample(HcType.menstruation, 1, at(30, 8)),
          sample(HcType.menstruation, 2, at(30, 20)),
        ])['health_menstruation'],
        'ふつう',
      );
      expect(
        valuesForDay([
          sample(HcType.menstruation, 0, at(30, 8)),
        ])['health_menstruation'],
        '量は不明',
      );
    });
  });

  group('latestHealthValues', () {
    test('項目ごとに、値があったいちばん新しい日を返す（並びは一覧の順）', () {
      final findings = latestHealthValues(
        [
          sample(HcType.floors, 5, at(28, 8)),
          sample(HcType.floors, 2, at(29, 8)),
          sample(HcType.weight, 61, at(20, 7)),
        ],
        today: at(30, 21),
        days: 30,
      );
      expect(findings.map((f) => f.metric.fieldId), [
        'health_floors',
        'health_weight',
      ]);
      expect(findings.first.day, DateTime(2026, 10, 29));
      expect(findings.first.value, 2);
      expect(findings.last.day, DateTime(2026, 10, 20));
    });

    test('遡る日数より古い記録は見ない', () {
      final findings = latestHealthValues(
        [sample(HcType.floors, 5, at(1, 8))],
        today: at(30, 21),
        days: 7,
      );
      expect(findings, isEmpty);
    });
  });

  group('deviceFillTargets', () {
    final steps = healthMetricFor('health_steps')!.toField();
    final weight = healthMetricFor('health_weight')!.toField();
    final menstruation = healthMetricFor('health_menstruation')!.toField();
    const sleep = RecordField(
      id: kSleepFieldId,
      label: '睡眠時間',
      kind: FieldKind.numeric,
      unit: '時間',
    );
    final fields = [steps, weight, menstruation, sleep];

    Map<String, Object> targets(
      Map<String, Object> readings,
      Map<String, dynamic>? record, {
      List<RecordField>? only,
    }) => deviceFillTargets(
      fields: only ?? fields,
      readings: readings,
      record: record,
    );

    test('空の項目には入れる', () {
      expect(targets({'health_steps': 8231}, null), {'health_steps': 8231});
    });

    test('利用者が入れた値には触らない', () {
      final record = {
        'values': {'health_weight': 60.0},
      };
      expect(targets({'health_weight': 62.0}, record), isEmpty);
    });

    test('前に端末から入れた値は、変わっていれば新しい値にする（今日の歩数は増える）', () {
      final record = {
        'values': {'health_steps': 3000},
        kDeviceFilledKey: ['health_steps'],
      };
      expect(targets({'health_steps': 8231}, record), {'health_steps': 8231});
      expect(targets({'health_steps': 3000.0}, record), isEmpty);
    });

    test('AI が会話から入れた値は、端末の値で置き換える', () {
      final record = {
        'values': {kSleepFieldId: 7},
        kAutoFilledKey: [kSleepFieldId],
      };
      expect(targets({kSleepFieldId: 6.5}, record), {kSleepFieldId: 6.5});
    });

    test('「消す」で取り消した項目は、空でも入れない', () {
      final record = {
        'values': <String, dynamic>{},
        kAutoRejectedKey: ['health_steps'],
      };
      expect(targets({'health_steps': 8231}, record), isEmpty);
    });

    test('その日の表に出ていない項目・型に合わない値は入れない', () {
      expect(targets({'health_steps': 8231}, null, only: [weight]), isEmpty);
      expect(targets({'health_menstruation': 'たくさん'}, null), isEmpty);
    });
  });

  group('withDeviceValues / deviceFilledIds', () {
    test('値を重ね、端末の印を足し、AI の印を外す。元の記録は書き換えない', () {
      final record = <String, dynamic>{
        'values': {kSleepFieldId: 7, 'mood': '良い'},
        kAutoFilledKey: [kSleepFieldId, 'mood'],
      };
      final next = withDeviceValues(record, {
        kSleepFieldId: 6.5,
        'health_steps': 8231,
      });
      expect(next['values'], {
        kSleepFieldId: 6.5,
        'mood': '良い',
        'health_steps': 8231,
      });
      expect(next[kDeviceFilledKey], [kSleepFieldId, 'health_steps']);
      expect(next[kAutoFilledKey], ['mood']);
      expect(record['values'], {kSleepFieldId: 7, 'mood': '良い'});
    });

    test('印があり、値も残っている項目だけを返す', () {
      final record = {
        'values': {'health_steps': 8231},
        kDeviceFilledKey: ['health_steps', 'health_weight'],
      };
      expect(deviceFilledIds(record), ['health_steps']);
      expect(deviceFilledIds(null), isEmpty);
    });
  });

  group('日々の記録との関わり', () {
    final steps = healthMetricFor('health_steps')!.toField();
    final glucose = healthMetricFor('health_blood_glucose')!.toField();
    const memo = RecordField(id: 'memo', label: 'メモ');

    test('端末から入れただけの日は「記録した日」に数えない', () {
      expect(
        hasAnyValue({
          'values': {'health_steps': 8231},
          kDeviceFilledKey: ['health_steps'],
        }),
        isFalse,
      );
      expect(
        hasAnyValue({
          'values': {'health_steps': 8231, 'memo': '散歩した'},
          kDeviceFilledKey: ['health_steps'],
        }),
        isTrue,
      );
    });

    test('記入状況の数に、端末の項目は入れない', () {
      final progress = recordProgress(
        [steps, glucose, memo],
        {
          'values': {'memo': '散歩した'},
        },
      );
      expect(progress, (filled: 1, total: 1));
    });

    test('AI に渡さない項目は、話題・日記・所見・期間の集計のどれにも出ない', () {
      final record = {
        'values': {'health_steps': 8231, 'health_blood_glucose': 98},
      };
      final rows = [steps, glucose];
      expect(recordSummary(rows, record), isNot(contains('血糖')));
      expect(recordSummary(rows, record), contains('歩数'));
      expect(
        recordSummary(rows, record, diaryOnly: true),
        isNot(contains('血糖')),
      );

      final days = [MapEntry('2026-10-30', record)];
      final index = {for (final f in rows) f.id: f};
      expect(
        DiaryPrompts.buildAnalysisPrompt(days, fields: index),
        isNot(contains('血糖')),
      );
      final summary = summarizePeriod(
        days,
        index,
        end: DateTime(2026, 10, 30),
        periodDays: 7,
      );
      expect(summary.fieldLines.join(), isNot(contains('血糖')));
      expect(summary.fieldLines.join(), contains('歩数'));
    });
  });

  group('RecordField', () {
    test('AIに送るかと、端末から足した出所を保存して読み戻せる', () {
      final field = healthMetricFor('health_weight')!.toField();
      final restored = RecordField.fromMap(field.toMap());
      expect(restored.shareWithAi, isFalse);
      expect(restored.source, FieldSource.health);
      expect(restored.isHealth, isTrue);
    });

    test('前からある項目（shareWithAi を持たない）は、AI に送る扱いで読む', () {
      final restored = RecordField.fromMap({'id': 'memo', 'label': 'メモ'});
      expect(restored.shareWithAi, isTrue);
      expect(restored.isHealth, isFalse);
    });
  });
}
