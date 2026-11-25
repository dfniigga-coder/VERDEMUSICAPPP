import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/api/audius_api.dart';
import 'data/api/search_api.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/local_tracks_repository.dart';
import 'data/repositories/music_repository.dart';
import 'providers/download_provider.dart';
import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'providers/search_provider.dart';
import 'services/audio_player_handler.dart';
import 'services/full_track_resolver.dart';
import 'services/lyrics_service.dart';
import 'services/mp3_download_service.dart';
import 'services/recommendation_service.dart';
import 'services/youtube_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ошибки Flutter/асинхронного кода не должны превращаться в вылет
  // приложения: логируем их и продолжаем работу. Это особенно важно для
  // сетевых ответов и фоновых задач, которые приходят уже после смены
  // экрана или закрытия нижнего листа.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Verde: uncaught error: $error\n$stack');
    return true;
  };

  try {
    await _runApp();
  } catch (error, stack) {
    debugPrint('Verde: startup failed: $error\n$stack');
    runApp(const _StartupErrorApp());
  }
}

Future<void> _runApp() async {
  // 1. Локальное хранилище
  final prefs = await SharedPreferences.getInstance();

  // 2. База данных + репозитории
  final libraryRepo = LibraryRepository(prefs)..load();
  final audiusApi = AudiusApi(prefs);
  final musicRepo = MusicRepository(audiusApi, prefs);
  final youtubeService = YoutubeService();
  // Прогреваем Invidious-хост заранее, чтобы первый трек стартовал
  // без ожидания проверки зеркал.
  unawaited(youtubeService.warmUpPlaybackHost());
  final searchApi = SearchApi(audiusApi, prefs, youtubeService);
  final localTracksRepo = LocalTracksRepository(OnAudioQuery(), prefs);
  final lyricsService = LyricsService();
  final mp3DownloadService = Mp3DownloadService(
    youtube: youtubeService,
    localTracks: localTracksRepo,
    lyrics: lyricsService,
  );
  final recommendationService = RecommendationService(
    prefs: prefs,
    searchApi: searchApi,
    library: libraryRepo,
    localTracks: localTracksRepo,
  );
  final downloadProvider = DownloadProvider(mp3DownloadService);

  // 3. Фоновый аудио-сервис (уведомление, экран блокировки, гарнитура).
  // Если сервис не поднялся, всё равно запускаем обычный just_audio:
  // музыка будет играть, а уведомление — нет. Это лучше, чем пустой экран
  // при старте.
  AudioPlayerHandler audioHandler;
  try {
    audioHandler = await AudioService.init<AudioPlayerHandler>(
      builder: () => AudioPlayerHandler(musicRepo, youtubeService),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.verde.music.playback',
        androidNotificationChannelName: 'Воспроизведение Verde',
        androidNotificationChannelDescription:
            'Управление музыкой в фоне и с экрана блокировки',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (error, stack) {
    debugPrint('Verde: audio_service init failed: $error\n$stack');
    audioHandler = AudioPlayerHandler(musicRepo, youtubeService);
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        Provider<MusicRepository>.value(value: musicRepo),
        Provider<LibraryRepository>.value(value: libraryRepo),
        Provider<RecommendationService>.value(value: recommendationService),
        Provider<YoutubeService>(
          create: (_) => youtubeService,
          dispose: (_, service) => service.dispose(),
        ),
        Provider<Mp3DownloadService>(
          create: (_) => mp3DownloadService,
          dispose: (_, service) => service.dispose(),
        ),
        Provider<LyricsService>(
          create: (_) => lyricsService,
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider<LocalTracksRepository>.value(
          value: localTracksRepo,
        ),
        ChangeNotifierProvider<DownloadProvider>(
          create: (_) => downloadProvider,
        ),
        ChangeNotifierProvider<PlayerProvider>(
          create: (_) => PlayerProvider(
            audioHandler,
            recommendations: recommendationService,
            youtube: youtubeService,
            downloads: downloadProvider,
          ),
        ),
        ChangeNotifierProvider<LibraryProvider>(
          create: (_) => LibraryProvider(libraryRepo),
        ),
        ChangeNotifierProvider<SearchProvider>(
          create: (_) => SearchProvider(searchApi, libraryRepo),
        ),
        Provider<FullTrackResolver>(
          create: (_) => FullTrackResolver(youtube: youtubeService),
          dispose: (_, resolver) => resolver.dispose(),
        ),
      ],
      child: const VerdeApp(),
    ),
  );

  // Разрешение запрашиваем уже после первого кадра: диалог Android 13+
  // не должен задерживать запуск интерфейса.
  unawaited(_requestNotificationPermission());
}

/// Запасной экран, если инициализация приложения не удалась.
///
/// Пользователь видит понятное сообщение и может перезапустить приложение,
/// вместо мгновенного закрытия процесса.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Не удалось запустить Verde',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Перезапустите приложение. Если ошибка повторяется — '
                    'очистите данные Verde в настройках Android.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Android 13+ требует runtime-разрешение на уведомления; без него
/// не показывается медиа-уведомление. На более старых версиях — granted.
Future<void> _requestNotificationPermission() async {
  try {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  } catch (_) {
    // permission_handler может отсутствовать на платформе — не критично.
  }
}
