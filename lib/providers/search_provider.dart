import 'package:flutter/foundation.dart';

import '../core/errors/app_exceptions.dart';
import '../data/api/search_api.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';

/// Поиск полных треков из YouTube Music + недавние запросы.
class SearchProvider extends ChangeNotifier {
  SearchProvider(this._searchApi, this._libraryRepo);

  final SearchApi _searchApi;
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

  List<Track> get visibleResults => _results ?? const [];

  bool get hasResults => visibleResults.isNotEmpty;

  bool get hasAnyResults => _results != null && _results!.isNotEmpty;

  String get emptySubtitle =>
      'Попробуйте уточнить название трека или исполнителя';

  bool get showRecent => _results == null && _error == null && !_loading;

  List<String> get recentSearches => _libraryRepo.recentSearches;

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      _seq++;
      _reset();
      notifyListeners();
      return;
    }

    final seq = ++_seq;
    _loading = true;
    _error = null;
    _lastQuery = q;
    notifyListeners();

    try {
      final outcome = await _searchApi.searchSources(
        q,
        onPartial: (partial) {
          if (seq != _seq) return;
          if (partial.tracks.isEmpty) return;

          _results = partial.tracks;
          _error = null;
          notifyListeners();
        },
      );
      if (seq != _seq) return;

      _results = outcome.tracks;
      _loading = false;

      if (outcome.tracks.isEmpty && outcome.allFailed) {
        _error = outcome.noNetwork
            ? const NetworkException().message
            : 'Не удалось получить результаты с YouTube Music. '
                  'Проверьте соединение и попробуйте ещё раз.';
      }
      notifyListeners();
    } on AppException catch (e) {
      if (seq != _seq) return;
      _error = e.message;
      _loading = false;
      notifyListeners();
    } catch (_) {
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
    _lastQuery = '';
  }
}
