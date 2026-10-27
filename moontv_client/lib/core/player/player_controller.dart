import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_settings.dart';
import '../../core/config/server_config.dart';
import '../../data/api/media_api.dart';
import '../../domain/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required ServerConfig server,
    required AppSettings settings,
    this.onCompleted,
  })  : _server = server,
        _settings = settings,
        player = Player(
          configuration: PlayerConfiguration(
            logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
          ),
        ) {
    videoController = VideoController(player);
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
        _errorDetail = value;
        notifyListeners();
      }),
    ]);
  }

  final ServerConfig _server;
  final AppSettings _settings;
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
    final proxyUrl = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: _rawUrl!,
      source: context.item.source,
      playbackToken: _settings.playbackToken,
      adblock: _settings.adblock,
      proxySegments: _settings.proxySegments,
    );
    // m3u8 走服务端代理可避开源站的 Brotli 压缩兼容问题（libmpv 无法解压），
    // 分片仍直连以保证速度；代理不可用时自动回退直连。
    _candidates = [proxyUrl, _rawUrl!];
    _candidateIndex = 0;
    if (kDebugMode) debugPrint('NEWTV play url: ${_candidates.first}');
    await _openUrl(_candidates.first);
  }

  Future<void> _openUrl(String url) async {
    try {
      await player.open(
        Media(
          url,
          httpHeaders: {
            'User-Agent': _server.userAgent,
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
