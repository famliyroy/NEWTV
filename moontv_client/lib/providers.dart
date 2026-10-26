import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/app_dependencies.dart';

final appDependenciesProvider = Provider<AppDependencies>((ref) {
  throw UnimplementedError('App dependencies must be overridden during bootstrap');
});
