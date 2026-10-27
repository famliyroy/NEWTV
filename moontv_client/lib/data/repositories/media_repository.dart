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

  static const _playRecordTtl = Duration(minutes: 5);

  Map<String, MediaItem>? _playRecords;
  DateTime _playRecordsAge = DateTime.fromMillisecondsSinceEpoch(0);

  /// 播放记录索引（`source+id` → 记录）。
  ///
  /// ⚠️ 后端 `GET /api/playrecords?key=` 是「删除该条记录」的语义，
  /// 因此这里**只能全量拉取后本地匹配**，绝不能带 key 去查。
  Future<Map<String, MediaItem>> playRecordMap({bool force = false}) async {
    final fresh = DateTime.now().difference(_playRecordsAge) < _playRecordTtl;
    if (!force && _playRecords != null && fresh) return _playRecords!;
    try {
      final list = await _api.history();
      final map = <String, MediaItem>{};
      for (final item in list) {
        if (item.source.isEmpty || item.id.isEmpty) continue;
        map[item.storageKey] = item;
      }
      _playRecords = map;
      _playRecordsAge = DateTime.now();
      return map;
    } on Object {
      // 拉取失败退回旧缓存：续播提示属于增强信息，不该打断播放。
      return _playRecords ?? const {};
    }
  }

  /// 单条播放记录（缓存未命中时返回 null）。
  Future<MediaItem?> playRecordFor(MediaItem item) async {
    if (item.source.isEmpty || item.id.isEmpty) return null;
    final map = await playRecordMap();
    return map[item.storageKey];
  }

  Future<void> invalidatePlayRecords() {
    _playRecordsAge = DateTime.fromMillisecondsSinceEpoch(0);
    return Future<void>.value();
  }

  Future<void> savePlayRecord(
    MediaItem item, {
    required int episodeIndex,
    required int playTimeSeconds,
    required int totalTimeSeconds,
  }) async {
    await _api.savePlayRecord(
      item,
      episodeIndex: episodeIndex,
      playTimeSeconds: playTimeSeconds,
      totalTimeSeconds: totalTimeSeconds,
    );
    // 同步本地索引：刚播完就回详情页时能立刻看到新进度，不必等 5 分钟 TTL。
    final map = _playRecords;
    if (map != null && item.source.isNotEmpty && item.id.isNotEmpty) {
      map[item.storageKey] = item.copyWith(
        lastEpisodeIndex: episodeIndex,
        playTimeSeconds: playTimeSeconds,
        totalTimeSeconds: totalTimeSeconds,
        saveTime: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> deletePlayRecord(MediaItem item) async {
    await _api.deletePlayRecord(item);
    _playRecords?.remove(item.storageKey);
  }

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
