import 'package:flutter/foundation.dart';

import '../core/errors/app_exceptions.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/music_repository.dart';

/// Поиск по Audius + недавние запросы.
class SearchProvider extends ChangeNotifier {
  SearchProvider(this._musicRepo, this._libraryRepo);

  final MusicRepository _musicRepo;
  final LibraryRepository _libraryRepo;

  int _seq = 0;

  List<Track>? _results;
  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  /// null — поиск ещё не выполнялся / поле очищено.
  List<Track>? get results => _results;

  bool get loading => _loading;

  String? get error => _error;

  String get lastQuery => _lastQuery;

  bool get hasResults => _results != null && _results!.isNotEmpty;

  bool get showRecent => _results == null && _error == null && !_loading;

  List<String> get recentSearches => _libraryRepo.recentSearches;

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      _reset();
      notifyListeners();
      return;
    }

    final seq = ++_seq;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final found = await _musicRepo.search(q);
      if (seq != _seq) return; // устаревший ответ — игнорируем
      _results = found;
      _lastQuery = q;
      _loading = false;
      notifyListeners();
    } on AppException catch (e) {
      if (seq != _seq) return;
      _error = e.message;
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (seq != _seq) return;
      _error = 'Что-то пошло не так. Попробуйте ещё раз.';
      _loading = false;
      notifyListeners();
    }
  }

  void saveRecent(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _libraryRepo.addRecentSearch(q);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    await _libraryRepo.clearRecentSearches();
    notifyListeners();
  }

  void _reset() {
    _results = null;
    _error = null;
    _loading = false;
  }
}
