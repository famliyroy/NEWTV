import '../../domain/models/bangumi_schedule.dart';
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
    // 部分片源的详情接口会返回空标题、站点 logo 作为海报、空简介，
    // 此时回退到搜索结果的元数据，避免详情页出现「无标题 + unknown」。
    final merged = result.copyWith(
      title: result.title.trim().isEmpty ? item.title : result.title,
      poster: _isUsablePoster(result.poster) ? result.poster : item.poster,
      description:
          result.description.trim().isEmpty ? item.description : result.description,
      year: _isUsableYear(result.year) ? result.year : item.year,
      typeName: result.typeName.trim().isEmpty ? item.typeName : result.typeName,
      remarks: result.remarks.trim().isEmpty ? item.remarks : result.remarks,
      doubanId: result.doubanId.isEmpty ? item.doubanId : result.doubanId,
      episodes: result.episodes.isEmpty ? item.episodes : result.episodes,
      episodeTitles:
          result.episodeTitles.isEmpty ? item.episodeTitles : result.episodeTitles,
      lastEpisodeIndex: item.lastEpisodeIndex,
      playTimeSeconds: item.playTimeSeconds,
      totalTimeSeconds: item.totalTimeSeconds,
      saveTime: item.saveTime,
    );
    _details[key] = _TimedDetail(merged);
    return merged;
  }

  static bool _isUsableYear(String value) {
    final year = value.trim();
    return year.isNotEmpty &&
        year.toLowerCase() != 'unknown' &&
        RegExp(r'\d{4}').hasMatch(year);
  }

  /// 过滤站点 logo 一类的占位海报。
  static bool _isUsablePoster(String value) {
    final poster = value.trim();
    if (poster.isEmpty) return false;
    final lower = poster.toLowerCase();
    return !lower.contains('/static/images/logo') &&
        !lower.contains('logo.jpg') &&
        !lower.contains('logo.png');
  }

  Future<List<MediaItem>> recommendations() => _api.doubanFeed('movie');

  Future<List<MediaItem>> discoverFeed(String kind) async {
    final key = 'feed:$kind';
    final cached = _searches[key];
    if (cached != null && cached.age < const Duration(minutes: 10)) {
      return cached.items;
    }
    final result = await _api.doubanFeed(kind);
    _searches[key] = _TimedSearch(result);
    return result;
  }

  Future<List<MediaItem>> trending() async {
    const key = 'feed:trending';
    final cached = _searches[key];
    if (cached != null && cached.age < const Duration(minutes: 10)) {
      return cached.items;
    }
    final result = await _api.trending();
    _searches[key] = _TimedSearch(result);
    return result;
  }

  Future<BangumiSchedule> bangumiSchedule({bool force = false}) async {
    if (!force &&
        _schedule != null &&
        DateTime.now().difference(_scheduleAge) < const Duration(hours: 6)) {
      return _schedule!;
    }
    final result = await _api.bangumiSchedule();
    _schedule = result;
    _scheduleAge = DateTime.now();
    return result;
  }

  BangumiSchedule? _schedule;
  DateTime _scheduleAge = DateTime.fromMillisecondsSinceEpoch(0);

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
