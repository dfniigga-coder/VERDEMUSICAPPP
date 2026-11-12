/// Текст трека из LRCLIB.
///
/// Сервис отдаёт либо обычный текст, либо LRC с таймкодами. Таймкоды
/// нужны, чтобы подсвечивать текущую строку и автоматически
/// прокручивать текст во время воспроизведения.
class LyricLine {
  const LyricLine({required this.time, required this.text});

  /// Момент, с которого начинается строка.
  final Duration time;

  final String text;
}

class Lyrics {
  const Lyrics({
    this.title,
    this.artist,
    this.plainText,
    this.lines = const <LyricLine>[],
    this.instrumental = false,
  });

  final String? title;

  final String? artist;

  /// Обычный текст без таймкодов.
  final String? plainText;

  /// Строки с таймкодами; пустой список, если синхронизации нет.
  final List<LyricLine> lines;

  final bool instrumental;

  bool get hasSynced => lines.isNotEmpty;

  bool get hasText =>
      (plainText?.trim().isNotEmpty ?? false) ||
      lines.any((line) => line.text.trim().isNotEmpty);

  bool get hasContent => instrumental || hasText;

  factory Lyrics.fromJson(Map<String, dynamic> json) {
    final syncedRaw = json['syncedLyrics'];
    final plainRaw = json['plainLyrics'];
    final synced = syncedRaw is String
        ? parseLrc(syncedRaw)
        : const <LyricLine>[];
    final plain = plainRaw is String && plainRaw.trim().isNotEmpty
        ? plainRaw.trim()
        : null;

    return Lyrics(
      title: _string(json['trackName']),
      artist: _string(json['artistName']),
      plainText: plain,
      lines: synced,
      instrumental: json['instrumental'] == true,
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static final RegExp _timestamp = RegExp(
    r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );

  /// Разбирает LRC-строки вида `[00:12.34]Текст`.
  ///
  /// Одна строка может содержать несколько таймкодов — тогда текст
  /// повторяется для каждого времени.
  static List<LyricLine> parseLrc(String source) {
    final result = <LyricLine>[];

    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final matches = _timestamp.allMatches(raw);
      if (matches.isEmpty) continue;

      final text = raw.replaceAll(_timestamp, '').trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '');
        final seconds = int.tryParse(match.group(2) ?? '');
        if (minutes == null || seconds == null) continue;

        final fraction = match.group(3);
        var milliseconds = 0;
        if (fraction != null && fraction.isNotEmpty) {
          final padded = fraction.padRight(3, '0').substring(0, 3);
          milliseconds = int.tryParse(padded) ?? 0;
        }

        result.add(
          LyricLine(
            time: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text: text,
          ),
        );
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}
