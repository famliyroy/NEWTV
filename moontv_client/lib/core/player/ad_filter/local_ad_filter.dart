import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/api/media_api.dart';
import '../hls_quality.dart';

/// 本地 m3u8 广告过滤结果。
class AdFilterResult {
  const AdFilterResult({
    this.fileUri,
    this.filePath,
    this.removedSegments = 0,
    this.totalSegments = 0,
    this.skippedLive = false,
    this.usedProxySource = false,
    this.proxyError,
  });

  /// 本地改写后的 `file:///...` 地址；为 null 表示跳过或失败（走原有候选链）。
  final String? fileUri;
  final String? filePath;
  final int removedSegments;
  final int totalSegments;
  final bool skippedLive;
  final bool usedProxySource;

  /// 拉取服务端代理时若失败，顺带返回可读原因供 PlayerController 记录诊断。
  final String? proxyError;

  bool get isSuccess => fileUri != null && fileUri!.isNotEmpty;
}

/// 纯函数过滤输出。
class FilteredPlaylist {
  const FilteredPlaylist({
    required this.content,
    required this.totalSegments,
    required this.keptSegments,
    this.abandonedFilter = false,
  });

  final String content;
  final int totalSegments;
  final int keptSegments;

  /// 过滤后剩余不足 2 段时触发防误杀回退（仍做去 DISCONTINUITY 与 URL 绝对化）。
  final bool abandonedFilter;

  int get removedSegments => totalSegments - keptSegments;
}

/// 客户端本地 m3u8 广告过滤插件（LocalAdFilter）。
///
/// 职责：
/// 1. 优先经 `/api/proxy-m3u8` 拉取 m3u8，失败自动回退直连源站（带浏览器 UA + Referer）；
/// 2. 若为 master playlist，按当前所选清晰度（或最高码率变体）继续拉取子 media playlist；
/// 3. 识别直播流（`#EXT-X-PLAYLIST-TYPE:EVENT` 或无 VOD/ENDLIST 标记）并跳过；
/// 4. 本地二次过滤：
///    - 剔除所有 `#EXT-X-DISCONTINUITY` 行（消除跨广告区 PTS 断层导致 mpv 快进回零与弹幕闪现）；
///    - URL 关键词命中剔除（与后端 7 词对齐）；
///    - `#EXTINF` 时长中位数启发式：剔除 `< 中位数 45%` 或 `> 中位数 200%` 的异常时长分片；
///    - 不连续块异源路径启发式：在存在 `#EXT-X-DISCONTINUITY` 的列表中，剔除目录前缀偏离主正片（>=70%）的短插播块；
///    - 防误杀保护：若过滤后不足 2 段，放弃剔除分片，回退保留全部分片；
/// 5. 将分片 URL 与 `#EXT-X-KEY` / `#EXT-X-MAP` 的 `URI="..."` 全部转为绝对地址；
/// 6. 写入应用缓存目录 `ad_filter/<source>_<id>.m3u8`，供 mpv 作为第一候选本地打开。
class LocalAdFilter {
  LocalAdFilter({
    required Dio dio,
    Future<Directory> Function()? tempDirProvider,
  })  : _dio = dio,
        _tempDirProvider = tempDirProvider ?? _defaultTempDir;

  /// 与后端 `/api/proxy-m3u8` 对齐的 7 个默认广告 URL 关键词。
  static const defaultAdKeywords = <String>[
    'sponsor',
    '/ad/',
    '/ads/',
    'advert',
    'adsegment',
    'guanggao',
    'adjump',
  ];

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

  static const _fetchTimeout = Duration(seconds: 10);
  static const _cacheSubdir = 'ad_filter';

  final Dio _dio;
  final Future<Directory> Function() _tempDirProvider;

  static Future<Directory> _defaultTempDir() async {
    try {
      return await getTemporaryDirectory();
    } on Object {
      return Directory.systemTemp;
    }
  }

  /// App 启动时清空 `ad_filter/` 临时目录。
  static Future<void> clearCache({
    Future<Directory> Function()? tempDirProvider,
  }) async {
    try {
      final baseDir = await (tempDirProvider ?? _defaultTempDir)();
      final dir = Directory(p.join(baseDir.path, _cacheSubdir));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('LocalAdFilter.clearCache ignored: $error');
    }
  }

  /// 执行拉取 → 选流 → 过滤 → 绝对化 → 落盘流水线。
  ///
  /// 任何异常均内部消化并返回 `AdFilterResult(fileUri: null)`，绝不阻塞原有播放候选链。
  Future<AdFilterResult> prepare({
    required String rawUrl,
    required String proxyUrl,
    required String serverBaseUrl,
    required String source,
    required String mediaId,
    String playbackToken = '',
    bool proxySegments = false,
    String? preferredQuality,
  }) async {
    String? proxyError;
    var usedProxy = false;

    try {
      final rawUri = Uri.tryParse(rawUrl);
      if (rawUri == null || !rawUri.hasScheme) {
        return const AdFilterResult();
      }

      // 1. 拉取入口 m3u8：优先走服务端代理，失败再直连源站。
      String? playlistText;
      final proxyFetch = await _fetchM3u8(proxyUrl);
      if (proxyFetch.text != null) {
        playlistText = proxyFetch.text;
        usedProxy = true;
      } else {
        proxyError = proxyFetch.error;
        final directFetch = await _fetchM3u8(
          rawUrl,
          referer: _originReferer(rawUri),
        );
        playlistText = directFetch.text;
      }

      if (playlistText == null) {
        return AdFilterResult(proxyError: proxyError);
      }

      var mediaText = playlistText;
      var mediaBaseUri = rawUri;

      // 2. 若是 master playlist（含 #EXT-X-STREAM-INF），解析出对应清晰度的子流再拉一次。
      if (mediaText.contains('#EXT-X-STREAM-INF')) {
        final variants = parseMasterPlaylist(mediaText, rawUri);
        if (variants.isEmpty) {
          return AdFilterResult(proxyError: proxyError);
        }
        final chosen = _pickVariant(variants, preferredQuality);
        final variantRawUri = sourceUriOf(chosen.url) ?? Uri.parse(chosen.url);
        final variantRawUrl = variantRawUri.toString();
        final variantProxyUrl = sourceUriOf(chosen.url) != null
            ? chosen.url
            : MediaApi.buildProxyUrl(
                baseUrl: serverBaseUrl,
                rawUrl: variantRawUrl,
                source: source,
                playbackToken: playbackToken,
                adblock: true,
                proxySegments: proxySegments,
              );

        String? subText;
        if (usedProxy) {
          final subProxy = await _fetchM3u8(variantProxyUrl);
          subText = subProxy.text;
        }
        if (subText == null) {
          final subDirect = await _fetchM3u8(
            variantRawUrl,
            referer: _originReferer(variantRawUri),
          );
          subText = subDirect.text;
        }
        if (subText == null) {
          return AdFilterResult(proxyError: proxyError);
        }
        mediaText = subText;
        mediaBaseUri = variantRawUri;
      }

      // 3. 识别直播流：#EXT-X-PLAYLIST-TYPE:EVENT 或既无 VOD 也无 #EXT-X-ENDLIST。
      if (isLivePlaylist(mediaText)) {
        return AdFilterResult(
          skippedLive: true,
          usedProxySource: usedProxy,
          proxyError: proxyError,
        );
      }

      // 4. 本地二次过滤 + URI 绝对化。
      final filtered = filterMediaPlaylist(
        mediaText,
        baseUri: mediaBaseUri,
        serverBaseUri: Uri.tryParse(serverBaseUrl),
      );
      if (filtered == null) {
        return AdFilterResult(proxyError: proxyError);
      }

      // 5. 写入临时文件 ad_filter/<source>_<id>.m3u8（同名覆盖）。
      final baseDir = await _tempDirProvider();
      final dir = Directory(p.join(baseDir.path, _cacheSubdir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safeSource = _sanitizeFilePart(source.isEmpty ? 'src' : source);
      final safeId = _sanitizeFilePart(
        mediaId.isEmpty ? rawUrl.hashCode.abs().toString() : mediaId,
      );
      final filePath = p.join(dir.path, '${safeSource}_$safeId.m3u8');
      final file = File(filePath);
      await file.writeAsString(filtered.content, flush: true);

      return AdFilterResult(
        fileUri: Uri.file(file.path).toString(),
        filePath: file.path,
        removedSegments: filtered.removedSegments,
        totalSegments: filtered.totalSegments,
        usedProxySource: usedProxy,
        proxyError: proxyError,
      );
    } on Object catch (error) {
      if (kDebugMode) debugPrint('LocalAdFilter.prepare failed: $error');
      return AdFilterResult(proxyError: proxyError);
    }
  }

  static HlsVariant _pickVariant(
    List<HlsVariant> variants,
    String? preferredQuality,
  ) {
    if (preferredQuality != null &&
        preferredQuality.isNotEmpty &&
        preferredQuality != '自动') {
      for (final variant in variants) {
        if (variant.label == preferredQuality) return variant;
      }
    }
    return variants.first;
  }

  Future<({String? text, String? error})> _fetchM3u8(
    String url, {
    String? referer,
  }) async {
    try {
      final headers = <String, String>{
        'User-Agent': _userAgent,
        'Accept-Encoding': 'identity',
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
      };
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: (_) => true,
          receiveTimeout: _fetchTimeout,
          sendTimeout: _fetchTimeout,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return (text: null, error: '服务端取流失败（HTTP $status）');
      }
      final contentType =
          (response.headers.value(Headers.contentTypeHeader) ?? '')
              .toLowerCase();
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) {
        return (text: null, error: '播放列表为空');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (contentType.contains('json') || text.trimLeft().startsWith('{')) {
        return (
          text: null,
          error: _extractServerError(text) ?? '服务端无法获取该播放地址',
        );
      }
      if (!text.contains('#EXTM3U')) {
        return (text: null, error: '返回的内容不是有效 m3u8 播放列表');
      }
      return (text: text, error: null);
    } on Object catch (error) {
      return (text: null, error: '$error');
    }
  }

  static String? _extractServerError(String text) {
    try {
      final data = jsonDecode(text);
      if (data is Map && data['error'] is String) {
        final value = (data['error'] as String).trim();
        return value.isEmpty ? null : value;
      }
    } on Object {
      // Ignore non-JSON body.
    }
    return null;
  }

  static String _originReferer(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) return '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port/';
  }

  static String _sanitizeFilePart(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  /// 判断是否为直播/事件流（`#EXT-X-PLAYLIST-TYPE:EVENT` 或无 VOD/ENDLIST 结束标记）。
  static bool isLivePlaylist(String text) {
    var hasEventType = false;
    var hasVodMarker = false;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim().toUpperCase();
      if (line.startsWith('#EXT-X-PLAYLIST-TYPE:')) {
        final type = line.substring('#EXT-X-PLAYLIST-TYPE:'.length).trim();
        if (type == 'EVENT') hasEventType = true;
        if (type == 'VOD') hasVodMarker = true;
      } else if (line == '#EXT-X-ENDLIST') {
        hasVodMarker = true;
      }
    }
    if (hasEventType) return true;
    return !hasVodMarker;
  }

  /// 对单码率 media playlist 执行二次去广告过滤与 URI 绝对化。
  ///
  /// 若输入不是有效的点播 media playlist（如分片数 < 2 或属直播流），返回 `null`。
  static FilteredPlaylist? filterMediaPlaylist(
    String content, {
    required Uri baseUri,
    Uri? serverBaseUri,
    List<String> adKeywords = defaultAdKeywords,
  }) {
    if (!content.contains('#EXTM3U') || !content.contains('#EXTINF')) {
      return null;
    }
    if (isLivePlaylist(content)) {
      return null;
    }

    final lines = content.split(RegExp(r'\r?\n'));
    final headerLines = <String>[];
    final segments = <_M3u8Segment>[];

    String? currentKeyLine;
    String? currentMapLine;
    String? pendingExtInf;
    double? pendingDuration;
    final pendingMetaLines = <String>[];
    var discontinuityGroup = 0;
    var sawDiscontinuityTag = false;
    var hasTargetDuration = false;
    var hasPlaylistType = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        final upper = line.toUpperCase();
        if (upper == '#EXTM3U') {
          if (headerLines.isEmpty) headerLines.add('#EXTM3U');
          continue;
        }
        // 规则 1：删除所有 #EXT-X-DISCONTINUITY（及 DISCONTINUITY-SEQUENCE）行。
        if (upper.startsWith('#EXT-X-DISCONTINUITY')) {
          sawDiscontinuityTag = true;
          discontinuityGroup++;
          continue;
        }
        if (upper == '#EXT-X-ENDLIST') {
          continue;
        }
        if (upper.startsWith('#EXT-X-KEY:')) {
          currentKeyLine = resolveAttributeUris(
            line,
            baseUri,
            serverBaseUri: serverBaseUri,
          );
          continue;
        }
        if (upper.startsWith('#EXT-X-MAP:')) {
          currentMapLine = resolveAttributeUris(
            line,
            baseUri,
            serverBaseUri: serverBaseUri,
          );
          continue;
        }
        if (upper.startsWith('#EXTINF:')) {
          pendingExtInf = line;
          pendingDuration = _parseExtInfDuration(line);
          continue;
        }
        if (upper.startsWith('#EXT-X-BYTERANGE:') ||
            upper.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
          if (pendingExtInf != null) {
            pendingMetaLines.add(line);
          }
          continue;
        }
        if (upper.startsWith('#EXT-X-TARGETDURATION:')) {
          hasTargetDuration = true;
        } else if (upper.startsWith('#EXT-X-PLAYLIST-TYPE:')) {
          hasPlaylistType = true;
        }
        if (segments.isEmpty && pendingExtInf == null) {
          headerLines.add(line);
        }
        continue;
      }

      // 非 '#' 行：分片 URI。
      if (pendingExtInf != null && pendingDuration != null) {
        final resolvedUrl = resolveM3u8Url(
          line,
          baseUri,
          serverBaseUri: serverBaseUri,
        );
        segments.add(
          _M3u8Segment(
            extInfLine: pendingExtInf,
            duration: pendingDuration,
            rawUrl: line,
            resolvedUrl: resolvedUrl,
            keyLine: currentKeyLine,
            mapLine: currentMapLine,
            metaLines: List<String>.from(pendingMetaLines),
            discontinuityGroup: discontinuityGroup,
          ),
        );
        pendingExtInf = null;
        pendingDuration = null;
        pendingMetaLines.clear();
      }
    }

    if (segments.length < 2) {
      return null;
    }

    final median = _computeMedian(
      segments.map((segment) => segment.duration).toList(),
    );
    final minDuration = median * 0.45;
    final maxDuration = median * 2.0;

    // 辅助启发式：若原列表含 #EXT-X-DISCONTINUITY 且正片目录占绝对多数（>=70%），
    // 识别出目录前缀与正片完全不同的短插播块（即便广告分片时长恰巧接近正片也能剔除）。
    final foreignDiscontinuityGroups = sawDiscontinuityTag
        ? _detectForeignDiscontinuityGroups(segments)
        : const <int>{};

    final kept = <_M3u8Segment>[];
    for (final segment in segments) {
      if (_matchesAdKeyword(segment.rawUrl, adKeywords) ||
          _matchesAdKeyword(segment.resolvedUrl, adKeywords)) {
        continue;
      }
      if (median > 0 &&
          (segment.duration < minDuration || segment.duration > maxDuration)) {
        continue;
      }
      if (foreignDiscontinuityGroups.contains(segment.discontinuityGroup)) {
        continue;
      }
      kept.add(segment);
    }

    // 规则 3 兜底：过滤后剩余分片少于 2 段则放弃剔除，防止误杀整部短片。
    final abandoned = kept.length < 2;
    final finalSegments = abandoned ? segments : kept;

    final out = <String>[];
    if (headerLines.isEmpty || headerLines.first != '#EXTM3U') {
      out.add('#EXTM3U');
    }
    out.addAll(headerLines);
    if (!hasPlaylistType) {
      out.add('#EXT-X-PLAYLIST-TYPE:VOD');
    }
    if (!hasTargetDuration) {
      final maxSeg = finalSegments
          .map((s) => s.duration)
          .fold<double>(6.0, math.max)
          .ceil();
      out.add('#EXT-X-TARGETDURATION:$maxSeg');
    }

    String? emittedKey;
    String? emittedMap;
    for (final segment in finalSegments) {
      if (segment.keyLine != emittedKey) {
        if (segment.keyLine != null) {
          out.add(segment.keyLine!);
        }
        emittedKey = segment.keyLine;
      }
      if (segment.mapLine != emittedMap) {
        if (segment.mapLine != null) {
          out.add(segment.mapLine!);
        }
        emittedMap = segment.mapLine;
      }
      out.add(segment.extInfLine);
      out.addAll(segment.metaLines);
      out.add(segment.resolvedUrl);
    }
    out.add('#EXT-X-ENDLIST');

    return FilteredPlaylist(
      content: '${out.join('\n')}\n',
      totalSegments: segments.length,
      keptSegments: finalSegments.length,
      abandonedFilter: abandoned,
    );
  }

  /// 将相对路径解析为绝对 URL（对齐后端 `resolveM3u8Links` 规则）。
  static String resolveM3u8Url(
    String rawRef,
    Uri playlistBaseUri, {
    Uri? serverBaseUri,
  }) {
    final trimmed = rawRef.trim();
    if (trimmed.isEmpty) return trimmed;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return trimmed;
    if (parsed.hasScheme) return parsed.toString();
    if (trimmed.startsWith('/api/') &&
        serverBaseUri != null &&
        serverBaseUri.hasScheme) {
      return serverBaseUri.resolveUri(parsed).toString();
    }
    return playlistBaseUri.resolveUri(parsed).toString();
  }

  /// 将 `#EXT-X-KEY` / `#EXT-X-MAP` 标签中的 `URI="..."` 转为绝对地址。
  static String resolveAttributeUris(
    String tagLine,
    Uri playlistBaseUri, {
    Uri? serverBaseUri,
  }) {
    return tagLine.replaceAllMapped(
      RegExp(r'''URI=(["'])([^"']+)\1'''),
      (match) {
        final quote = match.group(1) ?? '"';
        final rawUri = match.group(2) ?? '';
        final resolved = resolveM3u8Url(
          rawUri,
          playlistBaseUri,
          serverBaseUri: serverBaseUri,
        );
        return 'URI=$quote$resolved$quote';
      },
    );
  }

  static double? _parseExtInfDuration(String line) {
    final match = RegExp(r'^#EXTINF:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(line);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static double _computeMedian(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  static bool _matchesAdKeyword(String url, List<String> keywords) {
    final lower = url.toLowerCase();
    for (final keyword in keywords) {
      if (keyword.isNotEmpty && lower.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static Set<int> _detectForeignDiscontinuityGroups(
    List<_M3u8Segment> segments,
  ) {
    if (segments.length < 8) return const <int>{};
    final dirCounts = <String, int>{};
    final groupSegments = <int, List<_M3u8Segment>>{};
    for (final seg in segments) {
      final dir = _directoryPrefix(seg.resolvedUrl);
      dirCounts[dir] = (dirCounts[dir] ?? 0) + 1;
      groupSegments.putIfAbsent(seg.discontinuityGroup, () => []).add(seg);
    }
    if (groupSegments.length <= 1) return const <int>{};

    String? dominantDir;
    var dominantCount = 0;
    for (final entry in dirCounts.entries) {
      if (entry.value > dominantCount) {
        dominantCount = entry.value;
        dominantDir = entry.key;
      }
    }
    if (dominantDir == null ||
        dominantDir.isEmpty ||
        dominantCount < segments.length * 0.70) {
      return const <int>{};
    }

    final foreignGroups = <int>{};
    for (final entry in groupSegments.entries) {
      final group = entry.value;
      // 仅针对短小的插播块（<= 8 段且占比 < 25%），且块内分片目录全部异于主目录。
      if (group.length <= 8 &&
          group.length < segments.length * 0.25 &&
          group.every((s) => _directoryPrefix(s.resolvedUrl) != dominantDir)) {
        foreignGroups.add(entry.key);
      }
    }
    return foreignGroups;
  }

  static String _directoryPrefix(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final path = uri.path;
    final slash = path.lastIndexOf('/');
    final dir = slash >= 0 ? path.substring(0, slash) : path;
    return '${uri.scheme}://${uri.authority}$dir';
  }
}

class _M3u8Segment {
  const _M3u8Segment({
    required this.extInfLine,
    required this.duration,
    required this.rawUrl,
    required this.resolvedUrl,
    required this.discontinuityGroup,
    this.keyLine,
    this.mapLine,
    this.metaLines = const [],
  });

  final String extInfLine;
  final double duration;
  final String rawUrl;
  final String resolvedUrl;
  final String? keyLine;
  final String? mapLine;
  final List<String> metaLines;
  final int discontinuityGroup;
}
