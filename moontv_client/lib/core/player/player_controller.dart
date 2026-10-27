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
import 'ad_filter/local_ad_filter.dart';
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
    LocalAdFilter? adFilter,
    this.onCompleted,
    @visibleForTesting Future<void> Function(String url)? debugUrlOpener,
    @visibleForTesting Future<void> Function(Duration target)? debugSeekHandler,
  })  : _server = server,
        _settings = settings,
        _dio = dio,
        _adFilter = adFilter ?? (dio != null ? LocalAdFilter(dio: dio) : null),
        _debugUrlOpener = debugUrlOpener,
        _debugSeekHandler = debugSeekHandler {
    if (_debugUrlOpener != null) {
      return;
    }
    player = Player(
      configuration: PlayerConfiguration(
        logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
      ),
    );
    videoController = VideoController(player);
    final platform = player.platform;
    if (platform is NativePlayer) {
      // 允许本地改写后的 ad_filter/*.m3u8 引用远程 http(s) 分片与密钥地址。
      unawaited(platform.setProperty('load-unsafe-playlists', 'yes'));
      // libmpv 走自己的 TLS 栈，dio 的「允许自签名证书」对它不生效。
      if (server.allowSelfSigned) {
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
      player.stream.position.listen(handlePositionUpdate),
      player.stream.duration.listen(handleDurationUpdate),
      player.stream.playing.listen(handlePlayingUpdate),
      player.stream.buffering.listen(handleBufferingUpdate),
      player.stream.completed.listen((completed) {
        if (completed) onCompleted?.call();
      }),
      player.stream.error.listen(handleErrorEvent),
    ]);
  }

  final ServerConfig _server;

  /// 持有 storage 而非值快照：`open()` 每次都现场读，
  /// 用户在设置页/播放页改的开关无需重进 APP 即可生效。
  final SettingsController _settings;
  final Dio? _dio;
  final LocalAdFilter? _adFilter;
  final VoidCallback? onCompleted;
  final Future<void> Function(String url)? _debugUrlOpener;
  final Future<void> Function(Duration target)? _debugSeekHandler;

  late final Player player;
  late final VideoController videoController;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  /// 清晰度菜单里的「自动」项。
  static const autoQualityLabel = '自动';

  PlaybackContext? _context;
  Duration _position = Duration.zero;
  Duration _lastValidPosition = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _pendingQualitySeek;
  Duration? _recentUserSeekTarget;
  DateTime? _recentUserSeekAt;
  var _seekZeroRecoveryAttempted = false;
  double _rate = 1.0;
  String? _errorDetail;
  String? _rawUrl;
  String? _serverError;
  List<String> _candidates = const [];
  var _candidateIndex = 0;
  var _playing = false;
  var _buffering = false;
  var _hasPlayedAnyFrame = false;
  var _disposed = false;
  var _openGeneration = 0;
  String? _error;
  AdFilterResult? _localAdFilterResult;
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
  List<String> get candidates => List.unmodifiable(_candidates);
  int get candidateIndex => _candidateIndex;
  AdFilterResult? get localAdFilterResult => _localAdFilterResult;

  /// 当前正在使用的候选播放地址。
  String? get currentCandidateUrl {
    if (_candidates.isEmpty ||
        _candidateIndex < 0 ||
        _candidateIndex >= _candidates.length) {
      return null;
    }
    return _candidates[_candidateIndex];
  }

  /// 当前生效的播放链路简短名称（用于诊断展示）。
  ///
  /// 取值：`本地过滤` / `服务端代理` / `直连` / `全量代理`。
  String get activeRouteLabel {
    final url = currentCandidateUrl;
    if (url == null || url.isEmpty) return '直连';
    if (url.startsWith('file://')) return '本地过滤';
    if (url.contains('/api/proxy-m3u8')) {
      if (url.contains('proxySegments=true')) return '全量代理';
      return '服务端代理';
    }
    return '直连';
  }

  /// 当前生效播放链路的详细诊断说明（长按播放页标题展示）。
  String get activeRouteDescription {
    final label = activeRouteLabel;
    final filterResult = _localAdFilterResult;
    if (label == '本地过滤' && filterResult != null) {
      return '当前链路：本地过滤（已剔除 ${filterResult.removedSegments}/${filterResult.totalSegments} 段广告切片）';
    }
    if (_settings.settings.adblock && filterResult?.skippedLive == true) {
      return '当前链路：$label（直播流已跳过本地过滤）';
    }
    return '当前链路：$label';
  }

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

  @visibleForTesting
  void handlePositionUpdate(Duration value) {
    _position = value;
    if (value > const Duration(seconds: 2)) {
      _lastValidPosition = value;
    }
    if (_playing && !_buffering && value > Duration.zero) {
      _hasPlayedAnyFrame = true;
    }
    _checkUnexpectedResetAfterSeek(value);
    notifyListeners();
  }

  @visibleForTesting
  void handleDurationUpdate(Duration value) {
    _duration = value;
    _consumeQualitySeek();
    notifyListeners();
  }

  @visibleForTesting
  void handlePlayingUpdate(bool value) {
    _playing = value;
    if (value && !_buffering && _position > Duration.zero) {
      _hasPlayedAnyFrame = true;
    }
    notifyListeners();
  }

  @visibleForTesting
  void handleBufferingUpdate(bool value) {
    _buffering = value;
    if (!value && _playing && _position > Duration.zero) {
      _hasPlayedAnyFrame = true;
    }
    _consumeQualitySeek();
    if (!value) {
      _checkUnexpectedResetAfterSeek(_position);
    }
    notifyListeners();
  }

  @visibleForTesting
  void handleErrorEvent(String value) {
    // 已经成功出帧且仍在播放中的报错多为单个分片网络抖动，mpv 会自行重试，不应中断界面。
    // 注意：本地 file:// m3u8 在未下载任何分片前就会立即解析出 _duration > 0，
    // 因此必须以 _hasPlayedAnyFrame && _playing 判断是否已稳定起播。
    if (_hasPlayedAnyFrame && _playing) {
      if (kDebugMode) debugPrint('MPV transient error: $value');
      return;
    }
    if (_candidateIndex + 1 < _candidates.length) {
      unawaited(switchToNextCandidate());
      return;
    }
    _error = value.isEmpty ? '播放失败，请尝试切换片源' : '播放失败';
    _errorDetail = _serverError ?? value;
    notifyListeners();
  }

  /// 切换到下一个候选链路，并保留当前播放进度（防止从零播放）。
  Future<bool> switchToNextCandidate() async {
    if (_candidateIndex + 1 >= _candidates.length) return false;
    final resume = _position > const Duration(seconds: 2)
        ? _position
        : _lastValidPosition;
    if (resume > const Duration(seconds: 2)) {
      _pendingQualitySeek ??= resume;
    }
    _candidateIndex++;
    _error = null;
    _errorDetail = null;
    _hasPlayedAnyFrame = false;
    notifyListeners();
    await _openUrl(_candidates[_candidateIndex], preservePosition: true);
    return true;
  }

  Future<void> open(PlaybackContext context) async {
    final generation = ++_openGeneration;
    _context = context;
    _error = null;
    _errorDetail = null;
    _position = Duration.zero;
    _lastValidPosition = Duration.zero;
    _duration = Duration.zero;
    _hasPlayedAnyFrame = false;
    _variants = const [];
    _selectedQuality = autoQualityLabel;
    _pendingQualitySeek = null;
    _recentUserSeekTarget = null;
    _recentUserSeekAt = null;
    _seekZeroRecoveryAttempted = false;
    _localAdFilterResult = null;
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

    final baseCandidates = <String>[proxyUrl, _rawUrl!];
    if (proxyAllUrl != proxyUrl) baseCandidates.add(proxyAllUrl);

    if (settings.adblock &&
        _adFilter != null &&
        _rawUrl!.toLowerCase().contains('.m3u8')) {
      final filterResult = await _adFilter.prepare(
        rawUrl: _rawUrl!,
        proxyUrl: proxyUrl,
        serverBaseUrl: _server.baseUrl,
        source: context.item.source,
        mediaId: '${context.item.id}_$index',
        playbackToken: settings.playbackToken,
        proxySegments: settings.proxySegments,
        preferredQuality: _selectedQuality,
      );
      if (_disposed || generation != _openGeneration) return;
      _localAdFilterResult = filterResult;
      if (filterResult.proxyError != null) {
        _serverError = filterResult.proxyError;
      }
      if (filterResult.isSuccess) {
        // 候选顺序：[本地过滤文件, 服务端代理, 直连, 全量代理]
        _candidates = <String>[filterResult.fileUri!, ...baseCandidates];
        _candidateIndex = 0;
      } else {
        _candidates = baseCandidates;
        _candidateIndex =
            (filterResult.proxyError != null && _candidates.length > 1) ? 1 : 0;
      }
    } else {
      _candidates = baseCandidates;
      _candidateIndex = 0;
      // 先预检代理链路：服务端取流失败时会返回具体 error，
      // 提前跳过可以省掉一次 mpv 失败等待，也能把真实原因显示给用户。
      if (_dio != null) {
        final reason = await _probeProxy(proxyUrl);
        if (_disposed || generation != _openGeneration) return;
        if (reason != null) {
          _serverError = reason;
          if (_candidates.length > 1) _candidateIndex = 1;
          if (kDebugMode) debugPrint('NEWTV proxy probe failed: $reason');
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
        'NEWTV play url ($activeRouteLabel): ${_candidates[_candidateIndex]}',
      );
    }
    await _openUrl(_candidates[_candidateIndex], preservePosition: false);
    if (_disposed || generation != _openGeneration) return;
    // 清晰度探测不阻塞起播：拿到 master 后逐档测速，完成后再刷新菜单。
    if (_rawUrl != null && _rawUrl!.toLowerCase().contains('.m3u8')) {
      unawaited(_probeQuality());
    }
  }

  /// 清晰度切换或候选降级重开后恢复原播放位置。
  void _consumeQualitySeek() {
    final target = _pendingQualitySeek;
    if (target == null || _duration <= Duration.zero || _buffering) return;
    _pendingQualitySeek = null;
    if (target <= Duration.zero) return;
    unawaited(seek(target));
  }

  /// 防快进回零兜底：若用户刚执行了前进/拖动 seek（目标 >= 15s），
  /// 但底层流因未过滤的 #EXT-X-DISCONTINUITY 导致 PTS 重置到 0:00（< 3s），自动补跳一次。
  void _checkUnexpectedResetAfterSeek(Duration currentPos) {
    final target = _recentUserSeekTarget;
    final seekAt = _recentUserSeekAt;
    if (target == null || seekAt == null || _seekZeroRecoveryAttempted) return;
    final elapsed = DateTime.now().difference(seekAt);
    if (elapsed > const Duration(milliseconds: 2800)) {
      _recentUserSeekTarget = null;
      _recentUserSeekAt = null;
      return;
    }
    if (!_buffering &&
        _duration > Duration.zero &&
        target >= const Duration(seconds: 15) &&
        currentPos < const Duration(seconds: 3)) {
      _seekZeroRecoveryAttempted = true;
      unawaited(_performSeek(target));
    }
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
    final generation = ++_openGeneration;
    final context = _context;
    final settings = _settings.settings;
    final resume = _position > const Duration(seconds: 2)
        ? _position
        : _lastValidPosition;
    final rawVariantUrl =
        (sourceUriOf(variant.url) ?? Uri.parse(variant.url)).toString();
    final proxy = sourceUriOf(variant.url) != null
        ? variant.url
        : MediaApi.buildProxyUrl(
            baseUrl: _server.baseUrl,
            rawUrl: rawVariantUrl,
            source: context?.item.source ?? '',
            playbackToken: settings.playbackToken,
            adblock: settings.adblock,
            proxySegments: settings.proxySegments,
          );
    final baseCandidates = sourceUriOf(variant.url) != null
        // 服务端已把它重写成代理地址，补上源站直连作回退。
        ? <String>[variant.url, rawVariantUrl]
        : (proxy == variant.url
            ? <String>[variant.url]
            : <String>[proxy, variant.url]);

    if (settings.adblock && _adFilter != null) {
      final filterResult = await _adFilter.prepare(
        rawUrl: rawVariantUrl,
        proxyUrl: proxy,
        serverBaseUrl: _server.baseUrl,
        source: context?.item.source ?? '',
        mediaId: '${context?.item.id ?? ''}_${context?.episodeIndex ?? 0}_$label',
        playbackToken: settings.playbackToken,
        proxySegments: settings.proxySegments,
        preferredQuality: label,
      );
      if (_disposed || generation != _openGeneration) return;
      _localAdFilterResult = filterResult;
      _candidates = filterResult.isSuccess
          ? <String>[filterResult.fileUri!, ...baseCandidates]
          : baseCandidates;
    } else {
      _localAdFilterResult = null;
      _candidates = baseCandidates;
    }

    _candidateIndex = 0;
    _selectedQuality = label;
    _error = null;
    _errorDetail = null;
    _duration = Duration.zero;
    _position = Duration.zero;
    _hasPlayedAnyFrame = false;
    _pendingQualitySeek =
        resume > const Duration(seconds: 2) ? resume : null;
    notifyListeners();
    if (kDebugMode) {
      debugPrint('NEWTV switch quality ($label): ${_candidates.first}');
    }
    await _openUrl(_candidates.first, preservePosition: false);
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
          (response.headers.value(Headers.contentTypeHeader) ?? '')
              .toLowerCase();
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

  Future<void> _openUrl(String url, {bool preservePosition = true}) async {
    if (preservePosition && _pendingQualitySeek == null) {
      final resume = _position > const Duration(seconds: 2)
          ? _position
          : _lastValidPosition;
      if (resume > const Duration(seconds: 2)) {
        _pendingQualitySeek = resume;
      }
    }
    try {
      final opener = _debugUrlOpener;
      if (opener != null) {
        await opener(url);
        return;
      }
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

  Future<void> toggle() async => _playing ? player.pause() : player.play();

  Future<void> seek(Duration value) {
    final target = value < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && value > _duration
            ? _duration
            : value);
    if (target > const Duration(seconds: 2)) {
      _lastValidPosition = target;
    }
    if (target >= const Duration(seconds: 15)) {
      _recentUserSeekTarget = target;
      _recentUserSeekAt = DateTime.now();
      _seekZeroRecoveryAttempted = false;
    } else {
      _recentUserSeekTarget = null;
      _recentUserSeekAt = null;
    }
    return _performSeek(target);
  }

  Future<void> _performSeek(Duration target) {
    final handler = _debugSeekHandler;
    if (handler != null) {
      return handler(target);
    }
    return player.seek(target);
  }

  Future<void> seekRelative(Duration delta) => seek(_position + delta);

  Future<void> setRate(double rate) {
    _rate = rate;
    notifyListeners();
    if (_debugUrlOpener != null) return Future.value();
    return player.setRate(rate);
  }

  Future<void> setVolume(double volume) {
    if (_debugUrlOpener != null) return Future.value();
    return player.setVolume(volume.clamp(0, 100));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_debugUrlOpener == null) {
      unawaited(player.dispose());
    }
    super.dispose();
  }
}
