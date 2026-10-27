import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/bangumi_schedule.dart';
import '../../domain/models/media_item.dart';
import 'endpoints.dart';

class MediaApi {
  MediaApi(this._dio);

  final Dio _dio;

  Future<List<MediaItem>> search(String query) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.search,
        queryParameters: {'q': query},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final results = data['results'];
      if (results is! List) return const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map((item) => MediaItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<MediaItem> detail(MediaItem item) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.detail,
        queryParameters: {'id': item.id, 'source': item.source},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException(ApiErrorKind.business, '详情响应格式不正确');
      }
      final result = data['result'];
      if (result is Map) {
        final json = Map<String, dynamic>.from(result);
        json.putIfAbsent('id', () => data['detailId'] ?? item.id);
        json.putIfAbsent('source', () => item.source);
        json.putIfAbsent('source_name', () => item.sourceName);
        return MediaItem.fromJson(json);
      }
      if (data.containsKey('title') || data.containsKey('vod_name')) {
        return MediaItem.fromJson(data);
      }
      throw const ApiException(ApiErrorKind.business, '未找到该源的详情');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<MediaItem>> recommendations() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.recommendations);
      return _parseLooseList(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<MediaItem>> history() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.playRecords);
      return _parseLooseList(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> savePlayRecord(
    MediaItem item, {
    required int episodeIndex,
    required int playTimeSeconds,
    required int totalTimeSeconds,
  }) async {
    if (item.source.isEmpty || item.id.isEmpty) return;
    try {
      await _dio.post<dynamic>(
        Endpoints.playRecords,
        data: {
          'key': item.storageKey,
          'record': {
            'title': item.title,
            'source_name': item.sourceName,
            'cover': item.poster,
            'index': episodeIndex + 1,
            'total_episodes': item.episodes.isNotEmpty
                ? item.episodes.length
                : item.totalEpisodes,
            'play_time': playTimeSeconds,
            'total_time': totalTimeSeconds,
            'save_time': DateTime.now().millisecondsSinceEpoch,
            'year': item.year,
            'search_title': item.title,
          },
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> deletePlayRecord(MediaItem item) async {
    if (item.source.isEmpty || item.id.isEmpty) return;
    try {
      await _dio.delete<dynamic>(
        Endpoints.playRecords,
        queryParameters: {'key': item.storageKey},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<MediaItem>> favorites() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.favorites);
      return _parseLooseList(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> saveFavorite(MediaItem item) async {
    if (item.source.isEmpty || item.id.isEmpty) return;
    try {
      await _dio.post<dynamic>(
        Endpoints.favorites,
        data: {
          'key': item.storageKey,
          'favorite': {
            'title': item.title,
            'source_name': item.sourceName,
            'cover': item.poster,
            'total_episodes': item.episodes.isNotEmpty
                ? item.episodes.length
                : item.totalEpisodes,
            'save_time': DateTime.now().millisecondsSinceEpoch,
            'year': item.year,
            'search_title': item.title,
          },
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> deleteFavorite(MediaItem item) async {
    if (item.source.isEmpty || item.id.isEmpty) return;
    try {
      await _dio.delete<dynamic>(
        Endpoints.favorites,
        queryParameters: {'key': item.storageKey},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<MediaItem>> bangumi() async {
    final schedule = await bangumiSchedule();
    return schedule.allItems;
  }

  /// 豆瓣推荐（按分类）：`/api/douban/recommends?kind=movie|tv`
  Future<List<MediaItem>> doubanFeed(String kind) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.recommendations,
        queryParameters: {'kind': kind},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final list = data['list'];
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((json) => MediaItem.fromJson(Map<String, dynamic>.from(json)))
          .where((item) => item.title.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// 近期热门（服务端聚合，混合电影与剧集）。
  Future<List<MediaItem>> trending() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.tmdbTrending);
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final list = data['list'];
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((json) => MediaItem.fromJson(Map<String, dynamic>.from(json)))
          .where((item) => item.title.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// 新番时刻表：优先 `/api/bangumi/schedule`，失败时回退 `/api/bangumi/calendar`。
  Future<BangumiSchedule> bangumiSchedule() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.bangumi);
      final parsed = BangumiSchedule.tryParse(response.data);
      if (parsed != null && !parsed.isEmpty) return parsed;
    } on DioException {
      // Fall through to the calendar endpoint.
    }
    try {
      final response = await _dio.get<dynamic>(Endpoints.bangumiCalendar);
      final parsed = BangumiSchedule.tryParse(response.data);
      if (parsed != null) return parsed;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
    return BangumiSchedule.empty();
  }

  List<MediaItem> _parseLooseList(dynamic data) {
    dynamic list = data;
    if (data is Map<String, dynamic>) {
      list = data['results'] ??
          data['list'] ??
          data['data'] ??
          data['items'] ??
          data['favorites'] ??
          data['records'] ??
          data;
    }
    if (list is Map<String, dynamic>) {
      final parsed = <MediaItem>[];
      for (final entry in list.entries) {
        final value = entry.value;
        if (value is Map) {
          final json = Map<String, dynamic>.from(value);
          final parts = entry.key.split('+');
          if (parts.length >= 2) {
            json.putIfAbsent('source', () => parts.first);
            json.putIfAbsent('id', () => parts.sublist(1).join('+'));
          }
          final item = MediaItem.fromJson(json);
          if (item.title.isNotEmpty) parsed.add(item);
        } else if (value is List) {
          for (final element in value.whereType<Map<String, dynamic>>()) {
            final json = Map<String, dynamic>.from(element);
            json.putIfAbsent('weekday', () => entry.key);
            final item = MediaItem.fromJson(json);
            if (item.title.isNotEmpty) parsed.add(item);
          }
        }
      }
      parsed.sort((a, b) => b.saveTime.compareTo(a.saveTime));
      return parsed;
    }
    if (list is! List) return const [];
    final items = list.whereType<Map<String, dynamic>>().map((entry) {
      var json = Map<String, dynamic>.from(entry);
      final nested = json['result'] ?? json['media'] ?? json['item'];
      if (nested is Map) json = Map<String, dynamic>.from(nested);
      return MediaItem.fromJson(json);
    }).where((item) => item.title.isNotEmpty).toList();
    items.sort((a, b) => b.saveTime.compareTo(a.saveTime));
    return items;
  }

  static String buildProxyUrl({
    required String baseUrl,
    required String rawUrl,
    required String source,
    String playbackToken = '',
    bool adblock = true,
    bool proxySegments = false,
  }) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final query = StringBuffer()
      ..write('url=${Uri.encodeComponent(rawUrl)}')
      ..write('&source=${Uri.encodeComponent(source)}')
      ..write('&adblock=$adblock')
      ..write('&proxySegments=$proxySegments');
    if (playbackToken.isNotEmpty) {
      query.write('&token=${Uri.encodeComponent(playbackToken)}');
    }
    return '$base${Endpoints.proxyM3u8}?$query';
  }
}
