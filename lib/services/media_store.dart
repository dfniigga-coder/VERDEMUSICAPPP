import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Сохраняет готовый MP3 в общую папку Music/Verde через MediaStore.
///
/// На Android 10+ разрешения не нужны: файл добавляется в медиатеку
/// системным ContentResolver. На Android 8–9 приложение попросит
/// WRITE_EXTERNAL_STORAGE и скопирует файл в публичную папку.
class MediaStore {
  MediaStore._();

  static const MethodChannel _channel = MethodChannel(
    'com.verde.music/media_store',
  );

  /// Возвращает человекочитаемый путь вида `Music/Verde/Artist - Track.mp3`.
  /// null — платформа не Android или канал недоступен.
  static Future<String?> saveAudio({
    required String filePath,
    required String displayName,
    required String title,
    required String artist,
    String mimeType = 'audio/mpeg',
  }) async {
    if (!Platform.isAndroid) return null;

    final arguments = <String, Object?>{
      'filePath': filePath,
      'displayName': displayName,
      'title': title,
      'artist': artist,
      'mimeType': mimeType,
    };

    try {
      return await _invoke(arguments);
    } on PlatformException catch (error) {
      if (error.code != 'PERMISSION_DENIED') {
        throw MediaStoreException(
          error.message ?? 'Не удалось сохранить файл в Music/Verde.',
        );
      }
    }

    final status = await Permission.storage.request();
    if (!status.isGranted) {
      throw const MediaStoreException(
        'Нет разрешения на запись в Music. Файл оставлен в приложении.',
      );
    }

    try {
      return await _invoke(arguments);
    } on PlatformException catch (error) {
      throw MediaStoreException(
        error.message ?? 'Не удалось сохранить файл в Music/Verde.',
      );
    }
  }

  static Future<String?> _invoke(Map<String, Object?> arguments) {
    return _channel.invokeMethod<String>('saveAudio', arguments);
  }
}

class MediaStoreException implements Exception {
  final String message;

  const MediaStoreException(this.message);

  @override
  String toString() => message;
}
