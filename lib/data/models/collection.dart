/// Подборка (плейлист Audius) для отображения на главной.
class Collection {
  final String id;

  /// Название плейлиста на Audius.
  final String title;
  final String? subtitle;
  final String? artworkUrl;

  const Collection({
    required this.id,
    required this.title,
    this.subtitle,
    this.artworkUrl,
  });
}
