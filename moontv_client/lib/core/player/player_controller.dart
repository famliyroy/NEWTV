import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_settings.dart';
import '../../core/config/server_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/playback_resume.dart';
import '../../data/api/media_api.dart';
import '../../domain/models/media_item.dart';
import 'hls_quality.dart';

/// 播放请求统一使用浏览器 UA：部分片源站 WAF 会拒绝
/// `NEWTV/0.1` 这类非浏览器标识，表现为连接被重置。
const _playbackUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required ServerConfig server,
    required SettingsController settings,
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
        _consumePendingSeek();
        notifyListeners();
      }),
      player.stream.duration.listen((value) {
        _duration = value;
        _consumePendingSeek();
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

  /// 持有 storage 而非值快照：`open()` 每次都现场读，
  /// 用户在设置页/播放页改的开关无需重进 APP 即可生效。
  final SettingsController _settings;
  final Dio? _dio;
  final VoidCallback? onCompleted;
  final Player player;
  late final VideoController videoController;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  /// 清晰度菜单里的「自动」项。
  static const autoQualityLabel = '自动';

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
  List<HlsVariant> _variants = const [];
  String _selectedQuality = autoQualityLabel;
  bool _singleStreamQuality = false;
  bool _probingQuality = false;

  PlaybackContext? get context => _context;
  Duration get position => _position;
  Duration get duration => _duration;
  double get rate => _rate;
  bool get playing => _playing;
  bool get buffering => _buffering;
  String? get error => _error;
  String? get errorDetail => _errorDetail;

  /// 可选清晰度（已测速）；空表示尚未探测完或单码率。
  List<HlsVariant> get variants => _variants;
  String get selectedQuality => _selectedQuality;
  bool get probingQuality => _probingQuality;
  bool get singleStreamQuality => _singleStreamQuality;
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
    _variants = const [];
    _selectedQuality = autoQualityLabel;
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
    final settings = _settings.settings;
    final proxyUrl = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: _rawUrl!,
      source: context.item.source,
      playbackToken: settings.playbackToken,
      adblock: settings.adblock,
      proxySegments: settings.proxySegments,
    );
    // 全量代理分片模式：本机到源站 CDN 不通时，只能全部走用户自己的服务器。
    final proxyAllUrl = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: _rawUrl!,
      source: context.item.source,
      playbackToken: settings.playbackToken,
      adblock: settings.adblock,
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
    // 清晰度探测不阻塞起播：拿到 master 后逐档测速，完成后再刷新菜单。
    if (_rawUrl != null && _rawUrl!.contains('.m3u8')) {
      unawaited(_probeQuality());
    }
  }

  /// 媒体时长为 0 时 seek 会被播放器忽略，因此初始续播位置要等到
  /// duration 可用后再执行，并且只执行一次。
  ///
  /// 片尾阈值与详情页/继续观看提示保持一致（30 秒）：太靠后的记录不跳，
  /// 否则会停在放不出画面的位置。
  void _consumePendingSeek() {
    final target = _pendingInitialSeek;
    if (target == null || _duration <= Duration.zero) return;
    _pendingInitialSeek = null;
    if (target <= Duration.zero) return;
    if (target.inSeconds >= _duration.inSeconds - nearEndThresholdSeconds) {
      if (kDebugMode) {
        debugPrint('NEWTV skip near-end resume: $target / $_duration');
      }
      return;
    }
    unawaited(player.seek(target));
  }

  /// 拉取 master playlist 并测速。失败时静默降级为「自动（单一流）」。
  Future<void> _probeQuality() async {
    final raw = _rawUrl;
    final dio = _dio;
    if (raw == null || dio == null || _probingQuality) return;
    _probingQuality = true;
    notifyListeners();
    try {
      final settings = _settings.settings;
      final proxy = MediaApi.buildProxyUrl(
        baseUrl: _server.baseUrl,
        rawUrl: raw,
        source: _context?.item.source ?? '',
        playbackToken: settings.playbackToken,
        adblock: settings.adblock,
        proxySegments: settings.proxySegments,
      );
      final report = await HlsQualityProbe(dio).probe(
        [proxy, raw],
        baseUri: Uri.parse(raw),
      );
      // 探测期间可能已经切集/换源，结果只对发起时的地址有效。
      if (_rawUrl != raw) return;
      if (report.variants.isEmpty) {
        _singleStreamQuality = report.singleStream || report.error == null;
        _variants = const [];
      } else {
        _singleStreamQuality = false;
        _variants = report.variants;
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('NEWTV quality probe failed: $error');
      _singleStreamQuality = true;
    } finally {
      _probingQuality = false;
      notifyListeners();
    }
  }

  HlsVariant? _fastestVariant() {
    final measured = _variants.where((variant) => variant.measured).toList();
    if (measured.isEmpty) return _variants.isEmpty ? null : _variants.first;
    measured.sort(
      (a, b) => b.speedBytesPerSecond!.compareTo(a.speedBytesPerSecond!),
    );
    return measured.first;
  }

  /// 切换清晰度：用该变体的子 m3u8 重新起播，并回到原进度。
  Future<void> selectQuality(String label) async {
    if (label == _selectedQuality) return;
    final context = _context;
    if (context == null) return;
    if (label == autoQualityLabel) {
      final fastest = _fastestVariant();
      if (fastest == null) {
        _selectedQuality = autoQualityLabel;
        notifyListeners();
        await open(context);
        return;
      }
      await _openVariant(fastest, label: autoQualityLabel);
      return;
    }
    HlsVariant? variant;
    for (final candidate in _variants) {
      if (candidate.label == label) {
        variant = candidate;
        break;
      }
    }
    if (variant == null) return;
    await _openVariant(variant, label: variant.label);
  }

  Future<void> _openVariant(HlsVariant variant, {required String label}) async {
    final context = _context;
    final settings = _settings.settings;
    final resume = _position;
    final proxy = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: variant.url,
      source: context?.item.source ?? '',
      playbackToken: settings.playbackToken,
      adblock: settings.adblock,
      proxySegments: settings.proxySegments,
    );
    _candidates = sourceUriOf(variant.url) != null
        // 服务端已把它重写成代理地址，直接用，避免二次包裹。
        ? [variant.url]
        : (proxy == variant.url ? [variant.url] : [proxy, variant.url]);
    _candidateIndex = 0;
    _selectedQuality = label;
    _error = null;
    _errorDetail = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _pendingInitialSeek =
        resume > const Duration(seconds: 2) ? resume : null;
    notifyListeners();
    if (kDebugMode) debugPrint('NEWTV switch quality ($label): ${_candidates.first}');
    await _openUrl(_candidates.first);
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
