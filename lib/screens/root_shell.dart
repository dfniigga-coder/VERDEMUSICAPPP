import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/design_tokens.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../services/incoming_link_service.dart';
import '../services/youtube_link.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'search/search_screen.dart';
import '../widgets/common.dart';
import '../widgets/download_sheet.dart';
import '../widgets/glass_panel.dart';
import '../widgets/link_download_sheet.dart';
import '../widgets/mini_player.dart';
import '../widgets/pressable_scale.dart';

/// Каркас: 3 таба (IndexedStack сохраняет состояние) и плавающая
/// нижняя навигация. Мини-плеер и прогресс скачивания живут над ней.
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
    _downloadsRef?.notice.addListener(_showDownloadNotice);

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
    showAppSnackBar(context, message, isError: true);
  }

  void _showDownloadNotice() {
    final downloads = _downloadsRef;
    final notice = downloads?.notice.value;
    if (notice == null) return;
    downloads?.notice.value = null;
    if (!mounted) return;
    showAppSnackBar(context, notice.message, isError: notice.isError);
  }

  void _selectTab(int index) {
    if (index == _tabIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                HomeScreen(
                  isActive: _tabIndex == 0,
                  onOpenLibrary: () => _selectTab(2),
                  onOpenSearch: () => _selectTab(1),
                ),
                const SearchScreen(),
                const LibraryScreen(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DownloadProgressBanner(),
                  const MiniPlayerBar(),
                  const SizedBox(height: 8),
                  _FloatingNav(selectedIndex: _tabIndex, onSelect: _selectTab),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Плавающая навигация-капсула с blur и зелёной пилюлей активного таба.
class _FloatingNav extends StatelessWidget {
  final int selectedIndex;

  final ValueChanged<int> onSelect;

  const _FloatingNav({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blur: 22,
      color: AppColors.surfaceRaised.withValues(alpha: 0.9),
      borderRadius: AppRadii.xlAll,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Главная',
            selected: selectedIndex == 0,
            onTap: () => onSelect(0),
          ),
          _NavItem(
            icon: Icons.search_rounded,
            label: 'Поиск',
            selected: selectedIndex == 1,
            onTap: () => onSelect(1),
          ),
          _NavItem(
            icon: Icons.library_music_rounded,
            label: 'Библиотека',
            selected: selectedIndex == 2,
            onTap: () => onSelect(2),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;

  final String label;

  final bool selected;

  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: AnimatedContainer(
              duration: AppDurations.normal,
              curve: Curves.easeOutCubic,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accentSoft(0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected
                        ? AppColors.accentBright
                        : AppColors.textDim,
                  ),
                  if (selected) ...[
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentBright,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
