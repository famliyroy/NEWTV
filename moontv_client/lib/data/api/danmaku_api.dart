import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/config/app_settings.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/danmaku.dart';
import 'endpoints.dart';

/// 弹幕数据源抽象：MoonTVPlus 后端与自建 LogVar API 实现同一套端点语义。
abstract class DanmakuSource {
  /// 是否由客户端做「多源聚合」。LogVar 服务本身已聚合 dandan/animeko 等来源，
  /// 再叠加客户端聚合只会重复请求并触发 429。
  bool get aggregates;

  /// 当前数据源的可读描述，用于弹幕设置面板展示。
  String get description => aggregates ? 'MoonTVPlus 聚合' : '自定义弹幕源';

  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout});

  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout});

  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    required String source,
    Duration? timeout,
  });
}

/// MoonTVPlus 后端链路（`/api/danmaku/*`）。
class DanmakuApi implements DanmakuSource {
  DanmakuApi(this._dio);

  final Dio _dio;

  @override
  bool get aggregates => true;

  @override
  String get description => 'MoonTVPlus 聚合';

  @override
  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout}) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.danmakuSearch,
        queryParameters: {'keyword': keyword},
        options: timeout == null ? null : Options(receiveTimeout: timeout),
      );
      return _parseAnimes(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  @override
  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout}) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.danmakuEpisodes,
        queryParameters: {'animeId': animeId},
        options: timeout == null ? null : Options(receiveTimeout: timeout),
      );
      return _parseEpisodes(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  @override
  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    required String source,
    Duration? timeout,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        Endpoints.danmakuComment,
        queryParameters: {'episodeId': episode.episodeId},
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

/// 自建 LogVar 弹幕 API（NipaPlay 配套，dandanplay 兼容风格）。
///
/// 端点：
/// - `GET {base}/api/v2/search/anime?keyword=`
/// - `GET {base}/api/v2/bangumi/{animeId}`
/// - `GET {base}/api/v2/comment?url=<完整 http(s) 地址>&withRelated=true&chConvert=1`
///
/// 服务端有 429 限流，所有请求串行化并保证间隔 ≥1s，失败按指数退避重试。
class LogVarDanmakuApi implements DanmakuSource {
  LogVarDanmakuApi(this._dio, this.baseUrl);

  static const minRequestGap = Duration(milliseconds: 1100);

  final Dio _dio;
  final String baseUrl;
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _chain = Future.value();

  @override
  bool get aggregates => false;

  @override
  String get description {
    final uri = Uri.tryParse(_base);
    final host = uri == null
        ? _base
        : uri.hasPort
            ? '${uri.host}:${uri.port}'
            : uri.host;
    return '自定义 LogVar ($host)';
  }

  String get _base {
    var value = baseUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  @override
  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout}) async {
    final data = await _getJson(
      '/api/v2/search/anime',
      query: {'keyword': keyword},
      timeout: timeout,
    );
    return _parseAnimes(data);
  }

  @override
  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout}) async {
    final data = await _getJson(
      '/api/v2/bangumi/${Uri.encodeComponent(animeId)}',
      timeout: timeout,
    );
    return _parseEpisodes(data);
  }

  @override
  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    required String source,
    Duration? timeout,
  }) async {
    // LogVar 的 comment 端点要求 url 是完整 http(s) 地址，
    // 传 episodeId 会返回 `Invalid url format`。
    final target = episode.url.trim();
    if (target.isEmpty || !target.startsWith('http')) return const [];
    final data = await _getJson(
      '/api/v2/comment',
      query: {'url': target, 'withRelated': 'true', 'chConvert': '1'},
      timeout: timeout,
    );
    return parseLogVarComments(data, source: source);
  }

  Future<dynamic> _getJson(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final url = '$_base$path';
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _serialized(() {
          return _dio.get<dynamic>(
            url,
            queryParameters: query,
            options: Options(
              receiveTimeout: timeout ?? const Duration(seconds: 20),
              sendTimeout: timeout ?? const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 500,
            ),
          );
        });
        final status = response.statusCode ?? 0;
        if (status == 429) {
          lastError = const ApiException(
            ApiErrorKind.rateLimited,
            '弹幕服务限流，请稍后再试',
            statusCode: 429,
          );
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        if (status >= 400) {
          throw ApiException(
            ApiErrorKind.server,
            '弹幕服务返回错误（HTTP $status）',
            statusCode: status,
          );
        }
        final data = response.data;
        if (data is String && data.isNotEmpty) {
          try {
            return jsonDecode(data);
          } on FormatException {
            throw const ApiException(ApiErrorKind.business, '弹幕服务返回了非 JSON 数据');
          }
        }
        return data;
      } on ApiException catch (error) {
        lastError = error;
        if (error.kind != ApiErrorKind.rateLimited || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      } on DioException catch (error) {
        lastError = ApiException.from(error);
        if (attempt >= 2) throw lastError;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw lastError ?? const ApiException(ApiErrorKind.business, '弹幕服务暂时不可用');
  }

  /// 串行执行请求，保证相邻两次请求间隔不少于 [minRequestGap]。
  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _chain;
    final completer = Completer<void>();
    _chain = completer.future;
    await previous;
    try {
      final elapsed = DateTime.now().difference(_lastRequestAt);
      if (elapsed < minRequestGap) {
        await Future<void>.delayed(minRequestGap - elapsed);
      }
      return await action();
    } finally {
      _lastRequestAt = DateTime.now();
      if (!completer.isCompleted) completer.complete();
    }
  }
}

List<DanmakuAnime> _parseAnimes(dynamic data) {
  if (data is! Map) return const [];
  final animes = data['animes'];
  if (animes is! List) return const [];
  return animes
      .whereType<Map<String, dynamic>>()
      .map((item) => DanmakuAnime.fromJson(Map<String, dynamic>.from(item)))
      .where((item) => item.animeId.isNotEmpty)
      .toList();
}

List<DanmakuEpisode> _parseEpisodes(dynamic data) {
  if (data is! Map) return const [];
  final bangumi = data['bangumi'];
  final episodes = bangumi is Map ? bangumi['episodes'] : null;
  if (episodes is! List) return const [];
  return episodes
      .whereType<Map<String, dynamic>>()
      .map((item) => DanmakuEpisode.fromJson(Map<String, dynamic>.from(item)))
      .where((item) => item.episodeId.isNotEmpty)
      .toList();
}

/// 解析 LogVar 的 comment 响应。
///
/// 该服务的 `p` 只有 4 段：`时间,模式,颜色,[弹幕池]`，
/// 与 dandanplay 标准的 `时间,模式,字号,颜色,时间戳,池,用户,行号` 不同，
/// 直接套用通用解析会把颜色当成字号、把池当成颜色。
List<DanmakuComment> parseLogVarComments(dynamic data, {required String source}) {
  if (data is! Map) return const [];
  final comments = data['comments'];
  if (comments is! List) return const [];
  final result = <DanmakuComment>[];
  for (final raw in comments) {
    if (raw is! Map) continue;
    final text = '${raw['m'] ?? raw['Text'] ?? ''}'.trim();
    if (text.isEmpty) continue;
    final p = '${raw['p'] ?? ''}';
    final parts = p.split(',');
    String at(int index) => index < parts.length && index >= 0 ? parts[index].trim() : '';
    final mode = switch (int.tryParse(at(1))) {
      4 => DanmakuMode.bottom,
      5 => DanmakuMode.top,
      _ => DanmakuMode.scroll,
    };
    final fallbackTime = raw['t'] is num ? (raw['t'] as num).toDouble() : 0.0;
    final time = double.tryParse(at(0)) ?? fallbackTime;
    var color = 0xffffff;
    var fontSize = 25;
    var pool = '';
    var userHash = '';
    final id = '${raw['cid'] ?? at(7)}';
    if (parts.length >= 5) {
      // 标准 dandanplay：时间,模式,字号,颜色,时间戳,池,用户,行号
      fontSize = int.tryParse(at(2)) ?? 25;
      color = int.tryParse(at(3)) ?? 0xffffff;
      pool = at(5);
      userHash = at(6);
    } else if (parts.length == 4) {
      // LogVar 变体：时间,模式,颜色,池
      color = int.tryParse(at(2)) ?? 0xffffff;
      pool = at(3);
    }
    result.add(
      DanmakuComment(
        time: time,
        mode: mode,
        fontSize: fontSize,
        color: color,
        pool: pool,
        userHash: userHash,
        id: id,
        text: text,
        source: source,
      ),
    );
  }
  return result;
}

/// 按设置动态在「后端链路」与「自定义 LogVar」之间切换。
class SwitchableDanmakuSource implements DanmakuSource {
  SwitchableDanmakuSource(this._settings, Dio backendDio, {Dio? customDio})
      : _backend = DanmakuApi(backendDio),
        _customDio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {'Accept': 'application/json'},
              ),
            );

  final SettingsController _settings;
  final DanmakuApi _backend;
  final Dio _customDio;
  LogVarDanmakuApi? _custom;
  String? _customBase;

  DanmakuSource get active {
    final config = _settings.settings;
    if (!config.useCustomDanmakuApi) return _backend;
    final base = config.danmakuApiBaseUrl.trim();
    if (base.isEmpty) return _backend;
    if (_custom == null || _customBase != base) {
      _custom = LogVarDanmakuApi(_customDio, base);
      _customBase = base;
    }
    return _custom!;
  }

  @override
  bool get aggregates => active.aggregates;

  @override
  String get description => active.description;

  @override
  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout}) =>
      active.search(keyword, timeout: timeout);

  @override
  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout}) =>
      active.episodes(animeId, timeout: timeout);

  @override
  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    required String source,
    Duration? timeout,
  }) =>
      active.comments(episode, source: source, timeout: timeout);
}

/// 设置页「测试连通」用：直接打一次搜索接口。
Future<void> testLogVarConnection(Dio dio, String baseUrl) async {
  final api = LogVarDanmakuApi(dio, baseUrl);
  await api.search('test', timeout: const Duration(seconds: 12));
}
