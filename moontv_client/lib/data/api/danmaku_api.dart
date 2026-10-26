import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/danmaku.dart';
import 'endpoints.dart';

class DanmakuApi {
  DanmakuApi(this._dio);

  final Dio _dio;

  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout}) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.danmakuSearch,
        queryParameters: {'keyword': keyword},
        options: timeout == null ? null : Options(receiveTimeout: timeout),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final animes = data['animes'];
      if (animes is! List) return const [];
      return animes
          .whereType<Map<String, dynamic>>()
          .map((item) => DanmakuAnime.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.animeId.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout}) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.danmakuEpisodes,
        queryParameters: {'animeId': animeId},
        options: timeout == null ? null : Options(receiveTimeout: timeout),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final bangumi = data['bangumi'];
      final episodes = bangumi is Map ? bangumi['episodes'] : null;
      if (episodes is! List) return const [];
      return episodes
          .whereType<Map<String, dynamic>>()
          .map((item) => DanmakuEpisode.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.episodeId.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<DanmakuComment>> comments(
    String episodeId, {
    required String source,
    Duration? timeout,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.danmakuComment,
        queryParameters: {'episodeId': episodeId},
        options: timeout == null ? null : Options(receiveTimeout: timeout),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final comments = data['comments'];
        if (comments is! List) return const [];
        return comments.whereType<Map<String, dynamic>>().map((item) {
          return DanmakuComment.fromJson(
            Map<String, dynamic>.from(item),
            source: source,
          );
        }).where((item) => item.text.isNotEmpty).toList();
      }
      if (data is String) return _parseXml(data, source);
      return const [];
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  List<DanmakuComment> _parseXml(String xml, String source) {
    final pattern = RegExp('<d\\s+p="([^"]*)"[^>]*>([\\s\\S]*?)</d>');
    return pattern.allMatches(xml).map((match) {
      final text = match.group(2)!
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&amp;', '&');
      return DanmakuComment.parse(p: match.group(1)!, text: text, source: source);
    }).where((item) => item.text.isNotEmpty).toList();
  }
}
