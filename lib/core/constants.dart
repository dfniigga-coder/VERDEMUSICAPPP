/// Константы приложения.
class AppConstants {
  AppConstants._();

  /// Название приложения (отображается пользователю).
  static const String appName = 'Verde';

  /// Имя приложения для Audius (требуется параметром к каждому запросу API).
  static const String audiusAppName = 'VerdeMusic';

  /// Bootstrap-адрес, у которого запрашивается список discovery-серверов.
  static const String audiusBootstrapUrl = 'https://api.audius.co';

  /// Fallback discovery-сервер, если bootstrap недоступен.
  static const String audiusFallbackHost =
      'https://discoveryprovider.audius.co';

  /// Таймаут HTTP-запросов, с.
  static const int requestTimeoutSeconds = 15;

  /// Таймаут одного источника при мультипоиске, с.
  static const int searchTimeoutSeconds = 8;

  /// Таймаут поиска/резолва полной версии трека (SoundCloud, YouTube), с.
  static const int fullTrackTimeoutSeconds = 7;

  /// Сколько треков в подборках на главной.
  static const int trendingLimit = 30;

  /// Сколько треков в выдаче поиска (на каждый источник).
  static const int searchLimit = 25;

  /// Сколько плейлистов Audius тянем для раздела «Подборки».
  static const int playlistsLimit = 12;

  /// Ключи хранения в shared_preferences.
  static const String likedTracksKey = 'verde.liked_tracks';
  static const String playlistsKey = 'verde.playlists';
  static const String recentSearchesKey = 'verde.recent_searches';
  static const String homeCacheKey = 'verde.home_cache_v1';
  static const String audiusHostKey = 'verde.audius_host';
  static const String jamendoClientIdKey = 'verde.jamendo_client_id';
  static const String importedTracksKey = 'verde.imported_tracks';

  /// История прослушиваний для локальных рекомендаций.
  static const String playHistoryKey = 'verde.play_history_v1';

  /// Last.fm API key: можно сохранить в настройках или передать
  /// при сборке через `--dart-define=LASTFM_API_KEY=...`.
  static const String lastFmApiKeyKey = 'verde.lastfm_api_key';
  static const String lastFmApiKeyFromEnv = String.fromEnvironment(
    'LASTFM_API_KEY',
  );
}
