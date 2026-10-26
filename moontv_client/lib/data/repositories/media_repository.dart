import '../../domain/models/media_item.dart';
import '../api/media_api.dart';

class MediaRepository {
  MediaRepository(this._api);

  final MediaApi _api;
  final _details = <String, _TimedDetail>{};
  final _searches = <String, _TimedSearch>{};

  Future<List<MediaItem>> search(String query) async {
    final key = query.trim();
    final cached = _searches[key];
    if (cached != null && cached.age < const Duration(minutes: 5)) {
      return cached.items;
    }
    final result = await _api.search(key);
    _searches[key] = _TimedSearch(result);
    return result;
  }

  Future<MediaItem> detail(MediaItem item, {bool force = false}) async {
    final key = '${item.source}:${item.id}';
    final cached = _details[key];
    if (!force && cached != null && cached.age < const Duration(hours: 24)) {
      return cached.item;
    }
    final result = await _api.detail(item);
    final merged = result.copyWith(
      lastEpisodeIndex: item.lastEpisodeIndex,
      playTimeSeconds: item.playTimeSeconds,
      totalTimeSeconds: item.totalTimeSeconds,
      saveTime: item.saveTime,
    );
    _details[key] = _TimedDetail(merged);
    return merged;
  }

  Future<List<MediaItem>> recommendations() => _api.recommendations();
  Future<List<MediaItem>> history() => _api.history();
  Future<List<MediaItem>> favorites() => _api.favorites();
  Future<List<MediaItem>> bangumi() => _api.bangumi();

  Future<void> savePlayRecord(
    MediaItem item, {
    required int episodeIndex,
    required int playTimeSeconds,
    required int totalTimeSeconds,
  }) =>
      _api.savePlayRecord(
        item,
        episodeIndex: episodeIndex,
        playTimeSeconds: playTimeSeconds,
        totalTimeSeconds: totalTimeSeconds,
      );

  Future<void> deletePlayRecord(MediaItem item) => _api.deletePlayRecord(item);
  Future<void> saveFavorite(MediaItem item) => _api.saveFavorite(item);
  Future<void> deleteFavorite(MediaItem item) => _api.deleteFavorite(item);

  Future<bool> isFavorite(MediaItem item) async {
    if (item.source.isEmpty || item.id.isEmpty) return false;
    final list = await _api.favorites();
    return list.any((entry) => entry.storageKey == item.storageKey);
  }
}

class _TimedDetail {
  _TimedDetail(this.item) : createdAt = DateTime.now();
  final MediaItem item;
  final DateTime createdAt;
  Duration get age => DateTime.now().difference(createdAt);
}

class _TimedSearch {
  _TimedSearch(this.items) : createdAt = DateTime.now();
  final List<MediaItem> items;
  final DateTime createdAt;
  Duration get age => DateTime.now().difference(createdAt);
}
