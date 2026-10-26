import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_settings.dart';
import '../../core/config/server_config.dart';
import '../../data/api/media_api.dart';
import '../../domain/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({required ServerConfig server, required AppSettings settings})
      : _server = server,
        _settings = settings,
        player = Player() {
    videoController = VideoController(player);
    _subscriptions.addAll([
      player.stream.position.listen((value) {
        _position = value;
        notifyListeners();
      }),
      player.stream.duration.listen((value) {
        _duration = value;
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
      player.stream.error.listen((value) {
        _error = '播放失败，请尝试切换片源';
        notifyListeners();
      }),
    ]);
  }

  final ServerConfig _server;
  final AppSettings _settings;
  final Player player;
  late final VideoController videoController;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  PlaybackContext? _context;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  var _playing = false;
  var _buffering = false;
  String? _error;

  PlaybackContext? get context => _context;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get buffering => _buffering;
  String? get error => _error;

  Future<void> open(PlaybackContext context) async {
    _context = context;
    _error = null;
    notifyListeners();
    final rawUrl = context.item.episodes[context.episodeIndex];
    final proxyUrl = MediaApi.buildProxyUrl(
      baseUrl: _server.baseUrl,
      rawUrl: rawUrl,
      source: context.item.source,
      adblock: _settings.adblock,
      proxySegments: _settings.proxySegments,
    );
    try {
      await player.open(
        Media(proxyUrl, httpHeaders: {'User-Agent': _server.userAgent}),
        play: true,
      );
    } on Object {
      _error = '无法打开播放地址';
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
  Future<void> setRate(double rate) => player.setRate(rate);
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
