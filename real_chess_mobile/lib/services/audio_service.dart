import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  
  // Using URLs for now as we don't have local assets yet, 
  // or we can expect assets to be valid.
  // For this implementation, I will assume we will add assets later or use simple online ones?
  // Actually, best practice is to require assets. 
  // I will implement the service to try to play local assets 'assets/audio/move.mp3' etc.
  // The user will need to add these files. I will assume they exist or fail gracefully.
  
  // Better approach: Use a standard set of chess sounds from a public URL if assets fail?
  // No, let's stick to local assets and just log error if missing.
  
  static const String _moveSound = 'audio/move.mp3';
  static const String _captureSound = 'audio/capture.mp3';
  static const String _checkSound = 'audio/check.mp3';
  static const String _gameOverSound = 'audio/game_over.mp3';

  Future<void> playMove() async {
    try {
      await _player.play(AssetSource(_moveSound));
    } catch (e) {
      debugPrint('[AudioService] Failed to play move sound: $e');
    }
  }

  Future<void> playCapture() async {
    try {
      await _player.play(AssetSource(_captureSound));
    } catch (e) {
      debugPrint('[AudioService] Failed to play capture sound: $e');
    }
  }

  Future<void> playCheck() async {
    try {
      await _player.play(AssetSource(_checkSound));
    } catch (e) {
      debugPrint('[AudioService] Failed to play check sound: $e');
    }
  }

  Future<void> playGameOver() async {
    try {
      await _player.play(AssetSource(_gameOverSound));
    } catch (e) {
      debugPrint('[AudioService] Failed to play game over sound: $e');
    }
  }
}
