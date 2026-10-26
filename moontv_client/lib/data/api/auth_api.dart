import 'package:dio/dio.dart';

import '../../core/config/server_config.dart';
import '../../core/network/api_exception.dart';
import 'endpoints.dart';

class ServerProbeResult {
  const ServerProbeResult({required this.config, required this.storageType});

  final ServerConfig config;
  final String storageType;
  bool get needsUsername => storageType.toLowerCase() != 'localstorage';
}

class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<ServerProbeResult> probe(ServerConfig config) async {
    final probeDio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: const {'Accept': 'application/json'},
      ),
    );
    try {
      final response = await probeDio.get<dynamic>(Endpoints.serverConfig);
      final data = response.data;
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        throw const ApiException(
          ApiErrorKind.business,
          '该地址不是可识别的 MoonTVPlus 服务',
        );
      }
      final site = data['SiteConfig'];
      final storageType = site is Map<String, dynamic>
          ? '${site['StorageType'] ?? ''}'
          : '';
      return ServerProbeResult(config: config, storageType: storageType);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const ApiException(
          ApiErrorKind.business,
          '该地址不是 MoonTVPlus 服务',
          statusCode: 404,
        );
      }
      throw ApiException.from(error);
    } finally {
      probeDio.close();
    }
  }

  Future<void> login({String? username, required String password}) async {
    try {
      final response = await _dio.post<dynamic>(
        Endpoints.login,
        data: {
          if (username != null && username.trim().isNotEmpty)
            'username': username.trim(),
          'password': password,
        },
      );
      final data = response.data;
      if (response.statusCode != 200 ||
          (data is Map<String, dynamic> && data['ok'] == false)) {
        throw const ApiException(ApiErrorKind.authentication, '登录失败，请检查账号和密码');
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const ApiException(ApiErrorKind.authentication, '用户名或密码错误', statusCode: 401);
      }
      if (error.response?.statusCode == 429) {
        final retryAfter = error.response?.headers.value('retry-after');
        final seconds = int.tryParse(retryAfter ?? '');
        throw ApiException(
          ApiErrorKind.rateLimited,
          seconds == null ? '尝试过于频繁，请稍后再试' : '尝试过于频繁，请 $seconds 秒后重试',
          statusCode: 429,
        );
      }
      throw ApiException.from(error);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post<dynamic>(Endpoints.logout);
    } on DioException {
      // Local credentials are cleared even when the server is unreachable.
    }
  }
}
