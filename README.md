# Verde 🎵

Мобильный музыкальный плеер на Flutter в стиле Spotify / YouTube Music.
Тёмная тема, зелёный акцент, нативный Android-плеер с фоновым
воспроизведением и уведомлением на экране блокировки.

## Источники музыки

- **Audius API** — публичный каталог независимых артистов, полные треки.
  Ключ API **не нужен**: хост выбирается через `api.audius.co` с fallback.
- **Deezer** и **iTunes Search API** — легальные 30-секундные превью.
- **Jamendo** — полные треки; нужен бесплатный `client_id` в настройках.
- **Internet Archive** — полные аудиозаписи с `mediatype:audio`.
- **SoundCloud** — полные треки, если автор разрешил поток
  (`policy` ≠ SNIP/BLOCK, `StreamInfo.isSnipped == false`). Прямой stream URL
  проигрывает существующий just_audio, без второго `AudioPlayer`.
- **YouTube** — полноценный источник: поиск без API-ключа
  (`youtube_explode_dart`), извлечение аудиопотока для just_audio и фон,
  а также скачивание в MP3 с сохранением в `Music/Verde`. Если прямой
  аудиопоток получить не удалось, для превью остаётся резервный
  встроенный IFrame-плеер.
- **Скачивание** — YouTube → MP3 192 кбит/с (`ffmpeg_kit` + `libmp3lame`)
  с названием, исполнителем и обложкой. Готовый файл попадает в общую
  папку `Music/Verde` (через MediaStore) и в «Мои треки».
- **Локальные аудиофайлы** с телефона (`on_audio_query`), выбранные вручную
  файлы (`file_picker`) и прямые ссылки на MP3.

## Возможности

- Нижняя навигация: Главная / Поиск / Библиотека
- Главная в стиле YouTube Music: «Быстрый выбор», «Слушайте снова»
  (треки, которых не было больше 3 дней), «Похоже на …» через Last.fm
  и «Ежедневный микс» на 20 треков. Подборки строятся локально по истории,
  лайкам и медиатеке и обновляются после каждого прослушивания.
- Поиск сразу по Deezer, iTunes, Audius, Jamendo, Internet Archive и
  YouTube: параллельные запросы с таймаутом 8 с, дебаунс 400 мс, чипы
  «Все / Полные / Превью», бейджи источников и недавние запросы
- «Слушать полностью» у 30-секундных превью: сначала SoundCloud
  (замена stream URL в текущей очереди), затем YouTube — прямой
  аудиопоток играет в фоне через just_audio; IFrame-плеер остаётся
  запасным вариантом
- Скачивание любого трека в MP3: кнопка загрузки в результатах поиска
  и пункт «Скачать MP3» в меню трека. Прогресс виден в нижней панели
  из любого экрана; готовый файл сохраняется в `Music/Verde` и
  в «Мои треки»
- Плеер: play/pause, next/prev, перемотка, громкость, shuffle,
  repeat (off / все / трек)
- Мини-плеер с прогрессом; тап открывает полноэкранный плеер
  (обложка, управление, очередь)
- Очередь воспроизведения: «играть следующим», «в конец очереди»,
  удаление и очистка
- Библиотека: лайки, плейлисты (создать / переименовать / удалить /
  добавить треки из поиска или с телефона), «Мои треки», добавление
  файла и прямой ссылки, настройки Jamendo `client_id` и Last.fm API key
  (также можно передать при сборке: `--dart-define=LASTFM_API_KEY=...`)
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
| Сеть | `http` (Deezer, iTunes, Audius, Jamendo, Internet Archive, YouTube) |
| Полные версии | `soundcloud_explode_dart`, `youtube_explode_dart`, `youtube_player_iframe` |
| Скачивание | `ffmpeg_kit_flutter_new_audio`, `path_provider`, MediaStore |
| Хранение | `shared_preferences` |
| Локальные треки | `on_audio_query`, `permission_handler`, `file_picker` |
| Обложки | `cached_network_image` |

## Структура

```
lib/
  app.dart, main.dart            # вход, DI через MultiProvider
  core/                          # тема, константы, ошибки, форматтеры
  data/
    api/audius_api.dart          # клиент Audius (bootstrap → discovery)
    api/search_api.dart          # параллельный мультипоиск и нормализация
    models/                      # Track, Playlist, Collection
    repositories/                # музыка/кэш, библиотека, локальные треки
  providers/                     # PlayerProvider, LibraryProvider, SearchProvider,
                                 # DownloadProvider
  services/audio_player_handler.dart  # BaseAudioHandler: очередь, уведомление
  services/full_track_resolver.dart   # SoundCloud → YouTube (поток / videoId)
  services/youtube_service.dart       # поиск, match, аудиопоток, загрузка
  services/mp3_download_service.dart  # YouTube → MP3 + метаданные/обложка
  services/media_store.dart           # сохранение в Music/Verde
  services/recommendation_service.dart # история, Last.fm, Deezer/iTunes
  screens/                       # home, search, library, settings, player
  widgets/                       # мини-плеер, очередь, меню, artwork,
                                 # карточки подборок, «Слушать полностью»,
                                 # кнопка/лист скачивания, YouTube iframe...
android/app/src/main/
  AndroidManifest.xml            # разрешения + audio_service service/receiver
  kotlin/.../MainActivity.kt     # MethodChannel com.verde.music/media_store
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
| `WRITE_EXTERNAL_STORAGE` (≤ API 28) | MP3 в общую папку `Music/Verde` на Android 8–9; на 10+ используется MediaStore без разрешений |

## Заметки

- `minSdk = 26` (Android 8.0): иконка — adaptive-icon XML без
  PNG-фоллбэков для старых API.
- Скачанные треки хранятся в файлах приложения и дублируются в публичную
  `Music/Verde` (MediaStore на Android 10+, прямое копирование на 8–9).
  Если публичное сохранение не удалось, трек всё равно остаётся
  в «Моих треках».
- Загружайте только контент, на который у вас есть права. Использование
  YouTube для скачивания может нарушать его условия и авторские права —
  ответственность за использование лежит на пользователе.
- Release APK подписывается debug-ключом (шаблон Flutter); для публикации
  в Google Play подключите keystore.
- Приложение-идентификатор Audius: `VerdeMusic` (см. `lib/core/constants.dart`).
