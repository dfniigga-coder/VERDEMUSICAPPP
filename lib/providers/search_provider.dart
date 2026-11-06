import 'package:flutter/foundation.dart';

import '../core/errors/app_exceptions.dart';
import '../data/api/search_api.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';

/// Фильтр результатов поиска по длине трека.
enum SearchFilter { all, full, preview }

extension SearchFilterLabel on SearchFilter {
  String get label {
    switch (this) {
      case SearchFilter.all:
        return 'Все';
      case SearchFilter.full:
        return 'Полные';
      case SearchFilter.preview:
        return 'Превью';
    }
  }
}

/// Мультиисточниковый поиск + недавние запросы.
class SearchProvider extends ChangeNotifier {
  SearchProvider(this._searchApi, this._libraryRepo);

  final SearchApi _searchApi;
  final LibraryRepository _libraryRepo;

  int _seq = 0;

  List<Track>? _results;
  bool _loading = false;
  String? _error;
  String _lastQuery = '';
  SearchFilter _filter = SearchFilter.all;

  /// null — поиск ещё не выполнялся / поле очищено.
  List<Track>? get results => _results;

  bool get loading => _loading;

  String? get error => _error;

  String get lastQuery => _lastQuery;

  SearchFilter get filter => _filter;

  List<Track> get visibleResults {
    final all = _results;
    if (all == null) return const [];
    switch (_filter) {
      case SearchFilter.all:
        return all;
      case SearchFilter.full:
        return [
          for (final track in all)
            if (!track.isPreview) track,
        ];
      case SearchFilter.preview:
        return [
          for (final track in all)
            if (track.isPreview) track,
        ];
    }
  }

  bool get hasResults => visibleResults.isNotEmpty;

  bool get hasAnyResults => _results != null && _results!.isNotEmpty;

  String get emptySubtitle {
    switch (_filter) {
      case SearchFilter.all:
        return 'Попробуйте другой запрос или проверьте источники';
      case SearchFilter.full:
        return 'Полных треков по этому запросу нет';
      case SearchFilter.preview:
        return 'Превью по этому запросу нет';
    }
  }

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
    _filter = SearchFilter.all;
    notifyListeners();

    try {
      final outcome = await _searchApi.search(q);
      if (seq != _seq) return; // устаревший ответ — игнорируем

      _results = outcome.tracks;
      _loading = false;

      if (outcome.tracks.isEmpty && outcome.allFailed) {
        _error = outcome.noNetwork
            ? const NetworkException().message
            : 'Не удалось получить результаты. '
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

  void setFilter(SearchFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    notifyListeners();
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
    _filter = SearchFilter.all;
    _lastQuery = '';
  }
}
