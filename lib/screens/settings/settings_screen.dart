import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Настройки источников поиска.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final prefs = context.read<SharedPreferences>();
    _controller.text = prefs.getString(AppConstants.jamendoClientIdKey) ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final prefs = context.read<SharedPreferences>();
    final value = _controller.text.trim();
    try {
      if (value.isEmpty) {
        await prefs.remove(AppConstants.jamendoClientIdKey);
      } else {
        await prefs.setString(AppConstants.jamendoClientIdKey, value);
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Не удалось сохранить ключ', isError: true);
      return;
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      value.isEmpty ? 'Ключ Jamendo удалён' : 'Ключ Jamendo сохранён',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Источники поиска',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Deezer, iTunes, Audius и Internet Archive работают без ключей. '
            'Для Jamendo нужен бесплатный client_id — без него источник '
            'автоматически пропускается.',
            style: TextStyle(color: AppTheme.textDim, height: 1.45),
          ),
          const SizedBox(height: 24),
          const Text(
            'Jamendo client_id',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'Например: 1234abcd'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
          const SizedBox(height: 10),
          const Text(
            'Ключ можно получить на devportal.jamendo.com. '
            'Он хранится только на устройстве в shared_preferences.',
            style: TextStyle(
              color: AppTheme.textDim,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Что ищем', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const _SourceRow(
            icon: Icons.graphic_eq,
            title: 'Deezer',
            subtitle: 'Превью 30 секунд',
          ),
          const _SourceRow(
            icon: Icons.music_note,
            title: 'iTunes',
            subtitle: 'Превью 30 секунд',
          ),
          const _SourceRow(
            icon: Icons.waves,
            title: 'Audius',
            subtitle: 'Полные треки',
          ),
          const _SourceRow(
            icon: Icons.public,
            title: 'Jamendo',
            subtitle: 'Полные треки (нужен client_id)',
          ),
          const _SourceRow(
            icon: Icons.account_balance,
            title: 'Internet Archive',
            subtitle: 'Полные треки',
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;

  final String title;

  final String subtitle;

  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.textDim, size: 22),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
      ),
    );
  }
}
