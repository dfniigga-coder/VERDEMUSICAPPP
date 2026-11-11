import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../services/incoming_link_service.dart';
import '../services/youtube_link.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'search/search_screen.dart';
import '../widgets/common.dart';
import '../widgets/download_sheet.dart';
import '../widgets/link_download_sheet.dart';
import '../widgets/mini_player.dart';

/// Каркас: bottom nav = 3 таба (IndexedStack сохраняет состояние),
/// над ним мини-плеер.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;
  PlayerProvider? _playerRef;
  DownloadProvider? _downloadsRef;

  final IncomingLinkService _incomingLinks = IncomingLinkService();
  StreamSubscription<String>? _incomingLinkSubscription;
  bool _handlingIncomingLink = false;

  @override
  void initState() {
    super.initState();
    // Показываем снекбары об ошибках воспроизведения в любом табе.
    _playerRef = context.read<PlayerProvider>();
    _playerRef!.errorNotifier.addListener(_showPlayError);
    // И о завершении скачивания — тоже из любого таба.
    _downloadsRef = context.read<DownloadProvider>();
    _downloadsRef!.notice.addListener(_showDownloadNotice);

    // Ссылки из «Поделиться» YouTube Music и переходов по YouTube-ссылкам.
    _incomingLinkSubscription = _incomingLinks.links.listen(
      _handleIncomingLink,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleInitialLink());
    });
  }

  @override
  void dispose() {
    _playerRef?.errorNotifier.removeListener(_showPlayError);
    _downloadsRef?.notice.removeListener(_showDownloadNotice);
    _incomingLinkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleInitialLink() async {
    final link = await _incomingLinks.initialLink();
    if (link != null && mounted) _handleIncomingLink(link);
  }

  /// Поделились ссылкой YouTube Music → сразу проверяем её и запускаем
  /// скачивание в MP3. Для плейлистов и мусорного текста показываем
  /// подсказку и ничего не скачиваем.
  void _handleIncomingLink(String raw) {
    if (!mounted || _handlingIncomingLink) return;

    final link = YoutubeLink.parse(raw);
    if (link == null) {
      showAppSnackBar(
        context,
        'Ссылка не распознана. Нужна ссылка YouTube Music или YouTube.',
        isError: true,
      );
      return;
    }
    if (!link.hasVideo) {
      showAppSnackBar(
        context,
        'Это ссылка на плейлист. Откройте трек и поделитесь ссылкой на него.',
        isError: true,
      );
      return;
    }

    final downloads = _downloadsRef;
    if (downloads != null && downloads.isDownloading) {
      showAppSnackBar(
        context,
        'Уже скачивается «${downloads.task!.track.title}». '
        'Дождитесь окончания.',
        isError: true,
      );
      return;
    }

    _handlingIncomingLink = true;
    unawaited(
      showLinkDownloadSheet(
        context,
        initialUrl: raw,
        autoStart: true,
      ).whenComplete(() => _handlingIncomingLink = false),
    );
  }

  void _showPlayError() {
    final player = _playerRef;
    final message = player?.errorNotifier.value;
    if (message == null) return;
    player!.errorNotifier.value = null; // показать один раз
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2500),
      ),
    );
  }

  void _showDownloadNotice() {
    final downloads = _downloadsRef;
    final notice = downloads?.notice.value;
    if (notice == null) return;
    downloads!.notice.value = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(notice.message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: notice.isError ? 4 : 3),
        backgroundColor: notice.isError ? const Color(0xFF7A2E2E) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                HomeScreen(isActive: _tabIndex == 0),
                const SearchScreen(),
                const LibraryScreen(),
              ],
            ),
          ),
          Selector<PlayerProvider, bool>(
            selector: (_, player) => player.isPreparing,
            builder: (context, preparing, _) => preparing
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.shrink(),
          ),
          const DownloadProgressBanner(),
          const MiniPlayerBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Поиск',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Библиотека',
          ),
        ],
      ),
    );
  }
}
