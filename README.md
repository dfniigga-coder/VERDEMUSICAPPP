# Verde 🎵

Мобильный музыкальный плеер на Flutter в стиле Spotify / YouTube Music.
Тёмная тема, зелёный акцент, нативный Android-плеер с фоновым
воспроизведением и уведомлением на экране блокировки.

## Источники музыки (только легальные)

- **Audius API** — публичный каталог независимых артистов. Ключ API **не нужен**:
  хост выбирается через bootstrap-адрес `api.audius.co`.
- **Локальные аудиофайлы** с телефона (`on_audio_query`).

## Возможности

- Нижняя навигация: Главная / Поиск / Библиотека
- Главная: популярные треки (неделя), андеграунд и подборки Audius;
  кэш в shared_preferences — работает офлайн
- Поиск по названию и исполнителю + недавние запросы
- Плеер: play/pause, next/prev, перемотка, громкость, shuffle,
  repeat (off / все / трек)
- Мини-плеер с прогрессом; тап открывает полноэкранный плеер
  (обложка, управление, очередь)
- Очередь воспроизведения: «играть следующим», «в конец очереди»,
  удаление и очистка
- Библиотека: лайки, плейлисты (создать / переименовать / удалить /
  добавить треки из поиска или с телефона), локальные треки
- Фоновое воспроизведение и медиа-уведомление с кнопками
  (just_audio + audio_service, media3 session)
- Обработка ошибок: нет сети (оформленный ErrorView + кэш), трек не
  загрузился (снекбар + автопропуск `maxSkipsOnError`), нет доступа
  к локальным файлам (запрос разрешения на месте)

## Стек

| Что | Чем |
|---|---|
| UI | Flutter, Material 3, тёмная тема, SeedColor `#1DB954` |
| Аудио | `just_audio` (playlist API 0.10), `audio_service` 0.18 |
| Состояние | `provider` |
| Сеть | `http` |
| Хранение | `shared_preferences` |
| Локальные треки | `on_audio_query`, `permission_handler` |
| Обложки | `cached_network_image` |

## Структура

```
lib/
  app.dart, main.dart            # вход, DI через MultiProvider
  core/                          # тема, константы, ошибки, форматтеры
  data/
    api/audius_api.dart          # клиент Audius (bootstrap → discovery)
    models/                      # Track, Playlist, Collection
    repositories/                # музыка/кэш, библиотека, локальные треки
  providers/                     # PlayerProvider, LibraryProvider, SearchProvider
  services/audio_player_handler.dart  # BaseAudioHandler: очередь, уведомление
  screens/                       # home, search, library, player, root_shell
  widgets/                       # мини-плеер, очередь, меню, artwork...
android/app/src/main/
  AndroidManifest.xml            # разрешения + audio_service service/receiver
.github/workflows/build.yml     # CI: release APK как artifact
```

## Сборка без установленного SDK

Локальный Android SDK не нужен: на каждый push запускается workflow
`.github/workflows/build.yml` (GitHub Actions):

1. Скачивает Flutter 3.47.9 и JDK 17.
2. `flutter pub get` → `flutter analyze` → `flutter build apk --release`.
3. Публикует `verde-release-apk` как artifact — на странице последнего
   прогона Actions, раздел **Artifacts** (см. фото APK для установки).

Сборку можно запустить вручную: вкладка *Actions* → *build* → *Run workflow*.

## Разрешения Android

| Permission | Зачем |
|---|---|
| `INTERNET` | Audius API и стримы |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | фоновый плеер |
| `POST_NOTIFICATIONS` | медиа-уведомление (Android 13+ запрашивает рантайм) |
| `WAKE_LOCK` | media3 session, чтобы CPU не засыпал при загрузке |
| `RECEIVE_BOOT_COMPLETED` | перезапуск media-сессии аудио-сервиса |
| `READ_MEDIA_AUDIO` (+ `READ_EXTERNAL_STORAGE` ≤ API 32) | треки с телефона |

## Заметки

- `minSdk = 26` (Android 8.0): иконка — adaptive-icon XML без
  PNG-фоллбэков для старых API.
- Release APK подписывается debug-ключом (шаблон Flutter); для публикации
  в Google Play подключите keystore.
- Приложение-идентификатор Audius: `VerdeMusic` (см. `lib/core/constants.dart`).
