import 'dart:async';

import 'package:dio/dio.dart';

import '../../data/api/endpoints.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, {required this.onSessionExpired});

  final Dio _dio;
  final Future<void> Function() onSessionExpired;
  Future<bool>? _refreshOperation;

  Future<bool> _refreshSingleFlight() {
    return _refreshOperation ??= _refresh().whenComplete(() {
      _refreshOperation = null;
    });
  }

  Future<bool> _refresh() async {
    try {
      final response = await _dio.post<dynamic>(Endpoints.refresh);
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isAuthenticationCall = options.path == Endpoints.login ||
        options.path == Endpoints.refresh ||
        options.path == Endpoints.logout;
    if (err.response?.statusCode != 401 ||
        isAuthenticationCall ||
        options.extra['newtvRetried'] == true) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshSingleFlight();
    if (!refreshed) {
      await onSessionExpired();
      handler.next(err);
      return;
    }

    options.extra['newtvRetried'] = true;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
