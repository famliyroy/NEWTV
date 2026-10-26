import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  Timer? _hideTimer;
  var _controlsVisible = true;
  var _temporaryRate = false;
  double? _previousRate;

  @override
  void initState() {
    super.initState();
    final dependencies = ref.read(appDependenciesProvider);
    final settings = dependencies.settings.settings;
    final server = dependencies.session.server!;
    _player = PlayerController(server: server, settings: settings);
    _danmaku = DanmakuController(
      DanmakuRepository(DanmakuApi(dependencies.dioClient.dio)),
      dependencies.settings,
    );
    _player.addListener(() => _danmaku.setPosition(_player.position.inMilliseconds / 1000));
    unawaited(_player.open(widget.playback));
    unawaited(_danmaku.loadFor(widget.playback));
    _enterImmersiveMode();
    _scheduleHide();
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
    if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (mounted) Navigator.of(context).maybePop();
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
    _previousRate = 1;
    _temporaryRate = true;
    unawaited(_player.setRate(2));
  }

  void _stopTemporaryRate() {
    if (!_temporaryRate) return;
    _temporaryRate = false;
    unawaited(_player.setRate(_previousRate ?? 1));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
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
                      title: '${widget.playback.item.title} · ${widget.playback.item.episodeLabel(widget.playback.episodeIndex)}',
                      onBack: _exitPage,
                      onToggle: () => unawaited(_player.toggle()),
                      onSeek: (value) => unawaited(_player.seek(value)),
                      onBack10: () => unawaited(_player.seekRelative(const Duration(seconds: -10))),
                      onForward10: () => unawaited(_player.seekRelative(const Duration(seconds: 10))),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 44),
            const SizedBox(height: 12),
            Text(error, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            FilledButton(onPressed: player.retry, child: const Text('重试')),
          ],
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
                            ],
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
                            child: Row(
                              children: [
                                Text(_format(position), style: const TextStyle(color: Colors.white70)),
                                const Spacer(),
                                GestureDetector(
                                  onLongPress: onDanmakuSettings,
                                  child: IconButton.filledTonal(
                                    tooltip: danmaku.enabled ? '关闭弹幕' : '开启弹幕',
                                    onPressed: onToggleDanmaku,
                                    icon: Icon(danmaku.enabled ? Icons.subtitles : Icons.subtitles_off),
                                  ),
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
