import 'package:flutter/services.dart';

class AudioPlayerService {
  static const _channel = MethodChannel('com.nearbyconnect.app/audio_player');

  static Future<bool> play(String url) async {
    try {
      final res = await _channel.invokeMethod<bool>('play', {'url': url});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stop() async {
    try {
      final res = await _channel.invokeMethod<bool>('stop');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPlaying() async {
    try {
      final res = await _channel.invokeMethod<bool>('isPlaying');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getPlayingUrl() async {
    try {
      return await _channel.invokeMethod<String>('getPlayingUrl');
    } catch (_) {
      return null;
    }
  }

  static Future<void> openMaps(String url) async {
    try {
      await _channel.invokeMethod('openMaps', {'url': url});
    } catch (_) {}
  }
}
