import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_settings.dart';
import '../../core/config/server_config.dart';
import '../../core/network/api_exception.dart';
import '../../data/api/media_api.dart';
import '../../domain/models/media_item.dart';

/// 播放请求统一使用浏览器 UA：部分片源站 WAF 会拒绝
/// `NEWTV/0.1` 这类非浏览器标识，表现为连接被重置。
const _playbackUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required ServerConfig server,
    required AppSettings settings,
    Dio? dio,
    this.onCompleted,
  })  : _server = server,
        _settings = settings,
        _dio = dio,
        player = Player(
          configuration: PlayerConfiguration(
            logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
          ),
        ) {
    videoController = VideoController(player);
    // libmpv 走自己的 TLS 栈，dio 的「允许自签名证书」对它不生效。
    if (server.allowSelfSigned) {
      final platform = player.platform;
      if (platform is NativePlayer) {
        unawaited(platform.setProperty('tls-verify', 'no'));
      }
    }
    if (kDebugMode) {
      _subscriptions.add(
        player.stream.log.listen(
          (event) => debugPrint('MPV[${event.prefix}] ${event.text}'.trim()),
        ),
      );
    }
    _subscriptions.addAll([
      player.stream.position.listen((value) {
        _position = value;
        if (_pendingInitialSeek != null && _duration > Duration.zero) {
          final target = _pendingInitialSeek!;
          _pendingInitialSeek = null;
          if (target > Duration.zero &&
              target.inMilliseconds < _duration.inMilliseconds * 0.95) {
            unawaited(player.seek(target));
          }
        }
        notifyListeners();
      }),
      player.stream.duration.listen((value) {
        _duration = value;
        if (_pendingInitialSeek != null && _duration > Duration.zero) {
          final target = _pendingInitialSeek!;
          _pendingInitialSeek = null;
          if (target > Duration.zero &&
              target.inMilliseconds < _duration.inMilliseconds * 0.95) {
            unawaited(player.seek(target));
          }
        }
        notifyListeners();
      }),
      player.stream.playing.listen((value) {
        _playing = value;
        notifyListeners();
      }),
      player.stream.buffering.listen((value) {
        _buffering = value;
        notifyListeners();
      }),
      player.stream.completed.listen((completed) {
        if (completed) onCompleted?.call();
      }),
      player.stream.error.listen((value) {
        // 已经成功解析出媒体信息后的报错多为分片网络抖动，mpv 会自行重试，
        // 不应中断播放界面。
        if (_duration > Duration.zero) {
          if (kDebugMode) debugPrint('MPV transient error: $value');
          return;
        }
        // m3u8 与分片是两条独立链路：m3u8 经服务端可绕开部分源站的压缩编码
        // 兼容问题，分片则直连更快。任一失败自动切换另一条，全部失败才提示。
        if (_candidateIndex + 1 < _candidates.length) {
          _candidateIndex++;
          _error = null;
          _errorDetail = null;
          notifyListeners();
          unawaited(_openUrl(_candidates[_candidateIndex]));
          return;
        }
        _error = value.isEmpty ? '播放失败，请尝试切换片源' : '播放失败';
        _errorDetail = _serverError ?? value;
        notifyListeners();
      }),
    ]);
  }

  final ServerConfig _server;
  final AppSettings _settings;
  final Dio? _dio;
  final VoidCallback? onCompleted;
  final Player player;
  late final VideoController videoController;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  PlaybackContext? _context;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _pendingInitialSeek;
  double _rate = 1.0;
  String? _errorDetail;
  String? _rawUrl;
  String? _serverError;
  List<String> _candidates = const [];
  var _candidateIndex = 0;
  var _playing = false;
  var _buffering = false;
  String? _error;

  PlaybackContext? get context => _context;
  Duration get position => _position;
  Duration get duration => _duration;
  double get rate => _rate;
  bool get playing => _playing;
  bool get buffering => _buffering;
  String? get error => _error;
  String? get errorDetail => _errorDetail;
  bool get hasNextEpisode {
    final current = _context;
    if (current == null) return false;
    return current.episodeIndex + 1 < current.item.episodes.length;
  }

  Future<void> open(PlaybackContext context) async {
    _context = context;
    _error = null;
    _errorDetail = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _pendingInitialSeek = context.initialPositionSeconds > 0
        ? Duration(seconds: context.initialPositionSeconds)
        : null;
    notifyListeners();
    final episodes = context.item.episodes;
    if (episodes.isEmpty) {
      _error = '该片源没有可播放的地址，请返回切换其他片源';
      notifyListeners();
      return;
    }
    final index = context.episodeIndex.clamp(0, episodes.length - 1);
    _rawUrl = episodes[index];
    _serverError = null;
    final proxyUrl = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: _rawUrl!,
      source: context.item.source,
      playbackToken: _settings.playbackToken,
      adblock: _settings.adblock,
      proxySegments: _settings.proxySegments,
    );
    // 全量代理分片模式：本机到源站 CDN 不通时，只能全部走用户自己的服务器。
    final proxyAllUrl = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: _rawUrl!,
      source: context.item.source,
      playbackToken: _settings.playbackToken,
      adblock: _settings.adblock,
      proxySegments: true,
    );

    // 依次尝试：服务端取 m3u8（避开 Brotli 压缩）→ 直连源站 → 全量代理分片。
    final candidates = <String>[proxyUrl, _rawUrl!];
    if (proxyAllUrl != proxyUrl) candidates.add(proxyAllUrl);
    _candidates = candidates;
    _candidateIndex = 0;

    // 先预检代理链路：服务端取流失败时会返回具体 error，
    // 提前跳过可以省掉一次 mpv 失败等待，也能把真实原因显示给用户。
    if (_dio != null) {
      final reason = await _probeProxy(proxyUrl);
      if (reason != null) {
        _serverError = reason;
        if (_candidates.length > 1) _candidateIndex = 1;
        if (kDebugMode) debugPrint('NEWTV proxy probe failed: $reason');
      }
    }

    if (kDebugMode) debugPrint('NEWTV play url: ${_candidates[_candidateIndex]}');
    await _openUrl(_candidates[_candidateIndex]);
  }

  /// 打开前用 dio 取回播放列表开头，判断服务端是否成功取流。
  /// 返回 null 表示可用，否则返回可读的失败原因。
  Future<String?> _probeProxy(String url) async {
    try {
      final response = await _dio!.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-1023'},
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return '服务端取流失败（HTTP $status）';
      }
      final contentType =
          (response.headers.value(Headers.contentTypeHeader) ?? '').toLowerCase();
      final bytes = response.data ?? const <int>[];
      if (contentType.contains('json')) {
        final text = utf8.decode(bytes, allowMalformed: true);
        return _extractServerError(text) ?? '服务端无法获取该播放地址';
      }
      final head = String.fromCharCodes(bytes.take(16));
      if (bytes.isNotEmpty && !head.contains('#EXT')) {
        return '服务端返回的内容不是播放列表（可能被源站拦截）';
      }
      return null;
    } on Object catch (error) {
      return readableError(error);
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
      // 非 JSON 响应，交给调用方兜底。
    }
    return null;
  }

  Future<void> _openUrl(String url) async {
    try {
      await player.open(
        Media(
          url,
          httpHeaders: const {
            'User-Agent': _playbackUserAgent,
            // 部分片源站默认返回 Brotli 压缩流，libmpv 无法解压会直接报
            // "Failed to recognize file format"，因此要求不压缩的原始内容。
            'Accept-Encoding': 'identity',
          },
        ),
        play: true,
      );
    } on Object catch (error) {
      _error = '无法打开播放地址：$error';
      notifyListeners();
    }
  }

  Future<void> retry() async {
    final current = _context;
    if (current != null) await open(current);
  }

  static Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Future<void> toggle() async => _playing ? player.pause() : player.play();
  Future<void> seek(Duration value) => player.seek(_clampDuration(value, Duration.zero, _duration));
  Future<void> seekRelative(Duration delta) => seek(_position + delta);
  Future<void> setRate(double rate) {
    _rate = rate;
    notifyListeners();
    return player.setRate(rate);
  }
  Future<void> setVolume(double volume) => player.setVolume(volume.clamp(0, 100));

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
