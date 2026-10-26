import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../config/server_config.dart';
import 'auth_interceptor.dart';

class DioClient {
  DioClient({
    required CookieJar cookieJar,
    required Future<void> Function() onSessionExpired,
    ServerConfig? server,
  }) : dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            headers: const {'Accept': 'application/json'},
          ),
        ) {
    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(
      AuthInterceptor(dio, onSessionExpired: onSessionExpired),
    );
    if (server != null) updateServer(server);
  }

  final Dio dio;

  void updateServer(ServerConfig config) {
    dio.options.baseUrl = config.baseUrl;
    dio.options.headers['User-Agent'] = config.userAgent;
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        if (config.allowSelfSigned) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        return client;
      };
    }
  }
}
