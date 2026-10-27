import 'package:dio/dio.dart';

import '../../core/config/server_config.dart';
import '../../core/network/api_exception.dart';
import 'endpoints.dart';

class ServerProbeResult {
  const ServerProbeResult({
    required this.config,
    required this.storageType,
    this.siteName = 'MoonTVPlus',
    this.loginRequireTurnstile = false,
    this.turnstileSiteKey = '',
    this.enableRegistration = false,
    this.requireRegistrationInviteCode = false,
    this.registrationRequireTurnstile = false,
  });

  final ServerConfig config;
  final String storageType;
  final String siteName;
  final bool loginRequireTurnstile;
  final String turnstileSiteKey;
  final bool enableRegistration;
  final bool requireRegistrationInviteCode;
  final bool registrationRequireTurnstile;

  bool get needsUsername => storageType.toLowerCase() != 'localstorage';

  /// 注册入口是否应该出现：站点开启注册，且不是 localstorage 模式
  /// （localstorage 模式下后端直接 400「不支持注册」）。
  bool get canRegister => enableRegistration && needsUsername;

  factory ServerProbeResult.fromServerConfigJson(
    ServerConfig config,
    Map<String, dynamic> data,
  ) {
    final site = data['SiteConfig'];
    final siteMap = site is Map<String, dynamic> ? site : const <String, dynamic>{};

    String pickString(String key) {
      final top = data[key];
      if (top != null && '$top'.trim().isNotEmpty) return '$top'.trim();
      final nested = siteMap[key];
      if (nested != null && '$nested'.trim().isNotEmpty) return '$nested'.trim();
      return '';
    }

    bool pickBool(String key) {
      final top = data[key];
      if (top is bool) return top;
      if (top is String && top.isNotEmpty) return top.toLowerCase() == 'true';
      final nested = siteMap[key];
      if (nested is bool) return nested;
      if (nested is String && nested.isNotEmpty) {
        return nested.toLowerCase() == 'true';
      }
      return false;
    }

    final siteName = pickString('SiteName');
    return ServerProbeResult(
      config: config,
      storageType: pickString('StorageType'),
      siteName: siteName.isEmpty ? 'MoonTVPlus' : siteName,
      loginRequireTurnstile: pickBool('LoginRequireTurnstile'),
      turnstileSiteKey: pickString('TurnstileSiteKey'),
      enableRegistration: pickBool('EnableRegistration'),
      requireRegistrationInviteCode: pickBool('RequireRegistrationInviteCode'),
      registrationRequireTurnstile: pickBool('RegistrationRequireTurnstile'),
    );
  }
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
      return ServerProbeResult.fromServerConfigJson(config, data);
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

  static String? _extractServerError(dynamic data) {
    if (data is Map<String, dynamic>) {
      final raw = data['error'] ?? data['message'];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    return null;
  }

  Future<void> login({
    String? username,
    required String password,
    String? turnstileToken,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        Endpoints.login,
        data: {
          if (username != null && username.trim().isNotEmpty)
            'username': username.trim(),
          'password': password,
          if (turnstileToken != null && turnstileToken.trim().isNotEmpty)
            'turnstileToken': turnstileToken.trim(),
        },
      );
      final data = response.data;
      if (response.statusCode != 200 ||
          (data is Map<String, dynamic> && data['ok'] == false)) {
        throw ApiException(
          ApiErrorKind.authentication,
          _extractServerError(data) ?? '登录失败，请检查账号和密码',
        );
      }
    } on DioException catch (error) {
      final serverMessage = _extractServerError(error.response?.data);
      if (error.response?.statusCode == 400 && serverMessage != null) {
        throw ApiException(
          ApiErrorKind.business,
          serverMessage,
          statusCode: 400,
        );
      }
      if (error.response?.statusCode == 401) {
        throw ApiException(
          ApiErrorKind.authentication,
          serverMessage ?? '用户名或密码错误',
          statusCode: 401,
        );
      }
      if (error.response?.statusCode == 429) {
        final retryAfter = error.response?.headers.value('retry-after');
        final seconds = int.tryParse(retryAfter ?? '');
        throw ApiException(
          ApiErrorKind.rateLimited,
          serverMessage ??
              (seconds == null ? '尝试过于频繁，请稍后再试' : '尝试过于频繁，请 $seconds 秒后重试'),
          statusCode: 429,
        );
      }
      throw ApiException.from(error);
    }
  }

  /// 注册新账号。错误文案优先透传后端返回的 `error`（如「注册功能未开启」
  /// 「邀请码错误」「用户名只能包含字母、数字、下划线，长度3-20位」）。
  Future<void> register({
    required String username,
    required String password,
    String? inviteCode,
    String? turnstileToken,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        Endpoints.register,
        data: {
          'username': username.trim(),
          'password': password,
          if (inviteCode != null && inviteCode.trim().isNotEmpty)
            'inviteCode': inviteCode.trim(),
          if (turnstileToken != null && turnstileToken.trim().isNotEmpty)
            'turnstileToken': turnstileToken.trim(),
        },
      );
      final data = response.data;
      if (response.statusCode != 200 ||
          (data is Map<String, dynamic> && data['ok'] == false)) {
        throw ApiException(
          ApiErrorKind.business,
          _extractServerError(data) ?? '注册失败，请稍后重试',
        );
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final serverMessage = _extractServerError(error.response?.data);
      switch (status) {
        case 409:
          throw ApiException(
            ApiErrorKind.business,
            serverMessage ?? '该用户名已被占用，请换一个',
            statusCode: 409,
          );
        case 403:
          throw ApiException(
            ApiErrorKind.business,
            serverMessage ?? '注册功能未开启',
            statusCode: 403,
          );
        case 400:
          throw ApiException(
            ApiErrorKind.business,
            serverMessage ?? '注册信息不符合要求',
            statusCode: 400,
          );
        case 429:
          throw ApiException(
            ApiErrorKind.rateLimited,
            serverMessage ?? '尝试过于频繁，请稍后再试',
            statusCode: 429,
          );
      }
      throw ApiException.from(error);
    }
  }

  Future<void> verifyCookieSession() async {
    try {
      final response = await _dio.get<dynamic>(Endpoints.playRecords);
      if (response.statusCode != 200) {
        throw const ApiException(ApiErrorKind.authentication, 'Cookie 无效或已过期');
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
        throw const ApiException(
          ApiErrorKind.authentication,
          'Cookie 无效或已过期，请重新从浏览器复制',
          statusCode: 401,
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
