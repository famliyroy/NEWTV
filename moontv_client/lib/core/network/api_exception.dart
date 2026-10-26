import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

enum ApiErrorKind { network, timeout, authentication, rateLimited, server, business }

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is TimeoutException) {
      return const ApiException(ApiErrorKind.timeout, '连接超时，请检查网络后重试');
    }
    if (error is SocketException) {
      return const ApiException(ApiErrorKind.network, '无法连接服务器，请检查地址或网络');
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) {
        return const ApiException(ApiErrorKind.authentication, '登录已失效，请重新登录', statusCode: 401);
      }
      if (status == 429) {
        return const ApiException(ApiErrorKind.rateLimited, '尝试过于频繁，请稍后再试', statusCode: 429);
      }
      if (status != null && status >= 500) {
        return ApiException(ApiErrorKind.server, '服务端暂时异常（$status）', statusCode: status);
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return const ApiException(ApiErrorKind.timeout, '连接超时，请检查网络后重试');
      }
      if (error.type == DioExceptionType.badCertificate) {
        return const ApiException(ApiErrorKind.network, '证书无效，请检查服务器证书');
      }
      if (status == 404) {
        return const ApiException(ApiErrorKind.business, '该地址未提供所需服务', statusCode: 404);
      }
      return ApiException(
        ApiErrorKind.network,
        status == null ? '网络连接失败，请稍后重试' : '请求失败（$status）',
        statusCode: status,
      );
    }
    return const ApiException(ApiErrorKind.business, '操作未完成，请稍后重试');
  }

  @override
  String toString() => message;
}

String readableError(Object error) => ApiException.from(error).message;
