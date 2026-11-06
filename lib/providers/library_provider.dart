import 'package:flutter/foundation.dart';

import '../data/models/playlist.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';

/// Лайки и плейлисты. Все изменения идут через [LibraryRepository]
/// (shared_preferences) и сразу отражаются в UI.
class LibraryProvider extends ChangeNotifier {
  LibraryProvider(this._repo) {
    _sync();
  }

  final LibraryRepository _repo;

  List<Track> _liked = const [];
  List<Playlist> _playlists = const [];
  List<String> _recentSearches = const [];

  List<Track> get likedTracks => _liked;

  List<Playlist> get playlists => _playlists;

  List<String> get recentSearches => _recentSearches;

  bool isLiked(Track track) => _repo.isLiked(track);

  Future<void> toggleLike(Track track) async {
    await _repo.setLiked(track, !_repo.isLiked(track));
    _sync();
  }

  Playlist createPlaylist(String name) {
    final playlist = _repo.createPlaylist(name);
    _sync();
    return playlist;
  }

  void renamePlaylist(String id, String name) {
    _repo.renamePlaylist(id, name);
    _sync();
  }

  void deletePlaylist(String id) {
    _repo.deletePlaylist(id);
    _sync();
  }

  /// true — добавлен, false — уже был в плейлисте.
  bool addTrackToPlaylist(String playlistId, Track track) {
    final added = _repo.addTrackToPlaylist(playlistId, track);
    if (added) _sync();
    return added;
  }

  void removeTrackFromPlaylist(String playlistId, Track track) {
    _repo.removeTrackFromPlaylist(playlistId, track);
    _sync();
  }

  Playlist? playlistById(String id) => _repo.playlistById(id);

  // --- Недавние поиски -----------------------------------------------------

  void addRecentSearch(String query) {
    _repo.addRecentSearch(query);
    _sync();
  }

  Future<void> clearRecentSearches() async {
    await _repo.clearRecentSearches();
    _sync();
  }

  void _sync() {
    _liked = _repo.likedTracks;
    _playlists = _repo.playlists;
    _recentSearches = _repo.recentSearches;
    notifyListeners();
  }
}
