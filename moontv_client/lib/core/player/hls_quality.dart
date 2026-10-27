import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

/// 一条可切换的清晰度变体（来自 m3u8 的 `#EXT-X-STREAM-INF`）。
class HlsVariant {
  const HlsVariant({
    required this.label,
    required this.bandwidth,
    required this.url,
    this.speedBytesPerSecond,
  });

  /// 展示用名称，如 `1080P`；无分辨率信息时退化为码率。
  final String label;
  final int bandwidth;

  /// 子播放列表的绝对地址。
  final String url;

  /// 实测下载速率（字节/秒），null 表示未测或测速失败。
  final double? speedBytesPerSecond;

  HlsVariant withSpeed(double? value) => HlsVariant(
        label: label,
        bandwidth: bandwidth,
        url: url,
        speedBytesPerSecond: value,
      );

  bool get measured => speedBytesPerSecond != null;

  String get speedLabel {
    final value = speedBytesPerSecond;
    if (value == null) return '测速失败';
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(value / 1024).toStringAsFixed(0)} KB/s';
  }

  @override
  String toString() => 'HlsVariant($label, $bandwidth, $speedLabel)';
}

class HlsQualityReport {
  const HlsQualityReport({
    required this.variants,
    this.error,
    this.singleStream = false,
  });

  final List<HlsVariant> variants;
  final String? error;

  /// 源只有单一码率，无需提供切换菜单。
  final bool singleStream;

  bool get isEmpty => variants.isEmpty;
}

/// 若 [url] 是本站 `/api/proxy-m3u8?url=...` 形式，取出被代理的源站地址。
/// 服务端会把子播放列表地址重写成自己的代理地址，测速与相对路径解析
/// 都要回到源站地址上。
Uri? sourceUriOf(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return null;
  final raw = parsed.queryParameters['url'];
  if (raw == null || raw.isEmpty) return null;
  final source = Uri.tryParse(raw);
  if (source == null || !source.hasScheme) return null;
  return source;
}

/// 解析 master playlist。返回空列表表示这是单码率（media）播放列表。
List<HlsVariant> parseMasterPlaylist(String text, Uri baseUri) {
  final lines = text.split(RegExp(r'\r?\n'));
  final variants = <HlsVariant>[];
  final seen = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    final attributes = line.substring('#EXT-X-STREAM-INF:'.length);
    // HLS 规范里子播放列表地址紧跟在 STREAM-INF 的下一行，
    // 中间不允许再插入标签；若下一行不是地址则说明该条目损坏，直接跳过。
    final nextLine = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (nextLine.isEmpty || nextLine.startsWith('#')) continue;
    final resolved = _resolve(nextLine, baseUri);
    if (resolved == null || !seen.add(resolved)) continue;
    final bandwidth = _attributeInt(attributes, 'BANDWIDTH') ??
        _attributeInt(attributes, 'AVERAGE-BANDWIDTH') ??
        0;
    final height = _resolutionHeight(attributes);
    final name = _attributeString(attributes, 'NAME');
    final label = height != null
        ? '${height}P'
        : (name?.trim().isNotEmpty == true
            ? name!.trim()
            : bandwidth > 0
                ? '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps'
                : '未知清晰度');
    variants.add(HlsVariant(label: label, bandwidth: bandwidth, url: resolved));
  }
  // 码率降序，菜单里高清晰度排前面。
  variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  // 去掉重复标签（同分辨率不同码率时补码率后缀，避免菜单出现两个 1080P）。
  final labels = <String, int>{};
  return variants.map((variant) {
    final count = labels.update(variant.label, (value) => value + 1, ifAbsent: () => 0);
    if (count == 0) return variant;
    return HlsVariant(
      label: '${variant.label} · ${(variant.bandwidth / 1000000).toStringAsFixed(1)} Mbps',
      bandwidth: variant.bandwidth,
      url: variant.url,
      speedBytesPerSecond: variant.speedBytesPerSecond,
    );
  }).toList();
}

/// 取 media playlist 里第一个分片地址，用于测速。
Uri? firstSegmentUri(String text, Uri baseUri) {
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final resolved = _resolve(line, baseUri);
    return resolved == null ? null : Uri.parse(resolved);
  }
  return null;
}

String? _resolve(String value, Uri baseUri) {
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.hasScheme) return uri.toString();
  return baseUri.resolveUri(uri).toString();
}

int? _attributeInt(String attributes, String key) {
  final match = RegExp('$key=(\\d+)').firstMatch(attributes);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String? _attributeString(String attributes, String key) {
  final match = RegExp('$key="([^"]*)"').firstMatch(attributes);
  return match?.group(1);
}

int? _resolutionHeight(String attributes) {
  final match = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(attributes);
  if (match == null) return null;
  return int.tryParse(match.group(2)!);
}

/// 拉取 m3u8 并按需测速。
///
/// 测速口径：取每个变体的**首个分片**做 `Range: bytes=0-262143` 请求，
/// 用「实际字节 / 耗时」估算下载速率；单条变体失败重试一次仍失败则记为
/// 测速失败，不影响菜单展示。
class HlsQualityProbe {
  HlsQualityProbe(this._dio);

  static const _probeBytes = 262143;
  static const _segmentTimeout = Duration(seconds: 5);
  static const _playlistTimeout = Duration(seconds: 12);

  final Dio _dio;

  /// [candidateUrls] 依次尝试（通常是「服务端代理 → 直连」），
  /// 第一个成功取回 master 的地址用于发起请求。
  ///
  /// [baseUri] 必须是**原始 master 地址**：经服务端代理取回的内容仍是源站
  /// 原样播放列表，相对路径要相对源站解析；若服务端重写过地址，则变体地址
  /// 已是绝对 URL，base 不参与解析。
  Future<HlsQualityReport> probe(
    List<String> candidateUrls, {
    required Uri baseUri,
  }) async {
    String? text;
    Object? lastError;
    for (final url in candidateUrls) {
      try {
        text = await _getText(url, _playlistTimeout);
        break;
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (text == null) {
      return HlsQualityReport(variants: const [], error: '$lastError');
    }
    if (!text.contains('#EXT-X-STREAM-INF')) {
      return const HlsQualityReport(variants: [], singleStream: true);
    }
    final variants = parseMasterPlaylist(text, baseUri);
    if (variants.isEmpty) {
      return const HlsQualityReport(variants: [], singleStream: true);
    }
    final measured = await Future.wait(variants.map(_measure));
    return HlsQualityReport(variants: measured);
  }

  Future<HlsVariant> _measure(HlsVariant variant) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final playlistUri = sourceUriOf(variant.url) ?? Uri.parse(variant.url);
        final playlist = await _getText(variant.url, _segmentTimeout);
        final segment = firstSegmentUri(playlist, playlistUri);
        if (segment == null) return variant.withSpeed(null);
        final stopwatch = Stopwatch()..start();
        final response = await _dio.get<List<int>>(
          segment.toString(),
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Range': 'bytes=0-$_probeBytes',
              'User-Agent': _probeUserAgent,
            },
            validateStatus: (status) => status != null && status < 500,
            receiveTimeout: _segmentTimeout,
            sendTimeout: _segmentTimeout,
          ),
        );
        stopwatch.stop();
        final bytes = response.data?.length ?? 0;
        if (bytes <= 0) continue;
        final seconds = math.max(stopwatch.elapsedMilliseconds, 60) / 1000;
        return variant.withSpeed(bytes / seconds);
      } on Object {
        if (attempt == 0) continue;
        return variant.withSpeed(null);
      }
    }
    return variant.withSpeed(null);
  }

  Future<String> _getText(String url, Duration timeout) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'User-Agent': _probeUserAgent},
        receiveTimeout: timeout,
        sendTimeout: timeout,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw StateError('播放列表为空');
    }
    return data;
  }

  static const _probeUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';
}
