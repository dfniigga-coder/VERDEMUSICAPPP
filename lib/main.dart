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
import 'services/mp3_download_service.dart';
import 'services/recommendation_service.dart';
import 'services/youtube_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Локальное хранилище
  final prefs = await SharedPreferences.getInstance();

  // 2. База данных + репозитории
  final libraryRepo = LibraryRepository(prefs)..load();
  final audiusApi = AudiusApi(prefs);
  final musicRepo = MusicRepository(audiusApi, prefs);
  final youtubeService = YoutubeService();
  final searchApi = SearchApi(audiusApi, prefs, youtubeService);
  final localTracksRepo = LocalTracksRepository(OnAudioQuery(), prefs);
  final mp3DownloadService = Mp3DownloadService(
    youtube: youtubeService,
    localTracks: localTracksRepo,
  );
  final recommendationService = RecommendationService(
    prefs: prefs,
    searchApi: searchApi,
    library: libraryRepo,
    localTracks: localTracksRepo,
  );

  // 3. Разрешение на постоянные уведомления (Android 13+) — фон-плеер?
  await _requestNotificationPermission();

  // 4. Фоновый аудио-сервис (уведомление, экран блокировки, гарнитура)
  final audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(musicRepo),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.verde.music.playback',
      androidNotificationChannelName: 'Воспроизведение Verde',
      androidNotificationChannelDescription:
          'Управление музыкой в фоне и с экрана блокировки',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

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
        ChangeNotifierProvider<LocalTracksRepository>.value(
          value: localTracksRepo,
        ),
        ChangeNotifierProvider<PlayerProvider>(
          create: (_) => PlayerProvider(
            audioHandler,
            recommendations: recommendationService,
            youtube: youtubeService,
          ),
        ),
        ChangeNotifierProvider<LibraryProvider>(
          create: (_) => LibraryProvider(libraryRepo),
        ),
        ChangeNotifierProvider<SearchProvider>(
          create: (_) => SearchProvider(searchApi, libraryRepo),
        ),
        ChangeNotifierProvider<DownloadProvider>(
          create: (_) => DownloadProvider(mp3DownloadService),
        ),
        Provider<FullTrackResolver>(
          create: (_) => FullTrackResolver(youtube: youtubeService),
          dispose: (_, resolver) => resolver.dispose(),
        ),
      ],
      child: const VerdeApp(),
    ),
  );
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
