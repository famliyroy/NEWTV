import '../../domain/models/media_item.dart';

/// 距片尾多少秒以内视为「已看完」：可以定位到该集，但不再从片尾继续播。
const nearEndThresholdSeconds = 30;

/// 播放记录映射到当前片源后得到的「上次观看点」。
class ResumePoint {
  const ResumePoint({
    required this.episodeIndex,
    required this.startSeconds,
    required this.totalSeconds,
    required this.finished,
  });

  /// 上次观看的集下标（已按当前片源的集数钳制）。
  final int episodeIndex;

  /// 应当继续播放的秒数；片尾记录或异常值时为 0。
  final int startSeconds;

  final int totalSeconds;

  /// 记录已接近片尾。
  final bool finished;

  /// 是否值得提示「上次看到 第X集 XX:XX」。
  bool get hasProgress => startSeconds > 0;
}

/// 把播放记录（按 `storageKey` 匹配到的同一部片）映射到当前片源的集数上。
///
/// 返回 null 表示没有可用记录（没有记录、没有集数、或记录全为 0）。
ResumePoint? resolveResumePoint({
  required MediaItem item,
  required MediaItem? record,
}) {
  if (record == null) return null;
  if (item.episodes.isEmpty) return null;
  final index = record.lastEpisodeIndex.clamp(0, item.episodes.length - 1);
  final seconds = record.playTimeSeconds;
  if (index <= 0 && seconds <= 0) return null;
  final total = record.totalTimeSeconds;
  final finished = total > 0 && seconds >= total - nearEndThresholdSeconds;
  return ResumePoint(
    episodeIndex: index,
    startSeconds: finished ? 0 : seconds,
    totalSeconds: total,
    finished: finished,
  );
}

/// 起播位置：**只有选中集等于记录集数**才续播，其它集必须从头开始。
int resumeStartSeconds({
  required MediaItem item,
  required int selectedEpisode,
}) {
  if (item.playTimeSeconds <= 0) return 0;
  if (selectedEpisode != item.lastEpisodeIndex) return 0;
  final total = item.totalTimeSeconds;
  if (total > 0 && item.playTimeSeconds >= total - nearEndThresholdSeconds) {
    return 0;
  }
  return item.playTimeSeconds;
}
