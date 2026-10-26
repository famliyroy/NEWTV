import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/app_dependencies.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final dependencies = await AppDependencies.create();
  if (dependencies.preferences.getBool('sessionOnly') == true) {
    await dependencies.session.clearSession();
    await dependencies.preferences.setBool('sessionOnly', false);
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: Size(1024, 640),
      size: Size(1280, 760),
      title: 'NEWTV',
      center: true,
      backgroundColor: Color(0xFF0B0F14),
      titleBarStyle: TitleBarStyle.normal,
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }));
  }
  runApp(
    ProviderScope(
      overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
      child: const NewtvApp(),
    ),
  );
}
