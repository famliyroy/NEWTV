import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/player/player_controller.dart';
import '../../core/utils/playback_resume.dart';
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

  /// 断点续播提示（秒）；非空时在左下角显示「上次播放到 XX:XX，点击跳转」。
  int? _resumeHint;
  Timer? _resumeHintTimer;

  @override
  void initState() {
    super.initState();
    _currentPlayback = widget.playback;
    final dependencies = ref.read(appDependenciesProvider);
    final server = dependencies.session.server!;
    _player = PlayerController(
      server: server,
      // 传 storage 而不是值快照：去广告/代理分片/令牌改完无需重进页面。
      settings: dependencies.settings,
      dio: dependencies.dioClient.dio,
      onCompleted: _handleEpisodeCompleted,
    );
    _danmaku = DanmakuController(dependencies.danmakuRepository, dependencies.settings);
    _player.addListener(() {
      _danmaku
        ..setPosition(_player.position.inMilliseconds / 1000)
        ..setPlaying(_player.playing)
        ..setRate(_player.rate);
    });
    unawaited(_player.open(_currentPlayback));
    unawaited(_danmaku.loadFor(_currentPlayback));
    _progressSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncPlayProgress()),
    );
    _enterImmersiveMode();
    _scheduleHide();
    unawaited(_checkResumeHint());
  }

  /// 兜底续播：详情页没带初始位置时（例如从搜索直接进来），
  /// 再查一次播放记录，命中同集且 >10s 时给一个可点击的提示。
  Future<void> _checkResumeHint() async {
    if (_currentPlayback.initialPositionSeconds > 0) return;
    if (_currentPlayback.item.source.isEmpty || _currentPlayback.item.id.isEmpty) {
      return;
    }
    try {
      final record = await ref
          .read(appDependenciesProvider)
          .mediaRepository
          .playRecordFor(_currentPlayback.item);
      if (!mounted || record == null) return;
      if (record.lastEpisodeIndex != _currentPlayback.episodeIndex) return;
      if (record.playTimeSeconds < 10) return;
      // 停在片尾的记录不必提示「从上次继续」。
      if (record.totalTimeSeconds > 0 &&
          record.playTimeSeconds >=
              record.totalTimeSeconds - nearEndThresholdSeconds) {
        return;
      }
      // 播放器已经开始推进就不该再提示「从上次继续」。
      if (_player.position.inSeconds > 10) return;
      setState(() => _resumeHint = record.playTimeSeconds);
      _resumeHintTimer?.cancel();
      _resumeHintTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _resumeHint = null);
      });
    } on Object {
      // 提示属增强信息，失败静默。
    }
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
    final settings = ref.read(settingsProvider).settings;
    if (settings.autoplayNext && _player.hasNextEpisode) {
      unawaited(_switchEpisode(_currentPlayback.episodeIndex + 1));
    }
  }

  Future<void> _switchEpisode(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= _currentPlayback.item.episodes.length) return;
    await _syncPlayProgress();
    _danmaku.clear();
    _resumeHintTimer?.cancel();
    final nextContext = PlaybackContext(
      item: _currentPlayback.item,
      episodeIndex: nextIndex,
      availableSources: _currentPlayback.availableSources,
    );
    if (!mounted) return;
    setState(() {
      _currentPlayback = nextContext;
      _resumeHint = null;
    });
    unawaited(_player.open(nextContext));
    unawaited(_danmaku.loadFor(nextContext));
    unawaited(_checkResumeHint());
  }

  /// 换源：保留当前集号（对齐到新源的同一集），不必退回详情页。
  Future<void> _pickSource() async {
    final sources = _currentPlayback.availableSources
        .where((item) => item.episodes.isNotEmpty)
        .toList();
    if (sources.length < 2) return;
    final picked = await showModalBottomSheet<MediaItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.outline,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '切换播放源',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).maybePop(),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                controller: scrollController,
                children: [
                  for (final item in sources)
                    ListTile(
                      leading: Icon(
                        item.source == _currentPlayback.item.source
                            ? Icons.check_circle
                            : Icons.movie_outlined,
                      ),
                      title: Text(
                        item.sourceName.isEmpty ? item.source : item.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('共 ${item.episodes.length} 集'),
                      onTap: () => Navigator.of(sheetContext).pop(item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _syncPlayProgress().catchError((_) {});
    final index =
        _currentPlayback.episodeIndex.clamp(0, picked.episodes.length - 1);
    final next = PlaybackContext(
      item: picked,
      episodeIndex: index,
      availableSources: _currentPlayback.availableSources,
    );
    _danmaku.clear();
    _resumeHintTimer?.cancel();
    setState(() {
      _currentPlayback = next;
      _resumeHint = null;
    });
    unawaited(_player.open(next));
    unawaited(_danmaku.loadFor(next));
    unawaited(_checkResumeHint());
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
      context.pop(_currentPlayback.item);
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
    _resumeHintTimer?.cancel();
    _player.dispose();
    _danmaku.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // watch（不是 read）：设置在播放中改动要立即反映到弹幕/沉浸样式。
    final settings = ref.watch(settingsProvider).settings;
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
                    DanmakuOverlay(
                      controller: _danmaku,
                      settings: settings,
                      // 控制栏收起时，弹幕状态胶囊一并隐藏。
                      showStatus: _controlsVisible,
                    ),
                    if (_resumeHint != null)
                      Positioned(
                        left: 24,
                        bottom: 118,
                        child: _ResumeHint(
                          seconds: _resumeHint!,
                          onTap: () {
                            final target = Duration(seconds: _resumeHint!);
                            _resumeHintTimer?.cancel();
                            setState(() => _resumeHint = null);
                            unawaited(_player.seek(target));
                          },
                          onDismiss: () {
                            _resumeHintTimer?.cancel();
                            setState(() => _resumeHint = null);
                          },
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _player,
                      builder: (context, child) => _PlayerStatus(
                        player: _player,
                        onSwitchSource: _currentPlayback.availableSources.length > 1
                            ? _pickSource
                            : null,
                      ),
                    ),
                    _ControlsOverlay(
                      player: _player,
                      danmaku: _danmaku,
                      visible: _controlsVisible,
                      miniProgress: settings.immersiveMiniProgress,
                      title: '${_currentPlayback.item.title} · ${_currentPlayback.item.episodeLabel(_currentPlayback.episodeIndex)}',
                      canSwitchSource: _currentPlayback.availableSources.length > 1,
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
                      onSwitchSource: _pickSource,
                      onToggleDanmaku: () => _danmaku.setEnabled(!_danmaku.enabled),
                      onDanmakuSettings: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (sheetContext) => DraggableScrollableSheet(
                            expand: false,
                            initialChildSize: 0.9,
                            minChildSize: 0.28,
                            maxChildSize: 0.95,
                            builder: (context, scrollController) =>
                                DanmakuSettingsSheet(
                              controller: _danmaku,
                              scrollController: scrollController,
                            ),
                          ),
                        );
                        _showControls();
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

/// 「从上次位置继续？（XX:XX）」提示条。
///
/// 对齐网页版 MoonTVPlus 的 play-record-jump 交互：支持点击继续或「从头播」，5 秒无操作自动收起。
class _ResumeHint extends StatelessWidget {
  const _ResumeHint({
    required this.seconds,
    required this.onTap,
    required this.onDismiss,
  });

  final int seconds;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              '从上次位置继续？（${_clockLabel(seconds)}）',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(width: 6),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onTap,
              child: const Text('继续', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onDismiss,
              child: const Text('从头播', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

String _clockLabel(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

class _PlayerStatus extends StatelessWidget {
  const _PlayerStatus({required this.player, this.onSwitchSource});

  final PlayerController player;
  final VoidCallback? onSwitchSource;

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
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(onPressed: player.retry, child: const Text('重试')),
                  if (onSwitchSource != null)
                    OutlinedButton.icon(
                      onPressed: onSwitchSource,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('切换播放源'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
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
    required this.miniProgress,
    required this.title,
    required this.canSwitchSource,
    required this.onBack,
    required this.onToggle,
    required this.onSeek,
    required this.onBack10,
    required this.onForward10,
    required this.onNextEpisode,
    required this.onRateChanged,
    required this.onCycleFit,
    required this.onSwitchSource,
    required this.onToggleDanmaku,
    required this.onDanmakuSettings,
    required this.onInteract,
  });

  final PlayerController player;
  final DanmakuController danmaku;
  final bool visible;

  /// 沉浸态保留一条极细进度条（默认关）。
  final bool miniProgress;
  final String title;
  final bool canSwitchSource;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onBack10;
  final VoidCallback onForward10;
  final VoidCallback? onNextEpisode;
  final ValueChanged<double> onRateChanged;
  final VoidCallback onCycleFit;
  final VoidCallback onSwitchSource;
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
        final fraction = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 沉浸态：可选择保留一条 2px 的进度细线，否则完全无 UI。
            if (miniProgress && !visible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(
                      value: fraction,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Colors.white70),
                    ),
                  ),
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
                              if (canSwitchSource)
                                IconButton.filledTonal(
                                  tooltip: '切换播放源',
                                  onPressed: onSwitchSource,
                                  icon: const Icon(Icons.swap_horiz),
                                ),
                              const SizedBox(width: 8),
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
                                _QualityButton(player: player),
                                const SizedBox(width: 6),
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
            // 进度条必须置于渐变遮罩层（DecoratedBox）之上，否则全屏 DecoratedBox 会拦截拖拽手势。
            Positioned(
              left: 24,
              right: 24,
              bottom: 72,
              child: IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: PlayerProgressBar(
                    position: position,
                    duration: duration,
                    onSeek: onSeek,
                    onInteract: onInteract,
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

/// 清晰度入口：单码率只显示「自动（单一流）」，不做报错。
class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final variants = player.variants;
    if (variants.isEmpty) {
      if (player.probingQuality) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        );
      }
      if (player.singleStreamQuality) {
        // 单码率：只提示存在单一流，不提供无意义的切换菜单。
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '自动（单一流）',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    final items = <PopupMenuEntry<String>>[      PopupMenuItem(
        value: PlayerController.autoQualityLabel,
        child: _QualityRow(
          label: PlayerController.autoQualityLabel,
          hint: '取测速最优',
          selected: player.selectedQuality == PlayerController.autoQualityLabel,
        ),
      ),
      const PopupMenuDivider(),
      for (final variant in variants)
        PopupMenuItem(
          value: variant.label,
          child: _QualityRow(
            label: variant.label,
            hint: variant.speedLabel,
            selected: player.selectedQuality == variant.label,
          ),
        ),
    ];
    return PopupMenuButton<String>(
      tooltip: '清晰度',
      onSelected: (value) => unawaited(player.selectQuality(value)),
      itemBuilder: (context) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.high_quality_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              player.selectedQuality,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.label, required this.hint, required this.selected});

  final String label;
  final String hint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          selected ? Icons.check : Icons.circle_outlined,
          size: 16,
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
        ),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        Text(hint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 播放器进度条：维护本地拖拽态与 seek 收敛窗口。
///
/// - 拖动期间仅更新本地预览值并展示 `mm:ss / mm:ss` 气泡，忽略实时位置流推送、不触发底层 seek；
/// - 松手（`onChangeEnd`）时只发一次真实 seek；
/// - seek 发出后保持落点位置，待位置流跳到落点（误差 < 1s）或超时后再交回控制权，避免拇指闪回原处。
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onInteract,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onInteract;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  static const _convergenceThresholdMs = 1000;
  static const _convergenceHoldDuration = Duration(milliseconds: 1500);

  var _dragging = false;
  var _dragMs = 0.0;
  double? _pendingSeekMs;
  Timer? _convergenceTimer;

  @override
  void didUpdateWidget(covariant PlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration &&
        widget.duration <= Duration.zero) {
      _convergenceTimer?.cancel();
      _dragging = false;
      _pendingSeekMs = null;
      return;
    }
    if (!_dragging && _pendingSeekMs != null) {
      final diff =
          (widget.position.inMilliseconds - _pendingSeekMs!).abs();
      if (diff <= _convergenceThresholdMs) {
        _convergenceTimer?.cancel();
        _pendingSeekMs = null;
      }
    }
  }

  @override
  void dispose() {
    _convergenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final maxMs = totalMs <= 0 ? 1.0 : totalMs.toDouble();
    final rawMs = _dragging
        ? _dragMs
        : (_pendingSeekMs ?? widget.position.inMilliseconds.toDouble());
    final currentMs = rawMs.clamp(0.0, maxMs);
    final previewSec = (currentMs / 1000).round();
    final totalSec = totalMs <= 0 ? 0 : (totalMs / 1000).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_dragging)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24, width: 0.5),
            ),
            child: Text(
              '${_clockLabel(previewSec)} / ${_clockLabel(totalSec)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: _dragging ? 4 : 3,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: _dragging ? 8 : 6,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            min: 0,
            max: maxMs,
            value: currentMs,
            onChangeStart: totalMs <= 0
                ? null
                : (value) {
                    widget.onInteract();
                    _convergenceTimer?.cancel();
                    setState(() {
                      _dragging = true;
                      _dragMs = value;
                      _pendingSeekMs = null;
                    });
                  },
            onChanged: totalMs <= 0
                ? null
                : (value) {
                    widget.onInteract();
                    setState(() {
                      _dragging = true;
                      _dragMs = value;
                    });
                  },
            onChangeEnd: totalMs <= 0
                ? null
                : (value) {
                    widget.onInteract();
                    final targetMs = value.round().clamp(0, totalMs);
                    _convergenceTimer?.cancel();
                    setState(() {
                      _dragging = false;
                      _pendingSeekMs = targetMs.toDouble();
                    });
                    _convergenceTimer = Timer(_convergenceHoldDuration, () {
                      if (mounted && _pendingSeekMs != null) {
                        setState(() => _pendingSeekMs = null);
                      }
                    });
                    widget.onSeek(Duration(milliseconds: targetMs));
                  },
          ),
        ),
      ],
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
