import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/session_manager.dart';
import 'core/config/app_settings.dart';
import 'data/app_dependencies.dart';

final appDependenciesProvider = Provider<AppDependencies>((ref) {
  throw UnimplementedError('App dependencies must be overridden during bootstrap');
});

/// 会话与设置都以 ChangeNotifierProvider 暴露，UI 一律 watch 这两个 Provider。
///
/// `appDependenciesProvider` 引用的对象永远不变，直接 watch 它取设置只在
/// Provider 首次构建时求值，内部 ChangeNotifier 的通知不会触发重建。
final sessionProvider = ChangeNotifierProvider<SessionManager>(
  (ref) => ref.watch(appDependenciesProvider).session,
);

final settingsProvider = ChangeNotifierProvider<SettingsController>(
  (ref) => ref.watch(appDependenciesProvider).settings,
);
