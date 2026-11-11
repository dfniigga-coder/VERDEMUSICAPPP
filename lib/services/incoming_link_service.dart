import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Приём ссылок, которыми с приложением поделились из YouTube Music
/// (Android «Поделиться» → Verde) или которые открыли через Verde.
class IncomingLinkService {
  static const MethodChannel _method = MethodChannel(
    'com.verde.music/incoming_link',
  );
  static const EventChannel _events = EventChannel(
    'com.verde.music/incoming_link_events',
  );

  /// Ссылки, пришедшие, когда приложение уже запущено.
  Stream<String> get links {
    if (!Platform.isAndroid) return const Stream<String>.empty();
    return _events
        .receiveBroadcastStream()
        .where((event) => event is String)
        .cast<String>();
  }

  /// Ссылка, с которой приложение запустили (холодный старт).
  Future<String?> initialLink() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _method.invokeMethod<String>('getInitialLink');
    } catch (error) {
      debugPrint('IncomingLinkService: initial link failed: $error');
      return null;
    }
  }
}
