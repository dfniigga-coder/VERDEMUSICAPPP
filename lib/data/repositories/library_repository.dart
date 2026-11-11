import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// Хранилище библиотеки пользователя: лайки, плейлисты, недавние поиски.
/// Работает поверх shared_preferences, синхронно читает into memory.
class LibraryRepository {
  LibraryRepository(this._prefs);

  final SharedPreferences _prefs;

  final Map<String, Track> _liked = {};
  List<Playlist> _playlists = [];
  List<String> _recentSearches = [];

  // --- Лайки ---------------------------------------------------------------

  List<Track> get likedTracks => List.unmodifiable(_liked.values);

  bool isLiked(Track track) => _liked.containsKey(track.id);

  Future<void> setLiked(Track track, bool liked) async {
    var changed = false;
    if (liked) {
      if (!_liked.containsKey(track.id)) {
        _liked[track.id] = track;
        changed = true;
      }
    } else {
      changed = _liked.remove(track.id) != null;
    }
    if (!changed) return;
    await _saveString(
      AppConstants.likedTracksKey,
      Track.encodeList(_liked.values.toList()),
    );
  }

  // --- Плейлисты -----------------------------------------------------------

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  Playlist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Playlist createPlaylist(String name) {
    final clean = name.trim();
    final playlist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: clean.isEmpty ? 'Новый плейлист' : clean,
    );
    _playlists = [playlist, ..._playlists];
    _savePlaylists();
    return playlist;
  }

  void renamePlaylist(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    _playlists = [
      for (final p in _playlists)
        if (p.id == id) p.copyWith(name: clean) else p,
    ];
    _savePlaylists();
  }

  void deletePlaylist(String id) {
    _playlists = [
      for (final p in _playlists)
        if (p.id != id) p,
    ];
    _savePlaylists();
  }

  /// true, если трек добавлен. false — трек уже был в плейлисте.
  bool addTrackToPlaylist(String playlistId, Track track) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;
    final pl = _playlists[index];
    if (pl.contains(track)) return false;
    _playlists[index] = pl.copyWith(tracks: [...pl.tracks, track]);
    _savePlaylists();
    return true;
  }

  bool removeTrackFromPlaylist(String playlistId, Track track) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;
    final pl = _playlists[index];
    final next = pl.tracks.where((t) => t.id != track.id).toList();
    if (next.length == pl.tracks.length) return false;
    _playlists[index] = pl.copyWith(tracks: next);
    _savePlaylists();
    return true;
  }

  // --- Недавние поиски -----------------------------------------------------

  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  void addRecentSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _recentSearches = [q, ..._recentSearches.where((s) => s != q)];
    if (_recentSearches.length > 8) {
      _recentSearches = _recentSearches.sublist(0, 8);
    }
    _saveString(AppConstants.recentSearchesKey, jsonEncode(_recentSearches));
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = [];
    await _saveString(AppConstants.recentSearchesKey, '[]');
  }

  // --- Загрузка и сохранение ----------------------------------------------

  void load() {
    try {
      final likedRaw = _prefs.getString(AppConstants.likedTracksKey);
      _liked
        ..clear()
        ..addEntries(
          Track.listFromDynamic(likedRaw).map((t) => MapEntry(t.id, t)),
        );

      final plRaw = _prefs.getString(AppConstants.playlistsKey);
      final loaded = <Playlist>[];
      if (plRaw != null && plRaw.isNotEmpty) {
        final decoded = jsonDecode(plRaw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            try {
              loaded.add(Playlist.fromJson(item));
            } catch (_) {
              // пропускаем повреждённый плейлист
            }
          }
        }
      }
      _playlists = loaded
          .where((p) => p.id.isNotEmpty && p.name.trim().isNotEmpty)
          .toList(growable: false);

      final recentRaw = _prefs.getString(AppConstants.recentSearchesKey);
      if (recentRaw != null && recentRaw.isNotEmpty) {
        final decoded = jsonDecode(recentRaw);
        if (decoded is List) {
          _recentSearches = decoded.whereType<String>().toList();
        }
      }
    } on FormatException {
      throw const StorageException();
    } catch (_) {
      // Повреждённые данные не должны ломать приложение.
      _playlists = [];
      _recentSearches = [];
    }
  }

  Future<bool> _saveString(String key, String value) {
    try {
      return _prefs.setString(key, value);
    } catch (_) {
      return Future.value(false);
    }
  }

  Future<void> _savePlaylists() {
    return _saveString(
      AppConstants.playlistsKey,
      jsonEncode(_playlists.map((p) => p.toJson()).toList()),
    );
  }
}
