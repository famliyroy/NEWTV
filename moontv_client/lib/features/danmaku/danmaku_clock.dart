/// 弹幕时间轴：把播放器 10~20Hz 的离散位置上报，插值成屏幕刷新节奏的连续时间。
///
/// 核心思想——播放器位置只作**锚点**，每帧位置 = 锚点 + (墙钟差值 × 播放速率)。
/// 绝不能每帧直接跳到播放器上报的位置：位置是按 PTS 量化的（几十到几百毫秒
/// 一台阶），硬对齐会把台阶带回画面，表现就是「一前一后地顿挫」。
///
/// 误差处理分两档：
/// - 小误差（< [hardSyncThreshold]）：每次只吃掉 [correctionRatio]（20%），
///   收敛快且每步远小于一个像素，肉眼不可见；
/// - 大跳变（seek / 切集 / 长时间缓冲）：硬同步，并由调用方重置轨道分配。
class DanmakuClock {
  /// [now] 可注入（测试用假的墙钟）；默认用进程级 Stopwatch，避免反复创建。
  DanmakuClock({double Function()? now}) : _now = now ?? _defaultNow;

  static final _stopwatch = Stopwatch()..start();
  static double _defaultNow() => _stopwatch.elapsedMicroseconds / 1e6;

  /// 超过这个偏差就认定为 seek/切集，而不是插值误差。
  static const hardSyncThreshold = 1.0;

  /// 每次上报只修正 20% 的偏差，避免量化台阶重新出现。
  static const correctionRatio = 0.2;

  final double Function() _now;

  double _anchorMedia = 0;
  double _anchorClock = 0;
  double _rate = 1;
  var _anchored = false;

  double get now => _now();
  double get rate => _rate;
  bool get anchored => _anchored;

  /// 当前应显示的位置（秒）。
  double get position =>
      _anchored ? _anchorMedia + (now - _anchorClock) * _rate : _anchorMedia;

  /// 播放速率（0.1x~4x，覆盖 UI 的 0.5x~3x）。
  void setRate(double value) {
    if (value <= 0) return;
    _rate = value.clamp(0.1, 4.0);
  }

  /// 硬对齐到某个位置（切集 / 恢复播放 / 暂停时更新）。
  void reset(double mediaPosition) {
    _anchorMedia = mediaPosition;
    _anchorClock = now;
    _anchored = true;
  }

  /// 播放器上报了一个新位置。
  ///
  /// 返回 true 表示发生了硬跳变，调用方应重置轨道分配。
  bool report(double mediaPosition) {
    if (!_anchored) {
      reset(mediaPosition);
      return false;
    }
    final drift = mediaPosition - position;
    if (drift.abs() > hardSyncThreshold) {
      reset(mediaPosition);
      return true;
    }
    // 只调整时间原点（等价于把位置挪 20% 偏差），位置本身保持连续。
    _anchorClock -= correctionRatio * drift / _rate;
    return false;
  }
}
