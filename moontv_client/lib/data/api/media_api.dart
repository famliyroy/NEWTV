import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
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
      final response = await _dio.get<dynamic>(Endpoints.searchHistory);
      return _parseLooseList(response.data);
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

  Future<List<MediaItem>> bangumi() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.bangumi);
      return _parseLooseList(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  List<MediaItem> _parseLooseList(dynamic data) {
    dynamic list = data;
    if (data is Map<String, dynamic>) {
      list = data['results'] ??
          data['list'] ??
          data['data'] ??
          data['items'] ??
          data['favorites'];
    }
    if (list is Map<String, dynamic>) list = list.values.toList();
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map((entry) {
      var json = Map<String, dynamic>.from(entry);
      final nested = json['result'] ?? json['media'] ?? json['item'];
      if (nested is Map) json = Map<String, dynamic>.from(nested);
      return MediaItem.fromJson(json);
    }).where((item) => item.title.isNotEmpty).toList();
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
