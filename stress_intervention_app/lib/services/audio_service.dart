import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;
  AudioPlayer get player => _audioPlayer;

  // 再生状態変更のコールバック用
  Stream<PlayerState> get onPlayerStateChanged => _audioPlayer.onPlayerStateChanged;

  /// アセットの音楽（relax_music.wav）を再生する
  Future<void> playRelaxMusic() async {
    try {
      // audioplayers v6 では、デフォルトで assets/ がルートとなるため
      // assets/audio/relax_music.wav の場合は 'audio/relax_music.wav' を指定します。
      await _audioPlayer.play(AssetSource('audio/relax_music.wav'));
      _isPlaying = true;
      debugPrint('Audio started playing: relax_music.wav');
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  /// 一時停止
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _isPlaying = false;
      debugPrint('Audio paused');
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  /// 停止
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
      debugPrint('Audio stopped');
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  /// 音量調節 (0.0 から 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _audioPlayer.setVolume(volume);
    } catch (e) {
      debugPrint('Error setting volume: $e');
    }
  }

  /// ループ再生の設定
  Future<void> setLoop(bool loop) async {
    try {
      await _audioPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    } catch (e) {
      debugPrint('Error setting loop mode: $e');
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
