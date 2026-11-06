/// Утилиты форматирования для UI.

String _pad2(int n) => n.toString().padLeft(2, '0');

/// Время в формате «3:25», «1:03:02», «–:–» если неизвестно.
String formatDuration(Duration? d) {
  if (d == null) return '–:–';
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h:${_pad2(m)}:${_pad2(s)}';
  return '$m:${_pad2(s)}';
}

/// «12 треков», «3 трека», «1 трек», «Подборка» если количество неизвестно.
String trackCountLabel(int? count) {
  if (count == null || count <= 0) return 'Подборка';
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return '$count трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count трека';
  }
  return '$count треков';
}

/// Первая заглавная буква для аватара-заглушки.
String firstLetter(String text) {
  final t = text.trim();
  if (t.isEmpty) return '?';
  return t[0].toUpperCase();
}
