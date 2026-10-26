import 'dart:async';

import 'package:flutter/foundation.dart';

class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
