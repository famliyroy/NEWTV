import '../models/danmaku.dart';

/// 弹幕轨道分配器。
///
/// 每条轨道只记录一个 `freeAt`：该轨道最早可以再进场一条弹幕的时刻。
/// 新弹幕取**第一条** `freeAt <= 入场时刻` 的轨道；全部占用则丢弃这条弹幕
/// （B 站的行为，宁缺毋滥，避免叠字）。
///
/// 分配结果按弹幕键缓存，因此同一条弹幕从进场到离场**行号不变**，
/// 不会因为 active 列表进出而上下跳行。
class DanmakuTrackAllocator {
  final _scrollFreeAt = <double>[];
  final _topFreeAt = <double>[];
  final _bottomFreeAt = <double>[];
  final _rows = <String, int>{};
  final _rejected = <String>{};

  int _scrollRows = -1;
  int _topRows = -1;
  int _bottomRows = -1;

  int get scrollRows => _scrollRows < 0 ? 0 : _scrollRows;
  int get topRows => _topRows < 0 ? 0 : _topRows;
  int get bottomRows => _bottomRows < 0 ? 0 : _bottomRows;

  /// 轨道数变化（屏幕尺寸或字号变化）时重建，并清空旧分配。
  void configure({
    required int scrollRows,
    required int topRows,
    required int bottomRows,
  }) {
    if (scrollRows == _scrollRows &&
        topRows == _topRows &&
        bottomRows == _bottomRows) {
      return;
    }
    _scrollRows = scrollRows;
    _topRows = topRows;
    _bottomRows = bottomRows;
    reset();
  }

  /// 清空占用与分配（seek 跳转后调用）。
  void reset() {
    _scrollFreeAt
      ..clear()
      ..addAll(List<double>.filled(scrollRows, double.negativeInfinity));
    _topFreeAt
      ..clear()
      ..addAll(List<double>.filled(topRows, double.negativeInfinity));
    _bottomFreeAt
      ..clear()
      ..addAll(List<double>.filled(bottomRows, double.negativeInfinity));
    _rows.clear();
    _rejected.clear();
  }

  /// 记录「这条弹幕因无空轨被丢弃」。之后不再重试，避免它过一会儿又从
  /// 画面中间冒出来。
  void reject(String key) => _rejected.add(key);

  int? rowOf(String key) => _rows[key];

  /// 为一条弹幕分配轨道；返回 null 表示当前没有空轨，应当丢弃这条弹幕。
  ///
  /// - [width] 弹幕文字宽度（px）
  /// - [screenWidth] 画面宽度（px）
  /// - [window] 滚动弹幕横穿屏幕的时长（秒）
  /// - [fixedDuration] 顶部/底部弹幕停留时长（秒）
  /// - [gap] 同轨两条弹幕之间的安全间距（px）
  int? allocate({
    required String key,
    required DanmakuMode mode,
    required double time,
    required double width,
    required double screenWidth,
    required double window,
    required double fixedDuration,
    required double gap,
  }) {
    final cached = _rows[key];
    if (cached != null) return cached;
    if (_rejected.contains(key)) return null;

    switch (mode) {
      case DanmakuMode.scroll:
        if (_scrollRows <= 0) return null;
        // 文字尾巴完全进入屏幕后，再留出 gap 的间距，该轨道才算空出来。
        final speed = (screenWidth + width) / window;
        if (speed <= 0) return null;
        final freeAt = time + (width + gap) / speed;
        for (var row = 0; row < _scrollFreeAt.length; row++) {
          if (_scrollFreeAt[row] <= time) {
            _scrollFreeAt[row] = freeAt;
            _rows[key] = row;
            return row;
          }
        }
        return null;
      case DanmakuMode.top:
        return _allocateFixed(_topFreeAt, key, time, fixedDuration);
      case DanmakuMode.bottom:
        return _allocateFixed(_bottomFreeAt, key, time, fixedDuration);
    }
  }

  int? _allocateFixed(
    List<double> freeAtList,
    String key,
    double time,
    double duration,
  ) {
    for (var row = 0; row < freeAtList.length; row++) {
      if (freeAtList[row] <= time) {
        freeAtList[row] = time + duration;
        _rows[key] = row;
        return row;
      }
    }
    return null;
  }
}
