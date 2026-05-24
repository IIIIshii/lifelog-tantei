import 'package:speech_to_text/speech_to_text.dart';

// OSの音声認識API（iOS Speech / Android SpeechRecognizer）を薄くラップしたサービス。
// シングルトンで保持し、UI側はマイクボタンから start/stop を呼ぶだけで使えるようにする。
class SpeechService {
  static final instance = SpeechService._();
  SpeechService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  // 初回利用時に呼び出してマイク権限ダイアログを出す。成功なら true。
  Future<bool> initialize() async {
    if (_initialized) return _speech.isAvailable;
    _initialized = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _initialized;
  }

  // 音声認識を開始する。部分認識を含めて onResult に文字列を流す。
  // 端末側のVAD（無音検出）で自動停止することもあるため、それを呼び出し側に伝えるため onDone を用意。
  Future<bool> startListening({
    required void Function(String text) onResult,
    required void Function() onDone,
  }) async {
    final ok = await initialize();
    if (!ok) return false;

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: 'ja_JP',
      ),
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) onDone();
      },
    );
    return true;
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}
