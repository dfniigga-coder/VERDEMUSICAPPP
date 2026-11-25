import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/recommendation_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';

/// Настройки источников поиска и рекомендаций в стиле iOS / Apple Music.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _lastFmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final prefs = context.read<SharedPreferences>();
    _controller.text = prefs.getString(AppConstants.jamendoClientIdKey) ?? '';
    _lastFmController.text =
        prefs.getString(AppConstants.lastFmApiKeyKey) ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    _lastFmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final prefs = context.read<SharedPreferences>();
    final jamendo = _controller.text.trim();
    final lastFm = _lastFmController.text.trim();
    try {
      await _saveKey(prefs, AppConstants.jamendoClientIdKey, jamendo);
      await _saveKey(prefs, AppConstants.lastFmApiKeyKey, lastFm);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Не удалось сохранить ключи', isError: true);
      return;
    }
    if (!mounted) return;
    showAppSnackBar(context, 'Ключи сохранены');
  }

  Future<void> _saveKey(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Очистить историю рекомендаций?',
      message:
          'История прослушиваний и статистика «Мой вайб» будут очищены. '
          'Лайки и плейлисты сохранятся.',
      confirmLabel: 'Очистить',
    );
    if (!ok || !mounted) return;
    await context.read<RecommendationService>().clearHistory();
    if (!mounted) return;
    showAppSnackBar(context, 'История прослушиваний очищена');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, AppSpacing.pageBottom),
        children: [
          AppCard(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.forestMid.withValues(alpha: 0.45),
                AppColors.surfaceRaised,
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentSoft(0.22),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: AppColors.accentBright,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Поиск и воспроизведение работают напрямую через YouTube Music '
                    '(только полные треки, без 30-секундных превью). При скачивании '
                    'MP3 лирика из LRCLIB сохраняется автоматически в .lrc и теги.',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('API-ключи источников'),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Jamendo client_id',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(hintText: 'Например: 1234abcd'),
                ),
                const SizedBox(height: 6),
                const _Hint(
                  'Ключ с devportal.jamendo.com. Хранится только на устройстве.',
                ),
                const SizedBox(height: 18),
                const Text(
                  'Last.fm API key',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastFmController,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'Например: 0123456789abcdef0123456789abcdef',
                  ),
                ),
                const SizedBox(height: 6),
                const _Hint(
                  'Улучшает подборки «Похоже на …» и волну трека. Бесплатный ключ: '
                  'last.fm/api/account/create.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: const Text('Сохранить ключи'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('Рекомендации и статистика'),
          const SizedBox(height: 10),
          AppCard(
            onTap: _clearHistory,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.error.withValues(alpha: 0.14),
                  ),
                  child: const Icon(
                    Icons.delete_sweep_outlined,
                    size: 19,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Очистить историю прослушиваний',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Сбросит ленту «Недавние», «На повторе» и «Мой вайб»',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('Источник музыки и лирики'),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: const [
                _SourceRow(
                  icon: Icons.smart_display_rounded,
                  title: 'YouTube Music',
                  subtitle: 'Только полные треки и скачивание в MP3 (192 кбит/с)',
                  color: Color(0xFFFF6B6B),
                ),
                _SourceRow(
                  icon: Icons.lyrics_rounded,
                  title: 'LRCLIB',
                  subtitle: 'Синхронная лирика (.lrc и ID3-тег) для офлайн-режима',
                  color: AppColors.accentBright,
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: AppColors.text,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11.5,
        height: 1.45,
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool showDivider;

  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}
