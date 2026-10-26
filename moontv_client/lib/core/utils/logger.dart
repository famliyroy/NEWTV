import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class AppLog {
  AppLog._();

  static final Logger _logger = Logger(
    level: kReleaseMode ? Level.off : Level.info,
    printer: PrettyPrinter(methodCount: 0, lineLength: 100),
  );

  static void info(String message) => _logger.i(message);
  static void warning(String message) => _logger.w(message);
}
