import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'search/search_screen.dart';
import '../widgets/download_sheet.dart';
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

  @override
  void initState() {
    super.initState();
    // Показываем снекбары об ошибках воспроизведения в любом табе.
    _playerRef = context.read<PlayerProvider>();
    _playerRef!.errorNotifier.addListener(_showPlayError);
    // И о завершении скачивания — тоже из любого таба.
    _downloadsRef = context.read<DownloadProvider>();
    _downloadsRef!.notice.addListener(_showDownloadNotice);
  }

  @override
  void dispose() {
    _playerRef?.errorNotifier.removeListener(_showPlayError);
    _downloadsRef?.notice.removeListener(_showDownloadNotice);
    super.dispose();
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
