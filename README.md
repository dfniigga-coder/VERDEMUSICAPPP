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
  а также скачивание в MP3 с сохранением в `Music/Verde`. Основной путь —
  прямой googlevideo-URL из VISIONOS-манифеста: старт за 1–2 секунды,
  без промежуточного прокси. Ссылки кэшируются и прогреваются для
  следующих треков; Invidious используется только как аварийный fallback.
  Если аудиопоток получить не удалось, для превью остаётся резервный
  встроенный IFrame-плеер.
- **Скачивание** — YouTube → MP3 192 кбит/с (`ffmpeg_kit` + `libmp3lame`)
  с названием, исполнителем и обложкой. Готовый файл попадает в общую
  папку `Music/Verde` (через MediaStore) и в «Мои треки».
- **Скачивание по ссылке** — скопируйте ссылку в YouTube Music
  (`music.youtube.com/watch?v=…`, `youtu.be/…`) и вставьте её в Verde
  или поделитесь ею через Android-меню «Поделиться». Приложение само
  получит название, исполнителя и обложку, скачает аудиодорожку,
  конвертирует её в MP3 и сохранит в `Music/Verde`.
- **Локальные аудиофайлы** с телефона (`on_audio_query`), выбранные вручную
  файлы (`file_picker`) и прямые ссылки на MP3.

## Возможности

- Нижняя навигация: Главная / Поиск / Библиотека
- Главная в стиле YouTube Music: алгоритм идёт от конкретных песен
  пользователя. История, лайки, плейлисты и медиатека дают «семена», к
  каждому подбираются похожие треки — секции «Похоже на «…»» и общий
  микс «Для вас». Дополнительно показываются «Любимые исполнители» и
  «Слушайте снова» (треки, которых не было больше 3 дней). Если Last.fm
  не настроен, похожие находятся через связанных исполнителей Deezer и
  треки того же артиста. Подборки обновляются после каждого прослушивания.
- Поиск сразу по Deezer, iTunes, Audius, Jamendo, Internet Archive и
  YouTube: параллельные запросы с таймаутом 8–10 с, результаты появляются
  по мере ответа источников (Deezer/iTunes обычно первыми), кэш на 5 минут,
  дебаунс 250 мс, чипы «Все / Полные / Превью», бейджи источников и
  недавние запросы.
- Превью Deezer/iTunes больше не играют 30 секунд: при нажатии Verde
  сразу ищет полную версию на YouTube, скачивает её в MP3 192 кбит/с
  в «Мои треки» и `Music/Verde`, затем запускает локальный файл.
  Остальные превью не попадают в очередь, поэтому автопереход тоже
  всегда включает полный трек
- «Слушать полностью» у 30-секундных превью: сначала SoundCloud
  (замена stream URL в текущей очереди), затем YouTube — прямой
  аудиопоток играет в фоне через just_audio; IFrame-плеер остаётся
  запасным вариантом
- Скачивание любого трека в MP3: кнопка загрузки в результатах поиска
  и пункт «Скачать MP3» в меню трека. Прогресс виден в нижней панели
  из любого экрана; готовый файл сохраняется в `Music/Verde` и
  в «Мои треки»
- Скачивание по ссылке YouTube Music: иконка ссылки в поиске, пункт
  «Скачать с YouTube Music» в библиотеке или Android-меню «Поделиться»
  (а также открытие YouTube-ссылки сразу в Verde). Плейлисты
  отклоняются с подсказкой — нужна ссылка на конкретный трек
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
  services/youtube_service.dart       # поиск, match, метаданные, аудиопоток
  services/youtube_link.dart          # разбор ссылок YouTube / YouTube Music
  services/incoming_link_service.dart # ссылки из Android «Поделиться» / VIEW
  services/mp3_download_service.dart  # ссылка/YouTube → MP3 + метаданные/обложка
  services/media_store.dart           # сохранение в Music/Verde
  services/recommendation_service.dart # семена из ваших песен, Last.fm, Deezer
  screens/                       # home, search, library, settings, player
  widgets/                       # мини-плеер, очередь, меню, artwork,
                                 # карточки подборок, «Слушать полностью»,
                                 # кнопка/лист скачивания, лист «ссылка → MP3»,
                                 # YouTube iframe...
android/app/src/main/
  AndroidManifest.xml            # разрешения, audio_service, SEND/VIEW-фильтры
  kotlin/.../MainActivity.kt     # MediaStore + каналы входящих ссылок
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
