import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/player/player_controller.dart';
import '../../data/api/danmaku_api.dart';
import '../../data/repositories/danmaku_repository.dart';
import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../danmaku/danmaku_controller.dart';
import '../danmaku/danmaku_overlay.dart';
import '../danmaku/danmaku_settings_sheet.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({required this.playback, super.key});

  final PlaybackContext playback;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final PlayerController _player;
  late final DanmakuController _danmaku;
  late PlaybackContext _currentPlayback;
  Timer? _hideTimer;
  Timer? _progressSyncTimer;
  var _controlsVisible = true;
  var _temporaryRate = false;
  var _leaving = false;
  double? _previousRate;
  BoxFit _videoFit = BoxFit.contain;

  @override
  void initState() {
    super.initState();
    _currentPlayback = widget.playback;
    final dependencies = ref.read(appDependenciesProvider);
    final settings = dependencies.settings.settings;
    final server = dependencies.session.server!;
    _player = PlayerController(
      server: server,
      settings: settings,
      onCompleted: _handleEpisodeCompleted,
    );
    _danmaku = DanmakuController(
      DanmakuRepository(DanmakuApi(dependencies.dioClient.dio)),
      dependencies.settings,
    );
    _player.addListener(() => _danmaku.setPosition(_player.position.inMilliseconds / 1000));
    unawaited(_player.open(_currentPlayback));
    unawaited(_danmaku.loadFor(_currentPlayback));
    _progressSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncPlayProgress()),
    );
    _enterImmersiveMode();
    _scheduleHide();
  }

  Future<void> _syncPlayProgress() async {
    final playSec = _player.position.inSeconds;
    final totalSec = _player.duration.inSeconds;
    if (playSec <= 0) return;
    try {
      await ref.read(appDependenciesProvider).mediaRepository.savePlayRecord(
            _currentPlayback.item,
            episodeIndex: _currentPlayback.episodeIndex,
            playTimeSeconds: playSec,
            totalTimeSeconds: totalSec,
          );
    } on Object {
      // Progress sync errors should not interrupt playback.
    }
  }

  void _handleEpisodeCompleted() {
    unawaited(_syncPlayProgress());
    final settings = ref.read(appDependenciesProvider).settings.settings;
    if (settings.autoplayNext && _player.hasNextEpisode) {
      unawaited(_switchEpisode(_currentPlayback.episodeIndex + 1));
    }
  }

  Future<void> _switchEpisode(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= _currentPlayback.item.episodes.length) return;
    await _syncPlayProgress();
    _danmaku.clear();
    final nextContext = PlaybackContext(
      item: _currentPlayback.item,
      episodeIndex: nextIndex,
      availableSources: _currentPlayback.availableSources,
    );
    if (!mounted) return;
    setState(() => _currentPlayback = nextContext);
    unawaited(_player.open(nextContext));
    unawaited(_danmaku.loadFor(nextContext));
  }

  void _enterImmersiveMode() {
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _exitPage() async {
    if (_leaving) return;
    _leaving = true;
    _hideTimer?.cancel();
    _progressSyncTimer?.cancel();
    // 退出前把进度写回服务端，失败不阻塞返回。
    await _syncPlayProgress().catchError((_) {});
    if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (!mounted) return;
    // go_router 下必须用 router 的 pop，Navigator.maybePop 会静默失败导致卡在播放页。
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  Future<void> _toggleFullscreen() async {
    if (Platform.isWindows) {
      final full = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!full);
    }
  }

  void _startTemporaryRate() {
    if (_temporaryRate) return;
    _previousRate = _player.rate;
    _temporaryRate = true;
    unawaited(_player.setRate(2));
  }

  void _stopTemporaryRate() {
    if (!_temporaryRate) return;
    _temporaryRate = false;
    unawaited(_player.setRate(_previousRate ?? 1));
  }

  void _cycleVideoFit() {
    setState(() {
      _videoFit = switch (_videoFit) {
        BoxFit.contain => BoxFit.cover,
        BoxFit.cover => BoxFit.fill,
        _ => BoxFit.contain,
      };
    });
    _showControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressSyncTimer?.cancel();
    _player.dispose();
    _danmaku.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appDependenciesProvider).settings.settings;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_exitPage());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () => unawaited(_player.toggle()),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => unawaited(_player.seekRelative(const Duration(seconds: -5))),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => unawaited(_player.seekRelative(const Duration(seconds: 5))),
          const SingleActivator(LogicalKeyboardKey.keyF): () => unawaited(_toggleFullscreen()),
          const SingleActivator(LogicalKeyboardKey.keyD): () => _danmaku.setEnabled(!_danmaku.enabled),
          const SingleActivator(LogicalKeyboardKey.keyN): () {
            if (_player.hasNextEpisode) {
              unawaited(_switchEpisode(_currentPlayback.episodeIndex + 1));
            }
          },
          const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_exitPage()),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: MouseRegion(
              onHover: (_) => _showControls(),
              child: GestureDetector(
                onTap: _toggleControls,
                onDoubleTapDown: (details) {
                  final width = MediaQuery.sizeOf(context).width;
                  if (details.localPosition.dx < width * 0.36) {
                    unawaited(_player.seekRelative(const Duration(seconds: -10)));
                  } else if (details.localPosition.dx > width * 0.64) {
                    unawaited(_player.seekRelative(const Duration(seconds: 10)));
                  } else {
                    unawaited(_player.toggle());
                  }
                  _showControls();
                },
                onLongPressStart: (_) => _startTemporaryRate(),
                onLongPressEnd: (_) => _stopTemporaryRate(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(
                      controller: _player.videoController,
                      fit: _videoFit,
                      controls: (state) => const SizedBox.shrink(),
                    ),
                    DanmakuOverlay(controller: _danmaku, settings: settings),
                    AnimatedBuilder(
                      animation: _player,
                      builder: (context, child) => _PlayerStatus(player: _player),
                    ),
                    _ControlsOverlay(
                      player: _player,
                      danmaku: _danmaku,
                      visible: _controlsVisible,
                      title: '${_currentPlayback.item.title} · ${_currentPlayback.item.episodeLabel(_currentPlayback.episodeIndex)}',
                      onBack: _exitPage,
                      onToggle: () => unawaited(_player.toggle()),
                      onSeek: (value) => unawaited(_player.seek(value)),
                      onBack10: () => unawaited(_player.seekRelative(const Duration(seconds: -10))),
                      onForward10: () => unawaited(_player.seekRelative(const Duration(seconds: 10))),
                      onNextEpisode: _player.hasNextEpisode
                          ? () => unawaited(_switchEpisode(_currentPlayback.episodeIndex + 1))
                          : null,
                      onRateChanged: (rate) => unawaited(_player.setRate(rate)),
                      onCycleFit: _cycleVideoFit,
                      onToggleDanmaku: () => _danmaku.setEnabled(!_danmaku.enabled),
                      onDanmakuSettings: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => const DanmakuSettingsSheet(),
                        );
                      },
                      onInteract: _showControls,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerStatus extends StatelessWidget {
  const _PlayerStatus({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final error = player.error;
    if (error != null) {
      final detail = player.errorDetail;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 44),
              const SizedBox(height: 12),
              Text(error, style: const TextStyle(color: Colors.white)),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(onPressed: player.retry, child: const Text('重试')),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (player.buffering || player.duration == Duration.zero) {
      return const Center(child: CircularProgressIndicator());
    }
    return const SizedBox.shrink();
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.player,
    required this.danmaku,
    required this.visible,
    required this.title,
    required this.onBack,
    required this.onToggle,
    required this.onSeek,
    required this.onBack10,
    required this.onForward10,
    required this.onNextEpisode,
    required this.onRateChanged,
    required this.onCycleFit,
    required this.onToggleDanmaku,
    required this.onDanmakuSettings,
    required this.onInteract,
  });

  final PlayerController player;
  final DanmakuController danmaku;
  final bool visible;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onBack10;
  final VoidCallback onForward10;
  final VoidCallback? onNextEpisode;
  final ValueChanged<double> onRateChanged;
  final VoidCallback onCycleFit;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onDanmakuSettings;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([player, danmaku]),
      builder: (context, child) {
        final duration = player.duration;
        final position = player.position;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 24,
              right: 24,
              bottom: visible ? 76 : 12,
              child: _ProgressBar(
                position: position,
                duration: duration,
                onChanged: onSeek,
                onInteract: onInteract,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.62),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton.filledTonal(
                                tooltip: '切换画面比例',
                                onPressed: onCycleFit,
                                icon: const Icon(Icons.aspect_ratio),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _RoundControl(icon: Icons.replay_10, tooltip: '后退 10 秒', onPressed: onBack10),
                              const SizedBox(width: 32),
                              _RoundControl(
                                icon: player.playing ? Icons.pause : Icons.play_arrow,
                                tooltip: player.playing ? '暂停' : '播放',
                                large: true,
                                onPressed: onToggle,
                              ),
                              const SizedBox(width: 32),
                              _RoundControl(icon: Icons.forward_10, tooltip: '前进 10 秒', onPressed: onForward10),
                              if (onNextEpisode != null) ...[
                                const SizedBox(width: 24),
                                _RoundControl(icon: Icons.skip_next, tooltip: '下一集', onPressed: onNextEpisode!),
                              ],
                            ],
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
                            child: Row(
                              children: [
                                Text(_format(position), style: const TextStyle(color: Colors.white70)),
                                const Spacer(),
                                PopupMenuButton<double>(
                                  tooltip: '倍速',
                                  initialValue: player.rate,
                                  onSelected: onRateChanged,
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 0.5, child: Text('0.5x')),
                                    PopupMenuItem(value: 0.75, child: Text('0.75x')),
                                    PopupMenuItem(value: 1.0, child: Text('1.0x')),
                                    PopupMenuItem(value: 1.25, child: Text('1.25x')),
                                    PopupMenuItem(value: 1.5, child: Text('1.5x')),
                                    PopupMenuItem(value: 2.0, child: Text('2.0x')),
                                    PopupMenuItem(value: 3.0, child: Text('3.0x')),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: Text(
                                      '${player.rate.toStringAsFixed(player.rate == player.rate.roundToDouble() ? 1 : 2)}x',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onLongPress: onDanmakuSettings,
                                  child: IconButton.filledTonal(
                                    tooltip: danmaku.enabled ? '关闭弹幕（长按设置）' : '开启弹幕（长按设置）',
                                    onPressed: onToggleDanmaku,
                                    icon: Icon(danmaku.enabled ? Icons.subtitles : Icons.subtitles_off),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton.filledTonal(
                                  tooltip: '弹幕设置',
                                  onPressed: onDanmakuSettings,
                                  icon: const Icon(Icons.tune, size: 20),
                                ),
                                const SizedBox(width: 8),
                                Text(_format(duration), style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.onChanged,
    required this.onInteract,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChanged;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final current = position.inMilliseconds.clamp(0, total <= 0 ? 1 : total);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        min: 0,
        max: total <= 0 ? 1 : total.toDouble(),
        value: current.toDouble(),
        onChangeStart: (_) => onInteract(),
        onChanged: (value) {
          onInteract();
          onChanged(Duration(milliseconds: value.round()));
        },
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.large = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: Size.square(large ? 68 : 54),
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        foregroundColor: Colors.white,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: large ? 38 : 28),
    );
  }
}
