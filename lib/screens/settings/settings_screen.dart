import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme/design_tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';

/// Настройки источников поиска.
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
              colors: [AppColors.accentSoft(0.18), AppColors.surfaceRaised],
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentSoft(0.2),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: AppColors.accentBright,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Text(
                    'Deezer, iTunes, Audius, Internet Archive и YouTube работают '
                    'без ключей. Для Jamendo нужен бесплатный client_id, для '
                    'Last.fm — API key. Без ключей эти источники просто '
                    'пропускаются.',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Jamendo client_id'),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'Например: 1234abcd'),
          ),
          const SizedBox(height: 8),
          const _Hint(
            'Ключ можно получить на devportal.jamendo.com. Он хранится только '
            'на устройстве в shared_preferences.',
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Last.fm API key'),
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
          const SizedBox(height: 8),
          const _Hint(
            'Улучшает подборки «Похоже на …»: с ключом похожесть считается '
            'по Last.fm. Без ключа Verde использует связанных исполнителей '
            'Deezer и треки того же артиста. Бесплатный ключ: '
            'last.fm/api/account/create.',
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 19),
            label: const Text('Сохранить'),
          ),
          const SizedBox(height: 26),
          const Divider(),
          const SizedBox(height: 18),
          const _SectionTitle('Что ищем'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: const [
                _SourceRow(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Deezer',
                  subtitle: 'Превью 30 секунд',
                  color: Color(0xFFB06BFF),
                ),
                _SourceRow(
                  icon: Icons.music_note_rounded,
                  title: 'iTunes',
                  subtitle: 'Превью 30 секунд',
                  color: Color(0xFFFF6B81),
                ),
                _SourceRow(
                  icon: Icons.waves_rounded,
                  title: 'Audius',
                  subtitle: 'Полные треки',
                  color: Color(0xFFCC6BFF),
                ),
                _SourceRow(
                  icon: Icons.public_rounded,
                  title: 'Jamendo',
                  subtitle: 'Полные треки (нужен client_id)',
                  color: Color(0xFFFFB35C),
                ),
                _SourceRow(
                  icon: Icons.account_balance_rounded,
                  title: 'Internet Archive',
                  subtitle: 'Полные треки',
                  color: Color(0xFF6FA8FF),
                ),
                _SourceRow(
                  icon: Icons.smart_display_rounded,
                  title: 'YouTube',
                  subtitle: 'Полные треки и скачивание в MP3',
                  color: Color(0xFFFF6B6B),
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
        fontSize: 14,
        fontWeight: FontWeight.w700,
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
        fontSize: 11,
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
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
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
