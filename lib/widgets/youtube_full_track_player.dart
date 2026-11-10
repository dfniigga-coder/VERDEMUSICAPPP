import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../core/theme/app_theme.dart';
import '../data/models/resolved_track.dart';
import '../providers/player_provider.dart';
import 'artwork.dart';
import 'common.dart';

/// Встроенный YouTube-плеер для полного прослушивания трека.
///
/// Использует официальный iFrame Player API (без API-ключа и без извлечения
/// аудио). На время показа ставит just_audio на паузу; при закрытии может
/// вернуть фоновое воспроизведение, если пользователь этого хочет.
class YouTubeFullTrackPlayer extends StatefulWidget {
  const YouTubeFullTrackPlayer({
    super.key,
    required this.videoId,
    required this.title,
    this.artist = '',
    this.artworkUrl,
  });

  /// videoId (11 символов) или любой URL YouTube — URL нормализуется.
  final String videoId;

  final String title;
  final String artist;
  final String? artworkUrl;

  @override
  State<YouTubeFullTrackPlayer> createState() => _YouTubeFullTrackPlayerState();
}

/// Открывает YouTube-плеер в bottom sheet.
Future<void> showYouTubeFullTrack(
  BuildContext context, {
  required ResolvedTrack track,
}) async {
  final videoId = track.youtubeVideoId;
  if (videoId == null || videoId.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.surface,
    builder: (_) => YouTubeFullTrackPlayer(
      videoId: videoId,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
    ),
  );
}

class _YouTubeFullTrackPlayerState extends State<YouTubeFullTrackPlayer>
    with WidgetsBindingObserver {
  late final String _videoId;
  late final YoutubePlayerController _controller;
  late final PlayerProvider _player;

  StreamSubscription<YoutubePlayerValue>? _valueSubscription;
  bool _wasPlaying = false;
  bool _resumeAudio = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _videoId =
        YoutubePlayerController.convertUrlToId(widget.videoId) ??
        widget.videoId.trim();

    _player = context.read<PlayerProvider>();
    _wasPlaying = _player.isPlaying;
    _resumeAudio = _wasPlaying;

    _controller = YoutubePlayerController.fromVideoId(
      videoId: _videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        privacyEnhancedMode: true,
        interfaceLanguage: 'ru',
        captionLanguage: 'ru',
        playsInline: true,
      ),
    );

    _valueSubscription = _controller.stream.listen(_onPlayerValue);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_preparePlayback());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // YouTube ToS не разрешает фоновое воспроизведение — уходя в фон,
    // обязательно ставим видео на паузу, а не оставляем звук.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_pauseYoutube());
    }
  }

  Future<void> _preparePlayback() async {
    if (_wasPlaying) {
      try {
        await _player.pause();
      } catch (error) {
        debugPrint('YouTubeFullTrackPlayer: just_audio pause failed: $error');
      }
    }

    if (!mounted) return;
    try {
      await _controller.playVideo();
    } catch (error) {
      debugPrint('YouTubeFullTrackPlayer: playVideo failed: $error');
    }
  }

  Future<void> _pauseYoutube() async {
    try {
      await _controller.pauseVideo();
    } catch (error) {
      debugPrint('YouTubeFullTrackPlayer: pauseVideo failed: $error');
    }
  }

  void _onPlayerValue(YoutubePlayerValue value) {
    if (!mounted) return;

    final nextError = value.hasError ? _errorMessageFor(value.error) : null;
    if (nextError != _errorMessage) {
      setState(() => _errorMessage = nextError);
    }
  }

  String _errorMessageFor(YoutubeError error) {
    switch (error) {
      case YoutubeError.notEmbeddable:
      case YoutubeError.sameAsNotEmbeddable:
      case YoutubeError.sameAsNotEmbeddable2:
        return 'Автор запретил воспроизведение этого видео во встроенном '
            'плеере. Откройте его на YouTube.';
      case YoutubeError.videoNotFound:
      case YoutubeError.cannotFindVideo:
        return 'Видео недоступно или было удалено.';
      case YoutubeError.invalidParam:
        return 'Некорректная ссылка на видео.';
      default:
        return 'YouTube не смог воспроизвести видео. '
            'Попробуйте открыть его на YouTube.';
    }
  }

  Future<void> _openOnYoutube() async {
    final uri = Uri.https('www.youtube.com', '/watch', {'v': _videoId});

    // Внешний YouTube-плеер не должен конфликтовать с just_audio.
    if (_resumeAudio) {
      setState(() => _resumeAudio = false);
    }
    unawaited(_pauseYoutube());

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        showAppSnackBar(context, 'Не удалось открыть YouTube.', isError: true);
      }
    } catch (error) {
      debugPrint('YouTubeFullTrackPlayer: launchUrl failed: $error');
      if (mounted) {
        showAppSnackBar(context, 'Не удалось открыть YouTube.', isError: true);
      }
    }
  }

  Future<void> _shutdown() async {
    try {
      await _controller.close();
    } catch (error) {
      debugPrint('YouTubeFullTrackPlayer: close failed: $error');
    }

    if (_wasPlaying && _resumeAudio && _player.hasQueue) {
      try {
        if (!_player.isPlaying) await _player.resume();
      } catch (error) {
        debugPrint('YouTubeFullTrackPlayer: resume failed: $error');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _valueSubscription?.cancel();
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ArtworkView(size: 50, url: widget.artworkUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.artist.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _YoutubeBadge(),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                YoutubePlayer(
                  controller: _controller,
                  aspectRatio: 16 / 9,
                  autoFullScreen: false,
                  backgroundColor: Colors.black,
                ),
                if (_errorMessage != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.88),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'В фоне этот YouTube-плеер останавливается — ограничение IFrame. '
            'Обычные YouTube-треки Verde играет через прямой аудиопоток '
            'с фоновым воспроизведением.',
            style: TextStyle(fontSize: 12, color: AppTheme.textDim),
          ),
          if (_wasPlaying) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _resumeAudio,
              onChanged: (value) => setState(() => _resumeAudio = value),
              title: const Text(
                'Вернуть обычный плеер после закрытия',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _openOnYoutube,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Открыть на YouTube'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YoutubeBadge extends StatelessWidget {
  const _YoutubeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x33FF5252),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_display, size: 11, color: Color(0xFFFF8A80)),
          SizedBox(width: 4),
          Text(
            'YouTube (полный)',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF8A80),
            ),
          ),
        ],
      ),
    );
  }
}
